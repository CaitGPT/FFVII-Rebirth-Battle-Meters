-- Plain Lua 5.4 checks for meter_view.lua (run with tests/run_tests.py).
local View = require("meter_view")

local config = {rolling_window_seconds = 5}
local function kind(average, recent, total, biggest, by_source)
    return {average = average, recent = recent, total = total, biggest = biggest, by_source = by_source or {}}
end
local snapshot = {elapsed = 67.4, kinds = {
    damage = kind(4210.4, 3988, 1000, 9999, {Tifa = 250, Cloud = 750}),
    taken = kind(312, 287, 20904, 1290, {Tifa = 6404, Cloud = 14500}),
    heal = kind(40, 20, 2700, 900, {Aerith = 2700}),
    mp = kind(0, 0, 45, 9),
}}

assert(View.format_number(0) == "0")
assert(View.format_number(1000) == "1,000")
assert(View.format_number(1234567.6) == "1,234,568")
assert(View.format_number(nil) == "0")
assert(View.format_time(67.4) == "1:07")
assert(View.format_time(600) == "10:00")

assert(View.build(snapshot, "off", config) == nil, "off draws nothing")

local dps = View.build(snapshot, "dps", config)
assert(dps.title == "DPS" and dps.value == "4,210")
assert(dps.stats[1][1] == "Last 5 seconds" and dps.stats[1][2] == "3,988")
assert(dps.stats[2][1] == "Total" and dps.stats[2][2] == "1,000")
assert(dps.stats[3][1] == "Biggest hit" and dps.stats[3][2] == "9,999")
assert(dps.stats[4][1] == "Time" and dps.stats[4][2] == "1:07")
assert(#dps.stats == 4, "only HPS tracks MP")

-- Damage dealt has no line: HP loss on an enemy doesn't say who caused it.
assert(dps.show_line == false and #dps.segments == 0)

local hps = View.build(snapshot, "hps", config)
assert(hps.title == "HPS" and hps.stats[3][1] == "Biggest heal")
assert(hps.stats[4][1] == "MP spent" and hps.stats[4][2] == "45")
assert(hps.stats[5][1] == "Healing per MP" and hps.stats[5][2] == "60")
assert(#hps.segments == 1 and hps.segments[1].share == 1)

local dtps = View.build(snapshot, "dtps", config)
assert(dtps.title == "DTPS" and dtps.stats[3][1] == "Biggest hit taken")
-- The line keeps party order, whoever leads, and its sections add up to the whole.
local taken = dtps.segments
assert(dtps.show_line and #taken == 2 and taken[1].name == "Cloud" and taken[2].name == "Tifa")
assert(math.abs(taken[1].share + taken[2].share - 1) < 1e-9)
-- And a row per character after the usual four, in the line's order, with no hit events needed.
assert(#dtps.stats == 6 and dtps.stats[5][1] == "Cloud" and dtps.stats[6][1] == "Tifa")
assert(taken[1].color.R == 1 and taken[1].color.B < 0.5 and taken[2].color.R == 0 and taken[2].color.B == 0, "yellow, then black")

-- Nothing yet: no sections, and no dividing by zero MP.
local empty = {elapsed = 0, kinds = {damage = kind(0, 0, 0, 0), taken = kind(0, 0, 0, 0), heal = kind(0, 0, 0, 0), mp = kind(0, 0, 0, 0)}}
local none = View.build(empty, "hps", config)
assert(#none.segments == 0 and none.value == "0" and none.stats[5][2] == "-")

-- A guest character outside the list still gets a section.
local guest = {elapsed = 1, kinds = {damage = kind(0, 0, 0, 0), heal = kind(0, 0, 0, 0), taken = kind(1, 1, 10, 1, {Stranger = 4, Cloud = 6})}}
local line = View.build(guest, "dtps", config).segments
assert(#line == 2 and line[1].name == "Cloud" and line[2].name == "Stranger" and line[2].share == 0.4)

-- Damage by character, when the game's hit events explained it: a line in party order with Unattributed last, and a
-- row per character after the usual four.
local split = {elapsed = 30, kinds = {heal = kind(0, 0, 0, 0), taken = kind(0, 0, 0, 0), mp = kind(0, 0, 0, 0),
    damage = kind(100, 90, 3000, 999, {Unattributed = 300, Tifa = 900, Cloud = 1800})}}
split.kinds.damage.attributed = true
local by = View.build(split, "dps", config)
assert(by.show_line and #by.segments == 3)
assert(by.segments[1].name == "Cloud" and by.segments[2].name == "Tifa" and by.segments[3].name == "Unattributed")
assert(math.abs(by.segments[1].share + by.segments[2].share + by.segments[3].share - 1) < 1e-9)
assert(by.segments[3].color.R < 0.6 and by.segments[3].color.G < 0.7, "Unattributed is grey")
assert(#by.stats == 7 and by.stats[5][1] == "Cloud" and by.stats[5][2] == "1,800")
assert(by.stats[6][1] == "Tifa" and by.stats[7][1] == "Unattributed" and by.stats[7][2] == "300")
-- The other meters don't grow character rows.
assert(#View.build(split, "dtps", config).stats == 4)

-- Healing by who did it: rows after HPS's six lines, Unattributed last. Without the split (no Battle Meters Native),
-- HPS keeps its line by who received it and grows no rows.
local healing = {elapsed = 30, kinds = {damage = kind(0, 0, 0, 0), taken = kind(0, 0, 0, 0), mp = kind(0, 0, 40, 0),
    heal = kind(20, 10, 1000, 600, {Aerith = 600, Unattributed = 100, Tifa = 300})}}
healing.kinds.heal.attributed = true
local hv = View.build(healing, "hps", config)
assert(hv.show_line and #hv.segments == 3 and hv.segments[1].name == "Tifa" and hv.segments[3].name == "Unattributed")
assert(#hv.stats == 9 and hv.stats[7][1] == "Tifa" and hv.stats[8][1] == "Aerith" and hv.stats[8][2] == "600")
assert(hv.stats[9][1] == "Unattributed" and hv.stats[9][2] == "100")
healing.kinds.heal.attributed = nil
local received = View.build(healing, "hps", config)
assert(received.show_line and #received.stats == 6, "received split: a line, no rows")
