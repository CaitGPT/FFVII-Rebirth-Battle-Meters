-- Runs the real main.lua in the compact layout against fake game objects, as main_sim_test.lua does for the classic
-- one. It checks the wiring only: rows keep the party's slot order for the whole battle, the key names the view it
-- switched to for a moment, empty meters stay hidden, and Off flashes its name and hides while the fight keeps counting.
local saved = {print = print, time = os.time, loaded = {}}
for _, name in ipairs({"config", "settings", "overlay", "main"}) do saved.loaded[name] = package.loaded[name] end
local globals = {"StaticFindObject", "FindFirstOf", "ExecuteInGameThread", "LoopAsync", "RegisterKeyBind", "Key",
    "ModifierKey", "FName", "FText", "BattleMetersNativeHit", "BattleMetersNativeStatus"}
for _, name in ipairs(globals) do saved[name] = _G[name] end

local logs = {}
print = function(text) logs[#logs + 1] = tostring(text) end
local clock = 5000
os.time = function() return clock end
local game_time = 0

local next_address = 0x9000
local function obj(fields)
    next_address = next_address + 0x10
    local address = next_address
    fields = fields or {}
    fields.IsValid = function() return true end
    fields.GetAddress = function() return address end
    return fields
end
local function fname(s) return {ToString = function() return s end} end

local cfg = {}
for k, v in pairs(require("config")) do cfg[k] = v end
cfg.write_json, cfg.debug, cfg.layout = false, false, "compact"
package.loaded.config = cfg
-- The real cycle, without touching settings.txt.
local Settings = require("settings")
package.loaded.settings = {load = function() return "dps_full" end, save = function() end, next = Settings.next}
local shown, hidden
package.loaded.overlay = {show = function(view) shown, hidden = view, false end, hide = function() hidden = true end}

local world = {in_battle = false, enemies = {}, party = {}, hp = {}, max = {}}
local function actor(actor_name, hp)
    local a = obj({GetFName = function() return fname(actor_name .. "_Object") end})
    a.actor_name = actor_name
    a.GetController = function() return obj({IsA = function() return false end}) end
    world.hp[a], world.max[a] = hp, hp
    return a
end
local battle = obj({
    IsInBattle = function() world.ticks = (world.ticks or 0) + 1; return world.in_battle end,
    GetEnemyMembersRef = function() return world.enemies end,
    GetCharaHP = function(_, a) return world.hp[a] end,
    GetHPMax = function(_, a) return world.max[a] end,
    GetActorName = function(_, a) return fname(a.actor_name) end,
    GetCharaID = function() return fname("None") end,
})
local party_api = obj({
    GetBattleMemberCount = function() return #world.party end,
    GetBattleMember = function(_, i) return world.party[i + 1].actor end,
    GetBattleMemberType = function(_, i) return world.party[i + 1].kind end,
})
local pawn = obj({GetClass = function() return {GetFName = function() return fname("PC0002_Tifa_C") end} end})
local statics = obj({
    GetPlayerPawn = function() return pawn end,
    GetTimeSeconds = function() return game_time end,
    IsGamePaused = function() return false end,
})
local objects = {
    ["/Script/EndGame.Default__EndBattleAPI"] = battle,
    ["/Script/EndGame.Default__EndPartyAPI"] = party_api,
    ["/Script/EndGame.Default__EndMenuBPAPI"] = obj({BPGetPlayerMP = function() return 50 end}),
    ["/Script/Engine.Default__GameplayStatics"] = statics,
    ["/Script/EndGame.EndAIControllerEnemyBase"] = obj(),
}
StaticFindObject = function(path) return objects[path] end
FindFirstOf = function(name) if name == "GameEngine" then return obj({GameViewport = obj()}) end end
ExecuteInGameThread = function(fn) fn() end
local loop, key_pressed
LoopAsync = function(_, fn) loop = fn end
RegisterKeyBind = function(_, _, fn) key_pressed = fn end
local queue = {}
BattleMetersNativeHit = function()
    local h = table.remove(queue, 1)
    if h then return h[1], h[2], h[3], h[4] end
end
BattleMetersNativeStatus = function() return "ok", 0, 0 end
Key, ModifierKey = {D = 68}, {CONTROL = 1, SHIFT = 2}
FName = fname
FText = function(s) return s end

local function texts_of(view)
    local out = {}
    for i, t in ipairs(view and view.texts or {}) do out[t.text] = out[t.text] or i end
    return out
end

local ok, err = pcall(function()
    package.loaded.main = nil
    require("main")
    local function tick()
        local before = world.ticks or 0
        for _ = 1, 10 do
            loop()
            if (world.ticks or 0) > before then return end
        end
        error("no tick ran")
    end
    local function hit(damage, causer, target) queue[#queue + 1] = {damage, causer, target, false} end

    -- Out of combat, before any battle: each press still shows where it went, empty, then the panel goes.
    tick()
    assert(not shown, "nothing on screen before the first press")
    key_pressed(); tick()
    local t = texts_of(shown)
    assert(t["HPS · Compact"] and not hidden, "out of combat, no data: the press is named")
    local names = {}
    for _ = 1, 8 do
        key_pressed(); tick()
        t = texts_of(shown)
        for name in pairs(t) do if name:find(" · ") or name == "Off" then names[#names + 1] = name end end
    end
    assert(table.concat(names, ", ") == "HPS · Full, DTPS · Compact, DTPS · Full, All · Grid, All · Stack, Off, " ..
        "DPS · Compact, DPS · Full", table.concat(names, ", "))
    clock = clock + 3
    tick()
    assert(hidden, "no data: hidden once the name has gone")
    shown = nil

    -- Tifa is in the first slot, Cloud in the second.
    local tifa, cloud = actor("PC0002_Tifa_Battle", 1800), actor("PC0000_Cloud_Battle", 2000)
    local a = actor("EN2001_03_A", 5000)
    world.party = {{actor = tifa, kind = 2}, {actor = cloud, kind = 0}}
    world.enemies, world.in_battle = {a}, true
    tick()
    assert(hidden ~= false and not shown, "nothing counted yet: no panel")

    -- Cloud out-damages Tifa; the rows keep the slot order anyway.
    hit(900, "PC0000_Cloud_Battle", "EN2001_03_A")
    hit(100, "PC0002_Tifa_Battle", "EN2001_03_A")
    world.hp[a] = 4000
    game_time = 1
    tick()
    local t = texts_of(shown)
    assert(shown and shown.compact and t["DAMAGE"], "DPS full shows once there's damage")
    assert(t["Tifa"] and t["Cloud"] and t["Tifa"] < t["Cloud"], "slot order, not ranking")
    assert(not t["HEALING"], "single meter")

    -- The game lists Cloud first now (say, you took control of him): the rows don't move.
    world.party = {{actor = cloud, kind = 0}, {actor = tifa, kind = 2}}
    hit(500, "PC0000_Cloud_Battle", "EN2001_03_A")
    world.hp[a] = 3500
    game_time = 2
    tick()
    t = texts_of(shown)
    assert(t["Tifa"] < t["Cloud"], "order fixed for the battle")

    -- The key: two presses to the grid's neighbour... one press to HPS compact, named for a moment.
    key_pressed()
    tick()
    t = texts_of(shown)
    assert(t["HPS · Compact"], "named after the key press")
    clock = clock + 3
    game_time = 3
    tick()
    assert(hidden, "HPS has nothing yet: hidden once the name has gone")

    -- On to the grid: no healing yet, so no HEAL column.
    for _ = 1, 4 do key_pressed(); tick() end
    t = texts_of(shown)
    assert(t["All · Grid"] and t["DMG"] and not t["HEAL"], "grid named, without a HEAL column")
    clock = clock + 3
    game_time = 4
    tick()
    t = texts_of(shown)
    assert(not t["All · Grid"] and t["DMG"] and t["Tifa"] < t["Cloud"], "grid back to its time, same order")

    -- Past the stack to off: "Off" for a moment, then hidden, while the fight keeps counting.
    key_pressed(); tick()
    key_pressed(); tick()
    t = texts_of(shown)
    assert(t["Off"] and not hidden, "Off flashes its name")
    clock = clock + 3
    hit(500, "PC0002_Tifa_Battle", "EN2001_03_A")
    world.hp[a] = 3000
    game_time = 5
    tick()
    assert(hidden, "then the panel goes")
    key_pressed(); tick()   -- DPS compact: the fight's numbers are all there
    clock = clock + 3
    tick()
    t = texts_of(shown)
    assert(t["2.0k"] and t["1,400"] and t["600"] and t["Tifa"] < t["Cloud"], "still counted while off: " .. tostring(shown and #shown.texts))
end)

print, os.time = saved.print, saved.time
for _, name in ipairs(globals) do _G[name] = saved[name] end
package.loaded.config, package.loaded.settings, package.loaded.overlay, package.loaded.main =
    saved.loaded.config, saved.loaded.settings, saved.loaded.overlay, nil
if not ok then
    for _, line in ipairs(logs) do print("  log: " .. line) end
    error(err)
end
