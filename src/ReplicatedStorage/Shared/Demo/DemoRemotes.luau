--!strict
-- Shared/Demo/DemoRemotes.luau
--
-- DEMO-ONLY RemoteEvent registry for the "Brainrot Inc." vertical slice.
-- getOrCreate pattern: the first requirer (the server) creates the RemoteEvents
-- as children of THIS module; later requirers (the client) wait for and reuse
-- them. Returns a flat table of the RemoteEvents keyed by their exact name.
--
-- These names are a CONTRACT shared with the UI. Do not rename without updating
-- DemoServer, DemoClient, and the UI that consumes them.
--
--   Client -> Server:  OpenCrate(), Deploy(personality), Undeploy(slotIndex),
--                       Collect(), DeployToStand(standIndex, personality),
--                       SummonFighter(personality)
--   Server -> Client:  StateUpdate(state), CrateOpened(reveal), Moment(moment),
--                       InventoryUpdate(items), CoinUpdate({coins, pending}),
--                       OpenPlaceMenu(standIndex),
--                       BattleEvent({ kind = "win"|"ko", personality, coins? })
--
-- SHOWROOM LOOP (place → display → idle-production → collect):
--   DeployToStand(standIndex, personality)  C->S : place ONE caught Brainrot of
--                                 `personality` onto the SPECIFIC empty pedestal
--                                 `standIndex` (the player picks the podium by
--                                 triggering its Place prompt). Replaces the old
--                                 auto-fill Deploy(personality).
--   OpenPlaceMenu(standIndex)  S->C : the player triggered an empty stand's Place
--                                 prompt — open the place menu for that stand.
--   Collect()            C->S : bank the accrued `pending` into `coins`.
--   CoinUpdate           S->C : { coins: number, pending: number } (both floored).
--
-- NOTE: Deploy(personality) C->S is RETIRED (kept in the registry only so the
-- contract list / type is stable); the server no longer connects it. Placement
-- now flows through DeployToStand so the player chooses the podium.
--
-- CAPTURE LOOP (the active demo): catching is driven by ProximityPromptService on
-- the SERVER (no C->S remote needed for the catch itself). InventoryUpdate (S->C)
-- pushes the player's full caught-creature list after every catch / on join.
--
-- Isolated under the Demo/ namespace so the real remotes system is untouched.

local RunService = game:GetService("RunService")

-- Exact remote names. Order/grouping is documentation only.
local CLIENT_TO_SERVER = {
    "OpenCrate",
    "Deploy",
    "Undeploy",
    "Collect",
    "DeployToStand",
    -- COMBAT (Tahap 2): SummonFighter(personality) — summon an OWNED Brainrot of
    -- `personality` as a temporary field fighter that auto-battles the nearest
    -- wild. Server validates ownership + rate-limits; the bag is NOT consumed.
    "SummonFighter",
}

local SERVER_TO_CLIENT = {
    "StateUpdate",
    "CrateOpened",
    "Moment",
    "InventoryUpdate",
    "CoinUpdate",
    "OpenPlaceMenu",
    -- COMBAT (Tahap 2): BattleEvent({ kind = "win"|"ko", personality, coins? }) —
    -- transient combat feedback. The client renders it via the SAME Moment banner
    -- (it builds a friendly text from the payload); a dedicated remote keeps the
    -- combat-feedback stream distinct from the welcome-back Moment.
    "BattleEvent",
}

local ALL_NAMES = {}
for _, name in CLIENT_TO_SERVER do
    table.insert(ALL_NAMES, name)
end
for _, name in SERVER_TO_CLIENT do
    table.insert(ALL_NAMES, name)
end

export type DemoRemotes = {
    OpenCrate: RemoteEvent,
    Deploy: RemoteEvent,
    Undeploy: RemoteEvent,
    Collect: RemoteEvent,
    DeployToStand: RemoteEvent,
    SummonFighter: RemoteEvent,
    StateUpdate: RemoteEvent,
    CrateOpened: RemoteEvent,
    Moment: RemoteEvent,
    InventoryUpdate: RemoteEvent,
    CoinUpdate: RemoteEvent,
    OpenPlaceMenu: RemoteEvent,
    BattleEvent: RemoteEvent,
}

-- The module script instance is the parent for the RemoteEvents.
local container: Instance = script

local function getOrCreate(name: string): RemoteEvent
    if RunService:IsServer() then
        local existing = container:FindFirstChild(name)
        if existing and existing:IsA("RemoteEvent") then
            return existing
        end
        local remote = Instance.new("RemoteEvent")
        remote.Name = name
        remote.Parent = container
        return remote
    else
        -- Client: the server created these on boot; wait for replication.
        local remote = container:WaitForChild(name, 30)
        assert(remote and remote:IsA("RemoteEvent"), "[DemoRemotes] missing RemoteEvent: " .. name)
        return remote :: RemoteEvent
    end
end

local remotes = {} :: DemoRemotes
for _, name in ALL_NAMES do
    (remotes :: any)[name] = getOrCreate(name)
end

return remotes
