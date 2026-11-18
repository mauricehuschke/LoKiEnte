# LoKiEnte entwickeln und veröffentlichen

[English](README.md) · [Anwenderanleitung](../../README.de.md)

Diese Anleitung richtet sich an Mitwirkende, Maintainer und Personen, die einen
Fork von LoKiEnte anpassen. Für Installation und Nutzung dient die Haupt-README.

## Aufbau der Quellen

- `Quellpaket/`: bearbeitbare Provisionierungsskripte, Agentenabläufe, Vorlagen und Tests.
- `Provision-LoKiEnte.ps1`: erzeugter eigenständiger Installer mit eingebetteter ZIP und SHA-256.
- `Build-LoKiEnte.py`: bettet das Quellpaket in den Installer ein.
- `scripts/Build-Logo.ps1` und `assets/`: Logo-Original und abgeleitete Bilder.
- `README.md` / `README.de.md`: Installation und tägliche Nutzung.
- `Quellpaket/README.md`: detailliertes Provisionierungsverhalten; wird mit dem Paket installiert.
- `Quellpaket/WORKFLOW.md`: Anwenderabläufe; `Quellpaket/VALIDATION.md`: Prüfnachweise und Grenzen.

Lies vor Änderungen an Provisionierung oder Modellverhalten die
[technische Paketanleitung](../../Quellpaket/README.de.md). Englisch bleibt der
Standard; deutsche Anleitungen liegen mit `.de.md` daneben. Ändere beide Fassungen gemeinsam.

## Änderungen beitragen

Klone oder forke das Repository und arbeite auf einem Branch. Begrenze Änderungen
auf einen zusammenhängenden Zweck und ergänze passende Tests und Dokumentation.
Updates müssen bestehende Installationen, registrierte Projekte und eigene
Einstellungen weiterhin erhalten.

Änderungen an `main` erfolgen über Pull Requests. Der Schutz verlangt aufgelöste
Review-Kommentare und verhindert Force-Push und Löschen. Eine zweite Freigabe ist
im derzeitigen Ablauf mit einem Maintainer nicht verpflichtend. Aktuell gibt es
keine vorgeschriebenen CI-Prüfungen; das ersetzt keine passenden lokalen Tests.
Neue GitHub Actions müssen auf vollständige Commit-SHAs festgelegt sein und
möglichst geringe Workflow-Berechtigungen erhalten.

Lies vor Commit oder Veröffentlichung [SECURITY.md](../../SECURITY.de.md): Dort
stehen Hinweise zu Zugangsdaten, lokalen Installationsdaten, eingebetteten Archiven
und Git-Autorenmetadaten. Nutze synthetische Testdaten sowie den öffentlichen
GitHub-Benutzernamen mit No-Reply-Adresse für Commits. Berichte, Laufzeitprofile,
private Beispielprojekte und Tokens gehören nicht ins Repository.

## Installer bauen

Nutze Python 3 und Windows PowerShell 7 auf dem Entwicklungsrechner. Bearbeite
die Quellen in `Quellpaket`, aktualisiere die Zeile `Version:` in beiden
Paket-READMEs im Format `YYYY.MM.DD.N` und baue im Repository-Hauptordner neu:

```powershell
$packageReadme = Get-Content .\Quellpaket\README.md -Raw
$buildVersion = [regex]::Match($packageReadme, '(?m)^Version: (\d{4}\.\d{2}\.\d{2}\.\d+)').Groups[1].Value
if (-not $buildVersion) { throw 'Package version is missing.' }
python .\Build-LoKiEnte.py $buildVersion
if ($LASTEXITCODE -ne 0) { throw 'Installer build failed.' }
```

Der Builder vergleicht die gepackten Bytes mit den Quelldateien und hinterlegt
die Prüfsumme der Nutzlast. Bearbeite die Base64-Nutzlast nicht manuell. Auf dem
Zielrechner genügt die erzeugte PS1; eine separat gepflegte ZIP wird nicht verteilt.
Änderungen ausschließlich an der Haupt-README oder dieser Anleitung ändern das
eingebettete Paket nicht und benötigen keinen neuen Installer-Build.

Führe die zum geänderten Verhalten passenden Prüfungen aus. Der
[Validierungsnachweis](../../Quellpaket/VALIDATION.de.md) beschreibt vorhandene
Tests und ihre Aussagekraft. Bei Änderungen am Setup sind Neuinstallation und
erneute Provisionierung einer bestehenden Umgebung einschließlich Erhalt eigener
Einstellungen und Projekte zu testen. Echte GPU-, Modell- und GUI-Abnahme auf
einem Windows-Zielrechner ist zusätzlich zu synthetischen Regressionstests erforderlich.

## Release veröffentlichen

1. Prüfe Quellen, Installer-Nutzlast und betroffene Tests. Scanne Dateistand,
   Git-Historie und dekodierten Installer-Inhalt auf Geheimnisse.
2. Merge über einen Pull Request und tagge den genauen geprüften Commit. Die
   GitHub-Release-Version bezeichnet den veröffentlichten Stand; die interne
   datumsbasierte Version bezeichnet den eingebetteten Paket-Build.
3. Erstelle einen GitHub-Release-Entwurf. Füge vor Veröffentlichung den Installer
   unter dem dauerhaften Dateinamen `Provision-LoKiEnte.ps1` und seine Prüfsumme hinzu:

   ```powershell
   $digest = (Get-FileHash .\Provision-LoKiEnte.ps1 -Algorithm SHA256).Hash.ToLowerInvariant()
   "$digest  Provision-LoKiEnte.ps1" | Set-Content .\Provision-LoKiEnte.ps1.sha256 -Encoding ascii
   ```

4. Prüfe beide hochgeladenen Dateien, veröffentliche und teste Latest-Download
   sowie Prüfsumme ohne Anmeldung. Unveränderliche Releases sperren Tag und Dateien
   nach Veröffentlichung; Änderungen daran benötigen eine neue Version.

Versionsbezogene Einzelheiten gehören in Release-Notizen und Paketmetadaten.
Die Haupt-README verweist auf `releases/latest`; Anwender sollen keine Versionsnummer
im Download-Link anpassen müssen. Installationsanleitungen sollten auf die aktuelle
Haupt-README verweisen. Titel und Notizen können ohne Austausch der unveränderlichen
Dateien aktualisiert werden.

GitHub Releases passt zur eigenständigen PS1. GitHub Packages dient Registries
wie npm, NuGet und Container-Images und wird hierfür nicht benötigt.

## Logo und Projektname

- [Transparentes Original, 1254 × 1254 Pixel](../../assets/lokiente-logo.png)
- [PNG-Vorschau, 512 × 512 Pixel](../../assets/lokiente-preview.png)
- [Windows-Icon, 16 bis 256 Pixel](../../Quellpaket/assets/lokiente.ico)
- [Asset-Herkunft und Generierungsprompt](../../assets/README.de.md)

`scripts/Build-Logo.ps1` erzeugt unter Windows mit PowerShell 7 Vorschau und ICO
aus dem Original. Baue den Installer nach Änderungen an seinem ICO neu. Nur das
kleine Icon wird eingebettet; das hochauflösende PNG bleibt im Repository.
Die Desktopverknüpfung heißt LoKiEnte. Updates sichern und ersetzen passende alte
Verknüpfungen derselben Installation; `-NoShortcut` überspringt diesen Schritt.

## Kompatibilität und Hilfsskripte

Historische Kennungen (`loki_*`, `LOKI_*`, `shadow-*`), `LOKI-STATUS.md` und
Installationsmarker erhalten die Kompatibilität. Benenne sie nicht ohne getestete
Migration um. Bestehende Installationsordner werden nicht umbenannt. Die optionalen
Helfer `Provision-Run.ps1` und `Project-Run.ps1` behalten das bisherige Standardziel
`D:\LoKi`; für andere Ziele ist `-InstallRoot` anzugeben. Release-Anwender benötigen
diese Helfer nicht.

Der Standardname der optionalen Token-Umgebungsvariable lautet `LOKIENTE_LM_API_KEY`;
er ist kein Zugangswert. Updates erhalten den gespeicherten Variablennamen, sofern
er nicht ausdrücklich mit `-ApiTokenEnvironmentVariable` geändert wird. Tokens bleiben lokal.

Updates verteilen englische und deutsche Anleitungen. Persönliche `ANLEITUNG.md`
und eigene Auftragstexte bleiben erhalten. Eine unveränderte mitgelieferte deutsche
Welcome-README wird gesichert und durch die englische Anleitung ersetzt; angepasste
Welcome-Inhalte bleiben erhalten.

## Verwalteter VS-Code-Start

`Quellpaket/VsCodeProfile.ps1` führt lokale Profilvorgaben zusammen und paketiert
den Helfer ohne externe Abhängigkeiten aus `Quellpaket/vscode-startup/` als VSIX.
Setup installiert ihn über den regulären VS-Code-CLI im isolierten Erweiterungsordner
und prüft die Version. Versionen in package.json und extension.vsixmanifest müssen
übereinstimmen. Der Helfer verwendet öffentliche VS-Code-Erweiterungs-APIs und
Kilos eigenen Befehl zum Fokussieren der Seitenleiste. Er prüft Launcher-Umgebung
und tatsächlichen Profilspeicherpfad. VS-Code-SQLite-Speicher, Cloud-Sync-Zustand
und persönliche Profile dürfen dafür nicht verändert werden.

Profilerhaltung, Entfernung widersprechender Sync-Freigaben, Wiederholbarkeit,
VSIX-Inhalt, Arbeitsbereichsmigration und Startup-/Fehlerverhalten prüfen
Test-ProvisionSettings.ps1, Test-VsCodeProfile.ps1, Test-WorkspaceGuide.ps1 und
Test-VsCodeStartup.mjs. Ein echtes VS-Code-/Kilo-Fenster und angemeldeter Settings
Sync sind separate Integrationsprüfungen.

## Lizenz und Forks

[Apache License 2.0 mit Commons Clause 1.0](../../LICENSE.txt) gilt für LoKiEnte
selbst. Behalte bei der Weitergabe eines Forks beide Texte und erforderliche
Hinweise bei. Die Kombination ist Source Available, kein Open Source nach OSI.
Eigenständige mit LoKiEnte erstellte Projekte und Arbeitsergebnisse dürfen
kommerziell genutzt und verkauft werden.
