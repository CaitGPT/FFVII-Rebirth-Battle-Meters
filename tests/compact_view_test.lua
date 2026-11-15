-- Plain Lua 5.4 checks for compact_view.lua (run with tests/run_tests.py).
local View = require("compact_view")

local config = {rolling_window_seconds = 5}
local function kind(average, recent, total, biggest, by_source, attributed)
    return {average = average, recent = recent, total = total, biggest = biggest, by_source = by_source or {},
        attributed = attributed}
end
local function snapshot_with(damage_attributed)
    return {elapsed = 197.9, kinds = {
        damage = kind(440, 976, 87100, 866, {Barret = 51778, ["Red XIII"] = 17074, Yuffie = 18248}, damage_attributed),
        heal = kind(68.7, 0, 13593, 1178, {Barret = 8741, ["Red XIII"] = 2690, Yuffie = 2162}, damage_attributed),
        taken = kind(69.7, 0, 13794, 1255, {Barret = 8627, ["Red XIII"] = 2967, Yuffie = 2200}),
        mp = kind(0, 0, 40, 12),
    }}
end
local split = snapshot_with(true)

local function texts(view)
    local out = {}
    for _, t in ipairs(view.texts) do out[#out + 1] = t.text end
    return out
end
local function has(view, text)
    for _, t in ipairs(view.texts) do
        if t.text == text then return t end
    end
    return nil
end
local function index_of(view, text)
    for i, t in ipairs(view.texts) do
        if t.text == text then return i end
    end
    return nil
end

assert(View.format_short(950) == "950")
assert(View.format_short(2967) == "3.0k", View.format_short(2967))
assert(View.format_short(87100) == "87.1k")
assert(View.format_short(99960) == "100k", "rounds up into the next form: " .. View.format_short(99960))
assert(View.format_short(1234567) == "1.2M")
assert(View.format_time(197.9) == "3:17")

assert(View.build(split, "off", config) == nil, "off draws nothing")
assert(View.build(split, "dps", config) == nil, "classic names aren't compact modes")

-- Compact: the header line holds rate, total, biggest and time, then a bar per character, biggest first.
local dps = View.build(split, "dps_compact", config)
assert(dps.compact and dps.width == 320)
for _, text in ipairs({"DMG", "440/s", "87.1k", "max 866", "3:17", "Barret", "51,778", "59%", "Yuffie", "Red XIII"}) do
    assert(has(dps, text), "dps_compact shows " .. text .. ": " .. table.concat(texts(dps), " | "))
end
assert(index_of(dps, "Barret") < index_of(dps, "Red XIII") and index_of(dps, "Red XIII") < index_of(dps, "Yuffie"),
    "no party order given: the usual character order, not a ranking")
-- With the party's slot order, rows follow it, whoever leads.
local slotted = snapshot_with(true)
slotted.party_order = {"Yuffie", "Barret", "Red XIII"}
local sv = View.build(slotted, "dps_full", config)
assert(index_of(sv, "Yuffie") < index_of(sv, "Barret") and index_of(sv, "Barret") < index_of(sv, "Red XIII"), "slot order")
local sg = View.build(slotted, "grid", config)
assert(index_of(sg, "Yuffie") < index_of(sg, "Barret"), "the grid too")
assert(not has(dps, "Total"), "compact lists no stat rows")
-- Bars: a back and a share per character; the share's width is its part of the total.
assert(#dps.rects == 6)
local back, share = dps.rects[1], dps.rects[2]
assert(back.w == 296 and math.abs(share.w - 296 * 51778 / 87100) <= 1, share.w)
-- The time is the rightmost text on the header line.
local time = has(dps, "3:17")
assert(time.justify == 2 and time.x + time.w == 12 + 296)

-- HPS compact keeps to one line: no MP stats.
local hps = View.build(split, "hps_compact", config)
assert(has(hps, "HEAL") and not has(hps, "MP spent"), "HPS compact has no MP line")

-- Full: name and time on top, the bars, then each stat on its own row. HPS adds the two MP rows.
local full = View.build(split, "dps_full", config)
for _, text in ipairs({"DAMAGE", "3:17", "Total", "87,100", "Per sec", "440", "Last 5s", "976", "Highest", "866"}) do
    assert(has(full, text), "dps_full shows " .. text)
end
assert(index_of(full, "Red XIII") < index_of(full, "Total"), "stats come after the characters")
local hfull = View.build(split, "hps_full", config)
assert(has(hfull, "MP spent") and has(hfull, "Healing per MP") and has(hfull, "340"), "13,593 healing / 40 MP")
assert(not has(View.build(split, "dtps_full", config), "MP spent"))

-- Grid: time top left, a row per character in party order, a cell per meter, the stats underneath.
local grid = View.build(split, "grid", config)
local corner = has(grid, "3:17")
assert(corner.x == 12 and corner.justify == 0, "time in the top left corner")
for _, text in ipairs({"DMG", "HEAL", "TAKEN", "51.8k", "8.7k", "8.6k", "3.0k", "Total", "Per sec", "Last 5s", "Highest"}) do
    assert(has(grid, text), "grid shows " .. text)
end
assert(index_of(grid, "Barret") < index_of(grid, "Red XIII") and index_of(grid, "Red XIII") < index_of(grid, "Yuffie"),
    "party order, not ranking")
assert(index_of(grid, "Yuffie") < index_of(grid, "Total"), "stats under the characters")

-- Stack: all three meters, each with its compact header (no time of its own), the fight time on top.
local stack = View.build(split, "stack", config)
for _, text in ipairs({"Fight", "3:17", "DAMAGE", "HEALING", "TAKEN", "440/s", "69/s", "70/s"}) do
    assert(has(stack, text), "stack shows " .. text)
end
local count = 0
for _, t in ipairs(stack.texts) do if t.text == "3:17" then count = count + 1 end end
assert(count == 1, "one time for the whole stack")

-- Without Battle Meters Native, damage and healing have no split: no bars, never a guess. Damage taken still splits.
local totals = snapshot_with(nil)
local plain = View.build(totals, "dps_compact", config)
assert(#plain.rects == 0 and has(plain, "87.1k") and not has(plain, "Barret"))
local pgrid = View.build(totals, "grid", config)
assert(has(pgrid, "-") and has(pgrid, "8.6k"), "grid: '-' for damage and healing, damage taken by character")

-- Unattributed comes last, whatever its size, and guests sort after the party.
local odd = {elapsed = 10, kinds = {damage = kind(10, 10, 1000, 100, {Unattributed = 600, Cloud = 300, Stranger = 100}, true),
    heal = kind(0, 0, 0, 0), taken = kind(0, 0, 0, 0)}}
local rows = View.rows(odd.kinds.damage.by_source, 1000)
assert(rows[1].name == "Cloud" and rows[2].name == "Stranger" and rows[3].name == "Unattributed")
assert(rows[3].share == 0.6)
rows = View.rows(odd.kinds.damage.by_source, 1000, {"Stranger", "Cloud"})
assert(rows[1].name == "Stranger" and rows[2].name == "Cloud" and rows[3].name == "Unattributed", "Unattributed stays last")
local order = View.party_order({Unattributed = true, Stranger = true, Tifa = true, Cloud = true})
assert(order[1] == "Cloud" and order[2] == "Tifa" and order[3] == "Stranger" and order[4] == "Unattributed")

-- Nothing yet: no panel, unless a key was just pressed; then an empty one, with no dividing by zero.
local empty = {elapsed = 0, kinds = {damage = kind(0, 0, 0, 0), heal = kind(0, 0, 0, 0), taken = kind(0, 0, 0, 0)}}
for _, mode in ipairs({"dps_compact", "dps_full", "hps_full", "dtps_compact", "grid", "stack"}) do
    assert(View.build(empty, mode, config) == nil, mode .. " hides with nothing to show")
    local v = View.build(empty, mode, config, true)
    assert(v and v.height > 0, mode .. " shows when announced")
end
local announced = View.build(empty, "grid", config, true)
assert(has(announced, "DMG") and has(announced, "HEAL") and has(announced, "TAKEN"), "announced empty grid: all three")

-- No healing yet: the grid drops its column and the stack its section; HPS alone hides.
local no_heal = snapshot_with(true)
no_heal.kinds.heal = kind(0, 0, 0, 0)
local ng = View.build(no_heal, "grid", config)
assert(has(ng, "DMG") and has(ng, "TAKEN") and not has(ng, "HEAL"), "no HEAL column")
assert(ng.width == grid.width - 90 - 4, "one column narrower")
local ns = View.build(no_heal, "stack", config)
assert(has(ns, "DAMAGE") and has(ns, "TAKEN") and not has(ns, "HEALING"), "no HEALING section")
assert(View.build(no_heal, "hps_compact", config) == nil and View.build(no_heal, "hps_full", config) == nil)
assert(View.build(no_heal, "dps_compact", config), "the others still show")

-- Scale multiplies everything.
local big = View.build(split, "dps_compact", {rolling_window_seconds = 5, scale = 1.5})
assert(big.width == 480 and big.texts[1].size == 18)

-- Colours are shared tables, so the overlay can skip unchanged ones by identity.
assert(View.build(split, "dps_compact", config).rects[2].color == dps.rects[2].color)

-- Every stat row and header number is one size; only the bars' names and amounts are a step bigger.
for _, mode in ipairs({"dps_compact", "dps_full", "hps_full", "grid", "stack"}) do
    local v, sizes = View.build(split, mode, config), {}
    for _, t in ipairs(v.texts) do
        if t.text:match("/s$") or t.text:match("^max ") or t.text == "Total" or t.text == "Per sec" or t.text == "Highest" then
            sizes[t.size] = true
        end
    end
    local n = 0
    for _ in pairs(sizes) do n = n + 1 end
    assert(n == 1, mode .. ": stats in one font size")
end

-- Just after a key press, the header names the view: in place of the compact header's numbers, the full view's title,
-- the grid's time and the stack's "Fight". Off shows its name alone before the panel goes.
local named = {dps_compact = "DPS · Compact", dps_full = "DPS · Full", hps_compact = "HPS · Compact", hps_full = "HPS · Full",
    dtps_compact = "DTPS · Compact", dtps_full = "DTPS · Full", grid = "All · Grid", stack = "All · Stack"}
for mode, name in pairs(named) do
    assert(View.NAMES[mode] == name)
    local v = View.build(split, mode, config, true)
    assert(has(v, name), mode .. " is named")
    assert(not has(View.build(split, mode, config), name), mode .. ": the name goes once the moment has passed")
end
local just_switched = View.build(split, "dps_compact", config, true)
assert(not has(just_switched, "440/s") and has(just_switched, "3:17") and has(just_switched, "Barret"),
    "compact: the name replaces the numbers; time and bars stay")
assert(not has(View.build(split, "grid", config, true), "3:17"), "grid: the name takes the time's corner")
assert(not has(View.build(split, "stack", config, true), "Fight"))
local off = View.build(split, "off", config, true)
assert(off and #off.texts == 1 and off.texts[1].text == "Off" and #off.rects == 0)
assert(View.build(split, "off", config) == nil)
