#requires -Version 7.4
# Real Node/Git/files/workspace preparation, with a mocked GUI launch boundary.
param([string]$SourceRoot=(Split-Path -Parent $PSScriptRoot))
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
foreach($file in @('Common.ps1','Runtime.ps1','AgentTemplates.ps1','Workspace.ps1','DesktopRunner.ps1','VsCodeProfile.ps1','ToolchainAcceptance.ps1')){. (Join-Path $SourceRoot $file)}
$root=Join-Path ([IO.Path]::GetTempPath()) ('lokiente-acceptance-launch-'+[guid]::NewGuid().ToString('N'))
$checks=0
function Assert-Launch($Condition,$Message){if(-not $Condition){throw $Message};$script:checks++}
try{
    $script:processes=@()
    function Get-CimInstance {param($ClassName) return $script:processes}
    $code='C:\Synthetic\Code.exe'
    $script:processes=@(@{ExecutablePath=$code;CommandLine='Code.exe --user-data-dir C:\Other\profile'})
    Assert-ShadowAcceptanceProfileClosed -InstallRoot $root -CodePath $code
    $script:processes=@(@{ExecutablePath=$code;CommandLine=('Code.exe --user-data-dir "'+(Join-Path $root 'vscode-data')+'"')})
    $failed=$false;try{Assert-ShadowAcceptanceProfileClosed -InstallRoot $root -CodePath $code}catch{$failed=$_.Exception.Message -match 'already open'}
    Assert-Launch $failed 'An already-running work profile must block acceptance without closing it.'
    $script:processes=@(@{ExecutablePath=$code;CommandLine=$null})
    $failed=$false;try{Assert-ShadowAcceptanceProfileClosed -InstallRoot $root -CodePath $code}catch{$failed=$_.Exception.Message -match 'Cannot inspect'}
    Assert-Launch $failed 'An uninspectable existing editor must not be assumed safe to reuse.'
    $script:processes=@()
    $node=(Get-Command node -CommandType Application|Select-Object -First 1).Source
    $git=(Get-Command git -CommandType Application|Select-Object -First 1).Source
    $pwsh=(Get-Process -Id $PID).Path
    $script:expected=@{codeExecutable=$node;nodeExecutable=$node;gitExecutable=$git;powerShellExecutable=$pwsh;kiloExecutable=$node;kiloArgumentPrefix=@();npmVersion=$null}
    foreach($dir in @('app','kilo-managed','vscode-extensions/lokiente.managed-startup-synthetic')){[void][IO.Directory]::CreateDirectory((Join-Path $root $dir))}
    Copy-Item -LiteralPath (Join-Path $SourceRoot 'vscode-startup') -Destination (Join-Path $root 'app/vscode-startup') -Recurse
    foreach($file in @('DesktopRunner.ps1','Workspace.ps1')){Copy-Item -LiteralPath (Join-Path $SourceRoot $file) -Destination (Join-Path $root ('app/'+$file))}
    Copy-Item -LiteralPath (Join-Path $SourceRoot 'vscode-startup/package.json') -Destination (Join-Path $root 'vscode-extensions/lokiente.managed-startup-synthetic/package.json')
    Write-ShadowAcceptanceJson -Path (Join-Path $root 'toolchain.json') -Value $expected
    Write-ShadowAcceptanceJson -Path (Join-Path $root 'kilo-managed/kilo.json') -Value @{}
    Update-ShadowVsCodeProfile -InstallRoot $root -PowerShellPath $pwsh -VsCodeVersion '1.148.0'
    $settings=Join-Path $root 'vscode-data/User/settings.json';$before=(Get-FileHash -LiteralPath $settings).Hash
    function Get-ShadowBundledKilo {param($CodePath,$InstallRoot) return $node}
    function Start-ShadowEditor {
        param($InstallRoot,$CodePath,$Arguments,$WorkingDirectory,$Environment,[switch]$WaitForHost)
        if($script:simulatePersistenceFailure){
            $report=Read-ShadowAcceptanceJson -Path $Environment.LOKIENTE_TOOLCHAIN_REPORT -AsHashtable
            $report.status='FAIL';$report.persistenceFailure=@{code='EPERM';primaryReportPath=$Environment.LOKIENTE_TOOLCHAIN_REPORT}
            $report.reportPath=[IO.Path]::ChangeExtension($Environment.LOKIENTE_TOOLCHAIN_REPORT,'failure.json')
            $report.cases+=@(@{id='report-persistence';status='FAIL';evidence='Synthetic permanent report lock.'})
            Write-ShadowAcceptanceJson -Path $report.reportPath -Value $report
            return 'b'*32
        }
        if($script:simulateExit){
            Write-ShadowAcceptanceJson -Path (Join-Path $InstallRoot ('runtime/launch-requests/'+('b'*32)+'.status.json')) -Value @{phase='exited';exitCode=0}
            return 'b'*32
        }
        $normal=@(Get-ShadowVsCodeLaunchArguments -InstallRoot $InstallRoot -OpenPath $Environment.LOKIENTE_TOOLCHAIN_WORKSPACE)
        Assert-Launch (($Arguments|ConvertTo-Json -Compress) -ceq ($normal|ConvertTo-Json -Compress)) 'Acceptance must pass the exact desktop argument policy to the real collector boundary.'
        $normalEnv=Get-ShadowEditorEnvironment -InstallRoot $InstallRoot -ConfigJson '{}' -BundledKilo $node -Toolchain $script:expected
        foreach($key in $normalEnv.Keys){if($key -cne 'LOKIENTE_LOG_SINCE_UTC'){Assert-Launch ($Environment[$key] -ceq $normalEnv[$key]) "Desktop environment differs at $key"}}
        Assert-Launch $WaitForHost 'The installed helper handshake is required, not just a successful process start.'
        $baseline=Get-Content (Join-Path (Split-Path $Environment.LOKIENTE_TOOLCHAIN_REPORT) 'configuration-baseline.json') -Raw|ConvertFrom-Json
        Assert-Launch ($baseline.dataDirectory -ieq (Join-Path $InstallRoot 'vscode-data') -and $baseline.files.Count -eq 6) 'Configuration baseline must identify the real work profile and all shared configuration/source hashes.'
        Assert-Launch ($baseline.userSettings.'extensions.autoUpdate' -ceq 'off' -and $baseline.userSettings.'terminal.integrated.commandsToSkipShell'.Count -eq 4) 'Acceptance must capture the same migration-ready profile used for actual work, before the GUI starts.'
        $workspace=Get-Content -LiteralPath $baseline.workspace -Raw|ConvertFrom-Json
        Assert-Launch ($workspace.folders[0].path -ieq $WorkingDirectory -and $workspace.tasks.tasks.Count -gt 0 -and $workspace.settings.'chat.disableAIFeatures') 'The real workspace generator must produce the test project settings and tasks.'
        $report=Get-Content -LiteralPath $Environment.LOKIENTE_TOOLCHAIN_REPORT -Raw|ConvertFrom-Json -AsHashtable
        Assert-Launch ($report.projectGit.head -match '^[a-f0-9]{40,64}$' -and (($report.projectGit.initialized -and $report.projectGit.nativeCommands.Count -ge 6) -or (-not $report.projectGit.initialized -and $report.projectGit.nativeCommands.Count -eq 2))) 'Actual Git init/commit or verified reuse evidence must exist before the GUI launch.'
        if(-not $script:firstProject){$script:firstProject=$WorkingDirectory}else{Assert-Launch ($WorkingDirectory -ieq $script:firstProject -and $report.workspaceTrust.reused) 'WorkspaceTrust must reuse the prior owned project while keeping a fresh report.'}
        $report.status='BLOCKED';$report.cases+=@(@{id='workspace-trust';status='PASS';evidence='Synthetic trust history for the launch regression, not a target observation.'},@{id='synthetic-gui-boundary';status='BLOCKED';evidence='GUI/model execution intentionally not performed by this regression test.'})
        Write-ShadowAcceptanceJson -Path $Environment.LOKIENTE_TOOLCHAIN_REPORT -Value $report
        return 'b'*32
    }
    $script:simulateExit=$false
    $script:simulatePersistenceFailure=$false
    $script:firstProject=$null
    $result=Invoke-ShadowToolchainAcceptance -InstallRoot $root
    Assert-Launch ($result.status -ceq 'BLOCKED' -and $result.cases[-1].id -ceq 'synthetic-gui-boundary') 'Native preparation must reach the intended GUI boundary; it must never claim real acceptance.'
    Assert-Launch ((Get-FileHash -LiteralPath $settings).Hash -ceq $before) 'Acceptance preparation must preserve real profile settings byte for byte.'
    $priorRunId=$result.runId
    $result=Invoke-ShadowToolchainAcceptance -InstallRoot $root -WorkspaceTrust
    Assert-Launch ($result.status -ceq 'BLOCKED' -and $result.runId -cne $priorRunId -and $result.projectGit.ownerRunId -ceq $priorRunId) 'A reused trusted project must retain its owner and use a new report/run ID.'
    $script:simulateExit=$true
    $result=Invoke-ShadowToolchainAcceptance -InstallRoot $root
    Assert-Launch ($result.status -ceq 'BLOCKED' -and $result.cases[-1].evidence -match 'VS Code exited before acceptance completed') 'Closing the real editor before completion must block promptly instead of leaving a RUNNING report until the global deadline.'
    $script:simulateExit=$false;$script:simulatePersistenceFailure=$true
    $result=Invoke-ShadowToolchainAcceptance -InstallRoot $root
    Assert-Launch ($result.status -ceq 'FAIL' -and $result.persistenceFailure.code -ceq 'EPERM') 'The coordinator must consume a terminal persistence failure without waiting for its overall deadline.'
    $primary=Read-ShadowAcceptanceJson -Path $result.persistenceFailure.primaryReportPath
    Assert-Launch ($primary.status -ceq 'RUNNING') 'The coordinator must preserve the prior main report when the helper publishes a separate failure report.'
    $latest=Read-ShadowAcceptanceJson -Path (Join-Path $root 'diagnostics/toolchain/latest.json')
    Assert-Launch ($latest.status -ceq 'FAIL' -and $latest.runId -ceq $result.runId) 'The latest report must expose the actual persistence failure to provisioning.'
    @{suite='Acceptance production-profile launch';checks=$checks;passed=$true;limitations='Real native Git/Node and workspace preparation. Process inventory and GUI launch are synthetic boundaries.'}|ConvertTo-Json
}finally{
    $resolved=[IO.Path]::GetFullPath($root);$allowed=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
    if(-not $resolved.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notlike 'lokiente-acceptance-launch-*'){throw 'Unsafe cleanup'}
    if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
