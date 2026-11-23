# Sample Windows' locale-independent, per-process GPU performance data.
$ErrorActionPreference='Stop'
$engines='Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine'
$workers=@('llm-engine-host','llmster','llama-server','llama-box','llama-engine')
Write-Output 'READY'
while($true){
    $pids=@(Get-Process -Name $workers -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)
    if($pids.Count){
        foreach($engine in @(Get-CimInstance -ClassName $engines)){
            if($engine.UtilizationPercentage -gt 0 -and $engine.Name -match '^pid_(\d+)_.+engtype_(Compute(?:_?\d+)?|CUDA(?:_?\d+)?)$' -and $pids -contains [int]$Matches[1]){
                Write-Output 'COMPUTE'
                break
            }
        }
    }
    Start-Sleep -Milliseconds 300
}
