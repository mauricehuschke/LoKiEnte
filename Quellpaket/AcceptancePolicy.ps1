#requires -Version 7.4
# Deterministic acceptance contract; model verdicts cannot override these checks.
Set-StrictMode -Version Latest

function ConvertFrom-ShadowJsonObject {
    param([string]$Text)
    $candidate=$Text.Trim()
    if($candidate -match '(?s)^```(?:json)?\s*(.*?)\s*```$'){$candidate=$Matches[1]}
    $value=ConvertFrom-Json -InputObject $candidate -AsHashtable -NoEnumerate -ErrorAction Stop
    if($value -isnot [Collections.IDictionary]){throw 'The agent response must be a JSON object.'}
    return $value
}

function Get-ShadowChangeTypes {
    param($Value)
    if($Value -isnot [array] -or -not $Value.Count){throw 'changeTypes must contain at least one of security, ui, api or other.'}
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($type in $Value){
        if($type -isnot [string] -or $type -cnotin @('security','ui','api','other') -or -not $seen.Add($type)){
            throw 'Invalid or duplicate entry in changeTypes.'
        }
        $type
    }
}

function Get-ShadowPathChangeTypes {
    param([string[]]$Paths)
    # Extra conservative hints, never a replacement for task/plan/reviewer classification.
    foreach($path in $Paths){
        if($path -match '(?i)(auth|login|permission|credential|secret|security|session|token|upload|filesystem|storage)'){ 'security' }
        if($path -match '(?i)(\.(tsx|jsx|vue|svelte|html|css|scss)$|(?:^|/)(ui|components|pages|views)/)'){ 'ui' }
        if($path -match '(?i)(?:^|/)(api|routes|controllers|endpoints)(?:/|\.)'){ 'api' }
    }
}

function Assert-ShadowAcceptanceContract {
    param([Collections.IDictionary]$Policy,[object[]]$Checks)
    if(-not $Policy.Contains('schemaVersion') -or ($Policy.schemaVersion -isnot [int] -and $Policy.schemaVersion -isnot [long]) -or $Policy.schemaVersion -ne 2){
        throw 'checks.json requires schemaVersion 2. Run provisioning and read WORKFLOW.md.'
    }
    if(-not $Policy.Contains('acceptanceCriteria') -or $Policy.acceptanceCriteria -isnot [array] -or -not $Policy.acceptanceCriteria.Count){
        throw 'Complete acceptanceCriteria in checks.json: a fixed id and description per requirement.'
    }
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($criterion in $Policy.acceptanceCriteria){
        if($criterion -isnot [Collections.IDictionary] -or -not $criterion.Contains('id') -or
           $criterion.id -isnot [string] -or $criterion.id -cnotmatch '^AC-[1-9][0-9]*$' -or -not $seen.Add($criterion.id) -or
           -not $criterion.Contains('description') -or $criterion.description -isnot [string] -or [string]::IsNullOrWhiteSpace($criterion.description)){
            throw 'Acceptance criteria require unique IDs such as AC-1 and concrete descriptions.'
        }
    }
    if(-not $Policy.Contains('changeTypes')){throw 'Fill in changeTypes in checks.json.'}
    $null=Get-ShadowChangeTypes -Value $Policy.changeTypes
    foreach($check in $Checks){
        if(-not $check.Contains('kind') -or $check.kind -isnot [string] -or $check.kind -cnotin @('test','integration','static')){
            throw "Check $($check.name): add kind (test, integration or static) and reportFormat where applicable."
        }
        if($check.kind -cne 'static' -and (-not $check.Contains('reportFormat') -or $check.reportFormat -isnot [string] -or $check.reportFormat -cnotin @('junit','json'))){
            throw "Check $($check.name): specify reportFormat junit or json; write the report to {report} or LOKI_TEST_REPORT."
        }
    }
    if(-not @($Checks | Where-Object {$_.kind -cne 'static'}).Count){throw 'At least one test check with a structured report is required.'}
}

function ConvertFrom-ShadowAcceptancePlan {
    param([string]$Text,[object[]]$Criteria,[object[]]$Checks,[string]$Workflow,[string]$RegressionCheck)
    $plan=ConvertFrom-ShadowJsonObject $Text
    if(-not $plan.Contains('criteria') -or $plan.criteria -isnot [array] -or $plan.criteria.Count -ne $Criteria.Count){
        throw 'The test plan must cover every specified acceptance criterion exactly once.'
    }
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $references=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($item in $plan.criteria){
        if($item -isnot [Collections.IDictionary] -or -not $item.Contains('id') -or $item.id -cnotin @($Criteria.id) -or
           -not $seen.Add($item.id) -or -not $item.Contains('tests') -or $item.tests -isnot [array] -or -not $item.tests.Count){
            throw 'Missing, unknown or duplicate acceptance criterion, or missing test case mapping.'
        }
        $local=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach($reference in $item.tests){
            Assert-ShadowTestReference -Reference $reference -Checks $Checks
            $key=$reference.check+"`0"+$reference.testId
            if(-not $local.Add($key)){throw 'Duplicate test case in acceptance criterion.'}
            [void]$references.Add($key)
        }
    }
    if(-not $plan.Contains('expectedFailures') -or $plan.expectedFailures -isnot [array]){throw 'Test plan requires expectedFailures as an array.'}
    $seenFailures=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($reference in $plan.expectedFailures){
        Assert-ShadowTestReference -Reference $reference -Checks $Checks
        $key=$reference.check+"`0"+$reference.testId
        if(-not $references.Contains($key) -or -not $seenFailures.Add($key)){throw 'Expected failure must be a uniquely mapped test case.'}
        if($Workflow -ceq 'Bugfix' -and $reference.check -cne $RegressionCheck){throw 'Bugfix baseline failures must belong to regressionCheck.'}
    }
    if($Workflow -ceq 'Bugfix' -and -not $plan.expectedFailures.Count){throw 'Bugfix requires at least one specifically expected failing regression test.'}
    if($Workflow -cnotin @('Bugfix','Feature') -and $plan.expectedFailures.Count){throw 'This workflow does not allow failing baseline tests.'}
    return $plan
}

function Assert-ShadowTestReference {
    param($Reference,[object[]]$Checks)
    if($Reference -isnot [Collections.IDictionary] -or -not $Reference.Contains('check') -or $Reference.check -isnot [string] -or
       -not $Reference.Contains('testId') -or $Reference.testId -isnot [string] -or [string]::IsNullOrWhiteSpace($Reference.testId) -or
       $Reference.testId -match '[\x00-\x1f]' -or $Reference.testId.Length -gt 1000){throw 'Invalid test case reference.'}
    $check=@($Checks | Where-Object {$_.name -ceq $Reference.check})
    if($check.Count -ne 1 -or $check[0].kind -ceq 'static'){throw 'Acceptance criteria require concrete test cases from test/integration checks.'}
}

function Read-ShadowTestReport {
    param([string]$Path,[ValidateSet('junit','json')][string]$Format)
    $file=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if($file.PSIsContainer -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $file.Length -gt 16777216){throw 'Invalid test report file (file type or size exceeds 16 MiB).'}
    $cases=[Collections.Generic.List[object]]::new()
    if($Format -ceq 'json'){
        $document=ConvertFrom-ShadowJsonObject ([IO.File]::ReadAllText($Path))
        if(-not $document.Contains('schemaVersion') -or ($document.schemaVersion -isnot [int] -and $document.schemaVersion -isnot [long]) -or $document.schemaVersion -ne 1 -or -not $document.Contains('tests') -or $document.tests -isnot [array]){
            throw 'JSON test report requires schemaVersion 1 and a tests array.'
        }
        foreach($case in $document.tests){
            if($case -isnot [Collections.IDictionary] -or -not $case.Contains('id') -or -not $case.Contains('status')){throw 'Incomplete test case.'}
            $cases.Add([pscustomobject]@{Id=$case.id;Status=$case.status})
        }
    }else{
        $settings=[Xml.XmlReaderSettings]::new();$settings.DtdProcessing=[Xml.DtdProcessing]::Prohibit
        $settings.XmlResolver=$null;$settings.MaxCharactersInDocument=16777216
        $reader=[Xml.XmlReader]::Create($Path,$settings)
        try{$document=[Xml.XmlDocument]::new();$document.XmlResolver=$null;$document.Load($reader)}finally{$reader.Dispose()}
        if($document.DocumentElement.LocalName -cnotin @('testsuites','testsuite')){throw 'Not a JUnit test report.'}
        foreach($case in $document.SelectNodes('//testcase')){
            $name=$case.GetAttribute('name');$class=$case.GetAttribute('classname')
            if($case.GetAttribute('status') -cnotin @('','run','passed','success','notrun','disabled','skipped')){throw 'Unknown JUnit test status.'}
            $id=if($class){$class+'::'+$name}else{$name}
            $status=if($case.SelectSingleNode('failure|error')){'failed'}elseif($case.SelectSingleNode('skipped') -or $case.GetAttribute('status') -in @('notrun','disabled','skipped')){'skipped'}else{'passed'}
            if([string]::IsNullOrWhiteSpace($name)){throw 'JUnit test case without a name.'}
            $cases.Add([pscustomobject]@{Id=$id;Status=$status})
        }
        if($document.SelectNodes('//error[not(parent::testcase)]|//failure[not(parent::testcase)]').Count){throw 'JUnit reports an error outside a test case.'}
        # Do not accept a success-looking case list when the suite reports failures.
        if(-not @($cases | Where-Object Status -CEQ 'failed').Count){
            foreach($suite in $document.SelectNodes('//testsuite|/testsuites')){
                foreach($name in @('errors','failures')){if($suite.HasAttribute($name) -and $suite.GetAttribute($name) -notmatch '^0+$'){throw 'JUnit totals disagree with the test cases.'}}
            }
        }
    }
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($case in $cases){
        if($case.Id -isnot [string] -or [string]::IsNullOrWhiteSpace($case.Id) -or $case.Id -match '[\x00-\x1f]' -or $case.Id.Length -gt 1000 -or
           -not $seen.Add($case.Id) -or $case.Status -isnot [string] -or $case.Status -cnotin @('passed','failed','skipped')){throw 'Invalid or duplicate test case in report.'}
    }
    $passed=@($cases | Where-Object Status -CEQ 'passed').Count
    $failed=@($cases | Where-Object Status -CEQ 'failed').Count
    if($passed+$failed -eq 0){throw 'Test report contains no executed tests (empty or all skipped).'}
    [pscustomobject]@{Cases=$cases.ToArray();Total=$cases.Count;Passed=$passed;Failed=$failed;Skipped=($cases.Count-$passed-$failed);Sha256=(Get-FileHash -LiteralPath $Path).Hash}
}

function Get-ShadowAcceptanceIssues {
    param([object[]]$Checks,$Plan,[switch]$Baseline,[string[]]$ChangeTypes=@())
    $expected=if($Baseline){@($Plan.expectedFailures)}else{@()}
    foreach($check in $Checks){
        $failures=@($expected | Where-Object {$_.check -ceq $check.Name})
        $expectedExit=if($failures.Count){1}else{0}
        if($check.TimedOut -or $check.ExitCode -ne $expectedExit){"Check $($check.Name): Exit code $($check.ExitCode), expected $expectedExit; Timeout=$($check.TimedOut)."}
        if($check.Kind -ceq 'static'){continue}
        if($check.ReportError -or $null -eq $check.Report){"Check $($check.Name): no valid test report. $($check.ReportError)";continue}
        foreach($case in $check.Report.Cases){
            $shouldFail=$case.Id -cin @($failures | ForEach-Object {$_.testId})
            if(($shouldFail -and $case.Status -cne 'failed') -or (-not $shouldFail -and $case.Status -ceq 'failed')){
                "Check $($check.Name), Test $($case.Id): unexpected status $($case.Status)."
            }
        }
    }
    foreach($criterion in $Plan.criteria){
        foreach($reference in $criterion.tests){
            $check=@($Checks | Where-Object Name -CEQ $reference.check)
            if($check.Count -ne 1 -or $null -eq $check[0].Report){"$($criterion.id): report missing for $($reference.check).";continue}
            $case=@($check[0].Report.Cases | Where-Object Id -CEQ $reference.testId)
            $status=if(@($expected | Where-Object {$_.check -ceq $reference.check -and $_.testId -ceq $reference.testId}).Count){'failed'}else{'passed'}
            if($case.Count -ne 1 -or $case[0].Status -cne $status){"$($criterion.id): test $($reference.testId) is missing, skipped or not $status."}
        }
    }
    if(@($ChangeTypes | Where-Object {$_ -in @('ui','api')}).Count){
        $mapped=@($Plan.criteria | ForEach-Object {$_.tests} | ForEach-Object {$_.check})
        if(-not @($Checks | Where-Object {$_.Kind -ceq 'integration' -and $_.Name -cin $mapped}).Count){
            'UI/API changes require an integration check mapped to acceptance criteria.'
        }
    }
}

function Get-ShadowTestFileHashes {
    param([string]$ProjectPath,[string[]]$Paths)
    $hashes=[ordered]@{}
    foreach($path in $Paths){
        $null=Get-ShadowWritePaths -Policy @{writePaths=@($path)} -ProjectPath $ProjectPath
        $full=Join-Path $ProjectPath $path
        $hashes[$path]=if(Test-Path -LiteralPath $full -PathType Leaf){(Get-FileHash -LiteralPath $full).Hash}else{'MISSING'}
    }
    return $hashes
}

function Assert-ShadowTestFilesFrozen {
    param([string]$ProjectPath,[Collections.IDictionary]$Hashes)
    $actual=Get-ShadowTestFileHashes -ProjectPath $ProjectPath -Paths @($Hashes.Keys)
    foreach($path in $Hashes.Keys){if($actual[$path] -cne $Hashes[$path]){throw "Reviewed test file changed: $path. A new run with independent test authoring and review is required."}}
}
