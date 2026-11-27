#requires -Version 7.4
[CmdletBinding()]
param(
    [string]$InstallRoot=(Split-Path -Parent $PSScriptRoot),
    [string]$ProjectPath,
    [switch]$StartIndexing,
    [switch]$ResetSecurityProfile,
    [switch]$PauseOnError,
    [switch]$Desktop
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')
. (Join-Path $PSScriptRoot 'Runtime.ps1')
. (Join-Path $PSScriptRoot 'ModelSelection.ps1')
. (Join-Path $PSScriptRoot 'Indexing.ps1')
. (Join-Path $PSScriptRoot 'Ripgrep.ps1')
. (Join-Path $PSScriptRoot 'ModelPool.ps1')
. (Join-Path $PSScriptRoot 'Router.ps1')
. (Join-Path $PSScriptRoot 'AgentTemplates.ps1')
. (Join-Path $PSScriptRoot 'Workspace.ps1')
. (Join-Path $PSScriptRoot 'ProjectSelection.ps1')
. (Join-Path $PSScriptRoot 'DesktopRunner.ps1')
Initialize-ShadowToolchainLogging -InstallRoot $InstallRoot
try {
    if(-not $IsWindows){throw 'This launcher is designed for Windows.'}
    $InstallRoot=[IO.Path]::GetFullPath($InstallRoot)
    $securityScript=Join-Path $PSScriptRoot 'SecurityProfile.ps1'
    if($ResetSecurityProfile){& $securityScript -Action Disable -InstallRoot $InstallRoot;return}
    $policyFile=Join-Path $InstallRoot 'security/profile.json'
    if(Test-Path -LiteralPath $policyFile -ErrorAction Stop){
        $policy=Get-Content -LiteralPath $policyFile -Raw | ConvertFrom-Json -ErrorAction Stop
        if($policy.schema -ne 1 -or $policy.mode -cnotin @('standard','offline-vm')){throw 'Invalid security profile. Repair it or explicitly reset the profile.'}
        if($policy.mode -ceq 'offline-vm'){
            if($PauseOnError -or $Desktop){
                Add-Type -AssemblyName System.Windows.Forms
                $choice=[Windows.Forms.MessageBox]::Show(
                    "Open your isolated guest now?"+[Environment]::NewLine+"Yes: start the guest. No: reset to Standard for the next launch. Cancel: close.",
                    'LoKiEnte security profile','YesNoCancel','Question','Button1')
                if($choice -eq 'Cancel'){return}
                if($choice -eq 'No'){& $securityScript -Action Disable -InstallRoot $InstallRoot;return}
            }
            & $securityScript -Action Launch -InstallRoot $InstallRoot
            return
        }
    }
    $ProjectPath=Select-ShadowProject -InstallRoot $InstallRoot -ProjectPath $ProjectPath -Desktop:$Desktop
    if(-not $ProjectPath){
        Write-Host 'Startup cancelled. No model environment started.'
        return
    }
    $null=Assert-ShadowRipgrepReady -InstallRoot $InstallRoot
    $runtimeFile=Join-Path $InstallRoot 'runtime/runtime-state.json'
    $toolchainFile=Join-Path $InstallRoot 'toolchain.json'
    foreach($path in @($toolchainFile)){
        if(-not(Test-Path -LiteralPath $path)){throw "Installation missing: $path. Complete provisioning first."}
    }
    $chain=Get-Content -LiteralPath $toolchainFile -Raw|ConvertFrom-Json -AsHashtable
    $indexingMode=Get-ShadowIndexingMode -Toolchain $chain
    if((Get-LrProperty $chain 'modelMode' 'Single') -ne 'Dual' -and $indexingMode -cne 'Off'){throw 'Semantic indexing requires a provisioned Dual model pool.'}
    $startIndex=Select-ShadowIndexingForLaunch -Mode $indexingMode -StartIndexing:$StartIndexing -Desktop:$Desktop
    if($chain.ContainsKey('modelMode') -and $chain.modelMode -eq 'Dual'){
        $pool=Get-Content -LiteralPath (Join-Path $InstallRoot 'runtime/model-pool.json') -Raw|ConvertFrom-Json
        $router=Start-ShadowModelRouter -InstallRoot $InstallRoot -Pool $pool -NodePath $chain.nodeExecutable -PowerShellPath $chain.powerShellExecutable
        if($startIndex){$embedding=Initialize-ShadowEmbeddingModel -InstallRoot $InstallRoot -Pool $pool -Definition (Get-ShadowEmbeddingDefinition)}
        else{Stop-ShadowEmbeddingModel -InstallRoot $InstallRoot -Pool $pool;$embedding=Set-ShadowIndexingInactive -InstallRoot $InstallRoot -Mode $indexingMode}
        $embeddingArguments=Get-ShadowEmbeddingConfigurationArguments -Embedding $embedding -ApiBaseUrl $router.ApiBaseUrl
        $primary=[string](Get-LrProperty $pool 'PrimaryAlias' 'coder')
        $configuration=New-ShadowAgentConfiguration -InstallRoot $InstallRoot -ModelCatalog (Get-ShadowPoolCatalog $pool) -MainModel $primary -ApiBaseUrl $router.ApiBaseUrl -ApiTokenEnvironmentVariable $pool.ApiTokenEnvironmentVariable @embeddingArguments
    }else{
        $state=Get-Content -LiteralPath $runtimeFile -Raw|ConvertFrom-Json
        $runtime=Configure-LocalRuntime -StateRoot (Join-Path $InstallRoot 'runtime') -LmsPath $state.LmsPath -ModelKey $state.ModelPath -ContextLength $state.ContextLength -Port $state.Port -DownloadModel $false -ApiTokenEnvironmentVariable $state.ApiTokenEnvironmentVariable -AllowUnfitAttempt:($chain.ContainsKey('allowUnfitAttempt') -and $chain.allowUnfitAttempt -eq $true)
        if($runtime.Status -cnotin @('Ready','Deferred')){throw 'Local model status is unknown.'}
        $singleName=if($runtime.Status -ceq 'Deferred'){'LoKiEnte local [NOT YET VERIFIED]'}else{'LoKiEnte local - verified workflow'}
        $configuration=New-ShadowAgentConfiguration -InstallRoot $InstallRoot -ModelId $runtime.ModelId -ModelDisplayName $singleName -ApiBaseUrl $runtime.ApiBaseUrl -ContextLength $runtime.ContextLength -ApiTokenEnvironmentVariable $runtime.ApiTokenEnvironmentVariable
    }
    if($ProjectPath) {
        $entry=New-ShadowWorkspace -Root $InstallRoot -Project $ProjectPath -PwshPath $chain.powerShellExecutable
        Register-ShadowWorkspaces -Root $InstallRoot -Entries @($entry)
        $openPath=$entry.workspace
        $workingDirectory=$entry.project
        Write-ShadowMessage "Task: $($entry.task)"
        Write-ShadowMessage "Project checks: $($entry.checks)"
    } else {
        $openPath=Join-Path $InstallRoot 'welcome'
        $workingDirectory=$InstallRoot
    }
    $null=Assert-ShadowKiloEffectiveConfig -KiloExecutable $chain.kiloExecutable -KiloArgumentPrefix @($chain.kiloArgumentPrefix) -InstallRoot $InstallRoot -Config $configuration.Config -WorkingDirectory $workingDirectory
    $bundledKilo=Get-ShadowBundledKilo -CodePath $chain.codeExecutable -InstallRoot $InstallRoot
    $null=Assert-ShadowKiloEffectiveConfig -KiloExecutable $bundledKilo -InstallRoot $InstallRoot -Config $configuration.Config -WorkingDirectory $workingDirectory
    $null=Assert-ShadowKiloWorkflowTools -KiloExecutable $bundledKilo -InstallRoot $InstallRoot -Config $configuration.Config -WorkingDirectory $workingDirectory
    $environment=Get-ShadowEditorEnvironment -InstallRoot $InstallRoot -ConfigJson ($configuration.Config|ConvertTo-Json -Depth 40 -Compress) -BundledKilo $bundledKilo -Toolchain $chain
    $null=Start-ShadowEditor -InstallRoot $InstallRoot -CodePath $chain.codeExecutable -Arguments (Get-ShadowVsCodeLaunchArguments -InstallRoot $InstallRoot -OpenPath $openPath) -WorkingDirectory $workingDirectory -Environment $environment -WaitForHost
    if($startIndex -and $ProjectPath -and $chain.modelMode -eq 'Dual' -and $embedding.Status -ceq 'Ready'){
        Write-ShadowMessage 'Indexing: enable it in Kilo for this project; first exclude sensitive files in .gitignore or .kilocodeignore. Wait for Complete status.'
    }
    if(-not $startIndex){Write-ShadowMessage "Indexing is off for this launch (provisioned mode: $indexingMode). File search, subagents and tests remain available."}
    Write-ShadowMessage 'VS Code confirmed the current LoKiEnte helper in the managed profile. Kilo readiness and connection messages are in Output -> LoKiEnte.' 'OK'
} catch {
    Write-ShadowToolchainEvent -Component 'Launcher' -Level ERROR -Message $_.Exception.Message
    Write-Error -Message $_.Exception.Message -ErrorAction Continue
    if($Desktop){
        try{
            $chain=Get-Content -LiteralPath (Join-Path $InstallRoot 'toolchain.json') -Raw|ConvertFrom-Json
            $environment=@{LOKIENTE_MANAGED_VSCODE='1';LOKIENTE_INSTALL_ROOT=$InstallRoot;LOKIENTE_VSCODE_DATA_DIR=(Join-Path $InstallRoot 'vscode-data');LOKIENTE_STARTUP_DIAGNOSTICS_ONLY='1';LOKIENTE_STARTUP_VERSION=(Get-Content -LiteralPath (Join-Path $PSScriptRoot 'vscode-startup/package.json') -Raw|ConvertFrom-Json).version}
            $null=Start-ShadowEditor -InstallRoot $InstallRoot -CodePath $chain.codeExecutable -Arguments (Get-ShadowVsCodeLaunchArguments -InstallRoot $InstallRoot -OpenPath $InstallRoot) -WorkingDirectory $InstallRoot -Environment $environment -WaitForHost
            if($env:LOKIENTE_LAUNCH_ID -match '^[a-f0-9]{32}$'){[IO.File]::WriteAllText((Join-Path $InstallRoot ('runtime/launch-requests/'+$env:LOKIENTE_LAUNCH_ID+'.diagnostic-started')),'Diagnostic editor requested.')}
        }catch{Write-ShadowToolchainEvent -Component 'Desktop runner' -Level ERROR -Message ('Unable to open diagnostic editor: '+$_.Exception.Message)}
    }elseif($PauseOnError){
        try { $null=Read-Host 'Press Enter to close' } catch {}
    }
    exit 1
}
