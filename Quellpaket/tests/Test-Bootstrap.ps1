#requires -Version 7.4
<#
Independent tests for the PS5.1-compatible bootstrap and PS7 handoff.
Only temporary test directories and child PowerShell processes are used.
No WinGet/app/GPU installation or real setup is invoked.
Passing on PS7/Linux does not establish native Windows PowerShell 5.1 compatibility.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$BootstrapPath,
    [string]$HandoffPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'Invoke-SetupRequest.ps1')
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('shadow-bootstrap-tests-' + [guid]::NewGuid().ToString('N'))
$null = [IO.Directory]::CreateDirectory($testRoot)
$pwshExecutable = (Get-Process -Id $PID).Path
$script:testCount = 0

function Assert-BootstrapTest([bool]$Condition, [string]$Description) {
    if (-not $Condition) { throw "FAIL: $Description" }
    $script:testCount++
    Write-Host "PASS: $Description"
}
function Assert-BootstrapThrow([scriptblock]$Action, [string]$Pattern, [string]$Description) {
    $caught = $false
    try { & $Action | Out-Null } catch {
        $caught = $true
        if ($_.Exception.Message -notmatch $Pattern) { throw }
    }
    Assert-BootstrapTest $caught $Description
}
function Set-TestPayload {
    param([object[]]$Entries)
    $memory = [IO.MemoryStream]::new()
    try {
        $archive = [IO.Compression.ZipArchive]::new($memory, [IO.Compression.ZipArchiveMode]::Create, $true)
        try {
            foreach ($item in $Entries) {
                $entry = $archive.CreateEntry($item.Path)
                $stream = $entry.Open()
                try {
                    $bytes = [Text.Encoding]::UTF8.GetBytes($item.Content)
                    $stream.Write($bytes, 0, $bytes.Length)
                } finally { $stream.Dispose() }
            }
        } finally { $archive.Dispose() }
        $archiveBytes = $memory.ToArray()
        $script:payloadBase64 = [Convert]::ToBase64String($archiveBytes)
        $sha = [Security.Cryptography.SHA256]::Create()
        try { $script:payloadSha256 = ([BitConverter]::ToString($sha.ComputeHash($archiveBytes))).Replace('-', '').ToLowerInvariant() }
        finally { $sha.Dispose() }
    } finally { $memory.Dispose() }
}

try {
    $tokens = $null; $parseErrors = $null
    $bootstrapAst = [Management.Automation.Language.Parser]::ParseFile($BootstrapPath, [ref]$tokens, [ref]$parseErrors)
    Assert-BootstrapTest ($parseErrors.Count -eq 0) 'Bootstrap parses under installed PowerShell 7'
    $null = [Management.Automation.Language.Parser]::ParseFile($HandoffPath, [ref]$tokens, [ref]$parseErrors)
    Assert-BootstrapTest ($parseErrors.Count -eq 0) 'Handoff parses under installed PowerShell 7'
    # Import only function definitions. Never execute bootstrap installation code.
    foreach ($definition in $bootstrapAst.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] }, $false)) {
        . ([scriptblock]::Create($definition.Extent.Text))
    }
    $existingRoot=Join-Path $testRoot 'previous-installation'
    [void][IO.Directory]::CreateDirectory((Join-Path $existingRoot 'runtime'))
    Assert-BootstrapTest ((Read-BootstrapOptionState $existingRoot).Count -eq 0) 'Fresh root uses defaults'
    [IO.File]::WriteAllText((Join-Path $existingRoot 'shadow-local-ai-install.json'),'{}')
    [IO.File]::WriteAllText((Join-Path $existingRoot 'toolchain.json'),'{"modelMode":"Dual","allowUnfitAttempt":true}')
    [IO.File]::WriteAllText((Join-Path $existingRoot 'runtime/model-pool.json'),@'
{"Status":"Ready","ContextLength":16384,"BackendApiBaseUrl":"http://127.0.0.1:4590/v1","RouterApiBaseUrl":"http://127.0.0.1:4591/v1","ApiTokenEnvironmentVariable":"FIXTURE_TOKEN","AllowPartialGpuOffload":true,"Profiles":[{"Alias":"coder-high"},{"Alias":"fast"}]}
'@)
    $prior=Read-BootstrapOptionState $existingRoot
    Assert-BootstrapTest ($prior.ModelMode -ceq 'Dual' -and $prior.IncludeFastModel -and $prior.AllowPartialGpuOffload -and $prior.AllowUnfitAttempt -and $prior.Port -eq 4590 -and $prior.RouterPort -eq 4591) 'Legacy registered installation retains pool options'
    [IO.File]::WriteAllText((Join-Path $existingRoot 'provisioning-options.json'),'{"ModelMode":"Single","ModelKey":"existing/custom.gguf","ContextLength":8192,"ApiTokenEnvironmentVariable":"EXISTING_LOCAL_TOKEN"}')
    $prior=Read-BootstrapOptionState $existingRoot
    Assert-BootstrapTest ($prior.ModelMode -ceq 'Single' -and $prior.ModelKey -ceq 'existing/custom.gguf' -and $prior.ContextLength -eq 8192 -and $prior.ApiTokenEnvironmentVariable -ceq 'EXISTING_LOCAL_TOKEN') 'Recorded desired options supersede inferred legacy state'
    Assert-BootstrapTest ((ConvertTo-WindowsArgument '') -ceq '""') 'Empty native argument is quoted'
    Assert-BootstrapTest ((ConvertTo-WindowsArgument 'C:\with space\') -ceq '"C:\with space\\"') 'Trailing backslash is doubled before closing quote'
    Assert-BootstrapTest ((ConvertTo-WindowsArgument 'a"b') -ceq '"a\"b"') 'Embedded double quote is escaped'

    $receiver = Join-Path $testRoot 'argument-receiver.ps1'
    $argumentResult = Join-Path $testRoot 'argument-result.json'
    [IO.File]::WriteAllText($receiver, 'param([string]$OutputPath) [IO.File]::WriteAllText($OutputPath, (ConvertTo-Json -InputObject @($args) -Compress)); exit 0')
    $literalArguments = @('', 'plain', 'C:\with spaces\', 'quote"inside', 'slash\"quote', '$(throw ''MUST_NOT_EXECUTE'')', '$HOME; & test ` end', 'Unicode-Moe-ä-東京', "line1`nline2")
    $nativeExit = Invoke-BootstrapProcess -FilePath $pwshExecutable -Arguments (@('-NoLogo', '-NoProfile', '-File', $receiver, '-OutputPath', $argumentResult) + $literalArguments)
    Assert-BootstrapTest ($nativeExit -eq 0) 'Quoted native process starts successfully'
    $receivedArguments = @(Get-Content -LiteralPath $argumentResult -Raw | ConvertFrom-Json)
    Assert-BootstrapTest (($receivedArguments | ConvertTo-Json -Compress) -ceq ($literalArguments | ConvertTo-Json -Compress)) 'Spaces, quotes, slashes, Unicode and metacharacters round trip literally'

    Set-TestPayload @(@{ Path = 'one.txt'; Content = 'original' }, @{ Path = 'nested/two.txt'; Content = 'unchanged' })
    $install = Join-Path $testRoot 'install'
    Install-BootstrapPayload -Root $install
    Assert-BootstrapTest ([IO.File]::ReadAllText((Join-Path $install 'app/one.txt')) -ceq 'original') 'ZIP files extract to app'
    $firstWrite = (Get-Item -LiteralPath (Join-Path $install 'app/one.txt')).LastWriteTimeUtc
    Install-BootstrapPayload -Root $install
    Assert-BootstrapTest ((Get-Item -LiteralPath (Join-Path $install 'app/one.txt')).LastWriteTimeUtc -eq $firstWrite) 'Unchanged payload does not rewrite files'
    Assert-BootstrapTest (-not (Test-Path -LiteralPath (Join-Path $install 'backups'))) 'Unchanged payload creates no backup'
    Set-TestPayload @(@{ Path = 'one.txt'; Content = 'replacement' }, @{ Path = 'nested/two.txt'; Content = 'unchanged' })
    Install-BootstrapPayload -Root $install
    $backups = @(Get-ChildItem -LiteralPath (Join-Path $install 'backups') -File -Recurse)
    Assert-BootstrapTest ($backups.Count -eq 1 -and [IO.File]::ReadAllText($backups[0].FullName) -ceq 'original') 'Changed payload backs up original bytes exactly once'
    Assert-BootstrapTest ([IO.File]::ReadAllText((Join-Path $install 'app/one.txt')) -ceq 'replacement') 'Replacement is installed after backup'

    $badHashRoot = Join-Path $testRoot 'bad-hash'
    $script:payloadSha256 = '0' * 64
    Assert-BootstrapThrow { Install-BootstrapPayload -Root $badHashRoot } 'SHA256' 'Bad payload digest is rejected'
    Assert-BootstrapTest (-not (Test-Path -LiteralPath $badHashRoot)) 'Digest failure causes no extraction writes'
    Set-TestPayload @(@{ Path = '../escaped.txt'; Content = 'must not be written' })
    Assert-BootstrapThrow { Install-BootstrapPayload -Root (Join-Path $testRoot 'traversal') } 'Pfad|Paket' 'Parent traversal is rejected'
    Assert-BootstrapTest (-not (Test-Path -LiteralPath (Join-Path $testRoot 'traversal/escaped.txt'))) 'Traversal creates no outside file'
    $preflightRoot = Join-Path $testRoot 'preflight'
    Set-TestPayload @(@{ Path = 'valid-first.txt'; Content = 'must remain unwritten' }, @{ Path = '../bad-later.txt'; Content = 'invalid' })
    Assert-BootstrapThrow { Install-BootstrapPayload -Root $preflightRoot } 'Pfad|Paket' 'Every archive entry is validated before first write'
    Assert-BootstrapTest (-not (Test-Path -LiteralPath $preflightRoot)) 'Later invalid entry does not partially extract earlier files'
    Set-TestPayload @(@{ Path = 'same.txt'; Content = 'first' }, @{ Path = 'SAME.txt'; Content = 'second' })
    Assert-BootstrapThrow { Install-BootstrapPayload -Root (Join-Path $testRoot 'duplicates') } 'Doppelter' 'Case-insensitive duplicate ZIP destinations are rejected'
    Set-TestPayload @(@{ Path = 'file.txt:stream'; Content = 'invalid alternate stream' })
    Assert-BootstrapThrow { Install-BootstrapPayload -Root (Join-Path $testRoot 'ads') } 'Windows-Pfad' 'Windows alternate data stream paths are rejected'
    Set-TestPayload @(@{ Path = 'folder'; Content = 'file' }, @{ Path = 'folder/child.txt'; Content = 'child' })
    Assert-BootstrapThrow { Install-BootstrapPayload -Root (Join-Path $testRoot 'collision') } 'Kollision' 'File/directory collisions are rejected before extraction'

    # A pre-existing reparse point must not turn an owned relative path into an external write.
    $linkedRoot = Join-Path $testRoot 'linked'
    $outsideRoot = Join-Path $testRoot 'outside'
    $null = [IO.Directory]::CreateDirectory((Join-Path $linkedRoot 'app'))
    $null = [IO.Directory]::CreateDirectory($outsideRoot)
    $linkType = if ($IsWindows) { 'Junction' } else { 'SymbolicLink' }
    $null = New-Item -ItemType $linkType -Path (Join-Path $linkedRoot 'app/nested') -Target $outsideRoot
    Set-TestPayload @(@{ Path = 'nested/external.txt'; Content = 'must not escape' })
    Assert-BootstrapThrow { Install-BootstrapPayload -Root $linkedRoot } 'Reparse|Verknuepfung|symbol|junction' 'Existing directory reparse point is rejected'
    Assert-BootstrapTest (-not (Test-Path -LiteralPath (Join-Path $outsideRoot 'external.txt'))) 'Reparse-point rejection preserves external destination'
    $backupLinkedRoot = Join-Path $testRoot 'linked-backup'
    $null = [IO.Directory]::CreateDirectory($backupLinkedRoot)
    $null = New-Item -ItemType $linkType -Path (Join-Path $backupLinkedRoot 'backups') -Target $outsideRoot
    Set-TestPayload @(@{ Path = 'safe.txt'; Content = 'not yet written' })
    Assert-BootstrapThrow { Install-BootstrapPayload -Root $backupLinkedRoot } 'Reparse|Verknuepfung|symbol|junction' 'Existing backup directory reparse point is rejected'
    Assert-BootstrapTest (-not (Test-Path -LiteralPath (Join-Path $backupLinkedRoot 'app'))) 'Backup reparse failure occurs before app files are written'

    # Exercise the real in-memory dispatch and exit propagation without live CLIs/network.
    # The complete audit module is covered separately by Test-Audit.ps1 on PS5.1 and PS7.
    $auditHarness = Join-Path $testRoot 'audit-bootstrap.ps1'
    $auditInstall = Join-Path $testRoot 'audit-must-not-exist'
    Set-TestPayload @(
        @{Path='Audit.ps1';Content='param($InstallRoot,$ModelMode) [pscustomobject]@{schema=2;mode="AUDIT_ONLY";exitCode=2;status="BLOCKED";provisioningPerformed=$false;modelMode=$ModelMode}'},
        @{Path='Runtime.ps1';Content='# fixture'},
        @{Path='Common.ps1';Content='# fixture'},
        @{Path='ModelSelection.ps1';Content='# fixture'},
        @{Path='Ripgrep.ps1';Content='# fixture'}
    )
    $auditScript=[IO.File]::ReadAllText($BootstrapPath)
    $substitutions=@{'$payloadSha256'="'$script:payloadSha256'";'$payloadBase64'="'$script:payloadBase64'"}
    foreach($assignment in $bootstrapAst.FindAll({param($node) $node -is [Management.Automation.Language.AssignmentStatementAst] -and $substitutions.ContainsKey($node.Left.Extent.Text)},$false)|Sort-Object {$_.Right.Extent.StartOffset} -Descending){
        $extent=$assignment.Right.Extent
        $auditScript=$auditScript.Remove($extent.StartOffset,$extent.EndOffset-$extent.StartOffset).Insert($extent.StartOffset,$substitutions[$assignment.Left.Extent.Text])
    }
    [IO.File]::WriteAllText($auditHarness, $auditScript)
    $auditOutput = & $pwshExecutable -NoLogo -NoProfile -File $auditHarness -InstallRoot $auditInstall -AuditOnly
    $auditExit = $LASTEXITCODE
    Assert-BootstrapTest ($auditExit -eq 2) 'AuditOnly propagates blocked audit exit code without invoking setup'
    $inventory = $auditOutput | ConvertFrom-Json
    Assert-BootstrapTest ($inventory.mode -eq 'AUDIT_ONLY' -and -not $inventory.provisioningPerformed -and $inventory.modelMode -ceq 'Dual') 'AuditOnly executes the verified in-memory module and forwards model options'
    Assert-BootstrapTest (-not (Test-Path -LiteralPath $auditInstall)) 'AuditOnly does not create InstallRoot'
    if($IsWindows){
        $windowsPowerShell=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $legacyAudit=& $windowsPowerShell -NoLogo -NoProfile -NonInteractive -File $auditHarness -InstallRoot $auditInstall -AuditOnly
        Assert-BootstrapTest ($LASTEXITCODE -eq 2 -and ($legacyAudit|ConvertFrom-Json).mode -ceq 'AUDIT_ONLY') 'Actual Windows PowerShell 5.1 executes in-memory audit dispatch and preserves its exit code'
    }
    $auditScript=$auditScript.Replace("'$script:payloadSha256'",("'"+('0'*64)+"'"))
    [IO.File]::WriteAllText($auditHarness,$auditScript)
    $badAudit=& $pwshExecutable -NoLogo -NoProfile -File $auditHarness -InstallRoot $auditInstall -AuditOnly
    Assert-BootstrapTest ($LASTEXITCODE -eq 2 -and ($badAudit|ConvertFrom-Json).error -match 'SHA256') 'Invalid bundle produces structured audit failure before executing embedded code'
    $timedOut=$false
    try{$null=Invoke-BootstrapProcess $pwshExecutable @('-NoLogo','-NoProfile','-NonInteractive','-Command','Start-Sleep -Seconds 30') -TimeoutSeconds 1}catch{$timedOut=$_.Exception.Message -match 'Zeitlimit'}
    Assert-BootstrapTest $timedOut 'Bootstrap process timeout is bounded and explicit'
    $unboundedExit=Invoke-BootstrapProcess $pwshExecutable @('-NoLogo','-NoProfile','-NonInteractive','-Command','Start-Sleep -Milliseconds 200; exit 0') -TimeoutSeconds 0
    Assert-BootstrapTest ($unboundedExit -eq 0) 'Unbounded setup wait permits completion instead of killing the child immediately'

    # Use the real handoff script with a harmless stub Setup.ps1 in a temporary directory.
    $handoffRoot = Join-Path $testRoot 'handoff'
    $null = [IO.Directory]::CreateDirectory($handoffRoot)
    Copy-Item -LiteralPath $HandoffPath -Destination (Join-Path $handoffRoot 'Invoke-SetupRequest.ps1')
    $setupStub = Join-Path $handoffRoot 'Setup.ps1'
    $requestPath = Join-Path $handoffRoot 'request.json'
    [IO.File]::WriteAllText($requestPath, '{}')
    [IO.File]::WriteAllText($setupStub, 'exit 23')
    $null = & $pwshExecutable -NoLogo -NoProfile -File (Join-Path $handoffRoot 'Invoke-SetupRequest.ps1') -RequestPath $requestPath
    Assert-BootstrapTest ($LASTEXITCODE -eq 23) 'Handoff preserves a nonzero setup exit code'
    [IO.File]::WriteAllText($setupStub, 'exit 0')
    $null = & $pwshExecutable -NoLogo -NoProfile -File (Join-Path $handoffRoot 'Invoke-SetupRequest.ps1') -RequestPath $requestPath
    Assert-BootstrapTest ($LASTEXITCODE -eq 0) 'Handoff preserves successful setup exit code'
    [IO.File]::WriteAllText($requestPath, '{"UnapprovedOption":"x"}')
    $null = & $pwshExecutable -NoLogo -NoProfile -File (Join-Path $handoffRoot 'Invoke-SetupRequest.ps1') -RequestPath $requestPath 2>$null
    Assert-BootstrapTest ($LASTEXITCODE -ne 0) 'Handoff rejects unknown parameters'
    $handoffValueFile = Join-Path $handoffRoot 'received-request.json'
    [IO.File]::WriteAllText($setupStub, 'param($InstallRoot,$ProjectPath,$SkipModelDownload,[string]$ModelMode,[switch]$IncludeFastModel,[switch]$AllowPartialGpuOffload,[int]$RouterPort) @{InstallRoot=$InstallRoot;ProjectPath=@($ProjectPath);SkipModelDownload=$SkipModelDownload;ModelMode=$ModelMode;IncludeFastModel=[bool]$IncludeFastModel;AllowPartialGpuOffload=[bool]$AllowPartialGpuOffload;RouterPort=$RouterPort}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $PSScriptRoot "received-request.json"); exit 0')
    $requestObject = @{ InstallRoot = 'C:\Literal $(Get-Secret)'; ProjectPath = @('C:\one space', 'C:\two & space'); SkipModelDownload = $true; ModelMode='Dual'; IncludeFastModel=$true; AllowPartialGpuOffload=$true; RouterPort=2235 }
    [IO.File]::WriteAllText($requestPath, ($requestObject | ConvertTo-Json -Depth 5))
    $null = & $pwshExecutable -NoLogo -NoProfile -File (Join-Path $handoffRoot 'Invoke-SetupRequest.ps1') -RequestPath $requestPath
    $received = Get-Content -LiteralPath $handoffValueFile -Raw | ConvertFrom-Json
    Assert-BootstrapTest ($LASTEXITCODE -eq 0 -and $received.InstallRoot -ceq $requestObject.InstallRoot -and $received.ProjectPath.Count -eq 2 -and $received.SkipModelDownload -eq $true -and $received.ModelMode -ceq 'Dual' -and $received.IncludeFastModel -eq $true -and $received.AllowPartialGpuOffload -eq $true -and $received.RouterPort -eq 2235) 'JSON handoff preserves literal paths, arrays, booleans and model pool options'
    [IO.File]::WriteAllText($requestPath,'{}')
    [IO.File]::WriteAllText($setupStub,'[IO.File]::WriteAllText((Join-Path $PSScriptRoot "running"),"yes"); Start-Sleep -Seconds 5; exit 0')
    $start=[Diagnostics.ProcessStartInfo]::new()
    $start.FileName=$pwshExecutable;$start.UseShellExecute=$false
    foreach($argument in @('-NoLogo','-NoProfile','-NonInteractive','-File',(Join-Path $handoffRoot 'Invoke-SetupRequest.ps1'),'-RequestPath',$requestPath)){$start.ArgumentList.Add($argument)}
    $child=[Diagnostics.Process]::Start($start)
    try{
        $ready=Join-Path $handoffRoot 'running'
        for($i=0;$i -lt 50 -and -not(Test-Path -LiteralPath $ready);$i++){Start-Sleep -Milliseconds 100}
        Assert-BootstrapTest (Test-Path -LiteralPath $ready) 'Isolated handoff child started its setup'
        $busy=$false
        try{$lockProbe=[IO.File]::Open((Join-Path $testRoot 'setup-active.lock'),[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None);$lockProbe.Dispose()}
        catch [IO.IOException]{$busy=$true}
        Assert-BootstrapTest $busy 'Active setup child retains its own lock even if its parent is interrupted'
        if(-not $child.WaitForExit(15000)){throw 'Setup child timeout'}
        $lockProbe=[IO.File]::Open((Join-Path $testRoot 'setup-active.lock'),[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
        $lockProbe.Dispose()
        Assert-BootstrapTest ($child.ExitCode -eq 0) 'Child releases its setup lock after completion'
    }finally{
        if(-not $child.HasExited){$child.Kill();$child.WaitForExit()}
        $child.Dispose()
    }
    Write-Host "Bootstrap tests passed: $script:testCount. On Windows, in-memory audit dispatch is also exercised with Windows PowerShell 5.1."
} finally {
    $resolved=[IO.Path]::GetFullPath($testRoot)
    if(-not $resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notlike 'shadow-bootstrap-tests-*'){throw 'Unsafe cleanup path'}
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
