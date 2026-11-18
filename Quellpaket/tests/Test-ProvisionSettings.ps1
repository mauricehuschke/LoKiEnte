#requires -Version 7.4
param([string]$SourceRoot=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
. (Join-Path $SourceRoot 'Common.ps1')
$t=$null;$e=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $SourceRoot 'Setup.ps1'),[ref]$t,[ref]$e)
$main=@($ast.EndBlock.Statements|Where-Object {$_ -is [Management.Automation.Language.TryStatementAst]})[0]
$statements=@($main.Body.Statements)
$first=-1;$last=-1
for($i=0;$i -lt $statements.Count;$i++){
    if($statements[$i].Extent.Text.StartsWith('$profileRoot=')){$first=$i}
    if($statements[$i].Extent.Text.StartsWith('$codeArgs=')){$last=$i-1;break}
}
if($e -or $first -lt 0 -or $last -lt $first){throw 'Settings implementation not found'}
$update=[scriptblock]::Create(($statements[$first..$last].Extent.Text -join [Environment]::NewLine))
$InstallRoot=Join-Path ([IO.Path]::GetTempPath()) ('loki-settings-'+[guid]::NewGuid().ToString('N'))
$toolchain=@{powerShellExecutable='verified-pwsh.exe'}
try{
    & $update
    $file=Join-Path $InstallRoot 'vscode-data/User/settings.json'
    $settings=Get-Content -LiteralPath $file -Raw|ConvertFrom-Json -AsHashtable
    $settings['editor.fontSize']=17
    $settings['custom.extension.setting']=@{nested=@('preserve',123)}
    $settings['terminal.integrated.profiles.windows']['My Shell']=@{path='custom-shell.exe';args=@('-custom')}
    $settings['telemetry.telemetryLevel']='all'
    $before=$settings|ConvertTo-Json -Depth 100
    [IO.File]::WriteAllText($file,$before)
    & $update
    $after=Get-Content -LiteralPath $file -Raw|ConvertFrom-Json -AsHashtable
    if($after['editor.fontSize'] -ne 17 -or $after['custom.extension.setting'].nested[0] -cne 'preserve' -or
       $after['terminal.integrated.profiles.windows']['My Shell'].args[0] -cne '-custom'){throw 'User settings lost'}
    if($after['telemetry.telemetryLevel'] -cne 'off' -or $after['terminal.integrated.profiles.windows']['Shadow PowerShell'].path -cne 'verified-pwsh.exe'){throw 'Managed policy not restored'}
    if(-not @(Get-ChildItem -LiteralPath (Join-Path $InstallRoot 'backups/vscode-settings') -File -Recurse|Where-Object {[IO.File]::ReadAllText($_.FullName) -ceq $before}).Count){throw 'Previous settings not backed up'}
    $hash=(Get-FileHash -LiteralPath $file).Hash
    & $update
    if((Get-FileHash -LiteralPath $file).Hash -cne $hash){throw 'Settings update not repeatable'}
    @{suite='Existing VS Code settings preservation';checks=4;passed=$true}|ConvertTo-Json
}finally{
    $resolved=[IO.Path]::GetFullPath($InstallRoot)
    if(-not $resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notlike 'loki-settings-*'){throw 'Unsafe cleanup'}
    if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
