#requires -Version 7.4
# Project selection only: no model actions and no changes inside project folders.
function Resolve-ShadowProjectDirectory {
    param([Parameter(Mandatory)][string]$Path)
    $candidate=$Path.Trim()
    if($candidate.Length -ge 2 -and
       (($candidate.StartsWith('"') -and $candidate.EndsWith('"')) -or
        ($candidate.StartsWith("'") -and $candidate.EndsWith("'")))){
        $candidate=$candidate.Substring(1,$candidate.Length-2)
    }
    if([string]::IsNullOrWhiteSpace($candidate)){throw 'Bitte einen vorhandenen Projektordner angeben.'}
    $resolved=Resolve-Path -LiteralPath $candidate -ErrorAction Stop
    if($resolved.Provider.Name -cne 'FileSystem' -or -not(Test-Path -LiteralPath $resolved.ProviderPath -PathType Container)){
        throw 'Das Projekt muss ein vorhandener Dateisystemordner sein.'
    }
    return $resolved.ProviderPath
}

function Select-ShadowProject {
    param([Parameter(Mandatory)][string]$InstallRoot,[string]$ProjectPath)
    if(-not [string]::IsNullOrWhiteSpace($ProjectPath)){
        return Resolve-ShadowProjectDirectory -Path $ProjectPath
    }
    $projects=[Collections.Generic.List[string]]::new()
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $index=Join-Path $InstallRoot 'workspaces.json'
    if(Test-Path -LiteralPath $index){
        try {
            $entries=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($index)) -AsHashtable -NoEnumerate -ErrorAction Stop
            if($entries -isnot [array]){throw 'Erwartet wird eine Liste von Projekten.'}
            foreach($entry in $entries){
                if($entry -isnot [Collections.IDictionary] -or -not $entry.Contains('project') -or
                   $entry.project -isnot [string] -or [string]::IsNullOrWhiteSpace($entry.project)){
                    throw 'Ein Projekteintrag hat keinen gueltigen Projektpfad.'
                }
                if($seen.Add($entry.project)){$projects.Add($entry.project)}
            }
        } catch {
            throw "Projektliste nicht lesbar: $index. Die Datei bleibt unveraendert. $($_.Exception.Message)"
        }
    }
    while($true){
        Write-Host ''
        Write-Host 'Shadow Local AI - Projekt auswaehlen'
        for($i=0;$i -lt $projects.Count;$i++){
            $missing=if(Test-Path -LiteralPath $projects[$i] -PathType Container){''}else{' [nicht erreichbar]'}
            Write-Host "$($i+1): $($projects[$i])$missing"
        }
        if(-not $projects.Count){Write-Host 'Noch keine Projekte registriert.'}
        Write-Host 'N: Weiteren Projektordner oeffnen (Pfad eingeben)'
        Write-Host '0: Abbrechen'
        $choice=(Read-Host 'Auswahl').Trim()
        if($choice -eq '0'){return $null}
        if($choice -ieq 'N'){
            $candidate=Read-Host 'Vorhandener Projektordner (leere Eingabe zurueck)'
            if([string]::IsNullOrWhiteSpace($candidate)){continue}
        }else{
            $number=0
            if(-not [int]::TryParse($choice,[ref]$number) -or $number -lt 1 -or $number -gt $projects.Count){
                Write-Host 'Bitte eine angezeigte Nummer, N oder 0 eingeben.'
                continue
            }
            $candidate=$projects[$number-1]
        }
        try { return Resolve-ShadowProjectDirectory -Path $candidate }
        catch { Write-Host "Ordner kann nicht geoeffnet werden: $($_.Exception.Message)" }
    }
}
