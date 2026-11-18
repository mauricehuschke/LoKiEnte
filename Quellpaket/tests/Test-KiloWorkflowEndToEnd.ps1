#requires -Version 7.4
param([string]$SourceRoot=(Split-Path -Parent $PSScriptRoot),[string]$FixtureBase=[IO.Path]::GetTempPath())
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $SourceRoot 'Common.ps1')
. (Join-Path $SourceRoot 'AgentTemplates.ps1')
$fixture=Join-Path $FixtureBase ('shadow-kilo-e2e-'+[guid]::NewGuid().ToString('N'))
$install=Join-Path $fixture 'installation with spaces'
$project=Join-Path $fixture 'project with spaces'
$state=Join-Path $install 'projects/fixture'
$passed=$false
try{
    foreach($directory in @((Join-Path $install 'app'),(Join-Path $project 'tests'),$state)){[void][IO.Directory]::CreateDirectory($directory)}
    # Run the exact installed modules, including the real reviewed-task runner.
    Get-ChildItem -LiteralPath $SourceRoot -File | Where-Object {$_.Extension -in @('.ps1','.mjs','.md')} | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path (Join-Path $install 'app') $_.Name)
    }
    Copy-Item -LiteralPath (Join-Path $SourceRoot 'templates') -Destination (Join-Path $install 'app/templates') -Recurse
    $node=(Get-Command node -CommandType Application|Select-Object -First 1).Source
    $pwsh=(Get-Process -Id $PID).Path
    $git=(Get-Command git -CommandType Application|Select-Object -First 1).Source
    [IO.File]::WriteAllText((Join-Path $project 'app.cjs'),'module.exports=()=>1;')
    $null=Invoke-ShadowNative $git @('init','--quiet',$project) -Quiet
    $null=Invoke-ShadowNative $git @('-C',$project,'add','.') -Quiet
    $null=Invoke-ShadowNative $git @('-C',$project,'-c','user.name=Fixture','-c','user.email=fixture@example.invalid','-c','commit.gpgsign=false','-c',('core.hooksPath='+(Join-Path $fixture 'empty-hooks')),'commit','--quiet','-m','Synthetic bridge fixture') -Quiet
    $catalog=[ordered]@{'coder-high'=@{id='shadow-coder-high';name='High';context=32768;output=8192};'coder-fast'=@{id='shadow-coder-fast';name='Fast';context=32768;output=8192};review=@{id='shadow-review';name='Review';context=32768;output=8192}}
    $null=New-ShadowAgentConfiguration -InstallRoot $install -ModelCatalog $catalog -ApiBaseUrl 'http://127.0.0.1:1235/v1'
    # Reuse the independently exercised synthetic agent fixture, not a fake runner.
    $tokens=$null;$errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'Test-QualityWorkflow.ps1'),[ref]$tokens,[ref]$errors)
    if($errors.Count){throw 'Could not parse quality-workflow fixture'}
    $fakeSource=@($ast.FindAll({param($node) $node -is [Management.Automation.Language.StringConstantExpressionAst] -and $node.Value.StartsWith("import fs from 'node:fs';") -and $node.Value.Contains('SHADOW_TEST_MODE')},$true))
    if($fakeSource.Count -ne 1){throw 'Expected exactly one shared synthetic Kilo fixture'}
    $fake=Join-Path $fixture 'fake-kilo.mjs'
    [IO.File]::WriteAllText($fake,$fakeSource[0].Value)
    $checks=Join-Path $state 'checks.json'
    [IO.File]::WriteAllText($checks,'{"schemaVersion":2,"checks":[],"writePaths":[],"testWritePaths":[],"acceptanceCriteria":[],"changeTypes":[],"regressionCheck":"","custom":"preserve me"}')
    [IO.File]::WriteAllText((Join-Path $install 'workspaces.json'),(ConvertTo-Json -InputObject @(@{project=$project;checks=$checks}) -Depth 6))
    [IO.File]::WriteAllText((Join-Path $install 'toolchain.json'),(@{nodeExecutable=$node;powerShellExecutable=$pwsh;kiloExecutable=$node;kiloArgumentPrefix=@($fake)}|ConvertTo-Json -Depth 6))
    $calls=Join-Path $fixture 'agent-calls.jsonl'
    $result=Invoke-ShadowNative -FilePath $node -ArgumentList @((Join-Path $PSScriptRoot 'Test-KiloWorkflowEndToEnd.mjs'),$install,$project,$calls) -WorkingDirectory $fixture -Environment @{SHADOW_TEST_MODE='auto-generated';SHADOW_TEST_CALLS=$calls;SHADOW_TEST_SECRET='synthetic-not-for-check-process'} -TimeoutSeconds 240 -AllowFailure -Quiet
    if($result.ExitCode -ne 0){throw "Full bridge integration failed. $($result.StdOut) $($result.StdErr)"}
    $result.StdOut
    $passed=$true
}finally{
    $resolved=[IO.Path]::GetFullPath($fixture)
    if(-not $resolved.StartsWith([IO.Path]::GetFullPath($FixtureBase).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notlike 'shadow-kilo-e2e-*'){throw 'Unsafe fixture cleanup path'}
    if($passed){Remove-Item -LiteralPath $resolved -Recurse -Force}
    else{Write-Warning "Failed integration fixture retained for process/status inspection: $resolved"}
}
