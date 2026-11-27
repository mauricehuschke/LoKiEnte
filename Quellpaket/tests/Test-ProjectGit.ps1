#requires -Version 7.4
param([string]$SourceRoot=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
foreach($file in @('Common.ps1','Workspace.ps1','ProjectSelection.ps1')){. (Join-Path $SourceRoot $file)}
$testBase=Join-Path (Split-Path -Parent $SourceRoot) '.local';[void][IO.Directory]::CreateDirectory($testBase)
$root=Join-Path $testBase ('lokiente-project-git-'+[guid]::NewGuid().ToString('N'))
$git=(Get-Command git -CommandType Application|Select-Object -First 1).Source
$checks=0
function Assert-GitProject($Value,$Message){if(-not $Value){throw $Message};$script:checks++}
try{
    [void][IO.Directory]::CreateDirectory($root);$origin=Join-Path $root 'origin with spaces';[void][IO.Directory]::CreateDirectory($origin)
    $null=Invoke-ShadowNative $git @('init','--initial-branch','main',$origin) -Quiet
    [IO.File]::WriteAllText((Join-Path $origin 'tracked.txt'),'synthetic repository')
    $null=Invoke-ShadowNative $git @('-C',$origin,'add','tracked.txt') -Quiet
    $null=Invoke-ShadowNative $git @('-C',$origin,'-c','user.name=Test','-c','user.email=test@example.invalid','commit','-m','Synthetic test') -Quiet
    $target=Join-Path $root 'new clone ü';$cloneStatus='PASS'
    try{
        $selected=New-ShadowGitClone -InstallRoot $root -Repository $origin -Destination $target
        Assert-GitProject ($selected -eq $target -and [IO.File]::ReadAllText((Join-Path $target 'tracked.txt')) -eq 'synthetic repository') 'Git clone must create and verify a real repository in the chosen destination.'
    }catch{
        if($_.Exception.Message -notmatch 'NtCreateDirectoryObject.*0xC0000022'){throw}
        $cloneStatus='BLOCKED'
        # Continue independent repair/discovery checks with a separately initialized
        # local fixture; this is not counted as a successful clone.
        $target=Join-Path $root 'independent repair fixture'
        $null=Invoke-ShadowNative $git @('init','--initial-branch','main',$target) -Quiet
        [IO.File]::WriteAllText((Join-Path $target 'tracked.txt'),'synthetic repository')
    }
    $failed=$false;try{New-ShadowGitClone -InstallRoot $root -Repository $origin -Destination $target}catch{$failed=$true}
    Assert-GitProject $failed 'Clone must preserve an existing destination.'
    foreach($repository in @('https://user:password@example.invalid/repo.git','https://example.invalid/repo.git?token=private','ext::shell command','--upload-pack=bad')){
        $failed=$false;try{New-ShadowGitClone -InstallRoot $root -Repository $repository -Destination (Join-Path $root 'must-not-be-created')}catch{$failed=$true}
        Assert-GitProject $failed 'Credentials, helper protocols and option injection must be rejected before Git starts.'
    }
    $scan=Find-ShadowGitProjects -Path $root
    Assert-GitProject ($scan.Projects -contains $origin -and $scan.Projects -contains $target) 'Repository discovery must find real clones and avoid descending into .git.'
    $limited=Find-ShadowGitProjects -Path $root -MaxDirectories 1
    Assert-GitProject $limited.LimitReached 'Search limits must be reported instead of claiming a complete scan.'
    $entry=New-ShadowWorkspace -Root $root -Project $target -PwshPath (Get-Process -Id $PID).Path;Register-ShadowWorkspaces -Root $root -Entries @($entry)
    [IO.File]::WriteAllText($entry.task,'Keep this task unchanged.');$taskHash=(Get-FileHash -LiteralPath $entry.task).Hash
    $workspace=Get-Content -LiteralPath $entry.workspace -Raw|ConvertFrom-Json -AsHashtable;$workspace.settings['editor.fontSize']=19
    [IO.File]::WriteAllText($entry.workspace,($workspace|ConvertTo-Json -Depth 30))
    $moved=Join-Path $root 'moved clone'
    $resolvedTarget=[IO.Path]::GetFullPath($target);$resolvedMoved=[IO.Path]::GetFullPath($moved);$prefix=[IO.Path]::GetFullPath($root).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
    if(-not $resolvedTarget.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase) -or -not $resolvedMoved.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe test move'}
    Move-Item -LiteralPath $resolvedTarget -Destination $resolvedMoved
    $null=Repair-ShadowProjectRegistration -Root $root -OldPath $target -NewPath $moved -PwshPath (Get-Process -Id $PID).Path
    $saved=@(Get-ShadowWorkspaceIndex $root)
    Assert-GitProject ($saved.Count -eq 1 -and $saved[0].project -eq $moved -and $saved[0].task -eq $entry.task) 'Repair must update the path and retain the original task/checks identity.'
    Assert-GitProject ((Get-FileHash -LiteralPath $entry.task).Hash -eq $taskHash) 'Repair must preserve custom task contents byte-for-byte.'
    $workspace=Get-Content -LiteralPath $entry.workspace -Raw|ConvertFrom-Json -AsHashtable
    Assert-GitProject ($workspace.settings['editor.fontSize'] -eq 19 -and @($workspace.folders|Where-Object {$_.path -eq $target}).Count -eq 0 -and $workspace.folders[0].path -eq $moved) 'Repair must preserve custom workspace settings and remove stale root references.'
    $again=New-ShadowWorkspace -Root $root -Project $moved -PwshPath (Get-Process -Id $PID).Path
    Assert-GitProject ($again.task -eq $entry.task) 'Later desktop launch must continue using the repaired metadata.'
    @{suite='Git clone, discovery and project path repair';passed=($cloneStatus -eq 'PASS');cloneStatus=$cloneStatus;checks=$checks;limitations='Local synthetic Git repositories; clone is BLOCKED if Windows denies MSYS native object creation. No external authentication or GUI interaction.'}|ConvertTo-Json
    if($cloneStatus -eq 'BLOCKED'){exit 2}
}finally{
    $resolved=[IO.Path]::GetFullPath($root);$allowed=[IO.Path]::GetFullPath($testBase).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
    if(-not $resolved.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notlike 'lokiente-project-git-*'){throw 'Unsafe cleanup'}
    if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
