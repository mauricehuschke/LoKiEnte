#requires -Version 7.4
param([string]$SourceRoot=(Split-Path -Parent $PSScriptRoot))
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $SourceRoot 'Common.ps1')
. (Join-Path $SourceRoot 'AgentTemplates.ps1')
. (Join-Path $SourceRoot 'Runtime.ps1')
$root=Join-Path ([IO.Path]::GetTempPath()) ('lokiente-native-evidence-'+[guid]::NewGuid().ToString('N'))
$node=(Get-Command node -CommandType Application|Select-Object -First 1).Source
$previous=[Environment]::GetEnvironmentVariable('LOKIENTE_TEST_TOKEN','Process')
$checks=0
function Assert-Native($Value,$Message){if(-not $Value){throw $Message};$script:checks++}
try{
    Initialize-ShadowToolchainLogging -InstallRoot $root
    [Environment]::SetEnvironmentVariable('LOKIENTE_TEST_TOKEN','synthetic-log-secret','Process')
    Write-ShadowMessage 'Actual message is recorded.' 'OK'
    $result=Invoke-ShadowNative -FilePath $node -ArgumentList @('-e','process.stdout.write("private-config-stdout");process.stderr.write("Bearer abc123 synthetic-log-secret");process.exitCode=7') -AllowFailure -Quiet -TimeoutSeconds 5
    Assert-Native ($result.ExitCode -eq 7) 'A real nonzero exit must be preserved.'
    $script='require("node:child_process").spawn(process.execPath,["-e","setTimeout(()=>{},12000)"],{detached:true,stdio:["ignore",process.stdout,process.stderr]}).unref();process.exit(0)'
    $watch=[Diagnostics.Stopwatch]::StartNew();$failure=''
    try{Invoke-ShadowNative -FilePath $node -ArgumentList @('-e',$script) -Quiet -TimeoutSeconds 4|Out-Null}catch{$failure=$_.Exception.Message}
    Assert-Native ($failure -match 'output to close' -and $watch.Elapsed.TotalSeconds -lt 10) "Inherited output handles must not bypass the native deadline. Observed: $failure ($($watch.Elapsed.TotalSeconds) seconds)."
    $text=Get-Content -LiteralPath (Join-Path $root 'runtime/toolchain-events.jsonl') -Raw
    Assert-Native ($text -match 'Actual message is recorded' -and $text -match '"level":"ERROR"') 'Positive messages and actual process errors must be logged.'
    Assert-Native ($text -notmatch 'synthetic-log-secret|abc123|private-config-stdout') 'Credentials and configuration stdout must not enter the unified log.'
    function Get-ShadowLocalEnvironment {param($InstallRoot,$ConfigJson) return @{}}
    $watch.Restart();$failure=''
    try{Assert-ShadowKiloEffectiveConfig -KiloExecutable $node -KiloArgumentPrefix @('-e',$script) -InstallRoot $root -Config @{} -WorkingDirectory $SourceRoot -TimeoutSeconds 4|Out-Null}catch{$failure=$_.Exception.Message}
    Assert-Native ($failure -match 'configuration output did not close' -and $watch.Elapsed.TotalSeconds -lt 10) "Kilo effective-config output must share its command deadline. Observed: $failure ($($watch.Elapsed.TotalSeconds) seconds)."
    $result=Invoke-LrNative -FilePath $node -Arguments @('-e','process.stderr.write("synthetic-log-secret");process.exitCode=2') -LogDirectory (Join-Path $root 'runtime/logs') -TimeoutSeconds 5 -AllowFailure
    Assert-Native ($result.ExitCode -eq 2) 'LM Studio native wrapper must preserve the real tool failure.'
    $text=Get-Content -LiteralPath (Join-Path $root 'runtime/toolchain-events.jsonl') -Raw
    Assert-Native ($text -match 'LM Studio CLI' -and $text -match 'exited with code 2' -and $text -notmatch 'synthetic-log-secret') 'LM Studio command failures must reach the same redacted toolchain event log.'
    @{suite='Real native deadlines and local event logging';checks=$checks;passed=$true}|ConvertTo-Json
}finally{
    [Environment]::SetEnvironmentVariable('LOKIENTE_TEST_TOKEN',$previous,'Process')
    $resolved=[IO.Path]::GetFullPath($root)
    if(-not $resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notlike 'lokiente-native-evidence-*'){throw 'Unsafe cleanup'}
    if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
