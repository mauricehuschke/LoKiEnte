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
    if([string]::IsNullOrWhiteSpace($candidate)){throw 'Please specify an existing project directory.'}
    $resolved=Resolve-Path -LiteralPath $candidate -ErrorAction Stop
    if($resolved.Provider.Name -cne 'FileSystem' -or -not(Test-Path -LiteralPath $resolved.ProviderPath -PathType Container)){
        throw 'The project must be an existing filesystem directory.'
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
            if($entries -isnot [array]){throw 'Expected a list of projects.'}
            foreach($entry in $entries){
                if($entry -isnot [Collections.IDictionary] -or -not $entry.Contains('project') -or
                   $entry.project -isnot [string] -or [string]::IsNullOrWhiteSpace($entry.project)){
                    throw 'A project entry has no valid project path.'
                }
                if($seen.Add($entry.project)){$projects.Add($entry.project)}
            }
        } catch {
            throw "Project list unreadable: $index. File remains unchanged. $($_.Exception.Message)"
        }
    }
    while($true){
        Write-Host ''
        Write-Host 'LoKiEnte - select a project'
        for($i=0;$i -lt $projects.Count;$i++){
            $missing=if(Test-Path -LiteralPath $projects[$i] -PathType Container){''}else{' [unavailable]'}
            Write-Host "$($i+1): $($projects[$i])$missing"
        }
        if(-not $projects.Count){Write-Host 'No projects registered yet.'}
        Write-Host 'N: Open another project directory (enter path)'
        Write-Host '0: Cancel'
        $choice=(Read-Host 'Selection').Trim()
        if($choice -eq '0'){return $null}
        if($choice -ieq 'N'){
            $candidate=Read-Host 'Existing project directory (empty input to go back)'
            if([string]::IsNullOrWhiteSpace($candidate)){continue}
        }else{
            $number=0
            if(-not [int]::TryParse($choice,[ref]$number) -or $number -lt 1 -or $number -gt $projects.Count){
                Write-Host 'Enter a displayed number, N or 0.'
                continue
            }
            $candidate=$projects[$number-1]
        }
        try { return Resolve-ShadowProjectDirectory -Path $candidate }
        catch { Write-Host "Cannot open directory: $($_.Exception.Message)" }
    }
}
