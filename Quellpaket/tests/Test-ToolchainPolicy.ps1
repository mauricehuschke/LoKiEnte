#requires -Version 7.4
param([string]$SourceRoot=(Split-Path -Parent $PSScriptRoot))
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $SourceRoot 'ToolchainAcceptance.ps1')
$checks=0
function Assert-Policy($Value,[string]$Message){if(-not $Value){throw $Message};$script:checks++}
$launch=@(Get-ShadowAcceptanceLaunchArguments -Project 'D:\Synthetic Test\project' -DataDirectory 'D:\Synthetic Test\profile' -ExtensionsDirectory 'D:\Synthetic Test\extensions')
Assert-Policy ($launch[0] -ceq 'D:\Synthetic Test\project' -and $launch[[array]::IndexOf($launch,'--user-data-dir')+1] -ceq 'D:\Synthetic Test\profile') 'Normal acceptance launch must retain isolated workspace and profile paths with spaces.'
Assert-Policy ($launch -notcontains '--extensionTestsPath' -and $launch -notcontains '--extensionDevelopmentPath') 'Live acceptance must use the installed helper in an ordinary window, allowing the real trust workflow.'
Assert-Policy ($launch -notcontains '--disable-workspace-trust' -and $launch -notcontains '--disable-extensions' -and $launch -contains '--extensions-dir') 'Acceptance must preserve trust policy and load the installed extensions.'
function Read-Host { param($Prompt) throw 'Explicit switches must not prompt.' }
Assert-Policy ((Select-ShadowAcceptanceMode -RunAcceptanceTest) -ceq 'Run') 'Explicit run must run.'
Assert-Policy ((Select-ShadowAcceptanceMode -SkipAcceptanceTest) -ceq 'Skip') 'Explicit skip must skip.'
Assert-Policy ((Select-ShadowAcceptanceMode) -ceq 'Blocked') 'Unavailable input must not silently pass or skip.'
$failed=$false;try{Select-ShadowAcceptanceMode -RunAcceptanceTest -SkipAcceptanceTest}catch{$failed=$true}
Assert-Policy $failed 'Contradictory flags must fail.'
function Read-Host { param($Prompt) return '' }
Assert-Policy ((Select-ShadowAcceptanceMode) -ceq 'Run') 'Empty answer must run acceptance.'
foreach($answer in @('n','N','nein','no')){
    $script:answer=$answer
    function Read-Host { param($Prompt) return $script:answer }
    Assert-Policy ((Select-ShadowAcceptanceMode) -ceq 'Skip') 'Explicit negative answer must skip.'
}
foreach($answer in @('y','j','ja','yes')){
    $script:answer=$answer
    function Read-Host { param($Prompt) return $script:answer }
    Assert-Policy ((Select-ShadowAcceptanceMode) -ceq 'Run') 'Positive answer must run.'
}
$request=Get-Content (Join-Path $SourceRoot 'Invoke-SetupRequest.ps1') -Raw
$bootstrap=Get-Content (Join-Path (Split-Path -Parent $SourceRoot) 'Provision-LoKiEnte.ps1') -Raw
foreach($flag in @('RunAcceptanceTest','SkipAcceptanceTest')){
    Assert-Policy ($request.Contains("'$flag'")) "Request wrapper must allow $flag."
    Assert-Policy ($bootstrap.Contains("${flag}=[bool]`$$flag")) "Bootstrap must forward $flag."
}
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('lokiente-live-preparation-'+[guid]::NewGuid().ToString('N'))
try{
    [void][IO.Directory]::CreateDirectory((Join-Path $fixture 'runtime'))
    [void][IO.Directory]::CreateDirectory((Join-Path $fixture 'kilo-managed'))
    $executable=(Get-Process -Id $PID).Path
    Write-ShadowAcceptanceJson -Path (Join-Path $fixture 'toolchain.json') -Value @{codeExecutable=$executable;powerShellExecutable=$executable;nodeExecutable=$executable}
    [IO.File]::WriteAllText((Join-Path $fixture 'kilo-managed/kilo.json'),'{}')
    [IO.File]::WriteAllText((Join-Path $fixture 'runtime/model-pool.json'),'{}')
    $script:prepared=0;$script:inspected=0;$script:busy=$false
    function Write-ShadowMessage {param($Message,$Level)}
    function Start-ShadowModelRouter {param($InstallRoot,$Pool,$NodePath,$PowerShellPath) $script:prepared++;if($script:busy){throw 'SYNTHETIC_BUSY_ROUTER_PRESERVED'};return @{Status='Ready'}}
    function Get-ShadowBundledKilo {
        param($CodePath,$InstallRoot)
        $script:inspected++
        $directory=Get-ChildItem -LiteralPath (Join-Path $InstallRoot 'diagnostics/toolchain') -Directory|Sort-Object CreationTimeUtc -Descending|Select-Object -First 1
        $file=Join-Path $directory.FullName 'acceptance.json';$partial=Get-Content -LiteralPath $file -Raw|ConvertFrom-Json -AsHashtable
        $partial.cases=@(@{id='completed-before-launch-failure';status='PASS';evidence='Synthetic completed boundary.'})
        Write-ShadowAcceptanceJson -Path $file -Value $partial
        throw 'SYNTHETIC_MISSING_KILO_NO_PROCESS_STARTED'
    }
    $result=Invoke-ShadowToolchainAcceptance -InstallRoot $fixture
    Assert-Policy ($prepared -eq 1 -and $inspected -eq 1) 'Live acceptance must prepare the guarded router before inspecting/launching Kilo.'
    Assert-Policy ($result.status -ceq 'BLOCKED') 'Missing live prerequisites must produce BLOCKED, never PASS.'
    Assert-Policy ($result.cases[0].id -eq 'completed-before-launch-failure' -and $result.cases.Count -eq 2) 'A later launch failure must retain earlier completed evidence.'
    $xml=[xml](Get-Content (Join-Path $fixture 'diagnostics/toolchain/latest.junit.xml') -Raw)
    Assert-Policy ($xml.testsuites.testsuite.skipped -eq '1') 'Blocked live launch must replace latest JUnit with blocked/skipped evidence.'
    $script:busy=$true
    $result=Invoke-ShadowToolchainAcceptance -InstallRoot $fixture
    Assert-Policy ($result.status -ceq 'BLOCKED' -and $inspected -eq 1 -and $result.cases[0].evidence -match 'BUSY_ROUTER_PRESERVED') 'A busy router must block acceptance before launching another process.'
}finally{
    $resolved=[IO.Path]::GetFullPath($fixture)
    if(-not $resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notlike 'lokiente-live-preparation-*'){throw 'Unsafe cleanup'}
    if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
@{suite='Toolchain acceptance policy (synthetic input boundaries)';checks=$checks;passed=$true}|ConvertTo-Json
