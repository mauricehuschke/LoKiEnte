#requires -Version 5.1
# Invoked in memory by the verified bootstrap; never invokes installation code.
[CmdletBinding()]
param(
    [string]$InstallRoot,
    [string]$BundleVersion,
    [string]$PayloadHash,
    [Collections.IDictionary]$PackageFiles,
    [string]$ModelMode,
    [ValidateSet('Off','OnDemand','Automatic')][string]$IndexingMode='Off',
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
$IndexingMode=switch($IndexingMode){'Off'{'Off'} 'OnDemand'{'OnDemand'} 'Automatic'{'Automatic'}}
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
if($parseErrors.Count){throw 'Runtime module in the package contains syntax errors.'}
foreach($name in @('Get-LrProperty','ConvertFrom-LrModelList','Test-LrExpectedLoadProbe','Get-LrMissingLoadOptions','Select-LrProfile','Add-LrVariantMetadata','Find-LrModel')){
    $definition=$runtimeAst.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $name},$false)
    if($null -eq $definition){throw "Audit helper missing from package: $name"}
    . ([scriptblock]::Create($definition.Extent.Text))
    $commonAst=[Management.Automation.Language.Parser]::ParseInput($PackageFiles['Common.ps1'],[ref]$tokens,[ref]$parseErrors)
    if($parseErrors.Count){throw 'Common module in the package contains syntax errors.'}
    $definition=$commonAst.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Resolve-ShadowCodeCli'},$false)
    if($null -eq $definition){throw 'VS Code CLI path verification missing from package.'}
    . ([scriptblock]::Create($definition.Extent.Text))
}
$poolAst=[Management.Automation.Language.Parser]::ParseInput($PackageFiles['ModelPool.ps1'],[ref]$tokens,[ref]$parseErrors)
if($parseErrors.Count){throw 'Model pool module in package contains syntax errors.'}
$definition=$poolAst.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Get-SmpModelDefinitions'},$false)
if($null -eq $definition){throw 'Model catalog missing from package.'}
. ([scriptblock]::Create($definition.Extent.Text))
$selectionAst=[Management.Automation.Language.Parser]::ParseInput($PackageFiles['ModelSelection.ps1'],[ref]$tokens,[ref]$parseErrors)
if($parseErrors.Count){throw 'Model selection module in package contains syntax errors.'}
foreach($name in @('Get-ShadowModelCatalog','Get-ShadowModelRanking','Get-ShadowRecommendedModel')){
    $definition=$selectionAst.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $name},$false)
    if($null -eq $definition){throw "Audit model catalog missing: $name"}
    . ([scriptblock]::Create($definition.Extent.Text))
}
$ripgrepAst=[Management.Automation.Language.Parser]::ParseInput($PackageFiles['Ripgrep.ps1'],[ref]$tokens,[ref]$parseErrors)
if($parseErrors.Count){throw 'Ripgrep module in the package contains syntax errors.'}
$definition=$ripgrepAst.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Get-ShadowRipgrepInfo'},$false)
if($null -eq $definition){throw 'Ripgrep audit data missing.'}
. ([scriptblock]::Create($definition.Extent.Text))

function Add-AuditCheck {
    param([string]$Name,[ValidateSet('PASS','WARN','FAIL','MISSING','SKIP')][string]$Status,[string]$Message,$Data=$null)
    $checks.Add([pscustomobject]@{name=$Name;status=$Status;message=$Message;data=$Data})
}

function Invoke-AuditNative {
    param([string]$FilePath,[string[]]$Arguments,[int]$TimeoutSeconds=20,[switch]$AllowFailure)
    if([IO.Path]::GetExtension($FilePath) -in @('.cmd','.bat','.ps1')){throw 'Audit requires a native program entry point, not a shell shim.'}
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
            throw "Timeout ($TimeoutSeconds s) for $([IO.Path]::GetFileName($FilePath)). Only the audit CLI process was terminated; a background service it started may still be running."
        }
        $text=$stdout.GetAwaiter().GetResult()
        $errorText=$stderr.GetAwaiter().GetResult()
        if($AllowFailure){return [pscustomobject]@{ExitCode=$process.ExitCode;Stdout=$text;Stderr=$errorText}}
        if($process.ExitCode -ne 0){throw "$([IO.Path]::GetFileName($FilePath)) returned exit code $($process.ExitCode). Check the program separately."}
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
            if(-not $Uri.IsLoopback){throw 'Audit sends API tokens only to loopback addresses.'}
            if($BearerToken -match '[\r\n]'){throw 'API token contains invalid header characters; its value is not displayed.'}
            try{$client.DefaultRequestHeaders.Authorization=New-Object Net.Http.Headers.AuthenticationHeaderValue('Bearer',$BearerToken)}
            catch{throw 'API token cannot be used as an Authorization header; its value is not displayed.'}
        }
        try{$response=$client.GetAsync($Uri).GetAwaiter().GetResult()}
        catch{throw "Connection to $($Uri.Host):$($Uri.Port) failed or timed out."}
        if(-not $response.IsSuccessStatusCode){throw "HTTP $([int]$response.StatusCode) from $($Uri.Host):$($Uri.Port). No redirect or fallback performed."}
        $text=$response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        try{return ConvertFrom-Json -InputObject $text -ErrorAction Stop}
        catch{throw "Response from $($Uri.Host) is not valid JSON."}
    }finally{if($response){$response.Dispose()};$client.Dispose();$handler.Dispose()}
}

function ConvertFrom-AuditJson {
    param([string]$Json,[string]$Source,[switch]$ModelList)
    try{
        if($ModelList){ConvertFrom-LrModelList -Json $Json;return}
        return ConvertFrom-Json -InputObject $Json -ErrorAction Stop
    }
    catch{throw "Invalid JSON or unexpected structure from $Source. Raw data is not included in the audit report."}
}

Add-AuditCheck 'bundle' PASS 'Embedded ZIP verified using SHA256 before evaluation.' @{version=$BundleVersion;sha256=$PayloadHash}
if($AllowPartialGpuOffload){Add-AuditCheck 'model.offload' WARN 'Partial CPU offload selected; memory fit and performance will be checked during setup.'}
try{Assert-BootstrapOptions;Add-AuditCheck 'parameters' PASS 'Parameter combination and project paths are valid.'}
catch{Add-AuditCheck 'parameters' FAIL $_.Exception.Message}
try{
    if($env:OS -ne 'Windows_NT' -or -not [Environment]::Is64BitOperatingSystem -or
       -not [Environment]::Is64BitProcess -or $env:PROCESSOR_ARCHITECTURE -eq 'ARM64' -or $env:PROCESSOR_ARCHITEW6432 -eq 'ARM64'){
        throw 'Windows x64 and a 64-bit PowerShell process are required.'
    }
    $system=Get-CimInstance Win32_OperatingSystem
    $cpu=Get-CimInstance Win32_Processor|Select-Object -First 1
    $hardware=[pscustomobject]@{
        Gpu=$null;TotalRamBytes=([long]$system.TotalVisibleMemorySize*1KB)
        FreeRamBytes=([long]$system.FreePhysicalMemory*1KB)
    }
    Add-AuditCheck 'windows' PASS 'Windows x64 environment detected.' @{
        name=$system.Caption;build=$system.BuildNumber;cpu=$cpu.Name
        ramGiB=[math]::Round($hardware.TotalRamBytes/1GB,1);freeRamGiB=[math]::Round($hardware.FreeRamBytes/1GB,1)
        auditPowerShell=$PSVersionTable.PSVersion.ToString()
    }
}catch{Add-AuditCheck 'windows' FAIL $_.Exception.Message}
try{
    Assert-BootstrapInstallRoot -AllowSharedDirectory
    Add-AuditCheck 'installRoot' PASS 'Installation path and package identity are usable; no write test performed.' @{path=$InstallRoot;exists=(Test-Path -LiteralPath $InstallRoot)}
}catch{Add-AuditCheck 'installRoot' FAIL $_.Exception.Message}
try{
    $legacyRoot=Join-Path $env:LOCALAPPDATA 'ShadowLocalAI'
    if([IO.Path]::GetFullPath($InstallRoot).TrimEnd('\','/') -ine $legacyRoot.TrimEnd('\','/') -and (Test-Path -LiteralPath $legacyRoot)){
        Add-AuditCheck 'installRoot.legacy' WARN 'Legacy directory exists. Audit checks only installRoot and copies nothing. Use -InstallRoot to inspect the old directory explicitly; normal provisioning offers selection/copying.' @{path=$legacyRoot}
    }
}catch{Add-AuditCheck 'installRoot.legacy' FAIL 'Could not check the previous installation directory.'}
try{
    $lockPaths=@((Join-Path $InstallRoot 'provisioning.lock'),(Join-Path $InstallRoot 'setup-active.lock'))
    $foundLock=$false
    foreach($lockPath in $lockPaths){
        if(-not(Test-Path -LiteralPath $lockPath -PathType Leaf)){continue}
        $lock=[IO.File]::Open($lockPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
        $lock.Dispose();$foundLock=$true
    }
    if($foundLock){
        Add-AuditCheck 'setup.lock' PASS 'No exclusive provisioning run detected on the existing lock file.'
    }else{Add-AuditCheck 'setup.lock' SKIP 'No provisioning lock exists yet.'}
}catch{Add-AuditCheck 'setup.lock' FAIL 'Provisioning lock is occupied or unreadable. Complete active setup or check permissions.'}
try{
    $disks=@(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType = 3'|ForEach-Object {
        @{drive=$_.DeviceID;totalGiB=[math]::Round($_.Size/1GB,1);freeGiB=[math]::Round($_.FreeSpace/1GB,1)}
    })
    Add-AuditCheck 'storage' WARN 'Free space is a snapshot. The configured LM Studio model drive and download space must be checked separately; allow about 60 GB of reserve for a new installation.' $disks
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
            Add-AuditCheck "tool.$name" $status $(if($status -eq 'FAIL'){'Prerequisite missing; provide it before provisioning.'}else{'Missing; can be installed during normal setup.'})
            continue
        }
        $version=if($name -in @('code','lmstudio')){
            (Get-Item -LiteralPath $path).VersionInfo.ProductVersion
        }elseif($name -eq 'pwsh'){
            Invoke-AuditNative $path @('-NoLogo','-NoProfile','-NonInteractive','-Command','$PSVersionTable.PSVersion.ToString()')
        }elseif($name -eq 'nvidia-smi'){'see GPU check'}else{Invoke-AuditNative $path @('--version')}
        if($name -eq 'pwsh' -and [version]$version -lt [version]'7.4'){throw 'Existing PowerShell is older than 7.4; it will not be replaced automatically.'}
        if($name -eq 'node' -and ($version -notmatch '^v(\d+)\.' -or [int]$Matches[1] -lt 20)){throw 'Existing Node cannot be verified as version >=20.'}
        if($name -eq 'curl'){$version=($version -split '\r?\n')[0]}
        Add-AuditCheck "tool.$name" PASS 'Program found.' @{path=$path;version=$version}
    }catch{Add-AuditCheck "tool.$name" FAIL $_.Exception.Message}
}
try{
    $ripgrep=Get-ShadowRipgrepInfo -InstallRoot $InstallRoot
    Assert-BootstrapNoReparsePoint -Path $ripgrep.Path
    if(-not(Test-Path -LiteralPath $ripgrep.Path -PathType Leaf)){
        Add-AuditCheck 'tool.ripgrep' MISSING 'Ripgrep is missing from the isolated Kilo cache; normal setup will provide it.' @{path=$ripgrep.Path}
    }else{
        $hash=(Get-FileHash -LiteralPath $ripgrep.Path -Algorithm SHA256 -ErrorAction Stop).Hash
        if($hash -ine $ripgrep.ExecutableSha256){throw 'Existing ripgrep has an unknown checksum and remains unchanged.'}
        $version=Invoke-AuditNative $ripgrep.Path @('--version')
        if($version -notmatch '(?m)^ripgrep 15\.1\.0(?:\s|$)'){throw 'Ripgrep reports an unexpected version.'}
        Add-AuditCheck 'tool.ripgrep' PASS 'Verified ripgrep found in the isolated Kilo cache; Kilo file search will be tested during setup.' @{path=$ripgrep.Path;version=$ripgrep.Version}
    }
}catch{Add-AuditCheck 'tool.ripgrep' FAIL $_.Exception.Message}
try{
    if($tools['code']){
        $cli=Resolve-ShadowCodeCli -CodePath $tools['code']
        Add-AuditCheck 'vscode.cli' PASS 'The CLI entry point declared by installed VS Code exists; no extensions installed.' @{path=$cli}
    }else{
        Add-AuditCheck 'vscode.cli' SKIP 'VS Code is missing; cannot check its CLI path yet.'
    }
}catch{Add-AuditCheck 'vscode.cli' FAIL $_.Exception.Message}
try{
    $npm=$null
    if($tools['node']){$npm=Join-Path (Split-Path $tools['node'] -Parent) 'node_modules\npm\bin\npm-cli.js'}
    if(-not $npm -or -not(Test-Path -LiteralPath $npm -PathType Leaf)){
        $shim=Find-BootstrapExecutable 'npm.cmd'
        if($shim){$npm=Join-Path (Split-Path $shim -Parent) 'node_modules\npm\bin\npm-cli.js'}
    }
    $chainPath=Join-Path $InstallRoot 'toolchain.json'
    if (Test-Path -LiteralPath $chainPath -PathType Leaf) {
        $state=ConvertFrom-AuditJson -Json (Get-Content -LiteralPath $chainPath -Raw) -Source 'toolchain'
        $v=Get-LrProperty $state 'npmVersion'
        if ($v -match '^\d+\.\d+\.\d+$') {
            $private=Join-Path $InstallRoot "tooling/npm-versions/$v/node_modules/npm/bin/npm-cli.js"
            if ([IO.Path]::GetFullPath($private) -eq (Get-LrProperty $state 'npmEntry')) { $npm=$private }
        }
    }
    if($tools['node'] -and $npm -and (Test-Path -LiteralPath $npm -PathType Leaf)){
        $tools['npm']=$npm
        Add-AuditCheck 'tool.npm' PASS 'npm callable through the native Node entry point.' @{version=(Invoke-AuditNative $tools['node'] @($npm,'--version'))}
    }else{Add-AuditCheck 'tool.npm' $(if($tools['node']){'FAIL'}else{'MISSING'}) 'npm-cli.js or Node is missing.'}
}catch{Add-AuditCheck 'tool.npm' FAIL $_.Exception.Message}
try{
    $packageRoot=Join-Path $InstallRoot 'tooling\node_modules\@kilocode\cli'
    $manifestPath=Join-Path $packageRoot 'package.json'
    if(Test-Path -LiteralPath $manifestPath -PathType Leaf){
        $manifest=ConvertFrom-AuditJson -Json (Get-Content -LiteralPath $manifestPath -Raw) -Source 'Kilo manifest'
        if((Get-LrProperty $manifest 'name') -cne '@kilocode/cli' -or -not(Get-LrProperty $manifest 'version')){throw 'Installed Kilo manifest is incomplete.'}
        $bin=Get-LrProperty $manifest 'bin'
        $relative=if($bin -is [string]){$bin}else{Get-LrProperty $bin 'kilo'}
        if($relative -isnot [string] -or -not $relative){throw 'Installed Kilo manifest has no CLI entry point.'}
        $entry=[IO.Path]::GetFullPath((Join-Path $packageRoot $relative))
        $prefix=[IO.Path]::GetFullPath($packageRoot)+[IO.Path]::DirectorySeparatorChar
        if(-not $entry.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase) -or -not(Test-Path -LiteralPath $entry -PathType Leaf)){
            throw 'Kilo CLI entry point is missing or outside the managed package.'
        }
        Add-AuditCheck 'tool.kilo' PASS 'Managed Kilo manifest and entry point exist; effective configuration was not executed.' @{version=$manifest.version}
    }else{Add-AuditCheck 'tool.kilo' MISSING 'No private Kilo installation found. Setup may reuse a compatible global CLI.'}
}catch{Add-AuditCheck 'tool.kilo' FAIL $_.Exception.Message}
try{
    if(-not $tools['nvidia-smi']){throw 'GPU memory cannot be verified without nvidia-smi.'}
    $text=Invoke-AuditNative $tools['nvidia-smi'] @('--query-gpu=name,memory.total,memory.free,driver_version','--format=csv,noheader,nounits')
    $gpus=@(foreach($line in ($text -split '\r?\n')){
        if(-not $line.Trim()){continue}
        $parts=$line -split ',',4
        if($parts.Count -ne 4){throw 'Unexpected nvidia-smi output.'}
        $total=[double]::Parse($parts[1].Trim(),[Globalization.CultureInfo]::InvariantCulture)*1MB
        $free=[double]::Parse($parts[2].Trim(),[Globalization.CultureInfo]::InvariantCulture)*1MB
        if($total -le 0 -or $free -lt 0 -or $free -gt $total){throw 'Invalid GPU memory values.'}
        [pscustomobject]@{Name=$parts[0].Trim();TotalBytes=[long]$total;FreeBytes=[long]$free;Driver=$parts[3].Trim()}
    })
    if($gpus.Count -ne 1){throw "Detected $($gpus.Count) NVIDIA GPUs; setup requires exactly one."}
    if($null -eq $hardware){throw 'RAM inventory unavailable.'}
    $hardware.Gpu=$gpus[0]
    Add-AuditCheck 'gpu' PASS 'NVIDIA GPU and free memory detected.' $gpus[0]
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
        Add-AuditCheck 'model.hardware' WARN 'No approximate memory recommendation for at least one role. Select explicitly during setup; downloads remain available.' @{profiles=@($definitions|ForEach-Object {$_.Name});rolesWithoutFit=@($noFitRoles);requestedContext=$ContextLength}
    }else{
        Add-AuditCheck 'model.hardware' PASS 'Non-binding hardware-based suggestions; model selection takes place during setup. This does not prove actual model/context fit.' @{profiles=@($definitions|ForEach-Object {$_.Name});requestedContext=$ContextLength}
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
        if(-not(Test-Path -LiteralPath $path -PathType Leaf)){Add-AuditCheck "state.$($item.name)" MISSING 'No saved state exists yet.';continue}
        $state=ConvertFrom-AuditJson -Json (Get-Content -LiteralPath $path -Raw) -Source $item.name
        if((Get-LrProperty $state $item.schema) -ne $item.version){throw 'Unknown state schema; audit does not repair it automatically.'}
        $required=switch($item.name){
            'toolchain'{@('nodeExecutable','kiloExecutable','powerShellExecutable','codeExecutable')}
            'pool'{@('OwnerId','BackendApiBaseUrl','RouterApiBaseUrl','Profiles','Status')}
            'runtime'{@('ModelId','ModelPath','ApiBaseUrl','Status')}
            'ownership'{@('OwnerId')}
            'selection'{@('roles')}
            'provisioning'{@('status')}
        }
        foreach($field in $required){if(-not(Get-LrProperty $state $field)){throw "Required field missing from saved state: $field"}}
        if($item.name -eq 'ownership' -and ($null -eq $state.PSObject.Properties['Entries'] -or $state.Entries -isnot [array])){
            throw 'Ownership record has no entries list.'
        }
        foreach($field in @('ApiBaseUrl','BackendApiBaseUrl','RouterApiBaseUrl')){
            $value=Get-LrProperty $state $field
            if($value){
                $uri=[Uri]$value
                if(-not $uri.IsAbsoluteUri -or -not $uri.IsLoopback -or $uri.Scheme -ne 'http' -or
                   $uri.UserInfo -or $uri.Query -or $uri.Fragment -or $uri.AbsolutePath.TrimEnd('/') -cne '/v1'){
                    throw 'Saved model endpoint is not an unambiguous local HTTP /v1 endpoint.'
                }
            }
        }
        $states[$item.name]=$state
        $status=Get-LrProperty $state 'Status' (Get-LrProperty $state 'status')
        $valid=$null -eq $status -or $status -cin @('Ready','PROVISIONED')
        Add-AuditCheck "state.$($item.name)" $(if($valid){'PASS'}else{'WARN'}) 'Saved state read; this does not replace a current functional check.' @{status=$status}
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
        Add-AuditCheck 'model.selection' PASS 'Checking saved model selection against existing files; new recommendations appear during setup.'
    }else{
        Add-AuditCheck 'model.selection' WARN 'Saved model selection is not fully represented in the catalog; audit shows current suggestions rather than claiming a confirmed selection.'
    }
}
try{
    if($ApiTokenEnvironmentVariable){
        $token=[Environment]::GetEnvironmentVariable($ApiTokenEnvironmentVariable,'Process')
        if(-not $token){$token=[Environment]::GetEnvironmentVariable($ApiTokenEnvironmentVariable,'User')}
    }
    Add-AuditCheck 'authentication' PASS 'Only token availability recorded; no token value in the report.' @{variable=$ApiTokenEnvironmentVariable;present=(-not [string]::IsNullOrWhiteSpace($token))}
    $lmHome=Join-Path $env:USERPROFILE '.lmstudio'
    $pointer=Join-Path $env:USERPROFILE '.lmstudio-home-pointer'
    if(Test-Path -LiteralPath $pointer -PathType Leaf){
        $lmHome=(Get-Content -LiteralPath $pointer -Raw).Trim()
        if($lmHome -notmatch '^(?:[A-Za-z]:[\\/]|\\\\[^\\]+\\[^\\]+)' -or -not(Test-Path -LiteralPath $lmHome -PathType Container)){throw 'Invalid LM Studio home reference.'}
    }elseif(Test-Path -LiteralPath (Join-Path $env:USERPROFILE '.cache\lm-studio') -PathType Container){$lmHome=Join-Path $env:USERPROFILE '.cache\lm-studio'}
    $lms=Find-BootstrapExecutable 'lms.exe' @((Join-Path $lmHome 'bin\lms.exe'))
    $tools['lms']=$lms
    if(-not $lms){Add-AuditCheck 'tool.lms' MISSING 'LM Studio CLI missing; install the app or complete first-run setup.'}
    else{
        Add-AuditCheck 'tool.lms' PASS 'LM Studio CLI found.' @{path=$lms;version=(Invoke-AuditNative $lms @('--version'))}
        $help=Invoke-AuditNative $lms @('load','--help')
        $missing=@(Get-LrMissingLoadOptions -Help $help)
        $probe=$null
        if($missing -contains '--exact' -or $missing -contains '--local'){
            $probe=Invoke-AuditNative $lms @('load','--exact','--local','--estimate-only','--yes') -AllowFailure
            $missing=@(Get-LrMissingLoadOptions -Help $help -ExactLocalProbe $probe)
        }
        Add-AuditCheck 'lms.capabilities' $(if($missing.Count){'FAIL'}else{'PASS'}) 'Load options checked through help and, where necessary, a controlled --estimate-only invocation without a model path; no model loaded. Hidden options are not rejected merely because help omits them.' @{missing=$missing;hiddenOptionsProbed=($null -ne $probe)}
        $server=ConvertFrom-AuditJson -Json (Invoke-AuditNative $lms @('server','status','--json')) -Source 'lms server status'
        if((Get-LrProperty $server 'running') -isnot [bool]){throw 'Server status has no running boolean.'}
        if($server.running){
            $backendPort=[int](Get-LrProperty $server 'port' 0)
            if($backendPort -lt 1 -or $backendPort -gt 65535){throw 'Running server reports no valid port.'}
        }
        Add-AuditCheck 'lms.server' $(if($server.running){'PASS'}else{'MISSING'}) 'Server status read; no API server start requested.' @{running=$server.running;effectivePort=$backendPort}
        $downloaded=@(ConvertFrom-AuditJson -Json (Invoke-AuditNative $lms @('ls','--json')) -Source 'lms ls' -ModelList|Where-Object {
            (Get-LrProperty $_ 'type') -eq 'llm' -and $null -eq (Get-LrProperty $_ 'deviceIdentifier' '__unknown__')
        })
        if(@($downloaded|Where-Object {$null -ne (Get-LrProperty $_ 'selectedVariant')}).Count){
            $groups=@(ConvertFrom-AuditJson -Json (Invoke-AuditNative $lms @('ls','--variants','--json')) -Source 'lms ls --variants' -ModelList)
            Add-LrVariantMetadata -Models $downloaded -Groups $groups
        }
        $loaded=@(ConvertFrom-AuditJson -Json (Invoke-AuditNative $lms @('ps','--json')) -Source 'lms ps' -ModelList)
        Add-AuditCheck 'lms.models' PASS 'Local model files and loaded instances read.' @{downloadedCount=$downloaded.Count;loadedCount=$loaded.Count}
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
            Add-AuditCheck 'model.loaded' $(if($verifiedOwnership -and $idle){'PASS'}else{'WARN'}) 'Instance will neither be unloaded nor adopted. Unknown, pending or busy instances require further setup checks.' @{
                id=(Get-LrProperty $instance 'identifier');local=$local;idle=$idle;recordedOwner=$recognized
                ownershipVerified=$verifiedOwnership
            }
        }
    }
}catch{Add-AuditCheck 'lms' FAIL $_.Exception.Message}
foreach($definition in $definitions){
    try{
        $model=Find-LrModel -Models $downloaded -Profile $definition -ModelKey $ModelKey
        if($model){Add-AuditCheck 'model.file' PASS 'Exact local model file found.' @{profile=$definition.Name};continue}
        $status=if($ModelKey -or $SkipModelDownload){'FAIL'}else{'MISSING'}
        $message=if($ModelKey){'Explicit model not verified locally.'}elseif($SkipModelDownload){'Model file missing and downloads disabled.'}else{'Model file not verified locally; setup offers selection and download where applicable.'}
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
        Add-AuditCheck "port.$number" $(if($public.Count){'FAIL'}elseif($atPort.Count){'WARN'}else{'PASS'}) 'Port usage read; no service stopped.' @{
            listening=($atPort.Count -gt 0);loopbackOnly=($atPort.Count -gt 0 -and $public.Count -eq 0)
            addresses=@($atPort|ForEach-Object {$_.LocalAddress})
        }
    }
    if($ModelMode -eq 'Dual' -and $backendPort -eq $RouterPort){Add-AuditCheck 'ports.distinct' FAIL 'The actual backend port conflicts with the router port.'}
}catch{Add-AuditCheck 'ports' WARN $_.Exception.Message}
if($listenersKnown -and @($listeners|Where-Object {$_.LocalPort -eq $backendPort -and $_.LocalAddress -eq '127.0.0.1'}).Count){
    try{
        $catalog=Invoke-AuditJson -Uri "http://127.0.0.1:$backendPort/api/v1/models" -BearerToken $token
        if($null -eq $catalog -or $null -eq $catalog.PSObject.Properties['models'] -or $catalog.models -isnot [array]){throw 'No LM Studio REST v1 model data at the backend port.'}
        Add-AuditCheck 'api.backend' PASS 'LM Studio REST v1 reachable and authentication accepted; no inference requested.'
    }catch{Add-AuditCheck 'api.backend' FAIL $_.Exception.Message}
}else{Add-AuditCheck 'api.backend' SKIP 'No verified IPv4 loopback listener; no API request sent.'}
if($ModelMode -eq 'Dual' -and $listenersKnown -and @($listeners|Where-Object {$_.LocalPort -eq $RouterPort -and $_.LocalAddress -eq '127.0.0.1'}).Count){
    try{
        $health=Invoke-AuditJson -Uri "http://127.0.0.1:$RouterPort/health" -BearerToken $token
        if((Get-LrProperty $health 'service') -cne 'shadow-local-model-router'){throw 'Port does not belong to the expected model router.'}
        Add-AuditCheck 'api.router' $(if((Get-LrProperty $health 'ready') -eq $true){'PASS'}else{'WARN'}) 'Router status read; no restart requested.' @{
            ready=(Get-LrProperty $health 'ready');busy=(Get-LrProperty $health 'busy');queued=(Get-LrProperty $health 'queued')
        }
    }catch{Add-AuditCheck 'api.router' WARN $_.Exception.Message}
}
try{
    $manifest=Invoke-AuditJson -Uri 'https://registry.npmjs.org/@kilocode%2fcli/latest'
    if((Get-LrProperty $manifest 'name') -cne '@kilocode/cli' -or -not(Get-LrProperty $manifest 'version')){throw 'Public npm registry returned no matching Kilo manifest.'}
    Add-AuditCheck 'online.kilo' PASS 'Public npm registry reachable. A missing engines field is allowed; a differently configured npm registry is not checked here.' @{
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
        if($files.Count -ne 1){throw 'The model source does not confirm the exact GGUF file.'}
        Add-AuditCheck 'online.model' PASS 'Exact GGUF file found in the public catalog; no model data downloaded.' @{profile=$definition.Name;repository=$repository}
    }catch{Add-AuditCheck 'online.model' WARN $_.Exception.Message @{profile=$definition.Name}}
}
Add-AuditCheck 'inference' SKIP 'Memory estimation, model loading, chat/tool smoke tests and effective Kilo configuration are reserved for normal setup.'
$failed=@($checks|Where-Object {$_.status -eq 'FAIL'}).Count
$warnings=@($checks|Where-Object {$_.status -eq 'WARN'}).Count
$missing=@($checks|Where-Object {$_.status -eq 'MISSING'}).Count
[pscustomobject]@{
    schema=2;mode='AUDIT_ONLY';checkedAtUtc=[DateTime]::UtcNow.ToString('o');bundleVersion=$BundleVersion
    status=$(if($failed){'BLOCKED'}elseif($warnings -or $missing){'ATTENTION_REQUIRED'}else{'PRECHECK_PASSED'})
    exitCode=$(if($failed){2}else{0})
    provisioningPerformed=$false;inferenceVerified=$false;installRoot=$InstallRoot;requestedIndexingMode=$IndexingMode
    sideEffects='Audit writes no package files and requests no installation, inference or model switches. Existing CLI tools may write caches/logs or initialize their background service. Public metadata is queried online.'
    summary=@{failed=$failed;warnings=$warnings;missing=$missing;checks=$checks.Count}
    tools=$tools;checks=$checks.ToArray()
}
