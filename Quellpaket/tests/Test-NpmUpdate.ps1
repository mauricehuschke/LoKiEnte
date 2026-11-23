#requires -Version 7.4
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'Common.ps1')
$fixtureRoot=[IO.Directory]::CreateTempSubdirectory('lokiente-npm-')
try {
    $script:installs=0
    $script:bundled='11.20.0'
    function Resolve-ShadowNpm {param($NodePath) 'bundled-npm'}
    function Invoke-ShadowNative {
        param($FilePath,$ArgumentList,[switch]$AllowFailure,[switch]$Quiet)
        if ($ArgumentList -contains 'install') {
            $prefix=$ArgumentList[[array]::IndexOf($ArgumentList,'--prefix')+1]
            if ($ArgumentList -notcontains 'npm@12.2.3' -or $ArgumentList -notcontains '--ignore-scripts' -or
                $ArgumentList -notcontains '--engine-strict' -or !$prefix.StartsWith($fixtureRoot.FullName)) {throw 'Unexpected npm installation'}
            $cutoff=[datetimeoffset]$ArgumentList[[array]::IndexOf($ArgumentList,'--before')+1]
            if($cutoff -gt [datetimeoffset]::UtcNow.AddHours(-48)){throw 'Missing release-age guard'}
            $entry=Join-Path $prefix 'node_modules/npm/bin/npm-cli.js'
            [void][IO.Directory]::CreateDirectory((Split-Path $entry))
            [IO.File]::WriteAllText($entry,'12.2.3')
            [IO.File]::WriteAllText((Join-Path $prefix 'npm.cmd'),'fixture')
            $script:installs++
            return
        }
        $v=if($ArgumentList[0] -eq 'bundled-npm'){$script:bundled}else{[IO.File]::ReadAllText($ArgumentList[0])}
        @{StdOut=$v;ExitCode=0}
    }
    foreach($i in 1,2){
        $active=Install-ShadowNpm node $fixtureRoot.FullName '12.2.3'
        if($active.Version -ne '12.2.3' -or $script:installs -ne 1){throw 'npm upgrade or retry failed'}
    }
    [IO.File]::WriteAllText((Join-Path $fixtureRoot.FullName 'toolchain.json'),'{"npmVersion":"12.2.3"}')
    $frozen=Install-ShadowNpm node $fixtureRoot.FullName '11.20.0'
    if($frozen.Entry -ne $active.Entry){throw 'Policy change downgraded active npm'}
    $script:bundled='13.0.0'
    if((Install-ShadowNpm node $fixtureRoot.FullName '12.2.3').Entry -ne 'bundled-npm'){throw 'Newer bundled npm was replaced'}
    'PASS: npm upgrade, scoped install, 48-hour limit, reuse and no downgrade.'
} finally { $fixtureRoot.Delete($true) }
