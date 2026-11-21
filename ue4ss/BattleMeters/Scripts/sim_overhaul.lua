-- Simulator Upgrade (called Simulator Overhaul until 2026-11-21) draws its own meters panel in its Custom Training
-- course, combining this mod's meters with Training Dummy's. While a course runs it keeps a marker file,
-- meters-active.txt, in its mod folder: SimulatorUpgrade, SimulatorOverhaul in a build from before the rename, or
-- SimOverhaulMeters while it is being built. Battle Meters then stands aside, as it does on Training Dummy's courses. Pure Lua: the file check is passed in, so it is tested offline
-- (tests/sim_overhaul_test.lua).
local M = {}

M.MARKERS = {"SimulatorUpgrade", "SimulatorOverhaul", "SimOverhaulMeters"}
M.FILE = "meters-active.txt"

-- mods_dir: the ue4ss Mods folder, ending with a separator. exists(path) -> true when the file is there.
-- Returns the marker's path when a Custom Training course is running, else nil.
function M.course_running(mods_dir, exists, sep)
    if type(mods_dir) ~= "string" or mods_dir == "" then return nil end
    sep = sep or "\\"
    for _, folder in ipairs(M.MARKERS) do
        local path = mods_dir .. folder .. sep .. M.FILE
        if exists(path) then return path end
    end
    return nil
end

-- A plain file check, for the game.
function M.file_exists(path)
    local file = io.open(path, "rb")
    if file then file:close() end
    return file ~= nil
end

return M
