#requires -Version 7.4
[CmdletBinding()]
param([string]$SourceRoot=(Split-Path -Parent $PSScriptRoot))
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $SourceRoot 'Common.ps1')
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $SourceRoot 'Setup.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Setup syntax errors'}
$helper=$ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Resolve-ShadowSetupLms'},$false)
if($null -eq $helper){throw 'Manual initialization guard missing'}
. ([scriptblock]::Create($helper.Extent.Text))
function Start-Process {throw 'Unexpected automatic app start'}
function Start-Sleep {throw 'Unexpected polling'}
function Resolve-LocalLmsCommand {return 'C:\Synthetic\lms.exe'}
if((Resolve-ShadowSetupLms -StudioPath 'C:\LM Studio\LM Studio.exe') -cne 'C:\Synthetic\lms.exe'){throw 'Existing CLI was not reused'}
$count=1
foreach($case in @('missing','empty','broken-home')){
    $script:case=$case
    function Resolve-LocalLmsCommand {
        if($script:case -eq 'empty'){return $null}
        throw "Synthetic $script:case"
    }
    $failure=$null
    try{$null=Resolve-ShadowSetupLms -StudioPath 'C:\LM Studio\LM Studio.exe'}catch{$failure=$_.Exception.Message}
    if(-not $failure -or $failure -notmatch 'MANUAL ACTION REQUIRED' -or
       $failure -notmatch 'first-run dialogs' -or $failure -notmatch 'same parameters' -or
       $failure -notmatch 'will not resume automatically'){throw "Missing restart instructions for $case"}
    if($case -ne 'empty' -and $failure -notmatch [regex]::Escape("Synthetic $case")){throw 'Underlying resolution error was hidden'}
    $count++
}
$root=Join-Path ([IO.Path]::GetTempPath()) ('shadow-lm-init-test-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory((Join-Path $root 'runtime'))
try{
    [IO.File]::WriteAllText((Join-Path $root 'runtime\model-pool.json'),'{}')
    $main=@($ast.EndBlock.Statements|Where-Object {$_ -is [Management.Automation.Language.TryStatementAst]})[0]
    $statements=@($main.Body.Statements)
    $start=-1
    for($i=0;$i -lt $statements.Count;$i++){
        if($statements[$i].Extent.Text -match '^if \(\$ModelAction -eq ''Keep''\)'){$start=$i;break}
    }
    if($start -lt 0){throw 'Actual setup does not use the manual initialization guard'}
    $harness=@'
param($InstallRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$ModelAction='Configure'
$report=[ordered]@{schema=1;status='IN_PROGRESS'}
$studio='C:\Synthetic\LM Studio.exe'
function Resolve-LocalLmsCommand {throw 'Synthetic CLI missing'}
function Start-Process {[IO.File]::WriteAllText((Join-Path $InstallRoot 'unexpected'),'app');throw 'Unexpected app launch'}
function Start-Sleep {[IO.File]::WriteAllText((Join-Path $InstallRoot 'unexpected'),'wait');throw 'Unexpected wait'}
function Stop-ShadowModelRouter {[IO.File]::WriteAllText((Join-Path $InstallRoot 'unexpected'),'router');throw 'Unexpected router action'}
function Configure-LocalModelPool {[IO.File]::WriteAllText((Join-Path $InstallRoot 'unexpected'),'model');throw 'Unexpected model action'}
function Write-ShadowManagedFile {param($Path,$Content,$BackupRoot) [IO.File]::WriteAllText($Path,$Content);return $true}
'@
    $body=@($statements[$start..($statements.Count-1)]|ForEach-Object {$_.Extent.Text}) -join "`n"
    $harness+="`n"+$helper.Extent.Text+"`ntry {`n"+$body+"`n} "+$main.CatchClauses[0].Extent.Text
    $harnessPath=Join-Path $root 'harness.ps1'
    [IO.File]::WriteAllText($harnessPath,$harness)
    $result=Invoke-ShadowNative -FilePath (Get-Process -Id $PID).Path -ArgumentList @('-NoLogo','-NoProfile','-NonInteractive','-File',$harnessPath,'-InstallRoot',$root) -AllowFailure -Quiet -TimeoutSeconds 30
    if($result.ExitCode -ne 1){throw 'Setup did not exit with incomplete status'}
    $report=Get-Content -LiteralPath (Join-Path $root 'provisioning-report.json') -Raw|ConvertFrom-Json
    if($report.status -cne 'INCOMPLETE' -or $report.error -notmatch 'MANUAL ACTION REQUIRED'){throw 'Manual action was not persisted in the actual setup failure report'}
    if($result.StdOut -notmatch 'MANUAL ACTION REQUIRED' -or -not [string]::IsNullOrWhiteSpace($result.StdErr) -or
       $report.manualAction -cne 'LM_STUDIO_INITIALIZATION'){throw 'Manual action instructions were not displayed clearly on stdout'}
    if(Test-Path -LiteralPath (Join-Path $root 'unexpected')){throw 'Setup continued after the manual action guard'}
    $count+=4
    [pscustomobject]@{suite='LM Studio manual initialization';passed=$true;checks=$count}|ConvertTo-Json
}finally{Remove-Item -LiteralPath $root -Recurse -Force}
