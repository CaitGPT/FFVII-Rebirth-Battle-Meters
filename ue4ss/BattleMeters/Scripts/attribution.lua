-- Who dealt the damage, or who did the healing. Pure Lua: no game calls, so it can be tested outside the game (see
-- tests/attribution_test.lua). main.lua keeps one of these for damage dealt (targets are enemies, changes are HP lost)
-- and one for healing (targets are party members, changes are HP gained).
--
-- The totals stay what they always were: HP actually lost or gained, read every tick. The game's hit events say who hit
-- or healed whom and for how much, but a hit's number can be larger than the HP left (overkill, overhealing), and its
-- event may arrive a tick before or after the HP reading shows it. So hits are only ever matched against HP changes
-- already counted for that target: a character is credited at most what really changed, the credited amounts can never
-- add up to more than the total, and whatever no hit explains (poison, Regen, a hit whose event never came) stays
-- unattributed.
local M = {}
M.__index = M

M.UNATTRIBUTED = "Unattributed"

-- How long a hit and an HP change may be apart and still be matched, in seconds of game time.
local MATCH_WINDOW = 1.0

function M.new(match_window)
    local self = setmetatable({window = match_window or MATCH_WINDOW}, M)
    self:reset()
    return self
end

function M:reset()
    self.credited = {}        -- player name -> amount
    self.targets = {}         -- target name -> {changes = {{amount, t}}, hits = {{amount, who, t}}}
    self.aliases = {}         -- any name the game uses for a party member -> player name
    self.matched_hits = 0     -- hits that explained some HP change this battle
    self.unknown_target = 0   -- hits on a name that isn't a tracked target
    self.unknown_causer = {}  -- causer names that aren't party members, with a count
end

-- A name the game's hit events may use for a party member (its actor name, chara ID...).
function M:alias(name, player)
    if type(name) == "string" and name ~= "" and name ~= "None" and player then self.aliases[name] = player end
end

function M:player_of(name)
    return self.aliases[name]
end

-- A target has been seen: hits on it are matched from now on. Changes before its first HP reading aren't counted in the
-- total either.
function M:track(name)
    if type(name) ~= "string" or name == "" or name == "None" then return end
    self.targets[name] = self.targets[name] or {changes = {}, hits = {}}
end

local function credit(self, who, amount)
    self.credited[who] = (self.credited[who] or 0) + amount
end

local function match(self, hit, change)
    local amount = math.min(change.amount, hit.amount)
    if hit.who then credit(self, hit.who, amount) end
    if not hit.matched then
        hit.matched = true
        self.matched_hits = self.matched_hits + 1
    end
    change.amount, hit.amount = change.amount - amount, hit.amount - amount
end

local function keep(list, now, window)
    local out = {}
    for _, item in ipairs(list) do
        if item.amount > 0 and not (now and now - item.t > window) then out[#out + 1] = item end
    end
    return out
end

-- A hit is matched with a change in the same tick first: that's where it shows almost always, and it stops an overkill
-- hit soaking up a poison tick next to it. Then the oldest within the window. What is too old is dropped.
local function settle(self, target, now)
    for pass = 1, 2 do
        for _, hit in ipairs(target.hits) do
            for _, change in ipairs(target.changes) do
                if hit.amount <= 0 then break end
                local close = pass == 1 and change.t == hit.t or pass == 2 and math.abs(change.t - hit.t) <= self.window
                if change.amount > 0 and close then match(self, hit, change) end
            end
        end
    end
    target.hits, target.changes = keep(target.hits, now, self.window), keep(target.changes, now, self.window)
end

-- HP the target lost (damage) or gained (healing), exactly as added to the total.
function M:change(name, amount, now)
    local target = self.targets[name]
    if not target or type(amount) ~= "number" or amount <= 0 then return end
    target.changes[#target.changes + 1] = {amount = amount, t = now}
    settle(self, target, now)
end

-- One of the game's hit events, already sorted by main.lua into damage on an enemy or healing on a party member. Only
-- hits on a tracked target count. A hit by anyone who isn't a party member (a summon, an enemy, the scenery) still
-- uses up the change it explains, so it isn't credited to a character by mistake, but it stays unattributed.
function M:hit(amount, causer, target_name, now)
    if type(amount) ~= "number" or amount <= 0 then return end
    local target = self.targets[target_name]
    if not target then
        self.unknown_target = self.unknown_target + 1
        return
    end
    local who = self.aliases[causer]
    if not who and type(causer) == "string" then
        self.unknown_causer[causer] = (self.unknown_causer[causer] or 0) + 1
    end
    target.hits[#target.hits + 1] = {amount = amount, who = who, t = now}
    settle(self, target, now)
end

-- The target has left (an enemy died or fled, a member left the party). Its last change has already been passed in.
function M:forget(name)
    local target = self.targets[name]
    if target then settle(self, target, nil) end
    self.targets[name] = nil
end

-- The amount per character, plus the rest of the total as unattributed. Nil until a hit has been matched: then the
-- game's hit events aren't reaching us (Battle Meters Native isn't installed, or this scene doesn't send them), and the
-- panel keeps to the total.
function M:split(total)
    if self.matched_hits == 0 or type(total) ~= "number" or total <= 0 then return nil end
    local out, sum = {}, 0
    for who, amount in pairs(self.credited) do
        out[who] = amount
        sum = sum + amount
    end
    local rest = total - sum
    if rest >= 0.5 then out[M.UNATTRIBUTED] = rest end
    return out
end

return M
