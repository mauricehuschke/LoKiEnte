#requires -Version 7.4
[CmdletBinding()]
param([string]$SourceRoot=(Split-Path -Parent $PSScriptRoot))
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $SourceRoot 'Runtime.ps1')
$root=Join-Path ([IO.Path]::GetTempPath()) ('shadow-cli-test-'+[guid]::NewGuid().ToString('N'))
$checks=0
function Assert-Cli([bool]$Condition,[string]$Message){
    if(-not $Condition){throw "FAIL: $Message"}
    $script:checks++
}
try{
    $help='--parallel --context-length --estimate-only --identifier --gpu --yes'
    $engine=(Get-Process -Id $PID).Path
    $arguments=@('-NoProfile','-NonInteractive','-Command','[Console]::Error.Write("Path not provided: The parameter [model-key] is required when using --exact."); exit 1')
    $probe=Invoke-LrNative -FilePath $engine -Arguments $arguments -LogDirectory $root -AllowFailure
    Assert-Cli ($probe.ExitCode -eq 1 -and @(Get-LrMissingLoadOptions $help $probe).Count -eq 0) 'Real expected-error process can prove hidden option handling'
    Assert-Cli (@(Get-LrMissingLoadOptions ($help.Replace('--parallel','--parallel-extra')) $probe) -contains '--parallel') 'Hidden-flag proof does not excuse a missing visible capability'
    $failed=$false
    try{$null=Invoke-LrNative -FilePath $engine -Arguments $arguments -LogDirectory $root}catch{$failed=$_.Exception.Message -match 'fehlgeschlagen'}
    Assert-Cli $failed 'Ordinary native commands still fail on nonzero exit'
    $script:json='[]'
    function Invoke-LrNative {
        param($FilePath,$Arguments,$LogDirectory)
        return [pscustomobject]@{Stdout=$script:json;Stderr='';ExitCode=0;LogPath='synthetic-json.log'}
    }
    foreach($command in @('ls','ps')){
        $script:json='[]'
        Assert-Cli (@(Invoke-LrJson -LmsPath synthetic -Arguments @($command,'--json') -LogDirectory $root).Count -eq 0) "$command empty JSON is zero records"
        $script:json='[{"identifier":"one"},{"identifier":"two"}]'
        $models=@(Invoke-LrJson -LmsPath synthetic -Arguments @($command,'--json') -LogDirectory $root)
        Assert-Cli ($models.Count -eq 2 -and $models[1].identifier -ceq 'two') "$command enumerates actual model objects"
        foreach($invalid in @('{}','null','[null]','[{"identifier":"one"},42]')){
            $script:json=$invalid;$failed=$false
            try{$null=Invoke-LrJson -LmsPath synthetic -Arguments @($command,'--json') -LogDirectory $root}catch{$failed=$_.Exception.Message -match 'unerwartete Struktur'}
            Assert-Cli $failed "$command rejects invalid list shape"
        }
    }
    $script:json='{"running":false,"port":1234}'
    $status=Invoke-LrJson -LmsPath synthetic -Arguments @('server','status','--json') -LogDirectory $root
    Assert-Cli ($status.running -eq $false -and $status.port -eq 1234) 'Server status remains an object'
    [pscustomobject]@{suite='CLI compatibility';checks=$checks;passed=$true}|ConvertTo-Json
}finally{if(Test-Path -LiteralPath $root){Remove-Item -LiteralPath $root -Recurse -Force}}
