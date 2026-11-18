#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$SourceRoot,
    [Parameter(Mandatory)][string]$BootstrapPath,
    [string]$VerifiedRipgrepPath
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if(-not $SourceRoot){$SourceRoot=Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)}
$root=Join-Path ([IO.Path]::GetTempPath()) ('shadow-audit-tests-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
$install=Join-Path $root 'must-not-be-created'
$mockBin=Join-Path $root 'bin'
[void][IO.Directory]::CreateDirectory((Join-Path $mockBin 'node_modules\npm\bin'))
[IO.File]::WriteAllText((Join-Path $mockBin 'node_modules\npm\bin\npm-cli.js'),'fixture; never executed')
$results=New-Object 'Collections.Generic.List[string]'
function Assert-AuditTest([bool]$Condition,[string]$Name){
    if(-not $Condition){
        if(Get-Variable report -ErrorAction SilentlyContinue){$report.checks|Where-Object {$_.status -eq 'FAIL'}|Format-List name,message|Out-Host}
        throw "FAIL: $Name"
    }
    $results.Add($Name);Write-Host "PASS: $Name"
}
$tokens=$null;$errors=$null
$bootstrap=[Management.Automation.Language.Parser]::ParseFile($BootstrapPath,[ref]$tokens,[ref]$errors)
Assert-AuditTest ($errors.Count -eq 0) 'Bootstrap parses on this PowerShell version'
foreach($definition in $bootstrap.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst]},$false)){
    . ([scriptblock]::Create($definition.Extent.Text))
}
$auditAst=[Management.Automation.Language.Parser]::ParseFile((Join-Path $SourceRoot 'Audit.ps1'),[ref]$tokens,[ref]$errors)
Assert-AuditTest ($errors.Count -eq 0) 'Audit module parses on this PowerShell version'
foreach($definition in $auditAst.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst]},$false)){
    . ([scriptblock]::Create($definition.Extent.Text))
}
$auditBody=$auditAst.ParamBlock.Extent.Text+"`n"+(@($auditAst.EndBlock.Statements|Where-Object {
    $_ -isnot [Management.Automation.Language.FunctionDefinitionAst]
}|ForEach-Object {$_.Extent.Text}) -join "`n")
$audit=[scriptblock]::Create($auditBody)
$package=@{
    'Runtime.ps1'=[IO.File]::ReadAllText((Join-Path $SourceRoot 'Runtime.ps1'))
    'ModelPool.ps1'=[IO.File]::ReadAllText((Join-Path $SourceRoot 'ModelPool.ps1'))
    'Common.ps1'=[IO.File]::ReadAllText((Join-Path $SourceRoot 'Common.ps1'))
    'ModelSelection.ps1'=[IO.File]::ReadAllText((Join-Path $SourceRoot 'ModelSelection.ps1'))
    'Ripgrep.ps1'=[IO.File]::ReadAllText((Join-Path $SourceRoot 'Ripgrep.ps1'))
}
$script:offline=$false;$script:ram=28GB;$script:timeout=$false;$script:badJson=$false
$script:tokenSent=@();$script:nativeCalls=@();$script:public=$false
$script:loadedJson='[]';$script:probeExit=1
$script:modelJson='[]';$script:variantsJson='[]'
$script:mockCode=$null
$script:probeMessage='Path not provided: The parameter [model-key] is required when using the --exact flag.'
function Find-BootstrapExecutable {
    param($Name,$Candidates)
    if($Name -in @('Code.exe','code')){return $script:mockCode}
    if($Name -eq 'LM Studio.exe'){return $null}
    return Join-Path $mockBin $Name
}
function Get-CimInstance {
    param($ClassName,$Filter)
    switch($ClassName){
        'Win32_OperatingSystem'{[pscustomobject]@{Caption='Synthetic Windows';BuildNumber='test';TotalVisibleMemorySize=($script:ram/1KB);FreePhysicalMemory=([math]::Min($script:ram,24GB)/1KB)}}
        'Win32_Processor'{[pscustomobject]@{Name='Synthetic CPU'}}
        'Win32_LogicalDisk'{[pscustomobject]@{DeviceID='C:';Size=200GB;FreeSpace=100GB}}
        default{throw "Unexpected CIM query $ClassName"}
    }
}
function Get-NetTCPConnection {
    param($State,$ErrorAction)
    [pscustomobject]@{LocalPort=1234;LocalAddress=$(if($script:public){'0.0.0.0'}else{'127.0.0.1'})}
}
function Invoke-AuditNative {
    param($FilePath,$Arguments,$TimeoutSeconds,[switch]$AllowFailure)
    $name=[IO.Path]::GetFileName($FilePath)
    $script:nativeCalls+=($name+' '+($Arguments -join ' '))
    switch($name){
        'pwsh.exe'{return '7.4.7'}
        'node.exe'{return $(if($Arguments -contains '--version' -and $Arguments.Count -eq 1){'v22.0.0'}else{'10.0.0'})}
        'nvidia-smi.exe'{return 'Synthetic GPU, 20480, 19968, test-driver'}
        'rg.exe'{return 'ripgrep 15.1.0'}
        'lms.exe'{
            switch($Arguments[0]){
                '--version'{return '1.0.0'}
                'load'{
                    if(($Arguments -join ' ') -ceq 'load --help'){return '--parallel --context-length --estimate-only --identifier --gpu --yes'}
                    if(($Arguments -join ' ') -cne 'load --exact --local --estimate-only --yes' -or -not $AllowFailure){throw 'Audit tried to load a model'}
                    return [pscustomobject]@{ExitCode=$script:probeExit;Stdout='';Stderr=$script:probeMessage}
                }
                'server'{if(($Arguments -join ' ') -cne 'server status --json'){throw 'Audit tried to start/stop a server'};if($script:badJson){return '{"secret":"SYNTHETIC_AUDIT_TOKEN_NOT_A_SECRET",broken'};return '{"running":true,"port":1234}'}
                'ls'{if($script:timeout){throw 'Synthetic CLI timeout'};if($Arguments -contains '--variants'){return $script:variantsJson};return $script:modelJson}
                'ps'{return $script:loadedJson}
                default{throw 'Unexpected lms invocation'}
            }
        }
        default{return '1.0.0'}
    }
}
function Invoke-AuditJson {
    param([Uri]$Uri,[string]$BearerToken)
    if($BearerToken){$script:tokenSent+=@{host=$Uri.Host;token=$BearerToken}}
    if($Uri.IsLoopback){return [pscustomobject]@{models=@()}}
    if($script:offline){throw 'Synthetic offline source'}
    if($Uri.Host -eq 'registry.npmjs.org'){return [pscustomobject]@{name='@kilocode/cli';version='7.8.27';bin=@{kilo='bin/kilo'}}}
    if($Uri.Host -eq 'huggingface.co'){
        return [pscustomobject]@{siblings=@([pscustomobject]@{rfilename='Qwen3.8-27B-Q4_K_M.gguf'},[pscustomobject]@{rfilename='Qwen3-14B-Q4_K_M.gguf'},[pscustomobject]@{rfilename='gpt-oss-20b-MXFP4.gguf'},[pscustomobject]@{rfilename='Qwen3.5-9B-Q4_K_M.gguf'},[pscustomobject]@{rfilename='Qwen3.5-4B-Q4_K_M.gguf'})}
    }
    throw 'Unexpected online source'
}
$parameters=@{
    InstallRoot=$install;BundleVersion='test';PayloadHash='test';PackageFiles=$package
    ModelMode='Dual';IncludeFastModel=$false;PreferredModel='Auto';ModelKey=''
    ContextLength=32768;Port=1234;RouterPort=1235;ApiTokenEnvironmentVariable='SHADOW_AUDIT_SYNTHETIC_TOKEN'
    ProjectPath=@();SkipModelDownload=$false
}
$previous=[Environment]::GetEnvironmentVariable($parameters.ApiTokenEnvironmentVariable,'Process')
$previousProfile=$env:USERPROFILE
$previousLocalAppData=$env:LOCALAPPDATA
$env:USERPROFILE=Join-Path $root 'user'
$env:LOCALAPPDATA=Join-Path $root 'local-app-data'
[Environment]::SetEnvironmentVariable($parameters.ApiTokenEnvironmentVariable,'SYNTHETIC_AUDIT_TOKEN_NOT_A_SECRET','Process')
try{
    $report=& $audit @parameters
    Assert-AuditTest ($report.mode -ceq 'AUDIT_ONLY' -and $report.schema -eq 2 -and $report.exitCode -eq 0) 'Healthy preflight returns structured audit JSON with nonblocking missing components'
    Assert-AuditTest (-not $report.provisioningPerformed -and -not $report.inferenceVerified) 'Preflight never claims provisioned or inference-verified status'
    Assert-AuditTest (-not(Test-Path -LiteralPath $install)) 'Audit creates no installation directory'
    Assert-AuditTest (@($report.checks|Where-Object {$_.name -eq 'api.backend' -and $_.status -eq 'PASS'}).Count -eq 1) 'Empty valid REST model catalog is accepted'
    Assert-AuditTest (($report|ConvertTo-Json -Depth 15) -notmatch 'SYNTHETIC_AUDIT_TOKEN_NOT_A_SECRET') 'Audit JSON does not contain the token value'
    Assert-AuditTest (@($script:tokenSent|Where-Object {$_.host -ne '127.0.0.1'}).Count -eq 0) 'No public source receives the API token'
    Assert-AuditTest (@($script:nativeCalls|Where-Object {$_ -match ' install | unload |server start|runtime get'}).Count -eq 0) 'Audit never invokes mutating CLI commands'
    $script:ram=4GB
    $lowMemory=& $audit @parameters
    $fitCheck=@($lowMemory.checks|Where-Object {$_.name -ceq 'model.hardware'})[0]
    Assert-AuditTest ($fitCheck.status -ceq 'WARN' -and @($fitCheck.data.rolesWithoutFit).Count -eq 3 -and $lowMemory.exitCode -eq 0) 'Insufficient memory is an explicit audit warning, not a blocking failure'
    $script:ram=28GB
    Assert-AuditTest (@($report.checks|Where-Object {$_.name -eq 'tool.ripgrep' -and $_.status -eq 'MISSING'}).Count -eq 1) 'Audit reports missing managed ripgrep without installing it'
    $rgRoot=Join-Path $root 'rg-audit'
    $rgPath=Join-Path $rgRoot 'runtime-profile\cache\kilo\bin\rg.exe'
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $rgPath))
    [IO.File]::WriteAllText((Join-Path $rgRoot 'shadow-local-ai-install.json'),'{"schema":1,"product":"ShadowLocalAI"}')
    [IO.File]::WriteAllText($rgPath,'not trusted')
    $parameters.InstallRoot=$rgRoot
    $report=& $audit @parameters
    Assert-AuditTest (@($report.checks|Where-Object {$_.name -eq 'tool.ripgrep' -and $_.status -eq 'FAIL'}).Count -eq 1 -and
        [IO.File]::ReadAllText($rgPath) -ceq 'not trusted') 'Audit rejects and preserves an unknown cached executable'
    if($VerifiedRipgrepPath){
        [IO.File]::Delete($rgPath)
        [IO.File]::Copy($VerifiedRipgrepPath,$rgPath,$false)
        $report=& $audit @parameters
        Assert-AuditTest (@($report.checks|Where-Object {$_.name -eq 'tool.ripgrep' -and $_.status -eq 'PASS'}).Count -eq 1) 'Audit confirms a real checksum-verified ripgrep executable'
    }
    $parameters.InstallRoot=$install
    [void][IO.Directory]::CreateDirectory($install)
    [IO.File]::WriteAllText((Join-Path $install 'shadow-local-ai-install.json'),'{"schema":1,"product":"ShadowLocalAI"}')
    [IO.File]::WriteAllText((Join-Path $install 'model-selection.json'),'{"schema":1,"roles":[{"Alias":"coder","ExpectedPath":"lmstudio-community/Qwen3.5-9B-GGUF/Qwen3.5-9B-Q4_K_M.gguf"},{"Alias":"review","ExpectedPath":"lmstudio-community/gpt-oss-20b-GGUF/gpt-oss-20b-MXFP4.gguf"}]}')
    $report=& $audit @parameters
    Assert-AuditTest (@($report.checks|Where-Object {$_.name -eq 'model.selection' -and $_.status -eq 'WARN'}).Count -eq 1) 'Legacy selection is not reported as complete before coder-fast is chosen'
    [IO.File]::WriteAllText((Join-Path $install 'model-selection.json'),'{"schema":1,"roles":[{"Alias":"coder-high","ExpectedPath":"lmstudio-community/Qwen3-14B-GGUF/Qwen3-14B-Q4_K_M.gguf"},{"Alias":"coder-fast","ExpectedPath":"lmstudio-community/Qwen3.5-9B-GGUF/Qwen3.5-9B-Q4_K_M.gguf"},{"Alias":"review","ExpectedPath":"lmstudio-community/gpt-oss-20b-GGUF/gpt-oss-20b-MXFP4.gguf"}]}')
    $report=& $audit @parameters
    Assert-AuditTest (@($report.checks|Where-Object {$_.name -eq 'model.selection' -and $_.status -eq 'PASS'}).Count -eq 1 -and
        @($report.checks|Where-Object {$_.name -eq 'model.file' -and $_.data.profile -eq 'Qwen3.5-9B Q4_K_M'}).Count -eq 1) 'Audit checks all confirmed current model roles'
    [IO.File]::Delete((Join-Path $install 'model-selection.json'))
    [IO.File]::Delete((Join-Path $install 'shadow-local-ai-install.json'))
    [IO.Directory]::Delete($install)
    Assert-AuditTest (@($report.checks|Where-Object {$_.name -eq 'vscode.cli' -and $_.status -eq 'SKIP'}).Count -eq 1) 'VS Code CLI path check skips missing VS Code'
    $codeRoot=Join-Path $root 'VS Code fixture'
    $codeDir=Join-Path $codeRoot 'bin'
    $cliDir=Join-Path $codeRoot '69047191fc\resources\app\out'
    [void][IO.Directory]::CreateDirectory($codeDir);[void][IO.Directory]::CreateDirectory($cliDir)
    $script:mockCode=Join-Path $codeRoot 'Code.exe'
    [IO.File]::WriteAllText($script:mockCode,'synthetic')
    [IO.File]::WriteAllText((Join-Path $cliDir 'cli.js'),'synthetic')
    [IO.File]::WriteAllText((Join-Path $codeDir 'code.cmd'),'"%~dp0..\Code.exe" "%~dp0..\69047191fc\resources\app\out\cli.js" %*')
    $report=& $audit @parameters
    Assert-AuditTest (@($report.checks|Where-Object {$_.name -eq 'vscode.cli' -and $_.status -eq 'PASS' -and $_.data.path -eq (Join-Path $cliDir 'cli.js')}).Count -eq 1) 'Audit checks the active versioned VS Code CLI without invoking it'
    Remove-Item -LiteralPath (Join-Path $cliDir 'cli.js')
    $report=& $audit @parameters
    Assert-AuditTest (@($report.checks|Where-Object {$_.name -eq 'vscode.cli' -and $_.status -eq 'FAIL'}).Count -eq 1) 'Audit blocks a missing active VS Code CLI'
    $script:mockCode=$null
    Assert-AuditTest (@($report.checks|Where-Object {$_.name -eq 'lms.capabilities' -and $_.status -eq 'PASS' -and $_.data.hiddenOptionsProbed}).Count -eq 1) 'Hidden exact/local flags pass the guarded no-model probe'
    $modelCheck=@($report.checks|Where-Object {$_.name -eq 'lms.models'})[0]
    Assert-AuditTest ($modelCheck.data.downloadedCount -eq 0 -and $modelCheck.data.loadedCount -eq 0 -and
        @($report.checks|Where-Object {$_.name -eq 'model.loaded'}).Count -eq 0) 'Empty CLI arrays mean zero models and no phantom-instance warning'
    $script:modelJson='[{"type":"llm","modelKey":"qwen/qwen3-14b","path":"qwen/qwen3-14b","deviceIdentifier":null,"selectedVariant":"qwen/qwen3-14b@q4_k_m"}]'
    $script:variantsJson='[{"model":{"modelKey":"qwen/qwen3-14b","path":"qwen/qwen3-14b","deviceIdentifier":null,"selectedVariant":"qwen/qwen3-14b@q4_k_m"},"variants":[{"modelKey":"qwen/qwen3-14b@q4_k_m","path":"qwen/qwen3-14b","deviceIdentifier":null,"indexedModelIdentifier":"qwen/qwen3-14b@lmstudio-community/Qwen3-14B-GGUF/Qwen3-14B-Q4_K_M.gguf"}]}]'
    $report=& $audit @parameters
    Assert-AuditTest (@($report.checks|Where-Object {$_.name -eq 'model.file' -and $_.status -eq 'PASS' -and $_.data.profile -eq 'Qwen3-14B Q4_K_M'}).Count -eq 1) 'Audit recognizes exact recommended file in current CLI variant metadata'
    $script:variantsJson='[]'
    $report=& $audit @parameters
    Assert-AuditTest (@($report.checks|Where-Object {$_.name -eq 'lms' -and $_.status -eq 'FAIL'}).Count -eq 1) 'Audit fails closed when variant details cannot verify local identity'
    $script:modelJson='[]';$script:variantsJson='[]'
    $script:probeExit=0
    $report=& $audit @parameters
    Assert-AuditTest (@($report.checks|Where-Object {$_.name -eq 'lms.capabilities' -and $_.status -eq 'FAIL'}).Count -eq 1) 'Unexpected probe success is not accepted as proof'
    $script:probeExit=1;$script:probeMessage='unknown option --local'
    $report=& $audit @parameters
    Assert-AuditTest (@($report.checks|Where-Object {$_.name -eq 'lms.capabilities' -and $_.status -eq 'FAIL'}).Count -eq 1) 'Actually unsupported hidden flags remain blocking'
    $script:probeMessage='Path not provided: The parameter [model-key] is required when using the --exact flag.'
    foreach($size in @(1,2)){
        $script:loadedJson=ConvertTo-Json -InputObject @(1..$size|ForEach-Object {
            @{identifier="foreign-$_";deviceIdentifier=$null;status='idle';queued=0;path="foreign-$_.gguf"}
        })
        $report=& $audit @parameters
        $modelCheck=@($report.checks|Where-Object {$_.name -eq 'lms.models'})[0]
        Assert-AuditTest ($modelCheck.data.loadedCount -eq $size -and @($report.checks|Where-Object {$_.name -eq 'model.loaded' -and $_.data.id}).Count -eq $size) "CLI list with $size real records is counted and inspected individually"
    }
    foreach($invalid in @('{}','null','[null]')){
        $script:loadedJson=$invalid
        $report=& $audit @parameters
        Assert-AuditTest (@($report.checks|Where-Object {$_.name -eq 'lms' -and $_.status -eq 'FAIL'}).Count -eq 1) "Malformed model-list shape is explicit, not treated as an empty list: $invalid"
    }
    $script:loadedJson='[]'
    $shared=Join-Path $root 'script-directory'
    [void][IO.Directory]::CreateDirectory($shared)
    [IO.File]::WriteAllText((Join-Path $shared 'unrelated.txt'),'keep')
    $parameters.InstallRoot=$shared
    $report=& $audit @parameters
    Assert-AuditTest (@($report.checks|Where-Object {$_.name -eq 'installRoot' -and $_.status -eq 'PASS'}).Count -eq 1 -and
        @(Get-ChildItem -LiteralPath $shared -Force).Count -eq 1) 'Audit accepts a shared script directory without claiming or changing it'
    [void][IO.Directory]::CreateDirectory((Join-Path $shared 'app'))
    $report=& $audit @parameters
    Assert-AuditTest (@($report.checks|Where-Object {$_.name -eq 'installRoot' -and $_.status -eq 'FAIL'}).Count -eq 1) 'Audit rejects unowned managed-path collisions'
    $parameters.InstallRoot=$install
    $legacy=Join-Path $env:LOCALAPPDATA 'ShadowLocalAI'
    [void][IO.Directory]::CreateDirectory($legacy)
    [IO.File]::WriteAllText((Join-Path $legacy 'unrelated.txt'),'legacy')
    $report=& $audit @parameters
    Assert-AuditTest ($report.installRoot -ceq $install -and
        @($report.checks|Where-Object {$_.name -eq 'installRoot.legacy' -and $_.status -eq 'WARN'}).Count -eq 1 -and
        [IO.File]::ReadAllText((Join-Path $legacy 'unrelated.txt')) -ceq 'legacy' -and
        -not(Test-Path -LiteralPath $install)) 'Audit reports legacy directory without selecting, copying or altering it'
    Remove-Item -LiteralPath $legacy -Recurse -Force
    $parameters.IncludeFastModel=$true
    $report=& $audit @parameters
    $profileCheck=@($report.checks|Where-Object {$_.name -eq 'model.hardware'})[0]
    Assert-AuditTest ($profileCheck.status -ceq 'PASS' -and $profileCheck.data.profiles.Count -eq 4 -and $profileCheck.data.profiles -contains 'Qwen3.5-9B Q4_K_M') 'Optional fast model uses the same catalog as actual provisioning'
    $parameters.IncludeFastModel=$false;$parameters.SkipModelDownload=$true
    $report=& $audit @parameters
    Assert-AuditTest (@($report.checks|Where-Object {$_.name -eq 'model.file' -and $_.status -eq 'FAIL' -and $_.data.path -and $_.data.downloadUrl}).Count -eq 3) 'Missing selected models block audit when downloading is explicitly disabled'
    $parameters.SkipModelDownload=$false
    $script:badJson=$true
    $report=& $audit @parameters
    Assert-AuditTest ($report.exitCode -eq 2 -and ($report|ConvertTo-Json -Depth 15) -notmatch 'SYNTHETIC_AUDIT_TOKEN_NOT_A_SECRET') 'Malformed CLI JSON is reported without echoing its potentially sensitive raw contents'
    $script:badJson=$false
    $script:offline=$true;$script:timeout=$true
    $report=& $audit @parameters
    Assert-AuditTest ($report.exitCode -eq 2 -and $report.status -ceq 'BLOCKED') 'CLI failure is explicit and blocks readiness'
    Assert-AuditTest (@($report.checks|Where-Object {$_.name -eq 'online.kilo' -and $_.status -eq 'WARN'}).Count -eq 1) 'Offline registry is a warning, not fabricated metadata'
    Assert-AuditTest (@($report.checks|Where-Object {$_.name -eq 'inference'}).Count -eq 1) 'Audit continues collecting evidence after individual failures'
    $script:offline=$false;$script:timeout=$false;$script:ram=16GB
    $report=& $audit @parameters
    Assert-AuditTest (@($report.checks|Where-Object {$_.name -eq 'model.hardware' -and $_.status -eq 'PASS'}).Count -eq 1) 'Smaller models can be suggested when RAM is below the old fixed profile threshold'
    $script:ram=28GB;$parameters.RouterPort=1234
    $report=& $audit @parameters
    Assert-AuditTest (@($report.checks|Where-Object {$_.name -eq 'parameters' -and $_.status -eq 'FAIL'}).Count -eq 1) 'Conflicting configured ports are reported before setup'
    $parameters.RouterPort=1235;$script:public=$true
    $report=& $audit @parameters
    Assert-AuditTest (@($report.checks|Where-Object {$_.name -eq 'port.1234' -and $_.status -eq 'FAIL'}).Count -eq 1) 'Non-loopback listeners block audit readiness'
    $script:public=$false
    [void][IO.Directory]::CreateDirectory($install)
    [IO.File]::WriteAllText((Join-Path $install 'shadow-local-ai-install.json'),'{"schema":1,"product":"ShadowLocalAI"}')
    [IO.File]::WriteAllText((Join-Path $install 'toolchain.json'),'{"schema":999}')
    $report=& $audit @parameters
    Assert-AuditTest (@($report.checks|Where-Object {$_.name -eq 'state.toolchain' -and $_.status -eq 'FAIL'}).Count -eq 1) 'Unknown managed schemas are explicitly rejected'
    Assert-AuditTest ([IO.File]::ReadAllText((Join-Path $install 'toolchain.json')) -ceq '{"schema":999}') 'Invalid saved state is preserved byte-for-byte'
    [IO.File]::WriteAllText((Join-Path $install 'toolchain.json'),'{"schema":2}')
    $report=& $audit @parameters
    Assert-AuditTest (@($report.checks|Where-Object {$_.name -eq 'state.toolchain' -and $_.status -eq 'FAIL'}).Count -eq 1) 'Known schema without required fields is not reported as valid'
    $heldLock=[IO.File]::Open((Join-Path $install 'provisioning.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    try{
        $report=& $audit @parameters
        Assert-AuditTest (@($report.checks|Where-Object {$_.name -eq 'setup.lock' -and $_.status -eq 'FAIL'}).Count -eq 1) 'Audit detects a held provisioning lock without changing it'
    }finally{$heldLock.Dispose()}
    $nativeDefinition=$auditAst.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Invoke-AuditNative'},$false)
    . ([scriptblock]::Create($nativeDefinition.Extent.Text))
    $exe=(Get-Process -Id $PID).Path
    $output=Invoke-AuditNative $exe @('-NoLogo','-NoProfile','-NonInteractive','-Command','[Console]::Error.Write("warning"); "AUDIT_NATIVE_OK"')
    Assert-AuditTest ($output -ceq 'AUDIT_NATIVE_OK') 'Real audit process captures stdout without treating stderr warnings as errors'
    $probeResult=Invoke-AuditNative $exe @('-NoLogo','-NoProfile','-NonInteractive','-Command','[Console]::Error.Write("expected refusal"); exit 1') -AllowFailure
    Assert-AuditTest ($probeResult.ExitCode -eq 1 -and $probeResult.Stderr -ceq 'expected refusal') 'Native probe preserves expected exit status and stderr'
    $failed=$false
    try{$null=Invoke-AuditNative $exe @('-NoLogo','-NoProfile','-NonInteractive','-Command','Start-Sleep -Seconds 30') -TimeoutSeconds 1}catch{$failed=$_.Exception.Message -match 'Timeout'}
    Assert-AuditTest $failed 'Real audit subprocess timeout terminates its own process and reports failure'
    $httpDefinition=$auditAst.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Invoke-AuditJson'},$false)
    . ([scriptblock]::Create($httpDefinition.Extent.Text))
    $node=(Get-Command node.exe -CommandType Application|Select-Object -First 1).Source
    $serverCode='const http=require("node:http");const s=http.createServer((q,r)=>{r.setHeader("Content-Type","application/json");if(q.url==="/ok"){r.end(JSON.stringify({models:[],authenticated:q.headers.authorization==="Bearer synthetic"}));}else if(q.url==="/redirect"){r.writeHead(302,{Location:"http://example.invalid/"});r.end("{}");}else{r.writeHead(403);r.end(JSON.stringify({secret:"DO_NOT_ECHO_RESPONSE"}));}});s.listen(0,"127.0.0.1",()=>console.log(s.address().port));'
    $start=New-Object Diagnostics.ProcessStartInfo
    $start.FileName=$node;$start.UseShellExecute=$false;$start.CreateNoWindow=$true
    $start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
    $start.Arguments='--eval '+(ConvertTo-WindowsArgument $serverCode)
    $serverProcess=[Diagnostics.Process]::Start($start)
    try{
        $portTask=$serverProcess.StandardOutput.ReadLineAsync()
        if(-not $portTask.Wait(10000)){throw 'Synthetic HTTP server startup timed out'}
        $httpPort=[int]$portTask.Result
        if($httpPort -lt 1){throw 'Synthetic HTTP server did not report its port'}
        $answer=Invoke-AuditJson -Uri "http://127.0.0.1:$httpPort/ok" -BearerToken synthetic
        Assert-AuditTest ($answer.authenticated -and $answer.models.Count -eq 0) 'Real HTTP helper authenticates only the requested loopback endpoint'
        $failed=$false
        try{$null=Invoke-AuditJson -Uri "http://127.0.0.1:$httpPort/deny"}catch{$failed=$_.Exception.Message -match 'HTTP 403' -and $_.Exception.Message -notmatch 'DO_NOT_ECHO_RESPONSE'}
        Assert-AuditTest $failed 'HTTP errors report status without exposing server response bodies'
        $failed=$false
        try{$null=Invoke-AuditJson -Uri "http://127.0.0.1:$httpPort/redirect" -BearerToken synthetic}catch{$failed=$_.Exception.Message -match 'HTTP 302'}
        Assert-AuditTest $failed 'HTTP redirects are rejected rather than forwarding credentials'
        $failed=$false
        try{$null=Invoke-AuditJson -Uri "http://127.0.0.1:$httpPort/ok" -BearerToken ("private-header-fragment`ninvalid")}catch{$failed=$_.Exception.Message -notmatch 'private-header-fragment' -and $_.Exception.Message -match 'header characters'}
        Assert-AuditTest $failed 'Invalid token header characters fail without printing the token'
    }finally{
        if(-not $serverProcess.HasExited){$serverProcess.Kill();$serverProcess.WaitForExit()}
        $serverProcess.Dispose()
    }
    [pscustomobject]@{suite='Extended audit';passed=$true;checks=$results.Count;powerShell=$PSVersionTable.PSVersion.ToString();boundaries='CIM, application CLIs and remote HTTP mocked; native PowerShell process checks real'}|ConvertTo-Json
}finally{
    [Environment]::SetEnvironmentVariable($parameters.ApiTokenEnvironmentVariable,$previous,'Process')
    $env:USERPROFILE=$previousProfile
    $env:LOCALAPPDATA=$previousLocalAppData
    Remove-Item -LiteralPath $root -Recurse -Force
}
