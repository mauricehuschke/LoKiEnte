#requires -Version 7.4
param([string]$SourceRoot=(Split-Path -Parent $PSScriptRoot))
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $SourceRoot 'ProjectSelection.ps1')
. (Join-Path $SourceRoot 'Common.ps1')
. (Join-Path $SourceRoot 'Workspace.ps1')
$root=Join-Path ([IO.Path]::GetTempPath()) ('shadow-project-selection-'+[guid]::NewGuid().ToString('N'))
$script:answers=[Collections.Generic.Queue[string]]::new()
$script:count=0
function Read-Host { param($Prompt)
    if(-not $script:answers.Count){throw "Unexpected prompt: $Prompt"}
    return $script:answers.Dequeue()
}
function Assert-Selection([bool]$Value,[string]$Message){
    if(-not $Value){throw $Message}
    $script:count++
}
function Set-Answers([string[]]$Values){
    $script:answers.Clear()
    foreach($value in $Values){$script:answers.Enqueue($value)}
}
New-Item -ItemType Directory -Path $root | Out-Null
try{
    $project=Join-Path $root "Projekt ä & [test]'s"
    $second=Join-Path $root 'Second project'
    $missing=Join-Path $root 'Moved project'
    New-Item -ItemType Directory -Path $project,$second | Out-Null
    [IO.File]::WriteAllText((Join-Path $project 'keep.txt'),'unchanged')
    $index=Join-Path $root 'workspaces.json'
    Set-Answers @('0')
    Assert-Selection ($null -eq (Select-ShadowProject -InstallRoot $root)) 'Empty-list cancel failed'
    Assert-Selection (-not(Test-Path -LiteralPath $index)) 'Cancel must not create an index'
    Set-Answers @('bad','2147483648','N','','N',('"' + $project + '"'))
    $selected=Select-ShadowProject -InstallRoot $root
    Assert-Selection ($selected -ceq $project) 'New path with quotes/Unicode/metacharacters failed'
    Assert-Selection ($script:answers.Count -eq 0) 'Input recovery did not consume expected answers'
    $entry=New-ShadowWorkspace -Root $root -Project $selected -PwshPath (Get-Process -Id $PID).Path
    Register-ShadowWorkspaces -Root $root -Entries @($entry)
    Set-Answers @('1')
    Assert-Selection ((Select-ShadowProject -InstallRoot $root) -ceq $project) 'Registered project not selectable'
    $other=New-ShadowWorkspace -Root $root -Project $second -PwshPath (Get-Process -Id $PID).Path
    Register-ShadowWorkspaces -Root $root -Entries @($other)
    Set-Answers @('2')
    Assert-Selection ((Select-ShadowProject -InstallRoot $root) -ceq $second) 'Second project not retained'
    $raw=ConvertTo-Json -InputObject @(@{project=$missing},@{project=$project}) -Depth 5
    [IO.File]::WriteAllText($index,$raw)
    Set-Answers @('1','N',(Join-Path $project 'keep.txt'),'2')
    Assert-Selection ((Select-ShadowProject -InstallRoot $root) -ceq $project) 'Missing path/file recovery failed'
    Assert-Selection ([IO.File]::ReadAllText($index) -ceq $raw) 'Selection rewrote the index'
    Set-Answers @()
    Assert-Selection ((Select-ShadowProject -InstallRoot $root -ProjectPath $second) -ceq $second) 'Explicit path prompted'
    $failed=$false
    try { $null=Select-ShadowProject -InstallRoot $root -ProjectPath $missing } catch {$failed=$true}
    Assert-Selection $failed 'Explicit missing path must fail'
    [IO.File]::WriteAllText($index,'{"broken":true}')
    $failed=$false
    try { $null=Select-ShadowProject -InstallRoot $root } catch {$failed=$true}
    Assert-Selection $failed 'Malformed index must not be silently overwritten'
    Assert-Selection ([IO.File]::ReadAllText((Join-Path $project 'keep.txt')) -ceq 'unchanged') 'Project content changed'

    # Run the real launcher in a child with inert module boundaries. Cancellation
    # must finish before any runtime initialization; no VS Code/model is started.
    $app=Join-Path $root 'launcher-fixture'
    New-Item -ItemType Directory -Path $app | Out-Null
    Copy-Item -LiteralPath (Join-Path $SourceRoot 'Start-LocalAI.ps1'),(Join-Path $SourceRoot 'ProjectSelection.ps1') -Destination $app
    foreach($module in @('Runtime','ModelSelection','Ripgrep','ModelPool','Router','AgentTemplates','Workspace')){
        [IO.File]::WriteAllText((Join-Path $app ($module+'.ps1')),'')
    }
    [IO.File]::WriteAllText((Join-Path $app 'Common.ps1'),@'
function Read-Host {param($Prompt) return '0'}
function Assert-ShadowRipgrepReady {param($InstallRoot) throw 'Runtime was reached after cancel'}
'@)
    $result=Invoke-ShadowNative -FilePath (Get-Process -Id $PID).Path -ArgumentList @('-NoProfile','-File',(Join-Path $app 'Start-LocalAI.ps1'),'-InstallRoot',$app) -AllowFailure -Quiet -TimeoutSeconds 30
    Assert-Selection ($result.ExitCode -eq 0 -and $result.StdOut -like '*Startup cancelled*') 'Launcher cancellation reached runtime or failed'
    $result=Invoke-ShadowNative -FilePath (Get-Process -Id $PID).Path -ArgumentList @('-NoProfile','-File',(Join-Path $app 'Start-LocalAI.ps1'),'-InstallRoot',$app,'-ProjectPath',$missing,'-PauseOnError') -AllowFailure -Quiet -TimeoutSeconds 30
    Assert-Selection ($result.ExitCode -eq 1 -and $result.StdErr -notlike '*Runtime was reached*') 'Explicit invalid path did not fail before runtime'
    [pscustomobject]@{suite='Project selection and launcher cancellation';passed=$true;checks=$script:count}|ConvertTo-Json
}finally{
    $resolved=[IO.Path]::GetFullPath($root)
    if(-not $resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase) -or
       [IO.Path]::GetFileName($resolved) -notlike 'shadow-project-selection-*'){throw 'Unexpected cleanup target'}
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
