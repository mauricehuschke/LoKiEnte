# Eine Teamübersicht für Supporttickets entwickeln

[English](README.md)

Diese eigenständige Node.js-Übung verwendet erzeugte Tickets. Öffne eine frische Kopie des Startprojekts über den LoKiEnte-Desktopstarter und gib diesen Auftrag in Kilos `shadow-chat` ein.

> Ergänze das lokale Supportboard um eine Teamübersicht. Zeige auf der Startseite und unter GET /api/summary die Anzahl offener und erledigter Tickets mit Sichtbarkeit „team“. Die Beispieldaten müssen in beiden Ansichten 2 offene und 1 erledigtes Ticket ergeben, eine leere Liste zweimal 0. Interne Tickets dürfen keine Zahl beeinflussen. Weder Titel noch Kontaktdaten dürfen ausgegeben werden. Erhalte GET /health. Ändere nur src/tickets.cjs, src/server.cjs und src/page.cjs sowie separate Unit- und Integrationstests. Nutze den Feature-Workflow mit unabhängiger Testprüfung, Sicherheitsreview, Integrationsreview und Abschlussprüfung. Führe die Tests lokal aus. Keine neuen Abhängigkeiten oder externen Netzaufrufe.

Die Rollen und Ergebnisse erscheinen in Kilo und in `LOKI-STATUS.md`. Starte nach der Prüfung `node src/server.cjs` und öffne [das Board](http://127.0.0.1:4318/) sowie [den JSON-Endpunkt](http://127.0.0.1:4318/api/summary). Strg+C beendet den lokalen Server. Mit `node --test` wiederholst du die Tests.

Entpacke das heruntergeladene Startprojekt in einen eigenen Ordner. Lege dort, wo `package.json` liegt, zuerst den lokalen Git-Ausgangsstand an. Wähle den Ordner anschließend über den Desktopstarter aus.

```powershell
git init
git add .
git -c user.name=Example -c user.email=example@localhost -c commit.gpgsign=false commit -m "Start support board"
```
