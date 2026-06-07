--!strict
-- Shared/Config/ElementConfig.luau
--
-- Element System config (Monster Relic combat affinity), per
-- design/decisions/2026-06-07-element-system.md (E1-E5). Edited by DESIGNERS
-- for balance.
--
-- LIGHT CHART (E1/E2): a one-way advantage circle over exactly 5 elements —
--   Fire > Nature > Water > Volt > Wind > Fire
-- Each element beats EXACTLY ONE and loses to EXACTLY ONE; same-vs-same is
-- neutral. The only combat effect is a flat damage multiplier (elementMod)
-- applied by the Pet AI boss-combat engine (#25), BOTH directions
-- (summon -> boss and boss -> summon).
--
-- ORTHOGONALITY (element doc §4, locked): Element is COMBAT-ONLY. It must NOT
-- be consulted by Idle Production (#26 — Personality owns that axis), capture
-- success rate (#4 — item tier owns that), or any economy formula.
--
-- AUTHORITY: display sub-fields (name/color/icon, displayed roll odds derived
-- from rollWeights) MAY be mirrored to the client for UI. RESOLUTION fields
-- (advantageMod/disadvantageMod/beats) are read SERVER-SIDE for outcomes — a
-- tampered client cannot change a result because the server recomputes
-- elementMod itself. The roll is SERVER-SIDE ONLY (element doc §5 #4): the
-- client never supplies a rolled element.
--
-- This module is in ReplicatedStorage (per shared-modules rules) because it
-- holds NO secrets: pure tuning data + pure functions, no state.
--
-- Schema version: 1 (matches the `version` field below).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)

type Element = Types.Element

export type RollWeights = { [string]: number }

export type ElementDisplay = {
    name: string,
    color: string,
    emoji: string,
}

local ElementConfig = {
    -- Schema version of this config (bump on a structural change).
    version = 1,

    -- Element enum keys. Order here is the canonical UI display order AND the
    -- circle order (each entry beats the NEXT one, last beats first).
    -- Domain: exactly these 5 keys must exist (validate() injects any missing).
    order = { "Fire", "Nature", "Water", "Volt", "Wind" },

    -- The one-way advantage circle (E2, LOCKED 2026-06-07):
    -- Fire > Nature > Water > Volt > Wind > Fire.
    -- Derived reading: attacker beats defender => advantageMod; defender beats
    -- attacker => disadvantageMod; anything else (incl. same-vs-same) => neutral.
    beats = {
        Fire = "Nature", -- api membakar tanaman
        Nature = "Water", -- tanaman menyerap air
        Water = "Volt", -- air memadamkan/menghantarkan listrik
        Volt = "Wind", -- listrik menembus angin
        Wind = "Fire", -- angin meniup padam api
    } :: { [string]: string },

    -- Damage multiplier when the ATTACKER's element beats the defender's (E5).
    -- Range: 1.15-1.40. Default 1.25 (locked default; config-driven tune).
    advantageMod = 1.25,

    -- Damage multiplier when the DEFENDER's element beats the attacker's (E5).
    -- Keep symmetric with advantageMod (1/x not required; flat by design).
    -- Range: 0.60-0.85. Default 0.75.
    disadvantageMod = 0.75,

    -- Damage multiplier for every other pairing, INCLUDING same-vs-same and the
    -- defensive fallback for a missing/invalid element (element doc §5 #2-#3).
    -- Range: 1.0 (do not tune; neutral means neutral). Default 1.0.
    neutralMod = 1.0,

    -- Roll weights used by the capture-mint roll (E3: uniform at launch, NO
    -- area bias). Each weight is RELATIVE; probability = weight / sum(weights).
    -- Structure stays per-element so a future tune needs no migration.
    -- Range per weight: 0..1000 (integers recommended). Default: uniform 20.
    rollWeights = {
        Fire = 20, -- default 20 -> 20% at uniform
        Nature = 20, -- default 20 -> 20%
        Water = 20, -- default 20 -> 20%
        Volt = 20, -- default 20 -> 20%
        Wind = 20, -- default 20 -> 20%
    } :: RollWeights,

    -- Display-only metadata (UI badges, boss pre-encounter screen). Icons are
    -- emoji placeholders until final art (element doc §7).
    display = {
        Fire = { name = "Fire", color = "#FF5A3C", emoji = "🔥" },
        Nature = { name = "Nature", color = "#3CB043", emoji = "🌿" },
        Water = { name = "Water", color = "#3C8DFF", emoji = "💧" },
        Volt = { name = "Volt", color = "#FFD23C", emoji = "⚡" },
        Wind = { name = "Wind", color = "#9AD7D8", emoji = "🌪️" },
    } :: { [string]: ElementDisplay },
}

-- Set form of `order` for O(1) membership checks.
local ELEMENT_SET: { [string]: boolean } = {}
for _, e in ipairs(ElementConfig.order) do
    ELEMENT_SET[e] = true
end

-- True iff the value is a valid Element enum string.
function ElementConfig.isValidElement(value: any): boolean
    return type(value) == "string" and ELEMENT_SET[value] == true
end

-- ── elementMod (the ONLY combat effect; element doc §2) ─────────────────────
--
-- dmg = baseDmg * levelScale(L) * elementMod(attacker.element, defender.element)
--
-- Defensive fallback (element doc §5 #3): a nil/invalid element on EITHER side
-- resolves to neutralMod and logs (content error, e.g. a boss spec shipped
-- without an element) — combat must never crash on bad content. The optional
-- `logger` matches PlayerDataService's logger shape ((event, payload) -> ());
-- nil = silent (pure unit tests).
function ElementConfig.elementMod(
    attackerElem: any,
    defenderElem: any,
    logger: ((event: string, payload: { [string]: any }) -> ())?
): number
    local attackerValid = ElementConfig.isValidElement(attackerElem)
    local defenderValid = ElementConfig.isValidElement(defenderElem)
    if not attackerValid or not defenderValid then
        if logger then
            logger("elementmod_invalid_element", {
                attacker = tostring(attackerElem),
                defender = tostring(defenderElem),
            })
        end
        return ElementConfig.neutralMod
    end
    if ElementConfig.beats[attackerElem] == defenderElem then
        return ElementConfig.advantageMod
    end
    if ElementConfig.beats[defenderElem] == attackerElem then
        return ElementConfig.disadvantageMod
    end
    return ElementConfig.neutralMod
end

-- ── Validation (mirrors PersonalityConfig.validate) ─────────────────────────
--
-- Per config-data rules, VALIDATION LIVES IN CODE; numbers stay in the table.
-- Returns a SANITIZED copy of rollWeights:
--   * a NEGATIVE weight is clamped to 0 and logged (weight_clamped);
--   * a MISSING `order` key is injected at weight 0 and logged (weight_missing);
--   * if the POST-clamp sum is 0, FALL BACK to uniform across all five keys and
--     log a CRITICAL incident (rollweights_zero_fallback).
-- NEVER mutates the caller's source table (returns a fresh map).

-- Default uniform weight injected when the whole table is unusable. Mirrors the
-- per-key default above. Range: 1..1000. Default 20 (= 20% across five keys).
local UNIFORM_FALLBACK_WEIGHT = 20

function ElementConfig.validate(logger: ((event: string, payload: { [string]: any }) -> ())?): RollWeights
    local function log(event: string, payload: { [string]: any })
        if logger then
            logger(event, payload)
        end
    end

    local sanitized: RollWeights = {}
    local sum = 0

    for _, key in ipairs(ElementConfig.order) do
        local raw = ElementConfig.rollWeights[key]
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
        log("rollweights_zero_fallback", {
            keys = #ElementConfig.order,
            weight = UNIFORM_FALLBACK_WEIGHT,
        })
        for _, key in ipairs(ElementConfig.order) do
            sanitized[key] = UNIFORM_FALLBACK_WEIGHT
        end
    end

    return sanitized
end

-- ── rollElement (the capture-mint roll; E3) ─────────────────────────────────
--
-- SERVER-SIDE ONLY by convention (the client never calls this for an outcome;
-- element doc §5 #4). Pure given its inputs: pass a seeded Random for
-- deterministic tests; nil uses a module-level Random (production path).
-- `weights` defaults to validate()'s sanitized copy so a designer error can
-- never divide by zero.
local defaultRng = Random.new()

function ElementConfig.rollElement(rng: Random?, weights: RollWeights?): Element
    local r = rng or defaultRng
    local w = weights or ElementConfig.validate()

    local sum = 0
    for _, key in ipairs(ElementConfig.order) do
        sum += w[key]
    end

    local pick = r:NextNumber() * sum
    local acc = 0
    for _, key in ipairs(ElementConfig.order) do
        acc += w[key]
        if pick < acc then
            return key :: Element
        end
    end
    -- Float-edge fallback (pick == sum): last key in canonical order.
    return ElementConfig.order[#ElementConfig.order] :: Element
end

return ElementConfig
