--!strict
-- ServerScriptService/Demo/FtueService.luau
--
-- First-hour onboarding GOAL CHECKLIST (first-hour-daily-loop-gdd §2.1/§6.1). The
-- 6-step checklist that walks a NEW player through the core loop. SERVER-OWNED:
-- the client never reports progress — each goal's `done` state is DERIVED here
-- from the authoritative persisted profile:
--   catch3      <- rosterCount >= ftue.catchTarget
--   deploy1     <- any entry in the building's deployment map
--   upgrade1    <- factoryLevel >= 1
--   winduel     <- ftue.wonDuel flag
--   boss1       <- ftue.killedBoss flag
--   sanctuary5  <- factoryLevel >= ftue.sanctuaryLevelTarget
-- Only winduel/boss1 need persisted flags (set via noteWin); the rest fall out of
-- state the profile already tracks, so the checklist can never drift from reality.

local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataService = require(ServerStorage:WaitForChild("PlayerData"):WaitForChild("PlayerDataService"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local DemoConfig = require(Shared:WaitForChild("Demo"):WaitForChild("DemoConfig"))
local DemoRemotes = require(Shared:WaitForChild("Demo"):WaitForChild("DemoRemotes"))

local FtueService = {}

local CFG = DemoConfig.ftue
local BUILDING_ID = "b1" -- the single MVP factory building (matches DemoServer)

-- Resolve the done-state of every goal id from a persisted profile.
local function computeDone(data: any): { [string]: boolean }
    local buildings = data.base and data.base.buildings
    local b1 = buildings and buildings[BUILDING_ID]
    local level = (b1 and b1.factoryLevel) or 0
    local deployed = b1 ~= nil and next(b1.deployment) ~= nil
    local ftue = data.ftue or {}
    return {
        catch3 = (data.rosterCount or 0) >= CFG.catchTarget,
        deploy1 = deployed,
        upgrade1 = level >= 1,
        winduel = ftue.wonDuel == true,
        boss1 = ftue.killedBoss == true,
        sanctuary5 = level >= CFG.sanctuaryLevelTarget,
    }
end

-- Push the current checklist to `player` (no-op if disabled / no profile yet).
function FtueService.push(player: Player)
    if not CFG.enabled then
        return
    end
    local data = PlayerDataService.getData(player)
    if data == nil then
        return
    end
    local done = computeDone(data)
    local goals = {}
    local allDone = true
    for _, g in CFG.goals do
        local isDone = done[g.id] == true
        if not isDone then
            allDone = false
        end
        table.insert(goals, { id = g.id, icon = g.icon, label = g.label, done = isDone })
    end
    DemoRemotes.GoalUpdate:FireClient(player, { goals = goals, allDone = allDone })
end

-- Record a combat win (and a boss kill) — sets the persisted flags ONCE and
-- pushes the refreshed checklist. Safe to call on every win (idempotent).
function FtueService.noteWin(player: Player, isBoss: boolean)
    if not CFG.enabled then
        return
    end
    PlayerDataService.update(player, function(d)
        local ftue = d.ftue or { wonDuel = false, killedBoss = false }
        d.ftue = ftue
        local changed = false
        if not ftue.wonDuel then
            ftue.wonDuel = true
            changed = true
        end
        if isBoss and not ftue.killedBoss then
            ftue.killedBoss = true
            changed = true
        end
        return changed
    end)
    FtueService.push(player)
end

return FtueService
