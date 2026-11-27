## Austausch des Windows-Abnahmeberichts - Paket 2026.11.27.7

Der nächste Ziellauf brach direkt nach Workspace Trust mit EPERM beim Umbenennen
einer vollständigen temporären Datei auf acceptance.json ab. Eine echte Windows-
Reproduktion hält die Zieldatei mit FileShare.ReadWrite ohne Delete-Freigabe offen
und erzeugt denselben EPERM-/rename-Fehler. Der PowerShell-Koordinator las diese
Datei bisher regelmäßig per Get-Content. Die einzelne Logzeile belegt nicht, welcher
Prozess das Handle hielt; externe Leser können denselben Fehler auslösen.

Der Koordinator liest vollständige Schnappschüsse nun mit ReadWrite- und Delete-
Freigabe. Atomare Schreibvorgänge erhalten die Zieldatei und wiederholen EPERM,
EACCES und EBUSY höchstens fünf Sekunden. Andere Fehler brechen sofort ab. Bleibt
der Austausch gesperrt, bleibt die vollständige temporäre Datei zur Diagnose
erhalten. Die Abnahme endet mit FAIL und schreibt acceptance.failure.json samt
JUnit. Der Koordinator übernimmt dieses Endergebnis, aktualisiert latest.json/JUnit
und meldet es an Provisioning. Neustartsperre und Wiederverwendung eigener
Testprojekte berücksichtigen den Fehlerbericht ebenfalls; VS Code prüft weiterhin
das aktuelle Workspace-Vertrauen. Schreibfehler werden getrennt von Vertrauens-,
Modell- oder Aktivierungsfehlern erfasst. Endgültiges JSON folgt seiner JUnit-Datei.

Test-AcceptancePersistence.mjs besteht sechs Prüfungen: vorübergehende Sperrcodes,
dauerhafte Sperren mit erhaltenen Nachweisen, sofortiger Abbruch bei anderen
Fehlern, echte Windows-Sperre mit anschließender Freigabe, endgültiger Fehlerbericht
ohne native/Modellarbeit und 150 echte Node-Schreibvorgänge parallel zu 150 echten
PowerShell-Lesevorgängen. Die Startsuite besteht 56 Checks einschließlich Übernahme
des Fehlerberichts bei weiterhin RUNNING im alten Hauptbericht und FAIL in
latest.json. Ihre GUI-Grenze ist synthetisch; Zielinferenz und Darstellung sind
damit nicht belegt.

Der gemeinsame JavaScript-Lauf mit 14 Dateien besteht 98 Tests ohne übersprungene
oder fehlgeschlagene Fälle. Alle acht ausgewählten PowerShell-Suiten bestehen:
Abnahmestart, Richtlinien, Provisioning-Integration, native Fristen, VS-Code-Profil/
VSIX, Desktop-Runner, Provisioning-Bericht und automatische Optionen. Dazu gehört
ein echter konsolenfreier WinExe-Sammler mit Kindprozess. Bestehende Modellwahl-,
Klon- und Junction-Zweige des vorherigen Kandidaten wurden nicht erneut geprüft;
ihre dokumentierten Hosteinschränkungen bleiben von der Zielabnahme getrennt.

Die Zielabnahme dieses exakten Kandidaten bleibt UNVERIFIED. Provisioning und
Abnahme auf dem Ziel-PC erneut ausführen. Docker und Hyper-V sind nicht nötig.
Vor erfolgreicher Zielabnahme gibt es keinen PR, Main-Merge oder Release.

## Automatische Modelloptionen und Configure-Modellreset - Paket 2026.11.27.6

Das nächste Ziel-Setup brach nach der Prüfung vorhandener Modelldateien ab: Ein
manuell geladenes LM-Studio-Modell hatte nach dem Löschen der Laufzeitdaten keinen
erhaltenen LoKiEnte-Eigentumsnachweis. Configure stoppt nun den bekannten inaktiven
verwalteten Router, entlädt eindeutig identifizierte lokale Instanzen gezielt per
zeitlich begrenzter REST-Anfrage und prüft die leere Modellliste vor GPU-/RAM-Messung
für Empfehlungen und Smoke-Tests. Dieser explizite Configure-Schritt kann aktive
lokale Inferenz unterbrechen. Modelldateien und die normalen Eigentumsprüfungen
des Runners/Controllers bleiben erhalten. Fehlende ausdrücklich gewählte eigene
Single-Modelldateien liefern weiterhin vor einer Unterbrechung die manuellen
Downloadhinweise. Keep führt keinen Modellreset aus.

Neue Schalter durchlaufen PS5.1-Bootstrap, JSON-Kindprozess und PS7-Setup:
UseRecommendedModelsBasedOnGPU wählt aktuelle GPU-/RAM-Empfehlungen ohne Modellfragen
(Configure, identische vorhandene Dateien nutzen, fehlende herunterladen);
SilentMode bestätigt die erste Installationsabfrage ausdrücklich für diesen Aufruf;
WorkspaceTrust bevorzugt ein eigenes früher vertrautes Testprojekt im selben
Arbeitsprofil. Die Berichtslauf-ID bleibt neu; Projekt und Workspace-Pfad bleiben
gleich. VS Code muss das tatsächliche aktuelle Vertrauen bestätigen. Neue/gelöschte
Profile, Widerruf und fehlende Historie können die normale Rückfrage erfordern.
Keine Vertrauensdatenbank oder globale Sicherheitsoption wird bearbeitet. Die
Kilo-Sichtprüfung bleibt manuell und beachtet Abbruch/Gesamtfrist. LM Studios
Katalogerkennung endet nach höchstens 30 Prüfungen. Bestätigungsquelle, automatische
Auswahlstrategie/Hardware und Reset-Ergebnis werden lokal protokolliert.

Lokale Regressionen: 92 JavaScript-Tests im gemeinsamen Lauf von 13 Dateien bestanden.
Die PowerShell-Gruppe bestand 27 Suiten; nativer Git-Klon und Junction-Anlage bleiben
durch diesen Entwicklungshost BLOCKED. Zusätzliche bestehende Modellwahl- und
Bootstrap-Junction-Zweige haben dieselbe Hosteinschränkung. Neue Optionsprüfungen
bestanden 20 Checks mit echten Hashes/Dateien und realer JSON-/PowerShell-Übergabe;
der Configure-Reset bestand 23 Checks zu fehlender Eigentumsdatei, gezieltem Entladen,
Nachkontrolle und unveränderten normalen Eigentumsprüfungen. Die Startsuite bestand
53 Checks einschließlich echtem Git-Projekt-Reuse bei neuer Berichtslauf-ID.
Modellpool 51, native Fehlerbehandlung 29 und Teil-GPU-Offload 14 Checks bestanden.
Echte Setup-Integrationsschritte belegen automatische Empfehlungen ohne Rückfragen
bis zur Pool-Grenze und keinen Reset unter Keep.

Dieser Kandidat verändert keinen laufenden Test/Installation auf einem anderen PC.
Echtes GPU-/Modellentladen, Inferenz und GUI-Abnahme sind dort mit genau diesem Paket
neu zu prüfen. Die Zielabnahme bleibt UNVERIFIED. Erst erfolgreiche Nachweise erlauben
PR, Main-Merge und Release. Docker und Hyper-V sind nicht erforderlich.

## Kilo-Start, Output-Rückkopplung und Abnahme im Arbeitsprofil - Paket 2026.11.27.5

Die nächste Zieldiagnose zeigt einen vertrauten Host und danach eine in weniger
als vier Sekunden blockierte Abnahme: Kilo wurde vor abgeschlossener Erkennung
abgefragt. Derselbe Host aktivierte Kilo etwa zwölf Sekunden später. Kein
Modell-Roundtrip lief. Dem erzeugten Projekt fehlten Git-Repository und erster
Commit. Ein Handler des Swagger Viewers für Dokumentänderungen erzeugte 153
Renderer-Fehler, während das bereits fertige Testfenster weiter Logs übernahm.
Der Upload enthält Diagnose-/Abnahmenachweise, keinen neuen Provisioning-Report.

Dieser Kandidat wartet auf Kilos Erkennung und erfasst installierte und im Host
sichtbare Erweiterungen getrennt. Das synthetische Projekt erhält per echtem,
zeitlich begrenztem Git ein eigenes Repository mit erstem Commit. Geerbte
Git-Schreibumleitungen, Hooks und Signierung werden dabei nicht verwendet.
Benutzer-Repositories bleiben erhalten. Kilos Worktree-Verwaltung benötigt einen
vorhandenen Commit als Ausgangspunkt.

Die Abnahme nutzt jetzt das tatsächliche verwaltete Arbeitsprofil und installierte
Erweiterungsverzeichnis. Desktop und Test teilen nativen Sammler, Startargumente,
Umgebungsaufbau und Workspace-Generator. Offene verwaltete Fenster blockieren den
Start. Datei-Prüfsummen der Konfiguration/Quellen, ausdrücklich gesetzte wirksame
Einstellungen, verfügbare Benutzer-/Workspace-Werte und gespeicherte gegenüber
laufender Kilo-Konfiguration müssen übereinstimmen. Geerbte Standard-Objektschlüssel
bleiben zulässig. Die im echten Host sichtbaren Erweiterungen werden erfasst.
Der Seitenleistenbefehl fragt nach dem Schließen seines Fensters und startet danach
dieselbe native Abnahme durch einen unsichtbaren Runner.

Identische kürzlich erfasste VS-Code-Warnungen/-Fehler samt Stackfortsetzungen
werden je Quelle mit stillen Zählern und Originalpfaden zusammengefasst. Andere
Fehler bleiben sichtbar; die Original-Logs behalten alle Vorkommnisse. Das
unterbricht die Output-Rückkopplung ohne Änderung der Dritterweiterung. Erst nach
gespeichertem Bericht erscheint das Ergebnis, die Weiterleitung im Testfenster
stoppt, und ein Host-Neuladen wiederholt keinen fertigen Lauf. Abbruch und
Gesamtfrist blockieren die Abnahme, beenden deren nativen Kindprozess und erhalten
Befehlsnachweise. Ein späterer Inferenz-PASS lässt sich daraus nicht ableiten.

Lokale Nachweise: 89 JavaScript-Fälle im gemeinsamen Lauf von 13 Dateien bestanden.
Der PowerShell-Lauf bestand 22 Suiten; nativer lokaler Git-Klon und Junction-Anlage
bleiben durch Windows-Einschränkungen dieses Entwicklungshosts BLOCKED. Die neue
Startprüfung bestand 28 Checks mit echtem Node/Git/Dateisystem/Workspace-Aufbau
und simulierter GUI-Grenze einschließlich vorzeitig beendetem Editor. Der native
Sammler schreibt den Exitstatus atomar mit begrenzten temporären Pfadlängen. Die
zusätzliche Bootstrap-Suite ist bei der Junction-Anlage auf diesem Host BLOCKED.
Der kontrollierte Dokumentänderungs-Test kommt zur
Ruhe und leitet neue andere Fehler weiterhin weiter. Der gelieferte Renderer-Log
reduziert sich von 153 Swagger-Meldungen auf seine zwei unterschiedlichen Blöcke;
insgesamt werden 170 identische Warn-/Fehlerblöcke mit 3.643 Zeilen unterdrückt.

Echte VS-Code-/Kilo-/LM-Studio- und Sichtabnahme auf dem Ziel-PC bleiben UNVERIFIED.
Docker und Hyper-V werden nicht benötigt. Mit dem erzeugten Installer dieses
Branches neu provisionieren, verwaltete Fenster schließen und den nativen Test
wiederholen. Erst erfolgreiche Zielnachweise erlauben PR, Main-Merge und Release.

## Provisioning-Diagnose, nativer Launcher und Projektreparatur - Paket 2026.11.27.3

Dieser Stand ergänzt laufende Berichte mit Schema 2, Bootstrap-Übergabenachweise,
geschwärzte native stdout-/stderr-Ausgaben und den Erhalt teilweiser Abnahmenachweise.
Die Desktopverknüpfung verweist auf ein kompiliertes Windows-GUI-Programm. Echte
Prozess-/Argument-/Schwärzungstests prüfen den Sammler ohne Konsole. Erst eine zum
Start, Helferstand und Profil passende Bestätigung bestätigt VS Code. Kilos Erkennung
wartet auf spätere Registrierung; installierte Manifeste und laufende Extensions
werden getrennt erfasst.

Die Zielabnahme benötigt weder Docker noch Hyper-V. Die nativen Abhängigkeitsprüfungen
enthalten zusätzlich zu Kilo/Konfiguration/Werkzeugen/Suche einen synthetischen lokalen
Git-Klon. Die Projektwahl behält vorhandene Ordner und ergänzt begrenzte Git-Suche,
Klonen und Pfadreparatur mit Backups sowie Erhalt von Aufgaben/Prüfungen/Einstellungen.

Neue relevante Tests: Test-ProvisionReport.ps1 (echte Dateien/Prozessausgaben),
Test-DesktopRunner.ps1 (echtes Windows-GUI-Programm samt Kindprozess; simulierter
Host-Handshake), Test-KiloStartup.mjs (simulierte Extension-Registrierung),
Test-ProjectGit.ps1 (echtes Git und Dateisystem-Reparatur), Test-ProjectSelection.ps1
und Test-LauncherIcon.ps1. Die Dialogansicht und echte VS-Code-/Kilo-/LM-Studio-Inferenz
müssen weiterhin auf dem Zielsystem abgenommen werden.

Der native Git-Klon-Test ist in dieser Agent-Sitzung BLOCKED: Windows verweigert
MSYS NtCreateDirectoryObject mit 0xC0000022. Unabhängige Such-/Reparaturprüfungen laufen
mit einem gesondert initialisierten Repository weiter; sie zählen nicht als erfolgreicher
Klon. Bestehende Junction-Prüfungen bleiben ebenfalls durch Zugriffsverweigerung blockiert.
Es werden dafür weder VM noch Container verwendet. Fehlender Nachweis auf dem Ziel-PC
bleibt ausdrücklich ungeprüft.

## Nachbesserung zum Zielrechner-Bericht - Paket 2026.11.27.4

Der gelieferte Windows-Lauf von Build 2026.11.27.3 endete mit Warnungen. Die echte
Abnahme meldete einen Host-PASS und acht BLOCKED-Fälle wegen fehlendem Workspace
Trust. Kilo-/UI-Inferenz wurde in dieser Abnahme nicht ausgeführt. Die separaten
Provisioning-Smoke-Tests bestanden für drei Modelle; coder-high blieb ungeprüft.
Der absichtliche CLI-Fähigkeitstest ohne Modell war der einzige native Befehl mit
Exitcode ungleich null. Ein fehlender registrierter Projektordner ist eine eigene
Reparaturwarnung.

Korrekturen dieses Builds:
- Normaler VS-Code-Start mit isoliertem Profil und installiertem Helfer 0.3.2
  ersetzt den Extension-Entwicklungs-/Teststart. Workspace Trust bleibt aktiv;
  Manage Workspace Trust öffnet die Verwaltung. Die Entscheidung hat bis zu zehn
  Minuten Zeit; laufender Report und Konsole zeigen die Wartephase. Es werden
  weder Vertrauensdatenbank noch globale Sicherheitseinstellungen geändert.
- LM-Studio-Gesamtschätzung minus GPU-Anteil wird gegen Host-RAM geprüft,
  GPU-Anteil gegen VRAM; Reserven von 3 GiB/1 GiB bleiben bestehen. Einzelmodell
  und Modellpool verwenden dieselbe Prüfung. Ungültige Schätzungen oder geringe
  Sicherheit erlauben weiterhin keinen normalen Ladevorgang. Die gemeldete
  Hardware-/Schätzkombination ist synthetisch abgedeckt; echtes Laden ist auf dem
  Zielrechner erneut zu prüfen.
- Kontext-/Speicherzahlen und Wahrheitswerte bleiben im JSON erhalten;
  Pipeline-Zahlen werden nicht mehr zu leeren Objekten.
- Nur der genaue negative Fähigkeitstest traegt EXPECTED_NONZERO_EXIT; Exitcode
  und Streams bleiben erhalten. Echte Modell-/Runtime-/Authentifizierungsfehler
  bleiben Fehler. Historische Logs behalten ihren Schweregrad als Kennzeichnung,
  erzeugen aber keine neue Live-Fehlermeldung.

Lokale Regressionen: 70 JavaScript-Fälle im gemeinsamen Lauf von zehn Dateien
bestanden; Modellpool 51, Teil-Offload/Speichergrenzen 14, Einzelmodell-Fit 6,
native Modellfehler 29, CLI-Kompatibilität 16, CPU-Embedding 47, Reportwerte 13
und Abnahmerichtlinie 25 Prüfungen bestanden. Im ersten breiten Lauf überschritt
der Deadline-Test unter Last seine Grenze. Prozessstart und Befehlsausführung
nutzen jetzt ein gemeinsames Zeitbudget; danach bestand die unveränderte Suite
für native Befehle/Kilo-Konfiguration/Logging mit sieben Prüfungen. Lokaler
Git-Klon und Junction-Erstellung bleiben durch die Agentenumgebung BLOCKED.
Der Audit unter Windows PowerShell 5.1 bestand alle 51 Prüfungen, einschließlich
der extrahierten Fähigkeits-Hilfsfunktion. Die abschließenden Diagnose-/Starttests
bestanden 20 Fälle, darunter aktuelle Startfehler gegenüber datierter Loghistorie.
Dies ist ein Fix-Kandidat auf eigenem Branch. Ein neuer bestandener
Zielrechner-Lauf mit echten Kilo-Antworten ist Voraussetzung für PR, Main-Merge
und Release.

## Echte Toolketten-Abnahme und gemeinsame Ausgabe - Paket 2026.11.27.2

Nach der Einrichtung bietet das Provisioning die echte Abnahme an. RunAcceptanceTest
und SkipAcceptanceTest werden durch Bootstrap und Anfrageübergabe weitergereicht.
Enter startet den Test. Überspringen schreibt SKIPPED in JSON und JUnit und erzeugt
eine Warnung über die ungeprüfte Umgebung. FAIL liefert Exitcode 1, BLOCKED 2;
ausdrückliches Überspringen liefert 0 ohne einen Funktionsnachweis zu behaupten.

Der Live-Test verwendet installiertes Desktop-VS-Code mit echtem Extension Host,
installiertes Kilo samt eingebetteter Runtime, die vorbereitete lokale Konfiguration
und LM Studio. Er prüft Extension-Abhängigkeiten, Konfiguration/Werkzeugimporte/Suche
in beiden Kilo-Runtimes, echte Datei-Leseaufrufe mit abschließender Modellantwort für
jedes konfigurierte Modell und eine echte Kilo-Webview-Anfrage. Im Dual-Modus werden
Anfrage und erwarteter Antwortinhalt über einen zufälligen Nonce-Hash zugeordnet;
Prompts und Antworten werden nicht in Router-Ereignisse geschrieben. Die sichtbare
Chatantwort erfordert eine gesondert als manuell gekennzeichnete Sichtprüfung.
Fehlende, unvollständige, übersprungene oder nicht interaktiv bestätigte Nachweise
können niemals ein vollständiges PASS ergeben. Bei aktiviertem Indexing kommen echte
Embedding-Inferenz und LanceDB-Schreib-/Suchprüfung hinzu. Vollständige Repository-
Indexierung bleibt ein separater Arbeitslasttest.

Die Ausgabe LoKiEnte vereinigt verfügbare verwaltete VS-Code-/Kilo-Logs, Router-
Ereignisse, Controller-Logs, lokale Werkzeugereignisse und LM-Studio-Serverlogs mit
Quelle und Schweregrad. Gesundheitsprüfungen belegen Erreichbarkeit, keine Inferenz.
Regressionstests prüfen Schwärzung, begrenztes Nachlesen, UTF-8-Teilzeichen, Rotation,
HTTP-Ausfall/Wiederherstellung, ungültige/übergroße Antworten, Router-Zuordnung,
abgebrochene Streams und echte native Prozesse mit Zeitlimit/geerbten Ausgabekanälen.
Die Startup-UI-Unit-Tests simulieren VS Code und gelten nicht als echter Host-Nachweis.

Relevante Tests: Test-ToolchainAcceptance.mjs, Test-ToolchainDiagnostics.mjs,
Test-RouterEvidence.mjs, Test-ToolchainNative.ps1, Test-ToolchainPolicy.ps1,
Test-ToolchainProvisioning.ps1, Test-VsCodeStartup.mjs, Test-VsCodeProfile.ps1,
Test-RouterLifecycle.ps1, Test-RipgrepIntegration.ps1 und Test-SelectionIntegration.ps1.
Die installierte Abnahme startet über app/Test-Toolchain.ps1; vscode-tests/toolchain.cjs
ist der historische Extension-Host-Testeinstieg. Seit Build 2026.11.27.4 startet stattdessen
der installierte Helfer im normalen Fenster. Berichte bleiben lokal unter diagnostics/toolchain.

Lokale Validierung vom 27.11.2026: Der kombinierte JavaScript-Lauf mit neun Suiten
bestand 61 Fälle. Der abschließende Startup-Einzellauf prüft zusätzlich das Zeitlimit
beim Öffnen der Kilo-Seitenleiste (11 Fälle). Abnahmerichtlinie/Vorbereitung bestanden
21 Prüfungen, Provisioning-Überspringen/Berichte 13, native Prozesse/Konfigurations-
Zeitlimit/LM-Studio-Protokollierung 7, VSIX/Profil 36 und Router-Lebenszyklus 18.
Der Audit unter Windows PowerShell 5.1 bestand 51 Prüfungen, native Modellbefehle mit
Fehlerfällen 25. Einstellungenserhalt, Modellwahl-/Suchintegration, Indexing-Richtlinie
und -Start, CLI-Auflösung, Werkzeugerkennung, Arbeitsbereichsanleitung und Lokalisierung
bestanden ebenfalls. Die Kilo-Import-Junction-Prüfung bleibt wegen verweigertem Windows-
Zugriff BLOCKED. Der Installer-Inhalt wird bytegenau mit allen Paketquellen verglichen;
öffentliche Quellen und dekodierter Inhalt werden mit Gitleaks geprüft. Diese Prüfungen
belegen keine Inferenz.

Die Zielabnahme ist in dieser Entwicklungsumgebung weiterhin UNVERIFIED: Hier gibt
es keine verwaltete D:\LoKi-Installation samt Kilo-Runtime. Ein isolierter Startversuch
des echten Desktop-Hosts lieferte vor seinem Zeitlimit keinen Extension-Host-Bericht
und wird nicht als bestanden gezählt. Die betroffene Installation auf dem anderen PC
muss den neuen Installer/Test ausführen und ihren eigenen Bericht erzeugen. Der
vorhandene Bootstrap-Junction-Test und die Kilo-Import-Junction-Prüfung bleiben wegen verweigerter Windows-
Junction-Erzeugung blockiert; diese Prüfung wurde nicht abgeschwächt oder bestanden erklärt.

## Begrenzte Modellwechsel und konkrete Fehler - Paket 2026.11.27.1

Im unveränderten Code kehrte ein nativer Prozessaufruf erst nach 12,75 Sekunden
zurück, obwohl sein Zeitlimit fünf Sekunden betrug: Ein Kindprozess hielt die
geerbten Ausgabekanäle nach Ende der CLI offen. Das Lesen der Ausgabe verwendet
jetzt dasselbe Zeitlimit und abbrechbare Leseoperationen. Status-/Katalogabfragen
und Speicherschätzungen sind auf 60 Sekunden begrenzt; echte Modellladevorgänge
behalten 900 Sekunden. Nach einem Timeout mit unklarem Ladezustand sperrt der
Router weitere Modellwechsel bis zu einem bewussten Neustart.

Regressionen prüfen echte Unterprozesse, geerbte Ausgabekanäle, den PowerShell-
Controller, Loopback-HTTP, Fehlerberichte, Modellaliasse und Installationspfade
mit Leerzeichen. Die LM-Studio-/GPU-Grenzen der Lebenszyklustests sind simuliert.
Nicht unterstützte Architektur, Speicherablehnung und andere Ladefehler bleiben
unterscheidbar. Gescheiterte Profile müssen vor erneuter Verifizierung alle
Chat-/Tool-Smoke-Tests bestehen. Routerzustand und Ereignisse zeigen Lade- und
Inferenzphase sowie Fehler ohne Promptinhalte; private Exceptiondetails bleiben
im lokalen Controllerbericht.

Geprüfte Bereiche: Modellladefehler, Modellpool, Single-Modus, LMS-CLI,
partielles GPU-Offload, Modellvarianten, manuelle Modelle, Embeddings,
Routerlebenszyklus, Modellpflege, gespeicherte Optionen, Sprachdateien und die
HTTP-Routen für Chat und Embeddings. Der Test für manuelle Modelle prüft jetzt
den tatsächlichen Modellkonfigurationszweig statt einer veralteten Annahme über
eine Zuweisung auf oberster Ebene; sein bisheriger Fehler wurde auch am
unveränderten Ausgangsstand bestätigt.

Die betroffene Nutzerinstallation liegt auf einem anderen PC. Erfolgreiches
manuelles Laden bestätigt dort noch keine verwalteten Kontext-/Offloadwerte
oder API-Zugriffe. Diese Regressionen belegen die korrigierten Wartezeiten und
Fehlerpfade, nicht die unbeobachtete Ursache oder echte erfolgreiche Inferenz
auf diesem PC. Die Korrektur wechselt Modelle und Runtimes nicht automatisch.

## LoKiEnte-Logo und anbieterneutrale Benennung - Paket 2026.11.18.21

<!-- lokiente-language -->
[English](VALIDATION.md) · Deutsch

Die Programmausgaben sind Englisch. Diese Datei ist die deutsche Dokumentation.
<!-- /lokiente-language -->

## Lokales 9B-Modell in der verwalteten Kilo-IDE

Am 24. November 2026 wurde derselbe Featureauftrag über die Seitenleiste von Kilo Code 7.8.30 im verwalteten VS-Code-Workspace eingegeben. LM Studio führte Qwen3.5 9B Q4_K_M lokal mit einem Kontextfenster von 16.384 Tokens aus. Jede Zeile gehört zu einer eigenen Chat-Sitzung. Das Modell erzeugte seine Antworten selbst. Der Auftrag war, die bestehende Summary-API um HEAD zu erweitern, GET-Header und Health-Endpunkt zu erhalten und Integrationstests zu ergänzen.

| Auftrag | Letzte beobachtete Phase | Ergebnis |
| --- | --- | --- |
| `09b33099` | Workflowstart | Git meldete einen fehlenden geerbten Konfigurationswert. Kein Spezialist startete. Behoben in [PR #13](https://github.com/mauricehuschke/LoKiEnte/pull/13). |
| `7f225dc0` | `shadow-preparer` | Der Agent untersuchte die Anwendung und lieferte syntaktisch ungültiges JSON. Der Runner stoppte vor der ersten Änderung. [PR #14](https://github.com/mauricehuschke/LoKiEnte/pull/14) ergänzte einen zweiten Versuch mit Leserechten. |
| `6b370348` | `shadow-architect` | Der zweite Versuch lieferte einen Vertrag, den ein eigener Agent freigab. Der Architekturauftrag verlangte anschließend eine fehlende AGENTS.md. Der Architekt lieferte einen Plan, aber der fehlgeschlagene Lesezugriff machte die Phase ungültig. Implementierung und Featuretests wurden nicht gestartet. |
| `fd50cc55` | `shadow-preparer` (zweiter Versuch) | Mit dem aktualisierten Architekturauftrag lieferte keiner der beiden Vorbereitungsversuche einen akzeptierten Vertrag. Der Runner beendete den zweiten Versuch. Es liefen keine Featuretests. Der Arbeitsstand in Git blieb sauber. |

Die unabhängige Ausgangsmessung ergab 405 für HEAD und 200 für GET. Alle vier Sitzungen in der IDE endeten mit `NOT_VERIFIED`. Der am weitesten fortgeschrittene Lauf erreichte nach Freigabe des Vertrags die Architekturphase. Der [separate erfolgreiche Referenzlauf](https://github.com/mauricehuschke/LoKiEnte/blob/main/examples/support-board/head-verification.json) nutzte vorgegebene Rollenantworten, echte Git-Prüfungen und lokale HTTP-Tests. Vor der Implementierung bestanden sechs von acht Tests, danach alle acht. Die [Tour](https://lokiente.dev/#in-action) kennzeichnet beide Ergebnisse getrennt.

## Optionale Startart der Indizierung — Paket 2026.11.19.1

Die Indizierung ist jetzt standardmäßig aus, auch für bestehende Projekte und
Installationen. Die Provisionierung bietet Off, OnDemand und Automatic an;
`-IndexingMode` überspringt das Menü. OnDemand bereitet Abhängigkeiten vor, ohne
Embeddings zu laden, und fragt bei jedem Launcherstart nach (Vorgabe Nein).
Automatic prüft Embeddings bei Setup und Start und berücksichtigt Kilos einmalige
Projektfreigabe. Eine fehlgeschlagene Vorprüfung lässt Kilos Indizierung für diesen
Start deaktiviert. Die interne VS-Code-Freigabedatenbank wird nicht verändert.
Befehle und erforderlicher Sitzungsneustart stehen in [README.de.md](README.de.md).

Prüfnachweise:

- Indexierungsregel/Migration: 32 Prüfungen; tatsächlicher Konfigurationspfad des
  Launchers: 8; Modellauswahl-Setupintegration: 5; CPU-Embedding und sicheres
  Deaktivieren/Entladen: 47. Geprüft werden Altinstallationsvorgaben, globale
  Deaktivierung bei erhaltener Projektfreigabe, kein Embedding-Start/-Download mit
  Off, OnDemand ohne Start, ausdrückliche Startauswahl, fehlgeschlagene Vorprüfung
  und Ablehnung des Entladens aktiver oder unklarer Modelle.
- Der echte Kilo-Indexer 7.8.30 blieb nach ausdrücklicher Projektfreigabe gegen
  einen synthetischen Server Disabled und stellte keine Embedding-Anfrage.
  Seine tatsächliche Konfigurationsprüfung akzeptierte das vollständige erzeugte
  Off-Profil ohne installiertes LanceDB. Das bestätigt die Deaktivierung, keine
  echte Modellinferenz oder Suchqualität.
- Alle 33 Node-Tests für Router/Start/Sync bestanden. Der vollständige Qualitäts-
  workflow bestand 54 Prüfungen mit echten Prozessen/Git und synthetischen
  Agentenantworten. Bestanden haben auch Modellpool (44), Teiloffloading (8),
  Router-Lebenszyklus (18), Provisionierungseinstellungen (6), Workspace-Migration
  (14), Sprachmigration (28), Startbefehle (7), Ripgrep-Setup (7), Workflow-Erkennung
  (13) und Tool-Import-Vorprüfung (18).
- Bootstrap/Übergabe: 42 Prüfungen; Installationsort-Migration und Audit jeweils
  51 unter Windows PowerShell 5.1. Diese Regressionen installieren keine echten
  Anwendungen, laden keine Modelle herunter und führen keine GPU-Inferenz aus.

Die Zielabnahme steht aus: Alle LoKiEnte-Fenster schließen, bestehende Installation
erneut provisionieren und Off, OnDemand Nein/Ja sowie Automatic an einem kleinen,
freigegebenen Projekt prüfen. Off soll ohne IDX-Fehler oder geladenes Embedding
starten, OnDemand Nein inaktiv bleiben und ein aktivierter Lauf bei ausreichendem
RAM und bereitem LM Studio Complete erreichen. Erweiterungs-Sync und Qualitäts-
prüfungen müssen weiterhin funktionieren. Main, Releases und Plattformbranches
bleiben unverändert.

## Konservatives Laden des CPU-Embeddings — Paket 2026.11.18.26

Der Zielbericht zeigte ein durch LOW-Schätzsicherheit blockiertes Laden ohne
gemeldete Schutzregelfreigabe. Die bisherige Sammelmeldung konnte fälschlich einen
gemessenen RAM-Mangel nahelegen. Die Regression prüft jetzt diese Eingabe mit
konservativem Budget und unveränderter Reserve sowie anschließendem Laden und
Inferenz. Diese Regel gilt ausschließlich für das hashgeprüfte CPU-Embedding-Modell.

Die Embedding-Suite bestand 44 Prüfungen: unlesbare Schätzung, farbige/umgebrochene
CLI-Ausgabe, fehlende Reserve, ausdrückliche Schutzregelablehnung, abgelehnter
Ladeversuch, RAM-Druck nach Laden/Inferenz und begrenztes Zurückrollen bei aktiven,
ausgetauschten oder doppelten Instanzen. Bestanden haben außerdem Modellpool (44),
Teiloffloading (8), Router-Lebenszyklus (18) und Auswahlintegration (3).
LM Studio, Modellinferenz und RAM-Messungen sind in diesen Tests simuliert; die
Indizierung auf dem Ziel-PC bleibt abzunehmen. Der Nutzer hat funktionierenden
Erweiterungs-Sync bestätigt; main und veröffentlichtes Release bleiben unverändert.

## Embedding-Kompatibilität und nur Erweiterungen synchronisieren — Paket 2026.11.18.25

Dieser Kandidat ist vom stabilen Release getrennt. Die neuen Tests für Embedding-
Router und Sync-Hilfe sowie die bestehenden Router- und Startup-Tests bestanden
alle 33 Node-Tests. PowerShell-Regressionen prüfen Embedding-Bereitschaft und
Diagnose, Router-Austausch, Profilerhalt, Provisionierungseinstellungen, Launcher,
Projektauswahl, Workspace-Migration, Modellpools und GPU-Teiloffloading.
Alle 14 ausgewählten PowerShell-Suiten bestanden 334 Prüfungen, einschließlich
vollständigem Qualitätsworkflow (54), Bootstrap (42), Sprachmigration (28),
Startskripten (4) und Installationsort-Migration mit Windows PowerShell 5.1 (51).
Die Tests verwenden synthetische Agentenantworten und installieren keine Programme
oder Modelle. Der Installer enthält alle 98 Quelldateien bytegenau mit passender
Prüfsumme. Syntaxprüfungen bestanden für 67 PowerShell-Dateien, 14 Node-Dateien und
den Python-Builder; 72 lokale Markdown-Links, zwei JSON-Dateien und sechs
JSON-Beispiele wurden validiert.

Der echte Kilo-Indexer 7.8.30 reproduzierte die gemeldete Initialisierungsmeldung,
wenn ein synthetischer lokaler Server `dimensions` ablehnte. Derselbe Indexer
erreichte über die neue Route Complete, mit echtem LanceDB 0.26.2 und synthetischen
768-dimensionalen Embeddings. Ein direkter Server, der das Feld akzeptierte,
funktionierte ebenfalls. Das belegt die Kompatibilitätskorrektur, aber weder die
Ursache auf einem Zielrechner ohne Logs noch die Suchqualität mit einem echten Modell.

Der gepackte Startup-Helfer 0.1.2 wurde in einem isolierten Profil von VS Code
1.146.0 mit Kilo 7.8.30 installiert und aktiviert. Beide LoKiEnte-Befehle, der
offizielle Sync-Konfigurationsbefehl und der Kilo-Fokusbefehl waren verfügbar;
Kilo war aktiv und die verwaltete Vorgabe zur KI-Sichtbarkeit blieb gesetzt.
Es wurde kein angemeldetes Konto verwendet. Der Helfer öffnet die offizielle
Auswahlliste; nur Extensions auszuwählen und zu bestätigen bleibt beim Nutzer.
Die Tests prüfen Hinweise und Fehlerbehandlung, keine vorgetäuschte automatische
Kategorieauswahl. Lokale Vorlieben und Daten des entfernten Kontos bleiben erhalten.

Installation auf dem Zielrechner, echte LM-Studio-Embeddings/GPU-Inferenz, fertige
Projektindizierung und angemeldeter Erweiterungs-Sync bleiben Abnahmeprüfungen.
Ein erfolgreicher Vorabtest oder geöffneter Sync-Dialog belegt diese Ergebnisse nicht.

## Englisch als Standard und deutsche Dokumentation — Paket 2026.11.18.22

40 eigenstaendige PowerShell-/Node-Testsuiten bestanden nach der Sprachumstellung.
Der vollstaendige Qualitaetsworkflow bestand alle 54 Pruefungen, der Bootstrap 42
einschliesslich Windows-PowerShell-5.1-Handoff. Modellantworten und GPU-/LM-Studio-
Grenzen bleiben synthetisch; Installation, Inferenz und GUI-Abnahme auf dem
Zielrechner werden dadurch nicht ersetzt.

`tests/Test-Localization.ps1` prueft 28 Aspekte: englische Standarddateien, deutsche
Begleitdateien, installierte Sprachlinks, Migration alter Tasks/Ordner, Erhalt
eigener Aufgaben/Einstellungen/Ordner/Anleitungen und Welcome-Readme-Umstellung
mit Sicherung. Nur eine unveraenderte mitgelieferte deutsche Welcome-Readme wird
auf Englisch umgestellt. Angepasste Anleitungen, Beispielcode und Git-HEAD bleiben
erhalten; fehlende deutsche Begleitdateien werden ergaenzt.

Die aktive Agentenkonfiguration bindet ausschliesslich die englischen Regeln ein.
Deutsche Regeln sowie Auftrags- und Welcome-Vorlagen liegen daneben. Menues,
Meldungen, Diagnosen und Workflowstatus des Pakets sind Englisch. Betriebssystem
und Fremdprogramme koennen weiterhin ihre eigene Sprache verwenden. Es gibt
keinen Laufzeit-Sprachschalter.

Authentifizierungsfehler besitzen jetzt eine sprachunabhaengige Fehlerkennung.
Die Embedding-Suite mit 24 Pruefungen testet HTTP 401/403 durch den echten API-
Wrapper: weiterhin blockierender Fehler, keine Ausgabe des Antwortinhalts.
Die Regression fuer konkurrierende Dateierstellung prueft den nativen I/O-
Fehlertyp statt des lokalisierten Windows-Textes. Modellwahl: 28 Pruefungen bestanden.

Zusaetzlich bestanden: Syntax fuer 65 PowerShell- und 9 Node-Dateien sowie den
Python-Builder; alle 16 oeffentlichen Provisionierungsparameter dokumentiert.
20 Markdown-Dateien bilden 10 Sprachpaare; lokale Links und sechs JSON-Beispiele
sind gueltig. PowerShell-Codeaenderungen ausserhalb der Texte betreffen nur das
Laden der Vorlagen, die zweisprachige Migration und die Authentifizierungskennung.

Die neu gebaute Einzeldatei enthaelt 86 Dateien, bytegenau mit dem Quellpaket
verglichen und mit passender SHA-256. Gitleaks und Zusatzpruefungen fanden in
aktuellen Dateien und der entpackten Nutzlast keine Zugangsdaten oder privaten
Identifikatoren. Diese Aussage betrifft Dateiinhalte, keine Bereinigung alter
Autorenmetadaten in Git.

39 eigenständige PowerShell-/Node-Testsuiten bestanden. Dazu gehören der
Bootstrap einschließlich Windows PowerShell 5.1, Welcome-Projekt, Modell- und
Updateprüfungen sowie der Kilo-Chat-zu-Runner-Ablauf mit synthetischen Modellantworten.
Der gespeicherte Name der API-Token-Umgebungsvariable bleibt beim Update erhalten.

Der neue Windows-Test `tests/Test-LauncherIcon.ps1` prüft acht Aspekte: ICO-Größen,
Windows-Dekodierung, gespeicherte Verknüpfungseigenschaften, Neuanlage,
Wiederholungsupdate und Sicherung/Umbenennung passender alter Verknüpfungen.
Eine Verknüpfung mit abweichendem Zielaufruf bleibt erhalten. Alle Verknüpfungen
werden in temporären Testordnern erzeugt; der echte Desktop wird nicht verändert.
Sechs Prüfungen bestätigen außerdem den Erhalt eigener VS-Code-Einstellungen,
Sicherungen und angepasster Terminalprofile bei der Umbenennung des verwalteten Profils.
Zusätzlich wurden die PNG-Frames aller sieben ICO-Größen und die bytegenaue
Übereinstimmung der eingebetteten Nutzlast mit dem Quellpaket geprüft.

Aktuelle Dateien, Bilddateien, entpackte Nutzlast und historische Inhalte wurden
mit Gitleaks und ergänzenden Prüfungen auf private Identifikatoren untersucht.
Keine Zugangsdaten oder privaten Identifikatoren im aktuellen Dateistand gefunden.
Eine Dateiprüfung ersetzt keine Prüfung der Autorenmetadaten der Git-Historie.

Der Projekttitel und sichtbare Meldungen verwenden LoKiEnte. Anbieterbezogene
Hardwareannahmen wurden aus der Beschreibung entfernt; technische Kennungen und
vorhandene Installationspfade bleiben für Updates kompatibel. Das Paket ist für
Windows x64 mit dem bestehenden NVIDIA-Prüfpfad ausgelegt, kein Linux-/macOS-Installer.
Eine echte Neuinstallation und Modellinferenz auf zusätzlicher Hardware sind
durch diese Regressionstests nicht belegt.

## Gesamtprüfung — Paket 2026.11.18.20

Der erneute Pakettest umfasst alle eigenständigen vorhandenen PowerShell- und
Node-Testsuiten, einschließlich Bootstrap/Windows PowerShell 5.1, Modellwahl,
Speichergrenzen, Router, Abhängigkeiten, Kilo-Konfiguration, vollständigem
Qualitätsworkflow und Chat-zu-Runner-Ablauf. Test-CoderWorkflow ist ein Alias
derselben QualityWorkflow-Suite und wird nicht doppelt gezählt.

Ergebnis: 38 eigenständige Testsuiten bestanden. Ein veralteter Testharness
für die Ripgrep-Setup-Integration wurde um die neuen Setup-Grenzen ergänzt
und erfolgreich wiederholt; die echten Registry-/Welcome-Abläufe besitzen
eigene Tests. Der vollständige Qualitätsworkflow bestand alle 54 Prüfungen.

Zusätzlich geprüft: Erhalt eigener VS-Code-Einstellungen und Terminalprofile
bei Aktualisierung der verwalteten Vorgaben (4 Prüfungen), Starthelfer mit
explizitem Updateziel und literal erhaltenen Pfaden (4), Welcome-Erstellung,
Wiederholung nach simuliertem Git-Fehler und Erhalt bearbeiteter Beispiele (14).
Welcome veröffentlicht erst ein vollständig initialisiertes Git-Repository.
Git-Umleitungen stoppen bereits vor Dateischreibvorgängen. Fehlgeschlagene
Aufbauten bleiben als getrennte Diagnoseordner erhalten und blockieren keinen
neuen Versuch am normalen Ziel.

Eigene Checks, Aufgaben und nicht verwaltete Einstellungen bleiben erhalten.
Verwaltete Agentenkonfiguration, LoKiEnte-Tasks und festgelegte Profileinstellungen
werden bewusst auf den Paketstand gebracht; Vorzustände werden gesichert.
Nicht erreichbare Projekte bleiben registriert und werden als Warnung gemeldet.
Freigegebene Abhängigkeiten werden aktualisiert, neuere Versionen nicht
automatisch heruntergestuft.

Die Installer-ZIP-Nutzlast wird samt SHA-256 mit jeder Quelldatei verglichen.
Die frühere separate ZIP ist archiviert und wird vom Installer nicht benutzt.
Modelle/Installationen/Benutzerprojekte wurden für diesen Test nicht verändert:
Installations- und Modellgrenzen sind simuliert, Git/Node/PowerShell und lokale
HTTP-Testprozesse laufen tatsächlich. Echte GPU-/GUI-Abnahme erfolgt auf dem
Windows-PC mit dem Welcome-Auftrag.

## Automatische Aufträge und sichtbarer Ablauf — Paket 2026.11.18.18

Neue bzw. erweiterte Prüfungen:

- `tests/Test-TaskPreparation.ps1`: echte temporäre Git-Projekte; Kandidatenerkennung
  ohne Ausführen von Projektwerkzeugen; neue und bestehende Prüfkataloge,
  auftragsspezifische Erneuerung, Sicherungen, Erhalt eigener Felder/Befehle,
  manuelle Provenienzkonflikte, dauerhafte Grenzen und konkurrierende Änderungen.
- `node tests/Test-TaskPreparation.mjs`: echter Node-Testlauf mit JUnit-Bericht,
  feste Argumente, Pfadgrenzen, fehlende Frameworks, Jest-Assertion-Konvertierung
  und exakte Playwright-Dateifilter unter Windows und normalisierten Pfaden.
- `node tests/Test-WorkflowTools.mjs`: lokale Kilo-Werkzeuge und Hintergrundaufträge;
  Projektbindung, Statusausgabe, Prozessgrenzen, Abbruch und Fehlerpfade.
- `tests/Test-KiloWorkflowEndToEnd.ps1`: direkter Werkzeugauftrag durch Bridge,
  Hintergrundprozess und echten Runner bis zu automatischer Konfiguration,
  acht getrennten Agentenrollen und echten roten/grünen Node-Testberichten.
  Die Agentenantworten sind synthetisch; geprüft wird die vollständige Verdrahtung.
- `tests/Test-WorkspaceGuide.ps1`: neue und bestehende Registrierungen erhalten
  automatische Tasks und aktuelle Anleitung; eigene Aufgaben, Befehle und
  persönliche Auftragsdateien bleiben erhalten.
- `tests/Test-QualityWorkflow.ps1`: bestehende Qualitätsgates bleiben die Grundlage
  für Testautoren, eingefrorene Tests und unabhängige Abnahme. Synthetische
  Agentenantworten testen Kontrolllogik, keine Modellqualität.
- `tests/Test-WorkflowProgress.ps1`: echte Ausgabe vor Prozessende, gleichzeitiges
  Lesen von stderr, Zeitlimit, Prozessende bei Callbackfehler und begrenzte Events.
- `tests/Test-KiloWorkflowDiscovery.ps1`: Werkzeugregistrierung, Schemas und
  rollenabhängige Rechte ohne Modellinferenz; Fehler bleiben geschlossen.
- `tests/Test-KiloToolImportPreflight.ps1`: fremde Customtools und veränderte oder
  verknüpfte Shims werden vor dem Import erkannt, ohne Benutzerdateien anzufassen.

Für diese Paketversion bestanden die folgenden Prüfgruppen:

| Suite | Bestanden |
|---|---:|
| Vollständiger Qualitätsworkflow mit automatischer Vorbereitung | 54 |
| Vorbereitung / feste Frameworkadapter | 27 / 11 |
| Chatwerkzeuge und Worker / vollständiger Bridge-Runner-Ablauf | 12 / 14 |
| Fortschrittsstream / Kilo-Registry / Importvorprüfung | 9 / 13 / 18 |
| Akzeptanzvertrag und strukturierte Testberichte | 27 |
| Workspace- und Projektmigration | 12 |
| Kilo-Metadaten / Startbefehle | 17 / 5 |
| Projektauswahl / Setup-Integration | 14 / 3 |
| Bootstrap einschließlich Windows PowerShell 5.1 und Junction-Prüfung | 42 |

PowerShell-/Node-Syntaxprüfungen bestanden ebenfalls. Die offizielle Kilo-CLI
7.8.30 lud die vier Werkzeuge mit der erzeugten Konfiguration: im Hauptchat
verfügbar, beim Implementierer gesperrt. Auch die vollständige effektive
Konfiguration wurde ohne Inferenz geprüft. Der unabhängige Code-Review fand
einen Doppelworker-Sperrfehler und verlorene Modellangaben im Status; beide
wurden korrigiert und durch Regressionen abgesichert.

Ältere Zahlen weiter unten beziehen sich auf damalige Stände.
Der vollständige Bridge-/Runner-End-to-End-Test bestand mit 14 Prüfgruppen.
Die lokalen Frameworkadapter sind ohne Download testbar. Der Node-Lauf verwendet
echte Assertions; Jest wird hier mit repräsentativen Assertion-Berichten geprüft,
Vitest/Playwright/pytest benötigen zusätzlich den tatsächlichen Projektlauf.

Zielabnahme nach erneuter Provisionierung auf dem Windows-PC:

1. Ein neues und ein bestehendes registriertes Git-Projekt über den Launcher
   öffnen; eigene VS-Code-Tasks und vorhandene Checks auf Erhalt kontrollieren.
2. Einen kleinen Auftrag direkt in `shadow-chat` eingeben, ohne `task.md` oder
   `checks.json` zu bearbeiten. `loki_start`, Vorbereitung und unabhängigen
   Vorbereitungsreview sowie die anschließenden Qualitätsphasen beobachten.
3. `loki_status` und `LOKI-STATUS.md` auf reale Agentenrollen, Rollenmodelle und
   Phasen prüfen. `loki_details` muss auf den passenden Bericht verweisen. Externe
   Runnerphasen werden nicht als native Task-Kindersitzungen vorausgesetzt.
4. Einen zweiten Auftrag stellen: neue Kriterien und Dateipfade, erhaltene eigene
   Checks und gesicherter Vorzustand müssen nachvollziehbar sein.
5. In einem getrennten Probeauftrag einen fehlenden Testadapter bzw. unklaren
   Auftrag verwenden: konkretes `NEEDS_INPUT`, keine schreibende Umsetzung.
6. Einen laufenden Probeauftrag ausdrücklich abbrechen und `CANCELLED` abwarten;
   nach dem Abbruch bleiben eventuelle Quelländerungen zur Diff-Prüfung bestehen.
   `WORKER_UNRESPONSIVE` hingegen bestätigt kein Prozessende: nach 30 Sekunden
   ohne Start bzw. 120 Sekunden ohne Heartbeat Polling beenden, Protokolle und
   Prozesse prüfen und die bestehende Sperre nicht ungeprüft entfernen.

Diese Schritte ersetzen weder fachliche Abnahme noch den ersten Test mit den
realen Modellen, der installierten Kilo-Erweiterung und der Zielhardware.

## Qualitätsworkflow — Paket 2026.11.18.17

Neue ausführbare Prüfungen:

- `tests/Test-AcceptancePolicy.ps1`: feste Kriterien, konkrete Fallzuordnung,
  JSON/JUnit, echte Node-JUnit-Ausgabe, leere/übersprungene/fehlende Fälle,
  unerwartete Ausgangsfehler, doppelte IDs und XML-Entitäten.
- `tests/Test-QualityWorkflow.ps1` (auch über `Test-CoderWorkflow.ps1`): tatsächliche
  Git-Repositories, getrennte Prozesse und echte Assertions vor/nach Umsetzung;
  Agentenantworten sind kontrollierte synthetische Daten. Prüft Testautor, Testreview,
  High/Fast, Schreibgrenzen, Einfrieren der Tests, frische Sitzungen, feste Kriterien,
  Security-/Integrationspflicht, nachträgliche Risikoeinstufung und ungültige Berichte.
- `tests/Test-WorkspaceGuide.ps1`: neue und vorhandene Arbeitsbereiche, Migration,
  Erhalt eigener Befehle und wiederholbare Aktualisierung der Anwenderanleitung.

Die Modelle und der echte VS-Code-/Kilo-Ablauf werden dadurch nicht simuliert
zu einem Hardware-Abnahmenachweis. Nach Provisionierung einen kleinen Auftrag
mit den realen Modellen auf dem Windows-PC ausführen. Die unten folgenden
Abschnitte dokumentieren frühere Teststände und ihre damaligen Grenzen.

## Provisionierung und Updates — Paket 2026.11.17.16

Die Tests für Workspace-Migration decken einen frisch registrierten Ordner,
das Aktualisieren einer bestehenden Registrierung, eigene Einstellungen und
Aufgaben sowie den Erhalt einer vorübergehend nicht erreichbaren Registrierung
ab. Die Versionstests verwenden simulierte WinGet- und npm-Aufrufe und prüfen
genaue Identität, Freigabe, Verifikation und den Erhalt bereits neuerer Versionen.
Die reale Installation und der erste Kilo-Lauf auf dem Windows-PC sind eigene
Abnahmeschritte.

## Qualitätsprüfungen — Paket 2026.11.17.15

Die Windows-Tests prüfen den Auftrag mit echtem Git, PowerShell und getrennten
Prozessen. Die Agentenantworten sind synthetisch. Abgedeckt sind unter anderem
Sperrkonflikt, Schreibumfang, fehlende Weitergabe eines Testgeheimnisses per
Umgebungsvariable und ein vor dem Fix fehlschlagender, danach grüner Check.
Die Modelltests verwenden simulierte Speicherwerte und LM-Studio-Antworten.
Der Router-Lebenszyklus prüft den Prozessstart und die Wiederverwendung nach
einer Änderung der Speicherschätzung über echtes Loopback-HTTP.

## Semantische Suche auf dem Windows-PC abnehmen

1. Im Installationsordner mit PowerShell 7 `./app/New-ShadowIndexProbe.ps1`
   ausführen. Das Skript legt ausschließlich künstliche Testdateien unter
   `diagnostics` an und zeigt den Ordnerpfad sowie erwartete Treffer an.
2. Den Ordner über die Desktopverknüpfung öffnen, lokale Indexierung in Kilo
   für ihn aktivieren und auf **Complete** warten.
3. Im Kilo-Chat um die exklusive Verwendung von `semantic_search` für
   „When should we order more stock?“ bitten. In der Werkzeugausgabe muss
   `stock.ts` mit dem angezeigten positiven Marker enthalten sein. Ein reiner
   Chat-Text oder ein Treffer per Dateisuche zählt nicht als Nachweis.
4. Mit demselben Werkzeug nacheinander nach „lunar telescope green comet“ und
   „desert weather station wind speed“ suchen. Die zwei ignorierten Dateien
   und deren Marker dürfen in keiner Werkzeugausgabe stehen. Vergleiche mit
   den Angaben aus PowerShell, ohne die Marker in den Chat zu kopieren.
5. Wenn Ausschlüsse fehlschlagen, reale Projekte mit sensiblen Dateien noch
   nicht indexieren. Die Ignore-Regeln und den für das Projekt verwendeten
   Index überprüfen und die Probe mit einem neuen Testordner wiederholen.

Der Provisionierungsbericht belegt den Embedding-Endpunkt. Die Such- und
Ausschlussprobe muss in der tatsächlich installierten Kilo-Oberfläche erfolgen.

## Startmenue — Paket 2026.11.17.14

Der Launcher bietet vor dem Modellstart bekannte Projekte, die Eingabe eines
weiteren vorhandenen Projektordners und Abbrechen an. Explizites -ProjectPath
bleibt ohne Menue verwendbar. Der Desktop-Shortcut setzt -PauseOnError.

Unter Windows mit PowerShell 7 wurden fuer diese Aenderung ausgefuehrt:
- tests/Test-ProjectSelection.ps1: 14 bestandene Pruefungen, einschliesslich
  Registrierung/Wiederwahl, Unicode und Sonderzeichen, ungueltigen Eingaben,
  nicht erreichbaren Ordnern, Erhalt der Projektdateien und Launcher-Abbruch.
- tests/Test-StartCommand.ps1: 5 bestandene Pruefungen.
- tests/Test-WorkspaceGuide.ps1: 4 bestandene Pruefungen.
- tests/Test-Bootstrap.ps1: 39 bestandene Pruefungen einschliesslich nativer
  Windows-Junctions und des Audit-Handoffs unter Windows PowerShell 5.1.

Die Launcher-Abbruchtests verwenden inerte Laufzeitmodule. Sie starten keine
Modelle und kein VS Code. Desktopverknuepfung, GPU und der vollstaendige Start
auf dem Windows-PC muessen nach der erneuten Provisionierung geprueft werden.
Die historischen Pruefberichte weiter unten ersetzen diese Zielmaschinenpruefung nicht.
# Prüfbericht zum Provisionierungspaket

## Speicherfit als Warnung: 2026.11.17.13

Ein nicht nachgewiesener LoKiEnte-Speicherfit führt zu einem ausdrücklich
angezeigten Ladeversuch, ohne die Schutzregeln von LM Studio zu deaktivieren.
Wird dieser Versuch abgelehnt, bleiben Modelldateien erhalten und die
Provisionierung endet mit `PROVISIONED_WITH_WARNINGS` und Exitcode 0.
Ungeprüfte Profile werden nicht als bestandene Modelltests ausgegeben.
Ein späterer Modellaufruf versucht Laden und Tests erneut.

Lokale Regressionen simulieren zu wenig Speicher, erfolgreiche und abgelehnte
Ladeversuche, spätere Wiederherstellung, Routerfehler, Single-Modus und das
CPU-Embeddingmodell. Tatsächlicher Speicherbedarf und LM-Studio-Verhalten auf
dem Windows-PC sind damit nicht nachgewiesen.

## Kilo-Erweiterung 7.8.30: 2026.11.17.12

Das VS-Code-Backend 7.8.30 wurde isoliert mit den vier Modellkennzeichnungen
und den LoKiEnte-Agenten geprüft. Es indexierte eine synthetische Python-Datei
mit LanceDB 0.26.2 und einem simulierten lokalen Embedding-Endpunkt bis
`Complete`. Die separat installierte Kilo CLI 7.8.27 bestand die Prüfung
der wirksamen Konfiguration und Agenten. Die Dateisuche und Dateiauflistung
des VS-Code-Backends 7.8.30 bestanden mit geprüftem Windows-ripgrep.
Die reale LM-Studio-Inferenz und
Indexierung auf dem Windows-PC bleiben gesondert zu prüfen.

## Getrennte Codingprofile: 2026.11.17.11

Coder High und Coder Fast sind getrennt wählbare Routerprofile. Sichtbare
Modellnamen enthalten die Rolle und den tatsächlichen Modellnamen; die
Aufgabenvariante Coder Fast behält den unabhängigen Review und die Validierung.
Der Embedding-Endpunkt und der lokale Index bleiben von der Auswahl getrennt.
Das Kilo-7.8.28-Backend lieferte in einem isolierten Test alle vier
rollenmarkierten Modellnamen über seine Provider-API; die auswählbaren
eingebauten Agenten fehlten in der Agentenliste. Interne Hilfsagenten bleiben
erhalten. Weitere Tests prüfen die Pool-Migration, den Routerwechsel und den
echten Review-Ablauf mit synthetischen Modellantworten. Die UI und LM Studio
auf dem Windows-PC bleiben gesondert zu prüfen.

## Lokale CPU-Embeddings und Index-Konfiguration: 2026.11.17.10

`Test-Embedding.ps1` prüft mit simulierten LM-Studio-Grenzen Besitznachweise,
RAM-Reserve, den CPU-Ladeauftrag, Wiederverwendung, Vektorantworten und
Loopback-Konfiguration. Der unveränderte Pool-Lebenszyklus wurde erneut getestet.
LanceDB 0.26.2 wurde in einem isolierten Testverzeichnis installiert und das
native Modul geladen. Die wirksame Konfiguration wurde zusätzlich mit dem
VS-Code-Backend von Kilo 7.8.28 in einem isolierten Profil ausgelesen.
Auch die separate Kilo CLI 7.8.27 bestand die Konfigurationsprüfung.
Dasselbe Backend indexierte eine synthetische Python-Datei mit LanceDB und einem
simulierten lokalen Embedding-Endpunkt bis Status `Complete`. Eine echte
Indexierung und Modellinferenz auf dem Windows-PC sind damit nicht belegt.

## LoKiEnte-Fenster und Copilot: 2026.11.17.9

Der Launcher übergibt beim Öffnen eines neuen isolierten VS-Code-Fensters
`--disable-extension` für beide GitHub-Copilot-Erweiterungen. Dies verändert
keine anderen VS-Code-Profile oder bereits offenen Fenster. Der Argumenttest
prüft die IDs, den neuen Fensterstart und die isolierten Verzeichnisse; die
wirksame Deaktivierung muss im Zielsystem überprüft werden. Diese Änderung
aktiviert keine semantische Indexierung und behebt kein nachgewiesenes
Reasoning-Problem.

## Kilo-Dateisuche und Projektanleitung: 2026.11.17.8

Das offizielle Windows-x64-Archiv von ripgrep 15.1.0 und die darin enthaltene
`rg.exe` werden getrennt mit festgehaltenen SHA-256-Werten geprüft. Das Setup
installiert sie ausschließlich in den isolierten Kilo-Cache und führt echte
Kilo-Grep- und Dateiauflistungstests für die separate CLI und das mit der
VS-Code-Erweiterung gelieferte Backend aus. Eine vorhandene unbekannte Datei
wird nicht überschrieben.

Lokal wurden das offizielle Archiv, die ausführbare Datei und Kilo CLI 7.8.27
mit echtem nativen Windows-Binary und npm-Einstieg gegen eine synthetische
Projektdatei geprüft. Die Erweiterung 7.8.28 wurde hier nicht ausgeführt;
das Setup prüft sie auf dem Zielsystem selbst. `Test-WorkspaceGuide.ps1`
prüft die neue Anleitung und die unveränderte Wiederverwendung vorhandener
Aufträge, Checks und Anleitungen.

## Startbefehl für PowerShell 7: 2026.11.17.7

Der nach dem Setup angezeigte Startbefehl verwendet die ermittelte PowerShell 7,
`-ExecutionPolicy Bypass` für den gestarteten Prozess und die tatsächlichen
registrierten Projektpfade. Ohne Projekt wird ein Platzhalter ausgegeben.
Auch die erzeugte Desktop-Verknüpfung erhält die prozesslokale Option;
erzwungene Gruppenrichtlinien werden nicht verändert. `Test-StartCommand.ps1`
prüft mehrere Projekte, den Platzhalter und einen echten Unterprozess unter
eingeschränkter Ausführungsrichtlinie mit Leerzeichen, Apostrophen und
PowerShell-Sonderzeichen in Argumenten.

## Zitierte Smoke-Test-Antwort: 2026.11.17.6

Auf dem Windows-PC lieferte das Modell nach einem korrekten Tool-Aufruf die
Quittung als `"LOCAL_TOOL_OK"` statt als unzitierte Zeichenfolge. Chat- und
Tool-Rückantwort akzeptieren jetzt genau den erwarteten Text mit oder ohne
äußere doppelte Anführungszeichen und optionalen äußeren Leerraum. Zusätzliche
Erklärungen, falsche Werte, falsche Groß-/Kleinschreibung und ungültige
Tool-Aufrufe bleiben Fehler. Der HTTP-Regressionstest prüft beide zulässigen
Formen und weiterhin die Ablehnung von Zusatztext und falschen Tool-Antworten.

## Tool-Auswahl im Smoke-Test: 2026.11.17.5

LM Studio auf dem Windows-PC lehnte ein Objekt als `tool_choice` mit HTTP 400
ab und bestätigte die unterstützten Zeichenfolgen `none`, `auto`, `required`.
Ein anschließender echter Test mit `required` lieferte `report_value(17)` und
mit `none` die erwartete Tool-Rückantwort. Der Smoke-Test verwendet nun
`required`; er prüft weiterhin Toolname, eindeutige ID, den Wert 17 und die
abschließende Rückantwort. Ein lokaler HTTP-Regressionstest prüft die tatsächliche
JSON-Anfrage und lehnt falsche Antworten weiterhin ab.

## Große Modelldateien: 2026.11.17.4

Die Speicherplatzberechnung verwendet 64-Bit-Ganzzahlen für Dateigröße,
Teilfortschritt und Nullgrenze. `Test-LargeModelPreflight.ps1` prüft den
echten Installationsvorlauf mit der 9.001.753.376 Byte großen
Qwen3-14B-Datei, sowohl ohne als auch mit einem simulierten 3,5-GB-Teildownload.
Die geprüften Zahlen werden ausgegeben; es werden keine großen Dateien angelegt
oder geladen.

## Modellwahl und additive Downloads: 2026.11.17.3

Der Katalog enthält fünf feste GGUF-Varianten und ihre benötigten Projektoren.
Repository-Revision, Dateigröße und SHA-256 aller acht Dateien wurden gegen
öffentliche Hugging-Face-Metadaten der jeweiligen Revision geprüft. Vorschläge
beruhen auf freien Ressourcen und konservativen Dateigrößen-Heuristiken, nicht
auf gemessener Modellqualität oder einem garantierten Speicherfit.

`Test-ModelSelection.ps1` prüft Rollenwahl und bestätigte Wiederanläufe,
Hardwareänderung, realistische Speicherwerte, opt-out, Netzwerkfehler,
Fortsetzung von Teildateien, Integritätsfehler und den Schutz vorhandener
Dateien einschließlich eines konkurrierenden Zielzugriffs und Junctions.
`Test-SelectionIntegration.ps1` führt den echten Setup-Zweig isoliert aus;
`Test-ModelPool.ps1` prüft die Weitergabe anderer Modelle und einen Modellwechsel
ohne Dateilöschung. Ein echter HTTPS-Range-Wiederanlauf wurde mit einer 1.756 Byte
großen öffentlichen Datei geprüft. Das ist kein Langzeit- oder Geschwindigkeitstest
und keine echte LM-Studio-Registrierung eines neuen GGUF-Modells.

Der Bootstrap wartet ohne Gesamtzeitlimit auf das Setup. Eine vom Setup-Kind
gehaltene zusätzliche Sperre schützt vor einem zweiten Lauf, auch wenn der
Starter beendet wurde. Der Audit prüft gespeicherte Auswahlen oder zeigt
unverbindliche neue Vorschläge und bleibt ohne Downloads/Modellwechsel.

## Optionale CPU-Auslagerung: 2026.11.17.2

`Test-PartialGpuOffload.ps1` prüft die explizite Aktivierung, Reihenfolge und
Persistenz der GPU-Strategie, unveränderte Standardwerte, Kontextfallback,
GPU-/RAM-Reserven, Guardrails und Übereinstimmung der geschätzten und tatsächlich
angeforderten GPU-Option. LM-Studio- und GPU-Grenzen werden simuliert; reale
Leistung, CPU-Auslagerung und Inferenz bleiben auf dem Windows-PC zu prüfen.

## Modellvarianten in LM Studio: 2026.11.17.1

CLI-Commit 43d4b26 meldet Modell-IDs als `path` und Dateipfade in
`indexedModelIdentifier` der Variantenliste. Anhand der vom Windows-PC gelieferten
Ausgabe prüft `Test-ModelVariants.ps1` die Zuordnung aller drei exakten Dateien,
die Erhaltung älterer Dateipfade und Abbrüche bei geänderten, fehlenden oder
mehrdeutigen Varianten. Der Audit testet die gleiche Zuordnung unter PS5.1/PS7.
Vor und nach dem Laden werden die lokale Datei und ausgewählte Variante erneut
geprüft; ausstehende Eigentumsnachweise bewahren die Variantenidentität.
GPU-/LM-Studio-Grenzen werden simuliert; keine reale Inferenz wurde hier
durch das Paket durchgeführt.

## Manuelle Handlungsanweisungen: 2026.11.16.10

Fehlende Modelle und ein erforderlicher LM-Studio-Erststart werden als
strukturierte Handlungsanweisung auf stdout ausgegeben, nicht als rote
Fehlermeldung. Der Bericht bleibt `INCOMPLETE`, enthält die Kennung
`manualAction`, und der Exitcode bleibt 1. Tatsächliche Fehler gehen weiterhin
an stderr. Die ausführbaren Setup-Harnesses prüfen getrennte Zeilen für jedes
Modell, Datei, Quelle und nächste Schritte, vollständige Berichtsdaten,
Exitcode und Fehlerkanäle.

## Manuelle Modelldownloads: 2026.11.16.9

Das normale Setup prüft vor Router-/Modellaktionen alle ausgewählten lokalen
Modelldateien. Fehlen Modelle, nennt der kontrollierte Abbruch ausschließlich
die noch fehlenden exakten Dateien mit Quelle und verlangt den manuellen
Download in LM Studio sowie den erneuten Start mit denselben Parametern.
Das Setup ruft den Modellpool bzw. die Einzelmodellroutine mit deaktiviertem
Download auf. `-SkipModelDownload` bleibt als kompatibler Schalter gültig.
Der Auditbericht listet fehlende Profildateien einschließlich Quellen auf.

`Test-ManualModels.ps1` testet Dual mit und ohne optionales Modell,
teilweise und vollständig vorhandene Modelle, Einzelmodell und `ModelKey`,
Fehler bei mehrdeutigen Modellen sowie den echten Setup-Abbruch mit
`INCOMPLETE`-Bericht vor Router- oder Modellaktionen. Die LM-Studio- und
GPU-Grenzen werden simuliert; keine Modelle werden heruntergeladen.

## VS-Code-CLI-Pfad: 2026.11.16.8

Windows VS Code 1.146.0 verweist in seiner mitgelieferten `bin\code.cmd` auf
einen versionsabhängigen Unterordner. Der Resolver liest nur den erwarteten
einzelnen Aufruf aus dieser Datei, führt das Batch-Skript nicht aus und
verwendet exakt den dort angegebenen `cli.js` mit dem zugehörigen `Code.exe`.
Ältere nicht versionierte Layouts und Installationen ohne Batch-Datei mit
klassischem CLI-Pfad bleiben unterstützt; unbekannte oder mehrdeutige Pfade
werden explizit abgelehnt.

Der tatsächliche CLI-Aufruf `--version` wurde lokal gegen die installierte
VS-Code-Version 1.146.0 durchgeführt. Tests prüfen daneben synthetische alte
und neue Layouts, eine fehlerhafte/mehrdeutige Batch-Datei, fehlende CLI-Dateien,
die Argumentweitergabe und die zusätzliche lesende Audit-Prüfung. Es wurden
keine Erweiterungen installiert und keine persönliche VS-Code-Konfiguration
geändert.
Bei derselben Version wurde außerdem festgestellt, dass `--locate-extension`
keinen Pfad zurückgibt. Die Suche nach der gebündelten Kilo-CLI verwendet nun
die explizit mit `--list-extensions --show-versions` gemeldete Version und
prüft passende Paketmanifeste im isolierten Erweiterungsordner. Mehrdeutige
Treffer und fehlende Binärdateien werden abgelehnt.

## Auswahl bei vorhandenem Ziel: 2026.11.16.7

Das Startmenü erkennt eine gültige Ziel-Paketkennung und empfiehlt das
Fortsetzen mit Option 1, ohne einen vollständigen Umzug oder eine abgeschlossene
Provisionierung zu behaupten. Option 3 prüft vor der Bestätigung Paketkennungen
und bestehende Dateinamen; Konflikte führen zurück zur Auswahl, nicht zu
Zusammenführung oder Überschreiben. Der Kopiervorgang prüft Konflikte weiterhin
selbst vor der Veröffentlichung, auch wenn sie erst nach dem Menü entstehen.

## Kilo-Hilfeausgabe: 2026.11.16.6

Auf dem Windows-PC lieferte `kilo run --help` bei umgeleiteter Ausgabe
Exitcode 0, eine leere stdout und die vollständige Hilfe auf stderr. Das Setup
wertet beide Kanäle aus, ohne den erforderlichen erfolgreichen Exitcode und
die Optionsprüfung aufzugeben. `Test-KiloHelp.ps1` testet stdout, stderr,
gemischte Ausgabe, fehlende Optionen, nicht erfolgreiche Exitcodes und die
Wiederverwendung einer bereits installierten CLI ohne erneuten npm-Aufruf.
Zudem wird ein echter lokaler Unterprozess mit Hilfe auf stderr ausgeführt.

## NTFS-Kopierprüfung: 2026.11.16.5

Ein echter NTFS-Hardlink reproduziert den Fehlalarm: Nach einem Schreibzugriff
über einen zweiten Dateinamen kann die Verzeichnisauflistung noch alte Größe
und Änderungszeit melden, während der direkte Dateizugriff aktuelle Daten liefert.
Die Kopierprüfung aktualisiert die Metadaten deshalb vor der Bestandsaufnahme
und beim anschließenden Vergleich.

`Test-InstallationLocation.ps1` ergänzt vier Prüfungen: erfolgreiche Kopie
trotz zuvor veralteter NTFS-Verzeichnisdaten, identische Dateiinhalte, weiterhin
abgelehnte tatsächliche Änderungen mit konkreter Pfadangabe sowie Aufräumen
der Zwischenkopie ohne Veränderung vorhandener Zieldateien oder Zurücksetzen
der Quelldaten. Die Prüfung verwendet echte temporäre NTFS-Hardlinks; tatsächliche
Quelländerungen werden gezielt vor der Abschlusskontrolle ausgelöst.

## CLI-Kompatibilität und leere Modelllisten: 2026.11.16.4

Die Herstellerquelle für CLI-Commit `43d4b26` bestätigt, dass `--exact` und
`--local` vorhanden, aber aus der Hilfe ausgeblendet sind. Die Prüfung verwendet
deshalb gegebenenfalls den kontrollierten Fehler eines Aufrufs ohne Modellpfad,
zusätzlich abgesichert mit `--estimate-only`. Die Schutzoptionen werden nicht
aus den tatsächlichen Ladebefehlen entfernt.

- `Test-Audit.ps1`: 41 Prüfungen jeweils unter Windows PowerShell 5.1 und PS7,
  einschließlich versteckter/fehlender Optionen, unerwartetem Probe-Erfolg,
  korrekten Anzahlen bei null/einem/zwei Modellen und Ablehnung falscher JSON-Formen.
- `Test-LmsCliCompatibility.ps1`: 16 Prüfungen für native Exitcodes, erwartete
  Fehler, Modelllisten und unveränderte Serverstatus-Objekte.
- `Test-ModelPool.ps1`: 30 Prüfungen; erfolgreiche Einrichtung mit versteckten
  Optionen und Abbruch vor Downloads/Inferenz bei tatsächlich fehlender Unterstützung.

CLI-Ausgaben und GPU-/LM-Studio-Grenzen werden simuliert; native
PowerShell-Unterprozesse, JSON-Konvertierung und Dateizugriffe sind real.
Die aktualisierte Version muss auf dem Windows-PC erneut mit `-AuditOnly`
geprüft werden. Es wurde hier kein reales Modell geladen.

## Verzeichnisauswahl und Kopie: 2026.11.16.3

`Test-InstallationLocation.ps1` prüft unter PS7 und Windows PowerShell 5.1:
PS1-Ordner statt Terminal-Arbeitsverzeichnis, Zielauswahl, Bestätigung ausschließlich
mit `y`, keine Schreib-/Installationsaktionen vor Bestätigung, nichtinteraktive
Abbrüche sowie Audit ohne Nachfrage. Kopiertests prüfen unveränderte Quelldateien,
Anwendungseinstellungen und Modellzustände, angepasste verwaltete Pfade, erhaltene
JSON-Arrayformen, Sperren/aktive Prozesse, Konflikte, Verknüpfungen und Rücknahme
teilweise veröffentlichter Kopien. Alle Kopien verwenden temporäre Testdaten.

Aus dem gewählten Stammverzeichnis:

```powershell
pwsh -NoProfile -File ".\app\tests\Test-InstallationLocation.ps1" -BootstrapPath ".\Provision-LoKiEnte.ps1"
powershell -NoProfile -File ".\app\tests\Test-InstallationLocation.ps1" -BootstrapPath ".\Provision-LoKiEnte.ps1"
```

## Manueller LM-Studio-Erststart: 2026.11.16.2

`Test-LmStudioInitialization.ps1` prüft die unveränderte Weitergabe einer
vorhandenen CLI, fehlende/leere CLI-Auflösung und eine beschädigte
Home-Konfiguration. Ein isolierter Unterprozess führt den tatsächlichen
Setup-Abschnitt ab der CLI-Prüfung samt Fehlerbehandlung aus: fehlende CLI
beendet ihn mit Exitcode 1 und einem gespeicherten `INCOMPLETE`-Bericht mit
Handlungsanweisung. App-Start, Warteschleife und Modell-/Routeraktionen dürfen
in diesem Fall nicht ausgeführt werden. Es wird keine reale LM-Studio-App
gestartet und keine Installation ausgeführt.

## Reparaturstand 2026.11.16.1

Die Reparaturen ergänzen die nachfolgend dokumentierte Vorversion. Die aktuelle
Prüfung verwendet Windows, PowerShell 7.6.10 und Windows PowerShell 5.1.26100.9818.
Es wurden keine Anwendungen installiert und keine realen Modelle geladen oder
entladen. GPU-/LM-Studio-Grenzen und öffentliche HTTP-Quellen werden in den
Regressionstests simuliert; lokale HTTP-Verbindungen, Dateizugriffe,
Prozessaufrufe und Prozesszeitlimits werden tatsächlich ausgeführt.

Mitgelieferte Prüfungen unter `app\tests` nach dem Entpacken des Pakets:

| Test | Umfang |
|---|---|
| `Test-KiloMetadata.ps1` | String-/Array-/Objektantworten, fehlende/mehrdeutige Daten, Prerelease-/Buildversion und Abbruch vor Installationsschreibzugriffen. |
| `Test-ModelPool.ps1` | Bestehende 22 Modellpoolprüfungen plus 6 Wiederanlaufprüfungen: gespeicherter Ladeauftrag, REST-Ausfall nach Laden, Ablehnung abweichender Dateien, Wiederverwendung und persistierter Eigentumsnachweis. |
| `Test-RouterLifecycle.ps1` | 17 Prüfungen mit echten lokalen Node-Prozessen, einschließlich HTTP-503-Identität, Schutz beschäftigter Router und authentifiziertem Beenden. |
| `Test-Audit.ps1` | Auditbericht, Fehleraggregation, Hardware-/Modelloptionen, fehlende Downloads, Zustandsprüfung, Sperren, Token-Redaktion, keine Provisionierungsbefehle, echte Prozesszeitlimits und HTTP-/Redirectverhalten. Ausführung unter PS5.1 und PS7. |
| `Test-Bootstrap.ps1` | 35 Prüfungen zu Argumenten, Extraktion, Sicherungen, Hash, ungültigen Pfaden, PS5.1-Audit-Handoff, strukturierten Auditfehlern, Zeitlimits und Exitcodes. |

Beispiel nach dem Entpacken, im gewählten Stammverzeichnis und mit explizitem Pfad zur aktualisierten PS1:

```powershell
pwsh -NoProfile -File ".\app\tests\Test-KiloMetadata.ps1"
pwsh -NoProfile -File ".\app\tests\Test-ModelPool.ps1"
pwsh -NoProfile -File ".\app\tests\Test-RouterLifecycle.ps1"
pwsh -NoProfile -File ".\app\tests\Test-Audit.ps1" -BootstrapPath "C:\Downloads\Provision-LoKiEnte.ps1"
powershell -NoProfile -File ".\app\tests\Test-Audit.ps1" -BootstrapPath "C:\Downloads\Provision-LoKiEnte.ps1"
pwsh -NoProfile -File ".\app\tests\Test-Bootstrap.ps1" -BootstrapPath "C:\Downloads\Provision-LoKiEnte.ps1"
```

Diese Tests prüfen nicht die aktuell installierten LM-Studio-/Kilo-Versionen
oder die reale GPU des Zielsystems. Die vollständige Zielsysteminstallation und erste
GUI-/Agentennutzung bleiben eine notwendige Abnahme auf dem Windows-PC.

## Historischer Prüfbericht zur Vorversion

Die folgenden Ergebnisse und weitergehenden Testlisten stammen aus der früheren
Ausgabe. Die vollständige damalige Testsammlung gehört zum alten separaten ZIP,
nicht zum Umfang der oben aufgeführten aktuellen Reparaturtests.

Stand: 13. November 2026 (UTC), Paket 2026.11.14.1. Die folgenden Prüfungen wurden auf Debian Linux mit einer
portablen, anhand der offiziellen SHA256-Prüfsumme geprüften PowerShell 7.6.6
ausgeführt. Für die echten Kilo-Prüfungen wurde `@kilocode/cli` 7.8.27 in einem
separaten Testverzeichnis installiert. Die Testwerkzeuge gehören nicht zur
Installation auf dem Windows-PC.

## Ergebnis

Alle nachfolgend aufgeführten Prüfungen bestanden. Das bestätigt die geprüfte
Skriptlogik, Konfiguration und Fehlerbehandlung. Eine vollständige Installation
auf Windows oder ein Lauf des vorgesehenen LLM auf der GPU des Zielsystems wurde hier nicht
ausgeführt. Die Hardware und das Modell werden beim tatsächlichen Provisionierungslauf mit
verpflichtenden Chat-/Tool-Smoke-Tests geprüft. Die erste GUI-Nutzung und ein
kleiner echter Projektauftrag bleiben Teil der Abnahme auf dem Windows-PC.

| Prüfung | Umfang | Ergebnis |
|---|---|---|
| PowerShell-Syntax | Parserprüfung der Paketdateien mit PowerShell 7.6.6 | Keine Syntaxfehler |
| Bootstrap und PowerShell-Handoff | 32 Fälle mit echten temporären Dateien und Unterprozessen | Bestanden |
| Native Prozesse und verwaltete Dateien | 9 benannte Fälle | Bestanden |
| Review-Gate | 19 benannte Fälle mit echten temporären Git-Repositories | Bestanden |
| Vollständiger Aufgabenablauf | 8 Szenarien mit echten Prozessen und synthetischen Agentenantworten | Bestanden |
| Bestehende Projekte und Workspaces | 5 Erhaltungs- und Wiederholungsbedingungen | Bestanden |
| Echte Kilo-Konfiguration | Tatsächlicher CLI-Parser und effektive Konfiguration, 21 deklarierte Agenten | Bestanden |
| Echte lokale Kilo-API-Anbindung | Ohne Token und mit Testtoken gegen einen lokalen HTTP-Testserver | Beide Szenarien bestanden |
| LM-Studio-Ablauflogik | Gemockte Neuinstallation, Speicherfallback, Wiederholung und Fehlerfälle | Bestanden |

## Erweiterung auf mehrere lokale Modelle

Die Mehrmodellversion erweitert die zuvor geprüfte Einmodellvariante um
einen expliziten Modellpool, einen lokalen HTTP-Router und rollenabhängige
Kilo-Modelle. Auch für diese Erweiterung gab es keinen tatsächlichen GPU-Lauf.

| Prüfung der Erweiterung | Umfang | Ergebnis |
|---|---|---|
| Modellpool und Eigentumsregister | 22 gezielte Fälle, tatsächliche PowerShell-Steuerung und Dateisperren, simulierte LM-/GPU-Grenzen | Bestanden |
| HTTP-/SSE-Router | 23 Fälle mit echten lokalen Netzwerkverbindungen und Unterprozessen | Bestanden |
| Routerstart und Wiederverwendung | 15 Bedingungen mit echten Node-Prozessen und lokalem HTTP-Dienst | Bestanden |
| Mehrmodell-Konfiguration | 22 Bedingungen, einschließlich tatsächlicher Kilo-CLI und vollständiger Konfigurationsprüfung | Bestanden |
| Rollenbezogener Aufgabenrunner | 2 vollständige Szenarien mit unterschiedlichen Modellargumenten und Kontextgrenzen | Bestanden |
| Echte Kilo-CLI durch ausgelieferten Router | 5 Szenarien: Coder, Reviewer, kleiner Chat, GPT-OSS-artiger Reasoning-/Tool-Roundtrip und native Unteragenten-Delegation | Bestanden |

Der letzte Test verwendet **die tatsächliche Kilo CLI 7.8.27 und den gelieferten
Router**, dahinter jedoch einen synthetischen LM-Endpunkt und einen simulierten
Modellcontroller. Er belegt, dass Coder → Review-Unteragent → Coder tatsächlich
unterschiedliche Modellrouten anfordert, Tool-Call-Daten erhalten bleiben und
Reasoning-Inhalte über einen Tool-Roundtrip weitergegeben werden. Er belegt
keine Modellintelligenz und kein Verhalten der realen GPU.

Für Qwen sind die Metadaten auf `reasoning_content` ausgerichtet. Für GPT-OSS
wird das von LM Studio dokumentierte Feld `reasoning` verwendet. Beide Varianten
wurden mit echten Kilo-SDK-Requests gegen synthetische Antworten geprüft. Die
auf dem Windows-PC tatsächlich aktivierten Modelltemplates und Ausgabeformate sind
weiterhin durch die dortigen Funktionsprüfungen zu bestätigen.

### Abgedeckte Mehrmodell-Fehlerfälle

Der Router akzeptiert nur provisionierte Modell-Aliase und lokale Endpunkte.
Er erhält fragmentierte Tool-Argumente im SSE-Stream und serialisiert Anfragen
bis zum Ende der jeweiligen Generierung. Weiterleitungen an andere HTTP-Ziele
werden abgewiesen. Fehlerhafte Antworten, unvollständige Streams, falsche
Controllerergebnisse und unbekannte Modellnamen werden als Fehler behandelt.
Timeouts während Warteschlange, Laden und Generierung sowie Clientabbrüche sind
gezielt getestet. Ein unklarer Controller-Timeout sperrt weitere Modellwechsel,
statt eine möglicherweise noch laufende Ladeoperation zu überholen.

Der Lifecycle-Test bestätigt, dass ein passender beschäftigter Router ohne
Modellwechsel wiederverwendet wird. Ein fremder Dienst oder ein beschäftigter
Router mit unpassender Konfiguration wird erhalten. Nur ein eindeutig selbst
gestarteter, nicht bereit werdender Prozess wird im Fehlerpfad beendet.

Der Modellcontroller schützt fremde und aktive Modelle, prüft ID und Pfad vor
jedem eigenen Entladen, begrenzt Parallelität auf einen Slot und vereinheitlicht
den Kontext auf das tatsächlich getestete Minimum. Eine unklare alte v1-Instanz
wird konservativ nicht übernommen. Zusätzliche Modelldateien werden bei
Wiederholung wiederverwendet.

### Ausführbare Zusatztests

- `tests/Test-ModelPool.ps1`
- `tests/Test-ModelRouter.mjs`
- `tests/Test-RouterLifecycle.ps1`
- `tests/Test-MultiModelConfiguration.ps1`
- `tests/Test-MultiModelRunner.ps1`
- `tests/Test-MultiModelKilo.js` und `Prepare-MultiModelProbe.ps1`

Die Node-Routerprüfung lässt sich aus dem entpackten Paket mit
`node tests/Test-ModelRouter.mjs` ausführen. Die echten Kilo-Tests verlangen die
expliziten Pfade zur PowerShell- und Kilo-Testinstallation; die Paketauslieferung
enthält diese Testwerkzeuge nicht.

## Was konkret geprüft wurde

### Bootstrap und Fehlerweitergabe

32 Prüfungen bestätigten die vollständige ZIP-Vorabprüfung, unveränderte Wiederholung,
korrekte Sicherungen, SHA256-Kontrolle, wörtliche Argumentübergabe und den JSON-Handoff.
Pfadausbruch, doppelte Ziele, Datei-/Verzeichniskollisionen und Reparse-Links in Ziel-
oder Backup-Verzeichnissen werden zurückgewiesen. Die Inventur wurde mit simulierten
CIM-Antworten ausgeführt und erzeugte kein Installationsverzeichnis.

Ein tatsächlicher Unterprozesstest deckte zunächst auf, dass ein innerer Setup-Exitcode
verlorenging. Der Handoff propagiert jetzt den Fehlercode ausdrücklich; die Tests für
Exitcodes 0 und 23 bestehen. Ein weiterer Test bestätigte das ursprüngliche Folgen
vorhandener Verknüpfungen außerhalb des Zielordners; die vollständige Vorabprüfung
verhindert diesen Fall jetzt. Native Windows-Junctions und Windows PowerShell 5.1
wurden dabei weiterhin nicht ausgeführt.

### Prozesse und vorhandene Dateien

Die tatsächliche Prozessfunktion übergibt leere Argumente, Leerzeichen,
Anführungszeichen, Unicode, Zeilenumbrüche und Shell-Sonderzeichen unverändert.
Eine Meldung auf stderr bei Exitcode 0 gilt als erfolgreiche Ausführung. Ein
Exitcode ungleich 0 schlägt fehl oder wird bei explizit erlaubter Fehlerbehandlung
unverändert zurückgegeben. Beide Ausgabeströme werden parallel gelesen; der Test
verwendete jeweils 200 KB auf stdout und stderr. Ein Zeitlimit beendet einen
überlangen Prozess. `.cmd`, `.bat` und `.ps1` werden nicht als vermeintliche native
Programme gestartet.

Geänderte verwaltete Dateien erhalten eine Sicherung. Ohne Sicherungsziel wird
vorhandener abweichender Inhalt nicht überschrieben. Eine unveränderte Wiederholung
schreibt die Datei nicht neu und legt keine zusätzliche Sicherung an. Der
Workspace-Test bewahrte vorhandene Quelltexte, `AGENTS.md` und VS-Code-Einstellungen
im Projekt. Auch vom Benutzer angepasste Aufgaben und Prüfbefehle blieben bei
Wiederholung erhalten. Die Registrierung eines weiteren Projekts entfernte keinen
bestehenden Eintrag.

### Review und Validierung

Ein positiver Kontrolllauf erzeugte `VERIFIED` mit Exitcode 0. Das Gate verweigerte
diesen Status bei fehlenden, fehlgeschlagenen oder abgebrochenen Prüfbefehlen,
fehlgeschlagener Implementierung, gescheitertem Spezialistenwerkzeug, gemeinsam
genutzter Prüfersitzung, veraltetem Quellfingerabdruck, offenen Befunden sowie
`FAIL`- oder `BLOCKED`-Urteilen.

Zusätzliche Parserprüfungen lehnten Tool-Ausgaben als vermeintliche Freigabe,
unvollständiges JSON, bloßes „PASS“ im Text, einen früheren statt abschließenden
Antworttext, falsche Rolle, falschen Fingerabdruck und ungültige Sitzungskennungen
ab. Fehlermeldungen im Ereignisstrom verhindern eine spätere scheinbare Freigabe.
Der Validator muss sämtliche ausgeführten Prüfbefehle benennen.

Die Quellfingerabdrücke änderten sich bei Änderungen an versionierten Dateien,
am Git-Index und an nicht ignorierten unversionierten Dateien. Der besonders
fehleranfällige Fall „unterschiedlicher Indexinhalt bei gleichem Arbeitsbaum und
gleicher Git-Statusanzeige“ wurde ausdrücklich geprüft. Git-ignorierte Dateien
liegen bewusst außerhalb dieses Fingerabdrucks; der Prüfbericht nennt diese
Grenze. Damit werden etwa `node_modules`, erzeugte Dateien oder lokale
Umgebungsdateien nicht als geprüftes Quellmaterial ausgegeben.

Im vollständigen Ablauf ergaben sich folgende tatsächliche Prozessresultate:

| Szenario | Status | Exitcode |
|---|---|---|
| Gültige getrennte Freigaben und bestandener Prüfbefehl | `VERIFIED` | 0 |
| Keine Prüfbefehle konfiguriert | `REVIEWED_UNVALIDATED` | 2 |
| Prüfbefehl fehlgeschlagen | `NOT_VERIFIED` | 1 |
| Implementierungsprozess fehlgeschlagen | `NOT_VERIFIED` | 1 |
| Delegierter Spezialist meldet Werkzeugfehler | `NOT_VERIFIED` | 1 |
| Reviewer nennt veralteten Fingerabdruck | `NOT_VERIFIED` | 1 |
| Quelle wird während der Prüfung verändert | `NOT_VERIFIED` | 1 |
| Rollen verwenden dieselbe Sitzung | `NOT_VERIFIED` | 1 |

Die Agentenantworten dieser Ablaufprüfung sind synthetische Testdaten. Damit wird
die externe Koordination geprüft, nicht die Qualität eines Sprachmodells.

### Tatsächliche Kilo-Konfiguration und Authentifizierung

Die echte Kilo CLI akzeptierte die erzeugte Konfiguration. Ihre aufgelösten Werte
entsprachen dem lokalen Provider, dem festgelegten Modell, 32.768 Kontext-Tokens
und den konfigurierten Agentenrechten. Auch der vollständige Vergleich globaler
und agentenspezifischer Berechtigungen bestand. Ein nicht lokaler API-Endpunkt
wurde bereits vom Konfigurationsgenerator abgewiesen.

Für den Authentifizierungstest lief ein HTTP-Testserver ausschließlich auf
`127.0.0.1`. Die echte Kilo CLI rief `/v1/chat/completions` auf und gab dessen
Kontrollantwort zurück. Ohne Token wurde kein API-Key-Feld gespeichert. Mit einem
offensichtlich künstlichen Testtoken wurde der erwartete Bearer-Header übermittelt;
der Server hätte einen fehlenden oder falschen Token zurückgewiesen. Die
gespeicherte Konfiguration enthielt ausschließlich einen Umgebungsvariablenverweis,
keinen Tokenwert. Der Windows-spezifische Zugriff auf eine ausschließlich im
Benutzerprofil gesetzte Umgebungsvariable konnte auf Linux nicht systemnah geprüft
werden.

Die Prüfungen verwenden `KILO_TELEMETRY_LEVEL=off` sowie
`experimental.openTelemetry=false`. Beide Einstellungen sind auch Bestandteil
der gelieferten Konfiguration. Daraus folgt keine Garantie gegen sämtliche
Netzwerkaktivität aller installierten Programme; Paket- und Modell-Downloads
sowie mögliche öffentliche Metadatenabfragen sind eigenständige Vorgänge.

Die drei Einstellungen für automatische Inline-Vorschläge, deren Hotkey und
Chat-Autocomplete sind anhand des offiziellen Kilo-Erweiterungsmanifests geprüft
und im verwalteten VS-Code-Profil sowie den erzeugten Workspaces auf `false`
gesetzt. Der separate Autocomplete-Provider ist damit nicht Teil des lokalen
Chat-Routings. Die tatsächliche VS-Code-Oberfläche wurde hier nicht ausgeführt;
manuelle Befehle und selbst geänderte Einstellungen bleiben möglich.

### LM Studio

Die Runtime-Vertragstests verwenden simulierte CLI- und API-Antworten. Geprüft
wurden insbesondere die leere Erstinstallation, ein einmaliger Runtime- und
Modelldownload, der kontrollierte Fallback von 32K auf 16K Kontext, das Wiederverwenden
einer passenden vorhandenen Instanz, die Ablehnung eines öffentlichen Listeners,
der Erhalt eines fremden geladenen Modells sowie das Zurückweisen falscher
Tool-Argumente. Es wurde kein automatisches Entladen fremder Modelle beobachtet.

## Noch auf dem tatsächlichen Windows-PC zu prüfen

Windows PowerShell 5.1/ISE, WinGet, Installer/UAC, Windows-Verknüpfungen, die
VS-Code-Oberfläche und die NVIDIA-GPU wurden nicht unter Windows ausgeführt.
Der Bootstrap wurde zusätzlich auf PowerShell-5.1-kompatible Konstrukte geprüft;
eine PowerShell-7-Parserprüfung ersetzt keinen Windows-PowerShell-5.1-Lauf.

Auch Modellqualität, tatsächlicher VRAM-/RAM-Verbrauch, Geschwindigkeit und
Zuverlässigkeit bei längeren Aufgaben sind damit nicht vorweggenommen. Der
Provisionierer darf den lokalen Modellserver erst nach bestandener
Kontrollantwort, einem echten strukturierten Tool-Aufruf und der korrekten
Verarbeitung der Tool-Antwort als bereit markieren. Ein späteres `VERIFIED`-Receipt
bezieht sich auf den erfassten Quellstand und die konfigurierten Prüfungen; es ist
kein Beweis allgemeiner Fehlerfreiheit.

## Prüfdateien

Die ausführbaren Prüfungen des aktuellen Pakets liegen unter `tests/`.
Die Testdateien, die in historischen Abschnitten genannt werden, können aus
früheren Auslieferungen stammen. Synthetische Testserver und Agenten liefern
keinen Nachweis über die realen Modelle auf dem Windows-PC.

Herstellerquellen für den Telemetrieschalter und das geprüfte Ereignisformat:

- https://github.com/Kilo-Org/kilocode/blob/main/packages/kilo-telemetry/src/telemetry.ts
- https://github.com/Kilo-Org/kilocode/blob/main/packages/kilo-telemetry/src/client.ts
- https://kilo.ai/docs/code-with-ai/platforms/cli
- https://github.com/Kilo-Org/kilocode/blob/main/packages/opencode/src/cli/cmd/run.ts

## Prüfungen selbst wiederholen

Im Projektordner, mit PowerShell 7 und Node/Git:

```powershell
pwsh -NoProfile -File .\Quellpaket\tests\Test-Bootstrap.ps1 -BootstrapPath .\Provision-LoKiEnte.ps1
pwsh -NoProfile -File .\Quellpaket\tests\Test-CoderWorkflow.ps1
pwsh -NoProfile -File .\Quellpaket\tests\Test-ProjectSelection.ps1
pwsh -NoProfile -File .\Quellpaket\tests\Test-WorkspaceGuide.ps1
pwsh -NoProfile -File .\Quellpaket\tests\Test-DependencyUpdates.ps1
pwsh -NoProfile -File .\Quellpaket\tests\Test-RouterLifecycle.ps1
pwsh -NoProfile -File .\Quellpaket\tests\Test-ModelPool.ps1
pwsh -NoProfile -File .\Quellpaket\tests\Test-SingleModelFit.ps1
pwsh -NoProfile -File .\Quellpaket\tests\Test-Embedding.ps1
node .\Quellpaket\tests\Test-ModelRouter.mjs
```

Einen echten kleinen Codeauftrag und die semantische Suchprobe nach der
Provisionierung zusätzlich auf dem Windows-PC ausführen.
## Welcome-Projekt — Paket 2026.11.18.19

Test-WelcomeProject.ps1: 11 Prüfungen bestanden mit echtem Git und Node.
Geprüft: sauberer Anfangscommit ohne Remote, reproduzierbarer Rechenfehler,
automatische Erkennung des Node-JUnit-Checks, Erhalt bearbeiteter Dateien und
HEAD beim Update, frisches Beispiel ohne Rücksetzen sowie Registrierung beider
Projekte und Abbruch bei einem unbekannten vorhandenen Ordner.
Test-SelectionIntegration.ps1: 3 Setup-Integrationsprüfungen bestanden.
Alle 16 öffentlichen Bootstrapparameter sind gegen die README-Tabelle geprüft;
PowerShell-Syntaxprüfung bestanden. Der Probeauftrag mit echten lokalen
Modellen wird nach Provisionierung vom Anwender im Welcome-Beispiel gestartet.

## Verwalteter VS-Code-Start und Settings Sync — 2026.11.18.24

Die Profilmigrationstests prüfen neue Installationen, bestehende persönliche
Einstellungen, eigene Terminalprofile, Backups, wiederholte Provisionierung,
fehlerhafte Eingaben und die Erhaltung anderer Profile. Neue Tests prüfen
29 Profil-/VSIX-Bedingungen und zehn Startup-Szenarien, darunter fehlendes Kilo,
Aktivierungsfehler, abgeschaltetes automatisches Öffnen, Schließen während der
Aktivierung und eine geerbte Launcher-Umgebung in einem fremden Profil.
Arbeitsbereichstests prüfen die KI-Vorgabe bei neuen und bestehenden Arbeitsbereichen.

Ein lokaler Integrationstest mit VS Code 1.146.0 installierte die erzeugte VSIX
über den echten CLI zusammen mit Kilo 7.8.30. Prüfungen im Erweiterungshost
bestätigten die wirksame KI-Sichtbarkeitseinstellung, Sync-Ausnahmen, Kilo-Aktivierung
und den registrierten Fokusbefehl. Der echte Helfer rief diesen Befehl erfolgreich
auf. Der isolierte Test verwendete kein Benutzerkonto, keine Ziel-GPU und keine
Modellinferenz. Angemeldeter Cloud-Sync und die abschließende visuelle Abnahme auf
der Zielmaschine bleiben eigene Prüfungen. Der Installer bearbeitet weder die
interne Sync-Datenbank noch löst er Cloud-Konflikte automatisch auf.
