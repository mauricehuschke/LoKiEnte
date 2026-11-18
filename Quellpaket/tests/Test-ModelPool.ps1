#requires -Version 7.4
# Real orchestration and files; Windows/LM Studio/GPU/HTTP boundaries are mocked.
[CmdletBinding()]
param([string]$SourceRoot=(Split-Path -Parent $PSScriptRoot))
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $SourceRoot 'ModelPool.ps1')
Set-Variable -Name IsWindows -Value $true -Force
$root=Join-Path ([IO.Path]::GetTempPath()) ('shadow-pool-test-'+[guid]::NewGuid().ToString('N'))
$results=[Collections.Generic.List[string]]::new()
function Assert-Pool([bool]$Condition,[string]$Description){if(-not $Condition){throw "FAIL: $Description"};$results.Add($Description);Write-Host "PASS: $Description"}
function Throws-Pool([scriptblock]$Action,[string]$Pattern,[string]$Description){$caught=$false;try{& $Action|Out-Null}catch{$caught=$true;if($_.Exception.Message -notmatch $Pattern){throw}};Assert-Pool $caught $Description}
$script:downloaded=[Collections.Generic.HashSet[string]]::new()
$script:loaded=@();$script:server=$false;$script:public=$false;$script:badSmoke=$false;$script:badRest=$false
$script:downloadCalls=0;$script:unloadCalls=0;$script:loadCalls=0;$script:inferenceCalls=0
$script:noFitPath='';$script:rejectNoFit=$false
$script:hiddenOptionsSupported=$true
$script:fixtures=@(
    [pscustomobject]@{type='llm';deviceIdentifier=$null;path='lmstudio-community/Qwen3.8-27B-GGUF/Qwen3.8-27B-Q4_K_M.gguf';modelKey='qwen/qwen3.8-27b@q4_k_m'},
    [pscustomobject]@{type='llm';deviceIdentifier=$null;path='lmstudio-community/gpt-oss-20b-GGUF/gpt-oss-20b-MXFP4.gguf';modelKey='openai/gpt-oss-20b@mxfp4'},
    [pscustomobject]@{type='llm';deviceIdentifier=$null;path='lmstudio-community/Qwen3.5-9B-GGUF/Qwen3.5-9B-Q4_K_M.gguf';modelKey='qwen/qwen3.5-9b@q4_k_m'}
)
function Resolve-LocalLmsCommand {param($LmsPath);return 'C:\Mock\lms.exe'}
function Get-LocalNvidiaGpu {param($LogDirectory);return [pscustomobject]@{Gpu=[pscustomobject]@{Name='Mock A4500';FreeBytes=19.5GB;TotalBytes=20GB};TotalRamBytes=28GB;FreeRamBytes=25GB}}
function Ensure-LrInferenceEngine {param($LmsPath,$LogDirectory);return 'mock-cuda'}
function Get-NetTCPConnection {param($State,$LocalPort,$ErrorAction);if($script:server){[pscustomobject]@{LocalAddress=$(if($script:public){'0.0.0.0'}else{'127.0.0.1'});LocalPort=$LocalPort}}}
function Invoke-LrNative {
    param($FilePath,[string[]]$Arguments,$LogDirectory,$TimeoutSeconds,[switch]$AllowFailure)
    $text=''
    switch($Arguments[0]){
        'server'{$script:server=$true}
        'get'{
            $matches=@($script:fixtures|Where-Object {$Arguments[1].Contains([IO.Path]::GetFileName($_.path))})
            if($matches.Count -ne 1){throw 'Unknown mock model download'}
            [void]$script:downloaded.Add($matches[0].path);$script:downloadCalls++
        }
        'load'{
            if($Arguments -contains '--help'){$text='--parallel --context-length --estimate-only --identifier --gpu --yes'}
            elseif(($Arguments -join ' ') -ceq 'load --exact --local --estimate-only --yes'){
                if(-not $AllowFailure){throw 'Probe must handle the expected refusal'}
                return [pscustomobject]@{ExitCode=1;Stdout='';Stderr=$(if($script:hiddenOptionsSupported){'Path not provided: The parameter [model-key] is required when using --exact.'}else{'unknown option --local'});LogPath='mock.log'}
            }
            else {
                if($Arguments -notcontains '--exact' -or $Arguments -notcontains '--local'){throw 'Local exact-model guards were removed'}
                $context=[int]$Arguments[[array]::IndexOf($Arguments,'--context-length')+1]
                if($Arguments -contains '--estimate-only'){
                    $gpu=if($Arguments[1] -ceq $script:noFitPath){30}elseif($Arguments[1] -like '*Qwen3.8*' -and $context -gt 16384){22}else{17}
                    $total=if($Arguments[1] -ceq $script:noFitPath){26}else{19}
                    $text="Estimated GPU Memory: $gpu GiB`nEstimated Total Memory: $total GiB`nThis model may be loaded based on your resource guardrails settings."
                } else {
                    if($Arguments[1] -ceq $script:noFitPath -and $script:rejectNoFit){
                        if(-not $AllowFailure){throw 'Expected explicit resource-fit load attempt'}
                        return [pscustomobject]@{Stdout='';Stderr='Guardrail rejected';LogPath='mock.log';ExitCode=42}
                    }
                    if(@($script:loaded|Where-Object {(Get-LrProperty $_ 'type') -cne 'embedding'}).Count){throw 'Mock detected simultaneous coding-model load.'}
                    $script:loadCalls++
                    $script:loaded=@($script:loaded)+@([pscustomobject]@{deviceIdentifier=$null;path=$Arguments[1];modelKey='mock';identifier=$Arguments[[array]::IndexOf($Arguments,'--identifier')+1];contextLength=$context;parallel=1;status='idle';queued=0})
                }
            }
        }
        default{throw "Unexpected native command $($Arguments[0])"}
    }
    [pscustomobject]@{Stdout=$text;Stderr='';LogPath='mock.log';ExitCode=0}
}
function Invoke-LrJson {
    param($LmsPath,[string[]]$Arguments,$LogDirectory)
    switch($Arguments[0]){
        'server'{return [pscustomobject]@{running=$script:server;port=1234}}
        'ls'{return @($script:fixtures|Where-Object {$script:downloaded.Contains($_.path)})}
        'ps'{return $script:loaded}
        default{throw 'Unexpected JSON command'}
    }
}
function Invoke-LrApi {
    param($Uri,$Headers,$Method='GET',$Body,$TimeoutSeconds)
    if($Uri -match '/api/v1/models/unload$'){
        if($Body.instance_id -cnotin @($script:loaded.identifier)){throw 'Wrong instance unload'}
        $script:unloadCalls++;$script:loaded=@($script:loaded|Where-Object {$_.identifier -cne $Body.instance_id})
        return [pscustomobject]@{instance_id=$Body.instance_id}
    }
    if($Uri -match '/api/v1/models$'){
        if($script:badRest){$script:badRest=$false;throw 'Simulated REST timeout after load'}
        return [pscustomobject]@{models=@([pscustomobject]@{loaded_instances=@($script:loaded|ForEach-Object {[pscustomobject]@{id=$_.identifier;config=[pscustomobject]@{context_length=$_.contextLength;parallel=(Get-LrProperty $_ 'parallel')}}})})}
    }
    if($Uri -notmatch '/v1/chat/completions$'){throw 'Unexpected HTTP endpoint'}
    $script:inferenceCalls++
    if($script:badSmoke){return [pscustomobject]@{choices=@([pscustomobject]@{message=[pscustomobject]@{content='wrong'}})}}
    if(-not $Body.ContainsKey('tools')){return [pscustomobject]@{choices=@([pscustomobject]@{message=[pscustomobject]@{content='LOCAL_READY'}})}}
    if($Body.tool_choice -ceq 'none'){return [pscustomobject]@{choices=@([pscustomobject]@{message=[pscustomobject]@{content='LOCAL_TOOL_OK'}})}}
    if($Body.tool_choice -cne 'required'){throw 'Unsupported tool_choice; expected required or none'}
    return [pscustomobject]@{choices=@([pscustomobject]@{message=[pscustomobject]@{content=$null;tool_calls=@([pscustomobject]@{id='mock-call';type='function';function=[pscustomobject]@{name='report_value';arguments='{"value":17}'}})}})}
}
try {
    $script:hiddenOptionsSupported=$false
    Throws-Pool {Configure-LocalModelPool -InstallRoot (Join-Path $root 'unsupported')} 'load options not confirmed' 'Missing actual hidden-flag support blocks setup before loading'
    Assert-Pool ($script:loadCalls -eq 0 -and $script:downloadCalls -eq 0 -and $script:inferenceCalls -eq 0) 'Rejected capability probe neither downloads nor loads models'
    $script:hiddenOptionsSupported=$true
    $pool=Configure-LocalModelPool -InstallRoot $root
    Assert-Pool ($pool.Status -ceq 'Ready' -and $pool.Profiles.Count -eq 3) 'Three-model first installation becomes Ready only after all smoke tests'
    . (Join-Path $SourceRoot 'Router.ps1')
    $roleCatalog=Get-ShadowPoolCatalog $pool
    Assert-Pool ($roleCatalog['coder-high'].name -clike '[[]CODER HIGH[]]*' -and
        $roleCatalog['coder-fast'].name -clike '[[]CODER FAST[]]*' -and $roleCatalog.review.name -clike '[[]REVIEW[]]*') 'Displayed model names distinguish coding intensities and review'
    Assert-Pool ($script:downloadCalls -eq 3) 'Three selected role files are downloaded'
    Assert-Pool (@($pool.Profiles|Where-Object {$_.ContextLength -ne 16384}).Count -eq 0) 'All profiles use actual common 16K fallback'
    Assert-Pool ($pool.Profiles[0].InstanceId -cne $pool.Profiles[1].InstanceId) 'Distinct stable managed instance identifiers'
    Assert-Pool (@($pool.Profiles|Where-Object {$_.SmokeTests.ToolResultRoundTrip -cne 'Passed'}).Count -eq 0) 'Every model completed the genuine structured smoke contract'
    $owner=Get-SmpOwner $root
    Assert-Pool ($owner.Entries.Count -eq 3) 'Only verified loaded instances enter ownership registry'
    $beforeLoads=$script:loadCalls;$beforeInference=$script:inferenceCalls
    $same=Switch-ShadowLocalModel -InstallRoot $root -Alias coder-high
    Assert-Pool ($same.ModelId -ceq $pool.Profiles[0].InstanceId -and $script:loadCalls -eq $beforeLoads) 'Repeated active-model selection reuses existing instance'
    $script:badRest=$true
    Throws-Pool {Switch-ShadowLocalModel -InstallRoot $root -Alias coder-fast} 'Simulated REST timeout' 'Interrupted Coder Fast load remains explicit'
    $pendingFast=@((Get-SmpOwner $root).Entries|Where-Object {$_.InstanceId -ceq $pool.Profiles[1].InstanceId -and -not $_.Verified})
    Assert-Pool ($pendingFast.Count -eq 1) 'Interrupted Coder Fast load retains its pending ownership record'
    $recoveredFast=Switch-ShadowLocalModel -InstallRoot $root -Alias coder-fast
    Assert-Pool ($recoveredFast.Alias -ceq 'coder-fast' -and @((Get-SmpOwner $root).Entries|Where-Object {$_.InstanceId -ceq $recoveredFast.InstanceId -and $_.Verified}).Count -eq 1) 'Pending Coder Fast ownership is safely recovered'
    $null=Switch-ShadowLocalModel -InstallRoot $root -Alias coder-high
    $review=Switch-ShadowLocalModel -InstallRoot $root -Alias review
    Assert-Pool ($review.Alias -ceq 'review' -and $script:loaded.Count -eq 1 -and $script:loaded[0].identifier -ceq $review.InstanceId) 'Cross-model switch leaves only selected managed instance loaded'
    Assert-Pool ($script:inferenceCalls -eq $beforeInference) 'Ordinary switch verifies state without repeating three inference smoke requests'
    $again=Configure-LocalModelPool -InstallRoot $root -IncludeFastModel
    Assert-Pool ($again.Profiles.Count -eq 4 -and $script:downloadCalls -eq 3) 'Optional fast profile reuses the already downloaded model'
    Assert-Pool ($again.Profiles[0].InstanceId -ceq $pool.Profiles[0].InstanceId) 'Repeat provisioning preserves ownership and IDs'
    $embeddingOwner=Get-SmpOwner $root
    $embeddingId='shadow-'+$embeddingOwner.OwnerId+'-embedding'
    $embeddingOwner.Entries+=@([pscustomobject]@{InstanceId=$embeddingId;ModelPath='embedding.gguf';Verified=$true;Origin='verified-cpu-embedding'})
    Write-SmpJson -Path (Join-Path $root 'runtime/model-ownership.json') -Value $embeddingOwner -InstallRoot $root
    $script:loaded+=@([pscustomobject]@{type='embedding';identifier=$embeddingId;path='embedding.gguf';deviceIdentifier=$null;status='processing';queued=0;contextLength=2048})
    $switched=Switch-ShadowLocalModel -InstallRoot $root -Alias review
    Assert-Pool ($switched.Alias -ceq 'review' -and @($script:loaded|Where-Object {$_.identifier -ceq $embeddingId}).Count -eq 1) 'Coding-model switches retain the independently active owned CPU embedding model'
    $script:loaded=@($script:loaded|Where-Object {$_.identifier -cne $embeddingId})
    $embeddingOwner=Get-SmpOwner $root
    $embeddingOwner.Entries=@($embeddingOwner.Entries|Where-Object {$_.InstanceId -cne $embeddingId})
    Write-SmpJson -Path (Join-Path $root 'runtime/model-ownership.json') -Value $embeddingOwner -InstallRoot $root
    $null=Switch-ShadowLocalModel -InstallRoot $root -Alias coder-high
    $script:public=$true
    Throws-Pool {Switch-ShadowLocalModel -InstallRoot $root -Alias coder-high} 'Loopback' 'Public backend listener is rejected'
    $script:public=$false
    $saved=$script:loaded;$beforeUnloads=$script:unloadCalls
    $script:loaded=@([pscustomobject]@{deviceIdentifier=$null;path='foreign.gguf';identifier='foreign';status='idle';queued=0;contextLength=16384;parallel=1})
    Throws-Pool {Switch-ShadowLocalModel -InstallRoot $root -Alias review} 'external' 'Foreign idle model is preserved and blocks switching'
    Assert-Pool ($script:unloadCalls -eq $beforeUnloads) 'No foreign model unload was attempted'
    $script:loaded=$saved;$script:loaded[0].status='processing'
    Throws-Pool {Get-SmpOwnedLoaded -Pool $again -Owner (Get-SmpOwner $root) -LogDirectory 'mock' -IdleTimeoutSeconds 0} 'still working' 'Busy owned instance is not treated as idle after a client closes'
    Assert-Pool ($script:unloadCalls -eq $beforeUnloads) 'Busy model was never unloaded'
    $script:loaded[0].status='idle'
    $lock=Enter-SmpLock -InstallRoot $root
    try{Throws-Pool {Enter-SmpLock -InstallRoot $root -TimeoutSeconds 0} 'Another process' 'FileShare.None prevents a second model controller'}finally{$lock.Dispose()}
    $script:badRest=$true
    Throws-Pool {Switch-ShadowLocalModel -InstallRoot $root -Alias review} 'Simulated REST timeout' 'Verification failure after successful load remains an explicit error'
    $pending=@((Get-SmpOwner $root).Entries|Where-Object {$_.Origin -ceq 'pending-explicit-load'})
    Assert-Pool ($pending.Count -eq 1 -and -not $pending[0].Verified) 'Load intent is persisted before verification and does not claim readiness'
    $afterFailureLoads=$script:loadCalls;$afterFailureUnloads=$script:unloadCalls
    $expectedPath=$script:loaded[0].path
    $script:loaded[0].path='foreign.gguf'
    Throws-Pool {Switch-ShadowLocalModel -InstallRoot $root -Alias review} 'does not match' 'A pending identifier with a different path is never adopted'
    Assert-Pool ($script:unloadCalls -eq $afterFailureUnloads) 'Mismatched pending instance remains untouched'
    $script:loaded[0].path=$expectedPath
    $recovered=Switch-ShadowLocalModel -InstallRoot $root -Alias review
    Assert-Pool ($recovered.Status -ceq 'Ready' -and $script:loadCalls -eq $afterFailureLoads) 'Retry verifies and reuses the exact pending model without reloading'
    Assert-Pool (@((Get-SmpOwner $root).Entries|Where-Object {-not $_.Verified}).Count -eq 0) 'Recovered identity is saved durably after independent local identity lookup'
    $script:badSmoke=$true
    $null=Configure-LocalModelPool -InstallRoot $root
    $failed=Get-Content -LiteralPath (Join-Path $root 'runtime/model-pool.json') -Raw|ConvertFrom-Json
    Assert-Pool ($failed.Status -ceq 'Ready' -and $failed.VerificationStatus -ceq 'Partial' -and
        @($failed.Profiles|Where-Object {$_.VerificationState -ceq 'Deferred' -and $_.SmokeTests.Chat -ceq 'NotVerified'}).Count -eq $failed.Profiles.Count) 'Failed model tests leave downloaded profiles explicitly deferred without blocking setup'
    $loadsBeforeStart=$script:loadCalls
    $started=Start-LocalModelPool -InstallRoot $root
    Assert-Pool ($started.Status -ceq 'Ready' -and $script:loadCalls -eq $loadsBeforeStart) 'Router startup does not force a deferred primary model to load'
    Throws-Pool {Switch-ShadowLocalModel -InstallRoot $root -Alias coder-high} 'model test' 'A deferred profile is not claimed verified until its test succeeds'
    $script:badSmoke=$false;$script:loaded=@()
    $optRoot=Join-Path $root 'offload-opt-in'
    $optPool=Configure-LocalModelPool -InstallRoot $optRoot -AllowPartialGpuOffload
    $savedPool=Get-Content -LiteralPath (Join-Path $optRoot 'runtime/model-pool.json') -Raw|ConvertFrom-Json
    Assert-Pool ($optPool.AllowPartialGpuOffload -eq $true -and $savedPool.AllowPartialGpuOffload -eq $true) 'Explicit partial offload policy is saved in the ready pool'
    $null=Switch-ShadowLocalModel -InstallRoot $optRoot -Alias review
    $savedPool=Get-Content -LiteralPath (Join-Path $optRoot 'runtime/model-pool.json') -Raw|ConvertFrom-Json
    $reviewProfile=@($savedPool.Profiles|Where-Object {$_.Alias -ceq 'review'})[0]
    Assert-Pool ($savedPool.AllowPartialGpuOffload -eq $true -and $reviewProfile.Estimate.GpuOffload -ceq 'max') 'Model switching retains the offload policy and persists its new estimate'
    $script:loaded=@()
    . (Join-Path $SourceRoot 'ModelSelection.ps1')
    . (Join-Path $SourceRoot 'Router.ps1')
    $catalog=@(Get-ShadowModelCatalog)
    $coder=@($catalog|Where-Object {$_.Id -ceq 'qwen35-9b'})[0]
    $review=@($catalog|Where-Object {$_.Id -ceq 'gpt-oss-20b'})[0]
    $selection=@(@{Alias='coder';Name=$coder.Name;Definition=$coder},@{Alias='review';Name=$review.Name;Definition=$review})
    $beforeDownloads=$script:downloadCalls
    $customRoot=Join-Path $root 'custom-selection'
    $selectedPool=Configure-LocalModelPool -InstallRoot $customRoot -SelectedDefinitions $selection -DownloadModel:$false
    $config=Get-ShadowPoolCatalog $selectedPool
    Assert-Pool ($selectedPool.Profiles[0].ExpectedPath -ceq $coder.ExpectedPath -and $script:downloadCalls -eq $beforeDownloads -and
        $config.coder.interleaved -ceq 'reasoning_content' -and $config.review.interleaved -ceq 'reasoning') 'Selected models flow through model pool without downloads and keep model-specific reasoning fields'
    $newCoder=@($catalog|Where-Object {$_.Id -ceq 'qwen38-27b'})[0]
    $newSelection=@(@{Alias='coder';Name=$newCoder.Name;Definition=$newCoder},@{Alias='review';Name=$review.Name;Definition=$review})
    $beforeUnloads=$script:unloadCalls
    $changedPool=Configure-LocalModelPool -InstallRoot $customRoot -SelectedDefinitions $newSelection -DownloadModel:$false -ContextLength 16384
    Assert-Pool ($changedPool.Profiles[0].ExpectedPath -ceq $newCoder.ExpectedPath -and
        $script:loaded[0].path -ceq $newCoder.ExpectedPath -and $script:unloadCalls -gt $beforeUnloads) 'Changing a role with the same managed identifier reloads the newly selected file'
    $migratedSelection=@(
        @{Alias='coder-high';Name=$newCoder.Name;Definition=$newCoder},
        @{Alias='coder-fast';Name=$coder.Name;Definition=$coder},
        @{Alias='review';Name=$review.Name;Definition=$review}
    )
    $migratedPool=Configure-LocalModelPool -InstallRoot $customRoot -SelectedDefinitions $migratedSelection -DownloadModel:$false -ContextLength 16384
    Assert-Pool ($migratedPool.PrimaryAlias -ceq 'coder-high' -and $migratedPool.Profiles.Count -eq 3 -and
        $script:loaded[0].identifier -ceq $migratedPool.Profiles[0].InstanceId) 'Legacy coder pool migrates to the new roles without adopting foreign instances'
    $script:loaded=@();$script:noFitPath=$script:fixtures[0].path;$script:rejectNoFit=$true
    $deferredRoot=Join-Path $root 'no-fit-deferred'
    $deferredPool=Configure-LocalModelPool -InstallRoot $deferredRoot -ContextLength 16384 -DownloadModel:$false
    $deferredHigh=@($deferredPool.Profiles|Where-Object {$_.Alias -ceq 'coder-high'})[0]
    Assert-Pool ($deferredPool.Status -ceq 'Ready' -and $deferredPool.VerificationStatus -ceq 'Partial' -and
        $deferredHigh.VerificationState -ceq 'Deferred' -and $deferredHigh.SmokeTests.Chat -ceq 'NotRun' -and
        $script:downloaded.Contains($script:noFitPath) -and $deferredHigh.VerificationMessage -notmatch 'rejected') 'Insufficient memory defers the model without a load attempt by default'
    $deferredCatalog=Get-ShadowPoolCatalog $deferredPool
    Assert-Pool ($deferredCatalog['coder-high'].name -match '\[NOT YET VERIFIED\]$') 'The unverified model remains visible with an explicit status label'
    $script:rejectNoFit=$false;$script:noFitPath=''
    $recoveredHigh=Switch-ShadowLocalModel -InstallRoot $deferredRoot -Alias coder-high
    $afterRecovery=Get-Content -LiteralPath (Join-Path $deferredRoot 'runtime/model-pool.json') -Raw|ConvertFrom-Json
    $recoveredProfile=@($afterRecovery.Profiles|Where-Object {$_.Alias -ceq 'coder-high'})[0]
    Assert-Pool ($recoveredHigh.Status -ceq 'Ready' -and $recoveredProfile.VerificationState -ceq 'Verified' -and
        $recoveredProfile.SmokeTests.ToolResultRoundTrip -ceq 'Passed') 'A later request retries and verifies the deferred model without provisioning again'
    $script:loaded=@();$script:noFitPath=$script:fixtures[0].path;$script:rejectNoFit=$false
    $overridePool=Configure-LocalModelPool -InstallRoot (Join-Path $root 'no-fit-success') -ContextLength 16384 -DownloadModel:$false -AllowUnfitAttempt
    $overrideHigh=@($overridePool.Profiles|Where-Object {$_.Alias -ceq 'coder-high'})[0]
    Assert-Pool ($overrideHigh.VerificationState -ceq 'Verified' -and $overrideHigh.Estimate.ReserveOverride -eq $true) 'A successful load without LoKiEnte reserve still requires all smoke tests'
    $script:noFitPath='';$script:loaded=@()
    $legacyRoot=Join-Path $root 'legacy';[void][IO.Directory]::CreateDirectory((Join-Path $legacyRoot 'runtime'))
    $legacy=[ordered]@{SchemaVersion=1;Status='Ready';ModelId='shadow-local-coder';ModelPath='known.gguf';ReusedLoadedModel=$true;SmokeTests=@{Chat='Passed';ToolCall='Passed';ToolResultRoundTrip='Passed'}}
    [IO.File]::WriteAllText((Join-Path $legacyRoot 'runtime/runtime-state.json'),($legacy|ConvertTo-Json -Depth 8))
    Assert-Pool ((Get-SmpOwner $legacyRoot).Entries.Count -eq 0) 'Legacy reused instance is not assumed to belong to this package'
    Remove-Item -LiteralPath (Join-Path $legacyRoot 'runtime/model-ownership.json')
    $legacy.ReusedLoadedModel=$false
    [IO.File]::WriteAllText((Join-Path $legacyRoot 'runtime/runtime-state.json'),($legacy|ConvertTo-Json -Depth 8))
    Assert-Pool ((Get-SmpOwner $legacyRoot).Entries.Count -eq 1) 'Verified legacy instance explicitly created by v1 can be adopted'
    [pscustomobject]@{Suite='Multi-model pool lifecycle';Passed=$true;Checks=$results.Count;Limitations='Real orchestration and filesystem; LM Studio, GPU, HTTP and Windows boundaries mocked.'}|ConvertTo-Json
} finally {if(Test-Path -LiteralPath $root){Remove-Item -LiteralPath $root -Recurse -Force}}
