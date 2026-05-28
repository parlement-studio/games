--!nocheck
-- tests/ReplicatedStorage/Shared/Config/PersonalityConfig.spec.luau
--
-- TestEZ specs for PersonalityConfig.validate (personality-gdd §8 / E6). AAA
-- pattern, isolated tests, no external services. The validator NEVER mutates the
-- caller's source table (returns a fresh sanitized map), so each test restores
-- any field it overrides in afterEach.
--
-- Covers the Acceptance Criteria:
--   * §8 table transcribed verbatim (version/order/weights/flags/traits present)
--   * validate() recovers from negatives (clamp + log)                  (E6)
--   * validate() injects a missing order key at 0 (log)                 (E6)
--   * validate() falls back to uniform 20% when post-clamp sum == 0     (E6)
--   * a healthy uniform table validates to the same weights             (E6)
--   * displayed odds derive from rollWeights and sum to 100%            (AC)

return function()
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local PersonalityConfig = require(ReplicatedStorage.Shared.Config.PersonalityConfig)

    -- Snapshot/restore so a test that overrides rollWeights/order does not leak.
    local savedWeights
    local savedOrder

    beforeEach(function()
        savedWeights = PersonalityConfig.rollWeights
        savedOrder = PersonalityConfig.order
    end)

    afterEach(function()
        PersonalityConfig.rollWeights = savedWeights
        PersonalityConfig.order = savedOrder
    end)

    describe("§8 table transcription", function()
        it("declares version 1 and the five canonical order keys", function()
            -- Assert
            expect(PersonalityConfig.version).to.equal(1)
            expect(#PersonalityConfig.order).to.equal(5)
            local set = {}
            for _, k in ipairs(PersonalityConfig.order) do
                set[k] = true
            end
            expect(set.Hyper).to.equal(true)
            expect(set.Lazy).to.equal(true)
            expect(set.Chaotic).to.equal(true)
            expect(set.Loyal).to.equal(true)
            expect(set.Rebel).to.equal(true)
        end)

        it("declares uniform default weights of 20 each and the locked flags", function()
            -- Assert
            for _, k in ipairs({ "Hyper", "Lazy", "Chaotic", "Loyal", "Rebel" }) do
                expect(PersonalityConfig.rollWeights[k]).to.equal(20)
            end
            expect(PersonalityConfig.rerollGuaranteeDifferent).to.equal(false)
            expect(PersonalityConfig.fallbackPersonality).to.equal("Loyal")
        end)

        it("carries the production + battle params for every personality (§8)", function()
            local t = PersonalityConfig.traits
            -- Hyper
            expect(t.Hyper.productionMultiplier).to.equal(1.30)
            expect(t.Hyper.breakChance).to.equal(0.10)
            expect(t.Hyper.breakDurationSeconds).to.equal(20)
            expect(t.Hyper.battleBehaviorTag).to.equal("act_first_mistarget")
            expect(t.Hyper.mistargetChance).to.equal(0.20)
            -- Lazy
            expect(t.Lazy.productionMultiplier).to.equal(0.50)
            expect(t.Lazy.moraleAura.neighborMultiplier).to.equal(1.15)
            expect(t.Lazy.moraleAura.radiusSlots).to.equal(1)
            expect(t.Lazy.moraleAuraAffectsLazy).to.equal(false)
            expect(t.Lazy.battleBehaviorTag).to.equal("berserk_when_last")
            -- Chaotic
            expect(t.Chaotic.doubleChance).to.equal(0.50)
            expect(t.Chaotic.doubleMultiplier).to.equal(2.0)
            expect(t.Chaotic.zeroMultiplier).to.equal(0.0)
            expect(t.Chaotic.battleBehaviorTag).to.equal("random_moveset")
            -- Loyal
            expect(t.Loyal.immuneToNegativeEvents).to.equal(true)
            expect(t.Loyal.battleBehaviorTag).to.equal("bodyguard")
            expect(t.Loyal.bodyguardAllyHpThreshold).to.equal(0.30)
            -- Rebel
            expect(t.Rebel.overworkRebelCount).to.equal(3)
            expect(t.Rebel.walkoutChance).to.equal(0.15)
            expect(t.Rebel.walkoutContagionChance).to.equal(0.40)
            expect(t.Rebel.walkoutDurationSeconds).to.equal(300)
            expect(t.Rebel.walkoutMaxDurationSeconds).to.equal(600)
            expect(t.Rebel.battleBehaviorTag).to.equal("counter_double")
        end)
    end)

    describe("validate (E6)", function()
        it("returns the same weights for a healthy uniform table (no fallback)", function()
            -- Act
            local weights = PersonalityConfig.validate()

            -- Assert
            local sum = 0
            for _, k in ipairs(PersonalityConfig.order) do
                expect(weights[k]).to.equal(20)
                sum += weights[k]
            end
            expect(sum).to.equal(100)
        end)

        it("clamps a negative weight to 0 and logs (E6)", function()
            -- Arrange: a negative Hyper weight.
            PersonalityConfig.rollWeights = { Hyper = -50, Lazy = 20, Chaotic = 20, Loyal = 20, Rebel = 20 }
            local clamped = false
            local logger = function(event)
                if event == "weight_clamped" then
                    clamped = true
                end
            end

            -- Act
            local weights = PersonalityConfig.validate(logger)

            -- Assert: Hyper -> 0, others intact, incident logged.
            expect(weights.Hyper).to.equal(0)
            expect(weights.Lazy).to.equal(20)
            expect(clamped).to.equal(true)
        end)

        it("injects a missing order key at weight 0 and logs (E6)", function()
            -- Arrange: omit Rebel entirely.
            PersonalityConfig.rollWeights = { Hyper = 20, Lazy = 20, Chaotic = 20, Loyal = 20 }
            local missing = false
            local logger = function(event, payload)
                if event == "weight_missing" and payload.key == "Rebel" then
                    missing = true
                end
            end

            -- Act
            local weights = PersonalityConfig.validate(logger)

            -- Assert: Rebel present at 0; logged.
            expect(weights.Rebel).to.equal(0)
            expect(missing).to.equal(true)
        end)

        it("falls back to uniform 20 across all five when the post-clamp sum is 0 (E6 critical)", function()
            -- Arrange: every weight 0 (designer shipped sum=0).
            PersonalityConfig.rollWeights = { Hyper = 0, Lazy = 0, Chaotic = 0, Loyal = 0, Rebel = 0 }
            local fellBack = false
            local logger = function(event)
                if event == "rollweights_zero_fallback" then
                    fellBack = true
                end
            end

            -- Act
            local weights = PersonalityConfig.validate(logger)

            -- Assert: uniform 20 across all five; critical incident logged.
            local sum = 0
            for _, k in ipairs(PersonalityConfig.order) do
                expect(weights[k]).to.equal(20)
                sum += weights[k]
            end
            expect(sum).to.equal(100)
            expect(fellBack).to.equal(true)
        end)

        it("falls back to uniform when ALL weights are negative (clamp-to-0 then sum-0)", function()
            -- Arrange
            PersonalityConfig.rollWeights = { Hyper = -1, Lazy = -1, Chaotic = -1, Loyal = -1, Rebel = -1 }

            -- Act
            local weights = PersonalityConfig.validate()

            -- Assert: every key recovered to the uniform fallback.
            for _, k in ipairs(PersonalityConfig.order) do
                expect(weights[k]).to.equal(20)
            end
        end)

        it("does NOT mutate the caller's source rollWeights table", function()
            -- Arrange
            PersonalityConfig.rollWeights = { Hyper = -5, Lazy = 20, Chaotic = 20, Loyal = 20, Rebel = 20 }

            -- Act
            PersonalityConfig.validate()

            -- Assert: source still holds the (invalid) -5; only the RETURN is sanitized.
            expect(PersonalityConfig.rollWeights.Hyper).to.equal(-5)
        end)
    end)
end
