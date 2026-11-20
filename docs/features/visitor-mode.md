# Besucher-Modus

Als Parkbesucher durch den Park gehen – ein **Multiplayer**-Modus: die anderen sehen dich
als Figur. Die eigenen Modi des Spiels (Laufmodus, Gast-Kamera) bleiben unverändert; wir
benutzen ihre Funktionen technisch (ADR-014).
Code: `probe/PC2CoopProbe/Main/pc2coop/visitor.lua`, `probe/PC2CoopProbe/Main/pc2coop/figure.lua`,
`probe/PC2CoopProbe/Main/pc2coop/shop.lua`, `probe/PC2CoopProbe/Main/pc2coop/viz.lua`
(Figuren der anderen), Tasten aus `native/steam_net.cpp`.

### FEAT-160 – Besucher-Modus starten und beenden
- **Status:** Implemented · **Seit:** 1.11.0 · **Hängt ab von:** FEAT-142
- **Funktion:** „Als Besucher losgehen“ (Reiter Besuchen), Tab oder „Zurück zum Bauen“ beendet.
  Der Host kann den Modus per Regel abschalten.
- **Technik:** `Visitor.Start(view)`, `Visitor.Stop`, `Visitor.Active`, `Visitor.Tick`
  (vom Manager jedes Frame); UI-Aktion `visitor`. Beginnt dort, wo man hinschaut
  (`World.FocusPoint`). Die DLL bekommt alle 60 Frames `visitor|1|<maus>` (Tasten an,
  Mauszeiger fangen) – ohne Erneuerung schaltet sie nach 2 s ab.
- **UI:** Besucherleiste oben Mitte (`VisitorBar`) mit Steuerungshinweis.
- **Besonderheiten:** Verlässt das Spiel die Besucherkamera durch eigene Tasten, endet der
  Modus (Prüfung in `Visitor.Tick`).

### FEAT-161 – Animierte Gast-Figur
- **Status:** Implemented · **Seit:** 1.13.0 · **Ersetzt:** FEAT-172
- **Funktion:** Die Figur ist ein Parkgast mit Lauf-, Renn-, Steh- und Emote-Animationen.
- **Technik:** `figure.lua`: das Gast-Prefab `peep` wird per `api.entity.FindPrefab` gelesen,
  Gast-Logik (GuestVisual, BakedMotionApplication, BakedAnimTree …) entfernt, Modelle,
  Farben und eine Animation fest eingesetzt und mit `api.entity.CompilePrefab` (ACSE) als
  eigenes Prefab gebaut – eines pro Aussehen und Animation (`Figure.PrefabName`). Eine Figur
  (`Figure.New`, `Instance:Place`, `Instance:Warm`, `Instance:Destroy`) hält ein Objekt pro
  gezeigter Animation, versteckt die anderen bei y = −500. Animationen `Figure.ANIMS`
  (`<gruppe>$<name>`, z. B. `am$walkbase`), Gangart `Figure.Gait` (≤ 0,5 m/s stehen,
  ≤ 4,6 m/s gehen, sonst rennen). `Figure.Available` prüft CompilePrefab und `peep`.
- **Besonderheiten:** Nur Grundspiel-Modelle (Content0). Das Startbildschirm-Avatar-Prefab
  stürzt in einem Park ab (ADR-012). Ohne CompilePrefab: Statue (FEAT-172).

### FEAT-162 – Aussehen aus dem Frontier-Avatar
- **Status:** Implemented · **Seit:** 1.13.0
- **Funktion:** Alter/Geschlecht und Farben von Oberteil, Hose, Haaren aus dem eigenen Avatar;
  Kopf, Frisur, Kleidung aus den Grundspiel-Modellen gewählt (immer gleich je Spieler).
- **Technik:** `Figure.OwnLook` liest `Database.GameDatabase.tPlayers[..]:GetData("AvatarData",
  "Main")`, `Figure.FromAvatar` (Teil-Nummer modulo Modellliste), Text über `Figure.LookText`/
  `Figure.ParseLook` (streng geprüft). Verteilung: Gast → Host `look|<text>` (erst nach
  Beitrittszustimmung), Host trägt es in den Roster ein (15. Feld); `Visitor.SetLook`.
- **Besonderheiten:** Die Teil-Nummern des Avatars sind keine Modellnamen; eine
  Zuordnungstabelle wurde nicht gefunden.

### FEAT-163 – Steuerung von hinten (WASD, Maus, Kollision)
- **Status:** Implemented · **Seit:** 1.12.0
- **Funktion:** WASD relativ zur Kamera, Shift rennt (3,2 / 7,5 m/s), Maus dreht (Zeiger
  verschwindet), keine Wände/Deko/Bahnen durchlaufen, Stufen bis 0,6 m.
- **Technik:** `advanceFigure` (lokal), Kamera „Avatar“ des Spiels mit eigener Change-Source
  (`avatarCamera`); Kollision `blocked` (Physikstrahl in Hüfthöhe), Boden `groundAt`
  (Gelände, Volumen, Plattformen); Maus über DLL `mouse|dx|dy` → `Visitor.OnMouse`.
  QA-Naht `Visitor._TestKeys`.
- **UI:** Hinweis „Maus umsehen · WASD laufen · Shift rennen · E … · T … · V … · Tab zurück“.

### FEAT-164 – Ich-Sicht = Laufmodus des Spiels (V)
- **Status:** Implemented · **Seit:** 1.13.0 · **Ersetzt:** FEAT-174
- **Funktion:** V wechselt zwischen Figur und dem eingebauten Laufmodus (Springen Alt,
  Ducken Strg, Schwimmen, Lampe L, Einsteigen mit der Taste des Spiels). Die anderen sehen
  dich in beiden Ansichten als Figur.
- **Technik:** `Visitor.ToggleView`, `Visitor.WatchGuest` (UI-Modus `VisitorCamera` mit
  `startingTransform`), `Visitor.GuestView`; zurück: Figur an der Stelle des Läufers,
  Kamera-Anforderung erst nach dem Moduswechsel (`toFigure`, sonst setzt das Spiel die
  Kamera zurück – Fehler gefunden und behoben vor 1.13.0). Fährt man aus dem Laufmodus mit,
  bringt das Spiel einen danach zurück in den Laufmodus. UI-Aktion `view`, Taste `v`.

### FEAT-165 – Eingänge wie im Spiel (E)
- **Status:** Implemented-Untested · **Seit:** 1.13.0
- **Funktion:** E benutzt, was vor der Figur ist: Bahn-Eingang (einsteigen), Rutschen-Treppen,
  Shows; oben steht die Meldung des Spiels („Einsteigen: …“ oder warum nicht). Nach der Fahrt
  geht es am Ausgang weiter. Shops: FEAT-169.
- **Technik:** `Visitor.Interact`, `Visitor.Hint`; `Helpers.VisitorCameraTargetUtils`
  (`FindInteractionTarget` von den Augen der Figur in Blickrichtung, `TestInteraction`,
  `TriggerInteraction`, `GetInteractionString`, `GetBlockerString`); Texte als
  Spiel-Schlüssel, im JS mit `translate` übersetzt.
- **Besonderheiten:** Im Spiel nur über Unit-Tests geprüft (kein Bahn-Eingang in der Testkopie
  angesteuert).

### FEAT-166 – Fahrgeschäfte-Liste und Mitfahren
- **Status:** Implemented · **Seit:** 1.11.0
- **Funktion:** Liste der Bahnen (nächste zuerst) mit Begeisterung/Angst/Übelkeit, Warteschlange,
  Bewertungen; „Mitfahren“ ohne hinzulaufen.
- **Technik:** `Visitor.Rides(keyOf, cache, at)`, `Visitor.Ride(key, findRide)`
  (Kamera-Einstellungen des Spiels, `GamefaceCameraSettings`), `Visitor.Riding`.
  UI-Aktionen `visitorlist`, `ride`.

### FEAT-167 – Bewertungen und Vorschläge
- **Status:** Implemented · **Seit:** 1.11.0
- **Funktion:** 1–5 Sterne und ein kurzer Vorschlag je Fahrgeschäft; der Host speichert sie pro Park.
- **Technik:** `Session.Rate`, `Session.Ratings`, Nachricht `rate`, Datei
  `pc2coop-ratings-<Park>.txt` (`Session._RatingsFile`). UI-Aktion `rate`.

### FEAT-168 – Emotes und Emote-Rad
- **Status:** Implemented · **Seit:** 1.11.0 (als Animation seit 1.13.0)
- **Funktion:** T halten: Rad (Winken, Jubeln, Lachen, Super, Naja, Übel), Maus oder 1–6,
  T loslassen sendet; alle sehen die Animation und einen Toast.
- **Technik:** `Visitor.EMOTES`, `Visitor.OnKey`, `Visitor.Wheel`; `Session.Emote` →
  `emote|kind` → Host `em|sid|kind`; `Session._EmoteKind`, `Session.Emotes` (4 s, Essen 20 s).
  UI-Aktion `emote`, Klasse `EmoteWheel`, Knöpfe `EMOTE_BUTTONS`.

### FEAT-169 – Kaufen an Shops und Automaten
- **Status:** Implemented · **Seit:** 1.13.0
- **Funktion:** E vor einem Shop zeigt seine Artikel mit übersetzten Namen und Preisen;
  1–6 oder Klick kauft, E/Tab schließt. Der Preis geht in die Parkkasse, alle sehen
  „<Name> kauft …“. Geschlossene Shops verkaufen nichts.
- **Technik:** `shop.lua`: `Shop.InFront` (Strahlenfächer, Elternkette bis `IsFacility`),
  `Shop.Items` (`GetShopInventoryEntityID`, `GetShopInventory`, `GetShopInventoryItem`),
  `Shop.IsOpen`, `Shop.Credit` (Change-List mit `AddCashDelta`, Kategorie
  `ExpenditureCategory_FoodSales`/`DrinkSales`/`FacilitySales`), `Shop.Price`, `Shop.Readable`.
  `Visitor.Shop`, `Visitor.Pick`, `Visitor.CloseShop`; `Session.BuyPick` → Gast `buy|gid|index`
  → `Session._HostBuy` prüft und bucht, antwortet `sold|ok|...` oder `sold|no|<grund>`, sendet
  `em|sid|eat|q` (leise) an die anderen. Höchstens ein Kauf alle 2 s. UI-Aktionen `buy`, `shopclose`.
- **Besonderheiten:** Preise in Spiel-Einheiten (860 = 8,60). Ein Automat ohne Wegeanschluss
  ist geschlossen. Ohne Sitzung bucht der Spieler in seinen eigenen Park.

### FEAT-170 – Essen und Trinken beim Gehen
- **Status:** Implemented · **Seit:** 1.13.0
- **Funktion:** Nach dem Kauf isst/trinkt die Figur etwa 20 s lang beim Gehen.
- **Technik:** `Visitor.Ate` setzt `meal`; Animationen `walkeat` (`walkinteractusefoodr`),
  `walkdrink` (`walkinteractusecupl`); Mitspieler-Figuren über `p.emote` (1200 Frames).
- **Besonderheiten:** Die Steh-Varianten sind Teil-Animationen und bewegen allein nichts
  (getestet) – deshalb nur beim Gehen sichtbar.

### FEAT-171 – Figuren der Mitspieler
- **Status:** Implemented · **Seit:** 1.12.0 (als Gast-Figur seit 1.13.0)
- **Funktion:** Besuchende Mitspieler erscheinen als ihre Figur, laufen/rennen je nach
  Geschwindigkeit, schauen in Laufrichtung, spielen Emotes und Essen.
- **Technik:** `viz.lua` `guestFigure(p)`, `placeGuest` (geglättete Position, Gangart aus
  Geschwindigkeit), erkennt Besucher am Aktivitätstext „Besucher“; Aussehen aus `p.look`.

### FEAT-172 – Statue als Figur
- **Status:** Replaced (durch FEAT-161; bleibt als Rückfall) · **Seit:** 1.12.0
- **Technik:** Prefab `my_stoneguests_01_game`, Drehung +π/2 (`Visitor.FIGURE`,
  `Visitor.FIGURE_YAW`, `FIGURE` in `viz.lua`). Wird nur benutzt, wenn
  `Figure.Available()` falsch ist.
- **Warum ersetzt:** wirkte wie eine starre Statue ohne Animation (Rückmeldung des Eigners).

### FEAT-173 – „Gast begleiten“ (G)
- **Status:** Removed · **Seit:** nie veröffentlicht (gebaut 2026-11-19, entfernt vor 1.13.0)
- **Funktion:** G hängte die Gast-Kamera des Spiels an den nächsten Computer-Gast.
- **Warum entfernt:** doppelt zur Gast-Kamera im Radialmenü des Spiels und verwirrend
  (kein eigener Besucher). Die Taste wurde in der DLL durch V ersetzt. Commit `d135e5e`.

### FEAT-174 – Besucher v1: Laufkamera ohne Figur
- **Status:** Replaced (durch FEAT-163/FEAT-164) · **Seit:** 1.11.0
- **Technik:** Kamera „Walking“ (`walk()` in `visitor.lua`), bleibt als Rückfall, wenn keine
  Figur gebaut werden kann.
