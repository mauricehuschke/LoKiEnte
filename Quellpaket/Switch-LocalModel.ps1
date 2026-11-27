#requires -Version 7.4
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$InstallRoot,
    [Parameter(Mandatory)][ValidateSet('coder','coder-high','coder-fast','review','fast')][string]$Alias,
    [Parameter(Mandatory)][string]$ResultPath
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
try {
    . (Join-Path $PSScriptRoot 'Common.ps1')
    Initialize-ShadowToolchainLogging -InstallRoot $InstallRoot
    . (Join-Path $PSScriptRoot 'ModelPool.ps1')
    $result=Switch-ShadowLocalModel -InstallRoot $InstallRoot -Alias $Alias
    [IO.File]::WriteAllText($ResultPath,($result|ConvertTo-Json -Depth 10 -Compress),[Text.UTF8Encoding]::new($false))
    exit 0
} catch {
    $failure=$_
    $code=if($failure.Exception.Data['ShadowNativeTimeout']){if($failure.Exception.Data['ShadowControllerUncertain']){'controller_timeout'}else{'controller_check_timeout'}}elseif($failure.Exception.Data['ShadowRuntimeCompatibilityFailure']){'runtime_incompatible'}elseif($failure.Exception.Data['ShadowResourceFitFailure']){'resource_fit'}elseif($failure.Exception.Data['ShadowModelLoadFailure']){'model_load_failed'}elseif($failure.Exception.Data['ShadowModelVerificationFailure']){'model_unverified'}elseif($failure.Exception.Data['ShadowModelConflict']){'model_conflict'}elseif($failure.Exception.Data['ShadowModelBusy']){'model_busy'}elseif($failure.Exception.Data['ShadowLoopbackFailure']){'backend_not_loopback'}elseif($failure.Exception.Data['ShadowAuthenticationFailure']){'backend_authentication'}else{'controller_rejected'}
    $message=if($code -eq 'controller_timeout'){
        'LM Studio model loading or command output exceeded its deadline. Inspect LM Studio before restarting LoKiEnte; another load will not be started automatically.'
    }elseif($code -eq 'controller_check_timeout'){
        'An LM Studio status, catalog or memory check exceeded its deadline. Check LM Studio responsiveness and the local command log, then retry.'
    }elseif($code -eq 'resource_fit'){
        'Model cannot currently load: free memory and retry. The model file is preserved.'
    }elseif($code -eq 'runtime_incompatible'){
        'The selected LM Studio runtime does not support this model architecture. Select or update a compatible GPU runtime in LM Studio, then retry. See runtime/pool-logs.'
    }elseif($code -eq 'model_load_failed'){
        'LM Studio rejected the model load. Check the local model file, runtime and runtime/pool-logs, then retry.'
    }elseif($code -eq 'model_unverified'){
        'Model loaded, but the chat/tool test failed. Check local model and LM Studio logs.'
    }elseif($code -eq 'model_conflict'){
        'An external or manually loaded model blocks the managed model pool. Finish its work, unload it explicitly in LM Studio, then retry.'
    }elseif($code -eq 'model_busy'){
        'The managed model is still busy or its idle state is unknown. Wait for active requests to finish, then retry.'
    }elseif($code -eq 'backend_not_loopback'){
        'The LM Studio server is not bound exclusively to loopback. Disable serving on the local network and bind it to 127.0.0.1, then retry.'
    }elseif($code -eq 'backend_authentication'){
        'LM Studio denied API access. Set its token in the configured user environment variable and restart LoKiEnte; authentication stays enabled.'
    }else{'Local model switch rejected. Read runtime/model-switch-failure.json for the local cause and script location.'}
    # The router deletes its temporary result. Retain the cause on this machine
    # so generic controller refusals can also be diagnosed, without forwarding
    # native output or private paths in HTTP responses.
    try{
        $directory=Join-Path $InstallRoot 'runtime'
        [void][IO.Directory]::CreateDirectory($directory)
        $diagnostic=[ordered]@{
            SchemaVersion=1;CheckedAtUtc=[DateTime]::UtcNow.ToString('o');Alias=$Alias;Code=$code
            Message=$message;Detail=$failure.Exception.Message
            Script=[IO.Path]::GetFileName($failure.InvocationInfo.ScriptName);Line=$failure.InvocationInfo.ScriptLineNumber
        }
        [IO.File]::WriteAllText((Join-Path $directory 'model-switch-failure.json'),($diagnostic|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
    }catch{}
    $result=@{Status='Error';Alias=$Alias;Code=$code;Message=$message}
    try{[IO.File]::WriteAllText($ResultPath,($result|ConvertTo-Json -Depth 10 -Compress),[Text.UTF8Encoding]::new($false))}catch{}
    Write-Error -Message 'Local model switch failed. Check the control report.' -ErrorAction Continue
    exit 1
}
