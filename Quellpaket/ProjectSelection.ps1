#requires -Version 7.4
# Project selection, controlled Git clones and registration repair. No model actions.
function Resolve-ShadowProjectDirectory {
    param([Parameter(Mandatory)][string]$Path)
    $candidate=$Path.Trim()
    if($candidate.Length -ge 2 -and
       (($candidate.StartsWith('"') -and $candidate.EndsWith('"')) -or
        ($candidate.StartsWith("'") -and $candidate.EndsWith("'")))){
        $candidate=$candidate.Substring(1,$candidate.Length-2)
    }
    if([string]::IsNullOrWhiteSpace($candidate)){throw 'Please specify an existing project directory.'}
    $resolved=Resolve-Path -LiteralPath $candidate -ErrorAction Stop
    if($resolved.Provider.Name -cne 'FileSystem' -or -not(Test-Path -LiteralPath $resolved.ProviderPath -PathType Container)){
        throw 'The project must be an existing filesystem directory.'
    }
    return $resolved.ProviderPath
}

function Select-ShadowProject {
    param([Parameter(Mandatory)][string]$InstallRoot,[string]$ProjectPath,[switch]$Desktop)
    if(-not [string]::IsNullOrWhiteSpace($ProjectPath)){
        return Resolve-ShadowProjectDirectory -Path $ProjectPath
    }
    $projects=[Collections.Generic.List[string]]::new()
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $index=Join-Path $InstallRoot 'workspaces.json'
    if(Test-Path -LiteralPath $index){
        try {
            $entries=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($index)) -AsHashtable -NoEnumerate -ErrorAction Stop
            if($entries -isnot [array]){throw 'Expected a list of projects.'}
            foreach($entry in $entries){
                if($entry -isnot [Collections.IDictionary] -or -not $entry.Contains('project') -or
                   $entry.project -isnot [string] -or [string]::IsNullOrWhiteSpace($entry.project)){
                    throw 'A project entry has no valid project path.'
                }
                if($seen.Add($entry.project)){$projects.Add($entry.project)}
            }
        } catch {
            throw "Project list unreadable: $index. File remains unchanged. $($_.Exception.Message)"
        }
    }
    if($Desktop){return Select-ShadowDesktopProject -InstallRoot $InstallRoot -Projects $projects.ToArray()}
    while($true){
        Write-Host ''
        Write-Host 'LoKiEnte - select a project'
        for($i=0;$i -lt $projects.Count;$i++){
            $missing=if(Test-Path -LiteralPath $projects[$i] -PathType Container){''}else{' [unavailable]'}
            Write-Host "$($i+1): $($projects[$i])$missing"
        }
        if(-not $projects.Count){Write-Host 'No projects registered yet.'}
        Write-Host 'N: Open another project directory (enter path)'
        Write-Host '0: Cancel'
        $choice=(Read-Host 'Selection').Trim()
        if($choice -eq '0'){return $null}
        if($choice -ieq 'N'){
            $candidate=Read-Host 'Existing project directory (empty input to go back)'
            if([string]::IsNullOrWhiteSpace($candidate)){continue}
        }else{
            $number=0
            if(-not [int]::TryParse($choice,[ref]$number) -or $number -lt 1 -or $number -gt $projects.Count){
                Write-Host 'Enter a displayed number, N or 0.'
                continue
            }
            $candidate=$projects[$number-1]
        }
        try { return Resolve-ShadowProjectDirectory -Path $candidate }
        catch { Write-Host "Cannot open directory: $($_.Exception.Message)" }
    }
}

function Select-ShadowDesktopProject {
    param([string]$InstallRoot,[string[]]$Projects)
    Add-Type -AssemblyName System.Windows.Forms
    $form=[Windows.Forms.Form]::new();$form.Text='LoKiEnte - select a project';$form.Width=820;$form.Height=290;$form.StartPosition='CenterScreen';$form.FormBorderStyle='FixedDialog';$form.MaximizeBox=$false;$form.MinimizeBox=$false
    $label=[Windows.Forms.Label]::new();$label.Text='Open a registered project, find Git repositories, clone a repository or repair a moved path.';$label.SetBounds(18,16,770,30)
    $list=[Windows.Forms.ComboBox]::new();$list.DropDownStyle='DropDownList';$list.SetBounds(18,55,710,30)
    $list.Width=770;$list.DisplayMember='label'
    foreach($project in $Projects){[void]$list.Items.Add([pscustomobject]@{path=$project;label=$(if(Test-Path -LiteralPath $project -PathType Container){$project}else{'[missing] '+$project});registered=$true})}
    if($list.Items.Count){$list.SelectedIndex=0}
    $open=[Windows.Forms.Button]::new();$open.Text='Open project';$open.SetBounds(18,112,125,32);$open.Enabled=$list.Items.Count -gt 0
    $browse=[Windows.Forms.Button]::new();$browse.Text='Browse folder';$browse.SetBounds(153,112,125,32)
    $find=[Windows.Forms.Button]::new();$find.Text='Find Git projects';$find.SetBounds(288,112,145,32)
    $clone=[Windows.Forms.Button]::new();$clone.Text='Clone repository';$clone.SetBounds(443,112,145,32)
    $repair=[Windows.Forms.Button]::new();$repair.Text='Repair path';$repair.SetBounds(598,112,125,32)
    $status=[Windows.Forms.Label]::new();$status.SetBounds(18,160,770,30);$status.Text='[missing] entries remain registered until you repair their location.'
    $cancel=[Windows.Forms.Button]::new();$cancel.Text='Cancel';$cancel.SetBounds(668,202,120,32);$cancel.DialogResult='Cancel'
    $open.Add_Click({try{$form.Tag=Resolve-ShadowProjectDirectory ([string]$list.SelectedItem.path);$form.DialogResult='OK';$form.Close()}catch{[void][Windows.Forms.MessageBox]::Show($_.Exception.Message+' Use Repair path to reconnect a moved project.','LoKiEnte','OK','Error')}})
    $browse.Add_Click({$picker=[Windows.Forms.FolderBrowserDialog]::new();$picker.Description='Select an existing project directory';try{if($picker.ShowDialog() -eq 'OK'){$form.Tag=Resolve-ShadowProjectDirectory $picker.SelectedPath;$form.DialogResult='OK';$form.Close()}}finally{$picker.Dispose()}})
    $find.Add_Click({$picker=[Windows.Forms.FolderBrowserDialog]::new();$picker.Description='Search this directory for Git repositories';try{if($picker.ShowDialog() -eq 'OK'){$found=Find-ShadowGitProjects -Path $picker.SelectedPath;foreach($path in $found.Projects){if(-not @($list.Items|Where-Object {$_.path -ieq $path}).Count){[void]$list.Items.Add([pscustomobject]@{path=$path;label='[Git] '+$path;registered=$false})}};if($list.Items.Count -and $list.SelectedIndex -lt 0){$list.SelectedIndex=0};$open.Enabled=$list.Items.Count -gt 0;$status.Text="Found $($found.Projects.Count) Git repositories; scanned $($found.ScannedDirectories) directories. Limit reached: $($found.LimitReached)."}}catch{[void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'Git project search','OK','Error')}finally{$picker.Dispose()}})
    $clone.Add_Click({
        $request=Show-ShadowCloneDialog
        if($null -eq $request){return}
        try{
            $form.ControlBox=$false;foreach($button in @($open,$browse,$find,$clone,$repair,$cancel)){$button.Enabled=$false};$status.Text='Cloning repository. Authentication may open the Git credential manager.';$form.Refresh()
            $form.Tag=New-ShadowGitClone -InstallRoot $InstallRoot -Repository $request.repository -Destination $request.destination -ProgressCallback {[Windows.Forms.Application]::DoEvents()}
            $form.DialogResult='OK';$form.Close()
        }catch{$status.Text='Clone failed; existing directories were preserved.';Write-ShadowToolchainEvent -Component 'Projects' -Level ERROR -Message $_.Exception.Message;[void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'Git clone','OK','Error')}
        finally{$form.ControlBox=$true;foreach($button in @($browse,$find,$clone,$cancel)){$button.Enabled=$true};$open.Enabled=$list.Items.Count -gt 0;$repair.Enabled=$null -ne $list.SelectedItem -and $list.SelectedItem.registered}
    })
    $repair.Add_Click({
        if($null -eq $list.SelectedItem -or -not $list.SelectedItem.registered){return}
        $picker=[Windows.Forms.FolderBrowserDialog]::new();$picker.Description='Locate the moved project. Existing LoKiEnte tasks and checks are retained.'
        try{if($picker.ShowDialog() -eq 'OK'){$chain=Get-Content -LiteralPath (Join-Path $InstallRoot 'toolchain.json') -Raw|ConvertFrom-Json;$target=Repair-ShadowProjectRegistration -Root $InstallRoot -OldPath $list.SelectedItem.path -NewPath $picker.SelectedPath -PwshPath $chain.powerShellExecutable;$list.SelectedItem.path=$target;$list.SelectedItem.label=$target;$list.Refresh();$status.Text='Project path repaired; task and checks retained. Select Open project.'}}
        catch{Write-ShadowToolchainEvent -Component 'Projects' -Level ERROR -Message $_.Exception.Message;[void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'Repair project path','OK','Error')}finally{$picker.Dispose()}
    })
    $list.Add_SelectedIndexChanged({$repair.Enabled=$null -ne $list.SelectedItem -and $list.SelectedItem.registered})
    $repair.Enabled=$null -ne $list.SelectedItem -and $list.SelectedItem.registered
    $form.Controls.AddRange(@($label,$list,$open,$browse,$find,$clone,$repair,$status,$cancel));$form.AcceptButton=$open;$form.CancelButton=$cancel
    try{if($form.ShowDialog() -eq 'OK'){return [string]$form.Tag};return $null}finally{$form.Dispose()}
}

function Find-ShadowGitProjects {
    param([string]$Path,[ValidateRange(0,15)][int]$MaxDepth=5,[ValidateRange(1,50000)][int]$MaxDirectories=5000)
    $root=Resolve-ShadowProjectDirectory $Path;$queue=[Collections.Generic.Queue[object]]::new();$queue.Enqueue(@{path=$root;depth=0});$found=[Collections.Generic.List[string]]::new();$scanned=0
    while($queue.Count -and $scanned -lt $MaxDirectories){
        $item=$queue.Dequeue();$scanned++
        if(Test-Path -LiteralPath (Join-Path $item.path '.git')){$found.Add($item.path)}
        if($item.depth -ge $MaxDepth){continue}
        foreach($child in Get-ChildItem -LiteralPath $item.path -Directory -Force -ErrorAction SilentlyContinue){
            if($child.Attributes -band [IO.FileAttributes]::ReparsePoint -or $child.Name -in @('.git','node_modules','.vs','.venv','vendor','target','dist','build')){continue}
            $queue.Enqueue(@{path=$child.FullName;depth=$item.depth+1})
        }
    }
    return @{Projects=$found.ToArray();ScannedDirectories=$scanned;LimitReached=($queue.Count -gt 0)}
}

function New-ShadowGitClone {
    param([string]$InstallRoot,[string]$Repository,[string]$Destination,[scriptblock]$ProgressCallback)
    $Repository=$Repository.Trim()
    $local=Test-Path -LiteralPath $Repository -PathType Container -ErrorAction SilentlyContinue
    if($local){$Repository=[IO.Path]::GetFullPath($Repository).Replace('\','/')}
    if(-not $local -and $Repository -notmatch '^git@[A-Za-z0-9.-]+:[A-Za-z0-9._~/-]+$'){
        $uri=$null
        if(-not [Uri]::TryCreate($Repository,[UriKind]::Absolute,[ref]$uri) -or $uri.Scheme -notin @('https','ssh') -or $uri.Query -or $uri.Fragment -or ($uri.UserInfo -and -not($uri.Scheme -eq 'ssh' -and $uri.UserInfo -eq 'git'))){throw 'Use an HTTPS/SSH Git URL without embedded credentials, or an existing local repository directory.'}
    }
    $target=[IO.Path]::GetFullPath($Destination)
    if(Test-Path -LiteralPath $target){throw 'Clone target already exists. Choose a new directory; existing files are never overwritten.'}
    $parent=Split-Path -Parent $target
    if(-not(Test-Path -LiteralPath $parent -PathType Container)){throw 'Choose an existing parent directory for the clone.'}
    $git=$null;$chainPath=Join-Path $InstallRoot 'toolchain.json'
    if(Test-Path -LiteralPath $chainPath){$chain=Get-Content -LiteralPath $chainPath -Raw|ConvertFrom-Json -AsHashtable;if($chain.Contains('gitExecutable')){$git=$chain.gitExecutable}}
    if(-not $git){$git=(Get-Command git -CommandType Application -ErrorAction Stop|Select-Object -First 1).Source}
    $hooks=Join-Path $InstallRoot ('runtime/clone-hooks-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($hooks)
    try{
        $arguments=@('-c',('core.hooksPath='+$hooks),'clone')
        if($local){$arguments+=@('--local','--no-hardlinks')}
        $null=Invoke-ShadowNative -FilePath $git -ArgumentList ($arguments+@('--',$Repository,$target)) -WorkingDirectory $parent -Environment @{GIT_TERMINAL_PROMPT='0';GIT_TRACE='';GIT_TRACE_CURL=''} -ProgressCallback $ProgressCallback -Quiet -TimeoutSeconds 1800
        $verified=Invoke-ShadowNative -FilePath $git -ArgumentList @('-C',$target,'rev-parse','--show-toplevel') -Quiet -TimeoutSeconds 30
        $project=Resolve-ShadowProjectDirectory $verified.StdOut.Trim()
        Write-ShadowToolchainEvent -Component 'Projects' -Message "Git repository cloned and verified: $project"
        return $project
    }finally{if(Test-Path -LiteralPath $hooks){Remove-Item -LiteralPath $hooks -ErrorAction SilentlyContinue}}
}

function Show-ShadowCloneDialog {
    Add-Type -AssemblyName System.Windows.Forms
    $form=[Windows.Forms.Form]::new();$form.Text='LoKiEnte - clone Git repository';$form.Width=760;$form.Height=260;$form.StartPosition='CenterParent';$form.FormBorderStyle='FixedDialog';$form.MaximizeBox=$false;$form.MinimizeBox=$false
    $urlLabel=[Windows.Forms.Label]::new();$urlLabel.Text='Repository URL (HTTPS or SSH; no password/token in the URL)';$urlLabel.SetBounds(16,16,710,24)
    $url=[Windows.Forms.TextBox]::new();$url.SetBounds(16,44,710,28)
    $pathLabel=[Windows.Forms.Label]::new();$pathLabel.Text='Clone into a new directory';$pathLabel.SetBounds(16,84,710,24)
    $destination=[Windows.Forms.TextBox]::new();$destination.SetBounds(16,112,560,28)
    $browse=[Windows.Forms.Button]::new();$browse.Text='Choose parent';$browse.SetBounds(586,110,140,30)
    $browse.Add_Click({$picker=[Windows.Forms.FolderBrowserDialog]::new();try{if($picker.ShowDialog() -eq 'OK'){$name=($url.Text.TrimEnd('/') -split '[/:]')[-1] -replace '\.git$','';$name=$name -replace '[^a-zA-Z0-9._-]','_';if(-not $name){$name='repository'};$destination.Text=Join-Path $picker.SelectedPath $name}}finally{$picker.Dispose()}})
    $ok=[Windows.Forms.Button]::new();$ok.Text='Clone';$ok.SetBounds(456,166,125,32)
    $ok.Add_Click({if([string]::IsNullOrWhiteSpace($url.Text) -or [string]::IsNullOrWhiteSpace($destination.Text)){return};$form.Tag=@{repository=$url.Text;destination=$destination.Text};$form.DialogResult='OK';$form.Close()})
    $cancel=[Windows.Forms.Button]::new();$cancel.Text='Cancel';$cancel.DialogResult='Cancel';$cancel.SetBounds(596,166,130,32)
    $form.Controls.AddRange(@($urlLabel,$url,$pathLabel,$destination,$browse,$ok,$cancel));$form.AcceptButton=$ok;$form.CancelButton=$cancel
    try{if($form.ShowDialog() -eq 'OK'){return $form.Tag};return $null}finally{$form.Dispose()}
}

function Test-ShadowGitCloneReadiness {
    param([string]$InstallRoot,[string]$WorkingDirectory,[string]$GitPath)
    $directory=Join-Path $WorkingDirectory ('git-acceptance-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($directory)
    $origin=Join-Path $directory 'source.git'
    $null=Invoke-ShadowNative -FilePath $GitPath -ArgumentList @('init','--bare',$origin) -Quiet -TimeoutSeconds 30
    $target=New-ShadowGitClone -InstallRoot $InstallRoot -Repository $origin -Destination (Join-Path $directory 'clone')
    if(-not(Test-Path -LiteralPath (Join-Path $target '.git'))){throw 'Native Git clone did not produce a verifiable repository.'}
}
