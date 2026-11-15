-- The compact layouts: what goes where, as plain rectangles and text boxes. Pure Lua: no game calls, so it can be tested
-- outside the game (see tests/compact_view_test.lua). overlay.lua draws the result, and tools/preview/render.py draws
-- the same thing as a web page to check a change without starting the game.
--
-- Ctrl+Shift+D steps through these (see settings.lua):
--   dps_compact, hps_compact, dtps_compact  one meter: its stats on the header line, then a bar per character
--   dps_full, hps_full, dtps_full           one meter: a bar per character, then its stats listed underneath
--   grid                                    all three meters side by side: a row per character, the stats underneath
--   stack                                   all three meters, one under the other, each like the compact view
--
-- A bar's length is that character's share of the meter's total. Positions are in 1920x1080 units from the panel's top
-- left, already multiplied by config.scale.
local M = {}

local LABEL = {R = 0.68, G = 0.84, B = 0.95, A = 1}
local WHITE = {R = 1, G = 1, B = 1, A = 1}
local DIM = {R = 0.62, G = 0.70, B = 0.76, A = 1}
local BACK = {R = 0.25, G = 0.33, B = 0.42, A = 0.45}
local RULE = {R = 0.68, G = 0.84, B = 0.95, A = 0.25}
local LEFT, CENTER, RIGHT = 0, 1, 2   -- ETextJustify
M.colors = {label = LABEL, white = WHITE, dim = DIM, back = BACK, rule = RULE}

-- Bar colours, in party order: the classic line's, made see-through so the name on top stays readable. Tifa is tan
-- rather than black, which wouldn't show on the dark panel.
local FILL_ALPHA = 0.6
local CHARACTERS = {
    {"Cloud", 1.00, 0.85, 0.10}, {"Barret", 0.10, 0.65, 0.20}, {"Tifa", 0.72, 0.50, 0.32},
    {"Aerith", 1.00, 0.45, 0.72}, {"Red XIII", 0.85, 0.08, 0.08}, {"Yuffie", 0.10, 0.35, 1.00},
    {"Cait Sith", 1, 1, 1}, {"Zack", 0.40, 0.95, 1.00}, {"Sephiroth", 0.60, 0.30, 0.90},
    {"Vincent", 0.45, 0.05, 0.15}, {"Cid", 1.00, 0.55, 0.10},
}
local ORDER, FILL = {}, {}
for i, c in ipairs(CHARACTERS) do
    ORDER[c[1]] = i
    FILL[c[1]] = {R = c[2], G = c[3], B = c[4], A = FILL_ALPHA}   -- made once: overlay.lua skips unchanged colours by identity
end
local OTHER = {R = 0.55, G = 0.60, B = 0.65, A = FILL_ALPHA}
local UNATTRIBUTED = "Unattributed"   -- attribution.lua's name for damage no hit event explained

local KINDS = {
    {key = "damage", title = "DAMAGE", short = "DMG"},
    {key = "heal", title = "HEALING", short = "HEAL"},
    {key = "taken", title = "TAKEN", short = "TAKEN"},
}
local SINGLE = {
    dps_compact = {KINDS[1], "compact"}, dps_full = {KINDS[1], "full"},
    hps_compact = {KINDS[2], "compact"}, hps_full = {KINDS[2], "full"},
    dtps_compact = {KINDS[3], "compact"}, dtps_full = {KINDS[3], "full"},
}
-- Shown in the header for a moment after Ctrl+Shift+D, so you know where you are in the cycle.
M.NAMES = {
    off = "Off", dps_compact = "DPS · Compact", dps_full = "DPS · Full", hps_compact = "HPS · Compact",
    hps_full = "HPS · Full", dtps_compact = "DTPS · Compact", dtps_full = "DTPS · Full", grid = "All · Grid",
    stack = "All · Stack",
}

-- Sizes at scale 1.
local PAD, TOP, BOTTOM = 12, 8, 8
local HEAD = 24                -- header line
local ROW, BAR = 25, 22        -- bar rows: pitch and height
local STAT = 20                -- stat rows
local WIDTH = 320              -- single meters and the stack
local NAME_COL, COL, GAP = 100, 90, 4   -- the grid
local PCT_W = 40
local FONT = {title = 12, head = 12, name = 13, value = 13, pct = 11, stat = 12}
-- The header's numbers sit right-aligned in fixed slots, since text can't be measured: rate, total, biggest, time.
local SLOT = {rate = 66, total = 56, biggest = 84, time = 44}

function M.format_number(value)
    local text = tostring(math.floor((value or 0) + 0.5))
    local grouped = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (grouped:gsub("^,", ""))
end

-- 950, 3.0k, 87.1k, 951k, 1.2M: for the header line and the grid's narrow columns.
function M.format_short(value)
    value = math.floor((value or 0) + 0.5)
    if value < 1000 then return tostring(value) end
    if value < 99950 then return string.format("%.1fk", value / 1000) end
    if value < 999500 then return string.format("%dk", math.floor(value / 1000 + 0.5)) end
    return string.format("%.1fM", value / 1000000)
end

function M.format_time(seconds)
    local whole = math.floor(seconds or 0)
    return string.format("%d:%02d", math.floor(whole / 60), whole % 60)
end

local function fill_of(name)
    return FILL[name] or OTHER
end

local EMPTY = {average = 0, recent = 0, total = 0, biggest = 0, by_source = {}}
local function kind_of(snapshot, key)
    return snapshot.kinds[key] or EMPTY
end

-- Damage and healing split by who did it only when the game's hit events said so (see attribution.lua); damage taken is
-- always split by who took it. Nil when this meter has no split to show: then it shows its totals, never a guess.
local function split_of(key, k)
    if not k.by_source then return nil end
    if key == "taken" or k.attributed == true then return k.by_source end
    return nil
end

-- The party's own order (snapshot.party_order: battle slots, fixed for the battle by main.lua), then anyone else in the
-- usual character order, Unattributed last. Rows keep their place as the numbers change.
function M.party_order(names, party)
    local slot = {}
    for i, name in ipairs(party or {}) do slot[name] = i end
    local function rank(name)
        if name == UNATTRIBUTED then return 10000 end
        return slot[name] or 100 + (ORDER[name] or 100)
    end
    local list = {}
    for name in pairs(names) do list[#list + 1] = name end
    table.sort(list, function(a, b)
        if rank(a) ~= rank(b) then return rank(a) < rank(b) end
        return a < b
    end)
    return list
end

-- A row per character with something to show, in party order, with its share of the total.
function M.rows(by_source, total, party)
    local names = {}
    for name, amount in pairs(by_source) do
        if amount > 0 then names[name] = true end
    end
    local out = {}
    for _, name in ipairs(M.party_order(names, party)) do
        local amount = by_source[name]
        out[#out + 1] = {name = name, amount = amount, share = total > 0 and math.min(amount / total, 1) or 0}
    end
    return out
end

-- Collects what to draw in unscaled units, and scales it on the way out.
local function canvas()
    local c = {rects = {}, texts = {}}
    function c.rect(x, y, w, h, color)
        if w >= 0.5 and h > 0 then c.rects[#c.rects + 1] = {x = x, y = y, w = w, h = h, color = color} end
    end
    function c.text(x, y, w, h, text, size, color, justify)
        c.texts[#c.texts + 1] = {x = x, y = y, w = w, h = h, text = text, size = size, color = color, justify = justify or LEFT}
    end
    function c.finish(width, height, scale)
        local s = tonumber(scale) or 1
        if s <= 0 then s = 1 end
        local function r(v) return math.floor(v * s + 0.5) end
        for _, item in ipairs(c.rects) do
            item.x, item.y, item.w, item.h = r(item.x), r(item.y), math.max(1, r(item.w)), math.max(1, r(item.h))
        end
        for _, item in ipairs(c.texts) do
            item.x, item.y, item.w, item.h = r(item.x), r(item.y), r(item.w), r(item.h)
            item.size = math.max(6, r(item.size))
        end
        return {compact = true, width = r(width), height = r(height), rects = c.rects, texts = c.texts}
    end
    return c
end

-- One bar: the back, the coloured share, then the name, amount and percent on top.
local function bar_row(c, x, y, w, row)
    c.rect(x, y, w, BAR, BACK)
    c.rect(x, y, w * row.share, BAR, fill_of(row.name))
    c.text(x + 6, y + 1, w - PCT_W - 80, BAR, row.name, FONT.name, WHITE)
    c.text(x, y + 1, w - PCT_W - 2, BAR, M.format_number(row.amount), FONT.value, WHITE, RIGHT)
    c.text(x + w - PCT_W, y + 2, PCT_W - 4, BAR, string.format("%d%%", math.floor(row.share * 100 + 0.5)), FONT.pct, DIM, RIGHT)
end

local function bars(c, x, y, w, key, k, party)
    local split = split_of(key, k)
    if split and k.total > 0 then
        for _, row in ipairs(M.rows(split, k.total, party)) do
            bar_row(c, x, y, w, row)
            y = y + ROW
        end
    end
    return y
end

-- The compact header: the meter's name on the left; per second, total, biggest and (on its own) time on the right.
local function compact_header(c, x, y, w, k, time_text, title)
    c.text(x, y + 2, 120, HEAD, title, FONT.title, LABEL)
    local right = x + w
    if time_text then
        c.text(right - SLOT.time, y + 1, SLOT.time, HEAD, time_text, FONT.head, WHITE, RIGHT)
        right = right - SLOT.time
    end
    c.text(right - SLOT.biggest, y + 1, SLOT.biggest, HEAD, "max " .. M.format_number(k.biggest), FONT.head, DIM, RIGHT)
    right = right - SLOT.biggest
    c.text(right - SLOT.total, y + 1, SLOT.total, HEAD, M.format_short(k.total), FONT.head, DIM, RIGHT)
    right = right - SLOT.total
    c.text(right - SLOT.rate, y, SLOT.rate, HEAD, M.format_number(k.average) .. "/s", FONT.head, WHITE, RIGHT)
end

local function has_data(k)
    return (k.total or 0) > 0
end

-- The meters with something counted yet. With none, all of them when the panel must show (just after a key press),
-- otherwise none, and the panel stays hidden.
local function kinds_with_data(snapshot, announce)
    local list = {}
    for _, kind in ipairs(KINDS) do
        if has_data(kind_of(snapshot, kind.key)) then list[#list + 1] = kind end
    end
    if #list == 0 and announce then return KINDS end
    return list
end

local function single(snapshot, kind, style, config, announce, name)
    local k = kind_of(snapshot, kind.key)
    if not has_data(k) and not announce then return nil end
    local c = canvas()
    local x, w = PAD, WIDTH - PAD * 2
    local party = snapshot.party_order
    local time_text = M.format_time(snapshot.elapsed)
    local y = TOP
    if style == "compact" then
        if name then
            -- Just switched here: the view's name in place of the numbers, which come back a moment later.
            c.text(x, y + 2, w - SLOT.time, HEAD, name, FONT.title, LABEL)
            c.text(x + w - SLOT.time, y + 1, SLOT.time, HEAD, time_text, FONT.head, WHITE, RIGHT)
        else
            compact_header(c, x, y, w, k, time_text, kind.short)
        end
        y = bars(c, x, y + HEAD + 2, w, kind.key, k, party)
        return c.finish(WIDTH, y + BOTTOM - 3, config.scale)
    end

    -- Full: name and time, the bars, a rule, then each stat on its own row.
    c.text(x, y + 2, 200, HEAD, name or kind.title, FONT.title, LABEL)
    c.text(x + w - 80, y + 1, 80, HEAD, time_text, FONT.head, WHITE, RIGHT)
    y = bars(c, x, y + HEAD + 2, w, kind.key, k, party)
    c.rect(x, y + 2, w, 1, RULE)
    y = y + 7
    local rows = {
        {"Total", M.format_number(k.total), WHITE, FONT.stat},
        {"Per sec", M.format_number(k.average), WHITE, FONT.stat},
        {string.format("Last %ds", config.rolling_window_seconds or 5), M.format_number(k.recent), DIM, FONT.stat},
        {"Highest", M.format_number(k.biggest), DIM, FONT.stat},
    }
    if kind.key == "heal" then
        local mp = kind_of(snapshot, "mp").total or 0
        rows[#rows + 1] = {"MP spent", M.format_number(mp), DIM, FONT.stat}
        rows[#rows + 1] = {"Healing per MP", mp > 0 and M.format_number(k.total / mp) or "-", DIM, FONT.stat}
    end
    for _, row in ipairs(rows) do
        c.text(x, y + 1, w * 0.6, STAT, row[1], FONT.stat, DIM)
        c.text(x, y, w, STAT, row[2], row[4], row[3], RIGHT)
        y = y + STAT
    end
    return c.finish(WIDTH, y + BOTTOM, config.scale)
end

-- The meters with something counted, one under the other: no healing section until someone heals.
local function stack(snapshot, config, announce, name)
    local kinds = kinds_with_data(snapshot, announce)
    if #kinds == 0 then return nil end
    local c = canvas()
    local x, w = PAD, WIDTH - PAD * 2
    local y = TOP
    if name then
        c.text(x, y + 2, 200, HEAD, name, FONT.title, LABEL)
    else
        c.text(x, y + 1, 100, HEAD, "Fight", FONT.head, DIM)
    end
    c.text(x + w - 80, y + 1, 80, HEAD, M.format_time(snapshot.elapsed), FONT.head, WHITE, RIGHT)
    y = y + HEAD
    c.rect(x, y, w, 1, RULE)
    y = y + 4
    for _, kind in ipairs(kinds) do
        local k = kind_of(snapshot, kind.key)
        compact_header(c, x, y, w, k, nil, kind.title)
        y = bars(c, x, y + HEAD + 2, w, kind.key, k, snapshot.party_order) + 4
    end
    return c.finish(WIDTH, y + BOTTOM - 4, config.scale)
end

-- The meters with something counted, side by side: no healing column until someone heals.
local function grid(snapshot, config, announce, name)
    local kinds = kinds_with_data(snapshot, announce)
    if #kinds == 0 then return nil end
    local c = canvas()
    local width = PAD * 2 + NAME_COL + COL * #kinds + GAP * (#kinds - 1)
    local function col_x(i) return PAD + NAME_COL + (i - 1) * (COL + GAP) end
    local y = TOP
    -- Time in the top left corner, each meter's name over its column.
    if name then
        c.text(PAD, y + 2, NAME_COL, HEAD, name, FONT.title, LABEL)
    else
        c.text(PAD, y + 1, NAME_COL, HEAD, M.format_time(snapshot.elapsed), FONT.head, WHITE)
    end
    for i, kind in ipairs(kinds) do c.text(col_x(i), y + 2, COL, HEAD, kind.short, FONT.title, LABEL, CENTER) end
    y = y + HEAD

    local splits, names = {}, {}
    for i, kind in ipairs(kinds) do
        splits[i] = split_of(kind.key, kind_of(snapshot, kind.key))
        for name, amount in pairs(splits[i] or {}) do
            if amount > 0 then names[name] = true end
        end
    end
    local any = false
    for _, name in ipairs(M.party_order(names, snapshot.party_order)) do
        any = true
        c.text(PAD, y + 1, NAME_COL - 4, BAR, name, FONT.name, WHITE)
        for i, kind in ipairs(kinds) do
            local k, x = kind_of(snapshot, kind.key), col_x(i)
            c.rect(x, y, COL, BAR, BACK)
            if splits[i] then
                local amount = splits[i][name] or 0
                if amount > 0 and k.total > 0 then
                    c.rect(x, y, COL * math.min(amount / k.total, 1), BAR, fill_of(name))
                    c.text(x, y + 1, COL - 5, BAR, M.format_short(amount), FONT.value, WHITE, RIGHT)
                end
            else
                c.text(x, y + 1, COL - 5, BAR, "-", FONT.value, DIM, RIGHT)
            end
        end
        y = y + ROW
    end

    -- The stats, under the characters, each in its meter's column.
    if any then
        c.rect(PAD, y + 1, width - PAD * 2, 1, RULE)
        y = y + 6
    end
    local rows = {
        {"Total", "total", M.format_short, WHITE, FONT.stat},
        {"Per sec", "average", M.format_number, WHITE, FONT.stat},
        {string.format("Last %ds", config.rolling_window_seconds or 5), "recent", M.format_number, DIM, FONT.stat},
        {"Highest", "biggest", M.format_number, DIM, FONT.stat},
    }
    for _, row in ipairs(rows) do
        c.text(PAD, y + 1, NAME_COL, STAT, row[1], FONT.stat, DIM)
        for i, kind in ipairs(kinds) do
            c.text(col_x(i), y, COL - 5, STAT, row[3](kind_of(snapshot, kind.key)[row[2]]), row[5], row[4], RIGHT)
        end
        y = y + STAT
    end
    return c.finish(width, y + BOTTOM, config.scale)
end

-- Just the name: what "Off" shows for a moment before the panel goes.
local function name_only(name, config)
    local c = canvas()
    c.text(PAD, TOP + 2, 140, HEAD, name, FONT.title, LABEL)
    return c.finish(PAD * 2 + 100, TOP + HEAD + BOTTOM - 3, config.scale)
end

-- Nil when the meter is off, or when it has nothing to show yet: a meter appears with its first number. announce
-- (just after a key press) shows it anyway, with the view's name in the header, so you know where the key took you.
function M.build(snapshot, mode, config, announce)
    config = config or {}
    local name = announce and M.NAMES[mode] or nil
    if mode == "grid" then return grid(snapshot, config, announce, name) end
    if mode == "stack" then return stack(snapshot, config, announce, name) end
    local single_mode = SINGLE[mode]
    if single_mode then return single(snapshot, single_mode[1], single_mode[2], config, announce, name) end
    if mode == "off" and announce then return name_only(M.NAMES.off, config) end
    return nil
end

return M
