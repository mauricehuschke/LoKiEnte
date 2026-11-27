# Local model-router lifecycle. Dot-source Common.ps1, Runtime.ps1 and ModelPool.ps1 first.
Set-StrictMode -Version Latest

function Get-ShadowPoolCatalog {
    param([Parameter(Mandatory)]$Pool)
    Assert-SmpPool -Pool $Pool -RequireReady
    $catalog=[ordered]@{}
    foreach($profile in $Pool.Profiles){
        $roleLabel=switch($profile.Alias){
            'coder-high' {'CODER HIGH'}
            'coder-fast' {'CODER FAST'}
            'coder' {'CODER (LEGACY)'}
            'review' {'REVIEW'}
            'fast' {'FAST'}
            default {throw "Unknown model profile: $($profile.Alias)"}
        }
        $interleaved=[string](Get-LrProperty $profile 'Interleaved')
        if(-not $interleaved){$interleaved=if($profile.Alias -eq 'review'){'reasoning'}else{'reasoning_content'}}
        if($interleaved -cnotin @('reasoning','reasoning_content')){throw 'Invalid reasoning field in model profile.'}
        $stateSuffix=if((Get-LrProperty $profile 'VerificationState') -ceq 'Deferred'){' [NOT YET VERIFIED]'}else{''}
        $catalog[$profile.Alias]=[ordered]@{
            id=$profile.RouteId;name=('['+$roleLabel+'] '+$profile.Name+$stateSuffix);context=[int]$profile.ContextLength;output=[int]$profile.OutputLimit
            reasoning=$true;interleaved=$interleaved
        }
    }
    return $catalog
}

function Get-ShadowRouterHealth {
    [CmdletBinding(DefaultParameterSetName='Pool')]
    param([Parameter(Mandatory,ParameterSetName='Pool')]$Pool,
        [Parameter(Mandatory,ParameterSetName='Port')][ValidateRange(1024,65535)][int]$RouterPort,
        [Parameter(ParameterSetName='Port')][string]$ApiTokenEnvironmentVariable='LOKIENTE_LM_API_KEY')
    # Validate before constructing authentication headers or issuing a request.
    if($PSCmdlet.ParameterSetName -ceq 'Pool'){
        Assert-SmpPool -Pool $Pool
        $RouterPort=([Uri]$Pool.RouterApiBaseUrl).Port;$ApiTokenEnvironmentVariable=$Pool.ApiTokenEnvironmentVariable
    }
    $base="http://127.0.0.1:$RouterPort"
    try{
        $status=0
        $health=Invoke-RestMethod -Uri ($base+'/health') -Headers (Get-LrApiHeaders $ApiTokenEnvironmentVariable) -TimeoutSec 3 -NoProxy -SkipHttpErrorCheck -StatusCodeVariable status -ErrorAction Stop
        if($status -eq 200 -or ($status -eq 503 -and (Get-LrProperty $health 'service') -ceq 'shadow-local-model-router')){return $health}
        Write-Verbose "Router status unreadable (HTTP $status)."
        return $null
    }
    catch{Write-Verbose 'Router status unreachable or not readable as JSON.';return $null}
}

function ConvertFrom-ShadowRouterCommandLine {
    param([string]$CommandLine)
    if(-not $IsWindows){throw 'Router process recovery requires Windows process evidence.'}
    if(-not ('LoKiEnte.RouterArguments' -as [type])){
        Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
namespace LoKiEnte {
    public static class RouterArguments {
        [DllImport("shell32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
        private static extern IntPtr CommandLineToArgvW(string commandLine, out int count);
        [DllImport("kernel32.dll")]
        private static extern IntPtr LocalFree(IntPtr memory);
        public static string[] Parse(string commandLine) {
            int count; IntPtr memory=CommandLineToArgvW(commandLine, out count);
            if(memory==IntPtr.Zero) throw new Win32Exception();
            try {
                var result=new string[count];
                for(int i=0;i<count;i++) result[i]=Marshal.PtrToStringUni(Marshal.ReadIntPtr(memory,i*IntPtr.Size));
                return result;
            } finally { LocalFree(memory); }
        }
    }
}
'@
    }
    return [LoKiEnte.RouterArguments]::Parse($CommandLine)
}

function Get-ShadowOwnedRouterProcess {
    param([string]$InstallRoot,$Health,[int]$RouterPort,[string]$NodePath,[string]$PowerShellPath)
    $routerPid=[int](Get-LrProperty $Health 'pid' 0)
    if($routerPid -le 0 -or -not $NodePath -or -not $PowerShellPath){throw 'Missing process identity or managed executable paths.'}
    $samePath={param($a,$b) $a -and $b -and [IO.Path]::GetFullPath($a) -ieq [IO.Path]::GetFullPath($b)}
    foreach($directory in @($InstallRoot,(Join-Path $InstallRoot 'app'),(Join-Path $InstallRoot 'runtime'))){
        $item=Get-Item -LiteralPath $directory -Force -ErrorAction Stop
        if(-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Recovery paths must be ordinary installation directories.'}
    }
    foreach($file in @((Join-Path $InstallRoot 'app/ModelRouter.mjs'),(Join-Path $InstallRoot 'app/Switch-LocalModel.ps1'))){
        $item=Get-Item -LiteralPath $file -Force -ErrorAction Stop
        if($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Recovery scripts must be ordinary installation files.'}
    }
    $listeners=@(Get-NetTCPConnection -State Listen -LocalPort $RouterPort -ErrorAction Stop)
    if(-not $listeners.Count -or @($listeners|Where-Object {$_.LocalAddress -cne '127.0.0.1' -or [int]$_.OwningProcess -ne $routerPid}).Count){throw 'The loopback listener does not uniquely belong to the reported router PID.'}
    $native=@(Get-CimInstance -ClassName Win32_Process -Filter "ProcessId = $routerPid" -OperationTimeoutSec 5 -ErrorAction Stop)
    if($native.Count -ne 1 -or [int]$native[0].ProcessId -ne $routerPid -or -not (&$samePath $native[0].ExecutablePath $NodePath)){throw 'The process executable or PID does not match the managed Node path.'}
    $arguments=@(ConvertFrom-ShadowRouterCommandLine -CommandLine $native[0].CommandLine)
    if($arguments.Count -ne 12 -or -not (&$samePath $arguments[0] $NodePath) -or
       -not (&$samePath $arguments[1] (Join-Path $InstallRoot 'app/ModelRouter.mjs')) -or
       $arguments[2] -cne '--config' -or -not (&$samePath $arguments[3] (Join-Path $InstallRoot 'runtime/model-pool.json')) -or
       $arguments[4] -cne '--routing-digest' -or $arguments[5] -cnotmatch '^[a-f0-9]{64}$' -or $arguments[5] -cne [string](Get-LrProperty $Health 'configDigest') -or
       $arguments[6] -cne '--pwsh' -or -not (&$samePath $arguments[7] $PowerShellPath) -or
       $arguments[8] -cne '--switch-script' -or -not (&$samePath $arguments[9] (Join-Path $InstallRoot 'app/Switch-LocalModel.ps1')) -or
       $arguments[10] -cne '--port' -or $arguments[11] -cne [string]$RouterPort){throw 'The complete process command line does not match this installation.'}
    $owner=Invoke-CimMethod -InputObject $native[0] -MethodName GetOwnerSid -OperationTimeoutSec 5 -ErrorAction Stop
    if($owner.ReturnValue -ne 0 -or $owner.Sid -cne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value){throw 'The router process belongs to a different or unverified Windows account.'}
    $process=[Diagnostics.Process]::GetProcessById($routerPid)
    try{
        $null=$process.SafeHandle
        if($process.HasExited -or [math]::Abs(($process.StartTime.ToUniversalTime()-$native[0].CreationDate.ToUniversalTime()).TotalMilliseconds) -gt 1){throw 'The process identity changed while it was being verified.'}
        return $process
    }catch{$process.Dispose();throw}
}

function Stop-ShadowModelRouter {
    [CmdletBinding(DefaultParameterSetName='Pool')]
    param([Parameter(Mandatory)][string]$InstallRoot,[Parameter(Mandatory,ParameterSetName='Pool')]$Pool,
        [Parameter(Mandatory,ParameterSetName='Port')][ValidateRange(1024,65535)][int]$RouterPort,
        [Parameter(ParameterSetName='Port')][string]$ApiTokenEnvironmentVariable='LOKIENTE_LM_API_KEY',
        [string]$NodePath,[string]$PowerShellPath,[switch]$PassThru)
    if($PSCmdlet.ParameterSetName -ceq 'Pool'){
        Assert-SmpPool -Pool $Pool
        $RouterPort=([Uri]$Pool.RouterApiBaseUrl).Port;$ApiTokenEnvironmentVariable=$Pool.ApiTokenEnvironmentVariable
    }
    $healthArguments=@{RouterPort=$RouterPort;ApiTokenEnvironmentVariable=$ApiTokenEnvironmentVariable}
    $health=Get-ShadowRouterHealth @healthArguments
    if(-not $health){
        if(@(Get-NetTCPConnection -State Listen -LocalPort $RouterPort -ErrorAction SilentlyContinue).Count){throw "Router port $RouterPort is occupied, but the known router is unreachable. No process will be terminated."}
        if($PassThru){return [pscustomobject]@{Status='NotRunning';Method='None';RouterPort=$RouterPort}}
        return
    }
    if((Get-LrProperty $health 'service') -cne 'shadow-local-model-router'){throw 'The port does not belong to the expected local router. It remains unchanged.'}
    if((Get-LrProperty $health 'busy' $true) -or [int](Get-LrProperty $health 'queued' 1) -gt 0){throw 'The local router is still working. Complete active chats/tasks and retry.'}
    $controlPath=Join-Path $InstallRoot 'runtime/router-control.json'
    $method='AuthenticatedShutdown';$routerPid=[int](Get-LrProperty $health 'pid' 0)
    if(-not(Test-Path -LiteralPath $controlPath)){
        $method='VerifiedOwnedProcess';$process=$null
        Write-ShadowMessage "Router PID $routerPid answers on 127.0.0.1:$RouterPort, but $controlPath is missing. Checking Windows ownership before recovery."
        try{
            $process=Get-ShadowOwnedRouterProcess -InstallRoot $InstallRoot -Health $health -RouterPort $RouterPort -NodePath $NodePath -PowerShellPath $PowerShellPath
            $latest=Get-ShadowRouterHealth @healthArguments
            if(-not $latest -or (Get-LrProperty $latest 'service') -cne 'shadow-local-model-router' -or [int](Get-LrProperty $latest 'pid' 0) -ne $routerPid -or
               (Get-LrProperty $latest 'configDigest') -cne (Get-LrProperty $health 'configDigest') -or
               (Get-LrProperty $latest 'busy' $true) -or [int](Get-LrProperty $latest 'queued' 1) -gt 0){throw 'Router identity or idle state changed before recovery.'}
            $startUtc=$process.StartTime.ToUniversalTime().ToString('o')
            $process.Kill();if(-not $process.WaitForExit(5000)){throw 'The verified process did not exit.'}
            $evidence=@{utc=[DateTime]::UtcNow.ToString('o');kind='router-control-recovery';pid=$routerPid;processStartedUtc=$startUtc;routerPort=$RouterPort;installRoot=[IO.Path]::GetFullPath($InstallRoot);method=$method;accountMatched=$true;listenerMatched=$true;commandLineMatched=$true}
            $null=Write-ShadowManagedFile -Path (Join-Path $InstallRoot 'runtime/router-recovery.json') -Content ($evidence|ConvertTo-Json) -BackupRoot (Join-Path $InstallRoot 'backups/router-recovery')
            Write-ShadowMessage "Recovered orphaned LoKiEnte router PID $routerPid for this installation after verifying Windows owner, executable, command line and loopback listener." 'OK'
        }catch{throw "Control credentials for the running router are missing (PID $routerPid, port $RouterPort, $controlPath). Automatic recovery could not verify or stop this installation's idle router: $($_.Exception.Message) No unverified process will be terminated."}
        finally{if($process){$process.Dispose()}}
    }else{
        $control=Get-Content -LiteralPath $controlPath -Raw|ConvertFrom-Json
        $headers=Get-LrApiHeaders $ApiTokenEnvironmentVariable
        $headers['X-Shadow-Control']=[string]$control.token
        $base="http://127.0.0.1:$RouterPort"
        try{$result=Invoke-RestMethod -Uri ($base+'/admin/shutdown') -Method Post -Headers $headers -TimeoutSec 10 -NoProxy -ErrorAction Stop}
        catch{throw 'Could not stop the running router with authenticated shutdown. No arbitrary process kill was used instead.'}
        if((Get-LrProperty $result 'stopping' $false) -ne $true){throw 'The router did not confirm controlled shutdown.'}
    }
    for($i=0;$i -lt 20;$i++){
        if(-not(Get-ShadowRouterHealth @healthArguments)){
            if(@(Get-NetTCPConnection -State Listen -LocalPort $RouterPort -ErrorAction SilentlyContinue).Count){throw 'The router port is still occupied after shutdown.'}
            Write-ShadowMessage "Router PID $routerPid stopped via $method; loopback port $RouterPort is free." 'OK'
            if($PassThru){return [pscustomobject]@{Status='Stopped';Method=$method;RouterPort=$RouterPort;Pid=$routerPid}}
            return
        }
        Start-Sleep -Milliseconds 250
    }
    throw 'The router is still shutting down. Wait briefly and retry.'
}

function Get-ShadowRoutingDigest {
    param($Pool,[string]$NodePath,[string]$PowerShellPath)
    # Hash the routing contract only. Estimates, timestamps and verification
    # outcomes are runtime data and are refreshed by the controller.
    $contract=[ordered]@{Node=$NodePath;PowerShell=$PowerShellPath}
    foreach($name in @('SchemaVersion','OwnerId','PrimaryAlias','BackendApiBaseUrl','RouterApiBaseUrl','LmsPath','ApiTokenEnvironmentVariable','AllowPartialGpuOffload','AllowUnfitAttempt')){
        $contract[$name]=Get-LrProperty $Pool $name
    }
    $contract.Profiles=@(foreach($profile in $Pool.Profiles){
        $entry=[ordered]@{}
        foreach($name in @('Alias','RouteId','InstanceId','ModelPath','ModelKey','ExpectedPath','SelectedVariant','ContextLength','OutputLimit','Parallel')){
            $entry[$name]=Get-LrProperty $profile $name
        }
        $entry
    })
    $bytes=[Text.Encoding]::UTF8.GetBytes(($contract|ConvertTo-Json -Depth 8 -Compress))
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
}

function Start-ShadowModelRouter {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$InstallRoot,
        [Parameter(Mandatory)]$Pool,
        [Parameter(Mandatory)][string]$NodePath,
        [Parameter(Mandatory)][string]$PowerShellPath
    )
    Assert-SmpPool -Pool $Pool -RequireReady
    $poolPath=Join-Path $InstallRoot 'runtime/model-pool.json'
    $digest=Get-ShadowRoutingDigest $Pool $NodePath $PowerShellPath
    $health=Get-ShadowRouterHealth -Pool $Pool
    if($health -and (Get-LrProperty $health 'service') -ceq 'shadow-local-model-router' -and
       (Get-LrProperty $health 'configDigest') -ceq $digest -and (Get-LrProperty $health 'version') -ceq '2026.11.27.2' -and
       (Get-LrProperty $health 'ready' $false) -eq $true -and (Test-Path -LiteralPath (Join-Path $InstallRoot 'runtime/router-control.json'))){
        return [pscustomobject]@{Status='Ready';ApiBaseUrl=$Pool.RouterApiBaseUrl;Port=([Uri]$Pool.RouterApiBaseUrl).Port;Pid=$health.pid;ConfigDigest=$digest;Reused=$true}
    }
    Stop-ShadowModelRouter -InstallRoot $InstallRoot -Pool $Pool -NodePath $NodePath -PowerShellPath $PowerShellPath
    # Only restart/load the backend when no managed router is using it.
    $Pool=Start-LocalModelPool -InstallRoot $InstallRoot
    $digest=Get-ShadowRoutingDigest $Pool $NodePath $PowerShellPath
    $controlPath=Join-Path $InstallRoot 'runtime/router-control.json'
    if(Test-Path -LiteralPath $controlPath){$control=Get-Content -LiteralPath $controlPath -Raw|ConvertFrom-Json}
    else{
        $control=[pscustomobject]@{schema=1;token=[Convert]::ToHexString([Security.Cryptography.RandomNumberGenerator]::GetBytes(32)).ToLowerInvariant()}
        $null=Write-ShadowManagedFile -Path $controlPath -Content ($control|ConvertTo-Json)
    }
    if($control.schema -ne 1 -or $control.token -notmatch '^[a-f0-9]{64}$'){throw 'Invalid control credentials in local router profile.'}
    $start=[Diagnostics.ProcessStartInfo]::new()
    $start.FileName=$NodePath;$start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.WorkingDirectory=$InstallRoot
    foreach($arg in @((Join-Path $InstallRoot 'app/ModelRouter.mjs'),'--config',$poolPath,'--routing-digest',$digest,'--pwsh',$PowerShellPath,'--switch-script',(Join-Path $InstallRoot 'app/Switch-LocalModel.ps1'),'--port',([string]([Uri]$Pool.RouterApiBaseUrl).Port))){[void]$start.ArgumentList.Add($arg)}
    $start.Environment['SHADOW_LOCAL_ROUTER_CONTROL']=[string]$control.token
    if($Pool.ApiTokenEnvironmentVariable){
        $name=[string]$Pool.ApiTokenEnvironmentVariable
        $token=[Environment]::GetEnvironmentVariable($name,'Process')
        if([string]::IsNullOrWhiteSpace($token)){$token=[Environment]::GetEnvironmentVariable($name,'User')}
        if(-not [string]::IsNullOrWhiteSpace($token)){$start.Environment[$name]=$token}
    }
    $process=[Diagnostics.Process]::Start($start)
    try{
        for($attempt=0;$attempt -lt 30;$attempt++){
            if($process.HasExited){throw "Local router exited with code $($process.ExitCode). Check configuration and port."}
            $health=Get-ShadowRouterHealth -Pool $Pool
            if($health -and (Get-LrProperty $health 'service') -ceq 'shadow-local-model-router' -and
               (Get-LrProperty $health 'configDigest') -ceq $digest -and (Get-LrProperty $health 'pid') -eq $process.Id -and
               (Get-LrProperty $health 'ready' $false) -eq $true){
                return [pscustomobject]@{Status='Ready';ApiBaseUrl=$Pool.RouterApiBaseUrl;Port=([Uri]$Pool.RouterApiBaseUrl).Port;Pid=$process.Id;ConfigDigest=$digest;Reused=$false}
            }
            Start-Sleep -Milliseconds 500
        }
        throw 'Local router did not return its verified readiness status.'
    }catch{
        $failure=$_
        # This handle belongs to the process started above. Never discover/kill
        # a process merely because its PID or port matches a foreign service.
        try{if(-not $process.HasExited){$process.Kill($true);$null=$process.WaitForExit(5000)}}catch{Write-Warning 'Could not stop the router started by this run after startup failed.'}
        throw $failure
    }finally{$process.Dispose()}
}
