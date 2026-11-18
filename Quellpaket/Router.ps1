# Local model-router lifecycle. Dot-source Common.ps1, Runtime.ps1 and ModelPool.ps1 first.
Set-StrictMode -Version Latest

function Get-ShadowPoolCatalog {
    param([Parameter(Mandatory)]$Pool)
    Assert-SmpPool -Pool $Pool -RequireReady
    $catalog=[ordered]@{}
    foreach($profile in $Pool.Profiles){
        $roleLabel=switch($profile.Alias){
            'coder-high' {'CODER HIGH'}
            'coder-fast' {'CODER FAST'}
            'coder' {'CODER (ALT)'}
            'review' {'REVIEW'}
            'fast' {'FAST'}
            default {throw "Unbekanntes Modellprofil: $($profile.Alias)"}
        }
        $interleaved=[string](Get-LrProperty $profile 'Interleaved')
        if(-not $interleaved){$interleaved=if($profile.Alias -eq 'review'){'reasoning'}else{'reasoning_content'}}
        if($interleaved -cnotin @('reasoning','reasoning_content')){throw 'Ungueltiges Reasoning-Feld im Modellprofil.'}
        $stateSuffix=if((Get-LrProperty $profile 'VerificationState') -ceq 'Deferred'){' [NOCH NICHT GEPRUEFT]'}else{''}
        $catalog[$profile.Alias]=[ordered]@{
            id=$profile.RouteId;name=('['+$roleLabel+'] '+$profile.Name+$stateSuffix);context=[int]$profile.ContextLength;output=[int]$profile.OutputLimit
            reasoning=$true;interleaved=$interleaved
        }
    }
    return $catalog
}

function Get-ShadowRouterHealth {
    param([Parameter(Mandatory)]$Pool)
    # Validate before constructing authentication headers or issuing a request.
    Assert-SmpPool -Pool $Pool
    $base=([Uri]$Pool.RouterApiBaseUrl).GetLeftPart([UriPartial]::Authority)
    try{
        $status=0
        $health=Invoke-RestMethod -Uri ($base+'/health') -Headers (Get-LrApiHeaders $Pool.ApiTokenEnvironmentVariable) -TimeoutSec 3 -NoProxy -SkipHttpErrorCheck -StatusCodeVariable status -ErrorAction Stop
        if($status -eq 200 -or ($status -eq 503 -and (Get-LrProperty $health 'service') -ceq 'shadow-local-model-router')){return $health}
        Write-Verbose "Router-Status nicht lesbar (HTTP $status)."
        return $null
    }
    catch{Write-Verbose 'Router-Status nicht erreichbar oder nicht als JSON lesbar.';return $null}
}

function Stop-ShadowModelRouter {
    param([Parameter(Mandatory)][string]$InstallRoot,[Parameter(Mandatory)]$Pool)
    $health=Get-ShadowRouterHealth -Pool $Pool
    if(-not $health){
        $port=([Uri]$Pool.RouterApiBaseUrl).Port
        if(@(Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue).Count){throw "Router-Port $port ist belegt, aber der bekannte Router ist nicht erreichbar. Kein Prozess wird beendet."}
        return
    }
    if((Get-LrProperty $health 'service') -cne 'shadow-local-model-router'){throw 'Der Port gehoert nicht zum erwarteten lokalen Router. Er bleibt unveraendert.'}
    if((Get-LrProperty $health 'busy' $true) -or [int](Get-LrProperty $health 'queued' 1) -gt 0){throw 'Der lokale Router arbeitet noch. Laufende Chats/Auftraege abschliessen und erneut starten.'}
    $controlPath=Join-Path $InstallRoot 'runtime/router-control.json'
    if(-not(Test-Path -LiteralPath $controlPath)){throw 'Der Kontrollnachweis fuer den laufenden Router fehlt. Kein fremder Prozess wird beendet.'}
    $control=Get-Content -LiteralPath $controlPath -Raw|ConvertFrom-Json
    $headers=Get-LrApiHeaders $Pool.ApiTokenEnvironmentVariable
    $headers['X-Shadow-Control']=[string]$control.token
    $base=([Uri]$Pool.RouterApiBaseUrl).GetLeftPart([UriPartial]::Authority)
    try{$result=Invoke-RestMethod -Uri ($base+'/admin/shutdown') -Method Post -Headers $headers -TimeoutSec 10 -NoProxy -ErrorAction Stop}
    catch{throw 'Der laufende Router konnte nicht authentifiziert beendet werden. Er wurde nicht durch einen beliebigen Prozess-Kill ersetzt.'}
    if((Get-LrProperty $result 'stopping' $false) -ne $true){throw 'Der Router hat das kontrollierte Beenden nicht bestaetigt.'}
    for($i=0;$i -lt 20;$i++){
        if(-not(Get-ShadowRouterHealth -Pool $Pool)){return}
        Start-Sleep -Milliseconds 250
    }
    throw 'Der Router beendet sich noch. Einen Moment warten und erneut starten.'
}

function Get-ShadowRoutingDigest {
    param($Pool,[string]$NodePath,[string]$PowerShellPath)
    # Hash the routing contract only. Estimates, timestamps and verification
    # outcomes are runtime data and are refreshed by the controller.
    $contract=[ordered]@{Node=$NodePath;PowerShell=$PowerShellPath}
    foreach($name in @('SchemaVersion','OwnerId','PrimaryAlias','BackendApiBaseUrl','RouterApiBaseUrl','LmsPath','ApiTokenEnvironmentVariable','AllowPartialGpuOffload','AllowUnfitAttempt')){
        $contract[$name]=Get-LrProperty $Pool $name
    }
    $contract.Profiles=@(foreach($profile in $Pool.Profiles){
        $entry=[ordered]@{}
        foreach($name in @('Alias','RouteId','InstanceId','ModelPath','ModelKey','ExpectedPath','SelectedVariant','ContextLength','OutputLimit','Parallel')){
            $entry[$name]=Get-LrProperty $profile $name
        }
        $entry
    })
    $bytes=[Text.Encoding]::UTF8.GetBytes(($contract|ConvertTo-Json -Depth 8 -Compress))
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
}

function Start-ShadowModelRouter {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$InstallRoot,
        [Parameter(Mandatory)]$Pool,
        [Parameter(Mandatory)][string]$NodePath,
        [Parameter(Mandatory)][string]$PowerShellPath
    )
    Assert-SmpPool -Pool $Pool -RequireReady
    $poolPath=Join-Path $InstallRoot 'runtime/model-pool.json'
    $digest=Get-ShadowRoutingDigest $Pool $NodePath $PowerShellPath
    $health=Get-ShadowRouterHealth -Pool $Pool
    if($health -and (Get-LrProperty $health 'service') -ceq 'shadow-local-model-router' -and
       (Get-LrProperty $health 'configDigest') -ceq $digest -and (Get-LrProperty $health 'version') -ceq '2026.11.17.15' -and
       (Get-LrProperty $health 'ready' $false) -eq $true){
        return [pscustomobject]@{Status='Ready';ApiBaseUrl=$Pool.RouterApiBaseUrl;Port=([Uri]$Pool.RouterApiBaseUrl).Port;Pid=$health.pid;ConfigDigest=$digest;Reused=$true}
    }
    Stop-ShadowModelRouter -InstallRoot $InstallRoot -Pool $Pool
    # Only restart/load the backend when no managed router is using it.
    $Pool=Start-LocalModelPool -InstallRoot $InstallRoot
    $digest=Get-ShadowRoutingDigest $Pool $NodePath $PowerShellPath
    $controlPath=Join-Path $InstallRoot 'runtime/router-control.json'
    if(Test-Path -LiteralPath $controlPath){$control=Get-Content -LiteralPath $controlPath -Raw|ConvertFrom-Json}
    else{
        $control=[pscustomobject]@{schema=1;token=[Convert]::ToHexString([Security.Cryptography.RandomNumberGenerator]::GetBytes(32)).ToLowerInvariant()}
        $null=Write-ShadowManagedFile -Path $controlPath -Content ($control|ConvertTo-Json)
    }
    if($control.schema -ne 1 -or $control.token -notmatch '^[a-f0-9]{64}$'){throw 'Ungueltiger Kontrollnachweis im lokalen Routerprofil.'}
    $start=[Diagnostics.ProcessStartInfo]::new()
    $start.FileName=$NodePath;$start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.WorkingDirectory=$InstallRoot
    foreach($arg in @((Join-Path $InstallRoot 'app/ModelRouter.mjs'),'--config',$poolPath,'--routing-digest',$digest,'--pwsh',$PowerShellPath,'--switch-script',(Join-Path $InstallRoot 'app/Switch-LocalModel.ps1'),'--port',([string]([Uri]$Pool.RouterApiBaseUrl).Port))){[void]$start.ArgumentList.Add($arg)}
    $start.Environment['SHADOW_LOCAL_ROUTER_CONTROL']=[string]$control.token
    if($Pool.ApiTokenEnvironmentVariable){
        $name=[string]$Pool.ApiTokenEnvironmentVariable
        $token=[Environment]::GetEnvironmentVariable($name,'Process')
        if([string]::IsNullOrWhiteSpace($token)){$token=[Environment]::GetEnvironmentVariable($name,'User')}
        if(-not [string]::IsNullOrWhiteSpace($token)){$start.Environment[$name]=$token}
    }
    $process=[Diagnostics.Process]::Start($start)
    try{
        for($attempt=0;$attempt -lt 30;$attempt++){
            if($process.HasExited){throw "Lokaler Router wurde mit Exitcode $($process.ExitCode) beendet. Konfiguration und Port pruefen."}
            $health=Get-ShadowRouterHealth -Pool $Pool
            if($health -and (Get-LrProperty $health 'service') -ceq 'shadow-local-model-router' -and
               (Get-LrProperty $health 'configDigest') -ceq $digest -and (Get-LrProperty $health 'pid') -eq $process.Id -and
               (Get-LrProperty $health 'ready' $false) -eq $true){
                return [pscustomobject]@{Status='Ready';ApiBaseUrl=$Pool.RouterApiBaseUrl;Port=([Uri]$Pool.RouterApiBaseUrl).Port;Pid=$process.Id;ConfigDigest=$digest;Reused=$false}
            }
            Start-Sleep -Milliseconds 500
        }
        throw 'Lokaler Router hat seinen geprueften Bereitschaftsstatus nicht geliefert.'
    }catch{
        $failure=$_
        # This handle belongs to the process started above. Never discover/kill
        # a process merely because its PID or port matches a foreign service.
        try{if(-not $process.HasExited){$process.Kill($true);$null=$process.WaitForExit(5000)}}catch{Write-Warning 'Der selbst gestartete Router konnte nach fehlgeschlagenem Start nicht beendet werden.'}
        throw $failure
    }finally{$process.Dispose()}
}
