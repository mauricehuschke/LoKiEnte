#requires -Version 7.4
param([string]$SourceRoot=(Split-Path -Parent $PSScriptRoot))
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $SourceRoot 'AcceptancePolicy.ps1')
$root=Join-Path ([IO.Path]::GetTempPath()) ('shadow-acceptance-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
$script:count=0
function Assert-True($Value,[string]$Message){if(-not $Value){throw $Message};$script:count++}
function Reject([scriptblock]$Action,[string]$Message){$rejected=$false;try{& $Action | Out-Null}catch{$rejected=$true};Assert-True $rejected $Message}
function Json-Report([string]$Text){$path=Join-Path $root 'report.json';[IO.File]::WriteAllText($path,$Text);Read-ShadowTestReport $path json}
function Xml-Report([string]$Text){$path=Join-Path $root 'report.xml';[IO.File]::WriteAllText($path,$Text);Read-ShadowTestReport $path junit}
try{
    $check=@{name='unit';kind='test';reportFormat='json'}
    $policy=@{schemaVersion=2;changeTypes=@('other');acceptanceCriteria=@(@{id='AC-1';description='Reject invalid input'})}
    Assert-ShadowAcceptanceContract $policy @($check)
    $plan=ConvertFrom-ShadowAcceptancePlan '{"criteria":[{"id":"AC-1","tests":[{"check":"unit","testId":"reject"}]}],"expectedFailures":[]}' $policy.acceptanceCriteria @($check) Feature ''
    Assert-True ($plan.criteria.Count -eq 1) 'Valid mapping rejected'
    Reject {ConvertFrom-ShadowAcceptancePlan '{"criteria":[],"expectedFailures":[]}' $policy.acceptanceCriteria @($check) Feature ''} 'Missing criterion accepted'
    Reject {ConvertFrom-ShadowAcceptancePlan '{"criteria":[{"id":"AC-2","tests":[{"check":"unit","testId":"reject"}]}],"expectedFailures":[]}' $policy.acceptanceCriteria @($check) Feature ''} 'Foreign criterion accepted'
    Reject {ConvertFrom-ShadowAcceptancePlan '{"criteria":[{"id":"AC-1","tests":[{"check":"missing","testId":"reject"}]}],"expectedFailures":[]}' $policy.acceptanceCriteria @($check) Feature ''} 'Unknown check accepted'
    Reject {ConvertFrom-ShadowAcceptancePlan '{"criteria":[{"id":"AC-1","tests":[{"check":"unit","testId":"reject"}]}],"expectedFailures":[]}' $policy.acceptanceCriteria @($check) Bugfix unit} 'Bugfix without failing case accepted'
    $report=Json-Report '{"schemaVersion":1,"tests":[{"id":"reject","status":"passed"},{"id":"optional","status":"skipped"}]}'
    Assert-True ($report.Passed -eq 1 -and $report.Skipped -eq 1) 'JSON counts incorrect'
    $result=[pscustomobject]@{Name='unit';Kind='test';ExitCode=0;TimedOut=$false;Report=$report;ReportError=''}
    Assert-True (@(Get-ShadowAcceptanceIssues @($result) $plan).Count -eq 0) 'Valid acceptance rejected'
    Assert-True (@(Get-ShadowAcceptanceIssues @($result) $plan -ChangeTypes @('ui')).Count -gt 0) 'UI without integration accepted'
    $result.Kind='integration'
    Assert-True (@(Get-ShadowAcceptanceIssues @($result) $plan -ChangeTypes @('ui','api')).Count -eq 0) 'Mapped integration check rejected'
    $result.Kind='test';$result.Report=Json-Report '{"schemaVersion":1,"tests":[{"id":"unrelated","status":"passed"},{"id":"reject","status":"skipped"}]}'
    Assert-True (@(Get-ShadowAcceptanceIssues @($result) $plan).Count -gt 0) 'Skipped mapped case accepted'
    $result.Report=Json-Report '{"schemaVersion":1,"tests":[{"id":"unrelated","status":"passed"}]}'
    Assert-True (@(Get-ShadowAcceptanceIssues @($result) $plan).Count -gt 0) 'Missing mapped case accepted'
    $result.Report=Json-Report '{"schemaVersion":1,"tests":[{"id":"reject","status":"failed"}]}'
    Assert-True (@(Get-ShadowAcceptanceIssues @($result) $plan).Count -gt 0) 'Failed report with zero exit accepted'
    $plan.expectedFailures=@(@{check='unit';testId='reject'});$result.ExitCode=1
    Assert-True (@(Get-ShadowAcceptanceIssues @($result) $plan -Baseline).Count -eq 0) 'Expected red baseline rejected'
    $result.Report=Json-Report '{"schemaVersion":1,"tests":[{"id":"setup-error","status":"failed"}]}'
    Assert-True (@(Get-ShadowAcceptanceIssues @($result) $plan -Baseline).Count -gt 0) 'Unrelated baseline failure accepted'
    foreach($text in @('{"schemaVersion":1,"tests":[]}','{"schemaVersion":1,"tests":[{"id":"x","status":"skipped"}]}','{"schemaVersion":1,"tests":[{"id":"x","status":"passed"},{"id":"x","status":"passed"}]}','{"schemaVersion":1,"tests":[{"id":"x","status":"unknown"}]}')){
        Reject {Json-Report $text} 'Malformed/empty/duplicate JSON report accepted'
    }
    $report=Xml-Report '<testsuites><testsuite><testcase classname="Math" name="adds"/><testcase name="future"><skipped/></testcase><testcase name="broken"><failure message="assertion"/></testcase></testsuite></testsuites>'
    Assert-True ($report.Cases[0].Id -ceq 'Math::adds' -and $report.Failed -eq 1 -and $report.Skipped -eq 1) 'JUnit parsing failed'
    foreach($text in @('<testsuite tests="100"/>','<testsuite><testcase name="x"/><testcase name="x"/></testsuite>','<testsuite failures="1"><testcase name="x"/></testsuite>','<!DOCTYPE testsuite [<!ENTITY secret SYSTEM "file:///C:/Windows/win.ini">]><testsuite><testcase name="&secret;"/></testsuite>')){
        Reject {Xml-Report $text} 'Unsafe/inconsistent JUnit accepted'
    }
    Reject {Get-ShadowChangeTypes @('other','other')} 'Duplicate change type accepted'
    Reject {Get-ShadowChangeTypes @()} 'Missing change types accepted'
    Assert-True (@(Get-ShadowPathChangeTypes @('src/auth.ts','src/view.tsx','src/api/items.ts')).Count -eq 3) 'Risk path hints incomplete'
    # Real Node test runner with its built-in JUnit reporter, not synthetic XML.
    $fixture=Join-Path $root 'actual.test.cjs';$output=Join-Path $root 'actual.xml'
    [IO.File]::WriteAllText($fixture,"const {test}=require('node:test'); const assert=require('node:assert/strict'); test('adds',()=>assert.equal(1+1,2));")
    & node --test --test-reporter=junit "--test-reporter-destination=$output" $fixture
    if($LASTEXITCODE -ne 0){throw 'Real Node test failed'}
    $report=Read-ShadowTestReport $output junit
    Assert-True ($report.Passed -ge 1 -and @($report.Cases | Where-Object {$_.Id -match 'adds$'}).Count -eq 1) 'Real Node JUnit not accepted'
    [pscustomobject]@{suite='Acceptance contract and structured results';passed=$true;checks=$script:count}|ConvertTo-Json
}finally{
    $resolved=[IO.Path]::GetFullPath($root)
    if(-not $resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notlike 'shadow-acceptance-*'){throw 'Unsafe test cleanup path'}
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
