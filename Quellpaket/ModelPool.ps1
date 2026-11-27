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
            if($watch.Elapsed.TotalSeconds -ge $TimeoutSeconds){throw 'Another process is managing the model pool. No parallel model switch performed.'}
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
            throw 'Unknown model ownership file. Existing instances are preserved.'
        }
        if($null -eq $owner.PSObject.Properties['Entries'] -or $owner.Entries -isnot [array]){
            throw 'Model ownership file has no valid entries list.'
        }
        $ids=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach($entry in $owner.Entries){
            if((Get-LrProperty $entry 'Verified') -isnot [bool] -or -not(Get-LrProperty $entry 'InstanceId') -or
               -not(Get-LrProperty $entry 'ModelPath') -or -not $ids.Add([string]$entry.InstanceId)){
                throw 'Model ownership file contains incomplete or duplicate entries.'
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
    if($embeddingPending.Count -gt 1){throw 'Ambiguous pending embedding instances. No instance will be adopted.'}
    if($embeddingPending.Count){
        $entry=$embeddingPending[0]
        if($entry.InstanceId -cne ('shadow-'+$Owner.OwnerId+'-embedding')){throw 'Unknown embedding load request. No instance will be adopted.'}
        $instances=@(Invoke-LrJson -LmsPath $Pool.LmsPath -Arguments @('ps','--json') -LogDirectory $LogDirectory)
        $matches=@($instances|Where-Object {(Get-LrProperty $_ 'identifier') -ceq $entry.InstanceId})
        if($matches.Count){
            if($matches.Count -ne 1 -or (Get-LrProperty $matches[0] 'type') -cne 'embedding' -or
               (Get-LrProperty $matches[0] 'path') -cne $entry.ModelPath -or
               $null -ne (Get-LrProperty $matches[0] 'deviceIdentifier' '__unknown__') -or
               [int](Get-LrProperty $matches[0] 'contextLength' 0) -ne 2048){
                throw 'Pending embedding instance does not match its load request. It remains unchanged.'
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
            throw 'Unknown pending load request. No model instance will be adopted.'
        }
        $matches=@($loaded|Where-Object { (Get-LrProperty $_ 'identifier') -ceq $entry.InstanceId })
        if(-not $matches.Count){continue}
        if($matches.Count -ne 1 -or (Get-LrProperty $matches[0] 'path') -cne $entry.ModelPath -or
           $null -ne (Get-LrProperty $matches[0] 'deviceIdentifier' '__unknown__')){
            throw 'Pending load request does not match the local instance. It remains unchanged.'
        }
        $variant=[string](Get-LrProperty $entry 'SelectedVariant')
        $expected=[string](Get-LrProperty $entry 'ExpectedPath')
        if($variant){
            if(-not $expected -or (Get-LrProperty $matches[0] 'selectedVariant') -cne $variant){
                throw 'Pending load request does not match the saved model variant. Instance remains unchanged.'
            }
            Assert-LrSelectedModel -LmsPath $Pool.LmsPath -LogDirectory $LogDirectory -ExpectedPath $expected -ModelPath $entry.ModelPath
        }
        # Ownership proves identity, not readiness. The ordinary idle/config checks still run.
        Save-SmpOwnership -InstallRoot $InstallRoot -Owner $Owner -InstanceId $entry.InstanceId -ModelPath $entry.ModelPath -ExpectedPath $expected -SelectedVariant $variant -GpuOffload ([string](Get-LrProperty $entry 'GpuOffload'))
        Write-ShadowMessage "Recognized owned load request $($entry.InstanceId). Model readiness will be checked again." 'WARN'
    }
}

function Assert-SmpPool {
    param($Pool,[switch]$RequireReady)
    if((Get-LrProperty $Pool 'SchemaVersion') -ne 2){throw 'Unknown model pool schema. Rerun provisioning.'}
    if($RequireReady -and (Get-LrProperty $Pool 'Status') -cne 'Ready'){throw 'Model pool has not been fully verified. Complete provisioning first.'}
    $allowOffload=Get-LrProperty $Pool 'AllowPartialGpuOffload' $false
    if($allowOffload -isnot [bool]){throw 'Invalid CPU offload option in model pool.'}
    $endpoint=[Uri]$Pool.BackendApiBaseUrl
    if(-not $endpoint.IsLoopback -or $endpoint.Scheme -ne 'http' -or $endpoint.AbsolutePath.TrimEnd('/') -cne '/v1' -or $endpoint.UserInfo -or $endpoint.Query -or $endpoint.Fragment){
        throw 'Model pool does not use an unambiguous local LM Studio endpoint.'
    }
    $router=[Uri]$Pool.RouterApiBaseUrl
    if(-not $router.IsLoopback -or $router.Scheme -ne 'http' -or $router.AbsolutePath.TrimEnd('/') -cne '/v1' -or
       $router.UserInfo -or $router.Query -or $router.Fragment -or $router.Port -lt 1024 -or $router.Port -eq $endpoint.Port){
        throw 'Model pool does not use an unambiguous local router endpoint with a separate port.'
    }
    $aliases=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $ids=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($profile in @($Pool.Profiles)){
        if($profile.Alias -notin @('coder','coder-high','coder-fast','review','fast') -or -not $aliases.Add([string]$profile.Alias) -or -not $ids.Add([string]$profile.InstanceId)){
            throw 'Ambiguous or unknown model pool role.'
        }
        if(-not $profile.ModelPath -or [int]$profile.ContextLength -lt 8192 -or [int]$profile.ContextLength -gt 65536){throw 'Incomplete model profile.'}
    }
    if(-not $aliases.Contains('review')){throw 'Model pool requires a review profile.'}
    if($aliases.Contains('coder')){
        if($aliases.Contains('coder-high') -or $aliases.Contains('coder-fast')){throw 'Legacy and new coder pools must not be mixed.'}
    }elseif(-not $aliases.Contains('coder-high') -or -not $aliases.Contains('coder-fast')){
        throw 'Model pool requires coder-high and coder-fast.'
    }
    $primary=[string](Get-LrProperty $Pool 'PrimaryAlias' $(if($aliases.Contains('coder')){'coder'}else{'coder-high'}))
    if($primary -cnotin @('coder','coder-high') -or -not $aliases.Contains($primary)){
        throw 'The primary model of the model pool is invalid.'
    }
}

function Ensure-SmpServer {
    param($Pool,[string]$LogDirectory)
    $server=Invoke-LrJson -LmsPath $Pool.LmsPath -Arguments @('server','status','--json') -LogDirectory $LogDirectory
    $port=([Uri]$Pool.BackendApiBaseUrl).Port
    if([bool](Get-LrProperty $server 'running' $false)){
        if([int](Get-LrProperty $server 'port' 0) -ne $port){throw 'LM Studio is running on another port. Preserve the existing server; rerun provisioning.'}
    } else {
        if(@(Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue).Count){throw "Port $port is occupied by another service."}
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
            throw 'Multiple instances use the managed embedding identifier. No instance will be changed.'
        }
        $busy=$false
        foreach($item in $loaded){
            if($null -ne (Get-LrProperty $item 'deviceIdentifier' '__unknown__')){
                throw 'A remote or not unambiguously local model instance is loaded. It will not be changed.'
            }
            $owned=@($Owner.Entries|Where-Object {
                $_.Verified -eq $true -and $_.InstanceId -ceq (Get-LrProperty $item 'identifier') -and $_.ModelPath -ceq (Get-LrProperty $item 'path')
            })
            if($owned.Count -ne 1){
                $error=[InvalidOperationException]::new('An external or unverified managed model is loaded. It will not be unloaded. Finish existing model work and unload it explicitly yourself.')
                $error.Data['ShadowModelConflict']=$true
                throw $error
            }
            if((Get-LrProperty $owned[0] 'Origin') -ceq 'verified-cpu-embedding'){
                if((Get-LrProperty $item 'type') -cne 'embedding' -or
                   (Get-LrProperty $item 'identifier') -cne ('shadow-'+$Owner.OwnerId+'-embedding')){
                    throw 'The managed embedding instance is not unique. It remains unchanged.'
                }
                continue
            }
            $ownedVariant=[string](Get-LrProperty $owned[0] 'SelectedVariant')
            if($ownedVariant -and (Get-LrProperty $item 'selectedVariant') -cne $ownedVariant){
                throw 'The loaded variant does not match the ownership record. The instance remains unchanged.'
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
        if($watch.Elapsed.TotalSeconds -ge $IdleTimeoutSeconds){
            $error=[InvalidOperationException]::new('Managed model is still working or cannot be verified as idle. No model was unloaded.')
            $error.Data['ShadowModelBusy']=$true
            throw $error
        }
        Start-Sleep -Milliseconds 500
    }
}

function Remove-SmpOwnedInstance {
    param($Pool,$Owner,[string]$InstanceId,[string]$LogDirectory)
    $loaded=@(Get-SmpOwnedLoaded -Pool $Pool -Owner $Owner -LogDirectory $LogDirectory)
    $target=@($loaded|Where-Object { (Get-LrProperty $_ 'identifier') -ceq $InstanceId })
    if($target.Count -eq 0){return}
    if($target.Count -ne 1){throw 'Model instance to unload is not unique.'}
    $headers=Get-LrApiHeaders -ApiTokenEnvironmentVariable $Pool.ApiTokenEnvironmentVariable
    $root=$Pool.BackendApiBaseUrl -replace '/v1/?$',''
    $response=Invoke-LrApi -Uri "$root/api/v1/models/unload" -Headers $headers -Method POST -Body @{instance_id=$InstanceId} -TimeoutSeconds 120
    if((Get-LrProperty $response 'instance_id') -cne $InstanceId){throw 'LM Studio did not unambiguously confirm the targeted unload.'}
    $after=@(Invoke-LrJson -LmsPath $Pool.LmsPath -Arguments @('ps','--json') -LogDirectory $LogDirectory)
    if(@($after|Where-Object { (Get-LrProperty $_ 'identifier') -ceq $InstanceId }).Count){throw 'Model instance remains visible after unloading.'}
}

function Test-SmpLoadedProfile {
    param($Pool,$Profile,$Owner,[string]$LogDirectory)
    Assert-LrLoopbackListener -Port ([Uri]$Pool.BackendApiBaseUrl).Port
    $ps=@(Invoke-LrJson -LmsPath $Pool.LmsPath -Arguments @('ps','--json') -LogDirectory $LogDirectory)
    if(@($ps|Where-Object {(Get-LrProperty $_ 'identifier') -ceq ('shadow-'+$Owner.OwnerId+'-embedding')}).Count -gt 1){
        throw 'Multiple instances use the managed embedding identifier. No instance will be changed.'
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
    if($matching.Count -ne 1 -or $ps.Count -ne 1 -or [int](Get-LrProperty $matching[0] 'parallel' 0) -ne 1){throw 'Cannot verify the exact local model instance and single inference slot.'}
    $variant=[string](Get-LrProperty $Profile 'SelectedVariant')
    if($variant -and (Get-LrProperty $matching[0] 'selectedVariant') -cne $variant){throw 'Loaded model variant does not match the verified profile.'}
    if($variant){Assert-LrSelectedModel -LmsPath $Pool.LmsPath -LogDirectory $LogDirectory -ExpectedPath $Profile.ExpectedPath -ModelPath $Profile.ModelPath}
    $root=$Pool.BackendApiBaseUrl -replace '/v1/?$',''
    $catalog=Invoke-LrApi -Uri "$root/api/v1/models" -Headers (Get-LrApiHeaders $Pool.ApiTokenEnvironmentVariable) -TimeoutSeconds 60
    $instances=@(foreach($model in @(Get-LrProperty $catalog 'models' @())){
        foreach($instance in @(Get-LrProperty $model 'loaded_instances' @())){
            if((Get-LrProperty $instance 'id') -ceq $Profile.InstanceId){$instance}
        }
    })
    if($instances.Count -ne 1){throw 'Loaded model instance cannot be uniquely verified through REST.'}
    $config=Get-LrProperty $instances[0] 'config'
    if([int](Get-LrProperty $config 'context_length' 0) -ne [int]$Profile.ContextLength -or [int](Get-LrProperty $config 'parallel' 0) -ne 1){
        throw 'Actual model context or concurrency differs from the verified profile.'
    }
    return [pscustomobject]@{Status='Ready';Alias=$Profile.Alias;ModelId=$Profile.InstanceId;InstanceId=$Profile.InstanceId;ContextLength=[int]$Profile.ContextLength;Parallel=1}
}

function Set-SmpActiveProfile {
    param([string]$InstallRoot,$Pool,$Owner,[string]$Alias,[string]$LogDirectory,[switch]$AllowContextFallback,[switch]$AllowUnfitAttempt)
    $profiles=@($Pool.Profiles|Where-Object { $_.Alias -ceq $Alias })
    if($profiles.Count -ne 1){throw "Unknown model alias: $Alias"}
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
        $estimate=Invoke-LrModelCommand -LmsPath $Pool.LmsPath -Arguments @('load',$profile.ModelPath,'--exact','--local','--context-length',"$context",'--parallel','1','--gpu',$gpu,'--estimate-only','--yes') -LogDirectory $LogDirectory
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
        $fitMessage="No verified memory fit for $Alias. Last available: VRAM $freeGpu GiB, RAM $freeRam GiB; reserves: 1 GiB VRAM and 3 GiB RAM. Last estimate: $gpuBytes bytes GPU, $totalBytes bytes total. LM Studio estimates: $LogDirectory."
        if(-not $AllowUnfitAttempt){
            $error=[InvalidOperationException]::new($fitMessage)
            $error.Data['ShadowResourceFitFailure']=$true
            throw $error
        }
        $fit=if($guardrailCandidate){$guardrailCandidate}else{$lastCandidate}
        if(-not $fit){throw 'No usable LM Studio memory estimate available.'}
        $fit.ReserveOverride=$true
        Write-Warning "$fitMessage Attempting load without LoKiEnte reserve; LM Studio safeguards remain active."
    }
    $profile.ContextLength=[int]$fit.ContextLength
    $profile.OutputLimit=[math]::Min(8192,[int]($profile.ContextLength/4))
    $profile.Estimate=$fit
    if(@(Get-SmpOwnedLoaded -Pool $Pool -Owner $Owner -LogDirectory $LogDirectory).Count){
        throw 'A model instance was loaded during memory estimation. No further load started.'
    }
    if($expectedPath){Assert-LrSelectedModel -LmsPath $Pool.LmsPath -LogDirectory $LogDirectory -ExpectedPath $expectedPath -ModelPath $profile.ModelPath}
    $variant=[string](Get-LrProperty $profile 'SelectedVariant')
    Save-SmpOwnership -InstallRoot $InstallRoot -Owner $Owner -InstanceId $profile.InstanceId -ModelPath $profile.ModelPath -ExpectedPath $expectedPath -SelectedVariant $variant -GpuOffload $fit.GpuOffload -Pending
    Write-Host "Loading managed model $Alias with $($profile.ContextLength) tokens and GPU offload $($fit.GpuOffload) ..."
    $loadArguments=@('load',$profile.ModelPath,'--exact','--local','--context-length',"$($profile.ContextLength)",'--parallel','1','--gpu',$fit.GpuOffload,'--identifier',$profile.InstanceId,'--yes')
    $null=Invoke-LrModelCommand -LmsPath $Pool.LmsPath -Arguments $loadArguments -LogDirectory $LogDirectory -TimeoutSeconds 900
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
        if(-not ($_.Exception.Data['ShadowResourceFitFailure'] -or $_.Exception.Data['ShadowRuntimeCompatibilityFailure'] -or $_.Exception.Data['ShadowModelLoadFailure'])){throw}
        $Profile.SmokeTests=[pscustomobject]@{Chat='NotRun';ToolCall='NotRun';ToolResultRoundTrip='NotRun'}
        $Profile.VerificationState='Deferred'
        $Profile.VerificationMessage=$_.Exception.Message
        Write-Warning "Model $($Profile.Alias) remains downloaded and unverified: $($Profile.VerificationMessage)"
        return
    }
    try {
        $Profile.SmokeTests=Test-LrModelInference -ApiBaseUrl $Pool.BackendApiBaseUrl -ModelId $Profile.InstanceId -Headers (Get-LrApiHeaders $Pool.ApiTokenEnvironmentVariable)
        foreach($key in @('Chat','ToolCall','ToolResultRoundTrip')){
            if((Get-LrProperty $Profile.SmokeTests $key) -cne 'Passed'){throw "Model test $key failed."}
        }
        $Profile.VerificationState='Verified'
        $Profile.VerificationMessage=''
    } catch {
        $Profile.SmokeTests=[pscustomobject]@{Chat='NotVerified';ToolCall='NotVerified';ToolResultRoundTrip='NotVerified'}
        $Profile.VerificationState='Deferred'
        $Profile.VerificationMessage=$_.Exception.Message
        Write-Warning "Model $($Profile.Alias) remains downloaded; model test failed: $($Profile.VerificationMessage)"
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
    if(-not $IsWindows){throw 'The model pool is designed for Windows with an NVIDIA GPU.'}
    if($LegacyModelKey){throw 'An explicit LegacyModelKey belongs to the single-model profile. Multi-model profiles use the verified catalog files.'}
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
        if($Port -lt 1024 -or $Port -eq $RouterPort){throw 'Backend and router ports must be different valid ports.'}
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
                if(-not $DownloadModel){throw "Model $($item.Name) is missing; model downloads are disabled."}
                Write-Host "Downloading exact model file for $($item.Alias): $($item.Name) ..."
                $null=Invoke-LrNative -FilePath $lms -Arguments @('get',$item.Definition.DownloadUrl,'--gguf','--yes') -LogDirectory $logs -TimeoutSeconds 14400
                $model=Find-LrModel -Models @(Get-LrDownloadedModels -LmsPath $lms -LogDirectory $logs) -Profile $item.Definition
                if(-not $model){throw 'Could not locate an exact local match for the downloaded model.'}
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
                if(-not ($_.Exception.Data['ShadowResourceFitFailure'] -or $_.Exception.Data['ShadowRuntimeCompatibilityFailure'] -or $_.Exception.Data['ShadowModelLoadFailure'])){throw}
                $primaryProfile.SmokeTests=[pscustomobject]@{Chat='NotRun';ToolCall='NotRun';ToolResultRoundTrip='NotRun'}
                $primaryProfile.VerificationState='Deferred'
                $primaryProfile.VerificationMessage=$_.Exception.Message
                Write-Warning "Primary model remains downloaded and unverified: $($primaryProfile.VerificationMessage)"
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
        if($pool.OwnerId -cne $owner.OwnerId){throw 'Model pool and ownership record do not match.'}
        $logs=Join-Path $InstallRoot 'runtime/pool-logs'
        Ensure-SmpServer -Pool $pool -LogDirectory $logs
        $profiles=@($pool.Profiles|Where-Object {$_.Alias -ceq $Alias})
        if($profiles.Count -ne 1){throw "Unknown or ambiguous model alias: $Alias"}
        $profile=$profiles[0]
        try {
            $result=Set-SmpActiveProfile -InstallRoot $InstallRoot -Pool $pool -Owner $owner -Alias $Alias -LogDirectory $logs -AllowUnfitAttempt:(Get-LrProperty $pool 'AllowUnfitAttempt' $false)
        } catch {
            if($_.Exception.Data['ShadowResourceFitFailure'] -or $_.Exception.Data['ShadowRuntimeCompatibilityFailure'] -or $_.Exception.Data['ShadowModelLoadFailure']){
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
                    if((Get-LrProperty $tests $key) -cne 'Passed'){throw "Model test $key failed."}
                }
                $profile.SmokeTests=$tests
                $profile.VerificationState='Verified'
                $profile.VerificationMessage=''
            } catch {
                $profile.SmokeTests=[pscustomobject]@{Chat='NotVerified';ToolCall='NotVerified';ToolResultRoundTrip='NotVerified'}
                $profile.VerificationMessage=$_.Exception.Message
                Write-SmpJson -Path (Join-Path $InstallRoot 'runtime/model-pool.json') -Value $pool -InstallRoot $InstallRoot
                $error=[InvalidOperationException]::new("Model $Alias loaded, but the model test failed: $($_.Exception.Message)")
                $error.Data['ShadowModelVerificationFailure']=$true
                throw $error
            }
        }
        foreach($key in @('Chat','ToolCall','ToolResultRoundTrip')){
            if((Get-LrProperty $profile.SmokeTests $key) -cne 'Passed'){
                $error=[InvalidOperationException]::new("Model $Alias has no verifiably passed model test.")
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
        if($owner.OwnerId -cne $pool.OwnerId){throw 'Model pool and ownership record do not match.'}
        $logs=Join-Path $InstallRoot 'runtime/pool-logs'
        Ensure-SmpServer -Pool $pool -LogDirectory $logs
        Restore-SmpPendingOwnership -InstallRoot $InstallRoot -Pool $pool -Owner $owner -LogDirectory $logs
        $null=@(Get-SmpOwnedLoaded -Pool $pool -Owner $owner -LogDirectory $logs)
        return $pool
    } finally {$lock.Dispose()}
}

function Get-SmpEmbeddingMemoryCheck {
    param([string]$EstimateText,[long]$FreeRamBytes,[long]$ModelSizeBytes)
    $plain=($EstimateText -replace '\x1B\[[0-?]*[ -/]*[@-~]','') -replace '\s+',' '
    $total=Convert-LrEstimatedBytes -Text $plain -Label 'Estimated Total Memory'
    if($total -le 0 -or $FreeRamBytes -lt 0 -or $ModelSizeBytes -le 0){throw 'Invalid CPU embedding memory measurements.'}
    $guardrails=if($plain -match 'This model will fail to load based on your resource guardrails settings'){'Denied'}
        elseif($plain -match 'This model may be loaded based on your resource guardrails settings'){'Allowed'}else{'NotReported'}
    $low=$plain -match 'Confidence:\s*LOW\b'
    # Only the hash-verified CPU embedding model uses this conservative trial.
    # LOW is an uncertain estimate, not a measured resource shortage. The actual
    # load still enforces LM Studio guardrails; readiness requires real inference.
    $conservative=$low -or $guardrails -ceq 'NotReported'
    $budget=if($conservative){[long][math]::Max(1GB,[math]::Max(4.0*$total,4.0*$ModelSizeBytes))}else{$total}
    $reasons=@(if($guardrails -ceq 'Denied'){'lm_studio_guardrails_denied'};if($budget -gt ($FreeRamBytes-3GB)){'insufficient_ram_with_reserve'})
    return [pscustomobject][ordered]@{
        EstimatedBytes=$total;AvailableRamBytes=$FreeRamBytes;BudgetBytes=$budget;ReserveBytes=[long]3GB
        Guardrails=$guardrails;LowConfidence=$low;ConservativeTrial=$conservative;BlockingReasons=$reasons
        AvailableAfterLoadBytes=$null;AvailableAfterInferenceBytes=$null
    }
}

function Remove-SmpIdleEmbeddingInstance {
    param($Pool,$Owner,[string]$InstanceId,[string]$ModelPath,[string]$LogDirectory)
    # Used for rollback of a new load or an explicitly disabled owned embedding.
    # Do not use the coding-model unload helper: it deliberately excludes embeddings.
    $entries=@($Owner.Entries|Where-Object {$_.InstanceId -ceq $InstanceId -and $_.ModelPath -ceq $ModelPath -and $_.Verified -eq $true -and (Get-LrProperty $_ 'Origin') -ceq 'verified-cpu-embedding'})
    if($InstanceId -cne ('shadow-'+$Owner.OwnerId+'-embedding') -or $entries.Count -ne 1){throw 'Cannot verify embedding rollback ownership. No instance was unloaded.'}
    $matches=@(Invoke-LrJson -LmsPath $Pool.LmsPath -Arguments @('ps','--json') -LogDirectory $LogDirectory|Where-Object {(Get-LrProperty $_ 'identifier') -ceq $InstanceId})
    if(-not $matches.Count){return}
    if($matches.Count -ne 1 -or (Get-LrProperty $matches[0] 'type') -cne 'embedding' -or
       (Get-LrProperty $matches[0] 'path') -cne $ModelPath -or $null -ne (Get-LrProperty $matches[0] 'deviceIdentifier' '__unknown__') -or
       [int](Get-LrProperty $matches[0] 'contextLength' 0) -ne 2048 -or (Get-LrProperty $matches[0] 'status') -cne 'idle' -or
       [int](Get-LrProperty $matches[0] 'queued' -1) -ne 0){throw 'Embedding rollback cannot verify a unique idle local instance. No instance was unloaded.'}
    $apiRoot=$Pool.BackendApiBaseUrl -replace '/v1/?$',''
    $response=Invoke-LrApi -Uri ($apiRoot+'/api/v1/models/unload') -Headers (Get-LrApiHeaders $Pool.ApiTokenEnvironmentVariable) -Method POST -Body @{instance_id=$InstanceId} -TimeoutSeconds 120
    if((Get-LrProperty $response 'instance_id') -cne $InstanceId){throw 'LM Studio did not confirm the targeted embedding rollback.'}
    $remaining=@(Invoke-LrJson -LmsPath $Pool.LmsPath -Arguments @('ps','--json') -LogDirectory $LogDirectory|Where-Object {(Get-LrProperty $_ 'identifier') -ceq $InstanceId})
    if($remaining.Count){throw 'Embedding instance remains loaded after rollback.'}
}

function Start-ShadowEmbeddingModel {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$InstallRoot,[Parameter(Mandatory)]$Pool,[Parameter(Mandatory)]$Definition,[switch]$AllowUnfitAttempt)
    Assert-SmpPool -Pool $Pool -RequireReady
    $lock=Enter-SmpLock -InstallRoot $InstallRoot
    try {
        $owner=Get-SmpOwner -InstallRoot $InstallRoot
        if($owner.OwnerId -cne $Pool.OwnerId){throw 'Model pool and ownership record do not match.'}
        $logs=Join-Path $InstallRoot 'runtime/pool-logs'
        Ensure-SmpServer -Pool $Pool -LogDirectory $logs
        Restore-SmpPendingOwnership -InstallRoot $InstallRoot -Pool $Pool -Owner $owner -LogDirectory $logs
        $model=Find-LrModel -Models @(Get-LrDownloadedModels -LmsPath $Pool.LmsPath -LogDirectory $logs -Type embedding) -Profile $Definition
        if(-not $model){throw 'The verified local embedding model is not registered in LM Studio.'}
        $file=$Definition.Files[0]
        $modelFile=Join-Path (Join-Path (Resolve-ShadowModelDirectory) $Definition.Repository.Replace('/','\')) $file.Name
        if(-not(Test-ShadowModelFile -Path $modelFile -Size $file.Size -Sha256 $file.Sha256)){
            throw 'Embedding file does not match the verified catalog. It remains unchanged.'
        }
        $path=[string](Get-LrProperty $model 'path')
        $id='shadow-'+$owner.OwnerId+'-embedding'
        $null=@(Get-SmpOwnedLoaded -Pool $Pool -Owner $owner -LogDirectory $logs)
        $entries=@($owner.Entries|Where-Object {$_.InstanceId -ceq $id})
        if($entries.Count -gt 1 -or ($entries.Count -eq 1 -and ($entries[0].ModelPath -cne $path -or
           (Get-LrProperty $entries[0] 'Origin') -cnotin @('verified-cpu-embedding','pending-cpu-embedding')))){
            throw 'Embedding ownership file does not match the local model. No instance will be changed.'
        }
        $loaded=@(Invoke-LrJson -LmsPath $Pool.LmsPath -Arguments @('ps','--json') -LogDirectory $logs)
        $instances=@($loaded|Where-Object {(Get-LrProperty $_ 'identifier') -ceq $id})
        $reserveOverride=$false;$memoryCheck=$null;$loadedHere=$false
        if(-not $instances.Count){
            $estimate=Invoke-LrNative -FilePath $Pool.LmsPath -Arguments @('load',$path,'--exact','--local','--context-length','2048','--gpu','off','--estimate-only','--yes') -LogDirectory $logs
            $text=$estimate.Stdout+"`n"+$estimate.Stderr
            $hardware=Get-LocalNvidiaGpu -LogDirectory $logs
            $memoryCheck=Get-SmpEmbeddingMemoryCheck -EstimateText $text -FreeRamBytes $hardware.FreeRamBytes -ModelSizeBytes $file.Size
            $fitMessage="CPU embedding RAM fit: estimate $($memoryCheck.EstimatedBytes) bytes, load budget $($memoryCheck.BudgetBytes) bytes, available $($memoryCheck.AvailableRamBytes) bytes, reserve $($memoryCheck.ReserveBytes) bytes; confidence low: $($memoryCheck.LowConfidence); LM Studio guardrails: $($memoryCheck.Guardrails)."
            if($memoryCheck.BlockingReasons.Count){
                if(-not $AllowUnfitAttempt -or $memoryCheck.Guardrails -ceq 'Denied'){
                    $error=[InvalidOperationException]::new("No verified RAM fit for the CPU embedding model. Reasons: $($memoryCheck.BlockingReasons -join ', '). $fitMessage No further instance was loaded.")
                    $error.Data['ShadowResourceFitFailure']=$true
                    $error.Data['ShadowEmbeddingMemoryCheck']=$memoryCheck
                    throw $error
                }
                $reserveOverride=$true
                Write-Warning 'No verified RAM fit for the CPU embedding model. Attempting load without LoKiEnte reserve; LM Studio safeguards remain active.'
            }
            if($memoryCheck.ConservativeTrial -and -not $reserveOverride){Write-Host "$fitMessage Using a conservative CPU load and inference check; the 3 GiB reserve remains required."}
            $owner.Entries=@($owner.Entries|Where-Object {$_.InstanceId -cne $id})+@(
                [pscustomobject]@{InstanceId=$id;ModelPath=$path;Verified=$false;Origin='pending-cpu-embedding';ExpectedPath=$Definition.ExpectedPath;SelectedVariant='';GpuOffload='off'}
            )
            Write-SmpJson -Path (Join-Path $InstallRoot 'runtime/model-ownership.json') -Value $owner -InstallRoot $InstallRoot
            Write-Host 'Loading the local embedding model exclusively on the CPU ...'
            $loadArguments=@('load',$path,'--exact','--local','--context-length','2048','--gpu','off','--identifier',$id,'--yes')
            if($reserveOverride -or $memoryCheck.ConservativeTrial){
                $load=Invoke-LrNative -FilePath $Pool.LmsPath -Arguments $loadArguments -LogDirectory $logs -TimeoutSeconds 900 -AllowFailure
                $loadExit=Get-LrProperty $load 'ExitCode'
                if($loadExit -isnot [int] -and $loadExit -isnot [long]){throw 'LM Studio returned no usable exit code for the embedding load attempt.'}
                if($loadExit -ne 0){
                    $error=[InvalidOperationException]::new("LM Studio rejected the CPU embedding load attempt (exit code $loadExit). $fitMessage Details: $($load.LogPath)")
                    $error.Data['ShadowResourceFitFailure']=$true
                    $error.Data['ShadowEmbeddingMemoryCheck']=$memoryCheck
                    throw $error
                }
            }else{
                $null=Invoke-LrNative -FilePath $Pool.LmsPath -Arguments $loadArguments -LogDirectory $logs -TimeoutSeconds 900
            }
            Restore-SmpPendingOwnership -InstallRoot $InstallRoot -Pool $Pool -Owner $owner -LogDirectory $logs
            $loadedHere=$true
            $instances=@(Invoke-LrJson -LmsPath $Pool.LmsPath -Arguments @('ps','--json') -LogDirectory $logs|Where-Object {(Get-LrProperty $_ 'identifier') -ceq $id})
        }

        if($instances.Count -ne 1 -or (Get-LrProperty $instances[0] 'type') -cne 'embedding' -or
           (Get-LrProperty $instances[0] 'path') -cne $path -or $null -ne (Get-LrProperty $instances[0] 'deviceIdentifier' '__unknown__') -or
           [int](Get-LrProperty $instances[0] 'contextLength' 0) -ne 2048){
            throw 'Loaded embedding instance is not uniquely verified. It remains unchanged.'
        }
        if($loadedHere -and $memoryCheck.ConservativeTrial -and -not $reserveOverride){
            $memoryCheck.AvailableAfterLoadBytes=[long](Get-LocalNvidiaGpu -LogDirectory $logs).FreeRamBytes
            if($memoryCheck.AvailableAfterLoadBytes -lt 3GB){
                Remove-SmpIdleEmbeddingInstance -Pool $Pool -Owner $owner -InstanceId $id -ModelPath $path -LogDirectory $logs
                $error=[InvalidOperationException]::new('CPU embedding load left less than 3 GiB available RAM. The newly loaded embedding was unloaded; coding models remain unchanged.')
                $error.Data['ShadowResourceFitFailure']=$true;$error.Data['ShadowEmbeddingMemoryCheck']=$memoryCheck
                throw $error
            }
        }
        $inferenceError=$null
        try {
            $headers=Get-LrApiHeaders -ApiTokenEnvironmentVariable $Pool.ApiTokenEnvironmentVariable
            $response=Invoke-LrApi -Uri ($Pool.RouterApiBaseUrl+'/embeddings') -Headers $headers -Method POST -Body @{
                model=$id;input=@('local embedding test','local source search');encoding_format='base64';dimensions=768
            } -TimeoutSeconds 60
            $data=@(Get-LrProperty $response 'data' @())
            if($data.Count -ne 2){throw 'Embedding smoke test did not return two vectors.'}
            $indexes=[Collections.Generic.HashSet[int]]::new()
            foreach($item in $data){
                $index=Get-LrProperty $item 'index'
                if($index -isnot [int] -and $index -isnot [long]){throw 'Embedding smoke test returned no valid vector index.'}
                if($index -notin @(0,1) -or -not $indexes.Add([int]$index)){throw 'Embedding smoke test returned duplicate or invalid vector indices.'}
                $vector=Get-LrProperty $item 'embedding'
                if($vector -is [string]){
                    try{$bytes=[Convert]::FromBase64String($vector)}catch{throw 'Embedding smoke test returned invalid Base64.'}
                    if($bytes.Length -ne 3072){throw 'Embedding smoke test returned an unexpected vector dimension.'}
                    $vector=@(for($i=0;$i -lt $bytes.Length;$i+=4){[BitConverter]::ToSingle($bytes,$i)})
                }elseif($vector -is [array]){
                    if($vector.Count -ne 768){throw 'Embedding smoke test returned an unexpected vector dimension.'}
                }else{throw 'Embedding smoke test did not return a vector array.'}
                $nonzero=$false
                foreach($value in $vector){
                    if($value -isnot [int] -and $value -isnot [long] -and $value -isnot [float] -and $value -isnot [double] -and $value -isnot [decimal]){throw 'Embedding smoke test returned an invalid vector value.'}
                    if(-not [double]::IsFinite([double]$value)){throw 'Embedding smoke test returned an invalid vector value.'}
                    if([double]$value -ne 0){$nonzero=$true}
                }
                if(-not $nonzero){throw 'Embedding smoke test returned a zero vector.'}
            }
        } catch {$inferenceError=$_.Exception}
        if($loadedHere -and $memoryCheck.ConservativeTrial -and -not $reserveOverride){
            $memoryCheck.AvailableAfterInferenceBytes=[long](Get-LocalNvidiaGpu -LogDirectory $logs).FreeRamBytes
            if($memoryCheck.AvailableAfterInferenceBytes -lt 3GB){
                Remove-SmpIdleEmbeddingInstance -Pool $Pool -Owner $owner -InstanceId $id -ModelPath $path -LogDirectory $logs
                if($inferenceError -and $inferenceError.Data['ShadowAuthenticationFailure']){throw $inferenceError}
                $error=[InvalidOperationException]::new('CPU embedding inference left less than 3 GiB available RAM. The newly loaded embedding was unloaded; indexing remains deferred.')
                $error.Data['ShadowResourceFitFailure']=$true;$error.Data['ShadowEmbeddingMemoryCheck']=$memoryCheck
                $error.Data['ShadowEmbeddingSmokeTest']=if($inferenceError){'Failed'}else{'Passed'}
                throw $error
            }
        }
        if($inferenceError){
            if($inferenceError.Data['ShadowAuthenticationFailure']){throw $inferenceError}
            $error=[InvalidOperationException]::new("Embedding smoke test failed: $($inferenceError.Message)")
            $error.Data['ShadowEmbeddingVerificationFailure']=$true;$error.Data['ShadowEmbeddingMemoryCheck']=$memoryCheck
            throw $error
        }
        return [pscustomobject]@{Status='Ready';InstanceId=$id;ModelPath=$path;Dimension=768;Device='CPU';SmokeTest='Passed';ReserveOverride=$reserveOverride;MemoryCheck=$memoryCheck}
    } finally {$lock.Dispose()}
}

function Initialize-ShadowEmbeddingModel {
    param([Parameter(Mandatory)][string]$InstallRoot,[Parameter(Mandatory)]$Pool,[Parameter(Mandatory)]$Definition)
    try {
        $result=Start-ShadowEmbeddingModel -InstallRoot $InstallRoot -Pool $Pool -Definition $Definition -AllowUnfitAttempt:(Get-LrProperty $Pool 'AllowUnfitAttempt' $false)
    } catch {
        if(-not $_.Exception.Data['ShadowResourceFitFailure'] -and -not $_.Exception.Data['ShadowEmbeddingVerificationFailure']){throw}
        Write-Warning "Local indexing is not ready yet: $($_.Exception.Message) Model remains downloaded."
        $smoke=if($_.Exception.Data['ShadowEmbeddingSmokeTest']){[string]$_.Exception.Data['ShadowEmbeddingSmokeTest']}elseif($_.Exception.Data['ShadowEmbeddingVerificationFailure']){'Failed'}else{'NotRun'}
        $result=[pscustomobject]@{Status='Deferred';InstanceId=('shadow-'+$Pool.OwnerId+'-embedding');ModelPath=$Definition.ExpectedPath;Dimension=768;Device='CPU';SmokeTest=$smoke;Message=$_.Exception.Message;MemoryCheck=$_.Exception.Data['ShadowEmbeddingMemoryCheck']}
    }
    # Stable content avoids a new backup on every successful launch. API errors
    # are already sanitized; no request text or authentication values are stored.
    Write-SmpJson -Path (Join-Path $InstallRoot 'runtime/embedding-status.json') -InstallRoot $InstallRoot -Value ([ordered]@{
        schema=1;apiBaseUrl=$Pool.RouterApiBaseUrl;requestedDimensions=768;result=$result
    })
    return $result
}
