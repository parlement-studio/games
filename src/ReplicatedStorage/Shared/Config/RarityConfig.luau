--!strict
-- Shared/Config/RarityConfig.luau
--
-- Rarity System config, per design/decisions/2026-06-07-rarity-droprate.md
-- (R1-R5) + 2026-06-07-economy-sinks-fase0.md (S2/S3). Edited by DESIGNERS
-- for balance.
--
-- RARITY-BY-SOURCE (Vision Pivot Decision 8, LOCKED): rarity comes from the
-- CONTENT a monster was obtained from, not one big gacha pool:
--   Wild catch          -> roll Common 80% / Uncommon 20%   (rollWeights below)
--   Colony Boss drop    -> "Rare"      (supplied explicitly by the drop path)
--   Super Boss [later]  -> "Epic"
--   Raid Boss  [later]  -> "Legendary"
-- The roll therefore gives Rare+ a ZERO weight — they can never come from
-- grass. Boss-drop paths pass the rarity string straight into
-- Schema.newMonster (validated, never trusted blindly).
--
-- POWER ORDER GUARD (R3): statMult is deliberately moderate (<= x2.0) so the
-- hierarchy stays level (<= x8.9) > evolution (<= x2.0) >= rarity (<= x2.0)
-- > element (+/-25%) — effort beats luck; a Legendary Lv1 loses to a Rare Lv20.
--
-- AUTHORITY: display fields (name/color, displayed odds derived from
-- rollWeights) MAY be mirrored to the client for UI. RESOLUTION fields
-- (statMult/evolveCostMult) are applied SERVER-SIDE. The roll is SERVER-SIDE
-- ONLY at mint (R5: permanent once set, like element).
--
-- This module is in ReplicatedStorage (per shared-modules rules) because it
-- holds NO secrets: pure tuning data + pure functions, no state.
--
-- Schema version: 1 (matches the `version` field below).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)

type Rarity = Types.Rarity

export type RollWeights = { [string]: number }

export type RarityDisplay = {
    name: string,
    color: string,
}

local RarityConfig = {
    -- Schema version of this config (bump on a structural change).
    version = 1,

    -- Rarity enum keys, ascending. Canonical UI display order AND the tier
    -- ladder. Domain: exactly these 5 keys (validate() injects any missing).
    order = { "Common", "Uncommon", "Rare", "Epic", "Legendary" },

    -- WILD-CATCH roll weights (R1, LOCKED 80/20). RELATIVE weights;
    -- probability = weight / sum. Rare+ are ZERO here BY DESIGN (rarity-by-
    -- source): boss-drop paths supply their rarity explicitly instead of
    -- rolling. Range per weight: 0..1000 | Defaults: 80 / 20 / 0 / 0 / 0
    rollWeights = {
        Common = 80, -- default 80 -> 80%
        Uncommon = 20, -- default 20 -> 20%
        Rare = 0, -- boss drop only (never rolled from grass)
        Epic = 0, -- super boss only (later)
        Legendary = 0, -- raid boss only (later)
    } :: RollWeights,

    -- Combat stat multiplier (R3, LOCKED moderate). Multiplies the fighter's
    -- derived HP + damage as one factor alongside levelScale and elementMod.
    -- Range per value: 1.0-3.0 | Defaults: 1.0 / 1.15 / 1.35 / 1.6 / 2.0
    statMult = {
        Common = 1.0,
        Uncommon = 1.15,
        Rare = 1.35,
        Epic = 1.6,
        Legendary = 2.0,
    } :: { [string]: number },

    -- Evolution ACTIVATION cost multiplier (S2, LOCKED). Consumed by the
    -- Evolution sink: evolveCost(stage, rarity) = baseCost[stage] * this.
    -- Range per value: 1.0-10.0 | Defaults: 1.0 / 1.5 / 2.5 / 4.0 / 6.0
    evolveCostMult = {
        Common = 1.0,
        Uncommon = 1.5,
        Rare = 2.5,
        Epic = 4.0,
        Legendary = 6.0,
    } :: { [string]: number },

    -- CATCH-RATE multiplier (CAPTURE feature, LOCKED 2026-06-08): rarer monsters
    -- are HARDER to catch. The capture roll computes
    --   catchRate = clamp(baseCatchRate * catchRateMult[rarity] + pity, min, max)
    -- (base + clamp + pity live in DemoConfig.catch; this is the per-rarity
    -- difficulty factor only — single source of truth for "rarity affects catch").
    -- A value of 1.0 = no penalty (full base rate); lower = harder.
    -- Range per value: 0.05-1.0 | Defaults: 1.0 / 0.85 / 0.65 / 0.45 / 0.30
    catchRateMult = {
        Common = 1.0, -- easiest: base rate applies as-is
        Uncommon = 0.85,
        Rare = 0.65,
        Epic = 0.45,
        Legendary = 0.30, -- hardest: ~1/3 the base rate before pity
    } :: { [string]: number },

    -- Display-only metadata (badge tint per tier, R3 table). Hex strings so
    -- the UI builds Color3 itself (JSON-safe, theme-agnostic).
    display = {
        Common = { name = "Common", color = "#9CA3AF" }, -- abu-abu
        Uncommon = { name = "Uncommon", color = "#22C55E" }, -- hijau
        Rare = { name = "Rare", color = "#3B82F6" }, -- biru
        Epic = { name = "Epic", color = "#A855F7" }, -- ungu
        Legendary = { name = "Legendary", color = "#F59E0B" }, -- emas
    } :: { [string]: RarityDisplay },
}

-- Set form of `order` for O(1) membership checks.
local RARITY_SET: { [string]: boolean } = {}
for _, r in ipairs(RarityConfig.order) do
    RARITY_SET[r] = true
end

-- True iff the value is a valid Rarity enum string.
function RarityConfig.isValidRarity(value: any): boolean
    return type(value) == "string" and RARITY_SET[value] == true
end

-- Defensive stat-mult lookup: invalid/missing rarity resolves to 1.0 (neutral)
-- so combat math can never explode on bad content (mirrors elementMod's
-- neutral fallback philosophy).
function RarityConfig.statMultFor(rarity: any): number
    if RarityConfig.isValidRarity(rarity) then
        return RarityConfig.statMult[rarity]
    end
    return 1.0
end

-- Defensive evolve-cost-mult lookup (same fallback contract).
function RarityConfig.evolveCostMultFor(rarity: any): number
    if RarityConfig.isValidRarity(rarity) then
        return RarityConfig.evolveCostMult[rarity]
    end
    return 1.0
end

-- Defensive catch-rate-mult lookup (same neutral-fallback contract: an
-- invalid/missing rarity resolves to 1.0 so the capture roll can never explode
-- on bad content — it just applies the full base rate).
function RarityConfig.catchRateMultFor(rarity: any): number
    if RarityConfig.isValidRarity(rarity) then
        return RarityConfig.catchRateMult[rarity]
    end
    return 1.0
end

-- ── Validation (mirrors ElementConfig/PersonalityConfig.validate) ───────────
--
-- Returns a SANITIZED copy of rollWeights: negatives clamped to 0 (logged),
-- missing keys injected at 0 (logged), and a CRITICAL uniform fallback if the
-- post-clamp sum is 0 — except here the uniform fallback restores the LOCKED
-- wild distribution (80/20/0/0/0), not flat-uniform, because Rare+ must never
-- become rollable through a corrupted table. NEVER mutates the source table.

local FALLBACK_WEIGHTS: { [string]: number } = {
    Common = 80,
    Uncommon = 20,
    Rare = 0,
    Epic = 0,
    Legendary = 0,
}

function RarityConfig.validate(logger: ((event: string, payload: { [string]: any }) -> ())?): RollWeights
    local function log(event: string, payload: { [string]: any })
        if logger then
            logger(event, payload)
        end
    end

    local sanitized: RollWeights = {}
    local sum = 0

    for _, key in ipairs(RarityConfig.order) do
        local raw = RarityConfig.rollWeights[key]
        local weight: number
        if type(raw) ~= "number" then
            log("weight_missing", { key = key })
            weight = 0
        elseif raw < 0 then
            log("weight_clamped", { key = key, from = raw, to = 0 })
            weight = 0
        else
            weight = raw
        end
        sanitized[key] = weight
        sum += weight
    end

    if sum <= 0 then
        log("rollweights_zero_fallback", { keys = #RarityConfig.order })
        for key, weight in FALLBACK_WEIGHTS do
            sanitized[key] = weight
        end
    end

    return sanitized
end

-- ── rollRarity (the wild-catch mint roll; R1) ───────────────────────────────
--
-- SERVER-SIDE ONLY by convention (the client never supplies a rolled rarity).
-- Pure given its inputs: pass a seeded Random for deterministic tests; nil
-- uses a module-level Random (production path). `weights` defaults to
-- validate()'s sanitized copy. Zero-weight tiers are unreachable (the
-- accumulator never lands inside an empty span).
local defaultRng = Random.new()

function RarityConfig.rollRarity(rng: Random?, weights: RollWeights?): Rarity
    local r = rng or defaultRng
    local w = weights or RarityConfig.validate()

    local sum = 0
    for _, key in ipairs(RarityConfig.order) do
        sum += w[key]
    end

    local pick = r:NextNumber() * sum
    local acc = 0
    for _, key in ipairs(RarityConfig.order) do
        acc += w[key]
        if w[key] > 0 and pick < acc then
            return key :: Rarity
        end
    end
    -- Float-edge fallback (pick == sum): last NON-ZERO key in canonical order.
    for i = #RarityConfig.order, 1, -1 do
        local key = RarityConfig.order[i]
        if w[key] > 0 then
            return key :: Rarity
        end
    end
    return "Common"
end

return RarityConfig
