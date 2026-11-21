PC2Coop 1.14.0 - build live together in Planet Coaster 2, over Steam

The mod speaks English when Planet Coaster 2 does not run in German. (The full manual,
PC2Coop-LIESMICH.txt / LIESMICH.txt, is in German.)

Install (every player, once)
0. Install ACSE (mod loader for Planet Coaster 2) from Nexus Mods if you do not have it yet.
   It is not part of this package; without ACSE, PC2Coop does not start.
1. Quit Planet Coaster 2.
2. If this ZIP has INSTALL.cmd (GitHub package): unpack it into a folder of its own and
   double-click INSTALL.cmd. It finds the Steam folder by itself; if not:
   INSTALL.cmd -GameDir "D:\SteamLibrary\steamapps\common\Planet Coaster 2"
   If this ZIP only has a "Win64" folder (Nexus package): copy that folder into the game
   folder (Steam: right-click Planet Coaster 2 -> Manage -> Browse local files) and replace
   the old files. Afterwards Win64\ovldata\PC2CoopProbe holds Main.ovl, Manifest.xml and
   PC2CoopDiagnostic.dll.
Windows note: if SmartScreen or your virus scanner flags PC2CoopDiagnostic.dll, that is
because it is not signed.

Update
GitHub package: quit the game, double-click UPDATE.cmd. Nexus package: copy the new version
the same way. Everyone in a session needs the same mod version and the same game version;
the host turns others away and tells you who has to update.

Play
1. Host: main menu, tile "Multiplayer" -> "Start session".
2. Invite friends: click a free slot "+ Invite" and choose the friend (or "Steam overlay").
   Friends accept the invitation in Steam, or see "has an open session" on their own
   "Multiplayer" page and click "Join". Joining shows four steps; "Cancel" works until the
   park loads.
3. Host: open the park on the game's own pages - the tiles "Sandbox" (a new park or one of
   yours) or "Franchise" on the "Multiplayer" page. The park is sent to everyone and loads
   for them.
4. Build together. Top right: who is in the park (click someone to follow their camera).
   Bottom left: chat and what happens; Enter opens the chat input. The round "Multiplayer"
   button top left opens the window: Players, Plan (the park's board), History, Settings
   (rules, content, competition).
5. A short middle click marks a spot for everyone and opens a radial menu for it (test ride,
   ride along, ask to take over, comment, proposal, build zone, meeting point).
6. "Visit" (in the window) walks you through the park as a guest: WASD, Shift to run, E to
   use, F for the rides list, T for emotes, V for the view, Tab to go back.

You need: Steam friendship with the host (sessions are for the host's Steam friends only).
No Frontier account and no franchise needed.

Problems
Log file: <game folder>\Win64\ovldata\PC2CoopProbe\pc2coop-diagnostic-<number>.log
(one per game start; send the newest one, sorted by date). It contains the Steam names and
Steam IDs of the players in the session - send it privately, not in a public channel.

Privacy and limits
- Exactly two files arrive over the network: the host's park (pc2coop-join.bin/.trn in the
  game folder), only from the session's host; they are deleted after loading. Nothing else a
  player sends is saved or run.
- No server of our own: the connection runs over Steam. No administrator rights.
- In a session, everyone sees your DLC list, the folder names of your other mods and your
  Steam profile picture.
- Whoever plays with you may build and therefore also demolish - only invite people you
  trust with your park.

Remove
Quit the game. GitHub package: double-click UNINSTALL.cmd. Nexus package: delete the folder
Win64\ovldata\PC2CoopProbe in the game folder.

License and source
Own code: MIT (LICENSE-PC2Coop.txt). Source: https://github.com/istmirRegal/pc2coop
ACSE is not included (own download, own license). No game files, saves or third-party assets.
