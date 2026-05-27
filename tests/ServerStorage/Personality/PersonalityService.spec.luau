--!nocheck
-- tests/ServerStorage/Personality/PersonalityService.spec.luau
--
-- TestEZ specs for PersonalityService (System #2), per personality-gdd v1.1.
-- AAA pattern, isolated tests (runtime + caches reset between each), injected
-- RNG + clock for determinism, and the MockDataStore + PlayerDataService test
-- hooks (_setProfileForTest / setDataStoreService) so reroll/repair exercise the
-- REAL atomic write path WITHOUT touching a real store.
--
-- Covers the Acceptance Criteria:
--   * roll distribution over many seeded draws ~= rollWeights           (F5 / AC)
--   * getProductionModifier math (F1): personalityMult, Chaotic x2/x0,
--     paused (OnBreak/Walkout), morale neighbor factor                  (F1)
--   * getBattleBehavior returns the right tag + params per personality  (F4)
--   * isImmuneToNegative / getMoraleAura                                (queries)
--   * state machine allows ONLY Working/OnBreak/Walkout with injected
--     clock; Hyper break (F2); Rebel walkout + contagion (F3)           (§2.5)
--   * Walkout chaining terminates + is duration/cooldown bounded        (E2)
--   * reroll writes via the atomic path + is idempotent (E7) + rejects
--     in_battle (E4) + honors guaranteeDifferent                        (F5/E4/E7)
--   * validateOrRepair repairs unknown/missing enum + emits change      (E5)
--   * events PersonalityChanged / PersonalityMoment / WalkoutStarted    (§5.3)

return function()
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local ServerStorage = game:GetService("ServerStorage")

    local PersonalityService = require(ServerStorage.Personality.PersonalityService)
    local PersonalityConfig = require(ReplicatedStorage.Shared.Config.PersonalityConfig)
    local PlayerDataService = require(ServerStorage.PlayerData.PlayerDataService)
    local SessionLock = require(ServerStorage.PlayerData.SessionLock)
    local Schema = require(ServerStorage.PlayerData.Schema)
    -- MockDataStore lives under tests/ServerStorage/PlayerData (synced into
    -- ReplicatedStorage.Tests by test.project.json). Reference it there so we
    -- never touch a real store (mirrors the persistence spec's mock usage).
    local MockDataStore = require(ReplicatedStorage.Tests.ServerStorage.PlayerData.MockDataStore)

    local mockService

    -- Minimal mock Player (PlayerDataService only reads .UserId).
    local function mockPlayer(userId)
        return { UserId = userId, Name = "P" .. userId }
    end

    -- A controllable RNG: feed a queue of values in [0,1); falls back to a fixed
    -- value once drained so a stray call never errors.
    local function makeRng(values)
        local i = 0
        return function()
            i += 1
            if values[i] ~= nil then
                return values[i]
            end
            return 0.999999
        end
    end

    -- A controllable clock: returns whatever `t` is set to.
    local fakeClock = { t = 0 }

    -- Seed one Brainrot into a player's profile and return (player, entry).
    local function seedBrainrot(userId, personality)
        local player = mockPlayer(userId)
        PlayerDataService._setProfileForTest(userId, Schema.default(), player)
        local entry = Schema.newBrainrot({
            species = 1,
            personality = personality,
            source = "manual",
            hotspotId = "",
        })
        PlayerDataService.addBrainrot(player, entry)
        return player, PlayerDataService.getBrainrot(player, entry.id)
    end

    beforeEach(function()
        mockService = MockDataStore.newService()
        PlayerDataService.setDataStoreService(mockService)
        PlayerDataService.setLogger(function() end)
        SessionLock.setJobId("job-self")
        PlayerDataService._resetForTest()

        PersonalityService._resetForTest()
        PersonalityService.setLogger(function() end)
        fakeClock.t = 1000
        PersonalityService.setClock(function()
            return fakeClock.t
        end)
        -- Default deterministic RNG (overridden per-test as needed).
        PersonalityService.setRandom(makeRng({}))
    end)

    afterEach(function()
        PersonalityService._resetForTest()
        PlayerDataService._resetForTest()
    end)

    -- ── ROLL DISTRIBUTION (F5) ──────────────────────────────────────────────

    describe("rollPersonality distribution (F5)", function()
        it("draws each personality in proportion to rollWeights over many seeded draws", function()
            -- Arrange: a uniform RNG that sweeps [0,1) in even steps so the
            -- weighted picker lands in each band proportionally (deterministic).
            local draws = 10000
            local seq = {}
            for n = 1, draws do
                seq[n] = (n - 0.5) / draws -- midpoints across [0,1)
            end
            PersonalityService.setRandom(makeRng(seq))
            PersonalityService._resetValidatedWeightsForTest()

            local counts = { Hyper = 0, Lazy = 0, Chaotic = 0, Loyal = 0, Rebel = 0 }

            -- Act
            for _ = 1, draws do
                counts[PersonalityService.rollPersonality()] += 1
            end

            -- Assert: uniform 20% each -> ~2000 per personality (tight band, the
            -- sweep is exact so tolerance can be small).
            for _, k in ipairs(PersonalityConfig.order) do
                local frac = counts[k] / draws
                expect(frac > 0.18).to.equal(true)
                expect(frac < 0.22).to.equal(true)
            end
        end)

        it("respects a skewed weight table (the heavy key dominates)", function()
            -- Arrange: Hyper heavily weighted.
            local savedWeights = PersonalityConfig.rollWeights
            PersonalityConfig.rollWeights = { Hyper = 80, Lazy = 5, Chaotic = 5, Loyal = 5, Rebel = 5 }
            PersonalityService._resetValidatedWeightsForTest()
            local draws = 2000
            local seq = {}
            for n = 1, draws do
                seq[n] = (n - 0.5) / draws
            end
            PersonalityService.setRandom(makeRng(seq))
            local counts = { Hyper = 0, Lazy = 0, Chaotic = 0, Loyal = 0, Rebel = 0 }

            -- Act
            for _ = 1, draws do
                counts[PersonalityService.rollPersonality()] += 1
            end

            -- Assert: Hyper ~80%.
            local hyperFrac = counts.Hyper / draws
            expect(hyperFrac > 0.78).to.equal(true)
            expect(hyperFrac < 0.82).to.equal(true)

            PersonalityConfig.rollWeights = savedWeights
            PersonalityService._resetValidatedWeightsForTest()
        end)
    end)

    -- ── PRODUCTION MODIFIER (F1) ─────────────────────────────────────────────

    describe("getProductionModifier (F1)", function()
        it("applies the flat personalityMult for a Working Loyal (steady 1.0, not paused)", function()
            -- Arrange
            local entry = { id = "e1", personality = "Loyal" }

            -- Act
            local mod = PersonalityService.getProductionModifier(entry, {})

            -- Assert
            expect(mod.multiplier).to.equal(1.0)
            expect(mod.paused).to.equal(false)
            expect(mod.cycleOutcome).to.equal(nil)
        end)

        it("applies Hyper +30% (1.30) while Working", function()
            local mod = PersonalityService.getProductionModifier({ id = "h1", personality = "Hyper" }, {})
            expect(mod.multiplier).to.equal(1.30)
            expect(mod.paused).to.equal(false)
        end)

        it("applies Lazy -50% (0.50) and reports its own rate (aura is the neighbor's concern)", function()
            local mod = PersonalityService.getProductionModifier({ id = "l1", personality = "Lazy" }, {})
            expect(mod.multiplier).to.equal(0.50)
        end)

        it("Chaotic DOUBLES on a double-cycle roll and records the outcome (F1 / E3)", function()
            -- Arrange: RNG below doubleChance (0.50) -> double.
            PersonalityService.setRandom(makeRng({ 0.10 }))

            -- Act
            local mod = PersonalityService.getProductionModifier({ id = "c1", personality = "Chaotic" }, {})

            -- Assert: 1.0 * doubleMultiplier(2.0) = 2.0
            expect(mod.multiplier).to.equal(2.0)
            expect(mod.cycleOutcome).to.equal("double")
            expect(PersonalityService.getRuntime("c1").lastCycleOutcome).to.equal("double")
        end)

        it("Chaotic ZEROES on a zero-cycle roll (single producer is valid, E3)", function()
            -- Arrange: RNG at/above doubleChance -> zero.
            PersonalityService.setRandom(makeRng({ 0.90 }))

            -- Act
            local mod = PersonalityService.getProductionModifier({ id = "c2", personality = "Chaotic" }, {})

            -- Assert: 1.0 * zeroMultiplier(0.0) = 0.0
            expect(mod.multiplier).to.equal(0.0)
            expect(mod.cycleOutcome).to.equal("zero")
        end)

        it("applies the Lazy morale neighbor factor to a non-Lazy with an eligible Lazy neighbor", function()
            -- Arrange: a Loyal with a Lazy neighbor reported by the caller.
            -- Act
            local mod = PersonalityService.getProductionModifier(
                { id = "n1", personality = "Loyal" },
                { hasLazyNeighbor = true }
            )

            -- Assert: 1.0 * neighborMultiplier(1.15)
            expect(mod.multiplier).to.equal(1.15)
        end)

        it("does NOT apply the morale factor to a Lazy recipient (E1, moraleAuraAffectsLazy=false)", function()
            -- Arrange: a Lazy with a Lazy neighbor.
            local mod = PersonalityService.getProductionModifier(
                { id = "n2", personality = "Lazy" },
                { hasLazyNeighbor = true }
            )

            -- Assert: stays at its own 0.50 (no neighbor buff applied to Lazy).
            expect(mod.multiplier).to.equal(0.50)
        end)

        it("reports paused=true while OnBreak and while Walkout", function()
            -- Arrange
            PersonalityService._setRuntimeForTest("p1", { state = "OnBreak", stateStartedAt = 0 })
            PersonalityService._setRuntimeForTest("p2", { state = "Walkout", stateStartedAt = 0 })

            -- Act / Assert
            local m1 = PersonalityService.getProductionModifier({ id = "p1", personality = "Hyper" }, {})
            local m2 = PersonalityService.getProductionModifier({ id = "p2", personality = "Rebel" }, {})
            expect(m1.paused).to.equal(true)
            expect(m2.paused).to.equal(true)
        end)

        it("treats an unknown personality as the fallback for one tick (E5)", function()
            -- Arrange: garbage enum; fallback is Loyal (1.0).
            local mod = PersonalityService.getProductionModifier({ id = "u1", personality = "???" }, {})

            -- Assert
            expect(mod.multiplier).to.equal(1.0)
        end)
    end)

    -- ── BATTLE BEHAVIOR (F4) ─────────────────────────────────────────────────

    describe("getBattleBehavior (F4)", function()
        it("returns act_first_mistarget + mistargetChance for Hyper", function()
            local b = PersonalityService.getBattleBehavior("Hyper")
            expect(b.behaviorTag).to.equal("act_first_mistarget")
            expect(b.params.mistargetChance).to.equal(0.20)
        end)

        it("returns berserk_when_last + defense/berserk multipliers for Lazy", function()
            local b = PersonalityService.getBattleBehavior("Lazy")
            expect(b.behaviorTag).to.equal("berserk_when_last")
            expect(b.params.defenseMultiplier).to.equal(1.75)
            expect(b.params.berserkAttackMultiplier).to.equal(2.50)
        end)

        it("returns random_moveset + randomFromAnyMoveset for Chaotic", function()
            local b = PersonalityService.getBattleBehavior("Chaotic")
            expect(b.behaviorTag).to.equal("random_moveset")
            expect(b.params.randomFromAnyMoveset).to.equal(true)
        end)

        it("returns bodyguard + threshold/fraction for Loyal", function()
            local b = PersonalityService.getBattleBehavior("Loyal")
            expect(b.behaviorTag).to.equal("bodyguard")
            expect(b.params.bodyguardAllyHpThreshold).to.equal(0.30)
            expect(b.params.bodyguardDamageTakenFraction).to.equal(1.0)
        end)

        it("returns counter_double + counterDamageMultiplier for Rebel", function()
            local b = PersonalityService.getBattleBehavior("Rebel")
            expect(b.behaviorTag).to.equal("counter_double")
            expect(b.params.counterDamageMultiplier).to.equal(2.0)
        end)
    end)

    describe("simple config queries", function()
        it("isImmuneToNegative is true only for Loyal", function()
            expect(PersonalityService.isImmuneToNegative("Loyal")).to.equal(true)
            expect(PersonalityService.isImmuneToNegative("Hyper")).to.equal(false)
        end)

        it("getMoraleAura returns the aura only for Lazy", function()
            local aura = PersonalityService.getMoraleAura("Lazy")
            expect(aura).to.be.ok()
            expect(aura.neighborMultiplier).to.equal(1.15)
            expect(PersonalityService.getMoraleAura("Loyal")).to.equal(nil)
        end)
    end)

    -- ── STATE MACHINE: HYPER BREAK (F2) ──────────────────────────────────────

    describe("Hyper break (F2)", function()
        it("transitions Working -> OnBreak when the break roll succeeds + emits a Moment", function()
            -- Arrange: RNG below breakChance (0.10).
            PersonalityService.setRandom(makeRng({ 0.05 }))
            local moment
            PersonalityService.PersonalityMoment:Connect(function(p)
                moment = p
            end)
            local entry = { id = "hb1", personality = "Hyper" }

            -- Act
            local broke = PersonalityService.tryStartBreak(entry, 2000)

            -- Assert
            expect(broke).to.equal(true)
            expect(PersonalityService.getState("hb1")).to.equal("OnBreak")
            expect(moment.momentType).to.equal("break_started")
        end)

        it("does NOT break when the roll fails", function()
            PersonalityService.setRandom(makeRng({ 0.50 }))
            local broke = PersonalityService.tryStartBreak({ id = "hb2", personality = "Hyper" }, 2000)
            expect(broke).to.equal(false)
            expect(PersonalityService.getState("hb2")).to.equal("Working")
        end)

        it("never breaks a non-Hyper personality", function()
            PersonalityService.setRandom(makeRng({ 0.01 }))
            local broke = PersonalityService.tryStartBreak({ id = "hb3", personality = "Loyal" }, 2000)
            expect(broke).to.equal(false)
        end)

        it("auto-recovers OnBreak -> Working after breakDurationSeconds (update tick)", function()
            -- Arrange: start a break at t=2000 (duration 20).
            PersonalityService.setRandom(makeRng({ 0.05 }))
            PersonalityService.tryStartBreak({ id = "hb4", personality = "Hyper" }, 2000)
            expect(PersonalityService.getState("hb4")).to.equal("OnBreak")

            -- Act: tick before duration -> still OnBreak; tick after -> Working.
            PersonalityService.update({ hb4 = "Hyper" }, 2010)
            expect(PersonalityService.getState("hb4")).to.equal("OnBreak")
            local fired = PersonalityService.update({ hb4 = "Hyper" }, 2025)

            -- Assert
            expect(PersonalityService.getState("hb4")).to.equal("Working")
            expect(#fired).to.equal(1)
            expect(fired[1].to).to.equal("Working")
        end)
    end)

    -- ── STATE MACHINE: REBEL WALKOUT + CONTAGION (F3 / E2) ───────────────────

    describe("Rebel walkout (F3)", function()
        it("does NOT walk out below the overwork rebel count", function()
            PersonalityService.setRandom(makeRng({ 0.01 }))
            local started = PersonalityService.tryStartWalkout(
                { id = "w1", personality = "Rebel" },
                { rebelCount = 2, neighbors = {} }, -- below overworkRebelCount(3)
                3000
            )
            expect(started).to.equal(false)
            expect(PersonalityService.getState("w1")).to.equal("Working")
        end)

        it("starts a Walkout when overworked + the trigger roll succeeds, emitting WalkoutStarted", function()
            -- Arrange: rebelCount >= 3; one neighbor that does NOT chain.
            -- RNG: [trigger 0.05 (<0.15)], [contagion 0.99 (>=0.40) -> no chain].
            PersonalityService.setRandom(makeRng({ 0.05, 0.99 }))
            local walkoutEvent
            PersonalityService.WalkoutStarted:Connect(function(p)
                walkoutEvent = p
            end)
            local neighbor = { id = "wn1", personality = "Loyal" }

            -- Act
            local started, dragged = PersonalityService.tryStartWalkout(
                { id = "w2", personality = "Rebel" },
                { rebelCount = 3, neighbors = { neighbor } },
                3000
            )

            -- Assert: initiator walks out; neighbor did NOT chain.
            expect(started).to.equal(true)
            expect(PersonalityService.getState("w2")).to.equal("Walkout")
            expect(PersonalityService.getState("wn1")).to.equal("Working")
            expect(#dragged).to.equal(0)
            expect(walkoutEvent.id).to.equal("w2")
        end)

        it("drags a co-located neighbor when the contagion roll succeeds (E2 single roll per neighbor)", function()
            -- Arrange: RNG: [trigger 0.05], [contagion 0.10 (<0.40) -> chain].
            PersonalityService.setRandom(makeRng({ 0.05, 0.10 }))
            local neighbor = { id = "wn2", personality = "Loyal" }

            -- Act
            local started, dragged = PersonalityService.tryStartWalkout(
                { id = "w3", personality = "Rebel" },
                { rebelCount = 3, neighbors = { neighbor } },
                3000
            )

            -- Assert: neighbor dragged in, draggedInBy recorded.
            expect(started).to.equal(true)
            expect(#dragged).to.equal(1)
            expect(dragged[1]).to.equal("wn2")
            expect(PersonalityService.getState("wn2")).to.equal("Walkout")
            expect(PersonalityService.getRuntime("wn2").draggedInBy).to.equal("w3")
        end)

        it("is suppressed while the building is on cooldown (E2 guard d)", function()
            PersonalityService.setRandom(makeRng({ 0.01, 0.01 }))
            local started = PersonalityService.tryStartWalkout(
                { id = "w4", personality = "Rebel" },
                { rebelCount = 5, neighbors = {}, cooldownUntil = 5000 },
                3000 -- now < cooldownUntil
            )
            expect(started).to.equal(false)
        end)

        it("TERMINATES contagion: a full building of co-located neighbors rolls exactly once each (E2)", function()
            -- Arrange: 50 neighbors, trigger succeeds, EVERY contagion roll
            -- succeeds (worst case = whole building walks out). The picker rolls
            -- once per neighbor and never recurses, so it must terminate.
            local seq = { 0.05 } -- trigger
            for _ = 1, 50 do
                seq[#seq + 1] = 0.01 -- each contagion succeeds
            end
            PersonalityService.setRandom(makeRng(seq))
            local neighbors = {}
            for i = 1, 50 do
                neighbors[i] = { id = "bn" .. i, personality = "Rebel" }
            end

            -- Act
            local started, dragged = PersonalityService.tryStartWalkout(
                { id = "w5", personality = "Rebel" },
                { rebelCount = 51, neighbors = neighbors },
                3000
            )

            -- Assert: terminated; all 50 dragged exactly once (no re-roll loop).
            expect(started).to.equal(true)
            expect(#dragged).to.equal(50)
            expect(PersonalityService.getState("bn1")).to.equal("Walkout")
            expect(PersonalityService.getState("bn50")).to.equal("Walkout")
        end)

        it("auto-recovers Walkout -> Working bounded by min(duration, maxDuration) + reports cooldown (E2)", function()
            -- Arrange: start a walkout at t=3000. duration 300, max 600 ->
            -- min = 300, recovers at t >= 3300.
            PersonalityService.setRandom(makeRng({ 0.05 }))
            PersonalityService.tryStartWalkout(
                { id = "w6", personality = "Rebel" },
                { rebelCount = 3, neighbors = {} },
                3000
            )
            expect(PersonalityService.getState("w6")).to.equal("Walkout")

            -- Act: before bound -> still Walkout; at bound -> Working + cooldown.
            PersonalityService.update({ w6 = "Rebel" }, 3200)
            expect(PersonalityService.getState("w6")).to.equal("Walkout")
            local fired = PersonalityService.update({ w6 = "Rebel" }, 3301)

            -- Assert
            expect(PersonalityService.getState("w6")).to.equal("Working")
            expect(#fired).to.equal(1)
            expect(fired[1].from).to.equal("Walkout")
            expect(fired[1].cooldownSeconds).to.equal(600) -- walkoutCooldownSeconds
        end)
    end)

    -- ── STATE MACHINE GUARD: ONLY ALLOWED TRANSITIONS ───────────────────────

    describe("state machine transition guard (§2.5)", function()
        it("cannot start a break while already OnBreak (no OnBreak->OnBreak)", function()
            PersonalityService.setRandom(makeRng({ 0.01, 0.01 }))
            PersonalityService.tryStartBreak({ id = "g1", personality = "Hyper" }, 1000)
            expect(PersonalityService.getState("g1")).to.equal("OnBreak")
            -- A second attempt while OnBreak is a no-op (guard: state ~= Working).
            local broke = PersonalityService.tryStartBreak({ id = "g1", personality = "Hyper" }, 1000)
            expect(broke).to.equal(false)
            expect(PersonalityService.getState("g1")).to.equal("OnBreak")
        end)

        it("cannot start a walkout while OnBreak (state must be Working)", function()
            PersonalityService.setRandom(makeRng({ 0.01 }))
            PersonalityService.tryStartBreak({ id = "g2", personality = "Hyper" }, 1000)
            -- Now Hyper is OnBreak; even as Rebel-context it cannot walk out.
            PersonalityService.setRandom(makeRng({ 0.01 }))
            local started = PersonalityService.tryStartWalkout(
                { id = "g2", personality = "Rebel" },
                { rebelCount = 9, neighbors = {} },
                1000
            )
            expect(started).to.equal(false)
            expect(PersonalityService.getState("g2")).to.equal("OnBreak")
        end)
    end)

    -- ── REROLL (F5 / E4 / E7) ────────────────────────────────────────────────

    describe("rerollPersonality (F5 / E4 / E7)", function()
        it("re-draws + writes the personality field through the atomic path + emits PersonalityChanged", function()
            -- Arrange: a roster Loyal; RNG that draws Hyper (first band).
            local player, entry = seedBrainrot(3001, "Loyal")
            PersonalityService.setRandom(makeRng({ 0.0 })) -- first key in order = Hyper
            local changed
            PersonalityService.PersonalityChanged:Connect(function(p)
                changed = p
            end)

            -- Act
            local ok, result = PersonalityService.rerollPersonality(player, entry.id)

            -- Assert: field updated in the profile; event fired.
            expect(ok).to.equal(true)
            expect(result).to.equal("Hyper")
            expect(PlayerDataService.getBrainrot(player, entry.id).personality).to.equal("Hyper")
            expect(changed.oldPersonality).to.equal("Loyal")
            expect(changed.newPersonality).to.equal("Hyper")
            -- runtime reset to Working.
            expect(PersonalityService.getState(entry.id)).to.equal("Working")
        end)

        it("is idempotent: a retried idempotencyKey returns the prior result + does NOT re-roll (E7)", function()
            -- Arrange
            local player, entry = seedBrainrot(3002, "Loyal")
            -- First draw -> Hyper; a SECOND (if it ran) would draw Rebel.
            PersonalityService.setRandom(makeRng({ 0.0, 0.99 }))
            local key = "reroll-tx-1"
            local fireCount = 0
            PersonalityService.PersonalityChanged:Connect(function()
                fireCount += 1
            end)

            -- Act: same key twice (a retried request after a laggy ack).
            local ok1, r1 = PersonalityService.rerollPersonality(player, entry.id, { idempotencyKey = key })
            local ok2, r2 = PersonalityService.rerollPersonality(player, entry.id, { idempotencyKey = key })

            -- Assert: both succeed, SAME result, committed once, event fired once.
            expect(ok1).to.equal(true)
            expect(ok2).to.equal(true)
            expect(r1).to.equal("Hyper")
            expect(r2).to.equal("Hyper") -- prior stored result, not a fresh roll
            expect(PlayerDataService.getBrainrot(player, entry.id).personality).to.equal("Hyper")
            expect(fireCount).to.equal(1) -- no second PersonalityChanged on replay
        end)

        it("rejects with reason in_battle when the id is battle-locked (E4)", function()
            -- Arrange: a lock checker that locks this id.
            local player, entry = seedBrainrot(3003, "Loyal")
            PersonalityService.setBattleLockChecker(function(id)
                return id == entry.id
            end)

            -- Act
            local ok, reason = PersonalityService.rerollPersonality(player, entry.id)

            -- Assert: rejected, no change.
            expect(ok).to.equal(false)
            expect(reason).to.equal("in_battle")
            expect(PlayerDataService.getBrainrot(player, entry.id).personality).to.equal("Loyal")
        end)

        it("rejects not_found when the player does not own the id", function()
            local player = mockPlayer(3004)
            PlayerDataService._setProfileForTest(3004, Schema.default(), player)
            local ok, reason = PersonalityService.rerollPersonality(player, "no-such-id")
            expect(ok).to.equal(false)
            expect(reason).to.equal("not_found")
        end)

        it("honors guaranteeDifferent by excluding the current personality", function()
            -- Arrange: current Hyper. With guaranteeDifferent, an RNG of 0.0 would
            -- normally pick Hyper (first band); excluding Hyper, the first band is
            -- now Lazy -> must differ.
            local player, entry = seedBrainrot(3005, "Hyper")
            PersonalityService.setRandom(makeRng({ 0.0 }))

            -- Act
            local ok, result = PersonalityService.rerollPersonality(player, entry.id, { guaranteeDifferent = true })

            -- Assert: not Hyper.
            expect(ok).to.equal(true)
            expect(result).never.to.equal("Hyper")
        end)
    end)

    -- ── LOAD-TIME REPAIR (E5) ────────────────────────────────────────────────

    describe("validateOrRepair (E5)", function()
        it("leaves a valid entry untouched (no repair, no roll)", function()
            local player, entry = seedBrainrot(3010, "Chaotic")
            local repaired, personality = PersonalityService.validateOrRepair(player, entry.id, entry)
            expect(repaired).to.equal(false)
            expect(personality).to.equal("Chaotic")
        end)

        it("repairs an UNKNOWN enum: re-rolls, writes back, logs, emits change (E5)", function()
            -- Arrange: a roster entry with a corrupt personality value.
            local player = mockPlayer(3011)
            local data = Schema.default()
            local id = "corrupt-1"
            data.roster[id] = {
                id = id,
                species = 1,
                personality = "Banana", -- unknown enum
                level = 1,
                xp = 0,
                evoStage = 0,
                history = {},
                fav = false,
            }
            data.rosterCount = 1
            PlayerDataService._setProfileForTest(3011, data, player)
            PersonalityService.setRandom(makeRng({ 0.0 })) -- draws Hyper
            local logged = false
            PersonalityService.setLogger(function(event)
                if event == "personality_repaired" then
                    logged = true
                end
            end)
            local changed
            PersonalityService.PersonalityChanged:Connect(function(p)
                changed = p
            end)

            -- Act
            local repaired, personality = PersonalityService.validateOrRepair(player, id, data.roster[id])

            -- Assert: re-rolled to a valid enum, written back, logged, event fired.
            expect(repaired).to.equal(true)
            expect(personality).to.equal("Hyper")
            expect(PlayerDataService.getBrainrot(player, id).personality).to.equal("Hyper")
            expect(logged).to.equal(true)
            expect(changed.oldPersonality).to.equal(nil) -- (re)assignment, not a reroll
            expect(changed.newPersonality).to.equal("Hyper")
        end)

        it("repairs a MISSING/empty enum the same way (E5)", function()
            local player = mockPlayer(3012)
            local data = Schema.default()
            local id = "missing-1"
            data.roster[id] =
                { id = id, species = 1, personality = "", level = 1, xp = 0, evoStage = 0, history = {}, fav = false }
            data.rosterCount = 1
            PlayerDataService._setProfileForTest(3012, data, player)
            PersonalityService.setRandom(makeRng({ 0.0 }))

            local repaired, personality = PersonalityService.validateOrRepair(player, id, data.roster[id])
            expect(repaired).to.equal(true)
            expect(personality).to.equal("Hyper")
        end)
    end)

    -- ── EVENT CONTRACT (§5.3) ────────────────────────────────────────────────

    describe("event payloads (§5.3)", function()
        it("PersonalityMoment carries id, momentType, personality, payload, serverTime", function()
            -- Arrange
            PersonalityService.setRandom(makeRng({ 0.05 }))
            local moment
            PersonalityService.PersonalityMoment:Connect(function(p)
                moment = p
            end)

            -- Act
            PersonalityService.tryStartBreak({ id = "ev1", personality = "Hyper" }, 4000)

            -- Assert
            expect(moment.id).to.equal("ev1")
            expect(moment.momentType).to.equal("break_started")
            expect(moment.personality).to.equal("Hyper")
            expect(type(moment.payload)).to.equal("table")
            expect(type(moment.serverTime)).to.equal("number")
        end)

        it("WalkoutStarted carries id + draggedIds list", function()
            PersonalityService.setRandom(makeRng({ 0.05, 0.10 }))
            local walkout
            PersonalityService.WalkoutStarted:Connect(function(p)
                walkout = p
            end)

            PersonalityService.tryStartWalkout(
                { id = "ev2", personality = "Rebel" },
                { rebelCount = 3, neighbors = { { id = "evn", personality = "Loyal" } } },
                4000
            )

            expect(walkout.id).to.equal("ev2")
            expect(type(walkout.draggedIds)).to.equal("table")
            expect(walkout.draggedIds[1]).to.equal("evn")
        end)
    end)
end
