#requires -Version 7.4
[CmdletBinding()]
param([string]$SourceRoot=(Split-Path -Parent $PSScriptRoot))
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $SourceRoot 'Common.ps1')
. (Join-Path $SourceRoot 'Workspace.ps1')
$root=Join-Path ([IO.Path]::GetTempPath()) ('shadow-workspace-guide-'+[guid]::NewGuid().ToString('N'))
$project=Join-Path $root 'repository'
$managed=Join-Path $root 'managed'
[void][IO.Directory]::CreateDirectory($project)
try{
    $projectFile=Join-Path $project 'user.txt'
    [IO.File]::WriteAllText($projectFile,'existing project')
    $entry=New-ShadowWorkspace -Root $managed -Project $project -PwshPath (Get-Process -Id $PID).Path
    $guide=Join-Path (Split-Path -Parent $entry.task) 'GUIDE.md'
    if(-not(Test-Path -LiteralPath $guide -PathType Leaf)){throw 'Workspace guide was not created'}
    $content=[IO.File]::ReadAllText($guide)
    foreach($required in @('task.md','checks.json','Terminal > Run Task','VERIFIED','user permissions','loki_start','loki_status','LOKI-STATUS.md','preparation review')){
        if(-not $content.Contains($required)){throw "Guide is missing: $required"}
    }
    $workspace=Get-Content -LiteralPath $entry.workspace -Raw|ConvertFrom-Json
    foreach($task in $workspace.tasks.tasks){
        if($task.args[2] -cne '-ExecutionPolicy' -or $task.args[3] -cne 'Bypass'){throw 'VS Code task lacks a process-local execution policy'}
        if($task.args -notcontains '-AutoPrepare'){throw 'Managed workflow task does not prepare criteria and checks automatically'}
    }
    $auto=@($workspace.tasks.tasks|Where-Object {$_.label -ceq 'Local AI: Automatic task with verification'})
    if($auto.Count -ne 1 -or $auto[0].args -notcontains 'Auto'){throw 'Automatic workflow selection task missing'}
    $fastTasks=@($workspace.tasks.tasks|Where-Object {$_.label -match '\(Coder Fast\)'})
    if($fastTasks.Count -ne 3 -or @($fastTasks|Where-Object {$_.args -notcontains '-CoderProfile' -or $_.args -notcontains 'Fast'}).Count){
        throw 'Coder Fast workflow tasks are missing or do not select the fast coding profile'
    }
    $taskText='User task - do not replace'
    $checkText='{"writePaths":["src/code.ts","tests/code.test.ts"],"checks":[{"name":"existing","command":"npm","arguments":["run","test:ci"],"timeoutSeconds":60}],"custom":"keep"}'
    $guideText='User guide - do not replace'
    [IO.File]::WriteAllText($entry.task,$taskText)
    [IO.File]::WriteAllText($entry.checks,$checkText)
    [IO.File]::WriteAllText($guide,$guideText)
    $oldWorkspace=Get-Content -LiteralPath $entry.workspace -Raw|ConvertFrom-Json -AsHashtable
    $oldWorkspace.settings['editor.tabSize']=3
    $oldWorkspace.tasks.tasks+=@(@{label='Personal Task';type='process';command='personal.exe'})
    $oldWorkspace.tasks.tasks[0].command='old-powershell.exe'
    [IO.File]::WriteAllText($entry.workspace,($oldWorkspace|ConvertTo-Json -Depth 20))
    Register-ShadowWorkspaces -Root $managed -Entries @($entry,@{project=(Join-Path $root 'unreachable')})
    $new=Join-Path $root 'new-project'
    [void][IO.Directory]::CreateDirectory($new)
    $updated=Update-ShadowWorkspaces -Root $managed -ProjectPath @($new) -PwshPath (Get-Process -Id $PID).Path
    if($updated.Entries.Count -ne 2 -or $updated.Warnings.Count -ne 1 -or @(Get-ShadowWorkspaceIndex $managed).Count -ne 3){
        throw 'Update did not migrate known and new projects while retaining unreachable registration'
    }
    $migrated=Get-Content -LiteralPath $entry.checks -Raw|ConvertFrom-Json
    if($migrated.custom -cne 'keep' -or $migrated.checks[0].arguments[1] -cne 'test:ci' -or
       $migrated.writePaths -isnot [array] -or $migrated.writePaths.Count -ne 1 -or $migrated.writePaths[0] -cne 'src/code.ts' -or $migrated.regressionCheck -cne '' -or
       $migrated.schemaVersion -ne 2 -or $migrated.testWritePaths.Count -ne 1 -or $migrated.testWritePaths[0] -cne 'tests/code.test.ts' -or
       $migrated.acceptanceCriteria -isnot [array] -or $migrated.acceptanceCriteria.Count -or $migrated.changeTypes -isnot [array] -or $migrated.changeTypes.Count){
        throw 'Checks migration did not preserve user data and add safe defaults'
    }
    $workspace=Get-Content -LiteralPath $entry.workspace -Raw|ConvertFrom-Json
    if($workspace.settings.'editor.tabSize' -ne 3 -or $workspace.tasks.tasks.label -notcontains 'Personal Task' -or
       $workspace.tasks.tasks[0].command -ceq 'old-powershell.exe'){
        throw 'Managed workspace task was not updated or custom settings were lost'
    }
    $currentGuide=Join-Path (Split-Path -Parent $entry.task) 'LOKI-WORKFLOW.md'
    if(-not(Test-Path -LiteralPath $currentGuide) -or [IO.File]::ReadAllText($currentGuide) -cne [IO.File]::ReadAllText((Join-Path $SourceRoot 'WORKFLOW.md')).Replace('(WORKFLOW.de.md)','(LOKI-WORKFLOW.de.md)')){throw 'Managed current guide missing or stale'}
    $newEntry=@($updated.Entries | Where-Object {$_.project -ceq $new})[0]
    $fresh=Get-Content -LiteralPath $newEntry.checks -Raw | ConvertFrom-Json
    if($fresh.schemaVersion -ne 2 -or $fresh.testWritePaths.Count -or $fresh.acceptanceCriteria.Count -or $fresh.changeTypes.Count){throw 'Fresh workspace does not have safe v2 defaults'}
    $backupFiles=@(Get-ChildItem -LiteralPath (Join-Path $managed 'backups/project-checks') -File -Recurse)
    if(-not @($backupFiles | Where-Object {[IO.File]::ReadAllText($_.FullName) -ceq $checkText}).Count){throw 'Original policy was not backed up before migration'}
    $checkText=[IO.File]::ReadAllText($entry.checks)
    $again=New-ShadowWorkspace -Root $managed -Project $project -PwshPath (Get-Process -Id $PID).Path
    if([IO.File]::ReadAllText($again.task) -cne $taskText -or [IO.File]::ReadAllText($again.checks) -cne $checkText -or
       [IO.File]::ReadAllText($guide) -cne $guideText -or [IO.File]::ReadAllText($projectFile) -cne 'existing project'){
        throw 'Existing project or user-managed task, checks or guide was overwritten'
    }
    [pscustomobject]@{suite='Workspace guide and provisioning migration';passed=$true;checks=12}|ConvertTo-Json
}finally{
    $resolved=[IO.Path]::GetFullPath($root)
    if(-not $resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notlike 'shadow-workspace-guide-*'){throw 'Unsafe cleanup path'}
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
