# Datenschutz und Zugangsdaten

In dieses Repository gehören nur Quellen, Tests, Dokumentation und der
eingebettete Installer. Provisionierungsberichte, Laufzeitprofile, Modellzustände,
Sicherungen und Beispielprojekte einer tatsächlichen Installation bleiben lokal.
Die .gitignore schließt diese Dateien aus. Bereits getrackte Dateien werden
dadurch nicht automatisch aus älteren Commits entfernt.

API-Tokens über die vorgesehenen Umgebungsvariablen bzw. lokale
Zugangsdatenverwaltung bereitstellen. Variablennamen wie SHADOW_LM_API_KEY sind
keine Zugangsdaten. Keine echten Werte in Skripte, Tests, Screenshots oder Issues
kopieren. Nur synthetische Testdaten und neutrale Beispielpfade verwenden.

Vor Veröffentlichung Gitleaks auf Dateistand und Historie ausführen. Der Installer
enthält eine Base64-kodierte ZIP; deshalb müssen auch ihre entpackten Inhalte
gescannt werden. Archive in Sicherungen dürfen ebenfalls private Daten enthalten.
SHA-256-Prüfsummen in Manifesten sind keine geheimen Schlüssel.

Für Git-Commits die GitHub-No-Reply-Adresse und den öffentlichen Benutzernamen
verwenden. GitHub zeigt die passende No-Reply-Adresse in den E-Mail-Einstellungen.
Eine Änderung der Git-Konfiguration bereinigt keine bereits vorhandenen Commits.

Falls Zugangsdaten veröffentlicht wurden: zunächst sperren/rotieren und danach
die Historie bereinigen. Ein Löschcommit allein reicht nicht. Veröffentlichte
Historie nur koordiniert ersetzen; andere Klone und GitHub-Caches können alte
Inhalte weiterhin enthalten. Gegebenenfalls GitHub Support zur Entfernung
zwischengespeicherter sensibler Inhalte kontaktieren.
