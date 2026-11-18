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
        if(-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw "Testprojektpfad ist verknuepft oder ungueltig: $path"}
    }
}
$marker=Join-Path $project '.loki-welcome-example'
$git=Resolve-ShadowTool git
if(-not $git){throw 'Git fehlt. Zuerst die Provisionierung abschliessen.'}
foreach($name in @('GIT_DIR','GIT_WORK_TREE','GIT_INDEX_FILE','GIT_OBJECT_DIRECTORY','GIT_ALTERNATE_OBJECT_DIRECTORIES')){
    if([Environment]::GetEnvironmentVariable($name)){throw "Git-Umleitung $name ist gesetzt. In einer normalen PowerShell erneut starten."}
}
if(Test-Path -LiteralPath $project){
    if(-not(Test-Path -LiteralPath $marker -PathType Leaf) -or [IO.File]::ReadAllText($marker).Trim() -cne 'loki-discount-example-v1' -or -not(Test-Path -LiteralPath (Join-Path $project '.git') -PathType Container)){
        throw 'Vorhandener Welcome-Testordner wird nicht veraendert. Fuer die normale Provisionierung diesen Ordner erst pruefen und bei Bedarf sichern/umbenennen. -NewExample erzeugt separat ein weiteres Beispiel, repariert aber diesen Ordner nicht.'
    }
    foreach($path in @($marker,(Join-Path $project '.git'))){
        if((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Verknuepfter Beispielzustand wird nicht uebernommen.'}
    }
    $null=Invoke-ShadowNative $git @('-C',$project,'rev-parse','--verify','HEAD') -Quiet
}else{
    [void][IO.Directory]::CreateDirectory($welcome)
    $destination=$project
    $project=Join-Path $welcome ('.init-'+[guid]::NewGuid().ToString('N').Substring(0,12))
    $marker=Join-Path $project '.loki-welcome-example'
    $null=New-Item -ItemType Directory -Path $project -ErrorAction Stop
    try{
    foreach($name in @('package.json','discount.cjs','README.md')){
        [IO.File]::Copy((Join-Path $PSScriptRoot ('welcome-example/'+$name)),(Join-Path $project $name),$false)
    }
    $git=Resolve-ShadowTool git
    if(-not $git){throw 'Git fehlt. Provisionierung abschliessen und mit -NewExample erneut starten.'}
    # Synthetic initial history only; no remote, user hooks or global Git settings.
    $emptyConfig=[IO.Path]::GetTempFileName()
    $environment=@{GIT_CONFIG_NOSYSTEM='1';GIT_CONFIG_GLOBAL=$emptyConfig;GIT_CONFIG_COUNT='0'}
    try{
    $null=Invoke-ShadowNative $git @('-c','core.longpaths=true','init','--quiet','--template=',$project) -Environment $environment -Quiet
    $hooks=Join-Path $project '.git/loki-empty-hooks'
    [void][IO.Directory]::CreateDirectory($hooks)
    [IO.File]::WriteAllText($marker,'loki-discount-example-v1',[Text.UTF8Encoding]::new($false))
    $prefix=@('-C',$project,'-c','core.longpaths=true','-c',('core.hooksPath='+$hooks),'-c','core.autocrlf=false','-c','commit.gpgsign=false','-c','user.name=LoKi Example','-c','user.email=loki-example@localhost')
    $null=Invoke-ShadowNative $git ($prefix+@('add','--','package.json','discount.cjs','README.md','.loki-welcome-example')) -Environment $environment -Quiet
    $null=Invoke-ShadowNative $git ($prefix+@('commit','--quiet','-m','test: initial intentionally faulty discount example')) -Environment $environment -Quiet
    }finally{Remove-Item -LiteralPath $emptyConfig -Force}
    # Publish only a complete repository. Never replace an existing folder.
    [IO.Directory]::Move($project,$destination)
    $project=$destination
    }catch{
        throw "Welcome-Initialisierung fehlgeschlagen. Diagnoseordner: $project. $($_.Exception.Message)"
    }
}
$entry=New-ShadowWorkspace -Root $root -Project $project -PwshPath (Get-Process -Id $PID).Path
Register-ShadowWorkspaces -Root $root -Entries @($entry)
$entry
