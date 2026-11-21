# Mitspieler sehen

Was ein Spieler von den anderen sieht. Code: `probe/PC2CoopProbe/Main/pc2coop/viz.lua`
(Objekte im Park), `probe/PC2CoopProbe/Main/pc2coop/labels.lua` (Namensschilder),
`probe/PC2CoopProbe/Main/managers/pc2coopqa.lua` (füttert beide jedes Frame),
`probe/PC2CoopProbe/Main/pc2coop/world.lua` (Kamera, Blickpunkt, Aktivität).

### FEAT-090 – Spielerleiste oben rechts
- **Status:** Implemented · **Seit:** 1.9.1
- **Funktion:** Runde Chips aller Spieler mit Avatar, Name, Krone und Zustands-Icon; die
  Tätigkeit steht im Tooltip („Vici – hält Rock 04 · Klicken zum Folgen“, TP-13). Klick folgt
  der Kamera (FEAT-096).
- **Technik:** `CoopLayer.js` Klasse `PlayerBar`, `stateIcon`, `HoverTip` (Spiel-`TooltipContainer`),
  `playerActivity`, `activityText`.
- **UI:** Immer sichtbar in einem Park mit Sitzung. Icons des Spiels: `building` baut, `camera`
  schaut zu, `move` hält etwas, `downloadArrow` empfängt den Park, `clock` lädt oder im
  Hauptmenü, `eye` Folgen-Ziel (dazu gelb umrandet). Hat nach dem Laden niemand mehr eine
  Lade-Tätigkeit, steht einmal 5 s „Alle sind da“ darunter (TP-08, `allHere`, einmal je Park).

### FEAT-091 – Namensschilder über dem Blickpunkt
- **Status:** Implemented · **Seit:** 1.6.0
- **Funktion:** Der Name in der Spielerfarbe schwebt über der Stelle, auf die ein Mitspieler
  schaut (oder über seinem gehaltenen Objekt). Die Tätigkeit steht im Tooltip der
  Spielerleiste (TP-14); das Schild in der Welt hat keine Maus-Eingabe. Andere Schilder behalten
  ihr Wort: Ping „<Name> – hier!“ (Spielerfarbe), Brett, Park-Meldungen, Urheber (FEAT-098).
- **Technik:** `Labels.Init`, `Labels.Show`, `Labels._Text`, `Labels.Pin`, `Labels.Clear` über das
  Billboard-Widget des Spiels (UIBillboardWidgetsManager, „coaster labels“). Text
  „•#rrggbb Name“; `DebugToolImports.js` nimmt Punkt und Farbe ab und färbt den Text.
- **Besonderheiten:** Abschaltbar im Multiplayer-Fenster, Reiter „Einstellungen“, Abschnitt „Für dich“:
  „Mitspieler in der Welt zeigen“ (UI-Aktion `labels`, `Menu.labelsEnabled`, nur auf diesem PC,
  nicht gespeichert). Aus blendet Schilder, Bodenmarke, Sichtkegel, Geist und Sperr-Färbung aus;
  die Meldung am Objekt (FEAT-082) bleibt. Vorher nur im Entwickler-Menü (F8).

### FEAT-092 – Bodenmarke und Sichtkegel
- **Status:** Implemented · **Seit:** 1.6.0
- **Funktion:** Farbige Scheibe am Blickpunkt, gepunkteter Keil von der Kamera dorthin.
- **Technik:** `Viz.Update` (Scheiben-Prefab `pc_primitive_circle_game`, `DOTS`, Bodenhöhe per
  Geländestrahl), Hervorhebungskanal 3 in der Farbe des Spielers (`setColour`).
- **Besonderheiten:** Reine Anzeige-Objekte, nie Teil des Parks (nicht gespeichert; geprüft).
  Bei Besuchern ausgeblendet (die Figur ist dann die Marke).

### FEAT-093 – Geist des gehaltenen Objekts
- **Status:** Implemented · **Seit:** 1.6.0
- **Funktion:** Was ein Mitspieler in der Hand hat, erscheint eingefärbt an seiner Stelle;
  Fahrgeschäfte, Shops, Baupläne als große Scheibe mit Namen.
- **Technik:** `viz.lua` `safePrefab` (nur Szenerie mit `<name>` und `<name>_game`;
  Fahrgeschäfte/Engine-Prefabs nie, Liste `UNSAFE`), höchstens `MAX_GHOSTS` = 8.
- **Besonderheiten:** Ein Fahrgeschäft-Prefab zu instanziieren beendet das Spiel – daher die
  Sperrliste. QA: `ghost-sweep`.

### FEAT-094 – Sperr-Färbung
- **Status:** Implemented · **Seit:** 1.6.0 · **Hängt ab von:** FEAT-062
- **Technik:** `pc2coopqa.lua` sammelt gesperrte Entities aus `hold.gids` → `Viz.Update(..., locked, ...)`.

### FEAT-095 – Ping mit der mittleren Maustaste
- **Status:** Implemented · **Seit:** 1.7.0 (Mittelklick seit 1.9.0)
- **Funktion:** Kurzer Mittelklick setzt eine Markierung „hier!“ für alle (~8 s) und öffnet
  das Kontextmenü (FEAT-136). Gedrückt halten/ziehen dreht wie gewohnt die Kamera.
- **Technik:** DLL `key:mdown`/`key:mup|<ms>|<weg²>` → `Session._MiddleUp` → `Session.Ping`
  (`World.CursorPoint`); Nachricht `ping` → Host `pg` an alle; `PING_FRAMES` = 480;
  höchstens 1 Ping/s; `Session.Pings`. UI-Aktion `ping`.
- **Aussehen (seit 1.14.0, P6 A9):** Eine Markierung verdeckt nichts mehr. Auf einem Objekt
  blinkt dessen Umriss in der Spielerfarbe (Highlight-Kanal 3 des Spiels, wie gesperrte
  Objekte); `Sync.PartOnRay` sucht das geteilte Teil am Maus-Strahl (`World.CursorRay`, 2 m +
  3 % des Abstands), die Nachrichten tragen seine Id (`ping|x|y|z|gid`, `pg|…|gid`; keine
  F/S-Ids, `Session._PingGid`). Sonst ein Ring aus zehn kleinen Punkten flach am Boden, Mitte
  frei, nach Abstand skaliert; Baugebiete ein ruhender Punktring in ihrer Größe (12–40
  Punkte, Boden je Punkt). Vorher: gefüllte Scheibe mit drei Scheiben darüber, Baugebiet als
  große Scheibe. Test: `tests/test_viz_lua.py`.
- **Besonderheiten:** Der Zweig `key:ping` in `session.lua` stammt von einer früheren Taste;
  die DLL sendet ihn nicht mehr (siehe DEVLOG, Aufräumkandidat).

### FEAT-096 – Kamera folgen
- **Status:** Implemented · **Seit:** 1.7.0
- **Funktion:** Mitspieler anklicken: die eigene Kamera fliegt hin und zeigt, was er sieht;
  erneut klicken oder Kamera selbst bewegen beendet das.
- **Technik:** `Session.SetFollow`, `Session.Following`; `World.SetCamera`,
  `World.PlayerMovesCamera`; Folgen läuft in `pc2coopqa.lua`. UI-Aktion `follow`.

### FEAT-097 – Hinspringen
- **Status:** Implemented · **Seit:** 1.7.0
- **Funktion:** Zur Stelle eines Spielers, Pings, Brett-Eintrags oder einer Park-Meldung fliegen.
- **Technik:** UI-Aktionen `jump` (Spieler/Ping), `goto` (Ort); `World.SetCamera`.
  F7-Menü „Zu <Name>“.

### FEAT-098 – Urheber am Objekt
- **Status:** Implemented · **Seit:** 1.7.0
- **Funktion:** Am ausgewählten oder gehaltenen Objekt steht, wer es erstellt und wer es
  zuletzt bearbeitet hat. Der Host merkt sich das pro Park über Speichern und Laden.
- **Technik:** Gast fragt `who|gid` → Host antwortet `who|gid|creator|last` (`authorOf`);
  `Session.Attribution`; Datei `pc2coop-authors-<Park>.txt` (Notiz, `flushAuthors`,
  `savedAuthors`); `World.SelectedPart`, `Sync.HeldParts`, `Sync.GidOfPart`.
- **UI:** Namensschild „Erstellt von …, zuletzt …“ (`pc2coopqa.lua`, `authorTag`).

### FEAT-099 – Aktivitätstext
- **Status:** Implemented · **Seit:** 1.6.0
- **Funktion:** „baut Wege“, „platziert ein Fahrgeschäft“, „geht als Besucher …“, „isst“ …
- **Technik:** `World.Activity` (Editor-Modus), `Visitor.Activity`, Emotes
  (`Session.Emotes`); im `pres` als Feld `act`.
