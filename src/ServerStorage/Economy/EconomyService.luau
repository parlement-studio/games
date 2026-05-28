--!strict
-- ServerStorage/Economy/EconomyService.luau
--
-- The Economy / Currency (Meme Coins) service for Brainrot Inc., per
-- design/gdd/economy-gdd.md (v1.2). SERVER-ONLY, server-authoritative. Every
-- coin mutation in the entire game routes through award() or spend() here; no
-- consumer touches `data.coins` or DataStoreService directly.
--
-- LIFECYCLE (economy-gdd §2):
--   * Wallet API mutates via PlayerDataService.update() — the SINGLE atomic
--     mutation path (persistence v1.4 §2.3 / ADR-001). One in-memory commit per
--     mutation; rollback on mutator error (E10).
--   * Idempotency keys (txLog) prevent double-credit on retry / receipt replay
--     (E5). Required for raid_loot / quest_daily / field_combat_win /
--     devproduct_pack; recommended for capture; optional elsewhere.
--   * `stats.totalCoinsEarned` is incremented on EVERY credit and is NEVER
--     decremented by a sink — it is the leaderboard "net worth" metric
--     (persistence-gdd §2.6, LOCKED). Leaderboard #16 reads it via the
--     OrderedDataStore write piggybacked on the normal save (F-LEADERBOARD-WRITE,
--     handled by Persistence when totalCoinsEarned changed since last save).
--
-- KEY DISCIPLINE (.claude/rules/server-scripts.md, NON-NEGOTIABLE):
--   * Server is authoritative for every coin value. Client may MIRROR `coins`
--     for HUD display but the server is the price authority on every spend.
--   * Every award / spend reason is checked against the audit whitelists in
--     EconomyConfig — an unknown reason is rejected (E7), preventing typo'd
--     reasons from minting coins under unknown audit categories.
--   * Every amount must be a positive integer >= EconomyConfig.minMutation (E8).
--   * Pcall not strictly needed here (PlayerDataService.update is pcall-wrapped
--     internally), but a mutator-error result is treated as a hard failure that
--     leaves the live profile untouched (rollback).
--
-- BOUNDARY:
--   * Persistence #1 owns storage + atomic write path + idempotency log + the
--     in-memory CoinsChanged signal contract. Economy uses them.
--   * Capture #4 owns captureCostCoins (authoritative); Economy mirrors as
--     captureCostCoins_REFERENCE for the inflation model only.
--   * Raid #6 owns targetPool / raidLootPct; Economy only credits the resulting
--     loot via award.
--   * Pet AI #25 owns winCoins; Economy only credits via award with the
--     pairing-based idemKey "fcw:fighterId:wildId" (economy-gdd v1.2 §3.1).
--   * Reroll #11 owns the 24h reset state (which tier `k` a Brainrot is on);
--     Economy supplies rerollCost(k) and the spend.
--   * Idle #3 / Persistence persist upgrade levels (factoryLevel / etc.);
--     Economy reads `n` and supplies upgradeCost(track, n) + the spend.
--   * Monetization #15 owns DevProduct SKUs + ProcessReceipt grants; Economy
--     supplies the award entry point and the idempotency layer (the durable
--     consumedReceipts marker lives in persistence v1.4 §2.3a; ProcessReceipt
--     calls processReceiptGrant directly, not Economy.award).
--
-- The PlayerDataService dependency is INJECTABLE (setPlayerDataService) so
-- tests use a MOCK without touching the real atomic path. Logger is also
-- injectable for structured incident reporting.

local EconomyService = {}

-- ── DI handles (overridable for tests) ───────────────────────────────────────

-- The PlayerDataService module. Default is required lazily on first use so
-- tests can swap it via setPlayerDataService before any wallet call.
local playerDataService: any = nil

-- A CaptureConfig view for the capture-cost cross-reference at spend time
-- (single source of truth lives in CaptureConfig, not in EconomyConfig). Lazy.
local captureConfig: any = nil

-- Optional structured logger (incidents: invalid_reason, insufficient_funds,
-- balance_cap_hit, mutator_error). Replace with the project logger when one
-- exists; never raw print for incidents.
local logger: ((event: string, payload: { [string]: any }) -> ())? = nil

-- The EconomyConfig (lazy-required so a test can inject a fake config table
-- before first use — though normally the singleton is fine).
local EconomyConfig: any = nil

local function getPlayerDataService(): any
    if playerDataService == nil then
        local ServerStorage = game:GetService("ServerStorage")
        playerDataService = require(ServerStorage.PlayerData.PlayerDataService)
    end
    return playerDataService
end

local function getCaptureConfig(): any
    if captureConfig == nil then
        local ReplicatedStorage = game:GetService("ReplicatedStorage")
        captureConfig = require(ReplicatedStorage.Shared.Config.CaptureConfig)
    end
    return captureConfig
end

local function getEconomyConfig(): any
    if EconomyConfig == nil then
        local ReplicatedStorage = game:GetService("ReplicatedStorage")
        EconomyConfig = require(ReplicatedStorage.Shared.Config.EconomyConfig)
    end
    return EconomyConfig
end

local function log(event: string, payload: { [string]: any })
    if logger then
        logger(event, payload)
    end
end

-- ── Public API: dependency injection (tests / wiring) ───────────────────────

-- Inject a (mock) PlayerDataService for tests. Pass nil to revert to the real one.
function EconomyService.setPlayerDataService(svc: any)
    playerDataService = svc
end

-- Inject a (mock) CaptureConfig for tests.
function EconomyService.setCaptureConfig(cfg: any)
    captureConfig = cfg
end

-- Inject a (mock) EconomyConfig for tests.
function EconomyService.setEconomyConfig(cfg: any)
    EconomyConfig = cfg
end

-- Inject a structured logger.
function EconomyService.setLogger(fn: (event: string, payload: { [string]: any }) -> ())
    logger = fn
end

-- ── Public API: queries (read-only) ─────────────────────────────────────────

-- Current Meme Coins balance for a player. Returns nil if profile not loaded.
function EconomyService.getBalance(player: Player): number?
    local pds = getPlayerDataService()
    local data = pds.getData(player)
    return if data then data.coins else nil
end

-- The LEADERBOARD net-worth value (lifetime gross coins earned, monotonic
-- non-decreasing). Returns nil if profile not loaded. NEVER subtract from this
-- in any code path — it is the Richest Manager leaderboard signal
-- (persistence-gdd §2.6, LOCKED).
function EconomyService.getNetWorth(player: Player): number?
    local pds = getPlayerDataService()
    local data = pds.getData(player)
    return if data then data.stats.totalCoinsEarned else nil
end

-- Current premium Brain Cells balance (Phase 2). Provisioned default 0;
-- unused at launch (no faucet/sink in v1). Returns nil if profile not loaded.
function EconomyService.getGems(player: Player): number?
    local pds = getPlayerDataService()
    local data = pds.getData(player)
    return if data then data.gems else nil
end

-- Affordability check for a SPECIFIC spend. Returns true if the profile is
-- loaded AND coins >= amount. Returns false on missing profile / invalid input.
-- THIS IS A HINT, NOT A GATE — the actual spend re-checks server-side; a
-- client-trusted affordability gate would be an exploit (E4 / E7).
function EconomyService.canAfford(player: Player, amount: number): boolean
    if typeof(amount) ~= "number" or amount ~= amount then -- NaN guard
        return false
    end
    local pds = getPlayerDataService()
    local data = pds.getData(player)
    if data == nil then
        return false
    end
    return data.coins >= amount
end

-- The authoritative cost of an upgrade level (server price). Convenience
-- accessor over EconomyConfig.upgradeCost; identical behavior, kept here so
-- shop UIs can read prices through EconomyService without depending on Config.
function EconomyService.getUpgradeCost(track: string, level: number): number
    local cfg = getEconomyConfig()
    return cfg.upgradeCost(track, level)
end

-- The authoritative cost of the k-th paid slot unlock.
function EconomyService.getSlotUnlockCost(k: number): number
    local cfg = getEconomyConfig()
    return cfg.slotUnlockCost(k)
end

-- The authoritative cost of the k-th reroll on a Brainrot (k is 1-based).
function EconomyService.getRerollCost(k: number): number
    local cfg = getEconomyConfig()
    return cfg.rerollCost(k)
end

-- The authoritative capture cost (read from CaptureConfig — single source of
-- truth). Mirrored in EconomyConfig.captureCostCoins_REFERENCE for audit/model
-- only; this accessor returns the live CaptureConfig value.
function EconomyService.getCaptureCost(): number
    local cap = getCaptureConfig()
    -- CaptureConfig.captureCostCoins is the canonical name (capture-gdd §8.2).
    -- Defensive fallback to the reference mirror if Capture's field is missing
    -- (e.g. a stripped test fixture).
    if typeof(cap) == "table" and typeof(cap.captureCostCoins) == "number" then
        return cap.captureCostCoins
    end
    local cfg = getEconomyConfig()
    return cfg.captureCostCoins_REFERENCE
end

-- ── Internal: validated mutation helpers ────────────────────────────────────

-- Normalizes / validates a coin amount before a mutation. Returns the floor'd
-- positive integer amount, or nil + an error string on a defect.
local function validateAmount(amount: number): (number?, string?)
    if typeof(amount) ~= "number" or amount ~= amount then -- NaN
        return nil, "invalid_amount"
    end
    if amount <= 0 then
        return nil, "invalid_amount" -- E8: 0/negative rejected
    end
    local cfg = getEconomyConfig()
    if amount < cfg.minMutation then
        return nil, "below_min_mutation"
    end
    -- Floor — every coin amount is integer at rest (economy-gdd §8 units note).
    local floored = math.floor(amount)
    return floored, nil
end

-- ── Public API: award (credit coins via atomic update) ──────────────────────
--
-- Credits `amount` Meme Coins to `player`'s wallet. The amount is also added
-- to `stats.totalCoinsEarned` (monotonic non-decreasing — the leaderboard
-- value). Fires PlayerDataService.CoinsChanged on a successful commit.
--
-- The `reason` MUST be one of EconomyConfig.faucetReasons (audit whitelist).
-- The `idempotencyKey` is OPTIONAL but STRONGLY recommended for any source
-- where re-fire is plausible (raid_loot / quest_daily / field_combat_win /
-- devproduct_pack). A replay returns the prior stored result (no double-credit).
--
-- Returns (ok, result):
--   * (true, { newBalance, delta })   — committed; newBalance reflects the cap
--                                       (if maxBalance was hit, delta may be
--                                       less than `amount` and overflow_logged).
--   * (true, storedResult)            — idempotent replay; the prior commit stands.
--   * (false, "not_loaded")           — profile not loaded; no mutation.
--   * (false, "invalid_reason")       — reason not in faucetReasons whitelist.
--   * (false, "invalid_amount")       — amount is nil / NaN / 0 / negative.
--   * (false, "below_min_mutation")   — amount < EconomyConfig.minMutation.
--   * (false, "mutation_error")       — the mutator threw inside the atomic
--                                       path; the live profile is unchanged.
function EconomyService.award(player: Player, amount: number, reason: string, idempotencyKey: string?): (boolean, any)
    -- Reason validation (E7 — unknown reasons cannot mint).
    local cfg = getEconomyConfig()
    if typeof(reason) ~= "string" or not cfg.isFaucetReason(reason) then
        log("economy_invalid_award_reason", {
            userId = player.UserId,
            reason = tostring(reason),
            amount = amount,
        })
        return false, "invalid_reason"
    end

    -- Amount validation (E8).
    local amt, amtErr = validateAmount(amount)
    if amt == nil then
        return false, amtErr
    end

    -- Loaded-profile gate (avoid the atomic path's not_loaded path so the error
    -- surfaces synchronously to the caller for analytics).
    local pds = getPlayerDataService()
    if not pds.isLoaded(player) then
        return false, "not_loaded"
    end

    -- Atomic mutation. The mutator caps at maxBalance and reports overflow.
    local ok, result, replayed = pds.update(player, function(data)
        -- maxBalance cap (E2): clamp to avoid overflow; report any discarded
        -- portion so callers (and the logger) can see it.
        local headroom = math.max(0, cfg.maxBalance - data.coins)
        local credited = math.min(amt :: number, headroom)
        local overflowDiscarded = (amt :: number) - credited

        data.coins = data.coins + credited
        data.stats.totalCoinsEarned = data.stats.totalCoinsEarned + credited

        return {
            newBalance = data.coins,
            delta = credited,
            overflowDiscarded = overflowDiscarded,
            reason = reason,
            netWorth = data.stats.totalCoinsEarned,
        }
    end, idempotencyKey)

    if not ok then
        log("economy_award_failed", {
            userId = player.UserId,
            reason = reason,
            amount = amt,
            error = tostring(result),
        })
        return false, result
    end

    -- On a fresh commit (not a replay), fire the cross-system signal so Moment
    -- / Leaderboard / UI can react. On an idempotent replay, the prior commit
    -- already fired its signal — we do NOT re-fire (no double Moment).
    if not replayed then
        -- result is the table the mutator returned.
        if
            typeof(result) == "table"
            and typeof(result.overflowDiscarded) == "number"
            and result.overflowDiscarded > 0
        then
            log("economy_award_overflow", {
                userId = player.UserId,
                reason = reason,
                requested = amt,
                credited = result.delta,
                discarded = result.overflowDiscarded,
                newBalance = result.newBalance,
            })
        end
        pds.CoinsChanged:Fire(player, result.newBalance, result.delta, reason)
    end

    return true, result
end

-- ── Public API: spend (debit coins via atomic update) ───────────────────────
--
-- Debits `amount` Meme Coins from `player`'s wallet. Does NOT touch
-- `stats.totalCoinsEarned` — that field is monotonic non-decreasing
-- (the leaderboard signal). Fires PlayerDataService.CoinsChanged on a
-- successful commit.
--
-- The `reason` MUST be one of EconomyConfig.sinkReasons (audit whitelist).
-- The `idempotencyKey` is OPTIONAL; recommended for retried spend flows
-- (a UI that may re-fire a "Buy" tap during lag).
--
-- Returns (ok, result):
--   * (true, { newBalance, delta })   — committed.
--   * (true, storedResult)            — idempotent replay; the prior commit stands.
--   * (false, "not_loaded")
--   * (false, "invalid_reason")
--   * (false, "invalid_amount")
--   * (false, "below_min_mutation")
--   * (false, "insufficient_funds")   — coins < amount; no mutation, no log noise.
--   * (false, "mutation_error")
function EconomyService.spend(player: Player, amount: number, reason: string, idempotencyKey: string?): (boolean, any)
    local cfg = getEconomyConfig()
    if typeof(reason) ~= "string" or not cfg.isSinkReason(reason) then
        log("economy_invalid_spend_reason", {
            userId = player.UserId,
            reason = tostring(reason),
            amount = amount,
        })
        return false, "invalid_reason"
    end

    local amt, amtErr = validateAmount(amount)
    if amt == nil then
        return false, amtErr
    end

    local pds = getPlayerDataService()
    if not pds.isLoaded(player) then
        return false, "not_loaded"
    end

    -- Pre-mutation affordability hint to early-return without the deep-copy
    -- cost. The real check is INSIDE the mutator (single source of truth);
    -- this is an optimization + the only place to return a clean
    -- "insufficient_funds" without spamming the mutation_error path.
    local data = pds.getData(player)
    if data and data.coins < (amt :: number) then
        return false, "insufficient_funds"
    end

    local ok, result, replayed = pds.update(player, function(profile)
        -- Re-check inside the atomic boundary — defends against a race
        -- where two spends slip through the pre-check on the same tick.
        if profile.coins < (amt :: number) then
            -- ERROR pattern: errors discard the mutation (no partial state).
            -- The update() contract catches this via pcall and returns
            -- (false, "mutation_error"); we translate that back to
            -- "insufficient_funds" at the call site below.
            error("insufficient_funds")
        end
        profile.coins = profile.coins - (amt :: number)
        return {
            newBalance = profile.coins,
            delta = -(amt :: number),
            reason = reason,
        }
    end, idempotencyKey)

    if not ok then
        -- Translate the rare mutator-throw race back to a clean signal.
        if result == "mutation_error" then
            return false, "insufficient_funds"
        end
        log("economy_spend_failed", {
            userId = player.UserId,
            reason = reason,
            amount = amt,
            error = tostring(result),
        })
        return false, result
    end

    if not replayed then
        pds.CoinsChanged:Fire(player, result.newBalance, result.delta, reason)
    end

    return true, result
end

-- ── Public API: convenience faucet wrappers ─────────────────────────────────

-- F-FAUCET-QUEST — rolls a uniform-integer reward in the per-type {min,max}
-- range and credits via award(); the questId is REQUIRED as the idempotency
-- key (one payout per quest, E5). Returns the same shape as award().
function EconomyService.grantQuestReward(
    player: Player,
    questType: string,
    questId: string,
    rng: ((min: number, max: number) -> number)?
): (boolean, any)
    if typeof(questId) ~= "string" or questId == "" then
        return false, "invalid_quest_id"
    end
    local cfg = getEconomyConfig()
    local range = cfg.questRewards[questType]
    local amount: number
    if range == nil then
        amount = cfg.questRewardFallbackCoins
    else
        local rnd = if rng ~= nil then rng else math.random
        amount = rnd(range.min, range.max)
    end
    return EconomyService.award(player, amount, "quest_daily", "quest_daily:" .. questId)
end

-- F-FAUCET-REWARD — fallback generic positive reward (codes / FTUE / small
-- moments / redemptions). Source supplies the optional amount (or nil =
-- default rewardGenericCoins). idemKey REQUIRED to dedupe code redemptions
-- (E5: a player retrying a code cannot double-grant).
function EconomyService.grantGenericReward(player: Player, amount: number?, idempotencyKey: string): (boolean, any)
    if typeof(idempotencyKey) ~= "string" or idempotencyKey == "" then
        return false, "invalid_idem_key"
    end
    local cfg = getEconomyConfig()
    local amt = if typeof(amount) == "number" then amount else cfg.rewardGenericCoins
    return EconomyService.award(player, amt, "reward_generic", "reward_generic:" .. idempotencyKey)
end

return EconomyService
