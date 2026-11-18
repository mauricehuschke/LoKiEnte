#requires -Version 7.4
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$InstallRoot,
    [Parameter(Mandatory)][ValidateSet('coder','coder-high','coder-fast','review','fast')][string]$Alias,
    [Parameter(Mandatory)][string]$ResultPath
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'ModelPool.ps1')
try {
    $result=Switch-ShadowLocalModel -InstallRoot $InstallRoot -Alias $Alias
    [IO.File]::WriteAllText($ResultPath,($result|ConvertTo-Json -Depth 10 -Compress),[Text.UTF8Encoding]::new($false))
    exit 0
} catch {
    $code=if($_.Exception.Data['ShadowResourceFitFailure']){'resource_fit'}elseif($_.Exception.Data['ShadowModelVerificationFailure']){'model_unverified'}else{'controller_rejected'}
    $message=if($code -eq 'resource_fit'){
        'Model cannot currently load: free memory and retry. The model file is preserved.'
    }elseif($code -eq 'model_unverified'){
        'Model loaded, but the chat/tool test failed. Check local model and LM Studio logs.'
    }else{'Local model switch rejected. Check model pool and local logs.'}
    $result=@{Status='Error';Alias=$Alias;Code=$code;Message=$message}
    try{[IO.File]::WriteAllText($ResultPath,($result|ConvertTo-Json -Depth 10 -Compress),[Text.UTF8Encoding]::new($false))}catch{}
    Write-Error -Message 'Local model switch failed. Check the control report.' -ErrorAction Continue
    exit 1
}
