// Original MIT code (PC2 Co-op). Multiplayer layer inside the game's own HUD/FrontEnd
// views, using the game's components so it looks and feels native:
//   - player bar (top right), toasts (join/leave/chat), lobby window (members, Steam
//     friends with invite buttons, chat), "Multiplayer" entry in the pause menu.
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

let stateListener;
function subscribe() {
    if (stateListener !== undefined) return;
    try {
        stateListener = DS.getPropertyListener(CONTEXT, 'state', applyState);
        log('subscribed to state');
    } catch (error) {
        stateListener = undefined;
    }
}

function poll() {
    subscribe();
    try { applyState(DS.getValue(CONTEXT, 'state')); } catch (error) { /* context not created yet */ }
}

class StateComponent extends preact.Component {
    componentDidMount() {
        this._listener = (state) => this.setState({ coop: state });
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

// Small round player chips, always visible while in a session.
class PlayerBar extends StateComponent {
    render(props, state) {
        const coop = state.coop || {};
        if (!coop.role || !coop.players || coop.players.length === 0) return null;
        return preact.h('div', { style: { position: 'absolute', top: '84px', right: '24px', display: 'flex', flexDirection: 'column',
            alignItems: 'flex-end' } },
            coop.players.map((p) => preact.h('div', { key: p.sid, style: { display: 'flex', alignItems: 'center', margin: '3px 0',
                padding: '4px 12px 4px 4px', borderRadius: '20px', background: 'rgba(14, 33, 48, 0.72)' } },
                preact.h('div', { style: { width: '30px', height: '30px', borderRadius: '15px', background: '#' + p.color,
                    color: '#ffffff', fontSize: '17px', lineHeight: '30px', textAlign: 'center', marginRight: '9px' } },
                    (p.name || '?').substring(0, 1).toUpperCase()),
                preact.h('div', { style: { color: '#ffffff', fontSize: '16px' } },
                    p.name + (p.me ? ' (du)' : '')),
                p.host && preact.h(Icon, { src: 'img/icons/crown.svg', style: { width: '18px', height: '18px', marginLeft: '7px' } }),
                preact.h('div', { style: { color: '#9fd8f0', fontSize: '13px', marginLeft: '9px' } }, activityText(p.act, p.hold)))));
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
        return preact.h('div', { style: { position: 'absolute', bottom: '120px', left: '24px', display: 'flex', flexDirection: 'column' } },
            state.visible.map((t) => preact.h('div', { key: t.id, style: { margin: '4px 0', padding: '10px 16px', maxWidth: '520px',
                borderRadius: '10px', background: 'rgba(14, 33, 48, 0.82)', color: '#ffffff', fontSize: '17px',
                borderLeft: '5px solid #' + (t.color || '00c6ff') } }, t.loc ? shown(t.text) : t.text)));
    }
}

const FRIEND_STATE = ['offline', 'online', 'beschäftigt', 'abwesend', 'abwesend', 'online', 'online'];

class Lobby extends StateComponent {
    state = { chatPrompt: false };
    close = () => request('close');
    render(props, state) {
        const coop = state.coop || {};
        if (!coop.open) return null;
        if (state.chatPrompt) {
            return preact.h(InputfieldPrompt, { title: literal('Chat'), description: literal('Nachricht an alle im Park'),
                commitButtonLabel: literal('Senden'), defaultInputText: literal(''), maxInput: 200,
                onCancel: () => this.setState({ chatPrompt: false }),
                onCloseAndCommit: (text) => { this.setState({ chatPrompt: false }); if (text) request('chat', text); } });
        }
        const buttons = [];
        if (!coop.available) {
            // Nothing to do without Steam.
        } else if (!coop.role) {
            buttons.push({ label: literal(coop.canHost ? 'Raum hosten' : 'Park laden, dann hosten'), onSelect: () => request('host'),
                disabled: !coop.canHost });
        } else {
            if (coop.desync && coop.role === 'client') buttons.push({ label: literal('Neu synchronisieren'), onSelect: () => request('resync') });
            buttons.push({ label: literal('Steam-Overlay'), onSelect: () => request('invite_overlay') });
            buttons.push({ label: literal('Nachricht'), onSelect: () => this.setState({ chatPrompt: true }) });
            buttons.push({ label: literal(coop.role === 'host' ? 'Sitzung beenden' : 'Verlassen'), onSelect: () => request('leave') });
        }
        buttons.push({ label: literal('Schließen'), onSelect: this.close, inputName: 'UI_Cancel' });
        const join = coop.join || {};
        const status = !coop.available ? 'Steam ist nicht verfügbar.'
            : join.phase === 'failed' ? join.reason
            : join.phase && join.phase !== 'live' ? joinText(join)
            : !coop.role && !coop.canHost ? 'Nimm eine Steam-Einladung an, um direkt beizutreten. Zum Hosten zuerst einen Park laden.'
            : !coop.role ? 'Hoste deinen Park und lade Freunde über Steam ein. Sie bekommen deinen Park automatisch.'
            : coop.desync ? 'Nicht mehr synchron: ' + coop.desync + (coop.role === 'client' ? ' - "Neu synchronisieren" lädt den Park des Hosts erneut.' : '')
            : coop.role === 'host' ? 'Du bist Host' + (coop.franchise ? ' - Franchise-Park: Speichern lädt den gemeinsamen Stand hoch.' : '.')
            : 'Im Park von ' + (join.host || 'Host') + '.';
        const section = (title) => preact.h('div', { style: { color: '#00a0d8', fontSize: '17px', margin: '14px 0 6px' } }, title);
        const row = (children, key) => preact.h('div', { key, style: { display: 'flex', alignItems: 'center', justifyContent: 'space-between',
            padding: '5px 0', borderBottom: '1px solid rgba(0, 120, 170, 0.18)' } }, children);
        const friends = (coop.friends || []).slice(0, 30);
        const inSession = {};
        (coop.players || []).forEach((p) => { inSession[p.sid] = true; });
        return preact.h(Dialog, { modifiers: 'dialogApp', title: literal('Multiplayer'), description: literal(status), buttons },
            preact.h('div', { style: { width: '760px', maxHeight: '560px', overflowY: 'auto', textAlign: 'left', color: '#20435a',
                fontSize: '16px' } },
                coop.role === 'host' && (coop.requests || []).length > 0 && section('Möchte beitreten'),
                coop.role === 'host' && (coop.requests || []).map((r) => row([
                    preact.h('div', null, r.name),
                    preact.h('div', { style: { display: 'flex' } },
                        preact.h(Button, { label: literal('Zulassen'), onSelect: () => request('approve', r.sid) }),
                        preact.h(Button, { label: literal('Ablehnen'), onSelect: () => request('deny', r.sid) })),
                ], 'r' + r.sid)),
                coop.role && section('Im Park'),
                coop.role && (coop.players || []).map((p) => row([
                    preact.h('div', { style: { display: 'flex', alignItems: 'center' } },
                        preact.h('div', { style: { width: '14px', height: '14px', borderRadius: '7px', background: '#' + p.color, marginRight: '8px' } }),
                        p.name + (p.me ? ' (du)' : '') + (p.host ? ' - Host' : ''),
                        preact.h('span', { style: { color: '#6a8899', marginLeft: '10px' } }, activityText(p.act, p.hold))),
                    !p.me && p.x !== undefined ? preact.h(Button, { label: literal('Hinspringen'), onSelect: () => request('jump', p.sid) }) : null,
                ], 'p' + p.sid)),
                coop.role && coop.park && section('Park des Hosts'),
                coop.role && coop.park && preact.h('div', null, (coop.park.guests || 0).toLocaleString('de-DE') + ' Besucher · ' + money(coop.park)),
                coop.role && (coop.stats || []).length > 0 && section('Wer hat was gebaut'),
                coop.role && (coop.stats || []).map((s) => preact.h('div', { key: 's' + s.name, style: { padding: '2px 0' } },
                    s.name + ': ' + s.created + ' platziert, ' + s.edited + ' bearbeitet, ' + s.deleted + ' gelöscht')),
                coop.role && (coop.log || []).length > 0 && section('Verlauf'),
                coop.role && (coop.log || []).slice(-6).map((line, i) => preact.h('div', { key: 'l' + i, style: { padding: '2px 0', color: '#4a6b7d' } }, line)),
                coop.role && (coop.chat || []).length > 0 && section('Chat'),
                (coop.chat || []).slice(-8).map((c, i) => preact.h('div', { key: 'c' + i, style: { padding: '2px 0' } },
                    preact.h('span', { style: { color: '#' + (c.color || '20435a') } }, c.name + ': '), c.text)),
                coop.available && section('Steam-Freunde'),
                coop.available && friends.length === 0 && preact.h('div', null, 'Lade Freundesliste ...'),
                friends.map((f) => row([
                    preact.h('div', null, f.name,
                        preact.h('span', { style: { color: f.pc2 ? '#00a65a' : '#6a8899', marginLeft: '10px' } },
                            f.pc2 ? 'spielt Planet Coaster 2' : (FRIEND_STATE[f.state] || ''))),
                    !coop.role ? null
                        : inSession[f.sid] ? preact.h('span', { style: { color: '#00a65a' } }, 'ist dabei')
                        : preact.h(Button, { label: literal(f.invited ? 'Eingeladen' : 'Einladen'), disabled: f.invited,
                            onSelect: () => request('invite', f.sid) }),
                ], 'f' + f.sid))));
    }
}

function joinText(join) {
    const host = join.host ? ' von ' + join.host : '';
    if (join.phase === 'joining') return 'Trete der Sitzung bei ...';
    if (join.phase === 'asking') return 'Warte auf die Zustimmung' + host + ' ...';
    if (join.phase === 'confirm') return 'Beitritt' + (join.host ? ' bei ' + join.host : '') + ' wartet auf deine Bestätigung.';
    if (join.phase === 'awaiting') return 'Empfange den Park' + host + ' ... ' + Math.round((join.progress || 0) * 100) + ' %';
    if (join.phase === 'loading') return 'Lade den Park' + host + ' ...';
    return 'Verbunden' + host + '.';
}

// Card in the screen centre while a join is in progress (menu or park).
class JoinProgress extends StateComponent {
    render(props, state) {
        const coop = state.coop || {};
        const join = coop.join;
        if (!join || !join.phase || join.phase === 'live' || join.phase === 'failed' || join.phase === 'confirm' || coop.open) return null;
        const share = join.phase === 'awaiting' ? (join.progress || 0) : join.phase === 'loading' ? 1 : 0.02;
        return preact.h('div', { style: { position: 'absolute', left: '50%', top: '42%', width: '520px', marginLeft: '-260px',
            padding: '22px 28px', borderRadius: '14px', background: 'rgba(14, 33, 48, 0.9)', color: '#ffffff', textAlign: 'center' } },
            preact.h('div', { style: { fontSize: '22px', marginBottom: '6px' } }, 'Multiplayer'),
            preact.h('div', { style: { fontSize: '17px', color: '#9fd8f0', marginBottom: '14px' } }, joinText(join)),
            preact.h('div', { style: { height: '8px', borderRadius: '4px', background: 'rgba(255, 255, 255, 0.15)' } },
                preact.h('div', { style: { height: '8px', borderRadius: '4px', background: '#00c6ff', width: Math.round(share * 100) + '%' } })));
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
        return preact.h('div', { style: { position: 'absolute', top: 0, left: 0, width: '100%', height: '100%', pointerEvents: 'none' } },
            preact.h(PlayerBar, null),
            preact.h(Toasts, null),
            preact.h(JoinProgress, null),
            preact.h('div', { style: { pointerEvents: 'auto' } }, preact.h(Lobby, null)),
            preact.h('div', { style: { pointerEvents: 'auto' } }, preact.h(JoinFailed, null)),
            preact.h('div', { style: { pointerEvents: 'auto' } }, preact.h(JoinConfirm, null)));
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
                const description = literal('Mit Steam-Freunden live im selben Park bauen. Einladung annehmen oder einen Park laden und hosten.');
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
    else patchMainMenu().catch((e) => log('main menu import ' + e));
    const root = document.createElement('div');
    root.id = 'PC2Coop_root';
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
