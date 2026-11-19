#requires -Version 7.4
[CmdletBinding()]
param([string]$SourceRoot=(Split-Path -Parent $PSScriptRoot))
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $SourceRoot 'ModelPool.ps1')
. (Join-Path $SourceRoot 'ModelSelection.ps1')
. (Join-Path $SourceRoot 'Indexing.ps1')
. (Join-Path $SourceRoot 'AgentTemplates.ps1')
$root=Join-Path ([IO.Path]::GetTempPath()) ('shadow-embedding-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory((Join-Path $root 'runtime'))
$count=0
function Assert-Embedding([bool]$Condition,[string]$Message){if(-not $Condition){throw "FAIL: $Message"};$script:count++}
function Throws-Embedding([scriptblock]$Action,[string]$Pattern,[string]$Message){
    $failure=$null;try{& $Action|Out-Null}catch{$failure=$_.Exception.Message}
    Assert-Embedding ([bool]$failure -and $failure -match $Pattern) $Message
}
$script:realApi=(Get-Command Invoke-LrApi).ScriptBlock
$script:authStatus=0
function Invoke-RestMethod {
    $response=[Net.Http.HttpResponseMessage]::new([Net.HttpStatusCode]$script:authStatus)
    throw [Microsoft.PowerShell.Commands.HttpResponseException]::new('Synthetic response body must not leak',$response)
}
$definition=Get-ShadowEmbeddingDefinition
$pool=[pscustomobject]@{
    SchemaVersion=2;Status='Ready';OwnerId=('a'*24);PrimaryAlias='coder';LmsPath='fixture'
    BackendApiBaseUrl='http://127.0.0.1:1234/v1';RouterApiBaseUrl='http://127.0.0.1:1235/v1'
    ApiTokenEnvironmentVariable='';Profiles=@(
        [pscustomobject]@{Alias='coder';RouteId='shadow-coder';InstanceId='coder-id';ModelPath='coder.gguf';ContextLength=32768;OutputLimit=8192},
        [pscustomobject]@{Alias='review';RouteId='shadow-review';InstanceId='review-id';ModelPath='review.gguf';ContextLength=32768;OutputLimit=8192}
    )
}
$owner=[pscustomobject]@{SchemaVersion=1;OwnerId=$pool.OwnerId;Entries=@(
    [pscustomobject]@{InstanceId='coder-id';ModelPath='coder.gguf';Verified=$true;Origin='verified-explicit-load'}
)}
Write-SmpJson -Path (Join-Path $root 'runtime/model-ownership.json') -Value $owner -InstallRoot $root
$script:loaded=@([pscustomobject]@{type='llm';identifier='coder-id';path='coder.gguf';deviceIdentifier=$null;status='idle';queued=0;contextLength=32768;parallel=1})
$script:loads=0;$script:freeRam=8GB;$script:badFile=$false;$script:badVector=$false;$script:base64=$false;$script:duplicateIndex=$false;$script:rejectNoFit=$false
$script:estimateText="Estimated Total Memory: 1 GiB`nThis model may be loaded based on your resource guardrails settings."
$script:afterLoadRam=$null;$script:afterInferenceRam=$null;$script:unloads=0;$script:inferenceCalls=0
function Ensure-SmpServer {param($Pool,$LogDirectory)}
function Resolve-ShadowModelDirectory {return $root}
function Test-ShadowModelFile {param($Path,$Size,$Sha256) return -not $script:badFile}
function Get-LrDownloadedModels {
    param($LmsPath,$LogDirectory,$Type)
    if($Type -cne 'embedding'){throw 'Expected embedding model lookup'}
    return [pscustomobject]@{type='embedding';path=$definition.ExpectedPath;modelKey='nomic';deviceIdentifier=$null}
}
function Get-LocalNvidiaGpu {param($LogDirectory) return [pscustomobject]@{FreeRamBytes=$script:freeRam;Gpu=@{FreeBytes=10GB}}}
function Invoke-LrJson {
    param($LmsPath,$Arguments,$LogDirectory)
    if($Arguments[0] -cne 'ps'){throw 'Unexpected CLI request'}
    return $script:loaded
}
function Invoke-LrNative {
    param($FilePath,[string[]]$Arguments,$LogDirectory,$TimeoutSeconds,[switch]$AllowFailure)
    if($Arguments[0] -cne 'load' -or $Arguments -notcontains '--exact' -or
       $Arguments -notcontains '--local' -or $Arguments -notcontains 'off'){throw 'Unsafe embedding load'}
    if($Arguments -contains '--estimate-only'){
        return [pscustomobject]@{Stdout=$script:estimateText;Stderr='';LogPath='mock';ExitCode=0}
    }
    if($script:rejectNoFit){
        if(-not $AllowFailure){throw 'Expected explicit resource-fit load attempt'}
        return [pscustomobject]@{Stdout='';Stderr='rejected';LogPath='mock';ExitCode=43}
    }
    $script:loads++
    $id=$Arguments[[array]::IndexOf($Arguments,'--identifier')+1]
    $script:loaded+=@([pscustomobject]@{type='embedding';identifier=$id;path=$Arguments[1];deviceIdentifier=$null;status='idle';queued=0;contextLength=2048})
    if($null -ne $script:afterLoadRam){$script:freeRam=$script:afterLoadRam}
    return [pscustomobject]@{Stdout='';Stderr='';LogPath='mock';ExitCode=0}
}
function Invoke-LrApi {
    param($Uri,$Headers,$Method,$Body,$TimeoutSeconds)
    if($Uri -ceq 'http://127.0.0.1:1234/api/v1/models/unload'){
        if($Body.instance_id -cne ('shadow-'+$pool.OwnerId+'-embedding')){throw 'Attempted to unload a coding or foreign model'}
        $script:loaded=@($script:loaded|Where-Object {$_.identifier -cne $Body.instance_id})
        $script:unloads++
        return [pscustomobject]@{instance_id=$Body.instance_id}
    }
    if($Uri -cne 'http://127.0.0.1:1235/v1/embeddings' -or $Body.encoding_format -cne 'base64' -or $Body.dimensions -ne 768){throw 'Unexpected embedding request'}
    $script:inferenceCalls++
    if($null -ne $script:afterInferenceRam){$script:freeRam=$script:afterInferenceRam}
    if($script:authStatus){return & $script:realApi -Uri $Uri -Headers $Headers -Method $Method -Body $Body -TimeoutSeconds $TimeoutSeconds}
    $vector=@(for($i=0;$i -lt 768;$i++){if($script:badVector){0.0}else{0.25}})
    if($script:base64){
        $bytes=[byte[]]::new(3072)
        for($i=0;$i -lt 768;$i++){[BitConverter]::GetBytes([float]$vector[$i]).CopyTo($bytes,$i*4)}
        $vector=[Convert]::ToBase64String($bytes)
    }
    return [pscustomobject]@{data=@([pscustomobject]@{index=0;embedding=$vector},[pscustomobject]@{index=$(if($script:duplicateIndex){0}else{1});embedding=$vector})}
}
try{
    $normalEstimate=$script:estimateText
    $lowEstimate="Estimated Total Memory: 112.29 MiB`nConfidence: LOW"
    $check=Get-SmpEmbeddingMemoryCheck -EstimateText $lowEstimate -FreeRamBytes ([long](4.4GB)) -ModelSizeBytes $definition.Files[0].Size
    Assert-Embedding ($check.ConservativeTrial -and $check.LowConfidence -and $check.Guardrails -ceq 'NotReported' -and $check.BudgetBytes -eq 1GB -and $check.ReserveBytes -eq 3GB -and $check.BlockingReasons.Count -eq 0) 'Reported LOW estimate fits a conservative 1 GiB budget plus the unchanged reserve'
    $large=Get-SmpEmbeddingMemoryCheck -EstimateText 'Estimated Total Memory: 400 MiB Confidence: LOW' -FreeRamBytes 4GB -ModelSizeBytes $definition.Files[0].Size
    Assert-Embedding ($large.BudgetBytes -eq 1600MB -and $large.BlockingReasons -contains 'insufficient_ram_with_reserve') 'Conservative budget scales with the estimate instead of capping memory at 1 GiB'
    $colored=Get-SmpEmbeddingMemoryCheck -EstimateText ("Estimated Total Memory: 112.29 MiB`nConfidence: `e[33mLOW`e[0m`nThis model may be loaded based on your resource`nguardrails settings.") -FreeRamBytes 5GB -ModelSizeBytes $definition.Files[0].Size
    Assert-Embedding ($colored.LowConfidence -and $colored.Guardrails -ceq 'Allowed') 'Color escapes and wrapped guardrail text are normalized'
    Throws-Embedding {Get-SmpEmbeddingMemoryCheck -EstimateText 'unknown output' -FreeRamBytes 8GB -ModelSizeBytes $definition.Files[0].Size} 'Cannot interpret' 'An unparseable estimate never authorizes a trial'
    $script:estimateText=$lowEstimate;$script:freeRam=[long](4.4GB)
    $trial=Initialize-ShadowEmbeddingModel -InstallRoot $root -Pool $pool -Definition $definition
    Assert-Embedding ($trial.Status -ceq 'Ready' -and $trial.SmokeTest -ceq 'Passed' -and -not $trial.ReserveOverride -and $script:loads -eq 1 -and $script:inferenceCalls -eq 1 -and $trial.MemoryCheck.AvailableAfterInferenceBytes -ge 3GB) 'LOW confidence reaches ready only after actual load and inference without a reserve override'
    $diagnostic=Get-Content -LiteralPath (Join-Path $root 'runtime/embedding-status.json') -Raw|ConvertFrom-Json
    Assert-Embedding ($diagnostic.result.MemoryCheck.EstimatedBytes -gt 112MB -and $diagnostic.result.MemoryCheck.BudgetBytes -eq 1GB) 'Diagnostic report contains numeric memory evidence without raw CLI output'
    $rollbackOwner=Get-SmpOwner $root
    $script:loaded[1].status='processing'
    Throws-Embedding {Remove-SmpIdleEmbeddingInstance -Pool $pool -Owner $rollbackOwner -InstanceId $trial.InstanceId -ModelPath $definition.ExpectedPath -LogDirectory 'fixture'} 'idle local' 'Rollback never unloads an active embedding instance'
    $script:loaded[1].status='idle';$script:loaded[1].path='foreign.gguf'
    Throws-Embedding {Remove-SmpIdleEmbeddingInstance -Pool $pool -Owner $rollbackOwner -InstanceId $trial.InstanceId -ModelPath $definition.ExpectedPath -LogDirectory 'fixture'} 'idle local' 'Rollback rejects a substituted model path'
    $script:loaded[1].path=$definition.ExpectedPath
    $script:loaded=@($script:loaded[0],$script:loaded[1],$script:loaded[1])
    Throws-Embedding {Remove-SmpIdleEmbeddingInstance -Pool $pool -Owner $rollbackOwner -InstanceId $trial.InstanceId -ModelPath $definition.ExpectedPath -LogDirectory 'fixture'} 'idle local' 'Rollback rejects duplicate identifiers'
    $script:loaded=@($script:loaded[0]);$script:loads=0;$script:inferenceCalls=0
    foreach($stage in @('load','inference','failed-inference')){
        $script:freeRam=[long](4.4GB);$script:afterLoadRam=if($stage -ceq 'load'){2GB}else{$null}
        $script:afterInferenceRam=if($stage -cne 'load'){2GB}else{$null};$script:badVector=$stage -ceq 'failed-inference'
        $beforeUnloads=$script:unloads;$beforeInference=$script:inferenceCalls
        $deferredTrial=Initialize-ShadowEmbeddingModel -InstallRoot $root -Pool $pool -Definition $definition
        Assert-Embedding ($deferredTrial.Status -ceq 'Deferred' -and $script:unloads -eq $beforeUnloads+1 -and $script:loaded.Count -eq 1 -and $script:loaded[0].identifier -ceq 'coder-id') "Reserve violation after $stage rolls back only the newly loaded embedding"
        $expectedSmoke=if($stage -ceq 'load'){'NotRun'}elseif($script:badVector){'Failed'}else{'Passed'}
        Assert-Embedding ($deferredTrial.SmokeTest -ceq $expectedSmoke -and ($stage -cne 'load' -or $script:inferenceCalls -eq $beforeInference)) 'Deferred status accurately records whether inference ran'
    }
    $script:afterLoadRam=$null;$script:afterInferenceRam=$null;$script:badVector=$false;$script:freeRam=3.9GB
    $beforeLoads=$script:loads
    $shortage=Initialize-ShadowEmbeddingModel -InstallRoot $root -Pool $pool -Definition $definition
    Assert-Embedding ($shortage.Status -ceq 'Deferred' -and $shortage.MemoryCheck.BlockingReasons -contains 'insufficient_ram_with_reserve' -and $script:loads -eq $beforeLoads) 'LOW estimate cannot bypass the conservative budget or 3 GiB reserve'
    $script:freeRam=8GB;$script:estimateText=$lowEstimate+"`nThis model will fail to load based on your resource guardrails settings."
    $denied=Initialize-ShadowEmbeddingModel -InstallRoot $root -Pool $pool -Definition $definition
    Assert-Embedding ($denied.Status -ceq 'Deferred' -and $denied.MemoryCheck.BlockingReasons -contains 'lm_studio_guardrails_denied' -and $script:loads -eq $beforeLoads) 'Explicit LM Studio guardrail denial blocks loading despite ample RAM'
    Throws-Embedding {Start-ShadowEmbeddingModel -InstallRoot $root -Pool $pool -Definition $definition -AllowUnfitAttempt} 'lm_studio_guardrails_denied' 'A reserve override cannot bypass explicit embedding guardrail denial'
    $script:estimateText=$lowEstimate;$script:rejectNoFit=$true
    $rejected=Initialize-ShadowEmbeddingModel -InstallRoot $root -Pool $pool -Definition $definition
    Assert-Embedding ($rejected.Status -ceq 'Deferred' -and $rejected.SmokeTest -ceq 'NotRun' -and $rejected.Message -match 'exit code 43' -and $script:loads -eq $beforeLoads) 'Actual LM Studio rejection remains deferred without a false inference success'
    $script:estimateText=$normalEstimate;$script:rejectNoFit=$false;$script:loads=0;$script:unloads=0;$script:inferenceCalls=0
    Write-SmpJson -Path (Join-Path $root 'runtime/model-ownership.json') -Value $owner -InstallRoot $root
    $script:badFile=$true
    Throws-Embedding {Start-ShadowEmbeddingModel -InstallRoot $root -Pool $pool -Definition $definition} 'Embedding file' 'A changed embedding file is not loaded'
    Assert-Embedding ($script:loads -eq 0) 'Invalid file caused no model load'
    $script:badFile=$false;$script:freeRam=3GB
    Throws-Embedding {Start-ShadowEmbeddingModel -InstallRoot $root -Pool $pool -Definition $definition} 'RAM fit' 'RAM reserve blocks loading'
    Assert-Embedding ($script:loads -eq 0) 'Insufficient RAM caused no model load'
    $script:rejectNoFit=$true
    $deferred=Initialize-ShadowEmbeddingModel -InstallRoot $root -Pool $pool -Definition $definition
    Assert-Embedding ($deferred.Status -ceq 'Deferred' -and $deferred.SmokeTest -ceq 'NotRun' -and $script:loads -eq 0 -and $deferred.Message -notmatch 'rejected') 'Insufficient RAM defers the embedding without a load attempt'
    $pool | Add-Member -NotePropertyName AllowUnfitAttempt -NotePropertyValue $true
    $script:rejectNoFit=$false
    $forced=Initialize-ShadowEmbeddingModel -InstallRoot $root -Pool $pool -Definition $definition
    Assert-Embedding ($forced.Status -ceq 'Ready' -and $forced.ReserveOverride -eq $true -and $script:loads -eq 1) 'A successful CPU load without reserve is explicitly recorded'
    $script:freeRam=8GB
    $result=Start-ShadowEmbeddingModel -InstallRoot $root -Pool $pool -Definition $definition
    Assert-Embedding ($result.Status -ceq 'Ready' -and $result.Device -ceq 'CPU' -and $script:loads -eq 1) 'CPU embedding load and inference are verified'
    $again=Start-ShadowEmbeddingModel -InstallRoot $root -Pool $pool -Definition $definition
    Assert-Embedding ($again.InstanceId -ceq $result.InstanceId -and $script:loads -eq 1) 'Owned embedding instance is reused'
    $script:loaded+=@($script:loaded[1])
    Throws-Embedding {Get-SmpOwnedLoaded -Pool $pool -Owner (Get-SmpOwner $root) -LogDirectory 'fixture'} 'Multiple instances' 'Duplicate embedding instance identifiers are rejected'
    $script:loaded=@($script:loaded[0],$script:loaded[1])
    $recoveryOwner=Get-SmpOwner $root
    $pending=@($recoveryOwner.Entries|Where-Object {$_.InstanceId -ceq $result.InstanceId})[0]
    $pending.Verified=$false;$pending.Origin='pending-cpu-embedding'
    Write-SmpJson -Path (Join-Path $root 'runtime/model-ownership.json') -Value $recoveryOwner -InstallRoot $root
    $recovered=Start-ShadowEmbeddingModel -InstallRoot $root -Pool $pool -Definition $definition
    Assert-Embedding ($recovered.Status -ceq 'Ready' -and $script:loads -eq 1 -and
        @((Get-SmpOwner $root).Entries|Where-Object {$_.InstanceId -ceq $result.InstanceId -and $_.Verified}).Count -eq 1) 'Interrupted owned load is verified and reused'
    $script:loaded[1].status='processing'
    $owned=@(Get-SmpOwnedLoaded -Pool $pool -Owner (Get-SmpOwner $root) -LogDirectory 'fixture' -IdleTimeoutSeconds 0)
    Assert-Embedding ($owned.Count -eq 1 -and $owned[0].identifier -ceq 'coder-id') 'Busy CPU embedding does not block the coding pool'
    $script:loaded[1].status='idle'
    $script:base64=$true
    Assert-Embedding ((Start-ShadowEmbeddingModel -InstallRoot $root -Pool $pool -Definition $definition).Status -ceq 'Ready') 'Base64 float vectors are validated'
    foreach($status in @(401,403)){
        $script:authStatus=$status;$authFailure=$null
        try{$null=Initialize-ShadowEmbeddingModel -InstallRoot $root -Pool $pool -Definition $definition}catch{$authFailure=$_.Exception}
        Assert-Embedding ($null -ne $authFailure -and $authFailure.Data['ShadowAuthenticationFailure'] -eq $true -and -not $authFailure.Data['ShadowEmbeddingVerificationFailure']) "HTTP $status must remain a blocking authentication error"
        Assert-Embedding ($authFailure.Message.StartsWith('LM Studio API denied access.') -and -not $authFailure.Message.Contains('Synthetic response body')) 'Authentication failure is English and does not expose response content'
    }
    $script:authStatus=0
    $script:badVector=$true
    Throws-Embedding {Start-ShadowEmbeddingModel -InstallRoot $root -Pool $pool -Definition $definition} 'zero vector' 'Invalid inference does not report ready'
    $failedTest=Initialize-ShadowEmbeddingModel -InstallRoot $root -Pool $pool -Definition $definition
    Assert-Embedding ($failedTest.Status -ceq 'Deferred' -and $failedTest.SmokeTest -ceq 'Failed' -and $failedTest.Message -match 'zero vector') 'An embedding test failure remains an explicit nonblocking warning'
    $diagnostic=Get-Content -LiteralPath (Join-Path $root 'runtime/embedding-status.json') -Raw|ConvertFrom-Json
    Assert-Embedding ($diagnostic.result.Status -ceq 'Deferred' -and $diagnostic.apiBaseUrl -ceq $pool.RouterApiBaseUrl -and $diagnostic.requestedDimensions -eq 768) 'Failed Kilo-compatible preflight remains visible in the local diagnostic report'
    $script:badVector=$false;$script:duplicateIndex=$true
    Throws-Embedding {Start-ShadowEmbeddingModel -InstallRoot $root -Pool $pool -Definition $definition} 'vector indices' 'Duplicate vector indices are rejected'
    $script:duplicateIndex=$false
    $script:loaded[1].path='foreign.gguf'
    Throws-Embedding {Start-ShadowEmbeddingModel -InstallRoot $root -Pool $pool -Definition $definition} 'external' 'Changed embedding identity is not adopted'
    $script:loaded[1].path=$definition.ExpectedPath
    $entry=Join-Path $root 'tooling/lancedb/node_modules/@lancedb/lancedb/dist/index.js'
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $entry));[IO.File]::WriteAllText($entry,'fixture')
    $config=New-ShadowAgentConfiguration -InstallRoot $root -ModelCatalog ([ordered]@{
        'coder-high'=@{id='shadow-coder-high';context=32768;output=8192}
        'coder-fast'=@{id='shadow-coder-fast';context=16384;output=4096}
        review=@{id='shadow-review';context=32768;output=8192}
        fast=@{id='shadow-fast';context=16384;output=4096}
    }) -ApiBaseUrl $pool.RouterApiBaseUrl -EmbeddingApiBaseUrl $pool.RouterApiBaseUrl -EmbeddingModelId $result.InstanceId
    $envMap=Get-ShadowLocalEnvironment -InstallRoot $root -ConfigJson ($config.Config|ConvertTo-Json -Depth 40 -Compress)
    Assert-Embedding ($config.Config.indexing.provider -ceq 'openai-compatible' -and $config.Config.indexing.vectorStore -ceq 'lancedb' -and
        $config.Config.indexing.'openai-compatible'.baseUrl -ceq $pool.RouterApiBaseUrl -and
        $config.Config.permission.semantic_search -ceq 'allow' -and $envMap.KILO_LANCEDB_PATH -ceq $entry) 'Local indexing and semantic search are explicitly configured'
    Assert-Embedding ($config.Config.agent.'shadow-chat'.model -ceq 'lmstudio/coder-high' -and
        $config.Config.agent.'shadow-chat-fast'.model -ceq 'lmstudio/coder-fast' -and
        $config.Config.agent.'shadow-explorer'.model -ceq 'lmstudio/coder-fast' -and
        $config.Config.agent.'shadow-reviewer'.model -ceq 'lmstudio/review' -and
        $config.Config.agent.code.disable -eq $true -and $config.Config.agent.plan.disable -eq $true) 'Shadow roles map to the intended coding and review profiles'
    $editing=ConvertFrom-Json -InputObject ($config.Config|ConvertTo-Json -Depth 40) -AsHashtable
    Set-ShadowImplementationModel -Config $editing -CoderProfile Fast
    Assert-Embedding ($editing.agent.'shadow-implementer'.model -ceq 'lmstudio/coder-fast' -and
        $editing.agent.'shadow-frontend'.model -ceq 'lmstudio/coder-fast' -and
        $editing.agent.'shadow-backend'.model -ceq 'lmstudio/coder-fast' -and
        $editing.agent.'shadow-reviewer'.model -ceq 'lmstudio/review' -and
        $editing.agent.'shadow-validator'.model -ceq 'lmstudio/coder-high' -and
        (Get-ShadowRoleModelInfo -Config $editing -Role 'shadow-implementer').ContextLength -eq 16384) 'Fast implementation preserves independent review, validation and its own context limit'
    Throws-Embedding {New-ShadowAgentConfiguration -InstallRoot $root -ModelId 'test' -ApiBaseUrl $pool.RouterApiBaseUrl -EmbeddingApiBaseUrl 'https://example.invalid/v1' -EmbeddingModelId $result.InstanceId} 'loopback' 'External embedding endpoint is rejected'
    $script:loaded[1].status='processing'
    Throws-Embedding {Stop-ShadowEmbeddingModel -InstallRoot $root -Pool $pool} 'idle local' 'Disabling indexing preserves an active embedding instance'
    $script:loaded[1].status='idle'
    $beforeUnloads=$script:unloads
    Stop-ShadowEmbeddingModel -InstallRoot $root -Pool $pool
    Assert-Embedding ($script:loaded.Count -eq 1 -and $script:loaded[0].identifier -ceq 'coder-id' -and $script:unloads -eq $beforeUnloads+1) 'Disabling indexing unloads only the verified idle embedding and retains the coding model'
    Stop-ShadowEmbeddingModel -InstallRoot $root -Pool $pool
    Assert-Embedding ($script:unloads -eq $beforeUnloads+1) 'Repeated disable does not unload another model'
    [pscustomobject]@{suite='CPU embedding and indexing configuration';passed=$true;checks=$count;limitations='LM Studio and GPU boundaries are mocked.'}|ConvertTo-Json
}finally{Remove-Item -LiteralPath $root -Recurse -Force}
