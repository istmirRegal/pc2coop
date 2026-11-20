# Oberfläche (Einbindung ins Spiel)

Wie die Mod in die Oberfläche des Spiels kommt. Die vollständige Liste aller Knöpfe,
Fenster und Zustände steht in `docs/ui-ux/UI_INVENTORY.md`.
Code: `probe/PC2CoopProbe/ui/UIGameface/js/pc2coop/CoopLayer.js`,
`probe/PC2CoopProbe/Main/pc2coop/ui.lua`, `probe/PC2CoopProbe/Main/pc2coop/menu.lua`.

### FEAT-110 – Multiplayer-Fenster
- **Status:** Implemented · **Seit:** 1.8.0 (fünf Reiter seit 1.12.0)
- **Funktion:** Im Hauptmenü die Lobby (drei Spalten); im Park mit Sitzung fünf Reiter:
  Team, Besuchen, Planen, Verlauf, Sitzung.
- **Technik:** Klasse `Lobby` in `CoopLayer.js` (`PANEL_TABS`); `ui.lua` `TABS`,
  UI-Aktionen `open`, `close`, `paneltab`; `Ui.SetOpen`, `Ui.Toggle`.
- **Besonderheiten:** Feste Größen (Gameface schrumpft Flexboxen nicht).

### FEAT-111 – Reiter „Multiplayer“ in der Bauleiste
- **Status:** Implemented · **Seit:** 1.12.0 (beschriftet 1.12.1, außerhalb der TabBar 1.12.2)
- **Funktion:** Unten rechts in der Bauleiste ein Reiter „Multiplayer“, öffnet das Fenster.
- **Technik:** `patchBrowserClass` in `CoopLayer.js`: eigener `div` mit einem
  `BrowserTab` (onToggle → `open`), absolut positioniert rechts, **außerhalb** der TabBar
  des Spiels (ADR-007). `report()` schreibt verzögert ins Log („build bar tab shown“).
- **Besonderheiten:** In der TabBar gehört Reiter i zu Abschnitt i – ein zusätzlicher Reiter
  darin sperrte die Oberfläche (Fehler in 1.12.1, behoben 1.12.2). QA: `Ui._QaClickTab`.

### FEAT-112 – „Multiplayer“ im Pausemenü
- **Status:** Implemented · **Seit:** 1.4.1
- **Technik:** `patchMenuClass` fügt über `getGameMenuBtn` einen Eintrag über „Beenden“ ein.

### FEAT-113 – Kachel „Multiplayer“ im Hauptmenü
- **Status:** Implemented · **Seit:** 1.8.0
- **Technik:** `patchStartTabClass` (Play-Reiter, neben Karriere, `TileButton`).

### FEAT-114 – F7 öffnet Multiplayer
- **Status:** Implemented · **Seit:** 1.4.1
- **Technik:** DLL `key:menu` → `Session.OnMenuKey` (gesetzt vom Manager) → Fenster/Menü.

### FEAT-115 – Entwickler-Menü (F8)
- **Status:** Implemented · **Seit:** 1.6.0
- **Funktion:** Sync-Zustand, API-Rekorder an/aus, Namensschilder an/aus, Sync pausieren.
- **Technik:** `menu.lua` (`Menu.Init`, `Menu.Toggle`, Dialog-Stack des Spiels,
  `STRING_LITERAL`-Texte); DLL `key:dev` → `Session.OnDevKey`. Hauptseite: Raum hosten,
  Freunde einladen, Sitzung verlassen/beenden, „Zu <Name>“, Entwickler, Schließen.

### FEAT-116 – Toasts unten links
- **Status:** Implemented · **Seit:** 1.6.0 · **Hängt ab von:** FEAT-044
- **Technik:** Klasse `Toasts`; Farbe = Spielerfarbe oder Warnfarbe `ff922b`.

### FEAT-117 – Banner (Abstimmung, Wettbewerb, Einladung)
- **Status:** Implemented · **Seit:** 1.12.0
- **Technik:** Klassen `RequestCard` (Anfragen: FEAT-027, FEAT-141, FEAT-138, FEAT-147), `ConnectionPill` (FEAT-031), Uhr in `PlayerBar` (FEAT-145).

### FEAT-118 – Zustandsbrücke Lua ↔ Oberfläche
- **Status:** Implemented · **Seit:** 1.8.0
- **Funktion:** Lua veröffentlicht den Zustand als JSON; die Oberfläche schickt Anfragen zurück.
- **Technik:** `ui.lua` schreibt in den DataStore-Kontext `pc2coop` (`state`, `avatars`);
  `CoopLayer.js` `subscribe`/`applyState`; Anfragen über
  `Engine.sendEvent('PC2Coop_Request', '<n>|<befehl>|<arg>')` → `Ui._Request` → Tabelle der
  Aktionen in `ui.lua`. Log-Kanal `PC2Coop_Log` (`js|...`).
- **Besonderheiten:** Der Regex für Anfragen braucht ein abschließendes `|`. Die HUD-Ansicht
  wird erst kurz nach dem Start gehört; frühe Logzeilen gehen verloren (deshalb 4 s Verzögerung).
