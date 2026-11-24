#requires -Version 7.4
param([string]$SourceRoot=(Split-Path -Parent $PSScriptRoot),[string]$FixtureBase=[IO.Path]::GetTempPath(),[switch]$AdditionalOnly)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
foreach($file in @('Common.ps1','AgentTemplates.ps1','GateCore.ps1','WorkflowPolicy.ps1')){. (Join-Path $SourceRoot $file)}
$root=Join-Path $FixtureBase ('shadow-quality-'+[guid]::NewGuid().ToString('N'))
$project=Join-Path $root 'project'
[void][IO.Directory]::CreateDirectory((Join-Path $project 'tests'))
$script:count=0
function Assert-True($Value,[string]$Message){if(-not $Value){throw $Message};$script:count++}
try{
    $git=(Get-Command git -CommandType Application | Select-Object -First 1).Source
    $node=(Get-Command node -CommandType Application | Select-Object -First 1).Source
    $pwsh=(Get-Process -Id $PID).Path
    $app=Join-Path $project 'app.cjs';[IO.File]::WriteAllText($app,'module.exports=()=>1;')
    $runner=Join-Path $project 'check.cjs'
    [IO.File]::WriteAllText($runner,@'
const fs=require('node:fs');
if(process.env.SHADOW_TEST_SECRET||process.env.KILO_CONFIG_CONTENT)process.exit(7);
let status='passed';
try{require('./tests/app.test.cjs')();}catch(e){console.error(e.stack);status='failed';}
const final=require('./app.cjs')()===2,mode=process.argv[2]||'';
if(final&&mode==='missing-final')process.exit(0);
const tests=final&&mode==='empty-final'?[]:[{id:'returns-two',status:final&&mode==='skipped-final'?'skipped':status}];
fs.writeFileSync(process.env.LOKI_TEST_REPORT,JSON.stringify({schemaVersion:1,tests}));
console.log(JSON.stringify(tests));process.exit(status==='failed'?1:0);
'@)
    $null=Invoke-ShadowNative $git @('init','--quiet',$project) -Quiet
    $null=Invoke-ShadowNative $git @('-C',$project,'add','.') -Quiet
    $null=Invoke-ShadowNative $git @('-C',$project,'-c','user.name=Fixture','-c','user.email=fixture@example.invalid','-c','commit.gpgsign=false','-c',('core.hooksPath='+ (Join-Path $root 'empty-hooks')),'commit','--quiet','-m','synthetic fixture') -Quiet
    $catalog=[ordered]@{'coder-high'=@{id='shadow-coder-high';name='High';context=32768;output=8192};'coder-fast'=@{id='shadow-coder-fast';name='Fast';context=32768;output=8192};review=@{id='shadow-review';name='Review';context=32768;output=8192}}
    $null=New-ShadowAgentConfiguration -InstallRoot $root -ModelCatalog $catalog -ApiBaseUrl 'http://127.0.0.1:1235/v1'
    $task=Join-Path $root 'task.md';[IO.File]::WriteAllText($task,'AC-1: app must return two. Preserve user work.')
    $checks=Join-Path $root 'checks.json';$fake=Join-Path $root 'fake-kilo.mjs'
    [IO.File]::WriteAllText($fake,@'
import fs from 'node:fs';import path from 'node:path';import {randomUUID} from 'node:crypto';
const args=process.argv.slice(2),config=JSON.parse(process.env.KILO_CONFIG_CONTENT);
if(args[0]==='debug'&&args[1]==='config'){process.stdout.write(JSON.stringify(config));process.exit(0);}
if(args[0]!=='run')process.exit(2);
const get=k=>args[args.indexOf(k)+1],role=get('--agent'),model=get('--model'),project=get('--dir'),mode=process.env.SHADOW_TEST_MODE||'';
fs.appendFileSync(process.env.SHADOW_TEST_CALLS,JSON.stringify({role,model})+'\n');
if(args.includes('--file'))throw new Error('Managed prompts must not require external file access');
const prompt=fs.readFileSync(0,'utf8');
if(!prompt.trim())throw new Error('Workflow role received an empty prompt');
const generated=mode==='auto-generated',checkName=generated?'loki-node-test':'unit',testId=generated?'test::returns-two':'returns-two';
let text=JSON.stringify({summary:'Return two, preserve architecture.',changeTypes:['other']});
if(role==='shadow-architect'){
 const scope=JSON.parse(/^PROJECT SCOPE: (.+)$/m.exec(prompt)?.[1]??'null');
 if(!scope || !Array.isArray(scope.rootGuides))throw Error('Missing planning scope');
 for(const doc of ['AGENTS.md','README.md'])if(scope.rootGuides.includes(doc)!==fs.existsSync(path.join(project,doc)))throw Error('Incorrect listed project guide');
 if(mode==='arch-read-error')console.log(JSON.stringify({type:'tool_use',part:{state:{status:'error',error:'Unable to read the requested file'}}}));
 if(prompt.includes('Read AGENTS.md,') || (scope.productionFiles.length && !scope.productionFiles.includes('app.cjs')))throw Error('Unbounded planning prompt');
}
if(role==='shadow-preparer'){
 if(process.env.LOKI_WORKFLOW_CHILD!=='1'||config.agent[role].permission.loki_start!=='deny')process.exit(5);
 text=JSON.stringify(mode==='prep-needs-input'?{needsInput:'What behavior is expected?'}:{workflow:'Bugfix',acceptanceCriteria:[{id:'AC-1',description:'App returns two'}],changeTypes:['other'],writePaths:['app.cjs'],testWritePaths:['tests/app.test.cjs'],checkIds:[generated?'loki-node-test':'existing:unit'],regressionCheckId:generated?'loki-node-test':'existing:unit'});
 if(mode==='prep-malformed' || (mode==='prep-retry' && !prompt.includes('FORMAT RETRY:')))text='{"workflow" "Bugfix"}';
 if(mode==='prep-outside')fs.writeFileSync(path.join(project,'app.cjs'),'module.exports=()=>3;');
}
if(role==='shadow-test'){
 const p=config.agent[role].permission;
 if(p.edit['*']!=='deny'||p.bash!=='deny'||p.task!=='deny')process.exit(5);
 if(p.edit['tests/app.test.cjs']==='allow'){
  if(Object.keys(p.edit).length!==2)process.exit(5);
  fs.writeFileSync(path.join(project,'tests/app.test.cjs'),generated?"require('node:test')('returns-two',()=>require('node:assert/strict').equal(require('../app.cjs')(),2));":"module.exports=()=>require('node:assert/strict').equal(require('../app.cjs')(),2);");
 }else if(Object.keys(p.edit).length!==1)process.exit(5);
 if(mode==='author-outside')fs.writeFileSync(path.join(project,'app.cjs'),'module.exports=()=>3;');
 const expectedFailures=mode==='green'?[]:[{check:checkName,testId}];
 text=JSON.stringify({criteria:[{id:mode==='missing-criterion'?'AC-2':'AC-1',tests:[{check:checkName,testId}]}],expectedFailures});
}
if(role==='shadow-implementer'){
 const p=config.agent[role].permission.edit;
 if(p['*']!=='deny'||p['app.cjs']!=='allow'||Object.keys(p).length!==2||config.agent['shadow-test'].permission.edit!=='deny')process.exit(5);
 fs.writeFileSync(path.join(project,'app.cjs'),'module.exports=()=>2;');
 if(mode==='implement-test-edit')fs.appendFileSync(path.join(project,'tests/app.test.cjs'),'\n// unauthorized');
 if(mode==='implement-outside')fs.writeFileSync(path.join(project,'outside.txt'),'unexpected');
 text='Implemented production code only.';
}
const roles={'shadow-preparation-reviewer':'preparation-reviewer','shadow-test-reviewer':'test-reviewer','shadow-reviewer':'reviewer','shadow-validator':'validator','shadow-security':'security','shadow-integration':'integration'};
if(roles[role]){
 if(config.agent[role].permission.edit!=='deny'||config.agent[role].permission.bash!=='deny')process.exit(5);
 const fingerprint=/SOURCE FINGERPRINT: ([0-9a-f]{64})/.exec(prompt)?.[1];if(!fingerprint)process.exit(3);
 const prior=fs.readFileSync(process.env.SHADOW_TEST_CALLS,'utf8').trim().split('\n').map(JSON.parse).filter(x=>x.role===role).length;
 const failed=(mode==='prep-review-fail'&&role==='shadow-preparation-reviewer')||(mode==='test-review-fail'&&role==='shadow-test-reviewer')||(mode==='security-fail'&&role==='shadow-security')||(mode==='integration-fail'&&role==='shadow-integration')||(mode==='correct-once'&&role==='shadow-reviewer'&&prior===1);
 const verdict={schema_version:1,role:roles[role],verdict:failed?'FAIL':'PASS',source_fingerprint:fingerprint,findings:failed?['Synthetic concrete finding']:[],summary:'Read fixtures; synthetic assessment.'};
 if(role==='shadow-reviewer')verdict.change_types=mode==='reviewer-risk'?['security','ui']:['other'];
 if(role==='shadow-validator')verdict.checks_seen=[checkName];text=JSON.stringify(verdict);
}
process.stdout.write(JSON.stringify({type:'text',sessionID:mode==='reused-session'?'same-session':randomUUID(),part:{text}})+'\n');
'@)
    $script:calls=''
    function Invoke-FixtureRun([string]$Mode='', [string]$Profile='High', [string[]]$Types=@('other'), [string]$Kind='test', [string]$ReportMode='', [switch]$AlreadyFixed, [switch]$NoCriteria,[string]$Workflow='Bugfix',[int]$Corrections=0,[switch]$NoChecks,[switch]$Auto){
        Write-Host "Fixture: $Mode / $Profile / $($Types -join ',') / $ReportMode"
        [IO.File]::WriteAllText($app, $(if($AlreadyFixed){'module.exports=()=>2;'}else{'module.exports=()=>1;'}))
        $policy=[ordered]@{schemaVersion=2;writePaths=@('app.cjs');testWritePaths=@('tests/app.test.cjs');changeTypes=$Types;regressionCheck='unit';acceptanceCriteria=@(@{id='AC-1';description='App returns two'});checks=@(@{name='unit';kind=$Kind;reportFormat='json';command=$node;arguments=@($runner,$ReportMode);timeoutSeconds=30})}
        if($NoCriteria){$policy.acceptanceCriteria=@()}
        if($NoChecks){$policy.checks=@()}
        [IO.File]::WriteAllText($checks,($policy|ConvertTo-Json -Depth 10))
        $script:checksBefore=(Get-FileHash -LiteralPath $checks).Hash
        if($Mode -ceq 'auto-generated'){Remove-Item -LiteralPath $checks}
        $extra=@();if($Auto){$extra=@('-AutoPrepare','-RequestId','11111111-2222-4333-8444-555555555555')}
        $script:calls=Join-Path $root ('calls-'+[guid]::NewGuid().ToString('N')+'.jsonl')
        $result=Invoke-ShadowNative -FilePath $pwsh -ArgumentList (@('-NoProfile','-NonInteractive','-File',(Join-Path $SourceRoot 'Invoke-ReviewedTask.ps1'),'-InstallRoot',$root,'-ProjectPath',$project,'-TaskFile',$task,'-ChecksFile',$checks,'-Workflow',$Workflow,'-CoderProfile',$Profile,'-MaxCorrectionRounds',[string]$Corrections,'-KiloExecutable',$node,'-KiloArgumentPrefix',$fake)+$extra) -Environment @{SHADOW_TEST_CALLS=$script:calls;SHADOW_TEST_MODE=$Mode;SHADOW_TEST_SECRET='synthetic'} -AllowFailure -Quiet -TimeoutSeconds 180
        $path=($result.StdOut -split '\r?\n' | Where-Object {$_ -like 'Verification report: *'}) -replace '^Verification report: ',''
        if(-not $path){throw "Fixture did not emit receipt: $($result.StdOut) $($result.StdErr)"}
        $receipt=Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        if($receipt.status -ceq 'VERIFIED' -and $result.ExitCode -ne 0){throw 'VERIFIED with failing exit'}
        return $receipt
    }
    if(-not $AdditionalOnly){
    foreach($profile in @('High','Fast')){
        $receipt=Invoke-FixtureRun -Profile $profile
        Assert-True ($receipt.status -ceq 'VERIFIED') "Valid $profile failed: $($receipt.error)"
        $events=@(Get-Content -LiteralPath $script:calls | ConvertFrom-Json)
        Assert-True (($events.role -join ',') -ceq 'shadow-architect,shadow-test,shadow-test-reviewer,shadow-implementer,shadow-reviewer,shadow-validator') 'Incorrect sequence'
        $expected=if($profile -eq 'High'){'lmstudio/coder-high'}else{'lmstudio/coder-fast'}
        Assert-True (($events | Where-Object role -CEQ 'shadow-implementer').model -ceq $expected) 'Wrong model'
        Assert-True ($receipt.baseline_checks[0].Report.Failed -eq 1 -and $receipt.rounds[0].checks[0].Report.Passed -eq 1) 'No real red/green evidence'
        Assert-True ($receipt.test_review.Verdict.role -ceq 'test-reviewer' -and $receipt.frozen_test_hashes.'tests/app.test.cjs') 'No test review/freeze'
    }
    $receipt=Invoke-FixtureRun -Types @('security','api') -Kind integration
    Assert-True ($receipt.status -ceq 'VERIFIED' -and $receipt.rounds[0].specialists.security.Valid -and $receipt.rounds[0].specialists.integration.Valid) "Specialists failed: $($receipt.error)"
    $receipt=Invoke-FixtureRun -Mode reviewer-risk -Kind integration
    Assert-True ($receipt.status -ceq 'VERIFIED' -and $receipt.rounds[0].specialists.security.Valid -and $receipt.rounds[0].specialists.integration.Valid) 'Reviewer escalation ignored'
    foreach($mode in @('security-fail','integration-fail')){
        $receipt=Invoke-FixtureRun -Mode $mode -Types @('security','ui') -Kind integration
        Assert-True ($receipt.status -ceq 'NOT_VERIFIED' -and $receipt.rounds[0].reasons -match 'Required verification') "$mode did not block"
    }
    $receipt=Invoke-FixtureRun -Types @('ui');Assert-True ($receipt.error -match 'integration check') 'Missing integration allowed'
    foreach($mode in @('author-outside','implement-test-edit','implement-outside')){
        $receipt=Invoke-FixtureRun -Mode $mode
        Assert-True ($receipt.error -match 'outside the allowed write scope|Test file changed') "$mode not rejected: $($receipt.error)"
        if(Test-Path -LiteralPath (Join-Path $project 'outside.txt')){Remove-Item -LiteralPath (Join-Path $project 'outside.txt')}
    }
    foreach($mode in @('test-review-fail','missing-criterion','reused-session')){
        $receipt=Invoke-FixtureRun -Mode $mode;Assert-True ($receipt.status -ceq 'NOT_VERIFIED') "$mode passed"
        $events=@(Get-Content -LiteralPath $script:calls | ConvertFrom-Json)
        Assert-True ($events.role -notcontains 'shadow-implementer') "$mode did not stop implementation"
    }
    foreach($mode in @('empty-final','missing-final','skipped-final')){
        $receipt=Invoke-FixtureRun -ReportMode $mode
        Assert-True ($receipt.status -ceq 'NOT_VERIFIED' -and $receipt.rounds[0].reasons.Count -gt 0) "$mode passed"
    }
    $receipt=Invoke-FixtureRun -AlreadyFixed;Assert-True ($receipt.error -match 'not reproduced as planned') 'Already green baseline accepted'
    $receipt=Invoke-FixtureRun -NoCriteria;Assert-True ($receipt.error -match 'acceptanceCriteria' -and -not(Test-Path -LiteralPath $script:calls)) 'Missing criteria accepted'
    $lock=Enter-ShadowProjectRun $project
    try{$receipt=Invoke-FixtureRun;Assert-True ($receipt.error -match 'locked' -and -not(Test-Path -LiteralPath $script:calls)) 'Concurrent run accepted'}finally{$lock.Dispose()}
    }
    $receipt=Invoke-FixtureRun -Workflow Feature
    Assert-True ($receipt.status -ceq 'VERIFIED') "Feature failed: $($receipt.error)"
    foreach($workflow in @('Refactor','Review')){
        $receipt=Invoke-FixtureRun -Mode green -Workflow $workflow -AlreadyFixed
        Assert-True ($receipt.status -ceq 'VERIFIED') "$workflow failed: $($receipt.error)"
    }
    $receipt=Invoke-FixtureRun -Mode green -Workflow Architecture -AlreadyFixed -NoChecks
    Assert-True ($receipt.status -ceq 'REVIEWED_UNVALIDATED') "Architecture without checks incorrectly certified: $($receipt.error)"
    $receipt=Invoke-FixtureRun -Mode correct-once -Corrections 1
    Assert-True ($receipt.status -ceq 'VERIFIED' -and $receipt.rounds.Count -eq 2 -and $receipt.rounds[0].status -ceq 'NOT_VERIFIED') "Correction round failed: $($receipt.error)"
    foreach($mode in @('auto-existing','auto-generated')){
        $receipt=Invoke-FixtureRun -Mode $mode -Auto -Workflow Auto
        Assert-True ($receipt.status -ceq 'VERIFIED') "Auto preparation $mode failed: $($receipt.error)"
        $events=@(Get-Content -LiteralPath $script:calls | ConvertFrom-Json)
        Assert-True (($events.role -join ',') -ceq 'shadow-preparer,shadow-preparation-reviewer,shadow-architect,shadow-test,shadow-test-reviewer,shadow-implementer,shadow-reviewer,shadow-validator') 'Preparation is not independently reviewed before tests/implementation'
        Assert-True ($receipt.request_id -ceq '11111111-2222-4333-8444-555555555555' -and $receipt.preparation_review.Valid) 'Missing request correlation/preparation verdict'
        $saved=Get-Content -LiteralPath $checks -Raw | ConvertFrom-Json -AsHashtable
        Assert-True ($saved.automation.owner -ceq 'LoKi task preparation v1' -and $saved.acceptanceCriteria[0].id -ceq 'AC-1') 'Prepared policy not saved'
        $progress=Get-Content -LiteralPath (Join-Path $root ('runs/'+$receipt.run_id+'/workflow-events.jsonl')) | ConvertFrom-Json
        Assert-True (@($progress | Where-Object {$_.role -ceq 'shadow-preparation-reviewer' -and $_.state -ceq 'passed'}).Count -eq 1 -and $progress[-1].state -ceq 'finished') 'Missing structured progress/result'
    }
    $failedRead=Invoke-FixtureRun -Mode 'arch-read-error' -Workflow Feature
    Assert-True ($failedRead.status -ceq 'NOT_VERIFIED' -and $failedRead.error -like '*00-plan*') 'A real architecture tool error was ignored'
    [IO.File]::WriteAllText((Join-Path $project 'AGENTS.md'),'Use only the scoped files.')
    [IO.File]::WriteAllText((Join-Path $project 'README.md'),'Local fixture instructions.')
    $retry=Invoke-FixtureRun -Mode 'prep-retry' -Auto -Workflow Auto
    Assert-True ($retry.status -ceq 'VERIFIED' -and $retry.preparation_review.Valid) 'Recovered contract bypassed independent review or failed the workflow'
    $roles=@((Get-Content -LiteralPath $script:calls | ConvertFrom-Json).role)
    Assert-True (($roles[0..2] -join ',') -ceq 'shadow-preparer,shadow-preparer,shadow-preparation-reviewer') 'Format recovery did not run as fresh preparation before review'
    $history=Get-Content -LiteralPath (Join-Path $root ('runs/'+$retry.run_id+'/workflow-events.jsonl')) | ConvertFrom-Json
    $first=@($history | Where-Object phase -ceq '00-prepare')[-1]
    $second=@($history | Where-Object phase -ceq '00-prepare-retry')[-1]
    Assert-True ($first.state -ceq 'failed' -and $second.state -ceq 'passed') 'Live report must preserve the failed attempt and credit the accepted retry'
    $invalid=Invoke-FixtureRun -Mode 'prep-malformed' -Auto -Workflow Auto
    Assert-True ($invalid.status -ceq 'NOT_VERIFIED' -and $invalid.error -like '*twice*') 'Repeated malformed output must stop'
    $roles=@((Get-Content -LiteralPath $script:calls | ConvertFrom-Json).role)
    Assert-True (($roles -join ',') -ceq 'shadow-preparer,shadow-preparer' -and (Get-FileHash -LiteralPath $checks).Hash -ceq $script:checksBefore) 'Rejected preparation continued or overwrote user policy'
    foreach($mode in @('prep-review-fail','prep-needs-input','prep-outside')){
        $receipt=Invoke-FixtureRun -Mode $mode -Auto -Workflow Auto
        Assert-True ($receipt.status -ceq 'NOT_VERIFIED') "$mode unexpectedly verified"
        Assert-True ((Get-FileHash -LiteralPath $checks).Hash -ceq $script:checksBefore) "$mode overwrote checks.json before approval"
        $events=@(Get-Content -LiteralPath $script:calls | ConvertFrom-Json)
        Assert-True ($events.role -notcontains 'shadow-test' -and $events.role -notcontains 'shadow-implementer') "$mode did not stop execution"
    }
    [pscustomobject]@{suite='Reviewed workflow with automatic preparation and independent test author';passed=$true;checks=$script:count;limitations='Real Git, processes and assertions; agent responses are synthetic.'}|ConvertTo-Json
}finally{
    $resolved=[IO.Path]::GetFullPath($root)
    if(-not $resolved.StartsWith([IO.Path]::GetFullPath($FixtureBase).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notlike 'shadow-quality-*'){throw 'Unsafe cleanup path'}
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
