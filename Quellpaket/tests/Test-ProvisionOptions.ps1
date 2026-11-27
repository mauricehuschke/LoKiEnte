#requires -Version 7.4
# Actual recommendation/file-copy logic; no real model or network is used.
param([string]$SourceRoot=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
foreach($name in @('Common.ps1','Runtime.ps1','ModelSelection.ps1')){. (Join-Path $SourceRoot $name)}
$checks=0
function Assert-Option($Value,$Message){if(-not $Value){throw $Message};$script:checks++}
function Assert-OptionFailure($Action,$Pattern){$failure=$null;try{& $Action|Out-Null}catch{$failure=$_};Assert-Option ($failure -and $failure.Exception.Message -match $Pattern) "Expected failure: $Pattern"}
function Read-Host {param($Prompt) throw 'Unexpected interactive prompt'}
$bootstrap=Join-Path (Split-Path -Parent $SourceRoot) 'Provision-LoKiEnte.ps1'
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($bootstrap,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Bootstrap parse failure'}
foreach($name in @('Confirm-BootstrapInstallation','Assert-BootstrapOptions')){
    $definition=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq $name},$false)
    . ([scriptblock]::Create($definition.Extent.Text))
}
$ModelMode='Dual';$ModelAction='Configure';$ModelKey='';$PreferredModel='Auto';$IndexingMode='Off';$AllowPartialGpuOffload=$true;$IncludeFastModel=$true;$Port=1234;$RouterPort=1235;$ApiTokenEnvironmentVariable='';$ProjectPath=@()
Assert-BootstrapOptions -UseRecommendedModelsBasedOnGPU
$ModelAction='Keep';Assert-OptionFailure {Assert-BootstrapOptions -UseRecommendedModelsBasedOnGPU} 'requires Configure';$ModelAction='Configure'
$ModelKey='custom';Assert-OptionFailure {Assert-BootstrapOptions -UseRecommendedModelsBasedOnGPU} 'requires Configure';$ModelKey=''
Assert-Option (Confirm-BootstrapInstallation -Selection @{Root='D:\Synthetic';CopyFrom=$null} -SilentMode) 'SilentMode must replace the initial y confirmation.'
Assert-OptionFailure {Confirm-BootstrapInstallation -Selection @{Root='D:\Synthetic';CopyFrom=$null}} 'Unexpected interactive prompt'
$hardware=[pscustomobject]@{Gpu=[pscustomobject]@{FreeBytes=19GB};FreeRamBytes=21.6GB}
$previous=@([pscustomobject]@{Alias='coder-high';Id='qwen35-9b';Name='Old selection'})
$chosen=@(Select-ShadowModels -Hardware $hardware -Downloaded @() -PreviousProfiles $previous -IncludeFastModel -UseRecommendedModelsBasedOnGPU)
Assert-Option ($chosen.Count -eq 4 -and $chosen[0].Definition.Id -ceq 'qwen3-14b' -and $chosen[1].Definition.Id -ceq 'qwen35-9b') 'Automatic recommendations must use current hardware without saved-selection or confirmation prompts.'
$small=[pscustomobject]@{Gpu=[pscustomobject]@{FreeBytes=1GB};FreeRamBytes=4GB}
Assert-OptionFailure {Select-ShadowModels -Hardware $small -Downloaded @() -UseRecommendedModelsBasedOnGPU} 'No recommended model fits'
Assert-OptionFailure {Select-ShadowModels -Hardware $hardware -Downloaded @() -UseRecommendedModelsBasedOnGPU -PreferredId custom} 'cannot be combined'
$root=Join-Path ([IO.Path]::GetTempPath()) ('lokiente-provision-options-'+[guid]::NewGuid().ToString('N'))
try{
    $script:models=Join-Path $root 'models';[void][IO.Directory]::CreateDirectory((Join-Path $models 'test/repo'))
    $bytes=[Text.Encoding]::UTF8.GetBytes('synthetic exact model');$hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
    $weight=@{Name='model.gguf';Size=$bytes.Length;Sha256=$hash};$projector=@{Name='mmproj.gguf';Size=$bytes.Length;Sha256=$hash}
    $model=@{Id='synthetic';Name='Synthetic';Repository='test/repo';ExpectedPath='test/repo/model.gguf';Files=@($weight,$projector)}
    [IO.File]::WriteAllBytes((Join-Path $models 'test/repo/model.gguf'),$bytes)
    $script:source=Join-Path $root 'downloaded.bin';[IO.File]::WriteAllBytes($source,$bytes)
    $script:downloads=[Collections.Generic.List[string]]::new();$script:visible=$true;$script:sleeps=0
    function Resolve-ShadowModelDirectory {return $script:models}
    function Invoke-ShadowModelDownload {param($Model,$File,$DownloadRoot) $script:downloads.Add($File.Name);return $script:source}
    function Get-LrDownloadedModels {param($LmsPath,$LogDirectory) if($script:visible){return @{path='test/repo/model.gguf';modelKey='synthetic'}};return @()}
    function Start-Sleep {param($Seconds) $script:sleeps++}
    $definitions=@(@{Alias='coder-high';Definition=$model})
    Install-ShadowSelectedModels -Definitions $definitions -LmsPath synthetic -InstallRoot $root
    Assert-Option ($downloads.Count -eq 1 -and $downloads[0] -ceq 'mmproj.gguf') 'Only the missing exact catalog file is downloaded; the existing weight is reused.'
    Install-ShadowSelectedModels -Definitions $definitions -LmsPath synthetic -InstallRoot $root
    Assert-Option ($downloads.Count -eq 1) 'A fully present verified model needs no download.'
    $script:visible=$false
    Assert-OptionFailure {Install-ShadowSelectedModels -Definitions $definitions -LmsPath synthetic -InstallRoot $root -DiscoveryAttempts 2} 'after 2 checks'
    Assert-Option ($sleeps -eq 1) 'Failed LM Studio discovery must be bounded instead of waiting forever for user intervention.'
    $script:visible=$true
    [IO.File]::WriteAllText((Join-Path $models 'test/repo/mmproj.gguf'),'preserved conflicting data')
    Assert-OptionFailure {Install-ShadowSelectedModels -Definitions $definitions -LmsPath synthetic -InstallRoot $root} 'not identical'
    Assert-Option ([IO.File]::ReadAllText((Join-Path $models 'test/repo/mmproj.gguf')) -ceq 'preserved conflicting data') 'Automatic selection cannot overwrite a conflicting existing file.'
    $app=Join-Path $root 'app';[void][IO.Directory]::CreateDirectory($app)
    Copy-Item -LiteralPath (Join-Path $SourceRoot 'Invoke-SetupRequest.ps1') -Destination $app
    [IO.File]::WriteAllText((Join-Path $app 'Setup.ps1'),'param([switch]$UseRecommendedModelsBasedOnGPU,[switch]$SilentMode,[switch]$WorkspaceTrust) @{recommended=[bool]$UseRecommendedModelsBasedOnGPU;silent=[bool]$SilentMode;trust=[bool]$WorkspaceTrust}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $PSScriptRoot "received.json");exit 0')
    $request=Join-Path $root 'request.json';[IO.File]::WriteAllText($request,'{"UseRecommendedModelsBasedOnGPU":true,"SilentMode":true,"WorkspaceTrust":true}')
    & (Get-Process -Id $PID).Path -NoLogo -NoProfile -File (Join-Path $app 'Invoke-SetupRequest.ps1') -RequestPath $request
    $received=Get-Content (Join-Path $app 'received.json') -Raw|ConvertFrom-Json
    Assert-Option ($LASTEXITCODE -eq 0 -and $received.recommended -and $received.silent -and $received.trust) 'All three switches must survive the real JSON/PowerShell child handoff.'
    foreach($flag in @('UseRecommendedModelsBasedOnGPU','SilentMode','WorkspaceTrust')){
        Assert-Option ($ast.ParamBlock.Parameters.Name.VariablePath.UserPath -contains $flag) "Bootstrap parameter missing: $flag"
        Assert-Option ((Get-Content $bootstrap -Raw).Contains(($flag+'=[bool]$'+$flag))) "Bootstrap request flag missing: $flag"
    }
    @{suite='Provision options';checks=$checks;passed=$true;limitations='Real functions, files, hashes and child handoff. GPU inventory, downloads and LM Studio catalog are synthetic boundaries.'}|ConvertTo-Json
}finally{
    $resolved=[IO.Path]::GetFullPath($root);$allowed=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
    if(-not $resolved.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notlike 'lokiente-provision-options-*'){throw 'Unsafe cleanup'}
    if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
