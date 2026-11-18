#requires -Version 7.4
[CmdletBinding()]
param([string]$SourceRoot=(Split-Path -Parent $PSScriptRoot))
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
foreach($name in @('Common.ps1','Workspace.ps1','AgentTemplates.ps1')){. (Join-Path $SourceRoot $name)}
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('lokiente-language-'+[guid]::NewGuid().ToString('N'))
$project=Join-Path $fixture 'project'
$managed=Join-Path $fixture 'managed'
$count=0
function Assert-Language([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message};$script:count++}
try{
    [void][IO.Directory]::CreateDirectory($project)
    $entry=New-ShadowWorkspace -Root $managed -Project $project -PwshPath (Get-Process -Id $PID).Path
    $state=Split-Path -Parent $entry.task
    foreach($name in @('GUIDE.md','GUIDE.de.md','LOKI-WORKFLOW.md','LOKI-WORKFLOW.de.md','task.md','task.de.md')){
        Assert-Language (Test-Path -LiteralPath (Join-Path $state $name) -PathType Leaf) "Missing generated guide: $name"
    }
    Assert-Language ([IO.File]::ReadAllText($entry.task).StartsWith('# Task')) 'Default task is not English'
    Assert-Language ([IO.File]::ReadAllText((Join-Path $state 'task.de.md')).StartsWith('# Auftrag')) 'German task template was not retained'
    Assert-Language ([IO.File]::ReadAllText((Join-Path $state 'GUIDE.md')).Contains('(LOKI-WORKFLOW.de.md)')) 'English deployed language link is invalid'
    Assert-Language ([IO.File]::ReadAllText((Join-Path $state 'GUIDE.de.md')).Contains('(LOKI-WORKFLOW.md)')) 'German deployed language link is invalid'
    $legacyGuide=Join-Path $state 'ANLEITUNG.md'
    [IO.File]::WriteAllText($legacyGuide,'Personal legacy guide')
    [IO.File]::WriteAllText($entry.task,'Personal task')
    [IO.File]::WriteAllText((Join-Path $state 'task.de.md'),'Personal German task')
    $checks=Get-Content -LiteralPath $entry.checks -Raw|ConvertFrom-Json -AsHashtable
    $checks.description='Auftrag direkt in Kilo shadow-chat eingeben. Kriterien, Dateiumfang und lokale Testchecks werden pro Auftrag automatisch vorbereitet und unabhaengig geprueft. Eigene Checks und Grenzen bleiben erhalten; siehe LOKI-WORKFLOW.md.'
    $checks['custom']='preserve'
    [IO.File]::WriteAllText($entry.checks,($checks|ConvertTo-Json -Depth 20))
    $workspace=Get-Content -LiteralPath $entry.workspace -Raw|ConvertFrom-Json -AsHashtable
    foreach($task in $workspace.tasks.tasks){
        $task.label=if($task.label -eq 'Local AI: Automatic task with verification'){'Local AI: Auftrag automatisch mit Pruefung'}else{$task.label.Replace('with verification','mit Pruefung')}
    }
    $workspace.folders[1].name='Local AI - Auftrag und Checks'
    $customFolder=Join-Path $fixture 'personal-folder'
    $workspace.folders+=@{name='Local AI - Task and checks';path=$customFolder}
    $workspace.tasks.tasks+=@{label='Local AI: Feature mit Pruefung';type='process';command='personal.exe';args=@('custom')}
    $workspace.settings['editor.tabSize']=3
    [IO.File]::WriteAllText($entry.workspace,($workspace|ConvertTo-Json -Depth 20))
    $null=New-ShadowWorkspace -Root $managed -Project $project -PwshPath (Get-Process -Id $PID).Path
    $updated=Get-Content -LiteralPath $entry.workspace -Raw|ConvertFrom-Json
    Assert-Language (@($updated.tasks.tasks|Where-Object label -Like '*with verification').Count -eq 9) 'Managed English tasks missing or duplicated'
    $remaining=@($updated.tasks.tasks|Where-Object label -Like '*mit Pruefung')
    Assert-Language ($remaining.Count -eq 1 -and $remaining[0].command -ceq 'personal.exe') 'Legacy tasks were duplicated or custom task lost'
    Assert-Language ($updated.folders.Count -eq 3 -and $updated.folders[1].name -ceq 'Local AI - Task and checks') 'Legacy managed folder was duplicated'
    Assert-Language ($updated.folders[2].path -ceq $customFolder) 'Unrelated folder with the managed display name was removed'
    Assert-Language ($updated.settings.'editor.tabSize' -eq 3) 'Custom workspace settings changed'
    $checks=Get-Content -LiteralPath $entry.checks -Raw|ConvertFrom-Json
    Assert-Language ($checks.description.StartsWith('Enter tasks directly') -and $checks.custom -ceq 'preserve') 'Legacy managed description or custom check data migrated incorrectly'
    Assert-Language ([IO.File]::ReadAllText($legacyGuide) -ceq 'Personal legacy guide') 'Legacy personal guide was overwritten'
    Assert-Language ([IO.File]::ReadAllText($entry.task) -ceq 'Personal task' -and [IO.File]::ReadAllText((Join-Path $state 'task.de.md')) -ceq 'Personal German task') 'Personal task text was overwritten'
    $checks=Get-Content -LiteralPath $entry.checks -Raw|ConvertFrom-Json -AsHashtable
    $checks.description='Custom description'
    [IO.File]::WriteAllText($entry.checks,($checks|ConvertTo-Json -Depth 20))
    $null=New-ShadowWorkspace -Root $managed -Project $project -PwshPath (Get-Process -Id $PID).Path
    Assert-Language ((Get-Content -LiteralPath $entry.checks -Raw|ConvertFrom-Json).description -ceq 'Custom description') 'Custom description overwritten'
    $configuration=New-ShadowAgentConfiguration -InstallRoot $managed -ModelId 'fixture-local' -ApiBaseUrl 'http://127.0.0.1:1234/v1'
    Assert-Language ($configuration.Config.instructions.Count -eq 1 -and $configuration.Config.instructions[0] -ceq $configuration.RulesPath) 'German reference was activated as additional agent instructions'
    Assert-Language ([IO.File]::ReadAllText($configuration.RulesPath).Contains('Answer in English by default.')) 'Active rules do not default to English'
    Assert-Language (Test-Path -LiteralPath (Join-Path $managed 'kilo-managed/LOCAL-AI-RULES.de.md')) 'German rule reference missing'

    $welcome=& (Join-Path $SourceRoot 'New-WelcomeTestProject.ps1') -InstallRoot $managed
    $readme=Join-Path $welcome.project 'README.md'
    $german=Join-Path $welcome.project 'README.de.md'
    Assert-Language (Test-Path -LiteralPath $german) 'New Welcome project has no German README'
    $git=Resolve-ShadowTool git
    $head=(Invoke-ShadowNative $git @('-C',$welcome.project,'rev-parse','HEAD') -Quiet).StdOut
    $source=Join-Path $welcome.project 'discount.cjs'
    [IO.File]::AppendAllText($source,"`n// User work")
    $sourceHash=(Get-FileHash -LiteralPath $source).Hash
    $originalGerman=([IO.File]::ReadAllText($german) -replace '(?s)<!-- lokiente-language -->.*?<!-- /lokiente-language -->','') -replace '(\r?\n){3,}',"`r`n`r`n"
    [IO.File]::WriteAllText($readme,$originalGerman)
    [IO.File]::Delete($german)
    $null=& (Join-Path $SourceRoot 'New-WelcomeTestProject.ps1') -InstallRoot $managed
    Assert-Language ([IO.File]::ReadAllText($readme) -ceq [IO.File]::ReadAllText((Join-Path $SourceRoot 'welcome-example/README.md'))) 'Unmodified legacy Welcome guide did not migrate to English'
    Assert-Language (Test-Path -LiteralPath $german) 'Existing Welcome project did not receive German companion'
    Assert-Language (@(Get-ChildItem -LiteralPath (Join-Path $managed 'backups/welcome') -File -Recurse|Where-Object {[IO.File]::ReadAllText($_.FullName) -ceq $originalGerman}).Count -eq 1) 'Legacy guide was not backed up exactly'
    Assert-Language ((Get-FileHash -LiteralPath $source).Hash -ceq $sourceHash -and (Invoke-ShadowNative $git @('-C',$welcome.project,'rev-parse','HEAD') -Quiet).StdOut -ceq $head) 'Guide migration changed user code or committed changes'
    [IO.File]::WriteAllText($readme,'Customized Welcome guide')
    [IO.File]::WriteAllText($german,'Customized German guide')
    $null=& (Join-Path $SourceRoot 'New-WelcomeTestProject.ps1') -InstallRoot $managed
    Assert-Language ([IO.File]::ReadAllText($readme) -ceq 'Customized Welcome guide' -and [IO.File]::ReadAllText($german) -ceq 'Customized German guide') 'Customized Welcome guides overwritten'
    [pscustomobject]@{suite='English defaults and German companion migration';passed=$true;checks=$count}|ConvertTo-Json
}finally{
    $resolved=[IO.Path]::GetFullPath($fixture)
    if(-not $resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notlike 'lokiente-language-*'){throw 'Unsafe cleanup path'}
    if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
