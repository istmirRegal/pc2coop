# Feature Registry

Zentrale Liste **aller** Funktionen von PC2Coop, die es gibt oder gab. Jede Funktion hat
eine feste ID (`FEAT-nnn`). IDs werden nie neu vergeben, auch nicht nach dem Entfernen.
Die ausführliche Beschreibung jeder Funktion steht in der verlinkten Bereichsdatei unter
einer Überschrift `### FEAT-nnn`.

`tools/check_docs.py` prüft, dass Registry, Bereichsdateien und Code zusammenpassen
(jede ID genau einmal beschrieben, jede genannte Datei und Funktion existiert, jede
Netzwerknachricht, UI-Aktion und DLL-Befehl ist dokumentiert).

**Status-Werte**

| Status | Bedeutung |
|---|---|
| `Implemented` | im Code und in der Testkopie im Spiel geprüft (allein, mit nachgestelltem Mitspieler) |
| `Implemented-Untested` | im Code und mit Unit-Tests geprüft, im Spiel noch nicht |
| `Legacy` | noch im Repository, wird aber nicht mehr ausgeliefert oder benutzt |
| `Replaced` | durch eine andere Funktion ersetzt (Spalte „Ersetzt durch“ in der Bereichsdatei) |
| `Removed` | entfernt; die Bereichsdatei sagt warum |
| `Planned` | geplant, noch nicht gebaut |

Mit zwei echten Spielern wurde bisher nur der Grundablauf vor 1.5.0 getestet (Beitritt,
Park-Übertragung, Bauen); seine Fehler sind in 1.4.3/1.5.0 behoben. Alles Spätere ist allein
in der Testkopie mit nachgestelltem Mitspieler geprüft – „Implemented“ heißt deshalb nicht
„mit zwei PCs bestätigt“ (siehe ROADMAP.md).

**Neue ID vergeben:** nächste freie Nummer am Ende des passenden Bereichs nehmen; reicht
der Bereich nicht, die nächste freie Nummer ab 230.

## Installation und Verteilung — [features/installation-and-updates.md](../features/installation-and-updates.md)

| ID | Funktion | Status | Seit |
|---|---|---|---|
| FEAT-001 | Installer (`INSTALL.cmd`) | Implemented | 1.4.1 |
| FEAT-002 | ACSE-Prüfung beim Installieren | Implemented | 1.12.2 |
| FEAT-003 | Deinstallation (`UNINSTALL.cmd`) | Implemented | 1.4.1 |
| FEAT-004 | Updater (`UPDATE.cmd`) | Implemented | 1.4.1 |
| FEAT-005 | GitHub-Release-Paket | Implemented | 1.4.1 |
| FEAT-006 | Nexus-Paket ohne Skripte | Implemented | 1.12.3 |
| FEAT-007 | Keine ACSE-Dateien in Paketen | Implemented | 1.12.3 |
| FEAT-008 | Versionsangaben in der DLL | Implemented | 1.12.3 |
| FEAT-009 | Spielbuild-Erkennung | Implemented | 1.4.2 |
| FEAT-010 | Startskript der Python-Alpha (`START.cmd`) | Legacy | vor 1.4.1 |

## Sitzung und Lobby — [features/session-and-lobby.md](../features/session-and-lobby.md)

| ID | Funktion | Status | Seit |
|---|---|---|---|
| FEAT-020 | Sitzung hosten | Implemented | 1.4.1 |
| FEAT-021 | Lobby im Hauptmenü | Implemented | 1.8.0 |
| FEAT-022 | Laufenden Park hosten (Pausemenü) | Implemented | 1.4.1 |
| FEAT-023 | Freunde einladen | Implemented | 1.4.1 |
| FEAT-024 | Freundesliste | Implemented | 1.8.0 |
| FEAT-025 | Beitritt über Steam-Einladung | Implemented | 1.4.1 |
| FEAT-026 | Nur Sitzungen von Steam-Freunden | Implemented | 1.5.0 |
| FEAT-027 | Beitrittsanfragen und Freigabe durch den Host | Implemented | 1.6.1 |
| FEAT-028 | Nachfrage bei Beitritt per Startparameter | Implemented | 1.6.1 |
| FEAT-029 | Versionsprüfung (Mod und Spiel) | Implemented | 1.4.1 |
| FEAT-030 | Park-Übertragung beim Beitritt | Implemented | 1.4.1 |
| FEAT-031 | Beitrittsfortschritt und Beitrittsfehler | Implemented | 1.5.0 |
| FEAT-032 | Park-Auswahl in der Lobby | Replaced | 1.9.0 |
| FEAT-033 | Parkwechsel des Hosts für alle (Stage) | Implemented | 1.8.0 |
| FEAT-034 | Sitzungsleiste im Hauptmenü (vorher Mini-Lobby-Karte) | Implemented | 1.9.0 |
| FEAT-035 | Chat | Implemented | 1.8.0 |
| FEAT-036 | Steam-Profilbilder | Implemented | 1.8.0 |
| FEAT-037 | DLC- und Mod-Vergleich | Implemented | 1.8.0 |
| FEAT-038 | Nur gemeinsame Inhalte (Content Guard) | Implemented | 1.8.0 |
| FEAT-039 | Wiederbeitritt nach Absturz | Implemented | 1.7.0 |
| FEAT-040 | Verbindungsabbruch erkennen | Implemented | 1.6.1 |
| FEAT-041 | Neu synchronisieren | Implemented | 1.5.0 |
| FEAT-042 | Sitzung verlassen oder beenden | Implemented | 1.4.1 |
| FEAT-043 | Spielerfarben | Implemented | 1.4.1 |
| FEAT-044 | Verlauf (Feed) und Toasts | Implemented | 1.4.1 |
| FEAT-045 | Erst-Hinweis im Park | Implemented | 1.12.0 |
| FEAT-046 | Franchise-Parks hosten | Implemented-Untested | 1.8.0 |
| FEAT-047 | Sitzungsgedächtnis über Parkladen (DLL-KV) | Implemented | 1.4.1 |
| FEAT-048 | Gast-Profil beim Mitspieler (kein Verfall, Bauen kostenlos) | Implemented | 1.6.0 |

## Bau-Synchronisation — [features/build-sync.md](../features/build-sync.md)

| ID | Funktion | Status | Seit |
|---|---|---|---|
| FEAT-060 | Szenerie-Sync (platzieren, klonen, verschieben, drehen, skalieren, löschen) | Implemented | 1.4.1 |
| FEAT-061 | Host-Autorität und Reihenfolge | Implemented | 1.4.1 |
| FEAT-062 | Halten und Sperren beim Bearbeiten | Implemented | 1.6.0 |
| FEAT-063 | Konflikte: spätere Änderung wird zurückgenommen | Implemented | 1.6.0 |
| FEAT-064 | Gebündelte Übernahme | Implemented | 1.5.0 |
| FEAT-065 | Replay von Editor-Aufrufen (Gelände, Wege) | Implemented | 1.6.0 |
| FEAT-066 | Stempel und Pools aus Formen | Implemented | 1.12.0 |
| FEAT-067 | Löschen per Mehrfachauswahl | Implemented | 1.9.1 |
| FEAT-068 | Seen und Wasserfälle | Implemented-Untested | 1.12.0 |
| FEAT-069 | Ebene Fahrgeschäfte platzieren und abreißen | Implemented | 1.9.1 |
| FEAT-070 | Ein- und Ausgänge von Fahrgeschäften | Implemented-Untested | 1.10.0 |
| FEAT-071 | Parkverwaltung (Namen, Preise, Öffnen, Kredit, Forschung) | Implemented | 1.12.0 |
| FEAT-072 | Achterbahnen und Schienenbahnen als Bauplan | Implemented | 1.10.0 |
| FEAT-073 | Sperre der Bahn im Streckeneditor | Implemented | 1.10.0 |
| FEAT-074 | Rückgängig nur für eigene Schritte | Implemented | 1.6.0 |
| FEAT-075 | Beim Host unmögliche Änderungen überall entfernen | Implemented | 1.6.0 |
| FEAT-076 | Desync-Erkennung und Wiederholung | Implemented | 1.5.0 |
| FEAT-077 | Hinweis auf nicht synchronisierte Werkzeuge | Implemented | 1.6.0 |
| FEAT-078 | Pause und Spieltempo für alle | Implemented | 1.6.0 |
| FEAT-079 | Zahlen und Meldungen des Host-Parks | Implemented | 1.6.0 |
| FEAT-080 | Schutz, wenn ein gehaltenes Objekt gelöscht wird | Implemented | 1.6.0 |
| FEAT-081 | Fahrgeschäfte verschieben | Implemented-Untested | 1.12.0 |
| FEAT-082 | Ablehnung am Objekt | Implemented | unveröffentlicht |

## Mitspieler sehen — [features/presence.md](../features/presence.md)

| ID | Funktion | Status | Seit |
|---|---|---|---|
| FEAT-090 | Spielerleiste oben rechts | Implemented | 1.9.1 |
| FEAT-091 | Namensschilder über dem Blickpunkt | Implemented | 1.6.0 |
| FEAT-092 | Bodenmarke und Sichtkegel | Implemented | 1.6.0 |
| FEAT-093 | Geist des gehaltenen Objekts | Implemented | 1.6.0 |
| FEAT-094 | Sperr-Färbung | Implemented | 1.6.0 |
| FEAT-095 | Ping mit der mittleren Maustaste | Implemented | 1.7.0 |
| FEAT-096 | Kamera folgen | Implemented | 1.7.0 |
| FEAT-097 | Hinspringen | Implemented | 1.7.0 |
| FEAT-098 | Urheber am Objekt | Implemented | 1.7.0 |
| FEAT-099 | Aktivitätstext | Implemented | 1.6.0 |

## Oberfläche — [features/ui-integration.md](../features/ui-integration.md)

| ID | Funktion | Status | Seit |
|---|---|---|---|
| FEAT-110 | Multiplayer-Fenster (Park: links, vier Reiter; Hauptmenü: nur Rückfall) | Implemented | 1.8.0 |
| FEAT-111 | Reiter „Multiplayer“ in der Bauleiste | Replaced | 1.12.2 |
| FEAT-112 | „Multiplayer“ im Pausemenü | Implemented | 1.4.1 |
| FEAT-113 | Kachel „Multiplayer“ im Hauptmenü | Implemented | 1.8.0 |
| FEAT-114 | F7 öffnet Multiplayer | Implemented | 1.4.1 |
| FEAT-115 | Entwickler-Menü (F8, nur mit Dev-Flag) | Implemented | 1.6.0 |
| FEAT-116 | Chat-Bereich unten links | Implemented | 1.6.0 |
| FEAT-117 | Banner (Abstimmung, Wettbewerb, Einladung) | Implemented | 1.12.0 |
| FEAT-118 | Zustandsbrücke Lua ↔ Oberfläche | Implemented | 1.8.0 |
| FEAT-119 | Multiplayer-Seite im Hauptmenü | Implemented | 1.13.0 |
| FEAT-120 | Knopf „Multiplayer“ links oben | Implemented | unveröffentlicht |

## Team-Funktionen — [features/team.md](../features/team.md)

| ID | Funktion | Status | Seit |
|---|---|---|---|
| FEAT-130 | Brett: Baugebiete | Implemented | 1.12.0 |
| FEAT-131 | Brett: Aufgaben | Implemented | 1.12.0 |
| FEAT-132 | Brett: Kommentare | Implemented | 1.12.0 |
| FEAT-133 | Brett: Treffpunkte | Implemented | 1.12.0 |
| FEAT-134 | Bauvorschläge mit Abstimmung | Implemented | 1.12.0 |
| FEAT-135 | Brett-Marker im Park und Speicherung pro Park | Implemented | 1.12.0 |
| FEAT-136 | Mittelklick-Kontextmenü | Implemented | 1.12.0 |
| FEAT-137 | Übernahme anfragen | Implemented | 1.12.0 |
| FEAT-138 | Testfahrt-Einladung | Implemented | 1.12.0 |
| FEAT-139 | „Seit deinem letzten Besuch“ | Implemented | 1.12.0 |
| FEAT-140 | Park-Meldungen mit Ort | Implemented | 1.12.0 |
| FEAT-141 | Sicherungspunkte mit Abstimmung | Implemented | 1.12.0 |
| FEAT-142 | Sitzungsregeln und Schnellwahl | Implemented | 1.12.0 |
| FEAT-143 | Fremde Bauten nur nach Rückfrage abreißen | Implemented | 1.12.0 |
| FEAT-144 | Rollen- und Abwesenheits-Erklärung | Implemented | 1.12.0 |
| FEAT-145 | Wettbewerb: Bauduell | Implemented | 1.12.0 |
| FEAT-146 | Wettbewerb: Koop gegen die Uhr | Implemented | 1.12.0 |
| FEAT-147 | Wettbewerb: Bewertung und Ergebnis | Implemented | 1.12.0 |

## Besucher-Modus — [features/visitor-mode.md](../features/visitor-mode.md)

| ID | Funktion | Status | Seit |
|---|---|---|---|
| FEAT-160 | Besucher-Modus starten und beenden | Implemented | 1.11.0 |
| FEAT-161 | Animierte Gast-Figur | Implemented | 1.13.0 |
| FEAT-162 | Aussehen aus dem Frontier-Avatar | Implemented | 1.13.0 |
| FEAT-163 | Steuerung von hinten (WASD, Maus, Kollision) | Implemented | 1.12.0 |
| FEAT-164 | Ich-Sicht = Laufmodus des Spiels (V) | Implemented | 1.13.0 |
| FEAT-165 | Eingänge wie im Spiel (E) | Implemented-Untested | 1.13.0 |
| FEAT-166 | Fahrgeschäfte-Liste und Mitfahren | Implemented | 1.11.0 |
| FEAT-167 | Bewertungen und Vorschläge | Implemented | 1.11.0 |
| FEAT-168 | Emotes und Emote-Rad | Implemented | 1.11.0 |
| FEAT-169 | Kaufen an Shops und Automaten | Implemented | 1.13.0 |
| FEAT-170 | Essen und Trinken beim Gehen | Implemented | 1.13.0 |
| FEAT-171 | Figuren der Mitspieler | Implemented | 1.12.0 |
| FEAT-172 | Statue als Figur | Replaced | 1.12.0 |
| FEAT-173 | „Gast begleiten“ (G) | Removed | nie veröffentlicht |
| FEAT-174 | Besucher v1: Laufkamera ohne Figur | Replaced | 1.11.0 |

## DLL — [features/native-dll.md](../features/native-dll.md)

| ID | Funktion | Status | Seit |
|---|---|---|---|
| FEAT-190 | Steam-Lobby und Nachrichten | Implemented | 1.4.1 |
| FEAT-191 | Dateiübertragung | Implemented | 1.4.1 |
| FEAT-192 | Notizdateien im Spielordner | Implemented | 1.7.0 |
| FEAT-193 | Schlüssel-Wert-Speicher | Implemented | 1.4.1 |
| FEAT-194 | Freunde, Einladungen, Profilbilder, Mod-Liste | Implemented | 1.8.0 |
| FEAT-195 | Tasten und Maus im Besucher-Modus | Implemented | 1.12.0 |
| FEAT-196 | Mittelklick, F7, F8, Enter | Implemented | 1.6.0 |
| FEAT-197 | Echtzeit-Uhr | Implemented | 1.12.0 |
| FEAT-198 | Diagnose-Kanal und String-Probe | Implemented | 1.4.1 |
| FEAT-199 | Bahn-Dateien löschen | Implemented | 1.10.0 |

## Entwicklung und Tests — [features/dev-and-qa.md](../features/dev-and-qa.md)

| ID | Funktion | Status | Seit |
|---|---|---|---|
| FEAT-210 | Dev-Flag und QA-Befehle | Implemented | 1.4.1 |
| FEAT-211 | Lua-Skripte in der Testkopie (`qa_lua.py`) | Implemented | 1.6.0 |
| FEAT-212 | Game-Bot | Implemented | 1.4.1 |
| FEAT-213 | Watchdog und Screenshots | Implemented | 1.12.0 |
| FEAT-214 | API-Rekorder | Implemented | 1.6.0 |
| FEAT-215 | API-Introspektion | Implemented | 1.4.1 |
| FEAT-216 | Diagnose-Log | Implemented | 1.4.1 |
| FEAT-217 | LAN-Alpha im Spiel (`live.lua`) | Legacy | vor 1.4.1 |
| FEAT-218 | Python-Forschungswerkzeuge (`pc2coop/*.py`) | Legacy | vor 1.4.1 |
| FEAT-219 | Build-Pipeline | Implemented | 1.4.1 |
| FEAT-220 | Automatische Tests | Implemented | 1.4.1 |
| FEAT-221 | Dokumentations-Prüfung (`check_docs.py`) | Implemented | 1.13.0 |
