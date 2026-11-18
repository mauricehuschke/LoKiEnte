#requires -Version 7.4
[CmdletBinding()]
param([string]$SourceRoot=(Split-Path -Parent $PSScriptRoot))
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $SourceRoot 'Common.ps1')
. (Join-Path $SourceRoot 'Runtime.ps1')
$root=Join-Path ([IO.Path]::GetTempPath()) ('shadow-single-fit-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
$script:loaded=@();$script:rejectLoad=$true;$script:badSmoke=$false;$script:loadAttempts=0
function Resolve-LocalLmsCommand {param($LmsPath) return 'synthetic-lms'}
function Assert-LrLoadCapabilities {param($LmsPath,$LogDirectory)}
function Assert-LrLoopbackListener {param($Port)}
function Ensure-LrInferenceEngine {param($LmsPath,$LogDirectory) return 'synthetic-engine'}
function Get-LocalNvidiaGpu {
    param($LogDirectory)
    return [pscustomobject]@{Gpu=[pscustomobject]@{Name='Synthetic';FreeBytes=4GB;TotalBytes=20GB};FreeRamBytes=8GB;TotalRamBytes=28GB}
}
function Get-LrDownloadedModels {
    param($LmsPath,$LogDirectory)
    return [pscustomobject]@{type='llm';path='local/model';modelKey='local/model';deviceIdentifier=$null}
}
function Invoke-LrJson {
    param($LmsPath,$Arguments,$LogDirectory)
    switch($Arguments[0]){
        'server' {return [pscustomobject]@{running=$true;port=1234}}
        'ps' {return $script:loaded}
        default {throw 'Unexpected JSON request'}
    }
}
function Invoke-LrNative {
    param($FilePath,[string[]]$Arguments,$LogDirectory,$TimeoutSeconds,[switch]$AllowFailure)
    if($Arguments[0] -eq '--version'){return [pscustomobject]@{Stdout='synthetic';Stderr='';ExitCode=0;LogPath='mock'}}
    if($Arguments[0] -ne 'load'){throw 'Unexpected CLI request'}
    if($Arguments -contains '--estimate-only'){
        return [pscustomobject]@{Stdout="Estimated GPU Memory: 10 GiB`nEstimated Total Memory: 12 GiB`nThis model may be loaded based on your resource guardrails settings.";Stderr='';ExitCode=0;LogPath='mock'}
    }
    if(-not $AllowFailure){throw 'Expected explicit best-effort load'}
    $script:loadAttempts++
    if($script:rejectLoad){return [pscustomobject]@{Stdout='';Stderr='rejected';ExitCode=42;LogPath='mock'}}
    $context=[int]$Arguments[[array]::IndexOf($Arguments,'--context-length')+1]
    $id=$Arguments[[array]::IndexOf($Arguments,'--identifier')+1]
    $script:loaded=@([pscustomobject]@{type='llm';path='local/model';modelKey='local/model';identifier=$id;deviceIdentifier=$null;status='idle';queued=0;parallel=1;contextLength=$context})
    return [pscustomobject]@{Stdout='';Stderr='';ExitCode=0;LogPath='mock'}
}
function Invoke-LrApi {
    param($Uri,$Headers,$Method,$Body,$TimeoutSeconds)
    $instances=@($script:loaded|ForEach-Object {[pscustomobject]@{id=$_.identifier;config=[pscustomobject]@{context_length=$_.contextLength;parallel=1}}})
    return [pscustomobject]@{models=@([pscustomobject]@{loaded_instances=$instances})}
}
function Test-LrModelInference {
    param($ApiBaseUrl,$ModelId,$Headers)
    if($script:badSmoke){throw 'Synthetic model test failed'}
    return [pscustomobject]@{Chat='Passed';ToolCall='Passed';ToolResultRoundTrip='Passed'}
}
try {
    $arguments=@{StateRoot=$root;ModelKey='local/model';ContextLength=16384;Port=1234;DownloadModel=$false;LmsPath='synthetic';ApiTokenEnvironmentVariable=''}
    $blocked=$false
    try{$null=Configure-LocalRuntime @arguments}catch{$blocked=$_.Exception.Message -match 'No verified memory fit'}
    if(-not $blocked -or $script:loadAttempts){throw 'Strict single-model mode attempted a load despite insufficient memory.'}
    $arguments.AllowUnfitAttempt=$true
    $result=Configure-LocalRuntime @arguments
    $saved=Get-Content -LiteralPath (Join-Path $root 'runtime-state.json') -Raw|ConvertFrom-Json
    if($result.Status -cne 'Deferred' -or $saved.Status -cne 'Deferred' -or $saved.SmokeTests.Chat -cne 'NotRun' -or
       $saved.ModelPath -cne 'local/model' -or $script:loadAttempts -ne 1){
        throw 'Rejected low-memory model was not preserved as explicitly unverified.'
    }
    $script:rejectLoad=$false
    $result=Configure-LocalRuntime @arguments
    if($result.Status -cne 'Ready' -or -not $result.Estimate.ReserveOverride -or $result.SmokeTests.ToolCall -cne 'Passed'){
        throw 'Successful best-effort single model was not tested and recorded.'
    }
    $script:loaded=@();$script:badSmoke=$true
    $result=Configure-LocalRuntime @arguments
    if($result.Status -cne 'Deferred' -or $result.SmokeTests.Chat -cne 'NotVerified' -or
       $result.VerificationMessage -notmatch 'Synthetic model test failed'){
        throw 'Failed inference test was not surfaced as a deferred warning.'
    }
    [pscustomobject]@{suite='Single model low-memory behavior';passed=$true;checks=4;limitations='LM Studio and GPU boundaries are mocked.'}|ConvertTo-Json
} finally {
    if(Test-Path -LiteralPath $root){Remove-Item -LiteralPath $root -Recurse -Force}
}
