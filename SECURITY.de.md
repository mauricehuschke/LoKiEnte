# Datenschutz und Zugangsdaten

<!-- lokiente-language -->
[English](SECURITY.md) · Deutsch

Die Programmausgaben sind Englisch. Diese Datei ist die deutsche Dokumentation.
<!-- /lokiente-language -->

In dieses Repository gehören nur Quellen, Tests, Dokumentation und der
eingebettete Installer. Provisionierungsberichte, Laufzeitprofile, Modellzustände,
Sicherungen und Beispielprojekte einer tatsächlichen Installation bleiben lokal.
Die .gitignore schließt diese Dateien aus. Bereits getrackte Dateien werden
dadurch nicht automatisch aus älteren Commits entfernt.

API-Tokens über die vorgesehenen Umgebungsvariablen bzw. lokale
Zugangsdatenverwaltung bereitstellen. Variablennamen wie LOKIENTE_LM_API_KEY sind
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

## Werkzeugupdates

Für jede Update-Richtlinie gilt bei der Provisionierung ein Mindestalter von 48 Stunden. Vor dem Update ermittelt der Installer exakte Zielversionen. Dynamische Richtlinien benötigen einen datierten Katalognachweis. Siehe [Update-Anleitung](README.de.md#updates-für-entwicklungswerkzeuge-wählen).

## Isolierter Windows-Gast

In der Standardsitzung gelten Kilos Werkzeugrechte. Tests und Erweiterungen
haben die Rechte deines Windows-Kontos. Das optionale Offline-Profil startet
einen eigenen Hyper-V-Gast, bevor der Host Projekte, Modelle, Router oder
Editor öffnet. Promptregeln pflegst du in Kilo. Ein Profilwechsel gilt ab dem
nächsten Desktopstart. Schließe zuvor die verwalteten Host-Fenster.

### Einmalig vorbereiten

Prüfe zuerst **Check host capabilities** in der LoKiEnte-Seitenleiste. Die Prüfung zeigt die lokale Hyper-V-Verfügbarkeit und erkennbare GPU-Partitionen an, ohne eine VM zu starten.

1. Prüfe Hyper-V, seine PowerShell-Befehle und VMConnect auf dem Host. Dein
   Konto benötigt Verwaltungsrechte für Hyper-V. Beim Cloud-PC muss der
   Anbieter verschachtelte Virtualisierung unterstützen. Prüfe GPU-Partition
   und Treiber im Gast separat.
2. Provisioniere einen eigenen Windows-Gast mit dem Installer dieses Branches,
   den Modellen und Werkzeugen, solange Downloads möglich sind. Teste ein
   lokales Modell. Fahre den Gast herunter, entferne **alle virtuellen
   Netzwerkadapter** und wirf Installationsmedien aus. Verwende eine lokale
   VHDX-Systemplatte. Entferne durchgereichte Host-Laufwerke und Geräte,
   serielle Pipes und Fibre Channel. Für den GPU-Test ist GPU-P vorgesehen.
3. Aktiviere in den Integrationsdiensten der VM **Gastdienstschnittstelle**
   für die einseitige Übertragung in den Gast. Deaktiviere auf dem Host die
   **Richtlinie für den erweiterten Sitzungsmodus**. So bleiben Laufwerks-
   und Zwischenablagenumleitung gesperrt. Diese Richtlinie betrifft weitere
   VMs desselben Hosts. Der Launcher prüft sie. Die Netzwerkverbindung deines
   Shadow-Hosts bleibt für den Fernzugriff bestehen.
4. Wähle im verwalteten Host-Fenster **LoKiEnte → Choose security profile →
   Offline Hyper-V guest**, anschließend die VM und einen beschreibbaren,
   geschützten Host-Ordner. Der Launcher legt darin eine wiederverwendbare
   Datei `lokiente-et-<id>.probe` an. Standardmäßig verwendest du Projekte
   auf der Gastplatte. Optional kannst du eine Projekt-ZIP außerhalb des
   geschützten Ordners auswählen. Pro Start wird dieses Archiv im Gast als
   `C:\LoKiEnte-Imports\<Sitzung>\project.zip` abgelegt. Entpacke es dort.
   Änderungen bleiben auf der Gastplatte.
5. Schließe die verwalteten VS-Code-Fenster des Hosts. Starte die
   Desktopverknüpfung bei vollständig ausgeschalteter VM. Melde dich an der
   Basiskonsole des Gastes an, öffne dort dessen LoKiEnte-Verknüpfung und
   wähle ein Gastprojekt. Starte **LoKiEnte → Run E.T. acceptance test**.
   Fehlt eine Voraussetzung, bricht der Launcher ab. Ist die VM bereits
   gestartet und die Dateiübertragung scheitert, fahre sie vor dem nächsten
   Versuch herunter.

### Ergebnisse auswerten

Der Host bestätigt die VM-Konfiguration sowie die Existenz der Prüfdatei und
überträgt einen für diesen Gaststart gültigen Prüfauftrag. Ein Testprozess
des regulären Node-Projektprüfers prüft IPv4- und IPv6-Verbindungen auf
TCP-Port 443 (öffentliche Cloudflare-Adressen, keine Nutzdaten), externe
Schnittstellenadressen, lokales Loopback und das Öffnen der Host-Prüfdatei. Im gewählten Gastprojekt schreibt, liest und entfernt er eine temporäre Datei.
Eine reale Anfrage geht an das lokale LM-Studio-Modell im Gast. Nur ein
positiver GPU-Compute-Messwert eines bekannten Inferenzprozesses während der
Antwort zählt für den GPU-Test. Eine erkannte Grafikkarte oder eine CPU-Antwort
reicht nicht. Bei fehlenden Messwerten bleibt die GPU unbestätigt.
Einzelergebnisse findest du unter **Ausgabe → LoKiEnte Security** und in der
dort genannten lokalen JUnit-Datei. Der Test prüft konkrete Zugriffe. Die
Isolation setzt Hyper-V durch. Vertrauenswürdige Host-Administratoren verwalten
die VM. Lass ihre Netzverbindung während der Arbeit getrennt.

Im Dialog der Host-Desktopverknüpfung kannst du mit **Nein** das Profil zurücksetzen. Öffne die Verknüpfung anschließend erneut. **Abbrechen** behält das Offline-Profil bei.

Für die Rückkehr zur Standardsitzung schließe den Gast und führe auf dem Host
den folgenden Befehl mit deinem Installationspfad aus. Beim nächsten
Desktopstart erscheint wieder die normale Projektauswahl.

```powershell
pwsh -NoProfile -File 'D:\LoKiEnte\app\Start-LocalAI.ps1' -ResetSecurityProfile
```

Erneutes Provisionieren erhält die Profileinstellung. Aktualisiere den Gast in
einem getrennten Wartungsfenster. Eine VM mit Netzwerkadapter lässt sich im
Offline-Profil nicht starten. Nach dem Zurücksetzen kannst du die Prüfdatei
entfernen. [Hyper-V-Geräteumleitung](https://learn.microsoft.com/de-de/windows-server/virtualization/hyper-v/enhanced-session-mode)
