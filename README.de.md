# LoKiEnte – lokale KI-Entwicklung mit VS Code, Kilo und LM Studio

<!-- lokiente-language -->
[English](README.md) · Deutsch

Die Programmausgaben sind Englisch. Diese Datei ist die deutsche Dokumentation.
Neue Anleitungen liegen als GUIDE.md und GUIDE.de.md vor; bestehende persoenliche
ANLEITUNG.md und bearbeitete Auftraege bleiben erhalten. Unveraenderte mitgelieferte
Welcome-Readmes werden mit Sicherung auf Englisch umgestellt.
<!-- /lokiente-language -->

<p align="center">
  <img src="assets/lokiente-preview.png" width="280" alt="LoKiEnte: eine freche Ente mit gruenem Loki-Helm und goldenen Hoernern">
</p>

LoKiEnte richtet eine lokale Entwicklungsumgebung unter Windows ein. Du arbeitest
in VS Code, nutzt Kilo für Analyse und Entwicklung und führst die Modelle über
LM Studio auf deinem Rechner aus. Das Paket ist für Windows x64 auf lokalen PCs, Workstations und geeigneten
virtuellen Maschinen ausgelegt. Es prüft die tatsächlich verfügbaren Ressourcen.
Die automatischen GPU-Prüfungen sind derzeit auf NVIDIA ausgerichtet; andere
GPU-Hersteller und reine CPU-Systeme sind nicht als gleichwertige Zielkonfiguration
validiert. Linux und macOS werden vom Provisionierer nicht unterstützt.

**Schwerpunkt ist überprüfbare Codequalität:** Getrennte Agenten erstellen Tests,
implementieren eine begrenzte Änderung und prüfen anschließend Code und Ergebnisse.
Die Modelle arbeiten lokal. Für Installation und Downloads wird Internet benötigt;
Projektwerkzeuge können unabhängig davon Netzwerkzugriffe ausführen.

Paketversion: **2026.11.18.22**.

## Voraussetzungen

Hinweise zu privaten Dateien, API-Tokens und Git-Commit-Metadaten stehen in
[SECURITY.md](SECURITY.de.md). Lokale Berichte, Sicherungen und Laufzeitdaten
gehören nicht in das Repository.

- Windows x64, ein normales Benutzerkonto und ausreichend Speicher für die Modelle.
- Für den Start genügt Windows PowerShell 5.1; der Installer richtet benötigte
  Werkzeuge ein und nutzt anschließend PowerShell 7.4 oder neuer.
- Die Modellauswahl richtet sich nach RAM/VRAM. Eine größere Modelldatei ist
  keine Garantie für bessere Ergebnisse oder für ausreichenden Speicher.
- Für Codeaufträge: ein Git-Repository mit mindestens einem Commit, installierte
  Projektabhängigkeiten und bekannte, lokal ausführbare Testbefehle.

## Installieren oder aktualisieren

1. Kopiere die aktuelle `Provision-LoKiEnte.ps1` auf den Zielrechner.
   Die einzelne Datei enthält das Quellpaket; eine zusätzliche ZIP ist nicht nötig.
2. Öffne Windows PowerShell im Ordner der Datei. Für eine neue Installation etwa:

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Provision-LoKiEnte.ps1 -InstallRoot "$env:LOCALAPPDATA\LoKiEnte"
   ```

3. Prüfe das angezeigte Ziel und bestätige die Provisionierung mit `y`.
   Wähle und bestätige anschließend die angebotenen Modellprofile.
4. Falls LM Studio einen Erststart benötigt, öffne die App selbst, schließe die
   Ersteinrichtung ab und starte denselben Provisionierungsbefehl erneut.
5. Lies den Abschlussbericht. `PROVISIONED_WITH_WARNINGS` bedeutet, dass einzelne
   Funktionen oder Modelle noch nicht vollständig betriebsbereit geprüft sind.

**Für Updates denselben Installationsordner verwenden.** Vorher laufende
KI-Aufträge und LoKiEnte-Fenster schließen. Der Provisionierer aktualisiert auch
erreichbare, bereits registrierte Projekte. Eigene Aufgaben, Projektdateien und
Testbefehle bleiben erhalten. Die verwalteten Aufgaben und Kilo-Werkzeuge erhalten
die automatische Auftragsvorbereitung auch für bestehende Projekte.

Freigegebene Werkzeugversionen werden über `dependency-versions.json` im
Installationsordner gesteuert. Das Paket liefert die geprüfte Kilo-Erweiterung
mit einer Versionsfreigabe. Es aktualisiert nicht eigenständig die Bibliotheken
deiner Anwendungsprojekte. Details stehen in der [technischen README](Quellpaket/README.de.md).

## Bestehende Installation aktualisieren

Laufende LoKiEnte-Aufträge beenden und die LoKiEnte-VS-Code-Fenster schließen.
Die aktuelle PS1 auf den Windows-PC kopieren und PowerShell im Ordner dieser
Datei öffnen. Für die bestehende Installation unter D:\LoKi:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Provision-LoKiEnte.ps1 -InstallRoot "D:\LoKi"
```

Bei einem anderen bisherigen Installationsort genau diesen als InstallRoot
angeben. Ziel mit y bestätigen; angebotene Modellwahl prüfen.
Gespeicherte Modelloptionen werden übernommen, sofern sie nicht ausdrücklich
überschrieben werden. Ein ausdrücklich anderer ModelMode übernimmt die alten
Modelloptionen nicht. UpdateManaged ist für ein Update nicht nötig.

Optional übernimmt `Provision-Run.ps1` diesen Aufruf mit dem Standardziel
`D:\LoKi`. Er findet die PS1 neben sich, unabhängig vom aktuellen Arbeitsordner,
und erzwingt keine neuen Modelloptionen. Ein anderes Ziel lässt sich mit
`-InstallRoot` wählen. `Project-Run.ps1` öffnet für dasselbe Ziel die
Projektauswahl; `-ProjectPath` ist optional.

Eine separate ZIP wird nicht benötigt. Maßgeblich ist die aktuelle einzelne
PS1 mit ihrer eingebetteten Nutzlast.

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

## Welcome-Test ohne eigenes Anwendungsprojekt

Bei der Provisionierung entsteht `D:\LoKi\welcome\workflow-test` als eigenes,
registriertes Git-Beispiel. Es enthält eine absichtlich fehlerhafte
Rabattfunktion, ein package.json ohne externe Dependencies und den fertigen
Testauftrag in seiner README. Es werden nur künstliche Beispieldaten verwendet.
Ein lokaler Anfangscommit ermöglicht die Quellstandsprüfung; kein Remote oder
automatischer Commit der späteren Kilo-Änderungen wird eingerichtet.

1. Desktopverknüpfung starten und das registrierte `welcome\workflow-test` wählen.
2. Dessen README öffnen und den Testauftrag in Kilo `shadow-chat` einfügen.
3. Automatische checks.json, Vorbereitung und unabhängige Reviews beobachten.
   Die Ausgangstests müssen den Rechenfehler zeigen, danach müssen sie bestehen.
4. Rollen, Modelle und Ergebnisse in den Werkzeugkarten bzw. LOKI-STATUS.md
   prüfen. Ein passender VERIFIED-Bericht und ein nachvollziehbarer Git-Diff
   belegen den erfolgreichen Basisablauf. Security-/Integrationsphasen sind
   für diese reine Rechenfunktion nicht nötig.

Der vollständige [Testauftrag](Quellpaket/welcome-example/README.de.md) liegt auch
im Quellpaket. Er verlangt unter anderem 8000 Cent für 10000 Cent mit 20 %
Rabatt sowie Randfälle und Fehlerbehandlung.

Ein Update setzt den bearbeiteten Teststand nicht zurück. Für einen weiteren
Versuch erstellt dieser Befehl in PowerShell 7 einen neuen registrierten Ordner:

```powershell
& 'D:\LoKi\app\New-WelcomeTestProject.ps1' -InstallRoot 'D:\LoKi' -NewExample
```

Das Beispiel vermeidet Änderungen an eigenen Anwendungsprojekten.
Es ist keine Betriebssystem-Sandbox: Auch diese Prozesse laufen mit deinem Konto.

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

## Für Paketentwickler

`Quellpaket` enthält die bearbeitbaren Skripte, Anleitungen und Tests.
`Build-LoKiEnte.py` erzeugt daraus die eingebettete Nutzlast mit SHA-256.
Nach Änderung der Versionsangabe in `Quellpaket/README.md`:

```powershell
python .\Build-LoKiEnte.py 2026.11.18.22
```

Ausführbare Prüfungen und deren Grenzen sind in
[VALIDATION.md](Quellpaket/VALIDATION.de.md) dokumentiert. Ein echter Probeauftrag
und die GPU-/GUI-Abnahme müssen zusätzlich auf dem Zielrechner erfolgen.

## Logo und Projektname

Das Projekt heißt **LoKiEnte**. Der Desktop-Launcher erhält bei der Provisionierung
den Namen **LoKiEnte** und das Enten-Logo. Das gilt auch für Updates; passende alte
Verknüpfungen derselben Installation werden gesichert und ersetzt. `-NoShortcut`
überspringt diesen Schritt. Verknüpfungen zu anderen Installationen bleiben erhalten.

- [Transparentes PNG-Original, 1254 × 1254 Pixel](assets/lokiente-logo.png)
- [PNG-Vorschau, 512 × 512 Pixel](assets/lokiente-preview.png)
- [Windows-Icon, 16 bis 256 Pixel](Quellpaket/assets/lokiente.ico)
- [Asset-Herkunft und Generierungsprompt](assets/README.de.md)

`scripts/Build-Logo.ps1` erzeugt unter Windows mit PowerShell 7 aus dem Original
die Vorschau und das mehrstufige ICO erneut. Anschließend den Installer mit
`python .\Build-LoKiEnte.py 2026.11.18.22` neu bauen. Nur das kleine ICO wird
für die Desktopverknüpfung im Installer benötigt; das PNG-Original bleibt im Repo.

Die bisherigen technischen Kennungen (`loki_*`, `LOKI_*`, `shadow-*`),
Dateien wie `LOKI-STATUS.md` und Installationsmarker bleiben für bestehende
Projekte kompatibel. Vorhandene Installationsordner werden nicht umbenannt;
die Starthelfer verwenden weiterhin `D:\LoKi`, sofern kein `-InstallRoot`
angegeben wird. Neue Installationen können beispielsweise `D:\LoKiEnte` nutzen.

### Kompatibilität bestehender Installationen

Der neue Standard für den **Namen** einer optionalen Token-Umgebungsvariable ist
`LOKIENTE_LM_API_KEY`. Das ist kein Token. Beim Update bleibt der gespeicherte
Variablenname erhalten; mit `-ApiTokenEnvironmentVariable` kannst du ihn ausdrücklich
ändern. Den Wert weiterhin nur lokal bereitstellen. Interne historische Präfixe
sind keine Anbieterbindung und enthalten keine persönlichen Daten.
