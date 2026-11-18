#requires -Version 7.4
[CmdletBinding()]
param([string]$SourceRoot=(Split-Path -Parent $PSScriptRoot))
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $SourceRoot 'ModelPool.ps1')
. (Join-Path $SourceRoot 'ModelSelection.ps1')
. (Join-Path $SourceRoot 'AgentTemplates.ps1')
$root=Join-Path ([IO.Path]::GetTempPath()) ('shadow-embedding-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory((Join-Path $root 'runtime'))
$count=0
function Assert-Embedding([bool]$Condition,[string]$Message){if(-not $Condition){throw "FAIL: $Message"};$script:count++}
function Throws-Embedding([scriptblock]$Action,[string]$Pattern,[string]$Message){
    $failure=$null;try{& $Action|Out-Null}catch{$failure=$_.Exception.Message}
    Assert-Embedding ([bool]$failure -and $failure -match $Pattern) $Message
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
        return [pscustomobject]@{Stdout="Estimated Total Memory: 1 GiB`nThis model may be loaded based on your resource guardrails settings.";Stderr='';LogPath='mock';ExitCode=0}
    }
    if($script:rejectNoFit){
        if(-not $AllowFailure){throw 'Expected explicit resource-fit load attempt'}
        return [pscustomobject]@{Stdout='';Stderr='rejected';LogPath='mock';ExitCode=43}
    }
    $script:loads++
    $id=$Arguments[[array]::IndexOf($Arguments,'--identifier')+1]
    $script:loaded+=@([pscustomobject]@{type='embedding';identifier=$id;path=$Arguments[1];deviceIdentifier=$null;status='idle';queued=0;contextLength=2048})
    return [pscustomobject]@{Stdout='';Stderr='';LogPath='mock';ExitCode=0}
}
function Invoke-LrApi {
    param($Uri,$Headers,$Method,$Body,$TimeoutSeconds)
    if($Uri -cne 'http://127.0.0.1:1234/v1/embeddings' -or $Body.encoding_format -cne 'base64'){throw 'Unexpected embedding request'}
    $vector=@(for($i=0;$i -lt 768;$i++){if($script:badVector){0.0}else{0.25}})
    if($script:base64){
        $bytes=[byte[]]::new(3072)
        for($i=0;$i -lt 768;$i++){[BitConverter]::GetBytes([float]$vector[$i]).CopyTo($bytes,$i*4)}
        $vector=[Convert]::ToBase64String($bytes)
    }
    return [pscustomobject]@{data=@([pscustomobject]@{index=0;embedding=$vector},[pscustomobject]@{index=$(if($script:duplicateIndex){0}else{1});embedding=$vector})}
}
try{
    $script:badFile=$true
    Throws-Embedding {Start-ShadowEmbeddingModel -InstallRoot $root -Pool $pool -Definition $definition} 'Embeddingdatei' 'A changed embedding file is not loaded'
    Assert-Embedding ($script:loads -eq 0) 'Invalid file caused no model load'
    $script:badFile=$false;$script:freeRam=3GB
    Throws-Embedding {Start-ShadowEmbeddingModel -InstallRoot $root -Pool $pool -Definition $definition} 'RAM-Fit' 'RAM reserve blocks loading'
    Assert-Embedding ($script:loads -eq 0) 'Insufficient RAM caused no model load'
    $script:rejectNoFit=$true
    $deferred=Initialize-ShadowEmbeddingModel -InstallRoot $root -Pool $pool -Definition $definition
    Assert-Embedding ($deferred.Status -ceq 'Deferred' -and $deferred.SmokeTest -ceq 'NotRun' -and $script:loads -eq 0 -and $deferred.Message -notmatch 'abgelehnt') 'Insufficient RAM defers the embedding without a load attempt'
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
    Throws-Embedding {Get-SmpOwnedLoaded -Pool $pool -Owner (Get-SmpOwner $root) -LogDirectory 'fixture'} 'Mehrere Instanzen' 'Duplicate embedding instance identifiers are rejected'
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
    $script:badVector=$true
    Throws-Embedding {Start-ShadowEmbeddingModel -InstallRoot $root -Pool $pool -Definition $definition} 'Nullvektor' 'Invalid inference does not report ready'
    $failedTest=Initialize-ShadowEmbeddingModel -InstallRoot $root -Pool $pool -Definition $definition
    Assert-Embedding ($failedTest.Status -ceq 'Deferred' -and $failedTest.SmokeTest -ceq 'Failed' -and $failedTest.Message -match 'Nullvektor') 'An embedding test failure remains an explicit nonblocking warning'
    $script:badVector=$false;$script:duplicateIndex=$true
    Throws-Embedding {Start-ShadowEmbeddingModel -InstallRoot $root -Pool $pool -Definition $definition} 'Vektorindizes' 'Duplicate vector indices are rejected'
    $script:duplicateIndex=$false
    $script:loaded[1].path='foreign.gguf'
    Throws-Embedding {Start-ShadowEmbeddingModel -InstallRoot $root -Pool $pool -Definition $definition} 'fremdes' 'Changed embedding identity is not adopted'
    $script:loaded[1].path=$definition.ExpectedPath
    $entry=Join-Path $root 'tooling/lancedb/node_modules/@lancedb/lancedb/dist/index.js'
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $entry));[IO.File]::WriteAllText($entry,'fixture')
    $config=New-ShadowAgentConfiguration -InstallRoot $root -ModelCatalog ([ordered]@{
        'coder-high'=@{id='shadow-coder-high';context=32768;output=8192}
        'coder-fast'=@{id='shadow-coder-fast';context=16384;output=4096}
        review=@{id='shadow-review';context=32768;output=8192}
        fast=@{id='shadow-fast';context=16384;output=4096}
    }) -ApiBaseUrl $pool.RouterApiBaseUrl -EmbeddingApiBaseUrl $pool.BackendApiBaseUrl -EmbeddingModelId $result.InstanceId
    $envMap=Get-ShadowLocalEnvironment -InstallRoot $root -ConfigJson ($config.Config|ConvertTo-Json -Depth 40 -Compress)
    Assert-Embedding ($config.Config.indexing.provider -ceq 'openai-compatible' -and $config.Config.indexing.vectorStore -ceq 'lancedb' -and
        $config.Config.indexing.'openai-compatible'.baseUrl -ceq $pool.BackendApiBaseUrl -and
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
    [pscustomobject]@{suite='CPU embedding and indexing configuration';passed=$true;checks=$count;limitations='LM Studio and GPU boundaries are mocked.'}|ConvertTo-Json
}finally{Remove-Item -LiteralPath $root -Recurse -Force}
