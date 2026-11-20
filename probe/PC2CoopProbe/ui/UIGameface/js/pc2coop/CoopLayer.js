// Original MIT code (PC2 Co-op). Multiplayer layer inside the game's own HUD/FrontEnd
// views, using the game's components so it looks and feels native:
//   - lobby panel (player slots, where to play, content check, chat, friends, status),
//     the same in the main menu and in a park
//   - small lobby card in a corner of the main menu while the panel is closed
//   - player bar (top right), toasts, "Multiplayer" in the pause menu and main menu
// Data: Lua publishes JSON in DataStore ['pc2coop'].state; requests go back through
// ['pc2coop'].request as "<counter>|<command>|<argument>".
import { Icon } from '/js/common/components/Icon.js';
import * as DS from '/js/common/core/DataStore.js';
import * as Engine from '/js/common/core/Engine.js';
import { translate } from '/js/common/core/Localisation.js';
import * as preact from '/js/common/lib/preact.js';
import { Button } from '/js/project/components/Button.js';
import { Dialog } from '/js/project/components/Dialog.js';
import { InputField } from '/js/project/components/InputField.js';
import { Tab } from '/js/common/components/Tab.js';
import { loadCSS } from '/js/common/util/CSSUtil.js';
import { CloseButton } from '/js/project/components/CloseButton.js';
import { TooltipContainer } from '/js/project/components/Tooltip.js';
import { AnchorLocation, TargetLine } from '/js/common/components/Constraint.js';
import { ToggleRow } from '/js/project/components/ToggleRow.js';
import { ListStepperRow } from '/js/project/components/ListStepperRow.js';

// The window in a park uses the classes of the game's Panel and TabBar (TP-11). Their style sheets
// come with those components; the components themselves are not used (focus handling).
try { loadCSS('project/components/panel/Panel'); loadCSS('project/components/TabBar'); } catch (error) { /* look only */ }

const CONTEXT = ['pc2coop'];
let requestCounter = 0;
let currentState = {};
const listeners = new Set();

// Literal text for the game's translated components. ':' separates the token's fields, so
// a colon inside the text is replaced (a dialog with one in its description did not show).
function literal(text) {
    return '[STRING_LITERAL:Value=|' + String(text).replace(/[|\[\]]/g, '').replace(/\s*:\s*/g, ' - ') + '|]';
}

export function request(command, argument) {
    requestCounter += 1;
    try {
        Engine.sendEvent('PC2Coop_Request', requestCounter + '|' + command + '|' + (argument ?? ''));
    } catch (error) {
        log('request failed ' + error);
    }
}

// In the game the DataStore is C++-backed: read through property listeners (setValue,
// createContext and __doesContextExist only work in the development player).
function applyState(raw) {
    if (typeof raw !== 'string' || raw === currentState.__raw) return;
    try {
        currentState = JSON.parse(raw);
        currentState.__raw = raw;
        listeners.forEach((fn) => fn(currentState));
    } catch (error) {
        log('bad state ' + error);
    }
}

// Profile pictures (sid -> base64 PNG) come in their own element: they rarely change.
let avatars = {};
function applyAvatars(raw) {
    if (typeof raw !== 'string' || raw === avatars.__raw) return;
    try {
        avatars = JSON.parse(raw);
        avatars.__raw = raw;
    } catch (error) { log('bad avatars ' + error); return; }
    listeners.forEach((fn) => { try { fn(currentState); } catch (error) { log('avatar update ' + error); } });
}

let stateListener, avatarListener;
function subscribe() {
    if (stateListener === undefined) {
        try {
            stateListener = DS.getPropertyListener(CONTEXT, 'state', applyState);
            log('subscribed to state');
        } catch (error) {
            stateListener = undefined;
        }
    }
    if (avatarListener === undefined) {
        try { avatarListener = DS.getPropertyListener(CONTEXT, 'avatars', applyAvatars); } catch (error) { avatarListener = undefined; }
    }
}

// DLC packs: this game's owned mask goes to Lua (Lua compares the players); names for the panel.
let dlcModule = null;
function reportDlc() {
    if (!dlcModule || !currentState.available) return;
    const mask = Number(dlcModule.getOwnedDLCBitmask()) || 0;
    if (currentState.dlc !== mask) request('dlc', String(mask));
}

function dlcPacks() {
    try { return (dlcModule && dlcModule.getPaidDLCPacks()) || []; } catch (error) { return []; }
}

function owns(mask, id) {
    return mask !== undefined && mask !== null && Math.floor(Number(mask) / Number(id)) % 2 === 1;
}

function packName(pack) {
    try { return translate(pack.label); } catch (error) { return pack.name; }
}

let polls = 0;
// The game's tooltips above our layer: they live in a Layer_root of the game's LayerCollection,
// which has no z-index of its own, while our root has 10000 - a tooltip over the window or the
// player bar was drawn under them. Only the tooltip layer is raised, not the game's other layers.
function raiseTooltips() {
    let el = document.getElementsByClassName('TooltipContainer').item(0);
    while (el && String(el.className || '').indexOf('Layer_root') < 0) el = el.parentElement;
    if (el && el.style.zIndex !== '10001') el.style.zIndex = '10001';
}

function poll() {
    subscribe();
    try { raiseTooltips(); } catch (error) { /* tooltips stay where the game puts them */ }
    try { applyState(DS.getValue(CONTEXT, 'state')); } catch (error) { /* context not created yet */ }
    try { applyAvatars(DS.getValue(CONTEXT, 'avatars')); } catch (error) { /* not there yet */ }
    polls += 1;
    if (polls % 10 === 1) reportDlc();
    // Accent colour, colour-blind mode: about once a second; a change redraws the layer at once
    // (before, the old colours stayed until the next state change).
    if (polls % 3 === 1 && refreshPalette()) {
        listeners.forEach((fn) => { try { fn(currentState); } catch (error) { log('palette update ' + error); } });
    }
}

// Main menu screens the host picks a park from (loaded on demand: they exist only there).
let nav = null;

class StateComponent extends preact.Component {
    componentDidMount() {
        // The revision forces a render: the game's Preact skips a setState with equal values.
        this._listener = (state) => this.setState({ coop: state, revision: (this.state.revision || 0) + 1 });
        listeners.add(this._listener);
        this.setState({ coop: currentState });
    }
    componentWillUnmount() {
        listeners.delete(this._listener);
    }
}

const ACTIVITY = { baut: 'baut', schaut: 'schaut zu', empfaengt: 'synchronisiert', laedt: 'lädt den Park', '-': 'verbindet' };

// What a player is doing; a joiner shows how far the park transfer is ("holt45").
function activityText(act, hold) {
    const receiving = /^holt(\d+)$/.exec(act || '');
    if (receiving) return 'empfängt den Park ' + receiving[1] + ' %';
    if (hold) return 'hält ' + prettyName(hold);
    return ACTIVITY[act] !== undefined ? ACTIVITY[act] : (act || '');
}

// "AQ_Rock_04" -> "Rock 04": resource names without their set prefix.
function prettyName(resource) {
    return String(resource).replace(/^[A-Za-z0-9]{2,5}_/, '').replace(/_/g, ' ');
}

// Park notifications arrive in the game's own text format and are translated here.
function shown(text) {
    if (typeof text === 'string' && text.charAt(0) === '[') {
        try { return translate(text); } catch (error) { return text; }
    }
    return text;
}

function money(park) {
    if (park.unlimited) return 'Geld unbegrenzt';
    return 'Geld ' + Math.round(park.cash).toLocaleString('de-DE');
}

const h = preact.h;
// The game's own UI font (same list as its style sheets).
const FONT = 'StandardFont, StandardFont_fallback1, StandardFont_fallback2, StandardFont_fallback3, StandardFont_fallback4, '
    + 'StandardFont_fallback5, StandardFont_fallback6, StandardFont_fallback7';
// Colours come from the game's CSS variables (accent colour and colour-blind modes of the player).
// They are read like the game's BibleColours.js does: Gameface ignored var() in the inline
// 'background' shorthand (2026-11-20, window without background); plain values work everywhere.
// Defaults = the game's default theme.
const PALETTE_DEFAULT = { accent: '#008ACC', alert: '#FF3363', neutral3: '#9cbad0',accentButtonDesaturatedDark: '#2b6e9c', accentButtonLight: '#81d3fd', accentFaint: '#cce8f5', accentLight: '#64bde8', accentText: '#0b3a56', area: '#E8EFF4', highlight: '#FFBB00', panel: '#FFFFFF', positive: '#00CA65', positiveDark: '#099340', warning: '#EE7722', warningDark: '#9b5000', whiteColor: '#FFFFFF',
    'accent-triplet': '0, 138, 204', 'accentPanelBackground-triplet': '0, 32, 61',
    // Tint for white game icons on light ground, as the game's filter: var(--accentText-filter).
    'accentText-filter': 'coh-color-matrix(0, 0, 0, 0, 0.0431372549, 0, 0, 0, 0, 0.2274509804, 0, 0, 0, 0, 0.337254902, 0, 0, 0, 1, 0)' };
const palette = Object.assign({}, PALETTE_DEFAULT);
// Returns true when a colour changed. Right after the game switches the class on <body> the old
// values are still returned (2026-11-20), so this runs regularly instead of once.
function refreshPalette() {
    let changed = false;
    try {
        const styles = getComputedStyle(document.body);
        for (const name in PALETTE_DEFAULT) {
            const value = String(styles.getPropertyValue('--' + name) || '').trim();
            const usable = /-triplet$/.test(name) ? /^\d{1,3}\s*,\s*\d{1,3}\s*,\s*\d{1,3}$/.test(value) : value !== '';
            const next = usable ? value : PALETTE_DEFAULT[name];
            if (palette[name] !== next) { palette[name] = next; changed = true; }
        }
    } catch (e) { /* keep the last colours */ }
    return changed;
}
const C = (name) => palette[name] || PALETTE_DEFAULT[name];
// A game icon from /img/icons/. The game's Icon component ignores 'style' and gets its size only from
// CSS classes, so icons drawn with it had no size (2026-11-20). white: tint for dark backgrounds.
const glyph = (src, size, white, extra) => h('div', { style: Object.assign({ width: size, height: size, flexShrink: 0,
    backgroundImage: 'url(/' + src + ')', backgroundSize: 'contain', backgroundRepeat: 'no-repeat', backgroundPosition: 'center',
    filter: white ? 'brightness(0) invert(1)' : 'none' }, extra || {}) });
// Sizes follow the game's UI scale: 1rem = 20px at 1080p (UIScaleConfig.js), see docs/ui-ux/NATIVE_UI.md.
const rem = (px) => (Math.round(px / 20 * 1000) / 1000) + 'rem';
const remPx = () => parseFloat(document.documentElement.style.fontSize) || 20;
// Notice colours from Lua stand for a meaning (warning, wait, hint): they follow the game palette, so
// accent colour and colour-blind modes apply. Any other value is used as it is.
const NOTICE_TONE = { ff922b: 'warning', fcc419: 'highlight', ffd43b: 'highlight', '51cf66': 'positive', '4dabf7': 'accentLight', '00c6ff': 'accentLight' };
const noticeColor = (hex) => (hex && NOTICE_TONE[String(hex).toLowerCase()] ? C(NOTICE_TONE[String(hex).toLowerCase()])
    : hex ? '#' + hex : C('accentLight'));
// HUD background like the game's rgba(var(--accentPanelBackground-triplet), …): follows the accent colour.
const HUD_BG = (alpha) => 'rgba(' + C('accentPanelBackground-triplet') + ', ' + alpha + ')';
// The accent colour with transparency (lines, frames), rgba(var(--accent-triplet), …) in the game.
const ACCENT_A = (alpha) => 'rgba(' + C('accent-triplet') + ', ' + alpha + ')';

// Building blocks (docs/ui-ux/DESIGN_SYSTEM.md A6). HUD pill and HUD card: HUD background, white text.
const hudPill = (extra, alpha) => Object.assign({ display: 'flex', alignItems: 'center', padding: '0.25rem 0.6rem', borderRadius: '1rem',
    backgroundColor: HUD_BG(alpha || 0.85), color: C('whiteColor'), fontSize: '0.9rem' }, extra || {});
const hudCard = (extra, alpha) => Object.assign({ borderRadius: '0.5rem', backgroundColor: HUD_BG(alpha || 0.85), color: C('whiteColor'),
    fontSize: '0.9rem' }, extra || {});

// Profile pictures: the DLL sends an uncompressed PNG (stored zlib blocks, no row filters).
// Gameface shows no data: URLs, so the pixels are read here and painted on a canvas.
const B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
function fromBase64(text) {
    const out = [];
    let bits = 0, value = 0;
    for (let i = 0; i < text.length; i++) {
        const v = B64.indexOf(text.charAt(i));
        if (v < 0) continue;
        value = (value << 6) | v;
        bits += 6;
        if (bits >= 8) { bits -= 8; out.push((value >> bits) & 255); }
    }
    return out;
}

const pixelCache = {};
function avatarPixels(data) {
    if (pixelCache[data] !== undefined) return pixelCache[data];
    let result = null;
    try {
        const b = fromBase64(data);
        const u32 = (at) => ((b[at] << 24) >>> 0) + (b[at + 1] << 16) + (b[at + 2] << 8) + b[at + 3];
        let at = 8, w = 0, h = 0;
        const raw = [];
        while (at + 8 <= b.length) {
            const len = u32(at), type = String.fromCharCode(b[at + 4], b[at + 5], b[at + 6], b[at + 7]);
            const body = at + 8;
            if (type === 'IHDR') { w = u32(body); h = u32(body + 4); }
            if (type === 'IDAT') {
                let p = body + 2;
                while (p + 5 <= body + len) {
                    const final = b[p] & 1, n = b[p + 1] + (b[p + 2] << 8);
                    for (let i = 0; i < n; i++) raw.push(b[p + 5 + i]);
                    p += 5 + n;
                    if (final) break;
                }
            }
            at = body + len + 4;
        }
        if (w > 0 && h > 0 && w <= 64 && h <= 64 && raw.length >= h * (w * 4 + 1)) result = { w, h, raw };
    } catch (error) { result = null; }
    pixelCache[data] = result;
    return result;
}

function attached(el) {
    for (let node = el; node; node = node.parentNode) if (node === document.body) return true;
    return false;
}

// Painted once the canvas is in the page (a detached canvas loses what is drawn on it).
function paintAvatar(canvas, data, tries) {
    if (!canvas || canvas.__pc2coop === data) return;
    if (!attached(canvas)) {
        if ((tries || 0) < 40) setTimeout(() => paintAvatar(canvas, data, (tries || 0) + 1), 50);
        return;
    }
    canvas.__pc2coop = data;
    const pic = avatarPixels(data);
    if (!pic) return;
    try {
        const ctx = canvas.getContext('2d');
        for (let y = 0; y < pic.h; y++) {
            const row = y * (pic.w * 4 + 1) + 1;
            for (let x = 0; x < pic.w; x++) {
                const i = row + x * 4;
                ctx.fillStyle = 'rgba(' + pic.raw[i] + ',' + pic.raw[i + 1] + ',' + pic.raw[i + 2] + ',' + (pic.raw[i + 3] / 255) + ')';
                ctx.fillRect(x, y, 1, 1);
            }
        }
    } catch (error) { log('avatar paint ' + error); }
}

// Painted after it is in the page and again when the picture changes. Preact reuses removed
// canvas elements (cleared, but still marked as painted), so a fresh mount always repaints.
class AvatarCanvas extends preact.Component {
    componentDidMount() { this.paint(true); }
    componentDidUpdate(previous) { this.paint(previous.data !== this.props.data); }
    paint(fresh) {
        const canvas = this.base;
        if (!canvas) return;
        if (fresh) canvas.__pc2coop = undefined;
        paintAvatar(canvas, this.props.data);
    }
    render(props) {
        const pic = avatarPixels(props.data);
        return h('canvas', { width: pic ? pic.w : 1, height: pic ? pic.h : 1,
            style: { position: 'absolute', left: 0, top: 0, width: rem(props.size), height: rem(props.size) } });
    }
}

// Round profile picture; the player's colour and initial show while Steam has none.
function Avatar(props) {
    const p = props.player;
    const size = props.size || 40;
    // Passed in as a prop: the game's Preact re-renders a component only when its props change.
    const pic = props.pic;
    return h('div', { style: { position: 'relative', width: rem(size), height: rem(size), borderRadius: rem((size / 2)),
        backgroundColor: '#' + (p.color || '6a8899'), color: C('whiteColor'), fontSize: rem(Math.round(size * 0.5)), lineHeight: rem(size),
        textAlign: 'center', overflow: 'hidden', flexShrink: 0, border: '0.1rem solid #' + (p.color || '6a8899') } },
        (p.name || '?').substring(0, 1).toUpperCase(),
        pic && avatarPixels(pic) ? h(AvatarCanvas, { data: pic, size }) : null);
}

function list(value) { return Array.isArray(value) ? value : []; }

function hostOf(coop) { return list(coop.players).find((p) => p.host); }

// DLC packs of the host a player does not own (null: not known yet).
function missingPacks(host, player) {
    if (!host || host.dlc === undefined || player.dlc === undefined) return null;
    return dlcPacks().filter((pack) => owns(host.dlc, pack.id) && !owns(player.dlc, pack.id));
}

function contentLine(coop, p) {
    const host = hostOf(coop);
    if (p.host) return null;
    const missing = missingPacks(host, p);
    const hostMods = list(host && host.mods);
    const mods = list(p.mods);
    const lacking = hostMods.filter((m) => mods.indexOf(m) < 0);
    const extra = mods.filter((m) => hostMods.indexOf(m) < 0);
    const parts = [];
    if (missing && missing.length) parts.push('fehlt: ' + missing.map(packName).join(', '));
    if (lacking.length) parts.push('Mods fehlen: ' + lacking.join(', '));
    if (extra.length) parts.push('weitere Mods: ' + extra.join(', '));
    if (parts.length) return { text: parts.join(' · '), warn: true };
    if (missing === null) return { text: 'Inhalte werden geprüft ...', warn: false };
    return { text: 'Inhalte wie der Host', warn: false };
}

function statusOf(coop) {
    const join = coop.join || {};
    const players = list(coop.players);
    const host = hostOf(coop);
    if (!coop.available) return { text: 'Steam ist nicht verfügbar.', tone: 'warn' };
    if (join.phase === 'failed') return { text: join.reason, tone: 'warn' };
    if (join.phase === 'hostlobby') return { text: (join.host || 'Der Host') + ' ist zurück im Hauptmenü und wählt einen Park. Geh auch ins Hauptmenü, um dabeizubleiben.', tone: 'wait' };
    if (join.phase && ['live', 'lobby', 'rejoin'].indexOf(join.phase) < 0) return { text: joinText(join), tone: 'busy' };
    if (!coop.role) {
        return { text: coop.context === 'menu' ? 'Starte eine Sitzung oder tritt einem Freund bei.'
            : 'Starte eine Sitzung – Freunde treten bei und bauen mit.', tone: 'idle' };
    }
    if (coop.desync) return { text: 'Nicht mehr synchron: ' + coop.desync + (coop.role === 'client' ? ' - "Neu synchronisieren" lädt den Park des Hosts erneut.' : ''), tone: 'warn' };
    if (coop.stage === 'lobby') {
        const choice = coop.choice;
        const hostName = host ? host.name : 'Der Host';
        if (choice && choice.starting) return { text: hostName + ' öffnet ' + choice.title + ' - gleich lädt er bei allen.', tone: 'busy' };
        if (coop.role === 'host') {
            return { text: choice ? 'Ausgewählt: ' + choice.title + '. "Park öffnen" startet für alle.' : 'Wähle, wo ihr spielt. Alle sehen deine Auswahl.', tone: 'wait' };
        }
        return { text: choice ? hostName + ' hat gewählt: ' + choice.title + ' (' + choice.detail + ').' : hostName + ' wählt gerade, wo ihr spielt ...', tone: 'wait' };
    }
    const loading = players.filter((p) => /^holt/.test(p.act || '') || p.act === 'laedt' || p.act === 'lobby');
    if (loading.length) return { text: loading.map((p) => p.name).join(', ') + (loading.length > 1 ? ' laden' : ' lädt') + ' den Park ...', tone: 'busy' };
    return { text: 'Alle verbunden' + (coop.parkTitle ? ' - ' + coop.parkTitle : '') + '.', tone: 'ok' };
}

const TONE = { get ok() { return C('positive'); }, get busy() { return C('accentLight'); }, get wait() { return C('highlight'); },
    get warn() { return C('warning'); }, get idle() { return C('neutral3'); } };

const ACT_LOBBY = 'im Hauptmenü';

function playerActivity(coop, p) {
    if (p.act === 'lobby') return coop.stage === 'park' ? 'wartet auf den Park' : ACT_LOBBY;
    if (coop.stage === 'lobby') return ACT_LOBBY;
    return activityText(p.act, p.hold);
}

// A box that shows the game's tooltip while the mouse is over it (as Button does with tooltipOnHover).
class HoverTip extends preact.Component {
    render(props, state) {
        return h('div', { className: props.className, style: props.style, onClick: props.onClick,
            onMouseEnter: this.enter, onMouseLeave: this.leave },
            props.children,
            state.hover && props.tip && h(TooltipContainer, { target: this, tooltip: literal(props.tip), anchor: props.anchor, modifiers: 'wide' }));
    }
    enter = () => { this.setState({ hover: true }); setTimeout(() => { try { raiseTooltips(); } catch (error) { /* look only */ } }, 200); };
    leave = () => this.setState({ hover: false });
}

// Tooltip left of the box, centred on it (as the game's AtmosphereDropdown): above, the game's
// default, it ran over the right screen edge in the top right corner.
const TIP_LEFT = [{ location: AnchorLocation.Left, line: TargetLine.End }, { location: AnchorLocation.CenterV, line: TargetLine.Center }];

// State of a player as a game icon (TP-13); the words are in the tooltip.
function stateIcon(coop, p, following) {
    const act = String(p.act || '-');
    if (following) return 'eye';
    if (act === 'lobby' || coop.stage === 'lobby' || act === 'laedt' || act === '-') return 'clock';
    if (/^holt/.test(act) || act === 'empfaengt') return 'downloadArrow';
    if (coop.visitor && coop.visitor.emotes && coop.visitor.emotes[p.sid]) return null;
    if (p.hold) return 'move';
    if (act === 'baut') return 'building';
    if (act === 'schaut') return 'camera';
    return null;
}

// Session cluster, top right (UX_OVERHAUL.md §6): players with avatar, name, crown and a state
// icon; what they do is in the tooltip (TP-13), not cut off in the line. The competition clock
// below. The same place in building, visiting and riding; on a ride only the avatars, because
// the game's ride camera panel shares the corner.
class PlayerBar extends StateComponent {
    render(props, state) {
        const coop = state.coop || {};
        if (!coop.role || coop.context === 'menu' || list(coop.players).length === 0) return null;
        const compact = !!(coop.visitor && coop.visitor.riding);
        const comp = coop.team && coop.team.competition;
        const s = comp ? (comp.left || 0) : 0;
        // stretch: all pills as wide as the widest, so a tooltip left of one is not under another.
        return h('div', { style: { position: 'absolute', top: '4.2rem', right: '1rem', display: 'flex', flexDirection: 'column',
            alignItems: 'stretch' } },
            list(coop.players).map((p) => {
                const following = coop.following === p.sid;
                const activity = (coop.visitor && coop.visitor.emotes && coop.visitor.emotes[p.sid]) || playerActivity(coop, p);
                const icon = stateIcon(coop, p, following);
                // No colon: literal() turns it into a dash.
                const tip = p.name + ' – ' + activity + (p.me ? '' : following ? ' · Klicken beendet das Folgen' : ' · Klicken zum Folgen');
                return h(HoverTip, { key: p.sid, className: 'pc2coopTip', tip, anchor: TIP_LEFT, onClick: p.me ? undefined : () => request('follow', p.sid),
                    style: { display: 'flex', alignItems: 'center', margin: '0.15rem 0', pointerEvents: 'auto',
                    padding: compact ? '0.2rem' : '0.2rem 0.6rem 0.2rem 0.2rem', borderRadius: '1rem', backgroundColor: HUD_BG(0.72),
                    borderWidth: '0.1rem', borderStyle: 'solid', borderColor: following ? C('highlight') : 'transparent' } },
                    h(Avatar, { player: p, size: 28, pic: avatars[p.sid] }),
                    !compact && h('div', { style: { color: C('whiteColor'), fontSize: '0.9rem', marginLeft: '0.45rem' } }, p.name + (p.me ? ' (du)' : '')),
                    !compact && p.host && glyph('img/icons/crown.svg', '0.9rem', true, { marginLeft: '0.35rem' }),
                    !compact && icon && glyph('img/icons/' + icon + '.svg', '0.9rem', true, { marginLeft: '0.4rem',
                        opacity: following ? 1 : 0.75 }));
            }),
            comp && comp.phase === 'build' && !compact && h('div', { style: hudPill({ marginTop: '0.3rem' }) },
                glyph('img/icons/clock.svg', '0.9rem', true, { marginRight: '0.4rem' }),
                comp.label + (comp.topic ? ' · ' + comp.topic : '') + ' · ' + Math.floor(s / 60) + ':' + (s % 60 < 10 ? '0' : '') + (s % 60)));
    }
}

// Visitor mode: walk through the park as a guest, ride along, rate rides, emote. A small
// bar at the top centre; "Fahrgeschäfte" unfolds the rides with stats and ratings.
const EMOTE_BUTTONS = [['wave', 'Winken'], ['cheer', 'Jubeln'], ['laugh', 'Lachen'], ['up', 'Super'], ['down', 'Naja'], ['sick', 'Übel']];
const one = (v) => (typeof v === 'number' ? (Math.round(v * 10) / 10).toFixed(1) : '-');

class VisitorBar extends StateComponent {
    state = { picked: null, stars: {}, draft: '' };
    render(props, state) {
        const coop = state.coop || {};
        const visitor = coop.visitor;
        if (!visitor || !visitor.active || coop.context === 'menu' || coop.open) return null;
        const pill = { display: 'flex', flexDirection: 'column', alignItems: 'center', padding: '0.3rem 0.5rem', borderRadius: '0.9rem',
            backgroundColor: HUD_BG(0.82), color: C('whiteColor'), fontSize: '0.9rem' };
        const bar = h('div', { style: pill },
            visitor.active && h('div', { style: { margin: '0 0 0.2rem', color: C('accentButtonLight') } },
                visitor.riding ? 'Du fährst ' + visitor.riding + ' - "Zurück" unten rechts steigt aus'
                    : visitor.guest ? 'Ich-Sicht: WASD laufen, Alt springen, Strg ducken, L Lampe, Eingänge wie im Spiel · E Shop · T Emotes · V Ansicht von hinten · Tab zurück'
                    : 'Besucher: Maus umsehen · WASD laufen · Shift rennen · E Eingang oder Shop · T Emotes · V Ich-Sicht · Tab zurück'),
            // A shop's buy list: 1-6 buy, E or Tab close (names are the game's loc keys).
            visitor.shop && h('div', { style: { display: 'flex', flexDirection: 'column', margin: '0 0 0.3rem', padding: '0.3rem 0.5rem',
                    borderRadius: '0.5rem', backgroundColor: 'rgba(255, 255, 255, 0.08)' } },
                h('div', { style: { color: C('highlight'), margin: '0 0 0.2rem' } }, 'Kaufen: Taste 1-6 oder anklicken · E schließt'),
                ...list(visitor.shop.items).map((it) => h('div', { key: 'buy' + it.n, onClick: () => request('buy', String(it.n)),
                        style: { display: 'flex', justifyContent: 'space-between', padding: '0.1rem 0', cursor: 'pointer' } },
                    h('span', { style: { margin: '0 0.4rem 0 0', color: C('accentButtonLight') } }, it.n + ''),
                    h('span', { style: { flexGrow: 1 } }, (it.name && shown(it.name)) || it.fallback),
                    h('span', { style: { margin: '0 0 0 0.6rem' } }, it.price)))),
            // What E does at the entrance in front, in the game's own words (loc keys).
            visitor.active && !visitor.guest && visitor.hint && h('div', { style: { display: 'flex', margin: '0 0 0.2rem', color: C('highlight') } },
                h('span', { style: { margin: '0 0.3rem 0 0' } }, 'E:'), h('span', null, shown(visitor.hint.action)),
                visitor.hint.blocker && h('span', { style: { margin: '0 0 0 0.3rem', color: C('warning') } }, shown(visitor.hint.blocker))),
            buttons([
                !visitor.active && { label: 'Als Besucher losgehen', onSelect: () => request('visitor', '1') },
                ...(visitor.active && coop.role ? EMOTE_BUTTONS.map(([kind, label]) => ({ label, onSelect: () => request('emote', kind) })) : []),
                { label: visitor.list ? 'Liste schließen' : 'Fahrgeschäfte', onSelect: () => request('visitorlist', visitor.list ? '0' : '1') },
                visitor.active && !visitor.riding && { label: visitor.guest ? 'Ansicht von hinten' : 'Ich-Sicht', onSelect: () => request('view', '1') },
                visitor.active && { label: 'Zurück zum Bauen', onSelect: () => request('visitor', '0') },
            ]));
        const rides = list(visitor.rides);
        const picked = rides.find((r) => r.key === state.picked);
        const panel = visitor.list && h('div', { style: { width: '50rem', marginTop: '0.4rem', borderRadius: '0.6rem', overflow: 'hidden',
            backgroundColor: C('panel'), color: C('accentText'), fontSize: '0.9rem' } },
            h('div', { style: { height: '2.2rem', lineHeight: '2.2rem', padding: '0 0.9rem', backgroundColor: C('accent'), color: C('whiteColor'), fontSize: '1rem' } },
                'Fahrgeschäfte im Park - nächstes zuerst'),
            box(picked && coop.role ? 330 : 400, rides.length === 0
                ? h('div', { style: { padding: '0.9rem', color: C('accentButtonDesaturatedDark') } }, 'Noch keine Fahrgeschäfte im Park.')
                : rides.map((r) => {
                    const mine = state.stars[r.key] || r.mine;
                    const stats = typeof r.e === 'number'
                        ? 'Spaß ' + one(r.e) + '  ·  Angst ' + one(r.f) + '  ·  Übelkeit ' + one(r.n)
                        : 'noch nicht getestet';
                    const extra = [r.dist !== false ? r.dist + ' m' : null, typeof r.queue === 'number' ? Math.round(r.queue) + ' in der Schlange' : null,
                        r.trains ? r.trains + ' Züge' : null].filter(Boolean).join('  ·  ');
                    return h('div', { key: r.key, style: { padding: '0.4rem 0.9rem', borderBottom: '0.05rem solid ' + ACCENT_A(0.15),
                        backgroundColor: state.picked === r.key ? C('area') : 'transparent' } },
                        h('div', { style: { display: 'flex', justifyContent: 'space-between', alignItems: 'center' } },
                            h('div', { style: { width: '26rem' } },
                                h('div', { style: { fontSize: '1rem' } }, r.name + '  ', h('span', { style: { color: C('accentButtonDesaturatedDark'), fontSize: '0.9rem' } }, r.kind)),
                                h('div', { style: { color: C('accentButtonDesaturatedDark'), fontSize: '0.9rem' } }, stats + (extra ? '  ·  ' + extra : '')),
                                h('div', { style: { color: C('accent'), fontSize: '0.9rem' } },
                                    r.count ? 'Bewertung ' + one(r.avg) + ' / 5 (' + r.count + ')' : 'noch keine Bewertung')),
                            buttons([
                                { label: 'Mitfahren', onSelect: () => request('ride', r.key) },
                                ...(coop.role ? [1, 2, 3, 4, 5].map((n) => ({ label: (mine === n ? '(' + n + ')' : String(n)),
                                    onSelect: () => {
                                        this.setState({ picked: r.key, stars: { ...state.stars, [r.key]: n } });
                                        request('rate', r.key + '|' + n + '|');
                                    } })) : []),
                            ])),
                        list(r.comments).slice(-2).map((c, i) => h('div', { key: 'c' + i, style: { color: C('accentText'), fontSize: '0.9rem', marginTop: '0.15rem' } },
                            c.who + ' (' + c.stars + '/5): ' + c.text)));
                })),
            picked && coop.role && h('div', { style: { padding: '0.5rem 0.9rem', backgroundColor: C('area') } },
                h(InputField, { text: state.draft, promptText: literal('Vorschlag zu ' + picked.name), maxInputLength: 120,
                    beginEditOnSelect: true, onChange: (e) => this.setState({ draft: (e && e.text) || '' }), onCommit: (e) => {
                        const text = String((e && e.text) || '').trim().split('|').join(' ');
                        this.setState({ draft: '' });
                        const stars = state.stars[picked.key] || picked.mine;
                        if (text && stars) request('rate', picked.key + '|' + stars + '|' + text);
                    }, onCancel: () => this.setState({ draft: '' }) })));
        return h('div', { style: { position: 'absolute', top: '2.6rem', left: '50%', width: '50rem', marginLeft: '-25rem',
            display: 'flex', flexDirection: 'column', alignItems: 'center', pointerEvents: 'auto' } }, bar, panel);
    }
}

// Visitor mode: T held shows the emote wheel; the mouse (or 1-6) picks, letting go of T sends.
const WHEEL = [['Winken', 0], ['Jubeln', 1], ['Lachen', 2], ['Super', 3], ['Naja', 4], ['Übel', 5]];
class EmoteWheel extends StateComponent {
    render(props, state) {
        const coop = state.coop || {};
        const wheel = coop.visitor && coop.visitor.wheel;
        if (!wheel) return null;
        const radius = 150;
        return h('div', { style: { position: 'absolute', left: '50%', top: '50%', width: '0px', height: '0px' } },
            WHEEL.map(([label, i]) => {
                const angle = i * Math.PI / 3;
                const on = wheel.selected === i + 1;
                return h('div', { key: label, style: { position: 'absolute', left: rem((Math.sin(angle) * radius - 70)),
                    top: rem((-Math.cos(angle) * radius - 24)), width: '7rem', height: '2.4rem', lineHeight: '2.4rem', textAlign: 'center',
                    borderRadius: '1.2rem', fontSize: '1rem', backgroundColor: on ? C('accent') : HUD_BG(0.85), color: C('whiteColor'),
                    borderWidth: '0.1rem', borderStyle: 'solid', borderColor: on ? C('whiteColor') : 'rgba(255, 255, 255, 0.25)' } }, (i + 1) + '  ' + label);
            }),
            h('div', { style: { position: 'absolute', left: '-5.5rem', top: '-0.7rem', width: '11rem', textAlign: 'center', color: C('whiteColor'),
                fontSize: '0.9rem', textShadow: '0 0.05rem 0.15rem #000' } }, 'Maus bewegen, T loslassen'));
    }
}

// Everything that needs an answer, in one card at one place (UX_OVERHAUL.md TP-19): join requests
// (host), votes, test ride invitations, rating after a competition. One at a time, with a counter.
function pendingRequests(coop) {
    const team = coop.team || {};
    const out = [];
    if (coop.role === 'host') list(coop.requests).forEach((r) => out.push({ key: 'join' + r.sid, text: r.name + ' möchte beitreten.',
        actions: [{ label: 'Zulassen', modifiers: 'positive', onSelect: () => request('approve', r.sid) },
            { label: 'Ablehnen', onSelect: () => request('deny', r.sid) }] }));
    const vote = team.vote;
    if (vote) out.push({ key: 'vote', text: 'Abstimmung von ' + vote.by + ': ' + vote.text,
        note: vote.answered ? 'Deine Stimme ist abgegeben – warte auf die anderen.' : null,
        actions: vote.answered ? [] : [{ label: 'Ja', modifiers: 'positive', onSelect: () => request('vote', '1') },
            { label: 'Nein', onSelect: () => request('vote', '0') }] });
    const invite = team.invitation;
    if (invite) out.push({ key: 'invite', text: invite.by + ' lädt zur Testfahrt auf ' + invite.name + ' ein.',
        actions: [{ label: 'Mitfahren', modifiers: 'positive', onSelect: () => request('invitation', '1') },
            { label: 'Später', onSelect: () => request('invitation', '0') }] });
    const comp = team.competition;
    if (comp && comp.phase === 'rate' && list(comp.entries).some((e) => !e.me && !(e.d && e.t))) {
        out.push({ key: 'rate', text: 'Die Zeit ist um. Bewerte die Bauten der anderen.',
            actions: [{ label: 'Bewerten', modifiers: 'positive', onSelect: () => { request('paneltab', 'session'); request('open'); } }] });
    }
    return out;
}

class RequestCard extends StateComponent {
    render(props, state) {
        const coop = state.coop || {};
        if (coop.open) return null;
        const items = pendingRequests(coop);
        if (items.length === 0) return null;
        const item = items[0];
        return h('div', { key: item.key, style: { position: 'absolute', top: '7.5rem', left: '50%', width: '30rem', marginLeft: '-15rem',
            padding: '0.6rem 0.8rem', borderRadius: '0.5rem', backgroundColor: C('panel'), color: C('accentText'), fontSize: '1rem',
            boxShadow: '0 0 1.8rem rgba(0, 0, 0, 0.4)', pointerEvents: 'auto' } },
            h('div', { style: { display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' } },
                h('div', { style: { fontWeight: 'bold' } }, item.text),
                items.length > 1 && h('div', { style: { color: C('accentButtonDesaturatedDark'), fontSize: '0.9rem', marginLeft: '0.6rem',
                    whiteSpace: 'nowrap' } }, '1 von ' + items.length)),
            item.note && h('div', { style: { color: C('accentButtonDesaturatedDark'), fontSize: '0.9rem', marginTop: '0.3rem' } }, item.note),
            item.actions.length > 0 && h('div', { style: { marginTop: '0.4rem' } }, buttons(item.actions)));
    }
}

// The own connection to the host, only when something is wrong (UX_OVERHAUL.md TP-09): a pill at
// the top centre like the game's online notifications.
class ConnectionPill extends StateComponent {
    render(props, state) {
        const coop = state.coop || {};
        const join = coop.join || {};
        let pill = null;
        if (join.phase === 'silent') {
            pill = { icon: 'connectionStateDisconnected', tone: C('alert'), text: 'Keine Verbindung zum Host – warte …' };
        } else if (coop.desync && coop.role === 'client') {
            pill = { icon: 'warning', tone: C('warning'), text: 'Nicht synchron: ' + coop.desync,
                action: { label: 'Neu synchronisieren', onSelect: () => request('resync') } };
        } else if (join.phase === 'hostlobby') {
            pill = { icon: 'information', tone: C('accent'),
                text: (join.host || 'Der Host') + ' ist im Hauptmenü und wählt einen Park. Geh auch ins Hauptmenü, um dabeizubleiben.' };
        }
        if (!pill || coop.open) return null;
        return h('div', { style: { position: 'absolute', top: '5rem', left: '50%', width: '44rem', marginLeft: '-22rem',
            display: 'flex', justifyContent: 'center' } },
            h('div', { style: { display: 'flex', alignItems: 'center', padding: '0.35rem 0.5rem 0.35rem 0.8rem', borderRadius: '1.5rem',
                backgroundColor: pill.tone, color: C('whiteColor'), fontSize: '1rem', boxShadow: '0 0 0.5rem rgba(0, 0, 0, 0.3)',
                pointerEvents: 'auto' } },
                glyph('img/icons/' + pill.icon + '.svg', '1.2rem', true, { marginRight: '0.5rem' }),
                h('div', { style: { marginRight: pill.action ? '0.6rem' : '0.3rem' } }, pill.text),
                pill.action && buttons([pill.action])));
    }
}

// Where the mouse was last: the context menu opens there.
let mouseAt = null;
try { document.addEventListener('mousemove', (e) => { mouseAt = { x: e.clientX, y: e.clientY }; }); } catch (e) { mouseAt = null; }

// After an own mark (short middle click): what can be done at that spot, as a radial menu around
// the mouse in the look of the game's Alt radial menu (UX_OVERHAUL.md TP-15). The centre closes it.
const MARK_ITEMS = { invite: ['collaborate', 'Testfahrt mit allen'], ride: ['rideRider', 'Mitfahren'], comment: ['Pinned', 'Kommentar'],
    proposal: ['thumbsUp', 'Vorschlag'], area: ['pathArea', 'Baugebiet'], meet: ['marker', 'Treffpunkt'] };
class ContextMenu extends StateComponent {
    state = { hover: null };
    render(props, state) {
        const coop = state.coop || {};
        const ctx = coop.team && coop.team.context;
        if (!ctx || coop.open || (coop.visitor && coop.visitor.active)) { this.at = null; return null; }
        const key = ctx.x + ',' + ctx.z;
        if (!this.at || this.at.key !== key) {
            // Screen pixels (mouse); keep the whole circle (about 10 rem around) on screen.
            const w = window.innerWidth || 1920, hgt = window.innerHeight || 1080, margin = 11 * remPx();
            const m = mouseAt || { x: w / 2, y: hgt / 2 };
            this.at = { key, x: Math.min(Math.max(m.x, margin), w - margin), y: Math.min(Math.max(m.y, margin), hgt - margin) };
        }
        const items = [];
        if (ctx.ride) items.push(['invite', ...MARK_ITEMS.invite], ['ride', ...MARK_ITEMS.ride]);
        list(ctx.editors).forEach((e) => items.push(['take|' + e.sid, 'crossedTools', 'Übernahme von ' + e.name]));
        ['comment', 'proposal', 'area', 'meet'].forEach((k) => items.push([k, ...MARK_ITEMS[k]]));
        const radius = 7;
        return h('div', { style: { position: 'absolute', left: this.at.x + 'px', top: this.at.y + 'px', width: '0px', height: '0px' } },
            h('div', { style: { position: 'absolute', left: '-10rem', top: '-12.2rem', width: '20rem', display: 'flex', justifyContent: 'center' } },
                h('div', { style: { padding: '0.15rem 0.8rem', borderRadius: '0.5rem', backgroundColor: C('accent'), color: C('whiteColor'),
                    fontSize: '1.1rem', boxShadow: '0 0.1rem 0.2rem rgba(0, 0, 0, 0.2)' } }, ctx.ride ? ctx.ride.name : 'Markierung')),
            items.map(([arg, icon, label], i) => {
                const angle = i * 2 * Math.PI / items.length;
                const on = state.hover === arg;
                return h('div', { key: arg, onClick: () => request('ctx', arg), onMouseEnter: () => this.setState({ hover: arg }),
                    onMouseLeave: () => this.setState({ hover: null }),
                    style: { position: 'absolute', left: (Math.sin(angle) * radius - 4.5) + 'rem', top: (-Math.cos(angle) * radius - 1.8) + 'rem',
                        width: '9rem', display: 'flex', flexDirection: 'column', alignItems: 'center', pointerEvents: 'auto', cursor: 'pointer' } },
                    h('div', { style: { width: '3.4rem', height: '3.4rem', borderRadius: '1.7rem', display: 'flex', alignItems: 'center',
                        justifyContent: 'center', backgroundColor: on ? C('accent') : HUD_BG(0.85), boxShadow: '0 0 0.5rem rgba(0, 0, 0, 0.3)',
                        borderWidth: '0.15rem', borderStyle: 'solid', borderColor: on ? C('whiteColor') : 'rgba(255, 255, 255, 0.25)' } },
                        glyph('img/icons/' + icon + '.svg', '1.7rem', true)),
                    h('div', { style: { marginTop: '0.2rem', padding: '0.05rem 0.4rem', borderRadius: '0.35rem', backgroundColor: 'rgba(0, 0, 0, 0.45)',
                        color: C('whiteColor'), fontSize: '0.9rem', textAlign: 'center' } }, label));
            }),
            h('div', { onClick: () => request('ctx', 'close'), style: { position: 'absolute', left: '-1.4rem', top: '-1.4rem', width: '2.8rem',
                height: '2.8rem', borderRadius: '1.4rem', backgroundColor: HUD_BG(0.85), display: 'flex', alignItems: 'center',
                justifyContent: 'center', pointerEvents: 'auto', cursor: 'pointer' } }, glyph('img/icons/slimClose.svg', '1.1rem', true)));
    }
}

// A key as the game's input hints draw it: white outline, the key's name inside.
const keyCap = (label) => h('div', { style: { padding: '0 0.3rem', marginRight: '0.4rem', borderRadius: '0.25rem', borderWidth: '0.1rem',
    borderStyle: 'solid', borderColor: C('whiteColor') } }, label);
// Building block "Tastenhinweis": key and word (last: no gap after it), on the game's hint ground.
const keyHint = (key, word, last) => [keyCap(key), h('div', { style: { marginRight: last ? 0 : '0.9rem' } }, word)];
const hintBar = (extra, children) => h('div', { style: Object.assign({ display: 'flex', alignItems: 'center', padding: '0.3rem 0.4rem',
    borderRadius: '0.35rem', backgroundColor: 'rgba(0, 0, 0, 0.3)', color: C('whiteColor'), fontSize: '0.9rem' }, extra) }, children);

// Key hints like the game's input hints (bottom right, above the build bar): Enter opens the chat,
// the mark is the way to everything in the radial menu (TP-15, TP-22, UX-C1).
class MarkHint extends StateComponent {
    render(props, state) {
        const coop = state.coop || {};
        if (!coop.role || coop.context !== 'park' || coop.open || (coop.visitor && coop.visitor.active) || (coop.team && coop.team.context)) return null;
        return hintBar({ position: 'absolute', right: '1rem', bottom: '5.2rem' },
            [...keyHint('Enter', 'Chat'), ...keyHint('Mittelklick', 'Markieren', true)]);
    }
}

// Bottom left (TP-22): chat messages and what players did ("event"), fading out after a while;
// notices (warnings, answers) as cards above them. Enter (DLL "key:chat") opens the game's input
// field like a game chat: Enter sends, Esc or a click elsewhere closes, the draft stays.
const CHAT_SHOW_MS = 10000;
const NOTICE_SHOW_MS = 6000;
const chatFits = (coop) => !!coop.role && coop.context === 'park' && !coop.open;

class ChatArea extends StateComponent {
    state = { lines: [], notices: [], typing: false, draft: '' };
    componentDidMount() {
        super.componentDidMount();
        this._seen = 0;
        this._chatKey = null;
        this._closedAt = 0;
        this._foreignAt = 0;
        this._history = [];
        this._listenerChat = (coop) => { try { this.onCoop(coop || {}); } catch (error) { log('chat ' + error); } };
        listeners.add(this._listenerChat);
        this._listenerChat(currentState);
        this._timer = setInterval(() => { try { this.tick(); } catch (error) { log('chat tick ' + error); } }, 200);
    }
    componentWillUnmount() {
        super.componentWillUnmount();
        listeners.delete(this._listenerChat);
        clearInterval(this._timer);
        if (this.state.typing) request('chatinput', '0');
    }
    componentDidUpdate() {
        // Focus the game's input field once it is there; its own focus handler starts the edit.
        if (this.state.typing && !this._focused && this.base && this.base.querySelector) {
            const input = this.base.querySelector('input');
            if (input) {
                this._focused = true;
                this._input = input;
                input.focus();
            }
        }
    }
    onCoop(coop) {
        const fresh = (coop.toasts || []).filter((t) => t.id > this._seen);
        if (fresh.length) {
            this._seen = Math.max(...fresh.map((t) => t.id));
            const now = Date.now();
            const talk = (t) => t.kind === 'chat' || t.kind === 'event';
            const lines = fresh.filter(talk);
            this._history = [...this._history, ...lines].slice(-30);
            this.setState({
                lines: [...this.state.lines, ...lines.map((t) => ({ ...t, until: now + CHAT_SHOW_MS }))].slice(-6),
                notices: [...this.state.notices, ...fresh.filter((t) => !talk(t)).map((t) => ({ ...t, until: now + NOTICE_SHOW_MS }))].slice(-3) });
        }
        const key = coop.chatKey || 0;
        if (this._chatKey === null) this._chatKey = key;   // presses from before this view do not count
        else if (key !== this._chatKey) {
            this._chatKey = key;
            this.onEnter(coop);
        }
        if (this.state.typing && !chatFits(coop)) this.close(this.state.draft);
    }
    onEnter(coop) {
        const now = Date.now();
        // The same Enter also sends (the input field handles that itself) or confirms a text field
        // of the game: then the chat stays closed.
        if (this.state.typing || now - this._closedAt < 800 || now - this._foreignAt < 800 || !chatFits(coop)) return;
        this._focused = false;
        this.setState({ typing: true });
        request('chatinput', '1');
    }
    close(draft) {
        this._closedAt = Date.now();
        this._focused = false;
        this._input = null;
        this.setState({ typing: false, draft: draft || '' });
        request('chatinput', '0');
    }
    tick() {
        const active = document.activeElement;
        const tag = active && active.tagName ? String(active.tagName).toUpperCase() : '';
        if ((tag === 'INPUT' || tag === 'TEXTAREA') && active !== this._input) this._foreignAt = Date.now();
        const now = Date.now();
        const { lines, notices } = this.state;
        if (lines.some((t) => t.until < now) || notices.some((t) => t.until < now)) {
            this.setState({ lines: lines.filter((t) => t.until >= now), notices: notices.filter((t) => t.until >= now) });
        }
    }
    line(t) {
        const style = { padding: '0.1rem 0', fontSize: '0.9rem', color: C('whiteColor') };
        if (t.kind === 'chat') {
            // Gameface lays out every element as a flex box: name and text side by side, the text
            // wraps in its own column.
            const at = t.text.indexOf(': ');
            return h('div', { key: 'l' + t.id, style: { ...style, display: 'flex', flexDirection: 'row', alignItems: 'flex-start' } },
                at > 0 && h('div', { style: { color: '#' + (t.color || '9cbad0'), fontWeight: 'bold', flexShrink: 0, marginRight: '0.3rem' } }, t.text.slice(0, at) + ':'),
                h('div', { style: { flexGrow: 1, flexShrink: 1, minWidth: 0 } }, at > 0 ? t.text.slice(at + 2) : t.text));
        }
        return h('div', { key: 'l' + t.id, style: { ...style, color: C('neutral3') } }, t.loc ? shown(t.text) : t.text);
    }
    render(props, state) {
        const { notices, typing } = state;
        const lines = typing ? this._history.slice(-12) : state.lines;
        if (!typing && notices.length === 0 && lines.length === 0) return null;
        const coop = state.coop || {};
        // Right of the multiplayer window while it is open on the left edge (TP-11).
        const left = coop.open && coop.context === 'park' ? rem((PANEL_WIDTH + 1.2) * 20) : '1.2rem';
        return h('div', { style: { position: 'absolute', bottom: '6rem', left, width: '26rem', display: 'flex', flexDirection: 'column',
            alignItems: 'flex-start' } },
            notices.map((t) => h('div', { key: 'n' + t.id, style: hudCard({ margin: '0.2rem 0', padding: '0.5rem 0.8rem', maxWidth: '26rem',
                borderLeftWidth: '0.25rem', borderLeftStyle: 'solid', borderLeftColor: noticeColor(t.color) }, 0.82) },
                t.loc ? shown(t.text) : t.text)),
            (typing || lines.length > 0) && h('div', { style: hudCard({ alignSelf: 'stretch', marginTop: '0.2rem', padding: '0.4rem 0.6rem',
                pointerEvents: typing ? 'auto' : 'none' }, typing ? 0.85 : 0.55) },
                lines.length === 0 ? h('div', { style: { color: C('neutral3'), fontSize: '0.9rem' } }, 'Noch keine Nachrichten.') : lines.map((t) => this.line(t)),
                typing && h('div', { style: { marginTop: '0.4rem' } },
                    h(InputField, { text: state.draft, promptText: literal('Nachricht an alle'), maxInputLength: 200, modifiers: 'alt', commitOnCancel: false,
                        onChange: (e) => this.setState({ draft: (e && e.text) || '' }),
                        onCommit: (e) => {
                            const text = String((e && e.text) || '').trim();
                            this.close('');
                            if (text) request('chat', text);
                        },
                        onCancel: (e) => this.close((e && e.text) || '') })),
                typing && h('div', { style: { display: 'flex', alignItems: 'center', marginTop: '0.35rem', color: C('whiteColor'), fontSize: '0.9rem' } },
                    ...keyHint('Enter', 'Senden'), ...keyHint('Esc', 'Schließen', true))));
    }
}

const FRIEND_STATE = ['offline', 'online', 'beschäftigt', 'abwesend', 'abwesend', 'online', 'online'];
const SLOTS = 8;

// Where the lobby plays. Career and challenges need their own rules (shared goals), later.
const MODES = [
    { key: 'park', title: 'Eigener Park', text: 'Gespeicherten Park laden', screen: 'LoadPark', id: 2 },
    { key: 'franchise', title: 'Franchise', text: 'Park einer Franchise öffnen', screen: 'FranchiseMenu', id: 7 },
    { key: 'sandbox', title: 'Neuer Sandbox-Park', text: 'Karte und Regeln wählen', screen: 'SandboxStartMenu', id: 16 },
    { key: 'career', title: 'Karriere', text: 'kommt später', later: true },
    { key: 'challenge', title: 'Herausforderung', text: 'kommt später', later: true },
];

function openScreen(mode) {
    if (!nav || mode.later) return;
    request('close');
    const ids = nav.data && nav.data.FrontEndNavData && nav.data.FrontEndNavData.ScreenID;
    try { nav.nav.FrontEndNav.set(ids && ids[mode.screen] !== undefined ? ids[mode.screen] : mode.id); } catch (error) { log('nav ' + error); }
}

const section = (title, extra) => h('div', { style: { display: 'flex', alignItems: 'baseline', justifyContent: 'space-between',
    color: C('accent'), fontSize: '1rem', fontWeight: 'bold', margin: '0.8rem 0 0.4rem' } }, title, extra || null);

const row = (children, key) => h('div', { key, style: { display: 'flex', alignItems: 'center', justifyContent: 'space-between',
    flexWrap: 'wrap', padding: '0.25rem 0', borderBottom: '0.05rem solid ' + ACCENT_A(0.15) } }, children);

// wide: the group takes the whole row (narrow window: Gameface gave it too little width, the labels broke).
const buttons = (items, wide) => h('div', { style: { display: 'flex', flexWrap: 'wrap', justifyContent: 'flex-end', maxWidth: '100%',
    width: wide ? '100%' : 'auto' } },
    // flexShrink 0: in a narrow column a button moves to the next line instead of squeezing its text.
    items.filter(Boolean).map((b, i) => h('div', { key: 'b' + i, style: { margin: '0.1rem 0 0.1rem 0.3rem', maxWidth: '100%', flexShrink: 0 } },
        h(Button, { label: literal(b.label), onSelect: b.onSelect, disabled: b.disabled, inputName: b.inputName, modifiers: b.modifiers,
            tooltip: b.tip ? literal(b.tip) : undefined, tooltipOnHover: !!b.tip }))));

// The lobby: the same panel in the main menu and in a park. Three columns: players, where
// to play (or the park), chat and friends. Fixed sizes: Gameface does not shrink flex boxes.
const BIOMES = [['Temperate', 'Gemäßigt'], ['Mediterranean', 'Mediterran'], ['Taiga', 'Taiga'], ['Tropical', 'Tropisch']];
const box = (height, children, extra) => h('div', { style: Object.assign({ height: rem(height), overflowY: 'auto' }, extra || {}) }, children);

// Tabs of the multiplayer window in a park (docs/KONZEPT.md).
// Tabs of the window in a park (TP-11): key (as in ui.lua), tooltip, game icon. Visiting is a
// button in the build bar (TP-23), not a tab.
const PARK_TABS = [['team', 'Spieler', 'footerGuests'], ['plan', 'Planen', 'clipboard'], ['history', 'Verlauf', 'history'],
    ['session', 'Einstellungen', 'cog']];
const PANEL_WIDTH = 23.5;      // rem, like the game's info and tool panels
const PANEL_CONTENT = 26;      // rem, scrolls inside
const PANEL_TOP = 7.6;         // rem, below the game's round buttons top left (objectives, notifications)
const muted = (text, extra) => h('div', { style: Object.assign({ color: C('accentButtonDesaturatedDark'), fontSize: '0.9rem' }, extra || {}) }, text);
// Round icon button with tooltip, as in the game's info panels (LinkedObjectRow).
const iconButton = (icon, tip, onSelect, toggled) => h('div', { style: { marginLeft: '0.3rem', flexShrink: 0 } },
    h(Button, { icon: 'img/icons/' + icon + '.svg', modifiers: 'round centered mediumRound', tooltip: literal(tip), tooltipOnHover: true,
        toggled: !!toggled, onSelect }));
const BOARD_KINDS = [['task', 'Aufgabe'], ['area', 'Baugebiet'], ['proposal', 'Vorschlag'], ['comment', 'Kommentar'], ['meet', 'Treffpunkt']];
const BOARD_WORD = { task: 'Aufgabe', area: 'Baugebiet', proposal: 'Vorschlag', comment: 'Kommentar', meet: 'Treffpunkt' };
const BOARD_ICON = { task: 'clipboard', area: 'flag', proposal: 'thoughts', comment: 'pinActive', meet: 'marker' };
const AREA_SIZES = [10, 20, 40];
// A small info icon whose tooltip carries an explanation (TP-18, TP-20: no explanation texts on the page).
const infoTip = (tip, extra) => h(HoverTip, Object.assign({ tip }, extra || {}),
    glyph('img/icons/information.svg', '1.1rem', false, { filter: C('accentText-filter') }));
// Rules of the session (TP-20): key, row label, values, tooltip (the explanation lives there).
const RULES = [
    ['speed', 'Spieltempo und Pause', [['all', 'alle'], ['host', 'nur der Host']], 'Wer das Spieltempo ändern und pausieren darf.'],
    ['foreign', 'Fremde Bauten abreißen', [['free', 'erlaubt'], ['ask', 'erst fragen']],
        'Ob Mitspieler abreißen dürfen, was ein anderer gebaut hat, oder erst fragen.'],
    ['visitors', 'Besucher-Modus', [['1', 'erlaubt'], ['0', 'aus']], 'Ob Mitspieler als Besucher durch den Park gehen dürfen.'],
];
// The same sets as ui.lua rule_preset.
// Short words: the stepper in the narrow window cut "Locker zusammen bauen" (test copy).
const PRESETS = [['relaxed', 'Locker', { speed: 'all', foreign: 'free', visitors: '1' }],
    ['ordered', 'Geordnet', { speed: 'host', foreign: 'ask', visitors: '1' }],
    ['build', 'Nur bauen', { speed: 'host', foreign: 'ask', visitors: '0' }]];
const LOCKED = 'Nur der Host ändert Regeln.';
const END_TIP = 'Beendet die Sitzung für alle. Beim nächsten Mal lädst du den Park, und alle steigen wieder ein.';
const LEAVE_TIP = 'Der Park läuft beim Host weiter. Du kannst wieder beitreten.';

// "Für alle beenden?" (TP-30): asked before the host ends a session with other players in it.
let endAsked = false;
const endListeners = new Set();
function askEnd(on) { endAsked = !!on; endListeners.forEach((fn) => fn()); }
function endOrAsk(coop) {
    if (coop.role === 'host' && list(coop.players).length > 1) askEnd(true);
    else request('leave');
}
class EndConfirm extends preact.Component {
    componentDidMount() { this.update = () => this.forceUpdate(); endListeners.add(this.update); }
    componentWillUnmount() { endListeners.delete(this.update); }
    render() {
        if (!endAsked) return null;
        return h(Dialog, { modifiers: 'dialogApp', title: literal('Sitzung beenden'),
            description: literal('Für alle beenden? Alle Mitspieler verlassen dann den Park.'),
            buttons: [{ label: literal('Für alle beenden'), onSelect: () => { askEnd(false); request('leave'); } },
                { label: literal('Abbrechen'), onSelect: () => askEnd(false), inputName: 'UI_Cancel' }] });
    }
}

class Lobby extends StateComponent {
    state = { draft: '', tab: 'save', creative: true, kind: 'task', title: '', text: '', assignee: '', radius: 20 };
    render(props, state) {
        const coop = state.coop || {};
        if (!coop.open) return null;
        if (coop.context === 'park') return this.renderParkPanel(coop, state);
        const status = statusOf(coop);
        const host = hostOf(coop);
        const title = !coop.role ? 'Multiplayer'
            : coop.role === 'host' ? 'Deine Sitzung' : 'Sitzung von ' + (host ? host.name : 'Host');
        const footer = [];
        if (!coop.available) {
            // Nothing to do without Steam.
        } else if (!coop.role) {
            footer.push({ label: 'Sitzung starten', onSelect: () => request('host'), disabled: !coop.canHost });
        } else {
            if (coop.desync && coop.role === 'client') footer.push({ label: 'Neu synchronisieren', onSelect: () => request('resync') });
            footer.push({ label: 'Steam-Overlay', onSelect: () => request('invite_overlay') });
            footer.push({ label: coop.role === 'host' ? 'Beenden' : 'Verlassen', tip: coop.role === 'host' ? END_TIP : LEAVE_TIP,
                onSelect: () => endOrAsk(coop) });
        }
        footer.push({ label: 'Schließen', onSelect: () => request('close'), inputName: 'UI_Cancel' });
        const column = (width, children, last) => h('div', { style: { width: rem(width), height: '31.8rem', padding: '0 0.9rem',
            borderRight: last ? 'none' : '0.05rem solid ' + ACCENT_A(0.18) } }, children);
        return h('div', { style: { position: 'absolute', left: 0, top: 0, width: '100vw', height: '100vh', backgroundColor: 'rgba(0, 0, 0, 0.5)' } },
            h('div', { style: { position: 'absolute', left: '50%', top: '50%', width: '66rem', height: '39rem', marginLeft: '-33rem',
                marginTop: '-19.5rem', borderRadius: '0.7rem', overflow: 'hidden', backgroundColor: C('panel'), color: C('accentText'), fontSize: '1rem',
                boxShadow: '0 0.6rem 2rem rgba(0, 0, 0, 0.45)' } },
                h('div', { style: { display: 'flex', alignItems: 'center', height: '3.2rem', padding: '0 1.2rem', backgroundColor: C('accent'), color: C('whiteColor') } },
                    glyph('img/icons/collaborate.svg', '1.4rem', true, { marginRight: '0.6rem' }),
                    h('div', { style: { fontSize: '1.2rem', flexGrow: 1 } }, title),
                    coop.role && h('div', { style: { color: C('accentButtonLight'), fontSize: '1rem' } },
                        list(coop.players).length + ' / ' + SLOTS + ' Spieler' + (coop.stage === 'park' && coop.parkTitle ? ' · ' + coop.parkTitle : ''))),
                this.renderBody(coop, state, column),
                h('div', { style: { display: 'flex', alignItems: 'center', height: '4rem', padding: '0 1.2rem', backgroundColor: C('area'),
                    borderTop: '0.05rem solid ' + ACCENT_A(0.2) } },
                    h('div', { style: { width: '0.6rem', height: '0.6rem', borderRadius: '0.3rem', backgroundColor: TONE[status.tone] || TONE.idle,
                        marginRight: '0.5rem', flexShrink: 0 } }),
                    h('div', { style: { width: '32rem', fontSize: '1rem' } }, status.text),
                    h('div', { style: { width: '31rem' } }, buttons(footer)))));
    }

    // In a park with a session: five tabs; everywhere else the lobby as before.
    // Main menu: the lobby in three columns (the park has its own panel, renderParkPanel).
    renderBody(coop, state, column) {
        return h('div', { style: { height: '31.8rem' } },
            h('div', { style: { display: 'flex', height: rem(636) } },
                column(360, this.renderPlayers(coop)),
                column(540, [this.renderPlace(coop, state), this.renderContent(coop)]),
                column(420, [this.renderChat(coop, state), this.renderFriends(coop)], true)));
    }

    // The window in a park (TP-11): the game's panel look on the left edge, not modal - building
    // goes on while it is open, and the game's info panels keep the right side.
    renderParkPanel(coop, state) {
        const team = coop.team;
        const tab = team && PARK_TABS.some(([key]) => key === team.tab) ? team.tab : 'team';
        const status = statusOf(coop);
        const host = hostOf(coop);
        const title = !coop.role ? 'Multiplayer' : coop.role === 'host' ? 'Deine Sitzung' : 'Sitzung von ' + (host ? host.name : 'Host');
        let body;
        if (team && tab === 'plan') body = this.renderPlan(coop, state);
        else if (team && tab === 'history') body = this.renderHistory(coop);
        else if (team && tab === 'session') body = this.renderSession(coop);
        else body = this.renderPanelPlayers(coop, state);
        const footer = [];
        // Visiting is an action (TP-23). In the build bar a second tab covered the game's own icons
        // at UI scale 1.0, so it is here, on every tab.
        if (!(coop.visitor && coop.visitor.active)) footer.push({ label: 'Besuchen', onSelect: () => request('visitor', '1') });
        if (coop.role && coop.desync && coop.role === 'client') footer.push({ label: 'Neu synchronisieren', onSelect: () => request('resync') });
        if (coop.role) footer.push({ label: coop.role === 'host' ? 'Beenden' : 'Verlassen', tip: coop.role === 'host' ? END_TIP : LEAVE_TIP,
            onSelect: () => endOrAsk(coop) });
        return h('div', { style: { position: 'absolute', left: 0, top: rem(PANEL_TOP * 20), width: rem(PANEL_WIDTH * 20), pointerEvents: 'none',
            color: C('accentText'), fontSize: '1rem' } },
            h('div', { className: 'Panel_root pc2coopPanel' },
                h('div', { className: 'Panel_panel', style: { borderTopLeftRadius: 0, borderBottomLeftRadius: 0, overflow: 'hidden' } },
                    h('div', { className: 'Panel_titleBar', style: { borderTopLeftRadius: 0 } },
                        glyph('img/icons/collaborate.svg', '1.2rem', true, { marginRight: '0.4rem' }),
                        h('div', { className: 'Panel_titleBarLabel', style: { flexGrow: 1, flexShrink: 1, minWidth: 0, color: C('whiteColor') } }, title),
                        h(CloseButton, { rootClassName: 'Panel_titleBarCloseBtn', onSelect: () => request('close'), focusable: false, hideInputIcon: true })),
                    team && h('div', { className: 'TabBar_root panel' },
                        h('div', { className: 'TabBar_content panel' },
                            PARK_TABS.map(([key, label, icon]) => h(Tab, { key, icon: 'img/icons/' + icon + '.svg', tooltip: literal(label),
                                toggled: tab === key, onToggle: () => request('paneltab', key) })))),
                    h('div', { className: 'Panel_content', style: { borderBottomLeftRadius: 0, borderBottomRightRadius: 0, height: rem(PANEL_CONTENT * 20),
                        overflowY: 'auto', padding: '0.3rem 0.9rem 0.6rem' } }, body),
                    h('div', { style: { display: 'flex', flexDirection: 'column', padding: '0.5rem 0.9rem', backgroundColor: C('area'),
                        borderTopWidth: '0.05rem', borderTopStyle: 'solid', borderTopColor: ACCENT_A(0.2) } },
                        h('div', { style: { display: 'flex', alignItems: 'center', fontSize: '0.9rem' } },
                            h('div', { style: { width: '0.6rem', height: '0.6rem', borderRadius: '0.3rem', backgroundColor: TONE[status.tone] || TONE.idle,
                                marginRight: '0.5rem', flexShrink: 0 } }),
                            h('div', { style: { flexGrow: 1, flexShrink: 1, minWidth: 0 } }, status.text)),
                        footer.length > 0 && h('div', { style: { marginTop: '0.3rem' } }, buttons(footer))))));
    }

    // Tab "Spieler" (TP-12): join requests, players with icon buttons, "+ Einladen" for free places.
    renderPanelPlayers(coop, state) {
        const players = list(coop.players);
        if (!coop.role) {
            return [section('Spieler'),
                muted('Noch keine Sitzung. Starte eine, um diesen Park mit Freunden zu teilen.', { marginBottom: '0.5rem' }),
                buttons([{ label: 'Sitzung starten', onSelect: () => request('host'), disabled: !coop.canHost }])];
        }
        const requests = coop.role === 'host' ? list(coop.requests) : [];
        const out = [];
        if (requests.length > 0) {
            out.push(section('Möchte beitreten'));
            requests.forEach((r) => out.push(row([h('div', null, r.name), buttons([
                { label: 'Zulassen', onSelect: () => request('approve', r.sid) },
                { label: 'Ablehnen', onSelect: () => request('deny', r.sid) }])], 'r' + r.sid)));
        }
        out.push(section('Spieler', muted(players.length + ' / ' + SLOTS)));
        players.forEach((p) => {
            const content = contentLine(coop, p);
            const canLook = coop.stage === 'park' && !p.me && p.x !== undefined && p.act !== 'lobby';
            const following = coop.following === p.sid;
            out.push(h('div', { key: 'p' + p.sid, style: { display: 'flex', alignItems: 'center', padding: '0.35rem 0',
                borderBottomWidth: '0.05rem', borderBottomStyle: 'solid', borderBottomColor: ACCENT_A(0.15) } },
                h(Avatar, { player: p, size: 32, pic: avatars[p.sid] }),
                h('div', { style: { flexGrow: 1, flexShrink: 1, minWidth: 0, marginLeft: '0.5rem' } },
                    h('div', { style: { display: 'flex', alignItems: 'center', fontWeight: 'bold' } },
                        p.name + (p.me ? ' (du)' : ''),
                        // The crown is white: tinted like the game's icons on light ground.
                        p.host && glyph('img/icons/crown.svg', '0.8rem', false, { marginLeft: '0.3rem', filter: C('accentText-filter') })),
                    muted(following ? 'du folgst' : playerActivity(coop, p)),
                    content && content.warn && muted(content.text, { color: C('warningDark') })),
                canLook && iconButton('takemeto', 'Hinbringen', () => request('jump', p.sid)),
                canLook && iconButton('eye', following ? 'Nicht mehr folgen' : 'Folgen', () => request('follow', p.sid), following)));
        });
        const free = SLOTS - players.length;
        if (free > 0) {
            out.push(h('div', { key: 'invite', style: { marginTop: '0.4rem' } }, buttons([{ label: (state.inviting ? '− ' : '+ ') + 'Einladen',
                onSelect: () => this.setState({ inviting: !state.inviting }) }])));
            if (state.inviting) out.push(...this.renderPanelFriends(coop));
        }
        return out;
    }

    // Friends to invite (TP-05 in short: the free places' "+ Einladen" unfolds them).
    renderPanelFriends(coop) {
        const inSession = {};
        list(coop.players).forEach((p) => { inSession[p.sid] = true; });
        const friends = list(coop.friends).filter((f) => !inSession[f.sid]).slice(0, 60);
        return [section('Freunde einladen'),
            friends.length === 0 ? muted(coop.available ? 'Lade Freundesliste …' : 'Steam ist nicht bereit.')
                : h('div', { key: 'friends' }, friends.map((f) => row([
                    h('div', { style: { flexGrow: 1, flexShrink: 1, minWidth: 0 } },
                        h('div', null, f.name),
                        muted(f.lobby ? 'hat eine offene Sitzung' : f.pc2 ? 'spielt Planet Coaster 2' : (FRIEND_STATE[f.state] || ''),
                            f.lobby || f.pc2 ? { color: C('positiveDark') } : undefined)),
                    buttons([{ label: f.invited ? 'Eingeladen' : 'Einladen', disabled: f.invited, onSelect: () => request('invite', f.sid) }])], 'f' + f.sid))),
            h('div', { key: 'overlay', style: { marginTop: '0.4rem' } }, buttons([{ label: 'Steam-Overlay', onSelect: () => request('invite_overlay') }]))];
    }

    // Tab "Planen" (TP-17): the board first, a new entry behind "+ Neuer Eintrag".
    renderPlan(coop, state) {
        const team = coop.team || {};
        const items = list(team.board);
        const players = list(coop.players);
        // A context action (ping menu) picks the kind once and opens the form; after that the buttons here do.
        const fromContext = team.planSeq && team.planSeq !== state.planSeq;
        const kind = fromContext ? team.planKind : state.kind;
        const formOpen = state.planForm || fromContext;
        const needsPlace = kind !== 'task';
        const names = ['', ...players.map((p) => p.name)];
        // Who is next on the board entry (UX-C3): everybody, then each player.
        const nextName = (current) => names[(Math.max(0, names.indexOf(current || '')) + 1) % names.length];
        const add = () => {
            const clip = (t) => String(t || '').split('|').join(' ').trim();
            request('board_add', [kind, clip(state.title), clip(state.text), clip(state.assignee), kind === 'area' ? state.radius : 0].join('|'));
            this.setState({ title: '', text: '', kind, planSeq: team.planSeq, planForm: false });
        };
        const out = [section('Brett des Parks', infoTip('Alles auf dem Brett steht auch als Marker im Park. Aufgaben brauchen keinen Ort.'))];
        if (items.length === 0) out.push(muted('Noch nichts geplant.', { padding: '0.2rem 0 0.4rem' }));
        // Entries as rows with a type icon and icon buttons (TP-17): tick, thumbs, who, take me there, delete.
        items.forEach((item) => out.push(h('div', { key: item.id, style: { display: 'flex', alignItems: 'center', padding: '0.3rem 0',
            borderBottomWidth: '0.05rem', borderBottomStyle: 'solid', borderBottomColor: ACCENT_A(0.15) } },
            glyph('img/icons/' + (BOARD_ICON[item.kind] || 'clipboard') + '.svg', '1.2rem', false,
                { marginRight: '0.5rem', filter: C('accentText-filter'), opacity: item.done ? 0.55 : 1 }),
            h('div', { style: { flexGrow: 1, flexShrink: 1, minWidth: 0, opacity: item.done ? 0.55 : 1 } },
                h('div', null, (item.done ? '✓ ' : '') + item.title),
                muted(BOARD_WORD[item.kind] + ' · ' + item.by + (item.assignee ? ' → ' + item.assignee : '')
                    + (item.kind === 'proposal' ? ' · ' + item.yes + ' dafür, ' + item.no + ' dagegen' : '')),
                item.text && h('div', { style: { fontSize: '0.9rem' } }, item.text)),
            item.kind === 'task' && iconButton('tick', item.done ? 'Wieder offen' : 'Erledigt',
                () => request('board_done', item.id + '|' + (item.done ? '0' : '1')), item.done),
            item.kind === 'proposal' && iconButton('thumbsUp', 'Dafür', () => request('board_vote', item.id + '|1'), item.myVote === '1'),
            item.kind === 'proposal' && iconButton('thumbsDown', 'Dagegen', () => request('board_vote', item.id + '|0'), item.myVote === '0'),
            (item.kind === 'task' || item.kind === 'area') && !item.done && iconButton('footerGuests',
                'Zuständig – ' + (item.assignee || 'alle') + '. Klicken wechselt zu ' + (nextName(item.assignee) || 'alle') + '.',
                () => request('board_assign', item.id + '|' + nextName(item.assignee))),
            item.x !== false && iconButton('takemeto', 'Hinbringen', () => request('goto', item.x + '|' + item.z)),
            iconButton('delete', 'Löschen', () => request('board_del', item.id)))));
        if (!formOpen) {
            out.push(h('div', { key: 'new', style: { marginTop: '0.5rem' } }, buttons([{ label: '+ Neuer Eintrag', onSelect: () => this.setState({ planForm: true }) }])));
            return out;
        }
        out.push(section('Neuer Eintrag'),
            // Rows like the settings tab (TP-17): kind, who, size as the game's steppers.
            h('div', { key: 'kinds' }, h(ListStepperRow, { label: literal('Art'), items: BOARD_KINDS.map(([, word]) => literal(word)),
                listIndex: Math.max(0, BOARD_KINDS.findIndex(([key]) => key === kind)), focusable: false,
                onChange: (i) => this.setState({ kind: BOARD_KINDS[i][0], planSeq: team.planSeq, planForm: true }) })),
            h('div', { key: 'title', style: { margin: '0.3rem 0' } }, h(InputField, { text: state.title, maxInputLength: 60, beginEditOnSelect: true,
                promptText: literal(kind === 'area' ? 'Name des Gebiets ("Wikingerland")' : kind === 'task' ? 'Was ist zu tun?'
                    : kind === 'proposal' ? 'Idee ("Wildwasserbahn am See?")' : 'Titel'),
                onChange: (e) => this.setState({ title: (e && e.text) || '' }), onCommit: (e) => this.setState({ title: (e && e.text) || '' }) })),
            h('div', { key: 'text', style: { margin: '0.3rem 0' } }, h(InputField, { text: state.text, maxInputLength: 160, beginEditOnSelect: true,
                promptText: literal(kind === 'area' ? 'Auftrag ("Familienattraktion, Wikingerstil")' : 'Notiz (optional)'),
                onChange: (e) => this.setState({ text: (e && e.text) || '' }), onCommit: (e) => this.setState({ text: (e && e.text) || '' }) })),
            (kind === 'task' || kind === 'area') && h('div', { key: 'assignee' }, h(ListStepperRow, { label: literal('Zuständig'),
                items: names.map((n) => literal(n || 'alle')), listIndex: Math.max(0, names.indexOf(state.assignee || '')), focusable: false,
                onChange: (i) => this.setState({ assignee: names[i] || '' }) })),
            kind === 'area' && h('div', { key: 'radius' }, h(ListStepperRow, { label: literal('Größe'), items: AREA_SIZES.map((n) => literal(n + ' m')),
                listIndex: Math.max(0, AREA_SIZES.indexOf(state.radius)), focusable: false,
                onChange: (i) => this.setState({ radius: AREA_SIZES[i] || 20 }) })),
            needsPlace && muted('Ort: deine letzte Markierung (Mittelklick), sonst die Bildmitte.', { margin: '0.3rem 0' }),
            buttons([{ label: 'Hinzufügen', onSelect: add },
                { label: 'Abbrechen', onSelect: () => this.setState({ planForm: false, planSeq: team.planSeq, title: '', text: '' }) }]));
        return out;
    }

    // Tab "Verlauf" (TP-18): park messages as rows like the game's notifications (take me there,
    // dismiss), checkpoints, the session's log. "Seit deinem letzten Besuch" comes once as a
    // message on joining and stands in the log, not as a section here.
    renderHistory(coop) {
        const team = coop.team || {};
        const isHost = coop.role === 'host';
        const hidden = this.state.dismissed || {};
        const events = list(team.events).filter((e) => !hidden[e.label + '|' + e.x + '|' + e.z]);
        const checkTip = 'Eine Kopie des Parks beim Host. Zurückholen betrifft alle und braucht die Zustimmung aller.';
        return [
            section('Meldungen des Parks'),
            events.length === 0 ? muted('Gerade keine Pannen oder Probleme.')
                : h('div', { key: 'events' }, events.slice().reverse().map((e, i) => h('div', { key: 'e' + i, style: { display: 'flex', alignItems: 'center',
                    padding: '0.3rem 0', borderBottomWidth: '0.05rem', borderBottomStyle: 'solid', borderBottomColor: ACCENT_A(0.15) } },
                    glyph('img/icons/notifications_warning.svg', '1.2rem', false, { marginRight: '0.5rem', filter: C('accentText-filter') }),
                    h('div', { style: { flexGrow: 1, flexShrink: 1, minWidth: 0 } }, e.label),
                    iconButton('takemeto', 'Hinbringen', () => request('goto', e.x + '|' + e.z)),
                    // Only here, on this PC: the park keeps the message until the problem is gone.
                    iconButton('close', 'Ausblenden', () => this.setState({ dismissed: Object.assign({}, hidden, { [e.label + '|' + e.x + '|' + e.z]: true }) }))))),
            section('Sicherungspunkte', infoTip(checkTip)),
            list(team.checkpoints).length === 0 && muted('Noch keiner.'),
            h('div', { key: 'checkpoints' }, list(team.checkpoints).map((c) => row([h('div', null, c.label),
                isHost && buttons([{ label: 'Zurückholen…', tip: checkTip, onSelect: () => request('restore', String(c.n)) }])], 'c' + c.n))),
            isHost && h('div', { key: 'checkpoint', style: { marginTop: '0.3rem' } }, buttons([{ label: 'Sicherungspunkt erstellen', onSelect: () => request('checkpoint') }])),
            section('Verlauf der Sitzung'),
            list(coop.log).length === 0 ? muted('Noch nichts passiert.')
                : h('div', { key: 'log' }, list(coop.log).slice().reverse().map((line, i) => h('div', { key: 'l' + i, style: { fontSize: '0.9rem',
                    padding: '0.2rem 0', borderBottomWidth: '0.05rem', borderBottomStyle: 'solid', borderBottomColor: ACCENT_A(0.1) } }, shown(line)))),
        ];
    }

    renderCompetition(coop) {
        const team = coop.team || {};
        const comp = team.competition;
        const isHost = coop.role === 'host';
        const state = this.state;
        const areaOf = (name) => list(team.board).find((i) => i.kind === 'area' && i.assignee === name && i.x !== false);
        const out = [section('Wettbewerb'), muted('Ein Park, alle sehen dasselbe. Die Spielziele des Parks gelten für alle gemeinsam.')];
        if (!comp) {
            if (!isHost) { out.push(h('div', { style: { color: C('accentButtonDesaturatedDark') } }, 'Gerade kein Wettbewerb. Der Host kann einen starten.')); return out; }
            out.push(h('div', { style: { margin: '0.3rem 0', width: '100%' } }, h(InputField, { text: state.compTopic || '', maxInputLength: 60,
                beginEditOnSelect: true, promptText: literal('Thema ("Wikinger", "Familienbahn bis 20.000 €")'),
                onChange: (e) => this.setState({ compTopic: (e && e.text) || '' }), onCommit: (e) => this.setState({ compTopic: (e && e.text) || '' }) })));
            const topic = String(state.compTopic || '').split('|').join(' ');
            out.push(row([h('div', { style: { width: '100%' } }, 'Bauduell: jeder baut in seinem Baugebiet (Planen: Baugebiet mit Zuständigem), danach bewertet ihr Gestaltung und Technik'),
                buttons([15, 30, 60].map((m) => ({ label: m + ' Min.', onSelect: () => request('comp_start', 'duel|' + m + '|' + topic) })), true)], 'duel'));
            out.push(row([h('div', { style: { width: '100%' } }, 'Koop gegen die Uhr: gemeinsam die Aufgaben vom Brett schaffen'),
                buttons([15, 30, 60].map((m) => ({ label: m + ' Min.', onSelect: () => request('comp_start', 'timer|' + m + '|' + topic) })), true)], 'timer'));
            return out;
        }
        const clock = (s) => Math.floor(s / 60) + ':' + (s % 60 < 10 ? '0' : '') + (s % 60);
        out.push(h('div', { style: { fontSize: '1rem', margin: '0.2rem 0 0.4rem' } }, comp.label + (comp.topic ? ' · Thema: ' + comp.topic : '') + ' · '
            + (comp.phase === 'build' ? 'noch ' + clock(comp.left) : comp.phase === 'rate' ? 'Bewertung läuft' : 'Ergebnis')));
        if (comp.phase === 'rate') {
            const pick = state.compPick || {};
            list(comp.entries).filter((e) => !e.me).forEach((e) => {
                const chosen = Object.assign({ d: e.d, t: e.t }, pick[e.sid] || {});
                const set = (field, n) => {
                    const next = Object.assign({}, chosen, { [field]: n });
                    this.setState({ compPick: Object.assign({}, pick, { [e.sid]: next }) });
                    if (next.d && next.t) request('comp_rate', e.sid + '|' + next.d + '|' + next.t);
                };
                const area = areaOf(e.name);
                out.push(row([h('div', { style: { width: '10rem' } }, e.name),
                    area ? buttons([{ label: 'Hinbringen', onSelect: () => request('goto', area.x + '|' + area.z) }]) : h('div', { style: { width: '6rem' } }),
                    h('div', null, 'Gestaltung'), buttons([1, 2, 3, 4, 5].map((n) => ({ label: (chosen.d === n ? '● ' : '') + n, onSelect: () => set('d', n) }))),
                    h('div', null, 'Technik'), buttons([1, 2, 3, 4, 5].map((n) => ({ label: (chosen.t === n ? '● ' : '') + n, onSelect: () => set('t', n) })))], 'r' + e.sid));
            });
        }
        if (comp.phase === 'done' && comp.mode === 'duel') {
            list(comp.results).forEach((r, i) => out.push(row([h('div', { style: { width: '13rem' } }, (i + 1) + '. ' + r.name),
                h('div', null, 'Gestaltung ' + r.d.toFixed(1) + ' · Technik ' + r.t.toFixed(1) + ' (' + r.n + (r.n === 1 ? ' Stimme)' : ' Stimmen)'))], 'res' + i)));
        }
        if (isHost) out.push(buttons([{ label: comp.phase === 'build' ? (comp.mode === 'duel' ? 'Zeit beenden, bewerten' : 'Beenden')
            : comp.phase === 'rate' ? 'Bewertung abschließen' : 'Wettbewerb schließen', onSelect: () => request('comp_next') }]));
        return out;
    }

    // Tab "Einstellungen" (TP-20, TP-32): rows like the game's options menu (ToggleRow, ListStepperRow).
    // Explanations are tooltips; other players see the rules locked. focusable false: the rows do not
    // take the game's focus on hover (building goes on beside the window).
    renderSession(coop) {
        const rules = (coop.team && coop.team.rules) || {};
        const isHost = coop.role === 'host';
        const preset = PRESETS.findIndex(([, , values]) => Object.keys(values).every((k) => rules[k] === values[k]));
        // "Eigene" only while the rules match no set; choosing it changes nothing.
        const presetItems = (preset < 0 ? ['Eigene'] : []).concat(PRESETS.map(([, word]) => word));
        const role = isHost
            ? 'Du bist Host. Der Park läuft bei dir. Du legst die Regeln fest, bestätigst Beitrittsanfragen und erstellst Sicherungspunkte.'
            : 'Du baust frei mit. Was jemand anderes gerade bearbeitet, ist für dich gesperrt. Markiere es und frag nach der Übernahme. '
              + 'Rückgängig betrifft nur deine eigenen Schritte.';
        return [
            section('Für dich', muted('nur auf deinem PC')),
            h('div', { key: 'labels' }, h(ToggleRow, { label: literal('Mitspieler in der Welt zeigen'), toggled: !!coop.labels, focusable: false,
                tooltip: literal('Name, Blickrichtung, gehaltenes Objekt und Sperr-Färbung'), onToggle: (on) => request('labels', on ? '1' : '0') })),
            section('Regeln dieser Sitzung', h(HoverTip, { tip: role, className: 'pc2coopRoleTip' },
                glyph('img/icons/information.svg', '1.1rem', false, { filter: C('accentText-filter') }))),
            h('div', { key: 'preset' }, h(ListStepperRow, { label: literal('Schnellwahl'), items: presetItems.map(literal),
                listIndex: preset < 0 ? 0 : preset, disabled: !isHost, focusable: false,
                tooltip: literal(isHost ? 'Setzt alle Regeln auf einmal. Locker – alle dürfen alles. Geordnet – Tempo nur der Host, '
                    + 'fremde Bauten erst fragen. Nur bauen – dazu ohne Besucher-Modus.' : LOCKED),
                onChange: (i) => { const set = PRESETS[preset < 0 ? i - 1 : i]; if (set) request('rule_preset', set[0]); } })),
            ...RULES.map(([name, text, options, tip]) => h('div', { key: name }, name === 'visitors'
                ? h(ToggleRow, { label: literal(text), toggled: rules[name] === '1', disabled: !isHost, focusable: false,
                    tooltip: literal(isHost ? tip : LOCKED), onToggle: (on) => request('rule', name + '|' + (on ? '1' : '0')) })
                : h(ListStepperRow, { label: literal(text), items: options.map(([, word]) => literal(word)),
                    listIndex: Math.max(0, options.findIndex(([value]) => value === rules[name])), disabled: !isHost, focusable: false,
                    tooltip: literal(isHost ? tip : LOCKED), onChange: (i) => { if (options[i]) request('rule', name + '|' + options[i][0]); } }))),
            this.renderContentSetting(coop),
            this.renderCompetition(coop),
        ];
    }

    // Contents (DLC) of everybody: only a line when they differ; the host switches the guard (TP-12).
    renderContentSetting(coop) {
        const players = list(coop.players);
        if (!coop.role || players.length < 2) return null;
        const known = players.filter((p) => p.dlc !== undefined);
        const uneven = dlcPacks().filter((pack) => known.some((p) => owns(p.dlc, pack.id)) && known.some((p) => !owns(p.dlc, pack.id)));
        const text = known.length < players.length ? 'Die Inhalte der Mitspieler werden geprüft …'
            : uneven.length === 0 ? 'Alle haben dieselben Inhalte.'
            : 'Nicht alle haben: ' + uneven.map(packName).join(', ') + (coop.guard ? '. Daraus wird nichts gebaut.' : '. Wird trotzdem gebaut.');
        return h('div', { key: 'content' }, section('Inhalte'),
            muted(text, uneven.length ? { color: C('warningDark') } : undefined),
            coop.role === 'host' && uneven.length > 0 && h(ToggleRow, { label: literal('Nur gemeinsame Inhalte'), toggled: !!coop.guard, focusable: false,
                tooltip: literal('Aus Inhalten, die nicht alle haben, wird dann nichts gebaut.'), onToggle: (on) => request('guard', on ? '1' : '0') }));
    }

    renderPlayers(coop) {
        const players = list(coop.players);
        const requests = coop.role === 'host' ? list(coop.requests) : [];
        const slots = [];
        players.forEach((p) => {
            const content = contentLine(coop, p);
            const canLook = coop.stage === 'park' && coop.context === 'park' && !p.me && p.x !== undefined && p.act !== 'lobby';
            // Buttons on their own line under name and activity: next to the avatar they ran out of
            // the column ("Folgen" cut off, acceptance pictures 2026-11-20).
            slots.push(h('div', { key: 'p' + p.sid, style: { display: 'flex', flexDirection: 'column', padding: '0.35rem 0.5rem', margin: '0.25rem 0',
                borderRadius: '0.5rem', backgroundColor: C('whiteColor'), border: '0.05rem solid ' + ACCENT_A(0.18) } },
                h('div', { style: { display: 'flex', alignItems: 'center' } },
                    h(Avatar, { player: p, size: 40, pic: avatars[p.sid] }),
                    h('div', { style: { flexGrow: 1, minWidth: 0, marginLeft: '0.6rem' } },
                        h('div', { style: { display: 'flex', alignItems: 'center', fontSize: '1rem', fontWeight: 'bold' } },
                            p.name + (p.me ? ' (du)' : ''),
                            // The crown is white: tinted like the game's icons on light ground.
                            p.host && glyph('img/icons/crown.svg', '0.8rem', false, { marginLeft: '0.3rem', filter: C('accentText-filter') })),
                        h('div', { style: { color: C('accentButtonDesaturatedDark'), fontSize: '0.9rem' } }, playerActivity(coop, p)),
                        content && h('div', { style: { color: content.warn ? C('warningDark') : C('positiveDark'), fontSize: '0.9rem' } }, content.text))),
                canLook && h('div', { style: { marginTop: '0.25rem' } }, buttons([
                    { label: 'Hinbringen', onSelect: () => request('jump', p.sid) },
                    { label: coop.following === p.sid ? 'Nicht folgen' : 'Folgen', onSelect: () => request('follow', p.sid) }]))));
        });
        if (coop.role) {
            for (let i = players.length; i < SLOTS; i++) {
                slots.push(h('div', { key: 'e' + i, style: { padding: '0.6rem', margin: '0.25rem 0', borderRadius: '0.5rem', color: C('accentButtonDesaturatedDark'),
                    backgroundColor: C('area'), fontSize: '0.9rem' } }, 'Freier Platz'));
            }
        }
        return box(636, [
            requests.length > 0 && section('Möchte beitreten'),
            ...requests.map((r) => row([h('div', null, r.name), buttons([
                { label: 'Zulassen', onSelect: () => request('approve', r.sid) },
                { label: 'Ablehnen', onSelect: () => request('deny', r.sid) }])], 'r' + r.sid)),
            section('Spieler'),
            !coop.role && h('div', { style: { color: C('accentButtonDesaturatedDark'), padding: '0.3rem 0' } },
                coop.context === 'menu' ? 'Noch keine Sitzung. Starte eine oder tritt rechts einem Freund bei.'
                    : 'Noch keine Sitzung. Starte eine, um diesen Park mit Freunden zu teilen.'),
            ...slots]);
    }

    // Host in the main menu: pick a park; everyone sees the pick before it is opened.
    renderChooser(coop, state) {
        const tab = state.tab;
        const tabButton = (key, label, later) => h('div', { key, onClick: later ? undefined : () => this.setState({ tab: key }),
            style: { padding: '0.3rem 0.7rem', marginRight: '0.3rem', borderRadius: '0.8rem', fontSize: '0.9rem',
                backgroundColor: tab === key ? C('accent') : (later ? C('area') : C('whiteColor')), color: tab === key ? C('whiteColor') : (later ? C('neutral3') : C('accentText')),
                border: '0.05rem solid ' + (later ? 'rgba(0, 0, 0, 0.06)' : ACCENT_A(0.45)) } }, label);
        const picked = (key) => coop.chosen === key;
        const pickStyle = (on) => ({ padding: '0.4rem 0.6rem', margin: '0.2rem 0', borderRadius: '0.4rem', backgroundColor: on ? C('accentFaint') : C('whiteColor'),
            borderWidth: '0.05rem', borderStyle: 'solid', borderColor: on ? C('accent') : ACCENT_A(0.18) });
        let content;
        if (tab === 'save') {
            const parks = list(coop.parks);
            content = box(300, parks.length === 0 ? h('div', { style: { color: C('accentButtonDesaturatedDark'), padding: '0.4rem 0' } }, 'Keine gespeicherten Sandbox-Parks gefunden.')
                : parks.map((park) => h('div', { key: 's' + park.id, onClick: () => request('choose', 'save|' + park.id), style: pickStyle(picked('save:' + park.id)) },
                    h('div', { style: { fontSize: '1rem', fontWeight: 'bold' } }, park.name),
                    h('div', { style: { color: C('accentButtonDesaturatedDark'), fontSize: '0.9rem' } }, (BIOMES.find((b) => b[0] === park.world) || [0, park.world || 'Sandbox'])[1]))));
        } else if (tab === 'new') {
            const pickNew = (biome, creative) => request('choose', 'new|' + biome + '|' + (creative ? '1' : '0'));
            const current = (coop.chosen || '').indexOf('new:') === 0 ? coop.chosen.substring(4) : null;
            content = box(300, [
                h('div', { key: 'b', style: { display: 'flex', flexWrap: 'wrap' } }, BIOMES.map(([id, label]) => h('div', { key: id,
                    onClick: () => pickNew(id, state.creative), style: Object.assign(pickStyle(current === id), { width: '11.1rem', margin: '0.2rem 0.4rem 0.2rem 0' }) },
                    h('div', { style: { fontSize: '1rem', fontWeight: 'bold' } }, label)))),
                h('div', { key: 'm', style: { display: 'flex', marginTop: '0.5rem' } },
                    [[true, 'Kreativ (Geld unbegrenzt)'], [false, 'Mit Budget']].map(([creative, label]) => h('div', { key: label,
                        onClick: () => { this.setState({ creative }); if (current) pickNew(current, creative); },
                        style: Object.assign(pickStyle(state.creative === creative), { marginRight: '0.4rem', fontSize: '0.9rem' }) }, label)))]);
        } else {
            content = box(300, [
                h('div', { key: 't', style: { color: C('accentButtonDesaturatedDark'), padding: '0.4rem 0' } },
                    'Franchise-Parks wählst du im Franchise-Menü des Spiels. Sobald der Park offen ist, laden ihn alle in der Sitzung.'),
                h('div', { key: 'b' }, buttons([{ label: 'Franchise-Menü öffnen', onSelect: () => { request('choose', 'franchise'); openScreen(MODES[1]); } }]))]);
        }
        const choice = coop.choice;
        const canStart = choice && (choice.kind === 'save' || choice.kind === 'new') && !choice.starting;
        return [section('Wo spielen wir?', h('span', { style: { textTransform: 'none', letterSpacing: 0 } },
                tab === 'save' ? h('span', { onClick: () => request('parks'), style: { color: C('accent'), fontSize: '0.9rem' } }, 'aktualisieren') : null)),
            h('div', { key: 'tabs', style: { display: 'flex', marginBottom: '0.4rem' } },
                tabButton('save', 'Gespeichert'), tabButton('new', 'Neu'), tabButton('franchise', 'Franchise'),
                tabButton('career', 'Karriere · später', true)),
            content,
            h('div', { key: 'sel', style: { display: 'flex', alignItems: 'center', height: '3.8rem', marginTop: '0.4rem', padding: '0 0.6rem',
                borderRadius: '0.5rem', backgroundColor: choice ? C('accentFaint') : C('area') } },
                h('div', { style: { width: '15rem' } },
                    h('div', { style: { color: C('accentButtonDesaturatedDark'), fontSize: '0.9rem' } }, choice ? 'Ausgewählt - sehen alle' : 'Noch nichts ausgewählt'),
                    choice && h('div', { style: { fontSize: '1rem', fontWeight: 'bold' } }, choice.title),
                    choice && h('div', { style: { color: C('accentButtonDesaturatedDark'), fontSize: '0.9rem' } }, choice.detail)),
                h('div', { style: { width: '9.5rem' } }, canStart ? buttons([{ label: 'Park öffnen', onSelect: () => request('start') }]) : null))];
    }

    renderPlace(coop, state) {
        if (!coop.role) return box(470, null);
        if (coop.stage === 'lobby') {
            if (coop.canChoose) return box(470, this.renderChooser(coop, state), { overflowY: 'hidden' });
            const choice = coop.choice;
            const host = hostOf(coop);
            return box(470, [section('Wo spielen wir?'),
                h('div', { key: 'c', style: { padding: '0.7rem', borderRadius: '0.5rem', backgroundColor: choice ? C('accentFaint') : C('area') } },
                    choice ? [h('div', { key: 'l', style: { color: C('accentButtonDesaturatedDark'), fontSize: '0.9rem' } }, (host ? host.name : 'Der Host') + ' hat gewählt'),
                        h('div', { key: 't', style: { fontSize: '1.1rem', fontWeight: 'bold' } }, choice.title),
                        h('div', { key: 'd', style: { color: C('accentButtonDesaturatedDark') } }, choice.detail),
                        h('div', { key: 's', style: { marginTop: '0.4rem' } }, choice.starting ? 'Wird geöffnet - der Park lädt gleich bei dir.' : 'Wartet auf den Start durch den Host.')]
                        : h('div', { style: { color: C('accentButtonDesaturatedDark') } }, coop.role === 'host' ? 'Geh ins Hauptmenü, um einen Park zu wählen.'
                            : 'Der Host wählt noch. Sobald der Park offen ist, lädt er bei dir automatisch.'))]);
        }
        const out = [section('Park des Hosts', coop.parkTitle ? h('span', { style: { color: C('accentButtonDesaturatedDark'), textTransform: 'none', letterSpacing: 0 } }, coop.parkTitle) : null)];
        if (coop.park) out.push(h('div', { key: 'n' }, (coop.park.guests || 0).toLocaleString('de-DE') + ' Besucher · ' + money(coop.park)));
        list(coop.stats).forEach((s) => out.push(h('div', { key: 's' + s.name, style: { padding: '0.1rem 0', color: C('accentButtonDesaturatedDark') } },
            s.name + ': ' + s.created + ' platziert, ' + s.edited + ' bearbeitet, ' + s.deleted + ' gelöscht')));
        if (list(coop.log).length) {
            out.push(section('Verlauf'));
            list(coop.log).slice(-7).forEach((line, i) => out.push(h('div', { key: 'l' + i, style: { padding: '0.1rem 0', color: C('accentButtonDesaturatedDark') } }, line)));
        }
        return box(470, out);
    }

    renderChat(coop, state) {
        if (!coop.role) return null;
        const chat = list(coop.chat).slice(-30);
        return h('div', { key: 'chat', style: { height: '16.5rem' } },
            section('Chat'),
            h('div', { style: { height: '10.7rem', overflowY: 'auto', padding: '0.3rem 0.5rem', borderRadius: '0.4rem', backgroundColor: C('whiteColor'),
                border: '0.05rem solid ' + ACCENT_A(0.18) } },
                chat.length === 0 ? h('div', { style: { color: C('accentButtonDesaturatedDark'), fontSize: '0.9rem' } }, 'Noch keine Nachrichten.')
                    : chat.map((c, i) => h('div', { key: 'c' + i, style: { padding: '0.1rem 0', fontSize: '0.9rem' } },
                        h('span', { style: { color: '#' + (c.color || '20435a'), fontWeight: 'bold' } }, c.name + ': '), c.text))),
            h('div', { style: { marginTop: '0.4rem' } },
                h(InputField, { text: state.draft, promptText: literal('Nachricht an alle'), maxInputLength: 200,
                    beginEditOnSelect: true, onChange: (e) => this.setState({ draft: (e && e.text) || '' }), onCommit: (e) => {
                        const text = String((e && e.text) || '').trim();
                        this.setState({ draft: '' });
                        if (text) request('chat', text);
                    }, onCancel: () => this.setState({ draft: '' }) })));
    }

    renderContent(coop) {
        const players = list(coop.players);
        if (!coop.role || players.length < 2) return null;
        const known = players.filter((p) => p.dlc !== undefined);
        const uneven = dlcPacks().filter((pack) => known.some((p) => owns(p.dlc, pack.id)) && known.some((p) => !owns(p.dlc, pack.id)));
        const text = known.length < players.length ? 'DLCs der Mitspieler werden geprüft ...'
            : uneven.length === 0 ? 'Alle haben dieselben DLCs.'
            : 'Nicht alle haben: ' + uneven.map(packName).join(', ') + (coop.guard ? ' - daraus wird nichts gebaut.' : ' - wird trotzdem gebaut.');
        return h('div', { key: 'content', style: { height: '6.5rem' } },
            section('Inhalte'),
            h('div', { style: { color: uneven.length ? C('warningDark') : C('positiveDark'), fontSize: '0.9rem' } }, text),
            coop.role === 'host' && uneven.length > 0 && buttons([{ label: coop.guard ? 'Alle Inhalte erlauben' : 'Nur gemeinsame Inhalte',
                onSelect: () => request('guard', coop.guard ? '0' : '1') }]));
    }

    renderFriends(coop) {
        if (!coop.available) return null;
        const friends = list(coop.friends).slice(0, 60);
        const inSession = {};
        list(coop.players).forEach((p) => { inSession[p.sid] = true; });
        return h('div', { key: 'friends', style: { height: coop.role ? '15.3rem' : '31.8rem' } },
            section(coop.role ? 'Freunde einladen' : 'Steam-Freunde'),
            h('div', { style: { height: coop.role ? '12.8rem' : '29.3rem', overflowY: 'auto' } },
                friends.length === 0 ? h('div', { style: { color: C('accentButtonDesaturatedDark') } }, 'Lade Freundesliste ...')
                    : friends.map((f) => row([
                        h('div', { style: { width: '11.5rem' } },
                            h('div', { style: { fontSize: '1rem' } }, f.name),
                            h('div', { style: { color: f.lobby ? C('positiveDark') : f.pc2 ? C('positiveDark') : C('accentButtonDesaturatedDark'), fontSize: '0.9rem' } },
                                f.lobby ? 'hat eine offene Sitzung' : f.pc2 ? 'spielt Planet Coaster 2' : (FRIEND_STATE[f.state] || ''))),
                        inSession[f.sid] ? h('span', { style: { color: C('positiveDark'), fontSize: '0.9rem' } }, 'ist dabei')
                            : coop.role ? buttons([{ label: f.invited ? 'Eingeladen' : 'Einladen', disabled: f.invited, onSelect: () => request('invite', f.sid) }])
                            : f.lobby ? buttons([{ label: 'Beitreten', onSelect: () => request('join_friend', f.sid) }]) : null,
                    ], 'f' + f.sid))));
    }
}

// Small lobby card in the main menu while the panel is closed (settings, park selection ...).
class MiniLobby extends StateComponent {
    render(props, state) {
        try { return this.draw(state.coop || {}); } catch (error) { log('mini lobby ' + error); return null; }
    }
    draw(coop) {
        const join = coop.join || {};
        if (!coop.role || coop.open || coop.context !== 'menu' || ['failed', 'confirm', 'rejoin'].indexOf(join.phase) >= 0) return null;
        const status = statusOf(coop);
        if (!this._logged) {
            this._logged = true;
            setTimeout(() => {
                try {
                    const r = this.base && this.base.getBoundingClientRect();
                    log('mini lobby at ' + (r ? [r.left, r.top, r.width, r.height].map(Math.round).join(',') : '?') + ' of ' + window.innerWidth + 'x' + window.innerHeight);
                } catch (error) { log('mini lobby rect ' + error); }
            }, 500);
        }
        const chip = (label, onClick) => h('div', { onClick, style: { marginLeft: '0.4rem', padding: '0.25rem 0.6rem', borderRadius: '0.7rem',
            backgroundColor: ACCENT_A(0.9), color: C('whiteColor'), fontSize: '0.9rem' } }, label);
        return h('div', { style: hudCard({ position: 'absolute', left: '74rem', top: '11.5rem', width: '20.5rem', padding: '0.6rem 0.8rem', pointerEvents: 'auto',
            borderRadius: '0.6rem', fontSize: '1rem', borderLeftWidth: '0.25rem', borderLeftStyle: 'solid', borderLeftColor: TONE[status.tone] || TONE.idle }, 0.9) },
            h('div', { style: { display: 'flex', alignItems: 'center' } },
                h('div', { style: { fontSize: '1rem', flexGrow: 1 } }, coop.role === 'host' ? 'Deine Sitzung' : 'Sitzung'),
                list(coop.players).slice(0, SLOTS).map((p) => h('div', { key: p.sid, style: { marginLeft: '-0.3rem' } }, h(Avatar, { player: p, size: 26, pic: avatars[p.sid] })))),
            h('div', { style: { color: C('accentButtonLight'), fontSize: '0.9rem', margin: '0.3rem 0 0.4rem' } }, status.text),
            h('div', { style: { display: 'flex', justifyContent: 'flex-end' } },
                chip('Sitzung öffnen', () => request('open')),
                chip(coop.role === 'host' ? 'Beenden' : 'Verlassen', () => request('leave'))));
    }
}

function joinText(join) {
    const host = join.host ? ' von ' + join.host : '';
    if (join.phase === 'joining') return 'Trete der Sitzung bei …';
    if (join.phase === 'silent') return 'Keine Verbindung zum Host - warte ...';
    if (join.phase === 'asking') return 'Warte auf die Zustimmung' + host + ' ...';
    if (join.phase === 'confirm') return 'Beitritt' + (join.host ? ' bei ' + join.host : '') + ' wartet auf deine Bestätigung.';
    if (join.phase === 'awaiting') return 'Empfange den Park' + host + ' ... ' + Math.round((join.progress || 0) * 100) + ' %';
    if (join.phase === 'loading') return 'Lade den Park' + host + ' ...';
    if (join.phase === 'lobby') return 'In der Sitzung' + host + '.';
    return 'Verbunden' + host + '.';
}

// Card in the screen centre while a park is on its way (menu or park).
class JoinProgress extends StateComponent {
    render(props, state) {
        const coop = state.coop || {};
        const join = coop.join;
        // A lost connection in the park ('silent') is the connection pill, not this card.
        if (!join || ['joining', 'asking', 'awaiting', 'loading'].indexOf(join.phase) < 0 || coop.open) return null;
        const share = join.phase === 'awaiting' ? (join.progress || 0) : join.phase === 'loading' ? 1 : 0.02;
        return h('div', { style: hudCard({ position: 'absolute', left: '50%', top: '42%', width: '26rem', marginLeft: '-13rem',
            padding: '1.1rem 1.4rem', borderRadius: '0.7rem', fontSize: '1rem', textAlign: 'center' }, 0.9) },
            h('div', { style: { fontSize: '1.1rem', marginBottom: '0.3rem' } }, 'Multiplayer'),
            h('div', { style: { fontSize: '0.9rem', color: C('accentButtonLight'), marginBottom: '0.7rem' } }, joinText(join)),
            h('div', { style: { height: '0.4rem', borderRadius: '0.2rem', backgroundColor: 'rgba(255, 255, 255, 0.15)' } },
                h('div', { style: { height: '0.4rem', borderRadius: '0.2rem', backgroundColor: C('accentLight'), width: Math.round(share * 100) + '%' } })));
    }
}

// After a crash or a dropped connection: back into the same session from the main menu.
class Rejoin extends StateComponent {
    render(props, state) {
        const coop = state.coop || {};
        const join = coop.join;
        if (!join || join.phase !== 'rejoin' || coop.open) return null;
        return preact.h(Dialog, { modifiers: 'dialogApp', title: literal('Multiplayer'),
            description: literal('Du warst eben noch in der Sitzung von ' + (join.host || 'einem Freund') + '. Wieder beitreten?'),
            buttons: [{ label: literal('Wieder beitreten'), onSelect: () => request('rejoin') },
                { label: literal('Nein'), onSelect: () => request('forget_rejoin'), inputName: 'UI_Cancel' }] });
    }
}

// The lobby came with the start of the game (launch arguments), not from an invitation the
// player clicked: ask before this game takes a park from that host.
class JoinConfirm extends StateComponent {
    render(props, state) {
        const coop = state.coop || {};
        const join = coop.join;
        if (!join || join.phase !== 'confirm') return null;
        return preact.h(Dialog, { modifiers: 'dialogApp', title: literal('Multiplayer'),
            description: literal('Der Sitzung von ' + (join.host || 'einem Steam-Freund') + ' beitreten? Dein Spiel lädt dann den Park des Hosts.'),
            buttons: [{ label: literal('Beitreten'), onSelect: () => request('confirm_join') },
                { label: literal('Abbrechen'), onSelect: () => request('cancel_join'), inputName: 'UI_Cancel' }] });
    }
}

// Joining failed (old invite, park could not be loaded): say why and offer the way out.
class JoinFailed extends StateComponent {
    render(props, state) {
        const coop = state.coop || {};
        const join = coop.join;
        if (!join || join.phase !== 'failed' || coop.open) return null;
        const buttons = [];
        if (join.retry) buttons.push({ label: literal('Erneut versuchen'), onSelect: () => request('retry_join') });
        buttons.push({ label: literal(join.retry ? 'Abbrechen' : 'Schließen'), onSelect: () => request('cancel_join'), inputName: 'UI_Cancel' });
        return preact.h(Dialog, { modifiers: 'dialogApp', title: literal('Multiplayer'), description: literal(join.reason || 'Beitritt fehlgeschlagen.'), buttons });
    }
}

class CoopLayer extends preact.Component {
    render() {
        // Above the menu's own layers (its tiles have stacking contexts of their own).
        return h('div', { style: { position: 'absolute', top: 0, left: 0, width: '100vw', height: '100vh', pointerEvents: 'none', zIndex: 10000,
            fontFamily: FONT } },
            h(PlayerBar, null),
            h(VisitorBar, null),
            h(EmoteWheel, null),
            h(ConnectionPill, null),
            h(RequestCard, null),
            h(ContextMenu, null),
            h(MarkHint, null),
            h(ChatArea, null),
            h(JoinProgress, null),
            h(MiniLobby, null),
            h('div', { style: { pointerEvents: 'auto' } }, h(Lobby, null)),
            h('div', { style: { pointerEvents: 'auto' } }, h(JoinFailed, null)),
            h('div', { style: { pointerEvents: 'auto' } }, h(JoinConfirm, null)),
            h('div', { style: { pointerEvents: 'auto' } }, h(EndConfirm, null)),
            h('div', { style: { pointerEvents: 'auto' } }, h(Rejoin, null)));
    }
}

// Adds "Multiplayer" to the pause menu, right above "Exit". The menu class is wrapped by
// Focusable.decorate; its render returns a vnode whose nodeName is the real menu class.
// That class builds every entry with getGameMenuBtn, which we reuse for identical styling.
async function patchPauseMenu() {
    const module = await import('/js/project/modules/gameMenu/components/GameMenuModule.js');
    const decorated = module.GameMenu;
    if (!decorated || decorated.prototype.__pc2coop) return;
    const originalRender = decorated.prototype.render;
    decorated.prototype.render = function (...args) {
        const vnode = originalRender.apply(this, args);
        try { patchMenuClass(vnode && vnode.nodeName); } catch (error) { log('pause menu patch ' + error); }
        return vnode;
    };
    decorated.prototype.__pc2coop = true;
}

// The build bar at the bottom: an icon tab "Multiplayer" after the multi-select tab.
async function patchBuildBar() {
    const [browserModule, tabModule] = await Promise.all([import('/js/project/modules/browser/components/Browser.js'),
        import('/js/project/modules/browser/components/BrowserTab.js')]);
    const decorated = browserModule.Browser;
    if (!decorated || decorated.prototype.__pc2coop) return;
    const originalRender = decorated.prototype.render;
    decorated.prototype.render = function (...args) {
        const vnode = originalRender.apply(this, args);
        try { patchBrowserClass(vnode && vnode.nodeName, tabModule.BrowserTab); } catch (error) { report('build bar patch ' + error); }
        return vnode;
    };
    decorated.prototype.__pc2coop = true;
}

// The first vnode below node for which test is true, with the list it sits in.
function findNode(node, test) {
    if (!node || typeof node !== 'object') return null;
    const children = Array.isArray(node) ? node : node.children;
    if (!Array.isArray(children)) return null;
    for (let i = 0; i < children.length; i++) {
        const child = children[i];
        if (child && typeof child === 'object' && !Array.isArray(child) && test(child)) return { list: children, index: i, node: child };
        const deeper = findNode(child, test);
        if (deeper) return deeper;
    }
    return null;
}

function findTab(node, outcome) {
    if (!node || typeof node !== 'object') return null;
    const children = Array.isArray(node) ? node : node.children;
    if (!Array.isArray(children)) return null;
    for (let i = 0; i < children.length; i++) {
        const child = children[i];
        if (child && child.attributes && child.attributes.outcome === outcome) return { list: children, index: i, node: child };
        const deeper = findTab(child, outcome);
        if (deeper) return deeper;
    }
    return null;
}

function patchBrowserClass(browserClass, BrowserTab) {
    const proto = browserClass && browserClass.prototype;
    if (!proto || proto.__pc2coop || !BrowserTab) return;
    const render = proto.render;
    proto.render = function (...args) {
        const tree = render.apply(this, args);
        try {
            // NOT inside the game's TabBar: it pairs every tab with the browser section at the same
            // index, and a tab without one locked the whole UI on click (1.12.1). Next to it instead,
            // like the game's own "back to the browser" tab.
            const bar = findNode(tree, (n) => n.attributes && n.attributes.rootClassName === 'Browser_tabBar' && n.attributes.onChange);
            const multi = findTab(tree, 'multiselect');
            if (bar && multi && !findNode(tree, (n) => n.key === 'pc2coopTabBar')) {
                // Out of the flow at the right end of the bar's row: the game's bar keeps its place.
                bar.list.splice(bar.index + 1, 0, preact.h('div', { key: 'pc2coopTabBar', className: 'Browser_tabBar pc2coopTabBar',
                    style: { position: 'absolute', right: '0.6rem', bottom: '0px', width: 'auto' } },
                    preact.h(BrowserTab, { label: literal('Multiplayer'), icon: 'img/icons/collaborate.svg',
                        hidden: multi.node.attributes.hidden, modifiers: 'firstItem lastItem marginLeft',
                        onToggle: () => request('open') })));
                if (!buildBarShown) { buildBarShown = true; report('build bar tab shown'); }
            }
        } catch (error) { report('build bar tab ' + error); }
        return tree;
    };
    proto.__pc2coop = true;
    report('build bar patched');
}

// Into the mod's log file (pc2coop-diagnostic-*.log), so a missing tab can be looked into.
// Lua hears the HUD view's events only a moment after the HUD starts (an earlier line is
// lost, tested 1.12.1), so these lines go out a few seconds later.
let buildBarShown = false;
function report(message) {
    try { setTimeout(() => log(message), 4000); } catch (error) { log(message); }
}

function patchMenuClass(menuClass) {
    const proto = menuClass && menuClass.prototype;
    if (!proto || proto.__pc2coop || typeof proto.getGameMenuBtn !== 'function') return;
    const build = proto.getGameMenuBtn;
    proto.getGameMenuBtn = function (id, ...rest) {
        const button = build.call(this, id, ...rest);
        if (typeof id === 'string' && id.indexOf('Exit') === 0) {
            const ours = build.call(this, 'PC2CoopMultiplayer', 'collaborate', () => request('open'));
            if (ours && ours.attributes) ours.attributes.label = literal('Multiplayer');
            // In a session also leave or end it here (TP-30); the host is asked first (EndConfirm).
            const coop = currentState || {};
            if (!coop.role) return [ours, button];
            const leave = build.call(this, 'PC2CoopLeave', 'close', () => endOrAsk(currentState || {}));
            if (leave && leave.attributes) leave.attributes.label = literal(coop.role === 'host' ? 'Sitzung beenden' : 'Sitzung verlassen');
            return [ours, leave, button];
        }
        return button;
    };
    proto.__pc2coop = true;
    log('pause menu patched');
}

// Adds a "Multiplayer" tile to the main menu's Play tab, next to Career. Same pattern as the
// pause menu: the exported component is the Focusable wrapper around the real tab class.
async function patchMainMenu() {
    const tabModule = await import('/js/project/modules/frontEnd/views/mainMenu/menuTabs/FrontEndStartMenuTab.js');
    const tileModule = await import('/js/project/modules/frontEnd/components/FrontEndTileButton.js');
    const decorated = tabModule.FrontEndStartMenuTab;
    if (!decorated || decorated.prototype.__pc2coop) return;
    const originalRender = decorated.prototype.render;
    decorated.prototype.render = function (...args) {
        const vnode = originalRender.apply(this, args);
        try { patchStartTabClass(vnode && vnode.nodeName, tileModule.FrontEndTileButton); } catch (error) { log('main menu patch ' + error); }
        return vnode;
    };
    decorated.prototype.__pc2coop = true;
}

function findParent(node, key) {
    if (!node || typeof node !== 'object') return null;
    const children = Array.isArray(node) ? node : node.children;
    if (!Array.isArray(children)) return null;
    for (let i = 0; i < children.length; i++) {
        const child = children[i];
        if (child && (child.key === key || (child.attributes && child.attributes.key === key))) return { list: children, index: i };
        const deeper = findParent(child, key);
        if (deeper) return deeper;
    }
    return null;
}

function patchStartTabClass(tabClass, TileButton) {
    const proto = tabClass && tabClass.prototype;
    if (!proto || proto.__pc2coop || !TileButton) return;
    const render = proto.render;
    proto.render = function (...args) {
        const tree = render.apply(this, args);
        try {
            const at = findParent(tree, 'careerBtn');
            if (at && !at.list.some((c) => c && c.key === 'pc2coopBtn')) {
                const title = literal('Multiplayer');
                const description = literal('Mit Steam-Freunden live im selben Park bauen.');
                at.list.splice(at.index + 1, 0, preact.h(TileButton, { label: title, titleIcon: 'img/icons/collaborate.svg',
                    key: 'pc2coopBtn', description, backgroundImage: 'img/frontEnd/franchiseBG.png', outcome: 'PC2CoopMultiplayer',
                    onSelect: () => request('open'),
                    onFocusChanged: () => { if (typeof this.onButtonFocus === 'function') this.onButtonFocus(title, description); } }));
            }
        } catch (error) { log('main menu tile ' + error); }
        return tree;
    };
    proto.__pc2coop = true;
    log('main menu patched');
}

let started = false;
let log = (message) => console.log('PC2Coop: ' + message);
export function start(logger) {
    if (logger) log = logger;
    if (started) return;
    const app = String(window.location.href);
    if (app.indexOf('HUD.html') < 0 && app.indexOf('FrontEnd.html') < 0) return;
    started = true;
    if (app.indexOf('HUD.html') >= 0) {
        patchPauseMenu().catch((e) => console.log('PC2Coop: ' + e));
        patchBuildBar().catch((e) => report('build bar import ' + e));
        // QA: a counter from Lua presses the tab with a mouse-down event (no real mouse).
        let qaClicks = 0;
        listeners.add((s) => {
            if (!s.qaClickTab || s.qaClickTab === qaClicks) return;
            qaClicks = s.qaClickTab;
            const tab = document.querySelector('.pc2coopTabBar .Tab_root');
            report('qa tab press ' + (tab ? 'found' : 'missing'));
            if (tab) tab.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, button: 0 }));
        });
        // QA: another accent colour, colour-blind mode or UI scale for screenshots, only in this view
        // and never saved: the game's own ThemeConfig/UIScale calls (dev flag scripts only, Ui._QaLook).
        let qaLooks = '';
        listeners.add((s) => {
            if (!s.qaLook || s.qaLook === qaLooks) return;
            qaLooks = s.qaLook;
            const [accent, theme, scale, tab, tip] = String(s.qaLook).split('|').map(Number);
            // tip 1-8: that player in the cluster, 9: the first tab of the window - as if the mouse were on it;
            // 10: the question "Für alle beenden?", 11: the tooltip of the rules' info icon.
            if (tip === 10) askEnd(true);
            const hovered = tip >= 1 && tip <= 8 ? document.querySelectorAll('.pc2coopTip')[tip - 1]
                : tip === 9 ? document.querySelector('.pc2coopPanel .Tab_root') : tip === 11 ? document.querySelector('.pc2coopRoleTip') : null;
            if (hovered) hovered.dispatchEvent(new MouseEvent('mouseenter', { bubbles: false }));
            if (tip > 0 && tip !== 10) report('qa hover ' + (hovered ? 'found' : 'missing'));
            // tab 0: our build bar tab hidden (does the game's bar fit without it?)
            document.querySelectorAll('.pc2coopTabBar').forEach((el) => { el.style.display = tab === 0 ? 'none' : ''; });
            Promise.all([import('/js/config/ThemeConfig.js'), import('/js/common/core/UIScale.js')]).then(([themes, ui]) => {
                if (accent >= 0) themes.setAccentIndex(accent);
                if (theme >= 0) themes.setThemeIndex(theme);
                if (scale > 0) ui.setUserScale(scale);
                // The palette follows within a second (poll); the log shows what it read.
                setTimeout(() => log('qa look ' + s.qaLook + ' accent-triplet=' + C('accent-triplet')
                    + ' panel-triplet=' + C('accentPanelBackground-triplet')), 2000);
            }).catch((e) => report('qa look ' + e));
        });
    }
    else {
        patchMainMenu().catch((e) => log('main menu import ' + e));
        Promise.all([import('/js/project/modules/frontEnd/data/FrontEndNavigation.js'), import('/js/project/modules/frontEnd/data/FrontEndNavData.js')])
            .then(([navModule, dataModule]) => { nav = { nav: navModule, data: dataModule }; })
            .catch((e) => log('nav import ' + e));
    }
    import('/js/project/data/DLCDataUtil.js').then((module) => { dlcModule = module; }).catch((e) => log('dlc import ' + e));
    const root = document.createElement('div');
    root.id = 'PC2Coop_root';
    root.style.position = 'absolute';
    root.style.left = '0px';
    root.style.top = '0px';
    root.style.zIndex = '10000';
    document.body.appendChild(root);
    try {
        preact.render(preact.h(CoopLayer, null), root);
        log('layer rendered');
    } catch (error) {
        log('render failed: ' + error);
    }
    setInterval(() => { try { poll(); } catch (error) { log('poll failed: ' + error); } }, 300);
    request('hello', app.indexOf('HUD.html') >= 0 ? 'hud' : 'frontend');
}
