--!nocheck
-- tests/ServerStorage/PlayerData/MockDataStore.luau
--
-- A MOCK DataStoreService for tests (per .claude/rules/tests.md: mock external
-- services, NEVER touch the real DataStore). Implements the slice of the
-- DataStore API that Persistence uses: GetAsync, SetAsync, UpdateAsync, plus
-- service-level GetRequestBudgetForRequestType.
--
-- UpdateAsync CONTRACT (ADR-001 H3 — faithful to the real API):
--   * The transform is called with the CURRENT value (a deep copy).
--   * If the transform returns a NON-nil value, it is WRITTEN and returned.
--   * If the transform returns NIL, there is NO write: the existing value is
--     left UNCHANGED and that unchanged current value is returned. This is what
--     makes SessionLock's "return nil to refuse without clobbering" correct.
--
-- Features used by the specs:
--   * deep-ish copy on read/write so callers can't mutate stored tables
--   * `failNext(n)` to simulate `n` consecutive op failures (retry/backoff tests)
--   * `getRaw(name, key)` to assert on what was actually persisted
--   * `setRequestBudget(n)` to simulate a low/exhausted write budget (H2 tests);
--     defaults to a large value so the budget guard never falsely trips.

local MockDataStore = {}
MockDataStore.__index = MockDataStore

local function deepCopy(value)
    if type(value) ~= "table" then
        return value
    end
    local out = {}
    for k, v in pairs(value) do
        out[k] = deepCopy(v)
    end
    return out
end

-- One mock store (one DataStore name).
local Store = {}
Store.__index = Store

function Store.new()
    -- _updateCount lets specs assert how many UpdateAsync ops hit a store (e.g.
    -- proving a cancelled heartbeat fires no further lock writes — C3/C4).
    return setmetatable({ _data = {}, _failures = 0, _updateCount = 0 }, Store)
end

-- Force the next `n` operations on this store to throw.
function Store:failNext(n: number)
    self._failures = n
end

local function maybeFail(self)
    if self._failures > 0 then
        self._failures -= 1
        error("MockDataStore: simulated failure", 0)
    end
end

function Store:GetAsync(key)
    maybeFail(self)
    return deepCopy(self._data[key])
end

function Store:SetAsync(key, value)
    maybeFail(self)
    self._data[key] = deepCopy(value)
end

function Store:UpdateAsync(key, transform)
    maybeFail(self)
    self._updateCount += 1
    local current = deepCopy(self._data[key])
    local result = transform(current)
    if result ~= nil then
        self._data[key] = deepCopy(result)
        return deepCopy(result)
    end
    -- transform returned nil: keep existing value unchanged, return it.
    return deepCopy(self._data[key])
end

-- A large default so the budget guard (H2) never falsely throttles a test that
-- did not opt into a low budget. math.huge would not survive a JSON round-trip,
-- but this value is only ever read by GetRequestBudgetForRequestType.
local DEFAULT_REQUEST_BUDGET = 1e9

-- The mock service (mirrors DataStoreService:GetDataStore).
function MockDataStore.newService()
    local service = setmetatable({ _stores = {}, _requestBudget = DEFAULT_REQUEST_BUDGET }, MockDataStore)
    return service
end

-- Simulate the remaining request budget (H2). Set low to exercise the autosave
-- skip / shutdown stagger paths.
function MockDataStore:setRequestBudget(n: number)
    self._requestBudget = n
end

-- Mirrors DataStoreService:GetRequestBudgetForRequestType. Ignores the request
-- type (Persistence only queries SetIncrementAsync).
function MockDataStore:GetRequestBudgetForRequestType(_requestType)
    return self._requestBudget
end

function MockDataStore:GetDataStore(name: string)
    if self._stores[name] == nil then
        self._stores[name] = Store.new()
    end
    return self._stores[name]
end

-- Convenience for assertions.
function MockDataStore:getStore(name: string)
    return self:GetDataStore(name)
end

function MockDataStore:getRaw(name: string, key: string)
    return self:GetDataStore(name)._data[key]
end

return MockDataStore
