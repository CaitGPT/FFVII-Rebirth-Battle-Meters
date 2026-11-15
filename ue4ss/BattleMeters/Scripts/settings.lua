-- Which meter the key has switched to, kept in a small text file. Pure Lua: no game calls, so it can be tested outside
-- the game (see tests/settings_test.lua).
--
-- Each layout (config.layout) has its own cycle. The compact one: off, then each meter compact and full, then all
-- three as a grid and as a stack.
local M = {}

local CYCLES = {
    classic = {"off", "dps", "hps", "dtps"},
    compact = {"off", "dps_compact", "dps_full", "hps_compact", "hps_full", "dtps_compact", "dtps_full", "grid", "stack"},
}
-- A meter saved by the other layout opens as its nearest match here, so switching layouts keeps it on.
local CARRY = {
    classic = {dps_compact = "dps", dps_full = "dps", hps_compact = "hps", hps_full = "hps", dtps_compact = "dtps",
        dtps_full = "dtps", grid = "dps", stack = "dps"},
    compact = {dps = "dps_full", hps = "hps_full", dtps = "dtps_full"},
}

local function cycle_of(layout)
    return CYCLES[layout] and layout or "classic"
end

local function index_of(layout, mode)
    for i, m in ipairs(CYCLES[layout]) do
        if m == mode then return i end
    end
    return nil
end

-- The meter after this one; past the last, off. Anything unknown goes to the first meter.
function M.next(mode, layout)
    layout = cycle_of(layout)
    local cycle = CYCLES[layout]
    local i = index_of(layout, mode)
    if not i then return cycle[2] end
    return cycle[i % #cycle + 1]
end

-- One line like "meter=hps". Anything else in the file is ignored; an unknown meter means off.
function M.parse(text, layout)
    layout = cycle_of(layout)
    local mode = tostring(text or ""):match("meter%s*=%s*([%w_]+)")
    if mode and index_of(layout, mode) then return mode end
    if mode and CARRY[layout][mode] then return CARRY[layout][mode] end
    return "off"
end

function M.serialize(mode)
    return "meter=" .. mode .. "\n"
end

function M.load(path, layout)
    local file = io.open(path, "r")
    if not file then return M.parse(nil, layout) end
    local text = file:read("a")
    file:close()
    return M.parse(text, layout)
end

function M.save(path, mode)
    local file = io.open(path, "w")
    if not file then return false end
    file:write(M.serialize(mode))
    file:close()
    return true
end

return M
