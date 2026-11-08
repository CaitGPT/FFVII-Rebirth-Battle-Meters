-- What the on-screen meter shows, as a plain table. Pure Lua: no game calls, so it can be tested outside the
-- game (see tests/meter_view_test.lua). overlay.lua draws the result.
local M = {}

local METERS = {
    dps = {kind = "damage", title = "DPS", biggest = "Biggest hit"},
    hps = {kind = "heal", title = "HPS", biggest = "Biggest heal"},
    dtps = {kind = "taken", title = "DTPS", biggest = "Biggest hit taken"},
}

-- Each character's colour on the line, in party order, so a colour stays where it is as the shares change.
local CHARACTERS = {
    {name = "Cloud", color = {R = 1.00, G = 0.85, B = 0.10, A = 1}},      -- yellow
    {name = "Barret", color = {R = 0.10, G = 0.65, B = 0.20, A = 1}},     -- green
    {name = "Tifa", color = {R = 0, G = 0, B = 0, A = 1}},                -- black
    {name = "Aerith", color = {R = 1.00, G = 0.45, B = 0.72, A = 1}},     -- pink
    {name = "Red XIII", color = {R = 0.85, G = 0.08, B = 0.08, A = 1}},   -- red
    {name = "Yuffie", color = {R = 0.10, G = 0.35, B = 1.00, A = 1}},     -- blue
    {name = "Cait Sith", color = {R = 1, G = 1, B = 1, A = 1}},           -- white
    {name = "Zack", color = {R = 0.40, G = 0.95, B = 1.00, A = 1}},       -- cyan
    {name = "Sephiroth", color = {R = 0.60, G = 0.30, B = 0.90, A = 1}},  -- purple
    {name = "Vincent", color = {R = 0.45, G = 0.05, B = 0.15, A = 1}},    -- dark red
    {name = "Cid", color = {R = 1.00, G = 0.55, B = 0.10, A = 1}},        -- orange
}
local OTHER = {R = 0.55, G = 0.60, B = 0.65, A = 1}
local UNATTRIBUTED = "Unattributed"   -- attribution.lua's name for damage no hit event explained

function M.format_number(value)
    local text = tostring(math.floor((value or 0) + 0.5))
    local grouped = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (grouped:gsub("^,", ""))
end

function M.format_time(seconds)
    local whole = math.floor(seconds or 0)
    return string.format("%d:%02d", math.floor(whole / 60), whole % 60)
end

-- The line: one section per character with a share of the total. Shares add up to 1. Damage dealt has a line only when the
-- game's hit events said who dealt it (see attribution.lua); what they didn't explain is the grey Unattributed section,
-- last. Healing is split by who did it when the hit events said so, otherwise by who received it. Damage taken is split
-- by who took it.
local function segments_of(k)
    local out = {}
    if k.total <= 0 then return out end
    local known = {}
    for _, character in ipairs(CHARACTERS) do
        known[character.name] = true
        local amount = k.by_source[character.name]
        if amount and amount > 0 then
            out[#out + 1] = {name = character.name, share = amount / k.total, color = character.color}
        end
    end
    local others = {}
    for name in pairs(k.by_source) do
        if not known[name] and name ~= UNATTRIBUTED then others[#others + 1] = name end
    end
    table.sort(others)
    if (k.by_source[UNATTRIBUTED] or 0) > 0 then others[#others + 1] = UNATTRIBUTED end
    for _, name in ipairs(others) do
        out[#out + 1] = {name = name, share = k.by_source[name] / k.total, color = OTHER}
    end
    return out
end

-- Nil when the meter is off.
function M.build(snapshot, mode, config)
    local meter = METERS[mode]
    if not meter then return nil end
    local k = snapshot.kinds[meter.kind]
    local stats = {{string.format("Last %d seconds", config.rolling_window_seconds), M.format_number(k.recent)},
        {"Total", M.format_number(k.total)}, {meter.biggest, M.format_number(k.biggest)}}
    if mode == "hps" then
        local mp = snapshot.kinds.mp and snapshot.kinds.mp.total or 0
        stats[#stats + 1] = {"MP spent", M.format_number(mp)}
        stats[#stats + 1] = {"Healing per MP", mp > 0 and M.format_number(k.total / mp) or "-"}
    end
    stats[#stats + 1] = {"Time", M.format_time(snapshot.elapsed)}
    local show_line = meter.kind ~= "damage" or k.attributed == true
    local segments = show_line and segments_of(k) or {}
    -- Each character also gets a row, in the line's order, so each total can be read: damage and healing by who did it
    -- (only with the game's hit events), and damage taken by who took it (always; it comes straight from their HP).
    if meter.kind == "taken" or ((meter.kind == "damage" or meter.kind == "heal") and k.attributed == true) then
        for _, segment in ipairs(segments) do
            stats[#stats + 1] = {segment.name, M.format_number(k.by_source[segment.name])}
        end
    end
    return {title = meter.title, value = M.format_number(k.average), stats = stats, show_line = show_line,
        segments = segments}
end

return M
