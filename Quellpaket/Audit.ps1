#requires -Version 5.1
# Invoked in memory by the verified bootstrap; never invokes installation code.
[CmdletBinding()]
param(
    [string]$InstallRoot,
    [string]$BundleVersion,
    [string]$PayloadHash,
    [Collections.IDictionary]$PackageFiles,
    [string]$ModelMode,
    [bool]$IncludeFastModel,
    [bool]$AllowPartialGpuOffload,
    [string]$PreferredModel,
    [string]$ModelKey,
    [int]$ContextLength,
    [int]$Port,
    [int]$RouterPort,
    [string]$ApiTokenEnvironmentVariable,
    [string[]]$ProjectPath,
    [bool]$SkipModelDownload
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$checks=New-Object 'Collections.Generic.List[object]'
$tools=[ordered]@{}
$states=@{}
$hardware=$null
$definitions=@()
$downloaded=@()
$loaded=@()
$backendPort=$Port
$listeners=@()
$listenersKnown=$false
$token=$null

# Reuse the actual provisioning profile thresholds and exact model definitions.
$tokens=$null;$parseErrors=$null
$runtimeAst=[Management.Automation.Language.Parser]::ParseInput($PackageFiles['Runtime.ps1'],[ref]$tokens,[ref]$parseErrors)
if($parseErrors.Count){throw 'Runtime-Modul im Paket enthaelt Syntaxfehler.'}
foreach($name in @('Get-LrProperty','ConvertFrom-LrModelList','Get-LrMissingLoadOptions','Select-LrProfile','Add-LrVariantMetadata','Find-LrModel')){
    $definition=$runtimeAst.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $name},$false)
    if($null -eq $definition){throw "Audit-Helfer fehlt im Paket: $name"}
    . ([scriptblock]::Create($definition.Extent.Text))
    $commonAst=[Management.Automation.Language.Parser]::ParseInput($PackageFiles['Common.ps1'],[ref]$tokens,[ref]$parseErrors)
    if($parseErrors.Count){throw 'Gemeinsames Modul im Paket enthaelt Syntaxfehler.'}
    $definition=$commonAst.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Resolve-ShadowCodeCli'},$false)
    if($null -eq $definition){throw 'VS-Code-CLI-Pfadpruefung fehlt im Paket.'}
    . ([scriptblock]::Create($definition.Extent.Text))
}
$poolAst=[Management.Automation.Language.Parser]::ParseInput($PackageFiles['ModelPool.ps1'],[ref]$tokens,[ref]$parseErrors)
if($parseErrors.Count){throw 'Modellpool-Modul im Paket enthaelt Syntaxfehler.'}
$definition=$poolAst.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Get-SmpModelDefinitions'},$false)
if($null -eq $definition){throw 'Modellkatalog fehlt im Paket.'}
. ([scriptblock]::Create($definition.Extent.Text))
$selectionAst=[Management.Automation.Language.Parser]::ParseInput($PackageFiles['ModelSelection.ps1'],[ref]$tokens,[ref]$parseErrors)
if($parseErrors.Count){throw 'Modellauswahl im Paket enthaelt Syntaxfehler.'}
foreach($name in @('Get-ShadowModelCatalog','Get-ShadowModelRanking','Get-ShadowRecommendedModel')){
    $definition=$selectionAst.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $name},$false)
    if($null -eq $definition){throw "Audit-Modellkatalog fehlt: $name"}
    . ([scriptblock]::Create($definition.Extent.Text))
}
$ripgrepAst=[Management.Automation.Language.Parser]::ParseInput($PackageFiles['Ripgrep.ps1'],[ref]$tokens,[ref]$parseErrors)
if($parseErrors.Count){throw 'Ripgrep-Modul im Paket enthaelt Syntaxfehler.'}
$definition=$ripgrepAst.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Get-ShadowRipgrepInfo'},$false)
if($null -eq $definition){throw 'Ripgrep-Auditdaten fehlen.'}
. ([scriptblock]::Create($definition.Extent.Text))

function Add-AuditCheck {
    param([string]$Name,[ValidateSet('PASS','WARN','FAIL','MISSING','SKIP')][string]$Status,[string]$Message,$Data=$null)
    $checks.Add([pscustomobject]@{name=$Name;status=$Status;message=$Message;data=$Data})
}

function Invoke-AuditNative {
    param([string]$FilePath,[string[]]$Arguments,[int]$TimeoutSeconds=20,[switch]$AllowFailure)
    if([IO.Path]::GetExtension($FilePath) -in @('.cmd','.bat','.ps1')){throw 'Audit erwartet einen nativen Programmeinstieg, keinen Shell-Shim.'}
    $start=New-Object Diagnostics.ProcessStartInfo
    $start.FileName=$FilePath
    $start.Arguments=(@(foreach($argument in $Arguments){ConvertTo-WindowsArgument $argument}) -join ' ')
    $start.UseShellExecute=$false;$start.CreateNoWindow=$true
    $start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
    $start.EnvironmentVariables['NO_COLOR']='1'
    $process=New-Object Diagnostics.Process
    $process.StartInfo=$start
    try{
        [void]$process.Start()
        $stdout=$process.StandardOutput.ReadToEndAsync()
        $stderr=$process.StandardError.ReadToEndAsync()
        if(-not $process.WaitForExit($TimeoutSeconds*1000)){
            $process.Kill()
            throw "Zeitlimit ($TimeoutSeconds s) bei $([IO.Path]::GetFileName($FilePath)). Nur der Audit-CLI-Prozess wurde beendet; ein gestarteter Hintergrunddienst kann weiterlaufen."
        }
        $text=$stdout.GetAwaiter().GetResult()
        $errorText=$stderr.GetAwaiter().GetResult()
        if($AllowFailure){return [pscustomobject]@{ExitCode=$process.ExitCode;Stdout=$text;Stderr=$errorText}}
        if($process.ExitCode -ne 0){throw "$([IO.Path]::GetFileName($FilePath)) meldet Exitcode $($process.ExitCode). Programm separat pruefen."}
        return $text.Trim()
    }finally{$process.Dispose()}
}

function Invoke-AuditJson {
    param([Uri]$Uri,[string]$BearerToken)
    Add-Type -AssemblyName System.Net.Http
    $handler=New-Object Net.Http.HttpClientHandler
    $handler.AllowAutoRedirect=$false
    $handler.UseProxy=(-not $Uri.IsLoopback)
    $client=New-Object Net.Http.HttpClient($handler)
    $client.Timeout=[TimeSpan]::FromSeconds(20)
    $response=$null
    try{
        if($BearerToken){
            if(-not $Uri.IsLoopback){throw 'Audit sendet API-Token nur an Loopback.'}
            if($BearerToken -match '[\r\n]'){throw 'API-Token enthaelt ungueltige Headerzeichen; sein Wert wird nicht ausgegeben.'}
            try{$client.DefaultRequestHeaders.Authorization=New-Object Net.Http.Headers.AuthenticationHeaderValue('Bearer',$BearerToken)}
            catch{throw 'API-Token kann nicht als Authorization-Header verwendet werden; sein Wert wird nicht ausgegeben.'}
        }
        try{$response=$client.GetAsync($Uri).GetAwaiter().GetResult()}
        catch{throw "Verbindung zu $($Uri.Host):$($Uri.Port) fehlgeschlagen oder Zeitlimit erreicht."}
        if(-not $response.IsSuccessStatusCode){throw "HTTP $([int]$response.StatusCode) von $($Uri.Host):$($Uri.Port). Keine Weiterleitung und kein Fallback ausgefuehrt."}
        $text=$response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        try{return ConvertFrom-Json -InputObject $text -ErrorAction Stop}
        catch{throw "Antwort von $($Uri.Host) ist kein gueltiges JSON."}
    }finally{if($response){$response.Dispose()};$client.Dispose();$handler.Dispose()}
}

function ConvertFrom-AuditJson {
    param([string]$Json,[string]$Source,[switch]$ModelList)
    try{
        if($ModelList){ConvertFrom-LrModelList -Json $Json;return}
        return ConvertFrom-Json -InputObject $Json -ErrorAction Stop
    }
    catch{throw "Ungueltiges JSON oder unerwartete Struktur aus $Source. Rohdaten werden nicht in den Auditbericht uebernommen."}
}

Add-AuditCheck 'bundle' PASS 'Eingebettetes ZIP vor der Auswertung per SHA256 verifiziert.' @{version=$BundleVersion;sha256=$PayloadHash}
if($AllowPartialGpuOffload){Add-AuditCheck 'model.offload' WARN 'Teilweise CPU-Auslagerung ist ausgewaehlt; Speicherfit und Leistung werden erst im Setup geprueft.'}
try{Assert-BootstrapOptions;Add-AuditCheck 'parameters' PASS 'Parameterkombination und Projektpfade sind gueltig.'}
catch{Add-AuditCheck 'parameters' FAIL $_.Exception.Message}
try{
    if($env:OS -ne 'Windows_NT' -or -not [Environment]::Is64BitOperatingSystem -or
       -not [Environment]::Is64BitProcess -or $env:PROCESSOR_ARCHITECTURE -eq 'ARM64' -or $env:PROCESSOR_ARCHITEW6432 -eq 'ARM64'){
        throw 'Windows x64 und ein 64-Bit-PowerShell-Prozess sind erforderlich.'
    }
    $system=Get-CimInstance Win32_OperatingSystem
    $cpu=Get-CimInstance Win32_Processor|Select-Object -First 1
    $hardware=[pscustomobject]@{
        Gpu=$null;TotalRamBytes=([long]$system.TotalVisibleMemorySize*1KB)
        FreeRamBytes=([long]$system.FreePhysicalMemory*1KB)
    }
    Add-AuditCheck 'windows' PASS 'Windows-x64-Umgebung erkannt.' @{
        name=$system.Caption;build=$system.BuildNumber;cpu=$cpu.Name
        ramGiB=[math]::Round($hardware.TotalRamBytes/1GB,1);freeRamGiB=[math]::Round($hardware.FreeRamBytes/1GB,1)
        auditPowerShell=$PSVersionTable.PSVersion.ToString()
    }
}catch{Add-AuditCheck 'windows' FAIL $_.Exception.Message}
try{
    Assert-BootstrapInstallRoot -AllowSharedDirectory
    Add-AuditCheck 'installRoot' PASS 'Installationspfad und Paketkennung sind nutzbar; kein Schreibtest ausgefuehrt.' @{path=$InstallRoot;exists=(Test-Path -LiteralPath $InstallRoot)}
}catch{Add-AuditCheck 'installRoot' FAIL $_.Exception.Message}
try{
    $legacyRoot=Join-Path $env:LOCALAPPDATA 'ShadowLocalAI'
    if([IO.Path]::GetFullPath($InstallRoot).TrimEnd('\','/') -ine $legacyRoot.TrimEnd('\','/') -and (Test-Path -LiteralPath $legacyRoot)){
        Add-AuditCheck 'installRoot.legacy' WARN 'Bisheriges Verzeichnis vorhanden. Audit prueft nur installRoot und kopiert nichts. Altes Verzeichnis mit -InstallRoot gezielt pruefen; der normale Lauf bietet Auswahl/Kopie an.' @{path=$legacyRoot}
    }
}catch{Add-AuditCheck 'installRoot.legacy' FAIL 'Bisheriges Installationsverzeichnis konnte nicht geprueft werden.'}
try{
    $lockPaths=@((Join-Path $InstallRoot 'provisioning.lock'),(Join-Path $InstallRoot 'setup-active.lock'))
    $foundLock=$false
    foreach($lockPath in $lockPaths){
        if(-not(Test-Path -LiteralPath $lockPath -PathType Leaf)){continue}
        $lock=[IO.File]::Open($lockPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
        $lock.Dispose();$foundLock=$true
    }
    if($foundLock){
        Add-AuditCheck 'setup.lock' PASS 'Kein exklusiver Provisionierungslauf an der vorhandenen Sperrdatei erkannt.'
    }else{Add-AuditCheck 'setup.lock' SKIP 'Noch keine Provisionierungssperre vorhanden.'}
}catch{Add-AuditCheck 'setup.lock' FAIL 'Provisionierungssperre belegt oder nicht lesbar. Laufende Einrichtung abschliessen bzw. Zugriffsrechte pruefen.'}
try{
    $disks=@(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType = 3'|ForEach-Object {
        @{drive=$_.DeviceID;totalGiB=[math]::Round($_.Size/1GB,1);freeGiB=[math]::Round($_.FreeSpace/1GB,1)}
    })
    Add-AuditCheck 'storage' WARN 'Freier Platz ist eine Bestandsaufnahme. Das konfigurierte LM-Studio-Modelllaufwerk und Platz fuer Downloads muessen separat passen; fuer eine Neuinstallation etwa 60 GB Reserve einplanen.' $disks
}catch{Add-AuditCheck 'storage' WARN $_.Exception.Message}

$candidates=[ordered]@{
    winget=@((Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'))
    pwsh=@((Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'),(Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\pwsh.exe'))
    git=@((Join-Path $env:ProgramFiles 'Git\cmd\git.exe'))
    node=@((Join-Path $env:ProgramFiles 'nodejs\node.exe'))
    curl=@((Join-Path $env:SystemRoot 'System32\curl.exe'))
    code=@((Join-Path $env:LOCALAPPDATA 'Programs\Microsoft VS Code\Code.exe'),(Join-Path $env:ProgramFiles 'Microsoft VS Code\Code.exe'))
    lmstudio=@((Join-Path $env:LOCALAPPDATA 'Programs\LM Studio\LM Studio.exe'),(Join-Path $env:ProgramFiles 'LM Studio\LM Studio.exe'))
    'nvidia-smi'=@((Join-Path $env:SystemRoot 'System32\nvidia-smi.exe'))
}
foreach($name in $candidates.Keys){
    try{
        $commandName=if($name -eq 'code'){'code'}elseif($name -eq 'lmstudio'){'LM Studio.exe'}else{$name+'.exe'}
        $path=Find-BootstrapExecutable $commandName $candidates[$name]
        if($name -eq 'code' -and $path -and [IO.Path]::GetExtension($path) -eq '.cmd'){
            $exe=Join-Path (Split-Path (Split-Path $path -Parent) -Parent) 'Code.exe'
            $path=if(Test-Path -LiteralPath $exe -PathType Leaf){$exe}else{Find-BootstrapExecutable 'Code.exe' $candidates[$name]}
        }
        $tools[$name]=$path
        if(-not $path){
            $status=if($name -in @('winget','nvidia-smi')){'FAIL'}else{'MISSING'}
            Add-AuditCheck "tool.$name" $status $(if($status -eq 'FAIL'){'Voraussetzung fehlt; muss vor der Provisionierung bereitgestellt werden.'}else{'Fehlt; kann beim normalen Setup installiert werden.'})
            continue
        }
        $version=if($name -in @('code','lmstudio')){
            (Get-Item -LiteralPath $path).VersionInfo.ProductVersion
        }elseif($name -eq 'pwsh'){
            Invoke-AuditNative $path @('-NoLogo','-NoProfile','-NonInteractive','-Command','$PSVersionTable.PSVersion.ToString()')
        }elseif($name -eq 'nvidia-smi'){'siehe gpu-Pruefung'}else{Invoke-AuditNative $path @('--version')}
        if($name -eq 'pwsh' -and [version]$version -lt [version]'7.4'){throw 'Vorhandene PowerShell ist aelter als 7.4; sie wird nicht automatisch ersetzt.'}
        if($name -eq 'node' -and ($version -notmatch '^v(\d+)\.' -or [int]$Matches[1] -lt 20)){throw 'Vorhandenes Node ist nicht als Version >=20 nachweisbar.'}
        if($name -eq 'curl'){$version=($version -split '\r?\n')[0]}
        Add-AuditCheck "tool.$name" PASS 'Programm gefunden.' @{path=$path;version=$version}
    }catch{Add-AuditCheck "tool.$name" FAIL $_.Exception.Message}
}
try{
    $ripgrep=Get-ShadowRipgrepInfo -InstallRoot $InstallRoot
    Assert-BootstrapNoReparsePoint -Path $ripgrep.Path
    if(-not(Test-Path -LiteralPath $ripgrep.Path -PathType Leaf)){
        Add-AuditCheck 'tool.ripgrep' MISSING 'Ripgrep fehlt im isolierten Kilo-Cache; das normale Setup stellt es bereit.' @{path=$ripgrep.Path}
    }else{
        $hash=(Get-FileHash -LiteralPath $ripgrep.Path -Algorithm SHA256 -ErrorAction Stop).Hash
        if($hash -ine $ripgrep.ExecutableSha256){throw 'Vorhandenes ripgrep hat eine unbekannte Pruefsumme und bleibt unveraendert.'}
        $version=Invoke-AuditNative $ripgrep.Path @('--version')
        if($version -notmatch '(?m)^ripgrep 15\.1\.0(?:\s|$)'){throw 'Ripgrep meldet eine unerwartete Version.'}
        Add-AuditCheck 'tool.ripgrep' PASS 'Geprueftes ripgrep im isolierten Kilo-Cache gefunden; Kilo-Dateisuche wird im Setup getestet.' @{path=$ripgrep.Path;version=$ripgrep.Version}
    }
}catch{Add-AuditCheck 'tool.ripgrep' FAIL $_.Exception.Message}
try{
    if($tools['code']){
        $cli=Resolve-ShadowCodeCli -CodePath $tools['code']
        Add-AuditCheck 'vscode.cli' PASS 'Der vom installierten VS Code angegebene CLI-Einstieg ist vorhanden; keine Erweiterungen installiert.' @{path=$cli}
    }else{
        Add-AuditCheck 'vscode.cli' SKIP 'VS Code fehlt; CLI-Pfad kann noch nicht geprueft werden.'
    }
}catch{Add-AuditCheck 'vscode.cli' FAIL $_.Exception.Message}
try{
    $npm=$null
    if($tools['node']){$npm=Join-Path (Split-Path $tools['node'] -Parent) 'node_modules\npm\bin\npm-cli.js'}
    if(-not $npm -or -not(Test-Path -LiteralPath $npm -PathType Leaf)){
        $shim=Find-BootstrapExecutable 'npm.cmd'
        if($shim){$npm=Join-Path (Split-Path $shim -Parent) 'node_modules\npm\bin\npm-cli.js'}
    }
    if($tools['node'] -and $npm -and (Test-Path -LiteralPath $npm -PathType Leaf)){
        $tools['npm']=$npm
        Add-AuditCheck 'tool.npm' PASS 'npm ueber den nativen Node-Einstieg aufrufbar.' @{version=(Invoke-AuditNative $tools['node'] @($npm,'--version'))}
    }else{Add-AuditCheck 'tool.npm' $(if($tools['node']){'FAIL'}else{'MISSING'}) 'npm-cli.js fehlt oder Node ist nicht vorhanden.'}
}catch{Add-AuditCheck 'tool.npm' FAIL $_.Exception.Message}
try{
    $packageRoot=Join-Path $InstallRoot 'tooling\node_modules\@kilocode\cli'
    $manifestPath=Join-Path $packageRoot 'package.json'
    if(Test-Path -LiteralPath $manifestPath -PathType Leaf){
        $manifest=ConvertFrom-AuditJson -Json (Get-Content -LiteralPath $manifestPath -Raw) -Source 'Kilo-Manifest'
        if((Get-LrProperty $manifest 'name') -cne '@kilocode/cli' -or -not(Get-LrProperty $manifest 'version')){throw 'Installiertes Kilo-Manifest ist unvollstaendig.'}
        $bin=Get-LrProperty $manifest 'bin'
        $relative=if($bin -is [string]){$bin}else{Get-LrProperty $bin 'kilo'}
        if($relative -isnot [string] -or -not $relative){throw 'Installiertes Kilo-Manifest enthaelt keinen CLI-Einstieg.'}
        $entry=[IO.Path]::GetFullPath((Join-Path $packageRoot $relative))
        $prefix=[IO.Path]::GetFullPath($packageRoot)+[IO.Path]::DirectorySeparatorChar
        if(-not $entry.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase) -or -not(Test-Path -LiteralPath $entry -PathType Leaf)){
            throw 'Kilo-CLI-Einstieg fehlt oder liegt ausserhalb des verwalteten Pakets.'
        }
        Add-AuditCheck 'tool.kilo' PASS 'Verwaltetes Kilo-Manifest und Einstieg vorhanden; effektive Konfiguration nicht ausgefuehrt.' @{version=$manifest.version}
    }else{Add-AuditCheck 'tool.kilo' MISSING 'Keine private Kilo-Installation gefunden. Eine globale kompatible CLI kann das Setup gegebenenfalls wiederverwenden.'}
}catch{Add-AuditCheck 'tool.kilo' FAIL $_.Exception.Message}
try{
    if(-not $tools['nvidia-smi']){throw 'GPU-Speicher kann ohne nvidia-smi nicht verifiziert werden.'}
    $text=Invoke-AuditNative $tools['nvidia-smi'] @('--query-gpu=name,memory.total,memory.free,driver_version','--format=csv,noheader,nounits')
    $gpus=@(foreach($line in ($text -split '\r?\n')){
        if(-not $line.Trim()){continue}
        $parts=$line -split ',',4
        if($parts.Count -ne 4){throw 'Unerwartete nvidia-smi-Ausgabe.'}
        $total=[double]::Parse($parts[1].Trim(),[Globalization.CultureInfo]::InvariantCulture)*1MB
        $free=[double]::Parse($parts[2].Trim(),[Globalization.CultureInfo]::InvariantCulture)*1MB
        if($total -le 0 -or $free -lt 0 -or $free -gt $total){throw 'Ungueltige GPU-Speicherangaben.'}
        [pscustomobject]@{Name=$parts[0].Trim();TotalBytes=[long]$total;FreeBytes=[long]$free;Driver=$parts[3].Trim()}
    })
    if($gpus.Count -ne 1){throw "Erkannt: $($gpus.Count) NVIDIA-GPUs; das Setup setzt genau eine voraus."}
    if($null -eq $hardware){throw 'RAM-Bestandsaufnahme fehlt.'}
    $hardware.Gpu=$gpus[0]
    Add-AuditCheck 'gpu' PASS 'NVIDIA-GPU und freier Speicher ausgelesen.' $gpus[0]
    $noFitRoles=[Collections.Generic.List[string]]::new()
    if($ModelMode -eq 'Dual'){
        $catalog=@(Get-ShadowModelCatalog)
        $roles=@('coder-high','coder-fast','review')
        if($IncludeFastModel){$roles+=@('fast')}
        $definitions=@(foreach($role in $roles){
            $suggestion=Get-ShadowRecommendedModel -Role $role -Catalog $catalog -Hardware $hardware -AllowPartialGpuOffload:$AllowPartialGpuOffload
            if(-not $suggestion){$noFitRoles.Add($role)}else{$suggestion}
        })
    }elseif(-not $ModelKey -and $PreferredModel -eq 'Auto'){
        $catalog=@(Get-ShadowModelCatalog)
        $suggestion=Get-ShadowRecommendedModel -Role 'coder' -Catalog $catalog -Hardware $hardware
        if(-not $suggestion){$noFitRoles.Add('coder');$definitions=@()}else{$definitions=@($suggestion)}
    }else{$definitions=@(Select-LrProfile -PreferredModel $PreferredModel -Hardware $hardware -ModelKey $ModelKey)}
    if($noFitRoles.Count){
        Add-AuditCheck 'model.hardware' WARN 'Keine grobe Speicherempfehlung fuer mindestens eine Rolle. Im Setup bewusst auswaehlen; Downloads bleiben moeglich.' @{profiles=@($definitions|ForEach-Object {$_.Name});rolesWithoutFit=@($noFitRoles);requestedContext=$ContextLength}
    }else{
        Add-AuditCheck 'model.hardware' PASS 'Unverbindliche hardwarebasierte Vorschlaege; die Modellauswahl erfolgt im Setup. Kein Nachweis fuer den tatsaechlichen Modell-/Kontextfit.' @{profiles=@($definitions|ForEach-Object {$_.Name});requestedContext=$ContextLength}
    }
}catch{Add-AuditCheck 'model.hardware' FAIL $_.Exception.Message}

foreach($item in @(
    @{name='toolchain';path='toolchain.json';schema='schema';version=2},
    @{name='pool';path='runtime\model-pool.json';schema='SchemaVersion';version=2},
    @{name='runtime';path='runtime\runtime-state.json';schema='SchemaVersion';version=1},
    @{name='ownership';path='runtime\model-ownership.json';schema='SchemaVersion';version=1},
    @{name='selection';path='model-selection.json';schema='schema';version=1},
    @{name='provisioning';path='provisioning-report.json';schema='schema';version=1}
)){
    try{
        $path=Join-Path $InstallRoot $item.path
        if(-not(Test-Path -LiteralPath $path -PathType Leaf)){Add-AuditCheck "state.$($item.name)" MISSING 'Noch kein gespeicherter Zustand vorhanden.';continue}
        $state=ConvertFrom-AuditJson -Json (Get-Content -LiteralPath $path -Raw) -Source $item.name
        if((Get-LrProperty $state $item.schema) -ne $item.version){throw 'Unbekanntes Zustandsschema; keine automatische Reparatur im Audit.'}
        $required=switch($item.name){
            'toolchain'{@('nodeExecutable','kiloExecutable','powerShellExecutable','codeExecutable')}
            'pool'{@('OwnerId','BackendApiBaseUrl','RouterApiBaseUrl','Profiles','Status')}
            'runtime'{@('ModelId','ModelPath','ApiBaseUrl','Status')}
            'ownership'{@('OwnerId')}
            'selection'{@('roles')}
            'provisioning'{@('status')}
        }
        foreach($field in $required){if(-not(Get-LrProperty $state $field)){throw "Pflichtfeld fehlt im gespeicherten Zustand: $field"}}
        if($item.name -eq 'ownership' -and ($null -eq $state.PSObject.Properties['Entries'] -or $state.Entries -isnot [array])){
            throw 'Eigentumsnachweis enthaelt keine Eintragsliste.'
        }
        foreach($field in @('ApiBaseUrl','BackendApiBaseUrl','RouterApiBaseUrl')){
            $value=Get-LrProperty $state $field
            if($value){
                $uri=[Uri]$value
                if(-not $uri.IsAbsoluteUri -or -not $uri.IsLoopback -or $uri.Scheme -ne 'http' -or
                   $uri.UserInfo -or $uri.Query -or $uri.Fragment -or $uri.AbsolutePath.TrimEnd('/') -cne '/v1'){
                    throw 'Gespeicherter Modellendpunkt ist kein eindeutiger lokaler HTTP-/v1-Endpunkt.'
                }
            }
        }
        $states[$item.name]=$state
        $status=Get-LrProperty $state 'Status' (Get-LrProperty $state 'status')
        $valid=$null -eq $status -or $status -cin @('Ready','PROVISIONED')
        Add-AuditCheck "state.$($item.name)" $(if($valid){'PASS'}else{'WARN'}) 'Gespeicherter Zustand gelesen; ersetzt keine aktuelle Funktionspruefung.' @{status=$status}
    }catch{Add-AuditCheck "state.$($item.name)" FAIL $_.Exception.Message}
}
if(-not $ModelKey -and ($states.ContainsKey('selection') -or ($ModelMode -eq 'Dual' -and $states.ContainsKey('pool')))){
    $currentCatalog=@(Get-ShadowModelCatalog)
    $savedProfiles=if($states.ContainsKey('selection')){@(Get-LrProperty $states.selection 'roles' @())}else{@(Get-LrProperty $states.pool 'Profiles' @())}
    $savedDefinitions=[Collections.Generic.List[object]]::new()
    $unmatched=$false
    $seenAliases=@{}
    foreach($profile in $savedProfiles){
        $alias=[string](Get-LrProperty $profile 'Alias')
        if($ModelMode -eq 'Dual' -and $alias -eq 'coder'){$alias='coder-high'}
        if($ModelMode -eq 'Single' -and $alias -eq 'coder-high'){$alias='coder'}
        if($ModelMode -eq 'Single' -and $alias -ne 'coder'){continue}
        if($alias -eq 'fast' -and -not $IncludeFastModel){continue}
        if($alias -notin @('coder','coder-high','coder-fast','review','fast') -or $seenAliases.ContainsKey($alias)){$unmatched=$true;break}
        $seenAliases[$alias]=$true
        $expected=[string](Get-LrProperty $profile 'ExpectedPath')
        $match=@($currentCatalog|Where-Object {$_.ExpectedPath -ieq $expected})
        if($match.Count -ne 1){$unmatched=$true;break}
        $savedDefinitions.Add($match[0])
    }
    $minimum=if($ModelMode -eq 'Single'){1}elseif($IncludeFastModel){4}else{3}
    $rolesPresent=if($ModelMode -eq 'Single'){$seenAliases.ContainsKey('coder')}else{
        $seenAliases.ContainsKey('coder-high') -and $seenAliases.ContainsKey('coder-fast') -and
        $seenAliases.ContainsKey('review') -and (-not $IncludeFastModel -or $seenAliases.ContainsKey('fast'))
    }
    if(-not $unmatched -and $savedDefinitions.Count -eq $minimum -and $rolesPresent){
        $definitions=$savedDefinitions.ToArray()
        Add-AuditCheck 'model.selection' PASS 'Gespeicherte Modellauswahl wird auf vorhandene Dateien geprueft; neue Empfehlungen erscheinen beim Setup.'
    }else{
        Add-AuditCheck 'model.selection' WARN 'Gespeicherte Modellauswahl ist nicht vollstaendig im Katalog; Audit zeigt aktuelle Vorschlaege statt einer behaupteten bestaetigten Auswahl.'
    }
}
try{
    if($ApiTokenEnvironmentVariable){
        $token=[Environment]::GetEnvironmentVariable($ApiTokenEnvironmentVariable,'Process')
        if(-not $token){$token=[Environment]::GetEnvironmentVariable($ApiTokenEnvironmentVariable,'User')}
    }
    Add-AuditCheck 'authentication' PASS 'Nur Token-Verfuegbarkeit erfasst; kein Tokenwert im Bericht.' @{variable=$ApiTokenEnvironmentVariable;present=(-not [string]::IsNullOrWhiteSpace($token))}
    $lmHome=Join-Path $env:USERPROFILE '.lmstudio'
    $pointer=Join-Path $env:USERPROFILE '.lmstudio-home-pointer'
    if(Test-Path -LiteralPath $pointer -PathType Leaf){
        $lmHome=(Get-Content -LiteralPath $pointer -Raw).Trim()
        if($lmHome -notmatch '^(?:[A-Za-z]:[\\/]|\\\\[^\\]+\\[^\\]+)' -or -not(Test-Path -LiteralPath $lmHome -PathType Container)){throw 'Ungueltiger LM-Studio-Home-Verweis.'}
    }elseif(Test-Path -LiteralPath (Join-Path $env:USERPROFILE '.cache\lm-studio') -PathType Container){$lmHome=Join-Path $env:USERPROFILE '.cache\lm-studio'}
    $lms=Find-BootstrapExecutable 'lms.exe' @((Join-Path $lmHome 'bin\lms.exe'))
    $tools['lms']=$lms
    if(-not $lms){Add-AuditCheck 'tool.lms' MISSING 'LM-Studio-CLI fehlt; App installieren bzw. Erststart abschliessen.'}
    else{
        Add-AuditCheck 'tool.lms' PASS 'LM-Studio-CLI gefunden.' @{path=$lms;version=(Invoke-AuditNative $lms @('--version'))}
        $help=Invoke-AuditNative $lms @('load','--help')
        $missing=@(Get-LrMissingLoadOptions -Help $help)
        $probe=$null
        if($missing -contains '--exact' -or $missing -contains '--local'){
            $probe=Invoke-AuditNative $lms @('load','--exact','--local','--estimate-only','--yes') -AllowFailure
            $missing=@(Get-LrMissingLoadOptions -Help $help -ExactLocalProbe $probe)
        }
        Add-AuditCheck 'lms.capabilities' $(if($missing.Count){'FAIL'}else{'PASS'}) 'Ladeoptionen per Hilfe und gegebenenfalls kontrolliertem Aufruf ohne Modellpfad mit --estimate-only geprueft; kein Modell geladen. Versteckte Optionen werden nicht allein wegen fehlender Hilfe abgelehnt.' @{missing=$missing;hiddenOptionsProbed=($null -ne $probe)}
        $server=ConvertFrom-AuditJson -Json (Invoke-AuditNative $lms @('server','status','--json')) -Source 'lms server status'
        if((Get-LrProperty $server 'running') -isnot [bool]){throw 'Serverstatus enthaelt kein running-Boolean.'}
        if($server.running){
            $backendPort=[int](Get-LrProperty $server 'port' 0)
            if($backendPort -lt 1 -or $backendPort -gt 65535){throw 'Laufender Server meldet keinen gueltigen Port.'}
        }
        Add-AuditCheck 'lms.server' $(if($server.running){'PASS'}else{'MISSING'}) 'Serverstatus gelesen; kein API-Serverstart angefordert.' @{running=$server.running;effectivePort=$backendPort}
        $downloaded=@(ConvertFrom-AuditJson -Json (Invoke-AuditNative $lms @('ls','--json')) -Source 'lms ls' -ModelList|Where-Object {
            (Get-LrProperty $_ 'type') -eq 'llm' -and $null -eq (Get-LrProperty $_ 'deviceIdentifier' '__unknown__')
        })
        if(@($downloaded|Where-Object {$null -ne (Get-LrProperty $_ 'selectedVariant')}).Count){
            $groups=@(ConvertFrom-AuditJson -Json (Invoke-AuditNative $lms @('ls','--variants','--json')) -Source 'lms ls --variants' -ModelList)
            Add-LrVariantMetadata -Models $downloaded -Groups $groups
        }
        $loaded=@(ConvertFrom-AuditJson -Json (Invoke-AuditNative $lms @('ps','--json')) -Source 'lms ps' -ModelList)
        Add-AuditCheck 'lms.models' PASS 'Lokale Modelldateien und geladene Instanzen gelesen.' @{downloadedCount=$downloaded.Count;loadedCount=$loaded.Count}
        foreach($instance in $loaded){
            $owned=@()
            if($states.ContainsKey('ownership')){
                $owned=@((Get-LrProperty $states.ownership 'Entries' @())|Where-Object {
                    (Get-LrProperty $_ 'InstanceId') -ceq (Get-LrProperty $instance 'identifier') -and
                    (Get-LrProperty $_ 'ModelPath') -ceq (Get-LrProperty $instance 'path')
                })
            }
            $local=$null -eq (Get-LrProperty $instance 'deviceIdentifier' '__unknown__')
            $idle=(Get-LrProperty $instance 'status') -ceq 'idle' -and [int](Get-LrProperty $instance 'queued' 0) -eq 0
            $recognized=$local -and $owned.Count -eq 1
            $verifiedOwnership=$recognized -and (Get-LrProperty $owned[0] 'Verified') -eq $true
            Add-AuditCheck 'model.loaded' $(if($verifiedOwnership -and $idle){'PASS'}else{'WARN'}) 'Instanz wird weder entladen noch uebernommen. Unbekannte, ausstehende oder beschaeftigte Instanzen erfordern weitere Setup-Pruefungen.' @{
                id=(Get-LrProperty $instance 'identifier');local=$local;idle=$idle;recordedOwner=$recognized
                ownershipVerified=$verifiedOwnership
            }
        }
    }
}catch{Add-AuditCheck 'lms' FAIL $_.Exception.Message}
foreach($definition in $definitions){
    try{
        $model=Find-LrModel -Models $downloaded -Profile $definition -ModelKey $ModelKey
        if($model){Add-AuditCheck 'model.file' PASS 'Exakte lokale Modelldatei gefunden.' @{profile=$definition.Name};continue}
        $status=if($ModelKey -or $SkipModelDownload){'FAIL'}else{'MISSING'}
        $message=if($ModelKey){'Explizites Modell nicht lokal nachgewiesen.'}elseif($SkipModelDownload){'Modelldatei fehlt und der Download ist deaktiviert.'}else{'Modelldatei nicht lokal nachgewiesen; das Setup bietet Auswahl und ggf. Download an.'}
        Add-AuditCheck 'model.file' $status $message @{profile=$definition.Name;path=$definition.ExpectedPath;downloadUrl=$definition.DownloadUrl}
    }catch{Add-AuditCheck 'model.file' FAIL $_.Exception.Message}
}
try{
    $listeners=@(Get-NetTCPConnection -State Listen -ErrorAction Stop)
    $listenersKnown=$true
    foreach($number in @($backendPort,$RouterPort)|Select-Object -Unique){
        if($number -eq $RouterPort -and $ModelMode -ne 'Dual' -and $number -ne $backendPort){continue}
        $atPort=@($listeners|Where-Object {$_.LocalPort -eq $number})
        $public=@($atPort|Where-Object {$_.LocalAddress -notin @('127.0.0.1','::1')})
        Add-AuditCheck "port.$number" $(if($public.Count){'FAIL'}elseif($atPort.Count){'WARN'}else{'PASS'}) 'Portbelegung gelesen; kein Dienst beendet.' @{
            listening=($atPort.Count -gt 0);loopbackOnly=($atPort.Count -gt 0 -and $public.Count -eq 0)
            addresses=@($atPort|ForEach-Object {$_.LocalAddress})
        }
    }
    if($ModelMode -eq 'Dual' -and $backendPort -eq $RouterPort){Add-AuditCheck 'ports.distinct' FAIL 'Der tatsaechliche Backendport kollidiert mit dem Routerport.'}
}catch{Add-AuditCheck 'ports' WARN $_.Exception.Message}
if($listenersKnown -and @($listeners|Where-Object {$_.LocalPort -eq $backendPort -and $_.LocalAddress -eq '127.0.0.1'}).Count){
    try{
        $catalog=Invoke-AuditJson -Uri "http://127.0.0.1:$backendPort/api/v1/models" -BearerToken $token
        if($null -eq $catalog -or $null -eq $catalog.PSObject.Properties['models'] -or $catalog.models -isnot [array]){throw 'Keine LM-Studio-REST-v1-Modelldaten am Backendport.'}
        Add-AuditCheck 'api.backend' PASS 'LM-Studio-REST-v1 erreichbar und Authentifizierung akzeptiert; keine Inferenz angefordert.'
    }catch{Add-AuditCheck 'api.backend' FAIL $_.Exception.Message}
}else{Add-AuditCheck 'api.backend' SKIP 'Kein nachgewiesener IPv4-Loopback-Listener; keine API-Anfrage gesendet.'}
if($ModelMode -eq 'Dual' -and $listenersKnown -and @($listeners|Where-Object {$_.LocalPort -eq $RouterPort -and $_.LocalAddress -eq '127.0.0.1'}).Count){
    try{
        $health=Invoke-AuditJson -Uri "http://127.0.0.1:$RouterPort/health" -BearerToken $token
        if((Get-LrProperty $health 'service') -cne 'shadow-local-model-router'){throw 'Port gehoert nicht zum erwarteten Modellrouter.'}
        Add-AuditCheck 'api.router' $(if((Get-LrProperty $health 'ready') -eq $true){'PASS'}else{'WARN'}) 'Routerstatus gelesen; kein Neustart angefordert.' @{
            ready=(Get-LrProperty $health 'ready');busy=(Get-LrProperty $health 'busy');queued=(Get-LrProperty $health 'queued')
        }
    }catch{Add-AuditCheck 'api.router' WARN $_.Exception.Message}
}
try{
    $manifest=Invoke-AuditJson -Uri 'https://registry.npmjs.org/@kilocode%2fcli/latest'
    if((Get-LrProperty $manifest 'name') -cne '@kilocode/cli' -or -not(Get-LrProperty $manifest 'version')){throw 'Oeffentliche npm-Registry liefert kein passendes Kilo-Manifest.'}
    Add-AuditCheck 'online.kilo' PASS 'Oeffentliche npm-Registry erreichbar. Fehlendes engines-Feld ist erlaubt; eine abweichend konfigurierte npm-Registry wird hier nicht geprueft.' @{
        version=$manifest.version;engines=(Get-LrProperty $manifest 'engines');bin=(Get-LrProperty $manifest 'bin')
    }
}catch{Add-AuditCheck 'online.kilo' WARN $_.Exception.Message}
foreach($definition in $definitions){
    if(-not $definition.ExpectedPath -or $SkipModelDownload){continue}
    try{
        $parts=$definition.ExpectedPath -split '/',3
        $repository=$parts[0]+'/'+$parts[1]
        $model=Invoke-AuditJson -Uri ("https://huggingface.co/api/models/"+$repository)
        $files=@((Get-LrProperty $model 'siblings' @())|Where-Object {(Get-LrProperty $_ 'rfilename') -ceq $parts[2]})
        if($files.Count -ne 1){throw 'Exakte GGUF-Datei wird von der Modellquelle nicht bestaetigt.'}
        Add-AuditCheck 'online.model' PASS 'Exakte GGUF-Datei im oeffentlichen Katalog gefunden; keine Modelldaten heruntergeladen.' @{profile=$definition.Name;repository=$repository}
    }catch{Add-AuditCheck 'online.model' WARN $_.Exception.Message @{profile=$definition.Name}}
}
Add-AuditCheck 'inference' SKIP 'Speicherschaetzung, Modellladen, Chat-/Tool-Smoke-Tests und wirksame Kilo-Konfiguration bleiben dem normalen Setup vorbehalten.'
$failed=@($checks|Where-Object {$_.status -eq 'FAIL'}).Count
$warnings=@($checks|Where-Object {$_.status -eq 'WARN'}).Count
$missing=@($checks|Where-Object {$_.status -eq 'MISSING'}).Count
[pscustomobject]@{
    schema=2;mode='AUDIT_ONLY';checkedAtUtc=[DateTime]::UtcNow.ToString('o');bundleVersion=$BundleVersion
    status=$(if($failed){'BLOCKED'}elseif($warnings -or $missing){'ATTENTION_REQUIRED'}else{'PRECHECK_PASSED'})
    exitCode=$(if($failed){2}else{0})
    provisioningPerformed=$false;inferenceVerified=$false;installRoot=$InstallRoot
    sideEffects='Das Audit schreibt keine Paketdateien und fordert keine Installation, Inferenz oder Modellwechsel an. Vorhandene CLI-Werkzeuge koennen Cache/Logs schreiben oder ihren Hintergrunddienst initialisieren. Oeffentliche Metadaten werden online abgefragt.'
    summary=@{failed=$failed;warnings=$warnings;missing=$missing;checks=$checks.Count}
    tools=$tools;checks=$checks.ToArray()
}
