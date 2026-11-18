# Shadow Local AI – Provisionierung und geprüfte Agentenabläufe

Version: 2026.11.18.20 · Zielsystem: Windows x64 auf dem Shadow PC · Sprache der Arbeitsanweisungen: Deutsch

Bei jeder Provisionierung wird das eigene Beispiel unter welcome/workflow-test
registriert. Die [Beispielanleitung](welcome-example/README.md) enthält den
fertigen Kilo-Testauftrag. Bestehender Beispielcode bleibt beim Update erhalten;
New-WelcomeTestProject.ps1 -NewExample erzeugt einen frischen Versuch.

Dieses Paket richtet LM Studio, einen Pool lokaler Modelle, Kilo CLI und eine eigene VS-Code-Umgebung ein. Standard sind Coding und Review als getrennte Rollen; eine dritte Rolle ist optional. Für jede Rolle kann ein Modell ausgewählt werden, auch dasselbe Modell für mehrere Rollen. Es liefert vordefinierte Rollen und wiederverwendbare Arbeitsabläufe für Feature-Entwicklung, Bugfixes, Refactoring, Review und Architektur. Bestehende Software wird erkannt und möglichst weiterverwendet. Bestehende Repository-Dateien werden bei der Einrichtung nicht verändert.

LoKi-Starts öffnen ein neues Fenster mit isolierten Daten und Erweiterungen und
übergeben zusätzlich die VS-Code-Option `--disable-extension` für
`GitHub.copilot` und `GitHub.copilot-chat`. Die Option gilt nur für das so
gestartete Fenster; bestehende Fenster und persönliche Profile bleiben unverändert.
Auch bereits registrierte Projekte erhalten sie beim nächsten LoKi-Start.

### Lokale semantische Indexierung

Im Dual-Modus richtet die Provisionierung LanceDB 0.26.2 und das lokale
`nomic-embed-text-v1.5.Q4_K_M.gguf` ein. Die Datei wird mit Größe und SHA-256
geprüft, bei Bedarf heruntergeladen und ohne Überschreiben abgelegt. Das
Embeddingmodell wird zusätzlich zum jeweils aktiven Codingmodell mit `--gpu off`
gestartet und sein RAM-Bedarf geschätzt. Ein echter
lokaler Embedding-Aufruf mit zwei Vektoren ist Teil des Setups und Launcherstarts.
Die Berechnung und der Vektorspeicher bleiben lokal; es gibt keinen Cloud-Fallback.
Ist der Speicherfit nicht nachweisbar, bleibt das Modell standardmäßig
ungeprüft. Nur `-AllowUnfitAttempt` erlaubt einen Versuch ohne die Reserven des
Pakets. LM Studios Schutzregeln bleiben aktiv. Wird das Embeddingmodell nicht geladen
oder besteht es den Test nicht, bleibt die Einrichtung mit einer Warnung
benutzbar, aber die Indexierung ist noch nicht betriebsbereit. Beim nächsten
LoKi-Start wird sie erneut versucht. Beschädigte Modelldateien, unklare
Eigentumsverhältnisse und Authentifizierungsfehler bleiben ausdrücklich Fehler.
Im Single-Modus wird diese Indexierung derzeit nicht eingerichtet.
Die Integration ist für die VS-Code-Erweiterungen Kilo 7.8.28 und 7.8.30
geprüft. 7.8.30 ist der freigegebene Standard für Neuinstallationen und Updates.
Eine bereits neuere Version wird bei der Provisionierung auf die benötigten
Schnittstellen und Einstellungen geprüft. Die separat installierte Kilo CLI
hat eine eigene Versionsnummer.

Nach vollständigem Schließen der LoKi-Fenster und erneutem Start des Projekts
in Kilo **Einstellungen > Indexing** öffnen und für das jeweilige Projekt
freigeben. Diese Freigabe verwaltet Kilo pro Projekt; das Paket verändert nicht
dessen interne VS-Code-Datenbank. Erst der Status **Complete** und eine
tatsächliche semantische Suche belegen die fertige Indexierung des Projekts.
Die erfolgreiche Provisionierung allein beweist das nicht.

Kilo berücksichtigt `.gitignore` und `.kilocodeignore`, doch die
Werkzeug-Leserechte sind kein allgemeiner Filter für den Index. Vor der
Freigabe sensible Dateien und Zugangsdaten gezielt ausschließen. Der lokale
Index und seine Codeausschnitte sind nicht automatisch verschlüsselt.
Die installierte Kilo-Version unterscheidet beim OpenAI-kompatiblen
Embedding-Aufruf nicht zwischen Such- und Dokumentpräfixen, die Nomic empfiehlt.
Die Suchqualität ist daher nicht als optimal garantiert; Dateisuche und gezielte
Lektüre bleiben wichtige Ergänzungen.

Führe nach der Provisionierung einmal den Suchtest in [VALIDATION.md](VALIDATION.md)
aus. Er nutzt einen kleinen Ordner mit künstlichen Daten und prüft einen
erwarteten Treffer sowie Ausschlüsse über beide Ignore-Dateien.

### Geprüfte Entwicklung ab dieser Version

Die [Anwenderanleitung](WORKFLOW.md) führt durch den ersten Auftrag und enthält
ein vollständiges `checks.json`-Beispiel. Die wichtigsten Änderungen:

- Aufträge direkt in Kilo `shadow-chat` eingeben. `loki_start` startet den
  kontrollierten Ablauf; `loki_status`, `loki_details` und `loki_cancel` machen
  Fortschritt, Agentenrollen, Rollenmodelle, Ergebnisse und Abbruch zugänglich.
- `shadow-preparer` leitet Kriterien, Änderungsarten, exakte Dateien und passende
  lokale Testkandidaten ab. `shadow-preparation-reviewer` prüft sie unabhängig,
  bevor `checks.json` gesichert und aktualisiert wird. Kein JSON-Pflegen pro Prompt.
- `writePaths` gibt Produktionsdateien frei, `testWritePaths` ausschließlich Tests.
- Ein eigenständiger Testautor und unabhängiger Testreview arbeiten vor der Umsetzung.
  Danach bleiben die geprüften Tests während der Implementierung unverändert.
- Feste `acceptanceCriteria` mit IDs werden konkreten Testfällen aus frisch
  erzeugten JUnit-/JSON-Berichten zugeordnet. Reine Exitcodes genügen nicht.
- `changeTypes` bestimmt zusätzliche Pflichtprüfungen: `security` verlangt
  Security-Review, `ui`/`api` Integrationstests und Integrationsreview.
  Planung, Reviewer und Pfadhinweise können diese Einstufung erweitern.
- Die Provisionierung aktualisiert auch registrierte Projekte. Bestehende
  Befehle bleiben erhalten; auftragsspezifische Felder werden mit Herkunft und
  Prüfsummen erneuert. Alte Exitcode-Checks benötigen einen geprüften strukturierten
  Ersatz. Manuelle Änderungen an automatisch verwalteten Feldern und fehlende
  Voraussetzungen werden als konkreter `NEEDS_INPUT`-Konflikt gemeldet.

Alle Rollen laufen sequenziell im vorhandenen Checkout. Testprozesse verwenden
dein Windows-Konto; die bereinigte Umgebung ist keine Betriebssystem-Sandbox.
Diff, fachliche Abnahme, Commit und Push bleiben bei dir.

### Installer aus dem Quellpaket bauen

Auf dem Entwicklungsrechner die Version oben anpassen und
`python .\Build-ShadowLocalAI.py 2026.11.18.18` ausführen. Das Skript baut
die eingebettete Nutzlast und aktualisiert die Prüfsumme. Der Shadow PC benötigt
für die Provisionierung weiterhin nur die erzeugte PS1. Die separate alte ZIP
ist für diesen Ablauf entbehrlich. Der Provisionierungsbericht enthält
Paketversion und Prüfsumme des tatsächlich verwendeten Installers.

**Wichtig für die Einordnung:** Das Paket ist entwickelt und mit ausführbaren Parser-, Verhaltens- und Fehlertests geprüft. Es wurde hier nicht auf einem echten Windows-Shadow-PC mit GPU installiert. Der Installationslauf prüft die tatsächliche Hardware, die wirksame CLI-Konfiguration und, soweit das Laden gelingt, echte Chat-/Tool-Antworten. Nicht geprüfte Modelle werden ausdrücklich gekennzeichnet und ergeben `PROVISIONED_WITH_WARNINGS`, nicht den Nachweis vollständiger Modellbereitschaft.

## 1. Start in wenigen Schritten

Lade die aktualisierte `Provision-ShadowLocalAI.ps1` auf den Shadow PC. Die einzelne Datei enthält das vollständige Paket einschließlich dieser Anleitung und der Regressionstests für die Reparaturen. Ein separates ZIP einer älteren Version wird durch diese Aktualisierung nicht verändert und darf nicht als identische Ausgabe dieser Version angesehen werden.

Öffne **Windows PowerShell 64 Bit** im Downloadordner. Verwende zunächst dein normales Windows-Benutzerkonto. Ein Installationsprogramm kann bei Bedarf einen Windows-UAC-Dialog anzeigen.

### Erweitertes Audit ohne Provisionierung

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Provision-ShadowLocalAI.ps1 -AuditOnly
```

Dieser Modus benötigt kein installiertes PowerShell 7. Er prüft die Integrität des eingebetteten Pakets und führt das Audit direkt im Speicher unter Windows PowerShell 5.1 oder neuer aus. Er installiert nichts, schreibt keine Paketdateien und fordert weder Modellladen/-entladen noch einen API-Serverstart oder eine Inferenz an.

Ohne `-InstallRoot` prüft das Audit den Ordner der PS1-Datei. Es fragt weder nach
einer Verzeichnisauswahl noch nach `y`. Eine vorhandene ältere Einrichtung unter
`%LOCALAPPDATA%\ShadowLocalAI` wird als Hinweis gemeldet, aber nicht automatisch
stattdessen geprüft. Für diese Einrichtung ausdrücklich
`-AuditOnly -InstallRoot "$env:LOCALAPPDATA\ShadowLocalAI"` verwenden.

**Mögliche Nebeneffekte:** Aufgerufene CLI-Werkzeuge können selbst Cache-/Logdateien schreiben oder ihren Hintergrunddienst initialisieren. Das Audit fragt außerdem öffentliche Paket- und Modellmetadaten online ab. Es ist daher kein strikt offline ausgeführter, nebenwirkungsfreier Dateileser. API-Token werden ausschließlich an den lokalen Endpunkt gesendet und nicht im Bericht ausgegeben; HTTP-Weiterleitungen werden nicht verfolgt.

**Versteckte CLI-Optionen:** `--exact` und `--local` sind im
[LM-Studio-CLI-Commit 43d4b26](https://github.com/lmstudio-ai/lms/blob/43d4b26/src/subcommands/load.ts)
absichtlich aus `load --help` ausgeblendet. Fehlen sie dort, prüfen Audit und Setup
sie mit `lms load --exact --local --estimate-only --yes` **ohne Modellpfad**.
Nur der erwartete Abbruch wegen des fehlenden Modellpfads bestätigt die Optionen;
unbekannte Optionen, Verbindungsfehler oder unerwarteter Erfolg tun dies nicht.
Der Aufruf lädt kein Modell und schätzt ohne Modellpfad auch keinen Speicherbedarf.
Die Schutzoptionen bleiben beim tatsächlichen Schätzen und Laden erhalten.

Eine Antwort `[]` von `lms ls --json` oder `lms ps --json` zählt unter PowerShell
5.1 und 7 als **null Modelle**, nicht als unbekannte Modellinstanz. Unerwartete
JSON-Strukturen werden als Fehler gemeldet, nicht als leere Liste ausgegeben.

Geprüft werden:

- Windows x64, PowerShell-Version, CPU, Gesamt-/freier RAM und NVIDIA-VRAM;
- Werkzeugpfade und Versionen, npm-Einstieg, privates Kilo-Manifest und benötigte LM-Studio-CLI-Optionen;
- der aktive CLI-Einstieg der vorhandenen VS-Code-Installation anhand ihres `code.cmd`, ohne das Batch-Skript auszuführen;
- `curl` sowie das geprüfte `ripgrep` im isolierten Kilo-Cache;
- Parameterkombinationen, Projektpfade, Installationskennung und aktive Provisionierungssperre;
- freie lokale Laufwerke sowie die tatsächlichen Hardware-Mindestwerte der gewählten Modellprofile;
- gespeicherte Zustände, lokale Modelldateien, aktive Instanzen und aufgezeichnete Eigentumsnachweise;
- belegte Ports, Loopback-Bindung, REST-v1-Erreichbarkeit, Authentifizierung und Routerstatus;
- öffentliche npm-Metadaten und die exakten GGUF-Dateinamen im Hugging-Face-Katalog.

Das Modelllaufwerk kann von den Programmpfaden abweichen. Die Speicherübersicht ersetzt deshalb keine Prüfung des tatsächlich konfigurierten LM-Studio-Modellordners. Die öffentliche npm-Prüfung bestätigt auch nicht die Erreichbarkeit einer individuell konfigurierten anderen Registry.

Die Ausgabe ist JSON, Schema 2, mit `checks`, `summary`, `status` und `exitCode`. Jede Prüfung meldet `PASS`, `WARN`, `FAIL`, `MISSING` oder `SKIP`. Nach einzelnen Fehlern werden die übrigen Prüfungen fortgesetzt; externe Aufrufe haben Zeitlimits.

| Ergebnis | Bedeutung |
|---|---|
| `BLOCKED`, Exitcode 2 | Mindestens ein nachgewiesener Fehler, etwa ungeeignete Hardware, ungültiger Zustand oder eine defekte vorhandene CLI. |
| `ATTENTION_REQUIRED`, Exitcode 0 | Fehlende installierbare Komponenten oder Warnungen, etwa nicht erreichbare Onlinequellen. Hinweise vor dem Setup prüfen. |
| `PRECHECK_PASSED`, Exitcode 0 | Keine Fehler/Warnungen/fehlenden Komponenten in den ausgeführten Vorprüfungen. **Kein** Nachweis einer vollständigen Einrichtung. |

`inferenceVerified` bleibt im Audit immer `false`. Die tatsächliche Speicherschätzung für den angeforderten Kontext, Modell-/Tool-Smoke-Tests und wirksame Kilo-Konfiguration prüft erst das normale Setup. Ein Audit-Erfolg ist keine GPU- oder Agenten-Abnahme.

Optional den Bericht selbst speichern:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Provision-ShadowLocalAI.ps1 -AuditOnly > .\ShadowLocalAI-Audit.json
$LASTEXITCODE
```

Die Dateiumleitung schreibt den Bericht ausdrücklich auf deinen Wunsch, nicht durch das Audit selbst.

### Installation

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Provision-ShadowLocalAI.ps1
```

`ExecutionPolicy Bypass` gilt nur für den gestarteten Prozess. Das Paket ändert keine globale Ausführungsrichtlinie und umgeht keine durch Gruppenrichtlinien erzwungene Vorgabe.

### Zielverzeichnis und Bestätigung

Standard ist **der Ordner, in dem die PS1-Datei liegt**, nicht das Arbeitsverzeichnis
des Terminals. Mit `-InstallRoot "D:\LocalAI"` lässt sich ein anderes Ziel wählen.
Liegt unter `%LOCALAPPDATA%\ShadowLocalAI` bereits ein Verzeichnis, bietet der Lauf:

1. das gewählte Ziel verwenden (vorhandene Einrichtung weiterverwenden oder neu einrichten);
2. das bisherige Verzeichnis weiterverwenden;
3. die bisherige Einrichtung ins Ziel kopieren und dort fortsetzen.

Ist im Ziel bereits eine gültige Paketkennung vorhanden, weist das Menü darauf
hin und empfiehlt **Option 1** zum Fortsetzen im Ziel. Die Kennung belegt nicht,
dass eine frühere Kopie oder die Provisionierung vollständig war. Bei Option 3
prüft das Menü vor der Bestätigung auf eine vorhandene Paketkennung und
Namenskonflikte und bietet die Auswahl erneut an. Es führt nichts automatisch
zusammen und entscheidet nicht, welche von zwei unterschiedlichen Dateien gilt.
Bei mehreren Einrichtungen vor Option 1 selbst prüfen, ob der gewählte Stand
der gewünschte ist. Ein Kopieren in ein belegtes Ziel bleibt ausgeschlossen.

Anschließend werden Stammverzeichnis, gegebenenfalls Kopierquelle und
Installationsumfang angezeigt. **Erst die genaue Eingabe `y` erlaubt Änderungen.**
Jede andere Antwort bricht ab; ein nichtinteraktiver Lauf kann die Bestätigung
nicht umgehen.

Verwaltete Dateien, private Kilo-Werkzeuge, VS-Code-Profil und Erweiterungen liegen
unter dem Stammverzeichnis. Fehlende Basisprogramme dürfen ihre normalen
Installationsverzeichnisse verwenden; vorhandene Programme werden weiterverwendet.
Anwendungs-/Installer-Caches und globale Benutzerdaten können außerhalb liegen.
**Das in LM Studio konfigurierte Modellverzeichnis bleibt unverändert.**
Modelle werden über die vorhandene LM-Studio-Konfiguration gefunden bzw. geladen.

Zum Kopieren müssen die verwaltete VS-Code-Umgebung, Router und Aufträge beendet
sein. Aktive Prozesse/Sperren, Verknüpfungen und Namenskonflikte führen zum Abbruch.
Bei NTFS-Hardlinks können Verzeichnisauflistungen veraltete Dateigrößen und
Änderungszeiten enthalten. Deshalb werden diese Daten vor dem Vergleich frisch
vom Dateisystem gelesen. Tatsächliche Änderungen während der Kopie bleiben ein
Abbruchgrund; die Meldung nennt den betroffenen Pfad und bei Dateiänderungen
auch die verglichenen Zeitpunkte und Größen.
Es gibt keine automatische Zusammenführung oder Überschreibung eines anderen
Ziels. Fremde Dateien neben der PS1 bleiben erhalten; kollidierende verwaltete Namen
wie `app`, `runtime` oder `tooling` ohne Paketkennung werden abgelehnt.

Die Kopie erfolgt zunächst in einem Zwischenordner im Ziel und benötigt entsprechend
freien Platz für die gesamte Einrichtung. Verwaltete absolute Pfade in Toolchain,
Kilo-Konfiguration und Arbeitsbereichen werden angepasst. Anwendungseinstellungen,
Modell-Eigentumsnachweise und historische Daten werden nicht pauschal umgeschrieben.
Die Quelle bleibt unverändert als Sicherung erhalten; danach **nur die neue Umgebung
starten, niemals Quelle und Kopie parallel**. Der kopierte Bericht ist zunächst
`INCOMPLETE`; erst ein abgeschlossener Lauf am neuen Ort ergibt `PROVISIONED`
oder bei ausstehenden Modellprüfungen `PROVISIONED_WITH_WARNINGS`.
Der Desktop-Shortcut wird dabei neu erstellt, sofern nicht `-NoShortcut` gesetzt ist.

Optional kannst du gleich ein vorhandenes Repository registrieren:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Provision-ShadowLocalAI.ps1 -ProjectPath "C:\Dev\MeinProjekt"
```

### Modellauswahl und Downloads

Bei neueren LM-Studio-Versionen werden Dateien unter Modell-IDs gruppiert.
Das Setup gleicht die ausgewählte lokale Variante anhand von `lms ls --variants
--json` mit dem exakten Dateipfad ab und verwendet zum Laden die zugehörige
Modell-ID mit `--exact --local`. Die Auswahl wird vor Modellaktionen und nach
dem Laden erneut geprüft; fehlende oder mehrdeutige Metadaten führen zum Abbruch.
Die Auswahl in LM Studio muss weiterhin auf der gewünschten Variante stehen.

Das Setup schlägt für `coder-high`, `coder-fast`, `review` und optional `fast` anhand des aktuell
freien RAM/VRAM eine Vorauswahl vor. Die Empfehlung ist eine grobe Schätzung
aus Dateigröße und Reserve, **kein** gemessener Benchmark und kein Nachweis,
dass das Modell mit dem angeforderten Kontext passt. Pro Rolle kann eine andere
Nummer gewählt werden. Die Auswahl muss mit `y` bestätigt werden. Bei jedem
späteren Lauf werden die Hardwarewerte und Vorschläge neu angezeigt; die
vorherige bestätigte Auswahl bleibt als Wiederanlauf-Standard erhalten.

Fehlende Dateien werden danach von Hugging Face über HTTPS mit sichtbarer
`curl`-Fortschrittsanzeige heruntergeladen. Die Quelle verwendet festgehaltene
Repository-Revisionen und SHA-256-Werte. Netzwerkfehler werden mit sichtbarer
30-Sekunden-Pause unbegrenzt erneut versucht; vorhandene Teildateien werden,
wenn der Server HTTP-Range unterstützt, fortgesetzt. Es gibt kein festes
Gesamtzeitlimit. Integritätsfehler stoppen ausdrücklich; fragliche Dateien
bleiben erhalten. Die Geschwindigkeit des Hosts hängt von deiner Verbindung ab
und wurde nicht als die schnellste verfügbar gemessen.

Geprüfte Downloadkopien bleiben unter `model-downloads` im Stammverzeichnis
erhalten. Eine zweite, ebenfalls geprüfte Kopie wird ohne Überschreiben atomar
im **konfigurierten** LM-Studio-Modellverzeichnis abgelegt; das Setup wartet,
bis LM Studio die passende Variante erkennt. Es werden keine Modelle gelöscht.
Dadurch wird für neu heruntergeladene Modelle etwa der doppelte Dateiplatz
benötigt, wenn beide Ordner auf demselben Laufwerk liegen. Das Setup prüft
den zusätzlichen Platz vor Beginn. Strg+C unterbricht den Lauf; nach erneutem
Start und Bestätigung derselben Auswahl werden Teildateien wiederverwendet.

`-SkipModelDownload` verhindert Downloads weiterhin. Ein benutzerdefiniertes
`-ModelKey` muss lokal eindeutig vorhanden sein; bei Unklarheit `lms ls --json`
prüfen.

Ist die LM-Studio-CLI noch nicht verfügbar, beendet das Skript die Provisionierung
mit **MANUELLE AKTION ERFORDERLICH**, Exitcode 1 und Berichtstatus `INCOMPLETE`.
Es startet die App nicht automatisch, wartet nicht auf Dialoge und setzt sich
nicht selbst fort. Bis dahin eingerichtete Komponenten bleiben erhalten.

1. LM Studio selbst über das Windows-Startmenü öffnen; die Meldung nennt auch den Programmpfad.
2. Erststartdialoge abschließen und gegebenenfalls die LM-Studio-CLI einrichten bzw. reparieren. Die ursprüngliche Fehlerursache bleibt in der Meldung sichtbar.
3. Ein neues Terminal öffnen und **denselben Provisionierungsbefehl mit denselben Parametern, ohne `-AuditOnly`, erneut starten**.

Ist die CLI bereits auffindbar, läuft die Provisionierung ohne diesen manuellen
Zwischenschritt weiter. Ein bewusst erforderlicher manueller Schritt wird nicht
durch eine automatische Bestätigung von Dialogen ersetzt.

### Optional drei Modelle provisionieren

Wenn ein Modell mit vollständiger GPU-Auslagerung nicht passt, kann für den
Modellpool ausdrücklich `-AllowPartialGpuOffload` aktiviert werden:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Provision-ShadowLocalAI.ps1 -ModelMode Dual -IncludeFastModel -AllowPartialGpuOffload
```

Dann prüft das Setup pro Modell GPU-Offload `max`, `0.8` und `0.6`, jeweils
mit der angeforderten Kontextlänge und, falls kleiner, den Fallbacks 16384 und
8192. Die erste Kombination mit ausreichendem GPU-Speicher (1 GiB Reserve),
ausreichendem freiem RAM (Gesamtschätzung plus 3 GiB Reserve) und bestandenen
LM-Studio-Guardrails wird zuerst geladen. Gibt es keinen solchen Fit,
bleibt das Modell ungeprüft. Nur mit `-AllowUnfitAttempt` versucht LoKi
eine geschätzte Konfiguration außerhalb der eigenen Reserven. Die
LM-Studio-Guardrails bleiben aktiv. Ein Versuch ohne LoKi-Reserve
kann das System stark auslasten oder hängen lassen. Der wirksame Kontext wird für den Pool
vereinheitlicht und geladene Modelle durchlaufen weiterhin Smoke-Tests. Die
gespeicherte Option gilt auch bei späteren Modellwechseln; jeder neue
Ladevorgang wird anhand aktueller Ressourcen erneut geschätzt. Scheitert der
Ladeversuch, bleibt die Datei erhalten und das Modell wird als ungeprüft
angezeigt. Teilweise CPU-Auslagerung kann die Inferenz verlangsamen. Ohne den
Schalter wird nur `max` verwendet.
Der Schalter ist nur für `-ModelMode Dual` gültig.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Provision-ShadowLocalAI.ps1 -ModelMode Dual -IncludeFastModel
```

`Dual` bezeichnet die Basis aus Coding- und Review-Modell. Der zusätzliche Schalter
aktiviert das kleinere Modell für bewusst gewählte lesende Rollen. Er behauptet
keinen gemessenen Geschwindigkeitsvorteil.

Für den bisherigen Einmodellbetrieb:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Provision-ShadowLocalAI.ps1 -ModelMode Single
```

### VS Code mit deinem Projekt starten

Nach der Installation im gewählten Stammverzeichnis:

```powershell
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File ".\app\Start-LocalAI.ps1" -InstallRoot "." -ProjectPath "C:\Dev\MeinProjekt"
```

Das Setup gibt für jedes dort registrierte Projekt einen vollständigen Startbefehl
mit seinem tatsächlichen Pfad aus; ohne registriertes Projekt öffnet der
Startbefehl die Projektauswahl. Der Desktop-Shortcut **Shadow Local AI** zeigt
ebenfalls ein PowerShell-Menü: bekannte Projekte per Nummer auswählen,
mit **N** einen weiteren vorhandenen Projektordner per Pfad öffnen oder mit
**0** abbrechen. Pfade mit Leerzeichen und optionalen äußeren Anführungszeichen
werden unterstützt. Nicht erreichbare Projekte bleiben in der Liste erhalten;
nach einer ungültigen Auswahl kann erneut gewählt werden. Ein direkt
übergebenes `-ProjectPath` öffnet das Projekt ohne Menü.

Die Auswahl erfolgt vor dem Modellstart. Erst danach startet der Launcher die
lokale Umgebung und öffnet den projektbezogenen Workspace. Der Ordner wird
registriert; vorhandene Aufgaben und Checks bleiben erhalten. Es werden weder
Projektdateien erzeugt noch Git-Repositories initialisiert. Auch ein leerer
vorhandener Ordner lässt sich öffnen; für geprüfte Aufgabenläufe benötigt er
weiterhin ein Git-Repository mit mindestens einem Commit und passende Checks.

Bei einem Startfehler wartet die Desktopverknüpfung auf Enter, damit die Meldung
lesbar bleibt. Direkte Skriptaufrufe warten nur mit `-PauseOnError`.
Beide verwenden PowerShell 7 und `-ExecutionPolicy Bypass` nur
für den jeweiligen Prozess; erzwungene Gruppenrichtlinien haben weiterhin Vorrang.
Weitere Projekte registrierst du mit demselben Launcher und ihrem jeweiligen Pfad.
Einmal registrierte Projekte bleiben im Arbeitsbereichsindex erhalten.

## 2. Was installiert und eingerichtet wird

| Bestandteil | Verhalten |
|---|---|
| PowerShell 7 | Wird über WinGet installiert, falls nicht vorhanden. Mindestens 7.4 ist erforderlich. Windows PowerShell 5.1 bleibt erhalten. |
| Git, Node.js LTS, VS Code | Vorhandene Programme werden verwendet; fehlende werden über ihre WinGet-Pakete installiert. Eine unpassende bestehende Version wird gemeldet. |
| curl | Wird für Modelldownloads geprüft und bei Bedarf über WinGet bereitgestellt. |
| ripgrep | Version 15.1.0 wird aus dem offiziellen Release anhand fester SHA-256-Prüfsummen geprüft und im isolierten Kilo-Cache bereitgestellt. Setup testet Suche und Dateiauflistung mit Kilo-CLI und Erweiterungs-Backend. |
| LM Studio | Wird bei Bedarf installiert. Vorhandener Modellordner, Authentifizierung und laufende fremde Modelle bleiben erhalten. |
| Inferenz-Runtime | Eine vorhandene passende GGUF-GPU-Runtime wird verwendet. Fehlt sie vollständig, wird eine kompatible stabile CUDA-Runtime über LM Studio bezogen. |
| Modellpool | Modelle pro Rolle auswählen; fehlende geprüfte Dateien werden additiv heruntergeladen. Modellprüfungen laufen, sofern das Modell geladen werden kann; andernfalls bleibt der Status ungeprüft. |
| Lokaler Router | Ordnet die Modell-Aliase zu, serialisiert Inferenz und wechselt nur eindeutig verwaltete LM-Studio-Instanzen. |
| Kilo CLI | Eine kompatible Installation wird wiederverwendet; sonst Installation in das eigene Werkzeugverzeichnis, ohne globale npm-Pakete zu ersetzen. |
| Kilo in VS Code | Aktuelle Erweiterung über den vom Hersteller vorgesehenen Pre-Release-Kanal, in einem eigenen Erweiterungsverzeichnis. |
| Rollen und Workflows | Feste lokale Modellzuordnung pro Rolle; Hauptagent, Spezialisten, Gegenprüfung und Komprimierung bleiben lokal. Rechte und Schleifengrenzen sind vorkonfiguriert. |
| Projektanbindung | Externe `.code-workspace`-Datei, Auftragsdatei und Prüfdefinitionen. Die Einrichtung schreibt nicht in dein Repository. |

Standardverzeichnis: Ordner der `Provision-ShadowLocalAI.ps1`; alternativ das beim Start gewählte Stammverzeichnis oder `-InstallRoot`.

Die Bereitstellung deckt die geprüften Kilo-Grundwerkzeuge ab, nicht pauschal
alle Build-Abhängigkeiten oder Sprachserver beliebiger Projekte. Installiere
projektspezifische Abhängigkeiten nach den Projektanweisungen. Eine vorhandene
`rg.exe` mit unbekannter Prüfsumme im verwalteten Cache wird nicht überschrieben;
das Setup meldet den Konflikt. Das offizielle Archiv wird über HTTPS geladen,
vor der Nutzung geprüft und bei Fehlern nicht als Erfolg gemeldet. Eine
Prüfsumme ist keine unabhängige Herstellersignatur.

Bei VS Code wird der aktive `cli.js`-Pfad aus der mitgelieferten `bin\code.cmd`
ermittelt. Das unterstützt sowohl ältere Installationslayouts als auch die
versionsabhängigen Unterordner neuerer Windows-Versionen. Das Batch-Skript wird
nicht ausgeführt. Ist sein Aufbau nicht eindeutig oder fehlt der referenzierte
Einstieg, bricht das Setup mit dem betreffenden Pfad ab, statt eine beliebige
andere Version zu wählen.
Die verwaltete Kilo-Erweiterung wird über `--list-extensions --show-versions`
und ihr Paketmanifest im eigenen Erweiterungsverzeichnis eindeutig bestimmt.
Das von VS Code 1.146.0 nicht unterstützte `--locate-extension` wird nicht verwendet.

Die Kilo-CLI-Optionsprüfung wertet `stdout` und `stderr` aus und verlangt einen
erfolgreichen Exitcode. Die CLI kann ihre Hilfe bei umgeleiteter Ausgabe auf
`stderr` schreiben. Ein npm-Hinweis auf nicht freigegebene Installationsskripte
ist nicht automatisch ein Fehler; bei weiterhin fehlschlagender CLI-Prüfung
meldet das Setup den Exitcode oder die fehlenden Optionen und stoppt.

Die normale persönliche VS-Code-Umgebung einschließlich Codex, Copilot, Settings und Erweiterungen wird nicht umkonfiguriert. Die neue Umgebung verwendet eigene Verzeichnisse für Benutzerdaten, Erweiterungen und Kilo-Sitzungen. Auch vorhandene globale Kilo-Konfiguration wird nicht überschrieben.

Kilos automatische Inline- und Chat-Vervollständigung besitzt einen eigenen Providerpfad. Das Paket deaktiviert sie deshalb im verwalteten Profil und in den erzeugten Arbeitsbereichen. Bei einer bestehenden verwalteten Einrichtung werden nur diese drei Einstellungen angepasst und zuvor gesichert; andere Profilwerte bleiben erhalten. Eine lokale FIM-Codevervollständigung ist nicht Bestandteil dieses Pakets. Manuelle Autocomplete-Befehle bleiben in der Erweiterung verfügbar, und selbst geänderte Einstellungen können den Dienst wieder aktivieren. Dies ist keine Netzwerk-Sandbox.

Das Paket verändert keine Grafiktreiber, öffnet keine Firewall-Ports, installiert weder WSL noch Docker und führt keinen Neustart aus. GitHub-/Lovable-Anmeldungen und projektbezogene Zugangsdaten werden nicht erfunden oder übernommen.

## 3. Mehrere Modelle, ein kontrollierter GPU-Arbeitsplatz

Für Power Pro nennt Shadow eine RTX A4500 mit 20 GB VRAM und 28 GB RAM.
Die Erkennung auf deiner tatsächlichen Maschine ist maßgeblich.

| Profil | Modell | Gewichtsdatei | Standardzuordnung |
|---|---|---|---|
| `coder-high` | Auswählbar, z. B. Qwen3-14B Q4_K_M | etwa 9,0 GB | Anspruchsvoller Chat, Planung, Architektur und Implementierung |
| `coder-fast` | Auswählbar, z. B. Qwen3.5-9B Q4_K_M | etwa 5,63 GB plus Projektor | Schneller Entwicklungs-Chat, Recherche und optional Implementierung |
| `review` | Auswählbar, z. B. gpt-oss-20b MXFP4 | etwa 12,1 GB | Separater Reviewer und Security-Spezialist |
| `fast`, optional | Auswählbar, z. B. Qwen3.5-9B Q4_K_M | etwa 5,63 GB plus Projektor | Explizit auswählbarer lesender Chat/Explorer |

Die Dateigrößen sind Dezimal-GB auf dem Datenträger. Sie sind keine Messung des
VRAM-Verbrauchs; Kontext, Laufzeit und gegebenenfalls Bildprojektoren brauchen
zusätzlichen Speicher. Die beiden großen Modelle passen zusammen schon anhand
ihrer Gewichte nicht vollständig in 20 GB VRAM.

Deshalb bleiben alle provisionierten Modelle auf dem Datenträger verfügbar,
werden aber standardmäßig **nacheinander** in den GPU-Speicher geladen.
Der lokale Router lauscht standardmäßig auf `127.0.0.1:1235`; LM Studio behält
seinen eigenen Backend-Endpunkt, üblicherweise `127.0.0.1:1234`.

Kilo zeigt die Modelle mit den Rollenpräfixen `[CODER HIGH]`, `[CODER FAST]`,
`[REVIEW]` und optional `[FAST]` sowie dem jeweiligen Modellnamen. Die
Zuordnungen `lmstudio/coder-high`, `lmstudio/coder-fast`, `lmstudio/review`
und optional `lmstudio/fast` verweisen auf die gleichnamigen `shadow-`-Router-Aliase.
Der Router ersetzt den öffentlichen Alias
nur durch die nachgewiesene eigene LM-Studio-Instanz-ID. Beliebige Modellnamen
oder entfernte Endpunkte werden nicht durchgereicht.

Vor jedem Inferenz-Request prüft der Controller den tatsächlichen Modellstand.
Ein Wechsel entlädt ausschließlich eigene, eindeutig anhand von ID und Pfad
zugeordnete Instanzen. Fremde oder beschäftigte Modelle werden erhalten.
Der Router hält seinen Inferenzplatz bis zum Ende einer Antwort einschließlich
Streaming. Eine begrenzte Warteschlange ordnet weitere Anfragen ein.
Nach einer abgeschlossenen Tool-Anforderung ist der Platz wieder frei, sodass
ein echter Kilo-Unteragent ein anderes Modell verwenden kann.

### Kontext und Prüfungen

Jedes Modell wird separat geschätzt und, soweit das Laden gelingt, mit Chat,
Funktionsaufruf und Tool-Ergebnis geprüft. Vorgabe sind 32.768 Kontext-Tokens, mit kontrolliertem
Rückfall auf 16.384. Danach verwendet der Pool das kleinste gemeinsame
Kontextlimit; bei ungeprüften Modellen ist dessen tatsächliche Nutzbarkeit noch
nicht nachgewiesen. Dadurch kann auch die Komprimierungsrolle die Sitzungen
aller Profile verarbeiten. Für jede geladene Instanz wird `parallel=1` geprüft.

Passt ein Modell nicht, wird es heruntergeladen und die Provisionierung läuft
mit Warnung weiter. Ein abgelehnter Ladeversuch oder fehlgeschlagener Modelltest
wird als `Deferred` und in Kilo als `[NOCH NICHT GEPRUEFT]` gekennzeichnet.
Im Dual-Modus wird beim Auswählen das Laden erneut versucht und vor der eigentlichen Anfrage
ein Chat-/Tool-Test durchgeführt. Wenn LM Studio das Modell weiterhin nicht
laden kann oder der Test scheitert, wird diese Anfrage mit einer konkreten
Fehlermeldung abgelehnt; das ist keine Garantie für Ausführbarkeit bei
unzulänglichem Speicher. Freier Speicher ermöglicht einen erneuten Versuch
ohne erneute Provisionierung. Im Single-Modus meldet LoKi bei fehlendem
Speicherfit einen Startfehler. Mit `-AllowUnfitAttempt` kann die Provisionierung
einen Versuch außerhalb der eigenen Reserven erlauben. Es gibt keinen stillen
Modell- oder Cloudwechsel.
Die sichtbare Kennzeichnung wird beim nächsten LoKi-Start aus dem gespeicherten
Modellstatus neu erzeugt; nach einem erfolgreichen Nachtest kann sie im
bereits geöffneten Fenster bis dahin bestehen bleiben.
Der vorherige Einmodellweg bleibt verfügbar, etwa:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Provision-ShadowLocalAI.ps1 -ModelMode Single -PreferredModel GptOss20B
```

Ein vorhandenes eigenes Einzelmodell lässt sich weiterhin über den exakten
`path` aus `lms ls --json` wählen:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Provision-ShadowLocalAI.ps1 -ModelMode Single -ModelKey "EXAKTER-PFAD-AUS-LMS-LS" -SkipModelDownload
```

### Qualität und Wechselkosten

Die Zuordnung ist eine begründete Ausgangskonfiguration, kein Benchmark, der
GPT-OSS pauschal als besseren Reviewer ausweist. Die Gegenprüfung verwendet eine
andere Modellfamilie; der Validator arbeitet anschließend wieder mit Qwen in einer
frischen Sitzung. Damit entsteht eine zusätzliche Perspektive, aber keine
Garantie unabhängiger Denkfehler.

Modellwechsel kosten Ladezeit und den erneuten Aufbau des Inferenz-Caches.
Die gespeicherten Kilo-Chats bleiben davon getrennt erhalten. Verwandte
Implementierungsrollen verwenden deshalb dasselbe Coding-Modell. Das optionale
9B-Modell wird nicht automatisch für jede Kleinigkeit aufgerufen. Weniger
Gesamtparameter allein belegen auch keine höhere Geschwindigkeit; diese muss
auf deiner Hardware und mit repräsentativen Aufgaben gemessen werden.

In der GUI bleiben Hilfs- und Komprimierungsmodell beim Hauptmodell. Im strikten
Runner verwenden diese Hilfsaufgaben jeweils das aktuelle Phasenmodell. Dadurch
vermeiden wir dort zusätzliche Modellwechsel nur für Titel oder Zusammenfassungen.

## 4. Rollen, Spezialisten und Kaskaden

| Rolle | Zweck |
|---|---|
| `shadow-chat` | Chat, lesende Delegation und Start/Status des kontrollierten Entwicklungsauftrags mit Coder High |
| `shadow-chat-fast` | Lesender Entwicklungs-Chat mit Coder Fast |
| `shadow-plan` | Aufgabenzerlegung und Akzeptanzkriterien |
| `shadow-preparer` | Leitet Kriterien, Änderungsarten, genaue Dateien und bekannte Testkandidaten ab |
| `shadow-preparation-reviewer` | Prüft die Vorbereitung unabhängig gegen Originalauftrag und tatsächliches Projekt |
| `shadow-explorer` | Gezielte Suche nach Dateien, Aufrufen und bestehenden Regeln |
| `shadow-architect` | Architektur, SSOT, Schnittstellen und begrenzter Umsetzungsplan |
| `shadow-frontend` | UI, Komponenten, Zustandsführung und Barrierefreiheit |
| `shadow-backend` | APIs, Datenflüsse, Berechtigungen und Fehlerbehandlung |
| `shadow-test` | Sinnvolle Prüfungen, Regressionen und Testlücken |
| `shadow-test-reviewer` | Prüft Testcode und Assertions unabhängig vor deren Ausführung |
| `shadow-integration` | Pflichtreview für UI-/API-Änderungen und tatsächliche Integrationstests |
| `shadow-security` | Konkrete Sicherheitsbefunde mit Belegen |
| `shadow-implementer` | Begrenzte Umsetzung im kontrollierten Ablauf |
| `shadow-reviewer` | Separater Review von Auftrag, aktuellem Diff und betroffenen Dateien |
| `shadow-validator` | Separate Bewertung der wirklich ausgeführten Prüfungen und ihrer Aussagekraft |

Bei installiertem optionalen FAST-Profil kommen die lesenden Rollen `shadow-fast-chat` und `shadow-fast-explorer` hinzu. Sie erhalten keine abschließende Review- oder Validierungsverantwortung.

Die normalen Feature-, Bugfix- und Refactor-Aufgaben verwenden Coder High.
Die zusätzlich angebotenen VS-Code-Aufgaben mit `(Coder Fast)` verwenden
Coder Fast für die Implementierungs-, Frontend- und Backendrollen. Planung,
separater Review, Validierung und die ausdrücklich konfigurierten Checks bleiben
verpflichtend. Die Modellauswahl im freien Chat ändert die Modellwahl des
separaten Aufgabenablaufs nicht.

Frühere `coder`-Auswahlen werden beim nächsten Setup als Vorschlag für
`coder-high` übernommen; das bisherige `fast` kann als Ausgangsvorschlag für
`coder-fast` dienen. Vorhandene Modelle und der Embedding-Index bleiben erhalten.
Nach dem Update alle LoKi-Fenster schließen und eine neue Kilo-Sitzung öffnen;
alte Sitzungen können noch den nicht mehr angebotenen Alias `coder` gespeichert
haben. Eingebaute auswählbare Kilo-Agenten sind im LoKi-Profil deaktiviert;
interne Hilfsrollen wie die Kontextkomprimierung bleiben bestehen.

Die Kilo-Seitenleiste erhält `/feature`, `/bugfix`, `/refactor`, `/review` und
`/architecture`. Sie geben den gewünschten Ablauf an `shadow-chat` weiter.
Ein Auftrag kann ebenso ohne Slash-Befehl als natürliche Beschreibung eingehen.

**Der verbindliche Ablauf startet aus Kilo über das lokale Werkzeug `loki_start`.**
Der Chat selbst erhält damit keine allgemeinen Schreib- oder Shellrechte.
Das Werkzeug bindet den Auftrag an das registrierte Projekt und startet den
festen Runner mit `-AutoPrepare -Workflow Auto`. Vorbereitung und unabhängiger
Review müssen bestanden sein, bevor Testautor und Implementierer ihre begrenzten
Schreibrechte erhalten. Unteragenten dürfen keine neuen LoKi-Aufträge starten.
Die vorhandenen VS-Code-Tasks bleiben eine Alternative für `task.md`; auch sie
verwenden `-AutoPrepare`. Eigene Taskdefinitionen bleiben bei Updates erhalten.

### Wiederverwendbare Abläufe

Allen automatisch gestarteten Abläufen geht Vorbereitung → unabhängiger
Vorbereitungsreview voraus. Danach gelten unverändert die Qualitätsstufen:

- **Feature:** Kriterien/Plan → Testautor → Testreview → Ausgangstests → Umsetzung → Checks → Review → Pflichtspezialisten → Validierung.
- **Bugfix:** Kriterien/Ursache → Testautor → Testreview → konkret fehlgeschlagene Regression → Fix → bestandene Regression → Review → Pflichtspezialisten → Validierung.
- **Refactor:** Verhaltensinvarianten → Testautor → Testreview → bestandene Ausgangstests → Refactoring → Checks → Review → Pflichtspezialisten → Validierung.
- **Review:** Bestehenden Arbeitsbaum ohne Implementierungsphase prüfen → Checks → Review → Validierung.
- **Architecture:** Architekturvorschlag ohne Codeänderungen → Review des Vorschlags anhand der Codebasis → Prüfung der vorhandenen Evidenz. Ohne ausführbare einschlägige Checks entsteht kein `VERIFIED`.

Bei Befunden folgt höchstens **eine Korrekturrunde** als Vorgabe. Danach laufen Checks und beide Prüfer erneut. Per `-MaxCorrectionRounds` sind 0 bis 3 Korrekturrunden einstellbar. Das verhindert unendliche Agentenschleifen. Jede Stufe hat zusätzlich eine Schritt- und Zeitbegrenzung. Zu große Aufträge oder Review-Pakete werden zurückgewiesen, statt wichtige Befunde still abzuschneiden.

Die Rollen und ihre Modellzuordnung stehen deklarativ in `app\AgentTemplates.ps1`; daraus entsteht `kilo-managed\kilo.json`. Dauerhafte Änderungen der mitgelieferten Rollen gehören in die Vorlage, da Setup und Launcher die generierte Datei erneuern. Änderungen verwalteter Dateien werden gesichert; ein Paket-Update ersetzt die Vorlage nach Sicherung. Zusätzliche Rollen oder Prozessvarianten sollten deshalb bewusst in einer versionierten eigenen Anpassung gepflegt und mit den vorhandenen Gates getestet werden. Die Vorlage ist keine beliebige visuelle Workflow-Engine.

Die mitgelieferten Regeln fordern ausdrücklich Antworten auf Deutsch; der
`shadow-chat`-Prompt wiederholt dies. Deshalb können auch englische Eingaben
deutsche Antworten erhalten. `kilo-managed\LOCAL-AI-RULES.md` und die
Agentenkonfiguration sind generierte Dateien und werden beim Start aus den
Vorlagen erneuert.

## 5. Einen Auftrag tatsächlich ausführen

Siehe [WORKFLOW.md](WORKFLOW.md): Dort stehen Auftragsvorbereitung, das vollständige
Schema 2, unterstützte Testberichte, VS-Code-Aufgaben und Fehlerbehandlung.
Die gepflegte Anleitung wird bei jeder Provisionierung für registrierte Projekte
als `LOKI-WORKFLOW.md` aktualisiert. Persönliche `ANLEITUNG.md` bleiben erhalten.

`TaskPreparation.ps1` erfasst eine begrenzte Dateiinventur, Manifeste und lokal
vorhandene Runner. Es liest keine `.env`-Dateien und führt zur Erkennung keine
Projektbefehle aus. Modellvorschläge wählen ausschließlich Kandidaten-IDs;
`Run-ProjectCheck.mjs` führt die festen Node-/Vitest-/Jest-/Playwright-/TypeScript-
Vorlagen ohne Shell und Paketdownload aus. Python/pytest nutzt den lokalen
Interpreter mit JUnit. Fehlende Projektabhängigkeiten werden nicht installiert.
Unbekannte Buildketten können vorhandene manuelle Checks mit strukturierten
Berichten verwenden. Für dauerhafte zusätzliche Grenzen stehen
`limits.allowedWritePaths` und `limits.allowedTestWritePaths` bereit.

Auftragsspezifische Altwerte werden beim ersten automatischen Lauf unter
`automation.importedTaskFields` archiviert und im Vorbereitungsreview offengelegt.
Eigene Befehle und unbekannte Felder bleiben erhalten. Prüfsummen verhindern,
dass manuell geänderte automatische Kriterien oder Checks still ersetzt werden.
Die Sicherung und neue Datei entstehen erst nach bestandenem Review und erneuter
Prüfung von Quellstand, Eingaben und bisheriger `checks.json`.

## 6. Was VERIFIED genau bedeutet

Ein aktueller Quellfingerabdruck, erfolgreiche tatsächliche Checks, vollständige
Zuordnung aller festen Kriterien zu bestandenen Testfällen, unabhängiger Testreview,
Code-Review und Validierung sowie die gegebenenfalls erforderlichen Security-/
Integrationsurteile sind zwingend. Testdateien bleiben während der Umsetzung
gesperrt; Hash- und Umfangsprüfungen erkennen Änderungen vor nachfolgenden Checks.

Ein Testbericht ist vom ausgeführten Projektcode erzeugte Evidenz. Er beweist
weder die Echtheit jeder Assertion noch fachliche Vollständigkeit. Dafür sind
Testreview, Code-Review, Validierung und deine Abnahme erforderlich. Ignorierte
Dateien und externe Zustände liegen weiterhin außerhalb des Quellfingerabdrucks.
`VERIFIED` gilt ausschließlich für den erfassten Stand; offene Pflichtbefunde
verhindern diesen Status auch dann, wenn alle Testprozesse Exitcode 0 liefern.

## 7. Chats, Kontext und Protokolle

Die eigene Kilo-Umgebung speichert Sitzungen unter `runtime-profile`. Wiederöffnen erfolgt in der Kilo-Sitzungshistorie. Das gilt für den laufenden verwalteten Profilpfad; normale Kilo-/Copilot-Chats werden nicht automatisch importiert.

Automatische Kontextkomprimierung ist konfiguriert und erhält das tatsächlich geladene Kontextlimit. Eine Zusammenfassung bleibt verlustbehaftet: lange Historie auf Platte bedeutet nicht, dass jede alte Nachricht gleichzeitig im Modellkontext liegt. Dauerhafte Anforderungen gehören deshalb in die vorhandenen Projektanweisungen, SSOT und überprüfbare Akzeptanzkriterien.

Die strikten Aufgabenläufe starten bewusst frische Sitzungen pro Stufe. Unter `runs\<Zeitstempel-ID>` bleiben Auftrag, Plan, Antworten, Prüfbefehle, Ausgaben, Sitzungs-IDs, angeforderte Rollenmodelle und Receipt erhalten. Diese Ablaufbelege ermöglichen spätere Wiederaufnahme und Prüfung; sie simulieren keinen unbegrenzt großen gemeinsamen Kontext.

Der Kilo-Chat verfolgt seinen Hintergrundauftrag mit `loki_status`. Die Ausgabe
zeigt reale Phasen, Agentenrollen, angeforderte Rollenmodelle, Zustände und
Werkzeugaktivität. `loki_details` liefert den begrenzten Bericht; `LOKI-STATUS.md`
im Projekt-Auftragsordner spiegelt den aktuellen Status. Die kontrollierten
Phasen sind externe CLI-Sitzungen und werden nicht automatisch als native
Kilo-Task-Kindersitzungen oder als Inspector-Graph angezeigt. Native lesende
Chat-Unteragenten können zusätzlich ihre eigenen Kilo-Sitzungen haben.

Eine unterbrochene Statusabfrage beendet den Hintergrundauftrag nicht. Ein
ausdrücklicher Abbruch nutzt `loki_cancel`; erst `CANCELLED` bestätigt das Ende
des eigenen Prozessbaums. Bisherige Änderungen bleiben erhalten. Je Projekt ist
nur ein kontrollierter Auftrag gleichzeitig erlaubt. `NEEDS_INPUT` benennt
fehlende Voraussetzungen oder Konflikte, statt eine Freigabe vorzutäuschen.

`WORKER_UNRESPONSIVE` beendet automatisches Polling nach 30 Sekunden ohne
Workerstart bzw. 120 Sekunden ohne Heartbeat. Das bestätigt weder Prozessende
noch Erfolg; die Projektsperre bleibt bestehen. Jobprotokolle und lokale Prozesse
prüfen und die Sperre nicht blind löschen. `loki_status` kann später erneut prüfen,
`loki_cancel` weiterhin einen Abbruch vormerken. Eine gezielte Wiederherstellung
setzt bestätigtes Prozessende oder einen Systemneustart voraus.

## 8. Lokale Verarbeitung und bestehende Zugänge

Modellserver und Router sind an Loopback gebunden. Ein vorhandener öffentlich gebundener Server wird nicht still umgestellt; die Einrichtung stoppt mit einem Hinweis. Haupt-, Hilfs-, Unteragenten-, Memory- und Komprimierungsmodelle sind auf den lokalen Provider und den ausgewählten Modellkatalog festgelegt. Noch ungeprüfte Modelle sind ausdrücklich gekennzeichnet. Vor CLI-Arbeit wird die wirksame Konfiguration geprüft, einschließlich möglicher verwalteter Vorgaben. Abweichungen führen zu einem Fehler.

Kilo-Telemetrie wird für die gestarteten Prozesse abgeschaltet; VS-Code-Telemetrie im eigenen Profil ebenfalls. Automatische Code-Vektorindizierung ist in diesem Profil deaktiviert; die Agenten verwenden Dateisuche und gezielte Lesezugriffe. Es wird kein zusätzlicher Embedding-Dienst eingerichtet. Die Einrichtung selbst benötigt Internet für Software und Modell-Dateien. „Lokal“ bedeutet Modellinferenz auf deiner Shadow-VM, also weiterhin auf der Infrastruktur des Shadow-Anbieters. Das Paket ist kein Netzwerk-Isolationssystem und enthält keine pauschale Garantie, dass jedes Drittprogramm nie eine Update- oder Metadatenabfrage macht.

Wenn dein bestehender LM-Studio-Server Authentifizierung verlangt, stelle das Token im Prozess bereit, bevor du Setup bzw. Launcher startest:

```powershell
$env:SHADOW_LM_API_KEY = 'DEIN_BESTEHENDES_TOKEN'
```

Konfiguration und Bericht speichern nur den Namen der Umgebungsvariable, nicht das bestehende LM-Studio-API-Token. Der Router erhält es als Prozessumgebung. Für sein eigenes kontrolliertes Beenden erzeugt das Paket zusätzlich ein lokales zufälliges Kontrolltoken in `runtime\router-control.json`; dieses ist kein Modellanbieter-Zugang. Der Desktop-Shortcut erbt keine nur in einem anderen Terminal gesetzte Variable. Starte den Launcher in diesem Fall aus demselben Terminal. Das Paket schaltet vorhandene Authentifizierung nicht aus.

## 9. Lovable und weitere Projekte

Verbinde das gewünschte Lovable-Projekt mit seinem GitHub-Repository und klone es auf den Shadow, oder verwende einen vorhandenen Klon. Anmeldung, Organisation, Repository-URL und Branch sind deine bestehenden Projektdaten. Anschließend registrierst du den lokalen Ordner mit dem Launcher.

Ein lokaler Klon kann weiterhin denselben Supabase-/Cloud-Backendzustand verwenden wie die veröffentlichte Anwendung. Ein Git-Branch schafft keine getrennte Datenbank. Das Paket migriert, veröffentlicht, merged oder pusht deshalb nichts. Lokale Änderungen lassen sich später über deinen üblichen Review-/Git-Prozess in den mit Lovable synchronisierten Branch übernehmen.

Der Ansatz ist auch für andere Git-Projekte nutzbar. Die benötigte Programmiersprachen-Runtime, Package-Manager-Version und projektspezifischen Checks müssen zum Projekt passen; dieses Paket behauptet nicht, unbekannte Python-, Java-, .NET- oder native Buildketten automatisch vollständig einzurichten.

## 10. Wiederholung, Updates und typische Stopps

Beende vor einem Update laufende KI-Aufträge. Ein normaler erneuter Lauf verwendet passende Programme, heruntergeladene Modelle und verwaltete Dateien weiter. Er prüft alle ausgewählten Modelle erneut und beendet einen vorhandenen eigenen Router nur, wenn dieser keine aktive oder wartende Arbeit hat. Eine identische Datei wird nicht erneut geschrieben. Geänderte verwaltete Konfiguration erhält eine Sicherung. Aufgaben und projektspezifische Prüfdateien werden nach ihrer ersten Erstellung nicht neu initialisiert.

Ein normaler Provisionierungslauf ist auch ein Update. Verwende für eine
bestehende Umgebung denselben `-InstallRoot` und schließe deren VS-Code-Fenster
und laufende Aufträge vorher. Die zuletzt gespeicherte Modellkonfiguration dient
als Vorgabe. Ausdrücklich übergebene Optionen haben Vorrang.

Alle erreichbaren registrierten Projekte werden in diesem Lauf aktualisiert.
`-ProjectPath` nimmt zusätzlich weitere Projektordner auf. Der Installer
erneuert die verwalteten VS-Code-Aufgaben und erzeugt `LOKI-WORKFLOW.md` mit
dem Stand des Pakets. In alten `checks.json` ergänzt er fehlende Felder und
sichert das Original. Vorhandene Testbefehle, Schreibfreigaben, Aufträge und
eigene Workspace-Aufgaben bleiben erhalten. Die verwalteten Tasks erhalten
`-AutoPrepare` und einen zusätzlichen `Workflow Auto`-Einstieg. Der konkrete
Schreibumfang wird je Auftrag abgeleitet und unabhängig geprüft; er wird nicht
als neue unbegrenzte Dauerfreigabe übernommen. Unerreichbare Ordner bleiben im Index und
werden im Bericht genannt.

Die geprüfte Version der Kilo-Erweiterung wird ohne Zusatzschalter installiert,
wenn sie neuer ist als die installierte. Weitere freigegebene exakte
Werkzeugversionen können in `dependency-versions.json` im **Installationsordner**
stehen. Ein Beispiel mit lediglich der mitgelieferten Erweiterungsfreigabe:

```json
{
  "powerShell": null,
  "git": null,
  "node": null,
  "curl": null,
  "vsCode": null,
  "lmStudio": null,
  "kiloCli": null,
  "kiloVsCode": "7.8.30"
}
```

Für ein freigegebenes Update den jeweiligen Wert durch eine exakte
Versionsnummer ersetzen. Ein neuerer freigegebener Stand wird beim nächsten
Lauf installiert und anschließend geprüft. Ohne Versionsfreigabe bleibt ein
vorhandenes Basiswerkzeug erhalten. Bei einer Erstinstallation nutzt WinGet
für ein fehlendes, nicht gepinntes Basiswerkzeug seinen Standardkandidaten.
Eine fehlende, nicht gepinnte Kilo CLI wird installiert und auf Kompatibilität
geprüft. Die Kilo CLI wird in einem Versionsordner vorbereitet und erst nach
den Setup-Prüfungen im Toolchain-Index aktiviert. LanceDB, ripgrep und die
Modelldateien behalten ihre vom Paket geprüften Versionen bzw. Hashes.
`-UpdateManaged` wird für ältere Startbefehle weiterhin akzeptiert und ist
für Updates nicht mehr nötig. Freigaben und ausgewählte Werkzeugversionen
stehen im Provisionierungsbericht.

Der Installer verwaltet die LoKi-Werkzeuge. Die Manifest- und Lockdateien deiner
Projekt-Repositories gehören weiterhin zum jeweiligen Repository.

Die npm-Abfrage akzeptiert eine einzelne Versionszeichenfolge, ein einelementiges Array oder ein Versionsobjekt. Ein fehlendes `engines`-Feld ist kein Fehler. Mehrdeutige/leere Antworten werden vor der Installation abgewiesen; StrictMode bleibt aktiv. Nach der Installation wird die angeforderte Version mit dem installierten Manifest verglichen.

Vor einem Modellpool-Ladevorgang wird ein ausstehender Ladeauftrag gespeichert. Scheitert die anschließende Prüfung, kann ein erneuter Lauf eine exakt passende lokale Instanz anhand von ID und Modelldatei wiedererkennen. Das ist nur ein Eigentumsnachweis: Leerlauf, tatsächliche Konfiguration und gegebenenfalls die Setup-Smoke-Tests werden weiterhin geprüft. Ein fremdes Modell oder eine abweichende Datei wird nicht übernommen. Für einen Abbruch einer **älteren Version ohne gespeicherten Ladeauftrag** kann dieser Nachweis nicht nachträglich erfunden werden; gegebenenfalls muss die Instanz einmal bewusst in LM Studio entladen werden.

Ein bekannter, nicht bereiter Router mit HTTP 503 kann kontrolliert neu gestartet werden, sobald er keine aktive/wartende Arbeit mehr meldet und der Kontrollnachweis stimmt. Ein fremder oder nicht authentifizierbarer Dienst wird nicht beendet. Die Paketextraktion wird durch eine exklusive Provisionierungssperre vor parallelen Läufen geschützt. Das Vorhandensein der Sperrdatei allein bedeutet keinen aktiven Lauf; die Dateisperre wird beim Prozessende freigegeben.

Bei Fehlern enthält der Provisionierungsbericht zusätzlich Skriptname, Zeilennummer und Fehlerkennung. Nach einem Prozesszeitlimit können nachgelagerte Installer oder Dienste noch arbeiten: Status prüfen, bevor du den Lauf wiederholst.

Manuelle Änderungen an installierten Programmdateien werden beim nächsten Bootstrap-Lauf nach Sicherung durch den eingebetteten Paketstand ersetzt. Verwende deshalb diese aktualisierte PS1-Datei, nicht nur eine lokal korrigierte entpackte Datei.

| Meldung | Nächster Schritt |
|---|---|
| WinGet fehlt | Microsoft App Installer installieren/aktualisieren, danach erneut starten. |
| `lms.exe` fehlt | LM Studio einmal öffnen und Erststart abschließen. Falls nötig die offizielle CLI-Einrichtung verwenden. |
| Bestehende Node-/PowerShell-/LM-Studio-Version ungeeignet | Bestehende Installation gezielt aktualisieren bzw. reparieren. Der Installer ersetzt sie nicht blind. |
| Fremdes Modell geladen | Laufende Arbeit abschließen, das Modell in LM Studio bewusst entladen, erneut starten. |
| Kein Speicherfit | Andere GPU-/RAM-intensive Prozesse schließen, 16K-Kontext bzw. das kleinere Modellprofil wählen. |
| Öffentlicher Listener oder belegter Port | Bestehenden Dienst prüfen; Loopback bewusst konfigurieren oder einen freien `-Port` wählen. |
| Modell liefert keinen gültigen Tool-Aufruf | Lade-/Template-/Runtimeeinstellungen prüfen; keine Erfolgsmeldung erzwingen. |
| Wirksame Kilo-Konfiguration weicht ab | Kompatibilität bzw. verwaltete Vorgaben prüfen; sie werden nicht umgangen. |
| `NOT_VERIFIED` | `receipt.json` und die konkreten Agenten-/Checkausgaben lesen, Befund bearbeiten und erneut prüfen. |
| `NEEDS_INPUT` | Konkrete Rückfrage oder Voraussetzung aus `loki_details` klären und den ergänzten Auftrag erneut starten. |

Nach Konfigurationsänderungen alle Fenster des verwalteten Profils schließen und mit dem Launcher neu öffnen. Nach dem Wechsel vom Einmodellprofil eine neue Kilo-Sitzung beginnen oder in einer alten Sitzung ausdrücklich das neue lokale Modell auswählen: manuelle Modellwahlen können sitzungsbezogen erhalten bleiben. VS Code kann sonst den bereits laufenden Prozess und dessen alte Umgebung weiterverwenden. Die erste echte GUI-Nutzung muss bestätigen, dass die lokale Modellauswahl und Rollen in der installierten Erweiterung ankommen; Setup und Launcher prüfen sowohl die separate CLI als auch die eingebettete CLI der Erweiterung. Das ersetzt dennoch keinen sichtbaren GUI-Test für jede spätere Erweiterungsversion.

## 11. Dateiaufbau und Sicherung

Wesentliche Dateien in der Installation:

- `app`: lesbare Skripte und diese Anleitung.
- `inventory.json`, `toolchain.json`, `provisioning-report.json`: erkannte Ausgangslage, konkrete Werkzeuge und Ergebnis.
- `runtime\model-pool.json`: tatsächlich überprüfte Modelle, Kontextgrenzen und Endpunkte.
- `runtime\model-ownership.json`: Zuordnung der vom Paket kontrollierten Modellinstanzen.
- `runtime\router-events.jsonl`: Router-Ereignisse ohne Prompt-, Antwort- oder Tokeninhalte.
- `runtime\runtime-state.json`: weiterhin vorhandener Zustand des optionalen Einmodellprofils.
- `kilo-managed`: erzeugte Rollen, Arbeitsregeln und Slash-Befehle.
- `runtime-profile`: lokale Kilo-Konfiguration, Cache und Sitzungsdaten für dieses Profil.
- `vscode-data`, `vscode-extensions`: separate VS-Code-Daten.
- `projects`, `workspaces`, `workspaces.json`: Aufträge, Checks und externe Projektarbeitsbereiche.
- `runs`: nachvollziehbare Prüfbelege je Aufgabenlauf.
- `workflow-jobs`: Hintergrundaufträge aus Kilo, Ereignisse, Status und Abbruchsignale.
- `projects\<Projektkennung>\LOKI-STATUS.md`: sichtbarer Verlauf des zuletzt veröffentlichten Kilo-Auftrags.
- `backups`: Sicherungen geänderter verwalteter Dateien.

Sichere insbesondere Anforderungen, Aufgaben, angepasste Vorlagen, Sitzungsdaten und Receipts entsprechend deinem üblichen Backupverfahren. Das Paket löscht diese Daten nicht automatisch. Es enthält keinen pauschalen Uninstaller, der gemeinsam benutzte Werkzeuge oder deine Modelle entfernt.

## 12. Primärquellen und Validierungsgrenze

Die Umsetzung wurde gegen die aktuellen Herstellerdokumentationen und CLI-Quellen geprüft:

- Shadow Power Pro: https://support.shadow.tech/hc/en-us/articles/33442461134609-Shadow-PC-Pro-Offers-Frequently-Asked-Questions
- LM Studio CLI: https://lmstudio.ai/docs/cli
- LM Studio lokale Modellladeoptionen: https://github.com/lmstudio-ai/lms/blob/main/src/subcommands/load.ts
- LM Studio REST-Modellstatus: https://lmstudio.ai/docs/developer/rest/list
- Qwen-Modell: https://lmstudio.ai/models/qwen/qwen3.8-27b
- Review-Modell: https://huggingface.co/openai/gpt-oss-20b
- Optionales kleines Modell: https://huggingface.co/Qwen/Qwen3.5-9B
- Modellwechsel/Auto-Evict: https://lmstudio.ai/docs/developer/core/ttl-and-auto-evict
- Exaktes Entladen: https://lmstudio.ai/docs/developer/rest/unload
- Exakte GGUF-Dateien: https://huggingface.co/lmstudio-community/Qwen3.8-27B-GGUF/tree/main
- Kilo-Installation und Erweiterungskanal: https://kilo.ai/docs/getting-started/installing
- Kilo CLI: https://kilo.ai/docs/code-with-ai/platforms/cli-reference
- Unteragenten: https://kilo.ai/docs/customize/custom-subagents
- Rollenrechte: https://kilo.ai/docs/customize/agent-permissions
- Wiederverwendbare Befehle: https://kilo.ai/docs/customize/workflows
- Kontextkomprimierung: https://kilo.ai/docs/customize/context/context-condensing
- Rollen- und Hilfsmodelle: https://kilo.ai/docs/code-with-ai/agents/model-selection
- Separater Autocomplete-Pfad: https://kilo.ai/docs/code-with-ai/features/autocomplete
- Aktuelle Erweiterungseinstellungen: https://github.com/Kilo-Org/kilocode/blob/main/packages/kilo-vscode/package.json
- VS-Code-Kommandozeile: https://code.visualstudio.com/docs/configure/command-line
- WinGet-Installation: https://learn.microsoft.com/en-us/windows/package-manager/winget/install
- Lovable/Git-Synchronisierung: https://docs.lovable.dev/integrations/git-sync-overview

Die beiliegenden Tests verwenden PowerShell 7 und echte temporäre Prozesse/Git-Repositories, simulieren aber Modellantworten und Windows-/GPU-Grenzen. Sie testen das Kontrollverhalten, keine Modellintelligenz. Der separate `VALIDATION.md` beschreibt den konkret ausgeführten Stand. Der abschließende Windows-/GPU-/VS-Code-Test erfolgt beim ersten Einsatz auf deinem Shadow.
