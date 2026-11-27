#requires -Version 7.4
param([string]$SourceRoot=(Split-Path -Parent $PSScriptRoot))
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
foreach($name in @('ModelPool.ps1','Indexing.ps1','AgentTemplates.ps1')){. (Join-Path $SourceRoot $name)}
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('lokiente-index-launch-'+[guid]::NewGuid().ToString('N'))
$null=[IO.Directory]::CreateDirectory((Join-Path $fixture 'runtime'))
$count=0
$Desktop=$false
function Assert-Launch([bool]$Value,[string]$Message){if(-not $Value){throw $Message};$script:count++}
function Read-Host {param($Prompt) $script:answer}
function Start-ShadowModelRouter {$script:routerCalls++;return @{ApiBaseUrl='http://127.0.0.1:1235/v1'}}
function Stop-ShadowEmbeddingModel {$script:stopCalls++}
function Initialize-ShadowEmbeddingModel {$script:initCalls++;return @{Status=$script:resultStatus;InstanceId=('shadow-'+('a'*24)+'-embedding')}}
function Get-ShadowEmbeddingDefinition {@{}}
function Get-ShadowPoolCatalog {@{coder=@{id='fixture';name='Fixture';context=32768;output=8192}}}
try {
    # Execute the actual launch policy/configuration statements, without opening
    # VS Code or invoking LM Studio. Config generation and persisted status are real.
    $tokens=$null;$errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $SourceRoot 'Start-LocalAI.ps1'),[ref]$tokens,[ref]$errors)
    if($errors.Count){throw 'Launcher syntax error'}
    $tryNode=@($ast.EndBlock.Statements|Where-Object {$_ -is [Management.Automation.Language.TryStatementAst]})[0]
    $statements=@($tryNode.Body.Statements)
    $start=@(0..($statements.Count-1)|Where-Object {$statements[$_].Extent.Text.StartsWith('$chain=Get-Content')})[0]
    $end=@(0..($statements.Count-1)|Where-Object {$statements[$_].Extent.Text.StartsWith('if($ProjectPath)')})[0]-1
    if($end -le $start){throw 'Launcher configuration boundaries were not found'}
    $launch=[scriptblock]::Create(($statements[$start..$end]|ForEach-Object {$_.Extent.Text}) -join "`n")
    $InstallRoot=$fixture;$toolchainFile=Join-Path $fixture 'toolchain.json'
    [IO.File]::WriteAllText((Join-Path $fixture 'runtime/model-pool.json'),'{"PrimaryAlias":"coder","ApiTokenEnvironmentVariable":""}')
    $cases=@(
        @{mode=$null;answer='y';load=0;stop=1;enabled=$false;status='Ready'},
        @{mode='Off';answer='y';load=0;stop=1;enabled=$false;status='Ready'},
        @{mode='OnDemand';answer='';load=0;stop=1;enabled=$false;status='Ready'},
        @{mode='OnDemand';answer='y';load=1;stop=0;enabled=$true;status='Ready'},
        @{mode='Automatic';answer='';load=1;stop=0;enabled=$true;status='Ready'},
        @{mode='Automatic';answer='';load=1;stop=0;enabled=$false;status='Deferred'}
    )
    foreach($case in $cases){
        $chainState=@{modelMode='Dual';nodeExecutable='fixture';powerShellExecutable='fixture'}
        if($null -ne $case.mode){$chainState.indexingMode=$case.mode}
        [IO.File]::WriteAllText($toolchainFile,($chainState|ConvertTo-Json))
        $script:answer=$case.answer;$script:resultStatus=$case.status
        $script:routerCalls=0;$script:initCalls=0;$script:stopCalls=0;$StartIndexing=$false
        . $launch
        Assert-Launch ($script:initCalls -eq $case.load -and $script:stopCalls -eq $case.stop -and $configuration.Config.indexing.enabled -eq $case.enabled) "Launch mode $($case.mode) with $($case.status) violated indexing policy"
    }
    [IO.File]::WriteAllText($toolchainFile,'{"modelMode":"Dual","indexingMode":"Off"}')
    $StartIndexing=$true;$script:routerCalls=0;$failure=''
    try{. $launch}catch{$failure=$_.Exception.Message}
    Assert-Launch ($failure -match 'Indexing is disabled' -and $script:routerCalls -eq 0) 'An Off override must fail before starting runtime services'
    [IO.File]::WriteAllText($toolchainFile,'{"modelMode":"Single","indexingMode":"Automatic"}')
    $StartIndexing=$false;$failure=''
    try{. $launch}catch{$failure=$_.Exception.Message}
    Assert-Launch ($failure -match 'Dual model pool' -and $script:routerCalls -eq 0) 'Unsupported saved Single indexing must fail before starting services'
    [pscustomobject]@{suite='Indexing launch integration';passed=$true;checks=$count;limitations='LM Studio and router are mocked; actual launcher selection/config generation runs.'}|ConvertTo-Json
} finally {
    $resolved=[IO.Path]::GetFullPath($fixture)
    if(-not $resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notlike 'lokiente-index-launch-*'){throw 'Unsafe cleanup'}
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
