#requires -Version 7.4
[CmdletBinding()]
param([string]$SourceRoot=(Split-Path -Parent $PSScriptRoot),[string]$VerifiedArchivePath,[string]$KiloNativePath,[string]$KiloEntryPath)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $SourceRoot 'Common.ps1')
. (Join-Path $SourceRoot 'ModelSelection.ps1')
. (Join-Path $SourceRoot 'AgentTemplates.ps1')
. (Join-Path $SourceRoot 'Ripgrep.ps1')
$root=Join-Path ([IO.Path]::GetTempPath()) ('shadow-ripgrep-test-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
$count=0
function Assert-Rg([bool]$Condition,[string]$Message){if(-not $Condition){throw "FAIL: $Message"};$script:count++}
function Assert-RgThrow([scriptblock]$Action,[string]$Pattern,[string]$Message){
    $failure=$null;try{& $Action|Out-Null}catch{$failure=$_.Exception.Message}
    Assert-Rg ($failure -and $failure -match $Pattern) $Message
}
$script:archiveBytes=[byte[]](1,2,3)
$script:downloads=0
function Get-ShadowRipgrepArchive {param($Url) $script:downloads++;return ,$script:archiveBytes}
try{
    $missing=Join-Path $root 'missing'
    Assert-RgThrow {Assert-ShadowRipgrepReady $missing} 'Ripgrep fehlt' 'Missing ripgrep is an explicit startup failure'
    Assert-RgThrow {Install-ShadowRipgrep $missing} 'ungueltige SHA256' 'Unverified archive is rejected'
    Assert-Rg (-not(Test-Path -LiteralPath (Get-ShadowRipgrepInfo $missing).Path)) 'Unverified archive writes no executable'
    $foreign=Join-Path $root 'foreign'
    $foreignPath=(Get-ShadowRipgrepInfo $foreign).Path
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $foreignPath))
    [IO.File]::WriteAllText($foreignPath,'existing user file')
    $before=$script:downloads
    Assert-RgThrow {Install-ShadowRipgrep $foreign} 'unbekannte Pruefsumme' 'Unknown existing executable is rejected'
    Assert-Rg ([IO.File]::ReadAllText($foreignPath) -ceq 'existing user file' -and $script:downloads -eq $before) 'Unknown executable is preserved without downloading or executing it'
    if($VerifiedArchivePath){
        $script:archiveBytes=[IO.File]::ReadAllBytes($VerifiedArchivePath)
        $managed=Join-Path $root 'managed'
        $path=Install-ShadowRipgrep -InstallRoot $managed
        $info=Get-ShadowRipgrepInfo $managed
        Assert-Rg ($path -ceq $info.Path -and (Get-FileHash -LiteralPath $path).Hash -ieq $info.ExecutableSha256) 'Official archive installs the exact verified executable'
        $before=$script:downloads
        $path2=Install-ShadowRipgrep -InstallRoot $managed
        Assert-Rg ($path2 -ceq $path -and $script:downloads -eq $before) 'Verified existing executable is reused without download'
        $catalog=[ordered]@{
            coder=@{id='shadow-coder';name='Synthetic coder';context=32768;output=8192}
            review=@{id='shadow-review';name='Synthetic review';context=32768;output=8192}
            fast=@{id='shadow-fast';name='Synthetic fast';context=32768;output=8192}
        }
        $configuration=New-ShadowAgentConfiguration -InstallRoot $managed -ModelCatalog $catalog -MainModel coder -ApiBaseUrl 'http://127.0.0.1:1235/v1'
        $configJson=$configuration.Config|ConvertTo-Json -Depth 40 -Compress
        $originalPath=[Environment]::GetEnvironmentVariable('PATH','Process')
        $environment=Get-ShadowLocalEnvironment -InstallRoot $managed -ConfigJson $configJson
        $expectedBin=Split-Path -Parent $path
        Assert-Rg ($environment.PATH.EndsWith($expectedBin,[StringComparison]::OrdinalIgnoreCase) -and
            [Environment]::GetEnvironmentVariable('PATH','Process') -ceq $originalPath) 'Managed bin is appended only to child PATH without changing the user or process PATH'
        if($KiloNativePath){
            Test-ShadowKiloSearch -InstallRoot $managed -KiloExecutable $KiloNativePath -ConfigJson $configJson
            $count++
        }
        if($KiloEntryPath){
            $node=(Get-Command node.exe -CommandType Application|Select-Object -First 1).Source
            Test-ShadowKiloSearch -InstallRoot $managed -KiloExecutable $node -KiloArgumentPrefix @($KiloEntryPath) -ConfigJson $configJson
            $count++
        }
    }else{Write-Host 'Official archive and real Kilo integration were not requested in this run.'}
    [pscustomobject]@{suite='Managed ripgrep';passed=$true;checks=$count;realArchive=[bool]$VerifiedArchivePath;realNativeKilo=[bool]$KiloNativePath;realWrapperKilo=[bool]$KiloEntryPath}|ConvertTo-Json
}finally{Remove-Item -LiteralPath $root -Recurse -Force}
