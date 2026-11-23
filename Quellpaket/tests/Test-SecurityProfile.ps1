#requires -Version 7.4
$ErrorActionPreference='Stop'
$root=Join-Path ([IO.Path]::GetTempPath()) ('lokiente-security-tests-'+[guid]::NewGuid().ToString('N'))
$script=Join-Path (Split-Path -Parent $PSScriptRoot) 'SecurityProfile.ps1'
$vmId=[guid]::NewGuid()
$fixture=@{enhanced=$false;network=$false;media=$false;disk=''}
$fixtureVm=[pscustomobject]@{Name='Fixture';VMId=$vmId;State='Off'}
function Import-Module {param($Name,$ErrorAction) if($Name -ne 'Hyper-V'){throw 'Unexpected import'}}
function Get-VM {param($Id,$ErrorAction) $fixtureVm}
function Get-VMHost { [pscustomobject]@{EnableEnhancedSessionMode=$fixture.enhanced} }
function Get-VMNetworkAdapter { param($VM) if($fixture.network){'adapter'} }
function Get-VMHardDiskDrive { param($VM) [pscustomobject]@{Path=$fixture.disk} }
function Get-VMDvdDrive {param($VM) if($fixture.media){[pscustomobject]@{Path='D:\fixture.iso'}}}
function Get-VMComPort {param($VM)}
function Get-VMFibreChannelHba {param($VM)}
function Get-VMAssignableDevice {param($VMName)}
function Start-VM {param($VM) throw 'Tests must not start a VM'}
function Assert-Rejected([scriptblock]$Run,[string]$Message){
    $failure=$null
    try{& $Run}catch{$failure=$_.Exception.Message}
    if(-not $failure -or $failure -notlike "*$Message*"){throw "Expected '$Message', got '$failure'"}
}
try{
    $blocked=Join-Path $root 'blocked'
    [void][IO.Directory]::CreateDirectory($blocked)
    $file=Join-Path $root 'security/profile.json'
    $fixture.network=$false;$fixture.enhanced=$false;$fixture.media=$false;$fixture.disk='D:\fixtures\guest.vhdx'
    $settings=@{Action='Enable';InstallRoot=$root;VmId=$vmId;ProtectedFolder=$blocked}
    & $script @settings
    $saved=[IO.File]::ReadAllText($file)
    if(($saved|ConvertFrom-Json).mode -ne 'offline-vm'){throw 'Profile was not persisted'}
    $fixture.network=$true
    Assert-Rejected {& $script -Action Launch -InstallRoot $root} 'network adapter'
    $fixture.network=$false;$fixture.enhanced=$true
    Assert-Rejected {& $script @settings} 'Enhanced Session'
    $fixture.enhanced=$false;$fixture.disk='\\server\disk.vhdx'
    Assert-Rejected {& $script @settings} 'virtual system disk'
    $fixture.disk='D:\fixtures\guest.vhdx';$fixture.media=$true
    Assert-Rejected {& $script @settings} 'mounted media'
    $fixture.media=$false
    $private=Join-Path $blocked 'private.zip';[IO.File]::WriteAllText($private,'fixture')
    Assert-Rejected {& $script @settings -ImportArchive $private} 'inside the protected folder'
    if([IO.File]::ReadAllText($file) -cne $saved){throw 'A rejected edit replaced the saved profile'}
    & $script -Action Disable -InstallRoot $root
    if((Get-Content $file -Raw|ConvertFrom-Json).mode -ne 'standard'){throw 'Recovery failed'}
    # Exercise the actual launcher. An invalid policy must be rejected before the
    # project selector, toolchain discovery, model loading or editor startup.
    [IO.File]::WriteAllText($file,'{"schema":1,"mode":"broken"}')
    $launcher=Join-Path (Split-Path -Parent $PSScriptRoot) 'Start-LocalAI.ps1'
    $out=& (Get-Process -Id $PID).Path -NoProfile -NonInteractive -File $launcher -InstallRoot $root 2>&1 | Out-String
    if($LASTEXITCODE -eq 0 -or $out -notmatch 'Invalid security profile'){throw 'Unexpected host fallback'}
    & (Get-Process -Id $PID).Path -NoProfile -NonInteractive -File $launcher -InstallRoot $root -ResetSecurityProfile
    if($LASTEXITCODE -ne 0 -or (Get-Content $file -Raw | ConvertFrom-Json).mode -ne 'standard'){throw 'Launcher recovery failed'}
    'Security profile persistence and fail-closed gates passed.'
}finally{
    $base=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
    if([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($root)) -ne $base -or [IO.Path]::GetFileName($root) -notlike 'lokiente-security-tests-*'){throw 'Unsafe cleanup'}
    if([IO.Directory]::Exists($root)){Remove-Item -LiteralPath $root -Force -Recurse}
}
