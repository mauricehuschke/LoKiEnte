#requires -Version 5.1
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'UpdatePolicy.ps1')
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'DependencyVersions.ps1')
$now=[datetimeoffset]'2027-01-04T12:00:00Z'
$cutoff=$now.AddHours(-48)
$items=@(
    @{Version='1.9.0'; Date='2027-01-02T13:00:00+01:00'},
    @{Version='1.10.0'; Date='2027-01-02T12:00:01Z'},
    @{Version='2.0.0'; Date='2026-01-02'},
    @{Version='3.0.0'; Date='broken'}
)
if ((Get-LoKiEnteEligibleVersion $items $cutoff test).Version -ne '1.9.0') { throw 'UTC age boundary failed.' }
$failed=$false
try { $null=Get-LoKiEnteEligibleVersion @($items[1]) $cutoff test } catch { $failed=$true }
if (!$failed) { throw 'Accepted an under-age release.' }
$folder=Join-Path ([IO.Path]::GetTempPath()) ('lokiente-policy-'+[guid]::NewGuid().ToString())
[void][IO.Directory]::CreateDirectory($folder)
function Assert-BootstrapNoReparsePoint {param($Path)}
$file=Join-Path $folder 'update-policy.json'
$legacy=Join-Path $folder 'dependency-versions.json'
try {
    [IO.File]::WriteAllText($legacy,'{"git":"2.1.0"}')
    $blocked=$false
    try { $null=Set-LoKiEnteUpdatePolicy $folder '' } catch { $blocked=$_.Exception.Message -match 'Custom dependency' }
    if (!$blocked -or [IO.File]::Exists($file)) {throw 'Existing custom pins were adopted silently.'}
    [IO.File]::Delete($legacy)
    foreach ($pair in @(@('','frozen'),@('LATEST','latest'),@('','latest'),@('lts','lts'),@('','lts'))) {
        if ((Set-LoKiEnteUpdatePolicy $folder $pair[0]) -cne $pair[1]) {throw 'Policy persistence failed.'}
    }
    [IO.File]::WriteAllText($file,'{"updatePolicy":"broken"}')
    $failed=$false
    try { $null=Set-LoKiEnteUpdatePolicy $folder '' } catch { $failed=$true }
    if (!$failed -or (Set-LoKiEnteUpdatePolicy $folder frozen) -ne 'frozen') {throw 'Invalid policy recovery failed.'}
} finally {
    if([IO.File]::Exists($file)){[IO.File]::Delete($file)}
    if([IO.File]::Exists($legacy)){[IO.File]::Delete($legacy)}
    [IO.Directory]::Delete($folder)
}
function Get-LoKiEnteJson {
    param($Uri,$Body)
    if ($Uri -match '/commits\?') {return @{sha=('a'*40);commit=@{committer=@{date='2027-01-01T12:00:00Z'}}}}
    if ($Uri -match '/contents/') {
        $versions=if ($Uri -match 'PowerShell') {@('7.7.0.0','7.6.3.0')} elseif ($Uri -match 'NodeJS/LTS') {'22.0.0'} elseif ($Uri -match 'NodeJS') {'23.0.0'} else {'2.0.0'}
        foreach($v in $versions){[pscustomobject]@{name=$v; type='dir'; sha=('b'*40)}}
        # Updated manifest tree is too new even though the directory already existed.
        $sha=if($Uri.EndsWith('master')){'e'*40}else{'f'*40}
        [pscustomobject]@{name='55.0.0';type='dir';sha=$sha}
        return
    }
    if ($Uri -match 'metadata.json'){return @{LTSReleaseTag=@('v7.6.3')}}
    if ($Uri -eq 'https://registry.npmjs.org/npm') {
        return ('{"dist-tags":{"latest":"12.2.4","latest-11":"11.20.0"},"versions":{"11.20.0":{"engines":{"node":">=20.0.0"}},"12.2.3":{"engines":{"node":"^22.22.2 || >=24.0.0"}},"12.2.4":{"engines":{"node":">=20.0.0"}}},"time":{"11.20.0":"2026-10-01T00:00:00Z","12.2.3":"2027-01-02T12:00:00Z","12.2.4":"2027-01-02T12:00:01Z"}}' | ConvertFrom-Json)
    }
    if ($Uri -match 'npmjs'){return ('{"dist-tags":{"latest":"2.0.0"},"versions":{"1.0.0":{},"2.0.0":{}},"time":{"1.0.0":"2027-01-01T12:00:00Z","2.0.0":"2027-01-04T11:00:00Z"}}'|ConvertFrom-Json)}
    if ($Uri -match 'marketplace'){return ('{"results":[{"extensions":[{"extensionName":"kilo-code","publisher":{"publisherName":"kilocode"},"versions":[{"version":"3.0.0","targetPlatform":"linux-x64","lastUpdated":"2026-12-01T12:00:00Z"},{"version":"2.0.0","targetPlatform":"win32-x64","lastUpdated":"2027-01-03T12:00:00Z"},{"version":"1.0.0","targetPlatform":"win32-x64","lastUpdated":"2027-01-01T12:00:00Z"}]}]}]}'|ConvertFrom-Json)}
    throw "Unexpected URL $Uri"
}
if ((Get-LoKiEnteRegistryTarget npm $cutoff ([version]'26.13.1')) -cne '12.2.3') {throw 'Eligible npm version was skipped'}
if ((Get-LoKiEnteRegistryTarget npm $cutoff ([version]'22.22.1')) -cne '11.20.0') {throw 'Incompatible npm was accepted'}
foreach($policy in @('latest','lts')){
    $plan=Resolve-LoKiEnteDependencyPlan $policy $now
    if($plan.git -ne '2.0.0' -or $plan.kiloCli -ne '1.0.0' -or $plan.kiloVsCode -ne '1.0.0'){throw 'Package eligibility selection failed.'}
    if($policy -eq 'lts' -and ($plan.node -ne '22.0.0' -or $plan.powerShell -ne '7.6.3.0')){throw 'LTS preference failed.'}
    if($policy -eq 'latest' -and ($plan.nodePackage -ne 'OpenJS.NodeJS' -or $plan.powerShell -ne '7.7.0.0')){throw 'Latest channels failed.'}
}
'PASS: 48-hour boundary, timestamp evidence, policy persistence, platform selection, catalog history and LTS routing.'
