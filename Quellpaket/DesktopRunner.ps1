Set-StrictMode -Version Latest

function Install-ShadowDesktopRunner {
    param([Parameter(Mandatory)][string]$InstallRoot,[Parameter(Mandatory)][string]$PowerShellPath)
    $directory=Join-Path $InstallRoot 'tooling/desktop-runner'
    $marker=Join-Path $directory 'owner.json';$binary=Join-Path $directory 'LoKiEnte.exe'
    if(Test-Path -LiteralPath $directory){
        if(-not(Test-Path -LiteralPath $marker)){throw 'Unknown desktop runner directory remains unchanged.'}
        $previous=Get-Content -LiteralPath $marker -Raw|ConvertFrom-Json
        if($previous.owner -cne 'lokiente-desktop-runner'){throw 'Unknown desktop runner owner.'}
        if((Test-Path -LiteralPath $binary) -and (Get-FileHash -LiteralPath $binary -Algorithm SHA256).Hash -ine $previous.binarySha256){throw 'Changed desktop runner executable remains unchanged. Inspect the local file.'}
    }
    $compiler=Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
    if(-not(Test-Path -LiteralPath $compiler)){throw 'Windows .NET Framework C# compiler is unavailable. The console-free desktop launcher cannot be built.'}
    $source=Join-Path $PSScriptRoot 'desktop-runner/Launcher.cs'
    $sourceHash=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
    [void][IO.Directory]::CreateDirectory($directory)
    if(-not(Test-Path -LiteralPath $marker)){[IO.File]::WriteAllText($marker,'{"owner":"lokiente-desktop-runner","binarySha256":"","sourceSha256":""}')}
    $previous=Get-Content -LiteralPath $marker -Raw|ConvertFrom-Json
    if(-not(Test-Path -LiteralPath $binary) -or $previous.sourceSha256 -ine $sourceHash){
        $temporary=Join-Path $directory ('LoKiEnte-'+[guid]::NewGuid().ToString('N')+'.exe')
        try{
            $null=Invoke-ShadowNative -FilePath $compiler -ArgumentList @('/nologo','/target:winexe','/optimize+','/reference:System.Windows.Forms.dll','/reference:System.Runtime.Serialization.dll',('/win32icon:'+(Join-Path $PSScriptRoot 'assets/lokiente.ico')),('/out:'+$temporary),$source) -Quiet -TimeoutSeconds 60
            [IO.File]::Move($temporary,$binary,$true)
        }finally{if(Test-Path -LiteralPath $temporary){Remove-Item -LiteralPath $temporary -Force}}
    }
    $state=@{owner='lokiente-desktop-runner';sourceSha256=$sourceHash;binarySha256=(Get-FileHash -LiteralPath $binary -Algorithm SHA256).Hash}
    [IO.File]::WriteAllText($marker,($state|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $directory 'powershell-path.txt'),[IO.Path]::GetFullPath($PowerShellPath),[Text.UTF8Encoding]::new($false))
    return $binary
}

function Start-ShadowEditor {
    param([string]$InstallRoot,[string]$CodePath,[string[]]$Arguments,[string]$WorkingDirectory,[Collections.IDictionary]$Environment,[switch]$WaitForHost)
    $runner=Join-Path $InstallRoot 'tooling/desktop-runner/LoKiEnte.exe'
    if(-not(Test-Path -LiteralPath $runner)){throw 'Console-free launcher is missing. Run provisioning with the current installer.'}
    $id=[guid]::NewGuid().ToString('N');$directory=Join-Path $InstallRoot 'runtime/launch-requests';[void][IO.Directory]::CreateDirectory($directory)
    $request=Join-Path $directory ($id+'.json')
    [IO.File]::WriteAllText($request,(@{file=$CodePath;arguments=$Arguments;workingDirectory=$WorkingDirectory;runId=$id}|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
    if($WaitForHost){[IO.File]::WriteAllText((Join-Path $directory 'current-launch.json'),(@{runId=$id;helperVersion=$Environment['LOKIENTE_STARTUP_VERSION'];utc=[DateTime]::UtcNow.ToString('o')}|ConvertTo-Json),[Text.UTF8Encoding]::new($false))}
    $start=[Diagnostics.ProcessStartInfo]::new($runner);$start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.WorkingDirectory=$WorkingDirectory
    [void]$start.ArgumentList.Add('--editor');[void]$start.ArgumentList.Add($request)
    foreach($key in $Environment.Keys){$start.Environment[$key]=[string]$Environment[$key]}
    $start.Environment['LOKIENTE_EDITOR_LAUNCH_ID']=$id
    foreach($key in @($start.Environment.Keys)){if($key -match '^(VSCODE|ELECTRON)_'){[void]$start.Environment.Remove($key)}}
    $process=[Diagnostics.Process]::Start($start)
    try{Write-ShadowToolchainEvent -Component 'Desktop runner' -Message "Editor log collector started (PID $($process.Id), launch $id)."}finally{$process.Dispose()}
    if($WaitForHost){$null=Wait-ShadowEditorHost -InstallRoot $InstallRoot -RunId $id -ExpectedVersion $Environment['LOKIENTE_STARTUP_VERSION']}
    return $id
}

function Wait-ShadowEditorHost {
    param([string]$InstallRoot,[string]$RunId,[string]$ExpectedVersion,[ValidateRange(1,300)][int]$TimeoutSeconds=90)
    $file=Join-Path $InstallRoot ('runtime/startup-handshakes/'+$RunId+'.json')
    $watch=[Diagnostics.Stopwatch]::StartNew()
    while($watch.Elapsed.TotalSeconds -lt $TimeoutSeconds){
        if(Test-Path -LiteralPath $file){
            try{$state=Get-Content -LiteralPath $file -Raw|ConvertFrom-Json}catch{$state=$null}
            if($state -and $state.launchId -ceq $RunId -and $state.helperVersion -ceq $ExpectedVersion -and [IO.Path]::GetFullPath($state.dataDirectory) -ieq [IO.Path]::GetFullPath((Join-Path $InstallRoot 'vscode-data'))){return $state}
        }
        $processStatus=Join-Path $InstallRoot ('runtime/launch-requests/'+$RunId+'.status.json')
        if(Test-Path -LiteralPath $processStatus){
            try{$status=Get-Content -LiteralPath $processStatus -Raw|ConvertFrom-Json}catch{$status=$null}
            if($status -and $status.phase -eq 'failed'){throw "VS Code process could not start: $($status.error). See runtime/launcher-logs."}
        }
        Start-Sleep -Milliseconds 200
    }
    throw "VS Code did not confirm the current LoKiEnte helper $ExpectedVersion in the managed profile. Fully close older managed VS Code windows and reopen LoKiEnte. See runtime/launcher-logs and Extension Host logs; installation listing alone does not prove a running extension."
}

function Test-ShadowDesktopRunnerReady {
    param([string]$InstallRoot,[string]$NodePath,[string]$WorkingDirectory)
    $directory=Join-Path $InstallRoot 'tooling/desktop-runner';$binary=Join-Path $directory 'LoKiEnte.exe'
    $owner=Get-Content -LiteralPath (Join-Path $directory 'owner.json') -Raw|ConvertFrom-Json
    if($owner.owner -cne 'lokiente-desktop-runner' -or (Get-FileHash -LiteralPath $binary).Hash -ine $owner.binarySha256){throw 'The installed desktop launcher cannot be verified.'}
    $bytes=[IO.File]::ReadAllBytes($binary);$header=[BitConverter]::ToInt32($bytes,60)
    if([BitConverter]::ToUInt16($bytes,$header+24+68) -ne 2){throw 'Desktop executable is not a console-free Windows GUI application.'}
    $marker='LOKIENTE_DESKTOP_PROBE_'+[guid]::NewGuid().ToString('N')
    $id=Start-ShadowEditor -InstallRoot $InstallRoot -CodePath $NodePath -Arguments @('-e',('console.log("'+$marker+'")')) -WorkingDirectory $WorkingDirectory -Environment @{}
    $log=Join-Path $InstallRoot ('runtime/launcher-logs/'+$id+'-editor.log');$watch=[Diagnostics.Stopwatch]::StartNew()
    while($watch.Elapsed.TotalSeconds -lt 15){
        if(Test-Path -LiteralPath $log){$text=[IO.File]::ReadAllText($log);if($text.Contains($marker) -and $text.Contains('Process exited with code 0')){return}}
        Start-Sleep -Milliseconds 100
    }
    throw 'The native desktop collector did not confirm its real child-process/output probe.'
}
