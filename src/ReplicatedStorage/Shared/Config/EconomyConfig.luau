--!strict
-- Shared/Config/EconomyConfig.luau
--
-- Tuning table for the Economy / Currency system (Meme Coins), per
-- design/gdd/economy-gdd.md (v1.2) §8. Edited by DESIGNERS for balance.
--
-- Consumers (Capture #4 reference only — see captureCostCoins_REFERENCE; Idle
-- Production #3, Raid #6, Reroll #11, Auto-Catch #10, Daily Quests #17, Field
-- Combat / Pet AI #25, Monetization #15, Leaderboard #16, UI/HUD #13) READ this
-- table; they NEVER hardcode coin values. EconomyService consumes the helper
-- formulas (upgradeCost / slotUnlockCost / rerollCost) — no caller computes a
-- cost curve in-line.
--
-- AUTHORITY (economy-gdd §4, locked): all RESOLUTION values (faucet amounts,
-- sink curves, idempotency reason whitelists) are read SERVER-SIDE only. The
-- client may mirror this table read-only so shops can render PREVIEW prices;
-- the server re-reads authoritative cost at spend time (E7). A tampered client
-- cannot name an amount — EconomyService.spend rejects mismatched intents.
--
-- This module is in ReplicatedStorage (per shared-modules rules) because it
-- holds NO secrets: pure tuning data + pure validator + pure curve helpers.
-- The wallet-mutation logic lives in EconomyService (ServerStorage), which
-- routes every write through PlayerDataService's atomic `update()` path with
-- idempotency keys (persistence v1.4 §2.3 / economy-gdd §2.3).
--
-- BOUNDARY (no contradictions introduced):
--   * Capture cost is OWNED by `CaptureConfig.captureCostCoins`. The value below
--     (captureCostCoins_REFERENCE) is a MIRROR for the inflation model + audit
--     only — the authoritative value lives in CaptureConfig. EconomyService
--     reads CaptureConfig directly on a capture spend (single source of truth).
--   * Raid loot `targetPool` + `raidLootPct` are OWNED by Raid #6's config —
--     not duplicated here. Economy only credits the resulting `loot` amount.
--   * Pet AI #25 `winCoins` is OWNED by PetCombatConfig (currently
--     DemoConfig.combat.winCoins). Economy only credits via award.
--   * DevProduct grant tiers are OWNED by Monetization #15.
--   * Upgrade LEVELS persist in `base.buildings[*].{factoryLevel,workerSlotLevel,
--     storageLevel}` (Idle #3 / Persistence v1.4 §3.2a). Economy reads `n` from
--     persistence and supplies `cost(n)`; Idle is the level-write owner.
--
-- Schema version: 1 (matches the `version` field below).

local EconomyConfig = {}

-- ── PUBLIC TYPES ─────────────────────────────────────────────────────────────

-- A faucet reward range: a coin reward is rolled uniformly in [min, max].
-- min <= max enforced by validate(); both are integer coin amounts.
export type RewardRange = {
    min: number,
    max: number,
}

-- An upgrade track: geometric cost curve cost(n) = floor(base * growth^n).
-- See §8.4 F-SINK-UPGRADE; helper: EconomyConfig.upgradeCost(track, n).
export type UpgradeTrack = {
    base: number,
    growth: number,
    maxLevel: number,
}

-- The roster-slot unlock track: geometric curve like upgrades, plus the
-- starting-slots seed and the hard rosterCap (matches persistence rosterCap).
-- See §8.6 F-SINK-SLOT-UNLOCK; helper: EconomyConfig.slotUnlockCost(k).
export type SlotUnlockTrack = {
    base: number,
    growth: number,
    slotsPerUnlock: number,
    startingSlots: number,
    rosterCap: number,
}

-- The Reroll cost ladder + 24h reset. LOCKED tier values per monetization
-- brainstorm: never retune (changing them is a design decision, not config tweak).
-- See §8.5 F-SINK-REROLL; helper: EconomyConfig.rerollCost(k).
export type RerollTrack = {
    costs: { number },
    resetHours: number,
}

-- Display suffix table: largest-first, format big numbers as "1.2K", "3.4M",
-- "5.6B", "7.8T". Pure display, never used for resolution math. Each entry is
-- {threshold, suffix}; the first whose threshold <= value wins.
export type DisplaySuffix = { number | string }

-- The full config table type — what `return EconomyConfig` resolves to.
export type EconomyConfigType = {
    version: number,
    maxBalance: number,
    minMutation: number,
    questRewards: { [string]: RewardRange },
    questRewardFallbackCoins: number,
    rewardGenericCoins: number,
    faucetReasons: { string },
    captureCostCoins_REFERENCE: number,
    raidSendCostCoins: number,
    dramaFixCostCoins: number,
    sinkReasons: { string },
    upgrades: { [string]: UpgradeTrack },
    slotUnlock: SlotUnlockTrack,
    reroll: RerollTrack,
    displaySuffixes: { DisplaySuffix },
    -- Helpers (pure functions; pre-validate raw values internally; ALL callers
    -- pass server-authoritative `n` / `k` from persisted state, never client).
    upgradeCost: (track: string, n: number) -> number,
    slotUnlockCost: (k: number) -> number,
    rerollCost: (k: number) -> number,
    formatCoins: (value: number) -> string,
    isFaucetReason: (reason: string) -> boolean,
    isSinkReason: (reason: string) -> boolean,
    isUpgradeTrack: (track: string) -> boolean,
    validate: (logger: ((event: string, payload: { [string]: any }) -> ())?) -> EconomyConfigType,
}

-- ── CONFIG VALUES (the master table — what designers edit) ───────────────────

EconomyConfig.version = 1

-- ── GLOBAL GUARDS ────────────────────────────────────────────────────────────

-- Hard ceiling on `coins` / `totalCoinsEarned` (E2). Doubles are exact to 2^53
-- (~9e15); we cap WELL below that. Should be unreachable given the sink curves
-- below — safety net only. Range: 1e9-9e15 | Default: 1e15 (one quadrillion).
EconomyConfig.maxBalance = 1e15

-- Minimum positive amount a single spend/award may charge (rejects 0/negative,
-- E8). Range: 1-100 | Default: 1
EconomyConfig.minMutation = 1

-- ── FAUCETS (Economy-owned values; idle/raid/field amounts computed elsewhere)

-- Daily Quests (#17) reward POOL, keyed by quest type. Paid ON QUEST COMPLETION.
-- Economy owns the {min,max} ranges; Daily Quests #17 owns WHICH quests roll,
-- their progress targets, the 3-per-day count, and the server-clock daily reset.
-- On completion, Economy rolls a coin reward uniformly in [min, max]
-- (§8.2, F-FAUCET-QUEST).
--
-- Pacing intent: a single quest ≈ one early-game upgrade's worth; a full
-- 3-quest day ≈ a few upgrades — meaningful but not eclipsing idle as the
-- primary faucet.
-- Each range: 0-100000 (min <= max).
EconomyConfig.questRewards = {
    capture_n = { min = 100, max = 200 }, -- "tangkap N Brainrot"
    win_raids = { min = 150, max = 300 }, -- "menang M raid"
    collect_x = { min = 100, max = 200 }, -- "kumpulkan X coins"
    evolve_one = { min = 200, max = 350 }, -- "evolve 1 Brainrot" (rarer goal, higher pay)
}

-- Fallback flat reward if a quest type has no range entry (defensive default,
-- e.g. a new quest type ships before its range is added). Used by F-FAUCET-QUEST.
-- Range: 0-100000 | Default: 150
EconomyConfig.questRewardFallbackCoins = 150

-- Generic positive reward fallback (codes, FTUE gift, small moment payout,
-- redeem). Used by F-FAUCET-REWARD when a source does not supply its own
-- amount. Range: 0-100000 | Default: 50
EconomyConfig.rewardGenericCoins = 50

-- Allowed faucet reason strings (audit / analytics whitelist). EconomyService
-- REJECTS award() calls whose reason is not in this set, so a typo'd reason
-- (or a tampered call) cannot mint coins under an unknown audit category.
-- Adding a new faucet = adding a string here AND the corresponding source.
EconomyConfig.faucetReasons = {
    "idle_collect", -- Idle Production #3 (PRIMARY)
    "raid_loot", -- Raid #6 (turn-based win)
    "field_combat_win", -- Field Combat / Pet AI #25 (real-time win, v1.2 added)
    "quest_daily", -- Daily Quests #17 (per-quest completion)
    "reward_generic", -- codes / FTUE / moments / one-off rewards
    "devproduct_pack", -- Monetization #15 (Robux pack)
}

-- ── FLAT SINKS ───────────────────────────────────────────────────────────────

-- Capture cost is OWNED BY CaptureConfig.captureCostCoins (default 25). MIRRORED
-- here for the economy model ONLY; the authoritative value lives in CaptureConfig
-- (capture-gdd §8.2). DO NOT edit here to change capture cost — edit CaptureConfig.
-- Listed for the inflation model + audit. validate() warns on mismatch with
-- CaptureConfig at boot.
EconomyConfig.captureCostCoins_REFERENCE = 25

-- Cost to send a raid team of 3 (per attempt). Gates raid spam; a per-attempt
-- sink. Tuned so a successful raid's expected loot comfortably exceeds it
-- (positive but not free) — see §8.3 F-FAUCET-RAID EV note.
-- Range: 0-100000 | Default: 100
EconomyConfig.raidSendCostCoins = 100

-- OPTIONAL drama/Walkout instant-fix cost. ALWAYS has a free "wait it out"
-- alternative (ethics lock — see economy-gdd §1 / §4 / §9 #23). Provisioned now;
-- consumed by Drama Events #23 (Phase 2). Range: 0-100000 | Default: 200
EconomyConfig.dramaFixCostCoins = 200

-- Allowed sink reason strings (audit / analytics whitelist). EconomyService
-- REJECTS spend() calls whose reason is not in this set.
EconomyConfig.sinkReasons = {
    "capture", -- Capture #4 (atomic with roster write)
    "upgrade_factory", -- Idle #3 (geometric curve)
    "upgrade_worker_slot", -- Idle #3 (geometric curve)
    "upgrade_storage", -- Idle #3 (geometric curve)
    "raid_send", -- Raid #6 (per-attempt)
    "reroll", -- Reroll #11 (capped escalating)
    "slot_unlock", -- Roster slot unlock (gentle geometric)
    "drama_fix", -- Drama Events #23 (P2; ALWAYS has free alternative)
}

-- ── UPGRADE CURVES (geometric; the PRIMARY inflation absorber, §8.4/§8.9) ────
-- cost(n) = floor(base * growth^n) for n in [0, maxLevel-1].
-- See §8.4 F-SINK-UPGRADE and EconomyConfig.upgradeCost(track, n).
EconomyConfig.upgrades = {
    factory = {
        -- Base cost of the FIRST factory upgrade (n=0). Range: 50-100000 | Default: 200
        base = 200,
        -- Geometric growth per level. > 1. Higher = steeper wall = stronger sink.
        -- Range: 1.10-2.00 | Default: 1.35 (each upgrade ~35% pricier than the last)
        growth = 1.35,
        -- Max purchasable levels (curve cap; prestige beyond is Phase 2).
        -- Range: 5-100 | Default: 30
        maxLevel = 30,
    },
    workerSlot = {
        -- Base cost to open the FIRST extra worker slot in a factory (n=0).
        -- Range: 50-100000 | Default: 150
        base = 150,
        -- Range: 1.10-2.00 | Default: 1.50 (slots are powerful; steeper)
        growth = 1.50,
        -- Range: 1-50 | Default: 10
        maxLevel = 10,
    },
    storage = {
        -- Base cost of the FIRST storage upgrade (pending-pool cap; idle §2.6/§8.6
        -- locks this to pending-pool cap only — the 8h offline window is a
        -- separate Phase-2 monetization lever). n=0. Range: 50-100000 | Default: 300
        base = 300,
        -- Range: 1.10-2.00 | Default: 1.40
        growth = 1.40,
        -- Range: 1-50 | Default: 12
        maxLevel = 12,
    },
}

-- ── ROSTER SLOT UNLOCK CURVE (to hard cap 200; persistence rosterCap) ────────
-- cost(k) = floor(base * growth^k); grants `slotsPerUnlock` per unlock; gated by
-- rosterCap so the curve cannot grant past 200. See §8.6 F-SINK-SLOT-UNLOCK.
EconomyConfig.slotUnlock = {
    -- Base cost of the first PAID slot unlock (n=0). Early slots cheap; late slots dear.
    -- Range: 50-100000 | Default: 250
    base = 250,
    -- Range: 1.05-1.50 | Default: 1.20 (gentle; we WANT players to grow the roster)
    growth = 1.20,
    -- How many slots one unlock grants (batch so we don't sell 200 one-at-a-time).
    -- Range: 1-25 | Default: 5
    slotsPerUnlock = 5,
    -- Starting free roster capacity at profile creation.
    -- Range: 5-200 | Default: 25
    startingSlots = 25,
    -- Hard cap (matches persistence rosterCap = 200). Range: 50-200 | Default: 200
    rosterCap = 200,
}

-- ── REROLL CURVE (LOCKED by monetization brainstorm — DO NOT retune) ─────────
-- Per-Brainrot escalating Meme Coins cost; resets to tier 1 after 24h with no
-- reroll. Mechanic (which reroll # a Brainrot is on, the 24h timer) is OWNED by
-- Reroll #11; Economy owns only the COST VALUES here and the spend. Robux path
-- is Monetization #15.
EconomyConfig.reroll = {
    -- Cost ladder by reroll count on a given Brainrot (1st, 2nd, 3rd, 4th+).
    -- Index 4 is the FLAT CAP (4th and every subsequent reroll within 24h).
    -- LOCKED VALUES — changing them is a design decision, not free-tuning.
    costs = { 250, 600, 1200, 2000 },
    -- Hours of no-reroll inactivity after which a Brainrot's reroll tier resets
    -- to 1 (250). Range: 1-72 | Default: 24 (LOCKED)
    resetHours = 24,
}

-- ── DISPLAY ──────────────────────────────────────────────────────────────────

-- Number-suffix thresholds for the HUD (§8.7). Keeps big idle numbers readable.
-- Largest-first; the first whose threshold <= value wins. Pure display.
EconomyConfig.displaySuffixes = {
    { 1e12, "T" }, -- trillions
    { 1e9, "B" }, -- billions
    { 1e6, "M" }, -- millions
    { 1e3, "K" }, -- thousands
}

-- ── HELPERS (pure functions) ─────────────────────────────────────────────────

-- F-SINK-UPGRADE — cost of the n-th upgrade level on a given track.
-- Server-authoritative: callers pass `n` from PERSISTED state (Idle #3's
-- base.buildings[*].<track>Level); the client never names `n`. Out-of-range
-- inputs return math.huge so the spend is rejected as unaffordable (E7).
function EconomyConfig.upgradeCost(track: string, n: number): number
    local cfg = EconomyConfig.upgrades[track]
    if cfg == nil then
        return math.huge
    end
    -- Clamp negative n to 0 (defensive); n at or above maxLevel is "nothing left
    -- to buy" — return math.huge so spend fails the affordability check.
    if n < 0 then
        n = 0
    end
    if n >= cfg.maxLevel then
        return math.huge
    end
    return math.floor(cfg.base * cfg.growth ^ n)
end

-- F-SINK-SLOT-UNLOCK — cost of the k-th paid slot unlock (k=0 is the first
-- paid unlock; the starting roster cap is `startingSlots`, free).
-- Range cap: at the unlock that would push total slots over `rosterCap`,
-- return math.huge (E10 — slot cap reached).
function EconomyConfig.slotUnlockCost(k: number): number
    local cfg = EconomyConfig.slotUnlock
    if k < 0 then
        k = 0
    end
    local totalSlotsAfter = cfg.startingSlots + (k + 1) * cfg.slotsPerUnlock
    if totalSlotsAfter > cfg.rosterCap then
        return math.huge
    end
    return math.floor(cfg.base * cfg.growth ^ k)
end

-- F-SINK-REROLL — cost of the k-th reroll on a given Brainrot (k is 1-based).
-- k <= 0 returns the first-tier cost (defensive); k >= length returns the cap.
function EconomyConfig.rerollCost(k: number): number
    local costs = EconomyConfig.reroll.costs
    if k <= 0 then
        return costs[1]
    end
    local idx = math.min(k, #costs)
    return costs[idx]
end

-- Format a coin value for the HUD — picks the largest applicable suffix
-- (§8.7 / displaySuffixes). For values below the smallest threshold, returns
-- the integer rendered without a suffix. Output is PURE DISPLAY — never
-- used for resolution math.
function EconomyConfig.formatCoins(value: number): string
    if value < 0 then
        return "0"
    end
    for _, entry in ipairs(EconomyConfig.displaySuffixes) do
        local threshold = entry[1] :: number
        local suffix = entry[2] :: string
        if value >= threshold then
            -- One decimal place for K/M/B/T (e.g. "1.2K", "3.4M").
            local scaled = value / threshold
            return string.format("%.1f%s", scaled, suffix)
        end
    end
    return tostring(math.floor(value))
end

-- Audit-whitelist helpers. EconomyService.award/spend call these on every
-- mutation; an unknown reason is a programmer error (or a tampered call) and
-- the mutation is rejected.
function EconomyConfig.isFaucetReason(reason: string): boolean
    for _, allowed in ipairs(EconomyConfig.faucetReasons) do
        if allowed == reason then
            return true
        end
    end
    return false
end

function EconomyConfig.isSinkReason(reason: string): boolean
    for _, allowed in ipairs(EconomyConfig.sinkReasons) do
        if allowed == reason then
            return true
        end
    end
    return false
end

function EconomyConfig.isUpgradeTrack(track: string): boolean
    return EconomyConfig.upgrades[track] ~= nil
end

-- ── VALIDATE (boot-time, per .claude/rules/gameplay-systems.md) ──────────────
--
-- Runs once at boot (from EconomyBootstrap). Numeric values are CLAMPED into
-- their documented ranges; whitelists are required non-empty; reward ranges
-- have min <= max enforced; reroll.costs must be a 4-entry monotonic ladder.
-- On any defect, validate logs `economy_config_<defect>` with the offending
-- field + repair action and degrades to a safe default rather than crashing.
--
-- Returns the (validated, possibly repaired) config table for callers that
-- want a guaranteed-clean view; callers may also continue using EconomyConfig
-- directly since the table is mutated in place. Mirrors the PersonalityConfig
-- pattern (validate returns a defensively-cleaned view).
function EconomyConfig.validate(logger: ((event: string, payload: { [string]: any }) -> ())?): EconomyConfigType
    local function log(event: string, payload: { [string]: any })
        if logger then
            logger(event, payload)
        end
    end

    -- Clamp a numeric field into [lo, hi] with a default fallback; log on a
    -- repair so QA notices.
    local function clampInPlace(holder: any, key: string, lo: number, hi: number, default: number, label: string)
        local v = holder[key]
        if typeof(v) ~= "number" or v ~= v then -- NaN guard
            log("economy_config_invalid_number", { field = label, value = tostring(v), repaired = default })
            holder[key] = default
            return
        end
        if v < lo or v > hi then
            local repaired = math.clamp(v, lo, hi)
            log("economy_config_out_of_range", { field = label, value = v, lo = lo, hi = hi, repaired = repaired })
            holder[key] = repaired
        end
    end

    -- Version pin.
    if EconomyConfig.version ~= 1 then
        log("economy_config_version_mismatch", { actual = EconomyConfig.version, expected = 1 })
        EconomyConfig.version = 1
    end

    -- Global guards.
    clampInPlace(EconomyConfig, "maxBalance", 1e9, 9e15, 1e15, "maxBalance")
    clampInPlace(EconomyConfig, "minMutation", 1, 100, 1, "minMutation")
    EconomyConfig.minMutation = math.floor(EconomyConfig.minMutation)

    -- Quest reward ranges (each {min,max} with min <= max).
    for questType, range in pairs(EconomyConfig.questRewards) do
        if typeof(range) ~= "table" or typeof(range.min) ~= "number" or typeof(range.max) ~= "number" then
            log("economy_config_invalid_quest_range", { questType = questType, repaired = "fallback" })
            EconomyConfig.questRewards[questType] = {
                min = EconomyConfig.questRewardFallbackCoins,
                max = EconomyConfig.questRewardFallbackCoins,
            }
        else
            clampInPlace(range, "min", 0, 100000, 0, "questRewards." .. questType .. ".min")
            clampInPlace(range, "max", 0, 100000, 0, "questRewards." .. questType .. ".max")
            if range.min > range.max then
                log("economy_config_quest_range_inverted", {
                    questType = questType,
                    min = range.min,
                    max = range.max,
                    repaired = "swap",
                })
                range.min, range.max = range.max, range.min
            end
            range.min = math.floor(range.min)
            range.max = math.floor(range.max)
        end
    end

    clampInPlace(EconomyConfig, "questRewardFallbackCoins", 0, 100000, 150, "questRewardFallbackCoins")
    EconomyConfig.questRewardFallbackCoins = math.floor(EconomyConfig.questRewardFallbackCoins)
    clampInPlace(EconomyConfig, "rewardGenericCoins", 0, 100000, 50, "rewardGenericCoins")
    EconomyConfig.rewardGenericCoins = math.floor(EconomyConfig.rewardGenericCoins)

    -- Reason whitelists must be non-empty and string-only.
    local function validateReasonList(holder: any, key: string, fallback: { string }, label: string)
        local list = holder[key]
        if typeof(list) ~= "table" or #list == 0 then
            log("economy_config_empty_reason_list", { field = label, repaired = "fallback" })
            holder[key] = fallback
            return
        end
        for i, r in ipairs(list) do
            if typeof(r) ~= "string" or r == "" then
                log("economy_config_invalid_reason", { field = label, index = i, value = tostring(r) })
                table.remove(list, i)
            end
        end
        if #list == 0 then
            log("economy_config_empty_reason_list_after_purge", { field = label, repaired = "fallback" })
            holder[key] = fallback
        end
    end
    validateReasonList(
        EconomyConfig,
        "faucetReasons",
        { "idle_collect", "raid_loot", "field_combat_win", "quest_daily", "reward_generic", "devproduct_pack" },
        "faucetReasons"
    )
    validateReasonList(EconomyConfig, "sinkReasons", {
        "capture",
        "upgrade_factory",
        "upgrade_worker_slot",
        "upgrade_storage",
        "raid_send",
        "reroll",
        "slot_unlock",
        "drama_fix",
    }, "sinkReasons")

    -- Flat sinks.
    clampInPlace(EconomyConfig, "captureCostCoins_REFERENCE", 0, 100000, 25, "captureCostCoins_REFERENCE")
    EconomyConfig.captureCostCoins_REFERENCE = math.floor(EconomyConfig.captureCostCoins_REFERENCE)
    clampInPlace(EconomyConfig, "raidSendCostCoins", 0, 100000, 100, "raidSendCostCoins")
    EconomyConfig.raidSendCostCoins = math.floor(EconomyConfig.raidSendCostCoins)
    clampInPlace(EconomyConfig, "dramaFixCostCoins", 0, 100000, 200, "dramaFixCostCoins")
    EconomyConfig.dramaFixCostCoins = math.floor(EconomyConfig.dramaFixCostCoins)

    -- Upgrade tracks.
    local upgradeDefaults: { [string]: UpgradeTrack } = {
        factory = { base = 200, growth = 1.35, maxLevel = 30 },
        workerSlot = { base = 150, growth = 1.50, maxLevel = 10 },
        storage = { base = 300, growth = 1.40, maxLevel = 12 },
    }
    for trackName, defaults in pairs(upgradeDefaults) do
        local track = EconomyConfig.upgrades[trackName]
        if typeof(track) ~= "table" then
            log("economy_config_missing_upgrade_track", { track = trackName, repaired = "default" })
            EconomyConfig.upgrades[trackName] = {
                base = defaults.base,
                growth = defaults.growth,
                maxLevel = defaults.maxLevel,
            }
        else
            clampInPlace(track, "base", 50, 100000, defaults.base, "upgrades." .. trackName .. ".base")
            track.base = math.floor(track.base)
            clampInPlace(track, "growth", 1.10, 2.00, defaults.growth, "upgrades." .. trackName .. ".growth")
            clampInPlace(track, "maxLevel", 1, 100, defaults.maxLevel, "upgrades." .. trackName .. ".maxLevel")
            track.maxLevel = math.floor(track.maxLevel)
        end
    end

    -- Slot unlock.
    local slotUnlock = EconomyConfig.slotUnlock
    clampInPlace(slotUnlock, "base", 50, 100000, 250, "slotUnlock.base")
    slotUnlock.base = math.floor(slotUnlock.base)
    clampInPlace(slotUnlock, "growth", 1.05, 1.50, 1.20, "slotUnlock.growth")
    clampInPlace(slotUnlock, "slotsPerUnlock", 1, 25, 5, "slotUnlock.slotsPerUnlock")
    slotUnlock.slotsPerUnlock = math.floor(slotUnlock.slotsPerUnlock)
    clampInPlace(slotUnlock, "startingSlots", 5, 200, 25, "slotUnlock.startingSlots")
    slotUnlock.startingSlots = math.floor(slotUnlock.startingSlots)
    clampInPlace(slotUnlock, "rosterCap", 50, 200, 200, "slotUnlock.rosterCap")
    slotUnlock.rosterCap = math.floor(slotUnlock.rosterCap)
    if slotUnlock.startingSlots > slotUnlock.rosterCap then
        log("economy_config_starting_slots_above_cap", {
            startingSlots = slotUnlock.startingSlots,
            rosterCap = slotUnlock.rosterCap,
            repaired = "clamp",
        })
        slotUnlock.startingSlots = slotUnlock.rosterCap
    end

    -- Reroll ladder — LOCKED 4-entry monotonic non-decreasing.
    local rerollDefaults = { 250, 600, 1200, 2000 }
    local reroll = EconomyConfig.reroll
    if typeof(reroll.costs) ~= "table" or #reroll.costs == 0 then
        log("economy_config_reroll_costs_missing", { repaired = "default" })
        reroll.costs = rerollDefaults
    else
        -- Pad / truncate to 4 entries; clamp each value into a sane range.
        for i = 1, 4 do
            local v = reroll.costs[i]
            if typeof(v) ~= "number" or v <= 0 then
                log(
                    "economy_config_reroll_cost_invalid",
                    { index = i, value = tostring(v), repaired = rerollDefaults[i] }
                )
                reroll.costs[i] = rerollDefaults[i]
            else
                reroll.costs[i] = math.floor(math.clamp(v, 1, 100000))
            end
        end
        -- Truncate any extra entries beyond 4.
        for i = #reroll.costs, 5, -1 do
            reroll.costs[i] = nil
        end
        -- Monotonic non-decreasing check (LOCKED ladder).
        for i = 2, 4 do
            if reroll.costs[i] < reroll.costs[i - 1] then
                log("economy_config_reroll_ladder_not_monotonic", {
                    index = i,
                    value = reroll.costs[i],
                    prev = reroll.costs[i - 1],
                    repaired = "raise_to_prev",
                })
                reroll.costs[i] = reroll.costs[i - 1]
            end
        end
    end
    clampInPlace(reroll, "resetHours", 1, 72, 24, "reroll.resetHours")
    reroll.resetHours = math.floor(reroll.resetHours)

    -- Display suffixes — must be non-empty + sorted largest-first; if mangled,
    -- reset to defaults (display polish, not load-bearing for resolution).
    local suffixDefaults = { { 1e12, "T" }, { 1e9, "B" }, { 1e6, "M" }, { 1e3, "K" } }
    if typeof(EconomyConfig.displaySuffixes) ~= "table" or #EconomyConfig.displaySuffixes == 0 then
        log("economy_config_display_suffixes_missing", { repaired = "default" })
        EconomyConfig.displaySuffixes = suffixDefaults
    else
        -- Verify sort largest-first; if not, replace with defaults.
        local sorted = true
        for i = 2, #EconomyConfig.displaySuffixes do
            local prev = EconomyConfig.displaySuffixes[i - 1][1] :: number
            local cur = EconomyConfig.displaySuffixes[i][1] :: number
            if cur > prev then
                sorted = false
                break
            end
        end
        if not sorted then
            log("economy_config_display_suffixes_unsorted", { repaired = "default" })
            EconomyConfig.displaySuffixes = suffixDefaults
        end
    end

    return EconomyConfig :: any
end

return EconomyConfig :: EconomyConfigType
