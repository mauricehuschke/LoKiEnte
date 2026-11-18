#requires -Version 7.4
[CmdletBinding()]
param([string]$SourceRoot=(Split-Path -Parent $PSScriptRoot))
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $SourceRoot 'Common.ps1')
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $SourceRoot 'Setup.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Setup syntax errors'}
foreach($name in @('Test-ShadowKiloEntry','Install-ShadowKilo')){
    $definition=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq $name},$false)
    if($null -eq $definition){throw "Missing helper: $name"}
    . ([scriptblock]::Create($definition.Extent.Text))
}
$checks=0
function Assert-Kilo([bool]$Condition,[string]$Description){
    if(-not $Condition){throw "FAIL: $Description"}
    $script:checks++
}
$engine=(Get-Command node.exe -CommandType Application|Select-Object -First 1).Source
$real=[ordered]@{
    kiloExecutable=$engine
    kiloArgumentPrefix=@('-e','process.stderr.write("--format --agent --dir")')
    kiloVersion='fixture'
}
Assert-Kilo (Test-ShadowKiloEntry $real) 'Real redirected process with help on stderr passes'
$script:output=[pscustomobject]@{ExitCode=0;StdOut='';StdErr=''}
$script:calls=0
function Invoke-ShadowNative {
    param($FilePath,$ArgumentList,$Environment,[switch]$AllowFailure,[switch]$Quiet,$TimeoutSeconds)
    $script:calls++
    if(($ArgumentList -join ' ') -cne 'entry run --help'){throw 'Unexpected native call; npm must not be invoked'}
    return $script:output
}
$entry=[ordered]@{kiloExecutable='node.exe';kiloArgumentPrefix=@('entry');kiloVersion='7.8.27'}
foreach($case in @(
    @{out='--format --agent --dir';err='';exit=0;expected=$true},
    @{out='';err='--format --agent --dir';exit=0;expected=$true},
    @{out='--format';err='--agent --dir';exit=0;expected=$true},
    @{out='--format --agent';err='';exit=0;expected=$false},
    @{out='--format --agent --dir';err='';exit=1;expected=$false},
    @{out='--format-extra --agent --dir';err='';exit=0;expected=$false}
)){
    $script:output=[pscustomobject]@{ExitCode=$case.exit;StdOut=$case.out;StdErr=$case.err}
    Assert-Kilo ((Test-ShadowKiloEntry $entry) -eq $case.expected) 'Output channel, exit code and exact option names are respected'
}
$script:output=[pscustomobject]@{ExitCode=0;StdOut='';StdErr='--format --agent --dir'}
function Get-ShadowKiloEntry {param($PackageRoot,$NodePath) return $entry}
$script:calls=0
$reused=Install-ShadowKilo -NodePath 'node.exe' -NpmEntry 'npm-cli.js' -Root 'C:\synthetic'
Assert-Kilo ($reused.kiloVersion -ceq '7.8.27' -and $script:calls -eq 1) 'Previously installed valid CLI is reused without npm or reinstall'
[pscustomobject]@{suite='Kilo help output';passed=$true;checks=$checks}|ConvertTo-Json
