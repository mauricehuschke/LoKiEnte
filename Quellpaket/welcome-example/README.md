# Welcome: Kilo-Workflow ausprobieren

Dieses eigenstaendige Git-Testprojekt enthaelt nur kuenstliche Beispieldaten.
Keine Pakete installieren: Node.js, node:test und node:assert/strict genuegen.
Die Provisionierung erstellt einmalig einen lokalen Anfangscommit. Es gibt
keinen Remote; spaetere Aenderungen werden nicht automatisch committet.

## Test starten

Desktopverknuepfung oeffnen und dieses workflow-test-Projekt auswaehlen.
Im Kilo-Agenten shadow-chat den folgenden Auftrag unveraendert eingeben:

> Behebe den Fehler in discountedPrice in discount.cjs. Die Funktion soll den
> verbleibenden Preis in ganzen Cent nach dem Rabatt liefern:
> (10000, 20) ergibt 8000, (10000, 0) ergibt 10000, (10000, 100) ergibt 0
> und (999, 10) ergibt 899. Negative Preise und Rabatte ausserhalb 0 bis 100
> muessen einen RangeError ausloesen. Verwende den Bugfix-Workflow.
> Leite Akzeptanzkriterien und checks.json automatisch ab. Lass den Testautor
> aussagekraeftige node:test-Tests in tests/discount.test.cjs schreiben und
> unabhaengig pruefen. Weise den Fehler vor dem Fix mit wirklich
> fehlgeschlagenen Tests nach. Aendere danach ausschliesslich discount.cjs.
> Behalte die eingefrorenen Tests bei und fuehre Code-Review und Validierung
> durch. Zeige Rollen, Modelle, Phasen und Ergebnisse bis zum Endstatus.
> Keine Dependencies, Netzwerkzugriffe, Commits oder Pushes.

Erwartet: Vorbereitung -> Vorbereitungsreview -> Architektur -> Testautor ->
Testreview -> rote Ausgangstests -> Implementierung -> gruene Tests ->
Code-Review -> Validierung. Nur ein passender VERIFIED-Bericht ist Erfolg.
checks.json entsteht im verwalteten Auftragsordner. Dort stehen auch
LOKI-STATUS.md und die Anleitung. Bei Rueckfragen/Fehlern die Details ansehen.
Dieser Test prueft den vollstaendigen Basisablauf. Security- und
Integrationsspezialisten werden bei entsprechenden Aenderungsarten verlangt;
die reine Rechenfunktion benoetigt sie nicht.

## Wiederholen

Updates erhalten deinen bearbeiteten Teststand. Fuer einen frischen Versuch
in PowerShell 7 ausfuehren (bei anderem Installationsort den Pfad anpassen):

```powershell
& 'D:\LoKi\app\New-WelcomeTestProject.ps1' -InstallRoot 'D:\LoKi' -NewExample
```

Danach den neu registrierten workflow-test-Ordner im Launcher auswaehlen.
Es wird kein vorhandenes Projekt zurueckgesetzt. Die Tests laufen weiterhin
mit deinem Windows-Konto; das Beispiel ist keine Betriebssystem-Sandbox.
