# Recherche vom 01.11.2026

## Beobachtungen aus öffentlichen Quellen

| Projekt | Stand und tatsächliche Aussage | Lizenz / Nutzung |
| --- | --- | --- |
| [Co-op Anything](https://github.com/cranebeaker/coop-anything) | Ablauf, QA-Werkzeuge und gemeinsame Recherche. Commit `f55babd6b2280ba788f5fd5ddd8c0559f09cbd43`. Kein PC2-Eintrag im untersuchten Verzeichnis. Issue 74 enthält einen älteren Forschungsstand. | MIT; lokal als Referenz geladen. |
| [Conholius / Planet-Coaster-2-Coop](https://github.com/Conholius/Planet-Coaster-2-Coop/tree/5ff13c620552e2f8702fa8055a4f4392d39a0782) | Letzter dokumentierter Stand 30.10.2026: Autor berichtet zwei lokale Spielinstanzen mit Scenery-/Grid-Bauaktionen und privater Lobby. Zwei-PC-Internetbetrieb ausdrücklich noch geplant. Öffentliches Git-Tree enthält Dokumentation, aber keinen Prototyp-Quellcode und kein installierbares Paket. Diese Berichte wurden hier nicht unabhängig reproduziert. | MIT für das öffentliche Repository. Private Implementierung ist nicht verfügbar. |
| [Serponic / PC2MP](https://github.com/Serponic/PC2MP/tree/a8df05ccc23575ddd1bb8357394116928accce39) | Letzter Commit 30.05.2026. README nennt Alpha 0.1.4 im Changelog, Alpha 0.1.3 im Titel. Ein öffentlicher Branch, keine GitHub-Releases gefunden. Der Empfangspfad für Bauaktionen schreibt einen Toast; der eigentliche Engine-Spawn ist auskommentiert (`dllmain.cpp`, Zeilen 1366–1395). Kein Nachweis vollständiger Bau-Synchronisation. | GPL-3.0; nur gelesen, kein Code in das eigene Projekt übernommen oder ausgeführt. |
| [ACSE](https://github.com/OpenNaja/ACSE/tree/8a843e61bcb57779778536e635d334d882cee7b1) | Cobra-Scripting-Erweiterung; öffentlicher Lua-Datenbank-Lebenszyklus als Einstieg. Die [PC2-Verteilung](https://www.nexusmods.com/planetcoaster2/mods/1) nennt 0.723 und eine ältere geprüfte Spielversion. Conholius berichtet 0.729 mit PC2 1.11.4.1011357; das beweist keine Kompatibilität mit unserem noch unbekannten Build. | GPL-3.0 plus Hinweise im Upstream-README; nicht gebündelt. |
| [ForgeUtils](https://github.com/Distantz/ForgeUtils) | Kandidat für Lua-Hooks/Logging. Ein Catalogue-Builder registriert Ressourcen und platziert nicht automatisch eine persistente Instanz. Noch keine eigene Laufzeitprüfung. | Vor Integration die Lizenz der gewählten Revision prüfen; nicht gebündelt. |
| [ACSE Mod Template](https://github.com/Distantz/ACSE-Mod-Template/tree/39ead68af2ea057cb4025151e114703f7af24f42) | Referenz für Manifest, Datenbank-Entry-Point und OVL-Paketierung. | API meldet keine Lizenz; keine Build-Skripte übernommen. Eigene Probe verwendet nur die notwendigen öffentlichen Schnittstellennamen. |

Die untersuchten öffentlichen Dateien sind über Commit und SHA-256 in
`sources.lock.json` dokumentiert. Die Liste ist kein Lock für installierbare
Abhängigkeiten; sie dokumentiert ausschließlich den gelesenen Quellenstand.

## Ableitungen für unseren Prototyp

- Einstieg über ACSE/Lua statt ungeprüfter nativer Speicheradressen.
- Erste unterstützte Operation: ein bestehendes, einfaches Deko-Objekt über den
  normalen Editorpfad platzieren. Die Quelle muss bestätigte Commits beobachten;
  ein Preview oder ein früher Placement-Event reicht nicht.
- Native Entity-/Part-IDs bleiben lokal. Das Modell verwendet eigene Objekt-IDs.
- Der Host entscheidet die Reihenfolge und prüft die erwartete Objektrevision.
  Gleiche Action-ID plus gleicher Inhalt liefert dasselbe Ergebnis. Löschen
  hinterlässt eine Markierung; alte Nachrichten erzeugen das Objekt nicht erneut.
- Im Spiel darf eine Modellannahme erst dann als akzeptierte Bauaktion gelten,
  wenn der Editor-Commit abgeschlossen und das Objekt zurückgelesen wurde.
- Zunächst getrennte Modelltests, dann ein Spielclient mit Save-/Reload-Prüfung,
  danach zwei tatsächliche Spielclients. Kein Determinismus der PC2-Simulation
  wird vorausgesetzt.

## Unbekannt / noch nicht geprüft

- Finale installierte Spielversion, EXE-Hash und exakte Lua-/OVL-Formate.
- Verträgliche ACSE-/ForgeUtils-Pakete und eine zuverlässige Logausgabe.
- Konkrete Signaturen der Editoroperationen im installierten Build.
- Rückgabewerte, Yield-Verhalten, Commit-Tokens und dauerhafte Platzierung.
- Getrennte Profile/Speicherorte, zwei gleichzeitige Spielinstanzen und Transport.
- Einbindung des Mod-Objektverzeichnisses in Spielstände und Absturzabgleich.

## searched

- Co-op-Anything: `data/`, `games/`, offene Issues und PR-Suche „Planet Coaster“.
- GitHub REST: Repositorysuchen `"planet coaster 2" multiplayer` und
  `planet coaster coop`; PC2MP-Branches und -Releases; aktueller Conholius-Git-Tree.
- Web: „Planet Coaster 2 co-op mod“, „Planet Coaster 2 Multiplayer Mod“ sowie
  Cobra-/ACSE-Suchen; öffentliche Nexus-Projektbeschreibung.
- Discord, nichtöffentliche Kanäle und Benutzerkonten wurden nicht abgefragt.
  ModDB/Archive.org und sämtliche Forks sind nicht vollständig untersucht.

Diese Suche belegt zwei gefundene Vorarbeiten; sie ist keine Behauptung, dass
alle existierenden Mods gefunden wurden.
