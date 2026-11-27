#requires -Version 7.4
<#
  LM Studio runtime provisioning. Dot-source this file from PowerShell 7.4 or newer.
  Public entry: Configure-LocalRuntime. No work occurs merely by dot-sourcing.

  Contract verified against LM Studio CLI source and REST v1 documentation:
  https://github.com/lmstudio-ai/lms/blob/main/src/subcommands/load.ts
  https://github.com/lmstudio-ai/lms/blob/main/src/subcommands/list.ts
  https://github.com/lmstudio-ai/lms/blob/main/src/subcommands/get.ts
  https://lmstudio.ai/docs/developer/rest/list

  Existing LM Studio storage, authentication, models and listeners are preserved.
  No automatic unloading, driver changes, public listeners or global config edits.
#>

function Get-LrProperty {
    param([AllowNull()]$Object, [Parameter(Mandatory)][string]$Name, $Default = $null)
    if ($null -eq $Object) { return $Default }
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) { return $Object[$Name] }
    } elseif ($null -ne $Object.PSObject.Properties[$Name]) { return $Object.$Name }
    return $Default
}

function ConvertFrom-LrModelList {
    param([Parameter(Mandatory)][string]$Json)
    $parse=@{InputObject=$Json;ErrorAction='Stop'}
    if($PSVersionTable.PSVersion.Major -ge 7){$parse.NoEnumerate=$true}
    $models=ConvertFrom-Json @parse
    if($models -isnot [array]){throw 'LM Studio must return a JSON list of models.'}
    foreach($model in $models){
        if($model -isnot [pscustomobject]){throw 'Invalid entry in the LM Studio model list.'}
    }
    # PS5.1 otherwise emits [] as one array object instead of zero records.
    foreach($model in $models){$model}
}

function Get-LrMissingLoadOptions {
    param([string]$Help,$ExactLocalProbe=$null)
    $probeText=[string](Get-LrProperty $ExactLocalProbe 'Stdout')+"`n"+[string](Get-LrProperty $ExactLocalProbe 'Stderr')
    $hiddenVerified=(Get-LrProperty $ExactLocalProbe 'ExitCode' -1) -eq 1 -and
        $probeText -match 'Path not provided' -and $probeText -match '\[model-key\]' -and $probeText -match '\-\-exact'
    foreach($flag in @('--parallel','--context-length','--estimate-only','--identifier','--gpu','--exact','--local')){
        if($flag -in @('--exact','--local') -and $hiddenVerified){continue}
        if($Help -notmatch ([regex]::Escape($flag)+'(?=[\s<,=]|$)')){$flag}
    }
}

function Assert-LrLoadCapabilities {
    param([string]$LmsPath,[string]$LogDirectory)
    $help=Invoke-LrNative -FilePath $LmsPath -Arguments @('load','--help') -LogDirectory $LogDirectory -TimeoutSeconds 30
    $text=$help.Stdout+"`n"+$help.Stderr
    $missing=@(Get-LrMissingLoadOptions -Help $text)
    if($missing -contains '--exact' -or $missing -contains '--local'){
        # Hidden flags: no model argument, and estimate-only as a second guard.
        # lms/43d4b26/src/subcommands/load.ts exits before estimation/loading.
        $probe=Invoke-LrNative -FilePath $LmsPath -Arguments @('load','--exact','--local','--estimate-only','--yes') -LogDirectory $LogDirectory -TimeoutSeconds 30 -AllowFailure
        $missing=@(Get-LrMissingLoadOptions -Help $text -ExactLocalProbe $probe)
    }
    if($missing.Count){throw "Required lms load options not confirmed: $($missing -join ', '). Check CLI/app connection and version. Details: $LogDirectory"}
}

function Resolve-LocalLmsCommand {
    [CmdletBinding()]
    param([string]$LmsPath)
    if ($LmsPath) {
        $resolved = (Resolve-Path -LiteralPath $LmsPath -ErrorAction Stop).Path
        if ([IO.Path]::GetExtension($resolved) -ine '.exe') {
            throw 'LmsPath must point to lms.exe; shell shims are not executed.'
        }
        return $resolved
    }
    $userDirectory = [Environment]::GetFolderPath('UserProfile')
    $pointerPath = Join-Path $userDirectory '.lmstudio-home-pointer'
    if (Test-Path -LiteralPath $pointerPath -PathType Leaf) {
        $lmHomePath = (Get-Content -LiteralPath $pointerPath -Raw -ErrorAction Stop).Trim()
        if (-not $lmHomePath -or -not [IO.Path]::IsPathFullyQualified($lmHomePath) -or
            -not (Test-Path -LiteralPath $lmHomePath -PathType Container)) {
            throw "Invalid LM Studio reference in $pointerPath. Repair existing configuration in LM Studio."
        }
    } elseif (Test-Path -LiteralPath (Join-Path $userDirectory '.cache/lm-studio') -PathType Container) {
        $lmHomePath = Join-Path $userDirectory '.cache/lm-studio'
    } else { $lmHomePath = Join-Path $userDirectory '.lmstudio' }
    $candidates = @(
        (Join-Path $lmHomePath 'bin/lms.exe')
        (Get-Command lms.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -First 1)
    ) | Where-Object { $_ }
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return (Resolve-Path -LiteralPath $candidate).Path }
    }
    throw 'lms.exe not found. Start LM Studio once; if necessary run: npx --yes lmstudio install-cli. Then rerun provisioning.'
}

function New-LrNativeTimeoutError {
    param([string[]]$Arguments,[int]$TimeoutSeconds,[string]$LogPath,[switch]$OutputDrain)
    $phase=if($OutputDrain){'waiting for command output to close'}else{'running the command'}
    [IO.File]::WriteAllText($LogPath,"LM Studio command '$($Arguments[0])' exceeded $TimeoutSeconds seconds while $phase.",[Text.UTF8Encoding]::new($false))
    $error=[TimeoutException]::new("LM Studio command '$($Arguments[0])' timed out while $phase ($TimeoutSeconds seconds). Check LM Studio and the local command log. Details: $LogPath")
    $error.Data['ShadowNativeTimeout']=$true
    # Terminating a CLI does not prove that the model server stopped loading.
    $error.Data['ShadowControllerUncertain']=($Arguments[0] -ceq 'load' -and $Arguments -notcontains '--estimate-only' -and $Arguments -notcontains '--help')
    return $error
}

function Invoke-LrNative {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter(Mandatory)][string]$LogDirectory,
        [int]$TimeoutSeconds = 600,
        [switch]$AllowFailure
    )
    $null = New-Item -ItemType Directory -Path $LogDirectory -Force
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $FilePath
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
    $startInfo.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)
    $startInfo.CreateNoWindow = $true
    $startInfo.Environment['NO_COLOR'] = '1'
    $startInfo.Environment['FORCE_COLOR'] = '0'
    foreach ($argument in $Arguments) { $startInfo.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    $readCancellation=[Threading.CancellationTokenSource]::new()
    $logPath = Join-Path $LogDirectory ((Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 6) + '.log')
    $eventWriter=Get-Command Write-ShadowToolchainEvent -CommandType Function -ErrorAction SilentlyContinue
    $evidenceClock=[Diagnostics.Stopwatch]::StartNew();$stdout='';$stderr='';$nativeExit=$null;$nativeFailure=$null
    if($eventWriter){Write-ShadowToolchainEvent -Component 'LM Studio CLI' -Message ("Starting native command: "+$Arguments[0])}
    try {
        $null = $process.Start()
        $stdoutTask = $process.StandardOutput.ReadToEndAsync($readCancellation.Token)
        $stderrTask = $process.StandardError.ReadToEndAsync($readCancellation.Token)
        $watch = [Diagnostics.Stopwatch]::StartNew()
        while (-not $process.WaitForExit(1000)) {
            if ($watch.Elapsed.TotalSeconds -gt $TimeoutSeconds) {
                # Stop this CLI invocation only, never the running model server.
                try{if(-not $process.HasExited){$process.Kill()}}catch{}
                $readCancellation.Cancel()
                throw (New-LrNativeTimeoutError -Arguments $Arguments -TimeoutSeconds $TimeoutSeconds -LogPath $logPath)
            }
            Write-Progress -Activity "LM Studio: $($Arguments[0])" -Status ('Running for {0:n0} seconds' -f $watch.Elapsed.TotalSeconds)
        }
        # A child started by the CLI may retain an inherited output handle after
        # the CLI exits. Waiting synchronously on ReadToEndAsync then has no
        # deadline, even though WaitForExit above was bounded.
        while(-not $stdoutTask.IsCompleted -or -not $stderrTask.IsCompleted){
            if($watch.Elapsed.TotalSeconds -gt $TimeoutSeconds){
                $readCancellation.Cancel()
                throw (New-LrNativeTimeoutError -Arguments $Arguments -TimeoutSeconds $TimeoutSeconds -LogPath $logPath -OutputDrain)
            }
            Start-Sleep -Milliseconds 50
        }
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        $nativeExit=$process.ExitCode
        [IO.File]::WriteAllText($logPath, ($stdout + [Environment]::NewLine + $stderr), [Text.UTF8Encoding]::new($false))
        if($eventWriter){
            Write-ShadowToolchainEvent -Component 'LM Studio CLI' -Level $(if($process.ExitCode -eq 0){'INFO'}else{'ERROR'}) -Message ("Command $($Arguments[0]) exited with code $($process.ExitCode). Details: $logPath")
            if($stderr.Trim()){Write-ShadowToolchainEvent -Component 'LM Studio CLI' -Level $(if($process.ExitCode -eq 0){'WARN'}else{'ERROR'}) -Message $stderr.TrimEnd()}
        }
        if ($process.ExitCode -ne 0 -and -not $AllowFailure) {
            throw "LM Studio command '$($Arguments[0])' failed (exit $($process.ExitCode)). Details: $logPath"
        }
        return [pscustomobject]@{ Stdout = $stdout; Stderr = $stderr; LogPath = $logPath; ExitCode = $process.ExitCode }
    } catch {
        $nativeFailure=$_.Exception.Message
        if($eventWriter){Write-ShadowToolchainEvent -Component 'LM Studio CLI' -Level ERROR -Message $_.Exception.Message}
        throw
    } finally {
        Write-Progress -Activity "LM Studio: $($Arguments[0])" -Completed
        $readCancellation.Cancel()
        $process.Dispose()
        $readCancellation.Dispose()
        if(Get-Command Add-ShadowProvisionCommand -CommandType Function -ErrorAction SilentlyContinue){Add-ShadowProvisionCommand -File $FilePath -Arguments $Arguments -WorkingDirectory ([string]$PWD) -TimeoutSeconds $TimeoutSeconds -ExitCode $nativeExit -Stdout $stdout -Stderr $stderr -DurationMs $evidenceClock.Elapsed.TotalMilliseconds -Failure $nativeFailure}
    }
}

function Invoke-LrModelCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$LmsPath,
        [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter(Mandatory)][string]$LogDirectory,
        [int]$TimeoutSeconds=60
    )
    # A successful memory estimate says nothing about architecture support.
    # Inspect both streams even for reserve overrides; an unsupported model
    # must never be reported as a shortage of memory.
    $result=Invoke-LrNative -FilePath $LmsPath -Arguments $Arguments -LogDirectory $LogDirectory -TimeoutSeconds $TimeoutSeconds -AllowFailure
    $exitCode=Get-LrProperty $result 'ExitCode'
    if($exitCode -isnot [int] -and $exitCode -isnot [long]){throw 'LM Studio returned no usable exit code for the model command.'}
    if($exitCode -eq 0){return $result}
    $text=([string](Get-LrProperty $result 'Stdout')+"`n"+[string](Get-LrProperty $result 'Stderr')) -replace '\x1B\[[0-?]*[ -/]*[@-~]', ''
    $details="Details: $($result.LogPath)"
    if($text -match '(?i)(unknown|unsupported) model architecture|model architecture[^\r\n]{0,100}(not supported|unsupported)'){
        $error=[InvalidOperationException]::new("The selected LM Studio runtime does not support this model architecture. In LM Studio, select or update a compatible GPU runtime, then retry the same model. More memory or AllowUnfitAttempt cannot fix this. $details")
        $error.Data['ShadowRuntimeCompatibilityFailure']=$true
    }elseif($text -match '(?i)out of (?:device |GPU |host )?memory|not enough (?:free )?(?:memory|VRAM|RAM)|insufficient (?:memory|VRAM|RAM)|(?:memory|resource)[ -]?guardrails?[^\r\n]*(?:reject|exceed|insufficient)|guardrail rejected|(?:cudaMalloc|failed to allocate)[^\r\n]*(?:fail|memory|buffer)'){
        $error=[InvalidOperationException]::new("LM Studio could not allocate memory for the selected model. Free memory and retry; the model file is preserved. $details")
        $error.Data['ShadowResourceFitFailure']=$true
    }else{
        $error=[InvalidOperationException]::new("LM Studio rejected the selected model command (exit $exitCode). Check the local model file, runtime and command log, then retry. $details")
        $error.Data['ShadowModelLoadFailure']=$true
    }
    # Keep native output in the local command log; do not forward it to clients.
    throw $error
}

function Invoke-LrJson {
    param([string]$LmsPath, [string[]]$Arguments, [string]$LogDirectory)
    $result = Invoke-LrNative -FilePath $LmsPath -Arguments $Arguments -LogDirectory $LogDirectory -TimeoutSeconds 60
    try {
        if($Arguments[0] -in @('ls','ps')){ConvertFrom-LrModelList -Json $result.Stdout;return}
        return ConvertFrom-Json -InputObject $result.Stdout -Depth 100 -ErrorAction Stop
    }
    catch { throw "LM Studio returned unreadable JSON or an unexpected structure. Check CLI/app version. Details: $($result.LogPath)" }
}

function Get-LocalNvidiaGpu {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$LogDirectory)
    $smi = Get-Command nvidia-smi.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    $smiPath = if ($smi) { $smi.Source } else { Join-Path $env:SystemRoot 'System32/nvidia-smi.exe' }
    if (-not (Test-Path -LiteralPath $smiPath -PathType Leaf)) {
        throw 'nvidia-smi.exe missing. Check the NVIDIA GPU and installed driver; this script does not install GPU drivers.'
    }
    $result = Invoke-LrNative -FilePath $smiPath -Arguments @('--query-gpu=index,name,memory.total,memory.free', '--format=csv,noheader,nounits') -LogDirectory $LogDirectory -TimeoutSeconds 30
    $gpus = @()
    foreach ($line in ($result.Stdout -split '\r?\n')) {
        if (-not $line.Trim()) { continue }
        $parts = $line -split ',', 4
        if ($parts.Count -ne 4 -or $parts[2].Trim() -notmatch '^\d+(\.\d+)?$' -or $parts[3].Trim() -notmatch '^\d+(\.\d+)?$') {
            throw "Could not reliably determine GPU memory. Details: $($result.LogPath)"
        }
        $gpus += [pscustomobject]@{
            Index = [int]$parts[0].Trim(); Name = $parts[1].Trim()
            TotalBytes = [long]([double]::Parse($parts[2].Trim(), [Globalization.CultureInfo]::InvariantCulture) * 1MB)
            FreeBytes = [long]([double]::Parse($parts[3].Trim(), [Globalization.CultureInfo]::InvariantCulture) * 1MB)
        }
    }
    if ($gpus.Count -ne 1) {
        throw "Detected $($gpus.Count) NVIDIA GPUs. Automatic single-GPU sizing is not assumed for this configuration."
    }
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    return [pscustomobject]@{
        Gpu = $gpus[0]
        TotalRamBytes = [long]$os.TotalVisibleMemorySize * 1KB
        FreeRamBytes = [long]$os.FreePhysicalMemory * 1KB
    }
}

function Select-LrProfile {
    param([string]$PreferredModel = 'Auto', [Parameter(Mandatory)]$Hardware, [string]$ModelKey)
    if ($ModelKey) {
        return [pscustomobject]@{ Name = 'Existing'; ExpectedPath = $null; DownloadUrl = $null }
    }
    $choice = $PreferredModel
    if ($choice -eq 'Auto') {
        if ($Hardware.Gpu.TotalBytes -ge 19GB -and $Hardware.TotalRamBytes -ge 24GB) { $choice = 'Qwen27B' }
        elseif ($Hardware.Gpu.TotalBytes -ge 15GB -and $Hardware.TotalRamBytes -ge 20GB) { $choice = 'GptOss20B' }
        else { throw 'GPU/RAM do not safely support the automatic profiles. No model was downloaded. Check hardware and a smaller explicit model.' }
    }
    if ($choice -eq 'Qwen27B') {
        if ($Hardware.Gpu.TotalBytes -lt 19GB -or $Hardware.TotalRamBytes -lt 24GB) {
            throw 'The Qwen27B profile requires at least 19 GiB VRAM and 24 GiB RAM here; the subsequent memory estimate must also fit.'
        }
        return [pscustomobject]@{
            Name = 'Qwen27B'; ExpectedPath = 'lmstudio-community/Qwen3.8-27B-GGUF/Qwen3.8-27B-Q4_K_M.gguf'
            DownloadUrl = 'https://huggingface.co/lmstudio-community/Qwen3.8-27B-GGUF/blob/main/Qwen3.8-27B-Q4_K_M.gguf'
        }
    }
    if ($choice -eq 'GptOss20B') {
        if ($Hardware.Gpu.TotalBytes -lt 15GB -or $Hardware.TotalRamBytes -lt 20GB) {
            throw 'The GptOss20B profile requires at least 15 GiB VRAM and 20 GiB RAM here.'
        }
        return [pscustomobject]@{
            Name = 'GptOss20B'; ExpectedPath = 'lmstudio-community/gpt-oss-20b-GGUF/gpt-oss-20b-MXFP4.gguf'
            DownloadUrl = 'https://huggingface.co/lmstudio-community/gpt-oss-20b-GGUF/blob/main/gpt-oss-20b-MXFP4.gguf'
        }
    }
    throw "Unknown model profile: $choice"
}

function Get-LrDownloadedModels {
    param([string]$LmsPath, [string]$LogDirectory, [ValidateSet('llm','embedding')][string]$Type='llm')
    # Exact loading uses entries in listDownloadedModels, not fuzzy model-name search.
    $models = @(Invoke-LrJson -LmsPath $LmsPath -Arguments @('ls', '--json') -LogDirectory $LogDirectory)
    $models=@($models | Where-Object {
        (Get-LrProperty $_ 'type') -eq $Type -and
        $null -eq (Get-LrProperty $_ 'deviceIdentifier' '__unknown__') -and
        (Get-LrProperty $_ 'path')
    })
    if(@($models|Where-Object {$null -ne (Get-LrProperty $_ 'selectedVariant')}).Count){
        $groups=@(Invoke-LrJson -LmsPath $LmsPath -Arguments @('ls','--variants','--json') -LogDirectory $LogDirectory)
        Add-LrVariantMetadata -Models $models -Groups $groups
    }
    return $models
}

function Add-LrVariantMetadata {
    param([object[]]$Models,[object[]]$Groups)
    foreach($model in $Models){
        $selected=[string](Get-LrProperty $model 'selectedVariant')
        if(-not $selected){continue}
        $key=[string](Get-LrProperty $model 'modelKey')
        $matches=@($Groups|Where-Object {
            $base=Get-LrProperty $_ 'model'
            (Get-LrProperty $base 'modelKey') -ceq $key -and
            $null -eq (Get-LrProperty $base 'deviceIdentifier' '__unknown__')
        })
        if($matches.Count -ne 1){throw "Variants for $key cannot be uniquely verified locally."}
        $base=Get-LrProperty $matches[0] 'model'
        if((Get-LrProperty $base 'selectedVariant') -cne $selected -or
           (Get-LrProperty $base 'path') -cne (Get-LrProperty $model 'path')){
            throw "Model selection for $key changed during the query. Please restart."
        }
        $variants=Get-LrProperty $matches[0] 'variants'
        $matching=@($variants|Where-Object {
            (Get-LrProperty $_ 'modelKey') -ceq $selected -and
            $null -eq (Get-LrProperty $_ 'deviceIdentifier' '__unknown__') -and
            (Get-LrProperty $_ 'path') -ceq (Get-LrProperty $model 'path')
        })
        if($matching.Count -ne 1){throw "Selected variant for $key cannot be uniquely verified locally."}
        $identifier=[string](Get-LrProperty $matching[0] 'indexedModelIdentifier')
        $prefix=$key+'@'
        if(-not $identifier.StartsWith($prefix,[StringComparison]::Ordinal) -or $identifier.Length -le $prefix.Length){
            throw "File identity of selected variant for $key is missing."
        }
        $model|Add-Member -NotePropertyName ShadowSelectedFile -NotePropertyValue ($identifier.Substring($prefix.Length)) -Force
    }
}

function Get-LrGgufEngines {
    param([Parameter(Mandatory)][string]$Text)
    $plain = $Text -replace '\x1B\[[0-?]*[ -/]*[@-~]', ''
    foreach ($line in ($plain -split '\r?\n')) {
        if ($line -notmatch '(?i)\bgguf\b') { continue }
        $fields = $line.Trim() -split '\s+'
        if ($fields.Count -lt 2 -or $fields[0] -notmatch '^[^\s]+@[^\s]+$') {
            throw 'Cannot interpret lms runtime ls output; runtime selection remains unchanged.'
        }
        [pscustomobject]@{ Specifier = $fields[0]; Selected = $line.Contains([string][char]0x2713) }
    }
}

function Ensure-LrInferenceEngine {
    param([string]$LmsPath, [string]$LogDirectory)
    # runtime ls has no JSON option. Its current source prints name@version,
    # a U+2713 selection mark, and supported formats. Unknown output fails closed.
    # https://github.com/lmstudio-ai/lms/blob/main/src/subcommands/runtime/list.ts
    $listing = Invoke-LrNative -FilePath $LmsPath -Arguments @('runtime', 'ls') -LogDirectory $LogDirectory
    $text = $listing.Stdout + "`n" + $listing.Stderr
    $engines = @(Get-LrGgufEngines -Text $text)
    if ($engines.Count) {
        $activeGpu = @($engines | Where-Object { $_.Selected -and $_.Specifier -match '(?i)(cuda|vulkan)' })
        if ($activeGpu.Count -eq 1) { return $activeGpu[0].Specifier }
        throw 'A GGUF inference runtime exists, but no unique active CUDA/Vulkan runtime was detected. Existing selection is preserved. Check lms runtime ls and explicitly select a suitable GPU runtime.'
    }
    if ($text -notmatch 'No runtimes found\.' -and $text -notmatch 'LLM ENGINE') {
        throw 'Could not unambiguously read installed inference runtimes. No automatic runtime switch.'
    }
    Write-Host 'Installing the compatible stable llama.cpp CUDA runtime (no driver installation) ...'
    # Search excludes incompatible runtimes unless --allow-incompatible is given.
    # Do this only when no existing GGUF engine/selection will be replaced.
    $null = Invoke-LrNative -FilePath $LmsPath -Arguments @('runtime', 'get', 'llama.cpp:cuda', '--channel', 'stable', '--yes') -LogDirectory $LogDirectory -TimeoutSeconds 1800
    $after = Invoke-LrNative -FilePath $LmsPath -Arguments @('runtime', 'ls') -LogDirectory $LogDirectory
    $installed = @(Get-LrGgufEngines -Text ($after.Stdout + "`n" + $after.Stderr))
    $cuda = @($installed | Where-Object { $_.Specifier -match '(?i)cuda' })
    $selectedCuda = @($cuda | Where-Object { $_.Selected })
    if ($selectedCuda.Count -eq 1) { return $selectedCuda[0].Specifier }
    if ($cuda.Count -ne 1) { throw 'CUDA runtime installation is unconfirmed. Check lms runtime ls and the download log.' }
    $null = Invoke-LrNative -FilePath $LmsPath -Arguments @('runtime', 'select', $cuda[0].Specifier) -LogDirectory $LogDirectory
    $selected = Invoke-LrNative -FilePath $LmsPath -Arguments @('runtime', 'ls') -LogDirectory $LogDirectory
    $verifiedCuda = @(Get-LrGgufEngines -Text ($selected.Stdout + "`n" + $selected.Stderr) | Where-Object { $_.Selected -and $_.Specifier -eq $cuda[0].Specifier })
    if ($verifiedCuda.Count -ne 1) { throw 'Installation succeeded, but the active CUDA runtime could not be confirmed.' }
    return $verifiedCuda[0].Specifier
}

function Find-LrModel {
    param([object[]]$Models, $Profile, [string]$ModelKey)
    $matches = @($Models | Where-Object {
        $key = [string](Get-LrProperty $_ 'modelKey')
        $path = [string](Get-LrProperty $_ 'path')
        if ($ModelKey) { return ($key -ceq $ModelKey -or $path -ceq $ModelKey) }
        $selectedFile=[string](Get-LrProperty $_ 'ShadowSelectedFile')
        return [string]::Equals(($path -replace '\\', '/'), $Profile.ExpectedPath, [StringComparison]::OrdinalIgnoreCase) -or
            ($selectedFile -and [string]::Equals(($selectedFile -replace '\\', '/'), $Profile.ExpectedPath, [StringComparison]::OrdinalIgnoreCase))
    })
    if ($matches.Count -gt 1) {
        throw 'Multiple exact local model matches found. Use -ModelKey with the full unique path from lms ls --json.'
    }
    if ($matches.Count -eq 1) { return $matches[0] }
    return $null
}

function Assert-LrSelectedModel {
    param([string]$LmsPath,[string]$LogDirectory,[string]$ExpectedPath,[string]$ModelPath)
    if(-not $ExpectedPath){return}
    $profile=[pscustomobject]@{ExpectedPath=$ExpectedPath}
    $model=Find-LrModel -Models @(Get-LrDownloadedModels -LmsPath $LmsPath -LogDirectory $LogDirectory) -Profile $profile
    if(-not $model -or (Get-LrProperty $model 'path') -cne $ModelPath){
        throw "Selected local model variant changed or is ambiguous: $ExpectedPath. No model switch performed."
    }
}

function Convert-LrEstimatedBytes {
    param([Parameter(Mandatory)][string]$Text, [Parameter(Mandatory)][string]$Label)
    $plain = $Text -replace '\x1B\[[0-?]*[ -/]*[@-~]', ''
    $pattern = [regex]::Escape($Label) + '\s*:\s*(?<amount>\d+(?:\.\d+)?)\s*(?<unit>Bytes|B|KiB|MiB|GiB|TiB|KB|MB|GB|TB)\b'
    $match = [regex]::Match($plain, $pattern, [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $match.Success) { throw "Cannot interpret LM Studio memory estimate: $Label. Check CLI version and log." }
    $amount = [double]::Parse($match.Groups['amount'].Value, [Globalization.CultureInfo]::InvariantCulture)
    $power = switch -Regex ($match.Groups['unit'].Value) { '^[Kk]' { 1 }; '^[Mm]' { 2 }; '^[Gg]' { 3 }; '^[Tt]' { 4 }; default { 0 } }
    # Current CLI emits KiB/MiB/GiB. Treat legacy MB/GB conservatively as binary too.
    return [long][Math]::Ceiling($amount * [Math]::Pow(1024, $power))
}

function Get-LrApiHeaders {
    param([string]$ApiTokenEnvironmentVariable)
    $headers = @{}
    if ($ApiTokenEnvironmentVariable) {
        $token = [Environment]::GetEnvironmentVariable($ApiTokenEnvironmentVariable, 'Process')
        if (-not $token) { $token = [Environment]::GetEnvironmentVariable($ApiTokenEnvironmentVariable, 'User') }
        if ($token) { $headers['Authorization'] = "Bearer $token" }
    }
    return $headers
}

function Invoke-LrApi {
    param([string]$Uri, [hashtable]$Headers, [string]$Method = 'GET', $Body, [int]$TimeoutSeconds = 300)
    $target=[Uri]$Uri
    if(-not $target.IsLoopback -or $target.Scheme -cne 'http' -or $target.UserInfo){throw 'LM Studio API access requires HTTP loopback without URL credentials.'}
    $arguments = @{ Uri = $Uri; Method = $Method; Headers = $Headers; TimeoutSec = $TimeoutSeconds; ErrorAction = 'Stop'; NoProxy=$true; MaximumRedirection=0 }
    if ($null -ne $Body) {
        $arguments.ContentType = 'application/json; charset=utf-8'
        $arguments.Body = [Text.Encoding]::UTF8.GetBytes(($Body | ConvertTo-Json -Depth 30 -Compress))
    }
    try { return Invoke-RestMethod @arguments }
    catch {
        # Do not emit response bodies or request headers, which might contain credentials.
        $errorResponse = Get-LrProperty $_.Exception 'Response'
        $status = if ($errorResponse) { [int](Get-LrProperty $errorResponse 'StatusCode' 0) } else { 0 }
        if ($status -eq 401 -or $status -eq 403) {
            $failure=[InvalidOperationException]::new('LM Studio API denied access. Existing authentication remains active. Store the API token in the specified user environment variable and retry.')
            $failure.Data['ShadowAuthenticationFailure']=$true
            throw $failure
        }
        throw "LM Studio API call failed (HTTP $status, $Method $Uri). Check LM Studio server and model logs."
    }
}

function Assert-LrLoopbackListener {
    param([int]$Port)
    $listeners = @(Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue)
    if ($listeners.Count -eq 0) { throw "No local listener found on port $Port." }
    $public = @($listeners | Where-Object { $_.LocalAddress -notin @('127.0.0.1', '::1') })
    if ($public.Count -gt 0) {
        $error=[InvalidOperationException]::new("Port $Port is not bound exclusively to loopback. Explicitly configure the existing LM Studio server for 127.0.0.1 and retry. This script does not change the running server.")
        $error.Data['ShadowLoopbackFailure']=$true
        throw $error
    }
}

function Test-LrExactReply {
    param([AllowEmptyString()][string]$Content,[Parameter(Mandatory)][string]$Expected)
    $text=$Content.Trim()
    return ($text -ceq $Expected -or $text -ceq ('"'+$Expected+'"'))
}

function Test-LrModelInference {
    param([string]$ApiBaseUrl, [string]$ModelId, [hashtable]$Headers)
    Write-Host 'Checking chat and actual tool calls of the loaded model ...'
    $chatBody = @{
        model = $ModelId; stream = $false; max_tokens = 4096; temperature = 0
        messages = @(
            @{ role = 'system'; content = 'Follow the user instruction exactly. Keep the final answer short.' },
            @{ role = 'user'; content = 'Reply with exactly the word LOCAL_READY and no other text.' }
        )
    }
    $chat = Invoke-LrApi -Uri "$ApiBaseUrl/chat/completions" -Headers $Headers -Method POST -Body $chatBody
    $choices = @(Get-LrProperty $chat 'choices')
    $content = if ($choices.Count) { [string](Get-LrProperty (Get-LrProperty $choices[0] 'message') 'content') } else { '' }
    if (-not (Test-LrExactReply -Content $content -Expected 'LOCAL_READY')) {
        throw 'Chat smoke test failed: model did not return the requested control response. No Ready status will be saved.'
    }
    $toolMessages = @(
        @{ role = 'system'; content = 'Use the supplied tool exactly as requested. Do not invent tool results.' },
        @{ role = 'user'; content = 'Call report_value with the integer value 17. Do not answer in prose.' }
    )
    $toolBody = @{
        model = $ModelId; stream = $false; max_tokens = 4096; temperature = 0; messages = $toolMessages
        tools = @(@{ type = 'function'; function = @{
            name = 'report_value'; description = 'Reports an integer to a deterministic local test.'
            parameters = @{ type = 'object'; properties = @{ value = @{ type = 'integer' } }; required = @('value'); additionalProperties = $false }
        } })
        tool_choice = 'required'
    }
    $response = Invoke-LrApi -Uri "$ApiBaseUrl/chat/completions" -Headers $Headers -Method POST -Body $toolBody
    $toolChoices = @(Get-LrProperty $response 'choices')
    if (-not $toolChoices.Count) { throw 'Tool smoke test: response without choices.' }
    $assistantMessage = Get-LrProperty $toolChoices[0] 'message'
    $calls = @(Get-LrProperty $assistantMessage 'tool_calls' @())
    if ($calls.Count -ne 1 -or (Get-LrProperty (Get-LrProperty $calls[0] 'function') 'name') -ne 'report_value') {
        throw 'Tool smoke test failed: no unique report_value call. Chat capability alone is insufficient for agents.'
    }
    try { $arguments = ConvertFrom-Json -InputObject (Get-LrProperty (Get-LrProperty $calls[0] 'function') 'arguments') -ErrorAction Stop }
    catch { throw 'Tool smoke test failed: function arguments are not valid JSON.' }
    $value = Get-LrProperty $arguments 'value'
    if ($value -isnot [long] -and $value -isnot [int]) { throw 'Tool smoke test failed: value is not a JSON integer.' }
    if ($value -ne 17 -or -not (Get-LrProperty $calls[0] 'id')) { throw 'Tool smoke test failed: incorrect value or missing tool-call ID.' }
    # A tool result round trip checks the chat template, not just one generated JSON blob.
    $toolBody.messages = @($toolMessages) + @(
        @{ role = 'assistant'; content = (Get-LrProperty $assistantMessage 'content'); tool_calls = $calls },
        @{ role = 'tool'; tool_call_id = (Get-LrProperty $calls[0] 'id'); content = '{"accepted":true,"receipt":"LOCAL_TOOL_OK"}' },
        @{ role = 'user'; content = 'Now reply with exactly the receipt string from the tool result, and no other text.' }
    )
    $toolBody.tool_choice = 'none'
    $roundTrip = Invoke-LrApi -Uri "$ApiBaseUrl/chat/completions" -Headers $Headers -Method POST -Body $toolBody
    $finalChoices = @(Get-LrProperty $roundTrip 'choices')
    $finalContent = if ($finalChoices.Count) { [string](Get-LrProperty (Get-LrProperty $finalChoices[0] 'message') 'content') } else { '' }
    if (-not (Test-LrExactReply -Content $finalContent -Expected 'LOCAL_TOOL_OK')) { throw 'Tool smoke test failed: model does not process the tool response correctly.' }
    return [pscustomobject]@{ Chat = 'Passed'; ToolCall = 'Passed'; ToolResultRoundTrip = 'Passed' }
}

function Write-LrRuntimeState {
    param([Parameter(Mandatory)][string]$StateRoot,[Parameter(Mandatory)]$State)
    $statePath=Join-Path $StateRoot 'runtime-state.json'
    $temporaryState=$statePath+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
    try {
        [IO.File]::WriteAllText($temporaryState,($State|ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temporaryState -Destination $statePath -Force
    } finally {if(Test-Path -LiteralPath $temporaryState){Remove-Item -LiteralPath $temporaryState -Force}}
}

function Configure-LocalRuntime {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StateRoot,
        [ValidateSet('Auto', 'Qwen27B', 'GptOss20B')][string]$PreferredModel = 'Auto',
        [ValidateRange(8192, 131072)][int]$ContextLength = 32768,
        [ValidateRange(1024, 65535)][int]$Port = 1234,
        [bool]$DownloadModel = $true,
        $SelectedProfile,
        [string]$ModelKey,
        [string]$LmsPath,
        [string]$ApiTokenEnvironmentVariable = 'LOKIENTE_LM_API_KEY',
        [switch]$AllowUnfitAttempt
    )
    if (-not $IsWindows) { throw 'Configure-LocalRuntime is designed for Windows with an NVIDIA GPU.' }
    $null = New-Item -ItemType Directory -Path $StateRoot -Force
    $logDirectory = Join-Path $StateRoot 'logs'
    $lms = Resolve-LocalLmsCommand -LmsPath $LmsPath
    $version = Invoke-LrNative -FilePath $lms -Arguments @('--version') -LogDirectory $logDirectory
    Assert-LrLoadCapabilities -LmsPath $lms -LogDirectory $logDirectory
    $hardware = Get-LocalNvidiaGpu -LogDirectory $logDirectory
    $profile = if($SelectedProfile){$SelectedProfile}else{Select-LrProfile -PreferredModel $PreferredModel -Hardware $hardware -ModelKey $ModelKey}
    Write-Host ('GPU: {0}; VRAM free/total: {1:n1}/{2:n1} GiB; RAM free/total: {3:n1}/{4:n1} GiB; Profile: {5}' -f $hardware.Gpu.Name, ($hardware.Gpu.FreeBytes / 1GB), ($hardware.Gpu.TotalBytes / 1GB), ($hardware.FreeRamBytes / 1GB), ($hardware.TotalRamBytes / 1GB), $profile.Name)

    $serverStatus = Invoke-LrJson -LmsPath $lms -Arguments @('server', 'status', '--json') -LogDirectory $logDirectory
    $reusedServer = [bool](Get-LrProperty $serverStatus 'running' $false)
    if ($reusedServer) {
        $Port = [int](Get-LrProperty $serverStatus 'port' 0)
        if ($Port -lt 1) { throw 'LM Studio reports a running server without a valid port.' }
        Assert-LrLoopbackListener -Port $Port
    } else {
        $occupied = @(Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue)
        if ($occupied.Count) { throw "Port $Port is already occupied. Preserve the existing service and rerun the script with a free -Port." }
        Write-Host "Starting LM Studio API at 127.0.0.1:$Port ..."
        $null = Invoke-LrNative -FilePath $lms -Arguments @('server', 'start', '--port', "$Port", '--bind', '127.0.0.1') -LogDirectory $logDirectory
        Assert-LrLoopbackListener -Port $Port
    }
    $headers = Get-LrApiHeaders -ApiTokenEnvironmentVariable $ApiTokenEnvironmentVariable
    $serverRoot = "http://127.0.0.1:$Port"
    $catalog = Invoke-LrApi -Uri "$serverRoot/api/v1/models" -Headers $headers -TimeoutSeconds 60
    if ($null -eq $catalog -or $null -eq $catalog.PSObject.Properties['models']) {
        throw 'Expected LM Studio REST v1 model data missing. Install a current LM Studio version.'
    }

    $models = @(Get-LrDownloadedModels -LmsPath $lms -LogDirectory $logDirectory)
    $selected = Find-LrModel -Models $models -Profile $profile -ModelKey $ModelKey
    $downloaded = $false
    $loadedBefore = @(Invoke-LrJson -LmsPath $lms -Arguments @('ps', '--json') -LogDirectory $logDirectory)
    $localLoaded = @($loadedBefore | Where-Object { $null -eq (Get-LrProperty $_ 'deviceIdentifier' '__unknown__') })
    $engine = $null
    if (-not $selected) {
        if ($ModelKey) { throw 'The explicit model is not uniquely available locally. Specify the full path or modelKey from lms ls --json.' }
        if (-not $DownloadModel) { throw 'The selected model is missing; DownloadModel is disabled.' }
        if ($localLoaded.Count) { throw 'Another local model is loaded. It will not be stopped. Explicitly unload models in LM Studio and rerun provisioning.' }
        $engine = Ensure-LrInferenceEngine -LmsPath $lms -LogDirectory $logDirectory
        Write-Host "Downloading $($profile.Name) from the specified GGUF file; existing LM Studio model directory is preserved ..."
        $null = Invoke-LrNative -FilePath $lms -Arguments @('get', $profile.DownloadUrl, '--gguf', '--yes') -LogDirectory $logDirectory -TimeoutSeconds 14400
        $models = @(Get-LrDownloadedModels -LmsPath $lms -LogDirectory $logDirectory)
        $selected = Find-LrModel -Models $models -Profile $profile
        if (-not $selected) { throw 'Download completed, but the exact expected local model was not found. No approximate replacement selected.' }
        $downloaded = $true
    }
    $selectedPath = [string](Get-LrProperty $selected 'path')
    $selectedKey = [string](Get-LrProperty $selected 'modelKey')
    $selectedVariant=[string](Get-LrProperty $selected 'selectedVariant')
    if(-not $ModelKey){Assert-LrSelectedModel -LmsPath $lms -LogDirectory $logDirectory -ExpectedPath $profile.ExpectedPath -ModelPath $selectedPath}
    $matchingLoaded = @($localLoaded | Where-Object {
        (Get-LrProperty $_ 'path') -ceq $selectedPath -and (Get-LrProperty $_ 'modelKey') -ceq $selectedKey
    })
    $foreignLoaded = @($localLoaded | Where-Object {
        (Get-LrProperty $_ 'path') -cne $selectedPath -or (Get-LrProperty $_ 'modelKey') -cne $selectedKey
    })
    if ($foreignLoaded.Count) { throw 'Other local models are already loaded. This script does not unload them. End the existing session or explicitly unload them yourself.' }
    if ($matchingLoaded.Count -gt 1) { throw 'Multiple instances of the target model are loaded. Provide a unique instance for local coding.' }
    $modelId = 'shadow-local-coder'
    $effectiveContext = $ContextLength
    $memoryEstimate = $null
    $reusedModel = $matchingLoaded.Count -eq 1
    if ($reusedModel) {
        $modelId = [string](Get-LrProperty $matchingLoaded[0] 'identifier')
        if (-not $modelId -or [int](Get-LrProperty $matchingLoaded[0] 'parallel' 0) -ne 1) {
            throw 'Existing model instance is not verifiably limited to one concurrent request. It remains unchanged; unload it in LM Studio and rerun provisioning.'
        }
        if ((Get-LrProperty $matchingLoaded[0] 'status') -eq 'processing' -or [int](Get-LrProperty $matchingLoaded[0] 'queued' 0) -gt 0) {
            throw 'Existing model instance is busy. Rerun provisioning after active requests finish.'
        }
    } else {
        if (-not $engine) { $engine = Ensure-LrInferenceEngine -LmsPath $lms -LogDirectory $logDirectory }
        try {
            # Reserve capacity for the desktop/VS Code; never disable LM Studio guardrails.
            $contexts = @($ContextLength)
            if ($ContextLength -gt 16384) { $contexts += 16384 }
            $guardrailCandidate=$null;$lastCandidate=$null
            foreach ($context in ($contexts | Select-Object -Unique)) {
                if(-not $ModelKey){Assert-LrSelectedModel -LmsPath $lms -LogDirectory $logDirectory -ExpectedPath $profile.ExpectedPath -ModelPath $selectedPath}
                Write-Host "Checking memory requirements for $context context tokens and one inference slot ..."
                $estimate = Invoke-LrModelCommand -LmsPath $lms -Arguments @('load', $selectedPath, '--exact', '--local', '--context-length', "$context", '--parallel', '1', '--gpu', 'max', '--estimate-only', '--yes') -LogDirectory $logDirectory
                $estimateText = $estimate.Stdout + "`n" + $estimate.Stderr
                $gpuBytes = Convert-LrEstimatedBytes -Text $estimateText -Label 'Estimated GPU Memory'
                $totalBytes = Convert-LrEstimatedBytes -Text $estimateText -Label 'Estimated Total Memory'
                $freshHardware = Get-LocalNvidiaGpu -LogDirectory $logDirectory
                $allowed = $estimateText -match 'This model may be loaded based on your resource guardrails settings\.'
                $candidate=[pscustomobject]@{GpuBytes=$gpuBytes;TotalBytes=$totalBytes;ContextLength=$context;LogPath=$estimate.LogPath;ReserveOverride=$false}
                $lastCandidate=$candidate
                if($allowed -and -not $guardrailCandidate){$guardrailCandidate=$candidate}
                if ($allowed -and $estimateText -notmatch 'Confidence:\s*LOW' -and
                    $gpuBytes -le ($freshHardware.Gpu.FreeBytes - 1GB) -and
                    $totalBytes -le ($freshHardware.FreeRamBytes - 3GB)) {
                    $effectiveContext = $context
                    $memoryEstimate = $candidate
                    break
                }
            }
            if ($null -eq $memoryEstimate) {
                $fitMessage="No verified memory fit with at least 16K context (or the requested smaller context). Logs: $logDirectory"
                if(-not $AllowUnfitAttempt){throw $fitMessage}
                $memoryEstimate=if($guardrailCandidate){$guardrailCandidate}else{$lastCandidate}
                if(-not $memoryEstimate){throw 'No usable LM Studio memory estimate available.'}
                $memoryEstimate.ReserveOverride=$true
                $effectiveContext=[int]$memoryEstimate.ContextLength
                Write-Warning "$fitMessage Attempting load without LoKiEnte reserve; LM Studio safeguards remain active."
            }
            Write-Host "Loading model with $effectiveContext context tokens, GPU offload max and exactly one inference slot ..."
            if(-not $ModelKey){Assert-LrSelectedModel -LmsPath $lms -LogDirectory $logDirectory -ExpectedPath $profile.ExpectedPath -ModelPath $selectedPath}
            $loadArguments=@('load', $selectedPath, '--exact', '--local', '--context-length', "$effectiveContext", '--parallel', '1', '--gpu', 'max', '--identifier', $modelId, '--yes')
            $null=Invoke-LrModelCommand -LmsPath $lms -Arguments $loadArguments -LogDirectory $logDirectory -TimeoutSeconds 900
        } catch {
            if(-not ($_.Exception.Data['ShadowResourceFitFailure'] -or $_.Exception.Data['ShadowRuntimeCompatibilityFailure'] -or $_.Exception.Data['ShadowModelLoadFailure'])){throw}
            $message=$_.Exception.Message
            $state=[pscustomobject]@{
                SchemaVersion=1;Status='Deferred';CheckedAtUtc=[DateTime]::UtcNow.ToString('o')
                LmsPath=$lms;LmsVersion=$version.Stdout.Trim();Profile=$profile.Name;ModelId=$modelId;ModelKey=$selectedKey;ModelPath=$selectedPath
                ContextLength=$effectiveContext;Parallel=1;ApiBaseUrl="$serverRoot/v1";Port=$Port;ApiTokenEnvironmentVariable=$ApiTokenEnvironmentVariable
                ReusedServer=$reusedServer;ReusedLoadedModel=$false;Downloaded=$downloaded;Hardware=$hardware;InferenceEngine=$engine
                Estimate=$memoryEstimate;SmokeTests=[pscustomobject]@{Chat='NotRun';ToolCall='NotRun';ToolResultRoundTrip='NotRun'};LogsPath=$logDirectory;VerificationMessage=$message
            }
            Write-LrRuntimeState -StateRoot $StateRoot -State $state
            Write-Warning $message
            return $state
        }
    }
    Assert-LrLoopbackListener -Port $Port
    $catalog = Invoke-LrApi -Uri "$serverRoot/api/v1/models" -Headers $headers -TimeoutSeconds 60
    $instances = @()
    foreach ($entry in @(Get-LrProperty $catalog 'models' @())) {
        foreach ($instance in @(Get-LrProperty $entry 'loaded_instances' @())) {
            if ((Get-LrProperty $instance 'id') -ceq $modelId) { $instances += [pscustomobject]@{ Model = $entry; Instance = $instance } }
        }
    }
    if ($instances.Count -ne 1) { throw 'Loaded target instance cannot be uniquely verified through REST v1.' }
    $actualConfig = Get-LrProperty $instances[0].Instance 'config'
    $actualContext = [int](Get-LrProperty $actualConfig 'context_length' 0)
    $actualParallel = [int](Get-LrProperty $actualConfig 'parallel' 0)
    if ($actualParallel -ne 1 -or $actualContext -lt [Math]::Min($ContextLength, 16384)) {
        throw "Loaded configuration is unsuitable: context=$actualContext, parallel=$actualParallel. Existing instance is preserved."
    }
    if (-not $reusedModel -and $actualContext -ne $effectiveContext) { throw 'Actual context differs from the requested load profile.' }
    $actualPs = @(Invoke-LrJson -LmsPath $lms -Arguments @('ps', '--json') -LogDirectory $logDirectory)
    $verified = @($actualPs | Where-Object { (Get-LrProperty $_ 'identifier') -ceq $modelId -and $null -eq (Get-LrProperty $_ 'deviceIdentifier' '__unknown__') -and (Get-LrProperty $_ 'path') -ceq $selectedPath })
    if ($verified.Count -ne 1) { throw 'Could not confirm local origin and exact model file after loading.' }
    if($selectedVariant -and (Get-LrProperty $verified[0] 'selectedVariant') -cne $selectedVariant){throw 'Loaded model variant does not match the verified profile.'}
    if($selectedVariant -and -not $ModelKey){Assert-LrSelectedModel -LmsPath $lms -LogDirectory $logDirectory -ExpectedPath $profile.ExpectedPath -ModelPath $selectedPath}
    $testError=''
    try {
        $tests = Test-LrModelInference -ApiBaseUrl "$serverRoot/v1" -ModelId $modelId -Headers $headers
    } catch {
        $testError=$_.Exception.Message
        $tests=[pscustomobject]@{Chat='NotVerified';ToolCall='NotVerified';ToolResultRoundTrip='NotVerified'}
        Write-Warning "Model test failed; model remains downloaded and unverified: $testError"
    }
    $state = [pscustomobject]@{
        SchemaVersion = 1; Status = $(if($testError){'Deferred'}else{'Ready'}); CheckedAtUtc = [DateTime]::UtcNow.ToString('o')
        LmsPath = $lms; LmsVersion = $version.Stdout.Trim(); Profile = $profile.Name
        ModelId = $modelId; ModelKey = $selectedKey; ModelPath = $selectedPath
        ContextLength = $actualContext; Parallel = $actualParallel; ApiBaseUrl = "$serverRoot/v1"; Port = $Port
        ApiTokenEnvironmentVariable = $ApiTokenEnvironmentVariable
        ReusedServer = $reusedServer; ReusedLoadedModel = $reusedModel; Downloaded = $downloaded
        Hardware = $hardware; InferenceEngine = $engine; Estimate = $memoryEstimate; SmokeTests = $tests; LogsPath = $logDirectory;VerificationMessage=$testError
    }
    Write-LrRuntimeState -StateRoot $StateRoot -State $state
    if($testError){Write-Warning "Local runtime not yet verified: $modelId; $actualContext Tokens; $serverRoot/v1"}
    else{Write-Host "Local runtime ready: $modelId; $actualContext Tokens; $serverRoot/v1"}
    return $state
}
