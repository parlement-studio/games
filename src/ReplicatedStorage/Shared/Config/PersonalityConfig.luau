--!strict
-- Shared/Config/PersonalityConfig.luau
--
-- Trait table for the Personality System (Creative Pillar #2), per
-- design/gdd/personality-gdd.md (v1.1) §8. Edited by DESIGNERS for balance.
--
-- Consumers (Idle Production #3, Battle #5, Raid #6, Evolution #8, Moment #12,
-- Reroll #11) READ this table; they NEVER hardcode personality numbers. No
-- derived stats are stored on Brainrots — every numeric effect is recomputed at
-- runtime by querying this table, so a config rebalance applies retroactively to
-- the whole roster with no migration (§2.2 #4).
--
-- AUTHORITY (personality-gdd §4, locked): the DISPLAY-only sub-fields (name /
-- color / blurb / displayed odds derived from rollWeights) MAY be mirrored to the
-- client for UI. The RESOLUTION fields (multipliers, probabilities, thresholds,
-- durations, battle params) are read SERVER-SIDE only — a tampered client cannot
-- change an outcome because consumers ignore client-supplied effect values.
--
-- This module is in ReplicatedStorage (per shared-modules rules) because it holds
-- NO secrets: it is pure tuning data + a pure validator. There is no
-- server-authoritative logic here; PersonalityService (ServerStorage) owns that.
--
-- Schema version: 1 (matches the `version` field below).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)

type Personality = Types.Personality

-- The raw config payload type (the literal returned table). Resolution numbers
-- live in the table; validation lives in CODE (PersonalityConfig.validate).
export type RollWeights = { [string]: number }

export type MoraleAura = {
    neighborMultiplier: number,
    radiusSlots: number,
}

export type Trait = {
    -- display
    name: string,
    color: string,
    blurb: string,
    -- production
    productionMultiplier: number,
    breakChance: number?,
    breakDurationSeconds: number?,
    doubleChance: number?,
    doubleMultiplier: number?,
    zeroMultiplier: number?,
    moraleAura: MoraleAura?,
    moraleAuraAffectsLazy: boolean?,
    immuneToNegativeEvents: boolean?,
    overworkRebelCount: number?,
    walkoutChance: number?,
    walkoutContagionChance: number?,
    walkoutDurationSeconds: number?,
    walkoutMaxDurationSeconds: number?,
    walkoutCooldownSeconds: number?,
    -- battle
    battleBehaviorTag: string,
    mistargetChance: number?,
    defenseMultiplier: number?,
    berserkAttackMultiplier: number?,
    randomFromAnyMoveset: boolean?,
    bodyguardAllyHpThreshold: number?,
    bodyguardDamageTakenFraction: number?,
    counterDamageMultiplier: number?,
}

export type PersonalityConfigType = {
    version: number,
    order: { string },
    rollWeights: RollWeights,
    rerollGuaranteeDifferent: boolean,
    fallbackPersonality: Personality,
    traits: { [string]: Trait },
    validate: (logger: ((event: string, payload: { [string]: any }) -> ())?) -> RollWeights,
}

local PersonalityConfig = {
    -- Schema version of this trait table (bump on a structural change).
    version = 1,

    -- Personality enum keys. Order here is the canonical UI display order.
    -- Domain: exactly these 5 keys must exist (validate() injects any missing).
    order = { "Hyper", "Lazy", "Chaotic", "Loyal", "Rebel" },

    -- Roll weights used by BOTH capture-roll and reroll (same table, locked, F5).
    -- Each weight is RELATIVE; probability = weight / sum(weights).
    -- Range per weight: 0..1000 (integers recommended). Default: uniform.
    -- Displayed odds in UI MUST be derived from these exact weights.
    rollWeights = {
        Hyper = 20, -- default 20  -> 20% at uniform
        Lazy = 20, -- default 20  -> 20%
        Chaotic = 20, -- default 20  -> 20%
        Loyal = 20, -- default 20  -> 20%
        Rebel = 20, -- default 20  -> 20%
    },

    -- If a reroll must always differ from the current personality (§2.4 #3).
    -- Default false (a reroll may return the same; odds shown include this).
    rerollGuaranteeDifferent = false,

    -- Used by consumers for ONE defensive tick if an enum is unknown (E5).
    -- Range: any valid personality key. Default "Loyal" (neutral / steady).
    fallbackPersonality = "Loyal",

    -- Per-personality trait definitions (declarative numbers + flags + tags;
    -- never executable behavior — consumers own the effect, this owns params).
    traits = {

        Hyper = {
            name = "Hyper", -- display
            color = "#FF5A3C", -- display (badge)
            blurb = "Works fast, burns out faster", -- display (-> localization at impl)

            -- PRODUCTION
            -- Multiplier applied to base production rate by Idle Production (F1).
            -- Range: 0.0..3.0. Default 1.30 (= +30% per source doc).
            productionMultiplier = 1.30,
            -- Per production cycle, chance to enter OnBreak (Bernoulli, F2).
            -- Range: 0.0..1.0. Default 0.10 (occasional break).
            breakChance = 0.10,
            -- How long a Break lasts (production = 0 during it). Server seconds.
            -- Range: 5..120. Default 20.
            breakDurationSeconds = 20,

            -- BATTLE (F4)
            battleBehaviorTag = "act_first_mistarget",
            -- Chance the first-strike hits the WRONG target.
            -- Range: 0.0..1.0. Default 0.20 (= 20% per source doc).
            mistargetChance = 0.20,
        },

        Lazy = {
            name = "Lazy",
            color = "#7B8794",
            blurb = "Slow worker, somehow motivates everyone else",

            -- PRODUCTION
            -- Range: 0.0..3.0. Default 0.50 (= -50% per source doc).
            productionMultiplier = 0.50,
            -- Morale aura buffs ADJACENT non-Lazy Brainrots' production (F1).
            moraleAura = {
                -- Multiplier applied to each affected neighbor's rate.
                -- Range: 1.0..2.0. Default 1.15 (+15% to neighbors).
                neighborMultiplier = 1.15,
                -- Adjacency radius in "slots" within the same building.
                -- Range: 1..8. Default 1 (immediate neighbors).
                radiusSlots = 1,
            },
            -- Whether Lazy can RECEIVE another Lazy's aura (see E1).
            -- Default false (Lazy never buffed; avoids all-Lazy stacking).
            moraleAuraAffectsLazy = false,

            -- BATTLE (F4)
            battleBehaviorTag = "berserk_when_last",
            -- Defense multiplier while NOT last-standing (high defense).
            -- Range: 1.0..3.0. Default 1.75.
            defenseMultiplier = 1.75,
            -- Attack multiplier once it is the LAST ally alive (berserk).
            -- Range: 1.0..4.0. Default 2.50.
            berserkAttackMultiplier = 2.50,
        },

        Chaotic = {
            name = "Chaotic",
            color = "#B14DFF",
            blurb = "Genius or disaster, never both",

            -- PRODUCTION (per-cycle coin flip; multiplier is double or zero, F1)
            -- Base, modified by the per-cycle flip below.
            -- Range: 0.0..3.0. Default 1.0.
            productionMultiplier = 1.0,
            -- Probability the cycle is the DOUBLE outcome (else ZERO).
            -- Range: 0.0..1.0. Default 0.50 (fair coin per source doc).
            doubleChance = 0.50,
            -- Multiplier on a "double" cycle. Range: 1.0..4.0. Default 2.0.
            doubleMultiplier = 2.0,
            -- Multiplier on a "zero" cycle. Range: 0.0..1.0. Default 0.0.
            zeroMultiplier = 0.0,

            -- BATTLE (F4)
            battleBehaviorTag = "random_moveset",
            -- If Chaotic may pull skills from ANY Brainrot's moveset (else own).
            -- Default true (per source doc: "from any Brainrot's moveset").
            randomFromAnyMoveset = true,
        },

        Loyal = {
            name = "Loyal",
            color = "#2EC4B6",
            blurb = "Dependable. Takes the hit for the team.",

            -- PRODUCTION
            -- Range: 0.0..3.0. Default 1.0 (steady).
            productionMultiplier = 1.0,
            -- Immune to negative Moment/event production effects.
            -- Default true (per source doc).
            immuneToNegativeEvents = true,

            -- BATTLE (F4)
            battleBehaviorTag = "bodyguard",
            -- Redirect ally damage when ally HP fraction is below this.
            -- Range: 0.0..1.0. Default 0.30 (= below 30% per source doc).
            bodyguardAllyHpThreshold = 0.30,
            -- Fraction of the redirected hit Loyal actually takes.
            -- Range: 0.0..1.0. Default 1.0 (takes full hit).
            bodyguardDamageTakenFraction = 1.0,
        },

        Rebel = {
            name = "Rebel",
            color = "#FFB627",
            blurb = "Won't be overworked. Brings friends.",

            -- PRODUCTION
            -- Range: 0.0..3.0. Default 1.0 (normal unless on Walkout).
            productionMultiplier = 1.0,
            -- "Overworked" threshold: number of Rebels co-located in ONE building
            -- at/above which Walkout becomes possible (F3).
            -- Range: 1..50. Default 3.
            overworkRebelCount = 3,
            -- Per-eligibility-check chance an overworked Rebel starts a Walkout.
            -- Range: 0.0..1.0. Default 0.15.
            walkoutChance = 0.15,
            -- Chance a co-located Brainrot is dragged into an active Walkout.
            -- Range: 0.0..1.0. Default 0.40. (<1 bounds chains — see E2.)
            walkoutContagionChance = 0.40,
            -- How long a single Walkout lasts. Server seconds.
            -- Range: 30..1800. Default 300 (5 min, matches drama-event flavor).
            walkoutDurationSeconds = 300,
            -- Hard cap on total chained-walkout duration per building (safety).
            -- Range: 60..3600. Default 600.
            walkoutMaxDurationSeconds = 600,
            -- Cooldown after a building's Walkout resolves before it can recur.
            -- Range: 0..7200. Default 600.
            walkoutCooldownSeconds = 600,

            -- BATTLE (F4)
            battleBehaviorTag = "counter_double",
            -- Damage multiplier on a survived-hit counterattack.
            -- Range: 1.0..4.0. Default 2.0 (= double per source doc).
            counterDamageMultiplier = 2.0,
        },
    },
}

-- ── Validation (E6) ────────────────────────────────────────────────────────
--
-- Per gameplay-systems / config-data rules, VALIDATION LIVES IN CODE; the
-- numbers stay in the table above. validate() runs once on server boot (see the
-- bootstrap) and returns a SANITIZED copy of rollWeights:
--   * a NEGATIVE weight is clamped to 0 and logged (weight_clamped);
--   * a MISSING `order` key is injected at weight 0 and logged (weight_missing);
--   * if the POST-clamp sum is 0, FALL BACK to uniform 20 across all five keys
--     and log a CRITICAL incident (rollweights_zero_fallback).
-- It NEVER mutates the caller's source table (returns a fresh map), so the
-- displayed-odds UI and the roller always read the same sanitized weights.
--
-- The optional `logger` matches PlayerDataService's logger shape
-- ((event, payload) -> ()); nil = silent (used in pure unit tests).

-- Default uniform weight injected when the whole table is unusable (E6).
-- Mirrors the per-key default above; kept here so the fallback path has a single
-- numeric source. Range: 1..1000. Default 20 (= 20% across five keys).
local UNIFORM_FALLBACK_WEIGHT = 20

function PersonalityConfig.validate(logger: ((event: string, payload: { [string]: any }) -> ())?): RollWeights
    local function log(event: string, payload: { [string]: any })
        if logger then
            logger(event, payload)
        end
    end

    local sanitized: RollWeights = {}
    local sum = 0

    for _, key in ipairs(PersonalityConfig.order) do
        local raw = PersonalityConfig.rollWeights[key]
        local weight: number
        if type(raw) ~= "number" then
            -- Missing (or non-numeric) key: inject at 0 and log (E6).
            log("weight_missing", { key = key })
            weight = 0
        elseif raw < 0 then
            -- Negative: clamp to 0 and log (E6).
            log("weight_clamped", { key = key, from = raw, to = 0 })
            weight = 0
        else
            weight = raw
        end
        sanitized[key] = weight
        sum += weight
    end

    if sum <= 0 then
        -- Post-clamp total is 0: the table is unusable. Fall back to uniform so
        -- the roller never divides by zero (E6 / F5). CRITICAL — a shipped
        -- designer error reached production.
        log("rollweights_zero_fallback", {
            keys = #PersonalityConfig.order,
            weight = UNIFORM_FALLBACK_WEIGHT,
        })
        for _, key in ipairs(PersonalityConfig.order) do
            sanitized[key] = UNIFORM_FALLBACK_WEIGHT
        end
    end

    return sanitized
end

return PersonalityConfig
