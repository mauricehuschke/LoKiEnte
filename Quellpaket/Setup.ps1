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
    [string]$ApiTokenEnvironmentVariable='SHADOW_LM_API_KEY',
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
    if($lines.Count -gt 1){throw 'Mehrere Kilo-Erweiterungsversionen im verwalteten Profil gemeldet; keine automatische Aenderung.'}
    if(-not $lines.Count){return $null}
    if($lines[0] -notmatch '(?i)^kilocode\.kilo-code@(\d+\.\d+\.\d+)[ \t]*$'){
        throw 'Die installierte Kilo-Erweiterung meldet keine eindeutig unterstuetzbare Versionsnummer.'
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
        throw 'Unbekanntes LanceDB-Verzeichnis bleibt unveraendert. Das eigene Verzeichnis pruefen.'
    }
    if(-not(Test-Path -LiteralPath $entry -PathType Leaf)){
        if(-not(Test-Path -LiteralPath $root)){
            [void][IO.Directory]::CreateDirectory($root)
            [IO.File]::WriteAllText($marker,'shadow-lancedb-0.26.2')
        }
        $null=Invoke-ShadowNative -FilePath $NodePath -ArgumentList @($NpmEntry,'install','--prefix',$root,'@lancedb/lancedb@0.26.2','--no-audit','--no-fund','--engine-strict') -TimeoutSeconds 1800
    }
    if(-not(Test-Path -LiteralPath $manifest -PathType Leaf)){throw 'LanceDB-Manifest fehlt.'}
    $package=Get-Content -LiteralPath $manifest -Raw|ConvertFrom-Json
    if($package.name -cne '@lancedb/lancedb' -or $package.version -cne '0.26.2'){throw 'LanceDB-Version stimmt nicht mit der Kilo-Integration ueberein.'}
    $null=Invoke-ShadowNative -FilePath $NodePath -ArgumentList @('-e','require(process.argv[1])',$entry) -Quiet -TimeoutSeconds 60
    return $entry
}

function Resolve-ShadowSetupLms {
    param([Parameter(Mandatory)][string]$StudioPath)
    try {
        $lms=Resolve-LocalLmsCommand
        if(-not $lms){throw 'LM-Studio-CLI ist noch nicht verfuegbar.'}
    } catch {
        $message=@"

======================================================================
  MANUELLE AKTION ERFORDERLICH: LM Studio einrichten
======================================================================

1. LM Studio selbst oeffnen:
   $StudioPath
2. Erststartdialoge abschliessen und die LM-Studio-CLI
   gegebenenfalls einrichten oder reparieren.
3. Ein neues Terminal oeffnen und das Provisionierungsskript
   mit denselben Parametern erneut starten (ohne -AuditOnly).

Ursache:
  $($_.Exception.Message)

Die Provisionierung ist angehalten und wird nicht automatisch fortgesetzt.
Bereits eingerichtete Komponenten bleiben erhalten.
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
    $lines.Add('  MANUELLE AKTION ERFORDERLICH: Modelle herunterladen')
    $lines.Add('======================================================================')
    $lines.Add('')
    $lines.Add('Die folgenden fehlenden Modelle selbst in LM Studio herunterladen.')
    $lines.Add('Bitte jeweils genau die angegebene Datei und Quantisierung waehlen.')
    $lines.Add('')
    if($ModelKey){
        $lines.Add("  Ausgewaehltes Modell: $ModelKey")
        $lines.Add('  Lokal nicht eindeutig gefunden. In LM Studio herunterladen und')
        $lines.Add('  den exakten path oder modelKey mit lms ls --json pruefen.')
        $lines.Add('')
    }else{
        $number=0
        foreach($item in $missing){
            $number++
            $lines.Add("  $number. [$($item.Alias)] $($item.Name)")
            $lines.Add("     Datei:  $($item.Definition.ExpectedPath)")
            $lines.Add('     Quelle:')
            $lines.Add("       $($item.Definition.DownloadUrl)")
            $lines.Add('')
        }
    }
    $lines.Add('Naechste Schritte:')
    $lines.Add('  1. Downloads in LM Studio vollstaendig abschliessen.')
    $lines.Add('  2. Dasselbe Provisionierungsskript mit denselben Parametern')
    $lines.Add('     erneut starten (ohne -AuditOnly).')
    $lines.Add('')
    $lines.Add('Das LM-Studio-Modellverzeichnis bleibt unveraendert.')
    $lines.Add('Vorhandene Modelle und eingerichtete Komponenten bleiben erhalten.')
    $lines.Add('Die Provisionierung wird nicht automatisch fortgesetzt.')
    $lines.Add('Status: INCOMPLETE (manueller Schritt ausstehend; Exitcode 1)')
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
        Write-ShadowMessage "Kein gueltiges Kilo-Paketmanifest: $manifest" 'WARN'
        return $null
    }
    $bin=Get-LrProperty $package 'bin'
    $relative=if ($bin -is [string]) { $bin } elseif ($bin -is [Collections.IDictionary]) { Get-LrProperty $bin 'kilo' } else { $null }
    if (-not $relative) { return $null }
    $entry=[IO.Path]::GetFullPath((Join-Path $PackageRoot $relative))
    if (-not $entry.StartsWith([IO.Path]::GetFullPath($PackageRoot)+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) {
        throw 'Unerwarteter CLI-Einstieg ausserhalb des installierten Pakets.'
    }
    if (-not (Test-Path -LiteralPath $entry -PathType Leaf)) { return $null }
    $version=ConvertFrom-ShadowKiloMetadata -Json ($package|ConvertTo-Json -Depth 30)
    return [ordered]@{kiloExecutable=$NodePath;kiloArgumentPrefix=@($entry);kiloVersion=$version}
}

function ConvertFrom-ShadowKiloMetadata {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Json)
    try { $info=ConvertFrom-Json -InputObject $Json -AsHashtable -NoEnumerate -ErrorAction Stop }
    catch { throw 'npm lieferte kein gueltiges JSON fuer die Kilo-Version. Registry/Proxy und npm-Ausgabe pruefen.' }
    if ($info -is [array] -and $info.Count -eq 1) { $info=$info[0] }
    $version=if ($info -is [string]) { $info } elseif ($info -is [Collections.IDictionary]) { Get-LrProperty $info 'version' } else { $null }
    if ($version -isnot [string] -or $version -cnotmatch '^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$') {
        throw 'npm lieferte keine eindeutige Kilo-Version. Erwartet wird genau eine Versionszeichenfolge oder ein Objekt mit version.'
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
        Write-ShadowMessage "Kilo-CLI-Hilfe meldete Exitcode $($help.ExitCode); Ausgabe wurde nicht als erfolgreiche Optionspruefung gewertet." 'WARN'
        return $false
    }
    if($missing.Count){
        Write-ShadowMessage "Kilo-CLI-Hilfe bestaetigt erforderliche Optionen nicht: $($missing -join ', ')." 'WARN'
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
        Write-ShadowMessage "Verwende vorhandene verwaltete Kilo CLI $($entry.kiloVersion)."
        return $entry
    }
    if($current -and $AcceptedVersion -and $current -gt [version]$AcceptedVersion){
        throw "Die neuere installierte Kilo CLI $current hat die Kompatibilitaetspruefung nicht bestanden. Sie wird nicht herabgestuft."
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
                Write-ShadowMessage 'Verwende vorhandene kompatible Kilo CLI; deren Konfiguration wird nicht veraendert.'
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
    Write-ShadowMessage "Installiere Kilo CLI $version in das eigene Werkzeugverzeichnis ..."
    $null=Invoke-ShadowNative -FilePath $NodePath -ArgumentList @($NpmEntry,'install','--prefix',$prefix,"@kilocode/cli@$version",'--no-audit','--no-fund','--engine-strict') -TimeoutSeconds 1800
    $entry=Get-ShadowKiloEntry -PackageRoot $privateRoot -NodePath $NodePath
    if (-not $entry -or $entry.kiloVersion -cne $version) { throw 'Die installierte Kilo-Version stimmt nicht mit der angeforderten Version ueberein.' }
    if (-not (Test-ShadowKiloEntry $entry)) { throw 'Installierte Kilo CLI konnte nicht gestartet werden oder ihre Hilfe bestaetigt die benoetigten Agenten-/JSON-Optionen nicht. Vorherigen Warnhinweis pruefen.' }
    return $entry
}


$report=$null
try {
    if (-not $IsWindows -or [Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString() -ne 'X64') { throw 'Dieses Provisionierungsskript ist fuer Windows x64 vorgesehen.' }
    if($ModelMode -eq 'Single' -and $IncludeFastModel){throw 'IncludeFastModel benoetigt ModelMode Dual.'}
    if($ModelMode -ne 'Dual' -and $AllowPartialGpuOffload){throw 'AllowPartialGpuOffload wird nur im Modellpool (ModelMode Dual) unterstuetzt.'}
    if($ModelMode -eq 'Dual' -and ($ModelKey -or $PreferredModel -eq 'GptOss20B')){throw 'ModelMode Dual nutzt den geprueften Qwen/GPT-OSS-Pool. Fuer ein eigenes Einzelmodell ModelMode Single verwenden.'}
    if($ModelMode -eq 'Dual' -and $Port -eq $RouterPort){throw 'Backend- und Routerport muessen verschieden sein.'}
    if($ApiTokenEnvironmentVariable -and $ApiTokenEnvironmentVariable -notmatch '^[A-Za-z_][A-Za-z0-9_]*$'){throw 'Ungueltiger Name der API-Token-Umgebungsvariable.'}
    foreach($project in $ProjectPath){if(-not(Test-Path -LiteralPath $project -PathType Container)){throw "Projektverzeichnis fehlt: $project"}}
    $InstallRoot=[IO.Path]::GetFullPath($InstallRoot)
    [IO.Directory]::CreateDirectory($InstallRoot) | Out-Null
    $report=[ordered]@{schema=1;bundleVersion=$BundleVersion;payloadSha256=$PayloadSha256;startedUtc=[DateTime]::UtcNow.ToString('o');status='IN_PROGRESS';installRoot=$InstallRoot;steps=@();warnings=@();allowUnfitAttempt=[bool]$AllowUnfitAttempt}
    $versions=Read-ShadowDependencyVersions -InstallRoot $InstallRoot
    $report.acceptedDependencyVersions=$versions
    $inventory=Get-ShadowInventory
    $report.inventoryFile='inventory.json'
    $null=Write-ShadowManagedFile -Path (Join-Path $InstallRoot 'inventory.json') -Content ($inventory|ConvertTo-Json -Depth 15) -BackupRoot (Join-Path $InstallRoot 'backups/inventory')
    if (-not $inventory.GPU) { throw 'NVIDIA-GPU nicht ueber nvidia-smi erreichbar. Es werden keine Grafiktreiber automatisch ersetzt.' }
    $winget=Resolve-ShadowTool -Name winget
    if (-not $winget) { throw 'WinGet fehlt. Windows App Installer installieren/aktualisieren und dieses Skript erneut ausfuehren.' }
    $git=Install-ShadowPackage -Tool git -PackageId 'Git.Git' -WingetPath $winget -AcceptedVersion $versions.git
    $node=Install-ShadowPackage -Tool node -PackageId 'OpenJS.NodeJS.LTS' -WingetPath $winget -AcceptedVersion $versions.node
    $curl=Install-ShadowPackage -Tool curl -PackageId 'cURL.cURL' -WingetPath $winget -AcceptedVersion $versions.curl
    $curlVersion=(Invoke-ShadowNative -FilePath $curl -ArgumentList @('--version') -Quiet -TimeoutSeconds 30).StdOut
    if($curlVersion -notmatch '(?m)^curl \d+\.\d+\.\d+'){throw 'curl ist vorhanden, aber nicht als funktionierende curl-CLI verifizierbar.'}
    $code=Install-ShadowPackage -Tool code -PackageId 'Microsoft.VisualStudioCode' -WingetPath $winget -AcceptedVersion $versions.vsCode
    $studio=Install-ShadowPackage -Tool lmstudio -PackageId 'ElementLabs.LMStudio' -WingetPath $winget -AcceptedVersion $versions.lmStudio
    $npm=Resolve-ShadowNpm -NodePath $node
    $nodeVersion=(Invoke-ShadowNative -FilePath $node -ArgumentList @('--version') -Quiet).StdOut.Trim()
    if ($nodeVersion -notmatch '^v(\d+)\.' -or [int]$Matches[1] -lt 20) {
        throw "Vorhandenes Node $nodeVersion ist fuer diese Basis zu alt. Es wurde nicht ersetzt. Eine passende Node-LTS-Version bereitstellen und erneut starten."
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
        'terminal.integrated.defaultProfile.windows'='Shadow PowerShell'
        'kilo-code.new.autocomplete.enableAutoTrigger'=$false
        'kilo-code.new.autocomplete.enableSmartInlineTaskKeybinding'=$false
        'kilo-code.new.autocomplete.enableChatAutocomplete'=$false
    }
    # Own profile only. Existing personal VS Code / Codex / Copilot profiles are never edited.
    $settingsFile=Join-Path $profileRoot 'User/settings.json'
    $settings=[ordered]@{}
    if (Test-Path -LiteralPath $settingsFile) {
        $settings=Get-Content -LiteralPath $settingsFile -Raw | ConvertFrom-Json -AsHashtable -NoEnumerate
        if ($settings -isnot [Collections.IDictionary]) { throw 'Das settings.json im verwalteten VS-Code-Profil muss ein JSON-Objekt enthalten.' }
    }
    foreach($key in $managedSettings.Keys){$settings[$key]=$managedSettings[$key]}
    $profiles='terminal.integrated.profiles.windows'
    if(-not $settings.Contains($profiles) -or $settings[$profiles] -isnot [Collections.IDictionary]){
        $settings[$profiles]=[ordered]@{}
    }
    $settings[$profiles]['Shadow PowerShell']=[ordered]@{path=$toolchain.powerShellExecutable;args=@('-NoLogo')}
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
    if(-not $extensionVersion){throw 'Kilo-Erweiterung wurde im verwalteten VS-Code-Profil nicht gefunden.'}
    if($extensionSpec -and $extensionVersion -cne $versions.kiloVsCode){throw 'VS Code meldet nach der Installation nicht die freigegebene Kilo-Version.'}
    $report.kiloVsCodeExtensionVersion=$extensionVersion
    $bundledKilo=Get-ShadowBundledKilo -CodePath $code -InstallRoot $InstallRoot
    $toolchain.bundledKiloExecutable=$bundledKilo
    $report.steps+=@('Git/Node/curl/VSCode/LMStudio vorhanden','Kilo CLI vorhanden','Kilo VSCode Erweiterung vorhanden','Ripgrep geprueft')

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
                throw 'Gespeicherte Modellauswahl ist ungueltig. Bestehende Dateien bleiben erhalten.'
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
        $report.warnings+=@('Lokale Indexierung ist konfiguriert; die Freigabe und der Abschluss muessen in Kilo fuer jedes Projekt geprueft werden.')
        foreach($profile in $pool.Profiles){
            if($profile.VerificationState -ceq 'Deferred'){$report.warnings+=@("Modell $($profile.Alias) ist heruntergeladen, aber noch ungeprueft: $($profile.VerificationMessage)")}
            elseif((Get-LrProperty $profile.Estimate 'ReserveOverride' $false)){$report.warnings+=@("Modell $($profile.Alias) wurde ohne LoKi-Speicherreserve getestet.")}
        }
        if($embedding.Status -ceq 'Deferred'){$report.warnings+=@("CPU-Embeddingmodell ist noch nicht betriebsbereit: $($embedding.Message)")}
        elseif(Get-LrProperty $embedding 'ReserveOverride' $false){$report.warnings+=@('CPU-Embeddingmodell wurde ohne LoKi-Speicherreserve getestet.')}
        $report.smokeTests=@($pool.Profiles|ForEach-Object {@{model=$_.Alias;checks=$_.SmokeTests}})
    }else{
        $report.warnings+=@('Die lokale semantische Indexierung wird im Single-Modus nicht eingerichtet.')
        if((Test-Path -LiteralPath $poolPath) -and -not $ModelKey){
            $alias=if($PreferredModel -eq 'GptOss20B'){'review'}else{[string](Get-LrProperty $previousPool 'PrimaryAlias' 'coder')}
            $null=Switch-ShadowLocalModel -InstallRoot $InstallRoot -Alias $alias
        }
        $singleProfile=if($selectedDefinitions.Count){$selectedDefinitions[0].Definition}else{$null}
        $runtime=Configure-LocalRuntime -StateRoot (Join-Path $InstallRoot 'runtime') -PreferredModel $PreferredModel -ModelKey $ModelKey -SelectedProfile $singleProfile -ContextLength $ContextLength -Port $Port -DownloadModel:$false -LmsPath $lms -ApiTokenEnvironmentVariable $ApiTokenEnvironmentVariable -AllowUnfitAttempt:$AllowUnfitAttempt
        if($runtime.Status -cnotin @('Ready','Deferred')){throw "Unbekannter Modellstatus: $($runtime.Status)"}
        $singleName=if($runtime.Status -ceq 'Deferred'){'Shadow local [NOCH NICHT GEPRUEFT]'}else{'Shadow local - verified workflow'}
        if($runtime.Status -ceq 'Deferred'){$report.warnings+=@("Einzelmodell ist heruntergeladen, aber noch ungeprueft: $($runtime.VerificationMessage)")}
        elseif(Get-LrProperty $runtime.Estimate 'ReserveOverride' $false){$report.warnings+=@('Einzelmodell wurde ohne LoKi-Speicherreserve getestet.')}
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
    $report.steps+=@('Dateisuche in Kilo CLI und VS-Code-Erweiterung geprueft')
    if(($ModelMode -eq 'Dual' -and $pool.VerificationStatus -cne 'Verified') -or
       ($ModelMode -eq 'Single' -and $runtime.Status -ceq 'Deferred')){
        $report.steps+=@('Lokaler Endpunkt konfiguriert; mindestens ein Modelltest steht aus')
    }else{$report.steps+=@('Modell und lokaler Endpunkt verifiziert')}
    $report.steps+=@('Agenten/Rollen/Workflows erzeugt und wirksame CLI-Konfiguration geprueft')

    $welcome=Join-Path $InstallRoot 'welcome'
    [IO.Directory]::CreateDirectory($welcome)|Out-Null
    $welcomeText=@'
# Shadow Local AI

Dieses Fenster verwendet ein eigenes VS-Code-Profil und lokale Modelle.

1. Starte die Desktopverknuepfung Shadow Local AI. Waehle ein bekanntes Projekt per Nummer oder N fuer einen weiteren vorhandenen Projektordner (Pfad eingeben). 0 bricht vor dem Modellstart ab. Ein direkter Launcher-Aufruf mit -ProjectPath oeffnet das Projekt ohne Menue.
2. Chat/Planung: Kilo-Seitenleiste. Rollen und /feature, /bugfix, /refactor, /review, /architecture sind vordefiniert.
3. Codeaenderungen direkt in shadow-chat eingeben. Kriterien und checks.json werden automatisch vorbereitet und unabhaengig geprueft.
4. Zum Ausprobieren im Launcher welcome/workflow-test waehlen. Der fertige Testauftrag steht in [workflow-test/README.md](workflow-test/README.md). Das Beispiel nutzt nur kuenstliche Daten, Node-Bordmittel und ein eigenes lokales Git-Repository.
5. Nur ein bestandener Aufgabenlauf darf VERIFIED melden. Der Status bezieht sich auf genau den geprueften Arbeitsbaum und die konfigurierten Pruefungen.

Fuer semantische Suche im Dual-Modus im Kilo-Bereich Einstellungen > Indexing
oeffnen und fuer das jeweilige Projekt die Indexierung freigeben. Vorher
.gitignore und .kilocodeignore auf sensible Dateien pruefen. Der Index wird
lokal gespeichert und ist nicht automatisch verschluesselt. Den Status
Complete abwarten; eine Konfiguration allein beweist keinen fertigen Index.

Kilo zeigt Rollen/Modelle/Phasen ueber loki_status und LOKI-STATUS.md; loki_details erklaert Befunde. Der Runner fuehrt die Tests aus. Der Chat schreibt nicht direkt.
Ein bearbeitetes Testprojekt bleibt beim Update erhalten. Ein frisches Beispiel erzeugt app/New-WelcomeTestProject.ps1 -InstallRoot <Installationsordner> -NewExample in PowerShell 7. Das Beispiel ist keine Betriebssystem-Sandbox.
Anmeldungen bei GitHub/Lovable und projektspezifische Geheimnisse werden nicht durch dieses Paket eingerichtet.
'@
    $null=Write-ShadowManagedFile -Path (Join-Path $welcome 'START_HERE.md') -Content $welcomeText -BackupRoot (Join-Path $InstallRoot 'backups/welcome')
    $welcomeProject=New-ShadowWelcomeTestProject -InstallRoot $InstallRoot
    $ProjectPath=@($ProjectPath)+@($welcomeProject.project)
    $workspaceUpdate=Update-ShadowWorkspaces -Root $InstallRoot -ProjectPath $ProjectPath -PwshPath $toolchain.powerShellExecutable
    $report.workspaces=@($workspaceUpdate.Entries)
    $report.warnings+=@($workspaceUpdate.Warnings)
    $report.steps+=@('Registrierte und neue Arbeitsbereiche auf den Paketstand gebracht')
    if (-not $NoShortcut) {
        $desktop=[Environment]::GetFolderPath('Desktop')
        if ($desktop) {
            $shortcutPath=Join-Path $desktop 'Shadow Local AI.lnk'
            if (Test-Path -LiteralPath $shortcutPath) {
                [IO.Directory]::CreateDirectory((Join-Path $InstallRoot 'backups/shortcuts'))|Out-Null
                Copy-Item -LiteralPath $shortcutPath -Destination (Join-Path $InstallRoot ('backups/shortcuts/'+[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffffffZ')+'.lnk'))
            }
            $shell=New-Object -ComObject WScript.Shell
            $shortcut=$shell.CreateShortcut($shortcutPath)
            $shortcut.TargetPath=$toolchain.powerShellExecutable
            $launcher=Join-Path $InstallRoot 'app/Start-LocalAI.ps1'
            if ($launcher.Contains('"')) { throw 'Unzulaessiges Anfuehrungszeichen im Installationspfad.' }
            $shortcut.Arguments='-NoLogo -NoProfile -ExecutionPolicy Bypass -File "'+$launcher+'" -InstallRoot "'+$InstallRoot+'" -PauseOnError'
            $shortcut.WorkingDirectory=$InstallRoot
            $shortcut.Description='Lokales Modell, eigene VS-Code-Umgebung und gepruefte Agentenablaeufe'
            $shortcut.Save()
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
    Write-ShadowMessage "Einrichtung: $($report.status). Bericht: $(Join-Path $InstallRoot 'provisioning-report.json')" $statusLevel
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
        try { $null=Write-ShadowManagedFile -Path (Join-Path $InstallRoot 'provisioning-report.json') -Content ($report|ConvertTo-Json -Depth 25) -BackupRoot (Join-Path $InstallRoot 'backups/reports') } catch { Write-Warning 'Bericht konnte nicht gespeichert werden.' }
    }
    if($isManualAction){Write-Host $_.Exception.Message}
    else{Write-Error -Message ("Einrichtung nicht vollstaendig: "+$_.Exception.Message) -ErrorAction Continue}
    exit 1
}
