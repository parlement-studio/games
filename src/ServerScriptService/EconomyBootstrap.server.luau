--!strict
-- ServerScriptService/EconomyBootstrap.server.luau
--
-- Lifecycle wiring for the Economy / Currency (Meme Coins) system (#9), per
-- design/gdd/economy-gdd.md (v1.2) §5 / §6 / §9. Mirrors the style of
-- PlayerDataBootstrap + PersonalityBootstrap: this Script ONLY wires things
-- together — no game logic lives here.
--
-- Wiring:
--   boot                              -> EconomyConfig.validate() once (E7; log)
--   boot                              -> EconomyService.setLogger
--   PlayerDataService.CoinsChanged    -> BalanceChanged remote (thin S->C)
--   PlayerDataService.DataLoaded      -> initial BalanceChanged push to client
--
-- REMOTE CONTRACT (economy-gdd §5):
--   * BalanceChanged (S->C) — { newBalance: number, delta: number, reason: string,
--     netWorth: number? } — fired whenever the player's coins move. Client mirrors
--     for HUD display; the SERVER is the price authority on every spend (§4 / E7).
--   * SpendRejected  (S->C) — { reason: string, requested: number, code: string } —
--     fired when a server-side spend rejects (insufficient_funds / not_loaded /
--     invalid_reason / etc.) so the UI can show a kid-friendly toast ("Meme Coins
--     tidak cukup"). NOT every error code surfaces to the client; only spend
--     paths route through this remote (await wiring from consumers like Reroll,
--     Capture, Upgrades).
--
-- There is NO Client->Server remote for awarding or spending coins — both are
-- driven entirely by SERVER-OWNED systems (Idle Collect, Raid result, Pet AI
-- win, Quest completion, DevProduct grant). A client never names an amount or
-- a reason (§4 / E7 / E8). Shop UIs send IDENTIFIER-ONLY intents (e.g.
-- "buy upgrade_factory") which the consumer system validates + calls
-- EconomyService.spend with the server-authoritative cost.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local EconomyConfig = require(ReplicatedStorage.Shared.Config.EconomyConfig)
local EconomyService = require(ServerStorage.Economy.EconomyService)
local PlayerDataService = require(ServerStorage.PlayerData.PlayerDataService)

-- Structured logger (replace with the project logger when one exists; never
-- raw print for incidents). Routed into EconomyService + EconomyConfig.validate.
local function structuredLog(event: string, payload: { [string]: any })
    warn(string.format("[Economy] %s %s", event, HttpService:JSONEncode(payload)))
end
EconomyService.setLogger(structuredLog)

-- (1) Validate the config table ONCE at boot (E7). Any out-of-range fields are
-- repaired in-place + logged; an unknown reason in award/spend is rejected at
-- call time via the whitelists set up here.
local validated = EconomyConfig.validate(structuredLog)
structuredLog("economy_config_validated", {
    version = validated.version,
    maxBalance = validated.maxBalance,
    faucetReasonsCount = #validated.faucetReasons,
    sinkReasonsCount = #validated.sinkReasons,
    factoryBase = validated.upgrades.factory.base,
    factoryGrowth = validated.upgrades.factory.growth,
    factoryMaxLevel = validated.upgrades.factory.maxLevel,
    rerollCap = validated.reroll.costs[4],
})

-- ── Thin Server -> Client remotes (§5.1) ────────────────────────────────────
-- Pass-through surface; consumer UI listens client-side (UI/HUD #13).
local function ensureRemote(name: string): RemoteEvent
    local existing = ReplicatedStorage:FindFirstChild(name)
    if existing and existing:IsA("RemoteEvent") then
        return existing
    end
    local remote = Instance.new("RemoteEvent")
    remote.Name = name
    remote.Parent = ReplicatedStorage
    return remote
end

local balanceChanged = ensureRemote("BalanceChanged")
local spendRejected = ensureRemote("SpendRejected")

-- Expose the rejection remote to EconomyService callers via the EconomyService
-- module (no global; callers explicitly invoke spendRejected when a UI-visible
-- spend fails, NOT for every internal failure mode).
function EconomyService.fireSpendRejected(player: Player, payload: { [string]: any })
    -- Defensive: a missing Player or torn-down remote is a no-op (Studio hot
    -- reload, player who left mid-flow).
    if typeof(player) ~= "Instance" or not player:IsA("Player") then
        return
    end
    spendRejected:FireClient(player, payload)
end

-- ── CoinsChanged -> BalanceChanged (the "wallet moved" projection) ──────────
-- Every successful award/spend in EconomyService fires PlayerDataService.CoinsChanged
-- (the single in-memory "wallet moved" event). We forward it to the affected
-- player only — coin balances are PRIVATE (do not FireAllClients).
PlayerDataService.CoinsChanged:Connect(function(player: Player, newBalance: number, delta: number, reason: string)
    -- Defensive: a stale signal from a player whose profile is being torn down.
    if typeof(player) ~= "Instance" or not player:IsA("Player") then
        return
    end
    if player.Parent == nil then
        return
    end
    -- Pull netWorth from the live profile so a single round-trip carries both
    -- (the HUD shows balance; the leaderboard tag shows netWorth).
    local data = PlayerDataService.getData(player)
    local netWorth = if data then data.stats.totalCoinsEarned else nil
    balanceChanged:FireClient(player, {
        newBalance = newBalance,
        delta = delta,
        reason = reason,
        netWorth = netWorth,
    })
end)

-- ── DataLoaded -> initial BalanceChanged push (the FTUE "you have N coins") ─
-- On profile load, push the current balance once so the client HUD has a value
-- before the first faucet/sink fires. Delta = 0 + reason = "load" signals to
-- the UI that this is a state-sync, not a gain/spend animation.
PlayerDataService.DataLoaded:Connect(function(player: Player, data: any)
    if typeof(player) ~= "Instance" or not player:IsA("Player") then
        return
    end
    if data == nil then
        return
    end
    balanceChanged:FireClient(player, {
        newBalance = data.coins,
        delta = 0,
        reason = "load",
        netWorth = data.stats.totalCoinsEarned,
    })
end)

-- Catch any players already in-game before this script ran (Studio play-solo,
-- hot reload). We do NOT call DataLoaded directly (PlayerDataService is the
-- owner); instead we read the live profile and push the initial state if it
-- is already loaded.
for _, player in ipairs(Players:GetPlayers()) do
    local data = PlayerDataService.getData(player)
    if data then
        balanceChanged:FireClient(player, {
            newBalance = data.coins,
            delta = 0,
            reason = "load",
            netWorth = data.stats.totalCoinsEarned,
        })
    end
end

structuredLog("economy_bootstrap_ready", { boot = true })
