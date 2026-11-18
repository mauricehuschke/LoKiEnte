#requires -Version 5.1
[CmdletBinding()]
param([ValidateNotNullOrEmpty()][string]$InstallRoot='D:\LoKi',[string]$ProjectPath)
$ErrorActionPreference='Stop'
$launcher=Join-Path $InstallRoot 'app\Start-LocalAI.ps1'
if(-not(Test-Path -LiteralPath $launcher -PathType Leaf)){throw 'LoKi-Launcher fehlt. Zuerst in diesen Installationsordner provisionieren.'}
$arguments=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$launcher,'-InstallRoot',$InstallRoot,'-PauseOnError')
if(-not [string]::IsNullOrWhiteSpace($ProjectPath)){$arguments+=@('-ProjectPath',$ProjectPath)}
& pwsh.exe @arguments
exit $LASTEXITCODE
