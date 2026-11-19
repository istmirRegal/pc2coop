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
        // On a ride the game's camera panel sits up here; the visitor bar shows the ride.
        if (coop.visitor && coop.visitor.riding) return null;
        const join = coop.join || {};
        return h('div', { style: { position: 'absolute', top: '84px', right: '24px', display: 'flex', flexDirection: 'column',
            alignItems: 'flex-end' } },
            list(coop.players).map((p) => h('div', { key: p.sid, onClick: p.me ? undefined : () => request('follow', p.sid),
                style: { display: 'flex', alignItems: 'center', margin: '3px 0', pointerEvents: p.me ? 'none' : 'auto',
                padding: '4px 12px 4px 4px', borderRadius: '20px', background: 'rgba(14, 33, 48, 0.72)',
                border: '2px solid ' + (coop.following === p.sid ? '#fcc419' : 'transparent') } },
                h(Avatar, { player: p, size: 28, pic: avatars[p.sid] }),
                h('div', { style: { color: '#ffffff', fontSize: '16px', marginLeft: '9px' } }, p.name + (p.me ? ' (du)' : '')),
                p.host && h(Icon, { src: 'img/icons/crown.svg', style: { width: '18px', height: '18px', marginLeft: '7px' } }),
                h('div', { style: { color: coop.following === p.sid ? '#fcc419' : '#9fd8f0', fontSize: '13px', marginLeft: '9px' } },
                    coop.following === p.sid ? 'du folgst - klicken beendet'
                        : ((coop.visitor && coop.visitor.emotes && coop.visitor.emotes[p.sid]) || playerActivity(coop, p))))),
            join.phase === 'hostlobby' && h('div', { style: { marginTop: '6px', padding: '8px 12px', maxWidth: '360px', borderRadius: '10px',
                background: 'rgba(14, 33, 48, 0.85)', color: '#fcc419', fontSize: '14px' } },
                'Host ist in der Lobby - Hauptmenü öffnen, um dabei zu bleiben.'));
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
        const pill = { display: 'flex', flexDirection: 'column', alignItems: 'center', padding: '6px 10px', borderRadius: '18px',
            background: 'rgba(14, 33, 48, 0.82)', color: '#ffffff', fontSize: '15px' };
        const bar = h('div', { style: pill },
            visitor.active && h('div', { style: { margin: '0 0 4px', color: '#9fd8f0' } },
                visitor.riding ? 'Du fährst ' + visitor.riding + ' - "Zurück" unten rechts steigt aus'
                    : visitor.guest ? 'Ich-Sicht: WASD laufen, Alt springen, Strg ducken, L Lampe, Eingänge wie im Spiel · E Shop · T Emotes · V Ansicht von hinten · Tab zurück'
                    : 'Besucher: Maus umsehen · WASD laufen · Shift rennen · E Eingang oder Shop · T Emotes · V Ich-Sicht · Tab zurück'),
            // A shop's buy list: 1-6 buy, E or Tab close (names are the game's loc keys).
            visitor.shop && h('div', { style: { display: 'flex', flexDirection: 'column', margin: '0 0 6px', padding: '6px 10px',
                    borderRadius: '10px', background: 'rgba(255, 255, 255, 0.08)' } },
                h('div', { style: { color: '#ffd43b', margin: '0 0 4px' } }, 'Kaufen: Taste 1-6 oder anklicken · E schließt'),
                ...list(visitor.shop.items).map((it) => h('div', { key: 'buy' + it.n, onClick: () => request('buy', String(it.n)),
                        style: { display: 'flex', justifyContent: 'space-between', padding: '2px 0', cursor: 'pointer' } },
                    h('span', { style: { margin: '0 8px 0 0', color: '#9fd8f0' } }, it.n + ''),
                    h('span', { style: { flexGrow: 1 } }, (it.name && shown(it.name)) || it.fallback),
                    h('span', { style: { margin: '0 0 0 12px' } }, it.price)))),
            // What E does at the entrance in front, in the game's own words (loc keys).
            visitor.active && !visitor.guest && visitor.hint && h('div', { style: { display: 'flex', margin: '0 0 4px', color: '#ffd43b' } },
                h('span', { style: { margin: '0 6px 0 0' } }, 'E:'), h('span', null, shown(visitor.hint.action)),
                visitor.hint.blocker && h('span', { style: { margin: '0 0 0 6px', color: '#ff922b' } }, shown(visitor.hint.blocker))),
            buttons([
                !visitor.active && { label: 'Als Besucher losgehen', onSelect: () => request('visitor', '1') },
                ...(visitor.active && coop.role ? EMOTE_BUTTONS.map(([kind, label]) => ({ label, onSelect: () => request('emote', kind) })) : []),
                { label: visitor.list ? 'Liste schließen' : 'Fahrgeschäfte', onSelect: () => request('visitorlist', visitor.list ? '0' : '1') },
                visitor.active && !visitor.riding && { label: visitor.guest ? 'Ansicht von hinten' : 'Ich-Sicht', onSelect: () => request('view', '1') },
                visitor.active && { label: 'Zurück zum Bauen', onSelect: () => request('visitor', '0') },
            ]));
        const rides = list(visitor.rides);
        const picked = rides.find((r) => r.key === state.picked);
        const panel = visitor.list && h('div', { style: { width: '1000px', marginTop: '8px', borderRadius: '12px', overflow: 'hidden',
            background: '#f4f8fa', color: INK, fontSize: '17px' } },
            h('div', { style: { height: '44px', lineHeight: '44px', padding: '0 18px', background: '#0e2130', color: '#ffffff', fontSize: '18px' } },
                'Fahrgeschäfte im Park - nächstes zuerst'),
            box(picked && coop.role ? 330 : 400, rides.length === 0
                ? h('div', { style: { padding: '18px', color: MUTED } }, 'Noch keine Fahrgeschäfte im Park.')
                : rides.map((r) => {
                    const mine = state.stars[r.key] || r.mine;
                    const stats = typeof r.e === 'number'
                        ? 'Spaß ' + one(r.e) + '  ·  Angst ' + one(r.f) + '  ·  Übelkeit ' + one(r.n)
                        : 'noch nicht getestet';
                    const extra = [r.dist !== false ? r.dist + ' m' : null, typeof r.queue === 'number' ? Math.round(r.queue) + ' in der Schlange' : null,
                        r.trains ? r.trains + ' Züge' : null].filter(Boolean).join('  ·  ');
                    return h('div', { key: r.key, style: { padding: '8px 18px', borderBottom: '1px solid rgba(0, 120, 170, 0.15)',
                        background: state.picked === r.key ? '#e3edf2' : 'transparent' } },
                        h('div', { style: { display: 'flex', justifyContent: 'space-between', alignItems: 'center' } },
                            h('div', { style: { width: '520px' } },
                                h('div', { style: { fontSize: '18px' } }, r.name + '  ', h('span', { style: { color: MUTED, fontSize: '15px' } }, r.kind)),
                                h('div', { style: { color: MUTED, fontSize: '15px' } }, stats + (extra ? '  ·  ' + extra : '')),
                                h('div', { style: { color: BLUE, fontSize: '15px' } },
                                    r.count ? 'Bewertung ' + one(r.avg) + ' / 5 (' + r.count + ')' : 'noch keine Bewertung')),
                            buttons([
                                { label: 'Mitfahren', onSelect: () => request('ride', r.key) },
                                ...(coop.role ? [1, 2, 3, 4, 5].map((n) => ({ label: (mine === n ? '(' + n + ')' : String(n)),
                                    onSelect: () => {
                                        this.setState({ picked: r.key, stars: { ...state.stars, [r.key]: n } });
                                        request('rate', r.key + '|' + n + '|');
                                    } })) : []),
                            ])),
                        list(r.comments).slice(-2).map((c, i) => h('div', { key: 'c' + i, style: { color: INK, fontSize: '15px', marginTop: '3px' } },
                            c.who + ' (' + c.stars + '/5): ' + c.text)));
                })),
            picked && coop.role && h('div', { style: { padding: '10px 18px', background: '#e3edf2' } },
                h(InputField, { text: state.draft, promptText: literal('Vorschlag zu ' + picked.name + ' ... (Enter sendet)'), maxInputLength: 120,
                    beginEditOnSelect: true, onChange: (e) => this.setState({ draft: (e && e.text) || '' }), onCommit: (e) => {
                        const text = String((e && e.text) || '').trim().split('|').join(' ');
                        this.setState({ draft: '' });
                        const stars = state.stars[picked.key] || picked.mine;
                        if (text && stars) request('rate', picked.key + '|' + stars + '|' + text);
                    }, onCancel: () => this.setState({ draft: '' }) })));
        return h('div', { style: { position: 'absolute', top: '52px', left: '50%', width: '1000px', marginLeft: '-500px',
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
                return h('div', { key: label, style: { position: 'absolute', left: (Math.sin(angle) * radius - 70) + 'px',
                    top: (-Math.cos(angle) * radius - 24) + 'px', width: '140px', height: '48px', lineHeight: '48px', textAlign: 'center',
                    borderRadius: '24px', fontSize: '19px', background: on ? BLUE : 'rgba(14, 33, 48, 0.85)', color: '#ffffff',
                    border: '2px solid ' + (on ? '#ffffff' : 'rgba(255, 255, 255, 0.25)') } }, (i + 1) + '  ' + label);
            }),
            h('div', { style: { position: 'absolute', left: '-110px', top: '-14px', width: '220px', textAlign: 'center', color: '#ffffff',
                fontSize: '15px', textShadow: '0 1px 3px #000' } }, 'Maus bewegen, T loslassen'));
    }
}

// A decision for everyone (e.g. back to a checkpoint): a banner at the top until answered.
class VoteBanner extends StateComponent {
    render(props, state) {
        const coop = state.coop || {};
        const vote = coop.team && coop.team.vote;
        if (!vote) return null;
        return h('div', { style: { position: 'absolute', top: '140px', left: '50%', width: '760px', marginLeft: '-380px', padding: '14px 18px',
            borderRadius: '12px', background: 'rgba(14, 33, 48, 0.92)', color: '#ffffff', fontSize: '18px', pointerEvents: 'auto' } },
            h('div', { style: { marginBottom: '8px' } }, 'Abstimmung von ' + vote.by + ': ' + vote.text),
            vote.answered ? h('div', { style: { color: '#9fd8f0' } }, 'Deine Stimme ist abgegeben - warte auf die anderen.')
                : buttons([{ label: 'Ja', onSelect: () => request('vote', '1') }, { label: 'Nein', onSelect: () => request('vote', '0') }]));
    }
}

// Where the mouse was last: the context menu opens there.
let mouseAt = null;
try { document.addEventListener('mousemove', (e) => { mouseAt = { x: e.clientX, y: e.clientY }; }); } catch (e) { mouseAt = null; }

// After an own ping (short middle click): what can be done at that spot.
class ContextMenu extends StateComponent {
    render(props, state) {
        const coop = state.coop || {};
        const ctx = coop.team && coop.team.context;
        if (!ctx || coop.open || (coop.visitor && coop.visitor.active)) { this.at = null; return null; }
        const key = ctx.x + ',' + ctx.z;
        if (!this.at || this.at.key !== key) {
            const w = window.innerWidth || 1920, hgt = window.innerHeight || 1080;
            const m = mouseAt || { x: w / 2, y: hgt / 2 };
            this.at = { key, x: Math.min(m.x + 18, w - 380), y: Math.min(Math.max(m.y - 20, 10), hgt - 420) };
        }
        const item = (label, arg, strong) => h('div', { key: arg, onClick: () => request('ctx', arg),
            style: { padding: '9px 14px', fontSize: '17px', cursor: 'pointer', borderTop: '1px solid rgba(255, 255, 255, 0.12)',
                color: strong ? '#9fe3ff' : '#ffffff' } }, label);
        return h('div', { style: { position: 'absolute', left: this.at.x + 'px', top: this.at.y + 'px', width: '360px', borderRadius: '10px',
            background: 'rgba(14, 33, 48, 0.94)', color: '#ffffff', pointerEvents: 'auto', overflow: 'hidden' } },
            h('div', { style: { padding: '8px 14px', fontSize: '15px', color: '#9fd8f0' } }, ctx.ride ? ctx.ride.name : 'Hier'),
            ctx.ride && item('Team zur Testfahrt einladen', 'invite', true),
            ctx.ride && item('Selbst mitfahren', 'ride'),
            ...list(ctx.editors).map((e) => item('Übernahme bei ' + e.name + ' anfragen (' + e.label + ')', 'take|' + e.sid, true)),
            item('Kommentar anheften', 'comment'),
            item('Bauvorschlag machen', 'proposal'),
            item('Hier bauen (Baugebiet)', 'area'),
            item('Treffpunkt', 'meet'),
            item('Schließen', 'close'));
    }
}

// A running competition: a small clock at the top for everyone.
class CompBanner extends StateComponent {
    render(props, state) {
        const coop = state.coop || {};
        const comp = coop.team && coop.team.competition;
        if (!comp || coop.open || comp.phase === 'done') return null;
        const s = comp.left || 0;
        const text = comp.phase === 'build' ? comp.label + (comp.topic ? ' · ' + comp.topic : '') + ' · noch ' + Math.floor(s / 60) + ':' + (s % 60 < 10 ? '0' : '') + (s % 60)
            : 'Bewerten: Multiplayer > Sitzung';
        return h('div', { style: { position: 'absolute', top: '18px', left: '50%', width: '520px', marginLeft: '-260px', textAlign: 'center',
            padding: '6px 12px', borderRadius: '16px', background: 'rgba(14, 33, 48, 0.85)', color: '#ffffff', fontSize: '17px' } }, text);
    }
}

// A test ride invitation from another player.
class InviteBanner extends StateComponent {
    render(props, state) {
        const coop = state.coop || {};
        const invite = coop.team && coop.team.invitation;
        if (!invite || coop.open) return null;
        return h('div', { style: { position: 'absolute', top: '140px', left: '50%', width: '640px', marginLeft: '-320px', padding: '12px 16px',
            borderRadius: '12px', background: 'rgba(14, 33, 48, 0.92)', color: '#ffffff', fontSize: '18px', pointerEvents: 'auto' } },
            h('div', { style: { marginBottom: '8px' } }, invite.by + ' lädt zur Testfahrt auf ' + invite.name + ' ein.'),
            buttons([{ label: 'Mitfahren', onSelect: () => request('invitation', '1') }, { label: 'Später', onSelect: () => request('invitation', '0') }]));
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

// The lobby: the same panel in the main menu and in a park. Three columns: players, where
// to play (or the park), chat and friends. Fixed sizes: Gameface does not shrink flex boxes.
const BIOMES = [['Temperate', 'Gemäßigt'], ['Mediterranean', 'Mediterran'], ['Taiga', 'Taiga'], ['Tropical', 'Tropisch']];
const box = (height, children, extra) => h('div', { style: Object.assign({ height: height + 'px', overflowY: 'auto' }, extra || {}) }, children);

// Tabs of the multiplayer window in a park (docs/KONZEPT.md).
const PANEL_TABS = [['team', 'Team'], ['visit', 'Besuchen'], ['plan', 'Planen'], ['history', 'Verlauf'], ['session', 'Sitzung']];
const BOARD_KINDS = [['task', 'Aufgabe'], ['area', 'Baugebiet'], ['proposal', 'Vorschlag'], ['comment', 'Kommentar'], ['meet', 'Treffpunkt']];
const BOARD_WORD = { task: 'Aufgabe', area: 'Baugebiet', proposal: 'Vorschlag', comment: 'Kommentar', meet: 'Treffpunkt' };
const RULES = [
    ['speed', 'Spieltempo und Pause', [['all', 'alle'], ['host', 'nur der Host']]],
    ['foreign', 'Fremde Bauten abreißen', [['free', 'erlaubt'], ['ask', 'erst fragen']]],
    ['visitors', 'Besucher-Modus', [['1', 'erlaubt'], ['0', 'aus']]],
];

class Lobby extends StateComponent {
    state = { draft: '', tab: 'save', creative: true, kind: 'task', title: '', text: '', assignee: '', radius: 20 };
    render(props, state) {
        const coop = state.coop || {};
        if (!coop.open) return null;
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
            footer.push({ label: 'Steam-Overlay', onSelect: () => request('invite_overlay') });
            footer.push({ label: coop.role === 'host' ? 'Beenden' : 'Verlassen', onSelect: () => request('leave') });
        }
        footer.push({ label: 'Schließen', onSelect: () => request('close'), inputName: 'UI_Cancel' });
        const column = (width, children, last) => h('div', { style: { width: width + 'px', height: '636px', padding: '0 18px',
            borderRight: last ? 'none' : '1px solid rgba(0, 120, 170, 0.18)' } }, children);
        return h('div', { style: { position: 'absolute', left: 0, top: 0, width: '100vw', height: '100vh', background: 'rgba(4, 16, 26, 0.5)' } },
            h('div', { style: { position: 'absolute', left: '50%', top: '50%', width: '1320px', height: '780px', marginLeft: '-660px',
                marginTop: '-390px', borderRadius: '14px', overflow: 'hidden', background: '#f4f8fa', color: INK, fontSize: '19px',
                boxShadow: '0 12px 40px rgba(0, 0, 0, 0.45)' } },
                h('div', { style: { display: 'flex', alignItems: 'center', height: '64px', padding: '0 24px', background: '#0e2130', color: '#ffffff' } },
                    h(Icon, { src: 'img/icons/collaborate.svg', style: { width: '28px', height: '28px', marginRight: '12px' } }),
                    h('div', { style: { fontSize: '28px', flexGrow: 1 } }, title),
                    coop.role && h('div', { style: { color: '#9fd8f0', fontSize: '18px' } },
                        list(coop.players).length + ' / ' + SLOTS + ' Spieler' + (coop.stage === 'park' && coop.parkTitle ? ' · ' + coop.parkTitle : ''))),
                this.renderBody(coop, state, column),
                h('div', { style: { display: 'flex', alignItems: 'center', height: '80px', padding: '0 24px', background: '#e3edf2',
                    borderTop: '1px solid rgba(0, 120, 170, 0.2)' } },
                    h('div', { style: { width: '12px', height: '12px', borderRadius: '6px', background: TONE[status.tone] || TONE.idle,
                        marginRight: '10px', flexShrink: 0 } }),
                    h('div', { style: { width: '640px', fontSize: '19px' } }, status.text),
                    h('div', { style: { width: '620px' } }, buttons(footer)))));
    }

    // In a park with a session: five tabs; everywhere else the lobby as before.
    renderBody(coop, state, column) {
        const team = coop.team;
        const inPark = coop.role && coop.context !== 'menu' && team;
        const tab = inPark ? team.tab : 'team';
        const bar = inPark && h('div', { style: { display: 'flex', height: '44px', alignItems: 'center', padding: '0 18px',
            background: '#e3edf2', borderBottom: '1px solid rgba(0, 120, 170, 0.2)' } },
            PANEL_TABS.map(([key, label]) => h('div', { key, onClick: () => request('paneltab', key),
                style: { padding: '6px 18px', marginRight: '8px', borderRadius: '16px', fontSize: '18px',
                    background: tab === key ? BLUE : '#ffffff', color: tab === key ? '#ffffff' : INK,
                    border: '1px solid rgba(0, 121, 173, 0.45)' } }, label)));
        const height = inPark ? 592 : 636;
        let body;
        if (tab === 'visit') body = this.renderVisit(coop, height);
        else if (tab === 'plan') body = this.renderPlan(coop, state, height);
        else if (tab === 'history') body = this.renderHistory(coop, height);
        else if (tab === 'session') body = this.renderSession(coop, height);
        else body = h('div', { style: { display: 'flex', height: height + 'px' } },
            column(360, this.renderPlayers(coop)),
            column(540, [this.renderPlace(coop, state), this.renderContent(coop)]),
            column(420, [this.renderChat(coop, state), this.renderFriends(coop)], true));
        return h('div', { style: { height: '636px' } }, bar, body);
    }

    renderVisit(coop, height) {
        const visitor = coop.visitor || {};
        const rules = (coop.team && coop.team.rules) || {};
        const blocked = coop.role === 'client' && rules.visitors === '0';
        return h('div', { style: { display: 'flex', height: height + 'px' } },
            h('div', { style: { width: '420px', padding: '0 18px', borderRight: '1px solid rgba(0, 120, 170, 0.18)' } },
                section('Als Besucher im Park'),
                h('div', { style: { color: MUTED, fontSize: '16px', marginBottom: '8px' } }, blocked
                    ? 'Der Host hat den Besucher-Modus für diese Sitzung ausgeschaltet.'
                    : 'Lauf durch euren Park, fahr mit, bewerte die Fahrgeschäfte. Die anderen sehen dich dort, wo du stehst.'),
                buttons([
                    !blocked && !visitor.active && { label: 'Als Besucher losgehen', onSelect: () => request('visitor', '1') },
                    visitor.active && { label: 'Zurück zum Bauen', onSelect: () => request('visitor', '0') },
                    !blocked && { label: 'Ich-Sicht (Spiel)', onSelect: () => { request('visitor', '1'); request('guest', '1'); } },
                ]),
                section('Steuerung'),
                h('div', { style: { fontSize: '16px', lineHeight: '24px' } },
                    'WASD laufen, Shift schneller', h('br'), 'Maus: umsehen', h('br'),
                    'T halten: Emotes  ·  E: einsteigen', h('br'), 'Tab: zurück zum Bauen'),
                section('Gemeinsam'),
                h('div', { style: { color: MUTED, fontSize: '16px' } },
                    'Testfahrt mit allen: in der Liste rechts "Mitfahren" - jeder kann einsteigen. Führung: Mitspieler oben rechts anklicken, dann folgst du ihm.')),
            h('div', { style: { width: '900px', padding: '0 18px' } },
                section('Fahrgeschäfte', h('span', { style: { color: MUTED, fontSize: '15px', textTransform: 'none' } }, 'das nächste zuerst')),
                box(height - 60, list(visitor.rides).length === 0
                    ? h('div', { style: { color: MUTED, padding: '8px 0' } }, 'Noch keine Fahrgeschäfte im Park.')
                    : list(visitor.rides).map((r) => row([
                        h('div', { style: { width: '470px' } },
                            h('div', { style: { fontSize: '18px' } }, r.name + '  ', h('span', { style: { color: MUTED, fontSize: '15px' } }, r.kind)),
                            h('div', { style: { color: MUTED, fontSize: '15px' } }, (typeof r.e === 'number'
                                ? 'Spaß ' + one(r.e) + '  ·  Angst ' + one(r.f) + '  ·  Übelkeit ' + one(r.n) : 'noch nicht getestet')
                                + (r.dist !== false ? '  ·  ' + r.dist + ' m' : '')),
                            h('div', { style: { color: BLUE, fontSize: '15px' } }, r.count ? 'Bewertung ' + one(r.avg) + ' / 5 (' + r.count + ')'
                                + (list(r.comments).length ? ' - "' + list(r.comments)[list(r.comments).length - 1].text + '"' : '') : 'noch keine Bewertung')),
                        buttons([{ label: 'Mitfahren', onSelect: () => { request('visitor', '1'); request('ride', r.key); } },
                            coop.role && { label: 'Alle einladen', onSelect: () => request('invite_ride', r.key + '|' + r.name) }]),
                    ], 'r' + r.key)))));
    }

    renderPlan(coop, state, height) {
        const team = coop.team || {};
        const items = list(team.board);
        const players = list(coop.players);
        // A context action (ping menu) picks the kind once; after that the buttons here do.
        const kind = team.planSeq && team.planSeq !== state.planSeq ? team.planKind : state.kind;
        const needsPlace = kind !== 'task';
        const nextAssignee = () => {
            const names = ['', ...players.map((p) => p.name)];
            const i = names.indexOf(state.assignee);
            this.setState({ assignee: names[(i + 1) % names.length] });
        };
        const add = () => {
            const clip = (t) => String(t || '').split('|').join(' ').trim();
            request('board_add', [kind, clip(state.title), clip(state.text), clip(state.assignee), kind === 'area' ? state.radius : 0].join('|'));
            this.setState({ title: '', text: '', kind, planSeq: team.planSeq });
        };
        return h('div', { style: { display: 'flex', height: height + 'px' } },
            h('div', { style: { width: '460px', padding: '0 18px', borderRight: '1px solid rgba(0, 120, 170, 0.18)' } },
                section('Neu'),
                h('div', { style: { display: 'flex', flexWrap: 'wrap', marginBottom: '8px' } },
                    BOARD_KINDS.map(([key, label]) => h('div', { key, onClick: () => this.setState({ kind: key, planSeq: team.planSeq }),
                        style: { padding: '6px 14px', margin: '0 6px 6px 0', borderRadius: '16px', fontSize: '17px',
                            background: kind === key ? BLUE : '#ffffff', color: kind === key ? '#ffffff' : INK,
                            border: '1px solid rgba(0, 121, 173, 0.45)' } }, label))),
                h('div', { style: { margin: '6px 0' } }, h(InputField, { text: state.title, maxInputLength: 60, beginEditOnSelect: true,
                    promptText: literal(kind === 'area' ? 'Name des Gebiets ("Wikingerland")' : kind === 'task' ? 'Was ist zu tun?'
                        : kind === 'proposal' ? 'Idee ("Wildwasserbahn am See?")' : 'Titel'),
                    onChange: (e) => this.setState({ title: (e && e.text) || '' }), onCommit: (e) => this.setState({ title: (e && e.text) || '' }) })),
                h('div', { style: { margin: '6px 0' } }, h(InputField, { text: state.text, maxInputLength: 160, beginEditOnSelect: true,
                    promptText: literal(kind === 'area' ? 'Auftrag: "Familienattraktion, max. 15.000 €, Wikingerstil"' : 'Notiz (optional)'),
                    onChange: (e) => this.setState({ text: (e && e.text) || '' }), onCommit: (e) => this.setState({ text: (e && e.text) || '' }) })),
                (kind === 'task' || kind === 'area') && row([h('div', null, 'Zuständig: ' + (state.assignee || 'alle')),
                    buttons([{ label: 'Wechseln', onSelect: nextAssignee }])], 'assignee'),
                kind === 'area' && row([h('div', null, 'Größe: ' + state.radius + ' m Radius'), buttons([10, 20, 40].map((n) =>
                    ({ label: n + ' m', onSelect: () => this.setState({ radius: n }) })))], 'radius'),
                needsPlace && h('div', { style: { color: MUTED, fontSize: '15px', margin: '6px 0' } },
                    'Ort: dein letzter Ping (mittlere Maustaste) - sonst die Bildmitte.'),
                buttons([{ label: 'Hinzufügen', onSelect: add }])),
            h('div', { style: { width: '860px', padding: '0 18px' } },
                section('Brett des Parks', h('span', { style: { color: MUTED, fontSize: '15px', textTransform: 'none' } },
                    'für alle sichtbar, auch als Marker im Park')),
                box(height - 60, items.length === 0
                    ? h('div', { style: { color: MUTED, padding: '8px 0' } }, 'Noch nichts geplant. Links ein Baugebiet, eine Aufgabe, einen Kommentar oder einen Treffpunkt anlegen.')
                    : items.map((item) => row([
                        h('div', { style: { width: '520px', opacity: item.done ? 0.55 : 1 } },
                            h('div', { style: { fontSize: '18px' } }, (item.done ? '✓ ' : '') + item.title + '  ',
                                h('span', { style: { color: MUTED, fontSize: '15px' } }, BOARD_WORD[item.kind] + ' · ' + item.by
                                    + (item.assignee ? ' → ' + item.assignee : ''))),
                            item.text && h('div', { style: { color: INK, fontSize: '15px' } }, item.text)),
                        buttons([
                            item.kind === 'task' && { label: item.done ? 'Wieder offen' : 'Erledigt', onSelect: () => request('board_done', item.id + '|' + (item.done ? '0' : '1')) },
                            item.kind === 'proposal' && { label: (item.myVote === '1' ? '✓ ' : '') + 'Dafür (' + item.yes + ')', onSelect: () => request('board_vote', item.id + '|1') },
                            item.kind === 'proposal' && { label: (item.myVote === '0' ? '✓ ' : '') + 'Dagegen (' + item.no + ')', onSelect: () => request('board_vote', item.id + '|0') },
                            item.x !== false && { label: 'Hinspringen', onSelect: () => request('goto', item.x + '|' + item.z) },
                            { label: 'Löschen', onSelect: () => request('board_del', item.id) },
                        ]),
                    ], item.id)))));
    }

    renderHistory(coop, height) {
        const team = coop.team || {};
        const isHost = coop.role === 'host';
        return h('div', { style: { display: 'flex', height: height + 'px' } },
            h('div', { style: { width: '640px', padding: '0 18px', borderRight: '1px solid rgba(0, 120, 170, 0.18)' } },
                section('Seit deinem letzten Besuch'),
                h('div', { style: { fontSize: '17px', color: team.since ? INK : MUTED } }, team.since || 'Dein erster Besuch in diesem Park - oder es gibt noch nichts zu vergleichen.'),
                section('Meldungen des Parks'),
                list(team.events).length === 0 ? h('div', { style: { color: MUTED } }, 'Gerade keine Pannen oder Probleme.')
                    : list(team.events).slice().reverse().map((e, i) => row([h('div', null, e.label),
                        buttons([{ label: 'Hinspringen', onSelect: () => request('goto', e.x + '|' + e.z) }])], 'e' + i)),
                section('Sicherungspunkte'),
                h('div', { style: { color: MUTED, fontSize: '15px', marginBottom: '6px' } },
                    'Eine Kopie des Parks beim Host. Zurückholen betrifft alle und braucht die Zustimmung aller.'),
                ...list(team.checkpoints).map((c) => row([h('div', null, c.label),
                    isHost && buttons([{ label: 'Zurückholen…', onSelect: () => request('restore', String(c.n)) }])], 'c' + c.n)),
                isHost && buttons([{ label: 'Sicherungspunkt erstellen', onSelect: () => request('checkpoint') }])),
            h('div', { style: { width: '680px', padding: '0 18px' } },
                section('Verlauf der Sitzung'),
                box(height - 60, list(coop.log).length === 0 ? h('div', { style: { color: MUTED } }, 'Noch nichts passiert.')
                    : list(coop.log).slice().reverse().map((line, i) => h('div', { key: 'l' + i, style: { fontSize: '16px',
                        padding: '4px 0', borderBottom: '1px solid rgba(0, 120, 170, 0.1)' } }, shown(line))))));
    }

    renderCompetition(coop) {
        const team = coop.team || {};
        const comp = team.competition;
        const isHost = coop.role === 'host';
        const state = this.state;
        const areaOf = (name) => list(team.board).find((i) => i.kind === 'area' && i.assignee === name && i.x !== false);
        const out = [section('Wettbewerb', h('span', { style: { color: MUTED, fontSize: '15px', textTransform: 'none' } },
            'ein Park, alle sehen dasselbe - die Spielziele des Parks (Szenario, Herausforderung) gelten für alle gemeinsam'))];
        if (!comp) {
            if (!isHost) { out.push(h('div', { style: { color: MUTED } }, 'Gerade kein Wettbewerb. Der Host kann einen starten.')); return out; }
            out.push(h('div', { style: { margin: '6px 0', width: '640px' } }, h(InputField, { text: state.compTopic || '', maxInputLength: 60,
                beginEditOnSelect: true, promptText: literal('Thema ("Wikinger", "Familienbahn bis 20.000 €")'),
                onChange: (e) => this.setState({ compTopic: (e && e.text) || '' }), onCommit: (e) => this.setState({ compTopic: (e && e.text) || '' }) })));
            const topic = String(state.compTopic || '').split('|').join(' ');
            out.push(row([h('div', { style: { width: '420px' } }, 'Bauduell: jeder baut in seinem Baugebiet (Planen: Baugebiet mit Zuständigem), danach bewertet ihr Gestaltung und Technik getrennt'),
                buttons([15, 30, 60].map((m) => ({ label: m + ' Min.', onSelect: () => request('comp_start', 'duel|' + m + '|' + topic) })))], 'duel'));
            out.push(row([h('div', { style: { width: '420px' } }, 'Koop gegen die Uhr: gemeinsam die Aufgaben vom Brett schaffen'),
                buttons([15, 30, 60].map((m) => ({ label: m + ' Min.', onSelect: () => request('comp_start', 'timer|' + m + '|' + topic) })))], 'timer'));
            return out;
        }
        const clock = (s) => Math.floor(s / 60) + ':' + (s % 60 < 10 ? '0' : '') + (s % 60);
        out.push(h('div', { style: { fontSize: '18px', margin: '4px 0 8px' } }, comp.label + (comp.topic ? ' · Thema: ' + comp.topic : '') + ' · '
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
                out.push(row([h('div', { style: { width: '200px' } }, e.name),
                    area ? buttons([{ label: 'Hinspringen', onSelect: () => request('goto', area.x + '|' + area.z) }]) : h('div', { style: { width: '120px' } }),
                    h('div', null, 'Gestaltung'), buttons([1, 2, 3, 4, 5].map((n) => ({ label: (chosen.d === n ? '● ' : '') + n, onSelect: () => set('d', n) }))),
                    h('div', null, 'Technik'), buttons([1, 2, 3, 4, 5].map((n) => ({ label: (chosen.t === n ? '● ' : '') + n, onSelect: () => set('t', n) })))], 'r' + e.sid));
            });
        }
        if (comp.phase === 'done' && comp.mode === 'duel') {
            list(comp.results).forEach((r, i) => out.push(row([h('div', { style: { width: '260px' } }, (i + 1) + '. ' + r.name),
                h('div', null, 'Gestaltung ' + r.d.toFixed(1) + ' · Technik ' + r.t.toFixed(1) + ' (' + r.n + (r.n === 1 ? ' Stimme)' : ' Stimmen)'))], 'res' + i)));
        }
        if (isHost) out.push(buttons([{ label: comp.phase === 'build' ? (comp.mode === 'duel' ? 'Zeit beenden, bewerten' : 'Beenden')
            : comp.phase === 'rate' ? 'Bewertung abschließen' : 'Wettbewerb schließen', onSelect: () => request('comp_next') }]));
        return out;
    }

    renderSession(coop, height) {
        const rules = (coop.team && coop.team.rules) || {};
        const isHost = coop.role === 'host';
        return h('div', { style: { padding: '0 18px', height: height + 'px', overflowY: 'auto' } },
            section('Regeln dieser Sitzung', h('span', { style: { color: MUTED, fontSize: '15px', textTransform: 'none' } },
                isHost ? 'du bestimmst sie als Host' : 'nur der Host kann sie ändern')),
            isHost && row([h('div', { style: { width: '420px', color: MUTED } }, 'Schnell wählen'),
                buttons([
                    { label: 'Locker zusammen bauen', onSelect: () => request('rule_preset', 'relaxed') },
                    { label: 'Geordnet', onSelect: () => request('rule_preset', 'ordered') },
                    { label: 'Nur bauen', onSelect: () => request('rule_preset', 'build') },
                ])], 'presets'),
            ...RULES.map(([name, label, options]) => row([h('div', { style: { width: '420px' } }, label),
                isHost ? buttons(options.map(([value, text]) => ({ label: (rules[name] === value ? '● ' : '') + text,
                    onSelect: () => request('rule', name + '|' + value) })))
                    : h('div', { style: { color: BLUE } }, (options.find((o) => o[0] === rules[name]) || ['', '-'])[1])], name)),
            this.renderCompetition(coop),
            section('Deine Rolle'),
            h('div', { style: { fontSize: '16px', color: INK, maxWidth: '1100px' } }, isHost
                ? 'Host: der Park läuft bei dir. Du legst die Regeln fest, erstellst Sicherungspunkte und schlägst vor, zu einem zurückzukehren. '
                  + 'Beitrittsanfragen bestätigst du im Tab Team.'
                : 'Mitspieler: du baust frei mit. Was jemand anderes gerade bearbeitet, ist für dich gesperrt - Mittelklick darauf und "Übernahme anfragen". '
                  + 'Rückgängig betrifft nur deine eigenen Schritte.'),
            section('Abwesenheit'),
            h('div', { style: { fontSize: '16px', color: INK, maxWidth: '1100px' } },
                'Der Park läuft beim Host. Verlässt der Host die Sitzung, endet sie für alle; beim nächsten Mal lädt er den Park und ihr steigt wieder ein. '
                + 'Pausiert der Host, pausiert der Park für alle (je nach Regel "Spieltempo").'),
            section('Beitritt'),
            h('div', { style: { fontSize: '16px', color: INK } },
                'Nur Steam-Freunde des Hosts sehen die Sitzung. Beitrittsanfragen erscheinen im Reiter "Team".'));
    }

    renderPlayers(coop) {
        const players = list(coop.players);
        const requests = coop.role === 'host' ? list(coop.requests) : [];
        const slots = [];
        players.forEach((p) => {
            const content = contentLine(coop, p);
            const canLook = coop.stage === 'park' && coop.context === 'park' && !p.me && p.x !== undefined && p.act !== 'lobby';
            slots.push(h('div', { key: 'p' + p.sid, style: { display: 'flex', alignItems: 'center', padding: '7px 10px', margin: '5px 0',
                borderRadius: '10px', background: '#ffffff', border: '1px solid rgba(0, 120, 170, 0.18)' } },
                h(Avatar, { player: p, size: 40, pic: avatars[p.sid] }),
                h('div', { style: { flexGrow: 1, minWidth: 0, marginLeft: '12px' } },
                    h('div', { style: { display: 'flex', alignItems: 'center', fontSize: '20px', fontWeight: 'bold' } },
                        p.name + (p.me ? ' (du)' : ''),
                        p.host && h(Icon, { src: 'img/icons/crown.svg', style: { width: '16px', height: '16px', marginLeft: '6px' } })),
                    h('div', { style: { color: MUTED, fontSize: '16px' } }, playerActivity(coop, p)),
                    content && h('div', { style: { color: content.warn ? '#c2410c' : '#237a37', fontSize: '15px' } }, content.text),
                    canLook && buttons([
                        { label: 'Hinspringen', onSelect: () => request('jump', p.sid) },
                        { label: coop.following === p.sid ? 'Nicht folgen' : 'Folgen', onSelect: () => request('follow', p.sid) }]))));
        });
        if (coop.role) {
            for (let i = players.length; i < SLOTS; i++) {
                slots.push(h('div', { key: 'e' + i, style: { padding: '12px', margin: '5px 0', borderRadius: '10px', color: MUTED,
                    background: '#e8f0f4', fontSize: '16px' } }, 'Freier Platz'));
            }
        }
        return box(636, [
            requests.length > 0 && section('Möchte beitreten'),
            ...requests.map((r) => row([h('div', null, r.name), buttons([
                { label: 'Zulassen', onSelect: () => request('approve', r.sid) },
                { label: 'Ablehnen', onSelect: () => request('deny', r.sid) }])], 'r' + r.sid)),
            section('Spieler'),
            !coop.role && h('div', { style: { color: MUTED, padding: '6px 0' } },
                coop.context === 'menu' ? 'Noch keine Lobby. "Lobby erstellen" unten - oder rechts der Lobby eines Freundes beitreten.'
                    : 'Noch keine Sitzung. "Diesen Park hosten" teilt ihn mit deinen Freunden.'),
            ...slots]);
    }

    // Host in the main menu: pick a park; everyone sees the pick before it is opened.
    renderChooser(coop, state) {
        const tab = state.tab;
        const tabButton = (key, label, later) => h('div', { key, onClick: later ? undefined : () => this.setState({ tab: key }),
            style: { padding: '6px 14px', marginRight: '6px', borderRadius: '16px', fontSize: '17px',
                background: tab === key ? BLUE : (later ? '#e9eef1' : '#ffffff'), color: tab === key ? '#ffffff' : (later ? '#9fb3bf' : INK),
                border: '1px solid ' + (later ? 'rgba(0, 0, 0, 0.06)' : 'rgba(0, 121, 173, 0.45)') } }, label);
        const picked = (key) => coop.chosen === key;
        const pickStyle = (on) => ({ padding: '8px 12px', margin: '4px 0', borderRadius: '8px', background: on ? '#d6eefa' : '#ffffff',
            border: '1px solid ' + (on ? BLUE : 'rgba(0, 120, 170, 0.18)') });
        let content;
        if (tab === 'save') {
            const parks = list(coop.parks);
            content = box(300, parks.length === 0 ? h('div', { style: { color: MUTED, padding: '8px 0' } }, 'Keine gespeicherten Sandbox-Parks gefunden.')
                : parks.map((park) => h('div', { key: 's' + park.id, onClick: () => request('choose', 'save|' + park.id), style: pickStyle(picked('save:' + park.id)) },
                    h('div', { style: { fontSize: '19px', fontWeight: 'bold' } }, park.name),
                    h('div', { style: { color: MUTED, fontSize: '15px' } }, (BIOMES.find((b) => b[0] === park.world) || [0, park.world || 'Sandbox'])[1]))));
        } else if (tab === 'new') {
            const pickNew = (biome, creative) => request('choose', 'new|' + biome + '|' + (creative ? '1' : '0'));
            const current = (coop.chosen || '').indexOf('new:') === 0 ? coop.chosen.substring(4) : null;
            content = box(300, [
                h('div', { key: 'b', style: { display: 'flex', flexWrap: 'wrap' } }, BIOMES.map(([id, label]) => h('div', { key: id,
                    onClick: () => pickNew(id, state.creative), style: Object.assign(pickStyle(current === id), { width: '222px', margin: '4px 8px 4px 0' }) },
                    h('div', { style: { fontSize: '19px', fontWeight: 'bold' } }, label)))),
                h('div', { key: 'm', style: { display: 'flex', marginTop: '10px' } },
                    [[true, 'Kreativ (Geld unbegrenzt)'], [false, 'Mit Budget']].map(([creative, label]) => h('div', { key: label,
                        onClick: () => { this.setState({ creative }); if (current) pickNew(current, creative); },
                        style: Object.assign(pickStyle(state.creative === creative), { marginRight: '8px', fontSize: '17px' }) }, label)))]);
        } else {
            content = box(300, [
                h('div', { key: 't', style: { color: MUTED, padding: '8px 0' } },
                    'Franchise-Parks wählst du im Franchise-Menü des Spiels. Sobald der Park offen ist, laden ihn alle in der Lobby.'),
                h('div', { key: 'b' }, buttons([{ label: 'Franchise-Menü öffnen', onSelect: () => { request('choose', 'franchise'); openScreen(MODES[1]); } }]))]);
        }
        const choice = coop.choice;
        const canStart = choice && (choice.kind === 'save' || choice.kind === 'new') && !choice.starting;
        return [section('Wo spielen wir?', h('span', { style: { textTransform: 'none', letterSpacing: 0 } },
                tab === 'save' ? h('span', { onClick: () => request('parks'), style: { color: BLUE, fontSize: '15px' } }, 'aktualisieren') : null)),
            h('div', { key: 'tabs', style: { display: 'flex', marginBottom: '8px' } },
                tabButton('save', 'Gespeichert'), tabButton('new', 'Neu'), tabButton('franchise', 'Franchise'),
                tabButton('career', 'Karriere · später', true)),
            content,
            h('div', { key: 'sel', style: { display: 'flex', alignItems: 'center', height: '76px', marginTop: '8px', padding: '0 12px',
                borderRadius: '10px', background: choice ? '#e1f3fb' : '#eef3f6' } },
                h('div', { style: { width: '300px' } },
                    h('div', { style: { color: MUTED, fontSize: '15px' } }, choice ? 'Ausgewählt - sehen alle' : 'Noch nichts ausgewählt'),
                    choice && h('div', { style: { fontSize: '19px', fontWeight: 'bold' } }, choice.title),
                    choice && h('div', { style: { color: MUTED, fontSize: '15px' } }, choice.detail)),
                h('div', { style: { width: '190px' } }, canStart ? buttons([{ label: 'Park öffnen', onSelect: () => request('start') }]) : null))];
    }

    renderPlace(coop, state) {
        if (!coop.role) return box(470, null);
        if (coop.stage === 'lobby') {
            if (coop.canChoose) return box(470, this.renderChooser(coop, state), { overflowY: 'hidden' });
            const choice = coop.choice;
            const host = hostOf(coop);
            return box(470, [section('Wo spielen wir?'),
                h('div', { key: 'c', style: { padding: '14px', borderRadius: '10px', background: choice ? '#e1f3fb' : '#eef3f6' } },
                    choice ? [h('div', { key: 'l', style: { color: MUTED, fontSize: '15px' } }, (host ? host.name : 'Der Host') + ' hat gewählt'),
                        h('div', { key: 't', style: { fontSize: '22px', fontWeight: 'bold' } }, choice.title),
                        h('div', { key: 'd', style: { color: MUTED } }, choice.detail),
                        h('div', { key: 's', style: { marginTop: '8px' } }, choice.starting ? 'Wird geöffnet - der Park lädt gleich bei dir.' : 'Wartet auf den Start durch den Host.')]
                        : h('div', { style: { color: MUTED } }, coop.role === 'host' ? 'Geh ins Hauptmenü, um einen Park zu wählen.'
                            : 'Der Host wählt noch. Sobald der Park offen ist, lädt er bei dir automatisch.'))]);
        }
        const out = [section('Park des Hosts', coop.parkTitle ? h('span', { style: { color: MUTED, textTransform: 'none', letterSpacing: 0 } }, coop.parkTitle) : null)];
        if (coop.park) out.push(h('div', { key: 'n' }, (coop.park.guests || 0).toLocaleString('de-DE') + ' Besucher · ' + money(coop.park)));
        list(coop.stats).forEach((s) => out.push(h('div', { key: 's' + s.name, style: { padding: '2px 0', color: MUTED } },
            s.name + ': ' + s.created + ' platziert, ' + s.edited + ' bearbeitet, ' + s.deleted + ' gelöscht')));
        if (list(coop.log).length) {
            out.push(section('Verlauf'));
            list(coop.log).slice(-7).forEach((line, i) => out.push(h('div', { key: 'l' + i, style: { padding: '2px 0', color: '#4a6b7d' } }, line)));
        }
        return box(470, out);
    }

    renderChat(coop, state) {
        if (!coop.role) return null;
        const chat = list(coop.chat).slice(-30);
        return h('div', { key: 'chat', style: { height: '330px' } },
            section('Chat'),
            h('div', { style: { height: '214px', overflowY: 'auto', padding: '6px 10px', borderRadius: '8px', background: '#ffffff',
                border: '1px solid rgba(0, 120, 170, 0.18)' } },
                chat.length === 0 ? h('div', { style: { color: MUTED, fontSize: '16px' } }, 'Noch keine Nachrichten.')
                    : chat.map((c, i) => h('div', { key: 'c' + i, style: { padding: '2px 0', fontSize: '17px' } },
                        h('span', { style: { color: '#' + (c.color || '20435a'), fontWeight: 'bold' } }, c.name + ': '), c.text))),
            h('div', { style: { marginTop: '8px' } },
                h(InputField, { text: state.draft, promptText: literal('Nachricht an alle ... (Enter sendet)'), maxInputLength: 200,
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
        return h('div', { key: 'content', style: { height: '130px' } },
            section('Inhalte'),
            h('div', { style: { color: uneven.length ? '#c2410c' : '#237a37', fontSize: '17px' } }, text),
            coop.role === 'host' && uneven.length > 0 && buttons([{ label: coop.guard ? 'Alle Inhalte erlauben' : 'Nur gemeinsame Inhalte',
                onSelect: () => request('guard', coop.guard ? '0' : '1') }]));
    }

    renderFriends(coop) {
        if (!coop.available) return null;
        const friends = list(coop.friends).slice(0, 60);
        const inSession = {};
        list(coop.players).forEach((p) => { inSession[p.sid] = true; });
        return h('div', { key: 'friends', style: { height: coop.role ? '306px' : '636px' } },
            section(coop.role ? 'Freunde einladen' : 'Steam-Freunde'),
            h('div', { style: { height: coop.role ? '256px' : '586px', overflowY: 'auto' } },
                friends.length === 0 ? h('div', { style: { color: MUTED } }, 'Lade Freundesliste ...')
                    : friends.map((f) => row([
                        h('div', { style: { width: '230px' } },
                            h('div', { style: { fontSize: '18px' } }, f.name),
                            h('div', { style: { color: f.lobby ? '#237a37' : f.pc2 ? '#2f9e44' : MUTED, fontSize: '15px' } },
                                f.lobby ? 'hat eine offene Lobby' : f.pc2 ? 'spielt Planet Coaster 2' : (FRIEND_STATE[f.state] || ''))),
                        inSession[f.sid] ? h('span', { style: { color: '#237a37', fontSize: '16px' } }, 'ist dabei')
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
            h(VisitorBar, null),
            h(VoteBanner, null),
            h(EmoteWheel, null),
            h(InviteBanner, null),
            h(ContextMenu, null),
            h(CompBanner, null),
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
                    style: { position: 'absolute', right: '12px', bottom: '0px', width: 'auto' } },
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
