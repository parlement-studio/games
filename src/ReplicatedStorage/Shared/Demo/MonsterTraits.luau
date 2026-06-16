--!strict
-- Shared/Demo/MonsterTraits.luau
--
-- Resolves a monster's future-proofing TRAITS from the replicated catalog:
--   * habitat  -> a GroundFollow locomotion mode + that mode's vertical params
--   * attack   -> the effective combat engage range (melee close / ranged afar)
-- Two ORTHOGONAL axes (see DemoConfig.monsterTraits + species[*].habitat/attack).
-- Every species is ground/melee today; this module is the single lookup so the
-- server (fighters + wilds) and any future system branch on traits identically.
-- PURE + stateless (config reads only) so it is safe on client or server.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DemoConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Demo"):WaitForChild("DemoConfig"))

local MonsterTraits = {}

local CFG = DemoConfig.monsterTraits

-- personality -> 1-based index in personalityOrder (matches entry.species, which
-- is minted as speciesByPersonality = the personality's order index).
local PERSONALITY_INDEX: { [string]: number } = {}
for i, p in ipairs(DemoConfig.personalityOrder) do
    PERSONALITY_INDEX[p] = i
end

export type LocomotionOpts = {
    locomotion: string,
    flyHeight: number?,
    waterDepth: number?,
    surfaceY: number?,
}

-- (habitat, attack) for a species INDEX (1-based, == entry.species). Unknown /
-- missing values fall back to the configured defaults.
function MonsterTraits.forSpecies(speciesIndex: number): (string, string)
    local id = DemoConfig.speciesOrder[speciesIndex]
    local sdef = if id ~= nil then DemoConfig.species[id] else nil
    local habitat = (sdef and sdef.habitat) or CFG.defaultHabitat
    local attack = (sdef and sdef.attack) or CFG.defaultAttack
    return habitat, attack
end

-- (habitat, attack) for a personality (wilds/fighters carry personality, and the
-- species index is derived the same way the catch mint does).
function MonsterTraits.forPersonality(personality: string): (string, string)
    return MonsterTraits.forSpecies(PERSONALITY_INDEX[personality] or 0)
end

-- The GroundFollow attach opts for a habitat (locomotion mode + vertical params).
function MonsterTraits.locomotionOpts(habitat: string): LocomotionOpts
    local h = CFG.habitats[habitat] or CFG.habitats[CFG.defaultHabitat]
    return {
        locomotion = h.locomotion,
        flyHeight = h.flyHeight,
        waterDepth = h.waterDepth,
        surfaceY = h.fallbackSurfaceY,
    }
end

-- Effective engage range (studs) for an attack style, scaled off `baseRange`
-- (combat.attackRangeStuds). Melee = baseRange; ranged stands further back.
function MonsterTraits.attackRange(attack: string, baseRange: number): number
    local a = CFG.attacks[attack] or CFG.attacks[CFG.defaultAttack]
    return baseRange * (a.rangeMult or 1)
end

return MonsterTraits
