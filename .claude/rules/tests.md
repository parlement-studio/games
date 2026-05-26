---
paths:
  - "tests/**"
---

# Tests Rules

Files matching these paths are tests (TestEZ, Jest-Lua, or manual test plans).

## Core Rules

1. **Descriptive test names.** `test_PlayerData_SavesCorrectly_WhenPlayerLeaves` not `test_save`.
2. **Arrange-Act-Assert (AAA) pattern.** Set up, execute, verify — in that order.
3. **No test interdependencies.** Each test should run in isolation. No shared state between tests.
4. **Mock external services.** DataStore, HttpService, MarketplaceService — never use real services in tests.
5. **Cover edge cases.** Empty data, max values, nil inputs, rapid repeated calls.

## AAA Pattern

```lua
it("grants gold after killing an enemy", function()
    -- Arrange
    local player = createMockPlayer()
    local enemy = createMockEnemy({id = "goblin", goldReward = 10})
    PlayerData.setData(player, {gold = 0})

    -- Act
    Combat.killEnemy(player, enemy)

    -- Assert
    local data = PlayerData.getData(player)
    expect(data.gold).to.equal(10)
end)
```

## Mock Pattern

```lua
local MockDataStoreService = {}

function MockDataStoreService:GetDataStore(name: string)
    return {
        _data = {},
        GetAsync = function(self, key)
            return self._data[key]
        end,
        SetAsync = function(self, key, value)
            self._data[key] = value
        end,
    }
end

-- In test setup:
local PlayerData = require(...)
PlayerData._dataStoreService = MockDataStoreService
```

## Edge Case Checklist

For any system under test, cover:
- **Zero**: empty list, 0 currency, nil input
- **One**: single item, minimum valid value
- **Many**: large list, near-max value
- **Max**: exactly at the limit
- **Over max**: above the limit (should reject)
- **Negative**: negative input (should reject or clamp)
- **Rapid**: many calls in quick succession (rate limit check)
- **Concurrent**: simulated multi-player conflicts

## Test Organization

Follow the source structure:
```
tests/
├── ServerScriptService/
│   └── PlayerDataService.spec.lua
├── ReplicatedStorage/
│   └── Shared/
│       └── Utils.spec.lua
└── init.spec.lua
```

## Naming Conventions

- File: `<ModuleName>.spec.lua` or `<ModuleName>.spec.luau`
- Describe: `describe("ModuleName", function() ... end)`
- It: `it("does expected behavior in scenario", function() ... end)`

## Forbidden Patterns

- ❌ Tests that depend on other tests passing/failing
- ❌ Real DataStore calls in tests
- ❌ Real HttpService calls in tests
- ❌ Vague test names: `test_1`, `test_save`
- ❌ Tests without assertions
- ❌ Tests that only test the happy path
- ❌ Tests that are so broad they don't isolate the issue on failure
