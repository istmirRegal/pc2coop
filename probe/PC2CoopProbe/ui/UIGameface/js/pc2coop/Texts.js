// Original MIT code (PC2 Co-op). English player texts (ADR-022). The mod's texts are written in
// German, in CoopLayer.js and in the Lua modules (toasts, the session's log, activities, join
// errors); CoopLayer.js shows them through tr(), which looks them up here when the game does not
// run in German.
//   EXACT     whole texts, German -> English
//   PATTERNS  texts with names or numbers in them: an anchored expression and a function that
//             builds the English text; parts that are texts of the mod go through tr() again,
//             names and numbers stay as they are.
// A text that is in neither stays German. Texts with " · " are translated part by part.
// Terms (UX_OVERHAUL.md §3): Sitzung session, Host host, Mitspieler player, Besuchen visit,
// Markieren mark, Hinbringen take me there, Brett board, Sicherungspunkt checkpoint.

const EXACT = {
    // Activities of a player (player bar tooltip, window)
    'baut': 'is building', 'schaut zu': 'is watching', 'synchronisiert': 'is syncing', 'lädt den Park': 'is loading the park',
    'verbindet': 'is connecting', 'im Hauptmenü': 'in the main menu', 'wartet auf den Park': 'is waiting for the park',
    'du folgst': 'you are following',
    'platziert einen Bauplan': 'is placing a blueprint', 'platziert ein Fahrgeschäft': 'is placing a ride',
    'setzt Ein- und Ausgang': 'is placing entrance and exit', 'baut eine Strecke': 'is building a track',
    'baut eine Achterbahn': 'is building a coaster', 'baut Wege': 'is building paths', 'formt das Gelände': 'is shaping the terrain',
    'bearbeitet Wasser': 'is editing water', 'baut einen Pool': 'is building a pool', 'baut eine Rutsche': 'is building a slide',
    'verwaltet Personal': 'is managing staff', 'verwaltet den Park': 'is managing the park',
    'Wege mit dem Widget bearbeiten': 'is editing paths with the widget',
    'geht als Besucher in Ich-Sicht durch den Park': 'is walking through the park in first person',
    'geht als Besucher durch den Park': 'is walking through the park as a visitor',
    'winkt': 'is waving', 'jubelt': 'is cheering', 'lacht': 'is laughing', 'ist schlecht': 'feels sick',
    'findet das super': 'loves this', 'findet das nicht gut': 'does not like this', 'isst': 'is eating', 'trinkt': 'is drinking',
    'übernimmt': 'is taking over',

    // Friends
    'offline': 'offline', 'online': 'online', 'beschäftigt': 'busy', 'abwesend': 'away',
    'hat eine offene Sitzung': 'has an open session', 'spielt Planet Coaster 2': 'is playing Planet Coaster 2',
    'ist dabei': 'is in', 'Steam-Freunde': 'Steam friends', 'Lade Freundesliste …': 'Loading friends list …',
    'Lade Freundesliste ...': 'Loading friends list ...', 'Freunde einladen': 'Invite friends', 'Freund einladen': 'Invite a friend',
    'Ohne Steam-Verbindung keine Freundesliste.': 'No friends list without a Steam connection.',
    'Gerade ist keiner deiner Steam-Freunde online.': 'None of your Steam friends is online right now.',
    'Die Einladung ist raus. Nach einer halben Minute kannst du noch einmal einladen.': 'The invitation is out. After half a minute you can invite again.',
    'Wen lädst du ein? Eingeladene warten blass im Platz.': 'Who do you invite? Invited friends wait, faded, in their slot.',
    'Wähle rechts einen Freund.': 'Choose a friend on the right.', 'Einen Steam-Freund in die Sitzung einladen.': 'Invite a Steam friend to the session.',
    'Freund wählen →': 'Choose friend →', 'keine Antwort': 'no answer', 'Noch einmal einladen': 'Invite again',
    'Einladen': 'Invite', '+ Einladen': '+ Invite', '− Einladen': '− Invite', 'Eingeladen': 'Invited', 'Beitreten': 'Join',

    // Content check
    'Inhalte werden geprüft ...': 'Checking content ...', 'Inhalte wie der Host': 'Same content as the host',
    'Die Inhalte der Mitspieler werden geprüft …': 'Checking the other players’ content …',
    'Alle haben dieselben Inhalte.': 'Everyone has the same content.', 'Inhalte': 'Content',
    'Nur gemeinsame Inhalte': 'Shared content only', 'Aus Inhalten, die nicht alle haben, wird dann nichts gebaut.': 'Content that not everyone has is then not built.',
    'DLCs der Mitspieler werden geprüft ...': 'Checking the players’ DLCs ...', 'Alle haben dieselben DLCs.': 'Everyone has the same DLCs.',
    'Alle Inhalte erlauben': 'Allow all content',

    // Steam connection
    'Die Steam-Verbindung der Mod fehlt.': 'The mod’s Steam connection is missing.',
    'PC2CoopDiagnostic.dll fehlt im Mod-Ordner oder wurde vom Virenscanner blockiert. Installiere die Mod neu und starte das Spiel neu.':
        'PC2CoopDiagnostic.dll is missing from the mod folder or was blocked by the virus scanner. Reinstall the mod and restart the game.',
    'Steam antwortet der Mod nicht.': 'Steam does not answer the mod.',
    'Starte Steam und das Spiel neu. Hilft das nicht, schick die Log-Datei aus dem Mod-Ordner.':
        'Restart Steam and the game. If that does not help, send the log file from the mod folder.',

    // Status line and session
    'Die Sitzung wird erstellt …': 'Creating the session …', 'Der Host': 'The host', 'Host': 'Host',
    'Starte eine Sitzung oder tritt einem Freund bei.': 'Start a session or join a friend.',
    'Starte eine Sitzung – Freunde treten bei und bauen mit.': 'Start a session – friends join and build with you.',
    'Alle warten, bis du einen Park öffnest.': 'Everyone is waiting for you to open a park.',
    'Alle verbunden.': 'Everyone is connected.', 'Alle sind da': 'Everyone is here',
    'Multiplayer': 'Multiplayer', 'Sitzung': 'Session', 'Deine Sitzung': 'Your session', 'Öffnen': 'Open',
    'Sitzung starten': 'Start session', 'Startet …': 'Starting …', 'Sitzung beenden': 'End session', 'Sitzung verlassen': 'Leave session',
    'Beenden': 'End', 'Verlassen': 'Leave', 'Schließen': 'Close', 'Abbrechen': 'Cancel', 'Fertig': 'Done',
    'Ja': 'Yes', 'Nein': 'No', 'Später': 'Later', 'Verstanden': 'Got it', 'Steam-Overlay': 'Steam overlay',
    'Noch keine Sitzung.': 'No session yet.',
    'Noch keine Sitzung. Starte eine, um diesen Park mit Freunden zu teilen.': 'No session yet. Start one to share this park with friends.',
    'Noch keine Sitzung. Starte eine oder tritt rechts einem Freund bei.': 'No session yet. Start one or join a friend on the right.',
    'Baut live zusammen im selben Park. Deine Steam-Freunde treten deiner Sitzung bei.': 'Build live together in the same park. Your Steam friends join your session.',
    'Mit Steam-Freunden live im selben Park bauen.': 'Build live in the same park with Steam friends.',
    'Sitzung offen': 'Session open',
    'Beendet die Sitzung für alle. Beim nächsten Mal lädst du den Park, und alle steigen wieder ein.':
        'Ends the session for everyone. Next time, you load the park and everyone joins again.',
    'Der Park läuft beim Host weiter. Du kannst wieder beitreten.': 'The park keeps running at the host’s. You can join again.',
    'Für alle beenden? Alle Mitspieler verlassen dann den Park.': 'End for everyone? All players then leave the park.',
    'Für alle beenden': 'End for everyone',

    // Main menu page
    'Wo spielen wir?': 'Where do we play?', 'Öffne einen Park – alle kommen mit.': 'Open a park – everyone comes along.',
    'Sandbox': 'Sandbox', 'Franchise': 'Franchise', 'Neuer Park oder einer deiner Parks': 'A new park or one of your parks',
    'Ein Park deiner Franchise': 'A park of your franchise', 'Freier Platz': 'Free slot', 'Spieler': 'Players',
    'möchte beitreten': 'wants to join', 'Möchte beitreten': 'Wants to join',
    'Wird geöffnet - der Park lädt gleich bei dir.': 'Opening – the park will load for you shortly.',
    'Wartet auf den Start durch den Host.': 'Waiting for the host to start.',
    'Geh ins Hauptmenü, um einen Park zu wählen.': 'Go to the main menu to choose a park.',
    'Der Host wählt noch. Sobald der Park offen ist, lädt er bei dir automatisch.': 'The host is still choosing. As soon as the park is open, it loads for you automatically.',
    'Park des Hosts': 'Host’s park', 'Der Park, den du hier öffnest, lädt bei allen.': 'The park you open here loads for everyone.',
    'Du trittst der Sitzung bei.': 'You are joining the session.', 'einen Park': 'a park',

    // Joining
    'Verbinden': 'Connect', 'Zustimmung': 'Approval', 'Park kommt': 'Park arrives', 'Park lädt': 'Park loads',
    'Verbinde mit der Sitzung …': 'Connecting to the session …', 'Warte auf die Zustimmung …': 'Waiting for approval …',
    'Beitritt wartet auf deine Bestätigung.': 'Joining is waiting for your confirmation.', 'Lade den Park …': 'Loading the park …',
    'In der Sitzung.': 'In the session.', 'Verbunden.': 'Connected.', 'Wieder beitreten': 'Rejoin', 'Erneut versuchen': 'Try again',
    'Beitritt fehlgeschlagen.': 'Joining failed.', 'einem Freund': 'a friend', 'einem Steam-Freund': 'a Steam friend',

    // Connection to the host
    'Keine Verbindung zum Host': 'No connection to the host', 'Neu synchronisieren': 'Resync', 'Ins Hauptmenü': 'To main menu',
    'Verbindung wieder da': 'Connection is back', 'Warten': 'Wait', 'Der Host ist im Hauptmenü': 'The host is in the main menu',
    'Hier warten': 'Wait here', 'Die Sitzung ist beendet': 'The session has ended', 'Weiterspielen': 'Keep playing', 'Hauptmenü': 'Main menu',

    // Requests
    'Zulassen': 'Admit', 'Ablehnen': 'Decline', 'Deine Stimme ist abgegeben – warte auf die anderen.': 'Your vote is in – wait for the others.',
    'Bau fertig, dann ist es frei.': 'Finish building, then it is free.',
    'Die Zeit ist um. Bewerte die Bauten der anderen.': 'Time is up. Rate the others’ builds.', 'Bewerten': 'Rate',

    // Window in a park
    'Planen': 'Plan', 'Verlauf': 'History', 'Einstellungen': 'Settings', 'Besuchen': 'Visit',
    'Hinbringen': 'Take me there', 'Folgen': 'Follow', 'Nicht mehr folgen': 'Stop following', 'Nicht folgen': 'Stop following',
    'Brett des Parks': 'Park board', 'Alles auf dem Brett steht auch als Marker im Park. Aufgaben brauchen keinen Ort.':
        'Everything on the board also shows as a marker in the park. Tasks need no place.',
    'Noch nichts geplant.': 'Nothing planned yet.', 'Wieder offen': 'Reopen', 'Erledigt': 'Done', 'Dafür': 'For', 'Dagegen': 'Against',
    'Löschen': 'Delete', '+ Neuer Eintrag': '+ New entry', 'Neuer Eintrag': 'New entry', 'Art': 'Type', 'Titel': 'Title',
    'Aufgabe': 'Task', 'Baugebiet': 'Build zone', 'Vorschlag': 'Proposal', 'Kommentar': 'Comment', 'Treffpunkt': 'Meeting point',
    'Name des Gebiets ("Wikingerland")': 'Name of the zone ("Viking Land")', 'Was ist zu tun?': 'What needs doing?',
    'Idee ("Wildwasserbahn am See?")': 'Idea ("Rapids ride by the lake?")', 'Auftrag ("Familienattraktion, Wikingerstil")': 'Brief ("Family ride, Viking style")',
    'Notiz (optional)': 'Note (optional)', 'Zuständig': 'Assigned', 'Größe': 'Size', 'alle': 'everyone',
    'Ort: deine letzte Markierung, sonst die Bildmitte.': 'Place: your last mark, otherwise the centre of the screen.', 'Hinzufügen': 'Add',
    'Eine Kopie des Parks beim Host. Zurückholen betrifft alle und braucht die Zustimmung aller.':
        'A copy of the park at the host’s. Restoring affects everyone and needs everyone’s consent.',
    'Meldungen des Parks': 'Park notifications', 'Gerade keine Pannen oder Probleme.': 'No breakdowns or problems right now.',
    'Ausblenden': 'Hide', 'Sicherungspunkte': 'Checkpoints', 'Noch keiner.': 'None yet.', 'Zurückholen…': 'Restore…',
    'Zurückholen': 'Restore', 'Sicherungspunkt erstellen': 'Create checkpoint', 'Sicherungspunkt zurückholen': 'Restore checkpoint',
    'Verlauf der Sitzung': 'Session history', 'Noch nichts passiert.': 'Nothing has happened yet.',
    'Wettbewerb': 'Competition', 'Ein Park, alle sehen dasselbe. Die Spielziele des Parks gelten für alle gemeinsam.':
        'One park, everyone sees the same. The park’s goals count for everyone together.',
    'Gerade kein Wettbewerb. Der Host kann einen starten.': 'No competition right now. The host can start one.',
    'Thema ("Wikinger", "Familienbahn bis 20.000 €")': 'Theme ("Vikings", "Family coaster up to 20,000 €")',
    'Bauduell: jeder baut in seinem Baugebiet (Planen: Baugebiet mit Zuständigem), danach bewertet ihr Gestaltung und Technik':
        'Build duel: everyone builds in their own build zone (Plan: build zone with someone assigned), then you rate design and engineering',
    'Koop gegen die Uhr: gemeinsam die Aufgaben vom Brett schaffen': 'Co-op against the clock: finish the board’s tasks together',
    'Bauduell': 'Build duel', 'Koop gegen die Uhr': 'Co-op against the clock',
    'Bewertung läuft': 'Rating in progress', 'Ergebnis': 'Result', 'Gestaltung': 'Design', 'Technik': 'Engineering',
    'Zeit beenden, bewerten': 'End time, rate', 'Bewertung abschließen': 'Finish rating', 'Wettbewerb schließen': 'Close competition',
    'Für dich': 'For you', 'nur auf deinem PC': 'only on your PC', 'Mitspieler in der Welt zeigen': 'Show players in the world',
    'Chat unten links einblenden': 'Show chat bottom left',
    // Problem report (FEAT-223)
    'Problembericht erstellen': 'Create problem report', 'Bericht wird erstellt …': 'Creating the report …',
    'Auf dem Desktop gespeichert:': 'Saved on your desktop:',
    'Klappt etwas nicht? Schick den Bericht dem Entwickler. Steam-IDs und Namen sind darin ersetzt.':
        'Something not working? Send the report to the developer. Steam IDs and names are replaced in it.',
    'Der Desktop-Ordner wurde nicht gefunden.': 'The desktop folder was not found.',
    'Die Datei ließ sich nicht schreiben.': 'The file could not be written.',
    'Es gibt noch keine Log-Datei.': 'There is no log file yet.', 'Unbekannter Fehler.': 'Unknown error.',
    'Keine Antwort von der Mod-DLL.': 'No answer from the mod DLL.', 'Die Mod-DLL ist nicht geladen.': 'The mod DLL is not loaded.',
    'Neue Nachrichten und was Mitspieler tun, kurz unten links. Enter öffnet den Chat trotzdem.':
        'New messages and what players do, briefly at the bottom left. Enter still opens the chat.',
    'Name, Blickrichtung, gehaltenes Objekt und Sperr-Färbung': 'Name, view direction, held object and lock colouring',
    'Regeln dieser Sitzung': 'Rules of this session', 'Schnellwahl': 'Preset', 'Eigene': 'Custom',
    'Locker': 'Relaxed', 'Geordnet': 'Orderly', 'Nur bauen': 'Build only', 'Locker zusammen bauen': 'Relaxed building together',
    'Setzt alle Regeln auf einmal. Locker – alle dürfen alles. Geordnet – Tempo nur der Host, fremde Bauten erst fragen. Nur bauen – dazu ohne Besucher-Modus.':
        'Sets all rules at once. Relaxed – everyone may do everything. Orderly – speed host only, ask before demolishing others’ builds. Build only – also without visitor mode.',
    'Nur der Host ändert Regeln.': 'Only the host changes rules.',
    'Spieltempo und Pause': 'Game speed and pause', 'nur der Host': 'host only', 'Wer das Spieltempo ändern und pausieren darf.': 'Who may change the game speed and pause.',
    'Fremde Bauten abreißen': 'Demolish others’ builds', 'erlaubt': 'allowed', 'erst fragen': 'ask first', 'aus': 'off',
    'Ob Mitspieler abreißen dürfen, was ein anderer gebaut hat, oder erst fragen.': 'Whether players may demolish what someone else built, or must ask first.',
    'Besucher-Modus': 'Visitor mode', 'Ob Mitspieler als Besucher durch den Park gehen dürfen.': 'Whether players may walk through the park as visitors.',
    'Du bist Host. Der Park läuft bei dir. Du legst die Regeln fest, bestätigst Beitrittsanfragen und erstellst Sicherungspunkte.':
        'You are the host. The park runs on your PC. You set the rules, approve join requests and create checkpoints.',
    'Du baust frei mit. Was jemand anderes gerade bearbeitet, ist für dich gesperrt. Markiere es und frag nach der Übernahme. Rückgängig betrifft nur deine eigenen Schritte.':
        'You build freely. What someone else is editing right now is locked for you. Mark it and ask to take over. Undo only affects your own steps.',
    'Nur der Host pausiert und ändert das Spieltempo. So ist es in dieser Sitzung eingestellt.': 'Only the host pauses and changes the game speed. That is how this session is set up.',
    'Rückgängig nimmt nur deinen eigenen letzten Schritt zurück. Stammt der neueste von einem Mitspieler, geht es nicht.':
        'Undo only takes back your own last step. If the latest one is another player’s, it does not work.',

    // Mark menu, chat, hints
    'Testfahrt mit allen': 'Test ride with everyone', 'Mitfahren': 'Ride along', 'Markierung': 'Mark', 'Markieren': 'Mark',
    'Chat': 'Chat', 'Noch keine Nachrichten.': 'No messages yet.', 'Nachricht an alle': 'Message to everyone', 'Nachricht': 'Message', 'Senden': 'Send',

    // Visiting
    'Kaufen': 'Buy', 'Liste zu': 'Close list', 'Fahrgeschäfte': 'Rides', 'Laufen': 'Walk', 'Springen': 'Jump', 'Strg': 'Ctrl',
    'Ducken': 'Crouch', 'Lampe': 'Torch', 'Shop': 'Shop', 'Emotes': 'Emotes', 'Ansicht': 'View', 'Zurück': 'Back', 'Umsehen': 'Look',
    'Umschalt': 'Shift', 'Rennen': 'Run', 'Benutzen': 'Use', 'Ich-Sicht': 'First person', 'Einkaufen': 'Shop',
    'Noch keine Fahrgeschäfte im Park.': 'No rides in the park yet.', 'noch nicht getestet': 'not tested yet',
    'noch keine Bewertung': 'no rating yet', 'Deine Wertung': 'Your rating', 'Fahrgeschäfte – nächstes zuerst': 'Rides – nearest first',
    'Winken': 'Wave', 'Jubeln': 'Cheer', 'Lachen': 'Laugh', 'Super': 'Great', 'Naja': 'Meh', 'Übel': 'Sick', 'T loslassen': 'Release T',
    'Achterbahn': 'Coaster', 'Rutsche': 'Slide', 'Bahn': 'Tracked ride', 'Fahrgeschäft': 'Ride',
    'nicht gefunden': 'not found', 'der Shop verkauft gerade nichts': 'the shop sells nothing right now', 'gerade nicht': 'not right now',
    'kein Shop vor dir': 'no shop in front of you', 'geh an einen Eingang oder Shop': 'go to an entrance or shop',
    'das Spiel lässt das gerade nicht zu': 'the game does not allow that right now',
    'Diesen Shop gibt es beim Host nicht': 'This shop does not exist at the host’s', 'Das gibt es dort nicht mehr': 'That is no longer sold there',
    'Der Shop ist geschlossen': 'The shop is closed', 'Dieser Shop ist noch nicht mit dem Host abgeglichen': 'This shop is not synced with the host yet',
    'Kaufen geht gerade nicht': 'You can’t buy that right now',
    'Der Host hat den Besucher-Modus für diese Sitzung ausgeschaltet.': 'The host turned off visitor mode for this session.',

    // Toasts and log lines without names (Lua)
    'Eine Änderung konnte hier nicht übernommen werden.': 'A change could not be applied here.',
    'Rückgängig geht nur für deinen eigenen letzten Schritt - der neueste hier stammt von einem Mitspieler.':
        'Undo only works for your own last step – the latest one here is another player’s.',
    'Nur der Host ändert das Spieltempo (Sitzungsregel).': 'Only the host changes the game speed (session rule).',
    'Die Verbindung war unterbrochen - der Park des Hosts wird neu geladen.': 'The connection was lost – the host’s park is loading again.',
    'Der Host hat deinen Beitritt abgelehnt.': 'The host declined your request to join.',
    'Der Host hat einen anderen Park geöffnet - er wird geladen.': 'The host opened another park – it is loading.',
    'Der Host dieser Sitzung ist nicht in deiner Steam-Freundesliste. Beitritt abgebrochen.':
        'The host of this session is not on your Steam friends list. Joining cancelled.',
    'Deine Sitzung läuft weiter. Öffne einen Park - alle laden ihn dann mit.': 'Your session is still running. Open a park – everyone loads it with you.',
    'Der Park des Hosts konnte nicht geladen werden.': 'The host’s park could not be loaded.',
    'Diese Einladung ist abgelaufen, die Sitzung gibt es nicht mehr. Lass dich neu einladen.':
        'This invitation has expired; the session no longer exists. Ask for a new invitation.',
    'Die Sitzung ist voll.': 'The session is full.', 'Die Sitzung ist nur für Steam-Freunde des Hosts.': 'The session is for the host’s Steam friends only.',
    'Host hat die Sitzung beendet': 'The host ended the session', 'Du bist bereits in dieser Sitzung.': 'You are already in this session.',
    'Einladung konnte nicht gesendet werden': 'The invitation could not be sent',
    'Die Zeit ist um. Jetzt bewertet ihr die Bauten der anderen.': 'Time is up. Now rate the others’ builds.', 'Die Zeit ist um.': 'Time is up.',
    'Die Bewertung ist abgeschlossen, das Ergebnis steht beim Wettbewerb.': 'Rating is finished; the result is shown with the competition.',
    'Nichts Neues - der Park ist wie beim letzten Mal.': 'Nothing new – the park is as it was last time.',
    'Sicherungspunkt konnte nicht gespeichert werden.': 'The checkpoint could not be saved.',
    'Tipp: Markieren zeigt allen eine Stelle und bietet Aktionen dafür an (Kommentar, Testfahrt, Übernahme). Alles Weitere öffnet der runde Knopf „Multiplayer“ links oben.':
        'Tip: Mark shows everyone a spot and offers actions for it (comment, test ride, takeover). The round “Multiplayer” button top left opens everything else.',
    'Steam hat nicht geantwortet. Versuch es noch einmal.': 'Steam did not answer. Try again.',
    'Keine Stelle gefunden. Markiere zuerst eine.': 'No spot found. Mark one first.',
    'Ein Wettbewerb läuft schon, oder es fehlen Angaben.': 'A competition is already running, or details are missing.',
    'Ein Mitspieler': 'A player', 'Meldung': 'Notification',
    'Panne': 'Breakdown', 'Wartung fällig': 'Maintenance due', 'Wartung überfällig': 'Maintenance overdue',
    'Gäste eingeschlossen': 'Guests trapped', 'Gäste stecken fest': 'Guests stuck', 'Blitzeinschlag': 'Lightning strike',
    'Parade kaputt': 'Parade broken', 'Wenig Fahrgäste': 'Few riders', 'Kein Strom': 'No power', 'Nicht getestet': 'Not tested',
    'Spieltempo: alle': 'Game speed: everyone', 'Spieltempo: nur der Host': 'Game speed: host only',
    'Besucher-Modus: erlaubt': 'Visitor mode: allowed', 'Besucher-Modus: aus': 'Visitor mode: off',
    'Fremde Bauten abreißen: erlaubt': 'Demolish others’ builds: allowed', 'Fremde Bauten abreißen: erst fragen': 'Demolish others’ builds: ask first',
    'hier nicht möglich (z. B. außerhalb der Parkgrenze)': 'not possible here (e.g. outside the park boundary)',
    'beim Host nicht möglich': 'not possible at the host’s',
    'Gespeicherter Park': 'Saved park', 'Neuer Sandbox-Park': 'New sandbox park', 'Park im Franchise-Menü': 'Park in the franchise menu',
    'Gemäßigt': 'Temperate', 'Mediterran': 'Mediterranean', 'Taiga': 'Taiga', 'Tropisch': 'Tropical',
};

// Number written the German way ("12.345") the English way ("12,345").
const num = (text) => String(text).replace(/\./g, ',');

// The translator CoopLayer.js uses while the game is not German: German text -> English text.
// Results are kept (the layer draws often); a text that is not known comes back as it is.
export function createTranslator() {
    const cache = new Map();
    const tables = {};
    const tr = (text) => {
        if (typeof text !== 'string' || text.length < 2) return text;
        const known = cache.get(text);
        if (known !== undefined) return known;
        let out = tables.exact.get(text);
        if (out === undefined) {
            out = text;
            for (const [pattern, build] of tables.patterns) {
                const m = pattern.exec(text);
                if (m) { try { out = build(...m); } catch (error) { out = text; } break; }
            }
            if (out === text && text.indexOf(' · ') > 0) out = text.split(' · ').map(tr).join(' · ');
        }
        if (cache.size > 3000) cache.clear();
        cache.set(text, out);
        return out;
    };
    Object.assign(tables, englishTexts(tr));
    return tr;
}

function englishTexts(tr) {
    const named = (who) => (who === 'Der Host' ? 'The host' : who === 'Ein Mitspieler' ? 'A player' : who);
    const VERB = { platziert: 'placed', bearbeitet: 'edited', gelöscht: 'deleted' };
    const PATTERNS = [
        // Activities with a name or a number
        [/^empfängt den Park (\d+) %$/, (m, n) => 'is receiving the park ' + n + ' %'],
        [/^hält (.+)$/, (m, what) => 'is holding ' + what],
        [/^fährt (.+)$/, (m, ride) => 'is riding ' + ride],
        [/^Geld ([\d.]+)$/, (m, n) => 'Money ' + num(n)],
        [/^Geld unbegrenzt$/, () => 'Unlimited money'],
        [/^([\d.]+) Besucher$/, (m, n) => num(n) + ' guests'],
        [/^fehlt: (.+)$/, (m, what) => 'missing: ' + what],
        [/^Mods fehlen: (.+)$/, (m, what) => 'mods missing: ' + what],
        [/^weitere Mods: (.+)$/, (m, what) => 'other mods: ' + what],

        // Player bar and window
        [/^(.+) – (.+) · Klicken zum Folgen$/, (m, who, act) => who + ' – ' + tr(act) + ' · Click to follow'],
        [/^(.+) – (.+) · Klicken beendet das Folgen$/, (m, who, act) => who + ' – ' + tr(act) + ' · Click to stop following'],
        [/^(.+) \(du\)$/, (m, who) => who + ' (you)'],
        [/^Sitzung von (.+)$/, (m, who) => who + '’s session'],
        [/^(\d+) \/ (\d+) Spieler$/, (m, a, b) => a + ' / ' + b + ' players'],
        [/^Spieler {2}(\d+) \/ (\d+)$/, (m, a, b) => 'Players  ' + a + ' / ' + b],
        [/^(\d+) dafür, (\d+) dagegen$/, (m, a, b) => a + ' for, ' + b + ' against'],
        [/^Zuständig – (.+)\. Klicken wechselt zu (.+)\.$/, (m, a, b) => 'Assigned – ' + tr(a) + '. Click to switch to ' + tr(b) + '.'],
        [/^(\d+) Min\.$/, (m, n) => n + ' min'],
        [/^Thema: (.+)$/, (m, t) => 'Theme: ' + t],
        [/^noch (\d+:\d\d)$/, (m, t) => t + ' left'],
        [/^Gestaltung ([\d.]+)$/, (m, n) => 'Design ' + n],
        [/^Technik ([\d.]+) \((\d+) Stimmen?\)$/, (m, n, v) => 'Engineering ' + n + ' (' + v + (v === '1' ? ' vote)' : ' votes)')],
        [/^Nicht alle haben: (.+)\. Daraus wird nichts gebaut\.$/, (m, what) => 'Not everyone has: ' + what + '. Nothing is built from it.'],
        [/^Nicht alle haben: (.+)\. Wird trotzdem gebaut\.$/, (m, what) => 'Not everyone has: ' + what + '. It is built anyway.'],
        [/^Nicht alle haben: (.+) - daraus wird nichts gebaut\.$/, (m, what) => 'Not everyone has: ' + what + ' – nothing is built from it.'],
        [/^Nicht alle haben: (.+) - wird trotzdem gebaut\.$/, (m, what) => 'Not everyone has: ' + what + ' – it is built anyway.'],
        [/^(.+): (\d+) platziert, (\d+) bearbeitet, (\d+) gelöscht$/, (m, who, a, b, c) => who + ': ' + a + ' placed, ' + b + ' edited, ' + c + ' deleted'],
        [/^(.+) hat gewählt$/, (m, who) => named(who) + ' has chosen'],
        [/^Die Sitzung ist im Park (.*)\.$/, (m, park) => 'The session is in the park ' + park + '.'],
        [/^(.+) wählt den Park\. Er lädt bei dir von selbst\.$/, (m, who) => named(who) + ' is choosing the park. It loads for you by itself.'],
        [/^Du trittst der Sitzung von (.+) bei\.$/, (m, who) => 'You are joining ' + who + '’s session.'],
        [/^Der Park, den du hier öffnest, lädt bei allen in deiner Sitzung( \((\d+) Mitspieler\))?\.$/,
            (m, all, n) => 'The park you open here loads for everyone in your session' + (n ? ' (' + n + (n === '1' ? ' player)' : ' players)') : '') + '.'],
        [/^Schritt (\d) von 4$/, (m, n) => 'Step ' + n + ' of 4'],
        [/^Vorschlag zu (.+)$/, (m, ride) => 'Suggestion for ' + ride],
        [/^Du fährst (.+)$/, (m, ride) => 'You are riding ' + ride],
        [/^Spaß ([\d.,-]+)$/, (m, n) => 'Excitement ' + n],
        [/^Angst ([\d.,-]+)$/, (m, n) => 'Fear ' + n],
        [/^Übelkeit ([\d.,-]+)$/, (m, n) => 'Nausea ' + n],
        [/^(\d+) warten$/, (m, n) => n + ' waiting'],
        [/^1 von (\d+)$/, (m, n) => '1 of ' + n],
        [/^Übernahme von (.+)$/, (m, who) => 'Take over from ' + who],
        [/^Gerade nicht verfügbar – (.+)$/, (m, why) => 'Not available right now – ' + tr(why)],
        [/^(.+) hat eine Sitzung – beitreten$/, (m, who) => who + ' has a session – join'],

        // Status line
        [/^(.+) wählt im Hauptmenü einen Park\.?$/, (m, who, dot) => named(who) + ' is choosing a park in the main menu' + (m.endsWith('.') ? '.' : '')],
        [/^(.+) ist nicht mehr in der Sitzung\.( Der Park bleibt bei dir offen, du kannst allein weiterspielen\.)?$/,
            (m, who, rest) => named(who) + ' is no longer in the session.' + (rest ? ' The park stays open for you, and you can keep playing alone.' : '')],
        [/^Nicht mehr synchron: (.+) - "Neu synchronisieren" lädt den Park des Hosts erneut\.$/,
            (m, why) => 'Out of sync: ' + why + ' – "Resync" loads the host’s park again.'],
        [/^Nicht (mehr )?synchron: (.+)$/, (m, more, why) => 'Out of sync: ' + why],
        [/^(.+) öffnet (.+) – gleich lädt er bei allen\.$/, (m, who, park) => named(who) + ' is opening ' + tr(park) + ' – it will load for everyone shortly.'],
        [/^Ausgewählt: (.+)\.$/, (m, what) => 'Selected: ' + tr(what) + '.'],
        [/^(.+) hat gewählt: (.+)\.$/, (m, who, what) => named(who) + ' chose: ' + tr(what) + '.'],
        [/^(.+) wählt gerade einen Park …$/, (m, who) => named(who) + ' is choosing a park …'],
        [/^(.+) laden den Park \.\.\.$/, (m, who) => who + ' are loading the park ...'],
        [/^(.+) lädt den Park \.\.\.$/, (m, who) => who + ' is loading the park ...'],
        [/^Alle verbunden - (.+)\.$/, (m, park) => 'Everyone is connected – ' + park + '.'],
        [/^(.+) antwortet seit einer halben Minute nicht\. Die Verbindung kann gleich wiederkommen\.$/,
            (m, who) => named(who) + ' has not answered for half a minute. The connection may come back any moment.'],
        [/^(.+) wählt einen Park, der dann auch bei dir lädt\. Was du bis dahin hier baust, sehen die anderen nicht\.$/,
            (m, who) => named(who) + ' is choosing a park, which then loads for you too. What you build here until then, the others will not see.'],

        // Joining
        [/^Verbinde mit der Sitzung von (.+) …$/, (m, who) => 'Connecting to ' + who + '’s session …'],
        [/^Warte auf die Zustimmung von (.+) …$/, (m, who) => 'Waiting for ' + who + '’s approval …'],
        [/^Beitritt bei (.+) wartet auf deine Bestätigung\.$/, (m, who) => 'Joining ' + who + ' is waiting for your confirmation.'],
        [/^Empfange den Park von (.+) … (\d+) %$/, (m, who, n) => 'Receiving ' + who + '’s park … ' + n + ' %'],
        [/^Empfange den Park … (\d+) %$/, (m, n) => 'Receiving the park … ' + n + ' %'],
        [/^Lade den Park von (.+) …$/, (m, who) => 'Loading ' + who + '’s park …'],
        [/^In der Sitzung von (.+)\.$/, (m, who) => 'In ' + who + '’s session.'],
        [/^Verbunden von (.+)\.$/, (m, who) => 'Connected to ' + who + '.'],
        [/^Du warst eben noch in der Sitzung von (.+)\. Wieder beitreten\?$/, (m, who) => 'You were just in ' + tr(who) + '’s session. Join again?'],
        [/^Der Sitzung von (.+) beitreten\? Dein Spiel lädt dann den Park des Hosts\.$/, (m, who) => 'Join ' + tr(who) + '’s session? Your game then loads the host’s park.'],

        // Requests and dialogs
        [/^(.+) möchte beitreten\.$/, (m, who) => who + ' would like to join.'],
        [/^Abstimmung von (.+?): (.+)$/, (m, who, what) => 'Vote by ' + who + ': ' + tr(what)],
        [/^(.+) lädt zur Testfahrt auf (.+) ein\.?$/, (m, who, ride) => who + ' invites everyone to a test ride on ' + ride + (m.endsWith('.') ? '.' : '')],
        [/^(.+) möchte bei „(.+)“ weitermachen\.$/, (m, who, what) => who + ' would like to carry on with “' + what + '”.'],
        [/^Park auf „(.+)“ zurücksetzen\? Was seitdem gebaut wurde, ist dann weg\.( Erst stimmen alle ab, dann laden alle den Park neu\.)?$/,
            (m, cp, vote) => 'Reset the park to “' + tr(cp) + '”? Everything built since then will be gone.' + (vote ? ' Everyone votes first, then everyone reloads the park.' : '')],
        [/^Park auf (.+) zurücksetzen\? Alle laden den Park dann neu\.$/, (m, cp) => 'Reset the park to ' + tr(cp) + '? Everyone then reloads the park.'],
        [/^Stand (\d+)$/, (m, n) => 'Checkpoint ' + n],

        // The session's log and toasts from Lua (names first)
        [/^(.+) hat (\d+) Objekte (platziert|bearbeitet|gelöscht)$/, (m, who, n, verb) => named(who) + ' ' + VERB[verb] + ' ' + n + ' objects'],
        [/^(.+) hat ein Fahrgeschäft abgerissen$/, (m, who) => named(who) + ' demolished a ride'],
        [/^(.+) hat eine Achterbahn gebaut$/, (m, who) => named(who) + ' built a coaster'],
        [/^(.+) hat eine Achterbahn geändert$/, (m, who) => named(who) + ' changed a coaster'],
        [/^(.+) hat das Spiel pausiert$/, (m, who) => named(who) + ' paused the game'],
        [/^(.+) lässt das Spiel laufen \((x\d)\)$/, (m, who, speed) => named(who) + ' lets the game run (' + speed + ')'],
        [/^(.+) hat einen Sicherungspunkt erstellt \(Stand (\d+)\)$/, (m, who, n) => named(who) + ' created checkpoint ' + n],
        [/^(.+) hat erledigt: (.+)$/, (m, who, what) => named(who) + ' completed: ' + what],
        [/^(.+) hat die Sitzung verlassen$/, (m, who) => who + ' left the session'],
        [/^(.+) ist der Sitzung beigetreten$/, (m, who) => who + ' joined the session'],
        [/^(.+) tritt bei und lädt den Park$/, (m, who) => who + ' is joining and loading the park'],
        [/^(.+) ist beigetreten$/, (m, who) => who + ' joined'],
        [/^(.+) zeigt auf etwas$/, (m, who) => who + ' is pointing at something'],
        [/^(.+) fragt (.+) nach Übernahme$/, (m, a, b) => named(a) + ' asks ' + named(b) + ' to hand over'],
        [/^(.+) bewertet (.+) mit (\d)\/5(: (.*))?$/, (m, who, ride, n, c, text) => who + ' rates ' + ride + ' ' + n + '/5' + (c ? ': ' + text : '')],
        [/^(.+): Änderung verworfen, (.+) war schneller$/, (m, a, b) => named(a) + ': change discarded, ' + named(b) + ' was faster'],
        [/^Das hat (.+) gebaut - frag erst nach \(Sitzungsregel\)\.$/, (m, who) => named(who) + ' built this – ask first (session rule).'],
        [/^(.+) hat das Objekt geändert, das du gerade bearbeitet hast\.$/, (m, who) => named(who) + ' changed the object you were editing.'],
        [/^(.+) hat das gerade geändert$/, (m, who) => named(who) + ' just changed this'],
        [/^Zurückgenommen: (.+) baut hier gerade\.$/, (m, who) => 'Undone: ' + named(who) + ' is building here.'],
        [/^Zurückgenommen: (.+) war bei diesem Objekt schneller\.$/, (m, who) => 'Undone: ' + named(who) + ' was faster with this object.'],
        [/^(.+) baut hier gerade\. Dein Werkzeug wurde zurückgesetzt\.$/, (m, who) => named(who) + ' is building here. Your tool was reset.'],
        [/^(.+) baut hier gerade$/, (m, who) => named(who) + ' is building here'],
        [/^(.+) war schneller$/, (m, who) => named(who) + ' was faster'],
        [/^„(.+)“ wird noch nicht an die anderen übertragen\.$/, (m, what) => '“' + what + '” is not sent to the others yet.'],
        [/^Bericht ging nicht: (.+)$/, (m, why) => 'The report did not work: ' + tr(why)],
        [/^(.+) hat PC2Coop (\S+), du (\S+)\. Ihr braucht dieselbe Version: PC2Coop-Setup → „Nach Update suchen“\.$/, (m, who, a, b) => who + ' has PC2Coop ' + a + ', you have ' + b + '. You need the same version: PC2Coop Setup → “Check for update”.'],
        [/^(.+) hat Spielversion (\S+), du (\S+)\. Beide aktualisieren das Spiel in Steam\.$/, (m, who, a, b) => who + ' has game version ' + a + ', you have ' + b + '. Both of you update the game in Steam.'],
        [/^Der Host hat PC2Coop (\S+), du (\S+)\. Ihr braucht dieselbe Version: Spiel beenden, PC2Coop-Setup → „Nach Update suchen“\.$/, (m, a, b) => 'The host has PC2Coop ' + a + ', you have ' + b + '. You need the same version: quit the game, PC2Coop Setup → “Check for update”.'],
        [/^Der Host hat Spielversion (\S+), du (\S+)\. Aktualisiert beide Planet Coaster 2 in Steam\.$/, (m, a, b) => 'The host has game version ' + a + ', you have ' + b + '. Both of you update Planet Coaster 2 in Steam.'],
        [/^(.+) war kurz weg - der Park wird neu übertragen$/, (m, who) => who + ' was gone for a moment – the park is sent again'],
        [/^(.+) ist nicht mehr synchron$/, (m, who) => who + ' is out of sync'],
        [/^(.+) konnte den Park nicht laden$/, (m, who) => who + ' could not load the park'],
        [/^Du bist weiter in der Sitzung von (.+)\. Der Host wählt einen Park\.$/, (m, who) => 'You are still in ' + who + '’s session. The host is choosing a park.'],
        [/^Bereit: du baust jetzt im Park von (.+)\.$/, (m, who) => 'Ready: you are now building in ' + who + '’s park.'],
        [/^Beitritt nicht möglich \(Steam-Code (.+)\)\. Lass dich neu einladen\.$/, (m, code) => 'Can’t join (Steam code ' + code + '). Ask for a new invitation.'],
        [/^Die Verbindung zu (.+) hängt\. Tritt neu bei\.$/, (m, who) => 'The connection to ' + who + ' is stuck. Join again.'],
        [/^Die Sitzung konnte nicht erstellt werden \(Steam-Code (.+)\)\.$/, (m, code) => 'The session could not be created (Steam code ' + code + ').'],
        [/^Die übertragene Park-Datei ist ungültig \((.+)\)\.$/, (m, why) => 'The park file that arrived is invalid (' + why + ').'],
        [/^Nicht gebaut: das Objekt ist aus einem DLC, das (.+) nicht hat\.$/, (m, who) => 'Not built: the object is from a DLC that ' + who + ' does not have.'],
        [/^(.+) wurde nicht zugelassen$/, (m, who) => who + ' was not admitted'],
        [/^Alle einverstanden: zurück auf (.+)$/, (m, cp) => 'Everyone agreed: back to ' + tr(cp)],
        [/^Änderung von (.+) zurückgenommen: (.+)$/, (m, who, why) => named(who) + '’s change undone: ' + tr(why)],
        [/^Objekt von (.+) entfernt: (.+)$/, (m, who, why) => named(who) + '’s object removed: ' + tr(why)],
        [/^Mitfahren geht gerade nicht \((.+)\)$/, (m, why) => 'Can’t ride along right now (' + tr(why) + ')'],
        [/^Der Park konnte nicht geöffnet werden \((.+)\)\.$/, (m, why) => 'The park could not be opened (' + why + ').'],
        [/^Regeln( "(.+)")?: (.+)$/, (m, l, label, list) => 'Rules' + (label ? ' "' + tr(label) + '"' : '') + ': ' + list.split(', ').map(tr).join(', ')],
        [/^(Panne|Wartung fällig|Wartung überfällig|Gäste eingeschlossen|Gäste stecken fest|Blitzeinschlag|Parade kaputt|Wenig Fahrgäste|Kein Strom|Nicht getestet|Meldung): (.+)$/,
            (m, word, name) => tr(word) + ': ' + name],
        // "Since your last visit" and its parts
        [/^Seit deinem letzten Besuch: (.+)$/, (m, parts) => 'Since your last visit: ' + parts.split('; ').map(tr).join('; ')],
        [/^(\d+) neue Fahrgeschäfte \((.+)\)$/, (m, n, list) => n + ' new rides (' + list + ')'],
        [/^(\d+) abgerissen \((.+)\)$/, (m, n, list) => n + ' demolished (' + list + ')'],
        [/^Kasse ([+-]?\d+) EUR$/, (m, n) => 'Cash ' + n + ' EUR'],
        [/^Aufgaben: (\d+) erledigt, (\d+) offen$/, (m, a, b) => 'Tasks: ' + a + ' done, ' + b + ' open'],
        [/^offene Meldung: (.+)$/, (m, what) => 'open notification: ' + tr(what)],
        [/^(.+) kauft (.+) \((.+)\)$/, (m, who, item, price) => named(who) + ' buys ' + item + ' (' + price + ')'],
        [/^Gekauft: (.+) \((.+)\)$/, (m, item, price) => 'Bought: ' + item + ' (' + price + ')'],
        // Single objects last: "<name> hat <object> platziert" (the object's name stays)
        [/^(.+?) hat (.+) (platziert|bearbeitet|gelöscht)$/, (m, who, what, verb) => named(who) + ' ' + VERB[verb] + ' ' + what],
        // "<name> – <activity>" (own entry in the player bar): the activity, when it is known.
        [/^(.+) – ([^–]+)$/, (m, who, act) => { const t = tr(act); return t === act ? m : who + ' – ' + t; }],
    ];
    return { exact: new Map(Object.entries(EXACT)), patterns: PATTERNS };
}
