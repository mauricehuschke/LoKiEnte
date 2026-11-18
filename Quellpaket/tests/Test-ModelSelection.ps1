#requires -Version 7.4
[CmdletBinding()]
param([string]$SourceRoot=(Split-Path -Parent $PSScriptRoot))
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $SourceRoot 'Runtime.ps1')
. (Join-Path $SourceRoot 'Common.ps1')
. (Join-Path $SourceRoot 'ModelSelection.ps1')
$count=0
function Assert-Selection([bool]$Condition,[string]$Message){if(-not $Condition){throw "FAIL: $Message"};$script:count++}
function Assert-SelectionThrow([scriptblock]$Action,[string]$Pattern,[string]$Message){
    $text=$null;try{& $Action|Out-Null}catch{$text=$_.Exception.Message}
    Assert-Selection ($text -and $text -match $Pattern) $Message
}
$catalog=@(Get-ShadowModelCatalog)
Assert-Selection ($catalog.Count -eq 5 -and @($catalog|Where-Object {$_.Id -eq 'qwen3-14b'}).Count -eq 1) 'Curated model catalog contains alternatives'
foreach($model in $catalog){
    Assert-Selection ($model.Revision -match '^[a-f0-9]{40}$' -and @($model.Files|Where-Object {$_.Size -le 0 -or $_.Sha256 -notmatch '^[a-f0-9]{64}$'}).Count -eq 0) "Pinned metadata is complete: $($model.Id)"
}
$script:answers=[Collections.Generic.Queue[string]]::new()
function Read-Host {param($Prompt) if(-not $script:answers.Count){throw 'Unexpected prompt'};return $script:answers.Dequeue()}
$hardware=[pscustomobject]@{Gpu=[pscustomobject]@{FreeBytes=19GB};FreeRamBytes=21.6GB}
foreach($answer in @('','','','','y')){$script:answers.Enqueue($answer)}
$chosen=@(Select-ShadowModels -Hardware $hardware -Downloaded @() -IncludeFastModel)
Assert-Selection ($chosen.Count -eq 4 -and $chosen[0].Alias -ceq 'coder-high' -and $chosen[0].Definition.Id -eq 'qwen3-14b' -and
    $chosen[1].Alias -ceq 'coder-fast' -and $chosen[1].Definition.Id -eq 'qwen35-9b' -and
    $chosen[2].Alias -ceq 'review' -and $chosen[3].Alias -ceq 'fast') 'Hardware-based recommendations select distinct high, fast and review roles'
$oldProfiles=@(
    [pscustomobject]@{Alias='coder';Id='qwen3-14b';Name='Qwen3-14B';ExpectedPath='lmstudio-community/Qwen3-14B-GGUF/Qwen3-14B-Q4_K_M.gguf'},
    [pscustomobject]@{Alias='fast';Id='qwen35-9b';Name='Qwen3.5-9B';ExpectedPath='lmstudio-community/Qwen3.5-9B-GGUF/Qwen3.5-9B-Q4_K_M.gguf'}
)
foreach($answer in @('','','','y')){$script:answers.Enqueue($answer)}
$migrated=@(Select-ShadowModels -Hardware $hardware -Downloaded @() -PreviousProfiles $oldProfiles)
Assert-Selection ($migrated[0].Alias -ceq 'coder-high' -and $migrated[0].Definition.Id -ceq 'qwen3-14b' -and
    $migrated[1].Alias -ceq 'coder-fast' -and $migrated[1].Definition.Id -ceq 'qwen35-9b') 'Legacy coder and fast defaults migrate to separately selectable roles'
$previous=@([pscustomobject]@{Alias='coder';Id='qwen35-9b';Name='Qwen3.5-9B';ExpectedPath='lmstudio-community/Qwen3.5-9B-GGUF/Qwen3.5-9B-Q4_K_M.gguf'})
foreach($answer in @('','y')){$script:answers.Enqueue($answer)}
$chosen=@(Select-ShadowModels -Hardware $hardware -Downloaded @() -PreviousProfiles $previous -Single)
Assert-Selection ($chosen.Count -eq 1 -and $chosen[0].Definition.Id -eq 'qwen35-9b') 'Previously confirmed selection remains default for a restart even when recommendation changes'
foreach($answer in @('','y')){$script:answers.Enqueue($answer)}
$chosen=@(Select-ShadowModels -Hardware $hardware -Downloaded @() -PreviousProfiles $previous -Single -PreferredId 'gpt-oss-20b')
Assert-Selection ($chosen[0].Definition.Id -eq 'gpt-oss-20b') 'Explicit preferred single model takes precedence over saved choice'
foreach($answer in @('','3','y')){$script:answers.Enqueue($answer)}
$smallHardware=[pscustomobject]@{Gpu=[pscustomobject]@{FreeBytes=1GB};FreeRamBytes=4GB}
$chosen=@(Select-ShadowModels -Hardware $smallHardware -Downloaded @() -Single)
Assert-Selection ($chosen[0].Definition.Id -eq 'qwen35-9b' -and $script:answers.Count -eq 0) 'No model is silently preselected when no heuristic candidate fits'
$larger=[pscustomobject]@{Gpu=[pscustomobject]@{FreeBytes=24GB};FreeRamBytes=26GB}
$upgraded=Get-ShadowRecommendedModel -Role coder -Catalog $catalog -Hardware $larger
Assert-Selection ($upgraded.Id -ceq 'qwen38-27b') 'Additional RAM and VRAM can produce a stronger model recommendation on a later run'
foreach($answer in @('2','3','','n')){$script:answers.Enqueue($answer)}
Assert-SelectionThrow {Select-ShadowModels -Hardware $hardware -Downloaded @()} 'cancelled' 'Declining selection prevents downloads'
$root=Join-Path ([IO.Path]::GetTempPath()) ('shadow-selection-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
try{
    $source=Join-Path $root 'source.bin'
    $bytes=[Text.Encoding]::UTF8.GetBytes('synthetic completed model')
    [IO.File]::WriteAllBytes($source,$bytes)
    $sha=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
    $file=@{Name='model.gguf';Size=$bytes.Length;Sha256=$sha}
    $modelRoot=Join-Path $root 'models';[void][IO.Directory]::CreateDirectory($modelRoot)
    Copy-ShadowModelFile -Source $source -ModelRoot $modelRoot -Repository 'test/repo' -File $file
    $target=Join-Path $modelRoot 'test\repo\model.gguf'
    Assert-Selection ((Get-FileHash -LiteralPath $target).Hash -ceq (Get-FileHash -LiteralPath $source).Hash -and (Test-Path -LiteralPath $source)) 'Atomic copy preserves original and produces identical target'
    Copy-ShadowModelFile -Source $source -ModelRoot $modelRoot -Repository 'test/repo' -File $file
    Assert-Selection ([IO.File]::ReadAllText($target) -ceq 'synthetic completed model') 'Identical existing target is reused'
    [IO.File]::WriteAllText($target,'different user content')
    Assert-SelectionThrow {Copy-ShadowModelFile -Source $source -ModelRoot $modelRoot -Repository 'test/repo' -File $file} 'exists' 'Existing conflicting model is never overwritten'
    Assert-Selection ([IO.File]::ReadAllText($target) -ceq 'different user content') 'Conflicting user file remains unchanged'
    $downloadRoot=Join-Path $root 'downloads'
    $fixture=[ordered]@{Id='fixture';Repository='test/repo';Revision=('a'*40)}
    [void][IO.Directory]::CreateDirectory((Join-Path $downloadRoot 'fixture'))
    $partial=Join-Path $downloadRoot 'fixture\model.gguf.partial'
    [IO.File]::WriteAllBytes($partial,$bytes)
    function Resolve-ShadowTool {param($Name) if($Name -eq 'curl'){return 'curl.exe'};throw 'Unexpected tool lookup'}
    function Invoke-ShadowCurl {throw 'Network must not run for verified complete partial'}
    $complete=Invoke-ShadowModelDownload -Model $fixture -File $file -DownloadRoot $downloadRoot
    Assert-Selection ((Test-Path -LiteralPath $complete) -and (Get-FileHash -LiteralPath $complete).Hash -ieq $sha) 'Completed interrupted download is verified and reused without network'
    $lockedPartial=Join-Path $root 'in-use.partial'
    [IO.File]::WriteAllText($lockedPartial,'partial')
    $script:held=[IO.File]::Open($lockedPartial,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    $script:waitCount=0
    function Start-Sleep {param($Seconds) if($Seconds -ne 10){throw 'Unexpected delay'};$script:waitCount++;$script:held.Dispose()}
    Wait-ShadowDownloadFile -Path $lockedPartial
    Assert-Selection ($script:waitCount -eq 1 -and [IO.File]::ReadAllText($lockedPartial) -ceq 'partial') 'An active writer is awaited without altering its partial file'
    $retryModel=@{Id='retry';Repository='test/repo';Revision=('a'*40)}
    [void][IO.Directory]::CreateDirectory((Join-Path $downloadRoot 'retry'))
    $retryPartial=Join-Path $downloadRoot 'retry\model.gguf.partial'
    [IO.File]::WriteAllBytes($retryPartial,$bytes[0..3])
    $script:attempts=0;$script:sleeps=0
    function Start-Sleep {param($Seconds) if($Seconds -ne 30){throw 'Unexpected delay'};$script:sleeps++}
    function Invoke-ShadowCurl {
        param($FilePath,[string[]]$Arguments)
        if($Arguments -notcontains '--continue-at' -or $Arguments -contains '--silent' -or
            $Arguments -notcontains '--proto-redir'){throw 'Resume, visible progress or TLS restriction missing'}
        $script:attempts++
        if($script:attempts -eq 1){return 7}
        $path=$Arguments[[array]::IndexOf($Arguments,'--output')+1]
        $stream=[IO.File]::Open($path,[IO.FileMode]::Append)
        try{$stream.Write($bytes,4,$bytes.Length-4)}finally{$stream.Dispose()}
        return 0
    }
    $retryComplete=Invoke-ShadowModelDownload -Model $retryModel -File $file -DownloadRoot $downloadRoot
    Assert-Selection ($script:attempts -eq 2 -and $script:sleeps -eq 1 -and (Get-FileHash -LiteralPath $retryComplete).Hash -ieq $sha) 'Failed connection retries and continues the preserved partial file'
    $corruptModel=@{Id='corrupt';Repository='test/repo';Revision=('a'*40)}
    [void][IO.Directory]::CreateDirectory((Join-Path $downloadRoot 'corrupt'))
    $corrupt=Join-Path $downloadRoot 'corrupt\model.gguf.partial'
    [IO.File]::WriteAllBytes($corrupt,(New-Object byte[] $bytes.Length))
    $priorAttempts=$script:attempts
    Assert-SelectionThrow {Invoke-ShadowModelDownload -Model $corruptModel -File $file -DownloadRoot $downloadRoot} 'incorrect hash' 'Complete but corrupt partial file is preserved and rejected'
    Assert-Selection ((Test-Path -LiteralPath $corrupt) -and $script:attempts -eq $priorAttempts) 'Corrupt user data is not deleted or silently replaced'
    $targetRoot=Join-Path $root 'registration target'
    [void][IO.Directory]::CreateDirectory($targetRoot)
    $fixtureModel=@{Id='registration';Name='Fixture';Repository='test/repo';ExpectedPath='test/repo/model.gguf';Files=@($file)}
    $definitions=@(@{Alias='coder';Name='Fixture';Definition=$fixtureModel})
    function Resolve-ShadowModelDirectory {return $targetRoot}
    function Invoke-ShadowModelDownload {param($Model,$File,$DownloadRoot) return $source}
    function Get-LrDownloadedModels {param($LmsPath,$LogDirectory) return [pscustomobject]@{path='test/repo/model.gguf';modelKey='fixture'}}
    Install-ShadowSelectedModels -Definitions $definitions -LmsPath 'fixture' -InstallRoot $root
    Assert-Selection ((Get-FileHash -LiteralPath (Join-Path $targetRoot 'test\repo\model.gguf')).Hash -ieq $sha -and (Test-Path -LiteralPath $source)) 'Installer copies verified selection into configured model directory and keeps the source'
    $missingModel=@{Id='missing';Name='Missing';Repository='other/repo';ExpectedPath='other/repo/model.gguf';Files=@($file)}
    Assert-SelectionThrow {Install-ShadowSelectedModels -Definitions @(@{Alias='coder';Definition=$missingModel}) -LmsPath fixture -InstallRoot $root -SkipModelDownload} 'SkipModelDownload' 'Explicit download opt-out never downloads a missing file'
    $outside=Join-Path $root 'outside';[void][IO.Directory]::CreateDirectory($outside)
    $linkedRoot=Join-Path $root 'linked-root'
    $null=New-Item -ItemType Junction -Path $linkedRoot -Target $outside
    Assert-SelectionThrow {Copy-ShadowModelFile -Source $source -ModelRoot $linkedRoot -Repository 'test/repo' -File $file} 'link' 'Model destination junction is refused'
    Assert-Selection (@(Get-ChildItem -LiteralPath $outside -Force).Count -eq 0) 'Junction rejection leaves external files untouched'
    [IO.Directory]::Delete($linkedRoot)
    $raceRoot=Join-Path $root 'race-root'
    [void][IO.Directory]::CreateDirectory($raceRoot)
    $raceTarget=Join-Path $raceRoot 'test\repo\model.gguf'
    function Test-ShadowModelFile {
        param($Path,$Size,$Sha256)
        if($Path -like '*.partial' -and -not(Test-Path -LiteralPath $raceTarget)){
            [IO.File]::WriteAllText($raceTarget,'concurrent user file')
        }
        return $true
    }
    $raceFailure=$null
    try{Copy-ShadowModelFile -Source $source -ModelRoot $raceRoot -Repository 'test/repo' -File $file}catch{$raceFailure=$_.Exception.GetBaseException()}
    Assert-Selection ($raceFailure -is [IO.IOException]) 'Concurrent creation of final destination causes an explicit I/O failure'
    Assert-Selection ([IO.File]::ReadAllText($raceTarget) -ceq 'concurrent user file') 'Atomic publication never replaces a concurrently created model'
    [pscustomobject]@{suite='Model selection and additive files';passed=$true;checks=$count}|ConvertTo-Json
}finally{Remove-Item -LiteralPath $root -Recurse -Force}
