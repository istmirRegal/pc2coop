# Team-Funktionen

Gemeinsam planen, entscheiden, spielen. Konzept: `docs/KONZEPT.md`. Code:
`probe/PC2CoopProbe/Main/pc2coop/board.lua` (Brett), `probe/PC2CoopProbe/Main/pc2coop/session.lua`
(Host-Logik, Nachrichten), `probe/PC2CoopProbe/Main/pc2coop/ui.lua` (Aktionen,
`contextState`, `anchor`), `CoopLayer.js` (Reiter Planen, Verlauf, Sitzung).

### FEAT-130 – Brett: Baugebiete
- **Status:** Implemented · **Seit:** 1.12.0
- **Funktion:** Gebiet mit Name, Auftrag („Familienattraktion, max. 15.000 €, Wikingerstil“),
  Zuständigem und Radius; erscheint als Marker im Park.
- **Technik:** `Board.Make`/`Board.Add` mit Art `area`; `Session.BoardAdd`; Nachricht
  `board|add|...`; Host verteilt `bd|...`. UI-Aktion `board_add` (Ort aus `anchor`:
  Ping-Stelle oder Blickpunkt, `World.FocusPoint`).

### FEAT-131 – Brett: Aufgaben
- **Status:** Implemented · **Seit:** 1.12.0
- **Funktion:** To-dos ohne Ort, optional zugewiesen, offen/erledigt.
- **Technik:** Art `task`; `Session.BoardSet` (Felder `done`, `assignee`); UI-Aktionen
  `board_done`, `board_assign`, `board_del` → `Session.BoardRemove`.
- **UI:** Zuständig nachträglich ändern (UX-C3): Icon-Knopf `footerGuests` an offenen Aufgaben
  und Baugebieten, ein Klick wechselt reihum (alle, dann jeder Spieler), Tooltip sagt wohin.

### FEAT-132 – Brett: Kommentare
- **Status:** Implemented · **Seit:** 1.12.0
- **Technik:** Art `comment` mit Ort.

### FEAT-133 – Brett: Treffpunkte
- **Status:** Implemented · **Seit:** 1.12.0
- **Technik:** Art `meet` mit Ort.

### FEAT-134 – Bauvorschläge mit Abstimmung
- **Status:** Implemented · **Seit:** 1.12.0
- **Funktion:** Bauidee an einer Stelle; jeder stimmt dafür oder dagegen.
- **Technik:** Art `proposal`; Stimmen im 13. Feld `name:1,name:0`; `Board.Tally`;
  `Set(id, "vote", "name:1")`, der Host setzt den Namen des Absenders ein. UI-Aktion `board_vote`.
- **UI:** „Dafür (n)“/„Dagegen (n)“, „1 Stimme“/„Stimmen“.

### FEAT-135 – Brett-Marker im Park und Speicherung pro Park
- **Status:** Implemented · **Seit:** 1.12.0
- **Funktion:** Alles mit Ort erscheint als Marker; das Brett bleibt über Spielstarts.
- **Technik:** Host schreibt jede Änderung als Zeile in `pc2coop-board-<Park>.txt`
  (`Board.Line`, `Board.Lines`, `Board.Apply`; `Session._BoardFile`); Namensschilder über
  `pc2coopqa.lua`. Neue Spieler bekommen das Brett beim Beitritt.

### FEAT-136 – Mittelklick-Kontextmenü
- **Status:** Implemented · **Seit:** 1.12.0 · **Hängt ab von:** FEAT-095
- **Funktion:** Nach eigenem Ping neben dem Mauszeiger ein Menü für genau diese Stelle (10 s):
  Fahrgeschäft → „Team zur Testfahrt einladen“, „Selbst mitfahren“; jemand bearbeitet dort
  etwas → „Übernahme anfragen“; immer „Kommentar anheften“, „Bauvorschlag machen“,
  „Hier bauen (Baugebiet)“, „Treffpunkt“.
- **Technik:** `pingContext`, `Session.Context`, `Session.CloseContext`, `CONTEXT_FRAMES`;
  `ui.lua` `contextState()` (nächste Bahn ≤ 30 m, Bearbeiter ≤ 40 m); UI-Aktion `ctx`
  (`take`, `proposal`, …). Klasse `ContextMenu` (Mausposition per `mousemove`).

### FEAT-137 – Übernahme anfragen
- **Status:** Implemented · **Seit:** 1.12.0
- **Funktion:** Bitte an den Bearbeitenden, fertig zu bauen und freizugeben; Wegnehmen geht nicht.
- **Technik:** `Session.AskTakeover` → `take-ask|sid` → Host → `tk|name|label` an den
  Bearbeiter; höchstens eine Frage pro Spieler alle 5 s. Beim Bearbeiter `Session.TakeAsk()`
  (läuft nach `Session.TAKE_ASK_FRAMES` ab), `Session.DismissTakeAsk`.
- **UI:** seit 2.0.0 Anfrage-Karte „<Name> möchte bei „<Objekt>“ weitermachen.“ mit
  „Verstanden“ (`take_ok`, UX TP-19); vorher ein Toast.

### FEAT-138 – Testfahrt-Einladung
- **Status:** Implemented · **Seit:** 1.12.0
- **Funktion:** „Alle einladen“: alle bekommen oben eine Einladung mit „Mitfahren“.
- **Technik:** `Session.InviteRide` → `ride-invite|key|name` → Host → `iv|...`;
  `Session.Invitation`, `Session.DismissInvitation`; `INVITE_RIDE_FRAMES` = 3600.
  UI-Aktionen `invite_ride`, `invitation`.

### FEAT-139 – „Seit deinem letzten Besuch“
- **Status:** Implemented · **Seit:** 1.12.0
- **Funktion:** Beim Wiederkommen: was sich im Park geändert hat (Geld, neue Fahrgeschäfte …).
- **Technik:** Host merkt `lastVisit[sid]` beim Verlassen (`Session._RememberVisit`), Datei
  pro Park; beim Beitritt `since|text` (`Session._Since`, `Session._SetRideLister`).
- **UI:** Einmal als Meldung „Seit deinem letzten Besuch: …“ beim Beitritt (Host: beim Laden des
  Parks) und als Zeile im „Verlauf der Sitzung“ nur dieses Spielers (`Session._ShowSince`, TP-18).
  Vorher ein eigener Abschnitt im Reiter Verlauf.

### FEAT-140 – Park-Meldungen mit Ort
- **Status:** Implemented · **Seit:** 1.12.0 · **Hängt ab von:** FEAT-079
- **Funktion:** Defekte, festsitzende Gäste, Blitzschlag … mit „Hinspringen“.
- **Technik:** `note|x|y|z|text`; `events`, `EVENT_FRAMES`; `Session.Events`, `Session.EventLabel`.
- **UI:** Reiter Verlauf, Zeilen wie die Meldungen des Spiels (TP-18): Icon, Text, „Hinbringen“,
  „Ausblenden“ (nur auf diesem PC, bis das Fenster neu aufgebaut wird).

### FEAT-141 – Sicherungspunkte mit Abstimmung
- **Status:** Implemented · **Seit:** 1.12.0
- **Funktion:** Host legt Sicherungspunkte an; zurück geht nur, wenn alle zustimmen.
- **Technik:** `Session.Checkpoint`, `Session.Propose`, `Session.Vote`, `Session._VoteCheck`,
  `Session.VoteView`; Nachrichten `vote`, `vote-answer`; Wiederherstellen lädt den
  gespeicherten Park für alle. UI-Aktionen `checkpoint`, `restore`, `vote`.
- **UI:** Reiter Verlauf „Sicherungspunkte“, Anfrage-Karte `RequestCard`. „Zurückholen…“ fragt
  erst (`RestoreConfirm`): allein im Park wäre die Abstimmung sofort durch.

### FEAT-142 – Sitzungsregeln und Schnellwahl
- **Status:** Implemented · **Seit:** 1.12.0
- **Funktion:** Spieltempo/Pause: alle oder nur Host; Fremde Bauten abreißen: frei oder fragen;
  Besucher-Modus: erlaubt oder aus. Schnellwahl „Locker zusammen bauen“, „Geordnet“, „Nur bauen“
  (im Fenster kurz „Locker“, „Geordnet“, „Nur bauen“, dazu „Eigene“, solange keine passt).
  Regeln bleiben bei Parkwechsel.
- **UI:** Reiter „Einstellungen“ als Zeilen wie im Optionsmenü des Spiels (`ListStepperRow`,
  `ToggleRow`, TP-20); Erklärung je Regel im Tooltip. Mitspieler sehen die Zeilen gesperrt mit
  Tooltip „Nur der Host ändert Regeln.“
- **Technik:** `rules`, `RULE_VALUES`, `Session.SetRule`, `Session.SetRules(values, label)`,
  `Session.Rules`; KV `rules` (FEAT-047); Nachricht `rules`; Verlauf „Regeln "<label>": …“.
  UI-Aktionen `rule`, `rule_preset`.

### FEAT-143 – Fremde Bauten nur nach Rückfrage abreißen
- **Status:** Implemented · **Seit:** 1.12.0 · **Hängt ab von:** FEAT-142, FEAT-098
- **Technik:** Regel `foreign = ask`: Host stellt das Abreißen zurück und fragt den Urheber;
  Spieler bekommt `ruledeny|text`.

### FEAT-144 – Rollen- und Abwesenheits-Erklärung
- **Status:** Implemented · **Seit:** 1.12.0
- **Funktion:** Was Host und Mitspieler dürfen und was passiert, wenn jemand geht. Seit dem
  UX-Overhaul (TP-20) als Tooltips statt Abschnitten: die Rolle am Info-Icon neben „Regeln dieser
  Sitzung“, das Gehen an „Beenden“/„Verlassen“ im Fuß des Fensters.
- **Technik:** Nur Darstellung in `CoopLayer.js` (`renderSession`, `HoverTip`, `END_TIP`, `LEAVE_TIP`).

### FEAT-145 – Wettbewerb: Bauduell
- **Status:** Implemented · **Seit:** 1.12.0
- **Funktion:** Thema, 15/30/60 Minuten; jeder baut in seinem Baugebiet; Uhr oben für alle.
- **Technik:** `Session.StartCompetition("duel", minutes, topic)`; Host hält `comp`,
  sendet `cp|...` (`Session._CompLine`, `Session._CompRead`); Echtzeit von der DLL (`now`,
  FEAT-197) über `Session._CompClock`, `Session._CompCheck`; Nachzügler bekommen die cp-Zeile.
  UI-Aktion `comp_start`. Uhr im Sitzungs-Cluster (`PlayerBar`), Bewerten über die Anfrage-Karte.

### FEAT-146 – Wettbewerb: Koop gegen die Uhr
- **Status:** Implemented · **Seit:** 1.12.0
- **Technik:** Modus `timer` in `COMP_MODES`; Aufgaben vom Brett mit Zeitlimit.

### FEAT-147 – Wettbewerb: Bewertung und Ergebnis
- **Status:** Implemented · **Seit:** 1.12.0
- **Funktion:** Nach der Bauzeit bewertet jeder die anderen (Gestaltung, Technik 1–5);
  Ergebnis für alle.
- **Technik:** `Session.RateEntry` (eigene Bauten nicht bewertbar), `comp-rate`;
  `Session.CompetitionNext`, `Session.Competition`. UI-Aktionen `comp_rate`, `comp_next`.
