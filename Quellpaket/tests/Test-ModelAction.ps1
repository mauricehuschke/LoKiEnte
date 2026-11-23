#requires -Version 5.1
param([string]$Bootstrap=(Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'Provision-LoKiEnte.ps1'))
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$tokens=$null; $errors=$null
$tree=[Management.Automation.Language.Parser]::ParseFile($Bootstrap,[ref]$tokens,[ref]$errors)
if ($errors) {throw $errors[0]}
foreach ($name in 'Select-BootstrapModelAction','Assert-BootstrapNoReparsePoint') {
    $def=$tree.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$false)
    . ([scriptblock]::Create($def.Extent.Text))
}
$root=Join-Path ([IO.Path]::GetTempPath()) ('lokiente-model-action-'+[guid]::NewGuid())
function Read-Host {param($Prompt) $script:prompts++;return $script:answer}
$script:prompts=0
$script:answer=''
try {
    [void][IO.Directory]::CreateDirectory((Join-Path $root 'runtime'))
    if ((Select-BootstrapModelAction $root '' @{} @{}).Action -ne 'Configure' -or $script:prompts){throw 'Fresh provisioning must configure'}
    $old=@{ModelMode='Dual';IncludeFastModel=$true}
    [IO.File]::WriteAllText((Join-Path $root 'toolchain.json'),'{"modelMode":"Dual","indexingMode":"OnDemand"}')
    [IO.File]::WriteAllText((Join-Path $root 'runtime/model-pool.json'),'{"Status":"Ready"}')
    $choice=Select-BootstrapModelAction $root '' $old @{IncludeFastModel=[switch]$true}
    if ($choice.Action -ne 'Keep' -or $choice.IndexingMode -ne 'OnDemand' -or $script:prompts -ne 1){throw 'Matching options must offer Keep and preserve indexing'}
    $script:answer='2'
    if ((Select-BootstrapModelAction $root '' $old @{}).Action -ne 'Configure'){throw 'Menu did not select maintenance'}
    $count=$script:prompts
    if ((Select-BootstrapModelAction $root 'Keep' $old @{}).Action -ne 'Keep' -or $script:prompts -ne $count){throw 'Explicit keep prompted'}
    if ((Select-BootstrapModelAction $root '' $old @{ModelMode='Single'}).Action -ne 'Configure'){throw 'Ignored a model mode change'}
    if ((Select-BootstrapModelAction $root '' $old @{} -Copying).Action -ne 'Configure'){throw 'Migration must reconfigure'}
    $rejected=$false
    try {$null=Select-BootstrapModelAction $root 'Keep' $old @{IndexingMode='Off'}}catch{$rejected=$true}
    if (!$rejected){throw 'Keep silently applied a different indexing policy'}
    'PASS: model maintenance selection, default, migration and conflicts.'
}finally{
    $expected=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
    if(![IO.Path]::GetFullPath($root).StartsWith($expected) -or [IO.Path]::GetFileName($root) -notlike 'lokiente-model-action-*'){throw 'Unexpected fixture'}
    [IO.Directory]::Delete($root,$true)
}
