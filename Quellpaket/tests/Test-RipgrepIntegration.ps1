#requires -Version 7.4
[CmdletBinding()]
param([string]$SourceRoot=(Split-Path -Parent $PSScriptRoot))
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $SourceRoot 'Common.ps1')
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $SourceRoot 'Setup.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Setup syntax errors'}
$startCommand=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq 'Get-ShadowStartCommands'},$false)
$main=@($ast.EndBlock.Statements|Where-Object {$_ -is [Management.Automation.Language.TryStatementAst]})[0]
$statements=@($main.Body.Statements)
$start=-1
for($i=0;$i -lt $statements.Count;$i++){
    if($statements[$i].Extent.Text -match '^\$report\.effectiveConfiguration='){$start=$i;break}
}
if($start -lt 0 -or $null -eq $startCommand){throw 'Setup verification section missing'}
$body=@($statements[$start..($statements.Count-1)]|ForEach-Object {$_.Extent.Text}) -join "`n"
$root=Join-Path ([IO.Path]::GetTempPath()) ('shadow-ripgrep-setup-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
try{
    $harness=@'
param($InstallRoot,$Scenario)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$report=[ordered]@{schema=1;status='IN_PROGRESS';steps=@();warnings=@()}
$configuration=[pscustomobject]@{Config=@{}}
$kilo=@{kiloExecutable='cli-fixture';kiloArgumentPrefix=@('entry-fixture')}
$bundledKilo='gui-fixture';$toolchain=@{powerShellExecutable='pwsh-fixture'}
$ModelAction='Configure';$ModelMode='Dual';$pool=[pscustomobject]@{VerificationStatus='Verified';Profiles=@()};$embedding=[pscustomobject]@{Status='Ready'}
if($Scenario -eq 'deferred'){$pool.VerificationStatus='Partial';$embedding.Status='Deferred';$report.warnings=@('Synthetic unverified model')}
if($Scenario -eq 'single-deferred'){$ModelMode='Single';$runtime=[pscustomobject]@{Status='Deferred';Estimate=$null};$report.warnings=@('Synthetic unverified model')}
if($Scenario -eq 'reserve'){$pool.Profiles=@([pscustomobject]@{Estimate=[pscustomobject]@{ReserveOverride=$true}});$report.warnings=@('Synthetic reserve override')}
$ProjectPath=@();$NoShortcut=$true
$RunAcceptanceTest=$true;$SkipAcceptanceTest=$false
$WorkspaceTrust=$false
# This suite isolates the search/setup gate. Live acceptance is tested separately.
function Select-ShadowAcceptanceMode {param($RunAcceptanceTest,$SkipAcceptanceTest) return 'Run'}
function Invoke-ShadowToolchainAcceptance {param($InstallRoot) return @{status='PASS'}}
function Write-ShadowToolchainEvent {param($Component,$Level,$Message)}
function Install-ShadowDesktopRunner {param($InstallRoot,$PowerShellPath) return (Join-Path $InstallRoot 'synthetic-desktop-runner.exe')}
$IndexingMode='Off';$IncludeFastModel=$false;$AllowPartialGpuOffload=$false;$AllowUnfitAttempt=$false
$RouterPort=1235;$Port=1234;$ContextLength=32768;$PreferredModel='Auto';$ModelKey='';$ApiTokenEnvironmentVariable=''
function Get-LrProperty {param($Object,$Name,$Default=$null) if($null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name]){return $Object.$Name};return $Default}
function Update-ShadowWorkspaces {param($Root,$ProjectPath,$PwshPath) return @{Entries=@();Warnings=@()}}
function Assert-ShadowKiloEffectiveConfig {param($KiloExecutable,$KiloArgumentPrefix,$InstallRoot,$Config,$WorkingDirectory) return @{Verified=$true}}
function Assert-ShadowKiloWorkflowTools {param($KiloExecutable,$KiloArgumentPrefix,$InstallRoot,$Config,$WorkingDirectory) return @{Verified=$true}}
function New-ShadowWelcomeTestProject {param($InstallRoot) return @{project=(Join-Path $InstallRoot 'welcome/workflow-test')}}
function Test-ShadowKiloSearch {
    param($InstallRoot,$KiloExecutable,$KiloArgumentPrefix,$ConfigJson)
    [IO.File]::AppendAllText((Join-Path $InstallRoot 'search-tests.txt'),$KiloExecutable+[Environment]::NewLine)
    if($Scenario -eq 'failure' -and $KiloExecutable -eq 'gui-fixture'){throw 'SYNTHETIC_SEARCH_FAILURE'}
}
function Write-ShadowManagedFile {param($Path,$Content,$BackupRoot) [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path));[IO.File]::WriteAllText($Path,$Content);return $true}
function Write-ShadowMessage {param($Message,$Level) Write-Host $Message}
'@
    $reportModule=(Join-Path $SourceRoot 'ProvisionReport.ps1').Replace("'","''")
    $harness+="`n. '$reportModule'`nStart-ShadowProvisionReport -InstallRoot `$InstallRoot -Report `$report`n"+$startCommand.Extent.Text+"`ntry {`n"+$body+"`n} "+$main.CatchClauses[0].Extent.Text
    Copy-Item -LiteralPath (Join-Path $SourceRoot 'templates') -Destination (Join-Path $root 'templates') -Recurse
    $harnessPath=Join-Path $root 'harness.ps1'
    [IO.File]::WriteAllText($harnessPath,$harness)
    foreach($scenario in @('success','deferred','single-deferred','reserve','failure')){
        $install=Join-Path $root $scenario
        [void][IO.Directory]::CreateDirectory($install)
        $result=Invoke-ShadowNative -FilePath (Get-Process -Id $PID).Path -ArgumentList @('-NoLogo','-NoProfile','-NonInteractive','-File',$harnessPath,'-InstallRoot',$install,'-Scenario',$scenario) -AllowFailure -Quiet -TimeoutSeconds 30
        $report=Get-Content -LiteralPath (Join-Path $install 'provisioning-report.json') -Raw|ConvertFrom-Json
        $calls=@(Get-Content -LiteralPath (Join-Path $install 'search-tests.txt'))
        if($calls.Count -ne 2 -or $calls[0] -cne 'cli-fixture' -or $calls[1] -cne 'gui-fixture'){throw 'Setup did not test both Kilo entry points'}
        if($scenario -eq 'success' -and ($result.ExitCode -ne 0 -or $report.status -cne 'PROVISIONED' -or
            $report.steps -notcontains 'File search verified in Kilo CLI and VS Code extension')){throw 'Successful search was not included in the provisioning report'}
        if($scenario -in @('deferred','single-deferred') -and ($result.ExitCode -ne 0 -or $report.status -cne 'PROVISIONED_WITH_WARNINGS' -or
            $report.warnings -notcontains 'Synthetic unverified model')){throw 'Deferred models should complete provisioning with an explicit warning'}
        if($scenario -eq 'reserve' -and ($result.ExitCode -ne 0 -or $report.status -cne 'PROVISIONED_WITH_WARNINGS' -or
            $report.warnings -notcontains 'Synthetic reserve override')){throw 'A successful load without reserve should still produce a warning'}
        if($scenario -eq 'failure' -and ($result.ExitCode -ne 1 -or $report.status -cne 'INCOMPLETE' -or
            $report.error -notmatch 'SYNTHETIC_SEARCH_FAILURE')){throw 'Failed search was incorrectly reported as provisioned'}
    }
    [pscustomobject]@{suite='Ripgrep setup gate';passed=$true;checks=7}|ConvertTo-Json
}finally{Remove-Item -LiteralPath $root -Recurse -Force}
