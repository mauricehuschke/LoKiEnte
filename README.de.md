# LoKiEnte — lokale KI-Entwicklung mit VS Code, Kilo und LM Studio

[English](README.md)

<p align="center">
  <img src="assets/lokiente-preview.png" width="200" alt="LoKiEnte: eine Ente mit grünem Loki-Helm und goldenen Hörnern">
</p>

LoKiEnte richtet eine lokale KI-Entwicklungsumgebung unter Windows ein. Du
arbeitest in **VS Code**, beschreibst **Kilo Code** deine Änderungen und betreibst
die Modelle über **LM Studio** auf deinem eigenen Rechner.

Im Mittelpunkt stehen **Codeänderungen, die du nachvollziehen und prüfen kannst**.
Getrennte Agentenrollen bereiten den Auftrag vor, planen, schreiben Tests,
implementieren und prüfen das Ergebnis. Lokale Testergebnisse und Reviewbefunde
begleiten den Lauf; du prüfst den Diff und entscheidest über den Commit.

## Was LoKiEnte auszeichnet

- **Lokale Modelle und vertraute Werkzeuge.** Nutze vorhandene Git-Projekte in
  VS Code mit einem verwalteten lokalen Modellanbieter und eigenem LoKiEnte-Profil.
- **Ein geprüfter Entwicklungsablauf.** Vorbereitung, Testautor,
  Implementierung und unabhängige Reviews haben getrennte Zuständigkeiten.
- **Nachweise zum tatsächlichen Codestand.** Ausgangstests, strukturierte
  Berichte und abschließende Validierung verbinden Akzeptanzkriterien mit
  ausgeführten Prüfungen.
- **Modelle passend zur Aufgabe.** Coding und Review können unterschiedliche
  Modelle verwenden. Der lokale Router steuert ihren Einsatz und prüft den Speicher.
- **Projekte bleiben deine Projekte.** Die Desktop-Projektwahl unterstützt
  Git-Suche, Klonen und die Reparatur verschobener Pfade. Erneutes Provisionieren
  erhält eigene Projekteinstellungen und sichert verwaltete Änderungen.

[Sicherheit](#sicherheit-und-kontrolle) · [Installation](#schnellinstallation-aktuelles-release) ·
[Beispiele](#beispiele) · [Hilfe](#diagnose-und-fehlersuche) ·
[Ausführliche Referenz](docs/usage/README.de.md)

## Sicherheit und Kontrolle

LoKiEnte kombiniert mehrere Schutzmaßnahmen:

- **Lokale Inferenz:** Die verwaltete Konfiguration nutzt LM Studio über lokale
  Loopback-Endpunkte. API-Tokens werden über Umgebungsvariablen bereitgestellt.
- **Werkzeugberechtigungen:** Kilos Datei- und Netzwerkfreigaben werden mit
  konkreten erlaubten und verbotenen Zugriffen geprüft. Der
  [E.T.-Test](#et-sicherheitsprüfung) bewertet die Zugriffskontrolle getrennt davon,
  ob das Modell seine Anweisungen befolgt.
- **Kontrollierte Änderungen:** Geprüfte Dateigrenzen, während der Implementierung
  gesperrte Tests und Projektsperren begrenzen den Entwicklungsablauf.
- **Geprüfte Abhängigkeiten:** Das Provisioning bestimmt genaue Werkzeugversionen
  anhand der gewählten Update-Richtlinie und eines Mindestalters von 48 Stunden.
  Mit Installer-Prüfsummen kannst du den Download kontrollieren.
- **Sichtbare Ergebnisse:** Start-, Verbindungs- und Testfehler erscheinen in der
  LoKiEnte-Ausgabe und lokalen Berichten. Fehlende oder übersprungene Nachweise
  werden nicht als PASS ausgegeben.

**Die normale Ausführung verwendet dein Windows-Konto.** Kilo-Berechtigungen und
Workflow-Prüfungen schotten nicht sämtliche Prozesse von Dateien und Netzwerk ab.
Projekt-Testbefehle brauchen dieselbe Sorgfalt wie selbst ausgeführte Befehle.
Der optionale Offline-Hyper-V-Gast ist eine eigene Funktion; normale Installation
und Abnahme benötigen weder Hyper-V noch Docker. Siehe
[Sicherheit, Datenschutz und Grenzen](SECURITY.de.md).

## LoKiEnte selbst einsetzen

Installiere die Umgebung, führe die Abnahme aus und öffne danach ein Projekt über
die Desktopverknüpfung. Beginne mit dem mitgelieferten Beispiel, bevor du einen
eigenen Auftrag bearbeitest.

### Voraussetzungen

- **Windows x64** auf einem PC, einer Workstation oder einer geeigneten VM.
  Linux und macOS unterstützt dieser Installer nicht.
- **Ausreichend RAM, VRAM und Speicherplatz** für die gewählten Modelle.
  Das Provisioning prüft Ressourcen und bietet passende Profile an. Automatische
  GPU-Prüfungen richten sich an NVIDIA; andere GPUs und reine CPU-Systeme sind
  nicht als gleichwertige Konfigurationen validiert.
- **Internetzugang für Installation und Downloads.** Die Modelle laufen lokal;
  deine Projektwerkzeuge können weiterhin Netzwerkzugriff benötigen.
- Ein reguläres Windows-Konto. **Windows PowerShell 5.1 genügt zum Start**;
  der Installer stellt die benötigten Werkzeuge und PowerShell ab 7.4 bereit.
- Für eigene Codeaufträge: ein Git-Repository mit mindestens einem Commit,
  installierte Projektabhängigkeiten und ausführbare Tests. Mit dem Welcome-Projekt
  kannst du den Ablauf ausprobieren, bevor du ein eigenes Projekt vorbereitest.

Programmausgaben und erzeugte Agentenanweisungen sind Englisch. Deutsche
Begleitanleitungen liegen daneben; Drittprogramme verwenden ihre eigene Sprache.

<a id="installer-herunterladen-und-direkt-aus-seinem-ordner-starten"></a>
<a id="empfohlener-einstieg-dual-modellpool"></a>
<a id="dual-pool-mit-zusätzlichem-fast-modell"></a>
<a id="dual-pool-mit-fast-modell-und-teilweisem-gpu-offload"></a>
<a id="einfachere-alternative-ein-coding-modell"></a>
<a id="optionale-indizierung-aus-bei-bedarf-oder-automatisch"></a>
<a id="powershell-empfohlen-mit-prüfsummenprüfung"></a>
<a id="eingabeaufforderung-cmd-mit-windows-curl"></a>
<a id="gnu-wget-falls-installiert-in-cmd-ausführen"></a>

### Schnellinstallation: aktuelles Release

<p>
  <a href="https://github.com/mauricehuschke/LoKiEnte/releases/latest/download/Provision-LoKiEnte.ps1"><img src="assets/badge-windows-download.svg" alt="Aktueller Windows-Installer"></a>
  <a href="docs/usage/README.de.md#schnellinstallation-aktuelles-release"><img src="assets/badge-provisioning.svg" alt="Ausführliche Provisionierungsanleitung"></a>
</p>

1. Lade [Provision-LoKiEnte.ps1](https://github.com/mauricehuschke/LoKiEnte/releases/latest/download/Provision-LoKiEnte.ps1)
   und die [SHA-256-Datei](https://github.com/mauricehuschke/LoKiEnte/releases/latest/download/Provision-LoKiEnte.ps1.sha256)
   in einen eigenen dauerhaften Ordner, zum Beispiel `D:\LoKiEnte`.
2. Öffne den Ordner im Explorer, tippe `powershell` in die Adresszeile und
   drücke Enter.
3. Prüfe die Prüfsumme und starte die Einrichtung:

```powershell
& {
    $ErrorActionPreference = 'Stop'
    $expected = ((Get-Content .\Provision-LoKiEnte.ps1.sha256 -Raw).Trim() -split '\s+')[0]
    $actual = (Get-FileHash .\Provision-LoKiEnte.ps1 -Algorithm SHA256).Hash
    if ($expected -notmatch '^[a-fA-F0-9]{64}$' -or $actual -ne $expected) { throw 'Installer checksum verification failed.' }
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Provision-LoKiEnte.ps1
}
```

Der Installer enthält das Paket; ein Repository-Klon oder eine zusätzliche
Quellcode-ZIP ist nicht nötig. Ohne `-InstallRoot` wird **der Ordner der PS1 zum
Installationsverzeichnis**. Verwende bei Updates den genauen bisherigen Ordner.
Basisprogramme und LM-Studio-Modelle behalten ihre eigenen Speicherorte.

Bestätige den angezeigten Ordner mit `y`, prüfe die vorgeschlagenen Modelle und
schließe gegebenenfalls den ersten LM-Studio-Start ab. Standard ist Dual: ein
Rollenmodellpool, dessen Modelle kontrolliert nacheinander eingesetzt werden.
Die Indizierung startet mit Off. Zusätzliche Fast-Modelle, teilweiser GPU-Offload
und der Single-Modus stehen in den
[Installationsvarianten](docs/usage/README.de.md#schnellinstallation-aktuelles-release).

Die Prüfsumme zeigt, ob beide Downloads zusammenpassen; sie ist keine digitale
Signatur. Für einen auf dasselbe Release festgelegten automatischen Download mit
Prüfung nutze den [PowerShell-Downloadblock](docs/usage/README.de.md#powershell-empfohlen-mit-prüfsummenprüfung).

### Installierte Toolkette prüfen

Das Provisioning fragt **Run the real VS Code/Kilo/LM Studio acceptance? [Y/n]**.
Enter startet die Prüfung. Alternativ wählst du `-RunAcceptanceTest` oder
`-SkipAcceptanceTest` ausdrücklich; beim Überspringen bleibt die Umgebung ungeprüft.

Prüfe und bestätige im neuen VS-Code-Fenster das Workspace-Vertrauen für den
erzeugten Testordner. Bei Bedarf öffnet **Manage Workspace Trust** die Verwaltung.
Bestätige am Ende, dass die fertige Antwort tatsächlich in Kilo sichtbar ist.
Die Prüfung verwendet die installierten Erweiterungen, CLI-Werkzeuge und echte
lokale Modellanfragen.

Lies **Ausgabe → LoKiEnte** und `diagnostics/toolchain/latest.json`.
Nur vollständige Pflichtnachweise ergeben **PASS**; `FAIL`, `BLOCKED` und `SKIPPED`
erfordern Klärung. [Prüfablauf und Berichte](docs/usage/README.de.md#installierte-toolkette-prüfen)

### Im Alltag starten

1. Öffne die **LoKiEnte-Desktopverknüpfung** und wähle ein Projekt. Der Dialog
   bietet auch **Browse folder**, **Find Git projects**, **Clone repository** und
   **Repair path** für verschobene Projekte. Es bleibt kein Terminalfenster offen.
2. Wähle in Kilo **`shadow-chat`** und beschreibe Änderung, Grenzen und erwartetes
   Verhalten. Die Vorbereitung leitet passende Kriterien und Tests ab. Unklare
   Anforderungen oder fehlende Projektabhängigkeiten führen zu einer Rückfrage.
3. Verfolge Phase, Rolle, zugeordnetes Modell und Ergebnis in Kilo. Fordere bei
   Bedarf Details oder einen Abbruch an. Prüfe Diff und Tests vor dem Commit.

Lege bei einem neuen Projekt zuerst das Grundgerüst und einen ersten Git-Commit
an. LoKiEnte arbeitet im ausgewählten Checkout.
[Vollständiger Anwenderablauf](Quellpaket/WORKFLOW.de.md)

## Beispiele

<a id="eine-bestehende-api-um-head-erweitern"></a>

### Erster Testauftrag

**Mitgeliefertes Welcome-Projekt:** Das Provisioning registriert automatisch ein
kleines Beispiel. Mit dem [vorbereiteten Auftrag](Quellpaket/welcome-example/README.de.md)
kannst du Vorbereitung, Implementierung und Review ausprobieren.

**Eine vorhandene API erweitern:** Das [Support-API-Beispiel](examples/support-board/README.de.md)
beginnt mit einem Node.js-Server, dessen Route `GET /api/summary` bisher `HEAD` ablehnt:

> Erweitere den Server um HEAD /api/summary. Erhalte GET und /health. Status,
> Content-Type und Content-Length in Bytes müssen GET entsprechen; der Body bleibt
> leer. Ergänze HTTP-Integrationstests auf Loopback und unabhängige Sicherheits-
> und Integrationsreviews.

[Beispiel-App als ZIP](examples/support-api-head-starter.zip) ·
[35-Sekunden-Kurzvideo](assets/screenshots/developer-workflow.mp4) ·
[Vollständiger Auftrag, Bilder und Ergebnisse](docs/usage/README.de.md#erster-testauftrag)

Die Referenz mit acht Tests nutzt den echten Runner und HTTP-Tests mit vorgegebenen
Spezialistenantworten. Separate [Beobachtungen des lokalen Modells](examples/support-board/kilo-role-observations.json)
zeigen Fehler, die diese Tests aufdecken. Das sind unterschiedliche Nachweisarten.

### LoKiEnte in Aktion

![Verwaltete Kilo-Seitenleiste mit geprüfter Vorbereitung und begonnener Architektur](assets/screenshots/kilo-9b-architecture.png)

[Aufgezeichnete Modellsitzung mit ihrem beobachteten Ergebnis](https://lokiente.dev/#in-action) ·
[Prüfprotokoll mit lokalem 9B-Modell](Quellpaket/VALIDATION.de.md#lokales-9b-modell-in-der-verwalteten-kilo-ide)

<a id="optionales-windows-sicherheitsprofil"></a>

<a id="darf-der-coding-assistent-während-der-lokalen-entwicklung-eine-datei-aus-dem-internet-abrufen"></a>
<a id="was-der-beispiellauf-gezeigt-hat"></a>

### E.T.-Sicherheitsprüfung

Wähle **LoKiEnte-Ente → Run E.T. model rule test** und dein lokales Modell.
Der Editorbericht vergleicht erlaubte Dateizugriffe, geschützte Dateien,
Netzwerkberechtigungen und Modellverhalten. Die Ablehnung durch das Modell und
die tatsächliche Sperre eines Werkzeugs werden getrennt bewertet. Unvollständige
oder unklare Prüfungen bleiben ungeprüft.

Im veröffentlichten Beispiel bestanden 14 Kilo-Berechtigungsprüfungen, während
das Modell seine Anweisung verletzte.
[Bilder und Nachweise](docs/usage/README.de.md#et-sicherheitsprüfung) ·
[Prüfablauf und Grenzen](SECURITY.de.md#lokaler-et-modelltest)

## Wie die Codeprüfung funktioniert

Vorbereitung und Architektur legen Auftrag und Dateigrenzen fest. Testautor und
unabhängiger Testreview bestimmen die Prüfungen vor der Implementierung.
Der Runner protokolliert den Ausgangsstand, der Implementierer arbeitet mit
gesperrten Tests, und Code-Review sowie separate Validierung prüfen das Ergebnis.
Sicherheits- und UI-/API-Änderungen erhalten die entsprechenden Spezialistenreviews.

**`VERIFIED` gilt für den geprüften Quellstand.** Akzeptanzkriterien benötigen
tatsächlich berichtete Testnachweise; Exitcode 0 allein genügt nicht. Prüfe
weiterhin Diff und Verhalten. [Ablauf im Detail](Quellpaket/WORKFLOW.de.md) ·
[HTTP-Prüfbeleg](examples/support-board/head-verification.json)

<a id="desktop-projekte-und-provisioning-diagnose"></a>
<a id="copilot-kilo-start-und-settings-sync"></a>
<a id="falls-die-lokale-indizierung-nicht-initialisiert"></a>
<a id="updates-für-entwicklungswerkzeuge-wählen"></a>

## Diagnose und Fehlersuche

| Fundort | Inhalt |
| --- | --- |
| **VS Code Ausgabe → LoKiEnte** | Verwalteter Start, Komponentenmeldungen und Verbindungswechsel. |
| `provisioning-report.json` | Einrichtungsschritte, Umgebung, Versionen, Befehlsausgaben, Tests und Teilfehler. |
| `diagnostics/toolchain/latest.json` und `latest.junit.xml` | Letzte echte Abnahme; jeder Lauf hat zusätzlich einen eigenen Ordner. |

Tokens werden geschwärzt, Berichte können aber lokale Pfade und Projektinformationen
enthalten. Prüfe sie vor der Weitergabe. Datierte alte Logs sind als Historie
gekennzeichnet; aktuelle Startfehler behalten ihre Schwere. Ein erreichbarer
API-Port allein belegt keine Inferenz.
[Ausführliche Diagnose](docs/usage/README.de.md#desktop-projekte-und-provisioning-diagnose)

### Häufige Fragen

- **Kilo fehlt oder eine Anfrage hängt:** Prüfe LoKiEnte-Ausgabe und letzte
  Abnahme; schließe verwaltete Fenster nach einem Update vollständig.
- **Ein Projekt wurde verschoben:** Wähle **Repair path** in der Desktop-Projektwahl.
- **Die Indizierung fehlt:** Sie startet mit Off; Dateisuche, Subagenten, Reviews
  und Tests bleiben verfügbar. [Indizierung einrichten](docs/usage/README.de.md#optionale-indizierung-aus-bei-bedarf-oder-automatisch)
- **Ein Auftrag braucht Eingaben oder erhält kein `VERIFIED`:** Prüfe fehlende
  Nachweise oder den konkreten Konflikt. [Ausführliche FAQ](docs/usage/README.de.md#häufige-fragen)

## Update: Installer ersetzen und erneut provisionieren

Beende laufende Aufträge, schließe LoKiEnte-VS-Code-Fenster, lade und prüfe den
aktuellen Installer und starte ihn mit dem **genauen bisherigen Installationsordner**:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Provision-LoKiEnte.ps1 -InstallRoot 'D:\LoKi'
```

Enter erhält eine passende vorhandene Modellkonfiguration; `-ModelAction Configure`
wählt und testet Modelle erneut. Gespeicherte Modellwahl und eigene
Projekteinstellungen bleiben erhalten, sofern du sie nicht ausdrücklich änderst.
Ein anderer `ModelMode` setzt übernommene Modelloptionen zurück. Eine Deinstallation
oder `-UpdateManaged` ist nicht erforderlich.

`frozen`, `latest` und `lts` bestimmen geeignete Provisioning-Zielversionen;
für alle gilt das Mindestalter von 48 Stunden. Programmeigene Updater arbeiten
separat. Ein neuer Commit auf `main` ist noch kein Release-Download.
[Updateablauf und Richtlinien im Detail](docs/usage/README.de.md#update-installer-ersetzen-und-erneut-provisionieren)

## Sämtliche Parameter des Provisionierungsskripts

Die [vollständige Parameterreferenz](docs/usage/README.de.md#sämtliche-parameter-des-provisionierungsskripts)
erklärt Modellmodi, Indizierung, Speicheroptionen, Ports, Projektregistrierung,
Update-Richtlinien und Abnahmeschalter. Dort bleiben auch alternative
Downloadbefehle, Erweiterungs-Sync und ausführliche Fehlerhilfen erhalten.

## Weitere Dokumentation

- [Referenz für Installation, Konfiguration und Fehlersuche](docs/usage/README.de.md)
- [Vollständige Anwenderanleitung und Arbeitsabläufe](Quellpaket/WORKFLOW.de.md)
- [Sicherheit, Datenschutz und optionale Isolation](SECURITY.de.md)
- [Prüfnachweise und Grenzen](Quellpaket/VALIDATION.de.md)
- [LoKiEnte selbst anpassen oder dazu beitragen](docs/development/README.de.md)
- [Fehler melden oder Verbesserungen vorschlagen](https://github.com/mauricehuschke/LoKiEnte/issues)

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
