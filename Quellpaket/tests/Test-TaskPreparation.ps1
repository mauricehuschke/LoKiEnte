#requires -Version 7.4
param([string]$SourceRoot=(Split-Path -Parent $PSScriptRoot))
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
foreach($file in @('GateCore.ps1','WorkflowPolicy.ps1','AcceptancePolicy.ps1','TaskPreparation.ps1')){. (Join-Path $SourceRoot $file)}
$root=Join-Path ([IO.Path]::GetTempPath()) ('shadow-preparation-'+[guid]::NewGuid().ToString('N'))
$project=Join-Path $root 'project';$install=Join-Path $root 'install';$checks=Join-Path $install 'checks.json'
[void][IO.Directory]::CreateDirectory((Join-Path $project 'tests'))
[void][IO.Directory]::CreateDirectory($install)
$script:count=0
function Assert-True($Value,[string]$Message){if(-not $Value){throw $Message};$script:count++}
function Reject([scriptblock]$Action,[string]$Message){$rejected=$false;try{& $Action|Out-Null}catch{$rejected=$true;if($_.Exception.Message -notmatch 'NEEDS_INPUT|Schreibpfad|Geschuetzt|geschuetzt|Projekt- oder Pruefkonfiguration'){throw}};Assert-True $rejected $Message}
function Context {Get-ShadowPreparationContext -ProjectPath $project -InstallRoot $install -ChecksFile $checks -ApplicationRoot $SourceRoot}
function Proposal {
    return [ordered]@{workflow='Feature';acceptanceCriteria=@(@{id='AC-1';description='Function returns two'});changeTypes=@('other');writePaths=@('src/app.cjs');testWritePaths=@('tests/app.test.cjs');checkIds=@('loki-node-test')}
}
try{
    [void][IO.Directory]::CreateDirectory((Join-Path $project 'src'))
    [IO.File]::WriteAllText((Join-Path $project 'src/app.cjs'),'module.exports=()=>1;')
    [IO.File]::WriteAllText((Join-Path $project 'tests/app.test.cjs'),'require("node:test").test("existing",()=>{});')
    [IO.File]::WriteAllText((Join-Path $project 'package.json'),'{"name":"fixture","scripts":{"test":"node --test","deploy":"upload-production"},"devDependencies":{}}')
    [IO.File]::WriteAllText((Join-Path $project '.gitignore'),"node_modules/`n.env`n")
    [IO.File]::WriteAllText((Join-Path $project '.env'),'SYNTHETIC_PRIVATE_TOKEN=do-not-read')
    & git init --quiet $project
    & git -C $project add .
    & git -C $project -c user.name=Fixture -c user.email=fixture@example.invalid -c commit.gpgsign=false -c ('core.hooksPath='+(Join-Path $root 'empty-hooks')) commit --quiet -m fixture
    if($LASTEXITCODE -ne 0){throw 'Fixture Git setup failed'}
    $context=Context
    Assert-True ($context.Inventory.files -notcontains '.env' -and -not(($context|ConvertTo-Json -Depth 30).Contains('do-not-read'))) 'Secret leaked into discovery'
    Assert-True (@($context.Candidates | Where-Object id -CEQ 'loki-node-test').Count -eq 1) 'Native candidate absent'
    Assert-True (-not $context.Inventory.manifests.package.scripts.Contains('deploy')) 'Deployment script advertised'
    $promptContext=Get-ShadowPreparationPromptContext $context
    $promptText=$promptContext|ConvertTo-Json -Depth 40 -Compress
    Assert-True ([Text.Encoding]::UTF8.GetByteCount($promptText) -lt 8000 -and -not $promptText.Contains('InputHashes')) 'Typical prompt includes audit hashes or exceeds compact budget'
    $proposal=Proposal;$prepared=New-ShadowPreparedPolicy $context 'Return two' $proposal
    Assert-True ($prepared.RunPolicy.checks.Count -eq 1 -and $prepared.RunPolicy.checks[0].arguments -contains 'tests/app.test.cjs') 'Prepared check files missing'
    Assert-True (-not(Test-Path -LiteralPath $checks)) 'Compilation wrote checks before review'
    $null=Save-ShadowPreparedPolicy $context $prepared
    $saved=Get-Content -LiteralPath $checks -Raw | ConvertFrom-Json -AsHashtable
    Assert-True ($saved.acceptanceCriteria[0].id -ceq 'AC-1' -and $saved.automation.owner -ceq 'LoKi task preparation v1') 'Saved ownership missing'
    $context=Context;$proposal=Proposal;$proposal.acceptanceCriteria[0].description='Function returns three';$proposal.testWritePaths=@('tests/new.test.cjs')
    $projection=Get-ShadowPreparationPromptContext $context
    Assert-True (@($projection.candidates|Where-Object id -CEQ 'existing:loki-node-test').Count -eq 0 -and ($projection|ConvertTo-Json -Depth 40) -notmatch 'fieldHashes') 'Prompt duplicates stale generated checks or provenance hashes'
    $next=New-ShadowPreparedPolicy $context 'Return three' $proposal
    Assert-True ($next.Policy.acceptanceCriteria[0].description -ceq 'Function returns three' -and $next.Policy.testWritePaths[0] -ceq 'tests/new.test.cjs') 'Next task retained stale scope'
    $null=Save-ShadowPreparedPolicy $context $next
    Assert-True (@(Get-ChildItem -LiteralPath (Join-Path $install 'backups/task-preparation') -File).Count -eq 1) 'Prior policy not backed up'
    $saved=Get-Content -LiteralPath $checks -Raw | ConvertFrom-Json -AsHashtable
    $saved.checks[0].timeoutSeconds=43;Write-ShadowUtf8File $checks ($saved|ConvertTo-Json -Depth 50)
    $context=Context;$review=Proposal;$review.workflow='Review';$review.writePaths=@();$review.testWritePaths=@();$review.checkIds=@()
    Reject {New-ShadowPreparedPolicy $context 'Review source' $review} 'Unselected modified generated check silently re-owned'
    Write-ShadowUtf8File $checks ($next.Policy|ConvertTo-Json -Depth 50)
    $saved=Get-Content -LiteralPath $checks -Raw | ConvertFrom-Json -AsHashtable
    $saved.changeTypes=@('security');Write-ShadowUtf8File $checks ($saved|ConvertTo-Json -Depth 50)
    $context=Context
    Reject {New-ShadowPreparedPolicy $context 'Another task' (Proposal)} 'Manual task-field change silently replaced'
    $legacy=@{custom=@{keep='yes'};writePaths=@('src/old.cjs');acceptanceCriteria=@(@{id='AC-1';description='Previous task'});checks=@(@{name='old-tests';command='npm';arguments=@('run','test');timeoutSeconds=60})}
    Write-ShadowUtf8File $checks ($legacy|ConvertTo-Json -Depth 20)
    $context=Context;$prepared=New-ShadowPreparedPolicy $context 'Return two' (Proposal)
    Assert-True ($prepared.Policy.custom.keep -ceq 'yes' -and $prepared.Policy.checks[0].command -ceq 'npm' -and $prepared.Policy.checks[0].arguments[1] -ceq 'test') 'Original fields or command lost'
    Assert-True ($prepared.Policy.automation.importedTaskFields.acceptanceCriteria[0].description -ceq 'Previous task' -and $prepared.Notes.Count -eq 2) 'Legacy task import or replacement not disclosed'
    Assert-True ($prepared.RunPolicy.checks.Count -eq 1 -and $prepared.RunPolicy.checks[0].reportFormat -ceq 'junit') 'Legacy replacement not usable'
    $projection=Get-ShadowPreparationPromptContext $context
    Assert-True ($projection.manualFields.custom.keep -ceq 'yes' -and @($projection.candidates|Where-Object id -CEQ 'existing:old-tests')[0].definition.arguments[1] -ceq 'test') 'Compact projection loses original manual commands or fields'
    $review=Proposal;$review.workflow='Review';$review.writePaths=@();$review.testWritePaths=@();$review.checkIds=@()
    $reviewed=New-ShadowPreparedPolicy $context 'Review source' $review
    Assert-True ($reviewed.RunPolicy.checks.Count -eq 0 -and $reviewed.RunPolicy.writePaths.Count -eq 0) 'Read-only task without framework cannot be prepared'
    $proposal=Proposal;$proposal.checkIds=@('existing:old-tests')
    Reject {New-ShadowPreparedPolicy $context 'Task' $proposal} 'Incomplete legacy command silently accepted'
    $legacy.limits=@{allowedWritePaths=@('src/other.cjs')}
    Write-ShadowUtf8File $checks ($legacy|ConvertTo-Json -Depth 20);$context=Context
    Reject {New-ShadowPreparedPolicy $context 'Task' (Proposal)} 'Manual limits widened'
    $legacy.Remove('limits');Write-ShadowUtf8File $checks ($legacy|ConvertTo-Json -Depth 20);$context=Context
    $proposal=Proposal;$proposal.checkIds=@('arbitrary-shell')
    Reject {New-ShadowPreparedPolicy $context 'Task' $proposal} 'Model-selected unknown executable accepted'
    $proposal=Proposal;$proposal.writePaths=@('package.json')
    Reject {New-ShadowPreparedPolicy $context 'Task' $proposal} 'Protected manifest authorized'
    $proposal=Proposal;$proposal.testWritePaths=@('../escape.cjs')
    Reject {New-ShadowPreparedPolicy $context 'Task' $proposal} 'Outside test path accepted'
    $prepared=New-ShadowPreparedPolicy $context 'Task' (Proposal)
    Write-ShadowUtf8File $checks '{"checks":[],"custom":"changed"}'
    Reject {Save-ShadowPreparedPolicy $context $prepared} 'Concurrent policy edit overwritten'
    $context=Context;$prepared=New-ShadowPreparedPolicy $context 'Task' (Proposal)
    [IO.File]::AppendAllText((Join-Path $project 'src/app.cjs'),"`n// external change")
    Reject {Save-ShadowPreparedPolicy $context $prepared} 'Source changed since preparation accepted'
    # Discover installed frameworks without executing their code.
    foreach($entry in @('node_modules/vitest/vitest.mjs','node_modules/jest/bin/jest.js','node_modules/@playwright/test/cli.js')){
        $full=Join-Path $project $entry;[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($full));[IO.File]::WriteAllText($full,'throw new Error("must not execute during discovery");')
    }
    $context=Context
    Assert-True (@($context.Candidates | Where-Object id -CEQ 'loki-vitest-test').Count -eq 1 -and @($context.Candidates | Where-Object id -CEQ 'loki-jest-test').Count -eq 1 -and @($context.Candidates | Where-Object id -CEQ 'loki-playwright-integration').Count -eq 1) 'Installed frameworks not discovered'
    Assert-True ((Get-ShadowPreparationHash @{b=2;a=1}) -ceq (Get-ShadowPreparationHash @{a=1;b=2})) 'Canonical hashes depend on key order'
    $unknown=Context;$unknown.ExistingPolicy.schemaVersion=99
    Reject {New-ShadowPreparedPolicy $unknown 'Task' (Proposal)} 'Unknown schema silently downgraded'
    [pscustomobject]@{suite='Automatic task preparation';passed=$true;checks=$script:count}|ConvertTo-Json
}finally{
    $resolved=[IO.Path]::GetFullPath($root)
    if(-not $resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notlike 'shadow-preparation-*'){throw 'Unsafe cleanup path'}
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
