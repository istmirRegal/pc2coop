# Projektüberblick

## Was

PC2Coop macht Planet Coaster 2 zu einem Live-Mehrspieler-Spiel: Steam-Freunde bauen
gleichzeitig im selben Park, sehen einander, planen zusammen und besuchen den Park als
Gäste. Ohne Server, ohne Ports – nur Steam und die Mod.

## Für wen

Freundesgruppen, die zusammen Parks bauen. Ziel aus den ursprünglichen Anforderungen
(`docs/COOP_DESIGN.md`): mindestens **drei** Spieler gleichzeitig, mit eigener Kamera,
ohne technische Einrichtung zwischen den Spielabenden. Bis zu 8 Plätze pro Lobby.

## Was es kann (Stand 1.13.0)

- **Sitzung:** Lobby im Hauptmenü oder im laufenden Park, Freunde einladen, Freigabe durch
  den Host, Park-Übertragung, Parkwahl in der Lobby, Wiederbeitritt (FEAT-020–048).
- **Bauen:** Szenerie, Gelände, Wege, Seen, Stempel, Fahrgeschäfte, Achterbahnen;
  Sperren beim Bearbeiten, Konfliktlösung durch den Host (FEAT-060–081).
- **Mitspieler sehen:** Spielerleiste, Namensschilder, Sichtkegel, Geister, Ping, Folgen (FEAT-090–099).
- **Team:** Brett (Gebiete, Aufgaben, Vorschläge, Kommentare, Treffpunkte), Kontextmenü,
  Testfahrt-Einladung, Sicherungspunkte, Regeln, Wettbewerbe (FEAT-130–147).
- **Besuchen:** animierte Figur im Avatar-Look, Ich-Sicht des Spiels, Eingänge, mitfahren,
  bewerten, Emotes, kaufen (FEAT-160–171).

Vollständig: `docs/project/FEATURES.md`.

## Wie

Alles im Spielprozess (ADR-001): Lua-Module über ACSE greifen auf die Spiel-APIs zu, eine
Preact-Ebene im Gameface-UI zeigt Fenster und Leisten, eine DLL spricht Steam. Der Host hat
den Park und entscheidet über die Reihenfolge (ADR-003). Details: `docs/architecture/`.

## Grenzen

- Gäste-Simulation (einzelne Gäste, Bedürfnisse, Warteschlangen) läuft im C++-Teil des
  Spiels ohne Skript-Schnittstelle: Gäste werden pro Spieler simuliert, nur Zahlen und
  Meldungen kommen vom Host.
- Manche Werkzeuge werden nicht übertragen (Hinweis an den Spieler, FEAT-077).
- Karriere und Herausforderungen: noch nicht (ROADMAP).
- Texte nur Deutsch.
- Nach 1.5.0 nicht mehr mit zwei echten PCs getestet (siehe FEATURES.md, Kopf).

## Verteilung

GitHub-Release mit Installer/Updater (`alpha-dist/`), Nexus-Paket zum Kopieren.
ACSE muss der Spieler selbst installieren (ADR-009). Lizenz MIT, keine Spieldateien.

## Beteiligte

Der Eigner leitet das Projekt und testet mit Freunden; KI-Assistenten entwickeln nach
`CLAUDE.md` und `docs/development/AI_WORKFLOW.md`.
