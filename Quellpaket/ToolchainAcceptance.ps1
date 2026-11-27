#requires -Version 7.4
# Live acceptance. No mocked VS Code, Kilo, router or model is accepted here.
Set-StrictMode -Version Latest

function Select-ShadowAcceptanceMode {
    param([switch]$RunAcceptanceTest,[switch]$SkipAcceptanceTest)
    if($RunAcceptanceTest -and $SkipAcceptanceTest){throw 'RunAcceptanceTest and SkipAcceptanceTest are mutually exclusive.'}
    if($SkipAcceptanceTest){return 'Skip'}
    if($RunAcceptanceTest){return 'Run'}
    while($true){
        try{$answer=Read-Host 'Run the real VS Code/Kilo/LM Studio acceptance in your managed work profile now? Close its VS Code windows first. [Y/n]'}
        catch{return 'Blocked'}
        if([string]::IsNullOrWhiteSpace($answer) -or $answer -match '^(?i:y|yes|j|ja)$'){return 'Run'}
        if($answer -match '^(?i:n|no|nein)$'){return 'Skip'}
        Write-Host 'Enter Y to test, or N to skip. Skipping does not verify the toolchain.'
    }
}

function Write-ShadowAcceptanceJson {
    param([string]$Path,$Value)
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $Path))
    $temporary=$Path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
    try{
        [IO.File]::WriteAllText($temporary,($Value|ConvertTo-Json -Depth 30),[Text.UTF8Encoding]::new($false))
        [IO.File]::Move($temporary,$Path,$true)
    }finally{if(Test-Path -LiteralPath $temporary){Remove-Item -LiteralPath $temporary -Force}}
}

function Read-ShadowAcceptanceJson {
    param([Parameter(Mandatory)][string]$Path,[switch]$AsHashtable)
    # Atomic replacement on Windows requires every reader to share Delete.
    # ReadToEnd keeps one complete old/new snapshot even if its name is replaced.
    $stream=[IO.FileStream]::new($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    try{
        $reader=[IO.StreamReader]::new($stream,[Text.Encoding]::UTF8,$true)
        try{$text=$reader.ReadToEnd()}finally{$reader.Dispose()}
    }finally{$stream.Dispose()}
    return ConvertFrom-Json -InputObject $text -AsHashtable:$AsHashtable -NoEnumerate
}

function Read-ShadowAcceptanceState {
    param([string]$Path,[string]$RunId,[switch]$AsHashtable)
    $failurePath=[IO.Path]::ChangeExtension($Path,'failure.json')
    if(Test-Path -LiteralPath $failurePath -PathType Leaf){
        $failure=Read-ShadowAcceptanceJson -Path $failurePath -AsHashtable:$AsHashtable
        if($failure.runId -ceq $RunId -and $failure.status -in @('FAIL','BLOCKED')){return $failure}
    }
    return Read-ShadowAcceptanceJson -Path $Path -AsHashtable:$AsHashtable
}

function Protect-ShadowAcceptanceText {
    param([AllowEmptyString()][string]$Text)
    foreach($entry in [Environment]::GetEnvironmentVariables('Process').GetEnumerator()){
        if($entry.Key -match '(?i)token|key|password|secret' -and ([string]$entry.Value).Length -gt 3){$Text=$Text.Replace([string]$entry.Value,'[REDACTED]')}
    }
    return ($Text -replace '(?i)(Bearer\s+|Basic\s+)[A-Za-z0-9+/_=.:-]+','$1[REDACTED]' -replace '(?i)((?:api[_-]?key|password|authorization|auth_token|access_token|refresh_token)\s*["'']?\s*[:=]\s*["'']?)[^\s"'',;}]+','$1[REDACTED]' -replace '(?i)([?&](?:token|key|password|auth_token)=)[^&\s]+','$1[REDACTED]')
}

function Write-ShadowAcceptanceProgress {
    param($State,$DependencyState,[Parameter(Mandatory)][hashtable]$Tracker,[datetime]$Now=[DateTime]::UtcNow,[int]$HeartbeatSeconds=15)
    if((Get-LrProperty $State 'runId') -cne $Tracker.runId){return}
    if(-not $Tracker.ContainsKey('seen')){$Tracker.seen=@{};$Tracker.active=@{};$Tracker.lastMessageUtc=$Now}
    $pending=[Collections.Generic.List[object]]::new()
    foreach($stream in @('host','dependency')){
        $value=if($stream -eq 'host'){$State}else{$DependencyState}
        if(-not $value -or (Get-LrProperty $value 'runId') -cne $Tracker.runId){continue}
        $events=@(Get-LrProperty $value 'progress' @())
        foreach($event in $events){$pending.Add(@{stream=$stream;key=($stream+'/event/'+$event.sequence);event=$event})}
        # Older reports and the persistence-failure fallback can contain results
        # without progress events. Those results must also reach the terminal.
        $fallbackSequence=$events.Count
        foreach($case in @(Get-LrProperty $value 'cases' @())){
            if(@($events|Where-Object {$_.id -ceq $case.id -and $_.status -cne 'RUNNING'}).Count){continue}
            $fallbackSequence++
            $pending.Add(@{stream=$stream;key=($stream+'/case/'+$case.id);event=@{sequence=$fallbackSequence;id=$case.id;component=(Get-LrProperty $case 'component' (Get-LrProperty $case 'name' 'LoKiEnte'));status=$case.status;evidence=(Get-LrProperty $case 'evidence' '');utc=(Get-LrProperty $value 'finishedAtUtc' (Get-LrProperty $value 'startedAtUtc' $Now.ToString('o')))}})
        }
    }
    $elapsed=[Math]::Max(0,($Now-$Tracker.startedAtUtc).TotalSeconds)
    foreach($item in @($pending|Sort-Object {[datetime]$_.event.utc},{$_.event.sequence})){
        if($Tracker.seen.ContainsKey($item.key)){continue}
        $event=$item.event;$status=[string]$event.status
        if($status -notin @('RUNNING','PASS','FAIL','BLOCKED','SKIPPED','NOT_APPLICABLE')){continue}
        $Tracker.seen[$item.key]=$true
        $key=$item.stream+'/'+$event.id
        if($status -ceq 'RUNNING'){$Tracker.active[$key]=$event}else{$Tracker.active.Remove($key)}
        $label=if($status -ceq 'RUNNING'){'START'}else{$status}
        $duration=Get-LrProperty $event 'durationMs'
        $detail=if($status -ceq 'RUNNING'){''}else{': '+[string](Get-LrProperty $event 'evidence' '')}
        if($null -ne $duration){$detail+=' ('+([double]$duration/1000).ToString('0.0',[Globalization.CultureInfo]::InvariantCulture)+'s)'}
        $message=Protect-ShadowAcceptanceText ("[Test +{0:0}s] {1}: {2} / {3}{4}" -f $elapsed,$label,$event.component,$event.id,$detail)
        Write-ShadowMessage ($message -replace '[\x00-\x1F\x7F]+',' ') $(if($status -eq 'PASS'){'OK'}elseif($status -in @('FAIL','BLOCKED','SKIPPED')){'WARN'}else{'INFO'})
        $Tracker.lastMessageUtc=$Now
    }
    if((Get-LrProperty $State 'status') -ne 'RUNNING'){return}
    if($DependencyState -and (Get-LrProperty $DependencyState 'runId') -ceq $Tracker.runId -and (Get-LrProperty $DependencyState 'status') -ne 'RUNNING'){
        foreach($key in @($Tracker.active.Keys|Where-Object {$_ -like 'dependency/*'})){$Tracker.active.Remove($key)}
    }
    $waiting=[string](Get-LrProperty $State 'waitingFor')
    $guidance=if($waiting -like 'workspace-trust*' -or $waiting -like 'kilo-visible-response*'){'Continue in the VS Code test window.'}else{'Waiting for component readiness.'}
    if($waiting -and (Get-LrProperty $Tracker 'waitingFor') -cne $waiting){
        Write-ShadowMessage "[Test +$([int]$elapsed)s] Waiting for: $waiting. $guidance"
        $Tracker.lastMessageUtc=$Now
    }
    $Tracker.waitingFor=$waiting
    if(($Now-$Tracker.lastMessageUtc).TotalSeconds -ge $HeartbeatSeconds){
        $current=@($Tracker.active.Values|Sort-Object {[datetime]$_.utc} -Descending|Select-Object -First 1)
        $step=if($current.Count){$current[0].component+' / '+$current[0].id}else{'VS Code startup / acceptance initialization'}
        $running=if($current.Count){[Math]::Max(0,($Now-[datetime]$current[0].utc).TotalSeconds)}else{$elapsed}
        $done=@(Get-LrProperty $State 'cases' @()).Count+@(Get-LrProperty $DependencyState 'cases' @()).Count
        $message="[Test +$([int]$elapsed)s] RUNNING: $step ($([int]$running)s in this step); $done results recorded."
        if($waiting){$message+=" Waiting for: $waiting. $guidance"}
        Write-ShadowMessage (Protect-ShadowAcceptanceText $message)
        $Tracker.lastMessageUtc=$Now
    }
}

function Test-ShadowToolchainDependencies {
    param([Parameter(Mandatory)][string]$InstallRoot,[Parameter(Mandatory)][string]$WorkingDirectory,[string]$ResultPath)
    $cases=[Collections.Generic.List[object]]::new()
    $report=[ordered]@{schema=1;kind='installed-toolchain-dependencies';runId=[Environment]::GetEnvironmentVariable('LOKIENTE_TOOLCHAIN_RUN_ID');status='RUNNING';startedAtUtc=[DateTime]::UtcNow.ToString('o');cases=@();progress=@()}
    if($ResultPath){Write-ShadowAcceptanceJson -Path $ResultPath -Value $report}
    $chain=Get-Content -LiteralPath (Join-Path $InstallRoot 'toolchain.json') -Raw|ConvertFrom-Json -AsHashtable
    $config=Get-Content -LiteralPath (Join-Path $InstallRoot 'kilo-managed/kilo.json') -Raw|ConvertFrom-Json -AsHashtable
    $bundled=$null
    foreach($spec in @(
        @{Id='desktop-collector';Name='Installed console-free desktop collector';Action={Test-ShadowDesktopRunnerReady -InstallRoot $InstallRoot -NodePath $chain.nodeExecutable -WorkingDirectory $WorkingDirectory}},
        @{Id='git-local-clone';Name='Native Git local repository clone';Action={Test-ShadowGitCloneReadiness -InstallRoot $InstallRoot -WorkingDirectory $WorkingDirectory -GitPath $chain.gitExecutable}},
        @{Id='ripgrep';Name='Provisioned ripgrep';Action={Assert-ShadowRipgrepReady -InstallRoot $InstallRoot}},
        @{Id='embedded-kilo';Name='Installed Kilo extension and embedded executable';Action={Get-ShadowBundledKilo -CodePath $chain.codeExecutable -InstallRoot $InstallRoot}},
        @{Id='cli-config';Name='Standalone Kilo effective provider, roles and permissions';Action={Assert-ShadowKiloEffectiveConfig -KiloExecutable $chain.kiloExecutable -KiloArgumentPrefix @($chain.kiloArgumentPrefix) -InstallRoot $InstallRoot -Config $config -WorkingDirectory $WorkingDirectory}},
        @{Id='cli-tools';Name='Standalone Kilo LoKiEnte tool imports';Action={Assert-ShadowKiloWorkflowTools -KiloExecutable $chain.kiloExecutable -KiloArgumentPrefix @($chain.kiloArgumentPrefix) -InstallRoot $InstallRoot -Config $config -WorkingDirectory $WorkingDirectory}},
        @{Id='cli-search';Name='Standalone Kilo actual file search';Action={Test-ShadowKiloSearch -InstallRoot $InstallRoot -KiloExecutable $chain.kiloExecutable -KiloArgumentPrefix @($chain.kiloArgumentPrefix) -ConfigJson ($config|ConvertTo-Json -Depth 40 -Compress)}},
        @{Id='embedded-config';Name='Embedded Kilo effective provider, roles and permissions';Action={if(-not $bundled){throw 'Embedded Kilo is unavailable.'};Assert-ShadowKiloEffectiveConfig -KiloExecutable $bundled -InstallRoot $InstallRoot -Config $config -WorkingDirectory $WorkingDirectory}},
        @{Id='embedded-tools';Name='Embedded Kilo LoKiEnte tool imports';Action={if(-not $bundled){throw 'Embedded Kilo is unavailable.'};Assert-ShadowKiloWorkflowTools -KiloExecutable $bundled -InstallRoot $InstallRoot -Config $config -WorkingDirectory $WorkingDirectory}},
        @{Id='embedded-search';Name='Embedded Kilo actual file search';Action={if(-not $bundled){throw 'Embedded Kilo is unavailable.'};Test-ShadowKiloSearch -InstallRoot $InstallRoot -KiloExecutable $bundled -ConfigJson ($config|ConvertTo-Json -Depth 40 -Compress)}}
    )){
        $clock=[Diagnostics.Stopwatch]::StartNew()
        $report.progress+=@{sequence=$report.progress.Count+1;utc=[DateTime]::UtcNow.ToString('o');id=$spec.Id;component=$spec.Name;status='RUNNING';evidence=''}
        if($ResultPath){Write-ShadowAcceptanceJson -Path $ResultPath -Value $report}
        try{
            Write-ShadowMessage "Acceptance: $($spec.Name)"
            $value=& $spec.Action
            if($spec.Id -eq 'embedded-kilo'){$bundled=[string]$value}
            $cases.Add([ordered]@{id=$spec.Id;name=$spec.Name;status='PASS';evidence='Executed against installed binaries and the prepared configuration.';durationMs=$clock.ElapsedMilliseconds})
            Write-ShadowMessage "PASS: $($spec.Name)" 'OK'
        }catch{
            $cases.Add([ordered]@{id=$spec.Id;name=$spec.Name;status='FAIL';evidence=(Protect-ShadowAcceptanceText $_.Exception.Message);durationMs=$clock.ElapsedMilliseconds})
            Write-ShadowMessage "FAIL: $($spec.Name): $($cases[-1].evidence)" 'WARN'
        }
        $case=$cases[-1]
        $report.cases=$cases.ToArray()
        $report.progress+=@{sequence=$report.progress.Count+1;utc=[DateTime]::UtcNow.ToString('o');id=$spec.Id;component=$spec.Name;status=$case.status;evidence=$case.evidence;durationMs=$case.durationMs}
        if($ResultPath){Write-ShadowAcceptanceJson -Path $ResultPath -Value $report}
    }
    $report.status=if(@($cases|Where-Object {$_.status -ne 'PASS'}).Count){'FAIL'}else{'PASS'}
    $report.finishedAtUtc=[DateTime]::UtcNow.ToString('o')
    if($ResultPath){Write-ShadowAcceptanceJson -Path $ResultPath -Value $report}
    return [pscustomobject]$report
}

function Write-ShadowAcceptanceJUnit {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$Report)
    $cases=@($Report.cases)
    $failures=@($cases|Where-Object {$_.status -eq 'FAIL'}).Count
    $skipped=@($cases|Where-Object {$_.status -notin @('PASS','FAIL')}).Count
    $xml='<?xml version="1.0" encoding="utf-8"?><testsuites><testsuite name="LoKiEnte live toolchain" tests="'+$cases.Count+'" failures="'+$failures+'" skipped="'+$skipped+'">'
    foreach($case in $cases){
        $xml+='<testcase name="'+[Security.SecurityElement]::Escape([string]$case.id)+'">'
        if($case.status -ne 'PASS'){
            $tag=if($case.status -eq 'FAIL'){'failure'}else{'skipped'}
            $xml+='<'+$tag+' message="'+[Security.SecurityElement]::Escape(([string]$case.evidence -replace '[\x00-\x08\x0B\x0C\x0E-\x1F]',''))+'"/>'
        }
        $xml+='</testcase>'
    }
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $Path))
    [IO.File]::WriteAllText($Path,($xml+'</testsuite></testsuites>'),[Text.UTF8Encoding]::new($false))
}

function Get-ShadowAcceptanceLaunchArguments {
    param([Parameter(Mandatory)][string]$InstallRoot,[Parameter(Mandatory)][string]$OpenPath)
    return Get-ShadowVsCodeLaunchArguments -InstallRoot $InstallRoot -OpenPath $OpenPath
}

function Invoke-ShadowToolchainAcceptance {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$InstallRoot,[ValidateRange(60,3600)][int]$TimeoutSeconds=3600,[switch]$WorkspaceTrust)
    $InstallRoot=[IO.Path]::GetFullPath($InstallRoot)
    $id=[guid]::NewGuid().ToString('N')
    $directory=Join-Path $InstallRoot ('diagnostics/toolchain/'+$id)
    $project=Join-Path $directory 'project'
    [void][IO.Directory]::CreateDirectory($project)
    $resultPath=Join-Path $directory 'acceptance.json'
    $tracker=@{runId=$id;startedAtUtc=[DateTime]::UtcNow}
    $latestPath=Join-Path $InstallRoot 'diagnostics/toolchain/latest.json'
    $initial=[ordered]@{schema=1;kind='live-toolchain-acceptance';runId=$id;status='RUNNING';startedAtUtc=[DateTime]::UtcNow.ToString('o');cases=@();reportPath=$resultPath}
    Write-ShadowAcceptanceJson -Path $resultPath -Value $initial
    try{
        $chain=Get-Content -LiteralPath (Join-Path $InstallRoot 'toolchain.json') -Raw|ConvertFrom-Json -AsHashtable
        $configPath=Join-Path $InstallRoot 'kilo-managed/kilo.json'
        $configJson=Get-Content -LiteralPath $configPath -Raw
        $null=$configJson|ConvertFrom-Json -AsHashtable
        foreach($tool in @('codeExecutable','powerShellExecutable','nodeExecutable','gitExecutable')){
            if(-not(Test-Path -LiteralPath $chain.$tool -PathType Leaf)){throw "Installed tool is unavailable: $tool"}
        }
        Assert-ShadowAcceptanceProfileClosed -InstallRoot $InstallRoot -CodePath $chain.codeExecutable
        $poolPath=Join-Path $InstallRoot 'runtime/model-pool.json'
        if(Test-Path -LiteralPath $poolPath -PathType Leaf){
            $pool=Get-Content -LiteralPath $poolPath -Raw|ConvertFrom-Json
            # Reuse the launcher's guarded lifecycle. Keep-mode provisioning may
            # otherwise leave an older router running without current evidence events.
            $null=Start-ShadowModelRouter -InstallRoot $InstallRoot -Pool $pool -NodePath $chain.nodeExecutable -PowerShellPath $chain.powerShellExecutable
        }
        $bundled=Get-ShadowBundledKilo -CodePath $chain.codeExecutable -InstallRoot $InstallRoot
        $expected=Get-Content -LiteralPath (Join-Path $InstallRoot 'app/vscode-startup/package.json') -Raw|ConvertFrom-Json
        $helper=@(Get-ChildItem -LiteralPath (Join-Path $InstallRoot 'vscode-extensions') -Directory -Filter 'lokiente.managed-startup-*' | Where-Object {
            $manifest=Get-Content -LiteralPath (Join-Path $_.FullName 'package.json') -Raw|ConvertFrom-Json
            $manifest.publisher -ceq 'lokiente' -and $manifest.name -ceq 'managed-startup' -and $manifest.version -ceq $expected.version
        })
        if($helper.Count -ne 1){throw 'The current LoKiEnte startup extension is missing or ambiguous. Reprovision before acceptance.'}
        $prepareArguments=@((Join-Path $InstallRoot 'app/vscode-startup/acceptance-project.cjs'),$InstallRoot,$id,$chain.gitExecutable)
        if($WorkspaceTrust){$prepareArguments+='--reuse-trusted'}
        $preparation=Invoke-ShadowNative -FilePath $chain.nodeExecutable -ArgumentList $prepareArguments -WorkingDirectory $directory -TimeoutSeconds 180 -Quiet
        $gitEvidence=$preparation.StdOut|ConvertFrom-Json
        $project=$gitEvidence.project
        $ownerRunId=[string]$gitEvidence.ownerRunId
        $initial.workspaceTrust=$gitEvidence.workspaceTrust
        Write-ShadowAcceptanceJson -Path (Join-Path $directory 'project-preparation.json') -Value $gitEvidence
        $initial.projectGit=$gitEvidence
        $initial.cases=@(@{id='acceptance-project-git';component='Git';status='PASS';evidence="Generated test project initialized with commit $($gitEvidence.head)."})
        Write-ShadowAcceptanceJson -Path $resultPath -Value $initial
        $workspace=New-ShadowWorkspace -Root $InstallRoot -Project $project -PwshPath $chain.powerShellExecutable
        $settingsPath=Join-Path $InstallRoot 'vscode-data/User/settings.json'
        $baselineFiles=@($settingsPath,$workspace.workspace,(Join-Path $InstallRoot 'kilo-managed/kilo.json'),(Join-Path $InstallRoot 'toolchain.json'),(Join-Path $InstallRoot 'app/DesktopRunner.ps1'),(Join-Path $InstallRoot 'app/Workspace.ps1'))
        $baseline=@{runId=$id;dataDirectory=(Join-Path $InstallRoot 'vscode-data');workspace=$workspace.workspace
            userSettings=(Get-Content -LiteralPath $settingsPath -Raw|ConvertFrom-Json -AsHashtable)
            workspaceSettings=(Get-Content -LiteralPath $workspace.workspace -Raw|ConvertFrom-Json -AsHashtable).settings
            files=@($baselineFiles|ForEach-Object {@{path=$_;sha256=(Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash.ToLowerInvariant()}})}
        Write-ShadowAcceptanceJson -Path (Join-Path $directory 'configuration-baseline.json') -Value $baseline
        $environment=Get-ShadowEditorEnvironment -InstallRoot $InstallRoot -ConfigJson $configJson -BundledKilo $bundled -Toolchain $chain
        $environment.LOKIENTE_MANAGED_VSCODE='1'
        $environment.LOKIENTE_INSTALL_ROOT=[IO.Path]::GetFullPath($InstallRoot)
        $environment.LOKIENTE_VSCODE_DATA_DIR=Join-Path $InstallRoot 'vscode-data'
        $environment.LOKIENTE_ET_KILO=$bundled
        $environment.LOKIENTE_TOOLCHAIN_REPORT=$resultPath
        $environment.LOKIENTE_TOOLCHAIN_PROJECT=$project
        $environment.LOKIENTE_TOOLCHAIN_PROJECT_OWNER=$ownerRunId
        $environment.LOKIENTE_TOOLCHAIN_RUN_ID=$id
        $environment.LOKIENTE_TOOLCHAIN_DEADLINE_UTC=[DateTime]::UtcNow.AddSeconds($TimeoutSeconds).ToString('o')
        $environment.LOKIENTE_TOOLCHAIN_WORKSPACE=$workspace.workspace
        $environment.LOKIENTE_STARTUP_VERSION=$expected.version
        $arguments=Get-ShadowAcceptanceLaunchArguments -InstallRoot $InstallRoot -OpenPath $workspace.workspace
        $initial.launch=@{mode='production-managed-profile';dataDirectory=$environment.LOKIENTE_VSCODE_DATA_DIR;extensionsDirectory=(Join-Path $InstallRoot 'vscode-extensions');arguments=@($arguments);workspace=$workspace.workspace;collector='desktop-runner'}
        Write-ShadowAcceptanceJson -Path $resultPath -Value $initial
        Write-ShadowMessage 'Starting acceptance with the real desktop launcher, managed VS Code profile, extensions and workspace template. Review Workspace Trust in the test window.'
        $launchId=Start-ShadowEditor -InstallRoot $InstallRoot -CodePath $chain.codeExecutable -Arguments $arguments -WorkingDirectory $project -Environment $environment -WaitForHost
        $watch=[Diagnostics.Stopwatch]::StartNew()
        while($watch.Elapsed.TotalSeconds -lt $TimeoutSeconds){
            $state=Read-ShadowAcceptanceState -Path $resultPath -RunId $id
            $dependencyPath=Join-Path $directory 'dependencies.json'
            $dependency=if(Test-Path -LiteralPath $dependencyPath -PathType Leaf){Read-ShadowAcceptanceJson -Path $dependencyPath}else{$null}
            Write-ShadowAcceptanceProgress -State $state -DependencyState $dependency -Tracker $tracker
            if($state.status -in @('PASS','FAIL','BLOCKED')){break}
            $statusPath=Join-Path $InstallRoot ('runtime/launch-requests/'+$launchId+'.status.json')
            if(Test-Path -LiteralPath $statusPath){
                $launchStatus=Read-ShadowAcceptanceJson -Path $statusPath
                if($launchStatus.phase -ceq 'failed'){throw "Desktop launcher failed: $($launchStatus.error)"}
                if($launchStatus.phase -ceq 'exited'){
                    $state=Read-ShadowAcceptanceState -Path $resultPath -RunId $id
                    if($state.status -in @('PASS','FAIL','BLOCKED')){break}
                    throw "VS Code exited before acceptance completed (exit $($launchStatus.exitCode)). No PASS was recorded."
                }
            }
            Start-Sleep -Milliseconds 500
        }
        if($state.status -notin @('PASS','FAIL','BLOCKED')){
            Write-ShadowAcceptanceJson -Path (Join-Path $directory 'cancellation.json') -Value @{runId=$id;reason='The native acceptance deadline expired. No PASS was recorded.';utc=[DateTime]::UtcNow.ToString('o')}
            throw 'The live acceptance deadline expired. No PASS was recorded. Close the test window before retrying.'
        }

    }catch{
        $failure=$_
        Write-ShadowAcceptanceJson -Path (Join-Path $directory 'cancellation.json') -Value @{runId=$id;reason=$failure.Exception.Message;utc=[DateTime]::UtcNow.ToString('o')}
        try{$partial=Read-ShadowAcceptanceState -Path $resultPath -RunId $id -AsHashtable}catch{$partial=$initial}
        $partial.cases=@($partial.cases)+@(@{id='live-host';name='Real VS Code acceptance';status='BLOCKED';evidence=$failure.Exception.Message})
        $partial.status=if(@($partial.cases|Where-Object {$_.status -eq 'FAIL'}).Count){'FAIL'}else{'BLOCKED'}
        $partial.finishedAtUtc=[DateTime]::UtcNow.ToString('o')
        Write-ShadowAcceptanceJson -Path $resultPath -Value $partial
    }
    $result=Read-ShadowAcceptanceState -Path $resultPath -RunId $id
    $dependencyPath=Join-Path $directory 'dependencies.json'
    $dependency=if(Test-Path -LiteralPath $dependencyPath -PathType Leaf){Read-ShadowAcceptanceJson -Path $dependencyPath}else{$null}
    Write-ShadowAcceptanceProgress -State $result -DependencyState $dependency -Tracker $tracker
    Write-ShadowAcceptanceJUnit -Path ([IO.Path]::ChangeExtension($resultPath,'junit.xml')) -Report $result
    Write-ShadowAcceptanceJson -Path $latestPath -Value $result
    Write-ShadowAcceptanceJUnit -Path (Join-Path $InstallRoot 'diagnostics/toolchain/latest.junit.xml') -Report $result
    Write-ShadowMessage "Live toolchain acceptance: $($result.status). Report: $($result.reportPath)" $(if($result.status -eq 'PASS'){'OK'}else{'WARN'})
    return $result
}
