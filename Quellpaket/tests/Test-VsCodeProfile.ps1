#requires -Version 7.4
param([string]$SourceRoot=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
. (Join-Path $SourceRoot 'Common.ps1')
. (Join-Path $SourceRoot 'VsCodeProfile.ps1')
$root=Join-Path ([IO.Path]::GetTempPath()) ('lokiente-profile-'+[guid]::NewGuid().ToString('N'))
$checks=0
function Assert-Profile([bool]$Value,[string]$Message){if(-not $Value){throw $Message};$script:checks++}
try{
    $managed=Join-Path $root 'managed install'
    $file=Join-Path $managed 'vscode-data/User/settings.json'
    $personal=Join-Path $root 'personal/settings.json'
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $personal))
    [IO.File]::WriteAllText($personal,'{"chat.disableAIFeatures":false,"editor.fontSize":19}')
    $personalHash=(Get-FileHash -LiteralPath $personal).Hash
    Update-ShadowVsCodeProfile -InstallRoot $managed -PowerShellPath 'test-pwsh.exe'
    $settings=Get-Content -LiteralPath $file -Raw|ConvertFrom-Json -AsHashtable
    Assert-Profile ($settings['chat.disableAIFeatures'] -eq $true) 'Fresh profile must hide built-in AI'
    Assert-Profile ($settings['settingsSync.ignoredExtensions'].Count -eq 4) 'Fresh profile must isolate Kilo, startup helper and both Copilot extensions'
    Assert-Profile ($settings['settingsSync.ignoredSettings'] -contains 'terminal.integrated.profiles.windows') 'Terminal paths must stay local'
    Assert-Profile ($settings['settingsSync.ignoredSettings'] -contains 'chat.disableAIFeatures') 'AI policy must not affect other synced devices'
    Assert-Profile (-not $settings.Contains('workbench.colorTheme')) 'Provisioning must not choose a personal theme'
    $settings['workbench.colorTheme']='Quiet Light'
    $settings['[typescript]']=@{'editor.defaultFormatter'='example.formatter'}
    $settings['lokiente.startup.openKilo']=$false
    $settings['chat.disableAIFeatures']=$false
    $settings['settingsSync.ignoredSettings']=@('CHAT.DISABLEAIFEATURES','editor.fontSize','-chat.disableAIFeatures','-terminal.integrated.profiles.windows','-custom.machine.setting')
    $settings['settingsSync.ignoredExtensions']=@('custom.extension','GitHub.Copilot','-github.copilot-chat','-kilocode.kilo-code')
    $before=$settings|ConvertTo-Json -Depth 100
    [IO.File]::WriteAllText($file,$before)
    Update-ShadowVsCodeProfile -InstallRoot $managed -PowerShellPath 'updated-pwsh.exe'
    $settings=Get-Content -LiteralPath $file -Raw|ConvertFrom-Json -AsHashtable
    Assert-Profile ($settings['workbench.colorTheme'] -ceq 'Quiet Light' -and $settings['[typescript]']['editor.defaultFormatter'] -ceq 'example.formatter') 'Personal settings must survive upgrades'
    Assert-Profile ($settings['lokiente.startup.openKilo'] -eq $false) 'Explicit startup opt-out must survive upgrades'
    Assert-Profile ($settings['terminal.integrated.profiles.windows']['LoKiEnte PowerShell'].path -ceq 'updated-pwsh.exe') 'Managed terminal must follow the approved PowerShell path'
    Assert-Profile ($settings['settingsSync.ignoredSettings'] -contains 'editor.fontSize' -and $settings['settingsSync.ignoredSettings'] -contains '-custom.machine.setting') 'Custom sync exclusions and unrelated opt-ins must survive'
    Assert-Profile ($settings['settingsSync.ignoredSettings'] -ccontains 'chat.disableAIFeatures') 'Incorrectly cased personal entries must not shadow required settings exclusions'
    Assert-Profile ($settings['settingsSync.ignoredSettings'] -notcontains '-chat.disableAIFeatures' -and $settings['settingsSync.ignoredSettings'] -notcontains '-terminal.integrated.profiles.windows') 'Managed settings must not be opted back into sync'
    Assert-Profile ($settings['settingsSync.ignoredExtensions'] -contains 'custom.extension' -and $settings['settingsSync.ignoredExtensions'] -notcontains '-kilocode.kilo-code' -and $settings['settingsSync.ignoredExtensions'] -notcontains '-github.copilot-chat') 'Custom extension exclusions must survive while managed opt-ins are removed'
    Assert-Profile (@($settings['settingsSync.ignoredExtensions']|Where-Object {$_ -ieq 'github.copilot'}).Count -eq 1) 'Extension exclusions must be case-insensitively unique'
    $hash=(Get-FileHash -LiteralPath $file).Hash
    $backups=@(Get-ChildItem -LiteralPath (Join-Path $managed 'backups/vscode-settings') -File)
    Assert-Profile (@($backups|Where-Object {[IO.File]::ReadAllText($_.FullName) -ceq $before}).Count -eq 1) 'Prior profile must be backed up'
    Update-ShadowVsCodeProfile -InstallRoot $managed -PowerShellPath 'updated-pwsh.exe'
    Assert-Profile ((Get-FileHash -LiteralPath $file).Hash -ceq $hash -and @(Get-ChildItem -LiteralPath (Join-Path $managed 'backups/vscode-settings') -File).Count -eq $backups.Count) 'Repeated provisioning must not rewrite or back up an unchanged profile'
    foreach($invalid in @('{"settingsSync.ignoredSettings":"wrong"}','{"settingsSync.ignoredExtensions":[1]}','[1,2]','{"broken":')){
        [IO.File]::WriteAllText($file,$invalid)
        $failed=$false
        try{Update-ShadowVsCodeProfile -InstallRoot $managed -PowerShellPath 'test.exe'}catch{$failed=$true}
        Assert-Profile ($failed -and [IO.File]::ReadAllText($file) -ceq $invalid) 'Invalid settings must fail without overwriting the file'
    }
    Assert-Profile ((Get-FileHash -LiteralPath $personal).Hash -ceq $personalHash) 'Personal profile must remain byte-identical'
    $vsix=New-ShadowVsCodeStartupVsix -InstallRoot $managed
    $archive=[IO.Compression.ZipFile]::OpenRead($vsix)
    try{
        Assert-Profile ($archive.Entries.Count -eq 5) 'VSIX must contain only the expected source and metadata files'
        foreach($entryName in @('extension/extension.cjs','extension/package.json','extension/LICENSE.txt')){
            $entry=$archive.GetEntry($entryName)
            $reader=[IO.StreamReader]::new($entry.Open())
            try{$actual=$reader.ReadToEnd()}finally{$reader.Dispose()}
            $source=if($entryName -eq 'extension/LICENSE.txt'){Join-Path $SourceRoot 'LICENSE.txt'}else{Join-Path $SourceRoot ('vscode-startup/'+$entryName.Substring(10))}
            Assert-Profile ($actual -ceq [IO.File]::ReadAllText($source)) "VSIX entry must match source: $entryName"
        }
        $reader=[IO.StreamReader]::new($archive.GetEntry('extension.vsixmanifest').Open())
        try{$xml=[xml]$reader.ReadToEnd()}finally{$reader.Dispose()}
        $package=Get-Content -LiteralPath (Join-Path $SourceRoot 'vscode-startup/package.json') -Raw|ConvertFrom-Json
        Assert-Profile ($xml.PackageManifest.Metadata.Identity.Version -ceq $package.version) 'VSIX metadata and package version must agree'
    }finally{$archive.Dispose()}
    $script:calls=@();$script:reportedVersion=$package.version
    function Invoke-ShadowCodeCli {
        param($CodePath,$Arguments)
        $script:calls+=,@($Arguments)
        return @{StdOut="lokiente.managed-startup@$script:reportedVersion"}
    }
    Install-ShadowVsCodeStartup -CodePath 'code.exe' -InstallRoot $managed
    Assert-Profile ($calls.Count -eq 2 -and $calls[0] -contains '--install-extension' -and $calls[0] -contains $vsix -and $calls[1] -contains '--list-extensions') 'Provisioning must install and verify the local VSIX'
    foreach($call in $calls){Assert-Profile ($call -contains (Join-Path $managed 'vscode-data') -and $call -contains (Join-Path $managed 'vscode-extensions')) 'Extension installation must use isolated directories'}
    $script:reportedVersion='0.0.0';$failed=$false
    try{Install-ShadowVsCodeStartup -CodePath 'code.exe' -InstallRoot $managed}catch{$failed=$true}
    Assert-Profile $failed 'Unverified startup extension version must fail provisioning'
    @{suite='Managed VS Code profile and startup package';checks=$checks;passed=$true}|ConvertTo-Json
}finally{
    $resolved=[IO.Path]::GetFullPath($root)
    if(-not $resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notlike 'lokiente-profile-*'){throw 'Unsafe cleanup'}
    if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
