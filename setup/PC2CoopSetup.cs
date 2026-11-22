// Original PC2Coop code, MIT. PC2Coop-Setup.exe: installs, updates and removes the mod.
//
// One window for players (German when Windows is German, English otherwise) and a command
// line for tests. It copies only the files listed in payload-manifest.json into
// <game>\Win64\ovldata\PC2CoopProbe, checks every SHA-256, keeps backups and rolls back on an
// error. Updates download the release ZIP from GitHub, check its SHA-256 and copy the mod
// files out of it; a downloaded program is never started. ACSE is never touched.
using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Globalization;
using System.IO;
using System.IO.Compression;
using System.Net;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows.Forms;
using Microsoft.Win32;

[assembly: AssemblyTitle("PC2Coop Setup")]
[assembly: AssemblyDescription("Installs, updates and removes the PC2Coop co-op mod for Planet Coaster 2")]
[assembly: AssemblyCompany("PC2Coop open source project")]
[assembly: AssemblyProduct("PC2Coop")]
[assembly: AssemblyCopyright("MIT License - source: github.com/istmirRegal/pc2coop")]
[assembly: AssemblyVersion(BuildInfo.AssemblyVersion)]
[assembly: AssemblyFileVersion(BuildInfo.AssemblyVersion)]
[assembly: AssemblyInformationalVersion(BuildInfo.Version)]

namespace PC2CoopSetup
{
    static class T
    {
        public static bool German = CultureInfo.CurrentUICulture.TwoLetterISOLanguageName == "de";
        public static string S(string de, string en) { return German ? de : en; }
    }

    static class Codes
    {
        public const int Ok = 0, Error = 1, GameRunning = 2, AcseMissing = 3, Vortex = 4, NoGame = 5,
            NoRights = 6, NotUnpacked = 7, UpToDate = 10;
    }

    class SetupException : Exception
    {
        public readonly int Code;
        public SetupException(int code, string message) : base(message) { Code = code; }
    }

    class GameState
    {
        public string Game;
        public bool Acse;
        public string AcseVersion;
        public bool Installed;
        public string InstalledVersion;
        public bool Vortex;
    }

    class ReleaseInfo
    {
        public string Version, ZipUrl, ShaUrl, Notes;
    }

    static class Core
    {
        public const string SteamAppId = "2688950";
        public const string AcsePage = "https://www.nexusmods.com/planetcoaster2/mods/1";
        public const string JournalName = ".pc2coop-alpha-install.json"; // same name as install.ps1 (<= 2.0.0)
        static readonly Regex SafeRelative = new Regex(@"^PC2CoopProbe/[A-Za-z0-9_.-]+$");
        static readonly string[] ModFiles = { "Main.ovl", "Manifest.xml", "PC2CoopDiagnostic.dll" };

        public static string Ovldata(string game) { return Path.Combine(game, "Win64", "ovldata"); }

        // The Steam game keeps PlanetCoaster2.exe in its main folder; Win64 is accepted as well.
        public static string GameExe(string folder)
        {
            if (string.IsNullOrEmpty(folder)) return null;
            foreach (var candidate in new[] { Path.Combine(folder, "PlanetCoaster2.exe"), Path.Combine(folder, "Win64", "PlanetCoaster2.exe") })
                if (File.Exists(candidate)) return candidate;
            return null;
        }

        public static bool IsGameDir(string folder)
        {
            try { return GameExe(folder) != null && Directory.Exists(Ovldata(folder)); }
            catch { return false; }
        }

        // The game folder, also when the player picked Win64 or ovldata instead.
        public static string NormalizeGameDir(string folder)
        {
            if (string.IsNullOrEmpty(folder)) return null;
            string current;
            try { current = Path.GetFullPath(folder).TrimEnd('\\'); } catch { return null; }
            for (int i = 0; i < 3 && current != null; i++)
            {
                if (IsGameDir(current)) return current;
                current = Path.GetDirectoryName(current);
            }
            return null;
        }

        public static string FindSteamGame()
        {
            var roots = new List<string>();
            try
            {
                using (var key = Registry.CurrentUser.OpenSubKey(@"Software\Valve\Steam"))
                {
                    var value = key == null ? null : key.GetValue("SteamPath") as string;
                    if (!string.IsNullOrEmpty(value)) roots.Add(value.Replace('/', '\\'));
                }
            }
            catch { }
            try
            {
                using (var key = Registry.LocalMachine.OpenSubKey(@"SOFTWARE\WOW6432Node\Valve\Steam"))
                {
                    var value = key == null ? null : key.GetValue("InstallPath") as string;
                    if (!string.IsNullOrEmpty(value)) roots.Add(value);
                }
            }
            catch { }
            var programs = Environment.GetEnvironmentVariable("ProgramFiles(x86)");
            if (!string.IsNullOrEmpty(programs)) roots.Add(Path.Combine(programs, "Steam"));
            var libraries = new List<string>(roots);
            foreach (var root in roots)
            {
                try
                {
                    var vdf = Path.Combine(root, "steamapps", "libraryfolders.vdf");
                    if (!File.Exists(vdf)) continue;
                    foreach (Match match in Regex.Matches(File.ReadAllText(vdf), "\"path\"\\s*\"((?:[^\"\\\\]|\\\\.)*)\""))
                        libraries.Add(match.Groups[1].Value.Replace("\\\\", "\\"));
                }
                catch { }
            }
            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var library in libraries)
            {
                if (!seen.Add(library)) continue;
                try
                {
                    var manifest = Path.Combine(library, "steamapps", "appmanifest_" + SteamAppId + ".acf");
                    if (!File.Exists(manifest)) continue;
                    var match = Regex.Match(File.ReadAllText(manifest), "\"installdir\"\\s*\"([^\"/\\\\:]+)\"");
                    if (!match.Success || match.Groups[1].Value == "." || match.Groups[1].Value == "..") continue;
                    var candidate = Path.Combine(library, "steamapps", "common", match.Groups[1].Value);
                    if (IsGameDir(candidate)) return candidate;
                }
                catch { }
            }
            return null;
        }

        static string SettingsFile()
        {
            return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "PC2Coop", "setup.json");
        }

        public static string RememberedGame()
        {
            try
            {
                var data = Json.Object(File.ReadAllText(SettingsFile()));
                var game = Json.Text(data, "game_dir");
                return IsGameDir(game) ? game : null;
            }
            catch { return null; }
        }

        public static void Remember(string game)
        {
            try
            {
                var file = SettingsFile();
                Directory.CreateDirectory(Path.GetDirectoryName(file));
                File.WriteAllText(file, Json.Write(new Dictionary<string, object> { { "game_dir", game } }));
            }
            catch { }
        }

        public static string FindGame()
        {
            return RememberedGame() ?? FindSteamGame();
        }

        public static string Hash(string path)
        {
            using (var sha = SHA256.Create())
            using (var stream = File.OpenRead(path))
            {
                var bytes = sha.ComputeHash(stream);
                var text = new StringBuilder(64);
                foreach (var b in bytes) text.Append(b.ToString("x2"));
                return text.ToString();
            }
        }

        static string Safe(string root, string relative)
        {
            if (relative == null || !SafeRelative.IsMatch(relative))
                throw new SetupException(Codes.Error, T.S("Ungültiger Pfad im Paket: ", "Invalid path in the package: ") + relative);
            var basePath = Path.GetFullPath(root).TrimEnd('\\') + "\\";
            var target = Path.GetFullPath(Path.Combine(root, relative.Replace('/', '\\')));
            if (!target.StartsWith(basePath, StringComparison.OrdinalIgnoreCase))
                throw new SetupException(Codes.Error, T.S("Pfad liegt außerhalb des Mod-Ordners.", "Path is outside the mod folder."));
            return target;
        }

        [StructLayout(LayoutKind.Sequential)]
        struct FileInfoByHandle
        {
            public uint Attributes;
            public System.Runtime.InteropServices.ComTypes.FILETIME Created, Accessed, Written;
            public uint Volume, SizeHigh, SizeLow, Links, IndexHigh, IndexLow;
        }

        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool GetFileInformationByHandle(Microsoft.Win32.SafeHandles.SafeFileHandle file, out FileInfoByHandle info);

        static uint Links(string path)
        {
            try
            {
                using (var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
                {
                    FileInfoByHandle info;
                    return GetFileInformationByHandle(stream.SafeFileHandle, out info) ? info.Links : 1;
                }
            }
            catch { return 1; }
        }

        // Vortex deploys hard links from its staging folder and writes vortex.deployment*.json.
        public static bool ManagedByVortex(string game)
        {
            var ovldata = Ovldata(game);
            foreach (var name in ModFiles)
            {
                var file = Path.Combine(ovldata, "PC2CoopProbe", name);
                if (File.Exists(file) && Links(file) > 1) return true;
            }
            foreach (var folder in new[] { game, Path.Combine(game, "Win64"), ovldata })
            {
                try
                {
                    foreach (var file in Directory.GetFiles(folder, "vortex.deployment*.json"))
                        if (File.ReadAllText(file).IndexOf("PC2CoopProbe", StringComparison.OrdinalIgnoreCase) >= 0) return true;
                }
                catch { }
            }
            return false;
        }

        public static bool GameRunning()
        {
            try { return Process.GetProcessesByName("PlanetCoaster2").Length > 0; } catch { return false; }
        }

        public static GameState Inspect(string game)
        {
            var state = new GameState { Game = game };
            var ovldata = Ovldata(game);
            state.Acse = File.Exists(Path.Combine(ovldata, "ACSE", "Main.ovl")) || Directory.Exists(Path.Combine(ovldata, "ACSEDebug"));
            try
            {
                var versionFile = Path.Combine(ovldata, "ACSE", "Version.txt");
                if (File.Exists(versionFile)) state.AcseVersion = File.ReadAllText(versionFile).Trim().Split(' ', '\t', '\r', '\n')[0];
            }
            catch { }
            var dll = Path.Combine(ovldata, "PC2CoopProbe", "PC2CoopDiagnostic.dll");
            state.Installed = File.Exists(Path.Combine(ovldata, "PC2CoopProbe", "Main.ovl"));
            if (state.Installed)
            {
                try
                {
                    var journal = LoadJournal(ovldata);
                    if (journal != null) state.InstalledVersion = Json.Text(journal, "version");
                }
                catch { }
                if (string.IsNullOrEmpty(state.InstalledVersion) && File.Exists(dll))
                {
                    try { state.InstalledVersion = FileVersionInfo.GetVersionInfo(dll).ProductVersion; } catch { }
                }
            }
            state.Vortex = ManagedByVortex(game);
            return state;
        }

        static Dictionary<string, object> LoadJournal(string ovldata)
        {
            var path = Path.Combine(ovldata, JournalName);
            if (!File.Exists(path)) return null;
            return Json.Object(File.ReadAllText(path));
        }

        public static Dictionary<string, object> LoadManifest(string package)
        {
            var path = Path.Combine(package, "payload-manifest.json");
            if (!File.Exists(path) || !Directory.Exists(Path.Combine(package, "Mod")))
                throw new SetupException(Codes.NotUnpacked, T.S(
                    "Die Mod-Dateien fehlen neben PC2Coop-Setup.exe. Bitte die ZIP-Datei zuerst entpacken (Rechtsklick → „Alle extrahieren…“) und Setup dann aus dem entpackten Ordner starten.",
                    "The mod files are missing next to PC2Coop-Setup.exe. Please extract the ZIP first (right-click → \"Extract All…\") and start Setup from the extracted folder."));
            return Json.Object(File.ReadAllText(path));
        }

        static void CheckReady(string game)
        {
            if (!IsGameDir(game))
                throw new SetupException(Codes.NoGame, T.S("Im gewählten Ordner ist kein Planet Coaster 2.", "The selected folder does not contain Planet Coaster 2."));
            if (GameRunning())
                throw new SetupException(Codes.GameRunning, T.S("Bitte Planet Coaster 2 zuerst beenden.", "Please close Planet Coaster 2 first."));
            if (ManagedByVortex(game))
                throw new SetupException(Codes.Vortex, T.S(
                    "PC2Coop ist über Vortex installiert. Aktualisiere oder entferne es bitte in Vortex – sonst kommen Vortex und Setup durcheinander.",
                    "PC2Coop is installed through Vortex. Please update or remove it in Vortex, otherwise Vortex and Setup get in each other's way."));
        }

        static SetupException NoRights(Exception error)
        {
            return new SetupException(Codes.NoRights, T.S(
                "Setup darf im Spielordner nicht schreiben. Rechtsklick auf PC2Coop-Setup.exe → „Als Administrator ausführen“. (",
                "Setup may not write to the game folder. Right-click PC2Coop-Setup.exe → \"Run as administrator\". (") + error.Message + ")");
        }

        class Step
        {
            public string Source, Target, Relative;
            public bool Existed, Delete;
        }

        // Returns the number of files changed. Throws SetupException.
        public static int Install(string game, string package, Action<string> say)
        {
            CheckReady(game);
            var ovldata = Ovldata(game);
            var manifest = LoadManifest(package);
            var version = Json.Text(manifest, "version");
            if (!File.Exists(Path.Combine(ovldata, "ACSE", "Main.ovl")) && !Directory.Exists(Path.Combine(ovldata, "ACSEDebug")))
                throw new SetupException(Codes.AcseMissing, T.S(
                    "ACSE fehlt. PC2Coop braucht den Mod-Loader ACSE. Lade ihn bei Nexus Mods herunter, installiere ihn und starte Setup dann noch einmal. Es wurde nichts verändert.",
                    "ACSE is missing. PC2Coop needs the mod loader ACSE. Download it from Nexus Mods, install it and start Setup again. Nothing was changed."));
            var modSource = Path.Combine(package, "Mod");
            var wanted = new Dictionary<string, string>();
            foreach (var entry in Json.List(manifest, "files"))
            {
                var relative = Json.Text(entry, "path");
                var sha = Json.Text(entry, "sha256");
                var source = Safe(modSource, relative);
                if (!File.Exists(source) || Hash(source) != sha)
                    throw new SetupException(Codes.NotUnpacked, T.S("Das Paket ist beschädigt: ", "The package is damaged: ") + relative
                        + T.S(". Bitte die ZIP-Datei neu herunterladen und entpacken.", ". Please download and extract the ZIP again."));
                wanted[relative] = sha;
            }
            var journal = LoadJournal(ovldata);
            var owned = new Dictionary<string, string>();
            var keep = new List<object>();
            if (journal != null)
            {
                foreach (var entry in Json.List(journal, "files"))
                {
                    var relative = Json.Text(entry, "path");
                    if (relative == null) continue;
                    if (relative.StartsWith("PC2CoopProbe/")) owned[relative] = Json.Text(entry, "sha256");
                    else keep.Add(entry); // ACSE files an old package installed: stay as they are
                }
            }
            var plan = new List<Step>();
            foreach (var pair in wanted)
            {
                var target = Safe(ovldata, pair.Key);
                bool exists = File.Exists(target);
                if (exists && Hash(target) == pair.Value) continue;
                plan.Add(new Step { Source = Safe(modSource, pair.Key), Target = target, Relative = pair.Key, Existed = exists });
            }
            foreach (var pair in owned)
            {
                if (wanted.ContainsKey(pair.Key)) continue;
                var target = Safe(ovldata, pair.Key);
                if (File.Exists(target) && Hash(target) == pair.Value)
                    plan.Add(new Step { Target = target, Relative = pair.Key, Existed = true, Delete = true });
            }
            var stamp = DateTime.UtcNow.ToString("yyyyMMdd-HHmmss-fffffff", CultureInfo.InvariantCulture);
            var backupRoot = Path.Combine(ovldata, ".pc2coop-alpha-backups", stamp);
            var applied = new List<Step>();
            try
            {
                foreach (var step in plan)
                {
                    Directory.CreateDirectory(Path.GetDirectoryName(step.Target));
                    if (step.Existed)
                    {
                        var backup = Safe(backupRoot, step.Relative);
                        Directory.CreateDirectory(Path.GetDirectoryName(backup));
                        File.Copy(step.Target, backup, true);
                    }
                    applied.Add(step);
                    if (step.Delete) { File.Delete(step.Target); continue; }
                    var temporary = step.Target + ".pc2coop-new";
                    File.Copy(step.Source, temporary, true);
                    if (File.Exists(step.Target)) File.Delete(step.Target);
                    File.Move(temporary, step.Target);
                }
                var files = new List<object>(keep);
                foreach (var pair in wanted)
                    files.Add(new Dictionary<string, object> { { "path", pair.Key }, { "sha256", pair.Value } });
                var state = new Dictionary<string, object> {
                    { "schema", 1 }, { "package", "PC2Coop" }, { "version", version }, { "installer", "PC2Coop-Setup " + BuildInfo.Version },
                    { "installed_utc", stamp }, { "files", files } };
                var journalPath = Path.Combine(ovldata, JournalName);
                var temporaryJournal = journalPath + "." + Guid.NewGuid().ToString("N") + ".tmp";
                File.WriteAllText(temporaryJournal, Json.Write(state), new UTF8Encoding(false));
                if (File.Exists(journalPath)) File.Delete(journalPath);
                File.Move(temporaryJournal, journalPath);
            }
            catch (Exception error)
            {
                applied.Reverse();
                foreach (var step in applied)
                {
                    try
                    {
                        if (step.Existed) File.Copy(Safe(backupRoot, step.Relative), step.Target, true);
                        else if (File.Exists(step.Target)) File.Delete(step.Target);
                        if (File.Exists(step.Target + ".pc2coop-new")) File.Delete(step.Target + ".pc2coop-new");
                    }
                    catch { }
                }
                if (error is SetupException) throw;
                if (error is UnauthorizedAccessException) throw NoRights(error);
                throw new SetupException(Codes.Error, T.S("Installation fehlgeschlagen, nichts verändert: ", "Installation failed, nothing changed: ") + error.Message);
            }
            PruneBackups(Path.Combine(ovldata, ".pc2coop-alpha-backups"));
            var exeHash = Json.Text(manifest, "tested_exe_sha256");
            try
            {
                if (!string.IsNullOrEmpty(exeHash) && Hash(GameExe(game)) != exeHash)
                    say(T.S("Hinweis: Diese Spielversion ist mit PC2Coop noch nicht getestet (getestet: Build ",
                        "Note: this game version has not been tested with PC2Coop yet (tested: build ")
                        + Json.Text(manifest, "tested_steam_build") + T.S("). Meistens klappt es trotzdem.", "). It usually works anyway."));
            }
            catch { }
            return plan.Count;
        }

        static void PruneBackups(string root)
        {
            try
            {
                var folders = Directory.GetDirectories(root);
                Array.Sort(folders, StringComparer.Ordinal);
                for (int i = 0; i < folders.Length - 3; i++) Directory.Delete(folders[i], true);
            }
            catch { }
        }

        // Removes the mod's own files; logs, park notes and ACSE stay.
        public static int Uninstall(string game)
        {
            CheckReady(game);
            var ovldata = Ovldata(game);
            var targets = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var name in ModFiles) targets.Add("PC2CoopProbe/" + name);
            var journal = LoadJournal(ovldata);
            if (journal != null)
                foreach (var entry in Json.List(journal, "files"))
                {
                    var relative = Json.Text(entry, "path");
                    if (relative != null && relative.StartsWith("PC2CoopProbe/")) targets.Add(relative);
                }
            int removed = 0;
            try
            {
                foreach (var relative in targets)
                {
                    var target = Safe(ovldata, relative);
                    if (File.Exists(target)) { File.Delete(target); removed++; }
                }
                var folder = Path.Combine(ovldata, "PC2CoopProbe");
                if (Directory.Exists(folder) && Directory.GetFileSystemEntries(folder).Length == 0) Directory.Delete(folder);
                var journalPath = Path.Combine(ovldata, JournalName);
                if (File.Exists(journalPath)) File.Delete(journalPath);
            }
            catch (UnauthorizedAccessException error) { throw NoRights(error); }
            catch (IOException error)
            {
                throw new SetupException(Codes.Error, T.S("Entfernen fehlgeschlagen: ", "Removing failed: ") + error.Message);
            }
            return removed;
        }

        static string ApiUrl() { return "https://api.github.com/repos/" + BuildInfo.Repo + "/releases/latest"; }

        static WebClient Client()
        {
            var client = new WebClient();
            client.Headers[HttpRequestHeader.UserAgent] = "PC2Coop-Setup/" + BuildInfo.Version;
            client.Encoding = Encoding.UTF8;
            return client;
        }

        public static ReleaseInfo Latest(string api)
        {
            bool official = string.IsNullOrEmpty(api);
            string text;
            try
            {
                using (var client = Client())
                {
                    client.Headers[HttpRequestHeader.Accept] = "application/vnd.github+json";
                    text = client.DownloadString(official ? ApiUrl() : api);
                }
            }
            catch (WebException error)
            {
                throw new SetupException(Codes.Error, T.S("GitHub ist gerade nicht erreichbar: ", "GitHub cannot be reached right now: ") + error.Message);
            }
            var release = Json.Object(text);
            var info = new ReleaseInfo { Notes = Json.Text(release, "body") };
            var prefix = "https://github.com/" + BuildInfo.Repo + "/releases/download/";
            foreach (var asset in Json.List(release, "assets"))
            {
                var name = Json.Text(asset, "name") ?? "";
                var url = Json.Text(asset, "browser_download_url") ?? "";
                if (official && !url.StartsWith(prefix, StringComparison.Ordinal)) continue;
                var match = Regex.Match(name, @"^PC2Coop-(\d+\.\d+\.\d+)\.zip$");
                if (match.Success) { info.Version = match.Groups[1].Value; info.ZipUrl = url; }
            }
            foreach (var asset in Json.List(release, "assets"))
                if (info.Version != null && Json.Text(asset, "name") == "PC2Coop-" + info.Version + ".zip.sha256")
                    info.ShaUrl = Json.Text(asset, "browser_download_url");
            if (info.Version == null)
                throw new SetupException(Codes.Error, T.S("Die neueste Version auf GitHub enthält kein PC2Coop-Paket.", "The newest release on GitHub has no PC2Coop package."));
            return info;
        }

        public static bool Newer(string candidate, string current)
        {
            Version a, b;
            if (!System.Version.TryParse(candidate ?? "", out a)) return false;
            if (!System.Version.TryParse(current ?? "", out b)) return true;
            return a > b;
        }

        // Download, check, unpack only the mod files and install them. Nothing downloaded runs.
        public static int Update(string game, ReleaseInfo info, Action<string> say)
        {
            CheckReady(game);
            if (string.IsNullOrEmpty(info.ShaUrl))
                throw new SetupException(Codes.Error, T.S("Zur neuen Version fehlt die Prüfsumme. Nichts installiert.", "The new version has no checksum. Nothing installed."));
            var work = Path.Combine(Path.GetTempPath(), "PC2Coop-update-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(work);
            try
            {
                var zip = Path.Combine(work, "package.zip");
                string shaText;
                say(T.S("Lade Version ", "Downloading version ") + info.Version + " …");
                try
                {
                    using (var client = Client())
                    {
                        client.DownloadFile(info.ZipUrl, zip);
                        shaText = client.DownloadString(info.ShaUrl);
                    }
                }
                catch (WebException error)
                {
                    throw new SetupException(Codes.Error, T.S("Download fehlgeschlagen: ", "Download failed: ") + error.Message);
                }
                var expected = Regex.Match(shaText ?? "", @"\b[0-9a-fA-F]{64}\b").Value.ToLowerInvariant();
                if (expected.Length == 0 || Hash(zip) != expected)
                    throw new SetupException(Codes.Error, T.S("Prüfsumme stimmt nicht – Download beschädigt. Nichts installiert.", "Checksum does not match – the download is damaged. Nothing installed."));
                var package = Path.Combine(work, "package");
                Extract(zip, package);
                var manifest = LoadManifest(package);
                if (Json.Text(manifest, "version") != info.Version)
                    throw new SetupException(Codes.Error, T.S("Paketinhalt passt nicht zur Versionsnummer. Nichts installiert.", "Package content does not match the version. Nothing installed."));
                return Install(game, package, say);
            }
            finally
            {
                try { Directory.Delete(work, true); } catch { }
            }
        }

        // Only PC2Coop/payload-manifest.json and PC2Coop/Mod/PC2CoopProbe/<file>; nothing else.
        public static void Extract(string zip, string target)
        {
            var manifestName = "PC2Coop/payload-manifest.json";
            var modPattern = new Regex(@"^PC2Coop/Mod/PC2CoopProbe/[A-Za-z0-9_.-]+$");
            using (var archive = ZipFile.OpenRead(zip))
            {
                foreach (var entry in archive.Entries)
                {
                    var name = entry.FullName.Replace('\\', '/');
                    if (!name.StartsWith("PC2Coop/") || name.Contains("..") || name.Contains(":"))
                        throw new SetupException(Codes.Error, T.S("Unerwarteter Eintrag im Paket: ", "Unexpected entry in the package: ") + entry.FullName);
                    string destination;
                    if (name == manifestName) destination = Path.Combine(target, "payload-manifest.json");
                    else if (modPattern.IsMatch(name)) destination = Path.Combine(target, "Mod", "PC2CoopProbe", name.Substring(name.LastIndexOf('/') + 1));
                    else continue;
                    Directory.CreateDirectory(Path.GetDirectoryName(destination));
                    entry.ExtractToFile(destination, true);
                }
            }
        }
    }

    static class Json
    {
        static JavaScriptSerializer Serializer() { return new JavaScriptSerializer { MaxJsonLength = 16 * 1024 * 1024 }; }

        public static Dictionary<string, object> Object(string text)
        {
            var value = Serializer().DeserializeObject(text) as Dictionary<string, object>;
            if (value == null) throw new SetupException(Codes.Error, "JSON");
            return value;
        }

        public static string Write(object value) { return Serializer().Serialize(value); }

        public static string Text(object data, string key)
        {
            var map = data as Dictionary<string, object>;
            object value;
            if (map == null || !map.TryGetValue(key, out value) || value == null) return null;
            return Convert.ToString(value, CultureInfo.InvariantCulture);
        }

        public static IEnumerable<object> List(object data, string key)
        {
            var map = data as Dictionary<string, object>;
            object value;
            if (map == null || !map.TryGetValue(key, out value) || value == null) yield break;
            var list = value as IEnumerable;
            if (value is Dictionary<string, object> || list == null) { yield return value; yield break; } // PowerShell wrote a single object
            foreach (var item in list) yield return item;
        }
    }

    // Command line (tests and power users): --install | --uninstall | --status | --check-update | --update
    // with --game <folder>, --source <package folder>, --api <url>, --lang de|en, --log <file>.
    static class Cli
    {
        static StreamWriter log, output;

        // UTF-8 on stdout whatever the console code page is (tests read it as UTF-8).
        static void Say(string line)
        {
            try
            {
                if (output == null) output = new StreamWriter(Console.OpenStandardOutput(), new UTF8Encoding(false)) { AutoFlush = true };
                output.WriteLine(line);
            }
            catch { }
            try { if (log != null) { log.WriteLine(line); log.Flush(); } } catch { }
        }

        public static int Run(Dictionary<string, string> options, string action)
        {
            string logPath;
            if (options.TryGetValue("log", out logPath)) log = new StreamWriter(logPath, false, new UTF8Encoding(false));
            try
            {
                string game;
                if (options.TryGetValue("game", out game)) game = Core.NormalizeGameDir(game) ?? game;
                else game = Core.FindGame();
                if (string.IsNullOrEmpty(game))
                    throw new SetupException(Codes.NoGame, T.S("Planet Coaster 2 wurde nicht gefunden. --game \"<Spielordner>\" angeben.",
                        "Planet Coaster 2 was not found. Pass --game \"<game folder>\"."));
                string source;
                if (!options.TryGetValue("source", out source)) source = Program.PackageFolder();
                string api;
                options.TryGetValue("api", out api);
                Say("game=" + game);
                if (action == "status")
                {
                    var state = Core.Inspect(game);
                    Say(string.Format(CultureInfo.InvariantCulture, "result=ok acse={0} installed={1} version={2} vortex={3}",
                        state.Acse ? "yes" : "no", state.Installed ? "yes" : "no", state.InstalledVersion ?? "", state.Vortex ? "yes" : "no"));
                    return Codes.Ok;
                }
                if (action == "install")
                {
                    int changed = Core.Install(game, source, Say);
                    Say("result=ok action=install changed=" + changed);
                    return Codes.Ok;
                }
                if (action == "uninstall")
                {
                    int removed = Core.Uninstall(game);
                    Say("result=ok action=uninstall removed=" + removed);
                    return Codes.Ok;
                }
                var info = Core.Latest(api);
                var current = Core.Inspect(game).InstalledVersion;
                bool newer = Core.Newer(info.Version, current);
                Say("latest=" + info.Version + " current=" + (current ?? "") + " update=" + (newer ? "yes" : "no"));
                if (action == "check-update") return Codes.Ok;
                if (!newer) { Say("result=ok action=update changed=0"); return Codes.UpToDate; }
                int count = Core.Update(game, info, Say);
                Say("result=ok action=update version=" + info.Version + " changed=" + count);
                return Codes.Ok;
            }
            catch (SetupException error)
            {
                Say("result=error code=" + error.Code + " message=" + error.Message);
                return error.Code;
            }
            catch (Exception error)
            {
                Say("result=error code=1 message=" + error.Message);
                return Codes.Error;
            }
            finally
            {
                if (log != null) log.Dispose();
            }
        }
    }

    class MainForm : Form
    {
        readonly Dictionary<string, string> options;
        readonly Label gameValue = new Label(), acseValue = new Label(), modValue = new Label(), status = new Label();
        readonly Button change = new Button(), acseButton = new Button(), install = new Button(),
            update = new Button(), remove = new Button(), play = new Button();
        string game;
        GameState state;
        ReleaseInfo pending;
        string packageVersion;

        public MainForm(Dictionary<string, string> options)
        {
            this.options = options;
            Text = T.S("PC2Coop einrichten", "PC2Coop setup");
            Font = new Font("Segoe UI", 9.75f);
            AutoScaleMode = AutoScaleMode.Dpi;
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = false;
            StartPosition = FormStartPosition.CenterScreen;
            AutoSize = true;
            AutoSizeMode = AutoSizeMode.GrowAndShrink;
            Padding = new Padding(0, 0, 18, 18);
            try { Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); } catch { }

            var layout = new TableLayoutPanel { ColumnCount = 3, AutoSize = true, AutoSizeMode = AutoSizeMode.GrowAndShrink, Location = new Point(18, 18) };
            layout.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            layout.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 380));
            layout.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));

            try { packageVersion = Json.Text(Core.LoadManifest(Program.PackageFolder()), "version"); } catch { }
            var title = new Label { Text = "PC2Coop " + (packageVersion ?? BuildInfo.Version), AutoSize = true,
                Font = new Font("Segoe UI Semibold", 15f), Margin = new Padding(0, 0, 0, 2) };
            var subtitle = new Label { Text = T.S("Live zusammen bauen in Planet Coaster 2", "Build live together in Planet Coaster 2"),
                AutoSize = true, ForeColor = SystemColors.GrayText, Margin = new Padding(0, 0, 0, 14) };
            layout.Controls.Add(title, 0, 0); layout.SetColumnSpan(title, 3);
            layout.Controls.Add(subtitle, 0, 1); layout.SetColumnSpan(subtitle, 3);

            Row(layout, 2, T.S("Spiel", "Game"), gameValue, change, T.S("Ändern …", "Change …"));
            Row(layout, 3, "ACSE", acseValue, acseButton, T.S("Herunterladen", "Download"));
            Row(layout, 4, "PC2Coop", modValue, null, null);

            var buttons = new FlowLayoutPanel { AutoSize = true, FlowDirection = FlowDirection.LeftToRight, Margin = new Padding(0, 16, 0, 0), WrapContents = false };
            foreach (var button in new[] { install, update, remove, play })
            {
                button.AutoSize = true;
                button.Padding = new Padding(8, 3, 8, 3);
                button.Margin = new Padding(0, 0, 8, 0);
                buttons.Controls.Add(button);
            }
            update.Text = T.S("Nach Update suchen", "Check for update");
            remove.Text = T.S("Entfernen", "Remove");
            play.Text = T.S("Spiel starten", "Start game");
            layout.Controls.Add(buttons, 0, 5); layout.SetColumnSpan(buttons, 3);

            status.AutoSize = true;
            status.MaximumSize = new Size(560, 0);
            status.Margin = new Padding(0, 14, 0, 0);
            layout.Controls.Add(status, 0, 6); layout.SetColumnSpan(status, 3);
            Controls.Add(layout);
            AcceptButton = install;

            change.Click += delegate { PickGame(); };
            acseButton.Click += delegate { Open(Core.AcsePage); };
            play.Click += delegate { Open("steam://rungameid/" + Core.SteamAppId); };
            install.Click += async delegate
            {
                if (pending != null) await Work(delegate(Action<string> say) { return Done(Core.Update(game, pending, say), pending.Version); });
                else await Work(delegate(Action<string> say) { return Done(Core.Install(game, Program.PackageFolder(), say), packageVersion); });
            };
            remove.Click += async delegate
            {
                if (MessageBox.Show(this, T.S("PC2Coop aus dem Spiel entfernen? Logs, Park-Notizen und ACSE bleiben.", "Remove PC2Coop from the game? Logs, park notes and ACSE stay."),
                    Text, MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return;
                await Work(delegate(Action<string> say) { Core.Uninstall(game); return T.S("PC2Coop wurde entfernt.", "PC2Coop was removed."); });
            };
            update.Click += async delegate { await CheckUpdate(); };
            Shown += delegate { ShowGame(Core.FindGame()); };
        }

        static void Row(TableLayoutPanel layout, int row, string caption, Label value, Button button, string buttonText)
        {
            var label = new Label { Text = caption, AutoSize = true, Margin = new Padding(0, 7, 16, 7), Font = new Font("Segoe UI Semibold", 9.75f) };
            value.AutoSize = true;
            value.MaximumSize = new Size(380, 0);
            value.Margin = new Padding(0, 7, 8, 7);
            layout.Controls.Add(label, 0, row);
            layout.Controls.Add(value, 1, row);
            if (button != null)
            {
                button.Text = buttonText;
                button.AutoSize = true;
                button.Margin = new Padding(0, 3, 0, 3);
                layout.Controls.Add(button, 2, row);
            }
        }

        string Done(int changed, string version)
        {
            Core.Remember(game);
            return changed == 0
                ? T.S("PC2Coop " + version + " war schon installiert – alles aktuell.", "PC2Coop " + version + " was already installed – all up to date.")
                : T.S("Fertig! PC2Coop " + version + " ist installiert. Starte Planet Coaster 2 – im Hauptmenü findest du „Multiplayer“.",
                      "Done! PC2Coop " + version + " is installed. Start Planet Coaster 2 – you'll find \"Multiplayer\" in the main menu.");
        }

        static void Open(string target)
        {
            try { Process.Start(target); } catch { }
        }

        void PickGame()
        {
            using (var dialog = new FolderBrowserDialog())
            {
                dialog.Description = T.S("Wähle den Ordner von Planet Coaster 2 (er enthält „Win64“).", "Choose the Planet Coaster 2 folder (it contains \"Win64\").");
                if (game != null) dialog.SelectedPath = game;
                if (dialog.ShowDialog(this) != DialogResult.OK) return;
                var picked = Core.NormalizeGameDir(dialog.SelectedPath);
                if (picked == null) { SetStatus(T.S("In diesem Ordner ist kein Planet Coaster 2.", "This folder does not contain Planet Coaster 2."), true); return; }
                Core.Remember(picked);
                ShowGame(picked);
            }
        }

        void ShowGame(string folder)
        {
            game = folder;
            pending = null;
            if (game == null)
            {
                state = null;
                gameValue.Text = T.S("nicht gefunden – bitte „Ändern …“ wählen", "not found – please choose \"Change …\"");
                acseValue.Text = modValue.Text = "–";
                acseButton.Visible = false;
                install.Text = T.S("Installieren", "Install");
                install.Enabled = update.Enabled = remove.Enabled = false;
                return;
            }
            state = Core.Inspect(game);
            gameValue.Text = game;
            acseValue.Text = state.Acse ? T.S("vorhanden", "found") + (state.AcseVersion != null ? " (" + state.AcseVersion + ")" : "")
                : T.S("fehlt – PC2Coop braucht diesen Mod-Loader", "missing – PC2Coop needs this mod loader");
            acseValue.ForeColor = state.Acse ? SystemColors.ControlText : Color.Firebrick;
            acseButton.Visible = !state.Acse;
            modValue.Text = state.Vortex ? T.S("über Vortex installiert – bitte dort verwalten", "installed through Vortex – please manage it there")
                : state.Installed ? T.S("installiert", "installed") + (state.InstalledVersion != null ? " (" + state.InstalledVersion + ")" : "")
                : T.S("noch nicht installiert", "not installed yet");
            bool newer = Core.Newer(packageVersion, state.InstalledVersion);
            install.Text = !state.Installed ? T.S("Installieren", "Install")
                : newer ? T.S("Aktualisieren auf ", "Update to ") + packageVersion : T.S("Neu installieren", "Reinstall");
            install.Enabled = state.Acse && !state.Vortex && packageVersion != null;
            remove.Enabled = state.Installed && !state.Vortex;
            update.Enabled = !state.Vortex;
            if (packageVersion == null)
            {
                try { Core.LoadManifest(Program.PackageFolder()); } catch (SetupException error) { SetStatus(error.Message, true); }
            }
            else if (!state.Acse) SetStatus(T.S("Zuerst ACSE installieren: „Herunterladen“ öffnet die Seite bei Nexus Mods. Danach Setup neu starten.",
                "Install ACSE first: \"Download\" opens its page on Nexus Mods. Then start Setup again."), false);
            else if (state.Vortex) SetStatus(modValue.Text, false);
            else SetStatus("", false);
        }

        void SetStatus(string text, bool error)
        {
            status.Text = text;
            status.ForeColor = error ? Color.Firebrick : SystemColors.ControlText;
        }

        async Task Work(Func<Action<string>, string> job)
        {
            foreach (var button in new[] { change, install, update, remove }) button.Enabled = false;
            SetStatus(T.S("Einen Moment …", "One moment …"), false);
            Action<string> say = delegate(string line) { BeginInvoke((Action)delegate { SetStatus(line, false); }); };
            string message = null, failure = null;
            await Task.Run(delegate
            {
                try { message = job(say); }
                catch (SetupException error) { failure = error.Message; }
                catch (Exception error) { failure = error.Message; }
            });
            change.Enabled = true;
            ShowGame(game);
            if (failure != null) SetStatus(failure, true); else SetStatus(message, false);
        }

        async Task CheckUpdate()
        {
            ReleaseInfo info = null;
            string failure = null;
            update.Enabled = false;
            SetStatus(T.S("Frage GitHub nach der neuesten Version …", "Asking GitHub for the newest version …"), false);
            string api;
            options.TryGetValue("api", out api);
            await Task.Run(delegate
            {
                try { info = Core.Latest(api); } catch (Exception error) { failure = error.Message; }
            });
            update.Enabled = true;
            if (failure != null) { SetStatus(failure, true); return; }
            var current = state != null && state.InstalledVersion != null ? state.InstalledVersion : packageVersion;
            if (!Core.Newer(info.Version, current))
            {
                SetStatus(T.S("Du hast die neueste Version (" + current + ").", "You have the newest version (" + current + ")."), false);
                return;
            }
            pending = info;
            install.Text = T.S("Aktualisieren auf ", "Update to ") + info.Version;
            install.Enabled = state != null && state.Acse && !state.Vortex;
            SetStatus(T.S("Neue Version " + info.Version + " verfügbar. „Aktualisieren“ lädt sie von GitHub, prüft sie und installiert sie. Alle Mitspieler brauchen dieselbe Version.",
                "New version " + info.Version + " available. \"Update\" downloads it from GitHub, checks it and installs it. Everyone needs the same version."), false);
        }
    }

    static class Program
    {
        public static string PackageFolder()
        {
            return Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location);
        }

        [STAThread]
        static int Main(string[] args)
        {
            ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12;
            var options = new Dictionary<string, string>();
            string action = null;
            for (int i = 0; i < args.Length; i++)
            {
                var arg = args[i].ToLowerInvariant();
                if (arg == "--install" || arg == "--uninstall" || arg == "--status" || arg == "--check-update" || arg == "--update")
                    action = arg.Substring(2);
                else if ((arg == "--game" || arg == "--source" || arg == "--api" || arg == "--lang" || arg == "--log") && i + 1 < args.Length)
                    options[arg.Substring(2)] = args[++i];
            }
            string lang;
            if (options.TryGetValue("lang", out lang)) T.German = lang == "de";
            if (action != null) return Cli.Run(options, action);
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new MainForm(options));
            return 0;
        }
    }
}
