#requires -Version 7.4
# Policy shared by the reviewed runner and its offline tests.
function Enter-ShadowProjectRun {
    param([string]$ProjectPath)
    $gitDir=(Get-ShadowGitOutput $ProjectPath @('rev-parse','--absolute-git-dir')).Trim()
    try { return [IO.File]::Open((Join-Path $gitDir 'shadow-local-ai-run.lock'),'OpenOrCreate','ReadWrite','None') }
    catch [IO.IOException] { throw 'Projekt ist durch einen anderen Local-AI-Lauf gesperrt oder die Git-Sperrdatei ist nicht zugaenglich.' }
}

function Get-ShadowWritePaths {
    param([System.Collections.IDictionary]$Policy,[string]$ProjectPath)
    if(-not $Policy.Contains('writePaths') -or $Policy.writePaths -isnot [array] -or -not $Policy.writePaths.Count){
        throw 'Schreibende Auftraege benoetigen writePaths in checks.json (exakte projektbezogene Dateipfade).'
    }
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($path in $Policy.writePaths){
        if($path -isnot [string] -or $path -notmatch '^[^/\\:*?"<>|\[\]\x00-\x1f]+(?:/[^/\\:*?"<>|\[\]\x00-\x1f]+)*$'){
            throw "Ungueltiger Schreibpfad: $path. Exakten projektbezogenen Dateipfad mit / ohne Glob angeben."
        }
        $cursor=$ProjectPath
        foreach($part in $path.Split('/')){
            if($part -match '^\s|[ .]$|^(?:\.git|\.kilo|\.kilocode|\.vscode|\.github|node_modules)(?:$)|^\.env|^credentials|^(?:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)'){
                throw "Geschuetzter oder ungueltiger Schreibpfad: $path"
            }
            $cursor=Join-Path $cursor $part
            $item=Get-Item -LiteralPath $cursor -Force -ErrorAction SilentlyContinue
            if($item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){
                throw "Schreibpfad enthaelt eine Verknuepfung: $path"
            }
        }
        if(Test-Path -LiteralPath $cursor -PathType Container){throw "Schreibpfad muss eine Datei angeben: $path"}
        if([IO.Path]::GetFileName($path) -match '^(?:auth\.json|\.gitignore|\.kilocodeignore|\.gitattributes|\.npmrc|package(?:-lock)?\.json|pnpm-lock\.yaml|yarn\.lock|pyproject\.toml|pytest\.ini|tox\.ini|Makefile|Justfile|.*\.config\.[^/]+)$'){
            throw "Projekt- oder Pruefkonfiguration manuell aendern: $path"
        }
        if(Get-ShadowGitOutput $ProjectPath @('check-ignore','--',$path) -AllowedExitCodes @(0,1)){
            throw "Ignorierter Schreibpfad liegt ausserhalb des Pruefnachweises: $path"
        }
        if(-not $seen.Add($path)){throw "Doppelter Schreibpfad: $path"}
        $path
    }
}

function Get-ShadowDirtyFiles {
    param([string]$ProjectPath)
    $files=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::OrdinalIgnoreCase)
    $status=Get-ShadowGitOutput $ProjectPath @('status','--porcelain=v1','-z','--untracked-files=all','--no-renames')
    foreach($record in $status.Split([char]0,[StringSplitOptions]::RemoveEmptyEntries)){
        $path=$record.Substring(3)
        $absolute=Join-Path $ProjectPath $path
        $item=Get-Item -LiteralPath $absolute -Force -ErrorAction SilentlyContinue
        if($item -and ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint))){
            throw "Dateityp fuer Umfangspruefung nicht unterstuetzt: $path"
        }
        $files[$path]=if($item){(Get-FileHash -LiteralPath $absolute -Algorithm SHA256).Hash}else{'(deleted)'}
    }
    return ,$files
}

function Assert-ShadowWriteScope {
    param($Before,$After,[string[]]$WritePaths)
    $paths=@($Before.Keys)+@($After.Keys) | Sort-Object -Unique
    foreach($path in $paths){
        if($path -notin $WritePaths -and ($Before.ContainsKey($path) -ne $After.ContainsKey($path) -or $Before[$path] -cne $After[$path])){
            throw "Datei ausserhalb des erlaubten Schreibumfangs geaendert: $path. Diff manuell pruefen."
        }
    }
}

function Get-ShadowCheckEnvironment {
    param([string]$RunPath)
    $profile=Join-Path $RunPath 'check-profile'
    $temp=Join-Path $profile 'temp'
    $appData=Join-Path $profile 'appdata'
    $localAppData=Join-Path $profile 'localappdata'
    foreach($directory in @($temp,$appData,$localAppData)){[void][IO.Directory]::CreateDirectory($directory)}
    $values=@{}
    foreach($name in @('SystemRoot','SystemDrive','WINDIR','ComSpec','PATH','PATHEXT','ProgramFiles','ProgramFiles(x86)','ProgramW6432','ProgramData','NUMBER_OF_PROCESSORS','PROCESSOR_ARCHITECTURE')){
        $value=[Environment]::GetEnvironmentVariable($name,'Process')
        if($value){$values[$name]=$value}
    }
    $values.TEMP=$temp
    $values.TMP=$temp
    $values.USERPROFILE=$profile
    $values['HOME']=$profile
    $values.APPDATA=$appData
    $values.LOCALAPPDATA=$localAppData
    $values.CI='true'
    $values.GIT_TERMINAL_PROMPT='0'
    return $values
}

