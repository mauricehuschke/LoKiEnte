# Workspace definitions live outside existing repositories. Requires Common.ps1.
function Get-ShadowWorkspaceIndex {
    param([string]$Root)
    $index=Join-Path $Root 'workspaces.json'
    if(-not(Test-Path -LiteralPath $index)){return}
    $entries=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($index)) -AsHashtable -NoEnumerate
    if($entries -isnot [array]){throw "Workspace index is not a list: $index"}
    foreach($entry in $entries){
        if($entry -isnot [Collections.IDictionary] -or -not $entry.Contains('project') -or
           $entry.project -isnot [string] -or -not [IO.Path]::IsPathFullyQualified($entry.project)){
            throw "Workspace index contains no valid absolute project path: $index"
        }
        $entry
    }
}

function Update-ShadowWorkspaces {
    param([string]$Root,[string]$PwshPath,[string[]]$ProjectPath=@())
    $paths=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $entries=[Collections.Generic.List[object]]::new()
    $warnings=[Collections.Generic.List[string]]::new()
    $known=@(Get-ShadowWorkspaceIndex -Root $Root)
    foreach($path in (@($known | ForEach-Object {$_.project})+@($ProjectPath))){
        if(-not(Test-Path -LiteralPath $path -PathType Container)){
            $warnings.Add("Registered project temporarily unavailable: $path")
            continue
        }
        $full=(Resolve-Path -LiteralPath $path).ProviderPath
        if($paths.Add($full)){$entries.Add((New-ShadowWorkspace -Root $Root -Project $full -PwshPath $PwshPath))}
    }
    if($entries.Count){Register-ShadowWorkspaces -Root $Root -Entries $entries.ToArray()}
    return [pscustomobject]@{Entries=$entries.ToArray();Warnings=$warnings.ToArray()}
}

function New-ShadowWorkspace {
    param([string]$Root,[string]$Project,[string]$PwshPath)
    $projectFull=(Resolve-Path -LiteralPath $Project).Path
    $hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($projectFull.ToLowerInvariant()))).Substring(0,12)
    $safeName=([IO.Path]::GetFileName($projectFull.TrimEnd('\','/')) -replace '[^a-zA-Z0-9_-]','_')
    if (-not $safeName) { $safeName='project' }
    $workspaceFile=Join-Path $Root "workspaces/$safeName-$hash.code-workspace"
    $projectState=Join-Path $Root "projects/$safeName-$hash"
    [IO.Directory]::CreateDirectory($projectState) | Out-Null
    $taskPath=Join-Path $projectState 'task.md'
    $checksPath=Join-Path $projectState 'checks.json'
    $checksDescription='Enter tasks directly in Kilo shadow-chat. Criteria, file scope and local test checks are prepared automatically for each task and independently reviewed. Custom checks and boundaries are preserved; see LOKI-WORKFLOW.md.'
    $guidePath=Join-Path $projectState 'GUIDE.md'
    $guideText=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'WORKFLOW.md')).Replace('(WORKFLOW.de.md)','(LOKI-WORKFLOW.de.md)')
    if(-not(Test-Path -LiteralPath $guidePath)){
        $temporary=$guidePath+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
        try{
            $file=[IO.File]::Open($temporary,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
            try{
                $writer=[IO.StreamWriter]::new($file,[Text.UTF8Encoding]::new($false))
                try{$writer.Write($guideText);$writer.Flush()}finally{$writer.Dispose()}
            }finally{$file.Dispose()}
            [IO.File]::Move($temporary,$guidePath)
        }finally{if(Test-Path -LiteralPath $temporary){Remove-Item -LiteralPath $temporary -Force}}
    }
    $null=Write-ShadowManagedFile -Path (Join-Path $projectState 'LOKI-WORKFLOW.md') -Content $guideText -BackupRoot (Join-Path $Root 'backups/workspaces')
    $germanGuide=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'WORKFLOW.de.md')).Replace('(WORKFLOW.md)','(LOKI-WORKFLOW.md)')
    $null=Write-ShadowManagedFile -Path (Join-Path $projectState 'LOKI-WORKFLOW.de.md') -Content $germanGuide -BackupRoot (Join-Path $Root 'backups/workspaces')
    if(-not(Test-Path -LiteralPath (Join-Path $projectState 'GUIDE.de.md'))){
        [IO.File]::WriteAllText((Join-Path $projectState 'GUIDE.de.md'),$germanGuide,[Text.UTF8Encoding]::new($false))
    }
    if(-not(Test-Path -LiteralPath (Join-Path $projectState 'task.de.md'))){
        [IO.File]::WriteAllText((Join-Path $projectState 'task.de.md'),[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'templates/task.de.md')),[Text.UTF8Encoding]::new($false))
    }
    if (-not (Test-Path -LiteralPath $taskPath)) {
        $template=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'templates/task.md'))
        $null=Write-ShadowManagedFile -Path $taskPath -Content $template
    }
    if (-not (Test-Path -LiteralPath $checksPath)) {
        $checks=[ordered]@{
            description=$checksDescription
            schemaVersion=2
            testWritePaths=@()
            acceptanceCriteria=@()
            changeTypes=@()
            writePaths=@()
            regressionCheck=''
            checks=@()
        }
        $null=Write-ShadowManagedFile -Path $checksPath -Content ($checks|ConvertTo-Json -Depth 10)
    }else{
        $checks=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($checksPath)) -NoEnumerate -AsHashtable
        if($checks -isnot [Collections.IDictionary]){throw "Project checks are not a JSON object: $checksPath"}
        $migrated=$false
        if($checks.Contains('description') -and $checks.description -cin @(
            'Read WORKFLOW.md: specify production/test files, fixed criteria, categories and confirmed checks with reports.',
            'Auftrag direkt in Kilo shadow-chat eingeben. Kriterien, Dateiumfang und lokale Testchecks werden pro Auftrag automatisch vorbereitet und unabhaengig geprueft. Eigene Checks und Grenzen bleiben erhalten; siehe LOKI-WORKFLOW.md.',
            'WORKFLOW.md lesen: Produktions-/Testdateien, feste Kriterien, Kategorien und bestaetigte Checks mit Berichten eintragen.'
        )){
            $checks.description=$checksDescription;$migrated=$true
        }
        foreach($key in @('checks','writePaths','regressionCheck')){
            if(-not $checks.Contains($key)){
                $checks[$key]=if($key -ceq 'regressionCheck'){''}else{,@()}
                $migrated=$true
            }
        }
        if(-not $checks.Contains('schemaVersion')){$checks.schemaVersion=2;$migrated=$true}
        if(-not $checks.Contains('testWritePaths')){
            # Only split already authorized paths; never infer new write authority.
            $tests=@($checks.writePaths | Where-Object {$_ -is [string] -and $_ -match '(?i)(?:^|/)(?:tests?|__tests__|specs?)/|\.(?:test|spec)\.|(?:^|/)test_[^/]+$|_test\.[^/]+$'})
            $checks.testWritePaths=$tests
            $checks.writePaths=@($checks.writePaths | Where-Object {$_ -notin $tests})
            $migrated=$true
        }
        foreach($key in @('acceptanceCriteria','changeTypes')){
            if(-not $checks.Contains($key)){$checks[$key]=@();$migrated=$true}
        }
        if($migrated){$null=Write-ShadowManagedFile -Path $checksPath -Content ($checks|ConvertTo-Json -Depth 100) -BackupRoot (Join-Path $Root 'backups/project-checks')}
    }
    $runner=Join-Path $Root 'app/Invoke-ReviewedTask.ps1'
    $baseArgs=@('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',$runner,'-InstallRoot',$Root,'-ProjectPath',$projectFull,'-TaskFile',$taskPath,'-ChecksFile',$checksPath,'-AutoPrepare')
    $tasks=[Collections.Generic.List[object]]::new()
    foreach ($workflow in @('Auto','Feature','Bugfix','Refactor','Review','Architecture')) {
        $tasks.Add([ordered]@{
            label=$(if($workflow -ceq 'Auto'){'Local AI: Automatic task with verification'}else{"Local AI: $workflow with verification"});type='process';command=$PwshPath
            detail='Prepare an optional task from task.md, independently review checks.json and run the quality workflow.'
            args=@($baseArgs)+@('-Workflow',$workflow)
            options=@{cwd=$projectFull};problemMatcher=@()
            presentation=@{reveal='always';panel='dedicated';clear=$false}
            runOptions=@{instanceLimit=1}
        })
        if($workflow -in @('Feature','Bugfix','Refactor')){
            $tasks.Add([ordered]@{
                label="Local AI: $workflow (Coder Fast) with verification";type='process';command=$PwshPath
                args=@($baseArgs)+@('-Workflow',$workflow,'-CoderProfile','Fast')
                options=@{cwd=$projectFull};problemMatcher=@()
                presentation=@{reveal='always';panel='dedicated';clear=$false}
                runOptions=@{instanceLimit=1}
            })
        }
    }
    $workspace=[ordered]@{
        folders=@(@{name=$safeName;path=$projectFull},@{name='Local AI - Task and checks';path=$projectState})
        settings=[ordered]@{
            'chat.disableAIFeatures'=$true
            'kilo-code.new.autocomplete.enableAutoTrigger'=$false
            'kilo-code.new.autocomplete.enableSmartInlineTaskKeybinding'=$false
            'kilo-code.new.autocomplete.enableChatAutocomplete'=$false
        }
        tasks=@{version='2.0.0';tasks=@($tasks)}
    }
    if(Test-Path -LiteralPath $workspaceFile -PathType Leaf){
        $existing=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($workspaceFile)) -NoEnumerate -AsHashtable
        if($existing -isnot [Collections.IDictionary]){throw "Workspace is not a JSON object: $workspaceFile"}
        if($existing.Contains('settings')){
            if($existing.settings -isnot [Collections.IDictionary]){throw "Workspace settings are not a JSON object: $workspaceFile"}
            foreach($key in $workspace.settings.Keys){$existing.settings[$key]=$workspace.settings[$key]}
        }else{$existing.settings=$workspace.settings}
        if(-not $existing.Contains('tasks')){$existing.tasks=@{}}
        if($existing.tasks -isnot [Collections.IDictionary]){throw "Workspace tasks are not a JSON object: $workspaceFile"}
        $labels=@($workspace.tasks.tasks | ForEach-Object {$_.label})
        # Recognize legacy managed labels without removing unrelated user tasks.
        $legacyLabels=@('Local AI: Auftrag automatisch mit Pruefung')
        foreach($legacyWorkflow in @('Feature','Bugfix','Refactor','Review','Architecture')){
            $legacyLabels+="Local AI: $legacyWorkflow mit Pruefung"
            if($legacyWorkflow -in @('Feature','Bugfix','Refactor')){$legacyLabels+="Local AI: $legacyWorkflow (Coder Fast) mit Pruefung"}
        }
        $custom=@($existing.tasks['tasks'] | Where-Object {
            $_ -is [Collections.IDictionary] -and $_['label'] -notin $labels -and
            -not($_['label'] -in $legacyLabels -and $_['type'] -ceq 'process' -and @($_['args']) -contains $runner)
        })
        $existing.tasks.version='2.0.0'
        $existing.tasks.tasks=@($workspace.tasks.tasks)+$custom
        $extraFolders=@($existing['folders'] | Where-Object {
            $_ -is [Collections.IDictionary] -and $_['path'] -ne $projectState -and $_['path'] -ne $projectFull
        })
        $existing.folders=@($workspace.folders)+$extraFolders
        $workspace=$existing
    }
    $null=Write-ShadowManagedFile -Path $workspaceFile -Content ($workspace|ConvertTo-Json -Depth 20) -BackupRoot (Join-Path $Root 'backups/workspaces')
    return [ordered]@{project=$projectFull;workspace=$workspaceFile;task=$taskPath;checks=$checksPath}
}

function Register-ShadowWorkspaces {
    param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][object[]]$Entries)
    $index=Join-Path $Root 'workspaces.json'
    $byPath=[ordered]@{}
    foreach($entry in @(Get-ShadowWorkspaceIndex -Root $Root)){$byPath[$entry.project]=$entry}
    foreach($entry in $Entries){$byPath[[string]$entry.project]=$entry}
    $json=ConvertTo-Json -InputObject @($byPath.Values) -Depth 15
    $null=Write-ShadowManagedFile -Path $index -Content $json -BackupRoot (Join-Path $Root 'backups/workspaces')
}

