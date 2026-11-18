#requires -Version 7.4
Set-StrictMode -Version Latest

function Get-ShadowEmbeddingDefinition {
    return @{
        Id='nomic-embed-text-v15-q4';Name='Nomic Embed Text v1.5 Q4_K_M'
        ModelType='embedding';Repository='nomic-ai/nomic-embed-text-v1.5-GGUF'
        Revision='0188c9bf409793f810680a5a431e7b899c46104c'
        ExpectedPath='nomic-ai/nomic-embed-text-v1.5-GGUF/nomic-embed-text-v1.5.Q4_K_M.gguf'
        Files=@(@{Name='nomic-embed-text-v1.5.Q4_K_M.gguf';Size=84106624;Sha256='d4e388894e09cf3816e8b0896d81d265b55e7a9fff9ab03fe8bf4ef5e11295ac'})
    }
}

function Get-ShadowModelCatalog {
    $models=@(
        @{Id='qwen35-9b';Name='Qwen3.5-9B Q4_K_M';Repository='lmstudio-community/Qwen3.5-9B-GGUF';Revision='1379f25c6b505a3fc737bd7818cb09389cf807c1';Files=@(
            @{Name='Qwen3.5-9B-Q4_K_M.gguf';Size=5627044256;Sha256='cd76ec205963b3b33350093e6904d9de16c4e666fd104e1f632d25c7f15f2a13'},
            @{Name='mmproj-Qwen3.5-9B-BF16.gguf';Size=921704480;Sha256='330d17547bfdbcd0e7a0cb3f4b06b4ceeac0aaa1e449122d9d66ef957aeb74b3'}
        )},
        @{Id='qwen3-14b';Name='Qwen3-14B Q4_K_M';Repository='lmstudio-community/Qwen3-14B-GGUF';Revision='0e50c01ee999871cc2b0021a02bbd9ee3379507a';Files=@(
            @{Name='Qwen3-14B-Q4_K_M.gguf';Size=9001753376;Sha256='712c0791d5124d3dd6d1e4968de1201207afeae49c6e10fbeb9c58fe00c58555'}
        )},
        @{Id='gpt-oss-20b';Name='gpt-oss-20b MXFP4';Repository='lmstudio-community/gpt-oss-20b-GGUF';Revision='21f8a86825e36be34d24601e6d5ab45e2d366f4b';Files=@(
            @{Name='gpt-oss-20b-MXFP4.gguf';Size=12109565632;Sha256='65d06d31a3977d553cb3af137b5c26b5f1e9297a6aaa29ae7caa98788cde53ab'}
        )},
        @{Id='qwen38-27b';Name='Qwen3.8-27B Q4_K_M';Repository='lmstudio-community/Qwen3.8-27B-GGUF';Revision='5a7da681f60570ab5b439a587e912d2e5eddb582';Files=@(
            @{Name='Qwen3.8-27B-Q4_K_M.gguf';Size=16810714336;Sha256='e00082f779fa385cee8c68a3ec8833a75778cc87272240b942f74e0b8243e520'},
            @{Name='mmproj-Qwen3.8-27B-BF16.gguf';Size=931145856;Sha256='97ba9d70e7407f08c880def231fd360a312c76d0053387733f10dcf6affd75a1'}
        )},
        @{Id='qwen35-4b';Name='Qwen3.5-4B Q4_K_M';Repository='lmstudio-community/Qwen3.5-4B-GGUF';Revision='f9f88ac3e234be915e23811a6d28ea287bdb927e';Files=@(
            @{Name='Qwen3.5-4B-Q4_K_M.gguf';Size=2707513696;Sha256='25082a7dd3776cc3c741c6347d3bd04523f05796607b3fbc32fa3a25dfa1418c'},
            @{Name='mmproj-Qwen3.5-4B-BF16.gguf';Size=675568768;Sha256='ae08d9d7eceb8f2d0672d61b5e6aa78b611f2942b55ed71d21414980cc454b91'}
        )}
    )
    foreach($model in $models){
        $model.ExpectedPath=$model.Repository+'/'+$model.Files[0].Name
        $model.DownloadUrl='https://huggingface.co/'+$model.Repository+'/blob/main/'+$model.Files[0].Name
        $totalBytes=[long]0
        foreach($file in $model.Files){$totalBytes+=[long]$file.Size}
        $model.Bytes=$totalBytes
        $model.Interleaved=if($model.Id -ceq 'gpt-oss-20b'){'reasoning'}else{'reasoning_content'}
        $model
    }

    
}

function Get-ShadowModelRanking {
    param([string]$Role)
    switch($Role){
        'coder' {@('qwen38-27b','qwen3-14b','qwen35-9b','qwen35-4b','gpt-oss-20b')}
        'coder-high' {@('qwen38-27b','qwen3-14b','qwen35-9b','qwen35-4b','gpt-oss-20b')}
        'coder-fast' {@('qwen35-9b','qwen3-14b','qwen35-4b','gpt-oss-20b','qwen38-27b')}
        'review' {@('gpt-oss-20b','qwen3-14b','qwen35-9b','qwen35-4b','qwen38-27b')}
        'fast' {@('qwen35-9b','qwen35-4b','qwen3-14b','gpt-oss-20b','qwen38-27b')}
        default {throw "Unbekannte Modellrolle: $Role"}
    }
}

function Get-ShadowRecommendedModel {
    param([string]$Role,[object[]]$Catalog,$Hardware,[switch]$AllowPartialGpuOffload)
    $ranking=@(Get-ShadowModelRanking -Role $Role)
    foreach($id in $ranking){
        $candidate=@($Catalog|Where-Object {$_.Id -ceq $id})
        if($candidate.Count -ne 1){throw "Modellkatalog ist unvollstaendig: $id"}
        $gpuBytes=if($AllowPartialGpuOffload){$candidate[0].Bytes*0.8}else{$candidate[0].Bytes}
        if($candidate[0].Bytes+6GB -le $Hardware.FreeRamBytes -and $gpuBytes+4GB -le $Hardware.Gpu.FreeBytes){
            return $candidate[0]
        }
    }
    return $null
}

function Select-ShadowModels {
        param([Parameter(Mandatory)]$Hardware,[object[]]$Downloaded,[object[]]$PreviousProfiles,[switch]$IncludeFastModel,[switch]$Single,[switch]$AllowPartialGpuOffload,[string]$PreferredId)
        $catalog=@(Get-ShadowModelCatalog)
        $roles=if($Single){@('coder')}else{@('coder-high','coder-fast','review')}
        if(-not $Single -and $IncludeFastModel){$roles+=@('fast')}
        $chosen=[Collections.Generic.List[object]]::new()
        Write-Host "`nMODELLAUSWAHL - geschaetzte Empfehlung, keine Leistungs- oder Speicherfit-Garantie"
        Write-Host ("Frei: VRAM {0:N1} GiB; RAM {1:N1} GiB. Nur ein Coding-/Reviewmodell wird gleichzeitig geladen." -f ($Hardware.Gpu.FreeBytes/1GB),($Hardware.FreeRamBytes/1GB))
        if(-not $Single){Write-Host 'Fuer die lokale Indexierung wird zusaetzlich ein kleines CPU-Embeddingmodell geladen.'}
        Write-Host 'Vorhandene Modelle bleiben erhalten. Modelle werden niemals automatisch geloescht.'
        foreach($role in $roles){
            $ranking=@(Get-ShadowModelRanking -Role $role)
            $ordered=@(foreach($id in $ranking){$catalog|Where-Object {$_.Id -ceq $id}})
            $recommendation=Get-ShadowRecommendedModel -Role $role -Catalog $catalog -Hardware $Hardware -AllowPartialGpuOffload:$AllowPartialGpuOffload
            if($Single -and $PreferredId){
                $requested=@($catalog|Where-Object {$_.Id -ceq $PreferredId})
                if($requested.Count -ne 1){throw "Unbekanntes ausdruecklich gewaehltes Modell: $PreferredId"}
                $recommendation=$requested[0]
            }
            $roleDescription=switch($role){
                'coder-high' {'CODER HIGH - anspruchsvolle Entwicklung und Architektur'}
                'coder-fast' {'CODER FAST - schnellere Entwicklung und gezielte Recherche'}
                'review' {'REVIEW - unabhaengige Gegenpruefung und Sicherheit'}
                'fast' {'FAST - optionales kleines Modell fuer einfache Aufgaben'}
                default {'CODER - Einzelmodell'}
            }
            Write-Host "`nRolle: $roleDescription [$role]"
            $previous=@($PreviousProfiles|Where-Object {(Get-LrProperty $_ 'Alias') -ceq $role})
            if(-not $previous.Count -and $role -eq 'coder-high'){
                $previous=@($PreviousProfiles|Where-Object {(Get-LrProperty $_ 'Alias') -ceq 'coder'})
                if($previous.Count){Write-Host '  Uebernahmevorschlag aus dem bisherigen coder-Profil.'}
            }
            if(-not $previous.Count -and $role -eq 'coder-fast'){
                $previous=@($PreviousProfiles|Where-Object {(Get-LrProperty $_ 'Alias') -ceq 'fast'})
                if($previous.Count){Write-Host '  Ausgangsvorschlag aus dem bisherigen fast-Profil; getrennt anpassbar.'}
            }
            if(-not $previous.Count -and $Single){
                $previous=@($PreviousProfiles|Where-Object {(Get-LrProperty $_ 'Alias') -ceq 'coder-high'})
            }
            if($previous.Count -gt 1){throw "Bisherige Rolle $role ist mehrdeutig. Keine automatische Aenderung."}
            if($previous.Count -eq 1){Write-Host "  Bisheriges Profil: $([string](Get-LrProperty $previous[0] 'Name'))"}
            $previousCandidate=$null
            if($previous.Count -eq 1){
                $previousId=[string](Get-LrProperty $previous[0] 'Id')
                $previousPath=[string](Get-LrProperty $previous[0] 'ExpectedPath')
                $previousMatch=@($ordered|Where-Object {($previousId -and $_.Id -ceq $previousId) -or ($previousPath -and $_.ExpectedPath -ieq $previousPath)})
                if($previousMatch.Count -gt 1){throw "Bisheriges Modell fuer $role ist mehrdeutig."}
                if($previousMatch.Count -eq 1){$previousCandidate=$previousMatch[0]}
            }
            for($i=0;$i -lt $ordered.Count;$i++){
                $candidate=$ordered[$i]
                $existing=if(Find-LrModel -Models $Downloaded -Profile $candidate){'vorhanden'}else{'Download ggf. erforderlich'}
                $label=if($recommendation -and $candidate.Id -ceq $recommendation.Id){' EMPFEHLUNG'}else{''}
                if($previousCandidate -and $candidate.Id -ceq $previousCandidate.Id){$label+=' BISHER'}
                Write-Host ("  {0}. {1} ({2:N2} GiB Dateien; {3}){4}" -f ($i+1),$candidate.Name,($candidate.Bytes/1GB),$existing,$label)
            }
            $defaultModel=if($Single -and $PreferredId){$recommendation}elseif($previousCandidate){$previousCandidate}else{$recommendation}
            $default=if($defaultModel){1+([array]::IndexOf($ordered,$defaultModel))}else{0}
            if(-not $default){Write-Host 'Keine Vorauswahl passt zur groben Speicherreserve. Eine bewusste Auswahl ist erforderlich; der echte Fit wird weiterhin geprueft.'}
            $index=0
            while($true){
                $prompt=if($default){"Nummer waehlen oder Enter fuer $default; q bricht ab"}else{'Nummer waehlen; q bricht ab'}
                $choice=Read-Host $prompt
                if($choice -ceq 'q'){throw 'Modellauswahl abgebrochen. Keine Modelldatei geloescht oder heruntergeladen.'}
                if([string]::IsNullOrWhiteSpace($choice)){$index=$default}
                elseif(-not [int]::TryParse($choice,[ref]$index)){Write-Host 'Ungueltige Auswahl.';continue}
                if($index -ge 1 -and $index -le $ordered.Count){break}
                Write-Host 'Ungueltige Auswahl.'
            }

            

            

            

            

            

            
            $item=$ordered[$index-1]
            $chosen.Add(@{Alias=$role;Name=$item.Name;Definition=$item})
        }
        Write-Host "`nGewaehlte Rollen:"
        foreach($item in $chosen){Write-Host "  $($item.Alias): $($item.Name)"}
        Write-Host 'Die Modellauswahl wird spaeter erneut anhand der aktuellen Hardware angeboten.'
        if((Read-Host 'Diese Modellauswahl mit y bestaetigen') -cne 'y'){throw 'Modellauswahl abgebrochen. Keine Modelldatei geloescht oder heruntergeladen.'}
        return $chosen.ToArray()
    }

function Assert-ShadowDirectPath {
                param([Parameter(Mandatory)][string]$Path)
                $current=[IO.Path]::GetFullPath($Path)
                while($current){
                    try{$attributes=[IO.File]::GetAttributes($current)}
                    catch [IO.FileNotFoundException]{$attributes=$null}
                    catch [IO.DirectoryNotFoundException]{$attributes=$null}
                    if($null -ne $attributes -and ($attributes -band [IO.FileAttributes]::ReparsePoint)){
                        throw "Verknuepfung im Modellpfad: $current. Keine Modelldatei wird ueberschrieben."
                    }
                    $parent=[IO.Directory]::GetParent($current)
                    $current=if($parent){$parent.FullName}else{$null}
                }
            }

function Resolve-ShadowModelDirectory {
                $user=[Environment]::GetFolderPath('UserProfile')
                $pointer=Join-Path $user '.lmstudio-home-pointer'
                if(Test-Path -LiteralPath $pointer -PathType Leaf){
                    $homePath=(Get-Content -LiteralPath $pointer -Raw -ErrorAction Stop).Trim()
                    if(-not [IO.Path]::IsPathFullyQualified($homePath) -or -not(Test-Path -LiteralPath $homePath -PathType Container)){
                        throw 'LM-Studio-Home-Verweis ungueltig. Modellverzeichnis bleibt unveraendert.'
                    }
                }elseif(Test-Path -LiteralPath (Join-Path $user '.cache/lm-studio') -PathType Container){
                    $homePath=Join-Path $user '.cache/lm-studio'
                }else{$homePath=Join-Path $user '.lmstudio'}
                $settings=Join-Path $homePath 'settings.json'
                if(Test-Path -LiteralPath $settings -PathType Leaf){
                    try{$data=Get-Content -LiteralPath $settings -Raw -ErrorAction Stop|ConvertFrom-Json -AsHashtable -ErrorAction Stop}
                    catch{throw "LM-Studio-Einstellungen nicht lesbar: $settings. Kein Modell wird abgelegt."}
                    if($data -isnot [Collections.IDictionary] -or -not $data.Contains('downloadsFolder') -or
                       $data.downloadsFolder -isnot [string] -or -not [IO.Path]::IsPathFullyQualified($data.downloadsFolder)){
                        throw 'LM-Studio-Modellverzeichnis ist nicht eindeutig in settings.json hinterlegt. Kein Modell wird abgelegt.'
                    }
                    $root=[IO.Path]::GetFullPath($data.downloadsFolder)
                }else{$root=Join-Path $homePath 'models'}
                if(-not(Test-Path -LiteralPath $root -PathType Container)){throw "LM-Studio-Modellverzeichnis nicht vorhanden: $root"}
                Assert-ShadowDirectPath $root
                return $root
            }

function Test-ShadowModelFile {
                param([string]$Path,[long]$Size,[string]$Sha256)
                if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){return $false}
                Assert-ShadowDirectPath $Path
                if((Get-Item -LiteralPath $Path -Force).Length -ne $Size){return $false}
                return (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash -ieq $Sha256
            }

            function Invoke-ShadowCurl {
                param([string]$FilePath,[string[]]$Arguments)
                & $FilePath @Arguments
                return $LASTEXITCODE
            }

            function Wait-ShadowDownloadFile {
                param([string]$Path)
                while(Test-Path -LiteralPath $Path -PathType Leaf){
                    Assert-ShadowDirectPath $Path
                    try{
                        $handle=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
                        $handle.Dispose()
                        return
                    }catch [IO.IOException]{
                        Write-Host "Eine Teildatei ist noch in Verwendung: $Path. Warte vor dem Wiederanlauf; Strg+C bricht ab."
                        Start-Sleep -Seconds 10
                    }
                }
            }

function Invoke-ShadowModelDownload {
                param([Parameter(Mandatory)]$Model,[Parameter(Mandatory)]$File,[string]$DownloadRoot)
                $directory=Join-Path $DownloadRoot $Model.Id
                Assert-ShadowDirectPath $directory
                [void][IO.Directory]::CreateDirectory($directory)
                $complete=Join-Path $directory $File.Name
                $partial=$complete+'.partial'
                Assert-ShadowDirectPath $complete
                Assert-ShadowDirectPath $partial
                Wait-ShadowDownloadFile -Path $partial
                if(Test-Path -LiteralPath $complete){
                    if(Test-ShadowModelFile -Path $complete -Size $File.Size -Sha256 $File.Sha256){return $complete}
                    throw "Vorhandene Download-Datei stimmt nicht mit dem Katalog ueberein: $complete. Sie bleibt unveraendert."
                }
                if((Test-Path -LiteralPath $partial -PathType Leaf) -and (Get-Item -LiteralPath $partial).Length -gt $File.Size){
                    throw "Teildatei ist groesser als erwartet: $partial. Sie bleibt zur Untersuchung erhalten."
                }
                if((Test-Path -LiteralPath $partial -PathType Leaf) -and (Get-Item -LiteralPath $partial).Length -eq $File.Size){
                    if(Test-ShadowModelFile -Path $partial -Size $File.Size -Sha256 $File.Sha256){
                        [IO.File]::Move($partial,$complete)
                        return $complete
                    }
                    throw "Vollstaendige Teildatei hat einen falschen Hash: $partial. Sie bleibt erhalten; bitte vor einem erneuten Download pruefen."
                }
                $curl=Resolve-ShadowTool -Name curl
                if(-not $curl){throw 'curl.exe fehlt. Windows-curl bereitstellen; keine Modelldatei wurde geloescht.'}
                $url='https://huggingface.co/'+$Model.Repository+'/resolve/'+$Model.Revision+'/'+[Uri]::EscapeDataString($File.Name)
                $attempt=0
                while($true){
                    Wait-ShadowDownloadFile -Path $partial
                    $attempt++
                    Write-Host "`nDownload: $($File.Name) - Versuch $attempt (Abbruch mit Strg+C)"
                    Write-Host 'Quelle: Hugging Face; Fortschritt und Geschwindigkeit folgen. Kein Gesamtzeitlimit.'
                    $args=@('--disable','--fail','--location','--proto','=https','--proto-redir','=https','--max-redirs','10',
                        '--connect-timeout','60','--speed-limit','1','--speed-time','300',
                        '--continue-at','-','--output',$partial,'--url',$url)
                    $exitCode=Invoke-ShadowCurl -FilePath $curl -Arguments $args
                    if($exitCode -eq 0){
                        Write-Host "Pruefe Groesse und SHA-256: $($File.Name) ..."
                        if(Test-ShadowModelFile -Path $partial -Size $File.Size -Sha256 $File.Sha256){
                            [IO.File]::Move($partial,$complete)
                            return $complete
                        }
                        throw "Downloadpruefung fehlgeschlagen. Datei bleibt zur Untersuchung erhalten: $partial"
                    }elseif($exitCode -eq 33 -and (Test-Path -LiteralPath $partial)){
                        $preserved=$partial+'.range-'+[guid]::NewGuid().ToString('N')
                        [IO.File]::Move($partial,$preserved)
                        Write-Warning "Fortsetzung vom Server abgelehnt. Teildatei aufbewahrt: $preserved"
                    }else{Write-Warning "Download fehlgeschlagen (curl Exitcode $exitCode); Teildatei bleibt fuer den Wiederanlauf erhalten."}
                    Write-Host 'Neuer Versuch in 30 Sekunden. Strg+C beendet die Provisionierung.'
                    Start-Sleep -Seconds 30
                }
            }

function Copy-ShadowModelFile {
                param([string]$Source,[string]$ModelRoot,[string]$Repository,$File)
                $folder=Join-Path $ModelRoot $Repository.Replace('/','\')
                Assert-ShadowDirectPath $folder
                [void][IO.Directory]::CreateDirectory($folder)
                $target=Join-Path $folder $File.Name
                Assert-ShadowDirectPath $target
                if(Test-Path -LiteralPath $target){
                    if(Test-ShadowModelFile -Path $target -Size $File.Size -Sha256 $File.Sha256){return}
                    throw "Zieldatei existiert und stimmt nicht ueberein: $target. Sie bleibt unveraendert."
                }
                $temporary=Join-Path $folder ('.shadow-copy-'+[guid]::NewGuid().ToString('N')+'.partial')
                Write-Host "Kopiere gepruefte Datei nach LM Studio: $($File.Name) ..."
                [IO.File]::Copy($Source,$temporary,$false)
                if(-not(Test-ShadowModelFile -Path $temporary -Size $File.Size -Sha256 $File.Sha256)){
                    throw "Kopie stimmt nicht ueberein und bleibt zur Untersuchung erhalten: $temporary"
                }
                [IO.File]::Move($temporary,$target)
            }

function Install-ShadowSelectedModels {
                param([object[]]$Definitions,[string]$LmsPath,[string]$InstallRoot,[switch]$SkipModelDownload)
                $modelsRoot=Resolve-ShadowModelDirectory
                $downloadRoot=Join-Path $InstallRoot 'model-downloads'
                $logs=Join-Path $InstallRoot 'runtime/model-precheck-logs'
                $catalog=@{}
                foreach($item in $Definitions){$catalog[$item.Definition.Id]=$item.Definition}
                Write-Host "`nLM-Studio-Modellverzeichnis: $modelsRoot"
                Write-Host "Downloadkopien bleiben erhalten: $downloadRoot"
                $neededDownload=[long]0;$neededCopy=[long]0
                foreach($model in $catalog.Values){
                    foreach($file in $model.Files){
                        $destination=Join-Path (Join-Path $modelsRoot $model.Repository.Replace('/','\')) $file.Name
                        if(Test-Path -LiteralPath $destination){continue}
                        $neededCopy+=[long]$file.Size
                        $complete=Join-Path (Join-Path $downloadRoot $model.Id) $file.Name
                        if(-not(Test-Path -LiteralPath $complete)){
                            $partial=$complete+'.partial'
                            $partialLength=if(Test-Path -LiteralPath $partial -PathType Leaf){[long](Get-Item -LiteralPath $partial).Length}else{[long]0}
                            $neededDownload+=[Math]::Max([long]0,([long]$file.Size-$partialLength))
                        }
                    }
                }
                if(-not $SkipModelDownload -and ($neededDownload -gt 0 -or $neededCopy -gt 0)){
                    $downloadDrive=[IO.DriveInfo]::new([IO.Path]::GetPathRoot([IO.Path]::GetFullPath($downloadRoot)))
                    $modelDrive=[IO.DriveInfo]::new([IO.Path]::GetPathRoot([IO.Path]::GetFullPath($modelsRoot)))
                    if($downloadDrive.Name -ieq $modelDrive.Name){
                        if($downloadDrive.AvailableFreeSpace -lt ($neededDownload+$neededCopy)){throw 'Nicht genug Speicherplatz fuer Downloads und erhaltene Kopien. Keine Modelldatei geloescht.'}
                    }elseif($downloadDrive.AvailableFreeSpace -lt $neededDownload -or $modelDrive.AvailableFreeSpace -lt $neededCopy){
                        throw 'Nicht genug Speicherplatz auf dem Download- oder LM-Studio-Modelllaufwerk. Keine Modelldatei geloescht.'
                    }
                    Write-Host ("Zusaetzlicher Platzbedarf etwa: Download {0:N2} GiB; Modellkopien {1:N2} GiB." -f ($neededDownload/1GB),($neededCopy/1GB))
                }
                foreach($model in $catalog.Values){
                    foreach($file in $model.Files){
                        $destination=Join-Path (Join-Path $modelsRoot $model.Repository.Replace('/','\')) $file.Name
                        Assert-ShadowDirectPath $destination
                        if(Test-Path -LiteralPath $destination){
                            if(-not(Test-ShadowModelFile -Path $destination -Size $file.Size -Sha256 $file.Sha256)){
                                throw "Vorhandene Modelldatei ist nicht identisch: $destination. Sie bleibt unveraendert."
                            }
                            Write-Host "Bereits vorhanden und geprueft: $($file.Name)"
                            continue
                        }
                        if($SkipModelDownload){throw "Modelldatei fehlt und -SkipModelDownload ist gesetzt: $($model.Repository)/$($file.Name)."}
                        $source=Invoke-ShadowModelDownload -Model $model -File $file -DownloadRoot $downloadRoot
                        Copy-ShadowModelFile -Source $source -ModelRoot $modelsRoot -Repository $model.Repository -File $file
                    }
                }
                foreach($item in $Definitions){
                    $attempt=0
                    while($true){
                        $models=if($item.Definition -is [Collections.IDictionary] -and $item.Definition.Contains('ModelType') -and $item.Definition.ModelType -ceq 'embedding'){
                            @(Get-LrDownloadedModels -LmsPath $LmsPath -LogDirectory $logs -Type embedding)
                        }else{@(Get-LrDownloadedModels -LmsPath $LmsPath -LogDirectory $logs)}
                        if(Find-LrModel -Models $models -Profile $item.Definition){break}
                        $attempt++
                        Write-Host "Warte auf LM-Studio-Erkennung: $($item.Definition.ExpectedPath) (Versuch $attempt; Abbruch mit Strg+C)."
                        Write-Host 'Falls eine andere Variante ausgewaehlt ist, die gewaehlte Datei in LM Studio aktivieren.'
                        Start-Sleep -Seconds 10
                    }
                }
            }
