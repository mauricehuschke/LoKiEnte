#requires -Version 7.4
[CmdletBinding()]
param(
    [string]$InstallRoot=(Split-Path -Parent $PSScriptRoot),
    [string]$ProjectPath,
    [switch]$StartIndexing,
    [switch]$ResetSecurityProfile,
    [switch]$PauseOnError
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
function Get-ShadowVsCodeLaunchArguments {
    param([string]$InstallRoot,[string]$OpenPath)
    return @('--user-data-dir',(Join-Path $InstallRoot 'vscode-data'),
        '--extensions-dir',(Join-Path $InstallRoot 'vscode-extensions'),
        '--telemetry-level','off','--disable-extension','GitHub.copilot',
        '--disable-extension','GitHub.copilot-chat','--new-window',$OpenPath)
}
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
            if($PauseOnError){
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
    $ProjectPath=Select-ShadowProject -InstallRoot $InstallRoot -ProjectPath $ProjectPath
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
    $startIndex=Select-ShadowIndexingForLaunch -Mode $indexingMode -StartIndexing:$StartIndexing
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
    $environment=Get-ShadowLocalEnvironment -InstallRoot $InstallRoot -ConfigJson ($configuration.Config|ConvertTo-Json -Depth 40 -Compress)
    if ($chain['npmVersion']) {
        # Both the Node installer and a Windows npm global prefix place the shims
        # three directories above node_modules/npm/bin/npm-cli.js.
        $npmBin=[IO.Path]::GetDirectoryName($chain.npmEntry)
        $npmPrefix=[IO.Directory]::GetParent($npmBin).Parent.Parent.FullName
        $inheritedPath=if ($environment.Contains('PATH')) {$environment['PATH']} else {$env:PATH}
        $environment['PATH']=$npmPrefix+';'+[IO.Path]::GetDirectoryName($chain.nodeExecutable)+';'+$inheritedPath
    }
    $environment['LOKIENTE_MANAGED_VSCODE']='1'
    $environment['LOKIENTE_ET_KILO']=$bundledKilo
    $environment['LOKIENTE_VSCODE_DATA_DIR']=[IO.Path]::GetFullPath((Join-Path $InstallRoot 'vscode-data'))
    $start=[Diagnostics.ProcessStartInfo]::new()
    $start.FileName=[string]$chain.codeExecutable
    $start.WorkingDirectory=$workingDirectory
    $start.UseShellExecute=$false
    foreach($arg in (Get-ShadowVsCodeLaunchArguments -InstallRoot $InstallRoot -OpenPath $openPath)){
        [void]$start.ArgumentList.Add($arg)
    }
    foreach($key in $environment.Keys){$start.Environment[$key]=[string]$environment[$key]}
    # GUI launch must not inherit Electron's CLI-only switch from a parent terminal.
    foreach($key in @($start.Environment.Keys)){
        if($key -match '^(VSCODE|ELECTRON)_'){[void]$start.Environment.Remove($key)}
    }
    $process=[Diagnostics.Process]::Start($start)
    $process.Dispose()
    if($startIndex -and $ProjectPath -and $chain.modelMode -eq 'Dual' -and $embedding.Status -ceq 'Ready'){
        Write-ShadowMessage 'Indexing: enable it in Kilo for this project; first exclude sensitive files in .gitignore or .kilocodeignore. Wait for Complete status.'
    }
    if(-not $startIndex){Write-ShadowMessage "Indexing is off for this launch (provisioned mode: $indexingMode). File search, subagents and tests remain available."}
    Write-ShadowMessage 'VS Code started with the local profile. After configuration changes, fully close existing windows of this profile and restart.' 'OK'
} catch {
    Write-Error -Message $_.Exception.Message -ErrorAction Continue
    if($PauseOnError){
        try { $null=Read-Host 'Press Enter to close' } catch {}
    }
    exit 1
}
