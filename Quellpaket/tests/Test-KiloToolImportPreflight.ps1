#requires -Version 7.4
[CmdletBinding()]
param([string]$SourceRoot=(Split-Path -Parent $PSScriptRoot))
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $SourceRoot 'AgentTemplates.ps1')
$testRoot=Join-Path ([IO.Path]::GetTempPath()) ('loki-tool-import-'+[guid]::NewGuid().ToString('N'))
$profileRoot=Join-Path $testRoot 'user'
$install=Join-Path $testRoot 'install'
$oldTestHome=[Environment]::GetEnvironmentVariable('KILO_TEST_HOME','Process')
$count=0
function Assert-Import([bool]$Value,[string]$Message){if(-not $Value){throw "FAIL: $Message"};$script:count++}
function Reject-Import([scriptblock]$Action,[string]$Message){$failed=$false;try{& $Action|Out-Null}catch{$failed=$true};Assert-Import $failed $Message}
function Put-File([string]$Path,[string]$Text){$null=[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path));[IO.File]::WriteAllText($Path,$Text)}
try {
    $null=[IO.Directory]::CreateDirectory($profileRoot)
    $null=[IO.Directory]::CreateDirectory($install)
    [Environment]::SetEnvironmentVariable('KILO_TEST_HOME',$profileRoot,'Process')
    Assert-Import (Assert-ShadowKiloToolImports $install).Verified 'Empty isolated profile permitted'
    foreach($name in @('start','status','cancel','details')){
        Put-File (Join-Path $install "kilo-managed/tools/loki_$name.js") "export { $($name)Tool as default } from '../../app/KiloWorkflowTools.mjs';`n"
    }
    Assert-Import (Assert-ShadowKiloToolImports $install).Verified 'Only exact provisioned shims accepted'
    foreach($relative in @('user/.kilo/tools/collision.js','user/.kilo/tools/uppercase.JS','user/.kilocode/tool/foreign.ts','install/runtime-profile/config/kilo/tools/global.js','install/kilo-managed/tools/extra.js','install/kilo-managed/tool/loki_start.js')){
        $file=Join-Path $testRoot $relative
        Put-File $file 'throw new Error("Must never be imported");'
        Reject-Import {Assert-ShadowKiloToolImports $install} "Block foreign loader path: $relative"
        Assert-Import (([IO.File]::ReadAllText($file)) -ceq 'throw new Error("Must never be imported");') 'Foreign tool preserved'
        Remove-Item -LiteralPath $file
    }
    $changed=Join-Path $install 'kilo-managed/tools/loki_start.js'
    Put-File $changed 'export default {};'
    Reject-Import {Assert-ShadowKiloToolImports $install} 'Reject changed managed shim before registry import'
    Remove-Item -LiteralPath $changed
    $foreign=Join-Path $profileRoot '.kilo/tools/foreign.js'
    Put-File $foreign 'throw new Error("Must never be imported");'
    $fresh=Join-Path $testRoot 'fresh-install'
    Reject-Import {New-ShadowAgentConfiguration -InstallRoot $fresh -ModelId fixture -ApiBaseUrl 'http://127.0.0.1:1/v1'} 'Config generation checks foreign imports before writing managed files'
    Assert-Import (-not(Test-Path -LiteralPath $fresh)) 'Blocked generation leaves installation untouched'
    Remove-Item -LiteralPath $foreign
    if($IsWindows){
        $target=Join-Path $testRoot 'junction-target';$null=[IO.Directory]::CreateDirectory($target)
        $link=Join-Path $install 'kilo-managed/tool'
        # Empty directory left by the earlier fixture; remove only this exact one.
        if(Test-Path -LiteralPath $link){Remove-Item -LiteralPath $link}
        $null=New-Item -ItemType Junction -Path $link -Target $target
        Reject-Import {Assert-ShadowKiloToolImports $install} 'Reject junction in managed import directories'
        Remove-Item -LiteralPath $link
    }
    [pscustomobject]@{suite='Kilo customtool import preflight';passed=$true;checks=$count}|ConvertTo-Json
} finally {
    [Environment]::SetEnvironmentVariable('KILO_TEST_HOME',$oldTestHome,'Process')
    $resolved=[IO.Path]::GetFullPath($testRoot)
    $temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar)+[IO.Path]::DirectorySeparatorChar
    if($resolved.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -and [IO.Path]::GetFileName($resolved).StartsWith('loki-tool-import-') -and (Test-Path -LiteralPath $resolved)){
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
