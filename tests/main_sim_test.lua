-- Runs the real main.lua against fake game objects, a fake UE4SS and a fake Battle Meters Native, through a battle with
-- hit events and one without. It checks the wiring only: that hits reach the damage and healing splits, and that each
-- split adds up to the exact total. Whether the game really sends these events is for a live test.
local saved = {print = print, time = os.time, loaded = {}}
for _, name in ipairs({"config", "settings", "overlay", "main"}) do saved.loaded[name] = package.loaded[name] end
local globals = {"StaticFindObject", "FindFirstOf", "ExecuteInGameThread", "LoopAsync", "RegisterKeyBind", "Key",
    "ModifierKey", "FName", "FText", "BattleMetersNativeHit", "BattleMetersNativeStatus"}
for _, name in ipairs(globals) do saved[name] = _G[name] end

local logs = {}
print = function(text) logs[#logs + 1] = tostring(text) end
local clock = 1000
os.time = function() return clock end
local game_time = 0

-- Fake objects.
local next_address = 0x1000
local function obj(fields)
    next_address = next_address + 0x10
    local address = next_address
    fields = fields or {}
    fields.IsValid = function() return true end
    fields.GetAddress = function() return address end
    return fields
end
local function fname(s) return {ToString = function() return s end} end
local function named(s, fields)
    fields = obj(fields)
    fields.GetFName = function() return fname(s) end
    return fields
end

local cfg = {}
for k, v in pairs(require("config")) do cfg[k] = v end
cfg.write_json, cfg.debug = false, false
package.loaded.config = cfg
local next_mode = "dps"
package.loaded.settings = {load = function() return "dps" end, save = function() end,
    next = function() return next_mode end}
local shown
package.loaded.overlay = {show = function(view) shown = view end, hide = function() end}

local world = {in_battle = false, enemies = {}, party = {}, hp = {}, max = {}}
local function actor(actor_name, hp)
    local a = named(actor_name .. "_Object")
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
    GetCharaID = function(_, a) return fname(a.chara_id or "None") end,
})
local party_api = obj({
    GetBattleMemberCount = function() return #world.party end,
    GetBattleMember = function(_, i) return world.party[i + 1].actor end,
    GetBattleMemberType = function(_, i) return world.party[i + 1].kind end,
})
local pawn = obj({GetClass = function() return {GetFName = function() return fname("PC0000_Cloud_C") end} end})
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

-- Battle Meters Native, as it registers itself into this mod's Lua state: a queue of hits and a status.
local queue = {}
BattleMetersNativeHit = function()
    local h = table.remove(queue, 1)
    if h then return h[1], h[2], h[3], h[4] end
end
BattleMetersNativeStatus = function() return "ok", 0, 0 end
Key, ModifierKey = {D = 68}, {CONTROL = 1, SHIFT = 2}
FName = fname
FText = function(s) return s end

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
    -- One OnTakeDamage call, as Battle Meters Native queues it.
    local function hit(damage, causer, target, heal) queue[#queue + 1] = {damage, causer, target, heal == true} end
    local function logged(pattern)
        for _, line in ipairs(logs) do if line:find(pattern) then return line end end
        return nil
    end

    -- Battle 1: field scene with hit events.
    local cloud, tifa = actor("PC0000_Cloud_Battle", 2000), actor("PC0002_Tifa_Battle", 1800)
    local a, b = actor("EN2001_03_A", 1000), actor("EN2001_03_B", 500)
    world.party = {{actor = cloud, kind = 0}, {actor = tifa, kind = 2}}
    world.enemies = {a, b}
    hit(5000, "PC0000_Cloud_Battle", "EN0000_Field")   -- from before the battle: thrown away
    world.in_battle = true
    tick()
    assert(logged("hit events: Battle Meters Native is hooked"), "native hooked, said so")
    assert(#queue == 0, "stale hits discarded")
    assert(logged("party member Cloud: actor PC0000_Cloud_Battle"), "party names logged for the live test")

    -- Cloud hits A for 300, Tifa hits B for 200, A hits Cloud for 50 (doesn't count).
    hit(300, "PC0000_Cloud_Battle", "EN2001_03_A")
    hit(200, "PC0002_Tifa_Battle", "EN2001_03_B")
    hit(50, "EN2001_03_A", "PC0000_Cloud_Battle")
    world.hp[a], world.hp[b], world.hp[cloud] = 700, 300, 1950
    game_time = 0.2
    tick()

    -- Cloud's 999 kills B, which had 300 left. Tifa hits A for 250, and poison takes 50 more.
    hit(999, "PC0000_Cloud_Battle", "EN2001_03_B")
    hit(250, "PC0002_Tifa_Battle", "EN2001_03_A")
    world.enemies = {a}
    world.hp[a] = 400
    game_time = 0.4
    tick()

    -- Tifa heals Cloud with a 999 Cure; he was only 50 down, so 50 is hers. Regen gives Tifa 30 with no event.
    hit(999, "PC0002_Tifa_Battle", "PC0000_Cloud_Battle", true)
    world.hp[cloud], world.hp[tifa] = 2000, 1800
    world.hp[tifa] = 1770
    game_time = 0.5
    tick()
    world.hp[tifa] = 1800
    game_time = 0.55
    tick()

    -- Cloud finishes A (400 left, under half HP) and the battle ends in the same moment.
    hit(400, "PC0000_Cloud_Battle", "EN2001_03_A")
    world.enemies, world.in_battle = {}, false
    game_time = 0.6
    tick()
    -- Two seconds later the battle is over and the final numbers linger.
    clock = clock + 3
    tick()
    local d = shown
    assert(d and d.title == "DPS" and d.show_line, "DPS has a line")
    local rows = {}
    for _, stat in ipairs(d.stats) do rows[stat[1]] = stat[2] end
    assert(rows.Total == "1,500", "total is still the exact HP lost: " .. tostring(rows.Total))
    assert(rows.Cloud == "1,000" and rows.Tifa == "450" and rows.Unattributed == "50",
        string.format("split %s / %s / %s", tostring(rows.Cloud), tostring(rows.Tifa), tostring(rows.Unattributed)))
    assert(logged("damage by character: split %[Cloud 1000, Tifa 450, Unattributed 50%]; hits matched 5"),
        "battle-end report")
    assert(logged("healing by character: split %[Tifa 50, Unattributed 30%]; hits matched 1"), "healing report")

    -- The key steps to HPS: a row per healer after the six usual lines.
    next_mode = "hps"
    key_pressed()
    tick()
    local hps = shown
    assert(hps and hps.title == "HPS" and hps.show_line, "HPS has a line")
    rows = {}
    for _, stat in ipairs(hps.stats) do rows[stat[1]] = stat[2] end
    assert(#hps.stats == 8 and rows.Total == "80" and rows.Tifa == "50" and rows.Unattributed == "30",
        "HPS rows: " .. #hps.stats .. " " .. tostring(rows.Tifa))
    next_mode = "dps"
    key_pressed()

    -- Battle 2: Battle Meters Native isn't installed. Totals only, and healing keeps its split by who received it.
    BattleMetersNativeHit, BattleMetersNativeStatus = nil, nil
    local c = actor("EN0001_VR", 800)
    world.enemies, world.in_battle = {c}, true
    shown = nil
    clock = clock + 1
    tick()
    assert(logged("Battle Meters Native not installed, so damage and healing show totals only"), "said so")
    hit(300, "PC0000_Cloud_Battle", "EN0001_VR")
    world.hp[c] = 500
    game_time = 5
    tick()
    assert(shown and shown.show_line == false and #shown.stats == 4, "total only")
end)

-- Put the real globals and modules back for the other tests.
print, os.time = saved.print, saved.time
for _, name in ipairs(globals) do _G[name] = saved[name] end
for name, value in pairs(saved.loaded) do package.loaded[name] = value end
package.loaded.config, package.loaded.settings, package.loaded.overlay, package.loaded.main =
    saved.loaded.config, saved.loaded.settings, saved.loaded.overlay, nil
if not ok then
    for _, line in ipairs(logs) do print("  log: " .. line) end
    error(err)
end
print("main_sim_test: ok")
