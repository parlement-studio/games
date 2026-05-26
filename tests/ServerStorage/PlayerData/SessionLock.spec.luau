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

        it("re-acquires a lock we already own (fast rejoin, MINE case)", function()
            -- Arrange: pre-seed a fresh lock owned by THIS server.
            local store = mockService:getStore(Config.lockStoreName)
            store._data[Config.lockKeyPrefix .. 1002] = { jobId = THIS_JOB, time = os.time() }

            -- Act
            local ok = SessionLock.acquire(1002)

            -- Assert
            expect(ok).to.equal(true)
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
end
