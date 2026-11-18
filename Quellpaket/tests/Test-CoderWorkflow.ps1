#requires -Version 7.4
param([string]$SourceRoot=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
& (Join-Path $PSScriptRoot 'Test-QualityWorkflow.ps1') -SourceRoot $SourceRoot
