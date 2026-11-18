# Shared by Windows PowerShell 5.1 bootstrap and PowerShell 7 setup.
function Read-ShadowDependencyVersions {
    param([string]$InstallRoot)
    $versions=[ordered]@{
        powerShell=$null;git=$null;node=$null;curl=$null;vsCode=$null;lmStudio=$null
        kiloCli=$null;kiloVsCode='7.8.30'
    }
    $path=Join-Path $InstallRoot 'dependency-versions.json'
    if(Test-Path -LiteralPath $path){
        $document=(ConvertFrom-Json -InputObject ('{"value":'+[IO.File]::ReadAllText($path)+'}') -ErrorAction Stop).value
        if($document -isnot [pscustomobject]){throw "Versionsfreigaben sind kein JSON-Objekt: $path"}
        foreach($entry in $document.PSObject.Properties){
            if(-not $versions.Contains($entry.Name)){throw "Unbekannte Abhaengigkeit in $($path): $($entry.Name)"}
            if($null -ne $entry.Value -and ($entry.Value -isnot [string] -or
               $entry.Value -notmatch '^\d{1,8}\.\d{1,8}\.\d{1,8}(?:\.\d{1,8})?$')){
                throw "Freigabe fuer $($entry.Name) muss eine stabile Versionsnummer oder null sein."
            }
            if($entry.Name -in @('kiloCli','kiloVsCode') -and $entry.Value -and $entry.Value.Split('.').Count -ne 3){
                throw "Freigabe fuer $($entry.Name) muss dreiteilig sein."
            }
            if($entry.Name -eq 'kiloVsCode' -and -not $entry.Value){throw 'Kilo VS Code benoetigt eine freigegebene Version.'}
            if($entry.Name -eq 'powerShell' -and $entry.Value -and [version]$entry.Value -lt [version]'7.4.0'){
                throw 'Freigegebene PowerShell-Version muss mindestens 7.4.0 sein.'
            }
            $versions[$entry.Name]=$entry.Value
        }
    }
    return $versions
}

function Get-ShadowComparableVersion {
    param([string]$Text)
    # Ignore vendor decorations such as the Git for Windows suffix.
    if($Text -notmatch '(?<![\d.])(?<version>\d{1,8}\.\d{1,8}\.\d{1,8}(?:\.\d{1,8})?)(?![\d.])'){
        # Git for Windows appends .windows.N to the three numeric components.
        if($Text -notmatch '(?<version>\d{1,8}\.\d{1,8}\.\d{1,8})\.windows\.\d+'){return $null}
    }
    $value=$Matches['version']
    if($value.Split('.').Count -eq 3){$value+='.0'}
    return [version]$value
}
