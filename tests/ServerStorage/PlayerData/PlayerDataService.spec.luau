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

        it("returns the PRIOR stored result (not nil) on an idempotency-key replay (ADR-001 C2)", function()
            -- Arrange
            local player = mockPlayer(2014)
            PlayerDataService._setProfileForTest(2014, Schema.default())
            local key = "capture-xyz"

            -- Act: first commit returns a payload; replay must return THAT payload.
            local _, result1, dup1 = PlayerDataService.update(player, function(data)
                data.coins += 10
                return { newCoins = data.coins, brainrotId = "br-1" }
            end, key)
            local _, result2, dup2 = PlayerDataService.update(player, function(data)
                data.coins += 10 -- would double-charge if it ran
                return { newCoins = data.coins }
            end, key)

            -- Assert: replay returned the stored result, NOT nil, and did not re-run.
            expect(dup1).to.equal(false)
            expect(dup2).to.equal(true)
            expect(result2).to.be.ok()
            expect(result2.newCoins).to.equal(10)
            expect(result2.brainrotId).to.equal("br-1")
            expect(PlayerDataService.getData(player).coins).to.equal(10)
        end)

        it(
            "rolls back FULLY when the mutator throws: no state change, no seq bump, key NOT recorded, retry re-applies (H5)",
            function()
                -- Arrange
                local player = mockPlayer(2014)
                PlayerDataService._setProfileForTest(2014, Schema.default())
                local data0 = PlayerDataService.getData(player)
                local seqBefore = data0.nextSeq
                local coinsBefore = data0.coins
                local key = "tx-throws"

                -- Act: a mutator that mutates THEN throws.
                local ok, reason, dup = PlayerDataService.update(player, function(data)
                    data.coins += 999 -- partial mutation on the COPY
                    data.gems += 5
                    error("boom")
                end, key)

                -- Assert: failure surfaced, live profile untouched, key not recorded.
                expect(ok).to.equal(false)
                expect(reason).to.equal("mutation_error")
                expect(dup).to.equal(false)
                local after = PlayerDataService.getData(player)
                expect(after.coins).to.equal(coinsBefore)
                expect(after.gems).to.equal(0)
                expect(after.nextSeq).to.equal(seqBefore)
                expect(PlayerDataService.hasProcessed(player, key)).to.equal(false)
                expect(PlayerDataService.get(player).dirty).to.equal(false)

                -- And a retry with the SAME key re-applies (the failed attempt did
                -- not consume the idempotency key).
                local ok2 = PlayerDataService.update(player, function(data)
                    data.coins += 42
                end, key)
                expect(ok2).to.equal(true)
                expect(PlayerDataService.getData(player).coins).to.equal(coinsBefore + 42)
            end
        )

        it("commits a compound debit + addToRoster both-or-neither when it succeeds", function()
            -- Arrange: a capture-style mutation (charge coins AND add a Brainrot).
            local player = mockPlayer(2014)
            local data = Schema.default()
            data.coins = 500
            PlayerDataService._setProfileForTest(2014, data)
            local entry = Schema.newBrainrot({ species = 1, personality = "Loyal", source = "manual", hotspotId = "" })

            -- Act
            local ok = PlayerDataService.update(player, function(d)
                d.coins -= 200
                local added = Schema.addToRoster(d, entry)
                if not added then
                    error("roster_full")
                end
            end)

            -- Assert: BOTH effects committed.
            expect(ok).to.equal(true)
            local after = PlayerDataService.getData(player)
            expect(after.coins).to.equal(300)
            expect(after.rosterCount).to.equal(1)
            expect(after.roster[entry.id]).to.be.ok()
        end)

        it("rejects a cap-full capture INSIDE the transaction with NO debit (C5)", function()
            -- Arrange: roster exactly at the cap, with coins to spend.
            local player = mockPlayer(2014)
            local data = Schema.default()
            data.coins = 500
            for i = 1, Config.rosterCap do
                local id = "id-" .. i
                data.roster[id] = { id = id, personality = "Loyal", level = 1, history = {} }
            end
            data.rosterCount = Config.rosterCap
            PlayerDataService._setProfileForTest(2014, data)
            local extra = Schema.newBrainrot({ species = 1, personality = "Loyal", source = "manual", hotspotId = "" })

            -- Act: a capture mutator that debits THEN tries to add (add fails at cap).
            local ok, reason = PlayerDataService.update(player, function(d)
                d.coins -= 200
                local added, addReason = Schema.addToRoster(d, extra)
                if not added then
                    error(addReason, 0)
                end
            end)

            -- Assert: rejected; the debit rolled back (no coins lost, no roster growth).
            expect(ok).to.equal(false)
            expect(reason).to.equal("mutation_error")
            local after = PlayerDataService.getData(player)
            expect(after.coins).to.equal(500) -- NOT debited
            expect(after.rosterCount).to.equal(Config.rosterCap)
        end)

        it("bounds the txLog ring buffer to txLogMaxEntries via update() (E7)", function()
            -- Arrange
            local player = mockPlayer(2015)
            PlayerDataService._setProfileForTest(2015, Schema.default())

            -- Act: commit more idempotency-keyed updates than the cap.
            local total = Config.txLogMaxEntries + 25
            for i = 1, total do
                PlayerDataService.update(player, function(data)
                    data.coins += 1
                end, "k-" .. i)
            end

            -- Assert: trimmed to the last txLogMaxEntries; oldest evicted.
            local d = PlayerDataService.getData(player)
            expect(#d.txLogOrder).to.equal(Config.txLogMaxEntries)
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

    -- ── HEARTBEAT LIFECYCLE (C3 / C4) ──────────────────────────────────────

    describe("heartbeat lifecycle", function()
        it("cancels the heartbeat thread on onPlayerRemoving (no further lock writes — C3)", function()
            -- Arrange: a loaded profile with a real heartbeat thread.
            local player = mockPlayer(2030)
            PlayerDataService._setProfileForTest(2030, Schema.default(), player)
            local thread = PlayerDataService._startHeartbeatForTest(2030)
            expect(coroutine.status(thread)).never.to.equal("dead")
            local lockStore = mockService:getStore(Config.lockStoreName)
            local callsBefore = lockStore._updateCount

            -- Act
            PlayerDataService.onPlayerRemoving(player)

            -- Assert: thread cancelled, handle cleared, profile dropped. The ONLY
            -- lock UpdateAsync during removal is the single release() — proving the
            -- heartbeat was stopped BEFORE release (C3) and fires no further beats.
            expect(coroutine.status(thread)).to.equal("dead")
            expect(PlayerDataService._heartbeatThreadCountForTest()).to.equal(0)
            expect(PlayerDataService.isLoaded(player)).to.equal(false)
            expect(lockStore._updateCount - callsBefore).to.equal(1)
        end)

        it("cancels every heartbeat thread on saveAllOnClose (C4)", function()
            -- Arrange: two loaded profiles, each heartbeating.
            local p1, p2 = mockPlayer(2031), mockPlayer(2032)
            PlayerDataService._setProfileForTest(2031, Schema.default(), p1)
            PlayerDataService._setProfileForTest(2032, Schema.default(), p2)
            local t1 = PlayerDataService._startHeartbeatForTest(2031)
            local t2 = PlayerDataService._startHeartbeatForTest(2032)

            -- Act
            PlayerDataService.saveAllOnClose()

            -- Assert: both threads dead, all handles cleared, cache emptied.
            expect(coroutine.status(t1)).to.equal("dead")
            expect(coroutine.status(t2)).to.equal("dead")
            expect(PlayerDataService._heartbeatThreadCountForTest()).to.equal(0)
            expect(PlayerDataService.isLoaded(p1)).to.equal(false)
            expect(PlayerDataService.isLoaded(p2)).to.equal(false)
        end)
    end)

    -- ── DURABLE RECEIPT GRANT (ADR-001 §3) ─────────────────────────────────

    describe("processReceiptGrant", function()
        it("grants once + forces a durable save and returns success", function()
            -- Arrange
            local player = mockPlayer(2040)
            PlayerDataService._setProfileForTest(2040, Schema.default(), player)

            -- Act
            local granted = PlayerDataService.processReceiptGrant(player, "purchase-1", function(data)
                data.gems += 100
                return { gems = data.gems }
            end)

            -- Assert: gems credited, marker durable (now a TIMESTAMP, ADR-002 H-2),
            -- profile written.
            expect(granted).to.equal(true)
            local data = PlayerDataService.getData(player)
            expect(data.gems).to.equal(100)
            expect(type(data.consumedReceipts["purchase-1"])).to.equal("number")
            local raw = mockService:getRaw(Config.dataStoreName, Config.keyPrefix .. 2040)
            expect(raw.data.gems).to.equal(100)
            expect(type(raw.data.consumedReceipts["purchase-1"])).to.equal("number")
        end)

        it("does NOT double-credit on a redelivered purchaseId (replay via the durable marker)", function()
            -- Arrange
            local player = mockPlayer(2041)
            PlayerDataService._setProfileForTest(2041, Schema.default(), player)
            local grantCount = 0
            local mut = function(data)
                data.gems += 50
                grantCount += 1
            end

            -- Act: same purchaseId twice.
            local g1 = PlayerDataService.processReceiptGrant(player, "purchase-2", mut)
            local g2 = PlayerDataService.processReceiptGrant(player, "purchase-2", mut)

            -- Assert: granted both times (idempotent ack), but credited ONCE.
            expect(g1).to.equal(true)
            expect(g2).to.equal(true)
            expect(grantCount).to.equal(1)
            expect(PlayerDataService.getData(player).gems).to.equal(50)
        end)

        it(
            "ROLLS BACK the grant + marker when the forced save fails, then re-runs cleanly on redelivery (ADR-002 H-1)",
            function()
                -- Arrange: a loaded profile; capture the pre-grant state. Make
                -- every save attempt fail for the first grant attempt.
                local player = mockPlayer(2042)
                PlayerDataService._setProfileForTest(2042, Schema.default(), player)
                local pre = PlayerDataService.getData(player)
                local gemsBefore = pre.gems
                local wasDirty = PlayerDataService.get(player).dirty
                local store = mockService:getStore(Config.dataStoreName)
                store:failNext(Config.saveMaxAttempts + 1)
                local grantRuns = 0

                -- Act 1: grant whose forced save fails.
                local granted, reason = PlayerDataService.processReceiptGrant(player, "purchase-3", function(data)
                    data.gems += 25
                    grantRuns += 1
                end)

                -- Assert: NOT acked; BOTH the in-memory grant AND the durable
                -- marker are rolled back (memory == last durable state); dirty
                -- restored to its pre-grant value (no phantom dirty/grant).
                expect(granted).to.equal(false)
                expect(reason).to.equal("save_failed")
                local after = PlayerDataService.getData(player)
                expect(after.gems).to.equal(gemsBefore) -- grant reverted
                expect(after.consumedReceipts["purchase-3"]).to.equal(nil) -- marker gone
                expect(PlayerDataService.get(player).dirty).to.equal(wasDirty)

                -- Act 2: redelivery — the store now succeeds; re-run the SAME id.
                local granted2 = PlayerDataService.processReceiptGrant(player, "purchase-3", function(data)
                    data.gems += 25
                    grantRuns += 1
                end)

                -- Assert: now acked, grant applied EXACTLY once across both attempts.
                expect(granted2).to.equal(true)
                expect(grantRuns).to.equal(2) -- the mutator ran twice...
                expect(PlayerDataService.getData(player).gems).to.equal(gemsBefore + 25) -- ...but credited once
                local raw = mockService:getRaw(Config.dataStoreName, Config.keyPrefix .. 2042)
                expect(type(raw.data.consumedReceipts["purchase-3"])).to.equal("number")
            end
        )

        it("returns not_loaded when the profile is not cached (caller -> NotProcessedYet)", function()
            -- Arrange
            local player = mockPlayer(2043)

            -- Act
            local granted, reason = PlayerDataService.processReceiptGrant(player, "purchase-4", function() end)

            -- Assert
            expect(granted).to.equal(false)
            expect(reason).to.equal("not_loaded")
        end)
    end)

    -- ── AUTOSAVE CADENCE + BUDGET (H1 / H2, deviation) ──────────────────────

    describe("autosave cadence + budget", function()
        it("does NOT save a dirty profile before autosaveIntervalSec has elapsed", function()
            -- Arrange: dirty profile whose last save was JUST now.
            local player = mockPlayer(2050)
            PlayerDataService._setProfileForTest(2050, Schema.default(), player)
            PlayerDataService.markDirty(player)
            PlayerDataService._setLastSaveClockForTest(2050, os.clock()) -- 0s elapsed

            -- Act
            PlayerDataService._runAutosavePassForTest()

            -- Assert: nothing written; still dirty.
            expect(mockService:getRaw(Config.dataStoreName, Config.keyPrefix .. 2050)).never.to.be.ok()
            expect(PlayerDataService.get(player).dirty).to.equal(true)
        end)

        it("DOES save a dirty profile at/after autosaveIntervalSec", function()
            -- Arrange: dirty profile whose last save was > the interval ago.
            local player = mockPlayer(2051)
            PlayerDataService._setProfileForTest(2051, Schema.default(), player)
            PlayerDataService.update(player, function(data)
                data.coins += 7
            end)
            PlayerDataService._setLastSaveClockForTest(2051, os.clock() - (Config.autosaveIntervalSec + 1))

            -- Act
            PlayerDataService._runAutosavePassForTest()

            -- Assert: written; dirty cleared.
            local raw = mockService:getRaw(Config.dataStoreName, Config.keyPrefix .. 2051)
            expect(raw).to.be.ok()
            expect(raw.data.coins).to.equal(7)
            expect(PlayerDataService.get(player).dirty).to.equal(false)
        end)

        it("skips the autosave pass when the write budget is exhausted (H2)", function()
            -- Arrange: a due dirty profile but a starved budget.
            local player = mockPlayer(2052)
            PlayerDataService._setProfileForTest(2052, Schema.default(), player)
            PlayerDataService.markDirty(player)
            PlayerDataService._setLastSaveClockForTest(2052, os.clock() - (Config.autosaveIntervalSec + 1))
            mockService:setRequestBudget(0) -- exhausted

            -- Act
            PlayerDataService._runAutosavePassForTest()

            -- Assert: skipped; nothing written; still dirty (retries next tick).
            expect(mockService:getRaw(Config.dataStoreName, Config.keyPrefix .. 2052)).never.to.be.ok()
            expect(PlayerDataService.get(player).dirty).to.equal(true)
        end)

        it("saves an ORPHANED cache profile whose Player object is gone (H1)", function()
            -- Arrange: a dirty, due profile with NO live Player (orphan).
            PlayerDataService._setProfileForTest(2053, Schema.default(), nil)
            -- Mark dirty via the userId path (no Player object available).
            PlayerDataService.saveByUserId(2053) -- no-op (not dirty) — set dirty next
            local p = PlayerDataService.get({ UserId = 2053 })
            p.dirty = true
            p.data.coins = 11
            PlayerDataService._setLastSaveClockForTest(2053, os.clock() - (Config.autosaveIntervalSec + 1))

            -- Act
            PlayerDataService._runAutosavePassForTest()

            -- Assert: the orphan was saved (a Players:GetPlayers loop would miss it).
            local raw = mockService:getRaw(Config.dataStoreName, Config.keyPrefix .. 2053)
            expect(raw).to.be.ok()
            expect(raw.data.coins).to.equal(11)
        end)
    end)

    -- ── H-2: TIME-BOUNDED RECEIPT PRUNING (ADR-002) ────────────────────────

    describe("consumedReceipts time-bounded pruning (ADR-002 H-2)", function()
        it("does NOT evict an old marker by COUNT (dropping the 100 count cap)", function()
            -- Arrange: a fresh profile.
            local player = mockPlayer(2070)
            PlayerDataService._setProfileForTest(2070, Schema.default(), player)

            -- Act: consume one receipt, then far more than the old 100 count cap.
            -- All consumed "now", so NONE are past the time horizon.
            PlayerDataService.processReceiptGrant(player, "first-receipt", function(data)
                data.gems += 1
            end)
            for i = 1, 200 do
                PlayerDataService.processReceiptGrant(player, "r-" .. i, function(data)
                    data.gems += 1
                end)
            end

            -- Assert: the FIRST marker is STILL present (a count cap would have
            -- evicted it; time-pruning keeps every within-horizon marker so a
            -- redelivery within the horizon still dedupes).
            local data = PlayerDataService.getData(player)
            expect(type(data.consumedReceipts["first-receipt"])).to.equal("number")
            expect(#data.consumedReceiptsOrder).to.equal(201)
        end)

        it("PRUNES a marker older than the horizon while keeping recent ones", function()
            -- Arrange: a profile with a STALE marker (consumed long past the
            -- horizon) at the head and a recent marker after it.
            local player = mockPlayer(2071)
            local data = Schema.default()
            local now = os.time()
            local stale = now - (Config.consumedReceiptHorizonSec + 1000)
            data.consumedReceipts["old-receipt"] = stale
            data.consumedReceipts["recent-receipt"] = now - 5
            data.consumedReceiptsOrder = { "old-receipt", "recent-receipt" }
            PlayerDataService._setProfileForTest(2071, data, player)

            -- Act: consuming any new receipt triggers the front-of-list age prune.
            PlayerDataService.processReceiptGrant(player, "new-receipt", function(d)
                d.gems += 1
            end)

            -- Assert: the stale marker is pruned; the recent + new ones survive.
            local after = PlayerDataService.getData(player)
            expect(after.consumedReceipts["old-receipt"]).to.equal(nil)
            expect(type(after.consumedReceipts["recent-receipt"])).to.equal("number")
            expect(type(after.consumedReceipts["new-receipt"])).to.equal("number")
        end)

        it("still DEDUPES a redelivery within the horizon (no double credit)", function()
            -- Arrange
            local player = mockPlayer(2072)
            PlayerDataService._setProfileForTest(2072, Schema.default(), player)
            local runs = 0

            -- Act: same purchaseId delivered twice while well within the horizon.
            PlayerDataService.processReceiptGrant(player, "within-horizon", function(data)
                data.gems += 30
                runs += 1
            end)
            PlayerDataService.processReceiptGrant(player, "within-horizon", function(data)
                data.gems += 30
                runs += 1
            end)

            -- Assert: credited exactly once (the within-horizon marker deduped).
            expect(runs).to.equal(1)
            expect(PlayerDataService.getData(player).gems).to.equal(30)
        end)

        it("OVERFLOW-trims to consumedReceiptHardCap and logs when the cap is exceeded", function()
            -- Arrange: a profile already AT the hard cap of recent markers, plus
            -- one fresh consume to push it over. (Use a small synthetic cap proxy
            -- by seeding exactly the cap, all recent so time-pruning is a no-op.)
            local player = mockPlayer(2073)
            local data = Schema.default()
            local now = os.time()
            for i = 1, Config.consumedReceiptHardCap do
                local id = "cap-" .. i
                data.consumedReceipts[id] = now - 1
                table.insert(data.consumedReceiptsOrder, id)
            end
            PlayerDataService._setProfileForTest(2073, data, player)
            local overflowLogged = false
            PlayerDataService.setLogger(function(event)
                if event == "consumed_receipts_overflow" then
                    overflowLogged = true
                end
            end)

            -- Act: one more consume pushes the map over the hard cap.
            PlayerDataService.processReceiptGrant(player, "over-the-cap", function(d)
                d.gems += 1
            end)

            -- Assert: trimmed back to the cap; overflow incident logged; the
            -- newest (just-added) marker survived, the oldest was evicted.
            local after = PlayerDataService.getData(player)
            expect(#after.consumedReceiptsOrder).to.equal(Config.consumedReceiptHardCap)
            expect(overflowLogged).to.equal(true)
            expect(type(after.consumedReceipts["over-the-cap"])).to.equal("number")
            expect(after.consumedReceipts["cap-1"]).to.equal(nil)

            PlayerDataService.setLogger(function() end)
        end)
    end)

    -- ── M-2: SAVE FENCE / FREEZE-THEN-STEAL DUPE (ADR-002) ──────────────────

    describe("save fence (ADR-002 M-2)", function()
        it("FENCES OUT a stale server's save after another server steals the lock (no write)", function()
            -- Arrange: server A holds the profile (cached lockGen = 1, durable
            -- lock seeded by _setProfileForTest at gen 1). A has a dirty change.
            local player = mockPlayer(2080)
            PlayerDataService._setProfileForTest(2080, Schema.default(), player)
            PlayerDataService.update(player, function(data)
                data.coins += 500
            end)
            local profileStore = mockService:getStore(Config.dataStoreName)
            -- Simulate B STEALING the lock: durable lock now reads B at gen 2.
            SessionLock._writeLockForTest(2080, 2, OTHER_JOB)
            local fenced = false
            PlayerDataService.setLogger(function(event)
                if event == "save_fenced" then
                    fenced = true
                end
            end)
            local writeKey = Config.keyPrefix .. 2080
            expect(profileStore._data[writeKey]).never.to.be.ok() -- nothing written yet

            -- Act: A tries to save its divergent in-memory state.
            local ok = PlayerDataService.save(player, { force = true })

            -- Assert: fenced out -> save returns false, NO profile write occurred,
            -- save_fenced logged. A's divergent state dies with A (no dupe).
            expect(ok).to.equal(false)
            expect(fenced).to.equal(true)
            expect(profileStore._data[writeKey]).never.to.be.ok()
            -- Dirty stays set (the write never happened; recoverable via next tick
            -- on the authoritative server, but A no longer owns it).
            expect(PlayerDataService.get(player).dirty).to.equal(true)

            PlayerDataService.setLogger(function() end)
        end)

        it("the WINNING server (matching gen) saves normally through the fence", function()
            -- Arrange: this server owns the lock at gen 2; profile holds gen 2.
            local player = mockPlayer(2081)
            PlayerDataService._setProfileForTest(2081, Schema.default(), player)
            PlayerDataService._setLockGenForTest(2081, 2)
            SessionLock._writeLockForTest(2081, 2) -- durable lock: us, gen 2
            PlayerDataService.update(player, function(data)
                data.coins += 250
            end)

            -- Act
            local ok = PlayerDataService.save(player, { force = true })

            -- Assert: ownership proven -> write succeeds.
            expect(ok).to.equal(true)
            local raw = mockService:getRaw(Config.dataStoreName, Config.keyPrefix .. 2081)
            expect(raw.data.coins).to.equal(250)
            expect(raw.lockGen).to.equal(2) -- forensic fence stamp embedded
            expect(raw.lockJobId).to.equal(THIS_JOB)
        end)

        it("a FENCED receipt save rolls back the grant (M-2 feeds H-1)", function()
            -- Arrange: server holds gen 1; another server steals to gen 2.
            local player = mockPlayer(2082)
            PlayerDataService._setProfileForTest(2082, Schema.default(), player)
            local gemsBefore = PlayerDataService.getData(player).gems
            SessionLock._writeLockForTest(2082, 2, OTHER_JOB)

            -- Act: a receipt grant whose forced save is fenced out.
            local granted, reason = PlayerDataService.processReceiptGrant(player, "fenced-receipt", function(data)
                data.gems += 999
            end)

            -- Assert: not acked; grant + marker rolled back (we lost authority).
            expect(granted).to.equal(false)
            expect(reason).to.equal("save_failed")
            local after = PlayerDataService.getData(player)
            expect(after.gems).to.equal(gemsBefore)
            expect(after.consumedReceipts["fenced-receipt"]).to.equal(nil)
        end)
    end)

    -- ── M-1: HEARTBEAT AWAITS DEATH / NO RESURRECTION (ADR-002) ─────────────

    describe("stopHeartbeat awaits thread death (ADR-002 M-1)", function()
        it("thread is DEAD immediately after stopHeartbeat returns", function()
            -- Arrange: a loaded profile with a real heartbeat thread.
            local player = mockPlayer(2090)
            PlayerDataService._setProfileForTest(2090, Schema.default(), player)
            local thread = PlayerDataService._startHeartbeatForTest(2090)
            expect(coroutine.status(thread)).never.to.equal("dead")

            -- Act
            PlayerDataService.stopHeartbeat(2090)

            -- Assert: the await guarantees we OBSERVE dead, not assume it.
            expect(coroutine.status(thread)).to.equal("dead")
            expect(PlayerDataService._heartbeatThreadCountForTest()).to.equal(0)
        end)

        it("no lock UpdateAsync lands AFTER release (no resurrection write)", function()
            -- Arrange: a loaded profile + heartbeat; capture lock-store write
            -- count just before teardown.
            local player = mockPlayer(2091)
            PlayerDataService._setProfileForTest(2091, Schema.default(), player)
            local thread = PlayerDataService._startHeartbeatForTest(2091)
            local lockStore = mockService:getStore(Config.lockStoreName)
            local callsBefore = lockStore._updateCount

            -- Act: full removal (stop heartbeat -> save -> release -> drop).
            PlayerDataService.onPlayerRemoving(player)

            -- Assert: the heartbeat thread is dead, and the ONLY lock UpdateAsync
            -- during removal is the single release() — proving no in-flight beat
            -- refreshed (resurrected) the lock after release.
            expect(coroutine.status(thread)).to.equal("dead")
            expect(lockStore._updateCount - callsBefore).to.equal(1)

            -- And a subsequent settle window produces NO further lock writes.
            local settled = lockStore._updateCount
            task.wait(0.1)
            expect(lockStore._updateCount).to.equal(settled)
        end)
    end)

    -- ── SHUTDOWN BUDGET STAGGER (H2) ────────────────────────────────────────

    describe("saveAllOnClose budget stagger", function()
        it("still saves every profile when the budget is low (staggered)", function()
            -- Arrange: two dirty profiles + a low budget that triggers stagger.
            local p1, p2 = mockPlayer(2060), mockPlayer(2061)
            PlayerDataService._setProfileForTest(2060, Schema.default(), p1)
            PlayerDataService._setProfileForTest(2061, Schema.default(), p2)
            PlayerDataService.update(p1, function(data)
                data.coins = 1
            end)
            PlayerDataService.update(p2, function(data)
                data.coins = 2
            end)
            mockService:setRequestBudget(1) -- below shutdownBudgetStaggerThreshold

            -- Act
            PlayerDataService.saveAllOnClose()

            -- Assert: both persisted despite the low budget; cache cleared.
            expect(mockService:getRaw(Config.dataStoreName, Config.keyPrefix .. 2060).data.coins).to.equal(1)
            expect(mockService:getRaw(Config.dataStoreName, Config.keyPrefix .. 2061).data.coins).to.equal(2)
            expect(PlayerDataService.isLoaded(p1)).to.equal(false)
            expect(PlayerDataService.isLoaded(p2)).to.equal(false)
        end)
    end)
end
