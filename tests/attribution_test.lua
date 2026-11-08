-- Plain Lua 5.4 checks for attribution.lua (run with tests/run_tests.py).
local Attribution = require("attribution")
local U = Attribution.UNATTRIBUTED

local function fresh()
    local a = Attribution.new(1.0)
    a:alias("PC0000_Cloud_01", "Cloud")
    a:alias("PC0002_Tifa_01", "Tifa")
    a:alias("None", "Nobody")   -- ignored: not a name
    a:track("EN2001_03_A")
    a:track("EN2001_03_B")
    return a
end

-- No hit events at all: no split, so the panel keeps to the total.
local a = fresh()
a:change("EN2001_03_A", 500, 1.0)
assert(a:split(500) == nil, "no matched hit, no split")
assert(a:player_of("None") == nil)

-- Hits and losses in the same tick, either order.
a = fresh()
a:hit(300, "PC0000_Cloud_01", "EN2001_03_A", 1.0)
a:change("EN2001_03_A", 300, 1.0)
a:change("EN2001_03_B", 120, 1.2)
a:hit(120, "PC0002_Tifa_01", "EN2001_03_B", 1.2)
local s = a:split(420)
assert(s.Cloud == 300 and s.Tifa == 120 and s[U] == nil, "both credited in full")

-- A hit's event a tick before or after the HP reading still matches, within the window.
a = fresh()
a:hit(200, "PC0000_Cloud_01", "EN2001_03_A", 2.0)
a:change("EN2001_03_A", 200, 2.2)
a:change("EN2001_03_B", 90, 3.0)
a:hit(90, "PC0002_Tifa_01", "EN2001_03_B", 3.2)
s = a:split(290)
assert(s.Cloud == 200 and s.Tifa == 90, "late or early events match")

-- Overkill: the killing hit says 999 but the enemy only had 150 left. Only the 150 counts.
a = fresh()
a:change("EN2001_03_A", 150, 5.0)
a:hit(999, "PC0000_Cloud_01", "EN2001_03_A", 5.0)
s = a:split(150)
assert(s.Cloud == 150 and s[U] == nil, "credit never exceeds the HP lost")

-- Poison or anything else with no hit event stays unattributed; the split always adds up to the total.
a = fresh()
a:hit(400, "PC0002_Tifa_01", "EN2001_03_A", 1.0)
a:change("EN2001_03_A", 400, 1.0)
a:change("EN2001_03_A", 35, 4.0)   -- a poison tick, no hit
a:change("EN2001_03_A", 35, 6.0)
s = a:split(470)
assert(s.Tifa == 400 and s[U] == 70, "unexplained loss is unattributed")

-- A hit too far from any loss is dropped (a whiff the game still reported, or a guarded hit for 0 HP).
a = fresh()
a:hit(500, "PC0000_Cloud_01", "EN2001_03_A", 1.0)
a:change("EN2001_03_A", 500, 3.5)
s = a:split(500)
assert(s == nil, "out of the window: matched nothing")

-- Two characters hitting the same enemy in one tick: each gets their own hit, oldest first.
a = fresh()
a:hit(100, "PC0000_Cloud_01", "EN2001_03_A", 1.0)
a:hit(60, "PC0002_Tifa_01", "EN2001_03_A", 1.0)
a:change("EN2001_03_A", 160, 1.0)
s = a:split(160)
assert(s.Cloud == 100 and s.Tifa == 60)

-- Hits that don't count: zero damage, hits on a target not tracked (main.lua sends hits on the party elsewhere).
a = fresh()
a:hit(0, "PC0000_Cloud_01", "EN2001_03_A", 1.0)
a:hit(-5, "PC0000_Cloud_01", "EN2001_03_A", 1.0)
a:hit(100, "PC0000_Cloud_01", "EN9999_Unseen", 1.0)
a:change("EN2001_03_A", 100, 1.0)
assert(a:split(100) == nil, "none of those explain the loss")
assert(a.unknown_target == 1)

-- Healing works the same way, with party members as targets and HP gained as the change: overhealing isn't credited.
local h = Attribution.new(1.0)
h:alias("Tifa", "Tifa")
h:alias("Aerith", "Aerith")
h:track("Tifa")
h:track("Aerith")
h:hit(2280, "Tifa", "Tifa", 3.0)      -- Chakra for more than Tifa was missing
h:change("Tifa", 400, 3.0)
h:hit(1204, "Aerith", "Tifa", 4.0)
h:change("Tifa", 600, 4.2)
h:change("Aerith", 80, 6.0)           -- Regen, no hit
s = h:split(1080)
assert(s.Tifa == 400 and s.Aerith == 600 and s[U] == 80, "heals capped by HP gained, Regen unattributed")

-- A summon or anyone outside the party uses up the loss it explains, so it isn't credited to a character.
a = fresh()
a:hit(800, "SM0001_Ifrit", "EN2001_03_A", 1.0)
a:hit(100, "PC0000_Cloud_01", "EN2001_03_A", 1.0)
a:change("EN2001_03_A", 900, 1.0)
s = a:split(900)
assert(s.Cloud == 100 and s[U] == 800 and a.unknown_causer.SM0001_Ifrit == 1)

-- An enemy that leaves: its pending hits are matched against its killing blow, then it is forgotten.
a = fresh()
a:hit(250, "PC0000_Cloud_01", "EN2001_03_B", 7.0)
a:change("EN2001_03_B", 250, 7.0)
a:forget("EN2001_03_B")
a:hit(50, "PC0000_Cloud_01", "EN2001_03_B", 7.2)
assert(a:split(250).Cloud == 250 and a.unknown_target == 1, "hits after it left don't count")

-- Rounding: a remainder under half a point isn't shown.
a = fresh()
a:hit(10, "PC0000_Cloud_01", "EN2001_03_A", 1.0)
a:change("EN2001_03_A", 10, 1.0)
assert(a:split(10.2)[U] == nil)

-- reset() clears everything, aliases too (party members are named again each battle).
a:reset()
assert(a:player_of("PC0000_Cloud_01") == nil and next(a.credited) == nil and a.matched_hits == 0)

print("attribution_test: ok")
