#requires -Version 7.4
# Fresh-process production import contract, real paths/hashes/report files.
# Desktop, Kilo and executable-version boundaries below are explicit fixtures.
param([string]$SourceRoot=(Split-Path -Parent $PSScriptRoot))
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$checks=0
function Assert-Progress($Condition,$Message){if(-not $Condition){throw $Message};$script:checks++}
Assert-Progress (-not(Get-Command Assert-ShadowDirectPath -ErrorAction SilentlyContinue)) 'Run this regression in a fresh PowerShell process.'
$errors=$null;$tokens=$null
$entry=[Management.Automation.Language.Parser]::ParseFile((Join-Path $SourceRoot 'Test-Toolchain.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Invalid dependency entry point.'}
$imports=@($entry.EndBlock.Statements|Where-Object {$_ -is [Management.Automation.Language.ForEachStatementAst]})
Assert-Progress ($imports.Count -eq 1) 'The actual dependency entry-point import statement must be unambiguous.'
. ([scriptblock]::Create($imports[0].Extent.Text.Replace('$PSScriptRoot','$SourceRoot')))
Assert-Progress ([bool](Get-Command Assert-ShadowDirectPath -CommandType Function -ErrorAction SilentlyContinue)) 'The real dependency entry point must load the ripgrep path guard without parent-process setup imports.'
$root=Join-Path ([IO.Path]::GetTempPath()) ('lokiente-progress-'+[guid]::NewGuid().ToString('N'))
$previous=[Environment]::GetEnvironmentVariable('LOKIENTE_TOOLCHAIN_RUN_ID')
$secret=[Environment]::GetEnvironmentVariable('LOKIENTE_TEST_TOKEN')
try{
    foreach($directory in @('kilo-managed','runtime-profile/cache/kilo/bin')){[void][IO.Directory]::CreateDirectory((Join-Path $root $directory))}
    $script:resultPath=Join-Path $root 'dependencies.json'
    $script:guardedInfo=Get-ShadowRipgrepInfo -InstallRoot $root
    $failure='';try{Assert-ShadowRipgrepReady -InstallRoot $root}catch{$failure=$_.Exception.Message}
    Assert-Progress ($failure -match 'Ripgrep missing' -and $failure -notmatch 'not recognized') 'The isolated import contract must reach the real missing-file guard.'
    [IO.File]::WriteAllText($script:guardedInfo.Path,'synthetic executable boundary')
    $failure='';try{Assert-ShadowRipgrepReady -InstallRoot $root}catch{$failure=$_.Exception.Message}
    Assert-Progress ($failure -match 'unknown checksum') 'Actual bad ripgrep bytes must fail before the executable boundary.'
    $script:guardedInfo.ExecutableSha256=(Get-FileHash -LiteralPath $script:guardedInfo.Path).Hash
    function Get-ShadowRipgrepInfo {param($InstallRoot) return $script:guardedInfo}
    $script:versionCalls=0
    function Invoke-ShadowNative {param($FilePath,$ArgumentList,[switch]$Quiet,$TimeoutSeconds) $script:versionCalls++;return @{StdOut='ripgrep 15.1.0'}}
    Assert-Progress ((Assert-ShadowRipgrepReady -InstallRoot $root) -ceq $script:guardedInfo.Path -and $script:versionCalls -eq 1) 'The actual path/hash guards must allow the verified fixture to reach the version boundary.'
    Write-ShadowAcceptanceJson -Path (Join-Path $root 'toolchain.json') -Value @{nodeExecutable='fixture-node';gitExecutable='fixture-git';codeExecutable='fixture-code';kiloExecutable='fixture-kilo';kiloArgumentPrefix=@()}
    Write-ShadowAcceptanceJson -Path (Join-Path $root 'kilo-managed/kilo.json') -Value @{}
    $env:LOKIENTE_TOOLCHAIN_RUN_ID='a'*32
    function Test-ShadowDesktopRunnerReady {
        param($InstallRoot,$NodePath,$WorkingDirectory)
        $snapshot=Read-ShadowAcceptanceJson -Path $script:resultPath
        Assert-Progress ($snapshot.status -ceq 'RUNNING' -and $snapshot.cases.Count -eq 0 -and $snapshot.progress[-1].status -ceq 'RUNNING') 'Dependency START must be visible on disk before the action runs.'
    }
    function Test-ShadowGitCloneReadiness {
        param($InstallRoot,$WorkingDirectory,$GitPath)
        $snapshot=Read-ShadowAcceptanceJson -Path $script:resultPath
        Assert-Progress ($snapshot.cases[0].status -ceq 'PASS' -and $snapshot.progress[-1].id -ceq 'git-local-clone' -and $snapshot.progress[-1].status -ceq 'RUNNING') 'A short completed result and the next start must be retained between polling intervals.'
    }
    function Get-ShadowBundledKilo {param($CodePath,$InstallRoot) return 'fixture-embedded'}
    function Assert-ShadowKiloEffectiveConfig {param($KiloExecutable,$KiloArgumentPrefix,$InstallRoot,$Config,$WorkingDirectory)}
    function Assert-ShadowKiloWorkflowTools {param($KiloExecutable,$KiloArgumentPrefix,$InstallRoot,$Config,$WorkingDirectory)}
    function Test-ShadowKiloSearch {param($InstallRoot,$KiloExecutable,$KiloArgumentPrefix,$ConfigJson)}
    $result=Test-ShadowToolchainDependencies -InstallRoot $root -WorkingDirectory $root -ResultPath $script:resultPath
    Assert-Progress ($result.status -ceq 'PASS' -and $result.cases.Count -eq 10 -and $result.progress.Count -eq 20) 'All ten dependency results must retain their individual starts/results.'
    $persisted=Read-ShadowAcceptanceJson -Path $script:resultPath
    Assert-Progress ($persisted.status -ceq 'PASS' -and $persisted.runId -ceq $env:LOKIENTE_TOOLCHAIN_RUN_ID -and $persisted.progress[-1].durationMs -ge 0) 'The terminal dependency snapshot must preserve run identity, result and duration.'
    [IO.File]::WriteAllText($script:guardedInfo.Path,'changed bytes')
    $result=Test-ShadowToolchainDependencies -InstallRoot $root -WorkingDirectory $root -ResultPath $script:resultPath
    Assert-Progress ($result.status -ceq 'FAIL' -and @($result.cases|Where-Object {$_.status -eq 'FAIL'}).Count -eq 1 -and $result.cases[2].id -ceq 'ripgrep') 'The missing-import fix must keep the actual ripgrep integrity check strict.'
    $script:messages=[Collections.Generic.List[string]]::new()
    function Write-ShadowMessage {param($Message,$Level='INFO') $script:messages.Add("[$Level] $Message")}
    $env:LOKIENTE_TEST_TOKEN='synthetic-progress-secret'
    $start=[datetime]'2026-01-01T00:00:00Z'
    $tracker=@{runId='a'*32;startedAtUtc=$start}
    $state=@{runId='a'*32;status='RUNNING';cases=@();progress=@(@{sequence=1;utc=$start.ToString('o');id='dependencies';component='LoKiEnte';status='RUNNING';evidence=''})}
    $dependency=@{runId='a'*32;status='RUNNING';cases=@();progress=@(@{sequence=1;utc=$start.AddSeconds(1).ToString('o');id='ripgrep';component='ripgrep';status='RUNNING';evidence=''})}
    Write-ShadowAcceptanceProgress -State $state -DependencyState $dependency -Tracker $tracker -Now $start.AddSeconds(2)
    Assert-Progress ($messages.Count -eq 2 -and $messages[0] -match 'START:.*dependencies' -and $messages[1] -match 'START:.*ripgrep') 'Both host and nested starts must be printed in timestamp order.'
    Write-ShadowAcceptanceProgress -State $state -DependencyState $dependency -Tracker $tracker -Now $start.AddSeconds(16)
    Assert-Progress ($messages.Count -eq 2) 'Repeated snapshots must not repeat events or emit early heartbeats.'
    Write-ShadowAcceptanceProgress -State $state -DependencyState $dependency -Tracker $tracker -Now $start.AddSeconds(17)
    Assert-Progress ($messages.Count -eq 3 -and $messages[-1] -match 'RUNNING: ripgrep / ripgrep.*16s.*0 results') 'A long action must emit a heartbeat with the actual current nested step and elapsed time.'
    $dependency.progress+=@{sequence=2;utc=$start.AddSeconds(18).ToString('o');id='ripgrep';component='ripgrep';status='FAIL';evidence="Failed synthetic-progress-secret`nBearer synthetic-bearer";durationMs=17000}
    $dependency.cases=@(@{id='ripgrep';status='FAIL';evidence=$dependency.progress[-1].evidence});$dependency.status='FAIL'
    Write-ShadowAcceptanceProgress -State $state -DependencyState $dependency -Tracker $tracker -Now $start.AddSeconds(18)
    Assert-Progress ($messages.Count -eq 4 -and $messages[-1] -match 'FAIL:.*17.0s' -and $messages[-1] -notmatch 'synthetic-progress-secret|synthetic-bearer|\r|\n') 'Failure evidence must be printed once with duration, redaction and safe terminal text.'
    $state.progress+=@{sequence=2;utc=$start.AddSeconds(19).ToString('o');id='dependencies';component='LoKiEnte';status='FAIL';evidence='dependency failed'}
    $state.cases=@(@{id='dependencies';component='LoKiEnte';status='FAIL';evidence='dependency failed'},@{id='model';status='BLOCKED';evidence='Not executed'})
    $state.status='FAIL';$state.finishedAtUtc=$start.AddSeconds(19).ToString('o')
    Write-ShadowAcceptanceProgress -State $state -DependencyState $dependency -Tracker $tracker -Now $start.AddSeconds(19)
    Assert-Progress ($messages.Count -eq 6 -and $messages[-1] -match 'BLOCKED:.*model') 'The terminal snapshot must also display fallback/missing prerequisite results without duplicate case events.'
    Write-ShadowAcceptanceProgress -State $state -DependencyState $dependency -Tracker $tracker -Now $start.AddSeconds(90)
    Assert-Progress ($messages.Count -eq 6 -and $state.status -ceq 'FAIL') 'Finished runs must neither heartbeat nor change verdict.'
    $wrong=@{runId='b'*32;status='RUNNING';progress=@(@{sequence=99;id='foreign';status='PASS'})}
    Write-ShadowAcceptanceProgress -State $wrong -Tracker $tracker -Now $start.AddSeconds(91)
    Assert-Progress ($messages.Count -eq 6) 'Foreign run evidence must not appear as test progress.'
    $wait=@{runId='c'*32;status='RUNNING';waitingFor='workspace-trust';cases=@()}
    $waitTracker=@{runId=$wait.runId;startedAtUtc=$start}
    Write-ShadowAcceptanceProgress -State $wait -DependencyState $wrong -Tracker $waitTracker -Now $start
    Write-ShadowAcceptanceProgress -State $wait -Tracker $waitTracker -Now $start.AddSeconds(15)
    Assert-Progress ($messages.Count -eq 8 -and $messages[-1] -match 'Waiting for: workspace-trust. Continue in the VS Code test window' -and ($messages -join '') -notmatch 'foreign') 'Initialization/trust waits must heartbeat and ignore unrelated dependency snapshots.'
    @{suite='Dependency entry-point imports and acceptance progress';checks=$checks;passed=$true;limitations='Real PowerShell imports, files, hashes and JSON polling. GUI/Kilo/version execution boundaries are fixtures; no target acceptance claim.'}|ConvertTo-Json
}finally{
    [Environment]::SetEnvironmentVariable('LOKIENTE_TOOLCHAIN_RUN_ID',$previous)
    [Environment]::SetEnvironmentVariable('LOKIENTE_TEST_TOKEN',$secret)
    $resolved=[IO.Path]::GetFullPath($root);$allowed=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
    if(-not $resolved.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notlike 'lokiente-progress-*'){throw 'Unsafe cleanup'}
    if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
