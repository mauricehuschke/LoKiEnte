#requires -Version 7.4
[CmdletBinding()]
param([Parameter(Mandatory)][string]$RequestPath)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$arguments=Get-Content -LiteralPath $RequestPath -Raw|ConvertFrom-Json -AsHashtable
$allowed=@('ModelAction','UpdatePolicy','DependencyPlan','InstallRoot','ModelMode','IndexingMode','IncludeFastModel','AllowPartialGpuOffload','AllowUnfitAttempt','BundleVersion','PayloadSha256','RouterPort','PreferredModel','ModelKey','ApiTokenEnvironmentVariable','ContextLength','Port','ProjectPath','SkipModelDownload','UpdateManaged','NoShortcut','UseRecommendedModelsBasedOnGPU','SilentMode','WorkspaceTrust','RunAcceptanceTest','SkipAcceptanceTest','BootstrapEvidence')
foreach($key in $arguments.Keys){if($key -notin $allowed){throw "Unknown installation parameter: $key"}}
$lockPath=Join-Path (Split-Path -Parent $PSScriptRoot) 'setup-active.lock'
try{$lock=[IO.File]::Open($lockPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}
catch [IO.IOException]{throw 'Another setup instance is already running. No parallel provisioning started.'}
try{
    & (Join-Path $PSScriptRoot 'Setup.ps1') @arguments
    # A nested .ps1 exit sets LASTEXITCODE; -File otherwise returns 0.
    exit $LASTEXITCODE
}finally{$lock.Dispose()}
