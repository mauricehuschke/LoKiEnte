#requires -Version 7.4
param([string]$SourceRoot=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path $SourceRoot 'Common.ps1')
. (Join-Path $SourceRoot 'DependencyVersions.ps1')
$root=Join-Path ([IO.Path]::GetTempPath()) ('shadow-dependencies-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
try{
    $versions=Read-ShadowDependencyVersions $root
    if($versions.kiloVsCode -cne '7.8.30' -or $versions.git){throw 'Unexpected bundled dependency targets'}
    $policy=Join-Path $root 'dependency-versions.json'
    [IO.File]::WriteAllText($policy,'{"git":"2.51.0","kiloCli":"7.8.30"}')
    $versions=Read-ShadowDependencyVersions $root
    if($versions.git -cne '2.51.0' -or $versions.kiloCli -cne '7.8.30'){throw 'Approved versions were not loaded'}
    [IO.File]::WriteAllText($policy,'{"git":"latest"}')
    $rejected=$false
    try{$null=Read-ShadowDependencyVersions $root}catch{$rejected=$true}
    if(-not $rejected){throw 'Floating version was accepted as an upgrade target'}
    if((Get-ShadowComparableVersion 'git version 2.51.0.windows.1') -ne [version]'2.51.0.0'){throw 'Git for Windows version parsed incorrectly'}

    $script:present=$true
    $script:installed=[version]'2.50.0.0'
    $script:invocation=@()
    $script:applyChange=$true
    function Resolve-ShadowTool {param($Name) if($script:present){return 'git-fixture.exe'}}
    function Get-ShadowInstalledVersion {param($Tool,$Path) return $script:installed}
    function Update-ShadowProcessPath {}
    function Invoke-ShadowNative {
        param($FilePath,$ArgumentList,[switch]$AllowFailure)
        $script:invocation=@($ArgumentList)
        if($script:applyChange){$script:present=$true;$script:installed=[version]'2.51.0.0'}
        return [pscustomobject]@{ExitCode=0}
    }
    $arguments=@{Tool='git';PackageId='Git.Git';WingetPath='winget-fixture.exe'}
    $null=Install-ShadowPackage @arguments
    if($script:invocation.Count){throw 'Existing unpinned dependency was updated'}
    $null=Install-ShadowPackage @arguments -AcceptedVersion $versions.git
    if($script:invocation[0] -cne 'upgrade' -or
       ($script:invocation -join ' ') -notmatch '--id Git.Git --exact.*--version 2.51.0$'){
        throw 'Upgrade did not target the exact approved WinGet package version'
    }
    $script:invocation=@()
    $script:installed=[version]'2.52.0.0'
    $null=Install-ShadowPackage @arguments -AcceptedVersion $versions.git
    if($script:invocation.Count){throw 'Newer version was downgraded'}
    $script:present=$false
    $null=Install-ShadowPackage @arguments -AcceptedVersion $versions.git
    if($script:invocation[0] -cne 'install' -or $script:invocation -notcontains '2.51.0'){throw 'Fresh setup ignored the approved version'}
    $script:installed=[version]'2.50.0.0'
    $script:applyChange=$false
    $rejected=$false
    try{$null=Install-ShadowPackage @arguments -AcceptedVersion $versions.git}catch{$rejected=$_.Exception.Message -match 'does not meet approved version'}
    if(-not $rejected){throw 'Upgrade was accepted despite the executable still being old'}

    $tokens=$null;$parse=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $SourceRoot 'Setup.ps1'),[ref]$tokens,[ref]$parse)
    $definition=$ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Install-ShadowKilo'},$false)
    . ([scriptblock]::Create($definition.Extent.Text))
    $script:npmInstalled=$false
    function Get-ShadowKiloEntry {
        param($PackageRoot,$NodePath)
        if($PackageRoot -like '*kilo-versions*' -and -not $script:npmInstalled){return $null}
        $version=if($PackageRoot -like '*kilo-versions*'){'7.8.30'}else{'7.8.27'}
        return [ordered]@{kiloExecutable=$NodePath;kiloArgumentPrefix=@((Join-Path $PackageRoot 'bin/kilo.js'));kiloVersion=$version}
    }
    function Test-ShadowKiloEntry {param($Entry) return $true}
    function Invoke-ShadowNative {
        param($FilePath,$ArgumentList,$TimeoutSeconds)
        if($ArgumentList -notcontains '@kilocode/cli@7.8.30' -or $ArgumentList -notcontains 'install'){throw 'npm must use the approved version directly'}
        if ($ArgumentList -notcontains '--ignore-scripts' -or $ArgumentList -notcontains '--include=optional') {throw 'Unsafe Kilo install flags'}
        $beforeIndex=[array]::IndexOf($ArgumentList,'--before')
        if ($beforeIndex -lt 0 -or [datetimeoffset]$ArgumentList[$beforeIndex+1] -gt [datetimeoffset]::UtcNow.AddHours(-48)) {throw 'npm must apply the release age to its dependency tree'}
        $script:npmInstalled=$true
    }
    $result=Install-ShadowKilo -Root $root -NodePath 'fixture-node.exe' -NpmEntry 'npm-cli.js' -AcceptedVersion $versions.kiloCli
    if($result.kiloVersion -cne '7.8.30' -or $result.kiloArgumentPrefix[0] -notmatch 'kilo-versions[\\/]7.8.30'){
        throw 'New Kilo was not prepared in a version-specific directory'
    }
    if(Test-Path -LiteralPath (Join-Path $root 'toolchain.json')){throw 'Dependency staging unexpectedly published the toolchain'}
    [pscustomobject]@{suite='Approved dependency updates';passed=$true;checks=11}|ConvertTo-Json
}finally{
    $root=[IO.Path]::GetFullPath($root)
    if(-not $root.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase) -or
       [IO.Path]::GetFileName($root) -notlike 'shadow-dependencies-*'){throw 'Unexpected cleanup directory'}
    Remove-Item -LiteralPath $root -Recurse -Force
}
