--!strict
-- ServerScriptService/World/WorldService.luau
--
-- SERVER-ONLY cross-place teleport layer (System #27 traversal). Implements the
-- one operation the BunkBed + return portal need: send a player to a destination
-- place, private (reserved) or public, WITHOUT losing data.
--
-- CORRECTNESS — the destination server LOADS the profile fresh from the DataStore
-- (PlayerDataBootstrap on join), so we MUST force-save BEFORE TeleportAsync.
-- Otherwise progress earned since the last autosave (up to autosaveIntervalSec =
-- 5 min: coins, catches) would roll back on arrival. The save is the gate: if it
-- fails, we do NOT teleport.
--
-- SESSION LOCK — the source server releases the lock on PlayerRemoving (fires on
-- teleport: stopHeartbeat -> force save -> release). The destination acquires with
-- the standard retry (lockAcquireMaxAttempts x lockAcquireBackoffSec ~= 6s), which
-- covers the normal teleport handoff window. We do NOT pre-release here: a failed
-- teleport must leave the player fully intact in the source server.
--
-- Pure logic module; the bootstrap wires prompts + the player-facing notifier.

local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldConfig = require(ReplicatedStorage.Shared.Config.WorldConfig)
local TravelConfig = require(ReplicatedStorage.Shared.Config.TravelConfig)
local PlayerDataService = require(ServerStorage.PlayerData.PlayerDataService)

local WorldService = {}

-- Player-facing toast hook (injected by the bootstrap; defaults to no-op so the
-- module is testable without the UI layer). Called as notify(player, text).
local notifyFn: ((Player, string) -> ())? = nil

function WorldService.setNotifier(fn: (Player, string) -> ())
    notifyFn = fn
end

local function notify(player: Player, text: string)
    if notifyFn then
        notifyFn(player, text)
    end
end

-- Per-player travel debounce (anti-spam; a teleport reserves a server + forces a
-- save). Cleared on PlayerRemoving via clearPlayer.
local lastTravelClock: { [Player]: number } = {}

function WorldService.clearPlayer(player: Player)
    lastTravelClock[player] = nil
end

local function isOnCooldown(player: Player): boolean
    local now = os.clock()
    local last = lastTravelClock[player]
    if last ~= nil and (now - last) < TravelConfig.cooldownSec then
        return true
    end
    lastTravelClock[player] = now
    return false
end

-- Send `player` to the place keyed `destKey` (a WorldConfig.places key, e.g.
-- "kandang" | "overworld"). Returns true if the teleport was dispatched; false on
-- any guard failure (with a player-facing notify). NEVER throws.
function WorldService.travel(player: Player, destKey: string): boolean
    local destCfg = TravelConfig.destinations[destKey]
    if destCfg == nil then
        warn("[WorldService] unknown travel destination: " .. tostring(destKey))
        return false
    end

    local def = WorldConfig.getPlace(destKey)
    if def == nil or not WorldConfig.isPlaceReady(destKey) then
        notify(player, "Destination not available yet.")
        warn(
            "[WorldService] destination not ready: "
                .. destKey
                .. " (placeId="
                .. tostring(def and def.placeId or "nil")
                .. ")"
        )
        return false
    end

    if isOnCooldown(player) then
        return false
    end

    -- GATE: persist current state durably BEFORE leaving. The destination loads
    -- from the DataStore, so an unsaved teleport = rolled-back progress.
    local saved = PlayerDataService.save(player, { force = true })
    if not saved then
        notify(player, "Failed to save progress — try again in a moment.")
        warn("[WorldService] force-save failed pre-teleport for " .. player.Name)
        return false
    end

    local options = Instance.new("TeleportOptions")
    options:SetTeleportData({ from = WorldConfig.currentPlaceKind(), intent = destKey })

    -- PRIVATE destination: reserve a fresh per-player server. The base rebuilds
    -- from the persisted profile on arrival, so a new reserved server per trip is
    -- still the player's own private Sanctuary.
    if destCfg.reserved then
        local okReserve, accessCode = pcall(function()
            return TeleportService:ReserveServer(def.placeId)
        end)
        if not okReserve or type(accessCode) ~= "string" then
            notify(player, "Failed to prepare private server — try again.")
            warn("[WorldService] ReserveServer failed for " .. destKey .. ": " .. tostring(accessCode))
            return false
        end
        options.ReservedServerAccessCode = accessCode
    end

    notify(player, destCfg.loadingText)

    -- TeleportAsync can fail transiently (rate limit / flooded); retry per
    -- WorldConfig.teleport.retry. Async failures surface via TeleportInitFailed
    -- (wired in the bootstrap), which re-notifies the player.
    local attempts = 1 + math.max(WorldConfig.teleport.retry, 0)
    for attempt = 1, attempts do
        local ok, err = pcall(function()
            TeleportService:TeleportAsync(def.placeId, { player }, options)
        end)
        if ok then
            return true
        end
        warn(
            ("[WorldService] TeleportAsync failed (%d/%d) -> %s: %s"):format(attempt, attempts, destKey, tostring(err))
        )
        if attempt < attempts then
            task.wait(1)
        end
    end

    notify(player, "Teleport failed. Try again in a moment.")
    return false
end

-- Best-effort cleanup of the debounce map on leave.
Players.PlayerRemoving:Connect(function(player)
    lastTravelClock[player] = nil
end)

return WorldService
