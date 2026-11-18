#requires -Version 7.4
param([string]$SourceRoot=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $SourceRoot 'Setup.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Setup syntax errors'}
$desktopBlock=$ast.Find({param($node) $node -is [Management.Automation.Language.IfStatementAst] -and $node.Clauses[0].Item1.Extent.Text -ceq '$desktop'},$true)
if($null -eq $desktopBlock){throw 'Desktop shortcut setup block missing'}
$blockText=$desktopBlock.Clauses[0].Item2.Extent.Text
$action=[scriptblock]::Create($blockText.Substring(1,$blockText.Length-2))
$root=Join-Path ([IO.Path]::GetTempPath()) ('lokiente-icon-'+[guid]::NewGuid().ToString('N'))
$desktop=Join-Path $root 'desktop'
$InstallRoot=Join-Path $root 'installation with spaces'
$toolchain=@{powerShellExecutable=(Get-Process -Id $PID).Path}
try {
    [void][IO.Directory]::CreateDirectory($desktop)
    [void][IO.Directory]::CreateDirectory((Join-Path $InstallRoot 'app/assets'))
    $sourceIcon=Join-Path $SourceRoot 'assets/lokiente.ico'
    $installedIcon=Join-Path $InstallRoot 'app/assets/lokiente.ico'
    Copy-Item -LiteralPath $sourceIcon -Destination $installedIcon
    $bytes=[IO.File]::ReadAllBytes($installedIcon)
    if([BitConverter]::ToUInt16($bytes,2) -ne 1 -or [BitConverter]::ToUInt16($bytes,4) -ne 7){throw 'Seven-frame ICO expected'}
    $sizes=@(for($i=0;$i -lt 7;$i++){ $size=[int]$bytes[6+16*$i];if($size -eq 0){256}else{$size} })
    if(($sizes -join ',') -cne '16,24,32,48,64,128,256'){throw 'ICO size set wrong'}
    Add-Type -AssemblyName System.Drawing
    $decoded=[Drawing.Icon]::new($installedIcon,128,128)
    try {if($decoded.Width -ne 128 -or $decoded.Height -ne 128){throw 'Windows cannot decode large icon'}} finally {$decoded.Dispose()}
    & $action
    $shell=New-Object -ComObject WScript.Shell
    $linkPath=Join-Path $desktop 'LoKiEnte.lnk'
    $link=$shell.CreateShortcut($linkPath)
    if($link.IconLocation -cne ($installedIcon+',0') -or $link.TargetPath -ine $toolchain.powerShellExecutable -or $link.Arguments -notlike '*-PauseOnError' -or $link.WorkingDirectory -cne $InstallRoot){throw 'New launcher properties incorrect'}
    $oldPath=Join-Path $desktop 'Shadow Local AI.lnk'
    Copy-Item -LiteralPath $linkPath -Destination $oldPath
    $unrelated=$shell.CreateShortcut((Join-Path $desktop 'LoKi.lnk'))
    $unrelated.TargetPath=$toolchain.powerShellExecutable
    $unrelated.Arguments='-NoProfile -Command exit'
    $unrelated.Save()
    & $action
    if(Test-Path -LiteralPath $oldPath){throw 'Matching legacy shortcut was not migrated'}
    if(-not(Test-Path -LiteralPath (Join-Path $desktop 'LoKi.lnk'))){throw 'Unrelated shortcut removed'}
    if(@(Get-ChildItem -LiteralPath (Join-Path $InstallRoot 'backups/shortcuts') -Filter '*.lnk').Count -ne 2){throw 'Update and migration backups missing'}
    $updated=$shell.CreateShortcut($linkPath)
    if($updated.IconLocation -cne ($installedIcon+',0')){throw 'Icon missing after update'}
    @{suite='LoKiEnte desktop branding';passed=$true;checks=8}|ConvertTo-Json
} finally {
    $resolved=[IO.Path]::GetFullPath($root)
    $tempPrefix=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
    if(-not $resolved.StartsWith($tempPrefix,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notlike 'lokiente-icon-*'){throw 'Unsafe cleanup'}
    if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
