#requires -Version 7.4
param([string]$SourceRoot=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
. (Join-Path $SourceRoot 'Common.ps1')
. (Join-Path $SourceRoot 'GateCore.ps1')
. (Join-Path $SourceRoot 'WorkflowPolicy.ps1')
. (Join-Path $SourceRoot 'AcceptancePolicy.ps1')
. (Join-Path $SourceRoot 'TaskPreparation.ps1')
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('loki-welcome-'+[guid]::NewGuid().ToString('N'))
$count=0
function Assert($ok,$message){if(-not $ok){throw $message};$script:count++}
try{
    $entry=& (Join-Path $SourceRoot 'New-WelcomeTestProject.ps1') -InstallRoot $fixture
    $git=Resolve-ShadowTool git;$node=Resolve-ShadowTool node
    $head=(Invoke-ShadowNative $git @('-C',$entry.project,'rev-parse','HEAD') -Quiet).StdOut
    Assert ($head.Trim() -match '^[a-f0-9]{40,64}$') 'No initial history'
    Assert (-not (Invoke-ShadowNative $git @('-C',$entry.project,'status','--porcelain') -Quiet).StdOut.Trim()) 'Initial tree dirty'
    Assert (-not (Invoke-ShadowNative $git @('-C',$entry.project,'remote') -Quiet).StdOut.Trim()) 'Remote exists'
    $red=Invoke-ShadowNative $node @('-e',"require('node:assert/strict').equal(require('./discount.cjs')(10000,20),8000)") -WorkingDirectory $entry.project -Quiet -AllowFailure
    Assert ($red.ExitCode -ne 0 -and $red.StdErr.Contains('AssertionError')) 'Example does not reproduce real bug'
    $context=Get-ShadowPreparationContext -ProjectPath $entry.project -InstallRoot $fixture -ChecksFile $entry.checks -ApplicationRoot $SourceRoot
    Assert (@($context.Candidates|Where-Object id -EQ 'loki-node-test').Count -eq 1) 'No automatic native Node candidate'
    $proposal=@{workflow='Bugfix';writePaths=@('discount.cjs');testWritePaths=@('tests/discount.test.cjs');changeTypes=@('other');acceptanceCriteria=@(@{id='AC-1';description='Remaining price is correct'});checkIds=@('loki-node-test');regressionCheckId='loki-node-test'}
    $prepared=New-ShadowPreparedPolicy -Context $context -TaskText 'Fix the discount calculation' -Proposal $proposal
    Assert ($prepared.RunPolicy.checks[0].reportFormat -eq 'junit') 'No automatic structured check'
    $source=Join-Path $entry.project 'discount.cjs'
    [IO.File]::AppendAllText($source,[Environment]::NewLine+'// User work to preserve')
    $hash=(Get-FileHash -LiteralPath $source).Hash
    $again=& (Join-Path $SourceRoot 'New-WelcomeTestProject.ps1') -InstallRoot $fixture
    Assert ($again.project -eq $entry.project -and (Get-FileHash -LiteralPath $source).Hash -eq $hash) 'Update reset user work'
    Assert ((Invoke-ShadowNative $git @('-C',$entry.project,'rev-parse','HEAD') -Quiet).StdOut -eq $head) 'Update committed user work'
    $fresh=& (Join-Path $SourceRoot 'New-WelcomeTestProject.ps1') -InstallRoot $fixture -NewExample
    Assert ($fresh.project -ne $entry.project -and (Get-FileHash -LiteralPath $source).Hash -eq $hash) 'NewExample modified original'
    $index=Get-Content -LiteralPath (Join-Path $fixture 'workspaces.json') -Raw|ConvertFrom-Json
    Assert ($index.Count -eq 2) 'Both examples not registered'
    Remove-Item -LiteralPath (Join-Path $entry.project '.loki-welcome-example')
    $failed=$false;try{& (Join-Path $SourceRoot 'New-WelcomeTestProject.ps1') -InstallRoot $fixture|Out-Null}catch{$failed=$true}
    Assert ($failed -and (Get-FileHash -LiteralPath $source).Hash -eq $hash) 'Unknown existing folder was adopted/changed'
    $oldGitDir=$env:GIT_DIR
    try{
        $env:GIT_DIR=Join-Path $fixture 'foreign-git'
        $blockedRoot=Join-Path $fixture 'blocked'
        $failed=$false;try{& (Join-Path $SourceRoot 'New-WelcomeTestProject.ps1') -InstallRoot $blockedRoot|Out-Null}catch{$failed=$true}
        Assert ($failed -and -not(Test-Path -LiteralPath $blockedRoot)) 'Git override left a poisoned installation directory'
    }finally{$env:GIT_DIR=$oldGitDir}
    $mockApp=Join-Path $fixture 'mock-app'
    [void][IO.Directory]::CreateDirectory($mockApp)
    foreach($name in @('Common.ps1','Workspace.ps1','WORKFLOW.md','New-WelcomeTestProject.ps1','welcome-example')){
        Copy-Item -LiteralPath (Join-Path $SourceRoot $name) -Destination $mockApp -Recurse
    }
    Add-Content -LiteralPath (Join-Path $mockApp 'Common.ps1') -Value @'
$script:realNative=(Get-Command Invoke-ShadowNative).ScriptBlock
function Invoke-ShadowNative {
    param($FilePath,$ArgumentList,$Environment,[switch]$Quiet)
    if($ArgumentList -contains 'commit'){throw 'SYNTHETIC_INITIAL_COMMIT_FAILURE'}
    & $script:realNative -FilePath $FilePath -ArgumentList $ArgumentList -Environment $Environment -Quiet:$Quiet
}
'@
    $retryRoot=Join-Path $fixture 'retry'
    $failed=$false;try{& (Join-Path $mockApp 'New-WelcomeTestProject.ps1') -InstallRoot $retryRoot|Out-Null}catch{$failed=$_.Exception.Message.Contains('SYNTHETIC_INITIAL_COMMIT_FAILURE')}
    Assert ($failed -and -not(Test-Path -LiteralPath (Join-Path $retryRoot 'welcome/workflow-test'))) 'Partial repository was published'
    $retried=& (Join-Path $SourceRoot 'New-WelcomeTestProject.ps1') -InstallRoot $retryRoot
    Assert (Test-Path -LiteralPath (Join-Path $retried.project '.git/HEAD')) 'Retry after initial failure did not recover'
    @{suite='Welcome example and update preservation';passed=$true;checks=$count}|ConvertTo-Json
}finally{
    $resolved=[IO.Path]::GetFullPath($fixture)
    if(-not $resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notlike 'loki-welcome-*'){throw 'Unsafe cleanup'}
    if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
