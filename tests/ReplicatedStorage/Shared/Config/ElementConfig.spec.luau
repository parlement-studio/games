--!nocheck
-- tests/ReplicatedStorage/Shared/Config/ElementConfig.spec.luau
--
-- TestEZ specs for ElementConfig (design/decisions/2026-06-07-element-system.md
-- E1-E5). AAA pattern, isolated tests, no external services. Mirrors the
-- PersonalityConfig.spec idiom: tests that override config fields restore them
-- in afterEach.
--
-- Covers:
--   * E2 table transcription (5 elements, locked circle, locked default mods)
--   * elementMod: advantage / disadvantage / neutral / same-vs-same     (E5)
--   * elementMod: nil/invalid element -> neutral + logged               (§5 #2-#3)
--   * full-circle property: each element beats exactly one, loses to one (E2)
--   * validate(): clamp / inject / uniform-fallback (PersonalityConfig parity)
--   * rollElement: valid output, deterministic under a seeded Random,
--     all five reachable, zero-weight key never rolled                  (E3)

return function()
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local ElementConfig = require(ReplicatedStorage.Shared.Config.ElementConfig)

    local savedWeights
    local savedOrder

    beforeEach(function()
        savedWeights = ElementConfig.rollWeights
        savedOrder = ElementConfig.order
    end)

    afterEach(function()
        ElementConfig.rollWeights = savedWeights
        ElementConfig.order = savedOrder
    end)

    describe("E2 table transcription", function()
        it("declares version 1 and exactly the five canonical elements", function()
            -- Assert
            expect(ElementConfig.version).to.equal(1)
            expect(#ElementConfig.order).to.equal(5)
            local set = {}
            for _, k in ipairs(ElementConfig.order) do
                set[k] = true
            end
            expect(set.Fire).to.equal(true)
            expect(set.Nature).to.equal(true)
            expect(set.Water).to.equal(true)
            expect(set.Volt).to.equal(true)
            expect(set.Wind).to.equal(true)
        end)

        it("declares the LOCKED one-way circle Fire>Nature>Water>Volt>Wind>Fire", function()
            -- Assert
            expect(ElementConfig.beats.Fire).to.equal("Nature")
            expect(ElementConfig.beats.Nature).to.equal("Water")
            expect(ElementConfig.beats.Water).to.equal("Volt")
            expect(ElementConfig.beats.Volt).to.equal("Wind")
            expect(ElementConfig.beats.Wind).to.equal("Fire")
        end)

        it("declares the locked default mods 1.25 / 0.75 / 1.0 and uniform weights", function()
            -- Assert
            expect(ElementConfig.advantageMod).to.equal(1.25)
            expect(ElementConfig.disadvantageMod).to.equal(0.75)
            expect(ElementConfig.neutralMod).to.equal(1.0)
            for _, k in ipairs(ElementConfig.order) do
                expect(ElementConfig.rollWeights[k]).to.equal(20)
            end
        end)

        it("each element beats exactly ONE and is beaten by exactly ONE (circle property)", function()
            -- Arrange: count inbound edges per element.
            local beatenBy = {}
            for _, k in ipairs(ElementConfig.order) do
                beatenBy[k] = 0
            end

            -- Act
            for _, attacker in ipairs(ElementConfig.order) do
                local target = ElementConfig.beats[attacker]
                beatenBy[target] = beatenBy[target] + 1
            end

            -- Assert: every element has exactly one inbound edge, none beats itself.
            for _, k in ipairs(ElementConfig.order) do
                expect(beatenBy[k]).to.equal(1)
                expect(ElementConfig.beats[k]).never.to.equal(k)
            end
        end)
    end)

    describe("isValidElement", function()
        it("accepts all five canonical elements and rejects everything else", function()
            -- Assert
            for _, k in ipairs(ElementConfig.order) do
                expect(ElementConfig.isValidElement(k)).to.equal(true)
            end
            expect(ElementConfig.isValidElement("Dark")).to.equal(false)
            expect(ElementConfig.isValidElement("fire")).to.equal(false) -- case-sensitive
            expect(ElementConfig.isValidElement(nil)).to.equal(false)
            expect(ElementConfig.isValidElement(3)).to.equal(false)
            expect(ElementConfig.isValidElement({})).to.equal(false)
        end)
    end)

    describe("elementMod (E5)", function()
        it("returns advantageMod when the attacker beats the defender", function()
            -- Act + Assert: every advantage pairing on the circle.
            expect(ElementConfig.elementMod("Fire", "Nature")).to.equal(1.25)
            expect(ElementConfig.elementMod("Nature", "Water")).to.equal(1.25)
            expect(ElementConfig.elementMod("Water", "Volt")).to.equal(1.25)
            expect(ElementConfig.elementMod("Volt", "Wind")).to.equal(1.25)
            expect(ElementConfig.elementMod("Wind", "Fire")).to.equal(1.25)
        end)

        it("returns disadvantageMod when the defender beats the attacker", function()
            -- Act + Assert: the same circle read backwards.
            expect(ElementConfig.elementMod("Nature", "Fire")).to.equal(0.75)
            expect(ElementConfig.elementMod("Water", "Nature")).to.equal(0.75)
            expect(ElementConfig.elementMod("Volt", "Water")).to.equal(0.75)
            expect(ElementConfig.elementMod("Wind", "Volt")).to.equal(0.75)
            expect(ElementConfig.elementMod("Fire", "Wind")).to.equal(0.75)
        end)

        it("returns neutral for same-vs-same (element doc §5 #2)", function()
            -- Act + Assert
            for _, k in ipairs(ElementConfig.order) do
                expect(ElementConfig.elementMod(k, k)).to.equal(1.0)
            end
        end)

        it("returns neutral for non-adjacent pairings (two steps apart on the circle)", function()
            -- Fire and Water are two steps apart: neither beats the other.
            expect(ElementConfig.elementMod("Fire", "Water")).to.equal(1.0)
            expect(ElementConfig.elementMod("Water", "Fire")).to.equal(1.0)
            expect(ElementConfig.elementMod("Nature", "Volt")).to.equal(1.0)
            expect(ElementConfig.elementMod("Volt", "Nature")).to.equal(1.0)
        end)

        it("falls back to neutral AND logs when either element is nil/invalid (§5 #3)", function()
            -- Arrange
            local logged = 0
            local logger = function(event)
                if event == "elementmod_invalid_element" then
                    logged = logged + 1
                end
            end

            -- Act + Assert: nil attacker, invalid defender, both bad.
            expect(ElementConfig.elementMod(nil, "Fire", logger)).to.equal(1.0)
            expect(ElementConfig.elementMod("Fire", "Shadow", logger)).to.equal(1.0)
            expect(ElementConfig.elementMod(nil, nil, logger)).to.equal(1.0)
            expect(logged).to.equal(3)
        end)
    end)

    describe("validate (PersonalityConfig parity)", function()
        it("returns the same weights for a healthy uniform table", function()
            -- Act
            local weights = ElementConfig.validate()

            -- Assert
            local sum = 0
            for _, k in ipairs(ElementConfig.order) do
                expect(weights[k]).to.equal(20)
                sum += weights[k]
            end
            expect(sum).to.equal(100)
        end)

        it("clamps a negative weight to 0 and logs", function()
            -- Arrange
            ElementConfig.rollWeights = { Fire = -50, Nature = 20, Water = 20, Volt = 20, Wind = 20 }
            local clamped = false
            local logger = function(event)
                if event == "weight_clamped" then
                    clamped = true
                end
            end

            -- Act
            local weights = ElementConfig.validate(logger)

            -- Assert
            expect(weights.Fire).to.equal(0)
            expect(weights.Nature).to.equal(20)
            expect(clamped).to.equal(true)
        end)

        it("injects a missing order key at weight 0 and logs", function()
            -- Arrange: omit Wind entirely.
            ElementConfig.rollWeights = { Fire = 20, Nature = 20, Water = 20, Volt = 20 }
            local missing = false
            local logger = function(event, payload)
                if event == "weight_missing" and payload.key == "Wind" then
                    missing = true
                end
            end

            -- Act
            local weights = ElementConfig.validate(logger)

            -- Assert
            expect(weights.Wind).to.equal(0)
            expect(missing).to.equal(true)
        end)

        it("falls back to uniform when the post-clamp sum is 0 (critical)", function()
            -- Arrange
            ElementConfig.rollWeights = { Fire = 0, Nature = 0, Water = 0, Volt = 0, Wind = 0 }
            local fellBack = false
            local logger = function(event)
                if event == "rollweights_zero_fallback" then
                    fellBack = true
                end
            end

            -- Act
            local weights = ElementConfig.validate(logger)

            -- Assert
            for _, k in ipairs(ElementConfig.order) do
                expect(weights[k]).to.equal(20)
            end
            expect(fellBack).to.equal(true)
        end)

        it("does NOT mutate the caller's source rollWeights table", function()
            -- Arrange
            ElementConfig.rollWeights = { Fire = -5, Nature = 20, Water = 20, Volt = 20, Wind = 20 }

            -- Act
            ElementConfig.validate()

            -- Assert
            expect(ElementConfig.rollWeights.Fire).to.equal(-5)
        end)
    end)

    describe("rollElement (E3)", function()
        it("always returns a valid element", function()
            -- Act + Assert: many rolls, every result in the enum.
            local rng = Random.new(42)
            for _ = 1, 200 do
                local rolled = ElementConfig.rollElement(rng)
                expect(ElementConfig.isValidElement(rolled)).to.equal(true)
            end
        end)

        it("is deterministic under the same seeded Random", function()
            -- Arrange
            local a = Random.new(1337)
            local b = Random.new(1337)

            -- Act + Assert: identical sequences.
            for _ = 1, 50 do
                expect(ElementConfig.rollElement(a)).to.equal(ElementConfig.rollElement(b))
            end
        end)

        it("reaches ALL five elements over many uniform rolls", function()
            -- Arrange
            local rng = Random.new(7)
            local seen = {}

            -- Act
            for _ = 1, 500 do
                seen[ElementConfig.rollElement(rng)] = true
            end

            -- Assert
            for _, k in ipairs(ElementConfig.order) do
                expect(seen[k]).to.equal(true)
            end
        end)

        it("NEVER rolls a zero-weight element (weights override)", function()
            -- Arrange: Fire is disabled by the designer.
            local weights = { Fire = 0, Nature = 25, Water = 25, Volt = 25, Wind = 25 }
            local rng = Random.new(99)

            -- Act + Assert
            for _ = 1, 300 do
                expect(ElementConfig.rollElement(rng, weights)).never.to.equal("Fire")
            end
        end)

        it("survives an all-zero weights table via the validate() fallback (no infinite loop / nil)", function()
            -- Arrange: designer shipped sum=0; rollElement defaults weights via validate().
            ElementConfig.rollWeights = { Fire = 0, Nature = 0, Water = 0, Volt = 0, Wind = 0 }
            local rng = Random.new(5)

            -- Act
            local rolled = ElementConfig.rollElement(rng)

            -- Assert: still a valid element (uniform fallback inside validate()).
            expect(ElementConfig.isValidElement(rolled)).to.equal(true)
        end)
    end)
end
