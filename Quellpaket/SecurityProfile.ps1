#requires -Version 7.4
# Runs on the trusted Windows host. No host drive is attached to the guest.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Inspect','List','Enable','Disable','Launch')][string]$Action,
    [string]$InstallRoot=(Split-Path -Parent $PSScriptRoot),
    [guid]$VmId, [string]$ProtectedFolder, [string]$ImportArchive
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$profileFile=Join-Path $InstallRoot 'security/profile.json'

function Get-LocalFolder([string]$Path) {
    if($Path -notmatch '^[A-Za-z]:\\' -or $Path -match '[*?]'){throw 'Select a local Windows folder.'}
    $item=Get-Item -LiteralPath $Path -Force
    if(-not $item.PSIsContainer -or -not $item.Parent){throw 'Select a folder below the drive root.'}
    for($parent=$item;$parent;$parent=$parent.Parent){
        if($parent.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Linked folders cannot be used for a security profile.'}
    }
    if([IO.DriveInfo]::new($item.Root.FullName).DriveType -notin @('Fixed','Removable')){throw 'Select a local volume.'}
    return $item.FullName.TrimEnd('\')
}
function Assert-OfflineVm([guid]$Id) {
    Import-Module Hyper-V -ErrorAction Stop
    $machine=Get-VM -Id $Id -ErrorAction Stop
    if((Get-VMHost).EnableEnhancedSessionMode){throw 'Disable Enhanced Session Mode Policy in Hyper-V Settings before using the isolated profile. Drive and clipboard redirection must be unavailable.'}
    if(@(Get-VMNetworkAdapter -VM $machine).Count){throw 'Remove every virtual network adapter from the dedicated VM while it is off.'}
    $disks=@(Get-VMHardDiskDrive -VM $machine)
    if($disks.Count -ne 1 -or $disks[0].Path -notmatch '^[a-zA-Z]:\\.+\.a?vhdx$'){throw 'The VM must have exactly one local virtual system disk (VHDX or its AVHDX checkpoint).'}
    if(@(Get-VMDvdDrive -VM $machine | Where-Object Path).Count -or
       @(Get-VMComPort -VM $machine | Where-Object Path).Count -or
       @(Get-VMFibreChannelHba -VM $machine).Count -or
       @(Get-VMAssignableDevice -VMName $machine.Name).Count){throw 'Remove mounted media, serial pipes, Fibre Channel and directly assigned devices. Use GPU partitioning for GPU access.'}
    return $machine
}
function Save-Profile($Value){
    $directory=Split-Path -Parent $profileFile
    [void][IO.Directory]::CreateDirectory($directory)
    $tmp=Join-Path $directory ([guid]::NewGuid().ToString('N')+'.tmp')
    try{
        [IO.File]::WriteAllText($tmp,($Value|ConvertTo-Json))
        [IO.File]::Move($tmp,$profileFile,$true)
    }finally{if([IO.File]::Exists($tmp)){[IO.File]::Delete($tmp)}}
}
function Get-ProjectArchive([string]$Path,[string]$Blocked) {
    if(-not $Path){return}
    $item=Get-Item -LiteralPath $Path -Force
    if($item -isnot [IO.FileInfo] -or $item.Extension -ine '.zip' -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){
        throw 'Only an explicitly selected local project ZIP is supported.'
    }
    $directory=Get-LocalFolder $item.DirectoryName
    if(($directory+'\').StartsWith($Blocked+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'The project archive is inside the protected folder.'}
    return $item.FullName
}

try {
    if($Action -eq 'Disable'){Save-Profile @{schema=1;mode='standard'};return}
    if($Action -eq 'Inspect'){
        if(-not (Get-Module -ListAvailable Hyper-V)){
            Write-Output 'Hyper-V management tools unavailable. Check Windows edition, Hyper-V and provider support for nested virtualization.'
            return
        }
        Import-Module Hyper-V -ErrorAction Stop
        $vmHost=Get-VMHost -ErrorAction Stop
        Write-Output "Local Hyper-V host accessible. Enhanced session policy enabled: $($vmHost.EnableEnhancedSessionMode) (offline profile requires False)."
        if(Get-Command Get-VMHostPartitionableGpu -ErrorAction SilentlyContinue){
            $adapters=@(Get-VMHostPartitionableGpu -ErrorAction Stop)
            Write-Output "Partitionable GPUs reported: $($adapters.Count). Actual guest inference needs the E.T. test."
        }else{Write-Output 'GPU partition discovery is unavailable on this host.'}
        return
    }
    if($Action -eq 'List'){
        Import-Module Hyper-V -ErrorAction Stop
        ConvertTo-Json -InputObject @(Get-VM | Select-Object Name,VMId) -Compress
        return
    }
    if($Action -eq 'Enable'){
        $null=Assert-OfflineVm $VmId
        $blocked=Get-LocalFolder $ProtectedFolder
        $source=Get-ProjectArchive $ImportArchive $blocked
        Save-Profile @{schema=1;mode='offline-vm';vmId=$VmId;protectedFolder=$blocked;importArchive=$source;markerId=[guid]::NewGuid().ToString('D')}
        return
    }
    $policy=Get-Content -LiteralPath $profileFile -Raw|ConvertFrom-Json
    if($policy.schema -ne 1 -or $policy.mode -cne 'offline-vm'){throw 'Expected an enabled offline VM profile.'}
    $machine=Assert-OfflineVm ([guid]$policy.vmId)
    if($machine.State -ne 'Off'){throw 'Shut down the dedicated VM fully before starting a new isolated session.'}
    $blocked=Get-LocalFolder $policy.protectedFolder
    $source=Get-ProjectArchive $policy.importArchive $blocked
    $markerId=([guid]$policy.markerId).ToString('D')
    $marker=Join-Path $blocked ("lokiente-et-$markerId.probe")
    if(-not [IO.File]::Exists($marker)){
        $stream=[IO.File]::Open($marker,'CreateNew','Write','None')
        try{$bytes=[Text.Encoding]::ASCII.GetBytes($markerId);$stream.Write($bytes)}finally{$stream.Dispose()}
    }
    $file=Get-Item -LiteralPath $marker -Force
    if(($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $file.Length -ne 36 -or [IO.File]::ReadAllText($marker) -cne $markerId){throw 'The host test marker could not be verified.'}
    $sessionId=[guid]::NewGuid().ToString('D')
    $destination="C:\LoKiEnte-Imports\$sessionId\project.zip"
    $challenge=@{schema=1;vmId=[string]$machine.VMId;sessionId=$sessionId;markerPath=$marker;createdUtc=[datetime]::UtcNow.ToString('o');project=$(if($source){$destination})}
    $tempFile=Join-Path ([IO.Path]::GetTempPath()) ("lokiente-et-$sessionId.json")
    try{
        [IO.File]::WriteAllText($tempFile,($challenge | ConvertTo-Json))
        Start-VM -VM $machine | Out-Null
        $ready=$false
        for($i=0;$i -lt 45 -and -not $ready;$i++){
            try{
                Copy-VMFile -VM $machine -SourcePath $tempFile -DestinationPath "C:\ProgramData\LoKiEnte-ET\pending.json" -FileSource Host -CreateFullPath -Force -ErrorAction Stop
                $ready=$true
            }catch{if($i -eq 44){throw 'Guest file copy is unavailable. Enable Guest Service Interface and check the guest Windows integration services.'};Start-Sleep -Seconds 2}
        }
        if($source){
            Copy-VMFile -VM $machine -FileSource Host -SourcePath $source -DestinationPath $destination -CreateFullPath -ErrorAction Stop
        }
        $null=Assert-OfflineVm ([guid]$policy.vmId)
        $challenge.createdUtc=[datetime]::UtcNow.ToString('o')
        [IO.File]::WriteAllText($tempFile,($challenge|ConvertTo-Json))
        Copy-VMFile -VM $machine -SourcePath $tempFile -DestinationPath 'C:\ProgramData\LoKiEnte-ET\challenge.json' -FileSource Host -CreateFullPath -Force
        if($source){Write-Host "Guest project snapshot: $destination"}
        $viewer=[Diagnostics.ProcessStartInfo]::new()
        $viewer.FileName=Join-Path ([Environment]::SystemDirectory) 'vmconnect.exe'
        foreach($arg in @('localhost',$machine.Name)){[void]$viewer.ArgumentList.Add($arg)}
        [Diagnostics.Process]::Start($viewer).Dispose()
    }finally{if([IO.File]::Exists($tempFile)){[IO.File]::Delete($tempFile)}}
}catch{throw "LoKiEnte security profile: $($_.Exception.Message)"}
