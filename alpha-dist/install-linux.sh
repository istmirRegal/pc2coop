#!/usr/bin/env bash
# PC2Coop for Linux (Planet Coaster 2 through Steam/Proton): install, update, remove.
# The Linux counterpart of PC2Coop-Setup.exe, after a suggestion from a GitHub issue (CachyOS).
# Same package, same install journal, so Setup and this script understand each other.
#
#   bash PC2Coop-Linux-install.sh                 install or update (finds the game itself)
#   bash PC2Coop-Linux-install.sh --uninstall     remove the mod's own files
#   bash PC2Coop-Linux-install.sh --status        what is installed
#   ... --game-dir "$HOME/.local/share/Steam/steamapps/common/Planet Coaster 2"
#   ... --source <unpacked PC2Coop folder>        install that package instead of downloading
#
# Next to the unpacked ZIP (payload-manifest.json + Mod/) it installs that package; otherwise
# it downloads the newest release from GitHub, checks its SHA-256 and takes only the mod files
# out of it. Nothing downloaded is run. Needs bash, coreutils, grep, curl and unzip (or bsdtar
# or python3) - no jq. Exit codes: 0 ok, 1 error, 2 game running, 3 ACSE missing, 5 no game,
# 7 package broken or not unpacked, 10 already up to date.

set -u
REPO='istmirRegal/pc2coop'
APP_ID=2688950
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
JOURNAL_NAME='.pc2coop-alpha-install.json'
SAFE_RE='^PC2CoopProbe/[A-Za-z0-9_.-]+$'
MOD_FILES=(PC2CoopProbe/Main.ovl PC2CoopProbe/Manifest.xml PC2CoopProbe/PC2CoopDiagnostic.dll)

if [[ -t 2 ]]; then R=$'\e[31m' Y=$'\e[33m' G=$'\e[32m' N=$'\e[0m'; else R='' Y='' G='' N=''; fi
say()  { printf '%s\n' "$*" >&2; }
warn() { printf '%s%s%s\n' "$Y" "$*" "$N" >&2; }
fail() { local code=$1; shift; printf '%sresult=error code=%s %s%s\n' "$R" "$code" "$*" "$N" >&2; exit "$code"; }

sha() { sha256sum < "$1" | cut -d' ' -f1; }

# "path<TAB>sha256" per file entry of our JSON (manifest or journal). Our files always have
# "path" before "sha256" in each entry, written by package_release.py, Setup, install.ps1 or here.
json_files() {
    sed '1s/^\xEF\xBB\xBF//' -- "$1" | tr -d '\r\n' \
        | grep -oE '"(path|sha256)"[[:space:]]*:[[:space:]]*"[^"]*"' \
        | sed -E 's/^"(path|sha256)"[[:space:]]*:[[:space:]]*"([^"]*)"$/\1 \2/' \
        | awk '$1 == "path" { p = $2 } $1 == "sha256" && p != "" { print p "\t" tolower($2); p = "" }'
}
json_value() {   # first "key": "value" of a JSON file
    sed '1s/^\xEF\xBB\xBF//' -- "$1" | tr -d '\r\n' \
        | grep -oE "\"$2\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -n 1 | sed -E 's/.*"([^"]*)"$/\1/'
}

find_game() {
    local -a roots=() libs=()
    local r vdf lib manifest dir
    for r in "$HOME/.steam/steam" "$HOME/.steam/root" "$HOME/.local/share/Steam" \
             "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam" "$HOME/snap/steam/common/.local/share/Steam"; do
        [[ -d $r ]] && roots+=("$(realpath -- "$r")")
    done
    libs=("${roots[@]}")
    for r in "${roots[@]}"; do
        vdf="$r/steamapps/libraryfolders.vdf"
        [[ -f $vdf ]] || continue
        while IFS= read -r lib; do [[ -n $lib ]] && libs+=("$lib"); done \
            < <(grep -oE '"path"[[:space:]]*"[^"]*"' -- "$vdf" | sed -E 's/.*"([^"]*)"$/\1/')
    done
    for lib in "${libs[@]}"; do
        manifest="$lib/steamapps/appmanifest_${APP_ID}.acf"
        [[ -f $manifest ]] || continue
        dir=$(grep -oE '"installdir"[[:space:]]*"[^"/\\:]+"' -- "$manifest" | head -n 1 | sed -E 's/.*"([^"]*)"$/\1/')
        [[ -n $dir && $dir != . && $dir != .. && -d "$lib/steamapps/common/$dir" ]] && { printf '%s\n' "$lib/steamapps/common/$dir"; return 0; }
    done
    return 0
}

game_exe() {   # Steam keeps PlanetCoaster2.exe in the game's main folder; Win64 is accepted too
    local g=$1
    [[ -f $g/PlanetCoaster2.exe ]] && { printf '%s\n' "$g/PlanetCoaster2.exe"; return; }
    [[ -f $g/Win64/PlanetCoaster2.exe ]] && printf '%s\n' "$g/Win64/PlanetCoaster2.exe"
}

normalize_game() {   # the game folder, also when Win64 or ovldata was given
    local d up
    d=$(realpath -m -- "$1")
    for up in 0 1 2; do
        if [[ -n $(game_exe "$d") && -d $d/Win64/ovldata ]]; then printf '%s\n' "$d"; return; fi
        d=$(dirname -- "$d")
    done
}

safe() {   # safe <root> <relative>: the target inside root, or fail
    local rel=$2
    [[ $rel =~ $SAFE_RE ]] || fail 7 "Ungültiger Pfad im Paket: $rel"
    printf '%s/%s\n' "$1" "$rel"
}

check_ready() {
    [[ -n $(game_exe "$GAME") && -d $GAME/Win64/ovldata ]] || fail 5 "Im Ordner ist kein Planet Coaster 2: $GAME"
    if command -v pgrep >/dev/null 2>&1 && pgrep -f 'PlanetCoaster2\.exe' >/dev/null 2>&1; then
        fail 2 'Bitte Planet Coaster 2 zuerst beenden.'
    fi
}

install_package() {   # install_package <folder with payload-manifest.json and Mod/>
    local pkg=$1 ovl="$GAME/Win64/ovldata" manifest="$1/payload-manifest.json"
    check_ready
    [[ -f $manifest && -d $pkg/Mod ]] || fail 7 'Mod-Dateien fehlen: bitte die ZIP entpacken und dieses Skript daneben legen (oder ohne ZIP starten, dann lädt es selbst).'
    [[ -f $ovl/ACSE/Main.ovl || -d $ovl/ACSEDebug ]] || fail 3 'ACSE fehlt. PC2Coop braucht den Mod-Loader ACSE: https://www.nexusmods.com/planetcoaster2/mods/1 – den Ordner ACSE nach Win64/ovldata kopieren, dann erneut starten. Es wurde nichts verändert.'
    local version rel hash src tgt
    version=$(json_value "$manifest" version)
    local -A want=() owned=()
    local -a keep=() order=()
    while IFS=$'\t' read -r rel hash; do
        [[ -n $rel ]] || continue
        src=$(safe "$pkg/Mod" "$rel")
        [[ -f $src && $(sha "$src") == "$hash" ]] || fail 7 "Paket beschädigt: $rel. Bitte die ZIP neu laden und entpacken."
        want[$rel]=$hash; order+=("$rel")
    done < <(json_files "$manifest")
    (( ${#order[@]} )) || fail 7 'Das Paket enthält keine Mod-Dateien.'
    local journal="$ovl/$JOURNAL_NAME"
    if [[ -f $journal ]]; then
        while IFS=$'\t' read -r rel hash; do
            if [[ $rel == PC2CoopProbe/* ]]; then owned[$rel]=$hash; else keep+=("$rel"$'\t'"$hash"); fi
        done < <(json_files "$journal")
    fi
    local stamp backups
    stamp=$(date -u +%Y%m%d-%H%M%S-%N)
    backups="$ovl/.pc2coop-alpha-backups/$stamp"
    local -a done_t=() done_existed=() done_rel=()
    rollback() {
        local i
        for (( i = ${#done_t[@]} - 1; i >= 0; i-- )); do
            if (( done_existed[i] )); then cp -f -- "$backups/${done_rel[i]}" "${done_t[i]}" 2>/dev/null
            else rm -f -- "${done_t[i]}"; fi
        done
        fail 1 'Installation fehlgeschlagen; alles zurückgenommen. Schreibrechte im Spielordner prüfen.'
    }
    local changed=0 existed
    for rel in "${order[@]}"; do
        tgt=$(safe "$ovl" "$rel")
        [[ -f $tgt && $(sha "$tgt") == "${want[$rel]}" ]] && continue
        existed=0
        if [[ -f $tgt ]]; then
            existed=1
            mkdir -p -- "$(dirname -- "$backups/$rel")" && cp -p -- "$tgt" "$backups/$rel" || rollback
        fi
        done_t+=("$tgt"); done_existed+=("$existed"); done_rel+=("$rel")
        mkdir -p -- "$(dirname -- "$tgt")" && cp -f -- "$pkg/Mod/$rel" "$tgt.pc2coop-new" && mv -f -- "$tgt.pc2coop-new" "$tgt" || rollback
        changed=$((changed + 1))
    done
    # A file the old version owned and the new one does not have goes (with a backup).
    for rel in "${!owned[@]}"; do
        [[ -n ${want[$rel]+x} ]] && continue
        tgt=$(safe "$ovl" "$rel")
        if [[ -f $tgt && $(sha "$tgt") == "${owned[$rel]}" ]]; then
            mkdir -p -- "$(dirname -- "$backups/$rel")" && cp -p -- "$tgt" "$backups/$rel" && rm -f -- "$tgt" || rollback
            changed=$((changed + 1))
        fi
    done
    {
        printf '{"schema":1,"package":"PC2Coop","version":"%s","installer":"install-linux.sh","installed_utc":"%s","files":[' "$version" "$stamp"
        local first=1 entry
        for entry in "${keep[@]}"; do
            (( first )) || printf ','; first=0
            printf '{"path":"%s","sha256":"%s"}' "${entry%%$'\t'*}" "${entry#*$'\t'}"
        done
        for rel in "${order[@]}"; do
            (( first )) || printf ','; first=0
            printf '{"path":"%s","sha256":"%s"}' "$rel" "${want[$rel]}"
        done
        printf ']}\n'
    } > "$journal.tmp" && mv -f -- "$journal.tmp" "$journal" || rollback
    # The newest three backups stay.
    if [[ -d $ovl/.pc2coop-alpha-backups ]]; then
        ls -1 -- "$ovl/.pc2coop-alpha-backups" | sort | head -n -3 | while IFS= read -r old; do rm -rf -- "$ovl/.pc2coop-alpha-backups/$old"; done
    fi
    local tested exe
    tested=$(json_value "$manifest" tested_exe_sha256); exe=$(game_exe "$GAME")
    if [[ -n $tested && $(sha "$exe") != "$tested" ]]; then
        warn "Hinweis: Diese Spielversion ist mit PC2Coop noch nicht getestet (getestet: Build $(json_value "$manifest" tested_steam_build)). Meistens klappt es trotzdem."
    fi
    printf '%sPC2Coop %s ist installiert. Im Spiel: Hauptmenü → Multiplayer.%s\n' "$G" "$version" "$N" >&2
    printf 'result=ok action=install version=%s changed=%s\n' "$version" "$changed"
}

unzip_only() {   # unzip_only <zip> <target>: PC2Coop/payload-manifest.json and PC2Coop/Mod/PC2CoopProbe/<file>
    local zip=$1 target=$2 names name
    if command -v unzip >/dev/null 2>&1; then names=$(unzip -Z1 -- "$zip") || fail 1 'Die ZIP lässt sich nicht lesen.'
    elif command -v bsdtar >/dev/null 2>&1; then names=$(bsdtar -tf "$zip") || fail 1 'Die ZIP lässt sich nicht lesen.'
    elif command -v python3 >/dev/null 2>&1; then names=$(python3 -c 'import sys,zipfile; print("\n".join(zipfile.ZipFile(sys.argv[1]).namelist()))' "$zip") || fail 1 'Die ZIP lässt sich nicht lesen.'
    else fail 1 'Zum Entpacken fehlt unzip (sudo pacman -S unzip / sudo apt install unzip).'; fi
    local -a wanted=()
    while IFS= read -r name; do
        [[ -z $name ]] && continue
        [[ $name == PC2Coop/* && $name != *..* && $name != *:* && $name != *\\* ]] || fail 1 "Unerwarteter Eintrag im Paket: $name"
        [[ $name == PC2Coop/payload-manifest.json || $name =~ ^PC2Coop/Mod/PC2CoopProbe/[A-Za-z0-9_.-]+$ ]] && wanted+=("$name")
    done <<< "$names"
    mkdir -p -- "$target"
    if command -v unzip >/dev/null 2>&1; then unzip -qo -- "$zip" "${wanted[@]}" -d "$target" || fail 1 'Entpacken fehlgeschlagen.'
    elif command -v bsdtar >/dev/null 2>&1; then bsdtar -xf "$zip" -C "$target" "${wanted[@]}" || fail 1 'Entpacken fehlgeschlagen.'
    else python3 -c 'import sys,zipfile; z=zipfile.ZipFile(sys.argv[1]); [z.extract(n, sys.argv[2]) for n in sys.argv[3:]]' "$zip" "$target" "${wanted[@]}" || fail 1 'Entpacken fehlgeschlagen.'; fi
}

latest() {   # sets LATEST_VERSION, LATEST_ZIP, LATEST_SHA from GitHub's "latest release"
    local api=${API:-https://api.github.com/repos/$REPO/releases/latest} body url
    command -v curl >/dev/null 2>&1 || fail 1 'curl fehlt.'
    body=$(curl -fsSL -H 'User-Agent: PC2Coop-install-linux' -H 'Accept: application/vnd.github+json' -- "$api") \
        || fail 1 'GitHub ist gerade nicht erreichbar.'
    LATEST_VERSION='' LATEST_ZIP='' LATEST_SHA=''
    local name
    # Each asset's "name" comes before its "browser_download_url" (GitHub's JSON order).
    while IFS=$'\t' read -r name url; do
        [[ -z ${API:-} && $url != "https://github.com/$REPO/releases/download/"* ]] && continue
        if [[ $name =~ ^PC2Coop-([0-9]+\.[0-9]+\.[0-9]+)\.zip$ ]]; then LATEST_VERSION=${BASH_REMATCH[1]}; LATEST_ZIP=$url; fi
        [[ $name =~ ^PC2Coop-[0-9]+\.[0-9]+\.[0-9]+\.zip\.sha256$ ]] && LATEST_SHA=$url
    done < <(tr -d '\r\n' <<< "$body" | grep -oE '"(name|browser_download_url)"[[:space:]]*:[[:space:]]*"[^"]*"' \
        | sed -E 's/^"([a-z_]+)"[[:space:]]*:[[:space:]]*"([^"]*)"$/\1\t\2/' \
        | awk -F'\t' '$1 == "name" { n = $2 } $1 == "browser_download_url" { print n "\t" $2 }')
    [[ -n $LATEST_VERSION ]] || fail 1 'Die neueste Version auf GitHub enthält kein PC2Coop-Paket.'
    [[ -n $LATEST_SHA ]] || fail 1 'Zur neuen Version fehlt die Prüfsumme. Nichts installiert.'
}

installed_version() {
    local journal="$GAME/Win64/ovldata/$JOURNAL_NAME"
    [[ -f $journal ]] && json_value "$journal" version
}

install_latest() {   # download, check, unpack only the mod files, install them
    check_ready
    latest
    local current; current=$(installed_version)
    say "Neueste Version auf GitHub: $LATEST_VERSION${current:+ (installiert: $current)}"
    if [[ $current == "$LATEST_VERSION" && ${FORCE:-0} == 0 ]]; then
        printf 'result=ok action=install version=%s changed=0 uptodate=1\n' "$LATEST_VERSION"
        exit 10
    fi
    WORK=$(mktemp -d) || fail 1 'Kein temporärer Ordner.'
    trap 'rm -rf -- "${WORK:-}"' EXIT
    local work=$WORK
    say "Lade PC2Coop $LATEST_VERSION …"
    curl -fsSL -H 'User-Agent: PC2Coop-install-linux' -o "$work/package.zip" -- "$LATEST_ZIP" || fail 1 'Download fehlgeschlagen.'
    local expected; expected=$(curl -fsSL -H 'User-Agent: PC2Coop-install-linux' -- "$LATEST_SHA" | grep -oiE '\b[0-9a-f]{64}\b' | head -n 1 | tr 'A-F' 'a-f')
    [[ -n $expected && $(sha "$work/package.zip") == "$expected" ]] || fail 1 'Prüfsumme stimmt nicht – Download beschädigt. Nichts installiert.'
    unzip_only "$work/package.zip" "$work/out"
    [[ $(json_value "$work/out/PC2Coop/payload-manifest.json" version) == "$LATEST_VERSION" ]] || fail 1 'Paketinhalt passt nicht zur Versionsnummer.'
    install_package "$work/out/PC2Coop"
}

uninstall() {
    check_ready
    local ovl="$GAME/Win64/ovldata" journal="$GAME/Win64/ovldata/$JOURNAL_NAME" rel hash removed=0
    local -A targets=()
    for rel in "${MOD_FILES[@]}"; do targets[$rel]=1; done
    if [[ -f $journal ]]; then
        while IFS=$'\t' read -r rel hash; do [[ $rel == PC2CoopProbe/* ]] && targets[$rel]=1; done < <(json_files "$journal")
    fi
    for rel in "${!targets[@]}"; do
        [[ $rel =~ $SAFE_RE ]] || continue
        if [[ -f $ovl/$rel ]]; then rm -f -- "$ovl/$rel" || fail 1 "Entfernen fehlgeschlagen: $rel"; removed=$((removed + 1)); fi
    done
    rmdir -- "$ovl/PC2CoopProbe" 2>/dev/null
    rm -f -- "$journal"
    printf '%sPC2Coop wurde entfernt. Logs, Park-Notizen und ACSE bleiben.%s\n' "$G" "$N" >&2
    printf 'result=ok action=uninstall removed=%s\n' "$removed"
}

usage() {
    sed -n '2,18p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
}

main() {
    local action=install source='' arg
    GAME='' API='' FORCE=0
    while (( $# )); do
        arg=$1
        case $arg in
            --install) action=install ;;
            --uninstall|-u) action=uninstall ;;
            --status) action=status ;;
            --game-dir|--game) GAME=${2-}; shift ;;
            --game-dir=*) GAME=${arg#*=} ;;
            --source) source=${2-}; shift ;;
            --api) API=${2-}; shift ;;
            --force) FORCE=1 ;;
            --non-interactive) ;;
            -h|--help) usage; exit 0 ;;
            *) usage; exit 1 ;;
        esac
        shift
    done
    (( EUID != 0 )) || fail 1 'Bitte nicht mit sudo/als root starten (sonst gehören die Mod-Dateien root).'
    if [[ -n $GAME ]]; then GAME=$(normalize_game "$GAME"); [[ -n $GAME ]] || fail 5 'Im angegebenen Ordner ist kein Planet Coaster 2.'
    else GAME=$(find_game); [[ -n $GAME ]] || fail 5 'Planet Coaster 2 nicht gefunden. Mit --game-dir "<Spielordner>" starten.'; fi
    say "Spielordner: $GAME"
    case $action in
        status) printf 'result=ok installed=%s version=%s acse=%s\n' \
                    "$([[ -f $GAME/Win64/ovldata/PC2CoopProbe/Main.ovl ]] && echo yes || echo no)" "$(installed_version)" \
                    "$([[ -f $GAME/Win64/ovldata/ACSE/Main.ovl || -d $GAME/Win64/ovldata/ACSEDebug ]] && echo yes || echo no)" ;;
        uninstall) uninstall ;;
        install)
            if [[ -z $source ]]; then
                if [[ -f $SCRIPT_DIR/payload-manifest.json ]]; then source=$SCRIPT_DIR
                elif [[ -f $SCRIPT_DIR/PC2Coop/payload-manifest.json ]]; then source=$SCRIPT_DIR/PC2Coop; fi
            fi
            if [[ -n $source ]]; then install_package "$source"; else install_latest; fi ;;
    esac
}

main "$@"
