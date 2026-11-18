#requires -Version 7.4
param([Parameter(Mandatory)][string]$PackageRoot)
$ErrorActionPreference='Stop'
. (Join-Path $PackageRoot 'Quellpaket/Common.ps1')
$root=Join-Path ([IO.Path]::GetTempPath()) ("loki-entry user's & [x]-"+[guid]::NewGuid().ToString('N'))
try{
    [void][IO.Directory]::CreateDirectory($root)
    foreach($name in @('Provision-Run.ps1','Project-Run.ps1')){Copy-Item -LiteralPath (Join-Path $PackageRoot $name) -Destination $root}
    [IO.File]::WriteAllText((Join-Path $root 'Provision-ShadowLocalAI.ps1'),@'
param($InstallRoot,[switch]$AuditOnly)
@{root=$InstallRoot;audit=[bool]$AuditOnly}|ConvertTo-Json -Compress
'@)
    $pwsh=(Get-Process -Id $PID).Path
    $result=Invoke-ShadowNative $pwsh @('-NoProfile','-File',(Join-Path $root 'Provision-Run.ps1')) -WorkingDirectory ([IO.Path]::GetTempPath()) -Quiet
    if(($result.StdOut|ConvertFrom-Json).root -cne 'D:\LoKi'){throw 'Update default target is wrong'}
    $install=Join-Path $root "custom install"
    $result=Invoke-ShadowNative $pwsh @('-NoProfile','-File',(Join-Path $root 'Provision-Run.ps1'),'-InstallRoot',$install,'-AuditOnly') -WorkingDirectory ([IO.Path]::GetTempPath()) -Quiet
    $data=$result.StdOut|ConvertFrom-Json
    if($data.root -cne $install -or -not $data.audit){throw 'Update arguments not preserved'}
    [void][IO.Directory]::CreateDirectory((Join-Path $install 'app'))
    [IO.File]::WriteAllText((Join-Path $install 'app/Start-LocalAI.ps1'),@'
param($InstallRoot,$ProjectPath,[switch]$PauseOnError)
@{root=$InstallRoot;project=$ProjectPath;pause=[bool]$PauseOnError}|ConvertTo-Json -Compress
exit 7
'@)
    foreach($project in @('',"C:\example project's & [x]")){
        $argsList=@('-NoProfile','-File',(Join-Path $root 'Project-Run.ps1'),'-InstallRoot',$install)
        if($project){$argsList+=@('-ProjectPath',$project)}
        $result=Invoke-ShadowNative $pwsh $argsList -WorkingDirectory ([IO.Path]::GetTempPath()) -Quiet -AllowFailure
        $data=$result.StdOut|ConvertFrom-Json
        if($result.ExitCode -ne 7 -or $data.root -cne $install -or [string]$data.project -cne $project -or -not $data.pause){throw 'Launcher arguments/exit code lost'}
    }
    @{suite='Entry scripts and literal update target';checks=4;passed=$true}|ConvertTo-Json
}finally{
    $resolved=[IO.Path]::GetFullPath($root)
    if(-not $resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notlike 'loki-entry*'){throw 'Unsafe cleanup'}
    if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
