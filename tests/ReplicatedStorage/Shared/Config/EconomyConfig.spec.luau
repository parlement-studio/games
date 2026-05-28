--!nocheck
-- tests/ReplicatedStorage/Shared/Config/EconomyConfig.spec.luau
--
-- TestEZ specs for EconomyConfig (economy-gdd v1.2 §8). AAA pattern, isolated
-- tests. Pure-function helpers (upgradeCost / slotUnlockCost / rerollCost /
-- formatCoins / whitelist checks) need no mocks; validate() snapshot/restore
-- guards in-place repairs so a test cannot leak into the next.
--
-- Covers Acceptance Criteria:
--   * §8.1 table transcription (version + locked values + whitelists)
--   * §8.4 F-SINK-UPGRADE worked examples (factory n=0..29 + bounds)
--   * §8.5 F-SINK-REROLL LOCKED ladder + cap behavior
--   * §8.6 F-SINK-SLOT-UNLOCK + rosterCap guard
--   * §8.7 display formatter (K/M/B/T thresholds + below-threshold)
--   * §3.1 audit whitelist enforcement (faucet + sink reason checks)
--   * validate() repairs negatives / NaN / out-of-range / mangled lists

return function()
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local EconomyConfig = require(ReplicatedStorage.Shared.Config.EconomyConfig)

    -- Deep copy via JSON round-trip — sufficient for pure data tables. Restores
    -- the master table so a test that mutates a sub-field cannot leak.
    local HttpService = game:GetService("HttpService")
    local function snapshot()
        return HttpService:JSONDecode(HttpService:JSONEncode({
            maxBalance = EconomyConfig.maxBalance,
            minMutation = EconomyConfig.minMutation,
            questRewards = EconomyConfig.questRewards,
            questRewardFallbackCoins = EconomyConfig.questRewardFallbackCoins,
            rewardGenericCoins = EconomyConfig.rewardGenericCoins,
            faucetReasons = EconomyConfig.faucetReasons,
            captureCostCoins_REFERENCE = EconomyConfig.captureCostCoins_REFERENCE,
            raidSendCostCoins = EconomyConfig.raidSendCostCoins,
            dramaFixCostCoins = EconomyConfig.dramaFixCostCoins,
            sinkReasons = EconomyConfig.sinkReasons,
            upgrades = EconomyConfig.upgrades,
            slotUnlock = EconomyConfig.slotUnlock,
            reroll = EconomyConfig.reroll,
            displaySuffixes = EconomyConfig.displaySuffixes,
        }))
    end

    local saved
    beforeEach(function()
        saved = snapshot()
    end)
    afterEach(function()
        EconomyConfig.maxBalance = saved.maxBalance
        EconomyConfig.minMutation = saved.minMutation
        EconomyConfig.questRewards = saved.questRewards
        EconomyConfig.questRewardFallbackCoins = saved.questRewardFallbackCoins
        EconomyConfig.rewardGenericCoins = saved.rewardGenericCoins
        EconomyConfig.faucetReasons = saved.faucetReasons
        EconomyConfig.captureCostCoins_REFERENCE = saved.captureCostCoins_REFERENCE
        EconomyConfig.raidSendCostCoins = saved.raidSendCostCoins
        EconomyConfig.dramaFixCostCoins = saved.dramaFixCostCoins
        EconomyConfig.sinkReasons = saved.sinkReasons
        EconomyConfig.upgrades = saved.upgrades
        EconomyConfig.slotUnlock = saved.slotUnlock
        EconomyConfig.reroll = saved.reroll
        EconomyConfig.displaySuffixes = saved.displaySuffixes
    end)

    describe("§8.1 table transcription (locked values)", function()
        it("declares version 1 and the locked GLOBAL GUARDS", function()
            expect(EconomyConfig.version).to.equal(1)
            expect(EconomyConfig.maxBalance).to.equal(1e15)
            expect(EconomyConfig.minMutation).to.equal(1)
        end)

        it("carries the locked quest reward ranges for the four MVP quest types", function()
            expect(EconomyConfig.questRewards.capture_n.min).to.equal(100)
            expect(EconomyConfig.questRewards.capture_n.max).to.equal(200)
            expect(EconomyConfig.questRewards.win_raids.min).to.equal(150)
            expect(EconomyConfig.questRewards.win_raids.max).to.equal(300)
            expect(EconomyConfig.questRewards.collect_x.min).to.equal(100)
            expect(EconomyConfig.questRewards.collect_x.max).to.equal(200)
            expect(EconomyConfig.questRewards.evolve_one.min).to.equal(200)
            expect(EconomyConfig.questRewards.evolve_one.max).to.equal(350)
        end)

        it("carries the locked fallback + generic reward values", function()
            expect(EconomyConfig.questRewardFallbackCoins).to.equal(150)
            expect(EconomyConfig.rewardGenericCoins).to.equal(50)
        end)

        it("carries the locked flat sinks (raid_send=100, drama_fix=200)", function()
            expect(EconomyConfig.raidSendCostCoins).to.equal(100)
            expect(EconomyConfig.dramaFixCostCoins).to.equal(200)
        end)

        it("mirrors capture cost reference (25; CaptureConfig owns the authoritative value)", function()
            expect(EconomyConfig.captureCostCoins_REFERENCE).to.equal(25)
        end)

        it("includes the v1.2 field_combat_win faucet in the whitelist", function()
            local seen = {}
            for _, r in ipairs(EconomyConfig.faucetReasons) do
                seen[r] = true
            end
            expect(seen.idle_collect).to.equal(true)
            expect(seen.raid_loot).to.equal(true)
            expect(seen.field_combat_win).to.equal(true) -- v1.2 addition
            expect(seen.quest_daily).to.equal(true)
            expect(seen.reward_generic).to.equal(true)
            expect(seen.devproduct_pack).to.equal(true)
        end)

        it("declares the 8 sink reasons including the P2 drama_fix", function()
            local seen = {}
            for _, r in ipairs(EconomyConfig.sinkReasons) do
                seen[r] = true
            end
            expect(seen.capture).to.equal(true)
            expect(seen.upgrade_factory).to.equal(true)
            expect(seen.upgrade_worker_slot).to.equal(true)
            expect(seen.upgrade_storage).to.equal(true)
            expect(seen.raid_send).to.equal(true)
            expect(seen.reroll).to.equal(true)
            expect(seen.slot_unlock).to.equal(true)
            expect(seen.drama_fix).to.equal(true)
        end)

        it("declares the three upgrade tracks with locked base/growth/maxLevel", function()
            expect(EconomyConfig.upgrades.factory.base).to.equal(200)
            expect(EconomyConfig.upgrades.factory.growth).to.equal(1.35)
            expect(EconomyConfig.upgrades.factory.maxLevel).to.equal(30)
            expect(EconomyConfig.upgrades.workerSlot.base).to.equal(150)
            expect(EconomyConfig.upgrades.workerSlot.growth).to.equal(1.50)
            expect(EconomyConfig.upgrades.workerSlot.maxLevel).to.equal(10)
            expect(EconomyConfig.upgrades.storage.base).to.equal(300)
            expect(EconomyConfig.upgrades.storage.growth).to.equal(1.40)
            expect(EconomyConfig.upgrades.storage.maxLevel).to.equal(12)
        end)

        it("declares slotUnlock with startingSlots=25, slotsPerUnlock=5, rosterCap=200", function()
            expect(EconomyConfig.slotUnlock.startingSlots).to.equal(25)
            expect(EconomyConfig.slotUnlock.slotsPerUnlock).to.equal(5)
            expect(EconomyConfig.slotUnlock.rosterCap).to.equal(200)
            expect(EconomyConfig.slotUnlock.base).to.equal(250)
            expect(EconomyConfig.slotUnlock.growth).to.equal(1.20)
        end)

        it("declares the LOCKED reroll ladder {250, 600, 1200, 2000} + 24h reset", function()
            expect(EconomyConfig.reroll.costs[1]).to.equal(250)
            expect(EconomyConfig.reroll.costs[2]).to.equal(600)
            expect(EconomyConfig.reroll.costs[3]).to.equal(1200)
            expect(EconomyConfig.reroll.costs[4]).to.equal(2000)
            expect(EconomyConfig.reroll.resetHours).to.equal(24)
        end)
    end)

    describe("§8.4 F-SINK-UPGRADE (factory worked examples from GDD)", function()
        it("n=0 returns the base cost (200 for factory)", function()
            expect(EconomyConfig.upgradeCost("factory", 0)).to.equal(200)
        end)
        it("n=1 returns floor(200 * 1.35) = 270", function()
            expect(EconomyConfig.upgradeCost("factory", 1)).to.equal(270)
        end)
        it("n=2 returns floor(200 * 1.35^2) = 364", function()
            expect(EconomyConfig.upgradeCost("factory", 2)).to.equal(364)
        end)
        it("n=3 returns floor(200 * 1.35^3) = 492", function()
            expect(EconomyConfig.upgradeCost("factory", 3)).to.equal(492)
        end)
        it("n=5 returns floor(200 * 1.35^5) = 896", function()
            expect(EconomyConfig.upgradeCost("factory", 5)).to.equal(896)
        end)
        it("n=29 returns the last buyable level (under 1.3M)", function()
            local cost = EconomyConfig.upgradeCost("factory", 29)
            expect(cost > 1000000).to.equal(true)
            expect(cost < 2000000).to.equal(true)
        end)
        it("n=30 (at maxLevel) returns math.huge — nothing left to buy", function()
            expect(EconomyConfig.upgradeCost("factory", 30)).to.equal(math.huge)
        end)
        it("n=99 (past maxLevel) returns math.huge", function()
            expect(EconomyConfig.upgradeCost("factory", 99)).to.equal(math.huge)
        end)
        it("negative n is clamped to 0 (defensive)", function()
            expect(EconomyConfig.upgradeCost("factory", -5)).to.equal(200)
        end)
        it("unknown track returns math.huge (rejected unaffordable)", function()
            expect(EconomyConfig.upgradeCost("unknown_track", 0)).to.equal(math.huge)
        end)

        it("worker slot: n=0=150, n=9 valid, n=10 math.huge", function()
            expect(EconomyConfig.upgradeCost("workerSlot", 0)).to.equal(150)
            expect(EconomyConfig.upgradeCost("workerSlot", 9) < math.huge).to.equal(true)
            expect(EconomyConfig.upgradeCost("workerSlot", 10)).to.equal(math.huge)
        end)

        it("storage: n=0=300, n=11 valid, n=12 math.huge", function()
            expect(EconomyConfig.upgradeCost("storage", 0)).to.equal(300)
            expect(EconomyConfig.upgradeCost("storage", 11) < math.huge).to.equal(true)
            expect(EconomyConfig.upgradeCost("storage", 12)).to.equal(math.huge)
        end)
    end)

    describe("§8.5 F-SINK-REROLL (LOCKED ladder)", function()
        it("k=1 returns 250 (first reroll tier)", function()
            expect(EconomyConfig.rerollCost(1)).to.equal(250)
        end)
        it("k=2 returns 600", function()
            expect(EconomyConfig.rerollCost(2)).to.equal(600)
        end)
        it("k=3 returns 1200", function()
            expect(EconomyConfig.rerollCost(3)).to.equal(1200)
        end)
        it("k=4 returns 2000 (cap tier)", function()
            expect(EconomyConfig.rerollCost(4)).to.equal(2000)
        end)
        it("k=5..99 all return 2000 (flat cap, never escalates past)", function()
            expect(EconomyConfig.rerollCost(5)).to.equal(2000)
            expect(EconomyConfig.rerollCost(10)).to.equal(2000)
            expect(EconomyConfig.rerollCost(99)).to.equal(2000)
        end)
        it("k=0 returns the first-tier cost (defensive)", function()
            expect(EconomyConfig.rerollCost(0)).to.equal(250)
        end)
        it("k=-5 (negative) returns the first-tier cost (defensive)", function()
            expect(EconomyConfig.rerollCost(-5)).to.equal(250)
        end)
    end)

    describe("§8.6 F-SINK-SLOT-UNLOCK", function()
        it("k=0 returns base 250 (first paid unlock)", function()
            expect(EconomyConfig.slotUnlockCost(0)).to.equal(250)
        end)
        it("k=1 returns floor(250 * 1.20) = 300", function()
            expect(EconomyConfig.slotUnlockCost(1)).to.equal(300)
        end)
        it("k that pushes total slots over rosterCap returns math.huge", function()
            -- starting=25, per=5, cap=200 -> max paid unlocks = floor((200-25)/5) = 35
            -- k=34 should be the LAST valid unlock (push to 25 + 35*5 = 200 exactly)
            expect(EconomyConfig.slotUnlockCost(34) < math.huge).to.equal(true)
            -- k=35 would push to 205 -> rejected
            expect(EconomyConfig.slotUnlockCost(35)).to.equal(math.huge)
            expect(EconomyConfig.slotUnlockCost(99)).to.equal(math.huge)
        end)
        it("negative k is clamped to 0 (defensive)", function()
            expect(EconomyConfig.slotUnlockCost(-5)).to.equal(250)
        end)
    end)

    describe("§8.7 formatCoins (display polish)", function()
        it("formats sub-thousand values without a suffix", function()
            expect(EconomyConfig.formatCoins(0)).to.equal("0")
            expect(EconomyConfig.formatCoins(50)).to.equal("50")
            expect(EconomyConfig.formatCoins(999)).to.equal("999")
        end)
        it("formats thousand-range with K suffix", function()
            expect(EconomyConfig.formatCoins(1000)).to.equal("1.0K")
            expect(EconomyConfig.formatCoins(1500)).to.equal("1.5K")
            expect(EconomyConfig.formatCoins(12345)).to.equal("12.3K")
        end)
        it("formats million-range with M suffix", function()
            expect(EconomyConfig.formatCoins(1000000)).to.equal("1.0M")
            expect(EconomyConfig.formatCoins(1234567)).to.equal("1.2M")
        end)
        it("formats billion-range with B suffix", function()
            expect(EconomyConfig.formatCoins(5e9)).to.equal("5.0B")
        end)
        it("formats trillion-range with T suffix", function()
            expect(EconomyConfig.formatCoins(3.5e12)).to.equal("3.5T")
        end)
        it("clamps negative input to '0' (defensive)", function()
            expect(EconomyConfig.formatCoins(-100)).to.equal("0")
        end)
    end)

    describe("audit whitelist enforcement (§3.1 / §8.1)", function()
        it("isFaucetReason accepts every v1.2 reason", function()
            expect(EconomyConfig.isFaucetReason("idle_collect")).to.equal(true)
            expect(EconomyConfig.isFaucetReason("raid_loot")).to.equal(true)
            expect(EconomyConfig.isFaucetReason("field_combat_win")).to.equal(true)
            expect(EconomyConfig.isFaucetReason("quest_daily")).to.equal(true)
            expect(EconomyConfig.isFaucetReason("reward_generic")).to.equal(true)
            expect(EconomyConfig.isFaucetReason("devproduct_pack")).to.equal(true)
        end)
        it("isFaucetReason rejects an unknown reason (E7 — no minting under unknown)", function()
            expect(EconomyConfig.isFaucetReason("hack_mint")).to.equal(false)
            expect(EconomyConfig.isFaucetReason("")).to.equal(false)
            expect(EconomyConfig.isFaucetReason("raid_loots")).to.equal(false) -- typo guard
        end)
        it("isSinkReason accepts every documented sink", function()
            expect(EconomyConfig.isSinkReason("capture")).to.equal(true)
            expect(EconomyConfig.isSinkReason("upgrade_factory")).to.equal(true)
            expect(EconomyConfig.isSinkReason("upgrade_worker_slot")).to.equal(true)
            expect(EconomyConfig.isSinkReason("upgrade_storage")).to.equal(true)
            expect(EconomyConfig.isSinkReason("raid_send")).to.equal(true)
            expect(EconomyConfig.isSinkReason("reroll")).to.equal(true)
            expect(EconomyConfig.isSinkReason("slot_unlock")).to.equal(true)
            expect(EconomyConfig.isSinkReason("drama_fix")).to.equal(true)
        end)
        it("isSinkReason rejects unknown reasons", function()
            expect(EconomyConfig.isSinkReason("bogus")).to.equal(false)
            expect(EconomyConfig.isSinkReason("captures")).to.equal(false) -- typo guard
        end)
        it("isUpgradeTrack accepts factory / workerSlot / storage", function()
            expect(EconomyConfig.isUpgradeTrack("factory")).to.equal(true)
            expect(EconomyConfig.isUpgradeTrack("workerSlot")).to.equal(true)
            expect(EconomyConfig.isUpgradeTrack("storage")).to.equal(true)
            expect(EconomyConfig.isUpgradeTrack("workshop")).to.equal(false) -- typo guard
        end)
    end)

    describe("validate() defensive repair", function()
        it("returns the (sanitized) EconomyConfig table on a healthy input", function()
            local result = EconomyConfig.validate()
            expect(result).to.be.ok()
            expect(result.version).to.equal(1)
        end)
        it("clamps a NEGATIVE maxBalance into the documented range", function()
            EconomyConfig.maxBalance = -42 -- forced out-of-range
            EconomyConfig.validate()
            expect(EconomyConfig.maxBalance >= 1e9).to.equal(true)
        end)
        it("clamps a NaN minMutation back to the default", function()
            EconomyConfig.minMutation = 0 / 0 -- NaN
            EconomyConfig.validate()
            expect(EconomyConfig.minMutation >= 1).to.equal(true)
        end)
        it("swaps an INVERTED quest range so min <= max", function()
            EconomyConfig.questRewards.capture_n = { min = 500, max = 200 }
            EconomyConfig.validate()
            expect(EconomyConfig.questRewards.capture_n.min <= EconomyConfig.questRewards.capture_n.max).to.equal(true)
        end)
        it("repairs a NON-MONOTONIC reroll ladder (rises later tiers to >= prior)", function()
            EconomyConfig.reroll.costs = { 250, 600, 400, 2000 } -- tier 3 below tier 2
            EconomyConfig.validate()
            expect(EconomyConfig.reroll.costs[3] >= EconomyConfig.reroll.costs[2]).to.equal(true)
        end)
        it("seeds a MISSING upgrade track with safe defaults", function()
            EconomyConfig.upgrades.factory = nil
            EconomyConfig.validate()
            expect(EconomyConfig.upgrades.factory).to.be.ok()
            expect(EconomyConfig.upgrades.factory.base >= 50).to.equal(true)
        end)
        it("clamps startingSlots > rosterCap to rosterCap (cannot start over the cap)", function()
            EconomyConfig.slotUnlock.startingSlots = 500
            EconomyConfig.slotUnlock.rosterCap = 200
            EconomyConfig.validate()
            expect(EconomyConfig.slotUnlock.startingSlots <= EconomyConfig.slotUnlock.rosterCap).to.equal(true)
        end)
        it("falls back to default display suffixes if mangled", function()
            EconomyConfig.displaySuffixes = "garbage" :: any
            EconomyConfig.validate()
            expect(typeof(EconomyConfig.displaySuffixes)).to.equal("table")
            expect(#EconomyConfig.displaySuffixes > 0).to.equal(true)
        end)
        it("logs out-of-range repairs via the supplied logger", function()
            local logs = {}
            EconomyConfig.maxBalance = -42
            EconomyConfig.validate(function(event, payload)
                table.insert(logs, { event = event, payload = payload })
            end)
            local sawOutOfRange = false
            for _, entry in ipairs(logs) do
                if entry.event == "economy_config_out_of_range" then
                    sawOutOfRange = true
                end
            end
            expect(sawOutOfRange).to.equal(true)
        end)
    end)
end
