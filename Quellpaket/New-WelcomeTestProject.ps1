#requires -Version 7.4
[CmdletBinding()]
param([string]$InstallRoot=(Split-Path -Parent $PSScriptRoot),[switch]$NewExample)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')
. (Join-Path $PSScriptRoot 'Workspace.ps1')
$root=[IO.Path]::GetFullPath($InstallRoot)
$welcome=Join-Path $root 'welcome'
$project=Join-Path $welcome $(if($NewExample){'workflow-test-'+[guid]::NewGuid().ToString('N').Substring(0,10)}else{'workflow-test'})
foreach($path in @($root,$welcome,$project)){
    if(Test-Path -LiteralPath $path){
        $item=Get-Item -LiteralPath $path -Force
        if(-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw "Test project path is linked or invalid: $path"}
    }
}
$marker=Join-Path $project '.loki-welcome-example'
$git=Resolve-ShadowTool git
if(-not $git){throw 'Git is missing. Complete provisioning first.'}
foreach($name in @('GIT_DIR','GIT_WORK_TREE','GIT_INDEX_FILE','GIT_OBJECT_DIRECTORY','GIT_ALTERNATE_OBJECT_DIRECTORIES')){
    if([Environment]::GetEnvironmentVariable($name)){throw "Git redirection $name is set. Restart in a normal PowerShell session."}
}
if(Test-Path -LiteralPath $project){
    if(-not(Test-Path -LiteralPath $marker -PathType Leaf) -or [IO.File]::ReadAllText($marker).Trim() -cne 'loki-discount-example-v1' -or -not(Test-Path -LiteralPath (Join-Path $project '.git') -PathType Container)){
        throw 'Existing welcome test directory will not be changed. Inspect it and back it up/rename it if necessary before normal provisioning. -NewExample creates another example separately but does not repair this directory.'
    }
    foreach($path in @($marker,(Join-Path $project '.git'))){
        if((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Linked example state will not be adopted.'}
    }
    $null=Invoke-ShadowNative $git @('-C',$project,'rev-parse','--verify','HEAD') -Quiet
    $germanReadme=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'welcome-example/README.de.md'))
    $germanPath=Join-Path $project 'README.de.md'
    if(-not(Test-Path -LiteralPath $germanPath)){
        [IO.File]::Copy((Join-Path $PSScriptRoot 'welcome-example/README.de.md'),$germanPath,$false)
    }
    $readmePath=Join-Path $project 'README.md'
    if(Test-Path -LiteralPath $readmePath -PathType Leaf){
        if((Get-Item -LiteralPath $readmePath -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Linked Welcome guide will not be changed.'}
        $normalize={param([string]$Text) (($Text -replace '(?s)<!-- lokiente-language -->.*?<!-- /lokiente-language -->','').Replace("`r",'') -replace '\n{3,}',"`n`n").Trim()}
        if((& $normalize ([IO.File]::ReadAllText($readmePath))) -ceq (& $normalize $germanReadme)){
            $null=Write-ShadowManagedFile -Path $readmePath -Content ([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'welcome-example/README.md'))) -BackupRoot (Join-Path $root 'backups/welcome')
        }
    }
}else{
    [void][IO.Directory]::CreateDirectory($welcome)
    $destination=$project
    $project=Join-Path $welcome ('.init-'+[guid]::NewGuid().ToString('N').Substring(0,12))
    $marker=Join-Path $project '.loki-welcome-example'
    $null=New-Item -ItemType Directory -Path $project -ErrorAction Stop
    try{
    foreach($name in @('package.json','discount.cjs','README.md','README.de.md')){
        [IO.File]::Copy((Join-Path $PSScriptRoot ('welcome-example/'+$name)),(Join-Path $project $name),$false)
    }
    $git=Resolve-ShadowTool git
    if(-not $git){throw 'Git is missing. Complete provisioning and retry with -NewExample.'}
    # Synthetic initial history only; no remote, user hooks or global Git settings.
    $emptyConfig=[IO.Path]::GetTempFileName()
    $environment=@{GIT_CONFIG_NOSYSTEM='1';GIT_CONFIG_GLOBAL=$emptyConfig;GIT_CONFIG_COUNT='0'}
    try{
    $null=Invoke-ShadowNative $git @('-c','core.longpaths=true','init','--quiet','--template=',$project) -Environment $environment -Quiet
    $hooks=Join-Path $project '.git/loki-empty-hooks'
    [void][IO.Directory]::CreateDirectory($hooks)
    [IO.File]::WriteAllText($marker,'loki-discount-example-v1',[Text.UTF8Encoding]::new($false))
    $prefix=@('-C',$project,'-c','core.longpaths=true','-c',('core.hooksPath='+$hooks),'-c','core.autocrlf=false','-c','commit.gpgsign=false','-c','user.name=LoKiEnte Example','-c','user.email=loki-example@localhost')
    $null=Invoke-ShadowNative $git ($prefix+@('add','--','package.json','discount.cjs','README.md','README.de.md','.loki-welcome-example')) -Environment $environment -Quiet
    $null=Invoke-ShadowNative $git ($prefix+@('commit','--quiet','-m','test: initial intentionally faulty discount example')) -Environment $environment -Quiet
    }finally{Remove-Item -LiteralPath $emptyConfig -Force}
    # Publish only a complete repository. Never replace an existing folder.
    [IO.Directory]::Move($project,$destination)
    $project=$destination
    }catch{
        throw "Welcome initialization failed. Diagnostic directory: $project. $($_.Exception.Message)"
    }
}
$entry=New-ShadowWorkspace -Root $root -Project $project -PwshPath (Get-Process -Id $PID).Path
Register-ShadowWorkspaces -Root $root -Entries @($entry)
$entry
