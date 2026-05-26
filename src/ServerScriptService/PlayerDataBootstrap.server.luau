--!strict
-- ServerScriptService/PlayerDataBootstrap.server.luau
--
-- Lifecycle wiring for Data Persistence & Roster Core (System #1), per
-- design/gdd/persistence-gdd.md (v1.2) §2.1 / §2.5 + .claude/rules/datastores.md
-- (BindToClose handler REQUIRED; PlayerRemoving alone is insufficient).
--
-- This Script ONLY wires events to PlayerDataService — no data logic lives
-- here. Wiring:
--   Players.PlayerAdded   -> PlayerDataService.load  (kick on failure, E1/E2/E8)
--   Players.PlayerRemoving-> PlayerDataService.onPlayerRemoving (save + release)
--   game:BindToClose      -> save ALL in parallel + release locks (25s budget)
--   autosave loop         -> debounced dirty-flag saves (~5 min while dirty)

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local PlayerDataService = require(ServerStorage.PlayerData.PlayerDataService)

-- Structured logger (replace with the project logger when one exists; never
-- raw print for incidents). Routed into PlayerDataService + SessionLock.
PlayerDataService.setLogger(function(event: string, payload: { [string]: any })
    warn(string.format("[Persistence] %s %s", event, game:GetService("HttpService"):JSONEncode(payload)))
end)

-- Handle a player joining: acquire lock + load + migrate + accrual. A nil
-- return (or a thrown load) means the load failed (lock held elsewhere / read
-- failed / migrate failed) and the player must be kicked — never dropped into a
-- blank profile that would overwrite a real save (E1/E2/E8). The load itself is
-- pcall-wrapped (ADR-001 H4): an unexpected throw kicks rather than silently
-- leaking a half-loaded session.
local function onPlayerAdded(player: Player)
    local ok, data = pcall(PlayerDataService.load, player)
    if not ok then
        warn(string.format("[Persistence] load threw for %d: %s", player.UserId, tostring(data)))
    end
    if not ok or data == nil then
        player:Kick("Your game is open in another place, or your save couldn't be loaded. Please rejoin in a moment.")
    end
end

-- Connect PlayerAdded BEFORE sweeping existing players (ADR-001 L4): a player
-- who joins during the sweep is still caught by the event, closing the join gap.
-- The `profiles` guard inside load() makes a double-load (sweep + event for the
-- same player) a safe no-op.
Players.PlayerAdded:Connect(onPlayerAdded)

-- Some players may already be in-game before this script runs (Studio
-- play-solo, hot reload). Handle them too.
for _, player in ipairs(Players:GetPlayers()) do
    task.spawn(onPlayerAdded, player)
end

Players.PlayerRemoving:Connect(function(player: Player)
    PlayerDataService.onPlayerRemoving(player)
end)

-- Start the debounced autosave loop (saves only dirty profiles, debounced).
PlayerDataService.startAutosave()

-- Shutdown guard: save all connected players in parallel + release their locks
-- within the BindToClose budget (E4). This is the race-condition guard
-- PlayerRemoving cannot provide on a server shutdown.
game:BindToClose(function()
    PlayerDataService.saveAllOnClose()
end)
