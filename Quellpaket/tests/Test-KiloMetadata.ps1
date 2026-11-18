#requires -Version 7.4
[CmdletBinding()]
param([string]$SourceRoot=(Split-Path -Parent $PSScriptRoot))
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $SourceRoot 'Runtime.ps1')
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $SourceRoot 'Setup.ps1'),[ref]$tokens,[ref]$errors)
foreach($definition in $ast.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst]},$false)){
    . ([scriptblock]::Create($definition.Extent.Text))
}
$count=0
foreach($json in @('"7.8.27"','["7.8.27"]','{"version":"7.8.27"}','[{"version":"7.8.27","engines":{"node":">=20"}}]')){
    if((ConvertFrom-ShadowKiloMetadata $json) -cne '7.8.27'){throw "Wrong version: $json"}
    $count++
}
if((ConvertFrom-ShadowKiloMetadata '"1.2.3-rc.1+build.4"') -cne '1.2.3-rc.1+build.4'){throw 'Prerelease/build version rejected'}
$count++
foreach($json in @('','not json','{}','null','[]','["1.2.3","1.2.4"]','{"version":123}','"latest"','"1.2.3 --global"','[["1.2.3"]]')){
    $failed=$false
    try{$null=ConvertFrom-ShadowKiloMetadata $json}catch{$failed=$true}
    if(-not $failed){throw "Invalid metadata accepted: $json"}
    $count++
}
$script:argumentsSeen=@()
function Get-ShadowKiloEntry {param($PackageRoot,$NodePath);return $null}
function Invoke-ShadowNative {
    param($FilePath,$ArgumentList,[switch]$Quiet,$TimeoutSeconds)
    $script:argumentsSeen=$ArgumentList
    return [pscustomobject]@{StdOut='["1.2.3","1.2.4"]'}
}
$root=Join-Path ([IO.Path]::GetTempPath()) ('shadow-metadata-'+[guid]::NewGuid().ToString('N'))
try{
    $failed=$false
    try{$null=Install-ShadowKilo -NodePath 'mock.exe' -NpmEntry 'npm-cli.js' -Root $root}catch{$failed=$true}
    if(-not $failed -or (Test-Path -LiteralPath $root)){throw 'Ambiguous metadata caused installation writes'}
    if($script:argumentsSeen -contains 'engines' -or $script:argumentsSeen -notcontains 'version'){throw 'npm metadata request was not reduced to version'}
    $count+=2
}finally{
    if(Test-Path -LiteralPath $root){Remove-Item -LiteralPath $root -Recurse -Force}
}
[pscustomobject]@{suite='Kilo metadata';passed=$true;checks=$count}|ConvertTo-Json
