#requires -Version 7.4
[CmdletBinding()]
param([string]$InstallRoot=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath($InstallRoot)
$id=([guid]::NewGuid().ToString('N')).Substring(0,12)
$project=Join-Path $root "diagnostics/index-probe-$id"
[void](New-Item -ItemType Directory -Path $project)
$git=(Get-Command git -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
& $git init --quiet $project
if($LASTEXITCODE -ne 0){throw "Test-Repository konnte nicht initialisiert werden: $project"}
$publicMarker="VISIBLE_$id"
$gitIgnored="IGNORE_GIT_$id"
$kiloIgnored="IGNORE_KILO_$id"
Set-Content -LiteralPath (Join-Path $project '.gitignore') -Value @('/private-git.txt','/.kilocodeignore')
Set-Content -LiteralPath (Join-Path $project '.kilocodeignore') -Value '/private-kilo.txt'
Set-Content -LiteralPath (Join-Path $project 'stock.ts') -Value @"
// $publicMarker
// Restock when the inventory drops below the reorder point.
export const shouldRestock = (inventory: number, reorderPoint: number) => inventory < reorderPoint
"@
Set-Content -LiteralPath (Join-Path $project 'private-git.txt') -Value "$gitIgnored`nThe lunar telescope tracks a green comet."
Set-Content -LiteralPath (Join-Path $project 'private-kilo.txt') -Value "$kiloIgnored`nThe desert weather station tracks wind speed."
[pscustomobject]@{
    project=$project
    positiveQuery='When should we order more stock?'
    expectedFile='stock.ts'
    positiveMarker=$publicMarker
    ignoredQueries=@('lunar telescope green comet','desert weather station wind speed')
    ignoredMarkers=@($gitIgnored,$kiloIgnored)
}
