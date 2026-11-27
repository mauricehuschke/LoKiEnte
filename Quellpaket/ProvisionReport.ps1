# Structured, incremental local provisioning evidence. No VM/container dependency.
Set-StrictMode -Version Latest

function Protect-ShadowDiagnosticValue {
    param($Value,[string]$Name='')
    if($Name -match '(?i)(api.?key|password|secret|authorization|token)$'){return '[REDACTED]'}
    if($null -eq $Value){return $null}
    if($Value -is [string]){
        $safe=$Value
        foreach($entry in [Environment]::GetEnvironmentVariables('Process').GetEnumerator()){
            if($entry.Key -match '(?i)token|api.?key|password|secret' -and ([string]$entry.Value).Length -gt 3){$safe=$safe.Replace([string]$entry.Value,'[REDACTED]')}
        }
        return ($safe -replace '(?i)(Bearer\s+|Basic\s+)[A-Za-z0-9+/_=.:-]+','$1[REDACTED]' -replace '(?i)((?:api[_-]?key|password|authorization|access_token|refresh_token)\s*["'']?\s*[:=]\s*["'']?)[^\s"'',;}]+','$1[REDACTED]' -replace '(?i)([?&](?:token|key|password)=)[^&\s]+','$1[REDACTED]')
    }
    # Pipeline-decorated numbers (e.g. Select-Object -Unique) can also satisfy
    # -is [pscustomobject]. Preserve their scalar value instead of serializing {}.
    if($Value -is [ValueType]){return $Value}
    if($Value -is [Collections.IDictionary]){
        $result=[ordered]@{};foreach($key in $Value.Keys){$result[[string]$key]=Protect-ShadowDiagnosticValue $Value[$key] ([string]$key)};return ,$result
    }
    if($Value -is [Collections.IEnumerable]){
        $result=[Collections.Generic.List[object]]::new();foreach($item in $Value){$result.Add((Protect-ShadowDiagnosticValue $item))};return ,$result.ToArray()
    }
    if($Value -is [pscustomobject]){
        $result=[ordered]@{};foreach($property in $Value.PSObject.Properties){$result[$property.Name]=Protect-ShadowDiagnosticValue $property.Value $property.Name};return ,$result
    }
    return $Value
}

function Save-ShadowProvisionReport {
    $session=Get-Variable ShadowProvisionSession -Scope Script -ValueOnly -ErrorAction SilentlyContinue
    if(-not $session -or $session.saving){return}
    $session.saving=$true
    try{
        $session.report.updatedUtc=[DateTime]::UtcNow.ToString('o')
        $safe=Protect-ShadowDiagnosticValue $session.report
        $temporary=$session.path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
        try{[IO.File]::WriteAllText($temporary,($safe|ConvertTo-Json -Depth 80),[Text.UTF8Encoding]::new($false));[IO.File]::Move($temporary,$session.path,$true)}
        finally{if(Test-Path -LiteralPath $temporary){Remove-Item -LiteralPath $temporary -Force}}
    }finally{$session.saving=$false}
}

function Start-ShadowProvisionReport {
    param([Parameter(Mandatory)][string]$InstallRoot,[Parameter(Mandatory)][Collections.IDictionary]$Report,[Collections.IDictionary]$Parameters=@{})
    $path=Join-Path $InstallRoot 'provisioning-report.json'
    [void][IO.Directory]::CreateDirectory($InstallRoot)
    if(Test-Path -LiteralPath $path){
        $backup=Join-Path $InstallRoot 'backups/reports';[void][IO.Directory]::CreateDirectory($backup)
        Copy-Item -LiteralPath $path -Destination (Join-Path $backup ([DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffffffZ')+'-provisioning-report.json'))
    }
    $Report.schema=2;$Report.runId=[guid]::NewGuid().ToString('N')
    $Report.parameters=Protect-ShadowDiagnosticValue $Parameters
    $Report.activities=@();$Report.tests=@();$Report.commands=@();$Report.events=@()
    $Report.runtimeRequirements=@{dockerRequired=$false;hyperVRequired=$false;acceptance='Native Windows VS Code Extension Host, Kilo runtimes and local LM Studio; no container or VM.'}
    $Report.environment=[ordered]@{machine=[Environment]::MachineName;user=[Environment]::UserName;os=[Environment]::OSVersion.VersionString;architecture=[Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString();processArchitecture=[Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString();powerShell=$PSVersionTable.PSVersion.ToString();edition=$PSVersionTable.PSEdition;clr=[Environment]::Version.ToString();culture=[Globalization.CultureInfo]::CurrentCulture.Name;timeZone=[TimeZoneInfo]::Local.Id;processId=$PID;workingDirectory=[string]$PWD;variables=[ordered]@{}}
    foreach($key in @('PATH','PSModulePath','TEMP','TMP','PROCESSOR_ARCHITECTURE','NUMBER_OF_PROCESSORS','SystemRoot','LOCALAPPDATA','USERPROFILE','NO_PROXY','KILO_DISABLE_CODEBASE_INDEXING')){$Report.environment.variables[$key]=[Environment]::GetEnvironmentVariable($key,'Process')}
    $Report.environment.credentialVariableNames=@([Environment]::GetEnvironmentVariables('Process').Keys|Where-Object {$_ -match '(?i)token|api.?key|password|secret'})
    $script:ShadowProvisionSession=@{root=$InstallRoot;path=$path;report=$Report;saving=$false;sequence=0;streamSequence=0;started=[DateTime]::UtcNow}
    Save-ShadowProvisionReport
}

function Add-ShadowProvisionEvidence {
    param([ValidateSet('activities','tests','commands','events')][string]$Kind,$Value)
    $session=Get-Variable ShadowProvisionSession -Scope Script -ValueOnly -ErrorAction SilentlyContinue
    if(-not $session -or $session.saving){return}
    $session.sequence++
    $item=[ordered]@{sequence=$session.sequence;utc=[DateTime]::UtcNow.ToString('o')}
    foreach($key in $Value.Keys){$item[$key]=$Value[$key]}
    $safe=Protect-ShadowDiagnosticValue $item
    $session.report[$Kind]+= @($safe)
    Save-ShadowProvisionReport
}

function Add-ShadowProvisionCommand {
    param([string]$File,[string[]]$Arguments,[string]$WorkingDirectory,[int]$TimeoutSeconds,$ExitCode,[string]$Stdout,[string]$Stderr,[double]$DurationMs,[string]$Failure,[switch]$ExpectedFailure)
    $session=Get-Variable ShadowProvisionSession -Scope Script -ValueOnly -ErrorAction SilentlyContinue
    if(-not $session){return}
    $streams=[ordered]@{}
    foreach($entry in @(@{name='stdout';text=$Stdout},@{name='stderr';text=$Stderr})){
        $safe=[string](Protect-ShadowDiagnosticValue $entry.text)
        $stream=[ordered]@{characters=$safe.Length;text=$safe;truncated=$false}
        if($safe.Length -gt 262144){
            $session.streamSequence++
            $relative='diagnostics/provisioning/'+$session.report.runId+'/'+$session.streamSequence+'-'+$entry.name+'.log'
            $full=Join-Path $session.root $relative;[void][IO.Directory]::CreateDirectory((Split-Path -Parent $full))
            [IO.File]::WriteAllText($full,$safe,[Text.UTF8Encoding]::new($false))
            $stream.text=$safe.Substring(0,131072)+"`n[... truncated; complete redacted output in fullLog ...]`n"+$safe.Substring($safe.Length-131072)
            $stream.truncated=$true;$stream.fullLog=$relative
        }
        $streams[$entry.name]=$stream
    }
    Add-ShadowProvisionEvidence commands @{file=$File;arguments=$Arguments;workingDirectory=$WorkingDirectory;timeoutSeconds=$TimeoutSeconds;exitCode=$ExitCode;durationMs=[math]::Round($DurationMs,1);status=$(if($Failure){'ERROR'}elseif($null -ne $ExitCode -and $ExitCode -ne 0){if($ExpectedFailure){'EXPECTED_NONZERO_EXIT'}else{'NONZERO_EXIT'}}else{'COMPLETED'});expectedFailure=[bool]$ExpectedFailure;failure=$Failure;streamsCaptureComplete=($Failure -notmatch 'timeout|deadline|output.*close');streams=$streams}
}

function Invoke-ShadowProvisionStep {
    param([string]$Id,[string]$Component='Provisioning',[ValidateSet('Action','Test')][string]$Kind='Action',[Parameter(Mandatory)][scriptblock]$Action)
    $watch=[Diagnostics.Stopwatch]::StartNew()
    Add-ShadowProvisionEvidence activities @{id=$Id;component=$Component;kind=$Kind;status='RUNNING'}
    try{
        $value=& $Action
        if($Kind -eq 'Test' -and (($value -is [bool] -and -not $value) -or ($null -ne $value -and $null -ne $value.PSObject.Properties['ExitCode'] -and $value.ExitCode -ne 0))){throw 'The test action returned an unsuccessful result.'}
        $evidence=@{id=$Id;component=$Component;kind=$Kind;status=$(if($Kind -eq 'Test'){'PASS'}else{'COMPLETED'});durationMs=$watch.Elapsed.TotalMilliseconds;result=$value}
        Add-ShadowProvisionEvidence activities $evidence
        if($Kind -eq 'Test'){Add-ShadowProvisionEvidence tests $evidence}
        return $value
    }catch{
        $evidence=@{id=$Id;component=$Component;kind=$Kind;status='FAIL';durationMs=$watch.Elapsed.TotalMilliseconds;error=$_.Exception.Message;script=$_.InvocationInfo.ScriptName;line=$_.InvocationInfo.ScriptLineNumber;stack=$_.ScriptStackTrace}
        Add-ShadowProvisionEvidence activities $evidence
        if($Kind -eq 'Test'){Add-ShadowProvisionEvidence tests $evidence}
        throw
    }
}

function Complete-ShadowProvisionReport {
    param([Management.Automation.ErrorRecord]$Failure)
    $session=Get-Variable ShadowProvisionSession -Scope Script -ValueOnly -ErrorAction SilentlyContinue
    if(-not $session){return}
    $report=$session.report
    if($report.Contains('smokeTests')){
        if($report.smokeTests -is [string]){Add-ShadowProvisionEvidence tests @{id='model-smoke-tests';component='LM Studio';status='SKIPPED';evidence='ModelAction Keep reused saved state; current-run inference smoke tests were not executed.'}}
        else{
            $normalized=Protect-ShadowDiagnosticValue $report.smokeTests
            $groups=if($normalized -is [Collections.IDictionary]){@(@{model='single';checks=$normalized})}else{@($normalized)}
            foreach($group in $groups){foreach($name in $group.checks.Keys){$value=[string]$group.checks[$name];$status=switch($value){'Passed'{'PASS'} 'NotRun'{'SKIPPED'} 'NotVerified'{'FAIL'} default{'BLOCKED'}};Add-ShadowProvisionEvidence tests @{id=('model:'+$group.model+':'+$name);component='LM Studio';status=$status;evidence=$value}}}
        }
    }
    if($report.Contains('acceptance')){
        $acceptanceCases=if($report.acceptance -is [Collections.IDictionary]){if($report.acceptance.Contains('cases')){$report.acceptance.cases}else{@()}}elseif($report.acceptance.PSObject.Properties['cases']){$report.acceptance.cases}else{@()}
        foreach($case in @($acceptanceCases)){Add-ShadowProvisionEvidence tests @{id=('acceptance:'+$case.id);component='Live toolchain acceptance';status=$case.status;evidence=$case.evidence}}
        if($report.acceptance.PSObject.Properties['dependencies']){foreach($case in @($report.acceptance.dependencies.cases)){Add-ShadowProvisionEvidence tests @{id=('dependency:'+$case.id);component='Installed dependencies';status=$case.status;evidence=$case.evidence}}}
    }
    if($Failure){$report.failure=@{type=$Failure.Exception.GetType().FullName;message=$Failure.Exception.Message;innerException=[string]$Failure.Exception.InnerException;errorId=$Failure.FullyQualifiedErrorId;category=[string]$Failure.CategoryInfo;script=$Failure.InvocationInfo.ScriptName;line=$Failure.InvocationInfo.ScriptLineNumber;position=$Failure.InvocationInfo.PositionMessage;stack=$Failure.ScriptStackTrace}}
    $report.snapshots=[ordered]@{}
    foreach($file in @('inventory.json','toolchain.json','dependency-versions.json','provisioning-options.json','model-selection.json','workspaces.json','security/profile.json','runtime/model-pool.json','runtime/runtime-state.json','runtime/model-switch-failure.json','runtime/embedding-status.json','runtime/startup-health.json','vscode-data/User/settings.json','kilo-managed/kilo.json','diagnostics/toolchain/latest.json')){
        $full=Join-Path $session.root $file
        if(Test-Path -LiteralPath $full -PathType Leaf){try{$report.snapshots[$file]=Protect-ShadowDiagnosticValue (Get-Content -LiteralPath $full -Raw|ConvertFrom-Json -AsHashtable)}catch{$report.snapshots[$file]=@{error=$_.Exception.Message}}}
    }
    $report.extensionManifestInventory=@()
    $extensions=Join-Path $session.root 'vscode-extensions'
    if(Test-Path -LiteralPath $extensions){
        foreach($directory in Get-ChildItem -LiteralPath $extensions -Directory -ErrorAction SilentlyContinue){
            if($directory.Attributes -band [IO.FileAttributes]::ReparsePoint){continue}
            $manifest=Join-Path $directory.FullName 'package.json'
            if(Test-Path -LiteralPath $manifest){try{$value=Get-Content -LiteralPath $manifest -Raw|ConvertFrom-Json -AsHashtable;$report.extensionManifestInventory+=@(@{id=([string]$value.publisher+'.'+$value.name);version=$value.version;path=$directory.FullName;engines=$value['engines'];dependencies=$value['extensionDependencies'];note='Installed files; runtime activation is recorded separately in startup-health / acceptance.'})}catch{$report.extensionManifestInventory+=@(@{path=$directory.FullName;error=$_.Exception.Message})}}
        }
    }
    # Include this run's controller/VS Code logs and in-progress acceptance files.
    $report.logs=@()
    foreach($folder in @('runtime','diagnostics/toolchain','vscode-data/logs')){
        $base=Join-Path $session.root $folder
        if(-not(Test-Path -LiteralPath $base)){continue}
        foreach($file in Get-ChildItem -LiteralPath $base -Recurse -File -ErrorAction SilentlyContinue|Where-Object {$_.LastWriteTimeUtc -ge $session.started -and $_.Extension -in @('.log','.jsonl','.xml','.json')} ){
            if($file.Attributes -band [IO.FileAttributes]::ReparsePoint){continue}
            if($file.Name -in @('auth.json','router-control.json')){continue}
            $relative=[IO.Path]::GetRelativePath($session.root,$file.FullName)
            if($report.snapshots.Contains($relative.Replace('\','/'))){continue}
            try{
                $stream=[IO.File]::Open($file.FullName,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
                try{$size=$stream.Length;$offset=[math]::Max(0,$size-262144);[void]$stream.Seek($offset,[IO.SeekOrigin]::Begin);$reader=[IO.StreamReader]::new($stream,[Text.Encoding]::UTF8);try{$text=$reader.ReadToEnd()}finally{$reader.Dispose()}}finally{$stream.Dispose()}
                $report.logs+=@(@{path=$relative;bytes=$size;truncated=($offset -gt 0);tail=(Protect-ShadowDiagnosticValue $text)})
            }catch{$report.logs+=@(@{path=$relative;error=$_.Exception.Message})}
        }
    }
    $report.finishedUtc=[DateTime]::UtcNow.ToString('o')
    Save-ShadowProvisionReport
}
