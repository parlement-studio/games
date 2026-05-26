--!nocheck
-- tests/ServerStorage/PlayerData/MockDataStore.luau
--
-- A MOCK DataStoreService for tests (per .claude/rules/tests.md: mock external
-- services, NEVER touch the real DataStore). Implements the slice of the
-- DataStore API that Persistence uses: GetAsync, SetAsync, UpdateAsync.
--
-- Features used by the specs:
--   * deep-ish copy on read/write so callers can't mutate stored tables
--   * `failNext(n)` to simulate `n` consecutive op failures (retry/backoff tests)
--   * `getRaw(name, key)` to assert on what was actually persisted

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
    return setmetatable({ _data = {}, _failures = 0 }, Store)
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
    local current = deepCopy(self._data[key])
    local result = transform(current)
    if result ~= nil then
        self._data[key] = deepCopy(result)
        return deepCopy(result)
    end
    -- transform returned nil: keep existing value unchanged, return it.
    return deepCopy(self._data[key])
end

-- The mock service (mirrors DataStoreService:GetDataStore).
function MockDataStore.newService()
    local service = setmetatable({ _stores = {} }, MockDataStore)
    return service
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
