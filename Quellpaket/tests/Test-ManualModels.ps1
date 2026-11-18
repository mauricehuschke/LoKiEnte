#requires -Version 7.4
[CmdletBinding()]
param([string]$SourceRoot=(Split-Path -Parent $PSScriptRoot))
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $SourceRoot 'Common.ps1')
. (Join-Path $SourceRoot 'Runtime.ps1')
. (Join-Path $SourceRoot 'ModelPool.ps1')
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $SourceRoot 'Setup.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Setup syntax errors'}
$helper=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq 'Assert-ShadowSetupModels'},$false)
if($null -eq $helper){throw 'Manual model guard missing'}
. ([scriptblock]::Create($helper.Extent.Text))
$count=0
function Assert-Models([bool]$Condition,[string]$Description){
    if(-not $Condition){throw "FAIL: $Description"}
    $script:count++
}
$hardware=[pscustomobject]@{Gpu=[pscustomobject]@{Name='Synthetic';TotalBytes=20GB;FreeBytes=19GB};TotalRamBytes=28GB;FreeRamBytes=24GB}
$profiles=@(Get-SmpModelDefinitions -Hardware $hardware -IncludeFastModel)
$script:available=@()
function Get-LocalNvidiaGpu {param($LogDirectory) return $hardware}
function Get-LrDownloadedModels {param($LmsPath,$LogDirectory) return $script:available}
function Invoke-LrNative {throw 'Unexpected model CLI action during precheck'}
function Stop-ShadowModelRouter {throw 'Unexpected router action during precheck'}
function Get-ManualFailure {
    param([string]$Mode='Dual',[string]$Preferred='Auto',[string]$Key='', [switch]$Fast)
    try{
        Assert-ShadowSetupModels -LmsPath 'C:\fixture\lms.exe' -InstallRoot 'C:\fixture' -ModelMode $Mode -PreferredModel $Preferred -ModelKey $Key -IncludeFastModel:$Fast
        return ''
    }catch{return $_.Exception.Message}
}
$message=Get-ManualFailure -Fast
Assert-Models ($message -match 'MANUELLE AKTION ERFORDERLICH' -and $message -match 'denselben Parametern\s+erneut starten' -and $message -match 'nicht automatisch') 'All missing models stop with manual restart instructions'
$formatted=$message -replace "`r`n","`n"
Assert-Models ($formatted -match '(?m)^  1\. \[coder-high\] .+$' -and $formatted -match '(?m)^  2\. \[coder-fast\] .+$' -and
    $formatted -match '(?m)^  3\. \[review\] .+$' -and $formatted -match '(?m)^  4\. \[fast\] .+$' -and
    ([regex]::Matches($formatted,'(?m)^     Datei:  .+$')).Count -eq 4 -and
    ([regex]::Matches($formatted,'(?m)^     Quelle:$')).Count -eq 4 -and $formatted -match '(?m)^Naechste Schritte:$') 'Manual-action formatter separates model names, paths, URLs and next steps'
foreach($item in $profiles){
    Assert-Models ($message.Contains($item.Definition.ExpectedPath) -and $message.Contains($item.Definition.DownloadUrl)) "Exact filename and URL appear for $($item.Alias)"
}
$message=Get-ManualFailure
Assert-Models ($message -notmatch '\[fast\]') 'Optional fast role is not requested unless enabled'
$script:available=@([pscustomobject]@{path=$profiles[0].Definition.ExpectedPath;modelKey='coder-key'})
$message=Get-ManualFailure -Fast
Assert-Models (-not $message.Contains($profiles[0].Definition.ExpectedPath) -and $message.Contains($profiles[1].Definition.ExpectedPath) -and
    $message.Contains($profiles[2].Definition.ExpectedPath)) 'Only missing exact models are listed'
$script:available=@($profiles|ForEach-Object {[pscustomobject]@{path=$_.Definition.ExpectedPath;modelKey=$_.Alias+'-key'}}|Sort-Object -Property path -Unique)
Assert-Models ((Get-ManualFailure -Fast) -ceq '') 'All existing exact local models continue without download'
$script:available=@()
$message=Get-ManualFailure -Mode Single -Preferred GptOss20B
Assert-Models ($message.Contains($profiles[2].Definition.ExpectedPath) -and -not $message.Contains($profiles[0].Definition.ExpectedPath)) 'Single mode requests only the chosen profile'
$message=Get-ManualFailure -Mode Single -Key 'my/custom-model'
Assert-Models ($message.Contains('my/custom-model') -and $message -match 'lms ls --json') 'Missing custom key is explained without inventing a model URL'
$script:available=@([pscustomobject]@{path='custom/path';modelKey='my/custom-model'})
Assert-Models ((Get-ManualFailure -Mode Single -Key 'my/custom-model') -ceq '') 'Existing custom key continues'
$script:available=@([pscustomobject]@{path='one';modelKey='my/custom-model'},[pscustomobject]@{path='two';modelKey='my/custom-model'})
Assert-Models ((Get-ManualFailure -Mode Single -Key 'my/custom-model') -match 'Mehrere exakt') 'Ambiguous models remain explicit errors'
$main=@($ast.EndBlock.Statements|Where-Object {$_ -is [Management.Automation.Language.TryStatementAst]})[0]
$statements=@($main.Body.Statements)
$start=-1
for($i=0;$i -lt $statements.Count;$i++){
    if($statements[$i].Extent.Text -match '^\$lms=Resolve-ShadowSetupLms'){$start=$i;break}
}
if($start -lt 0){throw 'Setup LM Studio entry missing'}
$body=@($statements[$start..($statements.Count-1)]|ForEach-Object {$_.Extent.Text}) -join "`n"
Assert-Models ($body.IndexOf('Assert-ShadowSetupModels') -lt $body.IndexOf('Stop-ShadowModelRouter') -and
    ([regex]::Matches($body,'-DownloadModel:\$false')).Count -eq 2) 'Actual setup checks all models before router stop and disables both automatic download paths'
$root=Join-Path ([IO.Path]::GetTempPath()) ('shadow-manual-models-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory((Join-Path $root 'runtime'))
try{
    [IO.File]::WriteAllText((Join-Path $root 'runtime\model-pool.json'),'{}')
    $runtimeFile=(Join-Path $SourceRoot 'Runtime.ps1').Replace("'","''")
    $poolFile=(Join-Path $SourceRoot 'ModelPool.ps1').Replace("'","''")
    $harness=@'
param($InstallRoot,$Scenario='manual')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$report=[ordered]@{schema=1;status='IN_PROGRESS'}
$ModelMode='Single';$PreferredModel='Auto';$ModelKey='my/custom-model';$IncludeFastModel=$false;$studio='C:\LM Studio.exe'
'@
    $harness+="`n. '$runtimeFile'`n. '$poolFile'`n"
    $harness+=@'
function Resolve-ShadowSetupLms {param($StudioPath) return 'C:\lms.exe'}
function Get-LocalNvidiaGpu {param($LogDirectory) return [pscustomobject]@{Gpu=[pscustomobject]@{TotalBytes=20GB};TotalRamBytes=28GB}}
function Get-LrDownloadedModels {param($LmsPath,$LogDirectory) if($Scenario -eq 'error'){throw 'Synthetic model-list failure'};return @()}
function Stop-ShadowModelRouter {[IO.File]::WriteAllText((Join-Path $InstallRoot 'unexpected'),'router');throw 'Unexpected router stop'}
function Configure-LocalModelPool {[IO.File]::WriteAllText((Join-Path $InstallRoot 'unexpected'),'pool');throw 'Unexpected pool action'}
function Write-ShadowManagedFile {param($Path,$Content,$BackupRoot) [IO.File]::WriteAllText($Path,$Content);return $true}
'@
    $harness+="`n"+$helper.Extent.Text+"`ntry {`n"+$body+"`n} "+$main.CatchClauses[0].Extent.Text
    $harnessPath=Join-Path $root 'harness.ps1'
    [IO.File]::WriteAllText($harnessPath,$harness)
    $result=Invoke-ShadowNative -FilePath (Get-Process -Id $PID).Path -ArgumentList @('-NoLogo','-NoProfile','-NonInteractive','-File',$harnessPath,'-InstallRoot',$root) -AllowFailure -Quiet -TimeoutSeconds 30
    Assert-Models ($result.ExitCode -eq 1 -and $result.StdOut -match 'MANUELLE AKTION ERFORDERLICH' -and
        [string]::IsNullOrWhiteSpace($result.StdErr)) 'Actual setup displays manual action on stdout, not the red error stream, and exits nonzero'
    Assert-Models ($result.StdOut -match 'my/custom-model' -and $result.StdOut -notmatch 'Write-Error|Invoke-SetupRequest') 'Explicit missing custom model remains a readable manual action'
    $report=Get-Content -LiteralPath (Join-Path $root 'provisioning-report.json') -Raw|ConvertFrom-Json
    Assert-Models ($report.status -ceq 'INCOMPLETE' -and $report.manualAction -ceq 'MODEL_DOWNLOAD' -and
        $report.error -match 'my/custom-model') 'Actual failure report preserves the missing custom model'
    Assert-Models (-not(Test-Path -LiteralPath (Join-Path $root 'unexpected'))) 'No router stop or model action occurs before manual step'
    $failure=Invoke-ShadowNative -FilePath (Get-Process -Id $PID).Path -ArgumentList @('-NoLogo','-NoProfile','-NonInteractive','-File',$harnessPath,'-InstallRoot',$root,'-Scenario','error') -AllowFailure -Quiet -TimeoutSeconds 30
    Assert-Models ($failure.ExitCode -eq 1 -and $failure.StdErr -match 'Synthetic model-list failure' -and
        $failure.StdOut -notmatch 'MANUELLE AKTION ERFORDERLICH') 'Real errors remain on stderr and are not disguised as manual actions'
    [pscustomobject]@{suite='Manual model downloads';passed=$true;checks=$count}|ConvertTo-Json
}finally{Remove-Item -LiteralPath $root -Recurse -Force}
