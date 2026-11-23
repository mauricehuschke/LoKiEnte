#requires -Version 7.4
param([string]$SourceRoot=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
. (Join-Path $SourceRoot 'Common.ps1')
. (Join-Path $SourceRoot 'DependencyVersions.ps1')

$fixture=[IO.Directory]::CreateTempSubdirectory('lokiente-curl-')
$savedLocal=$env:LOCALAPPDATA
$savedProgram=$env:ProgramFiles
try {
    $env:LOCALAPPDATA=$fixture.FullName
    $env:ProgramFiles=$fixture.FullName
    $inbox=Join-Path $fixture.FullName 'System32/curl.exe'
    $registered=Join-Path $fixture.FullName 'custom package root'
    $official=Join-Path $registered 'curl-8.23.0_9-win64-mingw/bin/curl.exe'
    $older=Join-Path $registered 'curl-8.23.0_8-win64-mingw/bin/curl.exe'
    foreach($path in $inbox,$official,$older){
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path))
        [IO.File]::WriteAllText($path,'mock executable')
    }
    $receipt=@{DisplayVersion='8.23.0.9';InstallLocation=$registered}
    $script:packages=@()
    $script:onPath=@($inbox)
    $script:banner='curl 8.23.0 (x86_64-w64-mingw32) libcurl/8.23.0'
    $script:calls=0
    $script:activate=$true
    function Get-ShadowCurlPackageRegistration { $script:packages }
    function Get-Command {
        param($Name,$CommandType,[switch]$All,$ErrorAction)
        foreach($path in $script:onPath){[pscustomobject]@{Source=$path};if(!$All){break}}
    }
    function Update-ShadowProcessPath {}
    function Invoke-ShadowNative {
        param($FilePath,$ArgumentList,[switch]$AllowFailure,[switch]$Quiet,$TimeoutSeconds)
        if($FilePath -eq 'fixture-winget'){
            if(($ArgumentList -join ' ') -notmatch '^install --id cURL\.cURL --exact .*--version 8\.23\.0\.9$'){throw 'Unexpected installation command'}
            $script:calls++
            if($script:activate){$script:packages=@($receipt)}
            return @{ExitCode=0}
        }
        if($ArgumentList -ne '--version'){throw 'Unexpected curl command'}
        return @{StdOut=$script:banner;ExitCode=0}
    }

    $argsForInstall=@{Tool='curl';PackageId='cURL.cURL';WingetPath='fixture-winget';AcceptedVersion='8.23.0.9'}
    if ((Install-ShadowPackage @argsForInstall) -ne $official) {throw 'Successful update selected system curl instead of the registered executable'}
    if ((Install-ShadowPackage @argsForInstall) -ne $official -or $script:calls -ne 1) {throw 'A retry should reuse the verified installation'}
    $script:packages=@(@{DisplayVersion='8.23.0.8';InstallLocation=$registered},$receipt)
    if ((Resolve-ShadowTool curl) -ne $official) {throw 'Did not select the newer installed scope'}
    $script:packages=@()
    $script:onPath=@($inbox,$official)
    if ((Resolve-ShadowTool curl) -ne $official) {throw 'Lost portable bin behind system curl on PATH'}
    $script:onPath=@($inbox)
    $script:packages=@(@{DisplayVersion='8.23.0.9';InstallLocation=(Join-Path $registered 'missing')})
    $script:activate=$false
    $errorText=''
    try { $null=Install-ShadowPackage @argsForInstall } catch { $errorText=$_.Exception.Message }
    if (!$errorText.Contains('Detected 8.23.0.0') -or !$errorText.Contains($inbox)) {throw "Missing or misleading fallback diagnostic: $errorText"}
    if ((Get-ShadowInstalledVersion curl $older) -ne [version]'8.23.0.8'){throw 'Older packaging revision accepted'}
    $script:banner='curl 8.22.0 (Windows) libcurl/8.22.0'
    if ((Get-ShadowInstalledVersion curl $official) -ne [version]'8.22.0.0'){throw 'Package location masked a runtime version mismatch'}
    $script:banner='invalid output libcurl/8.23.0'
    if ($null -ne (Get-ShadowInstalledVersion curl $official)){throw 'Invalid runtime output accepted'}
    'PASS: curl installation, retry, scopes, PATH, stale receipt, old revision, mismatched and invalid runtime.'
} finally {
    $env:LOCALAPPDATA=$savedLocal
    $env:ProgramFiles=$savedProgram
    $fixture.Delete($true)
}
