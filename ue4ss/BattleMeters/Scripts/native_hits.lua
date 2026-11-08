-- The game's hit events, from Battle Meters Native (the optional C++ mod in ue4ss/BattleMetersNative). Called on the
-- game thread.
--
-- A Lua hook on the battle scene's OnTakeDamage never fires in this game's UE4SS, but the C++ mod sees every call and
-- queues Damage, CauserCharaName, DamagedCharaName and bHeal. It registers two functions into this mod's Lua state
-- before main.lua runs: BattleMetersNativeHit() hands over the oldest hit, and BattleMetersNativeStatus() says whether
-- it's hooked. Without the C++ mod neither exists, and the panel keeps to the totals.
local M = {}

local MAX_PER_TICK = 512   -- the queue holds 2048; a tick sees a few dozen at most

local function present()
    return type(BattleMetersNativeHit) == "function" and type(BattleMetersNativeStatus) == "function"
end

-- "ok" once the C++ mod is hooked, otherwise why not; plus hits it dropped since the last call and hits since load.
function M.status()
    if not present() then return "not installed", 0, 0 end
    local ok, text, dropped, total = pcall(BattleMetersNativeStatus)
    if not ok then return "status failed: " .. tostring(text), 0, 0 end
    return tostring(text), tonumber(dropped) or 0, tonumber(total) or 0
end

function M.available()
    return present() and M.status() == "ok"
end

-- Hits since the last call, oldest first: {damage, causer, target, heal}.
function M.drain()
    local out = {}
    if not present() then return out end
    for _ = 1, MAX_PER_TICK do
        local ok, damage, causer, target, heal = pcall(BattleMetersNativeHit)
        if not ok or damage == nil then break end
        out[#out + 1] = {damage = damage, causer = causer, target = target, heal = heal == true}
    end
    return out
end

-- Hits from before this battle (field events, the last fight's tail) are thrown away.
function M.discard()
    for _ = 1, 8 do
        if #M.drain() < MAX_PER_TICK then break end
    end
    M.status()
end

return M
