# LoKiEnte — lokale KI-Entwicklung mit VS Code, Kilo und LM Studio

[English](README.md) · Deutsch

<p align="center">
  <img src="assets/lokiente-preview.png" width="280" alt="LoKiEnte: eine freche Ente mit grünem Loki-Helm und goldenen Hörnern">
</p>

LoKiEnte richtet eine lokale KI-Entwicklungsumgebung unter Windows ein: VS Code
als Editor, Kilo für deine Entwicklungsaufträge und LM Studio für die Modelle
auf deinem Rechner. Du beschreibst eine Änderung; getrennte Agenten planen,
erstellen Tests, implementieren und prüfen das Ergebnis.

**Im Mittelpunkt steht überprüfbare Codequalität.** Kilo leitet Akzeptanzkriterien
und passende Testbefehle aus deinem Auftrag und Projekt ab. Du siehst den Ablauf
und die Ergebnisse und entscheidest selbst, was du committest.

[Installieren](#schnellinstallation-aktuelles-release) ·
[Erster Testauftrag](#erster-testauftrag) ·
[Aktualisieren](#update-installer-ersetzen-und-erneut-provisionieren) ·
[Optionen](#sämtliche-parameter-des-provisionierungsskripts) ·
[Hilfe](#häufige-fragen)

## Voraussetzungen

- **Windows x64** auf einem PC, einer Workstation oder einer geeigneten VM.
  Linux und macOS werden vom Installer nicht unterstützt.
- **Ausreichend RAM, Grafikspeicher und Speicherplatz** für die gewählten Modelle.
  Die Provisionierung prüft die verfügbaren Ressourcen und bietet passende Profile an.
  Die automatischen GPU-Prüfungen sind auf NVIDIA ausgerichtet; andere GPUs und
  reine CPU-Systeme sind nicht als gleichwertige Konfiguration validiert.
- **Internet** für Installation und Downloads. Die Modelle laufen anschließend
  lokal; Werkzeuge deiner Projekte können weiterhin Netzwerkzugriffe benötigen.
- Ein normales Windows-Benutzerkonto. **Windows PowerShell 5.1 genügt zum Start**;
  der Installer richtet benötigte Werkzeuge und PowerShell 7.4 oder neuer ein.
- Für eigene Codeaufträge: ein Git-Repository mit mindestens einem Commit,
  installierte Projektabhängigkeiten und ausführbare Tests. Das mitgelieferte
  Welcome-Testprojekt ermöglicht einen ersten Versuch ohne eigenes Projekt.

Programmausgaben und erzeugte Agentenanweisungen sind Englisch. Deutsche
Anleitungen liegen als `*.de.md` daneben; eine Sprachumschaltung im Programm
gibt es nicht. Ausgaben anderer Programme folgen deren eigenen Spracheinstellungen.

## Schnellinstallation: aktuelles Release

Lade das [aktuelle Release](https://github.com/mauricehuschke/LoKiEnte/releases/latest)
oder direkt den [eigenständigen Installer](https://github.com/mauricehuschke/LoKiEnte/releases/latest/download/Provision-LoKiEnte.ps1) herunter. Die PS1 enthält das
vollständige Quellpaket; die GitHub-Quellcode-ZIP und ein Repository-Klon sind nicht nötig.

### PowerShell (empfohlen, mit Prüfsummenprüfung)

Öffne Windows PowerShell in einem beschreibbaren Downloadordner und füge den
gesamten Block ein. Er ermittelt einmal das aktuelle veröffentlichte Release,
lädt beide Dateien derselben Version herunter, überschreibt gleichnamige Dateien
im aktuellen Ordner, prüft SHA-256 und startet die Provisionierung. Passe bei Bedarf
`InstallRoot` an.

```powershell
& {
    $ErrorActionPreference = 'Stop'
    $installRoot = "$env:LOCALAPPDATA\LoKiEnte"
    $release = Invoke-RestMethod 'https://api.github.com/repos/mauricehuschke/LoKiEnte/releases/latest'
    $base = "https://github.com/mauricehuschke/LoKiEnte/releases/download/$($release.tag_name)"
    Invoke-WebRequest "$base/Provision-LoKiEnte.ps1" -OutFile .\Provision-LoKiEnte.ps1 -UseBasicParsing
    Invoke-WebRequest "$base/Provision-LoKiEnte.ps1.sha256" -OutFile .\Provision-LoKiEnte.ps1.sha256 -UseBasicParsing
    $expected = ((Get-Content .\Provision-LoKiEnte.ps1.sha256 -Raw).Trim() -split '\s+')[0]
    if ($expected -notmatch '^[a-fA-F0-9]{64}$' -or (Get-FileHash .\Provision-LoKiEnte.ps1 -Algorithm SHA256).Hash -ne $expected) {
        throw 'Installer checksum verification failed. Do not run this download.'
    }
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Provision-LoKiEnte.ps1 -InstallRoot $installRoot
}
```

### Eingabeaufforderung (CMD, mit Windows curl)

```bat
curl.exe --fail --location --output Provision-LoKiEnte.ps1 "https://github.com/mauricehuschke/LoKiEnte/releases/latest/download/Provision-LoKiEnte.ps1" && powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Provision-LoKiEnte.ps1 -InstallRoot "%LOCALAPPDATA%\LoKiEnte"
```

### GNU wget (falls installiert, in CMD ausführen)

```bat
wget.exe -O Provision-LoKiEnte.ps1 "https://github.com/mauricehuschke/LoKiEnte/releases/latest/download/Provision-LoKiEnte.ps1" && powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Provision-LoKiEnte.ps1 -InstallRoot "%LOCALAPPDATA%\LoKiEnte"
```

Verwende für GNU wget `wget.exe`: `wget` ist in Windows PowerShell 5.1 ein Alias
für `Invoke-WebRequest` mit anderen Optionen. Die CMD-Varianten starten nur nach
erfolgreichem Download. Nutze für die Prüfsummenprüfung den empfohlenen PowerShell-Block.
Die Prüfsumme erkennt beschädigte oder nicht zusammenpassende Downloads; sie ist
keine digitale Signatur.

Bestätige den angezeigten Installationsordner mit `y`, prüfe die vorgeschlagenen
Modellprofile und schließe eine angeforderte LM-Studio-Ersteinrichtung ab. Falls
der Installer einen Erststart verlangt, führe danach denselben Befehl erneut aus.
Lies den Abschlussbericht, starte die Desktopverknüpfung **LoKiEnte** und wähle
das Welcome-Testprojekt. `PROVISIONED_WITH_WARNINGS` bedeutet, dass einzelne
Funktionen noch geprüft werden müssen.

## Erster Testauftrag

1. Starte nach der Provisionierung die Desktopverknüpfung **LoKiEnte**.
2. Wähle `welcome\workflow-test`. Es ist ein eigenes Beispielprojekt im
   Installationsordner und benötigt keine deiner Anwendungen.
3. Öffne dessen README, kopiere den enthaltenen Testauftrag und füge ihn in Kilo
   im Modus **`shadow-chat`** ein.
4. Beobachte Vorbereitung, Testautor, Implementierung und unabhängige Reviews
   in den Kilo-Werkzeugkarten oder in `LOKI-STATUS.md`.
5. Die Ausgangstests müssen den absichtlichen Fehler der Rabattfunktion zeigen;
   die abschließenden Tests müssen bestehen. Prüfe den Git-Diff und den Bericht
   mit Status `VERIFIED`.

Der [vollständige Testauftrag](Quellpaket/welcome-example/README.de.md) verwendet
nur künstliche Daten. Ein Update erhält deine Änderungen am Beispiel. Für einen
frischen Versuch führe in PowerShell 7 Folgendes aus; passe den Installationsordner
an, wenn du einen anderen gewählt hast:

```powershell
$installRoot = "$env:LOCALAPPDATA\LoKiEnte"
& "$installRoot\app\New-WelcomeTestProject.ps1" -InstallRoot $installRoot -NewExample
```

Das Beispiel vermeidet Änderungen an deinen Anwendungen. Es ist keine
Betriebssystem-Sandbox: Agenten und Tests laufen mit deinem Windows-Konto.

## Im Alltag starten

Öffne die erzeugte Desktopverknüpfung. Im PowerShell-Menü wählst du ein bekanntes
Projekt oder einen weiteren vorhandenen Ordner aus. LoKiEnte bereitet den lokalen
Modellzugriff vor und öffnet den verwalteten VS-Code-Arbeitsbereich.

Für ein neues Projekt zunächst einen Ordner und das Grundgerüst anlegen sowie
Git initialisieren und einen ersten Commit erstellen. Danach den Ordner auswählen.
LoKiEnte legt keinen zusätzlichen Git-Worktree an.

Wähle in Kilo `shadow-chat` und beschreibe direkt die gewünschte Änderung samt
Grenzen und erwartetem Verhalten. Kilo startet den geprüften Ablauf; ein
Vorbereitungsagent leitet Kriterien, Änderungsarten, genaue Dateigrenzen und
passende lokale Tests ab. Ein unabhängiger Reviewer prüft diese Vorbereitung,
bevor `checks.json` gesichert und ergänzt wird. Eine manuelle JSON-Pflege pro
Auftrag ist nicht nötig. Bei unklaren Anforderungen oder fehlender Testumgebung
meldet Kilo den konkreten Klärungsbedarf.

Die Statusausgabe in Kilo zeigt Phase, Agentenrolle, Rollenmodell und Ergebnis.
Im LoKiEnte-Auftragsordner steht zusätzlich `LOKI-STATUS.md`. Mit „Zeige die Details“
oder „Brich den Auftrag ab“ kannst du Bericht bzw. Abbruch anfordern. Die Rollen
laufen als getrennte externe CLI-Sitzungen; der Status ist keine native
Kilo-Task-Baumansicht. `task.md` und die VS-Code-Tasks bleiben eine optionale
Alternative mit derselben automatischen Vorbereitung.

Die [Anwenderanleitung mit vollständigem Beispiel](Quellpaket/WORKFLOW.de.md)
erklärt die Freigaben, Testberichte und Workflows. Nach Installation liegt sie
unter `app\WORKFLOW.md` und für jedes registrierte Projekt als `LOKI-WORKFLOW.md` vor.

## Wie die Codeprüfung funktioniert

1. Vorbereitung und unabhängiger Vorbereitungsreview legen den überprüfbaren Auftrag fest.
2. Ein Architekturagent plant anhand deiner Anforderungen.
3. Ein Testautor bearbeitet ausschließlich freigegebene Testdateien.
4. Ein unabhängiger Agent prüft diese Tests, bevor sie ausgeführt werden.
5. Der Runner führt Ausgangstests aus; Bugfixes müssen konkret reproduziert sein.
6. Der Implementierer bearbeitet die freigegebenen Produktionsdateien. Die Tests
   sind für diese Phase gesperrt.
7. Checks, Code-Review und eine separate Validierung prüfen das Ergebnis.
8. Sicherheitsrelevante Änderungen benötigen zusätzlich Security-Review;
   UI-/API-Änderungen Integrationsprüfungen und einen eigenen Prüfer.

Akzeptanzkriterien besitzen feste IDs und müssen durch tatsächlich berichtete
Testfälle abgedeckt sein. Ein Exitcode 0 ohne Testnachweis genügt nicht.

`VERIFIED` im Laufbericht bedeutet, dass die Prüfbedingungen für diesen Stand
bestanden wurden. Prüfe weiterhin Git-Diff und tatsächliches Verhalten.
Commit und Push führst du selbst aus. Ergebnisse von Sprachmodellen und Tests
sind keine Garantie für Fehlerfreiheit.

## Update: Installer ersetzen und erneut provisionieren

Beende laufende LoKiEnte-Aufträge und schließe dessen VS-Code-Fenster. Führe den
PowerShell-Block oben erneut im Ordner des heruntergeladenen Installers aus: Er
lädt das aktuelle Release und **überschreibt `Provision-LoKiEnte.ps1` samt Prüfsumme**.
Setze `$installRoot` vorher auf den **genauen bisherigen Installationsordner**.
Ersetze beispielsweise die entsprechende Zuweisung im Block durch:

```powershell
$installRoot = 'D:\LoKi'
```

Bei der Standardinstallation bleibt `$env:LOCALAPPDATA\LoKiEnte` erhalten.
Downloadordner und Installationsordner dürfen unterschiedlich sein. Der Download
allein aktualisiert keine Installation; erst die erneute Provisionierung tut das.

Dieser CMD-Befehl ersetzt beispielsweise den heruntergeladenen Installer und
aktualisiert die vorhandene Installation unter `D:\LoKi` (für eine Prüfsummenprüfung
den PowerShell-Block verwenden):

```bat
curl.exe --fail --location --output Provision-LoKiEnte.ps1 "https://github.com/mauricehuschke/LoKiEnte/releases/latest/download/Provision-LoKiEnte.ps1" && powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Provision-LoKiEnte.ps1 -InstallRoot "D:\LoKi"
```

Eine Deinstallation oder `-UpdateManaged` ist nicht erforderlich. Die Provisionierung
aktualisiert verwaltete Konfiguration, freigegebene Werkzeugversionen und erreichbare
registrierte Projekte. Eigene Projektdateien, Testbefehle und gespeicherte
Modelloptionen bleiben erhalten, sofern sie nicht ausdrücklich überschrieben werden.
Ein ausdrücklich geänderter `ModelMode` setzt übernommene Modelloptionen zurück.
Bibliotheken deiner Anwendungsprojekte werden nicht eigenständig aktualisiert.
Details stehen unter [allen Parametern](#sämtliche-parameter-des-provisionierungsskripts)
und in der [ausführlichen Anleitung](Quellpaket/WORKFLOW.de.md).

Der Latest-Link liefert immer das neueste veröffentlichte Release. Ein neuer
Commit auf `main` allein ist noch kein Installer-Update.

## Sämtliche Parameter des Provisionierungsskripts

Die Standards gelten für eine neue Einrichtung. Gespeicherte Modelloptionen
können sie bei einer erneuten Provisionierung ersetzen. Schalter sind
standardmäßig aus. Die Tabelle beschreibt die öffentliche PS1, nicht interne
Setup-Parameter.

| Parameter | Standard / zulässige Werte | Wirkung |
|---|---|---|
| `-InstallRoot` | Ordner der gestarteten PS1; nicht leer | LoKiEnte-Installationsordner. Beim Update denselben Ordner verwenden. Basisprogramme und LM-Studio-Modelle behalten ihre eigenen Speicherorte. |
| `-AuditOnly` | Schalter | Prüft Hardware, Werkzeuge, lokale Zustände und Online-Metadaten ohne Installation oder Modelldownload. Werkzeuge können eigene Logs/Caches schreiben oder Dienste initialisieren. Kein Provisionierungslauf. |
| `-ModelMode` | `Dual`; `Single` oder `Dual` | Dual: Rollenmodellpool mit Router und lokaler Indexierung. Modelle werden kontrolliert nacheinander verwendet; der Name bedeutet nicht zwei gleichzeitig geladene Codingmodelle. Single: ein Codingmodell, derzeit ohne eingerichtete semantische Indexierung. |
| `-IncludeFastModel` | Schalter | Zusätzliches kleines Fast-Modell im Dual-Pool anbieten; nur mit Dual zulässig. Nicht mit dem regulären Coder-Fast-Profil verwechseln. |
| `-AllowPartialGpuOffload` | Schalter | Teilweise CPU-/RAM-Auslagerung für den Modellpool erlauben. Kann größere Modelle ermöglichen, aber deutlich langsamer sein. |
| `-AllowUnfitAttempt` | Schalter | Modellstart trotz nicht nachgewiesener Speicherreserve versuchen. Kann zu Ladefehlern/OOM führen; LM Studios Schutzregeln bleiben aktiv. Kein notwendiger Updateparameter. |
| `-RouterPort` | `1235`; 1024–65535 | Lokaler Modellrouter-Port im Dual-Modus. Anderen Port als den LM-Studio-Port wählen. |
| `-PreferredModel` | `Auto`; `Auto`, `Qwen27B`, `GptOss20B` | Bevorzugtes Modell für die Auswahl. Auto nutzt Hardware und gespeicherte Auswahl; die konkrete Auswahl wird bestätigt. GptOss20B als explizite Vorgabe verlangt Single. |
| `-ModelKey` | nicht gesetzt; Zeichenfolge | Eindeutiger lokaler modelKey oder vollständiger Modellpfad aus `lms ls --json`; nur Single. Modell muss bereits vorhanden sein. |
| `-ApiTokenEnvironmentVariable` | `LOKIENTE_LM_API_KEY` | Name der Umgebungsvariable für den lokalen API-Token, nicht der Token selbst. Keine Geheimnisse als Parameter oder in Projektdateien ablegen. |
| `-ContextLength` | `32768`; 8192–65536 | Gewünschte Kontextgröße in Tokens. Ressourcenprüfung kann eine kleinere tatsächlich nutzbare Größe wählen. Größerer Kontext benötigt mehr Speicher. |
| `-Port` | `1234`; 1024–65535 | Lokaler LM-Studio-API-Port. |
| `-ProjectPath` | leeres String-Array | Zusätzliche vorhandene Projektordner registrieren/aktualisieren. Bereits registrierte erreichbare Projekte werden auch ohne diesen Parameter aktualisiert. Welcome-Testprojekt wird automatisch ergänzt. |
| `-SkipModelDownload` | Schalter | Fehlende Modelldateien nicht herunterladen; bei fehlenden benötigten Dateien stoppt die Einrichtung. Verhindert nicht Downloads/Updates anderer Werkzeuge. |
| `-UpdateManaged` | Schalter | Kompatibilität mit älteren Startbefehlen; aktuell keine zusätzliche Wirkung. Der normale Lauf aktualisiert verwaltete Dateien/Arbeitsbereiche ohnehin. |
| `-NoShortcut` | Schalter | Desktopverknüpfung in diesem Lauf nicht erzeugen/erneuern. Eine bestehende Verknüpfung wird dadurch nicht gelöscht. |

Modelloptionen, deren gespeicherte Werte übernommen werden können:
ModelMode, IncludeFastModel, AllowPartialGpuOffload, AllowUnfitAttempt,
RouterPort, PreferredModel, ModelKey, ApiTokenEnvironmentVariable,
ContextLength und Port. ProjectPath, AuditOnly, SkipModelDownload,
UpdateManaged und NoShortcut werden nicht als Modelloptionen übernommen.
Abhängigkeiten werden auf freigegebene Versionen angehoben; eine höhere
installierte Version wird nicht automatisch heruntergestuft. Ein automatisches
Update auf jede beliebige neueste Version ist damit nicht gemeint.

Für mehrere Projektpfade das Skript direkt aus einer PowerShell aufrufen,
damit das Array erhalten bleibt:

```powershell
& .\Provision-LoKiEnte.ps1 -InstallRoot 'D:\LoKi' -ProjectPath @('D:\Projekte\AppA', 'D:\Projekte\AppB')
```

Ist die Ausführungsrichtlinie dafür eingeschränkt, zuvor eine neue PowerShell
mit `powershell.exe -NoProfile -ExecutionPolicy Bypass` starten.
In PowerShell 7 lassen sich gespeicherte Schalter ausdrücklich ausschalten,
beispielsweise mit `-IncludeFastModel:$false` beim direkten Skriptaufruf.
Standardparameter von PowerShell wie Verbose, Debug, ErrorAction,
WarningAction, InformationAction, ErrorVariable, WarningVariable,
InformationVariable, OutVariable, OutBuffer und PipelineVariable kommen durch
CmdletBinding hinzu (unter PowerShell 7 zusätzlich ProgressAction).
Sie ändern keine Modelloptionen. WhatIf/Confirm werden hier nicht unterstützt;
die y-Abfrage bleibt die Freigabe zur Provisionierung.

## Häufige Fragen

**Warum startet der Schreibauftrag nach einem Update noch nicht?**
Ältere `checks.json` werden strukturell ergänzt. Der neue Auftrag wird automatisch
vorbereitet. Eigene Checks bleiben erhalten; alte reine Exitcode-Tests benötigen
einen unabhängig geprüften strukturierten Ersatz. Fehlen Werkzeuge oder wurde ein
automatisch verwaltetes Feld manuell geändert, zeigt `NEEDS_INPUT` den Konflikt.
Der ursprüngliche Stand bleibt in der Sicherung erhalten.

**Warum meldet LoKiEnte ein fremdes Kilo-Werkzeug?**
Kilo kann eigene JavaScript-/TypeScript-Werkzeuge aus seinem Benutzerprofil laden,
auch bei abgeschalteten externen Plugins. LoKiEnte prüft diese Importpfade vorab und
stoppt bei Konflikten. Die Meldung nennt die betroffene Datei; sichere und verlagere
sie bei Bedarf selbst außerhalb des angegebenen Kilo-Werkzeugordners. LoKiEnte löscht
oder überschreibt diese eigenen Werkzeuge nicht.

**Welche Tests erkennt LoKiEnte?**
Node-Tests sowie lokal installierte Vitest-, Jest- und Playwright-Runner werden
mit passenden Berichtadaptern angeboten; Python/pytest und TypeScript-Typechecks
werden ebenfalls unterstützt. Fehlende Projektabhängigkeiten installiert diese
Vorbereitung nicht. Für andere Buildketten kannst du eigene Projektchecks einmalig
einrichten. Ein erfolgreicher Typecheck allein ersetzt keine Verhaltenstests.

**Kann ich während eines Auftrags weiter an demselben Projekt ändern?**
Vermeide das. LoKiEnte sperrt parallele eigene Workflow-Läufe und kontrolliert den
Quellstand. Änderungen durch den Editor oder andere Prozesse können den Nachweis
ungültig machen; sie werden nicht automatisch zurückgesetzt.

**Warum wurde kein `VERIFIED` ausgestellt?**
Im Terminal steht der Pfad zur `receipt.json`. Dort findest du z. B. fehlende
Testfälle, ungültige Berichte, fehlgeschlagene Checks oder offene Reviewbefunde.
Ein notwendiger Testumbau erfordert einen neuen Lauf mit erneuter Testprüfung.

**Was bedeutet `WORKER_UNRESPONSIVE`?**
Nach 30 Sekunden ohne Workerstart bzw. 120 Sekunden ohne Heartbeat endet die
automatische Statusabfrage. Der Auftrag kann noch laufen; die Projektsperre bleibt
erhalten. Prüfe Jobprotokolle und Prozesse, bevor du wiederherstellst. Lösche die
Sperre nicht ungeprüft und starte keinen parallelen Auftrag.

**Ist die semantische Codesuche sofort bereit?**
Die lokale Indexierung muss im unterstützten Kilo-Profil pro Projekt freigegeben
und abgeschlossen werden. Prüfe sie einmal anhand der
[Suchprobe](Quellpaket/VALIDATION.de.md). Im Single-Modus wird sie derzeit nicht eingerichtet.

**Sind Testprozesse abgeschottet?**
Sie bekommen bereinigte Umgebungsvariablen und eigene Temp-/Profilpfade, laufen
aber mit deinem Windows-Konto. Sie können Dateien und Netzwerk erreichen.
Verwende bestätigte Testbefehle und lokale Testdaten ohne Produktionszugänge.

## Weitere Dokumentation

- [Vollständige Anwenderanleitung und Arbeitsabläufe](Quellpaket/WORKFLOW.de.md)
- [Welcome-Testauftrag](Quellpaket/welcome-example/README.de.md)
- [Fehler melden oder Verbesserungen vorschlagen](https://github.com/mauricehuschke/LoKiEnte/issues)
- [LoKiEnte selbst anpassen oder dazu beitragen](docs/development/README.de.md)

## Lizenz

[Apache License 2.0 mit Commons Clause 1.0](LICENSE.txt) erlaubt unter ihren
Bedingungen Klonen, Forken, Ändern, kostenlose Weitergabe und kommerzielle interne
Nutzung. Die Commons Clause schränkt den Verkauf von Produkten oder Leistungen
ein, deren Wert vollständig oder wesentlich aus der Funktionalität von LoKiEnte
stammt. Das kann auch Hosting und Beratung/Support betreffen. Beide Texte gelten
zusammen.

**Mit LoKiEnte entwickelte Projekte und Arbeitsergebnisse dürfen kommerziell
genutzt und verkauft werden.** Die Verwendung von LoKiEnte stellt diese
eigenständigen Ergebnisse nicht unter dessen Lizenz. Tatsächlich übernommener
LoKiEnte-Code behält seine Lizenzbedingungen; für Materialien Dritter gelten
deren eigene Lizenzen.

Die kombinierte Lizenz ist **Source Available, kein Open Source nach OSI**.
Maßgeblich sind die [englischen Lizenzbedingungen](LICENSE.txt); eine
[deutsche Erläuterung](LICENSE.de.txt) liegt daneben.
