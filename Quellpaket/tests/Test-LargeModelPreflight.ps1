#requires -Version 7.4
[CmdletBinding()]
param([string]$SourceRoot=(Split-Path -Parent $PSScriptRoot))
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $SourceRoot 'Runtime.ps1')
. (Join-Path $SourceRoot 'ModelSelection.ps1')
$root=Join-Path ([IO.Path]::GetTempPath()) ('shadow-large-preflight-'+[guid]::NewGuid().ToString('N'))
$modelRoot=Join-Path $root 'models'
[void][IO.Directory]::CreateDirectory($modelRoot)
$model=@(Get-ShadowModelCatalog|Where-Object {$_.Id -ceq 'qwen3-14b'})[0]
$definitions=@(@{Alias='coder';Name=$model.Name;Definition=$model})
$partial=Join-Path (Join-Path (Join-Path $root 'model-downloads') $model.Id) ($model.Files[0].Name+'.partial')
$script:partialExists=$false
$script:partialBytes=[long]0
$script:messages=[Collections.Generic.List[string]]::new()
function Resolve-ShadowModelDirectory {return $modelRoot}
function Invoke-ShadowModelDownload {param($Model,$File,$DownloadRoot) throw 'PREFLIGHT_COMPLETED'}
function Write-Host {param($Object) $script:messages.Add([string]$Object)}
function Test-Path {
    [CmdletBinding()]
    param([string]$LiteralPath,[string]$PathType)
    if($LiteralPath -ceq $partial -and $script:partialExists){return $true}
    Microsoft.PowerShell.Management\Test-Path @PSBoundParameters
}
function Get-Item {
    [CmdletBinding()]
    param([string]$LiteralPath)
    if($LiteralPath -ceq $partial -and $script:partialExists){return [pscustomobject]@{Length=$script:partialBytes}}
    Microsoft.PowerShell.Management\Get-Item @PSBoundParameters
}
try{
    $cases=@(
        @{Partial=[long]0;Exists=$false;Remaining=[long]9001753376},
        @{Partial=[long]3500000000;Exists=$true;Remaining=[long]5501753376},
        @{Partial=[long]10000000000;Exists=$true;Remaining=[long]0}
    )
    $drive=[IO.DriveInfo]::new([IO.Path]::GetPathRoot($root))
    if($drive.AvailableFreeSpace -lt [long]18003506752){throw 'Mindestens 16,77 GiB freier Testlaufwerksplatz erforderlich; es werden keine grossen Dateien erstellt.'}
    foreach($case in $cases){
        $script:partialExists=$case.Exists;$script:partialBytes=$case.Partial;$script:messages.Clear()
        $failure=$null
        try{Install-ShadowSelectedModels -Definitions $definitions -LmsPath 'fixture' -InstallRoot $root}
        catch{$failure=$_.Exception.Message}
        if($failure -cne 'PREFLIGHT_COMPLETED'){throw "Preflight did not reach the download boundary: $failure"}
        $expected="Zusaetzlicher Platzbedarf etwa: Download {0:N2} GiB; Modellkopien {1:N2} GiB." -f ($case.Remaining/1GB),([long]9001753376/1GB)
        if(-not $script:messages.Contains($expected)){throw "Incorrect exact space calculation for partial length $($case.Partial)."}
    }
    if(@(Get-ChildItem -LiteralPath $modelRoot -Force).Count -ne 0){throw 'Preflight unexpectedly wrote a model file'}
    [pscustomobject]@{suite='Large model preflight';passed=$true;checks=4}|ConvertTo-Json
}finally{Remove-Item -LiteralPath $root -Recurse -Force}
