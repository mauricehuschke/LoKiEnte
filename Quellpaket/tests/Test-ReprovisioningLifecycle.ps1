#requires -Version 7.4
# Real router lifecycle, Node/HTTP/process handles, Windows argv parsing and
# model-file download/copy/hash code. CIM/listener inventory, curl transport and
# LM Studio/GPU are explicit synthetic boundaries, not target acceptance.
param([string]$SourceRoot=(Split-Path -Parent $PSScriptRoot))
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $SourceRoot 'ModelPool.ps1')
. (Join-Path $SourceRoot 'ModelSelection.ps1')
. (Join-Path $SourceRoot 'Router.ps1')
$base=Join-Path ([IO.Path]::GetTempPath()) ('lokiente-reprovision-'+[guid]::NewGuid().ToString('N'))
$root=Join-Path $base 'install with spaces'
$node=(Get-Command node -CommandType Application|Select-Object -First 1).Source
$pwsh=(Get-Process -Id $PID).Path
$tcp=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,0);$tcp.Start();$port=([Net.IPEndPoint]$tcp.LocalEndpoint).Port;$tcp.Stop()
$checks=0;$script:activePid=0;$script:downloads=0;$script:metadataReads=0;$script:backendStarts=0
$createdHandles=[Collections.Generic.List[Diagnostics.Process]]::new()
$script:override=@{};$script:flipBusy=$false
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
function Assert-Repro($Condition,$Message){if(-not $Condition){throw $Message};$script:checks++}
function Remove-Fixture($Path){
    $resolved=[IO.Path]::GetFullPath($Path);$allowed=[IO.Path]::GetFullPath($base).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
    if(-not $resolved.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe fixture cleanup'}
    if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
function Write-FixtureState($Value){[IO.File]::WriteAllText((Join-Path $root 'fixture-state.json'),($Value|ConvertTo-Json))}
function New-FixtureInstallation {
    foreach($folder in @('app','runtime','models')){[void][IO.Directory]::CreateDirectory((Join-Path $root $folder))}
    [IO.File]::WriteAllText((Join-Path $root 'app/Switch-LocalModel.ps1'),'# Synthetic controller boundary')
    [IO.File]::WriteAllText((Join-Path $root 'app/ModelRouter.mjs'),@'
import http from 'node:http';import fs from 'node:fs';import path from 'node:path';
const args=process.argv.slice(2),get=k=>args[args.indexOf(k)+1],root=path.dirname(path.dirname(get('--config')));
const digest=get('--routing-digest'),secret=process.env.SHADOW_LOCAL_ROUTER_CONTROL;
const server=http.createServer((req,res)=>{
 let state={};try{state=JSON.parse(fs.readFileSync(path.join(root,'fixture-state.json'),'utf8'));}catch{}
 res.setHeader('content-type','application/json');
 if(req.url==='/health'){res.end(JSON.stringify({service:'shadow-local-model-router',version:'2026.11.27.2',configDigest:digest,pid:process.pid,ready:true,busy:!!state.busy,queued:0}));return;}
 if(req.url==='/admin/shutdown'&&req.headers['x-shadow-control']===secret){res.end('{"stopping":true}');server.close();return;}
 res.writeHead(403);res.end('{}');
});server.listen(Number(get('--port')),'127.0.0.1');
'@)
    $script:pool=[pscustomobject]@{SchemaVersion=2;Status='Ready';OwnerId=('a'*24);PrimaryAlias='coder';BackendApiBaseUrl='http://127.0.0.1:1234/v1';RouterApiBaseUrl="http://127.0.0.1:$port/v1";ApiTokenEnvironmentVariable='';Profiles=@(
        [pscustomobject]@{Alias='coder';RouteId='shadow-coder';Name='Synthetic';InstanceId='owned-coder';ModelPath='model.gguf';ContextLength=16384;OutputLimit=4096},
        [pscustomobject]@{Alias='review';RouteId='shadow-review';Name='Synthetic';InstanceId='owned-review';ModelPath='model.gguf';ContextLength=16384;OutputLimit=4096})}
    [IO.File]::WriteAllText((Join-Path $root 'runtime/model-pool.json'),($script:pool|ConvertTo-Json -Depth 10))
    Write-FixtureState @{}
}
function Start-LocalModelPool {param($InstallRoot);$script:backendStarts++;return $script:pool}
function Get-NetTCPConnection {
    param($State,$LocalPort,$ErrorAction)
    if($script:activePid -and (Get-Process -Id $script:activePid -ErrorAction SilentlyContinue)){
        [pscustomobject]@{LocalAddress=$(if($script:override.ContainsKey('ListenerAddress')){$script:override.ListenerAddress}else{'127.0.0.1'});OwningProcess=$(if($script:override.ContainsKey('ListenerPid')){$script:override.ListenerPid}else{$script:activePid})}
    }
}
function Get-CimInstance {
    param($ClassName,$Filter,$ErrorAction)
    $script:metadataReads++
    if($script:override.ContainsKey('Denied')){throw 'Synthetic CIM access denied'}
    $record=@{ProcessId=$script:activePid;ExecutablePath=$node;CommandLine=($script:routerArguments|ForEach-Object {'"'+$_+'"'}) -join ' ';CreationDate=(Get-Process -Id $script:activePid).StartTime}
    foreach($key in @('ExecutablePath','CommandLine','CreationDate','ProcessId')){if($script:override.ContainsKey($key)){$record[$key]=$script:override[$key]}}
    return [pscustomobject]$record
}
function Invoke-CimMethod {
    param($InputObject,$MethodName,$ErrorAction)
    if($script:flipBusy){Write-FixtureState @{busy=$true}}
    return [pscustomobject]@{ReturnValue=0;Sid=$(if($script:override.ContainsKey('Sid')){$script:override.Sid}else{$sid})}
}
function Start-FixtureRouter {
    $started=Start-ShadowModelRouter -InstallRoot $root -Pool $script:pool -NodePath $node -PowerShellPath $pwsh
    $script:activePid=$started.Pid
    $handle=[Diagnostics.Process]::GetProcessById($started.Pid);$null=$handle.SafeHandle;$createdHandles.Add($handle)
    $health=Get-ShadowRouterHealth -Pool $script:pool
    $script:routerArguments=@($node,(Join-Path $root 'app/ModelRouter.mjs'),'--config',(Join-Path $root 'runtime/model-pool.json'),'--routing-digest',$health.configDigest,'--pwsh',$pwsh,'--switch-script',(Join-Path $root 'app/Switch-LocalModel.ps1'),'--port',[string]$port)
    return $started
}
function Invoke-ShadowProvisionStep {param($Id,$Action) return &$Action}
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $SourceRoot 'Setup.ps1'),[ref]$tokens,[ref]$errors)
$reset=$ast.Find({param($n) $n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Extent.Text.StartsWith('$report.routerReset=')},$true)
if($errors -or -not $reset){throw 'Router preflight implementation not found'}
$modelReset=$ast.Find({param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -ceq 'Reset-ShadowSetupLoadedModels'},$true)
Assert-Repro ($modelReset -and $reset.Extent.StartOffset -lt $modelReset.Extent.StartOffset) 'Actual setup must stop/check routers before resetting or testing LM Studio models.'
$preflight=[scriptblock]::Create($reset.Extent.Text)
$previousPool=$null;$RouterPort=$port;$ApiTokenEnvironmentVariable='';$InstallRoot=$root;$toolchain=@{powerShellExecutable=$pwsh};$report=@{}
$content=[Text.Encoding]::UTF8.GetBytes('synthetic model transport fixture')
$hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($content)).ToLowerInvariant()
$definition=@{Id='fixture';Name='Synthetic model';Repository='test/repo';Revision=('a'*40);ExpectedPath='test/repo/model.gguf';Files=@(@{Name='model.gguf';Size=$content.Length;Sha256=$hash})}
$definitions=@(@{Alias='coder';Name='Synthetic model';Definition=$definition})
function Resolve-ShadowModelDirectory {return Join-Path $root 'models'}
function Resolve-ShadowTool {param($Name) if($Name -ceq 'curl'){return 'synthetic-curl.exe'};throw 'Unexpected tool lookup'}
function Invoke-ShadowCurl {param($FilePath,$Arguments);$script:downloads++;$output=$Arguments[[array]::IndexOf($Arguments,'--output')+1];[IO.File]::WriteAllBytes($output,$content);return 0}
function Get-LrDownloadedModels {param($LmsPath,$LogDirectory,$Type);return [pscustomobject]@{path=$definition.ExpectedPath;modelKey='fixture'}}
try{
    New-FixtureInstallation
    &$preflight;Assert-Repro ($report.routerReset.Status -ceq 'NotRunning') 'Fresh setup must record a free router endpoint.'
    Install-ShadowSelectedModels -Definitions $definitions -LmsPath synthetic -InstallRoot $root
    $model=Join-Path $root 'models/test/repo/model.gguf'
    Assert-Repro ($script:downloads -eq 1 -and (Get-FileHash $model).Hash -ieq $hash) 'First provisioning downloads, verifies and registers a missing file.'
    $first=Start-FixtureRouter
    $previousPool=$script:pool;&$preflight
    Assert-Repro ($report.routerReset.Method -ceq 'AuthenticatedShutdown' -and -not (Get-Process -Id $first.Pid -ErrorAction SilentlyContinue)) 'Reprovisioning an intact installation uses authenticated shutdown.'
    Install-ShadowSelectedModels -Definitions $definitions -LmsPath synthetic -InstallRoot $root
    Assert-Repro ($script:downloads -eq 1) 'Reprovisioning reuses verified model files without another download.'
    $second=Start-FixtureRouter
    Get-ChildItem -LiteralPath $root -Force|Where-Object {$_.Name -cne 'models'}|ForEach-Object {Remove-Fixture $_.FullName}
    New-FixtureInstallation;$previousPool=$null
    Assert-Repro (-not (Test-Path (Join-Path $root 'runtime/router-control.json')) -and (Get-ShadowRouterHealth -Pool $script:pool).pid -eq $second.Pid) 'Deleting everything except models leaves the real background router alive without its credentials.'
    $normalArguments=@($script:routerArguments)
    foreach($bad in @(
        @{Sid='S-1-0-0'},@{ExecutablePath=$pwsh},@{ProcessId=1},@{ListenerPid=1},@{ListenerAddress='0.0.0.0'},@{Denied=$true},
        @{CommandLine='"'+$node+'" --eval "foreign code"'},@{CreationDate=(Get-Process -Id $second.Pid).StartTime.AddSeconds(1)}
    )){
        $script:override=$bad;$failed=$false
        try{&$preflight}catch{$failed=$_.Exception.Message -match 'Control credentials.*missing'}
        Assert-Repro ($failed -and (Get-Process -Id $second.Pid -ErrorAction SilentlyContinue)) 'Unverified OS identity must preserve the process.'
    }
    foreach($index in @(1,3,7,9)){
        $changed=@($normalArguments);$changed[$index]=Join-Path $base 'foreign-installation/file.exe'
        $script:override=@{CommandLine=($changed|ForEach-Object {'"'+$_+'"'}) -join ' '};$failed=$false
        try{&$preflight}catch{$failed=$_.Exception.Message -match 'command line'}
        Assert-Repro ($failed -and (Get-Process -Id $second.Pid -ErrorAction SilentlyContinue)) 'A different installation/configuration/controller path must remain untouched.'
    }
    foreach($changed in @((@($normalArguments)+@('--eval','foreign')),(@($normalArguments[0..4])+@(('0'*64))+@($normalArguments[6..11])))){
        $script:override=@{CommandLine=($changed|ForEach-Object {'"'+$_+'"'}) -join ' '};$failed=$false
        try{&$preflight}catch{$failed=$_.Exception.Message -match 'command line'}
        Assert-Repro ($failed -and (Get-Process -Id $second.Pid -ErrorAction SilentlyContinue)) 'Extra process arguments and mismatched routing digests must prevent recovery.'
    }
    $script:override=@{};Write-FixtureState @{busy=$true};$before=$script:metadataReads;$failed=$false
    try{&$preflight}catch{$failed=$_.Exception.Message -match 'still working'}
    Assert-Repro ($failed -and $script:metadataReads -eq $before) 'Busy routers must block before recovery metadata or model work.'
    Write-FixtureState @{};$script:flipBusy=$true;$failed=$false
    try{&$preflight}catch{$failed=$_.Exception.Message -match 'idle state changed'}
    Assert-Repro ($failed -and (Get-Process -Id $second.Pid -ErrorAction SilentlyContinue)) 'A new busy state during identity verification must cancel recovery.'
    $script:flipBusy=$false;Write-FixtureState @{}
    $before=$script:backendStarts;&$preflight
    Assert-Repro ($report.routerReset.Method -ceq 'VerifiedOwnedProcess' -and -not (Get-Process -Id $second.Pid -ErrorAction SilentlyContinue) -and $script:backendStarts -eq $before) 'The exact verified orphan must stop before any backend/model restart.'
    $recovery=Get-Content (Join-Path $root 'runtime/router-recovery.json') -Raw|ConvertFrom-Json
    Assert-Repro ($recovery.pid -eq $second.Pid -and $recovery.accountMatched -and $recovery.commandLineMatched -and -not $recovery.PSObject.Properties['token']) 'Recovery evidence must identify the process without credentials.'
    Install-ShadowSelectedModels -Definitions $definitions -LmsPath synthetic -InstallRoot $root -SkipModelDownload
    Assert-Repro ($script:downloads -eq 1 -and (Get-FileHash $model).Hash -ieq $hash) 'A fresh installation with only the models directory retained must need no download.'
    $third=Start-FixtureRouter
    Assert-Repro ($third.Pid -ne $second.Pid -and (Test-Path (Join-Path $root 'runtime/router-control.json'))) 'The fresh router must get a new process and usable local control credentials.'
    $previousPool=$script:pool;&$preflight
    Assert-Repro ($report.routerReset.Method -ceq 'AuthenticatedShutdown') 'The next provisioning must work normally with recreated credentials.'
    $ready=Start-FixtureRouter
    Remove-Item -LiteralPath (Join-Path $root 'runtime/router-control.json') -Force
    $recovered=Start-FixtureRouter
    Assert-Repro ($recovered.Pid -ne $ready.Pid -and -not $recovered.Reused) 'A matching healthy router without credentials must recover instead of being silently reused by the desktop/start lifecycle.'
    &$preflight
    Remove-Fixture (Join-Path $root 'models');[void][IO.Directory]::CreateDirectory((Join-Path $root 'models'))
    Remove-Fixture (Join-Path $root 'model-downloads')
    Install-ShadowSelectedModels -Definitions $definitions -LmsPath synthetic -InstallRoot $root
    Assert-Repro ($script:downloads -eq 2 -and (Get-FileHash $model).Hash -ieq $hash) 'A fresh empty model directory must follow the download path again.'
    @{suite='First provisioning and reprovisioning lifecycle';passed=$true;checks=$checks;limitations='Real processes, loopback HTTP, Windows argv parsing, files, hashing and setup preflight. Windows CIM/listener inventory, network transport and LM Studio are mocked; target GPU/GUI remains unverified.'}|ConvertTo-Json
}finally{
    foreach($process in $createdHandles){try{if(-not $process.HasExited){$process.Kill();$null=$process.WaitForExit(5000)}}finally{$process.Dispose()}}
    $resolved=[IO.Path]::GetFullPath($base);$allowed=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
    if(-not $resolved.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notlike 'lokiente-reprovision-*'){throw 'Unsafe cleanup'}
    if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
