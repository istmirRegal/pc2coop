-- Original MIT code. One table shared by every instance of the mod's Lua modules.
-- Hooks installed from the database run in a different module context than the park
-- manager, and the main menu does not cache required modules; the engine's api table is
-- common to all of them, so the shared state hangs there (rawset: a plain assignment to
-- api.ui2 is refused).
local global = _G
local holder = global.api.ui2
local shared = global.rawget(holder, "__pc2coopShared")
if global.type(shared) ~= "table" then
    shared = {}
    global.rawset(holder, "__pc2coopShared", shared)
end
return shared
