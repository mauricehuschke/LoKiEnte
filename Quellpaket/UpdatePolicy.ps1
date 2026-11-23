# Shared by the Windows PowerShell bootstrap and PowerShell 7 setup.
function Get-LoKiEnteJson {
    param([string]$Uri, [string]$Body)
    $ProgressPreference='SilentlyContinue'
    $request = @{Uri=$Uri; TimeoutSec=45; UseBasicParsing=$true; ErrorAction='Stop'
        Headers=@{'User-Agent'='LoKiEnte-Provision'; Accept='application/json'}}
    if ($Body) { $request.Method='Post'; $request.Body=$Body; $request.ContentType='application/json' }
    try {
        $response = Invoke-WebRequest @request
        return (ConvertFrom-Json -InputObject $response.Content -ErrorAction Stop)
    } catch { throw "Cannot read release metadata from $Uri. Retry provisioning. $($_.Exception.Message)" }
}

function Get-LoKiEnteEligibleVersion {
    param([object[]]$Candidates, [datetimeoffset]$Cutoff, [string]$Tool)
    $best = $null
    foreach ($item in $Candidates) {
        if ($item.Version -notmatch '^\d+\.\d+\.\d+(?:\.\d+)?$' -or -not $item.Date) { continue }
        $stamp = [datetimeoffset]::MinValue
        if ($item.Date -is [datetime]) {
            if ($item.Date.Kind -eq [DateTimeKind]::Unspecified) { continue }
            $stamp = [datetimeoffset]$item.Date
        }
        elseif ($item.Date -is [datetimeoffset]) { $stamp = $item.Date }
        elseif ([string]$item.Date -notmatch '(?:Z|[+-]\d\d:\d\d)$' -or
            -not [datetimeoffset]::TryParse([string]$item.Date, [cultureinfo]::InvariantCulture,
                [Globalization.DateTimeStyles]::None, [ref]$stamp)) { continue }
        if ($stamp -le $Cutoff -and (!$best -or [version]$item.Version -gt [version]$best.Version)) { $best=$item }
    }
    if (!$best) { throw "No eligible $Tool release with evidence of at least 48 hours of age." }
    return $best
}

function Get-LoKiEnteWingetCandidates {
    param([string]$PackageId, [string]$Snapshot, [datetimeoffset]$SnapshotDate)
    $folder = $PackageId.Substring(0,1).ToLowerInvariant() + '/' + $PackageId.Replace('.','/')
    $uri = "https://api.github.com/repos/microsoft/winget-pkgs/contents/manifests/$folder"
    $old = @{}
    foreach ($entry in (Get-LoKiEnteJson "$($uri)?ref=$Snapshot")) {
        if ($entry.type -eq 'dir') { $old[$entry.name]=$entry.sha }
    }
    foreach ($entry in (Get-LoKiEnteJson "$($uri)?ref=master")) {
        if ($entry.type -eq 'dir' -and $entry.name -match '^\d+\.\d+\.\d+(?:\.\d+)?$' -and
            $entry.sha -cmatch '^[0-9a-f]{40}$' -and $old[$entry.name] -ceq $entry.sha) {
            [pscustomobject]@{Version=$entry.name; Date=$SnapshotDate; PackageId=$PackageId}
        }
    }
}

# npm publishes its supported Node lines as caret ranges and open-ended minima.
# Only accept alternatives whose meaning we can establish. npm checks engines again at install.
function Test-LoKiEnteNpmNodeRange {
    param([version]$NodeVersion,[string]$Range)
    $actual=[version]$NodeVersion.ToString(3)
    foreach ($alternative in $Range -split '\s*\|\|\s*') {
        if ($alternative.Trim() -notmatch '^(\^|>=)(\d+\.\d+\.\d+)$') {continue}
        $operator=$Matches[1]; $minimum=[version]$Matches[2]
        if ($actual -ge $minimum -and ($operator -eq '>=' -or ($minimum.Major -gt 0 -and $actual.Major -eq $minimum.Major))) { return $true }
    }
    return $false
}

function Get-LoKiEnteRegistryTarget {
    param([string]$Package,[datetimeoffset]$Cutoff,[version]$NodeVersion)
    $npm = Get-LoKiEnteJson "https://registry.npmjs.org/$Package"
    $stableTag = [string]$npm.'dist-tags'.latest
    if ($stableTag -notmatch '^\d+\.\d+\.\d+$') { throw "Invalid latest tag for $Package." }
    $otherTags = @($npm.'dist-tags'.PSObject.Properties | Where-Object { $_.Value -ne $stableTag -and ($Package -ne 'npm' -or $_.Name -notmatch '^latest-\d+$') } | ForEach-Object { $_.Value })
    $cli = foreach ($entry in $npm.time.PSObject.Properties) {
        if ($entry.Name -match '^\d+\.\d+\.\d+$' -and [version]$entry.Name -le [version]$stableTag -and
            $entry.Name -notin $otherTags -and $npm.versions.PSObject.Properties[$entry.Name]) {
            $release=$npm.versions.PSObject.Properties[$entry.Name].Value
            if ($release.PSObject.Properties['deprecated'] -and $release.deprecated) { continue }
            if ($NodeVersion) {
                if (!$release.PSObject.Properties['engines'] -or !$release.engines.PSObject.Properties['node']) { continue }
                if (!(Test-LoKiEnteNpmNodeRange $NodeVersion $release.engines.node)) { continue }
            }
            [pscustomobject]@{Version=$entry.Name; Date=$entry.Value}
        }
    }
    return (Get-LoKiEnteEligibleVersion $cli $Cutoff $Package).Version
}

function Resolve-LoKiEnteDependencyPlan {
    param([ValidateSet('frozen','latest','lts')][string]$Policy='frozen', [datetimeoffset]$Now=[datetimeoffset]::UtcNow)
    $cutoff = $Now.ToUniversalTime().AddHours(-48)
    # All six WinGet trees existed at b604f9a14219e28ed4f1ef7de96fb29771637210.
    # npm and the Windows x64 Marketplace build of Kilo 7.8.30 were published November 16.
    if ($Policy -eq 'frozen') {
        if ($cutoff -lt [datetimeoffset]'2026-11-20T00:00:00Z') { throw 'Frozen targets have not cleared the 48-hour cutoff. Check the system clock.' }
        return [ordered]@{powerShell='7.6.10.0'; git='2.56.0.4'; node='26.13.1'; npm='11.20.0'; curl='8.23.0.8'; vsCode='1.146.0'
            lmStudio='0.4.0'; kiloCli='7.8.30'; kiloVsCode='7.8.30'; nodePackage='OpenJS.NodeJS.LTS'}
    }

    $refTime = $cutoff.UtcDateTime.ToString("yyyy-MM-ddTHH:mm:ssZ")
    $history = @(Get-LoKiEnteJson "https://api.github.com/repos/microsoft/winget-pkgs/commits?sha=master&per_page=1&until=$refTime")
    if ($history.Count -ne 1 -or $history[0].sha -cnotmatch '^[a-f0-9]{40}$') { throw 'Missing dated WinGet catalog revision.' }
    $snapshot = $history[0].sha
    $snapshotDate = [datetimeoffset]$history[0].commit.committer.date
    if ($snapshotDate -gt $cutoff) { throw 'WinGet catalog revision is too recent.' }
    $packages = [ordered]@{powerShell='Microsoft.PowerShell'; git='Git.Git'; curl='cURL.cURL'
        vsCode='Microsoft.VisualStudioCode'; lmStudio='ElementLabs.LMStudio'; node='OpenJS.NodeJS.LTS'}
    $plan = [ordered]@{}
    foreach ($tool in $packages.Keys) {
        $items = @(Get-LoKiEnteWingetCandidates $packages[$tool] $snapshot $snapshotDate)
        if ($tool -eq 'node' -and $Policy -eq 'latest') {
            $items += @(Get-LoKiEnteWingetCandidates 'OpenJS.NodeJS' $snapshot $snapshotDate)
        }
        if ($tool -eq 'powerShell' -and $Policy -eq 'lts') {
            $metadata = Get-LoKiEnteJson 'https://raw.githubusercontent.com/PowerShell/PowerShell/master/tools/metadata.json'
            $lines = @($metadata.LTSReleaseTag | ForEach-Object { if ($_ -match '^v(\d+\.\d+)\.\d+$') { $Matches[1] } })
            $items = @($items | Where-Object { ([version]$_.Version).ToString(2) -in $lines })
        }
        $selected = Get-LoKiEnteEligibleVersion $items $cutoff $tool
        $plan[$tool] = $selected.Version
        if ($tool -eq 'node') { $plan.nodePackage = $selected.PackageId }
    }

    $plan.npm = Get-LoKiEnteRegistryTarget 'npm' $cutoff ([version]$plan.node)
    $plan.kiloCli = Get-LoKiEnteRegistryTarget '@kilocode%2fcli' $cutoff

    $body = @{filters=@(@{criteria=@(@{filterType=7; value='kilocode.kilo-code'})}); flags=17} | ConvertTo-Json -Depth 6
    $gallery = Get-LoKiEnteJson 'https://marketplace.visualstudio.com/_apis/public/gallery/extensionquery?api-version=7.2-preview.1' $body
    $extensions = @($gallery.results[0].extensions | Where-Object { $_.extensionName -eq 'kilo-code' -and $_.publisher.publisherName -eq 'kilocode' })
    if ($extensions.Count -ne 1) { throw 'Missing or ambiguous Kilo extension in the Marketplace.' }
    $vsix = foreach ($entry in $extensions[0].versions) {
        if ($entry.PSObject.Properties['targetPlatform'] -and $entry.targetPlatform -eq 'win32-x64') {
            [pscustomobject]@{Version=$entry.version; Date=$entry.lastUpdated}
        }
    }
    $plan.kiloVsCode = (Get-LoKiEnteEligibleVersion $vsix $cutoff 'Kilo VS Code for Windows x64').Version
    return $plan
}


function Set-LoKiEnteUpdatePolicy {
    param([string]$Root, [string]$Requested)
    $path = Join-Path $Root 'update-policy.json'
    Assert-BootstrapNoReparsePoint -Path $path
    $exists = Test-Path -LiteralPath $path -PathType Leaf
    if (!$Requested -and $exists) {
        $saved = (Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -ErrorAction Stop).updatePolicy
        if ($saved -notin @('frozen','latest','lts')) { throw 'Invalid saved UpdatePolicy. Specify -UpdatePolicy to replace it.' }
        return $saved.ToLowerInvariant()
    }
    if (!$Requested) {
        $legacy = Read-ShadowDependencyVersions $Root
        $baseline = Resolve-LoKiEnteDependencyPlan frozen
        foreach ($key in $legacy.Keys) {
            if ($legacy[$key] -and (Get-ShadowComparableVersion $legacy[$key]) -ne (Get-ShadowComparableVersion $baseline[$key])) {
                throw 'Custom dependency-versions.json pins were found. Select -UpdatePolicy frozen, latest or lts once to adopt the new policy.'
            }
        }
        $Requested = 'frozen'
    }
    if ($Requested -notin @('frozen','latest','lts')) { throw 'Invalid UpdatePolicy.' }
    $policy = $Requested.ToLowerInvariant()
    $temporary = Join-Path $Root ([guid]::NewGuid().ToString() + '.tmp')
    try {
        [IO.File]::WriteAllText($temporary, (@{updatePolicy=$policy} | ConvertTo-Json))
        if ($exists) { [IO.File]::Replace($temporary,$path,[NullString]::Value) }
        else { [IO.File]::Move($temporary,$path) }
    } finally { if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) } }
    return $policy
}
