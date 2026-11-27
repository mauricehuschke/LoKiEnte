#requires -Version 7.4
param([string]$SourceRoot=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
. (Join-Path $SourceRoot 'Common.ps1');. (Join-Path $SourceRoot 'ProvisionReport.ps1')
$root=Join-Path ([IO.Path]::GetTempPath()) ('lokiente-report-'+[guid]::NewGuid().ToString('N'))
$node=(Get-Command node -CommandType Application|Select-Object -First 1).Source
$previous=$env:LOKIENTE_TEST_TOKEN;$env:LOKIENTE_TEST_TOKEN='synthetic-report-secret'
$checks=0
function Assert-Report($Value,$Message){if(-not $Value){throw $Message};$script:checks++}
try{
    Initialize-ShadowToolchainLogging $root
    $report=[ordered]@{status='IN_PROGRESS';steps=@();warnings=@()}
    Start-ShadowProvisionReport -InstallRoot $root -Report $report -Parameters @{SkipAcceptanceTest=$true;ApiTokenEnvironmentVariable='LOKIENTE_TEST_TOKEN'}
    Assert-Report (Test-Path -LiteralPath (Join-Path $root 'provisioning-report.json')) 'Report must exist before the first operation.'
    $value=Invoke-ShadowProvisionStep -Id 'real-native-test' -Action {Invoke-ShadowNative -FilePath $node -ArgumentList @('-e','process.stdout.write("positive synthetic-report-secret");process.stderr.write("Bearer abc123");process.exitCode=3') -AllowFailure -Quiet -TimeoutSeconds 10}
    Assert-Report ($value.ExitCode -eq 3 -and $report.commands.Count -eq 1 -and $report.commands[0].exitCode -eq 3) 'Actual native arguments, outputs and exit status must be captured.'
    $null=Write-ShadowManagedFile -Path (Join-Path $root 'inventory.json') -Content '{"cpu":"synthetic","apiKey":"nested-private-key"}'
    $null=Write-ShadowManagedFile -Path (Join-Path $root 'runtime/router-recovery.json') -Content '{"kind":"router-control-recovery","pid":4242,"accountMatched":true,"method":"VerifiedOwnedProcess"}'
    $null=Invoke-ShadowNative -FilePath $node -ArgumentList @('-e','process.stdout.write("x".repeat(300000))') -Quiet -TimeoutSeconds 10
    Assert-Report ($report.commands[1].streams.stdout.truncated -and (Test-Path -LiteralPath (Join-Path $root $report.commands[1].streams.stdout.fullLog))) 'Oversized stdout must have an explicit inline limit and a complete redacted local log.'
    $failure=$null;try{Invoke-ShadowProvisionStep -Id 'failing-check' -Kind Test -Action {throw 'synthetic-report-secret check failed'}}catch{$failure=$_}
    Assert-Report ($report.tests[-1].status -eq 'FAIL') 'A failed test must be saved before final cleanup.'
    $report.smokeTests=[pscustomobject]@{Chat='Passed';ToolCall='Passed';ToolResultRoundTrip='NotRun'}
    $report.scalarEvidence=@{context=(32768|Select-Object -Unique);bytes=23255183360L;enabled=$true;values=@((16384|Select-Object -Unique),8192)}
    $report.status='INCOMPLETE';Complete-ShadowProvisionReport -Failure $failure
    $text=Get-Content -LiteralPath (Join-Path $root 'provisioning-report.json') -Raw;$saved=$text|ConvertFrom-Json
    Assert-Report ($saved.schema -eq 2 -and $saved.failure.stack -and $saved.snapshots.'inventory.json'.cpu -eq 'synthetic') 'Main report must embed environment, snapshots and exception stack.'
    Assert-Report ($saved.snapshots.'runtime/router-recovery.json'.pid -eq 4242 -and $saved.snapshots.'runtime/router-recovery.json'.accountMatched) 'Router recovery process identity must be retained in the self-contained provisioning report.'
    Assert-Report ($text -notmatch 'synthetic-report-secret|nested-private-key|abc123') 'Known secrets, nested credentials and Authorization headers must be redacted.'
    Assert-Report ($saved.runtimeRequirements.dockerRequired -eq $false -and $saved.runtimeRequirements.hyperVRequired -eq $false) 'Acceptance must not depend on a VM/container runtime.'
    Assert-Report ($saved.commands[0].arguments.Count -eq 2 -and $saved.commands[0].durationMs -ge 0 -and $saved.environment.powerShell) 'Report must retain command arguments, timing and process environment metadata.'
    Assert-Report (@($saved.tests|Where-Object {$_.id -eq 'model:single:ToolResultRoundTrip' -and $_.status -eq 'SKIPPED'}).Count -eq 1) 'PSCustomObject model results must retain passed versus unexecuted smoke evidence.'
    Assert-Report ($saved.scalarEvidence.context -eq 32768 -and $saved.scalarEvidence.context -is [ValueType] -and $saved.scalarEvidence.bytes -eq 23255183360L) 'Pipeline-decorated context and memory numbers must remain JSON numbers, never empty objects.'
    Assert-Report ($saved.scalarEvidence.enabled -eq $true -and ($saved.scalarEvidence.values -join ',') -eq '16384,8192') 'Booleans and numeric array entries must retain their values.'
    Add-ShadowProvisionCommand -File 'synthetic-capability-probe' -Arguments @('load','--estimate-only') -ExitCode 1 -ExpectedFailure -Stderr 'Expected negative fixture' -DurationMs 1
    Assert-Report ($report.commands[-1].status -ceq 'EXPECTED_NONZERO_EXIT' -and $report.commands[-1].exitCode -eq 1 -and $report.commands[-1].expectedFailure) 'Expected negative probes retain native exit/output evidence with an explicit expected-result classification.'
    Start-ShadowProvisionReport -InstallRoot $root -Report ([ordered]@{status='IN_PROGRESS'})
    Assert-Report (@(Get-ChildItem -LiteralPath (Join-Path $root 'backups/reports')).Count -eq 1) 'A later run must preserve the preceding report.'
    @{suite='Incremental self-contained provisioning diagnostics';passed=$true;checks=$checks;limitations='Real processes/files; synthetic environment data; no model inference.'}|ConvertTo-Json
}finally{
    $env:LOKIENTE_TEST_TOKEN=$previous
    $resolved=[IO.Path]::GetFullPath($root);$allowed=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
    if(-not $resolved.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notlike 'lokiente-report-*'){throw 'Unsafe cleanup'}
    if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
