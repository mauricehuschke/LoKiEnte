#requires -Version 7.4
# Read-only discovery and deterministic policy compilation. The caller performs
# independent model review before Save-ShadowPreparedPolicy and owns the run lock.
Set-StrictMode -Version Latest

function Get-ShadowPreparationHash {
    param($Value)
    function ConvertTo-Canonical($Item){
        if($null -eq $Item){return $null}
        if($Item -is [Collections.IDictionary]){
            $result=[ordered]@{}
            foreach($key in @($Item.Keys | Sort-Object -CaseSensitive)){$result[$key]=ConvertTo-Canonical $Item[$key]}
            return $result
        }
        if($Item -is [array]){return ,@($Item | ForEach-Object {ConvertTo-Canonical $_})}
        return $Item
    }
    $json=ConvertTo-Json -InputObject (ConvertTo-Canonical $Value) -Depth 80 -Compress
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($json))).ToLowerInvariant()
}

function Test-ShadowPreparationFile {
    param([string]$ProjectPath,[string]$RelativePath)
    if($RelativePath -match '(?i)(?:^|/)(?:\.git|node_modules|\.venv|venv|\.kilo|\.kilocode|\.vscode)(?:/|$)|(?:^|/)(?:\.env[^/]*|auth\.json|credentials[^/]*|id_rsa[^/]*|.*\.(?:pem|pfx|key))$'){return $false}
    $cursor=$ProjectPath
    foreach($part in $RelativePath.Split('/')){
        if($part -in @('.','..') -or $part -match '[:\\]'){return $false}
        $cursor=Join-Path $cursor $part
        $item=Get-Item -LiteralPath $cursor -Force -ErrorAction SilentlyContinue
        if($item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){return $false}
    }
    return $true
}

function Get-ShadowPreparationContext {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectPath,[Parameter(Mandatory)][string]$InstallRoot,
        [Parameter(Mandatory)][string]$ChecksFile,[string]$ApplicationRoot=$PSScriptRoot)
    $project=[IO.Path]::GetFullPath((Resolve-Path -LiteralPath $ProjectPath).Path)
    $source=Get-ShadowSourceFingerprint -ProjectPath $project
    $all=Get-ShadowGitOutput $project @('ls-files','--cached','--others','--exclude-standard','-z')
    $files=@($all.Split([char]0,[StringSplitOptions]::RemoveEmptyEntries) | Sort-Object -Unique | Where-Object {Test-ShadowPreparationFile $project $_})
    if($files.Count -gt 20000){throw 'NEEDS_INPUT: Project has more than 20000 relevant files. Prepare a bounded part of the project.'}
    $tests=@($files | Where-Object {$_ -match '(?i)(?:^|/)(?:tests?|__tests__|specs?|e2e|integration)/|\.(?:test|spec)\.|(?:^|/)test_[^/]+$|_test\.[^/]+$'})
    $inputs=[ordered]@{};$manifests=[ordered]@{};$candidates=[Collections.Generic.List[object]]::new()
    $node=Get-Command node -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    $adapter=Join-Path $ApplicationRoot 'Run-ProjectCheck.mjs'
    $packagePath=Join-Path $project 'package.json';$package=@{}
    if(Test-Path -LiteralPath $packagePath -PathType Leaf){
        if(-not(Test-ShadowPreparationFile $project 'package.json')){throw 'NEEDS_INPUT: package.json is linked.'}
        if((Get-Item -LiteralPath $packagePath).Length -gt 1048576){throw 'NEEDS_INPUT: package.json is too large.'}
        $package=ConvertFrom-ShadowJsonObject ([IO.File]::ReadAllText($packagePath))
        $inputs['package.json']=(Get-FileHash -LiteralPath $packagePath).Hash
        $dependencies=@()
        foreach($section in @('dependencies','devDependencies')){
            if($package.Contains($section) -and $package[$section] -is [Collections.IDictionary]){$dependencies+=@($package[$section].Keys)}
        }
        $scripts=[ordered]@{}
        if($package.Contains('scripts') -and $package.scripts -is [Collections.IDictionary]){
            foreach($name in $package.scripts.Keys){
                if($name -match '(?i)test|check|lint|build|type'){
                    $command=[string]$package.scripts[$name]
                    # No secret-looking environment assignment is copied into a prompt.
                    $command=$command -replace '(?i)([A-Z0-9_]*(?:TOKEN|SECRET|PASSWORD|API_KEY)[A-Z0-9_]*\s*=\s*)(?:"[^"]*"|''[^'']*''|[^\s;&]+)','$1[REDACTED]'
                    if($command.Length -gt 2000){$command='[Command too long; inspect locally]'}
                    $scripts[$name]=$command
                }
            }
        }
        $manifests.package=@{dependencies=@($dependencies | Sort-Object -Unique);scripts=$scripts}
    }
    foreach($name in @('pyproject.toml','pytest.ini','setup.cfg','tox.ini','requirements.txt','package-lock.json','pnpm-lock.yaml','yarn.lock')){
        $full=Join-Path $project $name
        if((Test-Path -LiteralPath $full -PathType Leaf) -and (Test-ShadowPreparationFile $project $name)){$inputs[$name]=(Get-FileHash -LiteralPath $full).Hash}
    }
    # These are metadata/path hints, not commands obtained from repository text.
    $frameworks=[Collections.Generic.List[string]]::new()
    if($node){
        if($package.Count -or @($files | Where-Object {$_ -match '\.(?:cjs|mjs|js)$'}).Count){$frameworks.Add('node')}
        foreach($framework in @('vitest','jest','playwright','tsc')){
            $entry=switch($framework){'vitest'{'node_modules/vitest/vitest.mjs'} 'jest'{'node_modules/jest/bin/jest.js'} 'playwright'{'node_modules/@playwright/test/cli.js'} 'tsc'{'node_modules/typescript/bin/tsc'}}
            if(Test-Path -LiteralPath (Join-Path $project $entry) -PathType Leaf){$frameworks.Add($framework);$inputs[$entry]=(Get-FileHash -LiteralPath (Join-Path $project $entry)).Hash}
        }
    }
    $python=$null
    if((Test-Path -LiteralPath (Join-Path $project 'pyproject.toml')) -or (Test-Path -LiteralPath (Join-Path $project 'pytest.ini')) -or @($tests | Where-Object {$_ -like '*.py'}).Count){
        $localPython=Join-Path $project '.venv/Scripts/python.exe'
        if(Test-Path -LiteralPath $localPython -PathType Leaf){$python=$localPython}else{$found=Get-Command python -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1;if($found){$python=$found.Source}}
        if($python){$frameworks.Add('pytest')}
    }
    foreach($framework in $frameworks){
        $kinds=if($framework -ceq 'tsc'){@('static')}elseif($framework -ceq 'playwright'){@('integration')}else{@('test','integration')}
        foreach($kind in $kinds){
            $name="loki-$framework-$kind"
            $command=if($framework -ceq 'pytest'){$python}else{$node.Source}
            $args=if($framework -ceq 'pytest'){@('-m','pytest','--junitxml={report}','--')}else{@($adapter,'--framework',$framework,'--project',$project,'--report','{report}')}
            $definition=[ordered]@{name=$name;kind=$kind;command=$command;arguments=$args;timeoutSeconds=900}
            if($kind -cne 'static'){$definition.reportFormat=if($framework -ceq 'jest'){'json'}else{'junit'}}
            $candidates.Add([ordered]@{id=$name;origin='detected';framework=$framework;definition=$definition;testFiles=@();notes='Fixed local executable template. No shell, install, download or package lifecycle script. Test files are bound from the reviewed proposal.'})
        }
    }
    $existing=[ordered]@{};$existingHash=$null
    if(Test-Path -LiteralPath $ChecksFile){
        $item=Get-Item -LiteralPath $ChecksFile -Force
        if($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $item.Length -gt 1048576){throw 'NEEDS_INPUT: checks.json is not a regular size-limited file.'}
        $existing=ConvertFrom-ShadowJsonObject ([IO.File]::ReadAllText($ChecksFile))
        $existingHash=(Get-FileHash -LiteralPath $ChecksFile).Hash
        if($existing.Contains('checks')){
            if($existing.checks -isnot [array]){throw 'NEEDS_INPUT: Existing checks field is not an array.'}
            $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
            foreach($check in $existing.checks){
                if($check -isnot [Collections.IDictionary] -or -not $check.Contains('name') -or $check.name -isnot [string] -or -not $seen.Add($check.name)){throw 'NEEDS_INPUT: Existing checks are invalid or have duplicate names.'}
                $usable=$check.Contains('kind') -and $check.kind -in @('test','integration','static') -and $check.Contains('command') -and $check.Contains('arguments') -and $check.arguments -is [array] -and $check.Contains('timeoutSeconds')
                if($usable -and $check.kind -ne 'static'){$usable=$check.Contains('reportFormat') -and $check.reportFormat -in @('junit','json')}
                $candidates.Add([ordered]@{id='existing:'+ $check.name;origin='existing';framework='existing';usable=[bool]$usable;definition=$check;notes=if($usable){'Existing user check; retained unchanged.'}else{'Legacy incomplete check. A detected structured replacement must be explicitly selected and independently reviewed; original definition remains saved.'}})
            }
        }
    }
    return [pscustomobject]@{ProjectPath=$project;InstallRoot=[IO.Path]::GetFullPath($InstallRoot);ChecksFile=[IO.Path]::GetFullPath($ChecksFile);ExistingHash=$existingHash;ExistingPolicy=$existing;SourceFingerprint=$source.Fingerprint;InputHashes=$inputs;Inventory=[ordered]@{files=@($files | Select-Object -First 200);fileCount=$files.Count;filesTruncated=($files.Count -gt 200);testFileCount=$tests.Count;testFilesTruncated=($tests.Count -gt 200);manifests=$manifests;frameworks=$frameworks.ToArray();configurationFiles=@($files | Where-Object {$_ -match '(?i)(?:^|/)(?:(?:vitest|jest|playwright)\.config\.[^/]+|tsconfig[^/]*\.json|pytest\.ini|pyproject\.toml)$'} | Select-Object -First 30);instructions=@($files | Where-Object {$_ -match '(?i)(?:^|/)(?:AGENTS|README)\.md$'} | Select-Object -First 20)};Candidates=$candidates.ToArray();AllTestFiles=@($tests | Select-Object -First 200)}
}

function Get-ShadowPreparationPromptContext {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Context)
    # Keep the complete Context for auditing and deterministic compilation. Only
    # this bounded projection belongs in model prompts; hashes are not semantics.
    $existing=$Context.ExistingPolicy
    $taskFields=@('writePaths','testWritePaths','acceptanceCriteria','changeTypes','regressionCheck')
    $previous=[ordered]@{};$custom=[ordered]@{};$generated=@();$managed=$false
    foreach($field in $taskFields){if($existing.Contains($field)){$previous[$field]=$existing[$field]}}
    foreach($key in $existing.Keys){if($key -notin ($taskFields+@('checks','automation','schemaVersion','description'))){$custom[$key]=$existing[$key]}}
    if($existing.Contains('automation') -and $existing.automation -is [Collections.IDictionary] -and
        $existing.automation.Contains('owner') -and $existing.automation.owner -ceq 'LoKi task preparation v1'){
        $managed=$true
        if($existing.automation.Contains('generatedCheckNames')){$generated=@($existing.automation.generatedCheckNames)}
    }
    $candidateData=@($Context.Candidates | Where-Object { -not ($_.origin -ceq 'existing' -and $_.definition.name -cin $generated)} | ForEach-Object {
        $item=[ordered]@{id=$_.id;origin=$_.origin;framework=$_.framework;definition=$_.definition}
        if($_.Contains('usable')){$item.usable=$_.usable}
        $item
    })
    $sampleFiles=@($Context.Inventory.files | Select-Object -First 80)
    $sampleTests=@($Context.AllTestFiles | Select-Object -First 40)
    return [ordered]@{
        project=$Context.ProjectPath
        inventory=[ordered]@{files=$sampleFiles;fileCount=$Context.Inventory.fileCount;filesTruncated=($Context.Inventory.fileCount -gt $sampleFiles.Count);
            testFiles=$sampleTests;testFileCount=$Context.Inventory.testFileCount;testFilesTruncated=($Context.Inventory.testFileCount -gt $sampleTests.Count);
            manifests=$Context.Inventory.manifests;frameworks=$Context.Inventory.frameworks;configurationFiles=$Context.Inventory.configurationFiles;instructions=$Context.Inventory.instructions}
        candidates=$candidateData
        previousTaskFields=$previous
        manualFields=$custom
        previousTaskAutomaticallyManaged=$managed
        rules=@('Only supplied candidate IDs are executable choices; no invented shell commands or installs.',
            'Complete manual existing checks remain mandatory; incomplete checks remain saved and require a reviewed structured replacement.',
            'Previous task fields are rederived for this task after independent review; initial unmanaged values are archived. Manual edits to generated fields cause NEEDS_INPUT.',
            'Manual limits and custom fields remain unchanged. File lists are samples when truncated: inspect relevant project files read-only.',
            'Framework test files are deterministically bound from detected tests plus reviewed exact new test paths; prior generated commands are rebound, never selected as stale existing checks.')
    }
}

function New-ShadowPreparedPolicy {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)][string]$TaskText,[Parameter(Mandatory)][Collections.IDictionary]$Proposal)
    foreach($key in @('workflow','acceptanceCriteria','changeTypes','writePaths','testWritePaths','checkIds')){if(-not $Proposal.Contains($key)){throw "NEEDS_INPUT: Preparation missing $key."}}
    if($Proposal.workflow -cnotin @('Feature','Bugfix','Refactor','Review','Architecture')){throw 'NEEDS_INPUT: Unknown workflow.'}
    if($TaskText.Length -gt 20000 -or [string]::IsNullOrWhiteSpace($TaskText)){throw 'NEEDS_INPUT: Task missing or too large.'}
    $readonly=$Proposal.workflow -in @('Review','Architecture')
    foreach($key in @('writePaths','testWritePaths')){
        if($Proposal[$key] -isnot [array] -or $Proposal[$key].Count -gt 60){throw "NEEDS_INPUT: $key must be a bounded array."}
        if($Proposal[$key].Count){$null=Get-ShadowWritePaths -Policy @{writePaths=$Proposal[$key]} -ProjectPath $Context.ProjectPath}
    }
    if(-not $readonly -and -not $Proposal.writePaths.Count){throw 'NEEDS_INPUT: No production file scope identified.'}
    if($readonly -and ($Proposal.writePaths.Count -or $Proposal.testWritePaths.Count)){throw 'NEEDS_INPUT: Read-only task must not include write permissions.'}
    foreach($path in $Proposal.writePaths){if($path -in $Proposal.testWritePaths){throw 'NEEDS_INPUT: Production and test file scopes overlap.'}}
    $existing=$Context.ExistingPolicy
    if($existing.Contains('schemaVersion') -and $existing.schemaVersion -notin @(1,2)){throw 'NEEDS_INPUT: Unknown checks.json schema version. No automatic downgrade.'}
    $policy=ConvertFrom-ShadowJsonObject (ConvertTo-Json -InputObject $existing -Depth 80)
    $notes=[Collections.Generic.List[string]]::new();$imported=[ordered]@{}
    $taskFields=@('writePaths','testWritePaths','acceptanceCriteria','changeTypes','regressionCheck')
    $previousAuto=$null
    if($existing.Contains('automation')){
        if($existing.automation -isnot [Collections.IDictionary] -or -not $existing.automation.Contains('owner') -or $existing.automation.owner -cne 'LoKi task preparation v1'){throw 'NEEDS_INPUT: automation is already owned by something else.'}
        $previousAuto=$existing.automation
        if(-not $previousAuto.Contains('fieldHashes') -or $previousAuto.fieldHashes -isnot [Collections.IDictionary] -or
            -not $previousAuto.Contains('checkHashes') -or $previousAuto.checkHashes -isnot [Collections.IDictionary] -or
            -not $previousAuto.Contains('generatedCheckNames') -or $previousAuto.generatedCheckNames -isnot [array]){throw 'NEEDS_INPUT: Provenance record for prepared fields missing.'}
        foreach($field in $taskFields){
            if(-not $existing.Contains($field) -or -not $previousAuto.fieldHashes.Contains($field) -or (Get-ShadowPreparationHash $existing[$field]) -cne $previousAuto.fieldHashes[$field]){
                throw "NEEDS_INPUT: $field was manually changed since the last automatic preparation. First clarify this change explicitly as a requirement."
            }
        }
        foreach($name in $previousAuto.generatedCheckNames){
            $previousChecks=@(if($existing.Contains('checks')){$existing.checks | Where-Object {$_.name -ceq $name}})
            if($previousChecks.Count -ne 1 -or -not $previousAuto.checkHashes.Contains($name) -or
                (Get-ShadowPreparationHash $previousChecks[0]) -cne $previousAuto.checkHashes[$name]){throw "NEEDS_INPUT: Automatically generated check '$name' was manually changed/removed. Clarify provenance first."}
        }
        if($previousAuto.Contains('importedTaskFields')){$imported=$previousAuto.importedTaskFields}
    }else{
        foreach($field in $taskFields){if($existing.Contains($field) -and $existing[$field]){$imported[$field]=$existing[$field]}}
        if($imported.Count){$notes.Add('Existing task-specific fields will be derived again for the new task; originals are retained under automation.importedTaskFields and in the file backup. Reviewer must confirm the intended task boundary.')}
    }
    # Explicit durable limits are never inferred or broadened by a model.
    if($existing.Contains('limits')){
        if($existing.limits -isnot [Collections.IDictionary]){throw 'NEEDS_INPUT: limits must be an object.'}
        foreach($pair in @(@('allowedWritePaths','writePaths'),@('allowedTestWritePaths','testWritePaths'))){
            if($existing.limits.Contains($pair[0])){
                if($existing.limits[$pair[0]] -isnot [array]){throw 'NEEDS_INPUT: Boundaries must be arrays of exact file paths.'}
                foreach($path in $Proposal[$pair[1]]){if($path -notin $existing.limits[$pair[0]]){throw "NEEDS_INPUT: $path is outside limits.$($pair[0])."}}
            }
        }
    }
    if($Proposal.checkIds -isnot [array]){throw 'NEEDS_INPUT: checkIds must be an array.'}
    $selected=[Collections.Generic.List[object]]::new();$selectedIds=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $generatedNames=if($previousAuto -and $previousAuto.Contains('generatedCheckNames')){@($previousAuto.generatedCheckNames)}else{@()}
    $wanted=@($Proposal.checkIds)
    # Existing complete manual checks remain mandatory. Generated checks from a
    # different task do not silently become permanent scope or test requirements.
    foreach($candidate in $Context.Candidates){if($candidate.origin -ceq 'existing' -and $candidate.usable -and $candidate.definition.name -cnotin $generatedNames){$wanted+=@($candidate.id)}}
    foreach($id in $wanted){
        if($id -isnot [string]){throw 'NEEDS_INPUT: Check ID must be a string.'}
        if(-not $selectedIds.Add($id)){continue}
        $matches=@($Context.Candidates | Where-Object {$_.id -ceq $id})
        if($matches.Count -ne 1){throw "NEEDS_INPUT: Unknown check candidate $id."}
        $candidate=$matches[0]
        if($candidate.origin -ceq 'existing' -and $candidate.definition.name -cin $generatedNames){throw "NEEDS_INPUT: Previously generated check $id must be rebound through its currently detected candidate."}
        if($candidate.origin -ceq 'existing' -and -not $candidate.usable){throw "NEEDS_INPUT: Legacy check $id has no supported structured result format yet. Select a detected replacement."}
        $definition=ConvertFrom-ShadowJsonObject ($candidate.definition|ConvertTo-Json -Depth 30)
        if($candidate.origin -ceq 'detected' -and $candidate.framework -cne 'tsc'){
            if($Context.Inventory.testFilesTruncated){throw 'NEEDS_INPUT: More than 200 test files detected; use an existing targeted project check.'}
            $pool=@($Context.AllTestFiles)+@($Proposal.testWritePaths)
            $extension=if($candidate.framework -ceq 'pytest'){'\.py$'}elseif($candidate.framework -ceq 'node'){'\.(?:cjs|mjs|js)$'}else{'\.(?:cjs|mjs|js|jsx|ts|tsx)$'}
            $paths=@($pool | Sort-Object -Unique | Where-Object {$_ -match $extension})
            if($definition.kind -ceq 'integration'){
                $integrationPattern=if($candidate.framework -ceq 'playwright'){'(?i)(?:^|/)(?:integration|e2e)(?:/|\.)|\.(?:integration|e2e|spec)\.'}else{'(?i)(?:^|/)(?:integration|e2e)(?:/|\.)|\.(?:integration|e2e)\.'}
                $paths=@($paths | Where-Object {$_ -match $integrationPattern})
            }
            elseif($candidate.framework -ne 'playwright'){$paths=@($paths | Where-Object {$_ -notmatch '(?i)(?:^|/)(?:integration|e2e)(?:/|\.)|\.(?:integration|e2e)\.'})}
            if(-not $paths.Count){throw "NEEDS_INPUT: No suitable test files for $id. Specify exact new test files in the proposal."}
            if($paths.Count -gt 200){throw "NEEDS_INPUT: More than 200 test files for $id; configure project checks explicitly."}
            foreach($path in $paths){if(-not(Test-ShadowPreparationFile $Context.ProjectPath $path)){throw 'NEEDS_INPUT: Test path is linked or protected.'}}
            if($candidate.framework -ceq 'pytest'){$definition.arguments+=@($paths)}else{foreach($path in $paths){$definition.arguments+=@('--file',$path)}}
        }
        $selected.Add([ordered]@{id=$id;origin=$candidate.origin;definition=$definition})
    }
    $manualIncomplete=@($Context.Candidates | Where-Object {$_.origin -ceq 'existing' -and -not $_.usable})
    foreach($old in $manualIncomplete){
        if($readonly){$notes.Add("Legacy incomplete check '$($old.definition.name)' remains saved; the read-only task will not execute it.");continue}
        if(-not @($selected | Where-Object {$_.origin -ceq 'detected' -and $_.definition.kind -cne 'static'}).Count){throw "NEEDS_INPUT: No structured replacement for existing incomplete check $($old.definition.name)."}
        $notes.Add("Legacy check '$($old.definition.name)' remains saved unchanged. The independent reviewer must compare the selected structured replacement with the original command and its purpose.")
    }
    $runChecks=@($selected | ForEach-Object {$_.definition})
    if(@($runChecks | ForEach-Object {$_.name} | Sort-Object -Unique).Count -ne $runChecks.Count){throw 'NEEDS_INPUT: Selected checks have conflicting names.'}
    if($runChecks.Count -gt 12){throw 'NEEDS_INPUT: More than twelve checks in the task.'}
    $policy.schemaVersion=2
    foreach($field in @('writePaths','testWritePaths','acceptanceCriteria','changeTypes')){$policy[$field]=$Proposal[$field]}
    $policy.regressionCheck=''
    if($Proposal.workflow -ceq 'Bugfix'){
        if(-not $Proposal.Contains('regressionCheckId')){throw 'NEEDS_INPUT: Bugfix requires regressionCheckId.'}
        $regression=@($selected | Where-Object {$_.id -ceq $Proposal.regressionCheckId -and $_.definition.kind -cne 'static'})
        if($regression.Count -ne 1){throw 'NEEDS_INPUT: regressionCheckId does not identify a selected test check.'}
        $policy.regressionCheck=$regression[0].definition.name
    }
    $savedChecks=[Collections.Generic.List[object]]::new()
    if($existing.Contains('checks')){foreach($check in $existing.checks){$savedChecks.Add($check)}}
    $newGenerated=[Collections.Generic.List[string]]::new()
    foreach($name in $generatedNames){$newGenerated.Add($name)}
    foreach($item in $selected){
        $matching=@($savedChecks | Where-Object {$_.name -ceq $item.definition.name})
        if($matching.Count){
            if((Get-ShadowPreparationHash $matching[0]) -cne (Get-ShadowPreparationHash $item.definition)){
                # Never replace a manual check. Rebind generated task-dependent
                # paths only when its saved full definition still has provenance.
                $name=$item.definition.name
                if($name -cnotin $generatedNames -or -not $previousAuto.Contains('checkHashes') -or -not $previousAuto.checkHashes.Contains($name) -or
                    (Get-ShadowPreparationHash $matching[0]) -cne $previousAuto.checkHashes[$name]){throw "NEEDS_INPUT: Check '$name' was manually defined/changed and must not be replaced."}
                $index=$savedChecks.IndexOf($matching[0]);$savedChecks[$index]=$item.definition
            }
        }else{$savedChecks.Add($item.definition);if($item.origin -ceq 'detected'){$newGenerated.Add($item.definition.name)}}
    }
    $policy.checks=$savedChecks.ToArray()
    $fieldHashes=[ordered]@{};foreach($field in $taskFields){$fieldHashes[$field]=Get-ShadowPreparationHash $policy[$field]}
    $checkHashes=[ordered]@{};foreach($check in $savedChecks){if($check.name -cin $newGenerated){$checkHashes[$check.name]=Get-ShadowPreparationHash $check}}
    $taskHash=Get-ShadowPreparationHash $TaskText
    $policy.automation=[ordered]@{owner='LoKi task preparation v1';taskHash=$taskHash;workflow=$Proposal.workflow;fieldHashes=$fieldHashes;generatedCheckNames=@($newGenerated | Sort-Object -Unique);checkHashes=$checkHashes;selectedCheckIds=@($selected | ForEach-Object {$_.id});importedTaskFields=$imported;notes=$notes.ToArray();inputHashes=$Context.InputHashes}
    $runPolicy=ConvertFrom-ShadowJsonObject ($policy|ConvertTo-Json -Depth 80)
    $runPolicy.checks=$runChecks
    if($readonly){
        # Reuse only the schema/criteria validator. This sentinel is neither saved
        # nor run: read-only reviews do not need an executable test suite.
        Assert-ShadowAcceptanceContract -Policy $runPolicy -Checks @(@{name='schema-validation-only';kind='test';reportFormat='json'})
    }else{Assert-ShadowAcceptanceContract -Policy $runPolicy -Checks $runChecks}
    return [pscustomobject]@{Policy=$policy;RunPolicy=$runPolicy;TaskHash=$taskHash;Workflow=$Proposal.workflow;Notes=$notes.ToArray();SelectedCandidates=$selected.ToArray();ExistingHash=$Context.ExistingHash}
}

function Save-ShadowPreparedPolicy {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)]$Prepared)
    # Must be called only after the external independent preparation review.
    if((Get-ShadowSourceFingerprint $Context.ProjectPath).Fingerprint -cne $Context.SourceFingerprint){throw 'NEEDS_INPUT: Project changed since preparation.'}
    foreach($name in $Context.InputHashes.Keys){if((Get-FileHash -LiteralPath (Join-Path $Context.ProjectPath $name)).Hash -cne $Context.InputHashes[$name]){throw "NEEDS_INPUT: Project input changed since preparation: $name"}}
    if($Context.ExistingHash){
        if(-not(Test-Path -LiteralPath $Context.ChecksFile -PathType Leaf) -or (Get-FileHash -LiteralPath $Context.ChecksFile).Hash -cne $Context.ExistingHash){throw 'NEEDS_INPUT: checks.json changed in the meantime.'}
        $backup=Join-Path $Context.InstallRoot ('backups/task-preparation/'+[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ')+'-'+[guid]::NewGuid().ToString('N')+'.checks.json')
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($backup))
        [IO.File]::Copy($Context.ChecksFile,$backup,$false)
    }elseif(Test-Path -LiteralPath $Context.ChecksFile){throw 'NEEDS_INPUT: checks.json was created in the meantime.'}
    Write-ShadowUtf8File -Path $Context.ChecksFile -Text ($Prepared.Policy|ConvertTo-Json -Depth 80)
    return $Context.ChecksFile
}
