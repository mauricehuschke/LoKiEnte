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
for($i=0;$i -lt $statements.Count;$i++){if($statements[$i].Extent.Text -match '^\$lms=Resolve-ShadowSetupLms'){$start=$i;break}}
if($start -lt 0){throw 'Setup selection entry missing'}
$body=@($statements[$start..($statements.Count-1)]|ForEach-Object {$_.Extent.Text}) -join "`n"
$root=Join-Path ([IO.Path]::GetTempPath()) ('shadow-selection-integration-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
try{
    $runtimeFile=(Join-Path $SourceRoot 'Runtime.ps1').Replace("'","''")
    $selectionFile=(Join-Path $SourceRoot 'ModelSelection.ps1').Replace("'","''")
    $commonFile=(Join-Path $SourceRoot 'Common.ps1').Replace("'","''")
    $harness=@'
param($InstallRoot,$Scenario)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$report=[ordered]@{schema=1;status='IN_PROGRESS';steps=@();warnings=@()}
$ModelMode='Dual';$PreferredModel='Auto';$ModelKey='';$IncludeFastModel=$true;$AllowPartialGpuOffload=$true;$AllowUnfitAttempt=$false
$SkipModelDownload=$false;$ContextLength=32768;$Port=1234;$RouterPort=1235;$ApiTokenEnvironmentVariable='';$studio='fixture'
$ProjectPath=@();$NoShortcut=$true;$node='node-fixture';$toolchain=@{powerShellExecutable='pwsh-fixture'}
$kilo=@{kiloExecutable='cli-fixture';kiloArgumentPrefix=@()};$bundledKilo='gui-fixture'
$script:selectionPrompt=0
function Read-Host {param($Prompt) if($Prompt -like '*Confirm*'){return 'y'};$script:selectionPrompt++;if($script:selectionPrompt -eq 1){return '3'};return ''}
'@
    $harness+="`n. '$commonFile'`n. '$runtimeFile'`n. '$selectionFile'`n"
    $harness+=@'
function Resolve-ShadowSetupLms {param($StudioPath) return 'fixture'}
function Get-LocalNvidiaGpu {param($LogDirectory) return [pscustomobject]@{Gpu=[pscustomobject]@{FreeBytes=19GB};FreeRamBytes=21.6GB}}
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
function Initialize-ShadowEmbeddingModel {param($InstallRoot,$Pool,$Definition) return [pscustomobject]@{Status='Deferred';InstanceId='shadow-fixture-embedding';Message='Synthetic insufficient RAM'}}
function Get-ShadowPoolCatalog {param($Pool) return @{}}
function New-ShadowAgentConfiguration {param($InstallRoot,$ModelCatalog,$MainModel,$ApiBaseUrl,$ApiTokenEnvironmentVariable,$EmbeddingModelId,$EmbeddingApiBaseUrl) return [pscustomobject]@{Config=@{}}}
function Assert-ShadowKiloEffectiveConfig {param($KiloExecutable,$KiloArgumentPrefix,$InstallRoot,$Config,$WorkingDirectory) return @{Verified=$true}}
function Assert-ShadowKiloWorkflowTools {param($KiloExecutable,$KiloArgumentPrefix,$InstallRoot,$Config,$WorkingDirectory) return @{Verified=$true}}
function Test-ShadowKiloSearch {param($InstallRoot,$KiloExecutable,$KiloArgumentPrefix,$ConfigJson)}
function Update-ShadowWorkspaces {param($Root,$ProjectPath,$PwshPath) return @{Entries=@();Warnings=@()}}
function New-ShadowWelcomeTestProject {param($InstallRoot) return @{project=(Join-Path $InstallRoot 'welcome/workflow-test')}}
function Get-ShadowStartCommands {param($PowerShellPath,$InstallRoot,$ProjectPaths) return 'synthetic-start-command'}
'@
    $harness+="`ntry {`n"+$body+"`n} "+$main.CatchClauses[0].Extent.Text
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
    $warning=Invoke-ShadowNative -FilePath (Get-Process -Id $PID).Path -ArgumentList @('-NoLogo','-NoProfile','-NonInteractive','-File',$harnessPath,'-InstallRoot',$root,'-Scenario','warning') -AllowFailure -Quiet -TimeoutSeconds 30
    $report=Get-Content -LiteralPath (Join-Path $root 'provisioning-report.json') -Raw|ConvertFrom-Json
    if($warning.ExitCode -ne 0 -or $report.status -cne 'PROVISIONED_WITH_WARNINGS' -or
       @($report.warnings|Where-Object {$_ -match 'Synthetic insufficient memory'}).Count -ne 1 -or
       @($report.warnings|Where-Object {$_ -match 'Synthetic insufficient RAM'}).Count -ne 1){
        throw "Resource warnings blocked setup or were not recorded: $($warning.StdErr)"
    }
    [pscustomobject]@{suite='Selection setup integration';passed=$true;checks=3}|ConvertTo-Json
}finally{Remove-Item -LiteralPath $root -Recurse -Force}
