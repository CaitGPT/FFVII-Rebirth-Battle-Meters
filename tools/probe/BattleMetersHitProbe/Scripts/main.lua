-- Battle Meters hit probe: a development-only UE4SS mod, never shipped. It answers, in one live fight, which of the
-- game's Blueprint callbacks run per hit and with what names (issue 1). It changes nothing in the game.
--
-- When a battle starts it logs every battle-scene actor and its class chain, then hooks each candidate callback on
-- every Blueprint class in the scene's, the enemies' AI and the party's AI class chains that has its own override.
-- It logs the first calls of each with their parameters, and a count per callback when the battle ends.
-- Controls: enemy AI events such as OnActionInvoke run often, so if they count up, Blueprint hooks work here.
local TAG = "[BattleMetersHitProbe] "
local BATTLE_API = "/Script/EndGame.Default__EndBattleAPI"
local PARTY_API = "/Script/EndGame.Default__EndPartyAPI"
local SHOW_CALLS = 4        -- calls logged in full per callback
local MAX_DEPTH = 16

local SCENE_FUNCTIONS = {"OnTakeDamage", "OnIncrementBattleCountPerID", "OnCharaPartsDamage", "OnBPMessageFromAIBP",
    "OnCharaSyncAction", "OnMotionMessage", "OnAddStatusChangeID", "OnEndCombinationAbility"}
local AI_FUNCTIONS = {"OnTakeDamageInvoke", "OnTakeDamageHPFirstInvoke", "OnTakeDamageOverTime", "OnGiveDamageInvoke",
    "OnTakeAbilityInvoke", "OnReactionSensingInvoke", "OnUseAbility", "OnUseAbilityInvoke", "OnCreateDamageSource",
    "OnIncrementBattleCountPerID", "OnKilledInvoke", "OnActionInvoke", "OnProwlInvoke", "OnMotionMessageInvoke",
    "OnAITimerInvoke", "OnDead"}

local function log(message) print(TAG .. message .. "\n") end
local function safe(f, ...)
    local ok, value = pcall(f, ...)
    if ok then return value end
    return nil
end
local function valid(object)
    return object ~= nil and safe(function() return object:IsValid() end) == true
end
local function full_name(object)
    return safe(function() return object:GetFullName() end) or "?"
end
local function path_of(object)
    local full = safe(function() return object:GetFullName() end)
    return type(full) == "string" and full:match("^%S+%s+(%S+)$") or nil
end

-- Only methods each UE4SS type is known to have are called: asking for a missing member breaks the Lua state.
local function describe(value)
    local kind = type(value)
    if kind == "number" or kind == "boolean" or kind == "string" or kind == "nil" then return tostring(value) end
    if kind ~= "userdata" and kind ~= "table" then return kind end
    -- UE4SS values are userdata with a type() method; a plain table (a struct such as FVector) has none.
    local utype = safe(function() return value:type() end) or kind
    if type(utype) ~= "string" then utype = kind end
    if utype == "FName" or utype == "FString" or utype == "FText" then
        return safe(function() return value:ToString() end) or utype
    end
    if utype == "UObject" or utype == "AActor" or utype == "UClass" or utype == "UStruct" or utype == "UFunction" then
        return safe(function() return value:GetFName():ToString() end) or utype
    end
    return utype
end

local hooks = {}   -- function path -> {pre, post, calls}
local function hook(function_path)
    if hooks[function_path] then return end
    local entry = {calls = 0}
    local ok, pre, post = pcall(RegisterHook, function_path, function(context, ...)
        entry.calls = entry.calls + 1
        if entry.calls <= SHOW_CALLS then
            local parts = {describe(safe(function() return context:get() end))}
            for i = 1, select("#", ...) do
                local param = select(i, ...)
                parts[#parts + 1] = describe(safe(function() return param:get() end))
            end
            log(string.format("call %s #%d: %s", function_path, entry.calls, table.concat(parts, " | ")))
        end
    end)
    if ok then
        entry.pre, entry.post = pre, post
        hooks[function_path] = entry
        log("hooked " .. function_path)
    else
        log("hook failed " .. function_path .. ": " .. tostring(pre))
    end
end

-- Every Blueprint class in the chain with its own override of a listed function.
local function hook_chain(class, functions, label)
    local chain, current = {}, class
    for _ = 1, MAX_DEPTH do
        if not valid(current) then break end
        local path = path_of(current)
        if not path then break end
        chain[#chain + 1] = path
        if path:sub(1, 8) == "/Script/" then break end
        for _, name in ipairs(functions) do
            local function_path = path .. ":" .. name
            if valid(safe(StaticFindObject, function_path)) then hook(function_path) end
        end
        current = safe(function() return current:GetSuperStruct() end)
    end
    log(label .. " class chain: " .. table.concat(chain, " <- "))
end

local probed_classes = {}
local function probe_class(class, functions, label)
    local key = path_of(class) or "?"
    if probed_classes[key] then return end
    probed_classes[key] = true
    hook_chain(class, functions, label)
end

local function controller_class(actor)
    local controller = safe(function() return actor:GetController() end)
    return valid(controller) and safe(function() return controller:GetClass() end) or nil
end

local function probe_battle(battle)
    for _, scene in ipairs(safe(FindAllOf, "EndBattleSceneBlueprint") or {}) do
        if valid(scene) then
            log("scene actor " .. full_name(scene))
            local class = safe(function() return scene:GetClass() end)
            if class then probe_class(class, SCENE_FUNCTIONS, "scene") end
        end
    end
    local out = {}
    local list = safe(function() return battle:GetEnemyMembersRef(out) end)
    local enemies = {}
    local function add(item)
        local actor = item
        if type(item) == "userdata" then
            local kind = safe(function() return item:type() end)
            if kind == "RemoteUnrealParam" or kind == "LocalUnrealParam" then actor = safe(function() return item:get() end) end
        end
        if valid(actor) then enemies[#enemies + 1] = actor end
    end
    local value = list ~= nil and list or out
    if type(value) == "table" then
        if #value == 1 and type(value[1]) == "userdata" and safe(function() return value[1]:type() end) == "TArray" then
            safe(function() value[1]:ForEach(function(_, e) add(e) end) end)
        else
            for _, item in ipairs(value) do add(item) end
        end
    elseif type(value) == "userdata" then
        safe(function() value:ForEach(function(_, e) add(e) end) end)
    end
    for _, enemy in ipairs(enemies) do
        local name = safe(function() return battle:GetActorName(enemy):ToString() end) or "?"
        log("enemy " .. name .. " = " .. full_name(enemy))
        local class = controller_class(enemy)
        if class then probe_class(class, AI_FUNCTIONS, "enemy AI " .. name) end
    end
    local party = safe(StaticFindObject, PARTY_API)
    local count = valid(party) and safe(function() return party:GetBattleMemberCount() end) or 0
    for i = 0, math.min(count or 0, 8) - 1 do
        local member = safe(function() return party:GetBattleMember(i) end)
        if valid(member) then
            local name = safe(function() return battle:GetActorName(member):ToString() end) or "?"
            local class = controller_class(member)
            log("party " .. name .. " controller class " .. (class and full_name(class) or "none"))
            if class then probe_class(class, AI_FUNCTIONS, "party AI " .. name) end
        end
    end
end

local function report_and_unhook()
    local lines = {}
    for function_path, entry in pairs(hooks) do lines[#lines + 1] = string.format("%6d  %s", entry.calls, function_path) end
    table.sort(lines)
    log("battle over; calls per hooked callback:")
    for _, line in ipairs(lines) do log(line) end
    for function_path, entry in pairs(hooks) do pcall(UnregisterHook, function_path, entry.pre, entry.post) end
    hooks, probed_classes = {}, {}
end

local in_battle, probes, armed = false, 0, false
local function tick()
    -- Battle functions only after a save has loaded: calling them from the title screen has crashed this game.
    if not armed then
        local controller = safe(FindFirstOf, "EndPlayerControllerBP_C")
        armed = valid(controller) and valid(safe(function() return controller.Pawn end))
        if not armed then return end
    end
    local battle = safe(StaticFindObject, BATTLE_API)
    if not valid(battle) then return end
    local now = safe(function() return battle:IsInBattle() end) == true
    if now and not in_battle then
        in_battle, probes = true, 0
        log("battle started")
    elseif not now and in_battle then
        in_battle = false
        report_and_unhook()
    end
    -- Enemies and the scene can appear a moment late, and reinforcements later still: look a few times.
    if in_battle and probes < 5 then
        probes = probes + 1
        probe_battle(battle)
    end
end

pcall(ExecuteInGameThread, function() end)
LoopAsync(1000, function()
    ExecuteInGameThread(function()
        local ok, err = pcall(tick)
        if not ok then log("tick error: " .. tostring(err)) end
    end)
    return false
end)
log("loaded")
