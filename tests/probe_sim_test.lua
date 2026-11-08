-- Runs the development hit probe (tools/probe) against a fake UE4SS: it must hook every override in the scene's and the
-- AI's Blueprint chains, log calls with readable parameters, report counts when the battle ends and unhook.
local saved = {print = print}
local globals = {"StaticFindObject", "FindFirstOf", "FindAllOf", "RegisterHook", "UnregisterHook", "ExecuteInGameThread",
    "LoopAsync"}
for _, name in ipairs(globals) do saved[name] = _G[name] end

local logs = {}
print = function(text) logs[#logs + 1] = tostring(text) end

local function obj(fields)
    fields = fields or {}
    fields.IsValid = function() return true end
    return fields
end
local function fname(s) return {type = function() return "FName" end, ToString = function() return s end} end
local function class(full, super)
    return obj({GetFullName = function() return full end, GetSuperStruct = function() return super end})
end
local native_scene = class("Class /Script/EndGame.EndBattleSceneBlueprint")
local btsc_base = class("BlueprintGeneratedClass /Game/BluePrint/BattleScene/Common/btsc_base.btsc_base_C", native_scene)
local native_ai = class("Class /Script/EndGame.EndAIControllerEnemyBase")
local en_base = class("BlueprintGeneratedClass /Game/AI/EN_Base_AIBP.EN_Base_AIBP_C", native_ai)
local mandragora = class("BlueprintGeneratedClass /Game/AI/EN2205_AIBP.EN2205_AIBP_C", en_base)

local world = {in_battle = false}
local enemy = obj({GetController = function() return obj({GetClass = function() return mandragora end}) end,
    GetFullName = function() return "EN2205_C /Game/Level.Level:PersistentLevel.EN2205_01" end})
local battle = obj({
    IsInBattle = function() return world.in_battle end,
    GetEnemyMembersRef = function() return {enemy} end,
    GetActorName = function(_, a) return fname(a == enemy and "EN2205_01" or "Cloud") end,
})
local objects = {
    ["/Script/EndGame.Default__EndBattleAPI"] = battle,
    ["/Script/EndGame.Default__EndPartyAPI"] = obj({GetBattleMemberCount = function() return 0 end}),
    ["/Game/BluePrint/BattleScene/Common/btsc_base.btsc_base_C:OnTakeDamage"] = obj(),
    ["/Game/BluePrint/BattleScene/Common/btsc_base.btsc_base_C:OnIncrementBattleCountPerID"] = obj(),
    ["/Game/AI/EN_Base_AIBP.EN_Base_AIBP_C:OnActionInvoke"] = obj(),
    ["/Game/AI/EN2205_AIBP.EN2205_AIBP_C:OnTakeDamageInvoke"] = obj(),
}
local hooks, unhooked = {}, 0
StaticFindObject = function(path) return objects[path] end
FindFirstOf = function(name)
    if name == "EndPlayerControllerBP_C" then return obj({Pawn = obj()}) end
end
FindAllOf = function(name)
    if name == "EndBattleSceneBlueprint" then
        return {obj({GetClass = function() return btsc_base end,
            GetFullName = function() return "btsc_base_C /Game/Level.Level:PersistentLevel.btsc_base_C_1" end})}
    end
end
RegisterHook = function(path, fn) hooks[path] = fn; return 1, 2 end
UnregisterHook = function() unhooked = unhooked + 1 end
ExecuteInGameThread = function(fn) fn() end
local loop
LoopAsync = function(_, fn) loop = fn end

local ok, err = pcall(function()
    local here = debug.getinfo(1, "S").source
    assert(here, "test source")
    dofile((package.path:match("([^;]*)[\\/]ue4ss[\\/]BattleMeters[\\/]Scripts[\\/]%?%.lua")) ..
        "/tools/probe/BattleMetersHitProbe/Scripts/main.lua")
    local function logged(pattern)
        for _, line in ipairs(logs) do if line:find(pattern, 1, true) then return line end end
    end
    loop()
    world.in_battle = true
    loop()
    for _, path in ipairs({"btsc_base_C:OnTakeDamage", "btsc_base_C:OnIncrementBattleCountPerID",
            "EN_Base_AIBP_C:OnActionInvoke", "EN2205_AIBP_C:OnTakeDamageInvoke"}) do
        assert(logged("hooked /Game/") and logged(path), "hooked " .. path)
    end
    assert(logged("scene class chain: /Game/BluePrint/BattleScene/Common/btsc_base.btsc_base_C <- /Script/EndGame.EndBattleSceneBlueprint"))
    assert(logged("enemy EN2205_01 = EN2205_C"))
    local function param(v) return {get = function() return v end} end
    local fire = hooks["/Game/BluePrint/BattleScene/Common/btsc_base.btsc_base_C:OnTakeDamage"]
    for _ = 1, 6 do fire(param(obj()), param(312), param(fname("Cloud")), param(fname("EN2205_01")), param(false)) end
    assert(logged("#1: ") and logged("| 312 | Cloud | EN2205_01 | false"), "parameters readable")
    assert(not logged("#5: "), "only the first calls in full")
    loop()   -- looking again doesn't hook twice
    world.in_battle = false
    loop()
    assert(logged("     6  /Game/BluePrint/BattleScene/Common/btsc_base.btsc_base_C:OnTakeDamage"), "count at the end")
    assert(logged("     0  /Game/AI/EN_Base_AIBP.EN_Base_AIBP_C:OnActionInvoke"))
    assert(unhooked == 4, "all unhooked, got " .. unhooked)
end)

print = saved.print
for _, name in ipairs(globals) do _G[name] = saved[name] end
if not ok then
    for _, line in ipairs(logs) do print("  log: " .. line) end
    error(err)
end
print("probe_sim_test: ok")
