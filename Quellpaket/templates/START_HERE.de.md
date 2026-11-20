# LoKiEnte

<!-- lokiente-language -->
[English](START_HERE.md) · Deutsch

Die Programmausgaben sind Englisch. Diese Datei ist die deutsche Dokumentation.
<!-- /lokiente-language -->

Dieses Fenster verwendet ein eigenes VS-Code-Profil und lokale Modelle.

1. Starte die Desktopverknuepfung LoKiEnte. Waehle ein bekanntes Projekt per Nummer oder N fuer einen weiteren vorhandenen Projektordner (Pfad eingeben). 0 bricht vor dem Modellstart ab. Ein direkter Launcher-Aufruf mit -ProjectPath oeffnet das Projekt ohne Menue.
2. Chat/Planung: Kilo-Seitenleiste. Rollen und /feature, /bugfix, /refactor, /review, /architecture sind vordefiniert.
3. Codeaenderungen direkt in shadow-chat eingeben. Kriterien und checks.json werden automatisch vorbereitet und unabhaengig geprueft.
4. Zum Ausprobieren im Launcher welcome/workflow-test waehlen. Der fertige Testauftrag steht in [Beispielanleitung](../welcome-example/README.de.md). Das Beispiel nutzt nur kuenstliche Daten, Node-Bordmittel und ein eigenes lokales Git-Repository.
5. Nur ein bestandener Aufgabenlauf darf VERIFIED melden. Der Status bezieht sich auf genau den geprueften Arbeitsbaum und die konfigurierten Pruefungen.

Die Indizierung ist standardmaessig fuer alle Projekte aus. Fuer semantische
Suche im Dual-Modus mit -IndexingMode OnDemand oder Automatic provisionieren.
OnDemand fragt beim Desktopstart nach (Enter bedeutet Nein). Vor einer anderen
Auswahl alle LoKiEnte-Fenster schliessen. Nach dem Start der Indizierung in Kilo
Einstellungen > Indexing oeffnen und einmalig fuer das Projekt freigeben.
Dateisuche, Subagenten und Tests funktionieren auch ohne Indizierung. Vorher
.gitignore und .kilocodeignore auf sensible Dateien pruefen. Der Index wird
lokal gespeichert und ist nicht automatisch verschluesselt. Den Status
Complete abwarten; eine Konfiguration allein beweist keinen fertigen Index.

Kilo zeigt Rollen/Modelle/Phasen ueber loki_status und LOKI-STATUS.md; loki_details erklaert Befunde. Der Runner fuehrt die Tests aus. Der Chat schreibt nicht direkt.
Ein bearbeitetes Testprojekt bleibt beim Update erhalten. Ein frisches Beispiel erzeugt app/New-WelcomeTestProject.ps1 -InstallRoot <Installationsordner> -NewExample in PowerShell 7. Das Beispiel ist keine Betriebssystem-Sandbox.
Anmeldungen bei GitHub/Lovable und projektspezifische Geheimnisse werden nicht durch dieses Paket eingerichtet.
