#requires -Version 7.4
[CmdletBinding()]
param([string]$SourceRoot=(Split-Path -Parent $PSScriptRoot))
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $SourceRoot 'ModelPool.ps1')
$count=0
function Assert-Offload([bool]$Condition,[string]$Description){if(-not $Condition){throw "FAIL: $Description"};$script:count++}
function Restore-SmpPendingOwnership {param($InstallRoot,$Pool,$Owner,$LogDirectory)}
function Get-SmpOwnedLoaded {param($Pool,$Owner,$LogDirectory) return @()}
function Save-SmpOwnership {param($InstallRoot,$Owner,$InstanceId,$ModelPath,$ExpectedPath,$SelectedVariant,$GpuOffload,[switch]$Pending)}
function Test-SmpLoadedProfile {param($Pool,$Profile,$LogDirectory) return [pscustomobject]@{Status='Ready';Alias=$Profile.Alias}}
function Get-LocalNvidiaGpu {param($LogDirectory) return [pscustomobject]@{Gpu=[pscustomobject]@{FreeBytes=$script:freeGpu};FreeRamBytes=$script:freeRam}}
$script:estimates=@();$script:loads=@();$script:mode='normal';$script:freeGpu=19GB;$script:freeRam=24GB
function Invoke-LrNative {
    param($FilePath,$Arguments,$LogDirectory,$TimeoutSeconds)
    $gpu=$Arguments[[array]::IndexOf($Arguments,'--gpu')+1]
    $context=[int]$Arguments[[array]::IndexOf($Arguments,'--context-length')+1]
    if($Arguments -contains '--estimate-only'){
        $script:estimates+=("$gpu/$context")
        $vram=if($gpu -eq 'max'){19.24}elseif($gpu -eq '0.8'){15.72}else{11.91}
        $total=if($script:mode -eq 'context' -and $context -gt 8192){23}else{19.24}
        $guard=if($script:mode -eq 'guardrail'){'This model will fail to load based on your resource guardrails settings.'}else{'This model may be loaded based on your resource guardrails settings.'}
        $confidence=if($script:mode -eq 'low'){"`nConfidence: LOW"}else{''}
        return [pscustomobject]@{Stdout="Estimated GPU Memory: $vram GiB`nEstimated Total Memory: $total GiB`n$guard$confidence";Stderr='';LogPath='synthetic.log'}
    }
    $script:loads+=("$gpu/$context")
    return [pscustomobject]@{Stdout='';Stderr='';LogPath='synthetic.log'}
}
function New-Fixture([bool]$Allow){
    return [pscustomobject]@{
        LmsPath='fixture';AllowPartialGpuOffload=$Allow
        Profiles=@([pscustomobject]@{Alias='coder';InstanceId='shadow-fixture-coder';ModelPath='fixture';ContextLength=32768;OutputLimit=8192;Estimate=$null})
    }
}
$owner=[pscustomobject]@{Entries=@()}
$pool=New-Fixture $true
$null=Set-SmpActiveProfile -InstallRoot 'fixture' -Pool $pool -Owner $owner -Alias coder -LogDirectory 'fixture' -AllowContextFallback
Assert-Offload ($script:estimates.Count -eq 4 -and ($script:estimates -join ',') -ceq 'max/32768,max/16384,max/8192,0.8/32768') 'Tries max contexts before 80 percent'
Assert-Offload ($script:loads.Count -eq 1 -and $script:loads[0] -ceq '0.8/32768' -and $pool.Profiles[0].Estimate.GpuOffload -ceq '0.8') 'Loads exactly the GPU setting and context that passed estimation'
$script:estimates=@();$script:loads=@();$pool=New-Fixture $false
$failed=$false;try{$null=Set-SmpActiveProfile -InstallRoot fixture -Pool $pool -Owner $owner -Alias coder -LogDirectory fixture -AllowContextFallback}catch{$failed=$_.Exception.Message -match 'No verified memory fit'}
Assert-Offload ($failed -and ($script:estimates -join ',') -ceq 'max/32768,max/16384' -and $script:loads.Count -eq 0) 'Default retains only max GPU and original context fallback'
$script:estimates=@();$script:loads=@();$script:freeRam=21.94GB;$pool=New-Fixture $true
$failed=$false;try{$null=Set-SmpActiveProfile -InstallRoot fixture -Pool $pool -Owner $owner -Alias coder -LogDirectory fixture -AllowContextFallback}catch{$failed=$_.Exception.Message -match 'reserves: 1 GiB VRAM and 3 GiB RAM'}
Assert-Offload ($failed -and $script:estimates.Count -eq 9 -and $script:loads.Count -eq 0) 'Actual reported RAM shortage blocks every combination without loading'
foreach($mode in @('guardrail','low')){
    $script:mode=$mode;$script:freeRam=24GB;$script:estimates=@();$script:loads=@();$pool=New-Fixture $true
    $failed=$false;try{$null=Set-SmpActiveProfile -InstallRoot fixture -Pool $pool -Owner $owner -Alias coder -LogDirectory fixture -AllowContextFallback}catch{$failed=$true}
    Assert-Offload ($failed -and $script:loads.Count -eq 0) "$mode estimates cannot authorize loading"
}
$script:mode='normal';$script:freeRam=24GB;$script:freeGpu=12.8GB;$script:estimates=@();$script:loads=@();$pool=New-Fixture $true
$failed=$false;try{$null=Set-SmpActiveProfile -InstallRoot fixture -Pool $pool -Owner $owner -Alias coder -LogDirectory fixture -AllowContextFallback}catch{$failed=$true}
Assert-Offload ($failed -and $script:loads.Count -eq 0) 'GPU reserve cannot be bypassed even for 60 percent'
$script:mode='context';$script:freeRam=24GB;$script:freeGpu=19GB;$script:estimates=@();$script:loads=@();$pool=New-Fixture $true
$null=Set-SmpActiveProfile -InstallRoot fixture -Pool $pool -Owner $owner -Alias coder -LogDirectory fixture -AllowContextFallback
Assert-Offload ($script:loads.Count -eq 1 -and $script:loads[0] -ceq '0.8/8192' -and $pool.Profiles[0].ContextLength -eq 8192) 'Requested 8192 context fallback is used only after higher contexts fail'
[pscustomobject]@{suite='Partial GPU offload';passed=$true;checks=$count}|ConvertTo-Json
