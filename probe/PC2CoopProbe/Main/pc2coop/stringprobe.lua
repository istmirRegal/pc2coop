-- Fixed-value return tests only. Incoming strings are never executed as code.
local global = _G
local Probe = {}
function Probe.Run(emit)
    local path = ".\\Win64\\ovldata\\PC2CoopProbe\\PC2CoopDiagnostic.dll"
    local greeting = global.package.loadlib(path, "pc2_probe_greeting")
    local empty = global.package.loadlib(path, "pc2_probe_empty")
    local binary = global.package.loadlib(path, "pc2_probe_binary")
    if global.type(greeting) ~= "function" or global.type(empty) ~= "function"
        or global.type(binary) ~= "function" then
        emit("native-return:exports-unavailable"); return false
    end
    local first = greeting()
    if first ~= "PC2Coop native return OK" then
        emit("native-return:profile-or-state-rejected; type=" .. global.type(first)); return false
    end
    if empty() ~= "" or binary() ~= "Grüße\0PC2" then
        emit("native-return:binary-mismatch"); return false
    end
    local retained = {}
    for i=1,256 do
        retained[i] = binary()
        if retained[i] ~= "Grüße\0PC2" then emit("native-return:repeat-mismatch"); return false end
    end
    local gc = "unavailable"
    if global.type(global.collectgarbage) == "function" then
        local ok = global.pcall(global.collectgarbage, "collect")
        gc = ok and "completed" or "rejected"
    end
    for i=1,#retained do
        if retained[i] ~= "Grüße\0PC2" then emit("native-return:retention-mismatch"); return false end
    end
    emit("native-return:passed; greeting=1; empty=1; UTF8-NUL=1; retained=256; GC=" .. gc)
    return true
end
return Probe
