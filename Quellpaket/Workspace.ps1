# Workspace definitions live outside existing repositories. Requires Common.ps1.
function Get-ShadowWorkspaceIndex {
    param([string]$Root)
    $index=Join-Path $Root 'workspaces.json'
    if(-not(Test-Path -LiteralPath $index)){return}
    $entries=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($index)) -AsHashtable -NoEnumerate
    if($entries -isnot [array]){throw "Arbeitsbereichsindex ist keine Liste: $index"}
    foreach($entry in $entries){
        if($entry -isnot [Collections.IDictionary] -or -not $entry.Contains('project') -or
           $entry.project -isnot [string] -or -not [IO.Path]::IsPathFullyQualified($entry.project)){
            throw "Arbeitsbereichsindex enthaelt keinen gueltigen absoluten Projektpfad: $index"
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
            $warnings.Add("Registriertes Projekt voruebergehend nicht erreichbar: $path")
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
    $checksDescription='Auftrag direkt in Kilo shadow-chat eingeben. Kriterien, Dateiumfang und lokale Testchecks werden pro Auftrag automatisch vorbereitet und unabhaengig geprueft. Eigene Checks und Grenzen bleiben erhalten; siehe LOKI-WORKFLOW.md.'
    $guidePath=Join-Path $projectState 'ANLEITUNG.md'
    $guideText=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'WORKFLOW.md'))
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
    if (-not (Test-Path -LiteralPath $taskPath)) {
        $template=@'
# Auftrag

Optionaler Dateiauftrag: Beschreibe eine kleine, klar abgegrenzte Aenderung.
Alternativ den Auftrag direkt im Kilo-Agenten shadow-chat eingeben.

## Anforderungen
- ...

## Erwartetes Ergebnis
- ... (Akzeptanzkriterien und passende Checks werden automatisch abgeleitet und geprueft)

## Grenzen und betroffene Bereiche
- Bestehende AGENTS.md, SSOT und Architekturentscheidungen beruecksichtigen.
- Keine Datenbankmigration anwenden, kein Deployment, kein Push.

## Hinweise fuer Reviewer
- ...
'@
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
        if($checks -isnot [Collections.IDictionary]){throw "Projektpruefungen sind kein JSON-Objekt: $checksPath"}
        $migrated=$false
        if($checks.Contains('description') -and $checks.description -ceq 'WORKFLOW.md lesen: Produktions-/Testdateien, feste Kriterien, Kategorien und bestaetigte Checks mit Berichten eintragen.'){
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
            label=$(if($workflow -ceq 'Auto'){'Local AI: Auftrag automatisch mit Pruefung'}else{"Local AI: $workflow mit Pruefung"});type='process';command=$PwshPath
            detail='Optionalen Auftrag aus task.md vorbereiten, checks.json unabhaengig pruefen und Qualitaetsworkflow ausfuehren.'
            args=@($baseArgs)+@('-Workflow',$workflow)
            options=@{cwd=$projectFull};problemMatcher=@()
            presentation=@{reveal='always';panel='dedicated';clear=$false}
            runOptions=@{instanceLimit=1}
        })
        if($workflow -in @('Feature','Bugfix','Refactor')){
            $tasks.Add([ordered]@{
                label="Local AI: $workflow (Coder Fast) mit Pruefung";type='process';command=$PwshPath
                args=@($baseArgs)+@('-Workflow',$workflow,'-CoderProfile','Fast')
                options=@{cwd=$projectFull};problemMatcher=@()
                presentation=@{reveal='always';panel='dedicated';clear=$false}
                runOptions=@{instanceLimit=1}
            })
        }
    }
    $workspace=[ordered]@{
        folders=@(@{name=$safeName;path=$projectFull},@{name='Local AI - Auftrag und Checks';path=$projectState})
        settings=[ordered]@{
            'kilo-code.new.autocomplete.enableAutoTrigger'=$false
            'kilo-code.new.autocomplete.enableSmartInlineTaskKeybinding'=$false
            'kilo-code.new.autocomplete.enableChatAutocomplete'=$false
        }
        tasks=@{version='2.0.0';tasks=@($tasks)}
    }
    if(Test-Path -LiteralPath $workspaceFile -PathType Leaf){
        $existing=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($workspaceFile)) -NoEnumerate -AsHashtable
        if($existing -isnot [Collections.IDictionary]){throw "Workspace ist kein JSON-Objekt: $workspaceFile"}
        if($existing.Contains('settings')){
            if($existing.settings -isnot [Collections.IDictionary]){throw "Workspace-Settings sind kein JSON-Objekt: $workspaceFile"}
            foreach($key in $workspace.settings.Keys){$existing.settings[$key]=$workspace.settings[$key]}
        }else{$existing.settings=$workspace.settings}
        if(-not $existing.Contains('tasks')){$existing.tasks=@{}}
        if($existing.tasks -isnot [Collections.IDictionary]){throw "Workspace-Tasks sind kein JSON-Objekt: $workspaceFile"}
        $labels=@($workspace.tasks.tasks | ForEach-Object {$_.label})
        $custom=@($existing.tasks['tasks'] | Where-Object {
            $_ -is [Collections.IDictionary] -and $_['label'] -notin $labels
        })
        $existing.tasks.version='2.0.0'
        $existing.tasks.tasks=@($workspace.tasks.tasks)+$custom
        $extraFolders=@($existing['folders'] | Where-Object {
            $_ -is [Collections.IDictionary] -and $_['name'] -ne 'Local AI - Auftrag und Checks' -and $_['path'] -ne $projectFull
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

