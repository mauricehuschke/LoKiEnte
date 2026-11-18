#requires -Version 7.4
# Bounded structured progress consumed by the local Kilo tools; never executable data.
function Initialize-ShadowWorkflowProgress {
    param([string]$InstallRoot,[string]$RunPath,[string]$ProgressFile)
    $script:ShadowWorkflowProgressPath=Join-Path $RunPath 'workflow-events.jsonl'
    if($ProgressFile){
        $path=[IO.Path]::GetFullPath($ProgressFile)
        $jobs=[IO.Path]::GetFullPath((Join-Path $InstallRoot 'workflow-jobs')).TrimEnd('\','/')
        if(-not $path.StartsWith($jobs+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or
           [IO.Path]::GetFileName($path) -cne 'events.jsonl'){throw 'ProgressFile muss events.jsonl in einem lokalen Workflowjob sein.'}
        $cursor=[IO.DirectoryInfo]::new([IO.Path]::GetDirectoryName($path))
        while($cursor -and $cursor.FullName.Length -ge $jobs.Length){
            if($cursor.Exists -and ($cursor.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Verknuepfung im Fortschrittspfad.'}
            $cursor=$cursor.Parent
        }
        if(Test-Path -LiteralPath $path){
            $item=Get-Item -LiteralPath $path -Force
            if($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Ungueltige Fortschrittsdatei.'}
        }
        $script:ShadowWorkflowProgressPath=$path
    }
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($script:ShadowWorkflowProgressPath))
}

function Write-ShadowWorkflowProgress {
    param([string]$Phase,[string]$Role='runner',[string]$Model='',
        [string]$State='running',[string]$Message='',[string]$SessionId='',
        [string]$Tool='',[hashtable]$Extra=@{})
    $event=[ordered]@{time=[DateTime]::UtcNow.ToString('o');phase=$Phase;role=$Role;model=$Model;state=$State;message=$Message;sessionId=$SessionId;tool=$Tool}
    foreach($key in $Extra.Keys){if(-not $event.Contains($key)){$event[$key]=$Extra[$key]}}
    [IO.File]::AppendAllText($script:ShadowWorkflowProgressPath,($event|ConvertTo-Json -Depth 6 -Compress)+"`n",[Text.UTF8Encoding]::new($false))
}

function Write-ShadowAgentProgress {
    param([string]$Line,[string]$Phase,[string]$Role,[string]$Model)
    if($Line.Length -gt 1048576){return}
    try{$event=ConvertFrom-Json -InputObject $Line -AsHashtable -NoEnumerate -ErrorAction Stop}catch{return}
    if($event -isnot [Collections.IDictionary] -or -not $event.Contains('type')){return}
    $session=if($event.Contains('sessionID')){[string]$event.sessionID}else{''}
    if($event.type -ceq 'tool_use' -and $event.Contains('part') -and $event.part -is [Collections.IDictionary]){
        $tool=if($event.part.Contains('tool')){[string]$event.part.tool}else{'tool'}
        $state='tool';$message='Werkzeug aktiv'
        if($event.part.Contains('state') -and $event.part.state -is [Collections.IDictionary] -and $event.part.state.Contains('status')){
            $message='Werkzeug: '+[string]$event.part.state.status
        }
        Write-ShadowWorkflowProgress -Phase $Phase -Role $Role -Model $Model -State $state -Message $message -SessionId $session -Tool $tool
    }elseif($event.type -cin @('step_start','step_finish','error','text')){
        $message=switch -CaseSensitive ($event.type){'step_start'{'Agent arbeitet'} 'step_finish'{'Agentenschritt abgeschlossen'} 'error'{'Agent meldet Fehler'} 'text'{'Agentenantwort eingegangen'}}
        Write-ShadowWorkflowProgress -Phase $Phase -Role $Role -Model $Model -State 'activity' -Message $message -SessionId $session
    }
}
