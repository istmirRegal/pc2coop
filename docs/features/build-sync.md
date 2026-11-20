# Bau-Synchronisation

Wie Bauänderungen eines Spielers bei allen ankommen. Drei Wege (ADR-004):
1. **Szenerie-Teile** werden nach jedem Commit als Endzustand gelesen (`up`/`del`).
2. **Editor-Aufrufe** (Gelände, Wege, Pools, ebene Fahrgeschäfte, Parkverwaltung) werden
   mitgeschnitten und bei den anderen wieder abgespielt (`cmd`).
3. **Strecken-Fahrgeschäfte** gehen als Bauplan-Datei (`ride`).

Code: `probe/PC2CoopProbe/Main/pc2coop/sync.lua`, `probe/PC2CoopProbe/Main/pc2coop/replay.lua`,
`probe/PC2CoopProbe/Main/pc2coop/rides.lua`, `probe/PC2CoopProbe/Main/pc2coop/capture.lua`,
Host-Logik in `probe/PC2CoopProbe/Main/pc2coop/session.lua`.

### FEAT-060 – Szenerie-Sync
- **Status:** Implemented · **Seit:** 1.4.1 · **Hängt ab von:** FEAT-061
- **Funktion:** Deko, Szenerie, Gebäudeteile, Shops: platzieren, klonen, verschieben, drehen,
  Größe ändern, löschen – auch während jemand selbst etwas hält.
- **Technik:** `sync.lua` umhüllt `api.undo.CommitPreview` (Hooks `Handlers.BeforeCommit`,
  `Handlers.AfterCommit`). Nach einem lokalen Commit liest es alle synchronisierten Teile neu
  (verschoben/gelöscht) und sucht neue Teile per Kugelabfrage um den Platzierungspunkt.
  Ergebnis: Zeilen `sync:up|...` / `sync:del|...` an `Session.OnSyncLine`. Fremde Zustände
  kommen über `Sync.Receive` und werden im Editor nachgebaut (eine Vorschau zur Zeit,
  `Handlers.WaitForRemote`). Teile-IDs: `gid` (geteilte ID, `Sync.EntityToGid`,
  `Sync.GidToEntity`, `Sync.LocalPart`, `Sync.GidOfPart`); Größe über `Sync.NoteScale`.
- **Besonderheiten:** Das Spiel umgeht Wrapper auf Methoden der Change-List-Userdata bei
  `:`-Aufrufen; deshalb wird `CommitPreview` umhüllt (ADR-004).

### FEAT-061 – Host-Autorität und Reihenfolge
- **Status:** Implemented · **Seit:** 1.4.1
- **Funktion:** Der Host ordnet alle Änderungen, vergibt Revisionen und merkt Urheber.
- **Technik:** `session.lua`: lokale Funktionen `authorityUp`, `authorityDelete`, `deliver`,
  `toGame`; `objects`, `tombstones`, `seq`; Host verteilt `ops`-Blöcke. Gast-Nachrichten
  `up`, `del`, `cmd`, `ride` an den Host.

### FEAT-062 – Halten und Sperren beim Bearbeiten
- **Status:** Implemented · **Seit:** 1.6.0
- **Funktion:** Wer ein Objekt zuerst aufnimmt, hat es; andere sehen es eingefärbt und können
  es nicht nehmen (ihr Werkzeug wird zurückgesetzt, am Objekt steht, wer es bearbeitet).
- **Technik:** Nachricht `hold|label|gids|items` → `hostHold`; `locks`, `holds`,
  `Session.Holds`; `Sync.SetRemoteLocks`, `Sync.RemoteLocks`, `Sync.HeldParts`, `Sync._SetHeld`;
  `hold-denied|name|gid` → `Session._Denied`; `hold-lost`; Host antwortet `deny|name|gid`/`h`.
- **UI:** Sperr-Färbung (FEAT-094), „<Name> baut hier gerade“ am Objekt (FEAT-082).

### FEAT-063 – Konflikte: spätere Änderung wird zurückgenommen
- **Status:** Implemented · **Seit:** 1.6.0
- **Funktion:** Kommen zwei Änderungen am selben Objekt gleichzeitig an, gilt die Reihenfolge
  beim Host; die spätere wird zurückgenommen, der Spieler sieht am Objekt, wer schneller war
  (FEAT-082).
- **Technik:** Revisionen in `authorityUp`; `conflicts`-Zähler im Roster. Die Ablehnung
  `R|gid|grund|wer` nennt, wer das Objekt zuletzt geändert hat (`restore`) oder es hält
  (`refuseLocked`).

### FEAT-064 – Gebündelte Übernahme
- **Status:** Implemented · **Seit:** 1.5.0
- **Funktion:** Viele Änderungen kommen als Block an; der Verlauf fasst sie zu einer Zeile zusammen.
- **Technik:** `ops`-Nachrichten mit mehreren Zeilen; `bursts` (eine Logzeile pro Serie).

### FEAT-065 – Replay von Editor-Aufrufen (Gelände, Wege)
- **Status:** Implemented · **Seit:** 1.6.0
- **Funktion:** Gelände-Pinsel, Spline-Wege, Wege-Pinsel und -Radierer, Wege/Objekte unter
  dem Mauszeiger löschen.
- **Technik:** `replay.lua`: Listen `OPERATION_METHODS` (gameterrain-Pinsel), `OBJECT_METHODS`
  (volumes, flatrides, ridestation), `HIER_METHODS` (`RemoveVolume`,
  `AddVolumeChunkToCompositeObject`), `CHANGELIST_METHODS`. `Replay.Install` umhüllt sie;
  `Replay.OnPreview` sammelt, `Replay.OnCommit` liefert einen Batch (`;`-getrennte Aufrufe,
  Rückgaben als `@rN`); `Replay.Split` teilt lange Batches; `Replay.Apply` spielt fremde
  Batches in eine neue Change-List und committet. Volumen werden über den Strahl des Editors
  (`y`-Argument), Chunks über einen Abwärtsstrahl (`k`-Argument) adressiert.
- **Besonderheiten:** Nur Methoden aus den Listen werden abgespielt, Argumente geprüft;
  nichts aus dem Netz wird als Code ausgeführt (ADR-005).

### FEAT-066 – Stempel und Pools aus Formen
- **Status:** Implemented · **Seit:** 1.12.0
- **Technik:** `volumes.CreateMoveObjectForVolumeOutline` (`outline = true`) in `replay.lua`;
  die Platzierung (`SetPosition`, `SetTransform`) geht im Batch mit.
- **Besonderheiten:** In der Testkopie bestätigt (Kopie 30 m versetzt erscheint als eigenes Objekt).

### FEAT-067 – Löschen per Mehrfachauswahl
- **Status:** Implemented · **Seit:** 1.9.1 (Fahrgeschäfte), Wege/Pools korrekt seit 1.12.3
- **Funktion:** Mehrere Objekte, Fahrgeschäfte, Wege- und Pool-Stücke auf einmal löschen.
- **Technik:** `replay.lua` ummantelt `SceneryUtils.DeleteMultiSelection_Core` (`demolishing`,
  `rN=@demolish`) und `AddVolumeChunkToCompositeObject`. Lokale Funktion `chunkAt` geht vom
  getroffenen Kollisions-Objekt bis zum Elternteil mit eigener Volumen-ID hoch.
- **Besonderheiten:** Vor 1.12.3 ging das Löschen von Wegen/Pools per Mehrfachauswahl
  nicht an die Mitspieler („chunk without probe“). Test:
  `test_a_ray_hitting_the_collision_child_still_finds_the_chunk`.

### FEAT-068 – Seen und Wasserfälle
- **Status:** Implemented-Untested · **Seit:** 1.12.0
- **Technik:** `gameterrain.CreateLake`, `gameterrain.CreateWaterfall` in `CHANGELIST_METHODS`.
- **Besonderheiten:** Per Skript nicht sicher aufrufbar; nur von Hand prüfbar.

### FEAT-069 – Ebene Fahrgeschäfte platzieren und abreißen
- **Status:** Implemented · **Seit:** 1.9.1
- **Technik:** `flatrides.CreateFlatRideEditToken`, `AddFlatRide`, `GetFlatRideEditToken`,
  `RemoveFlatRide`; Abreißen über Menü oder Mehrfachauswahl. Fahrgeschäfte aus Bauplänen gehen
  als Bauplan-Datei (FEAT-072).

### FEAT-070 – Ein- und Ausgänge von Fahrgeschäften
- **Status:** Implemented-Untested · **Seit:** 1.10.0
- **Technik:** `ridestation.GetRideStationEditToken`, `CreateEntranceExitEditToken`,
  `AddEntranceExit`, `MoveEntranceExit`, `RemoveEntranceExit`,
  `volumes.CreateMoveObjectPlatformGateJoin`.

### FEAT-071 – Parkverwaltung
- **Status:** Implemented · **Seit:** 1.12.0 (Parkname seit 1.4.1)
- **Funktion:** Parkname, Eintrittspreis, Fast-Pass/Pool-Pass-Preise, Fahrgeschäfte und
  Shops öffnen/schließen, Shop-Preise, Kredite, Forschung, Beleuchtungszeiten.
- **Technik:** `IMMEDIATE_METHODS` in `replay.lua` (`facilities`, `pools`, `attractions`,
  `ridestation`, `park`, `techtree`, `money`): sofort gesendet als `!api.Method(args)`,
  Objekt-Argumente als geteilte IDs (`e<gid>`).
- **Besonderheiten:** Gleichzeitige Änderungen: Reihenfolge beim Host gilt. Kredite
  gleichzeitig können leicht auseinanderlaufen (bekannte Grenze). In der Testkopie
  bestätigt: Eintrittspreis, Parkname, Kredit, Öffnen/Schließen.

### FEAT-072 – Achterbahnen und Schienenbahnen als Bauplan
- **Status:** Implemented · **Seit:** 1.10.0
- **Funktion:** Achterbahnen, Schienenfahrgeschäfte, Wasserrutschen (mit Plattform) und
  Fahrgeschäfte aus Bauplänen: neu bauen, ändern, abreißen. Die Bahn geht als kleine
  Bauplan-Datei, sobald der Streckeneditor verlassen wird.
- **Technik:** `rides.lua`: `Rides.Tick` erkennt geänderte Bahnen, speichert sie mit
  `SaveBlueprintToFile` als `pc2coop-ride-<n>-<m>.blueprint`, sendet sie (`ride`); die
  anderen tauschen ihre Kopie in einer Change-List (`Rides.Apply`). `Rides.ValidKey`,
  `Rides.ValidFile`, `Rides.FileReady`, `Rides.Baseline`, `Rides.Abandon`; `ridedel` löscht
  die Datei nach dem Einbau (DLL `del`). Schlüssel: `Sync.RideKey` (gerundete Position).
- **Besonderheiten:** Farben/Züge ohne Streckenänderung kommen erst mit der nächsten
  Streckenänderung (bekannte Lücke).

### FEAT-073 – Sperre der Bahn im Streckeneditor
- **Status:** Implemented · **Seit:** 1.10.0
- **Technik:** `Rides.Editing`; Halten wie FEAT-062.

### FEAT-074 – Rückgängig nur für eigene Schritte
- **Status:** Implemented · **Seit:** 1.6.0
- **Funktion:** Strg+Z nimmt nur den eigenen letzten Schritt zurück; stammt der neueste von
  einem Mitspieler, ist Rückgängig gesperrt.
- **Technik:** `Sync.MayUndo`, `Handlers.AfterUndo`; Ereignis `undo-blocked` → Toast.

### FEAT-075 – Beim Host unmögliche Änderungen überall entfernen
- **Status:** Implemented · **Seit:** 1.6.0
- **Funktion:** Baut ein Gast etwas, das im Host-Park nicht geht (z. B. außerhalb der
  Parkgrenze), wird es bei allen entfernt und im Verlauf vermerkt.
- **Technik:** `Session._HostRefused`, `recent` (Zeile je Sequenz), `rejected`-Zeilen aus sync.

### FEAT-076 – Desync-Erkennung und Wiederholung
- **Status:** Implemented · **Seit:** 1.5.0
- **Funktion:** Kann eine fremde Änderung nicht übernommen werden, wird sie einmal wiederholt;
  sonst Hinweis und „Neu synchronisieren“ (FEAT-041).
- **Technik:** `sync:desync|...` → `Session.Desync`, `desync`; Gast meldet dem Host `desync`.

### FEAT-077 – Hinweis auf nicht synchronisierte Werkzeuge
- **Status:** Implemented · **Seit:** 1.6.0
- **Funktion:** „Wege mit Anfassern nachträglich bearbeiten“ wird nicht synchronisiert; der
  Spieler bekommt einen Hinweis.
- **Technik:** `OBJECT_METHODS.volumes.CreateMoveObjectsForSelection = {unsupported = ...}` →
  `sync:unsupported` → Toast (höchstens alle 600 Frames).

### FEAT-078 – Pause und Spieltempo für alle
- **Status:** Implemented · **Seit:** 1.6.0 · **Hängt ab von:** FEAT-142
- **Funktion:** Wer pausiert oder vorspult, tut es für alle (mit Hinweis wer).
  Regel „nur der Host“ möglich.
- **Technik:** `World.Time`, `World.SetTime`, `World.HookHUD`; Nachricht `time`;
  `Session._LocalTime`; `Sync.SetPaused`.

### FEAT-079 – Zahlen und Meldungen des Host-Parks
- **Status:** Implemented · **Seit:** 1.6.0
- **Funktion:** Besucher und Geld des Host-Parks im Fenster; Meldungen des Host-Parks
  (defekt, kein Strom, …) bei allen.
- **Technik:** `World.Numbers` (im Roster), `World.HookNotifications` → `Session._ParkNote`
  → `note|x|y|z|text` (Ort für FEAT-140).

### FEAT-080 – Schutz, wenn ein gehaltenes Objekt gelöscht wird
- **Status:** Implemented · **Seit:** 1.6.0
- **Funktion:** Löscht ein Mitspieler das Objekt, das man gerade hält, stürzt das Spiel nicht ab.
- **Technik:** Trifft eine fremde Änderung ein gehaltenes Teil, bricht `sync.lua` die eigene
  Vorschau ab (`sync:hold-lost|wer|gid`, Meldung am Objekt, FEAT-082) und verlässt das Werkzeug
  (`World.LeaveTool`), bevor
  die Änderung angewendet wird. QA-Befehl `held-delete-test`.

### FEAT-081 – Fahrgeschäfte verschieben
- **Status:** Implemented-Untested · **Seit:** 1.12.0
- **Technik:** `flatrides.MoveFlatRide` in `OBJECT_METHODS`.
- **Besonderheiten:** Per Skript nicht prüfbar: das Spiel lehnt jede Verschiebung ohne seine
  Gelände-Anpassung pro Frame ab (bIntersectingTerrain). Nur von Hand prüfbar.

### FEAT-082 – Ablehnung am Objekt
- **Status:** Implemented · **Seit:** unveröffentlicht · **Hängt ab von:** FEAT-062, FEAT-063,
  FEAT-080, FEAT-091
- **Funktion:** Wird eine eigene Änderung zurückgenommen, steht der Grund 5 s lang am Objekt,
  mit dem Namen des Mitspielers: „Vici baut hier gerade“ (Objekt gehalten, auch beim
  Aufnehmen), „Vici war schneller“ (spätere Änderung), „Vici hat das gerade geändert“
  (gehaltenes Objekt fremd geändert). Das Objekt blinkt 2 s in der Farbe des Mitspielers.
  Ist das Objekt in diesem Spiel nicht zu finden, kommt die Meldung als Karte unten links.
- **Technik:**
  - Host: `R|gid|grund|wer`, `deny|name|gid` (statt nur Grund bzw. Name).
  - sync: `sync:rejected|gid|grund|wer`, `sync:hold-denied|name|gid`, `sync:hold-lost|wer|gid`
    (`touchesHeld` gibt die Zeile zurück, die gewonnen hat).
  - session: `markConflict` legt eine Marke an (höchstens 4, eine je Objekt). `checkMarks`
    prüft jeden Frame mit `Sync.GidToEntity`, ob das Objekt da ist; nach 0,5 s ohne Objekt
    wird daraus eine Karte. `Session.Conflicts` liefert die sichtbaren Marken.
  - `pc2coopqa.lua`: Schild über die Coaster-Labels (wie FEAT-091, 4 m über dem Objekt),
    Blinken über die Sperr-Färbung (`locked`, Kanal 3, FEAT-094) alle 0,25 s.
- **UI:** Schild in der Welt, kein Toast (TP-16, UX-E2).
- **Besonderheiten:** Namen und gids aus dem Netz werden geprüft (`clean`, Muster). Ein
  Name „host“ (Löschung durch den Host) wird zu „Ein Mitspieler“. Grund `fremd` (Sitzungsregel)
  hat seine eigene Meldung und bekommt keine Marke. Geprüft in der Testkopie mit
  nachgestelltem Mitspieler (gehalten, schneller, Karte als Rückfall).
