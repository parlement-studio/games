--!nocheck
-- tests/ServerStorage/Economy/EconomyService.spec.luau
--
-- TestEZ specs for EconomyService (System #9 — economy-gdd v1.2). AAA pattern,
-- isolated tests. Uses an inline MOCK PlayerDataService (the only persistence
-- API EconomyService touches) — never the real DataStoreService.
--
-- Covers Acceptance Criteria + edge cases:
--   * award/spend reject invalid reason / amount / not-loaded                (E7/E8)
--   * award credits coins AND bumps totalCoinsEarned (monotonic)             (§2.6)
--   * spend debits coins WITHOUT touching totalCoinsEarned (leaderboard sig) (§2.6)
--   * award/spend idempotency replay returns prior result, NO signal re-fire (E5)
--   * award caps at maxBalance + reports overflow                            (E2)
--   * spend rejects insufficient funds                                       (E4)
--   * canAfford() is a hint (the spend re-checks server-side)                (§4)
--   * helpers: getUpgradeCost / getSlotUnlockCost / getRerollCost / getCaptureCost
--   * grantQuestReward rolls inside the type range, idemKey shape "quest_daily:<id>"
--   * grantGenericReward uses default amount when nil

return function()
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local ServerStorage = game:GetService("ServerStorage")

    local EconomyService = require(ServerStorage.Economy.EconomyService)
    local EconomyConfig = require(ReplicatedStorage.Shared.Config.EconomyConfig)

    -- ── Inline mock PlayerDataService ────────────────────────────────────────

    -- A minimal Signal stand-in (fires synchronously, records subscribers).
    local function newSignal()
        local conns = {}
        local sig = {}
        function sig:Connect(fn)
            local id = #conns + 1
            conns[id] = fn
            return {
                Disconnect = function()
                    conns[id] = nil
                end,
            }
        end
        function sig:Fire(...)
            for _, fn in pairs(conns) do
                fn(...)
            end
        end
        function sig:_subscriberCount()
            local n = 0
            for _ in pairs(conns) do
                n += 1
            end
            return n
        end
        return sig
    end

    -- A minimal in-memory PlayerDataService stand-in. Holds one profile per
    -- mock player (keyed by userId) + an in-memory txLog for idempotency.
    local function newMockPds()
        local mock = {}
        local profiles = {}
        local txLogs = {} -- per-player idempotency map

        mock.CoinsChanged = newSignal()
        mock.DataLoaded = newSignal()
        mock.DataSaved = newSignal()

        function mock.setData(player, data)
            profiles[player.UserId] = data
            txLogs[player.UserId] = txLogs[player.UserId] or {}
        end
        function mock.clear(player)
            profiles[player.UserId] = nil
            txLogs[player.UserId] = nil
        end
        function mock.getData(player)
            return profiles[player.UserId]
        end
        function mock.isLoaded(player)
            return profiles[player.UserId] ~= nil
        end
        function mock.markDirty(_player) end

        -- Mimic the real update() contract: replay-on-idemKey, deep-copy then
        -- pcall(mutator), commit-on-success, rollback on error.
        function mock.update(player, mutator, idemKey)
            local data = profiles[player.UserId]
            if data == nil then
                return false, "not_loaded", false
            end
            local log = txLogs[player.UserId]
            if idemKey ~= nil and log[idemKey] ~= nil then
                return true, log[idemKey], true -- replay; prior result
            end
            -- Shallow-clone-of-clone for the fields the tests actually touch
            -- (coins / stats.totalCoinsEarned). The real update deep-copies the
            -- entire data table; this mock only needs to support what
            -- EconomyService writes.
            local copy = {
                coins = data.coins,
                gems = data.gems,
                stats = {
                    totalCoinsEarned = data.stats.totalCoinsEarned,
                    playtime = data.stats.playtime,
                    lifetimeCaptures = data.stats.lifetimeCaptures,
                },
            }
            local ok, result = pcall(mutator, copy)
            if not ok then
                return false, "mutation_error", false
            end
            -- Commit: swap into the live profile (only the fields the mutator
            -- may touch; preserve everything else by writing back into `data`).
            data.coins = copy.coins
            data.gems = copy.gems
            data.stats.totalCoinsEarned = copy.stats.totalCoinsEarned
            if idemKey ~= nil then
                log[idemKey] = result
            end
            return true, result, false
        end

        return mock
    end

    -- A minimal Player stand-in (EconomyService only reads .UserId).
    local function mockPlayer(userId)
        return setmetatable({
            UserId = userId,
            Name = "P" .. userId,
            ClassName = "Player",
            Parent = workspace, -- a non-nil parent so bootstrap-style "is player gone" checks pass
        }, {
            __index = function(_, k)
                if k == "IsA" then
                    return function(_, className)
                        return className == "Player" or className == "Instance"
                    end
                end
                return nil
            end,
        })
    end

    local function freshProfileData()
        return {
            coins = 0,
            gems = 0,
            stats = {
                totalCoinsEarned = 0,
                playtime = 0,
                lifetimeCaptures = 0,
            },
        }
    end

    local pds

    beforeEach(function()
        pds = newMockPds()
        EconomyService.setPlayerDataService(pds)
        EconomyService.setEconomyConfig(EconomyConfig)
        EconomyService.setLogger(function() end)
    end)

    afterEach(function()
        EconomyService.setPlayerDataService(nil)
        EconomyService.setEconomyConfig(nil)
        EconomyService.setLogger(function() end)
    end)

    -- ── AWARD ──────────────────────────────────────────────────────────────

    describe("award — validation", function()
        it("rejects an unknown faucet reason (E7 — no minting under unknown)", function()
            local player = mockPlayer(3001)
            pds.setData(player, freshProfileData())
            local ok, err = EconomyService.award(player, 100, "bogus_reason")
            expect(ok).to.equal(false)
            expect(err).to.equal("invalid_reason")
        end)

        it("rejects a zero amount (E8)", function()
            local player = mockPlayer(3002)
            pds.setData(player, freshProfileData())
            local ok, err = EconomyService.award(player, 0, "idle_collect")
            expect(ok).to.equal(false)
            expect(err).to.equal("invalid_amount")
        end)

        it("rejects a negative amount (E8 — never silently flip into a debit)", function()
            local player = mockPlayer(3003)
            pds.setData(player, freshProfileData())
            local ok, err = EconomyService.award(player, -50, "idle_collect")
            expect(ok).to.equal(false)
            expect(err).to.equal("invalid_amount")
        end)

        it("rejects an unloaded profile with not_loaded", function()
            local player = mockPlayer(3004)
            local ok, err = EconomyService.award(player, 100, "idle_collect")
            expect(ok).to.equal(false)
            expect(err).to.equal("not_loaded")
        end)
    end)

    describe("award — happy path", function()
        it("credits coins AND bumps totalCoinsEarned (monotonic non-decreasing)", function()
            local player = mockPlayer(3010)
            pds.setData(player, freshProfileData())
            local ok, result = EconomyService.award(player, 100, "idle_collect")
            expect(ok).to.equal(true)
            expect(result.newBalance).to.equal(100)
            expect(result.delta).to.equal(100)
            expect(result.netWorth).to.equal(100)
            expect(pds.getData(player).coins).to.equal(100)
            expect(pds.getData(player).stats.totalCoinsEarned).to.equal(100)
        end)

        it("fires CoinsChanged with (player, newBalance, delta, reason) on a fresh commit", function()
            local player = mockPlayer(3011)
            pds.setData(player, freshProfileData())
            local seen = {}
            pds.CoinsChanged:Connect(function(p, b, d, r)
                table.insert(seen, { player = p, balance = b, delta = d, reason = r })
            end)
            EconomyService.award(player, 75, "raid_loot")
            expect(#seen).to.equal(1)
            expect(seen[1].balance).to.equal(75)
            expect(seen[1].delta).to.equal(75)
            expect(seen[1].reason).to.equal("raid_loot")
        end)

        it("floors a non-integer amount before crediting", function()
            local player = mockPlayer(3012)
            pds.setData(player, freshProfileData())
            local ok, result = EconomyService.award(player, 100.75, "idle_collect")
            expect(ok).to.equal(true)
            expect(result.newBalance).to.equal(100)
        end)
    end)

    describe("award — idempotency (E5)", function()
        it("returns the prior result on a replay AND does NOT re-fire CoinsChanged", function()
            local player = mockPlayer(3020)
            pds.setData(player, freshProfileData())
            local fires = 0
            pds.CoinsChanged:Connect(function()
                fires += 1
            end)
            local key = "raid_loot:raid-abc"
            local ok1, result1 = EconomyService.award(player, 200, "raid_loot", key)
            local ok2, result2 = EconomyService.award(player, 200, "raid_loot", key)
            expect(ok1).to.equal(true)
            expect(ok2).to.equal(true)
            expect(result1.newBalance).to.equal(result2.newBalance) -- same prior result
            expect(pds.getData(player).coins).to.equal(200) -- credit happened ONCE
            expect(fires).to.equal(1) -- signal fired ONCE
        end)
    end)

    describe("award — maxBalance cap (E2)", function()
        it("clamps to maxBalance and reports overflowDiscarded", function()
            local player = mockPlayer(3030)
            local profile = freshProfileData()
            profile.coins = EconomyConfig.maxBalance - 100 -- room for only 100 more
            profile.stats.totalCoinsEarned = profile.coins
            pds.setData(player, profile)
            local ok, result = EconomyService.award(player, 500, "idle_collect")
            expect(ok).to.equal(true)
            expect(result.delta).to.equal(100) -- only 100 credited
            expect(result.overflowDiscarded).to.equal(400) -- 400 discarded
            expect(pds.getData(player).coins).to.equal(EconomyConfig.maxBalance)
        end)
    end)

    -- ── SPEND ──────────────────────────────────────────────────────────────

    describe("spend — validation", function()
        it("rejects an unknown sink reason (E7)", function()
            local player = mockPlayer(3100)
            pds.setData(player, freshProfileData())
            local ok, err = EconomyService.spend(player, 100, "bogus")
            expect(ok).to.equal(false)
            expect(err).to.equal("invalid_reason")
        end)

        it("rejects zero / negative amount (E8)", function()
            local player = mockPlayer(3101)
            pds.setData(player, freshProfileData())
            local ok1, err1 = EconomyService.spend(player, 0, "capture")
            expect(ok1).to.equal(false)
            expect(err1).to.equal("invalid_amount")
            local ok2, err2 = EconomyService.spend(player, -25, "capture")
            expect(ok2).to.equal(false)
            expect(err2).to.equal("invalid_amount")
        end)

        it("rejects unloaded profile", function()
            local player = mockPlayer(3102)
            local ok, err = EconomyService.spend(player, 25, "capture")
            expect(ok).to.equal(false)
            expect(err).to.equal("not_loaded")
        end)
    end)

    describe("spend — insufficient funds (E4)", function()
        it("returns insufficient_funds and DOES NOT mutate coins", function()
            local player = mockPlayer(3110)
            local profile = freshProfileData()
            profile.coins = 10
            pds.setData(player, profile)
            local ok, err = EconomyService.spend(player, 25, "capture")
            expect(ok).to.equal(false)
            expect(err).to.equal("insufficient_funds")
            expect(pds.getData(player).coins).to.equal(10) -- untouched
        end)
    end)

    describe("spend — happy path", function()
        it("debits coins WITHOUT touching totalCoinsEarned (monotonic leaderboard signal)", function()
            local player = mockPlayer(3120)
            local profile = freshProfileData()
            profile.coins = 500
            profile.stats.totalCoinsEarned = 500
            pds.setData(player, profile)
            local ok, result = EconomyService.spend(player, 100, "upgrade_factory")
            expect(ok).to.equal(true)
            expect(result.newBalance).to.equal(400)
            expect(result.delta).to.equal(-100)
            expect(pds.getData(player).coins).to.equal(400)
            expect(pds.getData(player).stats.totalCoinsEarned).to.equal(500) -- UNCHANGED
        end)

        it("fires CoinsChanged with a NEGATIVE delta on spend", function()
            local player = mockPlayer(3121)
            local profile = freshProfileData()
            profile.coins = 300
            pds.setData(player, profile)
            local seen = {}
            pds.CoinsChanged:Connect(function(_p, _b, d, r)
                table.insert(seen, { delta = d, reason = r })
            end)
            EconomyService.spend(player, 50, "reroll")
            expect(#seen).to.equal(1)
            expect(seen[1].delta).to.equal(-50)
            expect(seen[1].reason).to.equal("reroll")
        end)
    end)

    describe("spend — idempotency (E5)", function()
        it("replay returns the prior result without re-firing CoinsChanged", function()
            local player = mockPlayer(3130)
            local profile = freshProfileData()
            profile.coins = 500
            pds.setData(player, profile)
            local fires = 0
            pds.CoinsChanged:Connect(function()
                fires += 1
            end)
            local key = "reroll:brainrot-xyz:k1"
            local ok1, result1 = EconomyService.spend(player, 250, "reroll", key)
            local ok2, result2 = EconomyService.spend(player, 250, "reroll", key)
            expect(ok1).to.equal(true)
            expect(ok2).to.equal(true)
            expect(result1.newBalance).to.equal(result2.newBalance)
            expect(pds.getData(player).coins).to.equal(250) -- debit happened ONCE
            expect(fires).to.equal(1)
        end)
    end)

    -- ── QUERIES ────────────────────────────────────────────────────────────

    describe("queries (getBalance / getNetWorth / canAfford)", function()
        it("getBalance returns nil for unloaded profile", function()
            expect(EconomyService.getBalance(mockPlayer(3201))).to.equal(nil)
        end)
        it("getBalance returns the live coins value", function()
            local player = mockPlayer(3202)
            local profile = freshProfileData()
            profile.coins = 1234
            pds.setData(player, profile)
            expect(EconomyService.getBalance(player)).to.equal(1234)
        end)
        it("getNetWorth returns totalCoinsEarned", function()
            local player = mockPlayer(3203)
            local profile = freshProfileData()
            profile.stats.totalCoinsEarned = 9999
            pds.setData(player, profile)
            expect(EconomyService.getNetWorth(player)).to.equal(9999)
        end)
        it("canAfford true when balance >= amount, false otherwise", function()
            local player = mockPlayer(3204)
            local profile = freshProfileData()
            profile.coins = 100
            pds.setData(player, profile)
            expect(EconomyService.canAfford(player, 50)).to.equal(true)
            expect(EconomyService.canAfford(player, 100)).to.equal(true)
            expect(EconomyService.canAfford(player, 101)).to.equal(false)
        end)
    end)

    -- ── HELPERS (price accessors) ──────────────────────────────────────────

    describe("price accessors (server-authoritative)", function()
        it("getUpgradeCost matches EconomyConfig.upgradeCost", function()
            expect(EconomyService.getUpgradeCost("factory", 0)).to.equal(200)
            expect(EconomyService.getUpgradeCost("factory", 1)).to.equal(270)
            expect(EconomyService.getUpgradeCost("factory", 30)).to.equal(math.huge)
        end)
        it("getSlotUnlockCost matches EconomyConfig.slotUnlockCost", function()
            expect(EconomyService.getSlotUnlockCost(0)).to.equal(250)
        end)
        it("getRerollCost matches the LOCKED ladder", function()
            expect(EconomyService.getRerollCost(1)).to.equal(250)
            expect(EconomyService.getRerollCost(4)).to.equal(2000)
            expect(EconomyService.getRerollCost(99)).to.equal(2000)
        end)
        it("getCaptureCost reads CaptureConfig (single source of truth)", function()
            -- Inject a fake CaptureConfig so the test does not depend on the real one.
            EconomyService.setCaptureConfig({ captureCostCoins = 42 })
            expect(EconomyService.getCaptureCost()).to.equal(42)
            EconomyService.setCaptureConfig(nil)
        end)
    end)

    -- ── CONVENIENCE FAUCETS ────────────────────────────────────────────────

    describe("grantQuestReward", function()
        it("rolls a reward in the per-type range and credits via award", function()
            local player = mockPlayer(3300)
            pds.setData(player, freshProfileData())
            -- Force the RNG to the range min so we can assert on a known value.
            local ok, result = EconomyService.grantQuestReward(player, "capture_n", "q-2026-05-29-01", function(lo, _)
                return lo
            end)
            expect(ok).to.equal(true)
            expect(result.delta).to.equal(EconomyConfig.questRewards.capture_n.min) -- 100
        end)
        it("falls back to questRewardFallbackCoins for an unknown quest type", function()
            local player = mockPlayer(3301)
            pds.setData(player, freshProfileData())
            local ok, result = EconomyService.grantQuestReward(player, "no_such_quest_type", "q-x")
            expect(ok).to.equal(true)
            expect(result.delta).to.equal(EconomyConfig.questRewardFallbackCoins) -- 150
        end)
        it("rejects an empty quest id (idem key would collide across quests)", function()
            local player = mockPlayer(3302)
            pds.setData(player, freshProfileData())
            local ok, err = EconomyService.grantQuestReward(player, "capture_n", "")
            expect(ok).to.equal(false)
            expect(err).to.equal("invalid_quest_id")
        end)
    end)

    describe("grantGenericReward", function()
        it("uses rewardGenericCoins when amount is nil", function()
            local player = mockPlayer(3310)
            pds.setData(player, freshProfileData())
            local ok, result = EconomyService.grantGenericReward(player, nil, "redeem-code-XYZ")
            expect(ok).to.equal(true)
            expect(result.delta).to.equal(EconomyConfig.rewardGenericCoins) -- 50
        end)
        it("uses the supplied amount when present", function()
            local player = mockPlayer(3311)
            pds.setData(player, freshProfileData())
            local ok, result = EconomyService.grantGenericReward(player, 200, "ftue-welcome")
            expect(ok).to.equal(true)
            expect(result.delta).to.equal(200)
        end)
        it("rejects empty idem key (E5 — needed to dedupe redemptions)", function()
            local player = mockPlayer(3312)
            pds.setData(player, freshProfileData())
            local ok, err = EconomyService.grantGenericReward(player, 100, "")
            expect(ok).to.equal(false)
            expect(err).to.equal("invalid_idem_key")
        end)
    end)
end
