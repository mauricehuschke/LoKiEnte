#requires -Version 7.4
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$InstallRoot,
    [ValidateSet('Single','Dual')][string]$ModelMode='Dual',
    [switch]$IncludeFastModel,
    [switch]$AllowPartialGpuOffload,
    [switch]$AllowUnfitAttempt,
    [string]$BundleVersion,
    [string]$PayloadSha256,
    [ValidateRange(1024,65535)][int]$RouterPort=1235,
    [ValidateSet('Auto','Qwen27B','GptOss20B')][string]$PreferredModel='Auto',
    [string]$ModelKey,
    [string]$ApiTokenEnvironmentVariable='LOKIENTE_LM_API_KEY',
    [ValidateRange(8192,65536)][int]$ContextLength=32768,
    [ValidateRange(1024,65535)][int]$Port=1234,
    [string[]]$ProjectPath=@(),
    [switch]$SkipModelDownload,
    [switch]$UpdateManaged,
    [switch]$NoShortcut
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$PSNativeCommandUseErrorActionPreference=$false
. (Join-Path $PSScriptRoot 'Common.ps1')
. (Join-Path $PSScriptRoot 'DependencyVersions.ps1')
. (Join-Path $PSScriptRoot 'Runtime.ps1')
. (Join-Path $PSScriptRoot 'ModelPool.ps1')
. (Join-Path $PSScriptRoot 'ModelSelection.ps1')
. (Join-Path $PSScriptRoot 'Ripgrep.ps1')
. (Join-Path $PSScriptRoot 'Router.ps1')
. (Join-Path $PSScriptRoot 'AgentTemplates.ps1')
. (Join-Path $PSScriptRoot 'Workspace.ps1')

function New-ShadowWelcomeTestProject {
    param([string]$InstallRoot)
    & (Join-Path $PSScriptRoot 'New-WelcomeTestProject.ps1') -InstallRoot $InstallRoot
}

function Get-ShadowStartCommands {
    param([string]$PowerShellPath,[string]$InstallRoot,[string[]]$ProjectPaths=@())
    $launcher=Join-Path $InstallRoot 'app/Start-LocalAI.ps1'
    $shellLiteral="'"+$PowerShellPath.Replace("'","''")+"'"
    $launcherLiteral="'"+$launcher.Replace("'","''")+"'"
    $rootLiteral="'"+$InstallRoot.Replace("'","''")+"'"
    if(-not $ProjectPaths.Count){
        return "& $shellLiteral -NoLogo -NoProfile -ExecutionPolicy Bypass -File $launcherLiteral -InstallRoot $rootLiteral"
    }
    $paths=$ProjectPaths
    foreach($project in $paths){
        $projectLiteral="'"+$project.Replace("'","''")+"'"
        "& $shellLiteral -NoLogo -NoProfile -ExecutionPolicy Bypass -File $launcherLiteral -InstallRoot $rootLiteral -ProjectPath $projectLiteral"
    }
}

function Get-ShadowKiloExtensionVersion {
    param([AllowEmptyString()][string]$Output)
    $lines=@($Output -split '\r?\n'|Where-Object {$_ -match '(?i)^kilocode\.kilo-code(?:@|[ \t]*$)'})
    if($lines.Count -gt 1){throw 'Multiple Kilo extension versions reported in the managed profile; no automatic change.'}
    if(-not $lines.Count){return $null}
    if($lines[0] -notmatch '(?i)^kilocode\.kilo-code@(\d+\.\d+\.\d+)[ \t]*$'){
        throw 'The installed Kilo extension does not report an unambiguously supported version number.'
    }
    return $Matches[1]
}

function Get-ShadowKiloExtensionInstallSpec {
    param([AllowNull()][string]$Version,[string]$AcceptedVersion)
    if(-not $Version -or [version]$Version -lt [version]$AcceptedVersion){return "kilocode.kilo-code@$AcceptedVersion"}
    return $null
}

function Install-ShadowLanceDb {
    param([string]$InstallRoot,[string]$NodePath,[string]$NpmEntry)
    $root=Join-Path $InstallRoot 'tooling/lancedb'
    $entry=Join-Path $root 'node_modules/@lancedb/lancedb/dist/index.js'
    $manifest=Join-Path $root 'node_modules/@lancedb/lancedb/package.json'
    $marker=Join-Path $root 'shadow-lancedb-owner.txt'
    if((Test-Path -LiteralPath $root) -and
       (-not(Test-Path -LiteralPath $marker -PathType Leaf) -or [IO.File]::ReadAllText($marker) -cne 'shadow-lancedb-0.26.2')){
        throw 'Unknown LanceDB directory remains unchanged. Inspect the custom directory.'
    }
    if(-not(Test-Path -LiteralPath $entry -PathType Leaf)){
        if(-not(Test-Path -LiteralPath $root)){
            [void][IO.Directory]::CreateDirectory($root)
            [IO.File]::WriteAllText($marker,'shadow-lancedb-0.26.2')
        }
        $null=Invoke-ShadowNative -FilePath $NodePath -ArgumentList @($NpmEntry,'install','--prefix',$root,'@lancedb/lancedb@0.26.2','--no-audit','--no-fund','--engine-strict') -TimeoutSeconds 1800
    }
    if(-not(Test-Path -LiteralPath $manifest -PathType Leaf)){throw 'LanceDB manifest missing.'}
    $package=Get-Content -LiteralPath $manifest -Raw|ConvertFrom-Json
    if($package.name -cne '@lancedb/lancedb' -or $package.version -cne '0.26.2'){throw 'LanceDB version does not match the Kilo integration.'}
    $null=Invoke-ShadowNative -FilePath $NodePath -ArgumentList @('-e','require(process.argv[1])',$entry) -Quiet -TimeoutSeconds 60
    return $entry
}

function Resolve-ShadowSetupLms {
    param([Parameter(Mandatory)][string]$StudioPath)
    try {
        $lms=Resolve-LocalLmsCommand
        if(-not $lms){throw 'LM Studio CLI is not available yet.'}
    } catch {
        $message=@"

======================================================================
  MANUAL ACTION REQUIRED: Set up LM Studio
======================================================================

1. Open LM Studio yourself:
   $StudioPath
2. Complete first-run dialogs and configure or repair
   the LM Studio CLI if necessary.
3. Open a new terminal and rerun provisioning with the
   same parameters (without -AuditOnly).

Cause:
  $($_.Exception.Message)

Provisioning is paused and will not resume automatically.
Already configured components are preserved.
"@
        $action=[InvalidOperationException]::new($message)
        $action.Data['ShadowManualAction']='LM_STUDIO_INITIALIZATION'
        throw $action
    }
    return $lms
}

function Assert-ShadowSetupModels {
    param([string]$LmsPath,[string]$InstallRoot,[string]$ModelMode,[string]$PreferredModel,[string]$ModelKey,[switch]$IncludeFastModel)
    $logs=Join-Path $InstallRoot 'runtime/model-precheck-logs'
    $hardware=Get-LocalNvidiaGpu -LogDirectory $logs
    $models=@(Get-LrDownloadedModels -LmsPath $LmsPath -LogDirectory $logs)
    if($ModelMode -eq 'Dual'){
        $definitions=@(Get-SmpModelDefinitions -Hardware $hardware -IncludeFastModel:$IncludeFastModel)
    }else{
        $profile=Select-LrProfile -PreferredModel $PreferredModel -Hardware $hardware -ModelKey $ModelKey
        $definitions=@(@{Alias='single';Name=$profile.Name;Definition=$profile})
    }
    $missing=[Collections.Generic.List[object]]::new()
    foreach($item in $definitions){
        if(-not (Find-LrModel -Models $models -Profile $item.Definition -ModelKey $ModelKey)){
            $missing.Add($item)
        }
    }
    if(-not $missing.Count){return}
    $lines=[Collections.Generic.List[string]]::new()
    $lines.Add('')
    $lines.Add('======================================================================')
    $lines.Add('  MANUAL ACTION REQUIRED: Download models')
    $lines.Add('======================================================================')
    $lines.Add('')
    $lines.Add('Download the following missing models yourself in LM Studio.')
    $lines.Add('Choose exactly the specified file and quantization for each model.')
    $lines.Add('')
    if($ModelKey){
        $lines.Add("  Selected model: $ModelKey")
        $lines.Add('  No unique local match found. Download in LM Studio and')
        $lines.Add('  check the exact path or modelKey with lms ls --json.')
        $lines.Add('')
    }else{
        $number=0
        foreach($item in $missing){
            $number++
            $lines.Add("  $number. [$($item.Alias)] $($item.Name)")
            $lines.Add("     File:   $($item.Definition.ExpectedPath)")
            $lines.Add('     Source:')
            $lines.Add("       $($item.Definition.DownloadUrl)")
            $lines.Add('')
        }
    }
    $lines.Add('Next steps:')
    $lines.Add('  1. Complete all downloads in LM Studio.')
    $lines.Add('  2. Run the same provisioning script with the same parameters')
    $lines.Add('     again (without -AuditOnly).')
    $lines.Add('')
    $lines.Add('The LM Studio model directory remains unchanged.')
    $lines.Add('Existing models and configured components are preserved.')
    $lines.Add('Provisioning will not resume automatically.')
    $lines.Add('Status: INCOMPLETE (manual action pending; exit code 1)')
    $lines.Add('')
    $action=[InvalidOperationException]::new(($lines -join [Environment]::NewLine))
    $action.Data['ShadowManualAction']='MODEL_DOWNLOAD'
    throw $action
}

function Get-ShadowKiloEntry {
    param([string]$PackageRoot,[string]$NodePath)
    $manifest=Join-Path $PackageRoot 'package.json'
    if (-not (Test-Path -LiteralPath $manifest)) { return $null }
    $package=Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json -AsHashtable
    if ($package -isnot [Collections.IDictionary] -or (Get-LrProperty $package 'name') -ne '@kilocode/cli') {
        Write-ShadowMessage "No valid Kilo package manifest: $manifest" 'WARN'
        return $null
    }
    $bin=Get-LrProperty $package 'bin'
    $relative=if ($bin -is [string]) { $bin } elseif ($bin -is [Collections.IDictionary]) { Get-LrProperty $bin 'kilo' } else { $null }
    if (-not $relative) { return $null }
    $entry=[IO.Path]::GetFullPath((Join-Path $PackageRoot $relative))
    if (-not $entry.StartsWith([IO.Path]::GetFullPath($PackageRoot)+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) {
        throw 'Unexpected CLI entry point outside installed package.'
    }
    if (-not (Test-Path -LiteralPath $entry -PathType Leaf)) { return $null }
    $version=ConvertFrom-ShadowKiloMetadata -Json ($package|ConvertTo-Json -Depth 30)
    return [ordered]@{kiloExecutable=$NodePath;kiloArgumentPrefix=@($entry);kiloVersion=$version}
}

function ConvertFrom-ShadowKiloMetadata {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Json)
    try { $info=ConvertFrom-Json -InputObject $Json -AsHashtable -NoEnumerate -ErrorAction Stop }
    catch { throw 'npm returned no valid JSON for the Kilo version. Check registry/proxy and npm output.' }
    if ($info -is [array] -and $info.Count -eq 1) { $info=$info[0] }
    $version=if ($info -is [string]) { $info } elseif ($info -is [Collections.IDictionary]) { Get-LrProperty $info 'version' } else { $null }
    if ($version -isnot [string] -or $version -cnotmatch '^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$') {
        throw 'npm did not return a unique Kilo version. Expected exactly one version string or an object with version.'
    }
    return $version
}

function Test-ShadowKiloEntry {
    param([System.Collections.IDictionary]$Entry)
    if (-not $Entry) { return $false }
    $help=Invoke-ShadowNative -FilePath $Entry.kiloExecutable -ArgumentList (@($Entry.kiloArgumentPrefix)+@('run','--help')) -Environment @{KILO_TELEMETRY_LEVEL='off'} -AllowFailure -Quiet -TimeoutSeconds 60
    $text=$help.StdOut+"`n"+$help.StdErr
    $missing=@('--format','--agent','--dir'|Where-Object {$text -notmatch ([regex]::Escape($_)+'(?=[\s<,=]|$)')})
    if($help.ExitCode -ne 0){
        Write-ShadowMessage "Kilo CLI help returned exit code $($help.ExitCode); output was not accepted as successful option verification." 'WARN'
        return $false
    }
    if($missing.Count){
        Write-ShadowMessage "Kilo CLI help does not confirm required options: $($missing -join ', ')." 'WARN'
        return $false
    }
    return $true
}

function Install-ShadowKilo {
    param([string]$NodePath,[string]$NpmEntry,[string]$Root,[string]$AcceptedVersion)
    $privateRoot=Join-Path $Root 'tooling/node_modules/@kilocode/cli'
    $entry=Get-ShadowKiloEntry -PackageRoot $privateRoot -NodePath $NodePath
    $chainPath=Join-Path $Root 'toolchain.json'
    if(Test-Path -LiteralPath $chainPath -PathType Leaf){
        $chain=Get-Content -LiteralPath $chainPath -Raw | ConvertFrom-Json -AsHashtable
        $activeVersion=[string]$chain['kiloVersion']
        if($activeVersion -match '^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$'){
            $activeRoot=Join-Path $Root "tooling/kilo-versions/$activeVersion/node_modules/@kilocode/cli"
            $active=Get-ShadowKiloEntry -PackageRoot $activeRoot -NodePath $NodePath
            if($active -and $active.kiloVersion -ceq $activeVersion){$entry=$active}
        }
    }
    $current=if($entry){$entry.kiloVersion -as [version]}else{$null}
    if ($entry -and (-not $AcceptedVersion -or ($current -and $current -ge [version]$AcceptedVersion)) -and (Test-ShadowKiloEntry $entry)) {
        Write-ShadowMessage "Using existing managed Kilo CLI $($entry.kiloVersion)."
        return $entry
    }
    if($current -and $AcceptedVersion -and $current -gt [version]$AcceptedVersion){
        throw "The newer installed Kilo CLI $current failed compatibility checks. It will not be downgraded."
    }
    if (-not $AcceptedVersion -and -not $entry) {
        $existing=Get-Command kilo -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($existing) {
            if ([IO.Path]::GetExtension($existing.Source) -eq '.exe') {
                $entry=[ordered]@{kiloExecutable=$existing.Source;kiloArgumentPrefix=@();kiloVersion='existing-native'}
            } else {
                $existingPackage=Join-Path (Split-Path $existing.Source -Parent) 'node_modules/@kilocode/cli'
                $entry=Get-ShadowKiloEntry -PackageRoot $existingPackage -NodePath $NodePath
            }
            if ($entry -and (Test-ShadowKiloEntry $entry)) {
                Write-ShadowMessage 'Using existing compatible Kilo CLI; its configuration remains unchanged.'
                return $entry
            }
        }
    }
    $version=$AcceptedVersion
    if(-not $version){
        if($entry){$version=$entry.kiloVersion}
        else{
            $metadata=Invoke-ShadowNative -FilePath $NodePath -ArgumentList @($NpmEntry,'view','@kilocode/cli@latest','version','--json') -Quiet -TimeoutSeconds 120
            $version=ConvertFrom-ShadowKiloMetadata -Json $metadata.StdOut
        }
    }
    $prefix=Join-Path $Root "tooling/kilo-versions/$version"
    $privateRoot=Join-Path $prefix 'node_modules/@kilocode/cli'
    $candidate=Get-ShadowKiloEntry -PackageRoot $privateRoot -NodePath $NodePath
    if($candidate -and $candidate.kiloVersion -ceq $version -and (Test-ShadowKiloEntry $candidate)){return $candidate}
    [IO.Directory]::CreateDirectory($prefix) | Out-Null
    Write-ShadowMessage "Installing Kilo CLI $version in the private tool directory ..."
    $null=Invoke-ShadowNative -FilePath $NodePath -ArgumentList @($NpmEntry,'install','--prefix',$prefix,"@kilocode/cli@$version",'--no-audit','--no-fund','--engine-strict') -TimeoutSeconds 1800
    $entry=Get-ShadowKiloEntry -PackageRoot $privateRoot -NodePath $NodePath
    if (-not $entry -or $entry.kiloVersion -cne $version) { throw 'Installed Kilo version does not match the requested version.' }
    if (-not (Test-ShadowKiloEntry $entry)) { throw 'Installed Kilo CLI could not start or its help does not confirm required agent/JSON options. Check the preceding warning.' }
    return $entry
}


$report=$null
try {
    if (-not $IsWindows -or [Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString() -ne 'X64') { throw 'This provisioning script is designed for Windows x64.' }
    if($ModelMode -eq 'Single' -and $IncludeFastModel){throw 'IncludeFastModel requires ModelMode Dual.'}
    if($ModelMode -ne 'Dual' -and $AllowPartialGpuOffload){throw 'AllowPartialGpuOffload is supported only in the model pool (ModelMode Dual).'}
    if($ModelMode -eq 'Dual' -and ($ModelKey -or $PreferredModel -eq 'GptOss20B')){throw 'ModelMode Dual uses the verified Qwen/GPT-OSS pool. For a custom single model, use ModelMode Single.'}
    if($ModelMode -eq 'Dual' -and $Port -eq $RouterPort){throw 'Backend and router ports must be different.'}
    if($ApiTokenEnvironmentVariable -and $ApiTokenEnvironmentVariable -notmatch '^[A-Za-z_][A-Za-z0-9_]*$'){throw 'Invalid API token environment variable name.'}
    foreach($project in $ProjectPath){if(-not(Test-Path -LiteralPath $project -PathType Container)){throw "Project directory not found: $project"}}
    $InstallRoot=[IO.Path]::GetFullPath($InstallRoot)
    [IO.Directory]::CreateDirectory($InstallRoot) | Out-Null
    $report=[ordered]@{schema=1;bundleVersion=$BundleVersion;payloadSha256=$PayloadSha256;startedUtc=[DateTime]::UtcNow.ToString('o');status='IN_PROGRESS';installRoot=$InstallRoot;steps=@();warnings=@();allowUnfitAttempt=[bool]$AllowUnfitAttempt}
    $versions=Read-ShadowDependencyVersions -InstallRoot $InstallRoot
    $report.acceptedDependencyVersions=$versions
    $inventory=Get-ShadowInventory
    $report.inventoryFile='inventory.json'
    $null=Write-ShadowManagedFile -Path (Join-Path $InstallRoot 'inventory.json') -Content ($inventory|ConvertTo-Json -Depth 15) -BackupRoot (Join-Path $InstallRoot 'backups/inventory')
    if (-not $inventory.GPU) { throw 'NVIDIA GPU not reachable through nvidia-smi. Graphics drivers will not be replaced automatically.' }
    $winget=Resolve-ShadowTool -Name winget
    if (-not $winget) { throw 'WinGet missing. Install/update Windows App Installer and rerun this script.' }
    $git=Install-ShadowPackage -Tool git -PackageId 'Git.Git' -WingetPath $winget -AcceptedVersion $versions.git
    $node=Install-ShadowPackage -Tool node -PackageId 'OpenJS.NodeJS.LTS' -WingetPath $winget -AcceptedVersion $versions.node
    $curl=Install-ShadowPackage -Tool curl -PackageId 'cURL.cURL' -WingetPath $winget -AcceptedVersion $versions.curl
    $curlVersion=(Invoke-ShadowNative -FilePath $curl -ArgumentList @('--version') -Quiet -TimeoutSeconds 30).StdOut
    if($curlVersion -notmatch '(?m)^curl \d+\.\d+\.\d+'){throw 'curl exists but cannot be verified as a working curl CLI.'}
    $code=Install-ShadowPackage -Tool code -PackageId 'Microsoft.VisualStudioCode' -WingetPath $winget -AcceptedVersion $versions.vsCode
    $studio=Install-ShadowPackage -Tool lmstudio -PackageId 'ElementLabs.LMStudio' -WingetPath $winget -AcceptedVersion $versions.lmStudio
    $npm=Resolve-ShadowNpm -NodePath $node
    $nodeVersion=(Invoke-ShadowNative -FilePath $node -ArgumentList @('--version') -Quiet).StdOut.Trim()
    if ($nodeVersion -notmatch '^v(\d+)\.' -or [int]$Matches[1] -lt 20) {
        throw "Existing Node $nodeVersion is too old for this baseline. It was not replaced. Provide a suitable Node LTS version and retry."
    }
    $kilo=Install-ShadowKilo -NodePath $node -NpmEntry $npm -Root $InstallRoot -AcceptedVersion $versions.kiloCli
    $report.toolVersions=[ordered]@{
        powerShell=$PSVersionTable.PSVersion.ToString()
        node=$nodeVersion
        kiloCli=$kilo.kiloVersion
        curl=($curlVersion -split '\r?\n')[0]
    }
    $ripgrep=Install-ShadowRipgrep -InstallRoot $InstallRoot
    if($ModelMode -eq 'Dual'){$null=Install-ShadowLanceDb -InstallRoot $InstallRoot -NodePath $node -NpmEntry $npm}
    $toolchain=[ordered]@{
        schema=2;modelMode=$ModelMode;allowUnfitAttempt=[bool]$AllowUnfitAttempt;kiloExecutable=$kilo.kiloExecutable;kiloArgumentPrefix=@($kilo.kiloArgumentPrefix)
        kiloVersion=$kilo.kiloVersion;powerShellExecutable=(Get-Process -Id $PID).Path
        nodeExecutable=$node;npmEntry=$npm;gitExecutable=$git;codeExecutable=$code;curlExecutable=$curl;ripgrepExecutable=$ripgrep
    }

    $profileRoot=Join-Path $InstallRoot 'vscode-data'
    $extensionsRoot=Join-Path $InstallRoot 'vscode-extensions'
    [IO.Directory]::CreateDirectory($extensionsRoot)|Out-Null
    $managedSettings=[ordered]@{
        'telemetry.telemetryLevel'='off';'extensions.autoUpdate'=$false
        'terminal.integrated.defaultProfile.windows'='LoKiEnte PowerShell'
        'kilo-code.new.autocomplete.enableAutoTrigger'=$false
        'kilo-code.new.autocomplete.enableSmartInlineTaskKeybinding'=$false
        'kilo-code.new.autocomplete.enableChatAutocomplete'=$false
    }
    # Own profile only. Existing personal VS Code / Codex / Copilot profiles are never edited.
    $settingsFile=Join-Path $profileRoot 'User/settings.json'
    $settings=[ordered]@{}
    if (Test-Path -LiteralPath $settingsFile) {
        $settings=Get-Content -LiteralPath $settingsFile -Raw | ConvertFrom-Json -AsHashtable -NoEnumerate
        if ($settings -isnot [Collections.IDictionary]) { throw 'The managed VS Code profile settings.json must contain a JSON object.' }
    }
    foreach($key in $managedSettings.Keys){$settings[$key]=$managedSettings[$key]}
    $profiles='terminal.integrated.profiles.windows'
    if(-not $settings.Contains($profiles) -or $settings[$profiles] -isnot [Collections.IDictionary]){
        $settings[$profiles]=[ordered]@{}
    }
    # Remove only the unchanged legacy managed terminal profile; preserve custom entries.
    if($settings[$profiles].Contains('Shadow PowerShell')){
        $legacyProfile=$settings[$profiles]['Shadow PowerShell']
        if($legacyProfile -is [Collections.IDictionary] -and $legacyProfile.Count -eq 2 -and
           $legacyProfile.Contains('path') -and $legacyProfile.Contains('args') -and
           $legacyProfile.path -ieq $toolchain.powerShellExecutable -and
           @($legacyProfile.args).Count -eq 1 -and @($legacyProfile.args)[0] -ceq '-NoLogo'){
            $settings[$profiles].Remove('Shadow PowerShell')
        }
    }
    $settings[$profiles]['LoKiEnte PowerShell']=[ordered]@{path=$toolchain.powerShellExecutable;args=@('-NoLogo')}
    $null=Write-ShadowManagedFile -Path $settingsFile -Content ($settings|ConvertTo-Json -Depth 100) -BackupRoot (Join-Path $InstallRoot 'backups/vscode-settings')
    $codeArgs=@('--user-data-dir',$profileRoot,'--extensions-dir',$extensionsRoot,'--telemetry-level','off')
    $extensionList=Invoke-ShadowCodeCli -CodePath $code -Arguments ($codeArgs+@('--list-extensions','--show-versions'))
    $extensionVersion=Get-ShadowKiloExtensionVersion -Output $extensionList.StdOut
    if($extensionVersion){$report.kiloVsCodeExtensionVersion=$extensionVersion}
    $extensionSpec=Get-ShadowKiloExtensionInstallSpec -Version $extensionVersion -AcceptedVersion $versions.kiloVsCode
    if($extensionSpec) {
        $null=Invoke-ShadowCodeCli -CodePath $code -Arguments ($codeArgs+@('--install-extension',$extensionSpec,'--pre-release','--force'))
    }
    $extensionList=Invoke-ShadowCodeCli -CodePath $code -Arguments ($codeArgs+@('--list-extensions','--show-versions'))
    $extensionVersion=Get-ShadowKiloExtensionVersion -Output $extensionList.StdOut
    if(-not $extensionVersion){throw 'Kilo extension not found in the managed VS Code profile.'}
    if($extensionSpec -and $extensionVersion -cne $versions.kiloVsCode){throw 'VS Code does not report the approved Kilo version after installation.'}
    $report.kiloVsCodeExtensionVersion=$extensionVersion
    $bundledKilo=Get-ShadowBundledKilo -CodePath $code -InstallRoot $InstallRoot
    $toolchain.bundledKiloExecutable=$bundledKilo
    $report.steps+=@('Git/Node/curl/VSCode/LMStudio available','Kilo CLI available','Kilo VS Code extension available','Ripgrep verified')

    $lms=Resolve-ShadowSetupLms -StudioPath $studio
    $poolPath=Join-Path $InstallRoot 'runtime/model-pool.json'
    $previousPool=$null
    if(Test-Path -LiteralPath $poolPath){
        $previousPool=Get-Content -LiteralPath $poolPath -Raw|ConvertFrom-Json
    }
    $selectedDefinitions=@()
    if($ModelMode -eq 'Dual' -or ($ModelMode -eq 'Single' -and -not $ModelKey)){
        $selectionLogs=Join-Path $InstallRoot 'runtime/model-precheck-logs'
        $hardware=Get-LocalNvidiaGpu -LogDirectory $selectionLogs
        $downloaded=@(Get-LrDownloadedModels -LmsPath $lms -LogDirectory $selectionLogs)
        $selectionFile=Join-Path $InstallRoot 'model-selection.json'
        if(Test-Path -LiteralPath $selectionFile -PathType Leaf){
            $savedSelection=Get-Content -LiteralPath $selectionFile -Raw|ConvertFrom-Json
            if((Get-LrProperty $savedSelection 'schema') -ne 1 -or $null -eq $savedSelection.PSObject.Properties['roles'] -or $savedSelection.roles -isnot [array]){
                throw 'Saved model selection is invalid. Existing files are preserved.'
            }
            $previousProfiles=@($savedSelection.roles)
        }else{$previousProfiles=if($previousPool){@(Get-LrProperty $previousPool 'Profiles' @())}else{@()}}
        $preferredId=switch($PreferredModel){'Qwen27B'{'qwen38-27b'} 'GptOss20B'{'gpt-oss-20b'} default{''}}
        $selectedDefinitions=@(Select-ShadowModels -Hardware $hardware -Downloaded $downloaded -PreviousProfiles $previousProfiles -IncludeFastModel:$IncludeFastModel -Single:($ModelMode -eq 'Single') -AllowPartialGpuOffload:$AllowPartialGpuOffload -PreferredId $preferredId)
        $selectedState=[ordered]@{schema=1;roles=@($selectedDefinitions|ForEach-Object {
            [ordered]@{Alias=$_.Alias;Id=$_.Definition.Id;Name=$_.Name;ExpectedPath=$_.Definition.ExpectedPath}
        })}
        $null=Write-ShadowManagedFile -Path $selectionFile -Content ($selectedState|ConvertTo-Json -Depth 10) -BackupRoot (Join-Path $InstallRoot 'backups/model-selection')
        $downloadDefinitions=@($selectedDefinitions)
        if($ModelMode -eq 'Dual'){$downloadDefinitions+=@(@{Alias='embedding';Definition=(Get-ShadowEmbeddingDefinition)})}
        Install-ShadowSelectedModels -Definitions $downloadDefinitions -LmsPath $lms -InstallRoot $InstallRoot -SkipModelDownload:$SkipModelDownload
    }else{
        Assert-ShadowSetupModels -LmsPath $lms -InstallRoot $InstallRoot -ModelMode $ModelMode -PreferredModel $PreferredModel -ModelKey $ModelKey -IncludeFastModel:$IncludeFastModel
    }
    if($previousPool){
        Stop-ShadowModelRouter -InstallRoot $InstallRoot -Pool $previousPool
    }
    if($ModelMode -eq 'Dual'){
        $pool=Configure-LocalModelPool -InstallRoot $InstallRoot -ContextLength $ContextLength -Port $Port -RouterPort $RouterPort -IncludeFastModel:$IncludeFastModel -AllowPartialGpuOffload:$AllowPartialGpuOffload -AllowUnfitAttempt:$AllowUnfitAttempt -SelectedDefinitions $selectedDefinitions -DownloadModel:$false -LmsPath $lms -ApiTokenEnvironmentVariable $ApiTokenEnvironmentVariable
        $router=Start-ShadowModelRouter -InstallRoot $InstallRoot -Pool $pool -NodePath $node -PowerShellPath $toolchain.powerShellExecutable
        $embedding=Initialize-ShadowEmbeddingModel -InstallRoot $InstallRoot -Pool $pool -Definition (Get-ShadowEmbeddingDefinition)
        $configuration=New-ShadowAgentConfiguration -InstallRoot $InstallRoot -ModelCatalog (Get-ShadowPoolCatalog $pool) -MainModel $pool.PrimaryAlias -ApiBaseUrl $router.ApiBaseUrl -ApiTokenEnvironmentVariable $pool.ApiTokenEnvironmentVariable -EmbeddingModelId $embedding.InstanceId -EmbeddingApiBaseUrl $pool.BackendApiBaseUrl
        $report.runtime=$pool;$report.router=$router
        $report.embedding=$embedding
        $report.warnings+=@('Local indexing is configured; permission and completion must be checked in Kilo for each project.')
        foreach($profile in $pool.Profiles){
            if($profile.VerificationState -ceq 'Deferred'){$report.warnings+=@("Model $($profile.Alias) is downloaded but unverified: $($profile.VerificationMessage)")}
            elseif((Get-LrProperty $profile.Estimate 'ReserveOverride' $false)){$report.warnings+=@("Model $($profile.Alias) was tested without LoKiEnte memory reserve.")}
        }
        if($embedding.Status -ceq 'Deferred'){$report.warnings+=@("CPU embedding model is not ready yet: $($embedding.Message)")}
        elseif(Get-LrProperty $embedding 'ReserveOverride' $false){$report.warnings+=@('CPU embedding model was tested without LoKiEnte memory reserve.')}
        $report.smokeTests=@($pool.Profiles|ForEach-Object {@{model=$_.Alias;checks=$_.SmokeTests}})
    }else{
        $report.warnings+=@('Local semantic indexing is not configured in Single mode.')
        if((Test-Path -LiteralPath $poolPath) -and -not $ModelKey){
            $alias=if($PreferredModel -eq 'GptOss20B'){'review'}else{[string](Get-LrProperty $previousPool 'PrimaryAlias' 'coder')}
            $null=Switch-ShadowLocalModel -InstallRoot $InstallRoot -Alias $alias
        }
        $singleProfile=if($selectedDefinitions.Count){$selectedDefinitions[0].Definition}else{$null}
        $runtime=Configure-LocalRuntime -StateRoot (Join-Path $InstallRoot 'runtime') -PreferredModel $PreferredModel -ModelKey $ModelKey -SelectedProfile $singleProfile -ContextLength $ContextLength -Port $Port -DownloadModel:$false -LmsPath $lms -ApiTokenEnvironmentVariable $ApiTokenEnvironmentVariable -AllowUnfitAttempt:$AllowUnfitAttempt
        if($runtime.Status -cnotin @('Ready','Deferred')){throw "Unknown model status: $($runtime.Status)"}
        $singleName=if($runtime.Status -ceq 'Deferred'){'LoKiEnte local [NOT YET VERIFIED]'}else{'LoKiEnte local - verified workflow'}
        if($runtime.Status -ceq 'Deferred'){$report.warnings+=@("Single model is downloaded but unverified: $($runtime.VerificationMessage)")}
        elseif(Get-LrProperty $runtime.Estimate 'ReserveOverride' $false){$report.warnings+=@('Single model was tested without LoKiEnte memory reserve.')}
        $configuration=New-ShadowAgentConfiguration -InstallRoot $InstallRoot -ModelId $runtime.ModelId -ModelDisplayName $singleName -ApiBaseUrl $runtime.ApiBaseUrl -ContextLength $runtime.ContextLength -ApiTokenEnvironmentVariable $runtime.ApiTokenEnvironmentVariable
        $report.runtime=$runtime;$report.smokeTests=$runtime.SmokeTests
    }
    $report.effectiveConfiguration=Assert-ShadowKiloEffectiveConfig -KiloExecutable $kilo.kiloExecutable -KiloArgumentPrefix @($kilo.kiloArgumentPrefix) -InstallRoot $InstallRoot -Config $configuration.Config -WorkingDirectory $InstallRoot
    $report.effectiveGuiBackendConfiguration=Assert-ShadowKiloEffectiveConfig -KiloExecutable $bundledKilo -InstallRoot $InstallRoot -Config $configuration.Config -WorkingDirectory $InstallRoot
    $report.workflowCliTools=Assert-ShadowKiloWorkflowTools -KiloExecutable $kilo.kiloExecutable -KiloArgumentPrefix @($kilo.kiloArgumentPrefix) -InstallRoot $InstallRoot -Config $configuration.Config -WorkingDirectory $InstallRoot
    $report.workflowGuiTools=Assert-ShadowKiloWorkflowTools -KiloExecutable $bundledKilo -InstallRoot $InstallRoot -Config $configuration.Config -WorkingDirectory $InstallRoot
    $searchConfig=$configuration.Config|ConvertTo-Json -Depth 40 -Compress
    Test-ShadowKiloSearch -InstallRoot $InstallRoot -KiloExecutable $kilo.kiloExecutable -KiloArgumentPrefix @($kilo.kiloArgumentPrefix) -ConfigJson $searchConfig
    Test-ShadowKiloSearch -InstallRoot $InstallRoot -KiloExecutable $bundledKilo -ConfigJson $searchConfig
    $report.steps+=@('File search verified in Kilo CLI and VS Code extension')
    if(($ModelMode -eq 'Dual' -and $pool.VerificationStatus -cne 'Verified') -or
       ($ModelMode -eq 'Single' -and $runtime.Status -ceq 'Deferred')){
        $report.steps+=@('Local endpoint configured; at least one model test remains pending')
    }else{$report.steps+=@('Model and local endpoint verified')}
    $report.steps+=@('Agents/roles/workflows generated and effective CLI configuration verified')

    $welcome=Join-Path $InstallRoot 'welcome'
    [IO.Directory]::CreateDirectory($welcome)|Out-Null
    $welcomeText=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'templates/START_HERE.md')).Replace('(../welcome-example/README.md)','(workflow-test/README.md)')
    $null=Write-ShadowManagedFile -Path (Join-Path $welcome 'START_HERE.md') -Content $welcomeText -BackupRoot (Join-Path $InstallRoot 'backups/welcome')
    $null=Write-ShadowManagedFile -Path (Join-Path $welcome 'START_HERE.de.md') -Content ([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'templates/START_HERE.de.md')).Replace('(../welcome-example/README.de.md)','(workflow-test/README.de.md)')) -BackupRoot (Join-Path $InstallRoot 'backups/welcome')
    $welcomeProject=New-ShadowWelcomeTestProject -InstallRoot $InstallRoot
    $ProjectPath=@($ProjectPath)+@($welcomeProject.project)
    $workspaceUpdate=Update-ShadowWorkspaces -Root $InstallRoot -ProjectPath $ProjectPath -PwshPath $toolchain.powerShellExecutable
    $report.workspaces=@($workspaceUpdate.Entries)
    $report.warnings+=@($workspaceUpdate.Warnings)
    $report.steps+=@('Registered and new workspaces updated to the package version')
    if (-not $NoShortcut) {
        $desktop=[Environment]::GetFolderPath('Desktop')
        if ($desktop) {
            $shortcutPath=Join-Path $desktop 'LoKiEnte.lnk'
            if (Test-Path -LiteralPath $shortcutPath) {
                [IO.Directory]::CreateDirectory((Join-Path $InstallRoot 'backups/shortcuts'))|Out-Null
                Copy-Item -LiteralPath $shortcutPath -Destination (Join-Path $InstallRoot ('backups/shortcuts/'+[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffffffZ')+'.lnk'))
            }
            $shell=New-Object -ComObject WScript.Shell
            $shortcut=$shell.CreateShortcut($shortcutPath)
            $shortcut.TargetPath=$toolchain.powerShellExecutable
            $launcher=Join-Path $InstallRoot 'app/Start-LocalAI.ps1'
            if ($launcher.Contains('"')) { throw 'Invalid quotation mark in installation path.' }
            $shortcut.Arguments='-NoLogo -NoProfile -ExecutionPolicy Bypass -File "'+$launcher+'" -InstallRoot "'+$InstallRoot+'" -PauseOnError'
            $shortcut.WorkingDirectory=$InstallRoot
            $shortcut.Description='Local model, dedicated VS Code environment and reviewed agent workflows'
            $iconPath=Join-Path $InstallRoot 'app/assets/lokiente.ico'
            if(-not(Test-Path -LiteralPath $iconPath -PathType Leaf)){throw 'LoKiEnte desktop icon missing from installation package.'}
            $shortcut.IconLocation=$iconPath+',0'
            $shortcut.Save()
            # Rename only shortcuts managed by this same installation.
            foreach($legacyName in @('Shadow Local AI.lnk','LoKi.lnk')){
                $legacyPath=Join-Path $desktop $legacyName
                if(Test-Path -LiteralPath $legacyPath -PathType Leaf){
                    $legacy=$shell.CreateShortcut($legacyPath)
                    if($legacy.TargetPath -ieq $shortcut.TargetPath -and $legacy.Arguments -ceq $shortcut.Arguments){
                        $backupDirectory=Join-Path $InstallRoot 'backups/shortcuts'
                        [void][IO.Directory]::CreateDirectory($backupDirectory)
                        Copy-Item -LiteralPath $legacyPath -Destination (Join-Path $backupDirectory ([DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffffffZ')+'-'+$legacyName))
                        Remove-Item -LiteralPath $legacyPath
                    }
                }
            }
        }
    }
    $null=Write-ShadowManagedFile -Path (Join-Path $InstallRoot 'toolchain.json') -Content ($toolchain|ConvertTo-Json -Depth 10) -BackupRoot (Join-Path $InstallRoot 'backups/toolchain')
    $desired=[ordered]@{
        ModelMode=$ModelMode;IncludeFastModel=[bool]$IncludeFastModel;AllowPartialGpuOffload=[bool]$AllowPartialGpuOffload
        AllowUnfitAttempt=[bool]$AllowUnfitAttempt;RouterPort=$RouterPort;Port=$Port;ContextLength=$ContextLength
        PreferredModel=$PreferredModel;ModelKey=$ModelKey;ApiTokenEnvironmentVariable=$ApiTokenEnvironmentVariable
    }
    $null=Write-ShadowManagedFile -Path (Join-Path $InstallRoot 'provisioning-options.json') -Content ($desired|ConvertTo-Json) -BackupRoot (Join-Path $InstallRoot 'backups/provisioning-options')
    $report.status=if($report.warnings.Count -or ($ModelMode -eq 'Dual' -and ($pool.VerificationStatus -cne 'Verified' -or $embedding.Status -ceq 'Deferred' -or (Get-LrProperty $embedding 'ReserveOverride' $false) -or
        @($pool.Profiles|Where-Object {(Get-LrProperty $_.Estimate 'ReserveOverride' $false)}).Count)) -or
        ($ModelMode -eq 'Single' -and ($runtime.Status -ceq 'Deferred' -or (Get-LrProperty $runtime.Estimate 'ReserveOverride' $false)))){
        'PROVISIONED_WITH_WARNINGS'
    }else{'PROVISIONED'}
    $report.finishedUtc=[DateTime]::UtcNow.ToString('o')
    $null=Write-ShadowManagedFile -Path (Join-Path $InstallRoot 'provisioning-report.json') -Content ($report|ConvertTo-Json -Depth 25) -BackupRoot (Join-Path $InstallRoot 'backups/reports')
    $statusLevel=if($report.status -ceq 'PROVISIONED_WITH_WARNINGS'){'WARN'}else{'OK'}
    Write-ShadowMessage "Setup: $($report.status). Report: $(Join-Path $InstallRoot 'provisioning-report.json')" $statusLevel
    $projectPaths=@($report.workspaces|ForEach-Object {$_.project})
    foreach($command in (Get-ShadowStartCommands -PowerShellPath $toolchain.powerShellExecutable -InstallRoot $InstallRoot -ProjectPaths $projectPaths)){
        Write-ShadowMessage "Start: $command"
    }
    exit 0
}
catch {
    $manualAction=$_.Exception.Data['ShadowManualAction']
    $isManualAction=$manualAction -in @('LM_STUDIO_INITIALIZATION','MODEL_DOWNLOAD')
    if ($null -ne $report) {
        $report.status='INCOMPLETE';$report.error=$_.Exception.Message;$report.finishedUtc=[DateTime]::UtcNow.ToString('o')
        if($isManualAction){$report.manualAction=$manualAction}
        $report.failureLocation=@{
            script=[IO.Path]::GetFileName($_.InvocationInfo.ScriptName)
            line=$_.InvocationInfo.ScriptLineNumber
            errorId=$_.FullyQualifiedErrorId
        }
        try { $null=Write-ShadowManagedFile -Path (Join-Path $InstallRoot 'provisioning-report.json') -Content ($report|ConvertTo-Json -Depth 25) -BackupRoot (Join-Path $InstallRoot 'backups/reports') } catch { Write-Warning 'Could not save report.' }
    }
    if($isManualAction){Write-Host $_.Exception.Message}
    else{Write-Error -Message ("Setup incomplete: "+$_.Exception.Message) -ErrorAction Continue}
    exit 1
}
