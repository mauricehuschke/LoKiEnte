#requires -Version 7.4
[CmdletBinding()]
param([string]$SourceRoot=(Split-Path -Parent $PSScriptRoot))
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $SourceRoot 'Common.ps1')
$root=Join-Path ([IO.Path]::GetTempPath()) ('shadow-vscode-cli-'+[guid]::NewGuid().ToString('N'))
$count=0
function Assert-Code([bool]$Condition,[string]$Message){if(-not $Condition){throw "FAIL: $Message"};$script:count++}
function Assert-CodeThrow([scriptblock]$Action,[string]$Pattern,[string]$Message){
    $text=$null;try{& $Action|Out-Null}catch{$text=$_.Exception.Message}
    Assert-Code ($text -and $text -match $Pattern) $Message
}
function Write-Fixture([string]$Path,[string]$Text){
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path))
    [IO.File]::WriteAllText($Path,$Text)
}
try{
    $code=Join-Path $root 'VS Code\Code.exe'
    $base=Split-Path -Parent $code
    $wrapper=Join-Path $base 'bin\code.cmd'
    $old=Join-Path $base 'resources\app\out\cli.js'
    $active=Join-Path $base '69047191fc\resources\app\out\cli.js'
    Write-Fixture $code 'fixture'
    Write-Fixture $old 'old'
    Assert-Code ((Resolve-ShadowCodeCli $code) -ceq $old) 'Classic layout works without wrapper'
    Write-Fixture $wrapper '"%~dp0..\Code.exe" "%~dp0..\resources\app\out\cli.js" %*'
    Assert-Code ((Resolve-ShadowCodeCli $code) -ceq $old) 'Classic wrapper is resolved'
    Write-Fixture $active 'active'
    Write-Fixture $wrapper ('@echo off'+[Environment]::NewLine+'"%~dp0..\Code.exe" "%~dp0..\69047191fc\resources\app\out\cli.js" %*')
    Assert-Code ((Resolve-ShadowCodeCli $code) -ceq $active) 'Wrapper-selected version wins over stale classic CLI'
    Write-Fixture $wrapper '"%~dp0..\Code.exe" "%~dp0..\other-version\resources\app\out\cli.js" %*'
    Assert-CodeThrow {Resolve-ShadowCodeCli $code} 'missing.*other-version' 'Missing active version is not silently replaced by another CLI'
    Write-Fixture $wrapper '"%~dp0..\Code.exe" "%~dp0..\..\outside\resources\app\out\cli.js" %*'
    Assert-CodeThrow {Resolve-ShadowCodeCli $code} 'not unique|not.*uniquely|ambiguous' 'Parent traversal is rejected'
    Write-Fixture $wrapper ('"%~dp0..\Code.exe" "%~dp0..\resources\app\out\cli.js" %*'+[Environment]::NewLine+'"%~dp0..\Code.exe" "%~dp0..\69047191fc\resources\app\out\cli.js" %*')
    Assert-CodeThrow {Resolve-ShadowCodeCli $code} 'not unique|not.*uniquely|ambiguous' 'Multiple wrapper entries are rejected'
    Write-Fixture $wrapper '"%~dp0..\Code.exe" "%~dp0..\69047191fc\resources\app\out\cli.js" %*'
    $script:invoked=$null
    $script:cliOutput='ok'
    function Invoke-ShadowNative {
        param($FilePath,$ArgumentList,$Environment,$TimeoutSeconds)
        $script:invoked=[pscustomobject]@{file=$FilePath;arguments=$ArgumentList;environment=$Environment;timeout=$TimeoutSeconds}
        return [pscustomobject]@{ExitCode=0;StdOut=$script:cliOutput;StdErr=''}
    }
    $profile=Join-Path $root 'isolated profile'
    $extensionDir=Join-Path $root 'isolated extensions'
    $null=Invoke-ShadowCodeCli -CodePath $code -Arguments @('--user-data-dir',$profile,'--extensions-dir',$extensionDir,'--list-extensions')
    Assert-Code ($script:invoked.file -ceq $code -and $script:invoked.arguments[0] -ceq $active -and
        $script:invoked.arguments[2] -ceq $profile -and $script:invoked.arguments[4] -ceq $extensionDir -and
        $script:invoked.environment.ELECTRON_RUN_AS_NODE -ceq '1' -and $script:invoked.timeout -eq 1200) 'Native invocation preserves executable, active CLI, isolated paths and environment'
    $installRoot=Join-Path $root 'managed root'
    $extensionRoot=Join-Path $installRoot 'vscode-extensions'
    $ext=Join-Path $extensionRoot 'kilocode.kilo-code-7.8.27-win32-x64'
    Write-Fixture (Join-Path $ext 'package.json') '{"publisher":"kilocode","name":"kilo-code","version":"7.8.27"}'
    Write-Fixture (Join-Path $ext 'bin\kilo.exe') 'mock binary'
    $oldExt=Join-Path $extensionRoot 'kilocode.kilo-code-7.8.26'
    Write-Fixture (Join-Path $oldExt 'package.json') '{"publisher":"kilocode","name":"kilo-code","version":"7.8.26"}'
    $script:cliOutput="other.extension@1.2.3`nkilocode.kilo-code@7.8.27`n"
    $bundled=(Get-ShadowBundledKilo -CodePath $code -InstallRoot $installRoot)
    Assert-Code ([IO.Path]::GetFullPath($bundled) -ieq [IO.Path]::GetFullPath((Join-Path $ext 'bin\kilo.exe')) -and
        $script:invoked.arguments -contains '--list-extensions' -and $script:invoked.arguments -contains '--show-versions' -and
        $script:invoked.arguments -notcontains '--locate-extension') 'Select CLI-reported extension version in isolated root without unsupported location switch'
    $script:cliOutput='kilocode.kilo-code@7.8.27'+"`n"+'kilocode.kilo-code@7.8.26'
    Assert-CodeThrow {Get-ShadowBundledKilo -CodePath $code -InstallRoot $installRoot} 'not report a unique' 'Ambiguous installed versions fail explicitly'
    $script:cliOutput='kilocode.kilo-code@7.8.27'
    $duplicate=Join-Path $extensionRoot 'kilocode.kilo-code-duplicate'
    Write-Fixture (Join-Path $duplicate 'package.json') '{"publisher":"kilocode","name":"kilo-code","version":"7.8.27"}'
    Assert-CodeThrow {Get-ShadowBundledKilo -CodePath $code -InstallRoot $installRoot} 'not unique|not.*uniquely|ambiguous' 'Duplicate matching manifests are rejected'
    Remove-Item -LiteralPath $duplicate -Recurse -Force
    Remove-Item -LiteralPath (Join-Path $ext 'bin\kilo.exe')
    Assert-CodeThrow {Get-ShadowBundledKilo -CodePath $code -InstallRoot $installRoot} 'expected current CLI' 'Missing bundled binary fails explicitly'
    $tokens=$null;$errors=$null
    $setupAst=[Management.Automation.Language.Parser]::ParseFile((Join-Path $SourceRoot 'Setup.ps1'),[ref]$tokens,[ref]$errors)
    if($errors.Count){throw 'Setup parser errors'}
    foreach($name in @('Get-ShadowKiloExtensionVersion','Get-ShadowKiloExtensionInstallSpec')){
        $definition=$setupAst.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq $name},$false)
        if(-not $definition){throw "Missing helper: $name"}
        . ([scriptblock]::Create($definition.Extent.Text))
    }
    $main=@($setupAst.EndBlock.Statements|Where-Object {$_ -is [Management.Automation.Language.TryStatementAst]})[0]
    $statements=@($main.Body.Statements);$first=-1;$last=-1
    for($i=0;$i -lt $statements.Count;$i++){
        if($statements[$i].Extent.Text -match '^\$codeArgs='){$first=$i}
        if($statements[$i].Extent.Text -match '^\$bundledKilo='){$last=$i;break}
    }
    if($first -lt 0 -or $last -le $first){throw 'Kilo extension setup section missing'}
    $section=[scriptblock]::Create((@($statements[$first..($last-1)]|ForEach-Object {$_.Extent.Text}) -join "`n"))
    function Invoke-ShadowCodeCli {
        param($CodePath,$Arguments)
        if($Arguments -contains '--install-extension'){
            $spec=$Arguments[[array]::IndexOf($Arguments,'--install-extension')+1]
            $script:installs+=@($spec)
            if($spec -cmatch '^kilocode\.kilo-code@(\d+\.\d+\.\d+)$'){$script:installedVersion=$Matches[1]}
            else{$script:installedVersion='7.8.30'}
            return [pscustomobject]@{StdOut='installed';ExitCode=0}
        }
        $value=if($script:installedVersion){'kilocode.kilo-code@'+$script:installedVersion}else{''}
        return [pscustomobject]@{StdOut=$value;ExitCode=0}
    }
    function Invoke-ExtensionSection {
        param([string]$Version,[string]$Approved='7.8.30')
        $script:installedVersion=$Version;$script:installs=@()
        $versions=@{kiloVsCode=$Approved};$profileRoot='profile';$extensionsRoot='extensions';$report=[ordered]@{}
        . $section
        return $report
    }
    $result=Invoke-ExtensionSection -Version '7.8.30'
    Assert-Code ($result.kiloVsCodeExtensionVersion -ceq '7.8.30' -and $script:installs.Count -eq 0) 'Existing Kilo 7.8.30 is retained without reinstallation or downgrade'
    $result=Invoke-ExtensionSection -Version '7.8.28'
    Assert-Code ($result.kiloVsCodeExtensionVersion -ceq '7.8.30' -and $script:installs.Count -eq 1 -and $script:installs[0] -ceq 'kilocode.kilo-code@7.8.30') 'Regular provisioning upgrades to the tested newer extension'
    $result=Invoke-ExtensionSection -Version ''
    Assert-Code ($result.kiloVsCodeExtensionVersion -ceq '7.8.30' -and $script:installs[0] -ceq 'kilocode.kilo-code@7.8.30') 'Fresh Dual setup installs the tested extension'
    $result=Invoke-ExtensionSection -Version '7.8.31'
    Assert-Code ($result.kiloVsCodeExtensionVersion -ceq '7.8.31' -and $script:installs.Count -eq 0) 'Newer installed extension is retained for subsequent compatibility checks'
    $result=Invoke-ExtensionSection -Version '7.8.31' -Approved '7.9.0'
    Assert-Code ($result.kiloVsCodeExtensionVersion -ceq '7.9.0' -and $script:installs[0] -ceq 'kilocode.kilo-code@7.9.0') 'Explicitly approved newer target is installed exactly'
    Assert-CodeThrow {Get-ShadowKiloExtensionVersion -Output "kilocode.kilo-code@7.8.28`nkilocode.kilo-code@7.8.30"} 'Multiple' 'Ambiguous extension versions are rejected'
    Assert-CodeThrow {Get-ShadowKiloExtensionVersion -Output 'kilocode.kilo-code'} 'version number' 'An installed extension without a version is not treated as missing'
    [pscustomobject]@{suite='VS Code CLI resolution';passed=$true;checks=$count}|ConvertTo-Json
}finally{if(Test-Path -LiteralPath $root){Remove-Item -LiteralPath $root -Recurse -Force}}
