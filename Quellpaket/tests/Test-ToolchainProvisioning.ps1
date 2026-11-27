#requires -Version 7.4
# Exercises the real setup acceptance/skip/report statements with a synthetic live-run boundary.
param([string]$SourceRoot=(Split-Path -Parent $PSScriptRoot))
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $SourceRoot 'ToolchainAcceptance.ps1')
. (Join-Path $SourceRoot 'ProvisionReport.ps1')
$t=$null;$e=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $SourceRoot 'Setup.ps1'),[ref]$t,[ref]$e)
if($e.Count){throw 'Setup parse failure.'}
$main=@($ast.EndBlock.Statements|Where-Object {$_ -is [Management.Automation.Language.TryStatementAst]})[0]
$statements=@($main.Body.Statements)
$start=@(0..($statements.Count-1)|Where-Object {$statements[$_].Extent.Text.StartsWith('$acceptanceMode=')})[0]
$end=@(0..($statements.Count-1)|Where-Object {$statements[$_].Extent.Text.StartsWith('$report.finishedUtc=')})[0]-1
$actual=[scriptblock]::Create(($statements[$start..$end]|ForEach-Object {$_.Extent.Text}) -join "`n")
$root=Join-Path ([IO.Path]::GetTempPath()) ('lokiente-provision-acceptance-'+[guid]::NewGuid().ToString('N'))
$checks=0
function Assert-Provision($Value,$Message){if(-not $Value){throw $Message};$script:checks++}
function Read-Host {param($Prompt) throw 'Explicit options must not ask again.'}
function Write-ShadowMessage {param($Message,$Level)}
function Invoke-ShadowToolchainAcceptance {param($InstallRoot) $script:calls++;return @{status=$script:fixtureStatus}}
try{
    foreach($scenario in @('PASS','FAIL','BLOCKED','SKIPPED')){
        $InstallRoot=Join-Path $root $scenario
        $script:calls=0;$script:fixtureStatus=$scenario
        $RunAcceptanceTest=$scenario -ne 'SKIPPED';$SkipAcceptanceTest=$scenario -eq 'SKIPPED'
        $ModelAction='Keep';$report=[ordered]@{warnings=@()}
        . $actual
        Assert-Provision ($report.acceptance.status -ceq $scenario) 'Setup must preserve the actual verdict.'
        Assert-Provision ($script:calls -eq $(if($scenario -eq 'SKIPPED'){0}else{1})) 'Skip must never invoke live acceptance.'
        Assert-Provision ($report.status -ceq $(if($scenario -eq 'PASS'){'PROVISIONED'}else{'PROVISIONED_WITH_WARNINGS'})) 'Only a passed acceptance may finish without the unverified warning.'
        if($scenario -eq 'SKIPPED'){
            $saved=Get-Content -LiteralPath (Join-Path $InstallRoot 'diagnostics/toolchain/latest.json') -Raw|ConvertFrom-Json
            $xml=[xml](Get-Content -LiteralPath (Join-Path $InstallRoot 'diagnostics/toolchain/latest.junit.xml') -Raw)
            Assert-Provision ($saved.status -ceq 'SKIPPED' -and $xml.testsuites.testsuite.skipped -eq '1') 'JSON and JUnit must both show skipped, never a stale PASS.'
        }
    }
    @{suite='Actual provisioning acceptance and skip report integration';checks=$checks;passed=$true;limitations='Live runner is a synthetic boundary; setup statements, option policy and report files are real.'}|ConvertTo-Json
}finally{
    $resolved=[IO.Path]::GetFullPath($root)
    if(-not $resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notlike 'lokiente-provision-acceptance-*'){throw 'Unsafe cleanup'}
    if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
