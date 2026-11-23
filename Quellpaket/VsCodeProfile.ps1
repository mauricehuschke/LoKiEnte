#requires -Version 7.4
Set-StrictMode -Version Latest

function Merge-ShadowSyncExclusions {
    param([Collections.IDictionary]$Settings,[string]$Key,[string[]]$Required)
    $values=@()
    if($Settings.Contains($Key)){
        if($Settings[$Key] -isnot [array] -or @($Settings[$Key] | Where-Object {$_ -isnot [string]}).Count){
            throw "VS Code $Key must be an array of strings. Existing settings are preserved."
        }
        $values=@($Settings[$Key])
    }
    $result=[Collections.Generic.List[string]]::new()
    $comparer=if($Key -ceq 'settingsSync.ignoredExtensions'){[StringComparer]::OrdinalIgnoreCase}else{[StringComparer]::Ordinal}
    $requiredSet=[Collections.Generic.HashSet[string]]::new($Required,$comparer)
    $seen=[Collections.Generic.HashSet[string]]::new($comparer)
    foreach($value in $values){
        # An explicit '-key' opts back into sync; it cannot override managed isolation.
        if($value.StartsWith('-') -and $requiredSet.Contains($value.Substring(1))){continue}
        if($seen.Add($value)){$result.Add($value)}
    }
    foreach($value in $Required){if($seen.Add($value)){$result.Add($value)}}
    $Settings[$Key]=@($result.ToArray())
}

function Update-ShadowVsCodeProfile {
    param([Parameter(Mandatory)][string]$InstallRoot,[Parameter(Mandatory)][string]$PowerShellPath)
    $file=Join-Path $InstallRoot 'vscode-data/User/settings.json'
    $settings=[ordered]@{}
    if(Test-Path -LiteralPath $file){
        $settings=Get-Content -LiteralPath $file -Raw | ConvertFrom-Json -AsHashtable -NoEnumerate
        if($settings -isnot [Collections.IDictionary]){throw 'The managed VS Code profile settings.json must contain a JSON object.'}
    }
    $managed=[ordered]@{
        'telemetry.telemetryLevel'='off'
        'extensions.autoUpdate'=$false
        'chat.disableAIFeatures'=$true
        'terminal.integrated.defaultProfile.windows'='LoKiEnte PowerShell'
        'kilo-code.new.autocomplete.enableAutoTrigger'=$false
        'kilo-code.new.autocomplete.enableSmartInlineTaskKeybinding'=$false
        'kilo-code.new.autocomplete.enableChatAutocomplete'=$false
    }
    foreach($key in $managed.Keys){$settings[$key]=$managed[$key]}
    $profiles='terminal.integrated.profiles.windows'
    if(-not $settings.Contains($profiles) -or $settings[$profiles] -isnot [Collections.IDictionary]){
        $settings[$profiles]=[ordered]@{}
    }
    if($settings[$profiles].Contains('Shadow PowerShell')){
        $legacy=$settings[$profiles]['Shadow PowerShell']
        if($legacy -is [Collections.IDictionary] -and $legacy.Count -eq 2 -and
           $legacy.Contains('path') -and $legacy.Contains('args') -and $legacy.path -ieq $PowerShellPath -and
           @($legacy.args).Count -eq 1 -and @($legacy.args)[0] -ceq '-NoLogo'){
            $settings[$profiles].Remove('Shadow PowerShell')
        }
    }
    $settings[$profiles]['LoKiEnte PowerShell']=[ordered]@{path=$PowerShellPath;args=@('-NoLogo')}
    Merge-ShadowSyncExclusions -Settings $settings -Key 'settingsSync.ignoredSettings' -Required (@($managed.Keys)+@($profiles,'lokiente.startup.openKilo','github.copilot.enable'))
    Merge-ShadowSyncExclusions -Settings $settings -Key 'settingsSync.ignoredExtensions' -Required @('github.copilot','github.copilot-chat','kilocode.kilo-code','lokiente.managed-startup')
    $null=Write-ShadowManagedFile -Path $file -Content ($settings|ConvertTo-Json -Depth 100) -BackupRoot (Join-Path $InstallRoot 'backups/vscode-settings')
}

function New-ShadowVsCodeStartupVsix {
    param([Parameter(Mandatory)][string]$InstallRoot)
    $source=Join-Path $PSScriptRoot 'vscode-startup'
    $manifest=Get-Content -LiteralPath (Join-Path $source 'package.json') -Raw | ConvertFrom-Json
    $path=Join-Path $InstallRoot ("tooling/lokiente-managed-startup-$($manifest.version).vsix")
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $path))
    $temporary=$path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
    try{
        $stream=[IO.File]::Open($temporary,[IO.FileMode]::CreateNew)
        try{
            $zip=[IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Create,$true)
            try{
                $entries=[ordered]@{
                    '[Content_Types].xml'=(Join-Path $source '[Content_Types].xml')
                    'extension.vsixmanifest'=(Join-Path $source 'extension.vsixmanifest')
                    'extension/package.json'=(Join-Path $source 'package.json')
                    'extension/security-view.cjs'=(Join-Path $source 'security-view.cjs')
                    'extension/lokiente.png'=(Join-Path $source 'lokiente.png')
                    'extension/extension.cjs'=(Join-Path $source 'extension.cjs')
                    'extension/sync-guide.cjs'=(Join-Path $source 'sync-guide.cjs')
                    'extension/LICENSE.txt'=(Join-Path $PSScriptRoot 'LICENSE.txt')
                }
                foreach($name in $entries.Keys){
                    $entry=$zip.CreateEntry($name)
                    $entryStream=$entry.Open()
                    try{$bytes=[IO.File]::ReadAllBytes($entries[$name]);$entryStream.Write($bytes,0,$bytes.Length)}finally{$entryStream.Dispose()}
                }
            }finally{$zip.Dispose()}
        }finally{$stream.Dispose()}
        [IO.File]::Move($temporary,$path,$true)
    }finally{if(Test-Path -LiteralPath $temporary){Remove-Item -LiteralPath $temporary -Force}}
    return $path
}

function Install-ShadowVsCodeStartup {
    param([Parameter(Mandatory)][string]$CodePath,[Parameter(Mandatory)][string]$InstallRoot)
    $vsix=New-ShadowVsCodeStartupVsix -InstallRoot $InstallRoot
    $manifest=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'vscode-startup/package.json') -Raw | ConvertFrom-Json
    $arguments=@('--user-data-dir',(Join-Path $InstallRoot 'vscode-data'),'--extensions-dir',(Join-Path $InstallRoot 'vscode-extensions'),'--telemetry-level','off')
    $null=Invoke-ShadowCodeCli -CodePath $CodePath -Arguments ($arguments+@('--install-extension',$vsix,'--force'))
    $result=Invoke-ShadowCodeCli -CodePath $CodePath -Arguments ($arguments+@('--list-extensions','--show-versions'))
    if(@($result.StdOut -split '\r?\n' | Where-Object {$_ -ceq "lokiente.managed-startup@$($manifest.version)"}).Count -ne 1){
        throw 'LoKiEnte startup extension was not verified in the managed VS Code environment.'
    }
}
