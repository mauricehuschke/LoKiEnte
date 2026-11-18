#requires -Version 5.1
[CmdletBinding()]
param([ValidateNotNullOrEmpty()][string]$InstallRoot='D:\LoKi',[switch]$AuditOnly)
$ErrorActionPreference='Stop'
$installer=Join-Path $PSScriptRoot 'Provision-LoKiEnte.ps1'
if(-not(Test-Path -LiteralPath $installer -PathType Leaf)){throw 'Provision-LoKiEnte.ps1 is missing next to this launcher script.'}
$arguments=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$installer,'-InstallRoot',$InstallRoot)
if($AuditOnly){$arguments+='-AuditOnly'}
& powershell.exe @arguments
exit $LASTEXITCODE
