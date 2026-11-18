#requires -Version 7.4
# Explicit local model lifecycle. Dot-sourcing performs no setup.
# Common.ps1 and Runtime.ps1 are reused; existing LM Studio settings are never edited.
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'Common.ps1')
. (Join-Path $PSScriptRoot 'Runtime.ps1')

function Write-SmpJson {
    param([string]$Path,$Value,[string]$InstallRoot)
    $null=Write-ShadowManagedFile -Path $Path -Content ($Value|ConvertTo-Json -Depth 30) -BackupRoot (Join-Path $InstallRoot 'backups/model-pool')
}

function Enter-SmpLock {
    param([string]$InstallRoot,[int]$TimeoutSeconds=60)
    $directory=Join-Path $InstallRoot 'runtime'
    [void][IO.Directory]::CreateDirectory($directory)
    $path=Join-Path $directory 'model-pool.lock'
    $watch=[Diagnostics.Stopwatch]::StartNew()
    while($true){
        try{return [IO.File]::Open($path,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}
        catch [IO.IOException]{
            if($watch.Elapsed.TotalSeconds -ge $TimeoutSeconds){throw 'Ein anderer Prozess verwaltet gerade den Modellpool. Kein paralleler Modellwechsel ausgefuehrt.'}
            Start-Sleep -Milliseconds 250
        }
    }
}

function Get-SmpOwner {
    param([string]$InstallRoot)
    $path=Join-Path $InstallRoot 'runtime/model-ownership.json'
    if(Test-Path -LiteralPath $path){
        $owner=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json
        if((Get-LrProperty $owner 'SchemaVersion') -ne 1 -or (Get-LrProperty $owner 'OwnerId') -notmatch '^[a-f0-9]{24}$'){
            throw 'Unbekannte Modell-Eigentuemerdatei. Bestehende Instanzen bleiben erhalten.'
        }
        if($null -eq $owner.PSObject.Properties['Entries'] -or $owner.Entries -isnot [array]){
            throw 'Modell-Eigentuemerdatei enthaelt keine gueltige Eintragsliste.'
        }
        $ids=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach($entry in $owner.Entries){
            if((Get-LrProperty $entry 'Verified') -isnot [bool] -or -not(Get-LrProperty $entry 'InstanceId') -or
               -not(Get-LrProperty $entry 'ModelPath') -or -not $ids.Add([string]$entry.InstanceId)){
                throw 'Modell-Eigentuemerdatei enthaelt unvollstaendige oder doppelte Eintraege.'
            }
        }
        return $owner
    }
    $owner=[pscustomobject]@{SchemaVersion=1;OwnerId=[guid]::NewGuid().ToString('N').Substring(0,24);Entries=@()}
    # The v1 package's exact identifier may be adopted only with its saved verified path.
    # A user-supplied/reused custom alias remains foreign.
    $legacyPath=Join-Path $InstallRoot 'runtime/runtime-state.json'
    if(Test-Path -LiteralPath $legacyPath){
        $legacy=Get-Content -LiteralPath $legacyPath -Raw|ConvertFrom-Json
        $smoke=Get-LrProperty $legacy 'SmokeTests'
        if((Get-LrProperty $legacy 'SchemaVersion') -eq 1 -and (Get-LrProperty $legacy 'Status') -ceq 'Ready' -and
           (Get-LrProperty $legacy 'ReusedLoadedModel' $true) -eq $false -and
           (Get-LrProperty $legacy 'ModelId') -ceq 'shadow-local-coder' -and (Get-LrProperty $legacy 'ModelPath') -and
           (Get-LrProperty $smoke 'Chat') -ceq 'Passed' -and (Get-LrProperty $smoke 'ToolCall') -ceq 'Passed' -and
           (Get-LrProperty $smoke 'ToolResultRoundTrip') -ceq 'Passed'){
            $owner.Entries=@([pscustomobject]@{InstanceId='shadow-local-coder';ModelPath=[string]$legacy.ModelPath;Verified=$true;Origin='verified-v1-package'})
        }
    }
    Write-SmpJson -Path $path -Value $owner -InstallRoot $InstallRoot
    return $owner
}

function Save-SmpOwnership {
    param([string]$InstallRoot,$Owner,[string]$InstanceId,[string]$ModelPath,[switch]$Pending,[string]$ExpectedPath,[string]$SelectedVariant,[string]$GpuOffload)
    $Owner.Entries=@($Owner.Entries|Where-Object { $_.InstanceId -cne $InstanceId })+@(
        [pscustomobject]@{InstanceId=$InstanceId;ModelPath=$ModelPath;Verified=(-not $Pending);Origin=$(if($Pending){'pending-explicit-load'}else{'verified-explicit-load'});ExpectedPath=$ExpectedPath;SelectedVariant=$SelectedVariant;GpuOffload=$GpuOffload}
    )
    Write-SmpJson -Path (Join-Path $InstallRoot 'runtime/model-ownership.json') -Value $Owner -InstallRoot $InstallRoot
}

function Restore-SmpPendingOwnership {
    param([string]$InstallRoot,$Pool,$Owner,[string]$LogDirectory)
    $embeddingPending=@($Owner.Entries|Where-Object { (Get-LrProperty $_ 'Origin') -ceq 'pending-cpu-embedding' -and $_.Verified -eq $false })
    if($embeddingPending.Count -gt 1){throw 'Mehrdeutige ausstehende Embeddinginstanzen. Keine Instanz wird uebernommen.'}
    if($embeddingPending.Count){
        $entry=$embeddingPending[0]
        if($entry.InstanceId -cne ('shadow-'+$Owner.OwnerId+'-embedding')){throw 'Unbekannter Embedding-Ladeauftrag. Keine Instanz wird uebernommen.'}
        $instances=@(Invoke-LrJson -LmsPath $Pool.LmsPath -Arguments @('ps','--json') -LogDirectory $LogDirectory)
        $matches=@($instances|Where-Object {(Get-LrProperty $_ 'identifier') -ceq $entry.InstanceId})
        if($matches.Count){
            if($matches.Count -ne 1 -or (Get-LrProperty $matches[0] 'type') -cne 'embedding' -or
               (Get-LrProperty $matches[0] 'path') -cne $entry.ModelPath -or
               $null -ne (Get-LrProperty $matches[0] 'deviceIdentifier' '__unknown__') -or
               [int](Get-LrProperty $matches[0] 'contextLength' 0) -ne 2048){
                throw 'Ausstehende Embeddinginstanz stimmt nicht mit dem Ladeauftrag ueberein. Sie bleibt unveraendert.'
            }
            $entry.Verified=$true
            $entry.Origin='verified-cpu-embedding'
            Write-SmpJson -Path (Join-Path $InstallRoot 'runtime/model-ownership.json') -Value $Owner -InstallRoot $InstallRoot
        }
    }
    $pending=@($Owner.Entries|Where-Object {
        (Get-LrProperty $_ 'Verified') -eq $false -and (Get-LrProperty $_ 'Origin') -ceq 'pending-explicit-load'
    })
    if(-not $pending.Count){return}
    $loaded=@(Invoke-LrJson -LmsPath $Pool.LmsPath -Arguments @('ps','--json') -LogDirectory $LogDirectory)
    foreach($entry in $pending){
        if($entry.InstanceId -cnotmatch ('^shadow-'+[regex]::Escape($Owner.OwnerId)+'-(coder|coder-high|coder-fast|review|fast)$')){
            throw 'Unbekannter ausstehender Ladeauftrag. Keine Modellinstanz wird uebernommen.'
        }
        $matches=@($loaded|Where-Object { (Get-LrProperty $_ 'identifier') -ceq $entry.InstanceId })
        if(-not $matches.Count){continue}
        if($matches.Count -ne 1 -or (Get-LrProperty $matches[0] 'path') -cne $entry.ModelPath -or
           $null -ne (Get-LrProperty $matches[0] 'deviceIdentifier' '__unknown__')){
            throw 'Ausstehender Ladeauftrag stimmt nicht mit der lokalen Instanz ueberein. Sie bleibt unveraendert.'
        }
        $variant=[string](Get-LrProperty $entry 'SelectedVariant')
        $expected=[string](Get-LrProperty $entry 'ExpectedPath')
        if($variant){
            if(-not $expected -or (Get-LrProperty $matches[0] 'selectedVariant') -cne $variant){
                throw 'Ausstehender Ladeauftrag stimmt nicht mit der gespeicherten Modellvariante ueberein. Instanz bleibt unveraendert.'
            }
            Assert-LrSelectedModel -LmsPath $Pool.LmsPath -LogDirectory $LogDirectory -ExpectedPath $expected -ModelPath $entry.ModelPath
        }
        # Ownership proves identity, not readiness. The ordinary idle/config checks still run.
        Save-SmpOwnership -InstallRoot $InstallRoot -Owner $Owner -InstanceId $entry.InstanceId -ModelPath $entry.ModelPath -ExpectedPath $expected -SelectedVariant $variant -GpuOffload ([string](Get-LrProperty $entry 'GpuOffload'))
        Write-ShadowMessage "Eigenen Ladeauftrag $($entry.InstanceId) wiedererkannt. Modellbereitschaft wird erneut geprueft." 'WARN'
    }
}

function Assert-SmpPool {
    param($Pool,[switch]$RequireReady)
    if((Get-LrProperty $Pool 'SchemaVersion') -ne 2){throw 'Unbekanntes Modellpool-Schema. Provisionierung erneut ausfuehren.'}
    if($RequireReady -and (Get-LrProperty $Pool 'Status') -cne 'Ready'){throw 'Modellpool wurde noch nicht vollstaendig geprueft. Provisionierung zuerst abschliessen.'}
    $allowOffload=Get-LrProperty $Pool 'AllowPartialGpuOffload' $false
    if($allowOffload -isnot [bool]){throw 'Ungueltige CPU-Auslagerungsoption im Modellpool.'}
    $endpoint=[Uri]$Pool.BackendApiBaseUrl
    if(-not $endpoint.IsLoopback -or $endpoint.Scheme -ne 'http' -or $endpoint.AbsolutePath.TrimEnd('/') -cne '/v1' -or $endpoint.UserInfo -or $endpoint.Query -or $endpoint.Fragment){
        throw 'Modellpool verwendet keinen eindeutigen lokalen LM-Studio-Endpunkt.'
    }
    $router=[Uri]$Pool.RouterApiBaseUrl
    if(-not $router.IsLoopback -or $router.Scheme -ne 'http' -or $router.AbsolutePath.TrimEnd('/') -cne '/v1' -or
       $router.UserInfo -or $router.Query -or $router.Fragment -or $router.Port -lt 1024 -or $router.Port -eq $endpoint.Port){
        throw 'Modellpool verwendet keinen eindeutigen lokalen Router-Endpunkt mit getrenntem Port.'
    }
    $aliases=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $ids=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($profile in @($Pool.Profiles)){
        if($profile.Alias -notin @('coder','coder-high','coder-fast','review','fast') -or -not $aliases.Add([string]$profile.Alias) -or -not $ids.Add([string]$profile.InstanceId)){
            throw 'Mehrdeutige oder unbekannte Modellpool-Rolle.'
        }
        if(-not $profile.ModelPath -or [int]$profile.ContextLength -lt 8192 -or [int]$profile.ContextLength -gt 65536){throw 'Unvollstaendiges Modellprofil.'}
    }
    if(-not $aliases.Contains('review')){throw 'Modellpool braucht ein Reviewprofil.'}
    if($aliases.Contains('coder')){
        if($aliases.Contains('coder-high') -or $aliases.Contains('coder-fast')){throw 'Alter und neuer Coder-Pool duerfen nicht vermischt werden.'}
    }elseif(-not $aliases.Contains('coder-high') -or -not $aliases.Contains('coder-fast')){
        throw 'Modellpool braucht coder-high und coder-fast.'
    }
    $primary=[string](Get-LrProperty $Pool 'PrimaryAlias' $(if($aliases.Contains('coder')){'coder'}else{'coder-high'}))
    if($primary -cnotin @('coder','coder-high') -or -not $aliases.Contains($primary)){
        throw 'Das Hauptmodell des Modellpools ist ungueltig.'
    }
}

function Ensure-SmpServer {
    param($Pool,[string]$LogDirectory)
    $server=Invoke-LrJson -LmsPath $Pool.LmsPath -Arguments @('server','status','--json') -LogDirectory $LogDirectory
    $port=([Uri]$Pool.BackendApiBaseUrl).Port
    if([bool](Get-LrProperty $server 'running' $false)){
        if([int](Get-LrProperty $server 'port' 0) -ne $port){throw 'LM Studio laeuft auf einem anderen Port. Bestehenden Server erhalten; Provisionierung erneut ausfuehren.'}
    } else {
        if(@(Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue).Count){throw "Port $port ist durch einen anderen Dienst belegt."}
        $null=Invoke-LrNative -FilePath $Pool.LmsPath -Arguments @('server','start','--port',"$port",'--bind','127.0.0.1') -LogDirectory $LogDirectory
    }
    Assert-LrLoopbackListener -Port $port
}

function Get-SmpOwnedLoaded {
    param($Pool,$Owner,[string]$LogDirectory,[int]$IdleTimeoutSeconds=60)
    $watch=[Diagnostics.Stopwatch]::StartNew()
    while($true){
        $loaded=@(Invoke-LrJson -LmsPath $Pool.LmsPath -Arguments @('ps','--json') -LogDirectory $LogDirectory)
        $embeddingId='shadow-'+$Owner.OwnerId+'-embedding'
        if(@($loaded|Where-Object {(Get-LrProperty $_ 'identifier') -ceq $embeddingId}).Count -gt 1){
            throw 'Mehrere Instanzen verwenden die verwaltete Embeddingkennung. Keine Instanz wird veraendert.'
        }
        $busy=$false
        foreach($item in $loaded){
            if($null -ne (Get-LrProperty $item 'deviceIdentifier' '__unknown__')){
                throw 'Eine entfernte oder nicht eindeutig lokale Modellinstanz ist geladen. Sie wird nicht veraendert.'
            }
            $owned=@($Owner.Entries|Where-Object {
                $_.Verified -eq $true -and $_.InstanceId -ceq (Get-LrProperty $item 'identifier') -and $_.ModelPath -ceq (Get-LrProperty $item 'path')
            })
            if($owned.Count -ne 1){throw 'Ein fremdes oder nicht verifiziert verwaltetes Modell ist geladen. Es wird nicht entladen. Bestehende Modellarbeit beenden und bewusst selbst entladen.'}
            if((Get-LrProperty $owned[0] 'Origin') -ceq 'verified-cpu-embedding'){
                if((Get-LrProperty $item 'type') -cne 'embedding' -or
                   (Get-LrProperty $item 'identifier') -cne ('shadow-'+$Owner.OwnerId+'-embedding')){
                    throw 'Die verwaltete Embeddinginstanz ist nicht eindeutig. Sie bleibt unveraendert.'
                }
                continue
            }
            $ownedVariant=[string](Get-LrProperty $owned[0] 'SelectedVariant')
            if($ownedVariant -and (Get-LrProperty $item 'selectedVariant') -cne $ownedVariant){
                throw 'Die geladene Variante stimmt nicht mit dem Eigentumsnachweis ueberein. Die Instanz bleibt unveraendert.'
            }
            $status=[string](Get-LrProperty $item 'status' '__unknown__')
            $queued=[int](Get-LrProperty $item 'queued' 0)
            if($status -ne 'idle' -or $queued -gt 0){$busy=$true}
        }
        if(-not $busy){
            return @($loaded|Where-Object {
                $id=Get-LrProperty $_ 'identifier'
                -not @($Owner.Entries|Where-Object { $_.InstanceId -ceq $id -and (Get-LrProperty $_ 'Origin') -ceq 'verified-cpu-embedding' }).Count
            })
        }
        if($watch.Elapsed.TotalSeconds -ge $IdleTimeoutSeconds){throw 'Verwaltetes Modell arbeitet noch oder sein Leerlauf ist nicht nachweisbar. Kein Modell wurde entladen.'}
        Start-Sleep -Milliseconds 500
    }
}

function Remove-SmpOwnedInstance {
    param($Pool,$Owner,[string]$InstanceId,[string]$LogDirectory)
    $loaded=@(Get-SmpOwnedLoaded -Pool $Pool -Owner $Owner -LogDirectory $LogDirectory)
    $target=@($loaded|Where-Object { (Get-LrProperty $_ 'identifier') -ceq $InstanceId })
    if($target.Count -eq 0){return}
    if($target.Count -ne 1){throw 'Zu entladende Modellinstanz ist nicht eindeutig.'}
    $headers=Get-LrApiHeaders -ApiTokenEnvironmentVariable $Pool.ApiTokenEnvironmentVariable
    $root=$Pool.BackendApiBaseUrl -replace '/v1/?$',''
    $response=Invoke-LrApi -Uri "$root/api/v1/models/unload" -Headers $headers -Method POST -Body @{instance_id=$InstanceId} -TimeoutSeconds 120
    if((Get-LrProperty $response 'instance_id') -cne $InstanceId){throw 'LM Studio bestaetigte das gezielte Entladen nicht eindeutig.'}
    $after=@(Invoke-LrJson -LmsPath $Pool.LmsPath -Arguments @('ps','--json') -LogDirectory $LogDirectory)
    if(@($after|Where-Object { (Get-LrProperty $_ 'identifier') -ceq $InstanceId }).Count){throw 'Modellinstanz bleibt nach dem Entladen sichtbar.'}
}

function Test-SmpLoadedProfile {
    param($Pool,$Profile,$Owner,[string]$LogDirectory)
    Assert-LrLoopbackListener -Port ([Uri]$Pool.BackendApiBaseUrl).Port
    $ps=@(Invoke-LrJson -LmsPath $Pool.LmsPath -Arguments @('ps','--json') -LogDirectory $LogDirectory)
    if(@($ps|Where-Object {(Get-LrProperty $_ 'identifier') -ceq ('shadow-'+$Owner.OwnerId+'-embedding')}).Count -gt 1){
        throw 'Mehrere Instanzen verwenden die verwaltete Embeddingkennung. Keine Instanz wird veraendert.'
    }
    $ps=@($ps|Where-Object {
        $item=$_
        -not @($Owner.Entries|Where-Object {
            $_.Verified -eq $true -and (Get-LrProperty $_ 'Origin') -ceq 'verified-cpu-embedding' -and
            $_.InstanceId -ceq ('shadow-'+$Owner.OwnerId+'-embedding') -and
            $_.InstanceId -ceq (Get-LrProperty $item 'identifier') -and $_.ModelPath -ceq (Get-LrProperty $item 'path') -and
            (Get-LrProperty $item 'type') -ceq 'embedding' -and $null -eq (Get-LrProperty $item 'deviceIdentifier' '__unknown__')
        }).Count
    })
    $matching=@($ps|Where-Object {
        (Get-LrProperty $_ 'identifier') -ceq $Profile.InstanceId -and (Get-LrProperty $_ 'path') -ceq $Profile.ModelPath -and
        $null -eq (Get-LrProperty $_ 'deviceIdentifier' '__unknown__')
    })
    if($matching.Count -ne 1 -or $ps.Count -ne 1 -or [int](Get-LrProperty $matching[0] 'parallel' 0) -ne 1){throw 'Exakte lokale Modellinstanz und einzelner Inferenz-Slot sind nicht nachweisbar.'}
    $variant=[string](Get-LrProperty $Profile 'SelectedVariant')
    if($variant -and (Get-LrProperty $matching[0] 'selectedVariant') -cne $variant){throw 'Geladene Modellvariante stimmt nicht mit dem geprueften Profil ueberein.'}
    if($variant){Assert-LrSelectedModel -LmsPath $Pool.LmsPath -LogDirectory $LogDirectory -ExpectedPath $Profile.ExpectedPath -ModelPath $Profile.ModelPath}
    $root=$Pool.BackendApiBaseUrl -replace '/v1/?$',''
    $catalog=Invoke-LrApi -Uri "$root/api/v1/models" -Headers (Get-LrApiHeaders $Pool.ApiTokenEnvironmentVariable) -TimeoutSeconds 60
    $instances=@(foreach($model in @(Get-LrProperty $catalog 'models' @())){
        foreach($instance in @(Get-LrProperty $model 'loaded_instances' @())){
            if((Get-LrProperty $instance 'id') -ceq $Profile.InstanceId){$instance}
        }
    })
    if($instances.Count -ne 1){throw 'Geladene Modellinstanz ist ueber REST nicht eindeutig nachweisbar.'}
    $config=Get-LrProperty $instances[0] 'config'
    if([int](Get-LrProperty $config 'context_length' 0) -ne [int]$Profile.ContextLength -or [int](Get-LrProperty $config 'parallel' 0) -ne 1){
        throw 'Tatsaechlicher Modellkontext oder Parallelitaet weicht vom geprueften Profil ab.'
    }
    return [pscustomobject]@{Status='Ready';Alias=$Profile.Alias;ModelId=$Profile.InstanceId;InstanceId=$Profile.InstanceId;ContextLength=[int]$Profile.ContextLength;Parallel=1}
}

function Set-SmpActiveProfile {
    param([string]$InstallRoot,$Pool,$Owner,[string]$Alias,[string]$LogDirectory,[switch]$AllowContextFallback,[switch]$AllowUnfitAttempt)
    $profiles=@($Pool.Profiles|Where-Object { $_.Alias -ceq $Alias })
    if($profiles.Count -ne 1){throw "Unbekannter Modellalias: $Alias"}
    $profile=$profiles[0]
    $expectedPath=[string](Get-LrProperty $profile 'ExpectedPath')
    if($expectedPath){Assert-LrSelectedModel -LmsPath $Pool.LmsPath -LogDirectory $LogDirectory -ExpectedPath $expectedPath -ModelPath $profile.ModelPath}
    Restore-SmpPendingOwnership -InstallRoot $InstallRoot -Pool $Pool -Owner $Owner -LogDirectory $LogDirectory
    $loaded=@(Get-SmpOwnedLoaded -Pool $Pool -Owner $Owner -LogDirectory $LogDirectory)
    $allowOffload=Get-LrProperty $Pool 'AllowPartialGpuOffload' $false
    $ownerEntry=@($Owner.Entries|Where-Object {$_.InstanceId -ceq $profile.InstanceId})
    $priorGpu=if($ownerEntry.Count -eq 1){[string](Get-LrProperty $ownerEntry[0] 'GpuOffload')}else{''}
    if($loaded.Count -eq 1 -and (Get-LrProperty $loaded[0] 'identifier') -ceq $profile.InstanceId -and
       (Get-LrProperty $loaded[0] 'path') -ceq $profile.ModelPath -and
       [int](Get-LrProperty $loaded[0] 'contextLength' 0) -eq [int]$profile.ContextLength -and [int](Get-LrProperty $loaded[0] 'parallel' 0) -eq 1 -and
       ($allowOffload -or $priorGpu -notin @('0.8','0.6'))){
        return Test-SmpLoadedProfile -Pool $Pool -Profile $profile -Owner $Owner -LogDirectory $LogDirectory
    }
    foreach($instance in $loaded){Remove-SmpOwnedInstance -Pool $Pool -Owner $Owner -InstanceId (Get-LrProperty $instance 'identifier') -LogDirectory $LogDirectory}
    $contexts=@([int]$profile.ContextLength)
    if($AllowContextFallback -and $profile.ContextLength -gt 16384){$contexts+=16384}
    if($allowOffload -and $AllowContextFallback -and $profile.ContextLength -gt 8192){$contexts+=8192}
    $gpuOptions=if($allowOffload){@('max','0.8','0.6')}else{@('max')}
    $fit=$null;$guardrailCandidate=$null;$lastCandidate=$null
    foreach($gpu in $gpuOptions){
      foreach($context in ($contexts|Select-Object -Unique)){
        if($expectedPath){Assert-LrSelectedModel -LmsPath $Pool.LmsPath -LogDirectory $LogDirectory -ExpectedPath $expectedPath -ModelPath $profile.ModelPath}
        $estimate=Invoke-LrNative -FilePath $Pool.LmsPath -Arguments @('load',$profile.ModelPath,'--exact','--local','--context-length',"$context",'--parallel','1','--gpu',$gpu,'--estimate-only','--yes') -LogDirectory $LogDirectory
        $text=$estimate.Stdout+"`n"+$estimate.Stderr
        $gpuBytes=Convert-LrEstimatedBytes -Text $text -Label 'Estimated GPU Memory'
        $totalBytes=Convert-LrEstimatedBytes -Text $text -Label 'Estimated Total Memory'
        $hardware=Get-LocalNvidiaGpu -LogDirectory $LogDirectory
        $candidate=[pscustomobject]@{ContextLength=$context;GpuOffload=$gpu;GpuBytes=$gpuBytes;TotalBytes=$totalBytes;LogPath=$estimate.LogPath;ReserveOverride=$false}
        $lastCandidate=$candidate
        if(-not $guardrailCandidate -and $text -match 'This model may be loaded based on your resource guardrails settings\.'){
            $guardrailCandidate=$candidate
        }
        if($text -match 'This model may be loaded based on your resource guardrails settings\.' -and $text -notmatch 'Confidence:\s*LOW' -and
           $gpuBytes -le ($hardware.Gpu.FreeBytes-1GB) -and $totalBytes -le ($hardware.FreeRamBytes-3GB)){
            $fit=$candidate;break
        }
      }
      if($fit){break}
    }
    if(-not $fit){
        $freeGpu=[math]::Round($hardware.Gpu.FreeBytes/1GB,2)
        $freeRam=[math]::Round($hardware.FreeRamBytes/1GB,2)
        $fitMessage="Kein gepruefter Speicherfit fuer $Alias. Zuletzt frei: VRAM $freeGpu GiB, RAM $freeRam GiB; Reserven: 1 GiB VRAM und 3 GiB RAM. Letzte Schaetzung: $gpuBytes Bytes GPU, $totalBytes Bytes gesamt. LM-Studio-Schaetzungen: $LogDirectory."
        if(-not $AllowUnfitAttempt){
            $error=[InvalidOperationException]::new($fitMessage)
            $error.Data['ShadowResourceFitFailure']=$true
            throw $error
        }
        $fit=if($guardrailCandidate){$guardrailCandidate}else{$lastCandidate}
        if(-not $fit){throw 'Keine auswertbare LM-Studio-Speicherschaetzung vorhanden.'}
        $fit.ReserveOverride=$true
        Write-Warning "$fitMessage Ladeversuch ohne LoKiEnte-Reserve; LM-Studio-Schutzregeln bleiben aktiv."
    }
    $profile.ContextLength=[int]$fit.ContextLength
    $profile.OutputLimit=[math]::Min(8192,[int]($profile.ContextLength/4))
    $profile.Estimate=$fit
    if(@(Get-SmpOwnedLoaded -Pool $Pool -Owner $Owner -LogDirectory $LogDirectory).Count){
        throw 'Waehrend der Speicherschaetzung wurde eine Modellinstanz geladen. Kein weiterer Ladevorgang gestartet.'
    }
    if($expectedPath){Assert-LrSelectedModel -LmsPath $Pool.LmsPath -LogDirectory $LogDirectory -ExpectedPath $expectedPath -ModelPath $profile.ModelPath}
    $variant=[string](Get-LrProperty $profile 'SelectedVariant')
    Save-SmpOwnership -InstallRoot $InstallRoot -Owner $Owner -InstanceId $profile.InstanceId -ModelPath $profile.ModelPath -ExpectedPath $expectedPath -SelectedVariant $variant -GpuOffload $fit.GpuOffload -Pending
    Write-Host "Lade verwaltetes Modell $Alias mit $($profile.ContextLength) Tokens und GPU-Offload $($fit.GpuOffload) ..."
    $loadArguments=@('load',$profile.ModelPath,'--exact','--local','--context-length',"$($profile.ContextLength)",'--parallel','1','--gpu',$fit.GpuOffload,'--identifier',$profile.InstanceId,'--yes')
    if($fit.ReserveOverride){
        $load=Invoke-LrNative -FilePath $Pool.LmsPath -Arguments $loadArguments -LogDirectory $LogDirectory -TimeoutSeconds 900 -AllowFailure
        $loadExit=Get-LrProperty $load 'ExitCode'
        if($loadExit -isnot [int] -and $loadExit -isnot [long]){throw 'LM Studio lieferte keinen auswertbaren Exitcode fuer den Ladeversuch.'}
        if($loadExit -ne 0){
            $error=[InvalidOperationException]::new("$fitMessage LM Studio hat den Ladeversuch abgelehnt (Exitcode $($load.ExitCode)); Modell bleibt heruntergeladen. Details: $($load.LogPath)")
            $error.Data['ShadowResourceFitFailure']=$true
            throw $error
        }
    }else{
        $null=Invoke-LrNative -FilePath $Pool.LmsPath -Arguments $loadArguments -LogDirectory $LogDirectory -TimeoutSeconds 900
    }
    $result=Test-SmpLoadedProfile -Pool $Pool -Profile $profile -Owner $Owner -LogDirectory $LogDirectory
    Save-SmpOwnership -InstallRoot $InstallRoot -Owner $Owner -InstanceId $profile.InstanceId -ModelPath $profile.ModelPath -ExpectedPath $expectedPath -SelectedVariant $variant -GpuOffload $fit.GpuOffload
    return $result
}

function Get-SmpModelDefinitions {
    param([Parameter(Mandatory)]$Hardware,[switch]$IncludeFastModel)
    $fastDefinition=@{
        Name='Qwen9B';ExpectedPath='lmstudio-community/Qwen3.5-9B-GGUF/Qwen3.5-9B-Q4_K_M.gguf'
        DownloadUrl='https://huggingface.co/lmstudio-community/Qwen3.5-9B-GGUF/blob/main/Qwen3.5-9B-Q4_K_M.gguf'
    }
    $definitions=@(
        @{Alias='coder-high';Name='Qwen3.8-27B Q4_K_M';Definition=(Select-LrProfile -PreferredModel Qwen27B -Hardware $Hardware)},
        @{Alias='coder-fast';Name='Qwen3.5-9B Q4_K_M';Definition=$fastDefinition},
        @{Alias='review';Name='gpt-oss-20b MXFP4';Definition=(Select-LrProfile -PreferredModel GptOss20B -Hardware $Hardware)}
    )
    if($IncludeFastModel){$definitions+=@{Alias='fast';Name='Qwen3.5-9B Q4_K_M';Definition=$fastDefinition}}
    return $definitions
}

function Invoke-SmpProfileCheck {
    param([string]$InstallRoot,$Pool,$Owner,$Profile,[string]$LogDirectory,[switch]$AllowContextFallback)
    try {
        $null=Set-SmpActiveProfile -InstallRoot $InstallRoot -Pool $Pool -Owner $Owner -Alias $Profile.Alias -LogDirectory $LogDirectory -AllowContextFallback:$AllowContextFallback -AllowUnfitAttempt:(Get-LrProperty $Pool 'AllowUnfitAttempt' $false)
    } catch {
        if(-not $_.Exception.Data['ShadowResourceFitFailure']){throw}
        $Profile.SmokeTests=[pscustomobject]@{Chat='NotRun';ToolCall='NotRun';ToolResultRoundTrip='NotRun'}
        $Profile.VerificationState='Deferred'
        $Profile.VerificationMessage=$_.Exception.Message
        Write-Warning "Modell $($Profile.Alias) bleibt heruntergeladen und noch ungeprueft: $($Profile.VerificationMessage)"
        return
    }
    try {
        $Profile.SmokeTests=Test-LrModelInference -ApiBaseUrl $Pool.BackendApiBaseUrl -ModelId $Profile.InstanceId -Headers (Get-LrApiHeaders $Pool.ApiTokenEnvironmentVariable)
        foreach($key in @('Chat','ToolCall','ToolResultRoundTrip')){
            if((Get-LrProperty $Profile.SmokeTests $key) -cne 'Passed'){throw "Modelltest $key wurde nicht bestanden."}
        }
        $Profile.VerificationState='Verified'
        $Profile.VerificationMessage=''
    } catch {
        $Profile.SmokeTests=[pscustomobject]@{Chat='NotVerified';ToolCall='NotVerified';ToolResultRoundTrip='NotVerified'}
        $Profile.VerificationState='Deferred'
        $Profile.VerificationMessage=$_.Exception.Message
        Write-Warning "Modell $($Profile.Alias) bleibt heruntergeladen; der Modelltest ist nicht bestanden: $($Profile.VerificationMessage)"
    }
}

function Configure-LocalModelPool {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$InstallRoot,
        [ValidateRange(8192,65536)][int]$ContextLength=32768,
        [ValidateRange(1024,65535)][int]$Port=1234,
        [ValidateRange(1024,65535)][int]$RouterPort=1235,
        [switch]$IncludeFastModel,
        [switch]$AllowPartialGpuOffload,
        [switch]$AllowUnfitAttempt,
        [object[]]$SelectedDefinitions,
        [bool]$DownloadModel=$true,
        [string]$LmsPath,
        [string]$ApiTokenEnvironmentVariable='LOKIENTE_LM_API_KEY',
        [string]$LegacyModelKey
    )
    if(-not $IsWindows){throw 'Der Modellpool ist fuer Windows mit NVIDIA-GPU vorgesehen.'}
    if($LegacyModelKey){throw 'Ein explizites LegacyModelKey gehoert zum Einmodellprofil. Im Mehrmodellprofil werden die geprueften Katalogdateien verwendet.'}
    $lock=Enter-SmpLock -InstallRoot $InstallRoot
    try {
        $owner=Get-SmpOwner -InstallRoot $InstallRoot
        $logs=Join-Path $InstallRoot 'runtime/pool-logs'
        $lms=Resolve-LocalLmsCommand -LmsPath $LmsPath
        Assert-LrLoadCapabilities -LmsPath $lms -LogDirectory $logs
        $hardware=Get-LocalNvidiaGpu -LogDirectory $logs
        $definitions=if($SelectedDefinitions){@($SelectedDefinitions)}else{@(Get-SmpModelDefinitions -Hardware $hardware -IncludeFastModel:$IncludeFastModel)}
        $server=Invoke-LrJson -LmsPath $lms -Arguments @('server','status','--json') -LogDirectory $logs
        if([bool](Get-LrProperty $server 'running' $false)){$Port=[int](Get-LrProperty $server 'port' 0)}
        if($Port -lt 1024 -or $Port -eq $RouterPort){throw 'Backend- und Routerport muessen verschiedene gueltige Ports sein.'}
        $primary=if(@($definitions|Where-Object {$_.Alias -ceq 'coder'}).Count){'coder'}else{'coder-high'}
        $pool=[pscustomobject]@{
            SchemaVersion=2;Status='Provisioning';OwnerId=$owner.OwnerId;PrimaryAlias=$primary
            BackendApiBaseUrl="http://127.0.0.1:$Port/v1";RouterApiBaseUrl="http://127.0.0.1:$RouterPort/v1"
            LmsPath=$lms;ApiTokenEnvironmentVariable=$ApiTokenEnvironmentVariable;Profiles=@()
            Hardware=$hardware;InferenceEngine=$null;ContextLength=$ContextLength;Parallel=1;AllowPartialGpuOffload=[bool]$AllowPartialGpuOffload
            AllowUnfitAttempt=[bool]$AllowUnfitAttempt
            CheckedAtUtc=$null;LogsPath=$logs
        }
        Ensure-SmpServer -Pool $pool -LogDirectory $logs
        Restore-SmpPendingOwnership -InstallRoot $InstallRoot -Pool $pool -Owner $owner -LogDirectory $logs
        $null=@(Get-SmpOwnedLoaded -Pool $pool -Owner $owner -LogDirectory $logs)
        $pool.InferenceEngine=Ensure-LrInferenceEngine -LmsPath $lms -LogDirectory $logs
        foreach($item in $definitions){
            $models=@(Get-LrDownloadedModels -LmsPath $lms -LogDirectory $logs)
            $model=Find-LrModel -Models $models -Profile $item.Definition
            if(-not $model){
                if(-not $DownloadModel){throw "Modell $($item.Name) fehlt; Modelldownload wurde deaktiviert."}
                Write-Host "Lade exakte Modelldatei fuer $($item.Alias): $($item.Name) ..."
                $null=Invoke-LrNative -FilePath $lms -Arguments @('get',$item.Definition.DownloadUrl,'--gguf','--yes') -LogDirectory $logs -TimeoutSeconds 14400
                $model=Find-LrModel -Models @(Get-LrDownloadedModels -LmsPath $lms -LogDirectory $logs) -Profile $item.Definition
                if(-not $model){throw 'Heruntergeladenes Modell wurde lokal nicht exakt wiedergefunden.'}
            }
            $pool.Profiles+=@([pscustomobject]@{
                Alias=$item.Alias;Name=$item.Name;RouteId=('shadow-'+$item.Alias);InstanceId=('shadow-'+$owner.OwnerId+'-'+$item.Alias)
                ModelPath=[string](Get-LrProperty $model 'path');ModelKey=[string](Get-LrProperty $model 'modelKey')
                ExpectedPath=[string]$item.Definition.ExpectedPath
                SelectedVariant=[string](Get-LrProperty $model 'selectedVariant')
                Interleaved=[string](Get-LrProperty $item.Definition 'Interleaved')
                ContextLength=$ContextLength;OutputLimit=[math]::Min(8192,[int]($ContextLength/4));Parallel=1
                Estimate=$null;SmokeTests=$null;VerificationState='Pending';VerificationMessage=''
            })
        }
        Assert-SmpPool -Pool $pool
        $path=Join-Path $InstallRoot 'runtime/model-pool.json'
        Write-SmpJson -Path $path -Value $pool -InstallRoot $InstallRoot
        foreach($profile in $pool.Profiles){
            Invoke-SmpProfileCheck -InstallRoot $InstallRoot -Pool $pool -Owner $owner -Profile $profile -LogDirectory $logs -AllowContextFallback
            Write-SmpJson -Path $path -Value $pool -InstallRoot $InstallRoot
        }
        # A single compaction model must fit any active role's context. Use the
        # tested minimum consistently rather than advertise mismatched windows.
        $common=[int](($pool.Profiles|Measure-Object -Property ContextLength -Minimum).Minimum)
        foreach($profile in $pool.Profiles){
            if($profile.ContextLength -ne $common){
                $profile.ContextLength=$common;$profile.OutputLimit=[math]::Min(8192,[int]($common/4))
                Invoke-SmpProfileCheck -InstallRoot $InstallRoot -Pool $pool -Owner $owner -Profile $profile -LogDirectory $logs
            }
        }
        $primaryProfile=@($pool.Profiles|Where-Object {$_.Alias -ceq $pool.PrimaryAlias})[0]
        if($primaryProfile.VerificationState -ceq 'Verified'){
            try{
                $null=Set-SmpActiveProfile -InstallRoot $InstallRoot -Pool $pool -Owner $owner -Alias $pool.PrimaryAlias -LogDirectory $logs -AllowUnfitAttempt:$AllowUnfitAttempt
            }catch{
                if(-not $_.Exception.Data['ShadowResourceFitFailure']){throw}
                $primaryProfile.SmokeTests=[pscustomobject]@{Chat='NotRun';ToolCall='NotRun';ToolResultRoundTrip='NotRun'}
                $primaryProfile.VerificationState='Deferred'
                $primaryProfile.VerificationMessage=$_.Exception.Message
                Write-Warning "Hauptmodell bleibt heruntergeladen und noch ungeprueft: $($primaryProfile.VerificationMessage)"
            }
        }
        $pool.ContextLength=$common;$pool.Status='Ready';$pool.CheckedAtUtc=[DateTime]::UtcNow.ToString('o')
        $verification=if(@($pool.Profiles|Where-Object {$_.VerificationState -cne 'Verified'}).Count){'Partial'}else{'Verified'}
        $pool|Add-Member -NotePropertyName VerificationStatus -NotePropertyValue $verification -Force
        Write-SmpJson -Path $path -Value $pool -InstallRoot $InstallRoot
        return $pool
    } finally {$lock.Dispose()}
}

function Switch-ShadowLocalModel {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$InstallRoot,[ValidateSet('coder','coder-high','coder-fast','review','fast')][string]$Alias='coder-high')
    $lock=Enter-SmpLock -InstallRoot $InstallRoot
    try {
        $pool=Get-Content -LiteralPath (Join-Path $InstallRoot 'runtime/model-pool.json') -Raw|ConvertFrom-Json
        Assert-SmpPool -Pool $pool -RequireReady
        $owner=Get-SmpOwner -InstallRoot $InstallRoot
        if($pool.OwnerId -cne $owner.OwnerId){throw 'Modellpool und Eigentumsnachweis gehoeren nicht zusammen.'}
        $logs=Join-Path $InstallRoot 'runtime/pool-logs'
        Ensure-SmpServer -Pool $pool -LogDirectory $logs
        $profiles=@($pool.Profiles|Where-Object {$_.Alias -ceq $Alias})
        if($profiles.Count -ne 1){throw "Unbekannter oder mehrdeutiger Modellalias: $Alias"}
        $profile=$profiles[0]
        try {
            $result=Set-SmpActiveProfile -InstallRoot $InstallRoot -Pool $pool -Owner $owner -Alias $Alias -LogDirectory $logs -AllowUnfitAttempt:(Get-LrProperty $pool 'AllowUnfitAttempt' $false)
        } catch {
            if($_.Exception.Data['ShadowResourceFitFailure']){
                $profile|Add-Member -NotePropertyName VerificationState -NotePropertyValue 'Deferred' -Force
                $profile|Add-Member -NotePropertyName VerificationMessage -NotePropertyValue $_.Exception.Message -Force
                $profile.SmokeTests=[pscustomobject]@{Chat='NotRun';ToolCall='NotRun';ToolResultRoundTrip='NotRun'}
                $pool|Add-Member -NotePropertyName VerificationStatus -NotePropertyValue 'Partial' -Force
                Write-SmpJson -Path (Join-Path $InstallRoot 'runtime/model-pool.json') -Value $pool -InstallRoot $InstallRoot
            }
            throw
        }
        if((Get-LrProperty $profile 'VerificationState') -ceq 'Deferred'){
            try {
                $tests=Test-LrModelInference -ApiBaseUrl $pool.BackendApiBaseUrl -ModelId $profile.InstanceId -Headers (Get-LrApiHeaders $pool.ApiTokenEnvironmentVariable)
                foreach($key in @('Chat','ToolCall','ToolResultRoundTrip')){
                    if((Get-LrProperty $tests $key) -cne 'Passed'){throw "Modelltest $key wurde nicht bestanden."}
                }
                $profile.SmokeTests=$tests
                $profile.VerificationState='Verified'
                $profile.VerificationMessage=''
            } catch {
                $profile.SmokeTests=[pscustomobject]@{Chat='NotVerified';ToolCall='NotVerified';ToolResultRoundTrip='NotVerified'}
                $profile.VerificationMessage=$_.Exception.Message
                Write-SmpJson -Path (Join-Path $InstallRoot 'runtime/model-pool.json') -Value $pool -InstallRoot $InstallRoot
                $error=[InvalidOperationException]::new("Modell $Alias wurde geladen, aber der Modelltest ist nicht bestanden: $($_.Exception.Message)")
                $error.Data['ShadowModelVerificationFailure']=$true
                throw $error
            }
        }
        foreach($key in @('Chat','ToolCall','ToolResultRoundTrip')){
            if((Get-LrProperty $profile.SmokeTests $key) -cne 'Passed'){
                $error=[InvalidOperationException]::new("Modell $Alias hat keinen nachweislich bestandenen Modelltest.")
                $error.Data['ShadowModelVerificationFailure']=$true
                throw $error
            }
        }
        $verification=if(@($pool.Profiles|Where-Object {(Get-LrProperty $_ 'VerificationState') -ceq 'Deferred'}).Count){'Partial'}else{'Verified'}
        $pool|Add-Member -NotePropertyName VerificationStatus -NotePropertyValue $verification -Force
        Write-SmpJson -Path (Join-Path $InstallRoot 'runtime/model-pool.json') -Value $pool -InstallRoot $InstallRoot
        $result|Add-Member -NotePropertyName VerificationState -NotePropertyValue 'Verified' -Force
        return $result
    } finally {$lock.Dispose()}
}

function Start-LocalModelPool {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$InstallRoot)
    $pool=Get-Content -LiteralPath (Join-Path $InstallRoot 'runtime/model-pool.json') -Raw|ConvertFrom-Json
    Assert-SmpPool -Pool $pool -RequireReady
    $lock=Enter-SmpLock -InstallRoot $InstallRoot
    try {
        $owner=Get-SmpOwner -InstallRoot $InstallRoot
        if($owner.OwnerId -cne $pool.OwnerId){throw 'Modellpool und Eigentumsnachweis gehoeren nicht zusammen.'}
        $logs=Join-Path $InstallRoot 'runtime/pool-logs'
        Ensure-SmpServer -Pool $pool -LogDirectory $logs
        Restore-SmpPendingOwnership -InstallRoot $InstallRoot -Pool $pool -Owner $owner -LogDirectory $logs
        $null=@(Get-SmpOwnedLoaded -Pool $pool -Owner $owner -LogDirectory $logs)
        return $pool
    } finally {$lock.Dispose()}
}

function Start-ShadowEmbeddingModel {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$InstallRoot,[Parameter(Mandatory)]$Pool,[Parameter(Mandatory)]$Definition,[switch]$AllowUnfitAttempt)
    Assert-SmpPool -Pool $Pool -RequireReady
    $lock=Enter-SmpLock -InstallRoot $InstallRoot
    try {
        $owner=Get-SmpOwner -InstallRoot $InstallRoot
        if($owner.OwnerId -cne $Pool.OwnerId){throw 'Modellpool und Eigentumsnachweis gehoeren nicht zusammen.'}
        $logs=Join-Path $InstallRoot 'runtime/pool-logs'
        Ensure-SmpServer -Pool $Pool -LogDirectory $logs
        Restore-SmpPendingOwnership -InstallRoot $InstallRoot -Pool $Pool -Owner $owner -LogDirectory $logs
        $model=Find-LrModel -Models @(Get-LrDownloadedModels -LmsPath $Pool.LmsPath -LogDirectory $logs -Type embedding) -Profile $Definition
        if(-not $model){throw 'Das gepruefte lokale Embeddingmodell ist in LM Studio nicht registriert.'}
        $file=$Definition.Files[0]
        $modelFile=Join-Path (Join-Path (Resolve-ShadowModelDirectory) $Definition.Repository.Replace('/','\')) $file.Name
        if(-not(Test-ShadowModelFile -Path $modelFile -Size $file.Size -Sha256 $file.Sha256)){
            throw 'Embeddingdatei stimmt nicht mit dem geprueften Katalog ueberein. Sie bleibt unveraendert.'
        }
        $path=[string](Get-LrProperty $model 'path')
        $id='shadow-'+$owner.OwnerId+'-embedding'
        $null=@(Get-SmpOwnedLoaded -Pool $Pool -Owner $owner -LogDirectory $logs)
        $entries=@($owner.Entries|Where-Object {$_.InstanceId -ceq $id})
        if($entries.Count -gt 1 -or ($entries.Count -eq 1 -and ($entries[0].ModelPath -cne $path -or
           (Get-LrProperty $entries[0] 'Origin') -cnotin @('verified-cpu-embedding','pending-cpu-embedding')))){
            throw 'Embedding-Eigentuemerdatei stimmt nicht mit dem lokalen Modell ueberein. Keine Instanz wird veraendert.'
        }
        $loaded=@(Invoke-LrJson -LmsPath $Pool.LmsPath -Arguments @('ps','--json') -LogDirectory $logs)
        $instances=@($loaded|Where-Object {(Get-LrProperty $_ 'identifier') -ceq $id})
        $reserveOverride=$false
        if(-not $instances.Count){
            $estimate=Invoke-LrNative -FilePath $Pool.LmsPath -Arguments @('load',$path,'--exact','--local','--context-length','2048','--gpu','off','--estimate-only','--yes') -LogDirectory $logs
            $text=$estimate.Stdout+"`n"+$estimate.Stderr
            $total=Convert-LrEstimatedBytes -Text $text -Label 'Estimated Total Memory'
            $hardware=Get-LocalNvidiaGpu -LogDirectory $logs
            if($text -notmatch 'This model may be loaded based on your resource guardrails settings\.' -or $text -match 'Confidence:\s*LOW' -or
               $total -gt ($hardware.FreeRamBytes-3GB)){
                if(-not $AllowUnfitAttempt){
                    $error=[InvalidOperationException]::new('Kein gepruefter RAM-Fit fuer das CPU-Embeddingmodell mit 3 GiB Reserve. Keine weitere Instanz wurde geladen.')
                    $error.Data['ShadowResourceFitFailure']=$true
                    throw $error
                }
                $reserveOverride=$true
                Write-Warning 'Kein gepruefter RAM-Fit fuer das CPU-Embeddingmodell. Ladeversuch ohne LoKiEnte-Reserve; LM-Studio-Schutzregeln bleiben aktiv.'
            }
            $owner.Entries=@($owner.Entries|Where-Object {$_.InstanceId -cne $id})+@(
                [pscustomobject]@{InstanceId=$id;ModelPath=$path;Verified=$false;Origin='pending-cpu-embedding';ExpectedPath=$Definition.ExpectedPath;SelectedVariant='';GpuOffload='off'}
            )
            Write-SmpJson -Path (Join-Path $InstallRoot 'runtime/model-ownership.json') -Value $owner -InstallRoot $InstallRoot
            Write-Host 'Lade das lokale Embeddingmodell ausschliesslich auf der CPU ...'
            $loadArguments=@('load',$path,'--exact','--local','--context-length','2048','--gpu','off','--identifier',$id,'--yes')
            if($reserveOverride){
                $load=Invoke-LrNative -FilePath $Pool.LmsPath -Arguments $loadArguments -LogDirectory $logs -TimeoutSeconds 900 -AllowFailure
                $loadExit=Get-LrProperty $load 'ExitCode'
                if($loadExit -isnot [int] -and $loadExit -isnot [long]){throw 'LM Studio lieferte keinen auswertbaren Exitcode fuer den Embedding-Ladeversuch.'}
                if($loadExit -ne 0){
                    $error=[InvalidOperationException]::new("Kein gepruefter RAM-Fit fuer das CPU-Embeddingmodell; LM Studio hat den Ladeversuch abgelehnt (Exitcode $loadExit). Details: $($load.LogPath)")
                    $error.Data['ShadowResourceFitFailure']=$true
                    throw $error
                }
            }else{
                $null=Invoke-LrNative -FilePath $Pool.LmsPath -Arguments $loadArguments -LogDirectory $logs -TimeoutSeconds 900
            }
            Restore-SmpPendingOwnership -InstallRoot $InstallRoot -Pool $Pool -Owner $owner -LogDirectory $logs
            $instances=@(Invoke-LrJson -LmsPath $Pool.LmsPath -Arguments @('ps','--json') -LogDirectory $logs|Where-Object {(Get-LrProperty $_ 'identifier') -ceq $id})
        }

        if($instances.Count -ne 1 -or (Get-LrProperty $instances[0] 'type') -cne 'embedding' -or
           (Get-LrProperty $instances[0] 'path') -cne $path -or $null -ne (Get-LrProperty $instances[0] 'deviceIdentifier' '__unknown__') -or
           [int](Get-LrProperty $instances[0] 'contextLength' 0) -ne 2048){
            throw 'Geladene Embeddinginstanz ist nicht eindeutig verifiziert. Sie bleibt unveraendert.'
        }
        try {
            $headers=Get-LrApiHeaders -ApiTokenEnvironmentVariable $Pool.ApiTokenEnvironmentVariable
            $response=Invoke-LrApi -Uri ($Pool.BackendApiBaseUrl+'/embeddings') -Headers $headers -Method POST -Body @{
                model=$id;input=@('local embedding test','local source search');encoding_format='base64'
            } -TimeoutSeconds 60
            $data=@(Get-LrProperty $response 'data' @())
            if($data.Count -ne 2){throw 'Embedding-Smoke-Test lieferte nicht zwei Vektoren.'}
            $indexes=[Collections.Generic.HashSet[int]]::new()
            foreach($item in $data){
                $index=Get-LrProperty $item 'index'
                if($index -isnot [int] -and $index -isnot [long]){throw 'Embedding-Smoke-Test lieferte keinen gueltigen Vektorindex.'}
                if($index -notin @(0,1) -or -not $indexes.Add([int]$index)){throw 'Embedding-Smoke-Test lieferte doppelte oder ungueltige Vektorindizes.'}
                $vector=Get-LrProperty $item 'embedding'
                if($vector -is [string]){
                    try{$bytes=[Convert]::FromBase64String($vector)}catch{throw 'Embedding-Smoke-Test lieferte ungueltiges Base64.'}
                    if($bytes.Length -ne 3072){throw 'Embedding-Smoke-Test lieferte eine unerwartete Vektordimension.'}
                    $vector=@(for($i=0;$i -lt $bytes.Length;$i+=4){[BitConverter]::ToSingle($bytes,$i)})
                }elseif($vector -is [array]){
                    if($vector.Count -ne 768){throw 'Embedding-Smoke-Test lieferte eine unerwartete Vektordimension.'}
                }else{throw 'Embedding-Smoke-Test lieferte kein Vektorarray.'}
                $nonzero=$false
                foreach($value in $vector){
                    if($value -isnot [int] -and $value -isnot [long] -and $value -isnot [float] -and $value -isnot [double] -and $value -isnot [decimal]){throw 'Embedding-Smoke-Test lieferte einen ungueltigen Vektorwert.'}
                    if(-not [double]::IsFinite([double]$value)){throw 'Embedding-Smoke-Test lieferte einen ungueltigen Vektorwert.'}
                    if([double]$value -ne 0){$nonzero=$true}
                }
                if(-not $nonzero){throw 'Embedding-Smoke-Test lieferte einen Nullvektor.'}
            }
        } catch {
            if($_.Exception.Message -match '^LM-Studio-API verweigert den Zugriff'){throw}
            $error=[InvalidOperationException]::new("Embedding-Smoke-Test fehlgeschlagen: $($_.Exception.Message)")
            $error.Data['ShadowEmbeddingVerificationFailure']=$true
            throw $error
        }
        return [pscustomobject]@{Status='Ready';InstanceId=$id;ModelPath=$path;Dimension=768;Device='CPU';SmokeTest='Passed';ReserveOverride=$reserveOverride}
    } finally {$lock.Dispose()}
}

function Initialize-ShadowEmbeddingModel {
    param([Parameter(Mandatory)][string]$InstallRoot,[Parameter(Mandatory)]$Pool,[Parameter(Mandatory)]$Definition)
    try {
        return Start-ShadowEmbeddingModel -InstallRoot $InstallRoot -Pool $Pool -Definition $Definition -AllowUnfitAttempt:(Get-LrProperty $Pool 'AllowUnfitAttempt' $false)
    } catch {
        if(-not $_.Exception.Data['ShadowResourceFitFailure'] -and -not $_.Exception.Data['ShadowEmbeddingVerificationFailure']){throw}
        Write-Warning "Lokale Indexierung ist noch nicht betriebsbereit: $($_.Exception.Message) Modell bleibt heruntergeladen."
        $smoke=if($_.Exception.Data['ShadowEmbeddingVerificationFailure']){'Failed'}else{'NotRun'}
        return [pscustomobject]@{Status='Deferred';InstanceId=('shadow-'+$Pool.OwnerId+'-embedding');ModelPath=$Definition.ExpectedPath;Dimension=768;Device='CPU';SmokeTest=$smoke;Message=$_.Exception.Message}
    }
}
