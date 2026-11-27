#requires -Version 7.4
[CmdletBinding()]
param([string]$SourceRoot=(Split-Path -Parent $PSScriptRoot))
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $SourceRoot 'Common.ps1')
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $SourceRoot 'Setup.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Setup parser errors'}
$main=@($ast.EndBlock.Statements|Where-Object {$_ -is [Management.Automation.Language.TryStatementAst]})[0]
$statements=@($main.Body.Statements)
$start=-1
for($i=0;$i -lt $statements.Count;$i++){if($statements[$i].Extent.Text -match '^if \(\$ModelAction -eq ''Keep''\)'){$start=$i;break}}
if($start -lt 0){throw 'Setup selection entry missing'}
$body=@($statements[$start..($statements.Count-1)]|ForEach-Object {$_.Extent.Text}) -join "`n"
$root=Join-Path ([IO.Path]::GetTempPath()) ('shadow-selection-integration-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
try{
    $runtimeFile=(Join-Path $SourceRoot 'Runtime.ps1').Replace("'","''")
    $selectionFile=(Join-Path $SourceRoot 'ModelSelection.ps1').Replace("'","''")
    $indexingFile=(Join-Path $SourceRoot 'Indexing.ps1').Replace("'","''")
    $poolFile=(Join-Path $SourceRoot 'ModelPool.ps1').Replace("'","''")
    $commonFile=(Join-Path $SourceRoot 'Common.ps1').Replace("'","''")
    $harness=@'
param($InstallRoot,$Scenario,$IndexingMode='Automatic')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$ModelAction='Configure'
$report=[ordered]@{schema=1;status='IN_PROGRESS';steps=@();warnings=@()}
$ModelMode='Dual';$PreferredModel='Auto';$ModelKey='';$IncludeFastModel=$true;$AllowPartialGpuOffload=$true;$AllowUnfitAttempt=$false
$SkipModelDownload=$false;$ContextLength=32768;$Port=1234;$RouterPort=1235;$ApiTokenEnvironmentVariable='';$studio='fixture'
$ProjectPath=@();$NoShortcut=$true;$node='node-fixture';$toolchain=@{powerShellExecutable='pwsh-fixture'}
$kilo=@{kiloExecutable='cli-fixture';kiloArgumentPrefix=@()};$bundledKilo='gui-fixture'
$RunAcceptanceTest=$true;$SkipAcceptanceTest=$false
$WorkspaceTrust=$false;$UseRecommendedModelsBasedOnGPU=$Scenario -eq 'recommended'
# Synthetic acceptance boundary: this suite proves model-selection propagation only.
function Select-ShadowAcceptanceMode {param($RunAcceptanceTest,$SkipAcceptanceTest) return 'Run'}
function Invoke-ShadowToolchainAcceptance {param($InstallRoot) return @{status='PASS'}}
function Install-ShadowDesktopRunner {param($InstallRoot,$PowerShellPath) return (Join-Path $InstallRoot 'synthetic-desktop-runner.exe')}
$script:selectionPrompt=0
function Read-Host {param($Prompt) if($UseRecommendedModelsBasedOnGPU){throw 'Unexpected automatic-model prompt'};if($Prompt -like '*Confirm*'){return 'y'};$script:selectionPrompt++;if($script:selectionPrompt -eq 1){return '3'};return ''}
'@
    $harness+="`n. '$commonFile'`n. '$runtimeFile'`n. '$selectionFile'`n. '$poolFile'`n. '$indexingFile'`n"
    $harness+=@'
if($Scenario -like 'keep-*'){
    $ModelAction='Keep'
    $ModelMode=if ($Scenario -eq 'keep-single') {'Single'} else {'Dual'}
}
function Resolve-ShadowSetupLms {param($StudioPath) if ($ModelAction -eq 'Keep'){throw 'Keep contacted LM Studio'}; return 'fixture'}
function Reset-ShadowSetupLoadedModels {param($InstallRoot,$LmsPath,$Port,$ApiTokenEnvironmentVariable) if($ModelAction -ne 'Configure'){throw 'Keep must not reset models'};[IO.File]::AppendAllText((Join-Path $InstallRoot 'reset-seen'),"reset`n");return @{status='PASS';port=1234}}
function Get-LocalNvidiaGpu {param($LogDirectory) if(-not(Test-Path -LiteralPath (Join-Path $InstallRoot 'reset-seen'))){throw 'Models must be unloaded before recommendation hardware measurement'};return [pscustomobject]@{Gpu=[pscustomobject]@{FreeBytes=19GB};FreeRamBytes=21.6GB}}
function Get-LrDownloadedModels {param($LmsPath,$LogDirectory) return @()}
function Install-ShadowSelectedModels {param($Definitions,$LmsPath,$InstallRoot,[switch]$SkipModelDownload) [IO.File]::WriteAllText((Join-Path $InstallRoot 'install-seen'),($Definitions.Count.ToString()))}
function Configure-LocalModelPool {
    param($InstallRoot,$ContextLength,$Port,$RouterPort,[switch]$IncludeFastModel,[switch]$AllowPartialGpuOffload,[switch]$AllowUnfitAttempt,$SelectedDefinitions,$DownloadModel,$LmsPath,$ApiTokenEnvironmentVariable)
    [IO.File]::WriteAllText((Join-Path $InstallRoot 'pool-seen.json'),(@{roles=@($SelectedDefinitions|ForEach-Object {$_.Definition.Id});download=$DownloadModel;offload=[bool]$AllowPartialGpuOffload}|ConvertTo-Json))
    if($Scenario -ne 'warning'){throw 'SYNTHETIC_POOL_REACHED'}
    return [pscustomobject]@{
        Status='Ready';VerificationStatus='Partial';PrimaryAlias='coder-high';BackendApiBaseUrl='http://127.0.0.1:1234/v1';ApiTokenEnvironmentVariable=''
        Profiles=@([pscustomobject]@{Alias='coder-high';VerificationState='Deferred';VerificationMessage='Synthetic insufficient memory';Estimate=$null;SmokeTests=@{Chat='NotRun'}})
    }
}
function Start-ShadowModelRouter {param($InstallRoot,$Pool,$NodePath,$PowerShellPath) return [pscustomobject]@{ApiBaseUrl='http://127.0.0.1:1235/v1'}}
function Initialize-ShadowEmbeddingModel {param($InstallRoot,$Pool,$Definition) [IO.File]::WriteAllText((Join-Path $InstallRoot 'embedding-called'),'yes');return [pscustomobject]@{Status='Deferred';InstanceId='shadow-fixture-embedding';Message='Synthetic insufficient RAM'}}
function Get-ShadowPoolCatalog {param($Pool) return @{}}
function New-ShadowAgentConfiguration {param($InstallRoot,$ModelCatalog,$MainModel,$ApiBaseUrl,$ApiTokenEnvironmentVariable,$EmbeddingModelId,$EmbeddingApiBaseUrl) return [pscustomobject]@{Config=@{}}}
function Assert-ShadowKiloEffectiveConfig {param($KiloExecutable,$KiloArgumentPrefix,$InstallRoot,$Config,$WorkingDirectory) return @{Verified=$true}}
function Assert-ShadowKiloWorkflowTools {param($KiloExecutable,$KiloArgumentPrefix,$InstallRoot,$Config,$WorkingDirectory) return @{Verified=$true}}
function Test-ShadowKiloSearch {param($InstallRoot,$KiloExecutable,$KiloArgumentPrefix,$ConfigJson)}
function Update-ShadowWorkspaces {param($Root,$ProjectPath,$PwshPath) return @{Entries=@();Warnings=@()}}
function New-ShadowWelcomeTestProject {param($InstallRoot) return @{project=(Join-Path $InstallRoot 'welcome/workflow-test')}}
function Get-ShadowStartCommands {param($PowerShellPath,$InstallRoot,$ProjectPaths) return 'synthetic-start-command'}
'@
    $reportModule=(Join-Path $SourceRoot 'ProvisionReport.ps1').Replace("'","''")
    $harness+="`n. '$reportModule'`nStart-ShadowProvisionReport -InstallRoot `$InstallRoot -Report `$report`ntry {`n"+$body+"`n} "+$main.CatchClauses[0].Extent.Text
    Copy-Item -LiteralPath (Join-Path $SourceRoot 'templates') -Destination (Join-Path $root 'templates') -Recurse
    $harnessPath=Join-Path $root 'harness.ps1'
    [IO.File]::WriteAllText($harnessPath,$harness)
    $result=Invoke-ShadowNative -FilePath (Get-Process -Id $PID).Path -ArgumentList @('-NoLogo','-NoProfile','-NonInteractive','-File',$harnessPath,'-InstallRoot',$root,'-Scenario','failure') -AllowFailure -Quiet -TimeoutSeconds 30
    if($result.ExitCode -ne 1 -or $result.StdErr -notmatch 'SYNTHETIC_POOL_REACHED'){throw "Setup did not reach pool after selection: $($result.StdErr)"}
    $selection=Get-Content -LiteralPath (Join-Path $root 'model-selection.json') -Raw|ConvertFrom-Json
    $passed=Get-Content -LiteralPath (Join-Path $root 'pool-seen.json') -Raw|ConvertFrom-Json
    if($selection.roles.Count -ne 4 -or $selection.roles[0].Alias -cne 'coder-high' -or
       $selection.roles[1].Alias -cne 'coder-fast' -or $selection.roles[0].Id -cne 'qwen35-9b' -or
       $passed.roles[0] -cne 'qwen35-9b' -or $passed.download -ne $false -or -not $passed.offload -or
       [IO.File]::ReadAllText((Join-Path $root 'install-seen')) -cne '5'){
        throw 'Confirmed choices were not saved or propagated into setup'
    }
    $automatic=Invoke-ShadowNative -FilePath (Get-Process -Id $PID).Path -ArgumentList @('-NoLogo','-NoProfile','-NonInteractive','-File',$harnessPath,'-InstallRoot',$root,'-Scenario','recommended') -AllowFailure -Quiet -TimeoutSeconds 30
    $autoSelection=Get-Content -LiteralPath (Join-Path $root 'model-selection.json') -Raw|ConvertFrom-Json
    if($automatic.ExitCode -ne 1 -or $automatic.StdErr -notmatch 'SYNTHETIC_POOL_REACHED' -or $autoSelection.selectionMode -cne 'automatic-gpu-ram-recommendations' -or $autoSelection.roles[0].Id -cne 'qwen3-14b'){throw "Automatic recommendations did not reach the actual pool boundary without prompts: $($automatic.StdErr)"}
    $warning=Invoke-ShadowNative -FilePath (Get-Process -Id $PID).Path -ArgumentList @('-NoLogo','-NoProfile','-NonInteractive','-File',$harnessPath,'-InstallRoot',$root,'-Scenario','warning') -AllowFailure -Quiet -TimeoutSeconds 30
    $report=Get-Content -LiteralPath (Join-Path $root 'provisioning-report.json') -Raw|ConvertFrom-Json
    if($warning.ExitCode -ne 0 -or $report.status -cne 'PROVISIONED_WITH_WARNINGS' -or
       @($report.warnings|Where-Object {$_ -match 'Synthetic insufficient memory'}).Count -ne 1 -or
       @($report.warnings|Where-Object {$_ -match 'Synthetic insufficient RAM'}).Count -ne 1){
        throw "Resource warnings blocked setup or were not recorded: $($warning.StdErr)"
    }
    $runtimeDir=Join-Path $root 'runtime'
    [void][IO.Directory]::CreateDirectory($runtimeDir)
    $savedOptions=Join-Path $root 'provisioning-options.json'
    $beforeOptions=[IO.File]::ReadAllText($savedOptions)
    $beforeReset=[IO.File]::ReadAllText((Join-Path $root 'reset-seen'))
    foreach ($variant in @('single','dual')) {
        $savedRuntime=if ($variant -eq 'single') {
            @{Status='Ready';ModelId='saved-model';ApiBaseUrl='http://127.0.0.1:1234/v1';ContextLength=8192;ApiTokenEnvironmentVariable=''}
        } else {
            @{Status='Ready';SchemaVersion=2;PrimaryAlias='coder';BackendApiBaseUrl='http://127.0.0.1:1234/v1';RouterApiBaseUrl='http://127.0.0.1:1235/v1';ApiTokenEnvironmentVariable=''
              Profiles=@(@{Alias='coder';InstanceId='coder-id';ContextLength=8192;ModelPath='a.gguf'},@{Alias='review';InstanceId='review-id';ContextLength=8192;ModelPath='b.gguf'})}
        }
        $file=Join-Path $runtimeDir $(if($variant -eq 'single'){'runtime-state.json'}else{'model-pool.json'})
        $savedJson=$savedRuntime|ConvertTo-Json -Depth 8
        [IO.File]::WriteAllText($file,$savedJson)
        $run=Invoke-ShadowNative -FilePath (Get-Process -Id $PID).Path -ArgumentList @('-NoProfile','-NonInteractive','-File',$harnessPath,'-InstallRoot',$root,'-Scenario',"keep-$variant",'-IndexingMode','Off') -AllowFailure -Quiet
        if($run.ExitCode){throw "Keep $variant failed: $($run.StdErr)"}
        $report=Get-Content -LiteralPath (Join-Path $root 'provisioning-report.json') -Raw|ConvertFrom-Json
        if($report.smokeTests -cne 'NotRun' -or $report.status -ne 'PROVISIONED' -or [IO.File]::ReadAllText($file) -cne $savedJson -or [IO.File]::ReadAllText($savedOptions) -cne $beforeOptions -or [IO.File]::ReadAllText((Join-Path $root 'reset-seen')) -cne $beforeReset){throw "Keep changed or verified $variant models"}
        [IO.File]::Delete($file)
    }
    foreach($mode in @('Off','OnDemand')){
        Remove-Item -LiteralPath (Join-Path $root 'embedding-called') -ErrorAction SilentlyContinue
        $optional=Invoke-ShadowNative -FilePath (Get-Process -Id $PID).Path -ArgumentList @('-NoLogo','-NoProfile','-NonInteractive','-File',$harnessPath,'-InstallRoot',$root,'-Scenario','warning','-IndexingMode',$mode) -AllowFailure -Quiet -TimeoutSeconds 30
        if($optional.ExitCode -ne 0){throw "Optional setup failed: $($optional.StdErr)"}
        $report=Get-Content -LiteralPath (Join-Path $root 'provisioning-report.json') -Raw|ConvertFrom-Json
        $desired=Get-Content -LiteralPath (Join-Path $root 'provisioning-options.json') -Raw|ConvertFrom-Json
        $expectedCount=if($mode -ceq 'Off'){'4'}else{'5'}
        if((Test-Path -LiteralPath (Join-Path $root 'embedding-called')) -or $desired.IndexingMode -cne $mode -or
           [IO.File]::ReadAllText((Join-Path $root 'install-seen')) -cne $expectedCount -or $report.indexingMode -cne $mode){throw "Optional indexing policy was not propagated: $mode"}
    }
    [pscustomobject]@{suite='Selection setup integration';passed=$true;checks=6}|ConvertTo-Json
}finally{Remove-Item -LiteralPath $root -Recurse -Force}
