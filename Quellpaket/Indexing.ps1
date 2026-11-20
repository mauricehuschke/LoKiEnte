# Optional semantic indexing policy. Dot-sourcing performs no setup.
Set-StrictMode -Version Latest

function Get-ShadowIndexingMode {
    param([Parameter(Mandatory)]$Toolchain)
    $mode=[string](Get-LrProperty $Toolchain 'indexingMode' 'Off')
    switch($mode){'Off'{return 'Off'} 'OnDemand'{return 'OnDemand'} 'Automatic'{return 'Automatic'} default{throw 'Unknown indexing mode. Rerun provisioning with an explicit IndexingMode.'}}
}

function Select-ShadowIndexingForLaunch {
    param([ValidateSet('Off','OnDemand','Automatic')][string]$Mode='Off',[switch]$StartIndexing)
    $Mode=Get-ShadowIndexingMode -Toolchain @{indexingMode=$Mode}
    if($Mode -ceq 'Off'){
        if($StartIndexing){throw 'Indexing is disabled. Provision OnDemand or Automatic before requesting indexing.'}
        return $false
    }
    if($Mode -ceq 'Automatic' -or $StartIndexing){return $true}
    Write-Host 'Optional local indexing: starts the CPU embedding model for this launch. Kilo project consent is still required.'
    try {return ((Read-Host 'Start indexing for the selected project now? [y/N]') -ieq 'y')}
    catch {Write-Host 'No interactive indexing choice available. Indexing stays off for this launch.';return $false}
}

function Get-ShadowEmbeddingConfigurationArguments {
    param([Parameter(Mandatory)]$Embedding,[Parameter(Mandatory)][string]$ApiBaseUrl)
    if($Embedding.Status -ceq 'Ready'){
        return @{EmbeddingModelId=$Embedding.InstanceId;EmbeddingApiBaseUrl=$ApiBaseUrl}
    }
    return @{}
}

function Stop-ShadowEmbeddingModel {
    param([Parameter(Mandatory)][string]$InstallRoot,[Parameter(Mandatory)]$Pool)
    Assert-SmpPool -Pool $Pool -RequireReady
    $lock=Enter-SmpLock -InstallRoot $InstallRoot
    try {
        $owner=Get-SmpOwner -InstallRoot $InstallRoot
        if($owner.OwnerId -cne $Pool.OwnerId){throw 'Embedding ownership does not match the local model pool.'}
        $logs=Join-Path $InstallRoot 'runtime/pool-logs'
        Ensure-SmpServer -Pool $Pool -LogDirectory $logs
        Restore-SmpPendingOwnership -InstallRoot $InstallRoot -Pool $Pool -Owner $owner -LogDirectory $logs
        $id='shadow-'+$owner.OwnerId+'-embedding'
        $loaded=@(Invoke-LrJson -LmsPath $Pool.LmsPath -Arguments @('ps','--json') -LogDirectory $logs|Where-Object {(Get-LrProperty $_ 'identifier') -ceq $id})
        if(-not $loaded.Count){return}
        $entries=@($owner.Entries|Where-Object {$_.InstanceId -ceq $id})
        if($entries.Count -ne 1){throw 'Cannot verify the embedding instance to disable. Existing models remain unchanged.'}
        Remove-SmpIdleEmbeddingInstance -Pool $Pool -Owner $owner -InstanceId $id -ModelPath $entries[0].ModelPath -LogDirectory $logs
        Write-Host 'Unloaded the owned idle CPU embedding model because indexing is not starting.'
    } finally {$lock.Dispose()}
}

function Set-ShadowIndexingInactive {
    param([Parameter(Mandatory)][string]$InstallRoot,[ValidateSet('Off','OnDemand')][string]$Mode='Off')
    $Mode=Get-ShadowIndexingMode -Toolchain @{indexingMode=$Mode}
    $result=[pscustomobject]@{Status=$(if($Mode -ceq 'Off'){'Disabled'}else{'OnDemand'});SmokeTest='NotRun';Mode=$Mode}
    Write-SmpJson -Path (Join-Path $InstallRoot 'runtime/embedding-status.json') -InstallRoot $InstallRoot -Value ([ordered]@{
        schema=1;mode=$Mode;result=$result
    })
    return $result
}
