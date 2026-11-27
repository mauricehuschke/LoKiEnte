#requires -Version 7.4
param([string]$SourceRoot=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
. (Join-Path $SourceRoot 'Common.ps1');. (Join-Path $SourceRoot 'DesktopRunner.ps1')
$root=Join-Path ([IO.Path]::GetTempPath()) ('lokiente-desktop-'+[guid]::NewGuid().ToString('N'))
$checks=0
function Assert-Desktop($Value,$Message){if(-not $Value){throw $Message};$script:checks++}
try{
    $runner=Install-ShadowDesktopRunner -InstallRoot $root -PowerShellPath (Get-Process -Id $PID).Path
    $bytes=[IO.File]::ReadAllBytes($runner);$header=[BitConverter]::ToInt32($bytes,60)
    Assert-Desktop ([BitConverter]::ToUInt16($bytes,$header+24+68) -eq 2) 'Desktop launcher must use the Windows GUI subsystem, never a console subsystem.'
    $hash=(Get-FileHash -LiteralPath $runner).Hash
    $null=Install-ShadowDesktopRunner -InstallRoot $root -PowerShellPath (Get-Process -Id $PID).Path
    Assert-Desktop ((Get-FileHash -LiteralPath $runner).Hash -eq $hash) 'Unchanged launcher source must reuse the verified executable.'
    $node=(Get-Command node -CommandType Application|Select-Object -First 1).Source
    Test-ShadowDesktopRunnerReady -InstallRoot $root -NodePath $node -WorkingDirectory $root
    Assert-Desktop $true 'The installed acceptance probe must verify the actual native collector without a VM/container.'
    $arguments=@('-e','console.log(JSON.stringify(process.argv.slice(1)));console.error("synthetic-desktop-secret");process.exitCode=9','','path with spaces\','quote"inside','Unicode-ü','$(never execute)')
    $id=Start-ShadowEditor -InstallRoot $root -CodePath $node -Arguments $arguments -WorkingDirectory $root -Environment @{LOKIENTE_TEST_TOKEN='synthetic-desktop-secret';ELECTRON_RUN_AS_NODE='must-be-removed'}
    $log=Join-Path $root ('runtime/launcher-logs/'+$id+'-editor.log');$watch=[Diagnostics.Stopwatch]::StartNew()
    while($watch.Elapsed.TotalSeconds -lt 20){if((Test-Path -LiteralPath $log) -and ([IO.File]::ReadAllText($log)).Contains('Process exited with code 9')){break};Start-Sleep -Milliseconds 100}
    $text=[IO.File]::ReadAllText($log)
    Assert-Desktop ($text.Contains('Process exited with code 9') -and $text.Contains('[ERROR] [REDACTED]')) 'Real child stdout, stderr and nonzero exit must be collected without a terminal.'
    Assert-Desktop (-not $text.Contains('synthetic-desktop-secret')) 'The desktop collector must redact inherited token values.'
    $line=@($text -split '\r?\n'|Where-Object {$_ -match '\[INFO\] \['})[0]
    $actual=($line -replace '^.*?\[INFO\] ','')|ConvertFrom-Json -NoEnumerate
    Assert-Desktop (($actual|ConvertTo-Json -Compress) -ceq ($arguments[2..($arguments.Count-1)]|ConvertTo-Json -Compress)) 'Native Windows argument quoting must preserve empty strings, quotes, slashes, Unicode and shell metacharacters.'
    $handshake=Join-Path $root ('runtime/startup-handshakes/'+$id+'.json');[void][IO.Directory]::CreateDirectory((Split-Path -Parent $handshake))
    [IO.File]::WriteAllText($handshake,(@{launchId=$id;helperVersion='0.2.6';dataDirectory=(Join-Path $root 'vscode-data')}|ConvertTo-Json))
    $failed=$false;try{Wait-ShadowEditorHost -InstallRoot $root -RunId $id -ExpectedVersion '0.3.1' -TimeoutSeconds 1}catch{$failed=$true}
    Assert-Desktop $failed 'A stale installed/active helper version must not confirm startup.'
    [IO.File]::WriteAllText($handshake,(@{launchId=$id;helperVersion='0.3.1';dataDirectory=(Join-Path $root 'vscode-data')}|ConvertTo-Json))
    $state=Wait-ShadowEditorHost -InstallRoot $root -RunId $id -ExpectedVersion '0.3.1' -TimeoutSeconds 1
    Assert-Desktop ($state.launchId -eq $id) 'Only a matching launch/version/profile handshake may confirm the Extension Host.'
    @{suite='Console-free Windows desktop runner';passed=$true;checks=$checks;limitations='Real WinExe compile, PE header, child process and logs. VS Code/model UI not exercised.'}|ConvertTo-Json
}finally{
    $resolved=[IO.Path]::GetFullPath($root);$allowed=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
    if(-not $resolved.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notlike 'lokiente-desktop-*'){throw 'Unsafe cleanup'}
    if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
