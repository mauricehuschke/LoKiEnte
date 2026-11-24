# Compare the values observed by a real Git child before and after the IDE handoff.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../AgentTemplates.ps1')
$git = (Get-Command git -CommandType Application | Select-Object -First 1).Source
function Read-TestGitValues($indexed, $overlay, [switch]$DropEmpty) {
    $start = [Diagnostics.ProcessStartInfo]::new($git)
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($key in @($start.Environment.Keys)) {
        if ($key -match '^GIT_CONFIG_(COUNT|KEY_\d+|VALUE_\d+|PARAMETERS)$') { [void]$start.Environment.Remove($key) }
    }
    foreach ($map in @($indexed,$overlay)) {
        foreach ($key in $map.Keys) { $start.Environment[$key] = $map[$key] }
    }
    if ($DropEmpty) {
        foreach ($key in @($start.Environment.Keys)) {
            if ($start.Environment[$key] -ceq '') { [void]$start.Environment.Remove($key) }
        }
    }
    foreach ($arg in @('config','--null','--get-all','lokientetest.multi')) { $start.ArgumentList.Add($arg) }
    $proc = [Diagnostics.Process]::Start($start)
    try {
        $stdout = $proc.StandardOutput.ReadToEnd()
        $stderr = $proc.StandardError.ReadToEnd()
        $proc.WaitForExit()
        return @{ Output=$stdout; Error=$stderr; Code=$proc.ExitCode }
    } finally { $proc.Dispose() }
}
function Assert-Condition([bool]$Condition,[string]$Message) {
    if (-not $Condition) { throw $Message }
}
$inputEnv = @{
    GIT_CONFIG_COUNT='4'
    GIT_CONFIG_KEY_0='lokientetest.multi'; GIT_CONFIG_VALUE_0=''
    GIT_CONFIG_KEY_1='lokientetest.multi'; GIT_CONFIG_VALUE_1=" leading' ! = ä \ trailing "
    GIT_CONFIG_KEY_2='lokientetest.multi'; GIT_CONFIG_VALUE_2="line1`nline2"
    GIT_CONFIG_KEY_3='lokientetest.multi'; GIT_CONFIG_VALUE_3=''
    GIT_CONFIG_PARAMETERS="'lokientetest.multi'='higher precedence'"
}
$before = Read-TestGitValues $inputEnv @{}
$expected = (@($inputEnv.GIT_CONFIG_VALUE_0,$inputEnv.GIT_CONFIG_VALUE_1,$inputEnv.GIT_CONFIG_VALUE_2,$inputEnv.GIT_CONFIG_VALUE_3,'higher precedence') -join [char]0) + [char]0
Assert-Condition ($before.Code -eq 0 -and $before.Output -ceq $expected) 'Git baseline mismatch.'
$broken = Read-TestGitValues $inputEnv @{} -DropEmpty
Assert-Condition ($broken.Code -ne 0 -and $broken.Error.Contains('GIT_CONFIG_VALUE_0')) 'Expected the original failure.'
$map = Get-ShadowGitEnvironmentOverlay $inputEnv
$after = Read-TestGitValues $inputEnv $map -DropEmpty
Assert-Condition ($after.Code -eq 0 -and $after.Output -ceq $before.Output) 'Handoff changed Git output or precedence.'
Assert-Condition ($inputEnv.GIT_CONFIG_COUNT -eq '4' -and $inputEnv.Contains('GIT_CONFIG_VALUE_0')) 'Parent environment modified.'
$prefix = $inputEnv.Clone()
$prefix.GIT_CONFIG_VALUE_0 = 'first'
$prefix.GIT_CONFIG_KEY_1 = "lokientetest.with'quote.value"
$mapWithPrefix = Get-ShadowGitEnvironmentOverlay $prefix
$original = Read-TestGitValues $prefix @{}
$forwarded = Read-TestGitValues $prefix $mapWithPrefix -DropEmpty
Assert-Condition ($mapWithPrefix.GIT_CONFIG_COUNT -ceq '3' -and $original.Code -eq 0 -and $forwarded.Code -eq 0 -and $original.Output -ceq $forwarded.Output) 'Indexed prefix changed.'
$malformed = $inputEnv.Clone()
$malformed.GIT_CONFIG_PARAMETERS = 'invalid'
Assert-Condition ((Read-TestGitValues $malformed (Get-ShadowGitEnvironmentOverlay $malformed) -DropEmpty).Code -ne 0) 'Invalid higher-precedence parameters must still fail in Git.'
$effective = $inputEnv.Clone()
foreach ($key in $map.Keys) { $effective[$key]=$map[$key] }
Assert-Condition ((Get-ShadowGitEnvironmentOverlay $effective).Count -eq 0) 'Handoff must be idempotent.'
foreach ($envCase in @(@{},@{GIT_CONFIG_COUNT='0'},@{GIT_CONFIG_COUNT='1';GIT_CONFIG_KEY_0='a.b';GIT_CONFIG_VALUE_0='normal'})) {
    Assert-Condition ((Get-ShadowGitEnvironmentOverlay $envCase).Count -eq 0) 'Ordinary Git setup unexpectedly changed.'
}
foreach ($missing in @('GIT_CONFIG_KEY_1','GIT_CONFIG_VALUE_3')) {
    $invalid = $inputEnv.Clone()
    $invalid.Remove($missing)
    $rejected = $false
    try { $null = Get-ShadowGitEnvironmentOverlay $invalid } catch { $rejected = $_.Exception.Message.Contains($missing) }
    Assert-Condition $rejected 'Incomplete input must be rejected without guessing its value.'
}
Write-Output 'PASS: real Git baseline, reproduced missing value, byte-equivalent ordered values, inherited priority, unchanged parent, idempotence, ordinary environments and incomplete pairs.'
