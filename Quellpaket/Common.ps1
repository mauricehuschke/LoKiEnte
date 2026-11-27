# Shared helpers. PowerShell 7.4 or newer.
Set-StrictMode -Version Latest

function Initialize-ShadowToolchainLogging {
    param([Parameter(Mandatory)][string]$InstallRoot)
    $script:ShadowToolchainLogRoot=[IO.Path]::GetFullPath($InstallRoot)
}

function Write-ShadowToolchainEvent {
    param([string]$Component='LoKiEnte',[ValidateSet('INFO','WARN','ERROR')][string]$Level='INFO',[string]$Message)
    $root=Get-Variable -Name ShadowToolchainLogRoot -Scope Script -ValueOnly -ErrorAction SilentlyContinue
    if(-not $root){return}
    try{
        $safe=[string]$Message
        foreach($entry in [Environment]::GetEnvironmentVariables('Process').GetEnumerator()){
            if($entry.Key -match '(?i)token|api.?key|password' -and ([string]$entry.Value).Length -gt 3){$safe=$safe.Replace([string]$entry.Value,'[REDACTED]')}
        }
        $safe=$safe -replace '(?i)(Bearer\s+|Basic\s+)[A-Za-z0-9+/_=.:-]+','$1[REDACTED]'
        $safe=$safe -replace '(?i)((?:api[_-]?key|password|authorization|auth_token|access_token|refresh_token)\s*["'']?\s*[:=]\s*["'']?)[^\s"'',;}]+','$1[REDACTED]'
        $safe=$safe -replace '(?i)([?&](?:token|key|password|auth_token)=)[^&\s]+','$1[REDACTED]'
        $directory=Join-Path $root 'runtime';[void][IO.Directory]::CreateDirectory($directory)
        $record=[ordered]@{utc=[DateTime]::UtcNow.ToString('o');level=$Level;component=$Component;message=$safe;pid=$PID}
        [IO.File]::AppendAllText((Join-Path $directory 'toolchain-events.jsonl'),(($record|ConvertTo-Json -Compress)+[Environment]::NewLine),[Text.UTF8Encoding]::new($false))
        if(Get-Command Add-ShadowProvisionEvidence -CommandType Function -ErrorAction SilentlyContinue){Add-ShadowProvisionEvidence events $record}
    }catch{Write-Verbose 'Could not append the local toolchain event.'}
}

function Write-ShadowMessage {
    param([string]$Message, [ValidateSet('INFO','WARN','OK')][string]$Level='INFO')
    Write-Host ('[{0}] {1}' -f $Level, $Message)
    Write-ShadowToolchainEvent -Level $(if($Level -eq 'WARN'){'WARN'}else{'INFO'}) -Message $Message
}

function Invoke-ShadowNative {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList=@(),
        [string]$WorkingDirectory,
        [int]$TimeoutSeconds=1800,
        [switch]$AllowFailure,
        [switch]$Quiet,
        [hashtable]$Environment=@{},
        [scriptblock]$ProgressCallback
    )
    # Never use a shell to concatenate arguments. .cmd shims must be resolved to
    # their node/native entry point by the caller.
    if ([IO.Path]::GetExtension($FilePath) -in @('.cmd','.bat','.ps1')) {
        throw "Native entry point required, not a shell shim: $FilePath"
    }
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName=$FilePath
    $start.UseShellExecute=$false
    $start.CreateNoWindow=$true
    $start.RedirectStandardOutput=$true
    $start.RedirectStandardError=$true
    foreach ($argument in $ArgumentList) { $start.ArgumentList.Add([string]$argument) }
    if ($WorkingDirectory) { $start.WorkingDirectory=$WorkingDirectory }
    foreach ($name in $Environment.Keys) { $start.Environment[[string]$name]=[string]$Environment[$name] }
    $process=[Diagnostics.Process]::new()
    $process.StartInfo=$start
    $readCancellation=[Threading.CancellationTokenSource]::new()
    $commandName=[IO.Path]::GetFileName($FilePath)
    $evidenceClock=[Diagnostics.Stopwatch]::StartNew();$stdout='';$stderr='';$nativeFailure=$null;$nativeExit=$null
    Write-ShadowToolchainEvent -Component $commandName -Message 'Starting native tool.'
    try {
        if (-not $process.Start()) { throw 'Process did not start.' }
        if($PSVersionTable.PSVersion -ge [version]'7.4'){
            $outTask=$process.StandardOutput.ReadToEndAsync($readCancellation.Token)
            $errTask=$process.StandardError.ReadToEndAsync($readCancellation.Token)
        }else{
            $outTask=$process.StandardOutput.ReadToEndAsync()
            $errTask=$process.StandardError.ReadToEndAsync()
        }
        $clock=[Diagnostics.Stopwatch]::StartNew()
        while (-not $process.WaitForExit(1000)) {
            if($ProgressCallback){$null=& $ProgressCallback}
            if ($clock.Elapsed.TotalSeconds -ge $TimeoutSeconds) {
                $process.Kill($true)
                $readCancellation.Cancel()
                throw "Timeout after $TimeoutSeconds seconds: $([IO.Path]::GetFileName($FilePath))"
            }
            if (-not $Quiet -and ([int]$clock.Elapsed.TotalSeconds % 30 -eq 0)) {
                Write-Host ('  ... {0} has been running for {1}s' -f [IO.Path]::GetFileName($FilePath), [int]$clock.Elapsed.TotalSeconds)
            }
        }
        while(-not $outTask.IsCompleted -or -not $errTask.IsCompleted){
            if($clock.Elapsed.TotalSeconds -ge $TimeoutSeconds){
                $readCancellation.Cancel()
                throw "Timeout after $TimeoutSeconds seconds waiting for $commandName output to close."
            }
            Start-Sleep -Milliseconds 50
        }
        $stdout=$outTask.GetAwaiter().GetResult()
        $stderr=$errTask.GetAwaiter().GetResult()
        $result=[pscustomobject]@{ExitCode=$process.ExitCode;StdOut=$stdout;StdErr=$stderr}
        $nativeExit=$process.ExitCode
        Write-ShadowToolchainEvent -Component $commandName -Level $(if($result.ExitCode -eq 0){'INFO'}else{'ERROR'}) -Message "Native tool exited with code $($result.ExitCode)."
        if($stderr.Trim()){Write-ShadowToolchainEvent -Component $commandName -Level $(if($result.ExitCode -eq 0){'WARN'}else{'ERROR'}) -Message $stderr.TrimEnd()}
        if (-not $Quiet) {
            if ($stdout.Trim()) { Write-Host $stdout.TrimEnd() }
            if ($stderr.Trim()) { Write-Host $stderr.TrimEnd() }
        }
        if ($result.ExitCode -ne 0 -and -not $AllowFailure) {
            throw ('{0} failed (exit {1}). {2}' -f [IO.Path]::GetFileName($FilePath),$result.ExitCode,($stderr+$stdout).Trim())
        }
        return $result
    }
    catch { $nativeFailure=$_.Exception.Message;Write-ShadowToolchainEvent -Component $commandName -Level ERROR -Message $_.Exception.Message;throw }
    finally {
        $readCancellation.Cancel();$process.Dispose();$readCancellation.Dispose()
        if(Get-Command Add-ShadowProvisionCommand -CommandType Function -ErrorAction SilentlyContinue){Add-ShadowProvisionCommand -File $FilePath -Arguments $ArgumentList -WorkingDirectory $WorkingDirectory -TimeoutSeconds $TimeoutSeconds -ExitCode $nativeExit -Stdout $stdout -Stderr $stderr -DurationMs $evidenceClock.Elapsed.TotalMilliseconds -Failure $nativeFailure}
    }
}

function Update-ShadowProcessPath {
    if ($IsWindows) {
        $machinePath=[Environment]::GetEnvironmentVariable('Path','Machine')
        $userPath=[Environment]::GetEnvironmentVariable('Path','User')
        $parts=@($env:Path -split ';')+@($machinePath -split ';')+@($userPath -split ';')
        $env:Path=($parts | Where-Object { $_ } | Select-Object -Unique) -join ';'
    }
}

function Get-ShadowCurlPackageRegistration {
    # WinGet identifies portable installations by package ID and source ID.
    $productCode='cURL.cURL_Microsoft.Winget.Source_8wekyb3d8bbwe'
    foreach ($hive in 'HKCU:','HKLM:') {
        $key="$hive\Software\Microsoft\Windows\CurrentVersion\Uninstall\$productCode"
        $entry=Get-ItemProperty -LiteralPath $key -Name InstallLocation,DisplayVersion -ErrorAction SilentlyContinue
        if ($entry -and $entry.InstallLocation -and $entry.DisplayVersion -match '^\d+\.\d+\.\d+(?:\.\d+)?$') {
            $entry
        }
    }
}

function Resolve-ShadowTool {
    param([Parameter(Mandatory)][ValidateSet('git','node','npm','code','pwsh','winget','lmstudio','lms','curl')][string]$Name)
    $candidate=[Collections.Generic.List[string]]::new()
    $command=Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($Name -eq 'curl') {
        # A portable package may have no Links alias, and System32 usually comes
        # first in PATH. Use the exact executable named by the registered package.
        $packages=@(Get-ShadowCurlPackageRegistration | Sort-Object { [version]$_.DisplayVersion } -Descending)
        foreach ($package in $packages) {
            $version=[version]$package.DisplayVersion
            $archiveName='curl-'+$version.ToString(3)
            if ($version.Revision -gt 0) { $archiveName+='_'+$version.Revision }
            $candidate.Add((Join-Path $package.InstallLocation "$archiveName-win64-mingw/bin/curl.exe"))
        }
        foreach ($directory in @("$env:LOCALAPPDATA/Microsoft/WinGet/Links","$env:ProgramFiles/WinGet/Links")) {
            $candidate.Add((Join-Path $directory 'curl.exe'))
        }
        # WinGet can expose the nested bin directory directly through PATH.
        foreach ($application in @(Get-Command curl.exe -All -CommandType Application -ErrorAction SilentlyContinue)) {
            if ($application.Source -match '[\\/]curl-\d+\.\d+\.\d+(?:_\d+)?-win64-mingw[\\/]bin[\\/]curl\.exe$') {
                $candidate.Add($application.Source)
            }
        }
    }
    if ($command) { $candidate.Add($command.Source) }
    switch ($Name) {
        'code' {
            $candidate.Add((Join-Path $env:LOCALAPPDATA 'Programs/Microsoft VS Code/Code.exe'))
            $candidate.Add((Join-Path $env:ProgramFiles 'Microsoft VS Code/Code.exe'))
        }
        'git' { $candidate.Add((Join-Path $env:ProgramFiles 'Git/cmd/git.exe')) }
        'node' { $candidate.Add((Join-Path $env:ProgramFiles 'nodejs/node.exe')) }
        'npm' { $candidate.Add((Join-Path $env:ProgramFiles 'nodejs/npm.cmd')) }
        'pwsh' { $candidate.Add((Join-Path $env:ProgramFiles 'PowerShell/7/pwsh.exe')) }
        'winget' { $candidate.Add((Join-Path $env:LOCALAPPDATA 'Microsoft/WindowsApps/winget.exe')) }
        'curl' { $candidate.Add((Join-Path $env:SystemRoot 'System32/curl.exe')) }
        'lmstudio' {
            $candidate.Add((Join-Path $env:LOCALAPPDATA 'Programs/LM Studio/LM Studio.exe'))
            $candidate.Add((Join-Path $env:ProgramFiles 'LM Studio/LM Studio.exe'))
        }
        'lms' { $candidate.Add((Join-Path $env:USERPROFILE '.lmstudio/bin/lms.exe')) }
    }
    foreach ($path in $candidate) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
        if ($Name -eq 'code' -and [IO.Path]::GetExtension($path) -eq '.cmd') {
            $exe=Join-Path (Split-Path (Split-Path $path -Parent) -Parent) 'Code.exe'
            if (Test-Path -LiteralPath $exe -PathType Leaf) { return (Resolve-Path -LiteralPath $exe).Path }
            continue
        }
        return (Resolve-Path -LiteralPath $path).Path
    }
    return $null
}

function Resolve-ShadowNpm {
    param([Parameter(Mandatory)][string]$NodePath)
    $candidates=[Collections.Generic.List[string]]::new()
    $candidates.Add((Join-Path (Split-Path $NodePath -Parent) 'node_modules/npm/bin/npm-cli.js'))
    $npmCommand=Get-Command npm -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($npmCommand) {
        $candidates.Add((Join-Path (Split-Path $npmCommand.Source -Parent) 'node_modules/npm/bin/npm-cli.js'))
    }
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return (Resolve-Path -LiteralPath $candidate).Path }
    }
    throw 'npm-cli.js was not found. The existing Node/npm installation remains unchanged; repair that installation.'
}

function Install-ShadowNpm {
    param([string]$NodePath,[string]$Root,[string]$Target)
    $bundled=Resolve-ShadowNpm -NodePath $NodePath
    $bundledVersion=(Invoke-ShadowNative $NodePath @($bundled,'--version') -Quiet).StdOut.Trim()
    if ($bundledVersion -notmatch '^\d+\.\d+\.\d+$' -or $Target -notmatch '^\d+\.\d+\.\d+$') {throw 'Invalid npm version.'}

    $selected=$Target
    $stateFile=Join-Path $Root 'toolchain.json'
    if (Test-Path -LiteralPath $stateFile -PathType Leaf) {
        $saved=(Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json -AsHashtable)['npmVersion']
        if ($saved -match '^\d+\.\d+\.\d+$' -and [version]$saved -gt [version]$selected) { $selected=$saved }
    }
    if ([version]$bundledVersion -ge [version]$selected) {return @{Entry=$bundled;Version=$bundledVersion}}
    $prefix=Join-Path $Root "tooling/npm-versions/$selected"
    $entry=Join-Path $prefix 'node_modules/npm/bin/npm-cli.js'
    if (Test-Path -LiteralPath $entry -PathType Leaf) {
        $probe=Invoke-ShadowNative $NodePath @($entry,'--version') -AllowFailure -Quiet
        if ($probe.ExitCode -eq 0 -and $probe.StdOut.Trim() -ceq $selected -and (Test-Path -LiteralPath (Join-Path $prefix 'npm.cmd'))) {
            return @{Entry=$entry;Version=$selected}
        }
    }
    if ($selected -ne $Target) {throw "Previously active npm $selected is unavailable. Repair that installation before retrying."}
    $before=[datetime]::UtcNow.AddHours(-48).ToString('o')
    Write-ShadowMessage "Installing npm $selected for LoKiEnte ..."
    $null=Invoke-ShadowNative $NodePath @($bundled,'install','--global','--prefix',$prefix,"npm@$selected",'--before',$before,
        '--registry=https://registry.npmjs.org/','--ignore-scripts','--engine-strict','--no-update-notifier','--no-audit','--no-fund')
    $actual=(Invoke-ShadowNative $NodePath @($entry,'--version') -Quiet).StdOut.Trim()
    if ($actual -cne $selected -or !(Test-Path -LiteralPath (Join-Path $prefix 'npm.cmd'))) {throw "npm $selected failed verification."}
    return @{Entry=$entry;Version=$actual}
}

function Install-ShadowPackage {
    param([string]$Tool,[string]$PackageId,[string]$WingetPath,[string]$AcceptedVersion)
    $existing=Resolve-ShadowTool -Name $Tool
    $accepted=if($AcceptedVersion){Get-ShadowComparableVersion $AcceptedVersion}else{$null}
    if($existing -and $accepted){
        $current=Get-ShadowInstalledVersion -Tool $Tool -Path $existing
        if(-not $current){throw "Cannot determine installed version of $Tool. Upgrade to $AcceptedVersion was not started."}
        if($current -ge $accepted){
            Write-ShadowMessage "$Tool $current is already at or above the approved version $AcceptedVersion."
            return $existing
        }
    }elseif ($existing) {
        Write-ShadowMessage "Available: $Tool ($existing)"
        return $existing
    }
    $action=if($existing){'upgrade'}else{'install'}
    # System curl and the other Node channel can exist without this WinGet ID.
    # WinGet install also upgrades registered packages unless --no-upgrade is set.
    if ($existing -and $Tool -in @('curl','node')) { $action='install' }
    $arguments=@($action,'--id',$PackageId,'--exact','--source','winget','--silent','--accept-package-agreements','--accept-source-agreements','--disable-interactivity')
    if(-not $existing){$arguments+=@('--no-upgrade')}
    if($accepted){$arguments+=@('--version',$AcceptedVersion)}
    Write-ShadowMessage "WinGet $action for $PackageId $AcceptedVersion ..."
    $result=Invoke-ShadowNative -FilePath $WingetPath -ArgumentList $arguments -AllowFailure
    Update-ShadowProcessPath
    $resolved=Resolve-ShadowTool -Name $Tool
    if (-not $resolved) {
        throw "Package $PackageId was not found in a usable state (WinGet exit $($result.ExitCode)). If a restart was requested, rerun this script afterwards."
    }
    if ($result.ExitCode -notin @(0,3010,1641)) {
        # A tool discovered after a non-success installer exit is reported, not
        # silently accepted. Re-running reuses it after the operator has seen it.
        throw "WinGet returned $($result.ExitCode) for $PackageId. Program found, but installation status is unconfirmed. Check the output and retry."
    }
    if($accepted){
        $observed=Get-ShadowInstalledVersion -Tool $Tool -Path $resolved
        if(-not $observed -or $observed -lt $accepted){
            $display=if($observed){$observed.ToString()}else{'unknown'}
            throw "$Tool does not meet approved version $AcceptedVersion after WinGet. Detected $display at '$resolved' (WinGet exit $($result.ExitCode))."
        }
    }
    return $resolved
}

function Get-ShadowInstalledVersion {
    param([string]$Tool,[string]$Path)
    switch($Tool){
        'curl' {
            $file=Get-Item -LiteralPath $Path
            $binary=$file.FullName
            if ($file.LinkType -eq 'SymbolicLink') { $binary=$file.ResolveLinkTarget($true).FullName }
            $value=(Invoke-ShadowNative -FilePath $Path -ArgumentList @('--version') -Quiet -TimeoutSeconds 30).StdOut
            if ($value -notmatch '^curl (\d+\.\d+\.\d+)(?:\s|$)') { return $null }
            $baseVersion=$Matches[1]
            $revision=0
            # Only the verified executable's own archive layout supplies its
            # packaging revision. Never transfer a receipt to another curl.exe.
            if ($binary -match '[\\/]curl-(\d+\.\d+\.\d+)_(\d+)-win64-mingw[\\/]bin[\\/]curl\.exe$' -and
                $Matches[1] -eq $baseVersion) { $revision=$Matches[2] }
            return [version]"$baseVersion.$revision"
        }
        'git' {
            $value=(Invoke-ShadowNative -FilePath $Path -ArgumentList @('--version') -Quiet -TimeoutSeconds 30).StdOut
            if ($value -match '(\d+\.\d+\.\d+)\.windows\.(\d+)') {
                if ([int]$Matches[2] -gt 1) { return [version]($Matches[1]+'.'+$Matches[2]) }
            }
        }
        'lmstudio' { $value=(Get-Item -LiteralPath $Path).VersionInfo.ProductVersion }
        'code' { $value=(Invoke-ShadowCodeCli -CodePath $Path -Arguments @('--version')).StdOut }
        default { $value=(Invoke-ShadowNative -FilePath $Path -ArgumentList @('--version') -Quiet -TimeoutSeconds 30).StdOut }
    }
    return Get-ShadowComparableVersion $value
}

function Write-ShadowManagedFile {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][AllowEmptyString()][string]$Content,[string]$BackupRoot)
    $newBytes=[Text.UTF8Encoding]::new($false).GetBytes($Content)
    if (Test-Path -LiteralPath $Path) {
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "File conflict: $Path" }
        $oldBytes=[IO.File]::ReadAllBytes($Path)
        if ([Convert]::ToBase64String($oldBytes) -eq [Convert]::ToBase64String($newBytes)) {
            if(Get-Command Add-ShadowProvisionEvidence -CommandType Function -ErrorAction SilentlyContinue){Add-ShadowProvisionEvidence activities @{kind='ManagedFile';path=$Path;status='UNCHANGED';bytes=$newBytes.Length}}
            return $false
        }
        if (-not $BackupRoot) { throw "Existing file would be overwritten: $Path" }
        [IO.Directory]::CreateDirectory($BackupRoot) | Out-Null
        $tag=[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffffffZ')
        $backup=Join-Path $BackupRoot ($tag+'-'+[IO.Path]::GetFileName($Path))
        [IO.File]::Copy($Path,$backup,$false)
    }
    [IO.Directory]::CreateDirectory((Split-Path $Path -Parent)) | Out-Null
    $temporary=$Path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
    try {
        [IO.File]::WriteAllBytes($temporary,$newBytes)
        [IO.File]::Move($temporary,$Path,$true)
    } finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force } }
    if(Get-Command Add-ShadowProvisionEvidence -CommandType Function -ErrorAction SilentlyContinue){Add-ShadowProvisionEvidence activities @{kind='ManagedFile';path=$Path;status='WRITTEN';bytes=$newBytes.Length;backupDirectory=$BackupRoot}}
    return $true
}

function Get-ShadowInventory {
    $os=Get-CimInstance Win32_OperatingSystem
    $cpu=@(Get-CimInstance Win32_Processor | Select-Object Name,NumberOfCores,NumberOfLogicalProcessors)
    $drives=@(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType = 3' | ForEach-Object {
        @{Drive=$_.DeviceID;TotalGiB=[Math]::Round($_.Size/1GB,1);FreeGiB=[Math]::Round($_.FreeSpace/1GB,1)}
    })
    $gpu=$null
    $smi=Get-Command nvidia-smi -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($smi) {
        $result=Invoke-ShadowNative -FilePath $smi.Source -ArgumentList @('--query-gpu=name,memory.total,memory.free,driver_version','--format=csv,noheader,nounits') -AllowFailure -Quiet -TimeoutSeconds 30
        if ($result.ExitCode -eq 0) { $gpu=$result.StdOut.Trim() }
    }
    $tools=[ordered]@{}
    foreach ($name in @('pwsh','winget','git','node','npm','code','lmstudio','lms','curl')) { $tools[$name]=Resolve-ShadowTool -Name $name }
    return [ordered]@{
        TimestampUtc=[DateTime]::UtcNow.ToString('o');Windows=$os.Caption;Build=$os.BuildNumber
        Architecture=[Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
        MemoryGiB=[Math]::Round($os.TotalVisibleMemorySize/1MB,1)
        FreeMemoryGiB=[Math]::Round($os.FreePhysicalMemory/1MB,1)
        CPU=$cpu;GPU=$gpu;Drives=$drives;Tools=$tools
    }
}

function Resolve-ShadowCodeCli {
    param([Parameter(Mandatory)][string]$CodePath)
    $root=Split-Path -Parent ([IO.Path]::GetFullPath($CodePath))
    $wrapper=Join-Path $root 'bin/code.cmd'
    if(Test-Path -LiteralPath $wrapper -PathType Leaf){
        $exe=[regex]::Escape([IO.Path]::GetFileName($CodePath))
        $pattern='^\s*"%~dp0\.\.\\'+$exe+'"\s+"%~dp0\.\.\\(?:(?<version>[A-Za-z0-9][A-Za-z0-9._-]*)\\)?resources\\app\\out\\cli\.js"\s+%\*\s*$'
        $matches=@(Get-Content -LiteralPath $wrapper -ErrorAction Stop|Where-Object {$_ -match $pattern})
        if($matches.Count -ne 1){
            throw "VS Code CLI path in $wrapper is not unambiguous in the expected format. Existing installation remains unchanged."
        }
        $match=[regex]::Match($matches[0],$pattern,[Text.RegularExpressions.RegexOptions]::IgnoreCase)
        $relative=if($match.Groups['version'].Success){
            Join-Path $match.Groups['version'].Value 'resources/app/out/cli.js'
        }else{'resources/app/out/cli.js'}
        $cli=Join-Path $root $relative
        if(-not(Test-Path -LiteralPath $cli -PathType Leaf)){throw "The CLI entry point declared by VS Code is missing: $cli. Check the existing installation."}
        return $cli
    }
    $legacy=Join-Path $root 'resources/app/out/cli.js'
    if(Test-Path -LiteralPath $legacy -PathType Leaf){return $legacy}
    throw "VS Code CLI not found: $wrapper and $legacy. Check the existing installation."
}

function Invoke-ShadowCodeCli {
    param([string]$CodePath,[string[]]$Arguments)
    $cli=Resolve-ShadowCodeCli -CodePath $CodePath
    $environment=@{ELECTRON_RUN_AS_NODE='1';VSCODE_DEV=''}
    foreach($key in [Environment]::GetEnvironmentVariables('Process').Keys){
        if($key -match '^(VSCODE|ELECTRON)_'){$environment[$key]=''}
    }
    $environment.ELECTRON_RUN_AS_NODE='1'
    return Invoke-ShadowNative -FilePath $CodePath -ArgumentList (@($cli)+$Arguments) -Environment $environment -TimeoutSeconds 1200
}

function Get-ShadowBundledKilo {
    param([Parameter(Mandatory)][string]$CodePath,[Parameter(Mandatory)][string]$InstallRoot)
    $extensionsRoot=Join-Path $InstallRoot 'vscode-extensions'
    $result=Invoke-ShadowCodeCli -CodePath $CodePath -Arguments @('--user-data-dir',(Join-Path $InstallRoot 'vscode-data'),'--extensions-dir',$extensionsRoot,'--telemetry-level','off','--list-extensions','--show-versions')
    $versions=@($result.StdOut -split '\r?\n'|Where-Object {$_ -match '^kilocode\.kilo-code@[^@\s]+$'}|ForEach-Object {$_.Substring($_.IndexOf('@')+1)})
    if($versions.Count -ne 1){throw 'VS Code did not report a unique installed Kilo extension with a version in the managed profile.'}
    if(-not(Test-Path -LiteralPath $extensionsRoot -PathType Container)){throw 'Managed VS Code extension directory missing.'}
    $candidates=[Collections.Generic.List[string]]::new()
    foreach($directory in Get-ChildItem -LiteralPath $extensionsRoot -Directory -Force -ErrorAction Stop|Where-Object {$_.Name -like 'kilocode.kilo-code-*'}){
        if($directory.Attributes -band [IO.FileAttributes]::ReparsePoint){throw "Link in the managed Kilo extension directory: $($directory.FullName)."}
        $manifest=Join-Path $directory.FullName 'package.json'
        if(-not(Test-Path -LiteralPath $manifest -PathType Leaf)){throw "Kilo extension package manifest missing: $manifest"}
        try{$package=Get-Content -LiteralPath $manifest -Raw -ErrorAction Stop|ConvertFrom-Json -AsHashtable -ErrorAction Stop}
        catch{throw "Kilo extension package manifest unreadable: $manifest"}
        if($package -isnot [Collections.IDictionary] -or -not $package.Contains('publisher') -or
           -not $package.Contains('name') -or -not $package.Contains('version')){
            throw "Kilo extension package manifest incomplete: $manifest"
        }
        if($package['publisher'] -ieq 'kilocode' -and $package['name'] -ieq 'kilo-code' -and $package['version'] -ceq $versions[0]){
            $candidates.Add($directory.FullName)
        }
    }
    if($candidates.Count -ne 1){throw "Kilo extension version $($versions[0]) is not unique in the managed extension directory ($($candidates.Count) matches)."}
    $extensionPath=$candidates[0]
    $binary=Join-Path $extensionPath 'bin/kilo.exe'
    if(-not(Test-Path -LiteralPath $binary -PathType Leaf)){throw 'The installed Kilo extension does not contain the expected current CLI runtime. Check the pre-release channel.'}
    return $binary
}


