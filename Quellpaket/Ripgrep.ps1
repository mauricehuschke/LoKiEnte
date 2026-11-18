#requires -Version 7.4
Set-StrictMode -Version Latest

function Get-ShadowRipgrepInfo {
    param([Parameter(Mandatory)][string]$InstallRoot)
    return [pscustomobject]@{
        Path=(Join-Path $InstallRoot 'runtime-profile/cache/kilo/bin/rg.exe')
        Version='15.1.0'
        Url='https://github.com/BurntSushi/ripgrep/releases/download/15.1.0/ripgrep-15.1.0-x86_64-pc-windows-msvc.zip'
        ArchiveSha256='124510b94b6baa3380d051fdf4650eaa80a302c876d611e9dba0b2e18d87493a'
        ExecutableSha256='decdd4992f3f1b9a5ef9898f1b40ab16886d579d6516b4efd3d5eaa19364e408'
        Entry='ripgrep-15.1.0-x86_64-pc-windows-msvc/rg.exe'
        ExecutableBytes=4266496
    }
}

function Get-ShadowRipgrepArchive {
    param([Parameter(Mandatory)][string]$Url)
    $handler=[Net.Http.HttpClientHandler]::new()
    $handler.AllowAutoRedirect=$true
    $client=[Net.Http.HttpClient]::new($handler)
    $client.DefaultRequestHeaders.UserAgent.ParseAdd('ShadowLocalAI/1.0')
    $cancel=[Threading.CancellationTokenSource]::new([TimeSpan]::FromSeconds(120))
    $response=$null;$stream=$null;$memory=[IO.MemoryStream]::new()
    try{
        $response=$client.GetAsync($Url,[Net.Http.HttpCompletionOption]::ResponseHeadersRead,$cancel.Token).GetAwaiter().GetResult()
        if(-not $response.IsSuccessStatusCode){throw "Ripgrep-Download fehlgeschlagen (HTTP $([int]$response.StatusCode))."}
        if($response.RequestMessage.RequestUri.Scheme -cne 'https'){throw 'Ripgrep-Download wurde auf eine unsichere Adresse umgeleitet.'}
        if($response.Content.Headers.ContentLength -gt 8MB){throw 'Ripgrep-Archiv ist unerwartet gross.'}
        $stream=$response.Content.ReadAsStreamAsync($cancel.Token).GetAwaiter().GetResult()
        $buffer=New-Object byte[] 65536
        while(($read=$stream.ReadAsync($buffer,0,$buffer.Length,$cancel.Token).GetAwaiter().GetResult()) -gt 0){
            if($memory.Length+$read -gt 8MB){throw 'Ripgrep-Archiv ist unerwartet gross.'}
            $memory.Write($buffer,0,$read)
        }
        return ,$memory.ToArray()
    }finally{
        if($stream){$stream.Dispose()}
        if($response){$response.Dispose()}
        $memory.Dispose();$cancel.Dispose();$client.Dispose();$handler.Dispose()
    }
}

function Assert-ShadowRipgrepReady {
    param([Parameter(Mandatory)][string]$InstallRoot)
    $info=Get-ShadowRipgrepInfo -InstallRoot $InstallRoot
    Assert-ShadowDirectPath -Path $info.Path
    if(-not(Test-Path -LiteralPath $info.Path -PathType Leaf)){throw "Ripgrep fehlt im verwalteten Kilo-Cache: $($info.Path). Provisionierung erneut ausfuehren."}
    $hash=(Get-FileHash -LiteralPath $info.Path -Algorithm SHA256 -ErrorAction Stop).Hash
    if($hash -ine $info.ExecutableSha256){
        throw "Vorhandene rg.exe im verwalteten Kilo-Cache hat eine unbekannte Pruefsumme und bleibt unveraendert: $($info.Path). Bitte pruefen."
    }
    $result=Invoke-ShadowNative -FilePath $info.Path -ArgumentList @('--version') -Quiet -TimeoutSeconds 30
    if($result.StdOut -notmatch '(?m)^ripgrep 15\.1\.0(?:\s|$)'){throw 'Die gepruefte ripgrep-Datei meldet eine unerwartete Version.'}
    return $info.Path
}

function Install-ShadowRipgrep {
    param([Parameter(Mandatory)][string]$InstallRoot)
    $info=Get-ShadowRipgrepInfo -InstallRoot $InstallRoot
    Assert-ShadowDirectPath -Path $info.Path
    if(Test-Path -LiteralPath $info.Path){return Assert-ShadowRipgrepReady -InstallRoot $InstallRoot}
    Write-ShadowMessage 'Installiere geprueftes ripgrep fuer die isolierte Kilo-Dateisuche ...'
    try{$bytes=Get-ShadowRipgrepArchive -Url $info.Url}
    catch{throw "Ripgrep-Download fehlgeschlagen oder Zeitlimit erreicht. GitHub-Verbindung pruefen und Provisionierung erneut starten. Keine bestehende rg.exe wurde ersetzt."}
    $digest=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
    if($digest -cne $info.ArchiveSha256){throw 'Ripgrep-Archiv hat eine ungueltige SHA256-Pruefsumme. Es wurde nichts installiert.'}
    $memory=[IO.MemoryStream]::new($bytes)
    $archive=[IO.Compression.ZipArchive]::new($memory,[IO.Compression.ZipArchiveMode]::Read)
    try{
        $entries=@($archive.Entries|Where-Object {$_.FullName -ceq $info.Entry})
        if($entries.Count -ne 1 -or $entries[0].Length -ne $info.ExecutableBytes){throw 'Ripgrep-Archiv enthaelt keinen eindeutigen gueltigen Windows-Programmeinstieg.'}
        $file=[IO.MemoryStream]::new()
        $stream=$entries[0].Open()
        try{$stream.CopyTo($file);$executable=$file.ToArray()}finally{$stream.Dispose();$file.Dispose()}
        $digest=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($executable)).ToLowerInvariant()
        if($digest -cne $info.ExecutableSha256){throw 'Ripgrep-Programm hat eine ungueltige SHA256-Pruefsumme.'}
        $directory=Split-Path -Parent $info.Path
        Assert-ShadowDirectPath -Path $directory
        [void][IO.Directory]::CreateDirectory($directory)
        $temporary=Join-Path $directory ('.shadow-ripgrep-'+[guid]::NewGuid().ToString('N')+'.tmp')
        try{
            $file=[IO.File]::Open($temporary,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
            try{$file.Write($executable,0,$executable.Length)}finally{$file.Dispose()}
            Assert-ShadowDirectPath -Path $info.Path
            [IO.File]::Move($temporary,$info.Path)
        }finally{if(Test-Path -LiteralPath $temporary){Remove-Item -LiteralPath $temporary -Force}}
    }finally{$archive.Dispose();$memory.Dispose()}
    return Assert-ShadowRipgrepReady -InstallRoot $InstallRoot
}

function Test-ShadowKiloSearch {
    param([Parameter(Mandatory)][string]$InstallRoot,[Parameter(Mandatory)][string]$KiloExecutable,
          [string[]]$KiloArgumentPrefix=@(),[Parameter(Mandatory)][string]$ConfigJson)
    $directory=Join-Path ([IO.Path]::GetTempPath()) ('shadow-kilo-search-'+[guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($directory)
    try{
        $needle='SHADOW_RIPGREP_VERIFICATION_1742'
        [IO.File]::WriteAllText((Join-Path $directory 'probe.txt'),$needle,[Text.UTF8Encoding]::new($false))
        $environment=Get-ShadowLocalEnvironment -InstallRoot $InstallRoot -ConfigJson $ConfigJson
        $result=Invoke-ShadowNative -FilePath $KiloExecutable -ArgumentList (@($KiloArgumentPrefix)+@('debug','rg','search',$needle)) -WorkingDirectory $directory -Environment $environment -Quiet -AllowFailure -TimeoutSeconds 120
        if($result.ExitCode -ne 0){throw "Kilo-Dateisuche konnte nicht ausgefuehrt werden (Exitcode $($result.ExitCode))."}
        try{$matches=ConvertFrom-Json -InputObject $result.StdOut -AsHashtable -NoEnumerate -ErrorAction Stop}
        catch{throw 'Kilo-Dateisuche lieferte kein gueltiges Ergebnis-JSON.'}
        if($matches -isnot [array] -or $matches.Count -ne 1 -or
           $matches[0] -isnot [Collections.IDictionary] -or -not $matches[0].Contains('entry') -or
           $matches[0].entry -isnot [Collections.IDictionary] -or -not $matches[0].entry.Contains('path') -or
           -not $matches[0].Contains('text') -or $matches[0].entry.path -cne 'probe.txt' -or $matches[0].text -cne $needle){
            throw 'Kilo-Dateisuche hat die Testdatei nicht eindeutig gefunden.'
        }
        $files=Invoke-ShadowNative -FilePath $KiloExecutable -ArgumentList (@($KiloArgumentPrefix)+@('debug','rg','files','--glob','*.txt')) -WorkingDirectory $directory -Environment $environment -Quiet -AllowFailure -TimeoutSeconds 120
        if($files.ExitCode -ne 0 -or $files.StdOut.Trim() -cne 'probe.txt'){
            throw "Kilo-Dateiauflistung konnte die Testdatei nicht eindeutig finden (Exitcode $($files.ExitCode))."
        }
    }finally{if(Test-Path -LiteralPath $directory){Remove-Item -LiteralPath $directory -Recurse -Force}}
}
