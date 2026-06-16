--!strict
-- Shared/Demo/DemoRemotes.luau
--
-- DEMO-ONLY RemoteEvent registry for the "Monster Relic" vertical slice.
-- getOrCreate pattern: the first requirer (the server) creates the RemoteEvents
-- as children of THIS module; later requirers (the client) wait for and reuse
-- them. Returns a flat table of the RemoteEvents keyed by their exact name.
--
-- These names are a CONTRACT shared with the UI. Do not rename without updating
-- DemoServer, DemoClient, and the UI that consumes them.
--
--   Client -> Server:  OpenCrate(), Deploy(personality), Undeploy(slotIndex),
--                       Collect(), DeployToStand(standIndex, monsterId),
--                       SummonFighter(monsterId)
--   Server -> Client:  StateUpdate(state), CrateOpened(reveal), Moment(moment),
--                       InventoryUpdate(items), CoinUpdate({coins, pending}),
--                       OpenPlaceMenu(standIndex),
--                       BattleEvent({ kind = "win"|"ko", personality, coins? })
--
-- SHOWROOM LOOP (place → display → idle-production → collect):
--   DeployToStand(standIndex, personality)  C->S : place ONE caught Monster of
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
    -- COMBAT (Phase 2): SummonFighter(personality) — summon an OWNED Monster of
    -- `personality` as a temporary field fighter that auto-battles the nearest
    -- wild. Server validates ownership + rate-limits; the bag is NOT consumed.
    "SummonFighter",
    -- KANDANG MENU: RequestKandang() — ask the server for a fresh kandang
    -- snapshot (replied via OpenKandangMenu). Rate-limited server-side.
    "RequestKandang",
    -- KANDANG MENU: RecallDeployed(standIndex) — pull the monster deployed on
    -- `standIndex` back into the bag (menu replacement for the old per-monster
    -- Recall prompt). Server validates ownership + rate-limits.
    "RecallDeployed",
    -- ECONOMY SINK: UpgradeKandang() — buy the next kandang (factory) level.
    -- Cost = EconomyConfig.upgradeCost("factory", level); production bonus =
    -- DemoConfig.kandang.upgrade.bonusPerLevel per level. Server validates
    -- funds + cap + rate-limits; persists base.buildings.b1.factoryLevel.
    "UpgradeKandang",
    -- ECONOMY SINK (S2): EvolveMonster(monsterId) — pay the activation cost
    -- to evolve an ELIGIBLE bag monster one stage (milestone level + coins,
    -- x rarity). Server validates everything; persists entry.evoStage.
    "EvolveMonster",
    -- ECONOMY SINK (S4): BuyCaptureItem(bundle: boolean) — buy 1 Capture Net
    -- (false) or the 10-bundle (true) from the Kandang menu shop. Prices from
    -- CaptureConfig.items.capture_net; server validates funds + rate-limits;
    -- persists profile.items.capture_net.
    "BuyCaptureItem",
    -- COMBAT STANCE: SetStance(stance: "attack" | "defense") — set the player's
    -- summoned-fighter behavior. "attack" hunts wilds proactively; "defense" only
    -- retaliates when a wild attacks. Server validates the value; ephemeral
    -- (per-session, not persisted).
    "SetStance",
    -- DAILY QUEST: ClaimDailyQuest(questId: string) — claim the reward for a
    -- completed daily quest. Server validates progress >= target, idempotent via
    -- the persisted `claimed` flag; rate-limited. (first-hour-daily-loop-gdd §5)
    "ClaimDailyQuest",
}

local SERVER_TO_CLIENT = {
    "StateUpdate",
    "CrateOpened",
    "Moment",
    "InventoryUpdate",
    "CoinUpdate",
    "OpenPlaceMenu",
    -- COMBAT (Phase 2): BattleEvent({ kind = "win"|"ko", personality, coins? }) —
    -- transient combat feedback. The client renders it via the SAME Moment banner
    -- (it builds a friendly text from the payload); a dedicated remote keeps the
    -- combat-feedback stream distinct from the welcome-back Moment.
    "BattleEvent",
    -- BACKPACK (S4 items): BackpackUpdate({ items = { [itemId]: count } }) —
    -- pushed on hydrate and whenever an item count changes (purchase /
    -- consumption). Feeds the menu's Item tab.
    "BackpackUpdate",
    -- KANDANG MENU: OpenKandangMenu(payload) — open/refresh the kandang menu.
    -- payload = {
    --   capacity: number,                 -- total stands (6)
    --   deployed: { { index, personality, element, level } }, -- occupied slots
    --   free: { number },                 -- empty stand indices (ascending)
    -- }
    -- Sent when the player triggers the kandang terminal prompt, on
    -- RequestKandang, and after every deploy/recall (live refresh while open).
    -- payload.open: true ONLY for a fresh user intent (terminal prompt /
    -- RequestKandang) — everything else is a live refresh that must NOT
    -- pop the menu open (e.g. the post-catch net-counter push).
    "OpenKandangMenu",
    -- MERCHANT SHOP: OpenShopMenu() — the player triggered the Merchant NPC's
    -- prompt; open the shop modal. Item counts come from BackpackUpdate and
    -- prices from the replicated CaptureConfig, so the payload stays empty.
    "OpenShopMenu",
    -- CATCH CINEMATIC: CatchCinematic({ model, personality, element, success }) —
    -- a capture attempt RESOLVED; the catching client plays the net-throw +
    -- camera sequence (presentation only — the roster mint / charge already
    -- committed). `success = true` → struggle + suck-in + poof on the frozen
    -- wild (server despawns it after holdSec). `success = false` → MISS: the net
    -- bounces off + the wild flashes free (server keeps it; no shrink). The
    -- field is omitted only by the legacy always-success path (client treats
    -- absent → success).
    "CatchCinematic",
    -- FTUE: GoalUpdate({ goals = { {id,icon,label,done} }, allDone }) — pushes the
    -- onboarding goal checklist (first-hour-daily-loop-gdd) on join + whenever a
    -- goal completes. Client renders the panel and hides it once allDone.
    "GoalUpdate",
    -- DAILY QUEST: DailyUpdate({ quests = { {id,icon,label,progress,target,claimed,claimable} },
    -- loginReward?, resetInSec }) — pushes the daily quest panel on join, on
    -- reset, and whenever progress/claim changes. (first-hour-daily-loop-gdd §5)
    "DailyUpdate",
    -- MONSTER GALLERY: GalleryUpdate({ caught = { [\"species|element\"] = true } }) —
    -- the permanent dex set. Pushed on join and whenever a new combo is discovered.
    -- The client renders the full 5x5 grid from config; this only flags which cells
    -- are unlocked.
    "GalleryUpdate",
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
    RequestKandang: RemoteEvent,
    RecallDeployed: RemoteEvent,
    UpgradeKandang: RemoteEvent,
    EvolveMonster: RemoteEvent,
    BuyCaptureItem: RemoteEvent,
    SetStance: RemoteEvent,
    ClaimDailyQuest: RemoteEvent,
    StateUpdate: RemoteEvent,
    CrateOpened: RemoteEvent,
    Moment: RemoteEvent,
    InventoryUpdate: RemoteEvent,
    CoinUpdate: RemoteEvent,
    OpenPlaceMenu: RemoteEvent,
    BattleEvent: RemoteEvent,
    BackpackUpdate: RemoteEvent,
    OpenKandangMenu: RemoteEvent,
    OpenShopMenu: RemoteEvent,
    CatchCinematic: RemoteEvent,
    GoalUpdate: RemoteEvent,
    DailyUpdate: RemoteEvent,
    GalleryUpdate: RemoteEvent,
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
