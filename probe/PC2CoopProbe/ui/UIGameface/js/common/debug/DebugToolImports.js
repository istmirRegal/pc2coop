// Original MIT code (PC2 Co-op). Compatible implementation of the debug-tool registry
// interface used by the game's apps. Behaves like the stock module (debug tools load in
// development players only) and additionally starts the PC2 Co-op layer in HUD/FrontEnd.
import * as Engine from '/js/common/core/Engine.js';

// Diagnostics for the co-op layer: Lua copies ['pc2coop'].jslog into the mod log.
function coopLog(message) {
    try {
        Engine.sendEvent('PC2Coop_Log', String(message).substring(0, 300));
    } catch (error) {
        console.log('PC2Coop: ' + message);
    }
}

// The co-op name tags are drawn by the game's coaster label view (it imports this module).
// Tags of the mod start with a bullet and get a quieter look than the game's own heat-map
// labels, which stay as they are. Inline styles only: the label elements are re-used.
if (String(window.location.href).indexOf('CoasterLabels.html') >= 0) {
    const QUIET = { color: '#ffffff', backgroundColor: 'rgba(14, 33, 48, 0.6)', fontSize: '0.8em', lineHeight: '1.25rem',
        paddingLeft: '0.5rem', paddingRight: '0.5rem', borderTopLeftRadius: '0.65rem', borderTopRightRadius: '0.65rem',
        borderBottomLeftRadius: '0.65rem', borderBottomRightRadius: '0.65rem' };
    setInterval(() => {
        try {
            const items = document.querySelectorAll('.CoasterLabelItem_root');
            for (let i = 0; i < items.length; i++) {
                const item = items[i];
                const mine = (item.textContent || '').charAt(0) === '\u2022';
                if (mine === (item.__pc2coop === true)) continue;
                item.__pc2coop = mine;
                for (const key in QUIET) item.style[key] = mine ? QUIET[key] : '';
            }
        } catch (error) { /* labels keep the game's look */ }
    }, 250);
}

export async function loadDebugDefaultTools() {
    try {
        await import('/js/common/debug/DivInspector.js');
        await import('/js/common/debug/DebugInputPlayer.js');
        await import('/js/common/debug/RenderVisualiser.js');
        await import('/js/common/debug/DebugMemoryViewer.js');
        await import('/js/common/debug/DebugActionsViewer.js');
        if (Engine.isCoherentPlayer()) {
            await import('/js/common/debug/DebugControlContextViewer.js');
        }
    } catch (error) {
        console.log('PC2Coop: debug tools unavailable: ' + error);
    }
    try {
        coopLog('loading layer in ' + window.location.href);
        const layer = await import('/js/pc2coop/CoopLayer.js');
        layer.start(coopLog);
    } catch (error) {
        coopLog('layer failed: ' + error + ' ' + (error && error.stack));
    }
}

export let debugActionByName = {};
export function registerDebugAction(name, callback, defaultArgs, valueLabel, canAddExtraArgs) {
    if (debugActionByName[name] != undefined) {
        throw (new Error('registerDebugAction: callback with name ' + name + ' already exists.'));
    }
    debugActionByName[name] = { callback, defaultArgs: defaultArgs || [], valueLabel, canAddExtraArgs };
}
export function callDebugAction(name) {
    const action = debugActionByName[name];
    action.callback(...action.defaultArgs);
}
export function unregisterDebugAction(name) {
    delete debugActionByName[name];
}
export let debugSliderByName = {};
export function registerDebugSlider(name, onChange, onGetLabel, onGetValue, step, min, max) {
    if (debugSliderByName[name] != undefined) {
        throw (new Error('registerDebugSlider: slider with name ' + name + ' already exists.'));
    }
    debugSliderByName[name] = { onChange, onGetLabel, onGetValue, step, min, max };
}
export function unregisterDebugSlider(name) {
    delete debugSliderByName[name];
}
