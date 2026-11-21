# Oberfläche (Einbindung ins Spiel)

Wie die Mod in die Oberfläche des Spiels kommt. Die vollständige Liste aller Knöpfe,
Fenster und Zustände steht in `docs/ui-ux/UI_INVENTORY.md`.
Code: `probe/PC2CoopProbe/ui/UIGameface/js/pc2coop/CoopLayer.js`,
`probe/PC2CoopProbe/Main/pc2coop/ui.lua`, `probe/PC2CoopProbe/Main/pc2coop/menu.lua`.

### FEAT-110 – Multiplayer-Fenster (Park: links, vier Reiter; Hauptmenü: Lobby)
- **Status:** Implemented · **Seit:** 1.8.0 (Reiter seit 1.12.0, Fenster links seit UX-Overhaul P2)
- **Funktion:** Im Park ein Fenster im Look der Spiel-Fenster am linken Rand, nicht modal (Bauen
  geht weiter), mit vier Symbol-Reitern: Spieler, Planen, Verlauf, Einstellungen. „Besuchen“ ist
  ein Knopf im Fuß. Im Hauptmenü zeigt die Seite FEAT-119 alles. Das alte Fenster in drei
  Spalten (Rückfall, wenn die Seite nicht öffnen konnte) ist seit 1.14.0 entfernt: Erlaubt das
  Menü die Seite gerade nicht (Titelbild, Laden), öffnet sie, sobald es geht (`pendingPage`).
- **Technik:** Klasse `Lobby` in `CoopLayer.js`: `renderParkPanel` (Park, `PARK_TABS`) baut aus den
  CSS-Klassen von `Panel` und `TabBar` des Spiels, dem Spiel-`Tab` und `CloseButton`; die
  Komponente `Panel` selbst ist nicht benutzt, weil sie Fokus und Eingabe-Kontexte übernimmt.
  Im Hauptmenü zeichnet `Lobby` nichts (die Seite, FEAT-119). `ui.lua` `TABS`, UI-Aktionen `open`, `close`, `paneltab`;
  `Ui.SetOpen`, `Ui.Toggle`.
- **Besonderheiten:** Gameface bricht Knopfreihen in schmalen Spalten unzuverlässig um; lange
  Knöpfe stehen deshalb untereinander (`buttons(items, wide)`, Schnellwahl). Breite 23.5 rem wie
  die Info-Fenster des Spiels; Abstand oben 7.6 rem unter dessen runden Knöpfen.

### FEAT-111 – Reiter „Multiplayer“ in der Bauleiste
- **Status:** Replaced (durch FEAT-120, UX-Overhaul P6) · **Seit:** 1.12.0 (beschriftet 1.12.1, außerhalb der TabBar 1.12.2)
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
  In einer Sitzung zusätzlich „Sitzung verlassen“ bzw. „Sitzung beenden“ (Host, mit Nachfrage
  „Für alle beenden?“), TP-30.

### FEAT-113 – Kachel „Multiplayer“ im Hauptmenü
- **Status:** Implemented · **Seit:** 1.8.0
- **Technik:** `patchStartTabClass` (Play-Reiter, neben Karriere, `TileButton`). Öffnet die Seite
  (FEAT-119). Die Beschreibung zeigt den Zustand (TP-01, TP-02): „Sitzung offen · n/8“ oder
  „<Freund> hat eine Sitzung – beitreten“.

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
    Lua Tastendrücke `key:v` (T, E, V, F sind dann Buchstaben); Loslassen kommt durch.
  - `hello` (neue Oberfläche) setzt `SetTyping(false)`.

### FEAT-117 – Banner (Abstimmung, Wettbewerb, Einladung)
- **Status:** Implemented · **Seit:** 1.12.0
- **Technik:** Klassen `RequestCard` (Anfragen: FEAT-027, FEAT-141, FEAT-138, FEAT-147), `ConnectionPill` (FEAT-031), Uhr in `PlayerBar` (FEAT-145).

### FEAT-119 – Multiplayer-Seite im Hauptmenü
- **Status:** Implemented · **Seit:** 1.13.0 (UX-Overhaul P3) · **Ersetzt:** FEAT-032
- **Funktion:** Eine Seite im Rahmen des Hauptmenüs (Brotkrumen „Hauptmenü · Multiplayer“,
  Esc zurück). Ohne Sitzung: „Sitzung starten“ und die Steam-Freunde (wer eine Sitzung hat, oben,
  mit „Beitreten“). In der Sitzung: acht Plätze, ein freier Platz lädt ein (Freundesliste rechts,
  eingeladene Freunde blass im Platz), Chat, und für den Host die Kacheln „Sandbox“ und
  „Franchise“: Sie öffnen die Seiten des Spiels, der Host wählt dort den Park, alle laden mit.
- **Technik:** `CoopLayer.js`: `pageReady` trägt die Klasse `MultiplayerPage` als Seite
  `PAGE_ID` (900) in `FrontEndNavData.screens` ein (Eltern: Hauptmenü); für die Engine heißt sie
  „MainMenu“ (`FrontEndModeChange`). `openPage` navigiert dorthin, sobald das Fenster aufgeht;
  verlässt man die Seite (Esc, Brotkrumen, Spielseite), schickt `FrontEndNav.onChange` `close`.
  `openGamePage` wie die Spiel-Kacheln (`SandboxStartMenu`, Franchise über das Engine-Ereignis
  `FrontEndFranchiseSelected`). Rückfall ohne Seite: das alte Fenster (`lobbyFallback`).
  Beitrittsanfragen warten als Karte im Platz (TP-06). Kommen die Ladeseiten des Spiels
  (`LoadPark`, `SettingUpSpinner`), schickt die Seite `opening`: alle sehen in der Sitzungsleiste
  „<Host> öffnet einen Park – gleich lädt er bei allen.“ (TP-08). Den Namen des Parks kennt die
  Mod dabei nicht.
- **Besonderheiten:** Ein Neuzeichnen aus dem Öffnen heraus rief den Öffnen-Beobachter erneut auf
  und ließ das Spiel abstürzen (Rekursion); deshalb `setTimeout`. Im Spiel geprüft: Seite ohne und
  mit Sitzung, Schließen aus Lua, Sitzungsleiste auf Hauptmenü und Sandbox-Seite. Nicht geprüft:
  ein Park über die Spielseiten mit echtem Mitspieler (zwei PCs).

### FEAT-118 – Zustandsbrücke Lua ↔ Oberfläche
- **Status:** Implemented · **Seit:** 1.8.0
- **Funktion:** Lua veröffentlicht den Zustand als JSON; die Oberfläche schickt Anfragen zurück.
- **Technik:** `ui.lua` schreibt in den DataStore-Kontext `pc2coop` (`state`, `avatars`);
  `CoopLayer.js` `subscribe`/`applyState`; Anfragen über
  `Engine.sendEvent('PC2Coop_Request', '<n>|<befehl>|<arg>')` → `Ui._Request` → Tabelle der
  Aktionen in `ui.lua`. Log-Kanal `PC2Coop_Log` (`js|...`).
- **Besonderheiten:** Der Regex für Anfragen braucht ein abschließendes `|`. Die HUD-Ansicht
  wird erst kurz nach dem Start gehört; frühe Logzeilen gehen verloren (deshalb 4 s Verzögerung).

### FEAT-122 – Chat unten links abschaltbar („Für dich“)
- **Status:** Implemented · **Seit:** 1.14.0 (UX-Overhaul TP-32)
- **Funktion:** Schalter „Chat unten links einblenden“ im Reiter Einstellungen, Abschnitt „Für
  dich“. Aus: neue Nachrichten und Ereignisse erscheinen nicht mehr kurz unten links; Enter
  öffnet den Chat mit dem Verlauf trotzdem. Hinweise (Karten über dem Chat) bleiben.
- **Technik:** UI-Aktion `chatlines`, Zustand `chatLines`; `shared.chatLinesOff` (gilt bis zum
  Spielende, auch über das Laden eines Parks). `ChatArea.onCoop` nimmt dann keine Zeilen auf.

### FEAT-121 – Englisch nach der Sprache des Spiels
- **Status:** Implemented · **Seit:** 1.14.0
- **Funktion:** Läuft das Spiel nicht auf Deutsch, zeigt die Mod alle Texte auf Englisch:
  Fenster, Hauptmenü-Seite, Hinweise, Meldungen, Verlauf, Fehler beim Beitreten, Schilder an
  Objekten. Was Spieler schreiben (Chat, Brett), bleibt, wie es ist. In einer Sitzung sieht
  jeder die Texte in seiner Sprache.
- **Technik:** `Texts.js` (`createTranslator`: `EXACT`, `PATTERNS`, Teile mit „ · “) neben
  `CoopLayer.js`, geladen per `import('./Texts.js')`, wenn `System.getLanguage()` nicht
  `Language.German` ist. `tr()` in `h()` (jedes Text-Kind) und `literal()`; `keep()` für Text von
  Spielern; `buildPrompts()` baut die Hinweiszeile neu. Lua: `lang.lua` (`Lang.Set`, `Lang.Code`,
  `Lang.World` für Schilder in `managers/pc2coopqa.lua`), UI-Aktion `lang`, Zustand `lang`.
  QA: `Ui._QaLook` Feld 6 (1 Englisch, 2 Deutsch). ADR-022.
- **Besonderheiten:** Die Texte bleiben im Code Deutsch; ein neuer Text ohne Eintrag in
  `Texts.js` erscheint auf Deutsch. Muster hängen am genauen Wortlaut.

### FEAT-120 – Knopf „Multiplayer“ links oben
- **Status:** Implemented · **Seit:** 1.14.0 (UX-Overhaul P6)
- **Funktion:** Ein runder Knopf in der Knopfspalte des Spiels links oben (unter den
  Benachrichtigungen) öffnet und schließt das Multiplayer-Fenster; es klappt direkt darunter vom
  linken Rand aus. Ersetzt den Reiter in der Bauleiste (FEAT-111): kurzer Mausweg, die Leiste
  des Spiels bleibt symmetrisch.
- **Technik:** `patchManagementMenu`/`patchManagementClass` (wie beim Pausemenü über
  `Focusable.decorateEx`), `addMenuButton` fügt einen `ManagementMenuButton` des Spiels in
  `ManagementMenu_content` ein; `trackMenuButton` misst seine Unterkante, `panelTop()` setzt das
  Fenster darunter; Ausklappen über `left` mit `transition`. ADR-021.
- **QA:** `Ui._QaClickTab` drückt den Knopf; QA-Look „reiter 0“ blendet ihn aus.
