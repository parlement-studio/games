--!strict
-- StarterPlayerScripts/Demo/DemoClient.luau
--
-- DEMO-ONLY client CONTROLLER for the "Brainrot Inc." CAPTURE + INVENTORY slice.
-- This is a ModuleScript — the thin presentation-facing layer the UI consumes.
-- It does NOT build any ScreenGui; it only:
--   * holds the last server inventory (DemoClient.Inventory = { InventoryItem }),
--   * exposes a Signal the UI subscribes to (InventoryChanged),
--   * connects the S->C InventoryUpdate remote to that signal.
--
-- The CLIENT IS PRESENTATION ONLY: it never owns the inventory. Catching is
-- driven by the creature's built-in ProximityPrompt on the SERVER; there are no
-- catch intents to send. The server pushes InventoryUpdate after every catch.
--
-- Isolated under the Demo/ namespace. Trove for connection cleanup; Signal for
-- the public signal.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Signal = require(Packages:WaitForChild("Signal"))
local Trove = require(Packages:WaitForChild("Trove"))

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DemoFolder = Shared:WaitForChild("Demo")
local DemoRemotes = require(DemoFolder:WaitForChild("DemoRemotes"))

-- ── Types (the contract the UI builds against) ───────────────────────────
-- PROGRESSION: each item carries its roster `id` (the SUMMON target) and the
-- Brainrot's current `level`; the UI builds the display label itself (no `name`).
-- STAT SHEET: the server also derives the per-monster stat fields (xp/xpToNext for
-- the XP bar, hp/power combat stats, wins/coinsMade lifetime flavor) so the detail
-- modal renders entirely from this payload. All fields are server-authoritative;
-- the client only displays them (it never computes game state).
export type InventoryItem = {
    id: string, -- roster GUID; passed to DemoClient.summon to send out THIS Brainrot
    personality: string, -- "Hyper" | "Lazy" | "Chaotic" | "Loyal" | "Rebel"
    level: number, -- current progression level (>= 1)
    xp: number, -- XP banked toward the next level
    xpToNext: number, -- XP needed for the next level
    hp: number, -- derived combat Max HP at this level
    power: number, -- derived per-tick combat damage at this level + personality
    wins: number, -- lifetime battles won
    coinsMade: number, -- lifetime coins this Brainrot produced (floored)
}

export type Inventory = { InventoryItem }

-- Server-authoritative AUTO-COLLECT coin snapshot: the floored live total plus
-- the current production rate (coins/sec) used to interpolate between pushes.
export type CoinState = {
    coins: number,
    rate: number,
}

-- COMBAT (Tahap 2 + PROGRESSION): server -> client combat feedback. `kind` is
-- "win" (the fighter defeated a wild, `coins` = coins awarded) or "ko" (the
-- fighter fainted / timed out and returned to the bag). On a WIN, `leveledTo` is
-- set IFF the fighter's Brainrot leveled up (show a "Level Up!" banner instead of
-- coins); `level` is its current level for display. Presentation only; the server
-- owns coins, xp, and levels.
export type BattlePayload = {
    kind: string,
    personality: string,
    coins: number?,
    leveledTo: number?,
    level: number?,
}

-- ── Module ─────────────────────────────────────────────────────────────────
local DemoClient = {}

-- Last received authoritative inventory (empty until the first update arrives).
DemoClient.Inventory = {} :: Inventory

-- Last received authoritative coin values (display-only; server owns them).
-- AUTO-COLLECT interpolation state: the HUD smoothly climbs from `baseCoins` at
-- `ratePerSec`, measured from `lastAt`. `Coins` mirrors the last server total.
DemoClient.Coins = 0
local baseCoins = 0
local ratePerSec = 0
local lastAt = os.clock()

-- MONOTONIC display latch. Coins only ever go UP server-side, so the SHOWN
-- number must never visibly drop. `displayShown` is the highest value the HUD
-- has presented; both the CoinUpdate handler and getDisplayCoins() ratchet it
-- upward only. This removes the flicker where a fresh (slightly lower) server
-- snapshot would otherwise undercut the already-predicted total.
local displayShown = 0

-- Public signals (the UI connects to these).
-- InventoryChanged fires with (inventory: Inventory).
-- CoinsChanged fires (no args) on each CoinUpdate; the HUD reads the live total
--   via DemoClient.getDisplayCoins() (AUTO-COLLECT interpolation).
-- PlaceMenuRequested fires with (standIndex: number) when the player triggers an
--   empty podium's Place (F) prompt — the UI opens the place menu for that stand.
DemoClient.InventoryChanged = Signal.new()
DemoClient.CoinsChanged = Signal.new()
DemoClient.PlaceMenuRequested = Signal.new()
-- COMBAT (Tahap 2): fires with a banner-ready payload { kind, text, coins? } each
-- time the server sends a BattleEvent (a fighter WON a fight or was KO'd). The UI
-- shows it via the SAME transient Moment banner (no separate combat UI needed).
DemoClient.BattleFeedback = Signal.new()

local trove = Trove.new()
local started = false

-- ── init: connect S->C remotes to the signals. Call once. ────────────────
function DemoClient.init()
    if started then
        return
    end
    started = true

    trove:Add(DemoRemotes.InventoryUpdate.OnClientEvent:Connect(function(items: Inventory)
        DemoClient.Inventory = items or {}
        print(("[Inv][client] received InventoryUpdate count=%d"):format(#DemoClient.Inventory))
        DemoClient.InventoryChanged:Fire(DemoClient.Inventory)
    end))
    print("[Inv][client] InventoryUpdate handler connected")

    trove:Add(DemoRemotes.CoinUpdate.OnClientEvent:Connect(function(snapshot: CoinState)
        snapshot = snapshot or { coins = 0, rate = 0 }
        DemoClient.Coins = snapshot.coins or 0
        baseCoins = DemoClient.Coins
        ratePerSec = snapshot.rate or 0
        lastAt = os.clock()
        -- Ratchet the shown value UP only; never snap down below what the HUD
        -- has already displayed (server coins are monotonic non-decreasing).
        if baseCoins > displayShown then
            displayShown = baseCoins
        end
        print(("[Coin][client] coins=%d rate=%.2f/s"):format(DemoClient.Coins, ratePerSec))
        DemoClient.CoinsChanged:Fire()
    end))
    print("[Coin][client] CoinUpdate handler connected")

    trove:Add(DemoRemotes.OpenPlaceMenu.OnClientEvent:Connect(function(standIndex: number)
        print(("[Place][client] OpenPlaceMenu stand=%s"):format(tostring(standIndex)))
        DemoClient.PlaceMenuRequested:Fire(standIndex)
    end))
    print("[Place][client] OpenPlaceMenu handler connected")

    -- COMBAT (Tahap 2): translate a BattleEvent into a banner-ready payload and
    -- re-emit it on BattleFeedback (the UI shows it via the shared Moment banner).
    trove:Add(DemoRemotes.BattleEvent.OnClientEvent:Connect(function(payload: BattlePayload)
        if type(payload) ~= "table" or type(payload.kind) ~= "string" then
            return
        end
        local upper = string.upper(tostring(payload.personality or "?"))
        local text: string
        if payload.kind == "win" then
            -- PROGRESSION: a level-up takes priority in the banner (it is the
            -- rarer, more exciting event); otherwise show the coin reward.
            if type(payload.leveledTo) == "number" then
                text = string.format("⭐ %s Level Up! → Lv%d", upper, payload.leveledTo)
            else
                text = string.format("⚔ %s won the fight! +%d coins", upper, payload.coins or 0)
            end
        else
            text = string.format("⚔ %s returned to your bag", upper)
        end
        print(("[Combat][client] BattleEvent kind=%s personality=%s"):format(payload.kind, upper))
        DemoClient.BattleFeedback:Fire({ kind = payload.kind, text = text, coins = payload.coins })
    end))
    print("[Combat][client] BattleEvent handler connected")
end

-- ── Intents (C->S). The server validates + owns the result. ────────────────
-- Place one caught Brainrot of `personality` onto the SPECIFIC empty pedestal
-- `standIndex`. The player picked the podium (its Place prompt) and the creature
-- (a row in the place menu); the server validates both and owns the result.
function DemoClient.deployToStand(standIndex: number, personality: string)
    DemoRemotes.DeployToStand:FireServer(standIndex, personality)
end

-- COMBAT (Tahap 2 + PROGRESSION): summon a SPECIFIC owned Brainrot (by its roster
-- `brainrotId`) as a temporary field fighter that auto-battles the nearest wild.
-- Summoning by explicit id so XP/levels attach to the exact individual. The server
-- validates ownership (in roster, not deployed, not already fighting) + rate-limits;
-- the roster entry is NOT consumed (summoning is ephemeral).
function DemoClient.summon(brainrotId: string)
    DemoRemotes.SummonFighter:FireServer(brainrotId)
end

-- AUTO-COLLECT: the live coin total to display RIGHT NOW. Extrapolates from the
-- last server total (`baseCoins`) at `ratePerSec` since `lastAt`, so the HUD
-- climbs smoothly between server pushes. The prediction can only RAISE the
-- latched `displayShown`, never lower it, so the shown number is monotonic
-- non-decreasing (no down-then-up flicker between pushes). Floored to a whole
-- coin for display only; drift stays latency-bounded since `rate` is exact.
function DemoClient.getDisplayCoins(): number
    local predicted = baseCoins + ratePerSec * (os.clock() - lastAt)
    if predicted > displayShown then
        displayShown = predicted
    end
    return math.floor(displayShown)
end

-- AUTO-COLLECT: the current production rate (coins/sec) from the last server
-- push, for the HUD's "+N/s" line.
function DemoClient.getRate(): number
    return ratePerSec
end

-- Tear down all connections + signals (e.g. on a soft restart). Optional.
function DemoClient.destroy()
    trove:Clean()
    DemoClient.InventoryChanged:DisconnectAll()
    DemoClient.CoinsChanged:DisconnectAll()
    DemoClient.PlaceMenuRequested:DisconnectAll()
    DemoClient.BattleFeedback:DisconnectAll()
    started = false
end

return DemoClient
