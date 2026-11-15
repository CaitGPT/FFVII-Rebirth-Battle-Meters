-- Plain Lua 5.4 checks for settings.lua (run with tests/run_tests.py).
local Settings = require("settings")

assert(Settings.next("off") == "dps")
assert(Settings.next("dps") == "hps")
assert(Settings.next("hps") == "dtps")
assert(Settings.next("dtps") == "off", "the last press turns it off")
assert(Settings.next("nonsense") == "dps")

assert(Settings.parse("meter=hps\n") == "hps")
assert(Settings.parse("meter = off") == "off")
assert(Settings.parse("meter=loud") == "off", "an unknown value means the default")
assert(Settings.parse("nonsense") == "off")
assert(Settings.parse(nil) == "off", "no file means off: the first press brings up DPS")
assert(Settings.parse(Settings.serialize("dtps")) == "dtps", "round trip")

-- The compact layout's cycle: off, each meter compact then full, the grid, the stack, and back to off.
local cycle, mode = {}, "off"
for _ = 1, 9 do
    mode = Settings.next(mode, "compact")
    cycle[#cycle + 1] = mode
end
assert(table.concat(cycle, " ") == "dps_compact dps_full hps_compact hps_full dtps_compact dtps_full grid stack off",
    table.concat(cycle, " "))
assert(Settings.next("nonsense", "compact") == "dps_compact")
assert(Settings.parse("meter=grid", "compact") == "grid")
assert(Settings.parse(Settings.serialize("hps_full"), "compact") == "hps_full", "round trip")
-- A meter saved by the other layout opens as its nearest match, so switching layouts keeps the panel on.
assert(Settings.parse("meter=dps", "compact") == "dps_full")
assert(Settings.parse("meter=dtps_compact", "classic") == "dtps")
assert(Settings.parse("meter=stack", "classic") == "dps")
assert(Settings.parse("meter=stack", "nonsense") == "dps", "an unknown layout is classic")
