#requires -Version 7.4
param([string]$SourceRoot=(Split-Path -Parent $PSScriptRoot))
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $SourceRoot 'GateCore.ps1')
. (Join-Path $SourceRoot 'WorkflowProgress.ps1')
$root=Join-Path ([IO.Path]::GetTempPath()) ('shadow-progress-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
$count=0
function Assert($Condition,$Message){if(-not $Condition){throw $Message};$script:count++}
try{
    $node=(Get-Command node -CommandType Application | Select-Object -First 1).Source
    $script=Join-Path $root 'child.cjs';$marker=Join-Path $root 'marker';$pidFile=Join-Path $root 'child.pid'
    [IO.File]::WriteAllText($script,@'
const fs=require('node:fs');const [marker,pid,mode]=process.argv.slice(2);fs.writeFileSync(pid,String(process.pid));
if(mode==='echo'){process.stdout.write(fs.readFileSync(0));return;}
if(mode==='wait'){setInterval(()=>{},1000);return;}
process.stderr.write('x'.repeat(128*1024)+'\n');console.log('first');
const timer=setTimeout(()=>process.exit(9),5000);
const poll=setInterval(()=>{if(fs.existsSync(marker)){clearTimeout(timer);clearInterval(poll);console.log('last');}},20);
'@)
    $payload=("Unicode Grüße 🦆 and quotes ' --file"+"`n")*2500
    $result=Invoke-ShadowNativeProcess -FilePath $node -ArgumentList @($script,$marker,$pidFile,'echo') -WorkingDirectory $root -StandardInputText $payload -StdoutPath (Join-Path $root 'out') -StderrPath (Join-Path $root 'err') -TimeoutSeconds 20
    Assert ($result.ExitCode -eq 0 -and [IO.File]::ReadAllText((Join-Path $root 'out')).Replace("`r`n","`n") -ceq $payload) 'Large multiline UTF-8 stdin did not arrive intact'
    $result=Invoke-ShadowNativeProcess -FilePath $node -ArgumentList @($script,$marker,$pidFile,'stream') -WorkingDirectory $root -StdoutPath (Join-Path $root 'out') -StderrPath (Join-Path $root 'err') -TimeoutSeconds 10 -OnStdoutLine {
        param($line)
        if($line -ceq 'first'){[IO.File]::WriteAllText($marker,'callback before exit')}
    }
    Assert ($result.ExitCode -eq 0 -and [IO.File]::ReadAllText((Join-Path $root 'out')).Contains('last')) 'Stdout callback was not delivered before child exit'
    Assert ((Get-Item -LiteralPath (Join-Path $root 'err')).Length -gt 128000) 'Stderr was not concurrently drained'
    $result=Invoke-ShadowNativeProcess -FilePath $node -ArgumentList @($script,$marker,$pidFile,'wait') -WorkingDirectory $root -StdoutPath (Join-Path $root 'out') -StderrPath (Join-Path $root 'err') -TimeoutSeconds 1 -StandardInputText $payload -OnStdoutLine {param($line)}
    Assert ($result.TimedOut -and $result.ExitCode -eq 124) 'Streaming timeout missing'
    $childId=[int][IO.File]::ReadAllText($pidFile)
    Assert (-not(Get-Process -Id $childId -ErrorAction SilentlyContinue)) 'Timed-out own child still running'
    $failed=$false
    try{$null=Invoke-ShadowNativeProcess -FilePath $node -ArgumentList @($script,$marker,$pidFile,'stream') -WorkingDirectory $root -StdoutPath (Join-Path $root 'out') -StderrPath (Join-Path $root 'err') -TimeoutSeconds 10 -OnStdoutLine {param($line);throw 'callback failed'}}catch{$failed=$_.Exception.Message -match 'callback failed'}
    Assert $failed 'Callback failure disappeared'
    $childId=[int][IO.File]::ReadAllText($pidFile)
    Assert (-not(Get-Process -Id $childId -ErrorAction SilentlyContinue)) 'Callback failure orphaned child'
    $run=Join-Path $root 'runs/one';$events=Join-Path $root 'workflow-jobs/one/events.jsonl'
    Initialize-ShadowWorkflowProgress -InstallRoot $root -RunPath $run -ProgressFile $events
    Write-ShadowAgentProgress -Line '{"type":"tool_use","sessionID":"session-1","part":{"tool":"read","state":{"status":"completed","input":{"password":"not-in-progress"}}}}' -Phase 'review' -Role 'shadow-reviewer' -Model 'lmstudio/review'
    $event=ConvertFrom-Json ([IO.File]::ReadAllText($events))
    Assert ($event.role -ceq 'shadow-reviewer' -and $event.tool -ceq 'read' -and $event.sessionId -ceq 'session-1') 'Progress lost role/model/tool identity'
    Assert ($event.message -ceq 'Tool: completed') 'Tool progress is not English'
    Assert (-not [IO.File]::ReadAllText($events).Contains('not-in-progress')) 'Raw tool arguments leaked into progress'
    $failed=$false;try{Initialize-ShadowWorkflowProgress -InstallRoot $root -RunPath $run -ProgressFile (Join-Path $root 'outside/events.jsonl')}catch{$failed=$true}
    Assert $failed 'Arbitrary progress path accepted'
    [pscustomobject]@{suite='Streaming workflow progress';passed=$true;checks=$count}|ConvertTo-Json
}finally{
    $resolved=[IO.Path]::GetFullPath($root)
    if(-not $resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notlike 'shadow-progress-*'){throw 'Unsafe cleanup path'}
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
