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
        'Modell aktuell nicht ladbar: Speicher freigeben und erneut versuchen. Die Modelldatei bleibt erhalten.'
    }elseif($code -eq 'model_unverified'){
        'Modell geladen, aber der Chat-/Werkzeugtest ist fehlgeschlagen. Lokale Modell- und LM-Studio-Protokolle pruefen.'
    }else{'Der lokale Modellwechsel wurde abgelehnt. Modellpool und lokale Protokolle pruefen.'}
    $result=@{Status='Error';Alias=$Alias;Code=$code;Message=$message}
    try{[IO.File]::WriteAllText($ResultPath,($result|ConvertTo-Json -Depth 10 -Compress),[Text.UTF8Encoding]::new($false))}catch{}
    Write-Error -Message 'Lokaler Modellwechsel fehlgeschlagen. Kontrollbericht pruefen.' -ErrorAction Continue
    exit 1
}
