--!strict
-- ServerScriptService/Demo/GalleryService.luau
--
-- MONSTER GALLERY / dex (Monster Dex). Owns the PERMANENT set of distinct
-- species×element combos a player has ever caught (`data.dex`, key =
-- "species|element"). SERVER-AUTHORITATIVE: the dex is only ever written here,
-- on a successful catch. The first time a NEW combo is caught it registers
-- permanently (survives releasing the monster) and grants a discovery reward
-- (free Capture Nets). The client renders the full 5×5 grid from the replicated
-- species/element catalog; the server only ships the unlocked-key set.

local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataService = require(ServerStorage:WaitForChild("PlayerData"):WaitForChild("PlayerDataService"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local DemoConfig = require(Shared:WaitForChild("Demo"):WaitForChild("DemoConfig"))
local DemoRemotes = require(Shared:WaitForChild("Demo"):WaitForChild("DemoRemotes"))
local ElementConfig = require(Shared:WaitForChild("Config"):WaitForChild("ElementConfig"))

local GalleryService = {}

local CFG = DemoConfig.gallery

-- Canonical dex key for a (species, element) pair. Stable + JSON-safe; the client
-- builds the SAME key per grid cell to test unlocked state.
local function dexKey(species: any, element: any): string
    return tostring(species) .. "|" .. tostring(element)
end
GalleryService.dexKey = dexKey

-- Backfill the dex from the CURRENT roster the first time a profile loads without
-- one (old profiles predate the field). A migration, NOT a discovery — grants no
-- reward. New profiles already carry an empty dex from Schema.default.
function GalleryService.ensureDex(player: Player)
    if not CFG.enabled then
        return
    end
    local data = PlayerDataService.getData(player)
    if data == nil or data.dex ~= nil then
        return -- already has a dex (or no profile yet)
    end
    PlayerDataService.update(player, function(profile)
        if profile.dex ~= nil then
            return false
        end
        local dex: { [string]: boolean } = {}
        for _, entry in profile.roster do
            dex[dexKey(entry.species, entry.element)] = true
        end
        profile.dex = dex
        return true
    end)
end

-- Count the species whose FULL element row is present in `dex` (a "completed
-- set"). Species are the 1-based indices 1..#speciesOrder (matching the persisted
-- entry.species), each complete when every element of ElementConfig.order is
-- caught for it. Pure: reads only the passed dex set.
function GalleryService.completedSetCount(dex: { [string]: boolean }?): number
    if dex == nil then
        return 0
    end
    local count = 0
    for si = 1, #DemoConfig.speciesOrder do
        local full = true
        for _, element in ipairs(ElementConfig.order) do
            if dex[dexKey(si, element)] ~= true then
                full = false
                break
            end
        end
        if full then
            count += 1
        end
    end
    return count
end

-- The GLOBAL combat multiplier this dex grants: 1 + completedSets *
-- setBonusPerSet (e.g. 3 completed sets at 0.10 = x1.30). Applied to a player's
-- fighter HP + per-tick damage. Pure (takes the dex set).
function GalleryService.combatBonusMult(dex: { [string]: boolean }?): number
    return 1 + GalleryService.completedSetCount(dex) * CFG.setBonusPerSet
end

-- Push the unlocked dex set to the client (no-op if disabled / no profile yet).
function GalleryService.push(player: Player)
    if not CFG.enabled then
        return
    end
    local data = PlayerDataService.getData(player)
    if data == nil then
        return
    end
    DemoRemotes.GalleryUpdate:FireClient(player, { caught = data.dex or {} })
end

-- Record a successful catch. Returns true IFF this (species, element) combo was
-- NEW (a first-ever discovery) — the caller grants the discovery flavor (banner)
-- and refreshes the backpack, since the net reward is credited here atomically
-- with the dex write. Idempotent: a re-catch of a known combo returns false and
-- touches nothing.
function GalleryService.noteCatch(player: Player, species: any, element: any): boolean
    if not CFG.enabled then
        return false
    end
    local key = dexKey(species, element)
    local data = PlayerDataService.getData(player)
    if data == nil then
        return false
    end
    if data.dex ~= nil and data.dex[key] == true then
        return false -- already discovered; cheap pre-check avoids a needless txn
    end

    local discovered = false
    PlayerDataService.update(player, function(profile)
        if profile.dex == nil then
            profile.dex = {}
        end
        if profile.dex[key] == true then
            return false -- a racing catch registered it first
        end
        profile.dex[key] = true
        -- DISCOVERY REWARD: free Capture Nets, credited atomically with the dex
        -- write so the grant + the unlock can never diverge.
        local reward = CFG.discoveryNetReward
        if reward > 0 then
            profile.items = profile.items or {}
            profile.items.capture_net = (profile.items.capture_net or 0) + reward
        end
        discovered = true
        return true
    end)

    if discovered then
        GalleryService.push(player)
    end
    return discovered
end

return GalleryService
