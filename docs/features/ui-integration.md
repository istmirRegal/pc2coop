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
  darin sperrte die Oberfläche (Fehler in 1.12.1, behoben 1.12.2). QA: `Ui._QaClickTab`;
  `Ui._QaLook` stellt für Bilder Akzentfarbe, Farbenblind-Modus und UI-Skalierung der HUD-Ansicht
  um (nur Dev-Skripte, nichts gespeichert, `docs/development/TESTING.md`).

### FEAT-112 – „Multiplayer“ im Pausemenü
- **Status:** Implemented · **Seit:** 1.4.1
- **Technik:** `patchMenuClass` fügt über `getGameMenuBtn` einen Eintrag über „Beenden“ ein.

### FEAT-113 – Kachel „Multiplayer“ im Hauptmenü
- **Status:** Implemented · **Seit:** 1.8.0
- **Technik:** `patchStartTabClass` (Play-Reiter, neben Karriere, `TileButton`).

### FEAT-114 – F7 öffnet Multiplayer
- **Status:** Implemented · **Seit:** 1.4.1
- **Technik:** DLL `key:menu` → `Session.OnMenuKey` (gesetzt vom Manager) → Fenster/Menü.

### FEAT-115 – Entwickler-Menü (F8, nur mit Dev-Flag)
- **Status:** Implemented · **Seit:** 1.6.0 · **Nur für Entwickler seit:** UX-Overhaul P0 (TP-31)
- **Funktion:** Sync-Zustand, API-Rekorder an/aus, Namensschilder an/aus, Sync pausieren.
  Spieler sehen das Menü nicht: Hosten, Einladen und Verlassen stehen im Multiplayer-Fenster,
  der Schalter für die Anzeige der Mitspieler im Abschnitt „Für dich“ (FEAT-091).
- **Technik:** `menu.lua` (`Menu.Init`, `Menu.Toggle`, Dialog-Stack des Spiels,
  `STRING_LITERAL`-Texte); DLL `key:dev` → `Session.OnDevKey`. Die DLL meldet F8 nur, wenn
  `pc2coop-dev.flag` neben der DLL liegt (`pc2_developer_mode`, wie der QA-Kanal). Hauptseite:
  Raum hosten, Freunde einladen, Sitzung verlassen/beenden, „Zu <Name>“, Entwickler, Schließen.

### FEAT-116 – Chat-Bereich unten links
- **Status:** Implemented · **Seit:** 1.6.0 (als Toasts) · **Hängt ab von:** FEAT-044, FEAT-035
- **Funktion:** Chat und Spieler-Ereignisse unten links, blenden nach 10 s aus. **Enter** öffnet
  die Eingabe wie ein Spiel-Chat: Enter sendet, Esc oder ein Klick daneben schließt (Entwurf
  bleibt). Meldungen (Warnungen, Antworten) stehen als Karten darüber (6 s, höchstens 3).
- **Technik:** Klasse `ChatArea` (bis 1.13.0 `Toasts`). Lua markiert jeden Toast mit `kind`:
  `chat` (`Session._AddChat`), `event` (`addFeed`, Emotes, Markierungen, Bewertungen), sonst
  `notice`. DLL `key:chat` → `Session.OnChatKey` → `Ui.ChatKey` → Zähler `chatKey` im Zustand.
  Die Eingabe ist das `InputField` des Spiels (`alt`, `commitOnCancel: false`).
- **Besonderheiten:**
  - Enter öffnet nur im Park bei geschlossenem Fenster.
  - Kein Öffnen innerhalb von 0,8 s nach dem Senden oder nach Enter in einem Textfeld des Spiels
    (`document.activeElement` wird alle 0,2 s geprüft).
  - UI-Aktion `chatinput` 1/0 → `Session.SetTyping`: Solange die Eingabe offen ist, verwirft
    Lua Tastendrücke `key:v` (T, E, V, 1–6 sind dann Buchstaben); Loslassen kommt durch.
  - `hello` (neue Oberfläche) setzt `SetTyping(false)`.

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
