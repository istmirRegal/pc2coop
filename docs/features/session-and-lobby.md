# Sitzung und Lobby

Hosten, Einladen, Beitreten, Park-Übertragung, Lobby im Hauptmenü, Chat, Verbindung.
Hauptcode: `probe/PC2CoopProbe/Main/pc2coop/session.lua` (Rolle, Nachrichten, Zustand),
`probe/PC2CoopProbe/Main/pc2coop/ui.lua` (Aktionen der Oberfläche),
`probe/PC2CoopProbe/ui/UIGameface/js/pc2coop/CoopLayer.js` (Darstellung),
`native/steam_net.cpp` (Steam). Nachrichtenformate: `docs/architecture/NETWORKING.md`.

### FEAT-020 – Sitzung hosten
- **Status:** Implemented · **Seit:** 1.4.1 · **Hängt ab von:** FEAT-190
- **Funktion:** Ein Spieler eröffnet eine Steam-Lobby und wird Host. Der Host ist maßgeblich
  für Reihenfolge, Sperren und Urheber (FEAT-061).
- **Technik:** `Session.Host` → DLL `host` → Ereignis `lobby:created` / `lobby:entered`
  (Besitzer = Host). Die Lobby ist nur für Steam-Freunde sichtbar und hat höchstens 8 Plätze
  (DLL `CreateLobby`, `SLOTS = 8` in der Oberfläche).
- **UI:** Lobby-Fenster „Lobby erstellen“, Pausemenü „Diesen Park hosten“, F7-Menü
  „Raum hosten“ (`menu.lua`). UI-Aktion `host`. Bis Steam antwortet, ist „Sitzung starten“
  gesperrt („Startet …“, `JoinState` Phase `starting` aus `Session._starting`). Kann Steam die
  Lobby nicht erstellen (`lobby:error|create-failed`) oder antwortet 1800 Frames lang nicht,
  sagt `JoinFailed` es.
- **Besonderheiten:** Spielerfarben aus `COLORS` (FEAT-043).

### FEAT-021 – Lobby im Hauptmenü
- **Status:** Implemented · **Seit:** 1.8.0 · **Hängt ab von:** FEAT-020, FEAT-110
- **Funktion:** Host und Freunde treffen sich im Hauptmenü, bevor ein Park gewählt ist.
  Zurück ins Hauptmenü heißt zurück in die Lobby, nicht raus.
- **Technik:** `probe/PC2CoopProbe/Main/pc2coop/frontend.lua` (`Frontend.Tick`) betreibt
  Session und UI im Hauptmenü; `Session.SetContext("menu")`; `stage = "lobby"` (FEAT-033).
  `Ui.SetFrontend` schaltet die Lobby-Ansicht.
- **UI:** Kachel „Multiplayer“ (FEAT-113), Multiplayer-Seite (FEAT-119), Sitzungsleiste
  (FEAT-034). Der Host öffnet den Park auf den Seiten des Spiels.

### FEAT-022 – Laufenden Park hosten (Pausemenü)
- **Status:** Implemented · **Seit:** 1.4.1
- **Funktion:** Wer schon im Park ist, hostet genau diesen Park.
- **Technik:** UI-Aktion `host` im Park; `Session.Host`. Beigetretene laden den Park (FEAT-030).
- **UI:** Pausemenü → „Multiplayer“ → „Diesen Park hosten“; Reiter Team.

### FEAT-023 – Freunde einladen
- **Status:** Implemented · **Seit:** 1.4.1 · **Hängt ab von:** FEAT-024, FEAT-194
- **Funktion:** Host lädt Steam-Freunde direkt oder über das Steam-Overlay ein. Eingeladene
  kommen ohne Nachfrage hinein (FEAT-027).
- **Technik:** `Session.InviteFriend(sid)` → DLL `invite_user`; `Session.Invite` → DLL
  `invite` (Overlay). Ereignisse `invite:sent` (merkt `invited[sid]`) und `invite:failed`.
  Ein Knopf bleibt `INVITE_FRAMES` (~25 s) „Eingeladen“.
- **UI:** Knopf „Einladen“ pro Freund, „Steam-Overlay“; UI-Aktionen `invite`, `invite_overlay`.
  Auf der Multiplayer-Seite wartet ein Eingeladener blass in einem Platz (`asked` = Frame der
  Einladung), nach 2 Minuten „keine Antwort“ mit „Noch einmal einladen“.

### FEAT-024 – Freundesliste
- **Status:** Implemented · **Seit:** 1.8.0
- **Funktion:** Freunde, sortiert: spielt Planet Coaster 2, online, Rest; alphabetisch.
- **Technik:** `Session.RefreshFriends` → DLL `friends` → `friends:begin`, `friend`,
  `friends:end`; `Session.Friends`. „hat eine offene Lobby“ → `Session.JoinFriend`
  (UI-Aktion `join_friend`).
- **UI:** Seite „Multiplayer“ rechts, im Park Reiter Spieler. Seit UX-Overhaul P5 nur wer
  erreichbar ist (online, spielt, hat eine Sitzung, wartet auf eine Einladung); sonst „Gerade ist
  keiner deiner Steam-Freunde online.“ (`onlineFriends`). „Eingeladen“ hat einen Tooltip.

### FEAT-025 – Beitritt über Steam-Einladung
- **Status:** Implemented · **Seit:** 1.4.1 · **Hängt ab von:** FEAT-026, FEAT-029, FEAT-030
- **Funktion:** Wer eine Einladung in Steam annimmt, tritt der Lobby bei und bekommt den Park.
- **Technik:** DLL-Ereignisse `invite:accepted`, `lobby:entered`, `lobby:join-failed`;
  danach `hello` an den Host (Name, Baseline, Modus, Version, Spielversion, DLC, Mods).
  `Session.JoinState` liefert den Fortschritt (Phasen joining, awaiting, asking, loading, live).
- **UI:** Beitrittskarte in der Bildschirmmitte (FEAT-031).

### FEAT-026 – Nur Sitzungen von Steam-Freunden
- **Status:** Implemented · **Seit:** 1.5.0
- **Funktion:** Die Mod tritt nur Lobbys bei, deren Host in der eigenen Freundesliste steht;
  Lobbys sind nur für Freunde des Hosts sichtbar.
- **Technik:** Prüfung in der DLL beim Beitritt (`net:refused`) und Sichtbarkeit `friends only`.
- **Besonderheiten:** Teil der Sicherheitsregeln im README.

### FEAT-027 – Beitrittsanfragen und Freigabe durch den Host
- **Status:** Implemented · **Seit:** 1.6.1
- **Funktion:** Nicht eingeladene Freunde erscheinen beim Host unter „Möchte beitreten“ und
  bekommen den Park erst nach „Zulassen“.
- **Technik:** `askBeforeJoin`, `requests`, `Session.Requests`, `Session.Answer(sid, ok)`,
  `Session.SetAskBeforeJoin`, `Session._Admit`. Host → Gast: `wait`, `welcome`, `denied`.
- **UI:** Reiter Team „Möchte beitreten“ mit „Zulassen“/„Ablehnen“ (Aktionen `approve`, `deny`).

### FEAT-028 – Nachfrage bei Beitritt per Startparameter
- **Status:** Implemented · **Seit:** 1.6.1
- **Funktion:** Kommt eine Lobby mit dem Spielstart (Link/Startparameter statt angeklickter
  Einladung), fragt die Mod, bevor sie einen Park von diesem Host lädt.
- **Technik:** `joinSource = "launch"`, `confirm = {host}`; `Session.ConfirmJoin`,
  `Session.DismissJoin`. Vor der Zustimmung sendet der Gast nichts (auch kein Aussehen).
- **UI:** Komponente `JoinConfirm` (Aktionen `confirm_join`, `cancel_join`).

### FEAT-029 – Versionsprüfung (Mod und Spiel)
- **Status:** Implemented · **Seit:** 1.4.1
- **Funktion:** Unterschiedliche Mod- oder Spielversionen spielen nie zusammen; der Gast
  erfährt, wer aktualisieren muss.
- **Technik:** `Session.VERSION` und Spielversion im `hello`; Host antwortet `reject|...`;
  Ereignis `session:rejected-version`. `Session.VERSION` muss mit `probeVersion` in der
  Datenbank übereinstimmen (Test `tests/test_probe_lua.py`).
- **UI:** Fehlerkarte (FEAT-031).

### FEAT-030 – Park-Übertragung beim Beitritt
- **Status:** Implemented · **Seit:** 1.4.1 · **Hängt ab von:** FEAT-191
- **Funktion:** Der Host speichert seinen Park und schickt ihn; der Gast lädt ihn automatisch.
- **Technik:** Host: `sendPark` speichert über `manager:SaveParkToFile` /
  `SaveTerrainToFile` und sendet `pc2coop-join.trn` (Gelände) und `pc2coop-join.bin` (Park)
  über DLL `file`. Gast: `file:progress`, `file:done`, dann `Session._LoadPark` /
  `Session._TryLoad` → `RequestLoadParkFromFile`. Dateien haben feste Namen,
  Größenprüfung, werden nach dem Laden gelöscht. `park`-Nachricht beschreibt den Park.
- **UI:** Fortschritt „holt NN %“ in Spielerliste und Beitrittskarte.
- **Besonderheiten:** Einzige Dateien, die aus dem Netz auf die Platte kommen (README).

### FEAT-031 – Beitrittsfortschritt und Beitrittsfehler
- **Status:** Implemented · **Seit:** 1.5.0
- **Funktion:** Zeigt, wie weit der Beitritt ist, und bei Fehlern warum, mit Ausweg.
- **Technik:** `Session.JoinState` (Phasen inkl. `failed`, `confirm`, `rejoin`);
  `joinFailure`; `loadfailed` an den Host.
- **UI:** `JoinProgress`, `JoinFailed` („Erneut versuchen“ = `retry_join`, „Abbrechen“ = `cancel_join`).
  Texte z. B. „Einladung abgelaufen“, „Park konnte nicht geladen werden“. Seit UX-Overhaul P5
  vier Schritte mit dem `ProgressSteps` des Spiels (Verbinden, Zustimmung, Park kommt, Park
  lädt) und „Abbrechen“. Bricht der Spieler ab, während Steam noch beitritt, verlässt die Mod
  die Lobby, sobald sie kommt (`Session._dropLobby`, Log `session:join-cancelled`).

### FEAT-032 – Park-Auswahl in der Lobby
- **Status:** Replaced (durch FEAT-119: Park über die Seiten des Spiels; Lua bleibt, ohne Knopf)
  · **Seit:** 1.9.0 · **Hängt ab von:** FEAT-021
- **Warum ersetzt:** baute die Seiten des Spiels nach (UX-A6, TP-03); der Host wählt den Park so,
  wie er es gewohnt ist.
- **Funktion:** Host wählt „Gespeichert“ (eigene Sandbox-Parks), „Neu“ (Klima, Kreativ oder
  Budget) oder „Franchise“; alle sehen die Wahl, „Park öffnen“ startet für alle.
- **Technik:** `probe/PC2CoopProbe/Main/pc2coop/parks.lua` (`Parks.List`, `Parks.Load`,
  `Parks.New`, über `ParkLoadSaveManager` und `SandboxMenuHUD`); `Session.SetChoice`,
  `Session.Choice`, `Session.MarkStarting`. UI-Aktionen `parks`, `choose`, `start`.
- **UI:** bis UX-Overhaul P3 Lobby Mitte „Wo spielen wir?“ (Parkliste, Klima, „Park öffnen“).
  Heute: `parks` und `start` ohne Knopf, `choose` nur noch „franchise“ (Kachel Franchise).
- **Besonderheiten:** Karriere und Herausforderungen fehlen noch (ROADMAP).

### FEAT-033 – Parkwechsel des Hosts für alle (Stage)
- **Status:** Implemented · **Seit:** 1.8.0
- **Funktion:** Öffnet der Host einen anderen Park, laden alle diesen.
- **Technik:** `stage|lobby` bzw. `stage|park|<token>|<name>|<guard>`; `Session.Stage`,
  `Session._OnStage`; `parkToken` neu für jeden Park; `seenStage` verhindert Doppelaktionen.
- **UI:** Geht der Host zurück ins Hauptmenü, sieht ein Mitspieler im Park den Dialog „Der Host
  ist im Hauptmenü“ mit „Ins Hauptmenü“ und „Hier warten“ (der nächste Park lädt in beiden
  Fällen); danach bleibt die Pille. Log `session:host-in-menu`.

### FEAT-034 – Mini-Lobby-Karte im Hauptmenü
- **Status:** Implemented · **Seit:** 1.9.0
- **Funktion:** Sitzungsleiste (TP-04): auf jeder Seite des Hauptmenüs oben rechts unter dem
  Newsletter-Kasten, solange die Multiplayer-Seite nicht offen ist. Avatare, Zustand, „Öffnen“
  und „Beenden“/„Verlassen“; bleibt sichtbar, während der Host durch die Spielseiten geht.
- **UI:** Komponente `MiniLobby` (Aktionen `open`, `leave` über `endOrAsk`).

### FEAT-035 – Chat
- **Status:** Implemented · **Seit:** 1.8.0
- **Funktion:** Textchat in Lobby und Park; im Park unten links, **Enter** öffnet die Eingabe
  (FEAT-116).
- **Technik:** `Session.SendChat`, `Session._BroadcastChat`, `Session._AddChat`,
  `Session.Chat`; Nachricht `chat`. UI-Aktion `chat`.
- **UI:** Lobby rechte Spalte, Reiter Team; Eingabefeld (Enter sendet). Im Park `ChatArea`.
- **Besonderheiten:** Texte werden bereinigt (`cleanText`, 120 Zeichen bzw. 200 im Chat).

### FEAT-036 – Steam-Profilbilder
- **Status:** Implemented · **Seit:** 1.8.0
- **Funktion:** Runde Profilbilder der Spieler; Farbe und Anfangsbuchstabe, solange keins da ist.
- **Technik:** DLL `avatar` → Ereignis `avatar` (Base64-PNG); `Session.Avatars`;
  `CoopLayer.js` `avatarPixels`/`paintAvatar` malen auf ein Canvas (Gameface kann keine
  `data:`-URLs).
- **UI:** Komponenten `Avatar`, `AvatarCanvas`.

### FEAT-037 – DLC- und Mod-Vergleich
- **Status:** Implemented · **Seit:** 1.8.0
- **Funktion:** Die Lobby zeigt, wem welches DLC oder welche Mod fehlt.
- **Technik:** Oberfläche meldet die eigenen DLC (`reportDlc` → Aktion `dlc` →
  `Session.SetDlc`); DLL `mods` liefert Mod-Ordner (`Session._SetMods`); Gast → Host `info`;
  `World.RequiredDLC`.
- **UI:** `contentLine` je Spieler, Abschnitt „Inhalte“.

### FEAT-038 – Nur gemeinsame Inhalte (Content Guard)
- **Status:** Implemented · **Seit:** 1.8.0 · **Hängt ab von:** FEAT-037
- **Funktion:** Objekte aus einem DLC, das nicht alle haben, werden nicht gebaut; der Host
  kann „Alle Inhalte erlauben“.
- **Technik:** `contentGuard`, `Session.SetContentGuard`, `Session._ContentChanged`,
  `Session._ContentRefused`; Nachricht `content`; UI-Aktion `guard`.
- **UI:** Abschnitt „Inhalte“: im Park Schalter „Nur gemeinsame Inhalte“ (`ToggleRow`, nur Host,
  nur wenn nicht alle dasselbe haben), im Hauptmenü Knopf; Hinweis an den Bauenden.

### FEAT-039 – Wiederbeitritt nach Absturz
- **Status:** Implemented · **Seit:** 1.7.0
- **Funktion:** Nach Absturz oder Verbindungsverlust bietet das Hauptmenü „Wieder beitreten“
  an; der Spieler bekommt den aktuellen Park und seine Farbe zurück.
- **Technik:** Datei `pc2coop-lastsession.txt` (Notiz, FEAT-192); `Session._LastSession`,
  `Session._RejoinOffer`, `Session.Rejoin`, `Session.ForgetRejoin`; `departed[sid]` behält Farbe.
- **UI:** Komponente `Rejoin` (Aktionen `rejoin`, `forget_rejoin`).

### FEAT-040 – Verbindungsabbruch erkennen
- **Status:** Implemented · **Seit:** 1.6.1
- **Funktion:** Mitspieler sehen oben Mitte „Keine Verbindung zum Host“ mit der Zeit und
  „Verlassen“; nach 30 s fragt ein Dialog „Warten“ oder „Verlassen“. Ist die Verbindung wieder
  da, wird die Pille kurz grün (keine Meldungen mehr dazu). Kam etwas nicht an, lädt der Gast
  den Park neu.
- **Technik:** `lastHostFrame`/`hostSilent` (600 Frames); DLL `net:peer-stalled` →
  `players[sid].stale`; Host schickt `resync`. Host-Absturz beendet die Sitzung. Zeit, Dialog
  und grüner Moment in `CoopLayer.js` (`trackConnection`, `ConnectionPill`, `ConnectionDialog`).

### FEAT-041 – Neu synchronisieren
- **Status:** Implemented · **Seit:** 1.5.0
- **Funktion:** Lädt den aktuellen Park des Hosts neu, wenn etwas nicht übernommen werden konnte.
- **Technik:** `Session.Resync` (UI-Aktion `resync`); Host vermerkt `desync` im Verlauf.
- **UI:** Knopf „Neu synchronisieren“ im Multiplayer-Fenster.

### FEAT-042 – Sitzung verlassen oder beenden
- **Status:** Implemented · **Seit:** 1.4.1
- **Technik:** `Session.Leave` (UI-Aktion `leave`, F7 „Sitzung verlassen/beenden“);
  DLL `leave` → `lobby:left`. Verlässt der Host, endet die Sitzung für alle: Mitspieler sehen
  „Die Sitzung ist beendet“ (`JoinState` Phase `ended` aus `Session._ended`, bis
  `Session.DismissEnded`, UI-Aktion `ended_ok`; ein neuer Beitritt löscht es). Ein Besuch endet
  dabei, damit die Maus für den Dialog frei ist. Log `session:host-gone`.
- **UI:** „Beenden“ (Host) und „Verlassen“ im Fuß des Fensters, mit Tooltip. Ist noch jemand in
  der Sitzung, fragt der Host-Knopf erst „Für alle beenden?“ (Dialog `EndConfirm`, TP-30).

### FEAT-043 – Spielerfarben
- **Status:** Implemented · **Seit:** 1.4.1
- **Funktion:** Jeder Spieler hat eine Farbe (Spielerleiste, Marker, Toasts, Figur ohne Avatarfarben).
- **Technik:** `COLORS` in `session.lua`; zurückkehrende Spieler behalten ihre Farbe (`departed`).

### FEAT-044 – Verlauf (Feed) und Toasts
- **Status:** Implemented · **Seit:** 1.4.1
- **Funktion:** Beitritte, Austritte, Konflikte, Käufe usw. als Liste und kurz unten links.
- **Technik:** `addFeed` (Host sendet `feed|...` an alle), `toast`, `Session.Toasts`;
  Nachrichten mit `loc = true` sind Spieltexte und werden übersetzt (`shown` im JS).
- **UI:** `ChatArea` (Feed-Zeilen als `event`), Reiter Verlauf „Verlauf der Sitzung“.

### FEAT-045 – Erst-Hinweis im Park
- **Status:** Implemented · **Seit:** 1.12.0
- **Funktion:** Nach kurzer Zeit im Park mit Sitzung einmal ein Toast mit den wichtigsten Wegen
  (Mittelklick, Multiplayer-Reiter, F7).
- **Technik:** `firstUseHint()` in `Session.Tick`, `parkFrames`.

### FEAT-046 – Franchise-Parks hosten
- **Status:** Implemented-Untested · **Seit:** 1.8.0
- **Funktion:** Hostet man aus einem Franchise-Park, speichert der Host wie gewohnt ins Franchise.
- **Technik:** `Menu.FranchiseInfo` (IScenarioManager). Lobby-Modus „Franchise“ öffnet das
  Franchise-Menü des Spiels.

### FEAT-047 – Sitzungsgedächtnis über Parkladen (DLL-KV)
- **Status:** Implemented · **Seit:** 1.4.1 · **Hängt ab von:** FEAT-193
- **Funktion:** Rolle, Lobby und Phase überleben das Neuladen der Lua-Module beim Parkwechsel.
- **Technik:** DLL `kv` → Ereignis `kv` → `memory[...]` (z. B. `memory.phase`, `memory.lobby`,
  `memory.rules`).

### FEAT-048 – Gast-Profil beim Mitspieler
- **Status:** Implemented · **Seit:** 1.6.0
- **Funktion:** Beim Gast geht nichts von selbst kaputt und Bauen kostet nichts; der echte
  Spielstand ist beim Host (ADR-003).
- **Technik:** `World.ApplyGuestProfile` (nur Sandbox, so wird der übertragene Park geöffnet).
