#requires -Version 7.4
[CmdletBinding()]
param([string]$SourceRoot=(Split-Path -Parent $PSScriptRoot))
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $SourceRoot 'Runtime.ps1')
$root=Join-Path ([IO.Path]::GetTempPath()) ('lokiente-load-errors-'+[guid]::NewGuid().ToString('N'))
$script:checks=0
$script:nativeCommand=${function:Invoke-LrNative}
$script:childCommand=''
function Assert-Load([bool]$Condition,[string]$Message){
    if(-not $Condition){throw "FAIL: $Message"}
    $script:checks++
}
function Invoke-LrNative {
    param($FilePath,$Arguments,$LogDirectory,$TimeoutSeconds,[switch]$AllowFailure)
    Assert-Load ([bool]$AllowFailure) 'Model helper requests the native result before classifying it'
    # Exercise real process exit codes, UTF-8 streams and local command logs.
    & $script:nativeCommand -FilePath (Get-Process -Id $PID).Path -Arguments @('-NoProfile','-NonInteractive','-Command',$script:childCommand) -LogDirectory $LogDirectory -TimeoutSeconds 15 -AllowFailure
}
try {
    $probeArgs=@('load','--exact','--local','--estimate-only','--yes')
    $probeText='Path not provided. The parameter [model-key] is required when using the --exact flag.'
    Assert-Load (Test-LrExpectedLoadProbe -Arguments $probeArgs -ExitCode 1 -Text $probeText) 'The deliberate missing-model capability probe is an expected negative result.'
    Assert-Load (-not (Test-LrExpectedLoadProbe -Arguments @('load','real-model','--exact','--local','--estimate-only','--yes') -ExitCode 1 -Text $probeText)) 'A real selected-model failure must never be hidden as a capability probe.'
    Assert-Load (-not (Test-LrExpectedLoadProbe -Arguments $probeArgs -ExitCode 2 -Text $probeText)) 'An unexpected probe exit code remains an error.'
    Assert-Load (-not (Test-LrExpectedLoadProbe -Arguments $probeArgs -ExitCode 1 -Text 'Authentication failed')) 'Authentication and other native failures remain errors.'
    $cases=@(
        @{Command='[Console]::Error.Write("unknown model architecture: ''qwen35''"); exit 1';Flag='ShadowRuntimeCompatibilityFailure';Match='compatible GPU runtime'},
        @{Command='[Console]::Out.Write("unsupported model architecture: qwen35"); [Console]::Error.Write("out of memory"); exit 1';Flag='ShadowRuntimeCompatibilityFailure';Match='More memory'},
        @{Command='[Console]::Error.Write("CUDA out of memory"); exit 2';Flag='ShadowResourceFitFailure';Match='allocate memory'},
        @{Command='[Console]::Error.Write("Guardrail rejected"); exit 42';Flag='ShadowResourceFitFailure';Match='allocate memory'},
        @{Command='[Console]::Error.Write("invalid GGUF header; private-fixture-marker"); exit 1';Flag='ShadowModelLoadFailure';Match='command log'}
    )
    foreach($case in $cases){
        $script:childCommand=$case.Command
        $failure=$null
        try{$null=Invoke-LrModelCommand -LmsPath synthetic -Arguments @('load','selected.gguf','--exact','--local','--yes') -LogDirectory $root}catch{$failure=$_.Exception}
        Assert-Load ($null -ne $failure -and $failure.Data[$case.Flag] -eq $true -and $failure.Message -match $case.Match) 'Native load refusal has the correct cause and recovery instructions'
        Assert-Load ($failure.Message -notmatch 'private-fixture-marker|qwen35') 'Native output remains local'
        Assert-Load (@(Get-ChildItem -LiteralPath $root -Filter '*.log').Count -gt 0) 'Native output was recorded for diagnosis'
    }
    $script:childCommand='[Console]::Out.Write("Estimated GPU Memory: 2 GiB"); exit 0'
    $result=Invoke-LrModelCommand -LmsPath synthetic -Arguments @('load','selected.gguf','--estimate-only') -LogDirectory $root
    Assert-Load ($result.ExitCode -eq 0 -and $result.Stdout -ceq 'Estimated GPU Memory: 2 GiB') 'Successful estimates remain available to the memory planner'
    $python=(Get-Command python -CommandType Application|Select-Object -First 1).Source
    $watch=[Diagnostics.Stopwatch]::StartNew();$failure=$null
    try{$null=& $script:nativeCommand -FilePath $python -Arguments @('-c','import time;time.sleep(6)') -LogDirectory $root -TimeoutSeconds 2}catch{$failure=$_.Exception}
    Assert-Load ($null -ne $failure -and $failure.Data['ShadowNativeTimeout'] -eq $true -and $watch.Elapsed.TotalSeconds -lt 5) "The command deadline stops a running CLI (elapsed $($watch.Elapsed.TotalSeconds); error $failure)"
    $loadTimeout=New-LrNativeTimeoutError -Arguments @('load','selected.gguf') -TimeoutSeconds 1 -LogPath (Join-Path $root 'load-timeout.log')
    $estimateTimeout=New-LrNativeTimeoutError -Arguments @('load','selected.gguf','--estimate-only') -TimeoutSeconds 1 -LogPath (Join-Path $root 'estimate-timeout.log')
    Assert-Load ($loadTimeout.Data['ShadowControllerUncertain'] -eq $true -and $estimateTimeout.Data['ShadowControllerUncertain'] -eq $false) 'An uncertain model load cannot authorize another load'
    $program='import subprocess,sys,os; subprocess.Popen([sys.executable,"-c","import time;time.sleep(6)"],stdout=sys.stdout,stderr=sys.stderr,close_fds=False); os._exit(0)'
    $watch=[Diagnostics.Stopwatch]::StartNew();$failure=$null
    try{$null=& $script:nativeCommand -FilePath $python -Arguments @('-c',$program) -LogDirectory $root -TimeoutSeconds 2}catch{$failure=$_.Exception}
    Assert-Load ($null -ne $failure -and $failure.Data['ShadowNativeTimeout'] -eq $true -and
        $failure.Message -match 'output to close' -and $watch.Elapsed.TotalSeconds -lt 5) "Inherited handles cannot keep output draining beyond the command deadline (elapsed $($watch.Elapsed.TotalSeconds); error $failure)"
    [pscustomobject]@{suite='Native model command failures';passed=$true;checks=$script:checks;limitations='Real child processes and logs; no model inference.'}|ConvertTo-Json
}finally{
    if(Test-Path -LiteralPath $root){Remove-Item -LiteralPath $root -Recurse -Force}
}
