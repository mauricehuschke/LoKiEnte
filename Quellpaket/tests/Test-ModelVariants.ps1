#requires -Version 7.4
[CmdletBinding()]
param([string]$SourceRoot=(Split-Path -Parent $PSScriptRoot))
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $SourceRoot 'Runtime.ps1')
. (Join-Path $SourceRoot 'ModelPool.ps1')
$count=0
function Assert-Variant([bool]$Condition,[string]$Message){
    if(-not $Condition){throw "FAIL: $Message"}
    $script:count++
}
function Assert-VariantThrow([scriptblock]$Action,[string]$Pattern,[string]$Message){
    $errorText=$null;try{& $Action|Out-Null}catch{$errorText=$_.Exception.Message}
    Assert-Variant ($errorText -and $errorText -match $Pattern) $Message
}
$hardware=[pscustomobject]@{Gpu=[pscustomobject]@{TotalBytes=20GB};TotalRamBytes=28GB}
$profiles=@(Get-SmpModelDefinitions -Hardware $hardware -IncludeFastModel)
$keys=@('qwen/qwen3.8-27b','qwen/qwen3.5-9b','openai/gpt-oss-20b')
$suffixes=@('q4_k_m','q4_k_m','mxfp4')
$script:models=@();$script:groups=@()
for($i=0;$i -lt 3;$i++){
    $key=$keys[$i];$variant=$key+'@'+$suffixes[$i]
    $base=[pscustomobject]@{type='llm';modelKey=$key;path=$key;deviceIdentifier=$null;selectedVariant=$variant;variants=@($variant)}
    $detail=[pscustomobject]@{type='llm';modelKey=$variant;path=$key;deviceIdentifier=$null;indexedModelIdentifier=$key+'@'+$profiles[$i].Definition.ExpectedPath}
    $script:models+=@($base)
    $script:groups+=@([pscustomobject]@{model=$base;variants=@($detail)})
}
$script:invocations=@()
function Invoke-LrJson {
    param($LmsPath,[string[]]$Arguments,$LogDirectory)
    $script:invocations+=($Arguments -join ' ')
    if(($Arguments -join ' ') -ceq 'ls --json'){return $script:models}
    if(($Arguments -join ' ') -ceq 'ls --variants --json'){return $script:groups}
    throw 'Unexpected CLI call'
}
$found=@(Get-LrDownloadedModels -LmsPath 'fixture' -LogDirectory 'fixture')
foreach($i in 0..2){
    $match=Find-LrModel -Models $found -Profile $profiles[$i].Definition
    Assert-Variant ($null -ne $match -and $match.path -ceq $keys[$i] -and
        $match.ShadowSelectedFile -ceq $profiles[$i].Definition.ExpectedPath) "Exact selected local variant $i resolves to CLI model ID"
    Assert-LrSelectedModel -LmsPath 'fixture' -LogDirectory 'fixture' -ExpectedPath $profiles[$i].Definition.ExpectedPath -ModelPath $keys[$i]
    $count++
}
Assert-Variant (($script:invocations|Where-Object {$_ -eq 'ls --variants --json'}|Measure-Object).Count -gt 0) 'Variant details are queried, not inferred from the model name'
$legacy=[pscustomobject]@{type='llm';path=$profiles[0].Definition.ExpectedPath;modelKey='legacy';deviceIdentifier=$null}
Assert-Variant ($null -ne (Find-LrModel -Models @($legacy) -Profile $profiles[0].Definition)) 'Legacy exact file path remains supported'
$wrong=[pscustomobject]@{type='llm';modelKey=$keys[0]+'@q8_0';path=$keys[0];deviceIdentifier=$null;indexedModelIdentifier=$keys[0]+'@lmstudio-community/Qwen3.8-27B-GGUF/other.gguf'}
$script:models[0].selectedVariant=$wrong.modelKey
$script:groups[0].variants=@($wrong)
Assert-VariantThrow {Assert-LrSelectedModel -LmsPath fixture -LogDirectory fixture -ExpectedPath $profiles[0].Definition.ExpectedPath -ModelPath $keys[0]} 'geaendert' 'Changed selected variant stops before loading'
$script:models[0].selectedVariant=$keys[0]+'@'+$suffixes[0]
$script:groups[0].variants=@()
Assert-VariantThrow {Get-LrDownloadedModels -LmsPath fixture -LogDirectory fixture} 'nicht eindeutig' 'Missing variant metadata fails closed'
$script:groups[0].variants=@([pscustomobject]@{modelKey=$script:models[0].selectedVariant;path=$keys[0];deviceIdentifier=$null;indexedModelIdentifier='unexpected'})
Assert-VariantThrow {Get-LrDownloadedModels -LmsPath fixture -LogDirectory fixture} 'Dateiidentitaet' 'Unverifiable variant source fails closed'
$script:groups[0].variants=@([pscustomobject]@{modelKey=$script:models[0].selectedVariant;path=$keys[0];deviceIdentifier=$null;indexedModelIdentifier=$keys[0]+'@'+$profiles[0].Definition.ExpectedPath})
$script:groups+=@($script:groups[0])
Assert-VariantThrow {Get-LrDownloadedModels -LmsPath fixture -LogDirectory fixture} 'nicht eindeutig' 'Duplicate local groups fail closed'
[pscustomobject]@{suite='LM Studio model variants';passed=$true;checks=$count}|ConvertTo-Json
