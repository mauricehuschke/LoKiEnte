#requires -Version 7.4
# Real lifecycle functions/lock files; synthetic LM Studio command/API boundary.
param([string]$SourceRoot=(Split-Path -Parent $PSScriptRoot))
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $SourceRoot 'ModelPool.ps1')
$root=Join-Path ([IO.Path]::GetTempPath()) ('lokiente-model-reset-'+[guid]::NewGuid().ToString('N'))
$checks=0
function Assert-Reset($Value,$Message){if(-not $Value){throw $Message};$script:checks++}
function Write-ShadowMessage {param($Message,$Level)}
function Ensure-SmpServer {param($Pool,$LogDirectory) Assert-Reset ($Pool.BackendApiBaseUrl -ceq 'http://127.0.0.1:2345/v1') 'Reset must target the actual local LM Studio port.'}
function Invoke-LrJson {
    param($LmsPath,$Arguments,$LogDirectory)
    if($Arguments[0] -eq 'server'){return @{running=$true;port=2345}}
    if($Arguments[0] -eq 'ps'){return $script:loaded}
    throw 'Unexpected CLI action'
}
function Invoke-LrApi {
    param($Uri,$Headers,$Method,$Body,$TimeoutSeconds)
    Assert-Reset ($Uri -ceq 'http://127.0.0.1:2345/api/v1/models/unload' -and $Method -ceq 'POST' -and $TimeoutSeconds -eq 120) 'Unload must be a bounded targeted local REST request.'
    $script:unloads.Add([string]$Body.instance_id)
    if(-not $script:retain){$script:loaded=@($script:loaded|Where-Object {$_.identifier -cne $Body.instance_id})}
    return @{instance_id=$(if($script:wrongResponse){'other'}else{$Body.instance_id})}
}
try{
    $script:unloads=[Collections.Generic.List[string]]::new();$script:retain=$false;$script:wrongResponse=$false
    $script:loaded=@([pscustomobject]@{identifier='manually-loaded';path='synthetic/model.gguf';deviceIdentifier=$null;status='idle'})
    $owner=Get-SmpOwner -InstallRoot $root
    $pool=@{LmsPath='synthetic-lms'}
    $failure=$null;try{Get-SmpOwnedLoaded -Pool $pool -Owner $owner -LogDirectory $root}catch{$failure=$_}
    Assert-Reset ($failure -and $failure.Exception.Data['ShadowModelConflict']) 'Fresh ownership reproduces the reported foreign-model refusal.'
    $result=Reset-ShadowSetupLoadedModels -InstallRoot $root -LmsPath synthetic-lms -Port 1234 -ApiTokenEnvironmentVariable ''
    Assert-Reset ($result.status -ceq 'PASS' -and $result.unloaded.Count -eq 1 -and $result.unloaded[0] -ceq 'manually-loaded' -and $result.loadedAfter -eq 0) 'Configure must unload an already loaded manual model after local state was deleted.'
    Assert-Reset (@(Get-SmpOwnedLoaded -Pool $pool -Owner $owner -LogDirectory $root).Count -eq 0 -and $owner.Entries.Count -eq 0) 'The model is unloaded, not adopted under an invented ownership record.'
    $result=Reset-ShadowSetupLoadedModels -InstallRoot $root -LmsPath synthetic-lms -Port 1234 -ApiTokenEnvironmentVariable ''
    Assert-Reset ($result.unloaded.Count -eq 0 -and $unloads.Count -eq 1) 'An already empty server needs no unload request.'
    $script:loaded=@([pscustomobject]@{identifier='busy-local';deviceIdentifier=$null;status='busy'})
    $result=Reset-ShadowSetupLoadedModels -InstallRoot $root -LmsPath synthetic-lms -Port 1234 -ApiTokenEnvironmentVariable ''
    Assert-Reset ($result.unloaded[0] -ceq 'busy-local') 'Explicit Configure reset also unloads an active local model as requested.'
    foreach($instances in @(
        @(@{identifier='remote';deviceIdentifier='other-device'}),
        @(@{identifier='unknown'}),
        @(@{identifier='same';deviceIdentifier=$null},@{identifier='same';deviceIdentifier=$null})
    )){
        $script:loaded=@($instances);$before=$unloads.Count;$failure=$null
        try{Reset-ShadowSetupLoadedModels -InstallRoot $root -LmsPath synthetic-lms -Port 1234 -ApiTokenEnvironmentVariable ''}catch{$failure=$_}
        Assert-Reset ($failure -and $unloads.Count -eq $before) 'Nonlocal, ambiguous or duplicate identities must be rejected before any unload.'
    }
    $script:loaded=@(@{identifier='retained';deviceIdentifier=$null});$script:retain=$true;$failure=$null
    try{Reset-ShadowSetupLoadedModels -InstallRoot $root -LmsPath synthetic-lms -Port 1234 -ApiTokenEnvironmentVariable ''}catch{$failure=$_}
    Assert-Reset ($failure -and $failure.Exception.Message -match 'still reports loaded') 'A successful HTTP response alone cannot prove unloading.'
    $script:retain=$false;$script:wrongResponse=$true;$failure=$null
    try{Reset-ShadowSetupLoadedModels -InstallRoot $root -LmsPath synthetic-lms -Port 1234 -ApiTokenEnvironmentVariable ''}catch{$failure=$_}
    Assert-Reset ($failure -and $failure.Exception.Message -match 'did not confirm') 'A mismatched API instance ID must fail.'
    $source=Get-Content (Join-Path $SourceRoot 'Setup.ps1') -Raw
    Assert-Reset ($source.IndexOf('Reset-ShadowSetupLoadedModels') -lt $source.IndexOf('$selectedDefinitions=@()') -and $source.IndexOf('$selectedDefinitions=@()') -gt $source.IndexOf("} else {",$source.IndexOf("if (`$ModelAction -eq 'Keep')"))) 'Reset belongs to Configure before hardware-based model selection.'
    @{suite='Configure model reset';checks=$checks;passed=$true;limitations='Synthetic local LM Studio boundary, real ownership/lock logic. Target unload remains to be retested.'}|ConvertTo-Json
}finally{
    $resolved=[IO.Path]::GetFullPath($root);$allowed=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
    if(-not $resolved.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notlike 'lokiente-model-reset-*'){throw 'Unsafe cleanup'}
    if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
