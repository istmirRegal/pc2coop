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
import { InputfieldPrompt } from '/js/project/components/InputfieldPrompt.js';

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
function poll() {
    subscribe();
    try { applyState(DS.getValue(CONTEXT, 'state')); } catch (error) { /* context not created yet */ }
    try { applyAvatars(DS.getValue(CONTEXT, 'avatars')); } catch (error) { /* not there yet */ }
    polls += 1;
    if (polls % 10 === 1) reportDlc();
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
const BLUE = '#0079ad';
const INK = '#1b3a4e';
const MUTED = '#4b6a7c';

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
            style: { position: 'absolute', left: 0, top: 0, width: props.size + 'px', height: props.size + 'px' } });
    }
}

// Round profile picture; the player's colour and initial show while Steam has none.
function Avatar(props) {
    const p = props.player;
    const size = props.size || 40;
    // Passed in as a prop: the game's Preact re-renders a component only when its props change.
    const pic = props.pic;
    return h('div', { style: { position: 'relative', width: size + 'px', height: size + 'px', borderRadius: (size / 2) + 'px',
        background: '#' + (p.color || '6a8899'), color: '#ffffff', fontSize: Math.round(size * 0.5) + 'px', lineHeight: size + 'px',
        textAlign: 'center', overflow: 'hidden', flexShrink: 0, border: '2px solid #' + (p.color || '6a8899') } },
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
    if (join.phase === 'hostlobby') return { text: (join.host || 'Der Host') + ' ist zurück in der Lobby und wählt einen Park. Geh ins Hauptmenü, um dabei zu bleiben.', tone: 'wait' };
    if (join.phase && ['live', 'lobby', 'rejoin'].indexOf(join.phase) < 0) return { text: joinText(join), tone: 'busy' };
    if (!coop.role) {
        return { text: coop.context === 'menu' ? 'Erstelle eine Lobby oder tritt der Lobby eines Freundes bei.'
            : 'Hoste diesen Park und lade Freunde ein - sie bekommen ihn automatisch.', tone: 'idle' };
    }
    if (coop.desync) return { text: 'Nicht mehr synchron: ' + coop.desync + (coop.role === 'client' ? ' - "Neu synchronisieren" lädt den Park des Hosts erneut.' : ''), tone: 'warn' };
    if (coop.stage === 'lobby') {
        return { text: coop.role === 'host' ? 'Lobby offen. Wähle, wo ihr spielt - alle laden den Park dann automatisch.'
            : (host ? host.name : 'Der Host') + ' wählt gerade, wo ihr spielt ...', tone: 'wait' };
    }
    const loading = players.filter((p) => /^holt/.test(p.act || '') || p.act === 'laedt' || p.act === 'lobby');
    if (loading.length) return { text: loading.map((p) => p.name).join(', ') + (loading.length > 1 ? ' laden' : ' lädt') + ' den Park ...', tone: 'busy' };
    return { text: 'Alle verbunden' + (coop.parkTitle ? ' - ' + coop.parkTitle : '') + '.', tone: 'ok' };
}

const TONE = { ok: '#3fbf5f', busy: '#00c6ff', wait: '#fcc419', warn: '#ff922b', idle: '#9fb3bf' };

const ACT_LOBBY = 'in der Lobby';

function playerActivity(coop, p) {
    if (p.act === 'lobby') return coop.stage === 'park' ? 'wartet auf den Park' : ACT_LOBBY;
    if (coop.stage === 'lobby') return ACT_LOBBY;
    return activityText(p.act, p.hold);
}

// Small round player chips, always visible while in a park session.
class PlayerBar extends StateComponent {
    render(props, state) {
        const coop = state.coop || {};
        if (!coop.role || coop.context === 'menu' || list(coop.players).length === 0) return null;
        const join = coop.join || {};
        return h('div', { style: { position: 'absolute', top: '84px', right: '24px', display: 'flex', flexDirection: 'column',
            alignItems: 'flex-end' } },
            list(coop.players).map((p) => h('div', { key: p.sid, style: { display: 'flex', alignItems: 'center', margin: '3px 0',
                padding: '4px 12px 4px 4px', borderRadius: '20px', background: 'rgba(14, 33, 48, 0.72)' } },
                h(Avatar, { player: p, size: 28, pic: avatars[p.sid] }),
                h('div', { style: { color: '#ffffff', fontSize: '16px', marginLeft: '9px' } }, p.name + (p.me ? ' (du)' : '')),
                p.host && h(Icon, { src: 'img/icons/crown.svg', style: { width: '18px', height: '18px', marginLeft: '7px' } }),
                h('div', { style: { color: '#9fd8f0', fontSize: '13px', marginLeft: '9px' } }, playerActivity(coop, p)))),
            join.phase === 'hostlobby' && h('div', { style: { marginTop: '6px', padding: '8px 12px', maxWidth: '360px', borderRadius: '10px',
                background: 'rgba(14, 33, 48, 0.85)', color: '#fcc419', fontSize: '14px' } },
                'Host ist in der Lobby - Hauptmenü öffnen, um dabei zu bleiben.'));
    }
}

// Short notifications: joins, leaves, chat, conflicts.
class Toasts extends StateComponent {
    state = { visible: [] };
    componentDidMount() {
        super.componentDidMount();
        this._seen = 0;
        this._listenerToasts = (coop) => {
            const fresh = (coop.toasts || []).filter((t) => t.id > this._seen);
            if (fresh.length === 0) return;
            this._seen = Math.max(...fresh.map((t) => t.id));
            const now = Date.now();
            this.setState({ visible: [...this.state.visible, ...fresh.map((t) => ({ ...t, until: now + 6000 }))].slice(-5) });
        };
        listeners.add(this._listenerToasts);
        this._timer = setInterval(() => {
            const now = Date.now();
            if (this.state.visible.some((t) => t.until < now)) this.setState({ visible: this.state.visible.filter((t) => t.until >= now) });
        }, 500);
    }
    componentWillUnmount() {
        super.componentWillUnmount();
        listeners.delete(this._listenerToasts);
        clearInterval(this._timer);
    }
    render(props, state) {
        if (state.visible.length === 0) return null;
        return h('div', { style: { position: 'absolute', bottom: '120px', left: '24px', display: 'flex', flexDirection: 'column' } },
            state.visible.map((t) => h('div', { key: t.id, style: { margin: '4px 0', padding: '10px 16px', maxWidth: '520px',
                borderRadius: '10px', background: 'rgba(14, 33, 48, 0.82)', color: '#ffffff', fontSize: '17px',
                borderLeft: '5px solid #' + (t.color || '00c6ff') } }, t.loc ? shown(t.text) : t.text)));
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
    color: BLUE, fontSize: '18px', letterSpacing: '1px', textTransform: 'uppercase', margin: '16px 0 8px' } }, title, extra || null);

const row = (children, key) => h('div', { key, style: { display: 'flex', alignItems: 'center', justifyContent: 'space-between',
    flexWrap: 'wrap', padding: '5px 0', borderBottom: '1px solid rgba(0, 120, 170, 0.15)' } }, children);

const buttons = (items) => h('div', { style: { display: 'flex', flexWrap: 'wrap', justifyContent: 'flex-end', maxWidth: '100%' } },
    items.filter(Boolean).map((b, i) => h('div', { key: 'b' + i, style: { margin: '2px 0 2px 6px', maxWidth: '100%' } },
        h(Button, { label: literal(b.label), onSelect: b.onSelect, disabled: b.disabled, inputName: b.inputName }))));

// The lobby: the same panel in the main menu and in a park.
class Lobby extends StateComponent {
    state = { chatPrompt: false };
    render(props, state) {
        const coop = state.coop || {};
        if (!coop.open) return null;
        if (state.chatPrompt) {
            return h(InputfieldPrompt, { title: literal('Chat'), description: literal('Nachricht an alle in der Lobby'),
                commitButtonLabel: literal('Senden'), defaultInputText: literal(''), maxInput: 200,
                onCancel: () => this.setState({ chatPrompt: false }),
                onCloseAndCommit: (text) => { this.setState({ chatPrompt: false }); if (text) request('chat', text); } });
        }
        const status = statusOf(coop);
        const host = hostOf(coop);
        const title = !coop.role ? 'Multiplayer'
            : coop.role === 'host' ? 'Deine Lobby' : 'Lobby von ' + (host ? host.name : 'Host');
        const footer = [];
        if (!coop.available) {
            // Nothing to do without Steam.
        } else if (!coop.role) {
            footer.push({ label: coop.context === 'menu' ? 'Lobby erstellen' : 'Diesen Park hosten', onSelect: () => request('host'), disabled: !coop.canHost });
        } else {
            if (coop.desync && coop.role === 'client') footer.push({ label: 'Neu synchronisieren', onSelect: () => request('resync') });
            footer.push({ label: 'Einladen', onSelect: () => request('invite_overlay') });
            footer.push({ label: 'Nachricht', onSelect: () => this.setState({ chatPrompt: true }) });
            footer.push({ label: coop.role === 'host' ? 'Beenden' : 'Verlassen', onSelect: () => request('leave') });
        }
        footer.push({ label: 'Schließen', onSelect: () => request('close'), inputName: 'UI_Cancel' });
        // A dimmed backdrop keeps the menu behind it from being hovered or clicked.
        return h('div', { style: { position: 'absolute', left: 0, top: 0, width: '100vw', height: '100vh', background: 'rgba(4, 16, 26, 0.5)' } },
            h('div', { style: { position: 'absolute', left: '50%', top: '50%', width: '1180px', height: '780px', marginLeft: '-590px',
            marginTop: '-390px', display: 'flex', flexDirection: 'column', borderRadius: '14px', overflow: 'hidden',
            background: '#f4f8fa', color: INK, fontSize: '20px', boxShadow: '0 12px 40px rgba(0, 0, 0, 0.45)' } },
            h('div', { style: { display: 'flex', alignItems: 'center', height: '72px', flexShrink: 0, padding: '0 24px', background: '#0e2130', color: '#ffffff' } },
                h(Icon, { src: 'img/icons/collaborate.svg', style: { width: '28px', height: '28px', marginRight: '12px' } }),
                h('div', { style: { fontSize: '30px', flexGrow: 1 } }, title),
                coop.role && h('div', { style: { color: '#9fd8f0', fontSize: '18px' } },
                    list(coop.players).length + ' / ' + SLOTS + ' Spieler' + (coop.stage === 'park' && coop.parkTitle ? ' · ' + coop.parkTitle : ''))),
            h('div', { style: { display: 'flex', height: '574px', flexShrink: 0, overflow: 'hidden' } },
                h('div', { style: { width: '440px', height: '574px', padding: '4px 20px 16px 24px', overflowY: 'auto', borderRight: '1px solid rgba(0, 120, 170, 0.18)' } },
                    this.renderPlayers(coop)),
                h('div', { style: { width: '740px', height: '574px', padding: '4px 24px 16px 20px', overflowY: 'auto' } },
                    this.renderPlace(coop),
                    this.renderChat(coop),
                    this.renderContent(coop),
                    this.renderFriends(coop))),
            h('div', { style: { display: 'flex', alignItems: 'center', flexWrap: 'wrap', height: '134px', flexShrink: 0, padding: '8px 24px', background: '#e3edf2',
                borderTop: '1px solid rgba(0, 120, 170, 0.2)' } },
                h('div', { style: { display: 'flex', alignItems: 'center', flexGrow: 1, flexBasis: '420px', minWidth: 0, marginRight: '12px' } },
                    h('div', { style: { width: '12px', height: '12px', borderRadius: '6px', background: TONE[status.tone] || TONE.idle,
                        marginRight: '10px', flexShrink: 0 } }),
                    h('div', null, status.text)),
                h('div', { style: { flexBasis: '520px', flexGrow: 1, minWidth: 0 } }, buttons(footer)))));
    }

    renderPlayers(coop) {
        const players = list(coop.players);
        const requests = coop.role === 'host' ? list(coop.requests) : [];
        const slots = [];
        players.forEach((p) => {
            const content = contentLine(coop, p);
            const canLook = coop.stage === 'park' && coop.context === 'park' && !p.me && p.x !== undefined && p.act !== 'lobby';
            slots.push(h('div', { key: 'p' + p.sid, style: { display: 'flex', alignItems: 'center', padding: '8px 10px', margin: '6px 0',
                borderRadius: '10px', background: '#ffffff', border: '1px solid rgba(0, 120, 170, 0.18)' } },
                h(Avatar, { player: p, size: 44, pic: avatars[p.sid] }),
                h('div', { style: { flexGrow: 1, minWidth: 0, marginLeft: '12px' } },
                    h('div', { style: { display: 'flex', alignItems: 'center', fontSize: '22px', fontWeight: 'bold' } },
                        p.name + (p.me ? ' (du)' : ''),
                        p.host && h(Icon, { src: 'img/icons/crown.svg', style: { width: '16px', height: '16px', marginLeft: '6px' } })),
                    h('div', { style: { color: MUTED, fontSize: '17px' } }, playerActivity(coop, p)),
                    content && h('div', { style: { color: content.warn ? '#c2410c' : '#237a37', fontSize: '16px' } }, content.text),
                    canLook && buttons([
                        { label: 'Hinspringen', onSelect: () => request('jump', p.sid) },
                        { label: coop.following === p.sid ? 'Nicht folgen' : 'Folgen', onSelect: () => request('follow', p.sid) }]))));
        });
        if (coop.role) {
            for (let i = players.length; i < SLOTS; i++) {
                slots.push(h('div', { key: 'e' + i, style: { padding: '14px 12px', margin: '6px 0', borderRadius: '10px', color: MUTED,
                    background: '#e8f0f4', fontSize: '17px' } }, 'Freier Platz'));
            }
        }
        return [
            requests.length > 0 && section('Möchte beitreten'),
            ...requests.map((r) => row([h('div', null, r.name), buttons([
                { label: 'Zulassen', onSelect: () => request('approve', r.sid) },
                { label: 'Ablehnen', onSelect: () => request('deny', r.sid) }])], 'r' + r.sid)),
            section('Spieler'),
            !coop.role && h('div', { style: { color: MUTED, padding: '6px 0' } },
                coop.context === 'menu' ? 'Noch keine Lobby. Erstelle eine (unten) oder tritt rechts der Lobby eines Freundes bei.'
                    : 'Noch keine Sitzung. "Diesen Park hosten" teilt ihn mit deinen Freunden.'),
            ...slots,
        ];
    }

    renderPlace(coop) {
        if (!coop.role) return null;
        if (coop.stage === 'lobby' && coop.role === 'host' && coop.context === 'menu') {
            return [section('Wo spielen wir?'),
                h('div', { style: { display: 'flex', flexWrap: 'wrap' } }, MODES.map((mode) => h('div', { key: mode.key,
                    onClick: () => openScreen(mode),
                    style: { width: '220px', margin: '0 10px 10px 0', padding: '12px 14px', borderRadius: '10px',
                        background: mode.later ? '#e9eef1' : '#ffffff', color: mode.later ? '#9fb3bf' : INK,
                        border: '1px solid ' + (mode.later ? 'rgba(0, 0, 0, 0.06)' : 'rgba(0, 160, 216, 0.5)') } },
                    h('div', { style: { fontSize: '20px' } }, mode.title),
                    h('div', { style: { fontSize: '16px', color: mode.later ? '#b5c4cc' : MUTED } }, mode.text))))];
        }
        if (coop.stage === 'lobby') {
            return [section('Wo spielen wir?'), h('div', { style: { color: MUTED } },
                coop.role === 'host' ? 'Geh ins Hauptmenü, um einen Park zu wählen.' : 'Der Host wählt. Sobald der Park offen ist, lädt er bei dir automatisch.')];
        }
        const out = [section('Park des Hosts', coop.parkTitle ? h('span', { style: { color: MUTED, textTransform: 'none', letterSpacing: 0 } }, coop.parkTitle) : null)];
        if (coop.park) out.push(h('div', null, (coop.park.guests || 0).toLocaleString('de-DE') + ' Besucher · ' + money(coop.park)));
        list(coop.stats).forEach((s) => out.push(h('div', { key: 's' + s.name, style: { padding: '2px 0', color: MUTED } },
            s.name + ': ' + s.created + ' platziert, ' + s.edited + ' bearbeitet, ' + s.deleted + ' gelöscht')));
        if (list(coop.log).length) {
            out.push(section('Verlauf'));
            list(coop.log).slice(-5).forEach((line, i) => out.push(h('div', { key: 'l' + i, style: { padding: '2px 0', color: '#4a6b7d' } }, line)));
        }
        return out;
    }

    renderChat(coop) {
        if (!coop.role) return null;
        const chat = list(coop.chat).slice(-6);
        return [section('Chat'),
            chat.length === 0 && h('div', { style: { color: MUTED } }, 'Noch keine Nachrichten. "Nachricht" unten schreibt allen.'),
            ...chat.map((c, i) => h('div', { key: 'c' + i, style: { padding: '2px 0' } },
                h('span', { style: { color: '#' + (c.color || '20435a') } }, c.name + ': '), c.text))];
    }

    renderContent(coop) {
        const players = list(coop.players);
        if (!coop.role || players.length < 2) return null;
        const known = players.filter((p) => p.dlc !== undefined);
        const uneven = dlcPacks().filter((pack) => known.some((p) => owns(p.dlc, pack.id)) && known.some((p) => !owns(p.dlc, pack.id)));
        const out = [section('Inhalte')];
        if (known.length < players.length) out.push(h('div', { style: { color: MUTED } }, 'DLCs der Mitspieler werden geprüft ...'));
        else if (uneven.length === 0) out.push(h('div', { style: { color: '#237a37' } }, 'Alle haben dieselben DLCs.'));
        else {
            out.push(h('div', null, 'Nicht alle haben: ' + uneven.map(packName).join(', ')));
            out.push(h('div', { style: { color: MUTED, fontSize: '17px' } }, coop.guard
                ? 'Objekte daraus werden nicht gebaut (gemeinsamer Nenner).'
                : 'Objekte daraus werden trotzdem gebaut - bei wem das DLC fehlt, fehlen sie evtl.'));
        }
        if (coop.role === 'host') {
            out.push(buttons([{ label: coop.guard ? 'Alle Inhalte erlauben' : 'Nur gemeinsame Inhalte', onSelect: () => request('guard', coop.guard ? '0' : '1') }]));
        }
        return out;
    }

    renderFriends(coop) {
        if (!coop.available) return null;
        const friends = list(coop.friends).slice(0, 30);
        const inSession = {};
        list(coop.players).forEach((p) => { inSession[p.sid] = true; });
        return [section('Steam-Freunde'),
            friends.length === 0 && h('div', { style: { color: MUTED } }, 'Lade Freundesliste ...'),
            ...friends.map((f) => row([
                h('div', { style: { minWidth: 0 } }, f.name,
                    h('span', { style: { color: f.lobby ? '#2f9e44' : f.pc2 ? '#00a65a' : MUTED, marginLeft: '10px', fontSize: '17px' } },
                        f.lobby ? 'hat eine offene Lobby' : f.pc2 ? 'spielt Planet Coaster 2' : (FRIEND_STATE[f.state] || ''))),
                inSession[f.sid] ? h('span', { style: { color: '#2f9e44' } }, 'ist dabei')
                    : coop.role ? buttons([{ label: f.invited ? 'Eingeladen' : 'Einladen', disabled: f.invited, onSelect: () => request('invite', f.sid) }])
                    : f.lobby ? buttons([{ label: 'Beitreten', onSelect: () => request('join_friend', f.sid) }]) : null,
            ], 'f' + f.sid))];
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
        const chip = (label, onClick) => h('div', { onClick, style: { marginLeft: '8px', padding: '5px 12px', borderRadius: '14px',
            background: 'rgba(0, 160, 216, 0.9)', color: '#ffffff', fontSize: '17px' } }, label);
        return h('div', { style: { position: 'absolute', left: '1480px', top: '230px', width: '410px', padding: '12px 16px', pointerEvents: 'auto',
            borderRadius: '12px', background: 'rgba(14, 33, 48, 0.9)', color: '#ffffff', borderLeft: '5px solid ' + (TONE[status.tone] || TONE.idle) } },
            h('div', { style: { display: 'flex', alignItems: 'center' } },
                h('div', { style: { fontSize: '20px', flexGrow: 1 } }, coop.role === 'host' ? 'Deine Lobby' : 'Lobby'),
                list(coop.players).slice(0, SLOTS).map((p) => h('div', { key: p.sid, style: { marginLeft: '-6px' } }, h(Avatar, { player: p, size: 26, pic: avatars[p.sid] })))),
            h('div', { style: { color: '#9fd8f0', fontSize: '16px', margin: '6px 0 8px' } }, status.text),
            h('div', { style: { display: 'flex', justifyContent: 'flex-end' } },
                chip('Lobby öffnen', () => request('open')),
                chip(coop.role === 'host' ? 'Beenden' : 'Verlassen', () => request('leave'))));
    }
}

function joinText(join) {
    const host = join.host ? ' von ' + join.host : '';
    if (join.phase === 'joining') return 'Trete der Lobby bei ...';
    if (join.phase === 'silent') return 'Keine Verbindung zum Host - warte ...';
    if (join.phase === 'asking') return 'Warte auf die Zustimmung' + host + ' ...';
    if (join.phase === 'confirm') return 'Beitritt' + (join.host ? ' bei ' + join.host : '') + ' wartet auf deine Bestätigung.';
    if (join.phase === 'awaiting') return 'Empfange den Park' + host + ' ... ' + Math.round((join.progress || 0) * 100) + ' %';
    if (join.phase === 'loading') return 'Lade den Park' + host + ' ...';
    if (join.phase === 'lobby') return 'In der Lobby' + host + '.';
    return 'Verbunden' + host + '.';
}

// Card in the screen centre while a park is on its way (menu or park).
class JoinProgress extends StateComponent {
    render(props, state) {
        const coop = state.coop || {};
        const join = coop.join;
        if (!join || ['joining', 'asking', 'awaiting', 'loading', 'silent'].indexOf(join.phase) < 0 || coop.open) return null;
        const share = join.phase === 'awaiting' ? (join.progress || 0) : join.phase === 'loading' ? 1 : 0.02;
        return h('div', { style: { position: 'absolute', left: '50%', top: '42%', width: '520px', marginLeft: '-260px',
            padding: '22px 28px', borderRadius: '14px', background: 'rgba(14, 33, 48, 0.9)', color: '#ffffff', textAlign: 'center' } },
            h('div', { style: { fontSize: '22px', marginBottom: '6px' } }, 'Multiplayer'),
            h('div', { style: { fontSize: '17px', color: '#9fd8f0', marginBottom: '14px' } }, joinText(join)),
            h('div', { style: { height: '8px', borderRadius: '4px', background: 'rgba(255, 255, 255, 0.15)' } },
                h('div', { style: { height: '8px', borderRadius: '4px', background: '#00c6ff', width: Math.round(share * 100) + '%' } })));
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
            h(Toasts, null),
            h(JoinProgress, null),
            h(MiniLobby, null),
            h('div', { style: { pointerEvents: 'auto' } }, h(Lobby, null)),
            h('div', { style: { pointerEvents: 'auto' } }, h(JoinFailed, null)),
            h('div', { style: { pointerEvents: 'auto' } }, h(JoinConfirm, null)),
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

function patchMenuClass(menuClass) {
    const proto = menuClass && menuClass.prototype;
    if (!proto || proto.__pc2coop || typeof proto.getGameMenuBtn !== 'function') return;
    const build = proto.getGameMenuBtn;
    proto.getGameMenuBtn = function (id, ...rest) {
        const button = build.call(this, id, ...rest);
        if (typeof id === 'string' && id.indexOf('Exit') === 0) {
            const ours = build.call(this, 'PC2CoopMultiplayer', 'collaborate', () => request('open'));
            if (ours && ours.attributes) ours.attributes.label = literal('Multiplayer');
            return [ours, button];
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
                const description = literal('Mit Steam-Freunden live im selben Park bauen. Lobby öffnen, Freunde einladen, gemeinsam einen Park wählen.');
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
    if (app.indexOf('HUD.html') >= 0) patchPauseMenu().catch((e) => console.log('PC2Coop: ' + e));
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
