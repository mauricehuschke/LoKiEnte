# LoKi anwenden: vom Auftrag zum geprüften Code

Diese Anleitung beschreibt den Workflow ab Paket **2026.11.18.18**. Sie richtet
sich an Anwender, die mit VS Code und Git arbeiten können. Die lokale KI
unterstützt Entwicklung und Prüfung; fachliche Abnahme und Commit bleiben bei dir.

## 1. Projekt öffnen

Starte die erzeugte Desktopverknüpfung. Wähle ein bekanntes Projekt oder gib
einen weiteren vorhandenen Projektordner an. Für ein ganz neues Projekt zunächst
den Ordner und das gewünschte Grundgerüst selbst anlegen. Schreibende Workflows
benötigen die Wurzel eines Git-Repositories mit mindestens einem Commit.

VS Code öffnet den Quellordner und den zugehörigen LoKi-Auftragsordner. Die
Arbeitsbereichsdateien und LoKi-Konfiguration liegen außerhalb deines Repositories
unter `<InstallRoot>\projects\<Projektkennung>` bzw. `workspaces`.

Wähle in Kilo `shadow-chat` und gib deinen Auftrag direkt ein. Der Chat kann
lesen, beraten und über `loki_start` den kontrollierten Entwicklungsablauf starten.
Die eigentlichen Dateiänderungen erfolgen in dessen begrenzten Agentenphasen.
Ein eigener Auftragsdatei- oder JSON-Schritt ist im normalen Ablauf nicht nötig.

## 2. Einen kleinen Auftrag formulieren

Beschreibe gewünschtes Verhalten, Randbedingungen und Grenzen, beispielsweise:

> Ergänze in der Lagerlogik eine Nachbestellempfehlung: Sie soll gelten, wenn der
> Bestand unter der Mindestmenge liegt. Gleicher oder höherer Bestand genügt.
> Decke die Grenzfälle mit Tests ab; ändere keine Datenbank oder Oberfläche.

Kilo übergibt den vollständigen Auftrag an `loki_start`. Ein lesender
Vorbereitungsagent untersucht Projekt, vorhandene Tests und Regeln. Er leitet
Workflow, Akzeptanzkriterien `AC-1`, `AC-2`, …, Änderungsarten und exakte
Produktions-/Testdateien ab. Testbefehle wählt er aus lokal erkannten Vorlagen
oder vorhandenen Projektchecks; er darf keine freien Shellbefehle erfinden.

Ein unabhängiger **Vorbereitungsreview** prüft die Zuordnung zum Originalauftrag,
die Grenzen und die Testauswahl. Erst nach dessen `PASS` wird `checks.json`
gesichert und ergänzt. Bei unklaren Anforderungen, fehlenden Werkzeugen oder
Konflikten stoppt der Ablauf mit einer konkreten `NEEDS_INPUT`-Meldung. Kläre den
Punkt in Kilo und starte den ergänzten Auftrag erneut; es gibt keinen stillen
Wechsel zu weniger strengen Prüfungen.

Die Kriterien werden zu Laufbeginn festgehalten. Der Testautor darf ihre IDs
und Anzahl nicht ändern. Eine Zuordnung aller IDs beweist allein noch keine
vollständige fachliche Abdeckung; dafür bleiben die unabhängigen Reviews nötig.

## 3. Automatische Checks und eigene Vorgaben

`checks.json` enthält den geprüften Auftrag und wiederverwendbare Projektchecks.
Die automatisch verwalteten Kriterien, Kategorien und Dateipfade werden beim
nächsten Auftrag neu abgeleitet. Herkunft, Prüfsummen und Sicherungen verhindern,
dass manuelle Änderungen daran still überschrieben werden. Eigene vollständige
Checks bleiben verpflichtend; unbekannte Felder und Originalbefehle bleiben erhalten.
Beim ersten automatischen Auftrag werden ältere auftragsspezifische Felder unter
`automation.importedTaskFields` archiviert und dem Reviewer ausdrücklich gezeigt.

Erkannt werden der eingebaute Node-Test-Runner, lokal installierte Vitest-, Jest-
und Playwright-Runner, Python/pytest-Projekte sowie TypeScript-Typechecks. Node,
Vitest, Playwright und pytest nutzen JUnit; der Jest-Adapter übernimmt tatsächliche
Assertion-Ergebnisse in das unten beschriebene JSON. Die automatische Vorbereitung
installiert keine Pakete. Fehlt etwa pytest in der Python-Umgebung, muss es gemäß
Projektanleitung eingerichtet werden. Unbekannte Buildketten benötigen einmalig
einen passenden eigenen Check.

Alte reine `npm test`-/Exitcode-Checks bleiben gespeichert. Ein erkannter
strukturierter Ersatz wird nur nach unabhängigem Vergleich mit ihrem Zweck
für den Auftrag eingesetzt. Ist keine passende Variante vorhanden, stoppt die
Vorbereitung. Das reine Umbenennen eines Checks erzeugt keinen Testnachweis.

Alle Befehle laufen mit deinen **Benutzerrechten** im Projekt. Installiere
Projektabhängigkeiten vorher nach dessen Anleitung. Verwende lokale Testdaten
und nichtinteraktive Befehle. Für dauerhafte zusätzliche Grenzen kannst du
`limits.allowedWritePaths` und `limits.allowedTestWritePaths` als exakte
Dateipfadarrays hinterlegen; die automatische Vorbereitung erweitert sie nicht.

Optionales Referenzbeispiel für einen selbst konfigurierten Node-Check. Für den
normalen Kilo-Auftrag musst du dieses JSON nicht von Hand erstellen. Die genannte
Testdatei darf vom Testautor neu angelegt werden:

```json
{
  "schemaVersion": 2,
  "writePaths": ["src/stock.cjs"],
  "testWritePaths": ["tests/stock.test.cjs"],
  "changeTypes": ["other"],
  "acceptanceCriteria": [
    {"id": "AC-1", "description": "Bei Bestand unter der Mindestmenge wird eine Nachbestellung empfohlen; bei gleichem oder höherem Bestand nicht."}
  ],
  "regressionCheck": "tests",
  "checks": [
    {
      "name": "tests",
      "kind": "test",
      "reportFormat": "junit",
      "command": "node",
      "arguments": ["--test", "--test-reporter=junit", "--test-reporter-destination={report}", "tests/stock.test.cjs"],
      "timeoutSeconds": 120
    }
  ]
}
```

| Feld | Bedeutung |
|---|---|
| `writePaths` | Exakte Produktionsdateien relativ zur Repository-Wurzel; `/` als Trenner. Keine Globs. |
| `testWritePaths` | Exakte Dateien für den Testautor, getrennt von `writePaths`. Ein leeres Array erlaubt nur die Zuordnung bestehender Tests. |
| `acceptanceCriteria` | Eindeutige IDs `AC-1`, `AC-2`, … und konkrete Beschreibungen. |
| `changeTypes` | Eine oder mehrere Kategorien: `security`, `ui`, `api`, `other`. |
| `regressionCheck` | Bei Bugfix der Testcheck, dessen konkrete Regressionsfälle vor dem Fix scheitern müssen. |
| `checks[].kind` | `test` für Verhaltenstests, `integration` für Zusammenspiel von Komponenten, `static` für z. B. Typecheck/Lint/Build. |
| `reportFormat` | Für `test` und `integration`: `junit` oder das unten beschriebene `json`. Für `static` nicht nötig. |

Jeder Check braucht einen eindeutigen Namen, `command`, einzelne Stringargumente
und ein ganzzahliges Zeitlimit zwischen 1 und 7200 Sekunden. Maximal zwölf Checks
pro Auftrag. Mindestens ein Testcheck ist für eine vollständige Abnahme nötig;
ein erfolgreicher Build allein deckt keine Verhaltensanforderung ab.

Der Runner ersetzt `{report}` in Argumenten durch einen neuen absoluten Pfad für
genau diesen Check und diese Phase. Derselbe Pfad steht als `LOKI_TEST_REPORT`
bereit. Das Testwerkzeug muss seinen Bericht dorthin schreiben. Bereits vorhandene
Berichte werden nicht wiederverwendet. Die mitgelieferten Adapter sind Teil der
Provisionierung; eigene Testkommandos bleiben möglich. Der Testautor darf beides
nicht ändern. Keine Watch-Modi, Installations-,
Deployment- oder Produktivdatenbankbefehle als Checks verwenden.

Projektkonfiguration, Manifest-/Lockdateien, Ignore-Dateien und Zugangsdaten sind
keine freigebbaren Produktionsdateien. Eine nötige Änderung daran erledigst du
vor dem Lauf selbst. Bekannte Testpfade in `writePaths` werden zurückgewiesen;
auch Tests mit ungewöhnlichen Namen gehören ausdrücklich in `testWritePaths`.

## 4. Was automatisch geschieht

1. **Vorbereitung und Vorbereitungsreview:** Kriterien, Kategorien, Dateiumfang
   und lokale Checks werden aus dem Auftrag abgeleitet und unabhängig geprüft.
2. **Planung:** Ein lesender Architekturagent untersucht Projektregeln, Aufgabe
   und Risiken. Die Quelländerungen und Akzeptanzkriterien werden festgehalten.
3. **Testerstellung:** `shadow-test` schreibt ausschließlich freigegebene Tests.
   Er ordnet jedem Kriterium konkrete Testfall-IDs und Checknamen zu und nennt
   gegebenenfalls genau die erwarteten Ausgangsfehler.
4. **Testreview:** `shadow-test-reviewer` prüft die Tests in einer frischen Sitzung,
   bevor der Runner sie ausführt. Fehlende Assertions, abgeschwächte bestehende
   Tests, fingierte Berichte oder problematische Nebenwirkungen verhindern den Start.
5. **Ausgangstests:** Der Runner führt die Checks aus. Bei Bugfix müssen die
   benannten Regressionsfälle tatsächlich fehlschlagen. Bei Features sind vorab
   benannte neue Fehler erlaubt; bei Refactoring müssen die Ausgangstests bestehen.
6. **Implementierung:** Der Coding-Agent darf nur Produktionsdateien bearbeiten.
   Geprüfte Testdateien sind über Schreibrechte und Hashvergleiche geschützt.
7. **Erneute Checks und Review:** Tests laufen erneut; ein separater Reviewer
   prüft den Quellstand und beurteilt auch die tatsächlichen Änderungsarten.
8. **Pflichtspezialisten:** Je nach Änderungsart folgen Security- und
   Integrationsprüfung, jeweils in eigener Sitzung.
9. **Validierung:** Ein weiterer Agent beurteilt die fachliche Aussagekraft der
   ausgeführten Checks. Das Skript prüft zusätzlich die Kriterienzuordnung und
   einzelnen Testergebnisse. Erst danach ist `VERIFIED` möglich.

Frontend-/Backend-Spezialisten können während der Umsetzung sequenziell helfen.
Es läuft jeweils eine Modellgenerierung. Coder Fast betrifft die Umsetzung;
Testreview, Code-Review und Validierung behalten ihre eigenen Modellzuordnungen.

Muss ein bereits geprüfter Test geändert werden, stoppt der Auftrag. Korrigiere
bei Bedarf Aufgabe/Freigaben und starte einen neuen Lauf mit erneuter Testerstellung
und Testreview. Eine Korrekturrunde innerhalb desselben Laufs darf nur die
Produktion ändern. Es gibt standardmäßig höchstens eine solche Korrekturrunde.

## 5. Wann Spezialprüfungen verpflichtend sind

| Kategorie | Beispiele | Erforderliche Prüfung |
|---|---|---|
| `security` | Anmeldung, Berechtigungen, Dateizugriff, externe Eingaben, Geheimnisse, Vertrauensgrenzen | Separater `shadow-security` mit bestandenem Urteil |
| `ui` | Bedienoberfläche, Interaktionen, Zustände | Ein zugeordnetes `integration`-Testergebnis und `shadow-integration` |
| `api` | Schnittstellen, Endpunkte, Zusammenspiel von Komponenten | Ein zugeordnetes `integration`-Testergebnis und `shadow-integration` |
| `other` | Rein interne Logik ohne obige Merkmale | Testreview, Code-Review und Validierung bleiben verpflichtend |

Deine Kategorien, Planer- und Reviewerbewertung sowie konservative Pfadhinweise
werden zusammengeführt. Eine spätere Einstufung kann eine Prüfung hinzufügen,
aber nicht deine Einstufung abschwächen. Erkennt der Reviewer erst nach der
Implementierung einen Integrationsbedarf und fehlt der passende Check, ist das
Ergebnis nicht verifiziert. Ergänze ihn und starte neu.

Ein Unit-Test wird durch die Bezeichnung `integration` nicht zum Integrationstest.
Der Spezialist muss den tatsächlichen Bezug zu UI/API und ausgeführten Testfällen
prüfen. Diese semantische Einordnung bleibt eine Modellbewertung und kann irren.

## 6. Unterstützte Berichte

JUnit wird anhand der einzelnen `<testcase>`-Elemente ausgewertet. Eine Test-ID
ist `classname::name`, bei leerem `classname` nur `name`. Doppelte IDs innerhalb
eines Checks sind nicht zulässig; Testnamen entsprechend eindeutig gestalten.
`failure`/`error` zählen als fehlgeschlagen, `skipped` als übersprungen. XML-DTDs
und externe Entitäten werden abgewiesen. Testberichte sind auf 16 MiB begrenzt.

Ein eigenes bestätigtes Testwerkzeug kann alternativ dieses JSON schreiben:

```json
{
  "schemaVersion": 1,
  "tests": [
    {"id": "stock::below-minimum", "status": "passed"},
    {"id": "stock::at-minimum", "status": "failed"},
    {"id": "optional-scenario", "status": "skipped"}
  ]
}
```

Das Beispiel zeigt die Struktur, keinen erfolgreichen Lauf. Die Werte müssen
aus tatsächlich ausgeführten Assertions stammen. Ein eigener Reporter darf
keine pauschale Erfolgsliste erzeugen. Für verfügbare Frameworks deren Reporter
verwenden. Änderungen am Reporter erfolgen außerhalb des Agentenauftrags.

Ein leerer Bericht, null ausgeführte Tests, fehlende/übersprungene Pflichtfälle,
unerwartete Ausgangsfehler und fehlgeschlagene Endtests verhindern `VERIFIED`.
Nicht zugeordnete übersprungene Tests bleiben im Bericht sichtbar. Erwartete
Ausgangsfehler benötigen Exitcode 1 und genau die vorher benannten fehlgeschlagenen
Testfälle; Import-/Syntaxfehler sind kein gültiger Regressionsnachweis.

## 7. Sichtbarer Ablauf, Start und Ergebnis

Nach `loki_start` verfolgt Kilo den Auftrag mit `loki_status`. Die Werkzeugausgabe
zeigt Phase, Agentenrolle, angefordertes Rollenmodell und Zustand sowie aktuelle
Werkzeugaktivität. `loki_details` liefert den begrenzten Laufbericht und Ereignisse.
Zusätzlich steht im LoKi-Auftragsordner `LOKI-STATUS.md`; dort kannst du den Verlauf
auch neben dem Chat ansehen. Die Anzeigen stammen aus tatsächlichen Laufereignissen.

Die kontrollierten Phasen laufen als getrennte externe Kilo-CLI-Sitzungen. Sie
erscheinen über diese Statusansicht, nicht automatisch als native Kilo-Task-
Kindersitzungen oder als vollständiger Graph im Inspector. Native lesende
Chat-Unteragenten können daneben ihren eigenen Kilo-Verlauf haben. Sichtbar sind
Rollen, Aktivitäten und Ergebnisse, kein vollständiger interner Denkprozess.

Zum Abbrechen ausdrücklich in Kilo um Stopp bitten: `loki_cancel` beendet den
eigenen Prozessbaum; `loki_status` bestätigt anschließend `CANCELLED`. Das Abbrechen
einer Statusabfrage allein beendet einen Hintergrundauftrag nicht. Bereits
geschriebene Änderungen bleiben für deine Diff-Prüfung erhalten.

Als Alternative kannst du einen Auftrag in `task.md` schreiben und in VS Code
**Terminal > Aufgabe ausfuehren** → `Local AI: Auftrag automatisch mit Pruefung`
wählen. Auch die spezifischen Tasks `Local AI: Feature mit Pruefung`, `Bugfix`,
`Refactor` und die Varianten mit `(Coder Fast)` bereiten `checks.json` automatisch
vor. Der gewählte spezifische Workflow bleibt dabei verbindlich. Terminaltasks
schreiben ihre Ereignisse und Belege in den Laufordner; die Chat-Statuswerkzeuge
beziehen sich auf über `loki_start` gestartete Aufträge.
`Review` und `Architecture` bleiben lesend. Für eine vollständige Review-Abnahme
sind ebenfalls Kriterien und strukturierte Checks nötig. Ohne Checks können sie
höchstens `REVIEWED_UNVALIDATED` ergeben.

Im Terminal stehen Status und Pfad zu `runs\<Laufkennung>\receipt.json`.
Der Bericht enthält Kriterien, Testsitzung, Testreview, eingefrorene Testhashes,
Ausgangs- und Endergebnisse, Spezialurteile und konkrete Ablehnungsgründe.

| Status | Bedeutung |
|---|---|
| `VERIFIED`, Exitcode 0 | Alle technischen und agentengestützten Prüfbedingungen für diesen Quellstand bestanden. |
| `REVIEWED_UNVALIDATED`, Exitcode 2 | Lesender Review ohne ausführbare Abnahme; keine fertige Codefreigabe. |
| `NOT_VERIFIED`, Exitcode 1 | Fehler, fehlender Nachweis oder offener Befund; Bericht prüfen. |
| `NEEDS_INPUT` in Kilo | Konkrete Anforderung, Konfigurationsänderung oder fehlende Voraussetzung klären; noch keine Freigabe. |
| `CANCELLED` / `FAILED` in Kilo | Auftrag abgebrochen bzw. technische Ausführung gescheitert; vorhandenen Diff und Belege prüfen. |
| `WORKER_UNRESPONSIVE` in Kilo | Worker meldet sich nicht; automatisches Polling endet, Prozessende und Prüfergebnis sind unbestätigt. |

Bleibt ein Auftrag länger als 30 Sekunden in der Startwarteschlange oder fehlt
120 Sekunden lang ein Worker-Heartbeat, zeigt Kilo `WORKER_UNRESPONSIVE`.
Die Projektsperre bleibt erhalten. Prüfe lokale Jobprotokolle und Prozesse;
starte keinen zweiten Auftrag und lösche die Sperre nicht ungeprüft. Ein erneuter
Statusabruf kann einen wieder erreichbaren Worker zeigen; ein Abbruch kann
weiterhin vorgemerkt werden. Wiederherstellung erst nach bestätigtem Prozessende
oder Systemneustart, ohne den Auftrag dadurch als erfolgreich zu behandeln.

Prüfe den Git-Diff und die Anwendung selbst, bevor du committest. LoKi erzeugt
keinen separaten Worktree und führt keine automatischen Commits oder Pushes aus.
Bestehende Änderungen werden nicht zurückgesetzt. Nach Änderungen am geprüften
Quellstand ist ein neuer Prüflauf nötig.

Tests laufen unter deinem Windows-Konto. Bereinigte Umgebungsvariablen und eigene
Temp-/Profilpfade sind keine Betriebssystem-Sandbox. Projektcode und Tests können
weiterhin Dateien und Netzwerk erreichen. Verwende bestätigte Befehle, lokale
Testdaten und keine produktiven Zugangsdaten. Auch strukturierte Testberichte
beweisen nicht, dass Tests fachlich sinnvoll oder manipulationssicher sind.

## 8. Bestehende Projekte aktualisieren

Beende aktive LoKi-Aufträge und Fenster. Führe den neuen Provisionierer mit dem
bisherigen Installationsverzeichnis aus. Er aktualisiert alle erreichbaren
registrierten Projekte, ihre Aufgaben und `LOKI-WORKFLOW.md`.

Alte `checks.json` erhalten eine Sicherung und die neuen Felder. Bereits
freigegebene, eindeutig erkennbare Testpfade werden bei der erstmaligen Migration
von `writePaths` nach `testWritePaths` verschoben. Befehle und eigene Felder bleiben
erhalten. Die verwalteten VS-Code-Tasks verwenden danach die automatische
Vorbereitung; neue Aufträge können direkt im Kilo-Chat starten. Kriterien,
Kategorien und passende Berichte werden für den nächsten konkreten Auftrag
abgeleitet und reviewed. Alte reine Exitcode-Prüfungen gelten weiterhin nicht
automatisch als vollständiger Testnachweis.

Ein vorhandenes persönliches `ANLEITUNG.md` bleibt erhalten. Maßgeblich für den
aktuellen Ablauf ist die verwaltete Datei `LOKI-WORKFLOW.md`.

Technischer Hintergrund: [Node-Testreporter](https://nodejs.org/api/test.html#test-reporters)
und [Kilo-Agenten](https://kilo.ai/docs/customize/custom-subagents). Die für deine
Installation freigegebenen Versionen stehen im Provisionierungsbericht.
# Welcome-Probelauf

Die Provisionierung registriert ein eigenes Testprojekt unter
welcome/workflow-test. Wähle es im Launcher und kopiere den Auftrag aus seiner
README in shadow-chat. Die absichtlich fehlerhafte Rabattfunktion benötigt
nur Node.js ohne externe Pakete. Ein Anfangscommit ist bereits vorhanden.
Updates erhalten den bearbeiteten Stand; New-WelcomeTestProject.ps1 -NewExample
erzeugt einen weiteren, getrennten Versuch. Der Test prüft den Basisworkflow
mit roten/grünen Tests; Security-/Integrationsrollen sind bedarfsabhängig.

