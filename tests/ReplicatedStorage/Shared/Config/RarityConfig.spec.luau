--!nocheck
-- tests/ReplicatedStorage/Shared/Config/RarityConfig.spec.luau
--
-- TestEZ specs for RarityConfig (design/decisions/2026-06-07-rarity-droprate.md
-- R1-R5 + economy-sinks-fase0 S2/S3). AAA pattern, isolated tests; mirrors the
-- ElementConfig.spec idiom (override + afterEach restore).
--
-- Covers:
--   * R1/R3/S2 table transcription (5 tiers, 80/20 wild weights, locked mults)
--   * rarity-by-source guard: Rare+ are NEVER rolled from the default weights
--   * statMultFor / evolveCostMultFor defensive 1.0 fallback
--   * validate(): clamp / inject / LOCKED-80-20 fallback (NOT flat uniform)
--   * rollRarity: valid output, deterministic under seeded Random, both
--     rollable tiers reachable, zero-weight tiers unreachable

return function()
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local RarityConfig = require(ReplicatedStorage.Shared.Config.RarityConfig)

    local savedWeights
    local savedOrder

    beforeEach(function()
        savedWeights = RarityConfig.rollWeights
        savedOrder = RarityConfig.order
    end)

    afterEach(function()
        RarityConfig.rollWeights = savedWeights
        RarityConfig.order = savedOrder
    end)

    describe("R1/R3/S2 table transcription", function()
        it("declares version 1 and exactly the five canonical tiers ascending", function()
            expect(RarityConfig.version).to.equal(1)
            expect(#RarityConfig.order).to.equal(5)
            expect(RarityConfig.order[1]).to.equal("Common")
            expect(RarityConfig.order[2]).to.equal("Uncommon")
            expect(RarityConfig.order[3]).to.equal("Rare")
            expect(RarityConfig.order[4]).to.equal("Epic")
            expect(RarityConfig.order[5]).to.equal("Legendary")
        end)

        it("declares the LOCKED wild weights 80/20 with Rare+ at ZERO (rarity-by-source)", function()
            expect(RarityConfig.rollWeights.Common).to.equal(80)
            expect(RarityConfig.rollWeights.Uncommon).to.equal(20)
            expect(RarityConfig.rollWeights.Rare).to.equal(0)
            expect(RarityConfig.rollWeights.Epic).to.equal(0)
            expect(RarityConfig.rollWeights.Legendary).to.equal(0)
        end)

        it("declares the LOCKED moderate statMult ladder (R3)", function()
            expect(RarityConfig.statMult.Common).to.equal(1.0)
            expect(RarityConfig.statMult.Uncommon).to.equal(1.15)
            expect(RarityConfig.statMult.Rare).to.equal(1.35)
            expect(RarityConfig.statMult.Epic).to.equal(1.6)
            expect(RarityConfig.statMult.Legendary).to.equal(2.0)
        end)

        it("declares the LOCKED evolveCostMult ladder (S2)", function()
            expect(RarityConfig.evolveCostMult.Common).to.equal(1.0)
            expect(RarityConfig.evolveCostMult.Uncommon).to.equal(1.5)
            expect(RarityConfig.evolveCostMult.Rare).to.equal(2.5)
            expect(RarityConfig.evolveCostMult.Epic).to.equal(4.0)
            expect(RarityConfig.evolveCostMult.Legendary).to.equal(6.0)
        end)
    end)

    describe("isValidRarity + defensive lookups", function()
        it("accepts all five tiers and rejects everything else", function()
            for _, r in ipairs(RarityConfig.order) do
                expect(RarityConfig.isValidRarity(r)).to.equal(true)
            end
            expect(RarityConfig.isValidRarity("Mythic")).to.equal(false)
            expect(RarityConfig.isValidRarity("common")).to.equal(false) -- case-sensitive
            expect(RarityConfig.isValidRarity(nil)).to.equal(false)
            expect(RarityConfig.isValidRarity(2)).to.equal(false)
        end)

        it("statMultFor / evolveCostMultFor fall back to 1.0 on nil/invalid", function()
            expect(RarityConfig.statMultFor("Legendary")).to.equal(2.0)
            expect(RarityConfig.statMultFor(nil)).to.equal(1.0)
            expect(RarityConfig.statMultFor("Garbage")).to.equal(1.0)
            expect(RarityConfig.evolveCostMultFor("Epic")).to.equal(4.0)
            expect(RarityConfig.evolveCostMultFor(nil)).to.equal(1.0)
            expect(RarityConfig.evolveCostMultFor(123)).to.equal(1.0)
        end)
    end)

    describe("validate", function()
        it("returns the locked weights for a healthy table", function()
            local w = RarityConfig.validate()
            expect(w.Common).to.equal(80)
            expect(w.Uncommon).to.equal(20)
            expect(w.Rare).to.equal(0)
        end)

        it("clamps a negative weight to 0 and logs", function()
            RarityConfig.rollWeights = { Common = -5, Uncommon = 20, Rare = 0, Epic = 0, Legendary = 0 }
            local clamped = false
            local w = RarityConfig.validate(function(event)
                if event == "weight_clamped" then
                    clamped = true
                end
            end)
            expect(w.Common).to.equal(0)
            expect(clamped).to.equal(true)
        end)

        it("injects a missing tier at 0 and logs", function()
            RarityConfig.rollWeights = { Common = 80, Uncommon = 20, Rare = 0, Epic = 0 } -- Legendary omitted
            local missing = false
            local w = RarityConfig.validate(function(event, payload)
                if event == "weight_missing" and payload.key == "Legendary" then
                    missing = true
                end
            end)
            expect(w.Legendary).to.equal(0)
            expect(missing).to.equal(true)
        end)

        it("falls back to the LOCKED 80/20 (NOT flat uniform) when the sum is 0", function()
            -- Flat uniform would make Rare+ rollable from grass — forbidden.
            RarityConfig.rollWeights = { Common = 0, Uncommon = 0, Rare = 0, Epic = 0, Legendary = 0 }
            local fellBack = false
            local w = RarityConfig.validate(function(event)
                if event == "rollweights_zero_fallback" then
                    fellBack = true
                end
            end)
            expect(w.Common).to.equal(80)
            expect(w.Uncommon).to.equal(20)
            expect(w.Rare).to.equal(0)
            expect(w.Epic).to.equal(0)
            expect(w.Legendary).to.equal(0)
            expect(fellBack).to.equal(true)
        end)

        it("does NOT mutate the caller's source rollWeights table", function()
            RarityConfig.rollWeights = { Common = -1, Uncommon = 20, Rare = 0, Epic = 0, Legendary = 0 }
            RarityConfig.validate()
            expect(RarityConfig.rollWeights.Common).to.equal(-1)
        end)
    end)

    describe("rollRarity (R1)", function()
        it("always returns a valid tier", function()
            local rng = Random.new(42)
            for _ = 1, 200 do
                expect(RarityConfig.isValidRarity(RarityConfig.rollRarity(rng))).to.equal(true)
            end
        end)

        it("is deterministic under the same seeded Random", function()
            local a = Random.new(1337)
            local b = Random.new(1337)
            for _ = 1, 50 do
                expect(RarityConfig.rollRarity(a)).to.equal(RarityConfig.rollRarity(b))
            end
        end)

        it("NEVER rolls Rare/Epic/Legendary from the default weights (rarity-by-source)", function()
            local rng = Random.new(7)
            for _ = 1, 1000 do
                local rolled = RarityConfig.rollRarity(rng)
                expect(rolled == "Common" or rolled == "Uncommon").to.equal(true)
            end
        end)

        it("reaches BOTH rollable tiers at roughly 80/20 over many rolls", function()
            local rng = Random.new(99)
            local counts = { Common = 0, Uncommon = 0 }
            for _ = 1, 2000 do
                local rolled = RarityConfig.rollRarity(rng)
                counts[rolled] = (counts[rolled] or 0) + 1
            end
            expect(counts.Common > 1400 and counts.Common < 1800).to.equal(true) -- ~80% ± margin
            expect(counts.Uncommon > 250 and counts.Uncommon < 550).to.equal(true) -- ~20% ± margin
        end)

        it("respects a weights override (boss-style explicit distribution)", function()
            -- A future drop table could roll within a tier band; zero stays zero.
            local weights = { Common = 0, Uncommon = 0, Rare = 100, Epic = 0, Legendary = 0 }
            local rng = Random.new(5)
            for _ = 1, 100 do
                expect(RarityConfig.rollRarity(rng, weights)).to.equal("Rare")
            end
        end)
    end)
end
