--!strict
-- ServerScriptService/Demo/DailyService.luau
--
-- DAILY LOOP server core (first-hour-daily-loop-gdd §2.2/§4). Owns the daily
-- reset schedule, the 3-quest roll, progress tracking, and the idempotent claim.
-- SERVER-AUTHORITATIVE: the client never reports progress — every quest's
-- `progress` is bumped here from the SAME hooks the game already fires (catch,
-- boss-kill, coin-flush). The client only renders the pushed payload + sends a
-- ClaimDailyQuest(questId) intent.
--
-- Reset model: the day boundary is `floor((os.time() - resetHourUTC*3600)/86400)`
-- (an integer "day index", server-clock UTC). A profile whose stored reset is in
-- an EARLIER day index gets rolled fresh — applied on load (hydrate) AND by a
-- per-minute timer (so a server alive across midnight rolls online players). The
-- daily login reward is a small ritual auto-granted the first time a player is
-- seen each day (NOT a claim button).
--
-- Coin REWARDS are NOT credited here (this module has no access to the live coin
-- float). tryClaim only flips the persisted `claimed` flag atomically + returns
-- the reward amount; DemoServer credits it through the existing state.coins path.

local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataService = require(ServerStorage:WaitForChild("PlayerData"):WaitForChild("PlayerDataService"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local DemoConfig = require(Shared:WaitForChild("Demo"):WaitForChild("DemoConfig"))
local DemoRemotes = require(Shared:WaitForChild("Demo"):WaitForChild("DemoRemotes"))
local ElementConfig = require(Shared:WaitForChild("Config"):WaitForChild("ElementConfig"))

local DailyService = {}

local CFG = DemoConfig.daily
local DAY_SECONDS = 86400

-- Config lookup by quest id (icon + label + reward live in config; the persisted
-- quest carries only id/kind/param/target/progress/claimed).
local CFG_BY_ID: { [string]: any } = {}
for _, q in CFG.quests do
    CFG_BY_ID[q.id] = q
end

-- Integer "day index" for an os.time() value, offset by the reset hour so the
-- boundary lands at resetHourUTC:00 server time. Two times in the same day index
-- belong to the same daily window.
local function dayIndex(t: number): number
    return math.floor((t - CFG.resetHourUTC * 3600) / DAY_SECONDS)
end

-- Seconds until the NEXT reset boundary from `now` (for the client countdown).
local function resetInSec(now: number): number
    local nextBoundary = (dayIndex(now) + 1) * DAY_SECONDS + CFG.resetHourUTC * 3600
    return math.max(0, nextBoundary - now)
end

-- Roll the 3 quests for a fresh day from config. catch_element draws a random
-- target Element into `param`; the rest carry no param. Returns plain JSON-safe
-- quest records (the persisted shape).
local function rollQuests(): { any }
    local out = {}
    for _, q in CFG.quests do
        local param: string? = nil
        if q.randomElement then
            local order = ElementConfig.order
            param = order[math.random(1, #order)]
        end
        table.insert(out, {
            id = q.id,
            kind = q.kind,
            param = param,
            target = q.target,
            progress = 0,
            claimed = false,
        })
    end
    return out
end

-- ── Reset + login ritual ────────────────────────────────────────────────────

-- Backfill `daily` if missing, apply the daily reset if the stored window is
-- stale, and auto-grant the login reward the first time the player is seen this
-- day. Returns { reset, loginReward } so DemoServer can credit the coins through
-- the live float. Pre-checks via getData so a no-op day does NOT dirty the save.
function DailyService.ensureReset(player: Player): { reset: boolean, loginReward: number }
    local result = { reset = false, loginReward = 0 }

    local data = PlayerDataService.getData(player)
    if data ~= nil and data.daily ~= nil then
        local d = data.daily
        local fresh = d.lastResetAt ~= 0 and dayIndex(d.lastResetAt) >= dayIndex(os.time())
        if fresh and d.loginClaimed then
            return result -- nothing to do for this player today
        end
    end

    PlayerDataService.update(player, function(profile)
        local daily = profile.daily
        if daily == nil then
            daily = { lastResetAt = 0, loginClaimed = false, quests = {}, bossFirstKill = {} }
            profile.daily = daily
        end
        local now = os.time()
        local changed = false

        local needReset = daily.lastResetAt == 0 or dayIndex(daily.lastResetAt) < dayIndex(now)
        if needReset then
            daily.quests = rollQuests()
            daily.bossFirstKill = {}
            daily.loginClaimed = false
            daily.lastResetAt = now
            result.reset = true
            changed = true
        end

        -- LOGIN RITUAL: first sighting this day grants the small reward once.
        if not daily.loginClaimed then
            daily.loginClaimed = true
            result.loginReward = CFG.loginRewardCoins
            changed = true
        end

        return changed
    end)

    return result
end

-- ── Push ────────────────────────────────────────────────────────────────────

-- Build + ship the daily panel payload (no-op if disabled / no profile yet).
function DailyService.push(player: Player)
    local data = PlayerDataService.getData(player)
    if data == nil or data.daily == nil then
        return
    end
    local rows = {}
    for _, q in data.daily.quests do
        local cfg = CFG_BY_ID[q.id]
        local icon = if cfg then cfg.icon else "•"
        -- label template: %d <- target, %s <- param (extra arg ignored when the
        -- template has no %s, so one call serves every quest kind).
        local label = if cfg then string.format(cfg.label, q.target, q.param or "") else q.id
        local prog = math.floor(math.min(q.progress, q.target))
        table.insert(rows, {
            id = q.id,
            icon = icon,
            label = label,
            progress = prog,
            target = q.target,
            claimed = q.claimed,
            claimable = (q.progress >= q.target and not q.claimed),
        })
    end
    DemoRemotes.DailyUpdate:FireClient(player, {
        quests = rows,
        resetInSec = resetInSec(os.time()),
    })
end

-- ── Progress hooks ──────────────────────────────────────────────────────────

-- True iff the player has at least one ACTIVE (unclaimed + unmet) quest of
-- `kind` that `param` would advance (param nil = matches any). Read-only.
local function hasActive(data: any, kind: string, param: string?): boolean
    if data == nil or data.daily == nil then
        return false
    end
    for _, q in data.daily.quests do
        if q.kind == kind and not q.claimed and q.progress < q.target then
            if param == nil or q.param == nil or q.param == param then
                return true
            end
        end
    end
    return false
end

-- Add `amount` to every active quest of `kind` (capped at target). param-gated
-- like hasActive. Pre-checks so a no-op does not dirty the profile. Returns true
-- iff something progressed (caller pushes).
local function bump(player: Player, kind: string, amount: number, param: string?): boolean
    local data = PlayerDataService.getData(player)
    if not hasActive(data, kind, param) then
        return false
    end
    PlayerDataService.update(player, function(profile)
        if profile.daily == nil then
            return false
        end
        local changed = false
        for _, q in profile.daily.quests do
            if q.kind == kind and not q.claimed and q.progress < q.target then
                if param == nil or q.param == nil or q.param == param then
                    q.progress = math.min(q.target, q.progress + amount)
                    changed = true
                end
            end
        end
        return changed
    end)
    return true
end

-- A successful catch of `element` advances any catch_element quest for it.
function DailyService.noteCatch(player: Player, element: string?)
    if bump(player, "catch_element", 1, element) then
        DailyService.push(player)
    end
end

-- A boss defeat advances boss_kills AND marks bossFirstKill[personality] (the
-- latter reserved for Build #4 reward decay). Always pushes (bosses are rare).
function DailyService.noteBossKill(player: Player, personality: string?)
    local data = PlayerDataService.getData(player)
    if data == nil or data.daily == nil then
        return
    end
    PlayerDataService.update(player, function(profile)
        if profile.daily == nil then
            return false
        end
        local changed = false
        if personality ~= nil and profile.daily.bossFirstKill[personality] ~= true then
            profile.daily.bossFirstKill[personality] = true
            changed = true
        end
        for _, q in profile.daily.quests do
            if q.kind == "boss_kills" and not q.claimed and q.progress < q.target then
                q.progress = math.min(q.target, q.progress + 1)
                changed = true
            end
        end
        return changed
    end)
    DailyService.push(player)
end

-- Read-only: true iff defeating this boss personality RIGHT NOW would be the
-- first kill of the day (the daily map does not yet record it). The reward path
-- reads this BEFORE noteBossKill flips the map, to pick full vs decayed boss
-- reward (Build #4 / §2.3). Defaults to true (full reward) when daily state or
-- personality is missing, so a degraded path never silently under-pays.
function DailyService.isBossFirstKillToday(player: Player, personality: string?): boolean
    if personality == nil then
        return true
    end
    local data = PlayerDataService.getData(player)
    if data == nil or data.daily == nil then
        return true
    end
    return data.daily.bossFirstKill[personality] ~= true
end

-- Idle production earned (the per-flush production delta) advances earn_coins.
-- `amount` is a float; progress floors only at display time.
function DailyService.noteCoins(player: Player, amount: number)
    if amount <= 0 then
        return
    end
    if bump(player, "earn_coins", amount, nil) then
        DailyService.push(player)
    end
end

-- ── Claim ───────────────────────────────────────────────────────────────────

-- Atomically flip a completed quest's `claimed` flag. Returns (didClaim, reward).
-- didClaim reflects the TRANSACTION's result (only the call that actually flips
-- the flag gets true) so two racing claims can never both pay out. The caller
-- credits `reward` through the live coin float ONLY when didClaim is true.
function DailyService.tryClaim(player: Player, questId: string): (boolean, number)
    local data = PlayerDataService.getData(player)
    if data == nil or data.daily == nil then
        return false, 0
    end
    -- Cheap pre-check so an invalid/duplicate claim does not dirty the profile.
    local found = false
    for _, q in data.daily.quests do
        if q.id == questId then
            found = true
            if q.claimed or q.progress < q.target then
                return false, 0
            end
            break
        end
    end
    if not found then
        return false, 0
    end

    local cfg = CFG_BY_ID[questId]
    local reward = if cfg then cfg.rewardCoins else 0

    local ok, result = PlayerDataService.update(player, function(profile)
        if profile.daily == nil then
            return false
        end
        for _, q in profile.daily.quests do
            if q.id == questId then
                -- Re-check INSIDE the transaction: a racing claim that committed
                -- first will have set `claimed`, so this call returns false (no
                -- double payout) even though update still commits the no-op copy.
                if q.claimed or q.progress < q.target then
                    return false
                end
                q.claimed = true
                return true
            end
        end
        return false
    end)

    if ok and result == true then
        return true, reward
    end
    return false, 0
end

return DailyService
