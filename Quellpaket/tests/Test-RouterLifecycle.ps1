#requires -Version 7.4
# Real Router.ps1 + Node processes and loopback HTTP. LM lifecycle and Windows port
# inventory are boundary mocks; retry sleeps are shortened to keep tests bounded.
[CmdletBinding()]
param([string]$SourceRoot=(Split-Path -Parent $PSScriptRoot))
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $SourceRoot 'ModelPool.ps1')
. (Join-Path $SourceRoot 'Router.ps1')
$root=Join-Path ([IO.Path]::GetTempPath()) ('shadow-router-life-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory((Join-Path $root 'app'))
[void][IO.Directory]::CreateDirectory((Join-Path $root 'runtime'))
$node=(Get-Command node -CommandType Application|Select-Object -First 1).Source
$pwsh=(Get-Process -Id $PID).Path
$probe=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,0);$probe.Start();$port=([Net.IPEndPoint]$probe.LocalEndpoint).Port;$probe.Stop()
$pool=[pscustomobject]@{SchemaVersion=2;Status='Ready';OwnerId=('a'*24);PrimaryAlias='coder';BackendApiBaseUrl='http://127.0.0.1:1234/v1';RouterApiBaseUrl="http://127.0.0.1:$port/v1";ApiTokenEnvironmentVariable='SHADOW_ROUTER_LIFECYCLE_TEST_TOKEN';Profiles=@(
    [pscustomobject]@{Alias='coder';RouteId='shadow-coder';Name='Synthetic coder';InstanceId='owned-coder';ModelPath='coder.gguf';ContextLength=16384;OutputLimit=4096},
    [pscustomobject]@{Alias='review';RouteId='shadow-review';Name='Synthetic reviewer';InstanceId='owned-review';ModelPath='review.gguf';ContextLength=16384;OutputLimit=4096}
)}
$poolPath=Join-Path $root 'runtime/model-pool.json'
[IO.File]::WriteAllText($poolPath,($pool|ConvertTo-Json -Depth 15))
$fixtureStatePath=Join-Path $root 'fixture-state.json'
function Set-Fixture([hashtable]$State){[IO.File]::WriteAllText($fixtureStatePath,($State|ConvertTo-Json))}
Set-Fixture @{}
[IO.File]::WriteAllText((Join-Path $root 'app/ModelRouter.mjs'),@'
import http from 'node:http';import fs from 'node:fs';import crypto from 'node:crypto';import path from 'node:path';
const args=process.argv.slice(2),arg=name=>args[args.indexOf(name)+1];
const config=arg('--config'),pool=JSON.parse(fs.readFileSync(config,'utf8'));
const root=path.dirname(path.dirname(config));
const digest=arg('--routing-digest');
fs.writeFileSync(path.join(root,'fixture-pid.txt'),String(process.pid));
const server=http.createServer((req,res)=>{
  let state={};try{state=JSON.parse(fs.readFileSync(path.join(root,'fixture-state.json'),'utf8'));}catch{}
  const token=process.env[pool.ApiTokenEnvironmentVariable];
  if(token&&req.headers.authorization!==`Bearer ${token}`){res.writeHead(401);res.end('{}');return;}
  res.setHeader('content-type','application/json');
  if(req.url==='/health'){
    if(state.failed)res.statusCode=503;
    res.end(JSON.stringify({service:state.service||'shadow-local-model-router',version:'2026.11.17.15',ready:!state.failed&&state.ready!==false,configDigest:digest,pid:process.pid,busy:!!state.busy,queued:state.queued||0}));return;
  }
  if(req.url==='/admin/shutdown'&&req.method==='POST'){
    if(req.headers['x-shadow-control']!==process.env.SHADOW_LOCAL_ROUTER_CONTROL){res.writeHead(403);res.end('{}');return;}
    if(state.busy||state.queued){res.writeHead(409);res.end('{}');return;}
    res.end(JSON.stringify({stopping:true}));server.close(()=>process.exit(0));return;
  }
  res.writeHead(404);res.end('{}');
});
server.listen(Number(arg('--port')),'127.0.0.1');
'@)
$script:backendStarts=0;$script:occupied=$false
function Start-LocalModelPool {param($InstallRoot);$script:backendStarts++;return Get-Content -LiteralPath (Join-Path $InstallRoot 'runtime/model-pool.json') -Raw|ConvertFrom-Json}
function Get-NetTCPConnection {param($State,$LocalPort,$ErrorAction);if($script:occupied){[pscustomobject]@{LocalAddress='127.0.0.1';LocalPort=$LocalPort}}}
function Start-Sleep {param([int]$Milliseconds,[int]$Seconds);[Threading.Thread]::Sleep(50)}
$results=[Collections.Generic.List[string]]::new()
function Assert-Life([bool]$Condition,[string]$Name){if(-not $Condition){throw "FAIL: $Name"};$results.Add($Name);Write-Host "PASS: $Name"}
function Throws-Life([scriptblock]$Action,[string]$Pattern,[string]$Name){$caught=$false;try{&$Action|Out-Null}catch{$caught=$true;if($_.Exception.Message -notmatch $Pattern){throw}};Assert-Life $caught $Name}
$previous=[Environment]::GetEnvironmentVariable($pool.ApiTokenEnvironmentVariable,'Process')
[Environment]::SetEnvironmentVariable($pool.ApiTokenEnvironmentVariable,'synthetic-local-test-token','Process')
$created=[Collections.Generic.List[int]]::new()
try {
    $catalog=Get-ShadowPoolCatalog -Pool $pool
    Assert-Life ($catalog.coder.reasoning -and $catalog.review.reasoning -and $catalog.coder.interleaved -ceq 'reasoning_content' -and $catalog.review.interleaved -ceq 'reasoning') 'Known model catalog preserves model-specific reasoning metadata for the Kilo SDK'
    $bad=($pool|ConvertTo-Json -Depth 20|ConvertFrom-Json);$bad.RouterApiBaseUrl='https://example.invalid/v1'
    Throws-Life {Get-ShadowRouterHealth -Pool $bad} 'router endpoint' 'External router endpoint rejected before credentials or requests'
    $bad.RouterApiBaseUrl=$pool.BackendApiBaseUrl
    Throws-Life {Get-ShadowRouterHealth -Pool $bad} 'router endpoint' 'Backend and router ports must be distinct'
    $first=Start-ShadowModelRouter -InstallRoot $root -Pool $pool -NodePath $node -PowerShellPath $pwsh
    $created.Add($first.Pid)
    Assert-Life ($first.Status -ceq 'Ready' -and -not $first.Reused -and $script:backendStarts -eq 1) 'Initial launch starts backend once and verifies actual child PID and digest'
    Set-Fixture @{busy=$true;queued=1}
    $second=Start-ShadowModelRouter -InstallRoot $root -Pool $pool -NodePath $node -PowerShellPath $pwsh
    Assert-Life ($second.Reused -and $second.Pid -eq $first.Pid -and $script:backendStarts -eq 1) 'Live matching router is reused without a model change, even while busy'
    $pool.Profiles[0]|Add-Member -NotePropertyName Estimate -NotePropertyValue @{GpuBytes=1024}
    [IO.File]::WriteAllText($poolPath,($pool|ConvertTo-Json -Depth 15))
    $same=Start-ShadowModelRouter -InstallRoot $root -Pool $pool -NodePath $node -PowerShellPath $pwsh
    Assert-Life ($same.Reused -and $same.Pid -eq $first.Pid) 'Volatile estimate changes do not invalidate a busy router'
    $pool.Profiles[0].OutputLimit=2048
    [IO.File]::WriteAllText($poolPath,($pool|ConvertTo-Json -Depth 15))
    Throws-Life {Start-ShadowModelRouter -InstallRoot $root -Pool $pool -NodePath $node -PowerShellPath $pwsh} 'still working' 'Changed config does not stop a busy router'
    Assert-Life ($script:backendStarts -eq 1 -and $null -ne (Get-Process -Id $first.Pid -ErrorAction SilentlyContinue)) 'Busy process and active backend survive refused restart'
    Set-Fixture @{service='foreign-service'}
    Throws-Life {Stop-ShadowModelRouter -InstallRoot $root -Pool $pool} 'not.*expected' 'Foreign service is never killed based on its port'
    Set-Fixture @{}
    $controlPath=Join-Path $root 'runtime/router-control.json'
    $controlText=[IO.File]::ReadAllText($controlPath)
    [IO.File]::WriteAllText($controlPath,(@{schema=1;token=('0'*64)}|ConvertTo-Json))
    Throws-Life {Stop-ShadowModelRouter -InstallRoot $root -Pool $pool} 'authenticated' 'Wrong control token cannot shut down a router'
    Assert-Life ($null -ne (Get-Process -Id $first.Pid -ErrorAction SilentlyContinue)) 'Authentication failure preserves running process'
    [IO.File]::WriteAllText($controlPath,$controlText)
    $third=Start-ShadowModelRouter -InstallRoot $root -Pool $pool -NodePath $node -PowerShellPath $pwsh
    $created.Add($third.Pid)
    Assert-Life (-not $third.Reused -and $third.Pid -ne $first.Pid -and $script:backendStarts -eq 2) 'Idle changed config performs authenticated shutdown then fresh launch'
    Set-Fixture @{failed=$true;busy=$true}
    $failedHealth=Get-ShadowRouterHealth -Pool $pool
    Assert-Life ($null -ne $failedHealth -and -not $failedHealth.ready) 'HTTP 503 preserves the known router identity without claiming readiness'
    Throws-Life {Stop-ShadowModelRouter -InstallRoot $root -Pool $pool} 'still working' 'Failed but busy router cannot be shut down'
    Set-Fixture @{failed=$true}
    Stop-ShadowModelRouter -InstallRoot $root -Pool $pool
    Assert-Life ($null -eq (Get-ShadowRouterHealth -Pool $pool)) 'Authenticated idle shutdown also recovers an HTTP 503 router'
    Set-Fixture @{ready=$false}
    Throws-Life {Start-ShadowModelRouter -InstallRoot $root -Pool $pool -NodePath $node -PowerShellPath $pwsh} 'readiness status' 'Unhealthy new child fails startup'
    $failedPid=[int][IO.File]::ReadAllText((Join-Path $root 'fixture-pid.txt'))
    Assert-Life ($null -eq (Get-Process -Id $failedPid -ErrorAction SilentlyContinue)) 'Failed newly spawned router is terminated instead of orphaned'
    $script:occupied=$true
    Throws-Life {Stop-ShadowModelRouter -InstallRoot $root -Pool $pool} 'occupied' 'Unreachable occupied port is preserved without PID kill'
    [pscustomobject]@{Suite='Router PowerShell lifecycle';Passed=$true;Checks=$results.Count;Limitations='Real Node processes, loopback HTTP, auth and files. Backend startup and Windows listener inventory mocked; retry sleeps shortened.'}|ConvertTo-Json
} finally {
    [Environment]::SetEnvironmentVariable($pool.ApiTokenEnvironmentVariable,$previous,'Process')
    foreach($id in $created){$p=Get-Process -Id $id -ErrorAction SilentlyContinue;if($p){try{$p.Kill($true)}catch{}}}
    if(Test-Path -LiteralPath (Join-Path $root 'fixture-pid.txt')){$id=[int][IO.File]::ReadAllText((Join-Path $root 'fixture-pid.txt'));$p=Get-Process -Id $id -ErrorAction SilentlyContinue;if($p){try{$p.Kill($true)}catch{}}}
    Remove-Item -LiteralPath $root -Recurse -Force
}
