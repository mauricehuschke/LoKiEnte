#requires -Version 7.4
[CmdletBinding()]
param([string]$SourceRoot=(Split-Path -Parent $PSScriptRoot))
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $SourceRoot 'Common.ps1')
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $SourceRoot 'Setup.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Setup syntax errors'}
$definition=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq 'Get-ShadowStartCommands'},$false)
if($null -eq $definition){throw 'Start command helper missing'}
. ([scriptblock]::Create($definition.Extent.Text))
$launcherAst=[Management.Automation.Language.Parser]::ParseFile((Join-Path $SourceRoot 'Start-LocalAI.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Launcher syntax errors'}
$launchDefinition=$launcherAst.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq 'Get-ShadowVsCodeLaunchArguments'},$false)
if($null -eq $launchDefinition){throw 'VS Code launch argument helper missing'}
. ([scriptblock]::Create($launchDefinition.Extent.Text))
$pwsh=(Get-Process -Id $PID).Path
$root=Join-Path ([IO.Path]::GetTempPath()) ("shadow start's `$(`$bad)-"+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory((Join-Path $root 'app'))
try{
    $project="C:\Users\Example\project's `$(`$bad) & data"
    $commands=@(Get-ShadowStartCommands -PowerShellPath $pwsh -InstallRoot $root -ProjectPaths @($project,'C:\Second Project'))
    if($commands.Count -ne 2 -or $commands[0] -notmatch '-ExecutionPolicy Bypass -File' -or
       -not $commands[0].Contains("project''s") -or -not $commands[1].Contains('C:\Second Project')){
        throw 'Multiple project commands or PowerShell literal escaping is wrong'
    }
    $default=@(Get-ShadowStartCommands -PowerShellPath $pwsh -InstallRoot $root)
    if($default.Count -ne 1 -or $default[0].Contains('-ProjectPath')){throw 'No-project command must open project selection without a placeholder'}
    $args=@(Get-ShadowVsCodeLaunchArguments -InstallRoot $root -OpenPath $project)
    $disabled=@(for($i=0;$i -lt $args.Count;$i++){if($args[$i] -ceq '--disable-extension'){$args[$i+1]}})
    if($disabled.Count -ne 2 -or $disabled -cnotcontains 'GitHub.copilot' -or
       $disabled -cnotcontains 'GitHub.copilot-chat' -or $args -cnotcontains '--new-window' -or
       $args -cnotcontains $project -or $args -cnotcontains (Join-Path $root 'vscode-data') -or
       $args -cnotcontains (Join-Path $root 'vscode-extensions')){
        throw 'LoKiEnte launch must disable both Copilot extensions only in its isolated new window'
    }
    $launcher=Join-Path $root 'app\Start-LocalAI.ps1'
    [IO.File]::WriteAllText($launcher,@'
param([string]$InstallRoot,[string]$ProjectPath)
@{InstallRoot=$InstallRoot;ProjectPath=$ProjectPath;Policy=(Get-ExecutionPolicy -Scope Process).ToString()}|
    ConvertTo-Json -Compress|Set-Content -LiteralPath $env:SHADOW_START_TEST_OUTPUT
'@)
    $resultFile=Join-Path $root 'result.json'
    $result=Invoke-ShadowNative -FilePath $pwsh -ArgumentList @('-NoLogo','-NoProfile','-ExecutionPolicy','Restricted','-Command',$commands[0]) -Environment @{SHADOW_START_TEST_OUTPUT=$resultFile} -AllowFailure -Quiet -TimeoutSeconds 30
    if($result.ExitCode -ne 0){throw "Generated command failed under process Restricted: $($result.StdErr)"}
    $received=Get-Content -LiteralPath $resultFile -Raw|ConvertFrom-Json
    if($received.InstallRoot -cne $root -or $received.ProjectPath -cne $project -or $received.Policy -cne 'Bypass'){
        throw 'Generated command did not preserve literal arguments or process policy'
    }
    [pscustomobject]@{suite='PowerShell 7 start commands';passed=$true;checks=5}|ConvertTo-Json
}finally{Remove-Item -LiteralPath $root -Recurse -Force}
