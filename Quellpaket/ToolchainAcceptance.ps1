#requires -Version 7.4
# Live acceptance. No mocked VS Code, Kilo, router or model is accepted here.
Set-StrictMode -Version Latest

function Select-ShadowAcceptanceMode {
    param([switch]$RunAcceptanceTest,[switch]$SkipAcceptanceTest)
    if($RunAcceptanceTest -and $SkipAcceptanceTest){throw 'RunAcceptanceTest and SkipAcceptanceTest are mutually exclusive.'}
    if($SkipAcceptanceTest){return 'Skip'}
    if($RunAcceptanceTest){return 'Run'}
    while($true){
        try{$answer=Read-Host 'Run the real VS Code/Kilo/LM Studio acceptance now? Close other managed windows first. [Y/n]'}
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

function Test-ShadowToolchainDependencies {
    param([Parameter(Mandatory)][string]$InstallRoot,[Parameter(Mandatory)][string]$WorkingDirectory)
    $cases=[Collections.Generic.List[object]]::new()
    $chain=Get-Content -LiteralPath (Join-Path $InstallRoot 'toolchain.json') -Raw|ConvertFrom-Json
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
        try{
            Write-ShadowMessage "Acceptance: $($spec.Name)"
            $value=& $spec.Action
            if($spec.Id -eq 'embedded-kilo'){$bundled=[string]$value}
            $cases.Add([ordered]@{id=$spec.Id;name=$spec.Name;status='PASS';evidence='Executed against installed binaries and the prepared configuration.'})
            Write-ShadowMessage "PASS: $($spec.Name)" 'OK'
        }catch{
            $cases.Add([ordered]@{id=$spec.Id;name=$spec.Name;status='FAIL';evidence=$_.Exception.Message})
            Write-ShadowMessage "FAIL: $($spec.Name): $($_.Exception.Message)" 'WARN'
        }
    }
    return [pscustomobject]@{schema=1;kind='installed-toolchain-dependencies';cases=$cases.ToArray();status=$(if(@($cases|Where-Object {$_.status -ne 'PASS'}).Count){'FAIL'}else{'PASS'})}
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
    param([Parameter(Mandatory)][string]$Project,[Parameter(Mandatory)][string]$DataDirectory,[Parameter(Mandatory)][string]$ExtensionsDirectory)
    return @($Project,'--new-window','--user-data-dir',$DataDirectory,'--extensions-dir',$ExtensionsDirectory,
        '--skip-welcome','--skip-release-notes','--telemetry-level','off',
        '--disable-extension','GitHub.copilot','--disable-extension','GitHub.copilot-chat')
}

function Invoke-ShadowToolchainAcceptance {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$InstallRoot,[ValidateRange(60,3600)][int]$TimeoutSeconds=1800)
    $InstallRoot=[IO.Path]::GetFullPath($InstallRoot)
    $id=[guid]::NewGuid().ToString('N')
    $directory=Join-Path $InstallRoot ('diagnostics/toolchain/'+$id)
    $project=Join-Path $directory 'project'
    [void][IO.Directory]::CreateDirectory($project)
    $resultPath=Join-Path $directory 'acceptance.json'
    $latestPath=Join-Path $InstallRoot 'diagnostics/toolchain/latest.json'
    $initial=[ordered]@{schema=1;kind='live-toolchain-acceptance';runId=$id;status='RUNNING';startedAtUtc=[DateTime]::UtcNow.ToString('o');cases=@();reportPath=$resultPath}
    Write-ShadowAcceptanceJson -Path $resultPath -Value $initial
    try{
        $chain=Get-Content -LiteralPath (Join-Path $InstallRoot 'toolchain.json') -Raw|ConvertFrom-Json
        $configPath=Join-Path $InstallRoot 'kilo-managed/kilo.json'
        $configJson=Get-Content -LiteralPath $configPath -Raw
        $null=$configJson|ConvertFrom-Json -AsHashtable
        foreach($tool in @('codeExecutable','powerShellExecutable','nodeExecutable')){
            if(-not(Test-Path -LiteralPath $chain.$tool -PathType Leaf)){throw "Installed tool is unavailable: $tool"}
        }
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
        $environment=Get-ShadowLocalEnvironment -InstallRoot $InstallRoot -ConfigJson $configJson
        $environment.LOKIENTE_MANAGED_VSCODE='1'
        $environment.LOKIENTE_INSTALL_ROOT=[IO.Path]::GetFullPath($InstallRoot)
        $environment.LOKIENTE_VSCODE_DATA_DIR=Join-Path $directory 'vscode-data'
        $environment.LOKIENTE_ET_KILO=$bundled
        $environment.LOKIENTE_TOOLCHAIN_REPORT=$resultPath
        $environment.LOKIENTE_TOOLCHAIN_PROJECT=$project
        $environment.LOKIENTE_TOOLCHAIN_RUN_ID=$id
        $environment.LOKIENTE_EDITOR_LAUNCH_ID=''
        $environment.LOKIENTE_STARTUP_VERSION=$expected.version
        $start=[Diagnostics.ProcessStartInfo]::new()
        $start.FileName=$chain.codeExecutable;$start.WorkingDirectory=$project;$start.UseShellExecute=$false
        [IO.File]::WriteAllText((Join-Path $project 'README.md'),"# LoKiEnte acceptance workspace`n`nThis folder was generated locally for the LoKiEnte toolchain test.`nReview VS Code's Workspace Trust prompt and trust this test folder to run the checks.`nThe test reads generated probe files and requests local LM Studio inference.`nRun ID: $id`n",[Text.UTF8Encoding]::new($false))
        # Use the installed helper in an ordinary window. Extension test mode
        # suppresses the normal trust workflow and does not test installed startup.
        foreach($arg in (Get-ShadowAcceptanceLaunchArguments -Project $project -DataDirectory $environment.LOKIENTE_VSCODE_DATA_DIR -ExtensionsDirectory (Join-Path $InstallRoot 'vscode-extensions'))){[void]$start.ArgumentList.Add($arg)}
        foreach($key in $environment.Keys){$start.Environment[$key]=[string]$environment[$key]}
        foreach($key in @($start.Environment.Keys)){if($key -match '^(VSCODE|ELECTRON)_'){[void]$start.Environment.Remove($key)}}
        Write-ShadowMessage 'Starting real VS Code acceptance. In the new window, review and trust the generated test folder. Use Manage Workspace Trust if prompted; do not close the window during checks.'
        $process=[Diagnostics.Process]::Start($start)
        try{
            $watch=[Diagnostics.Stopwatch]::StartNew()
            $lastProgress=''
            while($watch.Elapsed.TotalSeconds -lt $TimeoutSeconds){
                $state=Get-Content -LiteralPath $resultPath -Raw|ConvertFrom-Json
                $progress=[string](Get-LrProperty $state 'waitingFor')
                if($progress -and $progress -cne $lastProgress){Write-ShadowMessage "Acceptance waiting for: $progress. Continue in the VS Code test window.";$lastProgress=$progress}
                if($state.status -in @('PASS','FAIL','BLOCKED')){break}
                if($process.HasExited -and $watch.Elapsed.TotalSeconds -gt 30){throw "VS Code exited without a completed acceptance report (exit $($process.ExitCode))."}
                Start-Sleep -Milliseconds 500
            }
            if($state.status -notin @('PASS','FAIL','BLOCKED')){
                # This is the unique test profile/process created above. Preserve normal windows and LM Studio.
                if(-not $process.HasExited){$process.Kill($true)}
                throw 'The live acceptance deadline expired. No PASS was recorded.'
            }
        }finally{$process.Dispose()}
    }catch{
        $failure=$_
        try{$partial=Get-Content -LiteralPath $resultPath -Raw|ConvertFrom-Json -AsHashtable}catch{$partial=$initial}
        $partial.cases=@($partial.cases)+@(@{id='live-host';name='Real VS Code acceptance';status='BLOCKED';evidence=$failure.Exception.Message})
        $partial.status=if(@($partial.cases|Where-Object {$_.status -eq 'FAIL'}).Count){'FAIL'}else{'BLOCKED'}
        $partial.finishedAtUtc=[DateTime]::UtcNow.ToString('o')
        Write-ShadowAcceptanceJson -Path $resultPath -Value $partial
    }
    $result=Get-Content -LiteralPath $resultPath -Raw|ConvertFrom-Json
    Write-ShadowAcceptanceJUnit -Path ([IO.Path]::ChangeExtension($resultPath,'junit.xml')) -Report $result
    Write-ShadowAcceptanceJson -Path $latestPath -Value $result
    Write-ShadowAcceptanceJUnit -Path (Join-Path $InstallRoot 'diagnostics/toolchain/latest.junit.xml') -Report $result
    Write-ShadowMessage "Live toolchain acceptance: $($result.status). Report: $resultPath" $(if($result.status -eq 'PASS'){'OK'}else{'WARN'})
    return $result
}
