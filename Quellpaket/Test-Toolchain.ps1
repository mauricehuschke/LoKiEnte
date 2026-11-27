#requires -Version 7.4
[CmdletBinding()]
param(
    [string]$InstallRoot=(Split-Path -Parent $PSScriptRoot),
    [switch]$DependenciesOnly,
    [switch]$WaitForProfileClose,
    [switch]$WorkspaceTrust,
    [string]$WorkingDirectory,
    [string]$ResultPath
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
foreach($file in @('Common.ps1','Runtime.ps1','ModelPool.ps1','Router.ps1','AgentTemplates.ps1','Ripgrep.ps1','Workspace.ps1','ProjectSelection.ps1','DesktopRunner.ps1','ToolchainAcceptance.ps1')){. (Join-Path $PSScriptRoot $file)}
Initialize-ShadowToolchainLogging -InstallRoot $InstallRoot
try{
    if($DependenciesOnly){
        if(-not $WorkingDirectory -or -not $ResultPath){throw 'Dependency acceptance requires WorkingDirectory and ResultPath.'}
        $result=Test-ShadowToolchainDependencies -InstallRoot $InstallRoot -WorkingDirectory $WorkingDirectory
        Write-ShadowAcceptanceJson -Path $ResultPath -Value $result
    }else{
        if($WaitForProfileClose){
            $chain=Get-Content -LiteralPath (Join-Path $InstallRoot 'toolchain.json') -Raw|ConvertFrom-Json
            $wait=[Diagnostics.Stopwatch]::StartNew()
            while($wait.Elapsed.TotalSeconds -lt 60){
                try{Assert-ShadowAcceptanceProfileClosed -InstallRoot $InstallRoot -CodePath $chain.codeExecutable;break}catch{Start-Sleep -Milliseconds 500}
            }
        }
        $result=Invoke-ShadowToolchainAcceptance -InstallRoot $InstallRoot -WorkspaceTrust:$WorkspaceTrust
    }
    $result|ConvertTo-Json -Depth 30
    if($result.status -eq 'PASS'){exit 0}
    if($result.status -eq 'BLOCKED'){exit 2}
    exit 1
}catch{
    if($DependenciesOnly -and $ResultPath){
        $result=@{schema=1;kind='installed-toolchain-dependencies';status='BLOCKED';cases=@(@{id='dependencies-prerequisite';status='BLOCKED';evidence=$_.Exception.Message})}
        Write-ShadowAcceptanceJson -Path $ResultPath -Value $result
    }
    Write-Error -Message $_.Exception.Message -ErrorAction Continue
    exit 1
}
