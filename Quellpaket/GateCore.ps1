# Requires PowerShell 7. This file only defines functions and is safe to dot-source.
Set-StrictMode -Version Latest

function Write-ShadowUtf8File {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent)) { [void][IO.Directory]::CreateDirectory($parent) }
    $temp = $Path + '.tmp-' + [guid]::NewGuid().ToString('N')
    [IO.File]::WriteAllText($temp, $Text, [Text.UTF8Encoding]::new($false))
    [IO.File]::Move($temp, $Path, $true)
}

function Invoke-ShadowNativeProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [Parameter(Mandatory)][string]$StdoutPath,
        [Parameter(Mandatory)][string]$StderrPath,
        [ValidateRange(1,86400)][int]$TimeoutSeconds = 1800,
        [hashtable]$Environment = @{},
        [switch]$CleanEnvironment,
        [scriptblock]$OnStdoutLine
    )
    if ([IO.Path]::GetExtension($FilePath) -in @('.cmd','.bat','.ps1')) {
        throw "A native executable is required: $FilePath. Use node.exe plus its script, or pwsh.exe -File."
    }
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $FilePath
    $start.WorkingDirectory = $WorkingDirectory
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
    $start.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)
    $start.CreateNoWindow = $true
    foreach ($argument in $ArgumentList) { [void]$start.ArgumentList.Add([string]$argument) }
    if($CleanEnvironment){$start.Environment.Clear()}
    foreach ($key in $Environment.Keys) { $start.Environment[[string]$key] = [string]$Environment[$key] }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $timedOut = $false
    $started = $false
    $outWriter=$null;$errWriter=$null
    try {
        if (-not $process.Start()) { throw "Cannot start $FilePath" }
        $started=$true
        if($OnStdoutLine){
            # Drain both streams while making whole lines visible to the controller.
            # A callback failure must never leave an editing child running.
            foreach($path in @($StdoutPath,$StderrPath)){Write-ShadowUtf8File -Path $path -Text ''}
            $outWriter=[IO.StreamWriter]::new([IO.FileStream]::new($StdoutPath,[IO.FileMode]::Append,[IO.FileAccess]::Write,[IO.FileShare]::Read),[Text.UTF8Encoding]::new($false))
            $errWriter=[IO.StreamWriter]::new([IO.FileStream]::new($StderrPath,[IO.FileMode]::Append,[IO.FileAccess]::Write,[IO.FileShare]::Read),[Text.UTF8Encoding]::new($false))
            $outWriter.AutoFlush=$true;$errWriter.AutoFlush=$true
            try{
                $outTask=$process.StandardOutput.ReadLineAsync();$errTask=$process.StandardError.ReadLineAsync()
                $outDone=$false;$errDone=$false;$drainDeadline=[double]::PositiveInfinity
                while(-not $outDone -or -not $errDone -or -not $process.HasExited){
                    if(-not $outDone -and $outTask.IsCompleted){
                        $line=$outTask.GetAwaiter().GetResult()
                        if($null -eq $line){$outDone=$true}else{$outWriter.WriteLine($line);& $OnStdoutLine $line | Out-Null;$outTask=$process.StandardOutput.ReadLineAsync()}
                    }
                    if(-not $errDone -and $errTask.IsCompleted){
                        $line=$errTask.GetAwaiter().GetResult()
                        if($null -eq $line){$errDone=$true}else{$errWriter.WriteLine($line);$errTask=$process.StandardError.ReadLineAsync()}
                    }
                    if(-not $timedOut -and $watch.Elapsed.TotalSeconds -ge $TimeoutSeconds){
                        $timedOut=$true;try{$process.Kill($true)}catch{}
                        $drainDeadline=$watch.Elapsed.TotalSeconds+10
                    }
                    if($watch.Elapsed.TotalSeconds -gt $drainDeadline){break}
                    if(($outDone -or -not $outTask.IsCompleted) -and ($errDone -or -not $errTask.IsCompleted)){Start-Sleep -Milliseconds 10}
                }
                [void]$process.WaitForExit(10000)
            }catch{
                if(-not $process.HasExited){try{$process.Kill($true);[void]$process.WaitForExit(10000)}catch{}}
                throw
            }finally{$outWriter.Dispose();$errWriter.Dispose()}
            $code=if($timedOut){124}else{$process.ExitCode}
            return [pscustomobject]@{ExitCode=$code;TimedOut=$timedOut;DurationSeconds=[math]::Round($watch.Elapsed.TotalSeconds,2);StdoutPath=$StdoutPath;StderrPath=$StderrPath}
        }
        # Drain both pipes concurrently to avoid deadlocks on long build output.
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $timedOut = $true
            try { $process.Kill($true) } catch { }
            [void]$process.WaitForExit(10000)
        }
        $outText = $stdout.GetAwaiter().GetResult()
        $errText = $stderr.GetAwaiter().GetResult()
        Write-ShadowUtf8File -Path $StdoutPath -Text $outText
        Write-ShadowUtf8File -Path $StderrPath -Text $errText
        $exitCode = if ($timedOut) { 124 } else { $process.ExitCode }
        [pscustomobject]@{ ExitCode=$exitCode; TimedOut=$timedOut; DurationSeconds=[math]::Round($watch.Elapsed.TotalSeconds,2); StdoutPath=$StdoutPath; StderrPath=$StderrPath }
    }
    finally {
        # Covers setup failures too (for example a log writer that cannot open).
        if($started -and -not $process.HasExited){try{$process.Kill($true);[void]$process.WaitForExit(10000)}catch{}}
        if($outWriter){$outWriter.Dispose()};if($errWriter){$errWriter.Dispose()}
        $watch.Stop(); $process.Dispose()
    }
}

function Get-ShadowGitOutput {
    param([Parameter(Mandatory)][string]$ProjectPath, [Parameter(Mandatory)][string[]]$Arguments,
        [int[]]$AllowedExitCodes=@(0))
    $git = (Get-Command git -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName=$git; $start.WorkingDirectory=$ProjectPath; $start.UseShellExecute=$false
    $start.RedirectStandardOutput=$true; $start.RedirectStandardError=$true
    $start.StandardOutputEncoding=[Text.UTF8Encoding]::new($false)
    [void]$start.ArgumentList.Add('-c'); [void]$start.ArgumentList.Add('core.quotepath=false')
    foreach ($arg in $Arguments) { [void]$start.ArgumentList.Add($arg) }
    $process=[Diagnostics.Process]::new(); $process.StartInfo=$start
    try {
        [void]$process.Start()
        $output=$process.StandardOutput.ReadToEndAsync(); $errorText=$process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(120000)) { $process.Kill($true); throw 'Git command timed out.' }
        $result=$output.GetAwaiter().GetResult(); $errorResult=$errorText.GetAwaiter().GetResult()
        if ($process.ExitCode -notin $AllowedExitCodes) { throw "Git failed ($($process.ExitCode)): $errorResult" }
        return $result
    } finally { $process.Dispose() }
}

function Get-ShadowSourceFingerprint {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectPath)
    $root=(Get-ShadowGitOutput $ProjectPath @('rev-parse','--show-toplevel')).Trim()
    $root=[IO.Path]::GetFullPath($root)
    $requested=[IO.Path]::GetFullPath($ProjectPath).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
    if (-not [string]::Equals($root.TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar),$requested,[StringComparison]::OrdinalIgnoreCase)) {
        throw 'ProjectPath must be the Git repository root, not a nested folder.'
    }
    $head=(Get-ShadowGitOutput $root @('rev-parse','HEAD')).Trim()
    $status=Get-ShadowGitOutput $root @('status','--porcelain=v1','-z','--untracked-files=all')
    $diff=Get-ShadowGitOutput $root @('diff','--binary','--no-ext-diff','--no-textconv','HEAD','--')
    $stagedDiff=Get-ShadowGitOutput $root @('diff','--cached','--binary','--no-ext-diff','--no-textconv','HEAD','--')
    $untracked=Get-ShadowGitOutput $root @('ls-files','--others','--exclude-standard','-z')
    $paths=@($untracked.Split([char]0,[StringSplitOptions]::RemoveEmptyEntries) | Sort-Object -CaseSensitive)
    $records=[Collections.Generic.List[string]]::new()
    $records.Add("HEAD=$head"); $records.Add("STATUS=$status"); $records.Add("DIFF=$diff"); $records.Add("STAGED=$stagedDiff")
    foreach($relative in $paths) {
        $absolute=Join-Path $root $relative
        $item=Get-Item -LiteralPath $absolute -Force -ErrorAction Stop
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Untracked link cannot be fingerprinted safely: $relative" }
        if($item.PSIsContainer) { throw "Untracked nested directory/repository needs separate review: $relative" }
        $hash=(Get-FileHash -LiteralPath $absolute -Algorithm SHA256 -ErrorAction Stop).Hash
        $records.Add("UNTRACKED=$relative`0$hash")
    }
    # Gitlinks/submodules require their own independent review; fail closed here.
    $indexTree=Get-ShadowGitOutput $root @('ls-files','--stage','-z')
    if ($indexTree -match '(?:^|\x00)160000 ') { throw 'Repositories containing Git submodules need separate review runs; this gate does not certify nested repositories.' }
    $records.Add("INDEX=$indexTree")
    $bytes=[Text.Encoding]::UTF8.GetBytes(($records -join "`n"))
    $hashBytes=[Security.Cryptography.SHA256]::HashData($bytes)
    [pscustomobject]@{ Fingerprint=[Convert]::ToHexString($hashBytes).ToLowerInvariant(); Head=$head; Status=$status; Diff=$diff; StagedDiff=$stagedDiff; IndexEntries=$indexTree; Untracked=$paths; Root=$root; Scope='Git HEAD, tracked working/index changes and non-ignored untracked files; ignored files are excluded.' }
}

function ConvertFrom-ShadowAgentEvents {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$EventPath, [Parameter(Mandatory)][string]$ExpectedRole, [Parameter(Mandatory)][string]$Fingerprint)
    $texts=[Collections.Generic.List[string]]::new(); $sessions=[Collections.Generic.HashSet[string]]::new()
    $hadError=$false; $reason=''; $verdict=$null
    foreach($line in [IO.File]::ReadLines($EventPath)) {
        if([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $event=ConvertFrom-Json -InputObject $line -AsHashtable -ErrorAction Stop } catch { continue }
        if($event -isnot [Collections.IDictionary]) { continue }
        if($event.ContainsKey('sessionID') -and -not [string]::IsNullOrWhiteSpace([string]$event.sessionID)) { [void]$sessions.Add([string]$event.sessionID) }
        if($event.ContainsKey('type') -and $event.type -eq 'error') { $hadError=$true }
        if($event.Contains('type') -and $event.type -eq 'tool_use' -and $event.Contains('part') -and $event.part -is [Collections.IDictionary] -and $event.part.Contains('state') -and $event.part.state -is [Collections.IDictionary] -and $event.part.state.Contains('status') -and $event.part.state.status -ceq 'error') { $hadError=$true }
        if($event.ContainsKey('type') -and $event.type -eq 'text' -and $event.ContainsKey('part') -and $event.part -is [Collections.IDictionary] -and $event.part.Contains('text')) {
            $texts.Add([string]$event.part.text)
        }
    }
    if($texts.Count -eq 0) { $reason='No final text event was found.' }
    else {
        # Accept a complete JSON response or one JSON code fence; never infer PASS from prose.
        $candidate=$texts[$texts.Count-1].Trim()
        if($candidate -match '(?s)^```(?:json)?\s*(.*?)\s*```$') { $candidate=$Matches[1] }
        try { $verdict=ConvertFrom-Json -InputObject $candidate -AsHashtable -ErrorAction Stop } catch { $reason='Final text is not a valid JSON verdict.' }
        if($verdict -isnot [Collections.IDictionary]) { $verdict=$null; if(-not $reason){$reason='Verdict must be a JSON object.'} }
    }
    $valid=$false
    if($null -ne $verdict) {
        foreach($key in @('schema_version','role','verdict','source_fingerprint','findings','summary')) {
            if(-not $verdict.Contains($key)) { $reason="Missing verdict field: $key"; break }
        }
        if(-not $reason) {
            if(($verdict.schema_version -isnot [int] -and $verdict.schema_version -isnot [long]) -or $verdict.schema_version -ne 1) { $reason='Unsupported verdict schema.' }
            elseif($verdict.role -isnot [string] -or $verdict.role -cne $ExpectedRole) { $reason='Unexpected role in verdict.' }
            elseif($verdict.source_fingerprint -cne $Fingerprint) { $reason='Verdict refers to a different source fingerprint.' }
            elseif($verdict.verdict -cnotin @('PASS','FAIL','BLOCKED')) { $reason='Unknown verdict value.' }
            elseif($verdict.findings -isnot [System.Array]) { $reason='findings must be an array.' }
            elseif([string]::IsNullOrWhiteSpace([string]$verdict.summary)) { $reason='A substantive summary is required.' }
            elseif($sessions.Count -ne 1) { $reason='Exactly one independent Kilo session ID is required.' }
            elseif($hadError) { $reason='Kilo reported an error event.' }
            else { $valid=$true }
        }
    }
    [pscustomobject]@{ Valid=$valid; Reason=$reason; SessionIds=@($sessions); Verdict=$verdict; HadError=$hadError }
}

function Test-ShadowReviewGate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Review, [Parameter(Mandatory)]$Validation,
        [AllowEmptyCollection()][object[]]$Checks=@(),
        [Parameter(Mandatory)][string]$ExpectedFingerprint,
        [Parameter(Mandatory)][string]$FinalFingerprint,
        $ImplementationSucceeded=$true,
        $ProcessSucceeded=$true
    )
    $reasons=[Collections.Generic.List[string]]::new()
    if($ImplementationSucceeded -isnot [bool] -or -not $ImplementationSucceeded){$reasons.Add('Implementation did not finish successfully.')}
    if($ProcessSucceeded -isnot [bool] -or -not $ProcessSucceeded){$reasons.Add('A review/validation process failed or timed out.')}
    if($ExpectedFingerprint -cne $FinalFingerprint){$reasons.Add('Source changed during or after review/validation.')}
    $reviewIsValid=($Review.Valid -is [bool] -and $Review.Valid)
    $validationIsValid=($Validation.Valid -is [bool] -and $Validation.Valid)
    if(-not $reviewIsValid){$reasons.Add("Invalid review: $($Review.Reason)")}
    if(-not $validationIsValid){$reasons.Add("Invalid validation: $($Validation.Reason)")}
    if($reviewIsValid -and $validationIsValid) {
        if($Review.SessionIds[0] -ceq $Validation.SessionIds[0]){$reasons.Add('Review and validation must be independent sessions.')}
        foreach($result in @($Review,$Validation)) {
            if($result.Verdict.verdict -cne 'PASS'){$reasons.Add("$($result.Verdict.role) did not pass.")}
            if(@($result.Verdict.findings).Count -gt 0){$reasons.Add("$($result.Verdict.role) has unresolved findings.")}
            if($result.Verdict.source_fingerprint -cne $ExpectedFingerprint){$reasons.Add('Verdict fingerprint mismatch.')}
        }
    }
    if($Checks.Count -eq 0){$reasons.Add('No explicit executable validation checks were configured.')}
    foreach($check in $Checks) {
        if($check.ExitCode -ne 0 -or $check.TimedOut){$reasons.Add("Check failed: $($check.Name)")}
    }
    if($validationIsValid) {
        if(-not $Validation.Verdict.Contains('checks_seen') -or $Validation.Verdict.checks_seen -isnot [System.Array]) {
            $reasons.Add('Validation agent did not enumerate checks_seen.')
        } else {
            if(@($Validation.Verdict.checks_seen).Count -ne $Checks.Count){$reasons.Add('Validation check count does not match execution.')}
            foreach($check in $Checks){if([string]$check.Name -cnotin @($Validation.Verdict.checks_seen)){$reasons.Add("Validation omitted check: $($check.Name)")}}
        }
    }
    $status=if($reasons.Count -eq 0){'VERIFIED'}elseif($Checks.Count -eq 0 -and $reviewIsValid -and $Review.Verdict.verdict -ceq 'PASS' -and @($Review.Verdict.findings).Count -eq 0 -and $ExpectedFingerprint -ceq $FinalFingerprint -and $ImplementationSucceeded -is [bool] -and $ImplementationSucceeded -and $ProcessSucceeded -is [bool] -and $ProcessSucceeded){'REVIEWED_UNVALIDATED'}else{'NOT_VERIFIED'}
    [pscustomobject]@{Status=$status; Verified=($status -eq 'VERIFIED'); Reasons=@($reasons)}
}
