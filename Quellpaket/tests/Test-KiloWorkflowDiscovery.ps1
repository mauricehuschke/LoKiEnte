#requires -Version 7.4
[CmdletBinding()]
param([string]$SourceRoot=(Split-Path -Parent $PSScriptRoot))
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $SourceRoot 'Common.ps1')
. (Join-Path $SourceRoot 'AgentTemplates.ps1')
$testRoot=Join-Path ([IO.Path]::GetTempPath()) ('loki-discovery-'+[guid]::NewGuid().ToString('N'))
$node=(Get-Command node -CommandType Application | Select-Object -First 1).Source
$count=0
function Assert-Discovery([bool]$Value,[string]$Message){if(-not $Value){throw "FAIL: $Message"};$script:count++}
function New-FixtureConfiguration {
    $tools=@('loki_start','loki_status','loki_cancel','loki_details')
    $config=@{permission=@{};agent=@{};provider=@{}}
    foreach($tool in $tools){$config.permission[$tool]='deny'}
    foreach($role in @('shadow-chat','shadow-chat-fast','shadow-implementer','shadow-plan','shadow-preparer','shadow-preparation-reviewer')){
        $permission=@{}
        foreach($tool in $tools){$permission[$tool]=if($role -in @('shadow-chat','shadow-chat-fast')){'allow'}else{'deny'}}
        $config.agent[$role]=@{permission=$permission}
    }
    return $config
}
function Invoke-DiscoveryCase([string]$Mode,[Collections.IDictionary]$Configuration,[switch]$Full){
    Assert-ShadowKiloWorkflowTools -KiloExecutable $node -KiloArgumentPrefix @((Join-Path $testRoot 'backend.mjs'),$Mode) -InstallRoot $testRoot -Config $Configuration -WorkingDirectory $testRoot -TimeoutSeconds 1 -Full:$Full
}
try {
    $null=New-Item -ItemType Directory -Path $testRoot
    @'
const [mode,command,subcommand,role]=process.argv.slice(2);
if(command!=='debug'||subcommand!=='agent'||process.argv.length!==6) process.exit(2);
if(process.env.KILO_PURE!=='1'||process.env.KILO_DISABLE_PROJECT_CONFIG!=='1'||process.env.KILO_DISABLE_MODELS_FETCH!=='1'||process.env.KILO_DISABLE_CODEBASE_INDEXING!=='1'||process.env.KILO_DISABLE_LSP_DOWNLOAD!=='1') process.exit(3);
if(mode==='timeout') {setTimeout(()=>{},10000);} else {
  if(mode==='exit') process.exit(4);
  if(mode==='json') {console.log('not json');process.exit(0);}
  const tools=Object.fromEntries(['loki_start','loki_status','loki_cancel','loki_details'].map(name=>[name,['shadow-chat','shadow-chat-fast'].includes(role)]));
  if(mode==='missing') delete tools.loki_start;
  if(mode==='string') tools.loki_start=String(tools.loki_start);
  if(mode==='leak'&&role==='shadow-implementer') tools.loki_start=true;
  console.log(JSON.stringify({name:mode==='identity'?'wrong-role':role,tools}));
}
'@ | Set-Content -LiteralPath (Join-Path $testRoot 'backend.mjs') -Encoding utf8NoBOM
    $config=New-FixtureConfiguration
    $result=Invoke-DiscoveryCase 'ok' $config
    Assert-Discovery ($result.Verified -and $result.RegistryRoles.Count -eq 2 -and $result.RegistryRoles['shadow-chat'] -and -not $result.RegistryRoles['shadow-implementer'] -and -not $result.InferenceUsed) 'Two real subprocess probes use strict environment and preserve allow/deny distinction'
    $result=Invoke-DiscoveryCase 'ok' $config -Full
    Assert-Discovery ($result.RegistryRoles.Count -eq 6 -and $result.PolicyRoles.Count -eq 6) 'Full probe covers every managed role'
    foreach($mode in @('exit','json','missing','string','leak','identity','timeout')){
        $failed=$false
        try{$null=Invoke-DiscoveryCase $mode $config}catch{$failed=$true}
        Assert-Discovery $failed "Reject $mode from real backend subprocess"
    }
    foreach($mutation in @('global','child','parent','required')){
        $broken=New-FixtureConfiguration
        switch($mutation){
            global {$broken.permission.loki_start='allow'}
            child {$broken.agent['shadow-preparation-reviewer'].permission.loki_start='allow'}
            parent {$broken.agent['shadow-chat-fast'].permission.loki_start='deny'}
            required {$broken.agent.Remove('shadow-preparer')}
        }
        $failed=$false
        try{$null=Invoke-DiscoveryCase 'ok' $broken}catch{$failed=$true}
        Assert-Discovery $failed "Reject $mutation configuration policy"
    }
    [pscustomobject]@{suite='Kilo workflow registry discovery';passed=$true;checks=$count}|ConvertTo-Json
} finally {
    $resolved=[IO.Path]::GetFullPath($testRoot)
    $temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar)+[IO.Path]::DirectorySeparatorChar
    if($resolved.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -and [IO.Path]::GetFileName($resolved).StartsWith('loki-discovery-') -and (Test-Path -LiteralPath $resolved)){
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
