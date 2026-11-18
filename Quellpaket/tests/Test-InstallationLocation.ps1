#requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory)][string]$BootstrapPath)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($BootstrapPath,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Bootstrap parser errors'}
foreach($definition in $ast.EndBlock.Statements|Where-Object {$_ -is [Management.Automation.Language.FunctionDefinitionAst]}){
    . ([scriptblock]::Create($definition.Extent.Text))
}
$count=0
function Assert-Location([bool]$Condition,[string]$Message){
    if(-not $Condition){throw "FAIL: $Message"}
    $script:count++
    Write-Host "PASS: $Message"
}
function Assert-LocationThrow([scriptblock]$Action,[string]$Pattern,[string]$Message){
    $errorText=$null
    try{& $Action|Out-Null}catch{$errorText=$_.Exception.Message}
    Assert-Location ($errorText -and $errorText -match $Pattern) $Message
}
function Write-Fixture([string]$Path,[string]$Text){
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path))
    [IO.File]::WriteAllText($Path,$Text,(New-Object Text.UTF8Encoding($false)))
}
function Read-Host {
    param($Prompt)
    $script:prompts++
    if($null -ne $script:answers){
        if($script:answers.Count -eq 0){throw 'Unexpected repeated menu prompt'}
        return $script:answers.Dequeue()
    }
    return $script:answer
}
function Get-CimInstance {param($ClassName,$ErrorAction) return $script:processes}
$root=Join-Path ([IO.Path]::GetTempPath()) ('shadow-location-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
$script:processes=@();$script:prompts=0;$script:answer='1';$script:answers=$null
try{
    $source=Join-Path $root "old user's install"
    $target=Join-Path $root 'script directory'
    $selected=Select-BootstrapInstallation $target $source
    Assert-Location ($selected.Root -ceq $target -and -not $selected.CopyFrom -and $script:prompts -eq 0) 'Absent legacy directory needs no selection'
    $driveRoot=[IO.Path]::GetPathRoot($root)
    Assert-Location ((Select-BootstrapInstallation $driveRoot $source).Root -ceq $driveRoot) 'Drive-root target stays absolute'
    Write-Fixture (Join-Path $source 'shadow-local-ai-install.json') '{"schema":1,"product":"ShadowLocalAI"}'
    foreach($choice in @('1','2','3')){
        $script:answer=$choice
        $selected=Select-BootstrapInstallation $target $source
        $expected=if($choice -eq '2'){$source}else{$target}
        Assert-Location ($selected.Root -ceq $expected -and [bool]$selected.CopyFrom -eq ($choice -eq '3')) "Legacy selection $choice chooses the requested action"
    }
    $script:answer='cancel'
    Assert-LocationThrow {Select-BootstrapInstallation $target $source} 'cancelled' 'Invalid selection cancels'
    $claimed=Join-Path $root 'claimed'
    Write-Fixture (Join-Path $claimed 'shadow-local-ai-install.json') '{"schema":1,"product":"ShadowLocalAI"}'
    Write-Fixture (Join-Path $claimed 'app\sentinel.txt') 'target work'
    $script:answers=[Collections.Generic.Queue[string]]::new()
    $script:answers.Enqueue('3');$script:answers.Enqueue('1')
    $selected=Select-BootstrapInstallation $claimed $source
    Assert-Location ($selected.Root -ceq $claimed -and $null -eq $selected.CopyFrom -and $script:answers.Count -eq 0 -and
        [IO.File]::ReadAllText((Join-Path $claimed 'app\sentinel.txt')) -ceq 'target work') 'Repeated copy into an owned target returns to menu and allows explicit continuation without writes'
    $conflict=Join-Path $root 'unclaimed conflict'
    Write-Fixture (Join-Path $source 'app\source.txt') 'source work'
    Write-Fixture (Join-Path $conflict 'app\target.txt') 'other work'
    $script:answers=[Collections.Generic.Queue[string]]::new()
    $script:answers.Enqueue('3');$script:answers.Enqueue('2')
    $selected=Select-BootstrapInstallation $conflict $source
    Assert-Location ($selected.Root -ceq $source -and $null -eq $selected.CopyFrom -and $script:answers.Count -eq 0 -and
        [IO.File]::ReadAllText((Join-Path $conflict 'app\target.txt')) -ceq 'other work') 'Unowned name conflict is reported before confirmation and user can select the old root'
    $invalid=Join-Path $root 'invalid marker'
    Write-Fixture (Join-Path $invalid 'shadow-local-ai-install.json') '{"product":"other","schema":1}'
    $script:answers=[Collections.Generic.Queue[string]]::new()
    $script:answers.Enqueue('3');$script:answers.Enqueue('2')
    $selected=Select-BootstrapInstallation $invalid $source
    Assert-Location ($selected.Root -ceq $source -and $null -eq $selected.CopyFrom -and
        [IO.File]::ReadAllText((Join-Path $invalid 'shadow-local-ai-install.json')) -ceq '{"product":"other","schema":1}') 'Invalid target identity never authorizes copying or overwriting'
    $script:answers=$null
    $selection=[pscustomobject]@{Root=$target;CopyFrom=$source}
    foreach($answer in @('','n','Y','yes','y')){
        $script:answer=$answer
        Assert-Location ((Confirm-BootstrapInstallation $selection) -eq ($answer -ceq 'y')) "Only literal y confirms ($answer)"
    }
    Write-Fixture (Join-Path $target 'unrelated.txt') 'keep'
    Assert-BootstrapInstallRoot -Root $target -AllowSharedDirectory
    Assert-Location ([IO.File]::ReadAllText((Join-Path $target 'unrelated.txt')) -ceq 'keep') 'Unrelated script-directory contents are preserved'
    Write-Fixture (Join-Path $target 'toolchain.json') '{}'
    Assert-LocationThrow {Assert-BootstrapInstallRoot -Root $target -AllowSharedDirectory} 'name conflict' 'Unowned managed-name collision is rejected'
    Remove-Item -LiteralPath (Join-Path $target 'toolchain.json')
    Write-Fixture (Join-Path $source 'app\fixture.ps1') '# copied app'
    Write-Fixture (Join-Path $source 'provisioning.lock') ''
    Write-Fixture (Join-Path $source 'runtime\model-pool.lock') ''
    Write-Fixture (Join-Path $source 'runtime\model-ownership.json') '{"SchemaVersion":1,"OwnerId":"012345678901234567890123","Entries":[]}'
    Write-Fixture (Join-Path $source 'runtime\model-pool.json') '{"ModelPath":"external/model.gguf","LmsPath":"C:\\LM Studio\\lms.exe"}'
    Write-Fixture (Join-Path $source 'vscode-data\User\settings.json') '{"editor.fontSize":17,"externalPath":"D:\\My Models"}'
    Write-Fixture (Join-Path $source 'workspaces.json') '[]'
    Write-Fixture (Join-Path $source 'toolchain.json') (@{
        kiloArgumentPrefix=@((Join-Path $source 'tooling\kilo.js'))
        sibling=$source+'-other\keep.js';outside='C:\Existing\node.exe'
    }|ConvertTo-Json)
    Write-Fixture (Join-Path $source 'kilo-managed\kilo.json') (@{instructions=@((Join-Path $source 'kilo-managed\rules.md'))}|ConvertTo-Json)
    Write-Fixture (Join-Path $source 'workspaces\project.code-workspace') (@{
        folders=@(@{path=(Join-Path $source 'projects\state')},@{path='D:\ExternalRepo'})
        tasks=@{tasks=@(@{args=@('-InstallRoot',$source);problemMatcher=@()})}
    }|ConvertTo-Json -Depth 10)
    Write-Fixture (Join-Path $source 'provisioning-report.json') '{"schema":1,"status":"PROVISIONED"}'
    $external=Join-Path $root 'LM Studio configuration.json'
    Write-Fixture $external '{"modelsDirectory":"D:\\My Models"}'
    $before=@{}
    foreach($file in Get-ChildItem -LiteralPath $source -File -Recurse -Force){$before[$file.FullName]=(Get-FileHash -LiteralPath $file.FullName).Hash}
    $script:processes=@([pscustomobject]@{ProcessId=999999;CommandLine='node.exe "'+(Join-Path $source 'app\ModelRouter.mjs')+'"'})
    Assert-LocationThrow {Copy-BootstrapInstallation $source $target} 'processes' 'Running source applications block the copy'
    $script:processes=@()
    $held=[IO.File]::Open((Join-Path $source 'provisioning.lock'),[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    try{Assert-LocationThrow {Copy-BootstrapInstallation $source $target} 'locked' 'Concurrent source provisioning blocks the copy'}finally{$held.Dispose()}
    Assert-LocationThrow {Copy-BootstrapInstallation $source (Join-Path $source 'nested')} 'nested' 'Overlapping roots are rejected'
    Copy-BootstrapInstallation $source $target
    $chain=Get-Content -LiteralPath (Join-Path $target 'toolchain.json') -Raw|ConvertFrom-Json
    Assert-Location ($chain.kiloArgumentPrefix[0] -ceq (Join-Path $target 'tooling\kilo.js') -and $chain.outside -ceq 'C:\Existing\node.exe' -and $chain.sibling -ceq ($source+'-other\keep.js')) 'Managed paths relocate without rewriting external paths or sibling prefixes'
    $index=ConvertFrom-Json -InputObject ('{"value":'+[IO.File]::ReadAllText((Join-Path $target 'workspaces.json'))+'}')
    Assert-Location ($index.value -is [array] -and $index.value.Count -eq 0) 'Empty workspace registry retains its array shape'
    $workspace=Get-Content -LiteralPath (Join-Path $target 'workspaces\project.code-workspace') -Raw|ConvertFrom-Json
    Assert-Location ($workspace.tasks.tasks[0].args[1] -ceq $target -and $workspace.folders[1].path -ceq 'D:\ExternalRepo' -and $workspace.tasks.tasks[0].problemMatcher.Count -eq 0) 'Workspace task paths relocate; external repositories and arrays survive'
    foreach($relative in @('app\fixture.ps1','runtime\model-ownership.json','runtime\model-pool.json','vscode-data\User\settings.json')){
        Assert-Location ((Get-FileHash -LiteralPath (Join-Path $target $relative)).Hash -ceq $before[(Join-Path $source $relative)]) "Copy preserves bytes of $relative"
    }
    foreach($file in $before.Keys){if((Get-FileHash -LiteralPath $file).Hash -cne $before[$file]){throw 'Copy modified the source'}}
    Assert-Location ((Get-ChildItem -LiteralPath $source -File -Recurse -Force).Count -eq $before.Count -and [IO.File]::ReadAllText($external) -ceq '{"modelsDirectory":"D:\\My Models"}') 'Source and LM Studio configuration stay unchanged'
    $report=Get-Content -LiteralPath (Join-Path $target 'provisioning-report.json') -Raw|ConvertFrom-Json
    Assert-Location ($report.status -ceq 'INCOMPLETE' -and $report.installRoot -ceq $target -and @(Get-ChildItem -LiteralPath (Join-Path $target 'backups\migration') -File -Recurse).Count -eq 1) 'Copied installation requires provisioning and retains its prior report'
    Assert-Location (-not(Test-Path -LiteralPath (Join-Path $target 'runtime\model-pool.lock')) -and -not(Test-Path -LiteralPath (Join-Path $target 'provisioning.lock'))) 'Source lock files are not copied'
    Assert-LocationThrow {Copy-BootstrapInstallation $source $target} 'already' 'Copy never merges or overwrites an existing destination'

    $failed=Join-Path $root 'rollback target'
    $moveDefinition=$ast.EndBlock.Statements|Where-Object {$_ -is [Management.Automation.Language.FunctionDefinitionAst] -and $_.Name -eq 'Move-BootstrapCopyEntry'}
    function Move-BootstrapCopyEntry {
        param($Source,$Destination)
        if($Destination -ceq (Join-Path $failed 'toolchain.json')){throw 'Synthetic publish failure'}
        if((Get-Item -LiteralPath $Source -Force).PSIsContainer){[IO.Directory]::Move($Source,$Destination)}else{[IO.File]::Move($Source,$Destination)}
    }
    Assert-LocationThrow {Copy-BootstrapInstallation $source $failed} 'Synthetic publish failure' 'Publish failure is explicit'
    Assert-Location (@(Get-ChildItem -LiteralPath $failed -Force).Count -eq 0) 'Publish failure rolls back only its own copied entries'
    . ([scriptblock]::Create($moveDefinition.Extent.Text))
    Write-Fixture (Join-Path $source 'toolchain.json') 'not JSON'
    Assert-LocationThrow {Copy-BootstrapInstallation $source $failed} 'Cannot migrate' 'Malformed managed configuration aborts before publication'
    Assert-Location (@(Get-ChildItem -LiteralPath $failed -Force).Count -eq 0) 'Failed staging leaves no partial destination'
    $linked=Join-Path $root 'linked source'
    Write-Fixture (Join-Path $linked 'shadow-local-ai-install.json') '{"schema":1,"product":"ShadowLocalAI"}'
    $null=New-Item -ItemType Junction -Path (Join-Path $linked 'junction') -Target $source
    Assert-LocationThrow {Copy-BootstrapInstallation $linked $failed} 'link' 'Source junctions cannot escape the copy boundary'
    [IO.Directory]::Delete((Join-Path $linked 'junction'))

    $hardlinkSource=Join-Path $root 'hardlink source'
    $hardlinkTarget=Join-Path $root 'hardlink target'
    Write-Fixture (Join-Path $hardlinkSource 'shadow-local-ai-install.json') '{"schema":1,"product":"ShadowLocalAI"}'
    $hardlinkFile=Join-Path $hardlinkSource 'tooling\package.txt'
    Write-Fixture $hardlinkFile 'old'
    [IO.File]::SetLastWriteTimeUtc($hardlinkFile,[datetime]'2020-01-01')
    $cacheLink=Join-Path $root 'package-cache.txt'
    $null=New-Item -ItemType HardLink -Path $cacheLink -Target $hardlinkFile
    [IO.File]::WriteAllText($cacheLink,'updated through cache link')
    Copy-BootstrapInstallation $hardlinkSource $hardlinkTarget
    Assert-Location ([IO.File]::ReadAllText((Join-Path $hardlinkTarget 'tooling\package.txt')) -ceq 'updated through cache link') 'Stale NTFS hardlink directory metadata does not falsely abort a consistent copy'
    Assert-Location ((Get-FileHash -LiteralPath $hardlinkFile).Hash -ceq (Get-FileHash -LiteralPath (Join-Path $hardlinkTarget 'tooling\package.txt')).Hash) 'Hardlinked source and copied content match exactly'

    $changingSource=Join-Path $root 'changing source'
    $changingTarget=Join-Path $root 'changing target'
    Write-Fixture (Join-Path $changingSource 'shadow-local-ai-install.json') '{"schema":1,"product":"ShadowLocalAI"}'
    $changingFile=Join-Path $changingSource 'app\changing.txt'
    Write-Fixture $changingFile 'before'
    [IO.File]::SetLastWriteTimeUtc($changingFile,[datetime]'2020-01-01')
    Write-Fixture (Join-Path $changingTarget 'unrelated.txt') 'keep'
    $script:sourceChanged=$false
    function Get-Item {
        [CmdletBinding()]
        param([string]$LiteralPath,[switch]$Force)
        if($LiteralPath -ceq $changingFile -and -not $script:sourceChanged){
            [IO.File]::WriteAllText($changingFile,'actually changed during copy')
            $script:sourceChanged=$true
        }
        Microsoft.PowerShell.Management\Get-Item @PSBoundParameters
    }
    try{
        Assert-LocationThrow {Copy-BootstrapInstallation $changingSource $changingTarget} 'changing\.txt.*UTC.*Bytes' 'Real source changes still abort and identify the file, timestamps and sizes'
    }finally{Remove-Item -LiteralPath 'Function:\Get-Item'}
    Assert-Location (@(Get-ChildItem -LiteralPath $changingTarget -Force).Count -eq 1 -and
        [IO.File]::ReadAllText((Join-Path $changingTarget 'unrelated.txt')) -ceq 'keep' -and
        [IO.File]::ReadAllText($changingFile) -ceq 'actually changed during copy') 'Source-change rejection removes only staging and preserves user files and source updates'

    # Run the actual wrapper in a child with installation boundaries replaced.
    $original=[IO.File]::ReadAllText($BootstrapPath)
    $mainAssignment=$ast.EndBlock.Statements|Where-Object {$_ -is [Management.Automation.Language.AssignmentStatementAst] -and $_.Left.Extent.Text -ceq '$setupLock'}
    $engine=(Get-Process -Id $PID).Path
    $wrapperSource=Join-Path $root 'wrapper copy source'
    Write-Fixture (Join-Path $wrapperSource 'shadow-local-ai-install.json') '{"schema":1,"product":"ShadowLocalAI"}'
    Write-Fixture (Join-Path $wrapperSource 'app\fixture.ps1') '# wrapper copy fixture'
    foreach($mode in @('decline','confirm','audit','noninteractive','copy-failure','copy-success')){
        $directory=Join-Path $root $mode
        $fixture=Join-Path $directory 'Provision-LoKiEnte.ps1'
        $stubs="`n`$env:LOCALAPPDATA='"+(Join-Path $root 'absent legacy').Replace("'","''")+"';`n"
        if($mode -eq 'decline'){$stubs+="function Read-Host {param(`$Prompt) return 'n'}`n"}
        if($mode -in @('confirm','copy-failure','copy-success')){$stubs+="function Read-Host {param(`$Prompt) return 'y'}`n"}
        if($mode -eq 'audit'){$stubs+="function Read-Host {throw 'PROMPT_MUST_NOT_RUN'}`n"}
        $stubs+=@'
function Find-BootstrapExecutable {throw 'INSTALL_MUST_NOT_RUN'}
function Read-BootstrapInventory {[pscustomobject]@{exitCode=0;installRoot=$InstallRoot;mode='AUDIT_ONLY'}}
'@
        if($mode -notlike 'copy-*'){
            $stubs+="`nfunction Assert-BootstrapInstallRoot {param([switch]`$AllowSharedDirectory) throw 'CONFIRMED_BEFORE_MUTATION'}`n"
        }else{
            $stubs+="`nfunction Select-BootstrapInstallation {param(`$RequestedRoot,`$LegacyRoot) [pscustomobject]@{Root=`$RequestedRoot;CopyFrom='"+$wrapperSource.Replace("'","''")+"'}}`n"
            $stubs+="function Get-CimInstance {param(`$ClassName,`$ErrorAction) return @()}`n"
            if($mode -eq 'copy-failure'){$stubs+="function Copy-BootstrapInstallation {param(`$SourceRoot,`$TargetRoot) throw 'SYNTHETIC_COPY_FAILURE'}`n"}
        }
        Write-Fixture $fixture ($original.Insert($mainAssignment.Extent.StartOffset,$stubs+"`n"))
        $start=New-Object Diagnostics.ProcessStartInfo
        $start.FileName=$engine;$start.WorkingDirectory=$root;$start.UseShellExecute=$false
        $args=@('-NoProfile','-NonInteractive','-File',$fixture)
        if($mode -eq 'audit'){$args+='-AuditOnly'}
        $start.Arguments=(@(foreach($arg in $args){ConvertTo-WindowsArgument $arg}) -join ' ')
        $start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
        $process=New-Object Diagnostics.Process
        $process.StartInfo=$start
        try{
            [void]$process.Start()
            $stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync()
            if(-not $process.WaitForExit(30000)){$process.Kill();throw 'Wrapper fixture timed out'}
            $output=$stdout.GetAwaiter().GetResult();$errorOutput=$stderr.GetAwaiter().GetResult()
            if($mode -eq 'audit'){
                Assert-Location ($process.ExitCode -eq 0 -and ($output|ConvertFrom-Json).installRoot -ceq $directory) 'Audit uses script directory without prompting'
            }elseif($mode -eq 'decline'){
                Assert-Location ($process.ExitCode -eq 0 -and $output.Contains($directory) -and -not $errorOutput) ("Default is script directory, not terminal working directory; declining exits cleanly. Exit="+$process.ExitCode+"; stderr="+$errorOutput.Substring(0,[Math]::Min(1000,$errorOutput.Length)))
            }elseif($mode -eq 'confirm'){
                Assert-Location ($process.ExitCode -eq 1 -and $errorOutput -match 'CONFIRMED_BEFORE_MUTATION') 'Literal y reaches setup validation'
            }elseif($mode -eq 'copy-success'){
                Assert-Location ($process.ExitCode -eq 1 -and $errorOutput -match 'INSTALL_MUST_NOT_RUN' -and
                    [IO.File]::ReadAllText((Join-Path $directory 'app\fixture.ps1')) -ceq '# wrapper copy fixture') 'Actual wrapper copies under its destination lock before installing prerequisites'
            }elseif($mode -eq 'copy-failure'){
                Assert-Location ($process.ExitCode -eq 1 -and $errorOutput -match 'SYNTHETIC_COPY_FAILURE') 'Actual wrapper propagates copy failure'
            }else{
                Assert-Location ($process.ExitCode -eq 1 -and $errorOutput -notmatch 'CONFIRMED_BEFORE_MUTATION|INSTALL_MUST_NOT_RUN') 'Noninteractive setup cannot silently authorize installation'
            }
            if($mode -eq 'copy-success'){
                $copyReport=Get-Content -LiteralPath (Join-Path $directory 'provisioning-report.json') -Raw|ConvertFrom-Json
                Assert-Location ($copyReport.status -ceq 'INCOMPLETE' -and (Test-Path -LiteralPath (Join-Path $directory 'shadow-local-ai-install.json'))) 'Later setup failure leaves a claimed, incomplete copy for rerun'
            }else{
                Assert-Location (@(Get-ChildItem -LiteralPath $directory -Force).Count -eq 1) "$mode wrapper leaves no unclaimed files or locks"
            }
        }finally{$process.Dispose()}
    }
    [pscustomobject]@{suite='Installation location';powerShell=$PSVersionTable.PSVersion.ToString();checks=$count;passed=$true}|ConvertTo-Json
}finally{Remove-Item -LiteralPath $root -Recurse -Force}
