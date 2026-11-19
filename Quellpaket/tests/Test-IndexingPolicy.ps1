#requires -Version 7.4
[CmdletBinding()]
param([string]$SourceRoot=(Split-Path -Parent $PSScriptRoot),[string]$BootstrapPath=(Join-Path (Split-Path -Parent $SourceRoot) 'Provision-LoKiEnte.ps1'))
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
foreach($name in @('ModelPool.ps1','Indexing.ps1','AgentTemplates.ps1','ModelSelection.ps1')){. (Join-Path $SourceRoot $name)}
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('lokiente-indexing-policy-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($fixture)
$count=0;$script:answer='';$script:prompts=0;$script:cannotPrompt=$false
function Assert-Indexing([bool]$Condition,[string]$Message){if(-not $Condition){throw "FAIL: $Message"};$script:count++}
function Reject-Indexing([scriptblock]$Action,[string]$Pattern){$errorMessage='';try{& $Action|Out-Null}catch{$errorMessage=$_.Exception.Message};Assert-Indexing ($errorMessage -match $Pattern) "Expected rejection: $Pattern"}
function Read-Host {param($Prompt) $script:prompts++;if($script:cannotPrompt){throw 'noninteractive'};return $script:answer}
try {
    Assert-Indexing ((Get-ShadowIndexingMode -Toolchain @{}) -ceq 'Off') 'Legacy installations default to Off instead of inheriting indexing'
    foreach($mode in @('Off','OnDemand','Automatic')){Assert-Indexing ((Get-ShadowIndexingMode -Toolchain @{indexingMode=$mode}) -ceq $mode) 'Saved launch mode is recognized'}
    Assert-Indexing ((Get-ShadowIndexingMode -Toolchain @{indexingMode='automatic'}) -ceq 'Automatic') 'PowerShell case-insensitive parameter values remain valid'
    Reject-Indexing {Get-ShadowIndexingMode -Toolchain @{indexingMode='unexpected'}} 'Unknown indexing mode'
    Assert-Indexing (-not (Select-ShadowIndexingForLaunch -Mode Off) -and $script:prompts -eq 0) 'Off never asks or starts'
    Reject-Indexing {Select-ShadowIndexingForLaunch -Mode Off -StartIndexing} 'Indexing is disabled'
    Assert-Indexing ((Select-ShadowIndexingForLaunch -Mode Automatic) -and $script:prompts -eq 0) 'Automatic starts without a launcher prompt'
    Assert-Indexing ((Select-ShadowIndexingForLaunch -Mode OnDemand -StartIndexing) -and $script:prompts -eq 0) 'Explicit one-launch opt-in is supported'
    foreach($answer in @('','n','yes','Y')){
        $script:answer=$answer
        Assert-Indexing ((Select-ShadowIndexingForLaunch -Mode OnDemand) -eq ($answer -ieq 'y')) 'OnDemand starts only after a deliberate y'
    }
    $script:cannotPrompt=$true
    Assert-Indexing (-not (Select-ShadowIndexingForLaunch -Mode OnDemand)) 'Noninteractive OnDemand remains off'
    $script:cannotPrompt=$false
    $tokens=$null;$errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile($BootstrapPath,[ref]$tokens,[ref]$errors)
    if($errors.Count){throw 'Bootstrap syntax error'}
    foreach($name in @('Select-BootstrapIndexingMode','Read-BootstrapOptionState','Assert-BootstrapNoReparsePoint')){
        $definition=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq $name},$false)
        . ([scriptblock]::Create($definition.Extent.Text))
    }
    foreach($selection in @(@('','Off'),@('0','Off'),@('1','OnDemand'),@('2','Automatic'))){
        $script:answer=$selection[0]
        Assert-Indexing ((Select-BootstrapIndexingMode) -ceq $selection[1]) 'Provisioning selection maps to an explicit mode'
    }
    $script:answer='invalid';Reject-Indexing {Select-BootstrapIndexingMode} 'Invalid indexing selection'
    Assert-Indexing ((Select-BootstrapIndexingMode -ResolvedModelMode Single) -ceq 'Off') 'Single mode does not offer unavailable indexing'
    [IO.File]::WriteAllText((Join-Path $fixture 'shadow-local-ai-install.json'),'{}')
    [IO.File]::WriteAllText((Join-Path $fixture 'provisioning-options.json'),'{"ModelMode":"Dual","IndexingMode":"Automatic"}')
    $savedOptions=Read-BootstrapOptionState -Root $fixture
    Assert-Indexing ($savedOptions.ModelMode -ceq 'Dual' -and -not $savedOptions.ContainsKey('IndexingMode')) 'Reprovisioning does not silently inherit previous automatic indexing'
    $inactive=Set-ShadowIndexingInactive -InstallRoot $fixture -Mode Off
    Assert-Indexing ($inactive.Status -ceq 'Disabled' -and -not(Test-Path (Join-Path $fixture 'tooling/lancedb'))) 'Off records an intentional disabled state without installing indexing dependencies'
    $prepared=Set-ShadowIndexingInactive -InstallRoot $fixture -Mode OnDemand
    Assert-Indexing ($prepared.Status -ceq 'OnDemand' -and $prepared.SmokeTest -ceq 'NotRun') 'OnDemand preparation makes no false inference claim'
    foreach($status in @('Disabled','OnDemand','Deferred')){
        Assert-Indexing ((Get-ShadowEmbeddingConfigurationArguments -Embedding @{Status=$status} -ApiBaseUrl 'http://127.0.0.1:1235/v1').Count -eq 0) 'Inactive or failed readiness never enables Kilo indexing'
    }
    $config=New-ShadowAgentConfiguration -InstallRoot $fixture -ModelId 'fixture' -ApiBaseUrl 'http://127.0.0.1:1235/v1'
    $envMap=Get-ShadowLocalEnvironment -InstallRoot $fixture -ConfigJson ($config.Config|ConvertTo-Json -Depth 40)
    Assert-Indexing ($config.Config.indexing.enabled -eq $false -and $envMap.KILO_DISABLE_CODEBASE_INDEXING -ceq '1' -and -not $envMap.ContainsKey('KILO_LANCEDB_PATH')) 'Default config disables indexing without requiring LanceDB'
    Assert-Indexing ($config.Config.permission['*'] -ceq 'deny' -and -not $config.Config.permission.Contains('semantic_search') -and $config.Config.permission.grep -ceq 'allow') 'File search remains available without semantic-search permission'
    $id='shadow-'+('a'*24)+'-embedding'
    $enabled=New-ShadowAgentConfiguration -InstallRoot $fixture -ModelId 'fixture' -ApiBaseUrl 'http://127.0.0.1:1235/v1' -EmbeddingModelId $id -EmbeddingApiBaseUrl 'http://127.0.0.1:1235/v1'
    Assert-Indexing ($enabled.Config.indexing.enabled -eq $true -and $enabled.Config.permission.semantic_search -ceq 'allow') 'Verified embedding arguments explicitly enable indexing'
    $disabled=New-ShadowAgentConfiguration -InstallRoot $fixture -ModelId 'fixture' -ApiBaseUrl 'http://127.0.0.1:1235/v1'
    Assert-Indexing ($disabled.Config.indexing.enabled -eq $false -and -not $disabled.Config.indexing.Contains('provider')) 'Reprovisioning overwrites a previously enabled managed config with Off'
    Assert-Indexing (@(Get-ChildItem -LiteralPath (Join-Path $fixture 'kilo-managed') -Filter 'kilo.json.backup-*').Count -gt 0) 'Prior managed configuration remains backed up'
    [pscustomobject]@{suite='Optional indexing policy and migration';passed=$true;checks=$count}|ConvertTo-Json
} finally {
    $resolved=[IO.Path]::GetFullPath($fixture)
    if(-not $resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notlike 'lokiente-indexing-policy-*'){throw 'Unsafe cleanup'}
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
