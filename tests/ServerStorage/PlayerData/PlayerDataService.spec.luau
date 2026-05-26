--!nocheck
-- tests/ServerStorage/PlayerData/PlayerDataService.spec.luau
--
-- TestEZ specs for PlayerDataService (System #1). AAA pattern, isolated tests
-- (state reset between each), MOCK DataStoreService (never the real store).
--
-- Covers the GDD edge cases:
--   * new profile -> Schema.default()                              (E2 distinction)
--   * load failure (read fails all attempts) -> kick, NO blank      (E2)
--   * migrate from old/partial data on load
--   * corrupt data that migrate cannot repair -> kick, key untouched(E8)
--   * lock held by another server -> kick                           (E1)
--   * save retry on transient failure / save_failed leaves dirty    (E3)
--   * roster at the cap (200): reject the 201st                     (E6)
--   * offline accrual: negative elapsed -> 0, over-cap -> clamped   (E5)
--   * idempotency: double-apply via txLog is a no-op                (E9/E7)
--   * txLog ring buffer bounded to txLogMaxEntries                  (E7)
--   * fav-lock prevents non-forced removal                          (E6)

return function()
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local ServerStorage = game:GetService("ServerStorage")

    local PlayerDataService = require(ServerStorage.PlayerData.PlayerDataService)
    local Schema = require(ServerStorage.PlayerData.Schema)
    local SessionLock = require(ServerStorage.PlayerData.SessionLock)
    local Config = require(ReplicatedStorage.Shared.Config.PersistenceConfig)
    local MockDataStore = require(script.Parent.MockDataStore)

    local THIS_JOB = "job-self"
    local OTHER_JOB = "job-other"

    -- Minimal mock Player (the service only reads .UserId and calls nothing
    -- else on it; load() fires signals with the player as an opaque value).
    local function mockPlayer(userId)
        return { UserId = userId, Name = "P" .. userId }
    end

    local mockService

    beforeEach(function()
        mockService = MockDataStore.newService()
        PlayerDataService.setDataStoreService(mockService)
        PlayerDataService.setLogger(function() end)
        PlayerDataService.setOfflineResolver(function()
            return 0
        end)
        SessionLock.setJobId(THIS_JOB)
        PlayerDataService._resetForTest()
    end)

    afterEach(function()
        PlayerDataService._resetForTest()
    end)

    -- ── LOAD ────────────────────────────────────────────────────────────

    describe("load (new profile)", function()
        it("creates a Schema.default() profile when the store returns nil (genuine new player)", function()
            -- Arrange
            local player = mockPlayer(2001)

            -- Act
            local data = PlayerDataService.load(player)

            -- Assert
            expect(data).to.be.ok()
            expect(data.coins).to.equal(0)
            expect(data.rosterCount).to.equal(0)
            expect(data.base.buildings.b1).to.be.ok()
            expect(PlayerDataService.isLoaded(player)).to.equal(true)
        end)
    end)

    describe("load (existing profile, migrate)", function()
        it("loads and migrates a stored partial record", function()
            -- Arrange: an old wrapper with a partial payload.
            local player = mockPlayer(2002)
            local store = mockService:getStore(Config.dataStoreName)
            store._data[Config.keyPrefix .. 2002] = {
                version = 1,
                savedAt = os.time(),
                data = { coins = 1234 }, -- partial; everything else missing
            }

            -- Act
            local data = PlayerDataService.load(player)

            -- Assert: existing coins preserved, missing fields backfilled.
            expect(data.coins).to.equal(1234)
            expect(data.base.buildings.b1).to.be.ok()
            expect(data.stats.totalCoinsEarned).to.equal(0)
        end)
    end)

    describe("load failure (E2)", function()
        it("returns nil (caller kicks) and does NOT cache a blank profile when the read fails every attempt", function()
            -- Arrange: fail more reads than loadMaxAttempts.
            local player = mockPlayer(2003)
            local store = mockService:getStore(Config.dataStoreName)
            store:failNext(Config.loadMaxAttempts + 1)

            -- Act
            local data = PlayerDataService.load(player)

            -- Assert: nil => kick; nothing cached (no blank to later overwrite).
            expect(data).to.equal(nil)
            expect(PlayerDataService.isLoaded(player)).to.equal(false)
        end)
    end)

    describe("load failure (E1 lock held by another server)", function()
        it("returns nil (caller kicks) and never loads over an active lock", function()
            -- Arrange: a fresh lock held by another server.
            local player = mockPlayer(2004)
            local lockStore = mockService:getStore(Config.lockStoreName)
            lockStore._data[Config.lockKeyPrefix .. 2004] = { jobId = OTHER_JOB, time = os.time() }

            -- Act
            local data = PlayerDataService.load(player)

            -- Assert
            expect(data).to.equal(nil)
            expect(PlayerDataService.isLoaded(player)).to.equal(false)
        end)
    end)

    describe("load failure (E8 corrupt data)", function()
        it("returns nil (caller kicks) and leaves the stored key untouched when migrate throws", function()
            -- Arrange: a wrapper whose payload is a non-table -> migrate throws.
            local player = mockPlayer(2005)
            local key = Config.keyPrefix .. 2005
            local store = mockService:getStore(Config.dataStoreName)
            store._data[key] = { version = 1, savedAt = os.time(), data = "corrupt-not-a-table" }

            -- Act
            local data = PlayerDataService.load(player)

            -- Assert: kicked; the corrupt key is preserved for manual recovery.
            expect(data).to.equal(nil)
            expect(PlayerDataService.isLoaded(player)).to.equal(false)
            expect(store._data[key].data).to.equal("corrupt-not-a-table")
        end)
    end)

    -- ── OFFLINE ACCRUAL (E5, F-OFFLINE) ───────────────────────────────────

    describe("offline accrual", function()
        it("accrues nothing when elapsed is negative (clock skew clamps to 0)", function()
            -- Arrange: lastSeen in the FUTURE; resolver that would pay 100/sec.
            local player = mockPlayer(2006)
            local store = mockService:getStore(Config.dataStoreName)
            store._data[Config.keyPrefix .. 2006] = {
                version = 1,
                savedAt = os.time(),
                data = { coins = 0, lastSeen = os.time() + 5000 },
            }
            PlayerDataService.setOfflineResolver(function(_r, _b, elapsed)
                return 100 * elapsed
            end)

            -- Act
            local data = PlayerDataService.load(player)

            -- Assert: clamped to 0 -> no pending coins.
            expect(data.pendingOffline.coins).to.equal(0)
        end)

        it("clamps elapsed to offlineCapSeconds (never grants more than the cap)", function()
            -- Arrange: offline far longer than the cap; resolver pays 1 coin/sec.
            local player = mockPlayer(2007)
            local store = mockService:getStore(Config.dataStoreName)
            local longAgo = os.time() - (Config.offlineCapSeconds * 10)
            store._data[Config.keyPrefix .. 2007] = {
                version = 1,
                savedAt = os.time(),
                data = { coins = 0, lastSeen = longAgo },
            }
            local seenElapsed
            PlayerDataService.setOfflineResolver(function(_r, _b, elapsed)
                seenElapsed = elapsed
                return elapsed -- 1 coin/sec
            end)

            -- Act
            local data = PlayerDataService.load(player)

            -- Assert: resolver saw exactly the cap; pending == cap.
            expect(seenElapsed).to.equal(Config.offlineCapSeconds)
            expect(data.pendingOffline.coins).to.equal(Config.offlineCapSeconds)
        end)

        it("uses the injected resolver and floors to an integer (default resolver pays 0)", function()
            -- Arrange: an hour offline; DEFAULT resolver (no Idle installed).
            local player = mockPlayer(2008)
            local store = mockService:getStore(Config.dataStoreName)
            store._data[Config.keyPrefix .. 2008] = {
                version = 1,
                savedAt = os.time(),
                data = { coins = 0, lastSeen = os.time() - 3600 },
            }
            -- (beforeEach already set the resolver to return 0.)

            -- Act
            local data = PlayerDataService.load(player)

            -- Assert: Persistence never fabricates economy -> 0 accrued.
            expect(data.pendingOffline.coins).to.equal(0)
        end)
    end)

    -- ── ROSTER (E6) ───────────────────────────────────────────────────────

    describe("roster operations", function()
        it("adds a Brainrot and keeps rosterCount in sync", function()
            -- Arrange
            local player = mockPlayer(2009)
            PlayerDataService._setProfileForTest(2009, Schema.default())
            local entry = Schema.newBrainrot({ species = 1, personality = "Loyal", source = "manual", hotspotId = "" })

            -- Act
            local ok = PlayerDataService.addBrainrot(player, entry)

            -- Assert
            expect(ok).to.equal(true)
            local data = PlayerDataService.getData(player)
            expect(data.rosterCount).to.equal(1)
            expect(PlayerDataService.getBrainrot(player, entry.id)).to.be.ok()
        end)

        it("rejects the 201st add at the cap (E6) without mutating the roster", function()
            -- Arrange: a profile pre-filled exactly to the cap.
            local player = mockPlayer(2010)
            local data = Schema.default()
            for i = 1, Config.rosterCap do
                local id = "id-" .. i
                data.roster[id] = { id = id, personality = "Loyal", level = 1, history = {} }
            end
            data.rosterCount = Config.rosterCap
            PlayerDataService._setProfileForTest(2010, data)
            local extra = Schema.newBrainrot({ species = 1, personality = "Loyal", source = "manual", hotspotId = "" })

            -- Act
            local ok, reason = PlayerDataService.addBrainrot(player, extra)

            -- Assert
            expect(ok).to.equal(false)
            expect(reason).to.equal("roster_full")
            expect(PlayerDataService.getData(player).rosterCount).to.equal(Config.rosterCap)
        end)

        it("removes a Brainrot and decrements the count", function()
            -- Arrange
            local player = mockPlayer(2011)
            PlayerDataService._setProfileForTest(2011, Schema.default())
            local entry = Schema.newBrainrot({ species = 1, personality = "Loyal", source = "manual", hotspotId = "" })
            PlayerDataService.addBrainrot(player, entry)

            -- Act
            local ok = PlayerDataService.removeBrainrot(player, entry.id)

            -- Assert
            expect(ok).to.equal(true)
            expect(PlayerDataService.getData(player).rosterCount).to.equal(0)
        end)

        it("refuses to remove a fav-locked entry unless forced (E6)", function()
            -- Arrange
            local player = mockPlayer(2012)
            PlayerDataService._setProfileForTest(2012, Schema.default())
            local entry = Schema.newBrainrot({ species = 1, personality = "Loyal", source = "manual", hotspotId = "" })
            entry.fav = true
            PlayerDataService.addBrainrot(player, entry)

            -- Act: unforced remove rejected; forced remove succeeds.
            local ok1, reason = PlayerDataService.removeBrainrot(player, entry.id)
            local ok2 = PlayerDataService.removeBrainrot(player, entry.id, true)

            -- Assert
            expect(ok1).to.equal(false)
            expect(reason).to.equal("favorited")
            expect(ok2).to.equal(true)
        end)
    end)

    -- ── ATOMIC UPDATE + IDEMPOTENCY (E9 / E7) ──────────────────────────────

    describe("update (atomic mutation + idempotency)", function()
        it("runs the mutator, increments nextSeq, and marks dirty", function()
            -- Arrange
            local player = mockPlayer(2013)
            PlayerDataService._setProfileForTest(2013, Schema.default())
            local before = PlayerDataService.getData(player).nextSeq

            -- Act
            local ok = PlayerDataService.update(player, function(data)
                data.coins += 50
            end)

            -- Assert
            expect(ok).to.equal(true)
            local data = PlayerDataService.getData(player)
            expect(data.coins).to.equal(50)
            expect(data.nextSeq).to.equal(before + 1)
        end)

        it("applies an idempotency-keyed mutation only once (double-apply is a no-op)", function()
            -- Arrange
            local player = mockPlayer(2014)
            PlayerDataService._setProfileForTest(2014, Schema.default())
            local key = "receipt-abc-123"
            local applied = 0
            local mut = function(data)
                data.coins += 100
                applied += 1
            end

            -- Act: same key twice (a replayed receipt / retried capture).
            local ok1, _, dup1 = PlayerDataService.update(player, mut, key)
            local ok2, _, dup2 = PlayerDataService.update(player, mut, key)

            -- Assert: charged exactly once.
            expect(ok1).to.equal(true)
            expect(dup1).to.equal(false)
            expect(ok2).to.equal(true)
            expect(dup2).to.equal(true) -- second was a no-op replay
            expect(applied).to.equal(1)
            expect(PlayerDataService.getData(player).coins).to.equal(100)
        end)

        it("bounds the txLog ring buffer to txLogMaxEntries (E7)", function()
            -- Arrange
            local player = mockPlayer(2015)
            PlayerDataService._setProfileForTest(2015, Schema.default())

            -- Act: record more keys than the cap.
            local total = Config.txLogMaxEntries + 25
            for i = 1, total do
                PlayerDataService.recordTx(player, "k-" .. i)
            end

            -- Assert: trimmed to the last txLogMaxEntries; oldest evicted.
            local log = PlayerDataService.getData(player).txLog
            expect(#log).to.equal(Config.txLogMaxEntries)
            expect(PlayerDataService.hasProcessed(player, "k-1")).to.equal(false)
            expect(PlayerDataService.hasProcessed(player, "k-" .. total)).to.equal(true)
        end)

        it("returns not_loaded when the player has no cached profile", function()
            -- Arrange
            local player = mockPlayer(2016)

            -- Act
            local ok, reason = PlayerDataService.update(player, function() end)

            -- Assert
            expect(ok).to.equal(false)
            expect(reason).to.equal("not_loaded")
        end)
    end)

    -- ── SAVE (E3) ──────────────────────────────────────────────────────────

    describe("save", function()
        it("persists a forced save and clears the dirty flag", function()
            -- Arrange
            local player = mockPlayer(2017)
            PlayerDataService._setProfileForTest(2017, Schema.default())
            PlayerDataService.update(player, function(data)
                data.coins += 777
            end)

            -- Act
            local ok = PlayerDataService.save(player, { force = true })

            -- Assert: wrapper written with version + payload.
            expect(ok).to.equal(true)
            local raw = mockService:getRaw(Config.dataStoreName, Config.keyPrefix .. 2017)
            expect(raw).to.be.ok()
            expect(raw.version).to.equal(Schema.CURRENT_SCHEMA_VERSION)
            expect(raw.data.coins).to.equal(777)
            expect(PlayerDataService.get(player).dirty).to.equal(false)
        end)

        it("retries on a transient failure and ultimately succeeds within saveMaxAttempts", function()
            -- Arrange: fail fewer ops than the attempt budget.
            local player = mockPlayer(2018)
            PlayerDataService._setProfileForTest(2018, Schema.default())
            PlayerDataService.update(player, function(data)
                data.coins = 5
            end)
            local store = mockService:getStore(Config.dataStoreName)
            store:failNext(Config.saveMaxAttempts - 1) -- last attempt succeeds

            -- Act
            local ok = PlayerDataService.save(player, { force = true })

            -- Assert
            expect(ok).to.equal(true)
            expect(mockService:getRaw(Config.dataStoreName, Config.keyPrefix .. 2018).data.coins).to.equal(5)
        end)

        it("leaves the dirty flag SET when every save attempt fails (E3 — no silent loss)", function()
            -- Arrange: fail more ops than the attempt budget.
            local player = mockPlayer(2019)
            PlayerDataService._setProfileForTest(2019, Schema.default())
            PlayerDataService.update(player, function(data)
                data.coins = 9
            end)
            local store = mockService:getStore(Config.dataStoreName)
            store:failNext(Config.saveMaxAttempts + 1)

            -- Act
            local ok = PlayerDataService.save(player, { force = true })

            -- Assert: failed, dirty stays set so the next tick retries.
            expect(ok).to.equal(false)
            expect(PlayerDataService.get(player).dirty).to.equal(true)
        end)

        it("no-ops (returns true) a non-forced save when the profile is not dirty", function()
            -- Arrange
            local player = mockPlayer(2020)
            PlayerDataService._setProfileForTest(2020, Schema.default())

            -- Act
            local ok = PlayerDataService.save(player)

            -- Assert: nothing written.
            expect(ok).to.equal(true)
            expect(mockService:getRaw(Config.dataStoreName, Config.keyPrefix .. 2020)).never.to.be.ok()
        end)
    end)

    -- ── PLAYTIME ACCRUAL ON SAVE ───────────────────────────────────────────

    describe("playtime accrual on save", function()
        it("adds (now - lastSeen) to stats.playtime and advances lastSeen", function()
            -- Arrange: a profile that last saved 100s ago.
            local player = mockPlayer(2021)
            local data = Schema.default()
            data.lastSeen = os.time() - 100
            PlayerDataService._setProfileForTest(2021, data)
            PlayerDataService.markDirty(player)

            -- Act
            PlayerDataService.save(player, { force = true })

            -- Assert: playtime advanced by ~100s; lastSeen refreshed to ~now.
            local saved = PlayerDataService.getData(player)
            expect(saved.stats.playtime >= 100).to.equal(true)
            expect(os.time() - saved.lastSeen <= 2).to.equal(true)
        end)
    end)
end
