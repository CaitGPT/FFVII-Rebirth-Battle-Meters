-- Plain Lua 5.4 checks for sim_overhaul.lua (run with tests/run_tests.py).
local SimOverhaul = require("sim_overhaul")

local present = {}
local function exists(path) return present[path] == true end
local mods = "C:\\Game\\ue4ss\\Mods\\"

assert(SimOverhaul.course_running(mods, exists) == nil, "no marker: no course")
present[mods .. "SimulatorUpgrade\\meters-active.txt"] = true
assert(SimOverhaul.course_running(mods, exists) == mods .. "SimulatorUpgrade\\meters-active.txt", "released mod")
present = {[mods .. "SimulatorOverhaul\\meters-active.txt"] = true}
assert(SimOverhaul.course_running(mods, exists) == mods .. "SimulatorOverhaul\\meters-active.txt",
    "a build from before the rename to Simulator Upgrade")
present = {[mods .. "SimOverhaulMeters\\meters-active.txt"] = true}
assert(SimOverhaul.course_running(mods, exists) == mods .. "SimOverhaulMeters\\meters-active.txt", "development build")
present = {["/g/Mods/SimulatorUpgrade/meters-active.txt"] = true}
assert(SimOverhaul.course_running("/g/Mods/", exists, "/"), "other separator")
assert(SimOverhaul.course_running("", exists) == nil and SimOverhaul.course_running(nil, exists) == nil, "no folder")
-- Another file in the folder isn't the marker, nor is the marker in another folder.
present = {[mods .. "SimulatorUpgrade\\settings.txt"] = true, [mods .. "SimulatorUpgradeNative\\meters-active.txt"] = true}
assert(SimOverhaul.course_running(mods, exists) == nil, "only the marker counts")
assert(SimOverhaul.file_exists("this file does not exist " .. tostring(os.time())) == false)
print("sim_overhaul_test: ok")
