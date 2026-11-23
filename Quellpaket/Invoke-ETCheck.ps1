#requires -Version 7.4
[CmdletBinding()]
param([Parameter(Mandatory)][string]$ProjectPath,[string]$InstallRoot=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
if(-not (Test-Path -LiteralPath (Join-Path $env:ProgramData 'LoKiEnte-ET/challenge.json'))){throw 'Run E.T. inside the guest launched by the offline profile.'}
$chain=Get-Content -LiteralPath (Join-Path $InstallRoot 'toolchain.json') -Raw | ConvertFrom-Json
$env:LOKIENTE_ET_PROJECT=(Get-Item -LiteralPath $ProjectPath -ErrorAction Stop).FullName
$reportDir=Join-Path $InstallRoot 'runtime/security-tests'
[void][IO.Directory]::CreateDirectory($reportDir)
$report=Join-Path $reportDir ([guid]::NewGuid().ToString('D')+'.xml')
& $chain.nodeExecutable (Join-Path $PSScriptRoot 'Run-ProjectCheck.mjs') --framework node --project (Join-Path $PSScriptRoot 'security-probe') --file et.test.cjs --report $report
$code=$LASTEXITCODE
if(-not [IO.File]::Exists($report)){throw "E.T. runner returned $code without a report."}
$xml=[xml][IO.File]::ReadAllText($report)
$cases=@($xml.SelectNodes('//testcase'))
$expected=@('External IPv4/IPv6 blocked; guest loopback works','Host-confirmed marker cannot be opened by a project test','Guest project allows a temporary test file','Managed LM Studio model generates tokens inside this guest','GPU compute observed on a local inference worker during generation')
foreach($name in $expected){
    if(-not @($cases | Where-Object {$_.GetAttribute('name') -ceq $name}).Count){Write-Output "UNVERIFIED  $name";$code=1}
}
foreach($case in $cases){
    $failure=$case.SelectSingleNode('failure|error')
    if($failure){ $code=1; Write-Output ("FAIL  "+$case.name+"  "+$failure.InnerText) }
    elseif($case.SelectSingleNode('skipped')){$code=1;Write-Output ("SKIP  "+$case.name)}
    else{Write-Output ("PASS  "+$case.name)}
}
Write-Output "Local report: $report"
exit $code
