--!nocheck
-- tests/ServerStorage/PlayerData/SessionLock.spec.luau
--
-- TestEZ specs for SessionLock (System #1, E1). AAA pattern, isolated tests,
-- MOCK DataStoreService (never touches the real store). Covers: free acquire,
-- re-acquire by same server, steal a STALE lock, refuse an ACTIVE lock held by
-- another server, heartbeat refresh, release semantics, store-failure safety.
--
-- NOTE: the active-lock test exercises the full retry/backoff loop, which uses
-- task.wait(lockAcquireBackoffSec) between attempts — this test takes a few
-- seconds by design (it proves we back off and ultimately fail rather than
-- loading over an active lock).

return function()
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local ServerStorage = game:GetService("ServerStorage")

    local SessionLock = require(ServerStorage.PlayerData.SessionLock)
    local Config = require(ReplicatedStorage.Shared.Config.PersistenceConfig)
    local MockDataStore = require(script.Parent.MockDataStore)

    local THIS_JOB = "job-self"
    local OTHER_JOB = "job-other"

    local mockService
    local function lockRecord(name, userId)
        return mockService:getRaw(name, Config.lockKeyPrefix .. userId)
    end

    beforeEach(function()
        mockService = MockDataStore.newService()
        SessionLock.setDataStoreService(mockService)
        SessionLock.setJobId(THIS_JOB)
    end)

    describe("SessionLock.acquire", function()
        it("acquires a FREE lock and writes our jobId", function()
            -- Act
            local ok = SessionLock.acquire(1001)

            -- Assert
            expect(ok).to.equal(true)
            expect(lockRecord(Config.lockStoreName, 1001).jobId).to.equal(THIS_JOB)
        end)

        it("returns gen 1 on a FREE acquire (ADR-002 M-2)", function()
            -- Act
            local ok, gen = SessionLock.acquire(1101)

            -- Assert: a fresh ownership transfer mints gen 1.
            expect(ok).to.equal(true)
            expect(gen).to.equal(1)
            expect(lockRecord(Config.lockStoreName, 1101).gen).to.equal(1)
        end)

        it("re-acquires a lock we already own (fast rejoin, MINE case)", function()
            -- Arrange: pre-seed a fresh lock owned by THIS server.
            local store = mockService:getStore(Config.lockStoreName)
            store._data[Config.lockKeyPrefix .. 1002] = { jobId = THIS_JOB, time = os.time() }

            -- Act
            local ok = SessionLock.acquire(1002)

            -- Assert
            expect(ok).to.equal(true)
        end)

        it("BUMPS gen on a mine-reacquire (ownership re-stamp, ADR-002 M-2)", function()
            -- Arrange: we own the lock at gen 4.
            local store = mockService:getStore(Config.lockStoreName)
            store._data[Config.lockKeyPrefix .. 1102] = { jobId = THIS_JOB, time = os.time(), gen = 4 }

            -- Act
            local ok, gen = SessionLock.acquire(1102)

            -- Assert: a reacquire is an ownership write -> strictly higher gen.
            expect(ok).to.equal(true)
            expect(gen).to.equal(5)
            expect(lockRecord(Config.lockStoreName, 1102).gen).to.equal(5)
        end)

        it("treats a lock value with NO gen as gen 0 and bumps to 1 (pre-ADR-002 value)", function()
            -- Arrange: a legacy lock value lacking the gen field.
            local store = mockService:getStore(Config.lockStoreName)
            store._data[Config.lockKeyPrefix .. 1103] = { jobId = THIS_JOB, time = os.time() }

            -- Act
            local ok, gen = SessionLock.acquire(1103)

            -- Assert
            expect(ok).to.equal(true)
            expect(gen).to.equal(1)
        end)

        it("steals a STALE lock held by a dead server and logs lock_stolen", function()
            -- Arrange: another server's lock, last heartbeat older than the
            -- stale window (presumed dead).
            local store = mockService:getStore(Config.lockStoreName)
            store._data[Config.lockKeyPrefix .. 1003] = {
                jobId = OTHER_JOB,
                time = os.time() - (Config.lockStaleSeconds + 5),
            }
            local stolen = false
            SessionLock.setLogger(function(event)
                if event == "lock_stolen" then
                    stolen = true
                end
            end)

            -- Act
            local ok = SessionLock.acquire(1003)

            -- Assert
            expect(ok).to.equal(true)
            expect(stolen).to.equal(true)
            expect(lockRecord(Config.lockStoreName, 1003).jobId).to.equal(THIS_JOB)

            SessionLock.setLogger(function() end)
        end)

        it("OUT-GENERATIONS a stolen stale lock (steal gen strictly > prior, ADR-002 M-2)", function()
            -- Arrange: a stale foreign lock at gen 7 (a frozen owner).
            local store = mockService:getStore(Config.lockStoreName)
            store._data[Config.lockKeyPrefix .. 1104] = {
                jobId = OTHER_JOB,
                time = os.time() - (Config.lockStaleSeconds + 5),
                gen = 7,
            }

            -- Act: we steal it.
            local ok, gen = SessionLock.acquire(1104)

            -- Assert: the stealer always mints a strictly higher generation, so a
            -- frozen owner saving with gen 7 can never match the new lock (gen 8).
            expect(ok).to.equal(true)
            expect(gen).to.equal(8)
            expect(lockRecord(Config.lockStoreName, 1104).jobId).to.equal(THIS_JOB)
        end)

        it("REFUSES an ACTIVE lock held & fresh by another server (returns false -> caller kicks)", function()
            -- Arrange: a fresh lock from another live server.
            local store = mockService:getStore(Config.lockStoreName)
            store._data[Config.lockKeyPrefix .. 1004] = { jobId = OTHER_JOB, time = os.time() }

            -- Act
            local ok = SessionLock.acquire(1004)

            -- Assert: never loaded over an active lock; ownership unchanged.
            expect(ok).to.equal(false)
            expect(lockRecord(Config.lockStoreName, 1004).jobId).to.equal(OTHER_JOB)
        end)
    end)

    describe("SessionLock.heartbeat", function()
        it("refreshes our lock's timestamp", function()
            -- Arrange: own a lock with an old timestamp.
            local store = mockService:getStore(Config.lockStoreName)
            local oldTime = os.time() - 10
            store._data[Config.lockKeyPrefix .. 1005] = { jobId = THIS_JOB, time = oldTime }

            -- Act
            SessionLock.heartbeat(1005)

            -- Assert
            expect(lockRecord(Config.lockStoreName, 1005).time >= oldTime).to.equal(true)
            expect(lockRecord(Config.lockStoreName, 1005).jobId).to.equal(THIS_JOB)
        end)

        it("does NOT clobber a lock another server has taken", function()
            -- Arrange: another server stole it.
            local store = mockService:getStore(Config.lockStoreName)
            store._data[Config.lockKeyPrefix .. 1006] = { jobId = OTHER_JOB, time = os.time() }

            -- Act
            SessionLock.heartbeat(1006)

            -- Assert
            expect(lockRecord(Config.lockStoreName, 1006).jobId).to.equal(OTHER_JOB)
        end)

        it("PRESERVES gen unchanged while refreshing time (ADR-002 M-2)", function()
            -- Arrange: own a lock at gen 3 with an old timestamp.
            local store = mockService:getStore(Config.lockStoreName)
            local oldTime = os.time() - 10
            store._data[Config.lockKeyPrefix .. 1107] = { jobId = THIS_JOB, time = oldTime, gen = 3 }

            -- Act
            SessionLock.heartbeat(1107)

            -- Assert: a heartbeat is NOT an ownership transfer -> gen is untouched,
            -- only time advances.
            expect(lockRecord(Config.lockStoreName, 1107).gen).to.equal(3)
            expect(lockRecord(Config.lockStoreName, 1107).time >= oldTime).to.equal(true)
        end)
    end)

    -- ── OWNERSHIP FENCE (ADR-002 M-2) ───────────────────────────────────────
    describe("SessionLock.ownershipMatches", function()
        it("returns true when the durable lock reads OUR jobId AND gen", function()
            -- Arrange
            local store = mockService:getStore(Config.lockStoreName)
            store._data[Config.lockKeyPrefix .. 1110] = { jobId = THIS_JOB, time = os.time(), gen = 2 }

            -- Act / Assert
            expect(SessionLock.ownershipMatches(1110, THIS_JOB, 2)).to.equal(true)
        end)

        it("returns false on a gen MISMATCH (a steal bumped the durable gen)", function()
            -- Arrange: durable lock is at a higher gen than we hold.
            local store = mockService:getStore(Config.lockStoreName)
            store._data[Config.lockKeyPrefix .. 1111] = { jobId = THIS_JOB, time = os.time(), gen = 9 }

            -- Act / Assert: we hold gen 8 -> fenced out.
            expect(SessionLock.ownershipMatches(1111, THIS_JOB, 8)).to.equal(false)
        end)

        it("returns false on a jobId MISMATCH (another server owns it)", function()
            -- Arrange
            local store = mockService:getStore(Config.lockStoreName)
            store._data[Config.lockKeyPrefix .. 1112] = { jobId = OTHER_JOB, time = os.time(), gen = 1 }

            -- Act / Assert
            expect(SessionLock.ownershipMatches(1112, THIS_JOB, 1)).to.equal(false)
        end)

        it("returns false when the lock is MISSING/cleared", function()
            -- Act / Assert: no record at all.
            expect(SessionLock.ownershipMatches(1113, THIS_JOB, 1)).to.equal(false)
        end)

        it("returns false (fence-out) when the GetAsync READ fails (money-safe)", function()
            -- Arrange: a valid lock, but force the read to fail.
            local store = mockService:getStore(Config.lockStoreName)
            store._data[Config.lockKeyPrefix .. 1114] = { jobId = THIS_JOB, time = os.time(), gen = 1 }
            store:failNext(1)

            -- Act / Assert: a failed read cannot prove ownership -> fence out.
            expect(SessionLock.ownershipMatches(1114, THIS_JOB, 1)).to.equal(false)
        end)
    end)

    describe("SessionLock.release", function()
        it("clears OUR lock", function()
            -- Arrange
            SessionLock.acquire(1007)

            -- Act
            SessionLock.release(1007)

            -- Assert
            expect(lockRecord(Config.lockStoreName, 1007)).never.to.be.ok()
        end)

        it("leaves another server's lock intact", function()
            -- Arrange
            local store = mockService:getStore(Config.lockStoreName)
            store._data[Config.lockKeyPrefix .. 1008] = { jobId = OTHER_JOB, time = os.time() }

            -- Act
            SessionLock.release(1008)

            -- Assert
            expect(lockRecord(Config.lockStoreName, 1008).jobId).to.equal(OTHER_JOB)
        end)
    end)

    describe("SessionLock failure safety", function()
        it("returns false (does not error) when the store fails every attempt", function()
            -- Arrange: fail more ops than attempts so all retries fail.
            local store = mockService:getStore(Config.lockStoreName)
            store:failNext(Config.lockAcquireMaxAttempts + 1)

            -- Act
            local ok = SessionLock.acquire(1009)

            -- Assert: never throws; reports failure so caller can kick.
            expect(ok).to.equal(false)
        end)
    end)

    -- ── MOCK UPDATEASYNC FIDELITY (ADR-001 H3) ──────────────────────────────
    -- The mock must mirror the real API: a transform returning nil performs NO
    -- write and returns the unchanged current value. SessionLock relies on this
    -- to "refuse without clobbering" an active foreign lock.

    describe("MockDataStore UpdateAsync nil semantics", function()
        it("does NOT write and returns the unchanged value when the transform returns nil", function()
            -- Arrange: a store with an existing value.
            local store = mockService:getStore(Config.lockStoreName)
            store._data["k"] = { jobId = OTHER_JOB, time = 123 }

            -- Act: a transform that returns nil (refuse).
            local returned = store:UpdateAsync("k", function(_existing)
                return nil
            end)

            -- Assert: stored value untouched; returned value == the unchanged current.
            expect(store._data["k"].jobId).to.equal(OTHER_JOB)
            expect(store._data["k"].time).to.equal(123)
            expect(returned.jobId).to.equal(OTHER_JOB)
            expect(returned.time).to.equal(123)
        end)

        it("writes and returns the new value when the transform returns non-nil", function()
            -- Arrange
            local store = mockService:getStore(Config.lockStoreName)
            store._data["k2"] = { jobId = OTHER_JOB, time = 1 }

            -- Act
            local returned = store:UpdateAsync("k2", function(_existing)
                return { jobId = THIS_JOB, time = 2 }
            end)

            -- Assert
            expect(store._data["k2"].jobId).to.equal(THIS_JOB)
            expect(returned.time).to.equal(2)
        end)
    end)
end
