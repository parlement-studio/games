--!strict
-- ServerScriptService/Demo/DemoServer.server.luau
--
-- DEMO-ONLY server for the "Brainrot Inc." CAPTURE + INVENTORY vertical slice.
--
-- ROUGH PROTOTYPE (briefing demo): relaxed standards, but SERVER-AUTHORITATIVE
-- so it is a real slice. State is IN-MEMORY ONLY (no DataStore) for fast
-- iteration — everything resets on server restart / rejoin. Isolated under the
-- Demo/ namespace so it does not touch the real persistence/idle systems.
--
-- THE LOOP (what this script owns):
--   The 5 creature Models pre-placed in the Workspace (`Brainrot_HYPER` ..
--   `Brainrot_REBEL`) each get a "Hold F to Catch" ProximityPrompt on startup.
--   When a player holds F near one, ProximityPromptService fires PromptTriggered
--   on the server -> we add the creature to that player's in-memory INVENTORY,
--   push the full inventory to that player (InventoryUpdate), remove the creature
--   from the world, then respawn it after `creatureRespawnSec` so the demo is
--   repeatable. The client only renders the inventory; the SERVER owns it.
--
-- The client NEVER mutates the inventory. The catch itself is driven entirely by
-- the built-in ProximityPrompt (no C->S remote). All prompt triggers are
-- validated (must belong to one of our creatures) and lightly rate-limited.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DemoFolder = Shared:WaitForChild("Demo")
local DemoConfig = require(DemoFolder:WaitForChild("DemoConfig"))
local DemoRemotes = require(DemoFolder:WaitForChild("DemoRemotes"))

-- PERSISTENCE INTEGRATION: the demo now reads/writes through the AUDITED
-- Persistence service so coins + caught creatures + which-stand survive a rejoin,
-- and offline coins accrue while away. We touch ONLY the public PlayerDataService
-- API (getData / isLoaded / addBrainrot / update / setOfflineResolver / DataLoaded)
-- and mint roster entries via Schema.newBrainrot — never DataStoreService directly.
-- Profiles are loaded by PlayerDataBootstrap on join (kick-on-fail + autosave +
-- BindToClose); this script just hydrates the live world from the loaded profile.
--
-- NOTE: the Showroom is a SINGLE-PLAYER demo space — deployed creatures re-spawn
-- for the joining player (slots are not shared across players).
local Types = require(Shared:WaitForChild("Types"))
local ElementConfig = require(Shared:WaitForChild("Config"):WaitForChild("ElementConfig"))
-- ECONOMY SINKS (demo): catch cost (CaptureConfig, authoritative) + the LOCKED
-- factory upgrade curve (EconomyConfig.upgradeCost) consumed by Upgrade Kandang.
local CaptureConfig = require(Shared:WaitForChild("Config"):WaitForChild("CaptureConfig"))
local EconomyConfig = require(Shared:WaitForChild("Config"):WaitForChild("EconomyConfig"))
-- RARITY (rarity doc R3): statMultFor multiplies fighter HP + damage as one
-- factor alongside levelScale/personality/elementMod. Defensive 1.0 fallback.
local RarityConfig = require(Shared:WaitForChild("Config"):WaitForChild("RarityConfig"))
local PlayerDataService = require(ServerStorage:WaitForChild("PlayerData"):WaitForChild("PlayerDataService"))
local Schema = require(ServerStorage:WaitForChild("PlayerData"):WaitForChild("Schema"))

type Types_PlayerData = Types.PlayerData

-- The single MVP building this demo persists deploys into.
local BUILDING_ID = "b1"

-- species id = 1-based index of the personality in DemoConfig.personalityOrder
-- (the persisted roster entry stores a numeric species; the demo only has the 5
-- personality archetypes, so personality order IS the species mapping). Fallback 1.
-- ELEMENT (sandbox wiring, element doc E2): emoji badge for an element key.
-- Returns "" for nil/unknown so a label never renders garbage.
local function elementEmoji(element: any): string
    local display = ElementConfig.display[element]
    return if display then display.emoji else ""
end

local speciesByPersonality: { [string]: number } = {}
for index, key in DemoConfig.personalityOrder do
    speciesByPersonality[key] = index
end

-- ── Types ────────────────────────────────────────────────────────────────
-- One bag item pushed to the client. PROGRESSION: the inventory is now DERIVED
-- FRESH from the authoritative roster on every push (not a drifting local list),
-- so level-ups show immediately. Each item carries the roster GUID (`id`, used by
-- SUMMON to target a SPECIFIC Brainrot), the personality, the entry's current
-- `level`, and the STAT-SHEET fields the client renders (xp/xpToNext for the bar,
-- hp/power derived combat stats, wins/coinsMade lifetime flavor). All fields are
-- derived SERVER-SIDE from the authoritative roster entry — the client never
-- computes game state, it only displays these.
type InventoryItem = {
    id: string, -- persisted roster GUID (also the SUMMON target)
    personality: string, -- canonical key: "Hyper" | "Lazy" | "Chaotic" | "Loyal" | "Rebel"
    element: string, -- persisted element enum ("Fire"|"Nature"|"Water"|"Volt"|"Wind"), display badge
    rarity: string, -- persisted rarity enum ("Common".."Legendary"), badge tint (rarity doc R3)
    evoStage: number, -- persisted evolution stage (0..maxStage)
    evolveCost: number?, -- coins for the NEXT stage (x rarity); nil = MAX stage
    evolveMilestone: number?, -- level required for the NEXT stage; nil = MAX stage
    level: number, -- current progression level of this Brainrot (>= 1)
    xp: number, -- XP banked toward the next level
    xpToNext: number, -- XP needed for the next level (xpCurveBase * level)
    hp: number, -- derived combat Max HP at this level
    power: number, -- derived per-tick combat damage at this level + personality
    wins: number, -- lifetime battles won (history.rwon)
    coinsMade: number, -- lifetime coins this Brainrot has produced (floored)
}

-- One occupied Showroom pedestal: which personality stands there + its clone +
-- the persisted roster GUID of the deployed creature (so recall can clear the
-- deployment map entry for the right id).
type DeployedSlot = {
    personality: string,
    model: Model,
    id: string, -- persisted roster GUID of the deployed creature
    -- KANDANG WANDER: os.clock() gate for this deployed monster's next wander
    -- move (mirrors the pack slots' nextMoveAt). nil on legacy/static slots.
    nextMoveAt: number?,
}

-- One ACTIVE summoned fighter (Tahap 2). Ephemeral field combatant — it is NOT a
-- bag item (summoning never consumes the bag), just a live model the combat loop
-- drives. `model` is the rigged clone; `nextCombatAt`/`nextSeekAt` are os.clock()
-- gates so we tick damage at combatTickSec and re-target at seekRetargetSec;
-- `despawnAt` is the auto-cleanup deadline; `engaged` is the wild it is currently
-- fighting (so we can clear that wild's InCombat flag if the fighter dies/despawns).
-- PROGRESSION: `brainrotId` links this fighter back to the SPECIFIC roster entry
-- that was summoned, so a win awards XP to the right individual. `level` is the
-- level SNAPSHOT taken at summon time (used to derive this fighter's HP/damage);
-- a mid-fight level-up does NOT re-derive the active fighter — the next summon
-- picks up the new level. Kept simple.
type FighterRecord = {
    personality: string,
    brainrotId: string,
    level: number,
    element: string, -- element SNAPSHOT from the summoned entry (element doc E3; drives elementMod)
    rarity: string, -- rarity SNAPSHOT from the summoned entry (rarity doc R3; drives statMult)
    evoStage: number, -- evolution stage SNAPSHOT (S2; drives evoStatMult + aura)
    model: Model,
    nextCombatAt: number,
    nextSeekAt: number,
    despawnAt: number,
    engaged: Model?,
    -- FORMATION JITTER (follow liveliness): a small random horizontal offset
    -- added to this fighter's formation slot, re-rolled every followJitterPeriodSec
    -- (os.clock() deadline in `jitterAt`) so idle following shuffles subtly.
    jitterOffset: Vector3,
    jitterAt: number,
}

type PlayerState = {
    -- NOTE (PROGRESSION): there is no persistent `inventory` list on the state
    -- anymore. The bag is DERIVED FRESH from PlayerDataService.getData(player).roster
    -- on every pushInventory (excluding deployed + actively-fighting ids), so it
    -- always reflects the authoritative roster (levels included).
    -- ── Showroom / idle-production (server-authoritative) ────────────────
    coins: number, -- live coin total (AUTO-COLLECT: production adds here directly)
    pending: number, -- UNUSED (kept = 0 for back-compat; auto-collect removed the bank step)
    slots: { [number]: DeployedSlot }, -- standIndex (1..showroomStandCount) -> slot
    rateBuckets: { [string]: { count: number, windowStart: number } },
    -- COINS-MADE (per-Brainrot flavor tally): os.clock() of the last flush at which
    -- we attributed idle production to the producing Brainrots. The delta since this
    -- stamp is split across the currently-deployed slots on each flush.
    lastCoinAttributeAt: number,
    -- ECONOMY SINK (Upgrade Kandang): live CACHE of the persisted
    -- base.buildings.b1.factoryLevel (seeded at hydrate, bumped on upgrade) so
    -- the per-second rate math never touches the profile. Authority stays in
    -- the persisted field.
    factoryLevel: number,
    -- ── Combat (Tahap 2) ─────────────────────────────────────────────────
    fighters: { FighterRecord }, -- active summoned fighters (capped at maxActiveFighters)
}

-- Tracks a placed creature so we can restore it after a catch.
type CreatureRecord = {
    name: string,
    personality: string,
    originalCFrame: CFrame,
}

-- ── State ──────────────────────────────────────────────────────────────────
local states: { [Player]: PlayerState } = {}

-- The creatures we manage, keyed by their ProximityPrompt instance so a trigger
-- resolves in O(1) and we only react to OUR prompts. Rebuilt on respawn.
local promptToRecord: { [ProximityPrompt]: CreatureRecord } = {}

-- COMBAT (Tahap 2): reverse map Model -> CreatureRecord for the wild creatures, so
-- the combat loop can faint+respawn a defeated wild by REUSING the existing catch
-- path (respawnCreature needs the record). Kept in sync with the catch prompt: an
-- entry exists exactly while the creature is present + catchable in the world.
local modelToRecord: { [Model]: CreatureRecord } = {}

-- Recall prompts on DEPLOYED display creatures, keyed by the prompt instance.
-- Maps to the owning player + their stand index so a recall trigger resolves in
-- O(1) and only the owner can undeploy. A prompt in NEITHER map is ignored.
type RecallTarget = {
    player: Player,
    index: number,
}
local deployedPromptToSlot: { [ProximityPrompt]: RecallTarget } = {}

-- "Place" prompts on EMPTY Showroom pedestals, keyed by the prompt instance ->
-- the stand index. Triggering one opens the place menu for THAT stand (the
-- player picks which podium). A stand is in EXACTLY one state: empty (Place
-- prompt here) or occupied (Recall prompt on its deployed creature) — never
-- both. `standToPlacePrompt` is the reverse index so we can remove a stand's
-- Place prompt in O(1) when it becomes occupied.
local placePromptToStand: { [ProximityPrompt]: number } = {}
local standToPlacePrompt: { [number]: ProximityPrompt } = {}

-- ── Personality resolution from the creature model name ───────────────────
-- The name suffix after `creaturePrefix` is the personality (UPPERCASE in the
-- world). Map it case-insensitively to the canonical key in personalityOrder.
local PREFIX = DemoConfig.demo3d.creaturePrefix
local personalityByUpper: { [string]: string } = {}
for _, key in DemoConfig.personalityOrder do
    personalityByUpper[string.upper(key)] = key
end

local function personalityFromName(modelName: string): string?
    if string.sub(modelName, 1, #PREFIX) ~= PREFIX then
        return nil
    end
    local suffix = string.sub(modelName, #PREFIX + 1)
    return personalityByUpper[string.upper(suffix)]
end

-- Fast set of valid personality keys for O(1) arg validation.
local isValidPersonality: { [string]: boolean } = {}
for _, key in DemoConfig.personalityOrder do
    isValidPersonality[key] = true
end

-- Production multiplier for a personality (steady baseline; the demo loop is
-- intentionally simple — no moment engine here). Falls back to 1.0.
local function prodMult(personality: string): number
    local def = DemoConfig.personalities[personality]
    return (def and def.prodMult) or 1
end

-- ── PROGRESSION (LEVEL / XP — battle-gdd v1.2 F2) ──────────────────────────
local PROGRESSION = DemoConfig.progression

-- Combat-stat multiplier for a given level (battle-gdd F2):
--   1 + statGrowthPerLevel * (level - 1)
-- `level` is clamped to [1, maxLevel] so an out-of-range value can never under-
-- or over-scale a stat. Lv1 = 1.0 (base), Lv2 = 1.08, … LvN = 1 + 0.08*(N-1).
local function levelScale(level: number): number
    local clamped = math.clamp(level, 1, PROGRESSION.maxLevel)
    return 1 + PROGRESSION.statGrowthPerLevel * (clamped - 1)
end

-- ECONOMY SINK (Upgrade Kandang): production multiplier from the persisted
-- kandang (factory) level: 1 + bonusPerLevel * level. Level 0 = 1.0 (base).
-- The level itself lives in profile.base.buildings.b1.factoryLevel (schema
-- field shipped with Persistence #1); the live state caches it for the rate
-- math (seeded at hydrate, bumped on upgrade).
local function kandangBonus(factoryLevel: number): number
    return 1 + DemoConfig.kandang.upgrade.bonusPerLevel * math.max(factoryLevel or 0, 0)
end

-- Current AUTO-COLLECT production rate (coins/sec) for a player: the sum over
-- every deployed slot of baseRatePerSlot * prodMult(personality), multiplied
-- by the kandang upgrade bonus. 0 if nothing is deployed. Shipped alongside
-- the live total so the client can interpolate.
local function currentRate(state: PlayerState): number
    local rate = 0
    for _, slot in state.slots do
        rate += DemoConfig.baseRatePerSlot * prodMult(slot.personality)
    end
    return rate * kandangBonus(state.factoryLevel)
end

-- OFFLINE RESOLVER (installed BEFORE any profile loads). Persistence owns the
-- clock + the clamped `elapsed`; we own the RATE. The rate mirrors currentRate
-- but is computed from the PERSISTED roster + deployment map (the live `state`
-- does not exist yet at load time): sum over each deployed roster id of
-- baseRatePerSlot * prodMult(entry.personality), times the persisted kandang
-- bonus. Returns integer coins. PURE + non-yielding (it runs inside the load
-- path).
PlayerDataService.setOfflineResolver(function(roster, base, elapsed)
    local b1 = base.buildings and base.buildings[BUILDING_ID]
    if not b1 then
        return 0
    end
    local rate = 0
    for _, brainrotId in b1.deployment do
        local entry = roster[brainrotId]
        if entry then
            rate += DemoConfig.baseRatePerSlot * prodMult(entry.personality)
        end
    end
    return math.floor(rate * kandangBonus(b1.factoryLevel) * elapsed)
end)

-- ── Helpers ──────────────────────────────────────────────────────────────

-- Light per-action rate limit. Returns true if the action is allowed.
local function allowAction(state: PlayerState, action: string, perSec: number): boolean
    local now = os.clock()
    local bucket = state.rateBuckets[action]
    if not bucket or now - bucket.windowStart >= 1 then
        state.rateBuckets[action] = { count = 1, windowStart = now }
        return true
    end
    if bucket.count >= perSec then
        return false
    end
    bucket.count += 1
    return true
end

-- Resolve the part the prompt attaches to: prefer the configured head part, then
-- the model PrimaryPart, then the first BasePart found. nil if no usable part.
local function findAnchorPart(model: Instance): BasePart?
    local head = model:FindFirstChild(DemoConfig.demo3d.headPartName)
    if head and head:IsA("BasePart") then
        return head
    end
    if model:IsA("Model") and model.PrimaryPart then
        return model.PrimaryPart
    end
    return model:FindFirstChildWhichIsA("BasePart", true)
end

-- Build + attach a "Hold F to Catch" ProximityPrompt to a creature's anchor part.
-- Registers it in promptToRecord. Returns false if the model has no usable part.
local function addCatchPrompt(model: Instance, record: CreatureRecord): boolean
    local anchor = findAnchorPart(model)
    if not anchor then
        return false
    end
    local prompt = Instance.new("ProximityPrompt")
    prompt.Name = "CatchPrompt"
    prompt.ActionText = DemoConfig.demo3d.catchActionText
    prompt.ObjectText = string.upper(record.personality)
    prompt.KeyboardKeyCode = Enum.KeyCode.F
    prompt.HoldDuration = DemoConfig.demo3d.catchHoldSec
    prompt.MaxActivationDistance = DemoConfig.demo3d.catchDistance
    prompt.RequiresLineOfSight = false
    prompt.Parent = anchor
    promptToRecord[prompt] = record
    if model:IsA("Model") then
        modelToRecord[model] = record -- combat faint path reuses this (Tahap 2)

        -- ELEMENT (sandbox wiring): every wild (re)spawn ROLLS a fresh element
        -- server-side (uniform 20%, element doc E3) onto an attribute the combat
        -- exchange reads for elementMod. The floating persona label gets the
        -- element emoji appended so the matchup is readable in-world; the
        -- authored base text is snapshot once into PersonaLabelBase so repeated
        -- respawns never stack emojis.
        local element = ElementConfig.rollElement()
        model:SetAttribute("Element", element)
        local personaLabel = model:FindFirstChild(DemoConfig.demo3d.personaLabelName, true)
        if personaLabel then
            local textLabel = personaLabel:FindFirstChildWhichIsA("TextLabel", true)
            if textLabel then
                local base = model:GetAttribute("PersonaLabelBase")
                if type(base) ~= "string" then
                    base = textLabel.Text
                    model:SetAttribute("PersonaLabelBase", base)
                end
                textLabel.Text = ("%s %s"):format(base :: string, elementEmoji(element))
            end
        end
    end
    return true
end

-- ── Inventory (DERIVED FRESH from the authoritative roster) ────────────────
-- PROGRESSION: rebuild the client bag list from PlayerDataService.getData().roster
-- on EVERY push, rather than from a drifting local list, so a level-up (which
-- mutates the roster entry) is reflected immediately. An entry is included ONLY
-- if it is NOT currently deployed (not a value in b1.deployment) AND NOT an active
-- fighter (its id is not linked to a live FighterRecord). Each client item carries
-- the full STAT-SHEET payload { id, personality, level, xp, xpToNext, hp, power,
-- wins, coinsMade } — all derived here from the authoritative entry; the client
-- builds the display label + sheet from it (it never computes game state).
local function pushInventory(player: Player)
    local state = states[player]
    if not state then
        warn("[Inv][server] pushInventory: NO STATE for " .. player.Name)
        return
    end
    local data = PlayerDataService.getData(player)
    if not data then
        return -- profile not loaded yet; a later push will carry the bag
    end

    -- BUSY ids: deployed (on a stand) OR currently an active fighter — excluded.
    local busy: { [string]: boolean } = {}
    local b1 = data.base.buildings[BUILDING_ID]
    if b1 then
        for _, deployedId in b1.deployment do
            if deployedId ~= nil then
                busy[deployedId] = true
            end
        end
    end
    for _, record in state.fighters do
        busy[record.brainrotId] = true
    end

    local combat = DemoConfig.combat
    local payload: { InventoryItem } = {}
    for id, entry in data.roster do
        if not busy[id] then
            -- Derive the stat-sheet fields from the authoritative entry. hp/power
            -- mirror the COMBAT derivation used at summon time (fighterMaxHP /
            -- fighterDamage), inlined here because those helpers are defined later
            -- in the file; the formulas are kept identical on purpose.
            local scale = levelScale(entry.level)
            local powerMult = if combat.personalityDamageScales then prodMult(entry.personality) else 1
            -- RARITY (R3): one moderate tier factor on both stats (C 1.0 .. L 2.0).
            local rarityMult = RarityConfig.statMultFor(entry.rarity)
            -- EVOLUTION (S2): ABSOLUTE stage multiplier (inlined like the rest —
            -- evoStatMult is defined later in the file; formula kept identical).
            local stage = entry.evoStage or 0
            local evo = DemoConfig.evolution
            local evoMult = if stage >= 1 and stage <= evo.maxStage then evo.statMult[stage] else 1
            local hp = math.round(combat.fighterBaseHP * scale * rarityMult * evoMult)
            local power = math.round(combat.fighterBaseDamagePerTick * scale * powerMult * rarityMult * evoMult)
            local wins = (entry.history and entry.history.rwon) or 0
            local coinsMade = math.floor((entry.history and entry.history.coins) or 0)
            -- EVOLVE button data (server-computed; nil cost/milestone = MAX).
            local evolveCost: number? = nil
            local evolveMilestone: number? = nil
            if stage < evo.maxStage then
                evolveMilestone = evo.levelMilestones[stage + 1]
                evolveCost = math.floor(evo.baseCost[stage + 1] * RarityConfig.evolveCostMultFor(entry.rarity))
            end
            table.insert(payload, {
                id = id,
                personality = entry.personality,
                element = entry.element,
                rarity = entry.rarity,
                evoStage = stage,
                evolveCost = evolveCost,
                evolveMilestone = evolveMilestone,
                level = entry.level,
                xp = entry.xp,
                xpToNext = PROGRESSION.xpCurveBase * entry.level,
                hp = hp,
                power = power,
                wins = wins,
                coinsMade = coinsMade,
            })
        end
    end
    print(("[Inv][server] push -> %s count=%d"):format(player.Name, #payload))
    DemoRemotes.InventoryUpdate:FireClient(player, payload)
end

-- ── Coins (server-authoritative, AUTO-COLLECT) ───────────────────────────
-- Push the RAW (unfloored) live coin total + the current production rate
-- (coins/sec). Sending the exact float (not math.floor) avoids a display
-- jitter: the client predicts baseCoins + rate*elapsed and snaps to this value
-- on each push. A floored value can land slightly BELOW the already-predicted
-- number, which would read as a visible decrease. The client floors only for
-- display. The server still OWNS the truth via state.coins.
local function pushCoins(player: Player)
    local state = states[player]
    if not state then
        return
    end
    DemoRemotes.CoinUpdate:FireClient(player, {
        coins = state.coins,
        rate = currentRate(state),
    })
end

-- Flush the live float coin total into the PERSISTED profile (floored to whole
-- coins — data.coins is integer). Routed through the audited update() transaction
-- (non-yielding mutator). When `clearOffline` is true we ALSO zero pendingOffline
-- so an already-applied welcome-back bonus is not re-granted on the next rejoin.
-- No-op if the player has no live state or no loaded profile (update returns
-- "not_loaded", which we ignore — the next flush retries).
local function flushCoins(player: Player, clearOffline: boolean)
    local state = states[player]
    if not state then
        return
    end
    -- COINS-MADE attribution (best-effort flavor): split the production accrued
    -- since the last flush across the currently-deployed slots, weighted by each
    -- slot's instantaneous rate (baseRatePerSlot * prodMult(personality)), and add
    -- it to that slot's roster entry's history.coins. Approximate by design — it
    -- attributes the WHOLE elapsed window at the CURRENT deployment (a slot placed
    -- mid-window gets the full window), which is fine for a lifetime flavor stat.
    -- Computed here so it commits inside the SAME atomic update() as data.coins.
    local now = os.clock()
    local elapsed = now - state.lastCoinAttributeAt
    state.lastCoinAttributeAt = now
    -- Snapshot (slot id -> coins delta) so the mutator stays pure + non-yielding.
    local deltas: { [string]: number } = {}
    if elapsed > 0 then
        for _, slot in state.slots do
            local slotRate = DemoConfig.baseRatePerSlot * prodMult(slot.personality)
            deltas[slot.id] = (deltas[slot.id] or 0) + slotRate * elapsed
        end
    end
    PlayerDataService.update(player, function(data)
        data.coins = math.floor(state.coins)
        for id, delta in deltas do
            local entry = data.roster[id]
            if entry then
                entry.history.coins += delta
            end
        end
        if clearOffline then
            data.pendingOffline = { coins = 0, from = 0, to = 0 }
        end
        return data.coins
    end)
end

-- ── Showroom ───────────────────────────────────────────────────────────────
local SHOWROOM = DemoConfig.showroom

-- Resolve a pedestal Part by 1-based index from the Showroom Model. nil if the
-- Showroom or the stand is missing (the demo degrades gracefully).
local function findStand(index: number): BasePart?
    local showroom = workspace:FindFirstChild(SHOWROOM.modelName)
    if not showroom then
        return nil
    end
    local stand = showroom:FindFirstChild(SHOWROOM.showroomStandPrefix .. tostring(index))
    if stand and stand:IsA("BasePart") then
        return stand
    end
    return nil
end

-- Set the pedestal's `Marker.SlotLabel` TextLabel text (server is text-only;
-- UITheme is client-side, so a neutral gold highlight is used here). Highlighted
-- = occupied (gold); un-highlighted = empty/neutral (soft gray).
local STAND_LABEL_COLOR = Color3.fromRGB(255, 206, 64)
local STAND_LABEL_NEUTRAL = Color3.fromRGB(170, 170, 170)

local function setStandLabel(stand: BasePart, text: string, highlight: boolean)
    local marker = stand:FindFirstChild("Marker")
    if not marker then
        return
    end
    local gui = marker:FindFirstChild("SlotLabel")
    if not gui then
        return
    end
    local label = gui:FindFirstChildWhichIsA("TextLabel", true)
    if not label then
        return
    end
    label.Text = text
    label.TextColor3 = if highlight then STAND_LABEL_COLOR else STAND_LABEL_NEUTRAL
end

-- ── Display templates (decoupled from the live wild creatures) ─────────────
-- BUG 1 FIX: deploy must NOT depend on a wild creature still being in the
-- Workspace — catching one does `model.Parent = nil` for `creatureRespawnSec`,
-- so cloning the LIVE creature failed mid-respawn ("missing template"). At
-- STARTUP we snapshot each `Brainrot_<P>` into ServerStorage.BrainrotTemplates,
-- stripped to a pure static prop and named by the CANONICAL personality (e.g.
-- "Hyper"). Deploy clones from this stable store, so catch/respawn never affects
-- deploy. ServerStorage is server-only (never replicated) — safe for templates.
local TEMPLATES_FOLDER_NAME = "BrainrotTemplates"
-- COMBAT (Tahap 2): a SEPARATE template store that KEEPS the Humanoid rig (unlike
-- BrainrotTemplates, which strips to a static prop). Fighters need the rig so the
-- server can walk them (Humanoid:MoveTo) and use the built-in health bar.
local FIGHTER_TEMPLATES_FOLDER_NAME = "FighterTemplates"
local PERSONA_LABEL_NAME = DemoConfig.demo3d.personaLabelName

-- Strip a clone down to a pure static prop: remove scripts/Humanoid/prompts and
-- the floating persona BillboardGui, then anchor every part (CanCollide false).
local function stripToProp(model: Model)
    for _, desc in model:GetDescendants() do
        local isBehavior = desc:IsA("BaseScript") or desc:IsA("Humanoid") or desc:IsA("ProximityPrompt")
        local isPersonaLabel = desc:IsA("BillboardGui") and desc.Name == PERSONA_LABEL_NAME
        if isBehavior or isPersonaLabel then
            desc:Destroy()
        end
    end
    for _, desc in model:GetDescendants() do
        if desc:IsA("BasePart") then
            desc.Anchored = true
            desc.CanCollide = false
        end
    end
end

-- Find (or create) the ServerStorage folder that holds the display templates.
local function getTemplatesFolder(): Folder
    local folder = ServerStorage:FindFirstChild(TEMPLATES_FOLDER_NAME)
    if folder and folder:IsA("Folder") then
        return folder
    end
    local created = Instance.new("Folder")
    created.Name = TEMPLATES_FOLDER_NAME
    created.Parent = ServerStorage
    return created
end

-- Build the stable templates at startup. Clones each `Brainrot_<P>` present in
-- the Workspace into ServerStorage, stripped + named by canonical personality.
-- Returns the number of templates built. Safe to call once on boot.
local function buildTemplates(): number
    local folder = getTemplatesFolder()
    local built = 0
    for _, creatureName in DemoConfig.demo3d.creatureNames do
        local personality = personalityFromName(creatureName)
        if not personality then
            continue
        end
        if folder:FindFirstChild(personality) then
            continue -- already snapshotted (idempotent)
        end
        local source = workspace:FindFirstChild(creatureName)
        if source and source:IsA("Model") then
            local template = source:Clone()
            template:SetAttribute("DemoCaught", nil) -- not a catchable wild creature
            stripToProp(template)
            template.Name = personality -- canonical key, e.g. "Hyper"
            template.Parent = folder
            built += 1
        else
            warn("[Deploy][server] no Workspace source to template for " .. creatureName)
        end
    end
    return built
end

-- ── Fighter templates (Tahap 2) ───────────────────────────────────────────
-- Find (or create) the ServerStorage folder that holds the RIGGED fighter
-- templates (Humanoid kept, unlike the static BrainrotTemplates).
local function getFighterTemplatesFolder(): Folder
    local folder = ServerStorage:FindFirstChild(FIGHTER_TEMPLATES_FOLDER_NAME)
    if folder and folder:IsA("Folder") then
        return folder
    end
    local created = Instance.new("Folder")
    created.Name = FIGHTER_TEMPLATES_FOLDER_NAME
    created.Parent = ServerStorage
    return created
end

-- Build the RIGGED fighter templates at startup. Mirrors buildTemplates() but
-- KEEPS the Humanoid rig: clones each `Brainrot_<P>` present + rigged in the
-- Workspace, removes ONLY the catch ProximityPrompt + the persona BillboardGui
-- (the fighter gets its own ⚔ label at summon time), clears DemoCaught, restores
-- full Health, and names by canonical personality. Returns the count built.
local function buildFighterTemplates(): number
    local folder = getFighterTemplatesFolder()
    local built = 0
    for _, creatureName in DemoConfig.demo3d.creatureNames do
        local personality = personalityFromName(creatureName)
        if not personality then
            continue
        end
        if folder:FindFirstChild(personality) then
            continue -- already snapshotted (idempotent)
        end
        local source = workspace:FindFirstChild(creatureName)
        if source and source:IsA("Model") then
            local template = source:Clone()
            template:SetAttribute("DemoCaught", nil)
            template:SetAttribute("InCombat", nil)
            -- Strip ONLY the catch prompts + the floating persona label; KEEP the
            -- Humanoid + parts so the fighter can walk and show its health bar.
            for _, desc in template:GetDescendants() do
                local isPrompt = desc:IsA("ProximityPrompt")
                local isPersonaLabel = desc:IsA("BillboardGui") and desc.Name == PERSONA_LABEL_NAME
                if isPrompt or isPersonaLabel then
                    desc:Destroy()
                end
            end
            -- Full Health on the template at the Lv1 BASE so every clone starts
            -- fresh; the actual per-summon HP is derived from the Brainrot's level
            -- (levelScale) in handleSummon, which overrides MaxHealth/Health there.
            local humanoid = template:FindFirstChildWhichIsA("Humanoid")
            if humanoid then
                humanoid.MaxHealth = DemoConfig.combat.fighterBaseHP
                humanoid.Health = DemoConfig.combat.fighterBaseHP
            end
            template.Name = personality -- canonical key, e.g. "Hyper"
            template.Parent = folder
            built += 1
        else
            warn("[Combat][server] no Workspace source to fighter-template for " .. creatureName)
        end
    end
    return built
end

-- KANDANG (paddock wander) tunables. Production mechanics are untouched —
-- this only changes the deployed clone's presentation (rigged + wandering).
local KANDANG = DemoConfig.kandang

-- EVOLUTION (sink S2): milestone + paid activation; ABSOLUTE stat multiplier
-- per stage (stage 0 = 1.0) and an element-colored aura on spawned clones.
local EVOLUTION = DemoConfig.evolution

-- Defensive stage->statMult lookup (nil/garbage/out-of-range -> 1.0).
local function evoStatMult(evoStage: any): number
    local s = if type(evoStage) == "number" then math.floor(evoStage) else 0
    if s >= 1 and s <= EVOLUTION.maxStage then
        return EVOLUTION.statMult[s]
    end
    return 1.0
end

-- EVOLUTION AURA (placeholder VFX per decision doc S2): a ParticleEmitter on
-- the model root, COLOR = the monster's element tint (ElementConfig.display),
-- density/size scaling with stage. Stage 0 = no-op. Survives until the model
-- is destroyed (recall/despawn); evolves apply to the NEXT spawn (a monster
-- must be in the BAG to evolve, so no live clone ever needs retrofitting).
local function addEvoAura(model: Model, element: any, evoStage: any)
    local s = if type(evoStage) == "number" then math.floor(evoStage) else 0
    if s < 1 then
        return
    end
    s = math.min(s, EVOLUTION.maxStage)
    local root = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
    if not root then
        return
    end
    local display = ElementConfig.display[element]
    local color = if display then Color3.fromHex(display.color) else Color3.fromRGB(255, 255, 255)
    local emitter = Instance.new("ParticleEmitter")
    emitter.Name = "EvoAura"
    emitter.Color = ColorSequence.new(color)
    emitter.Rate = EVOLUTION.aura.rates[s]
    emitter.Size = NumberSequence.new(EVOLUTION.aura.sizes[s])
    emitter.Lifetime = NumberRange.new(0.8, 1.4)
    emitter.Speed = NumberRange.new(0.5, 1.5)
    emitter.SpreadAngle = Vector2.new(180, 180)
    emitter.LightEmission = 0.6
    emitter.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.2),
        NumberSequenceKeypoint.new(1, 1),
    })
    emitter.Parent = root
end

-- GROUNDING: two-phase HipHeight fix shared with the pack prototype (the rigs
-- hover ~0.75 studs otherwise; scaled rigs proportionally more). See
-- Shared/Demo/RigGrounding.luau for the mechanism.
local RigGrounding = require(DemoFolder:WaitForChild("RigGrounding"))

-- KANDANG MENU forward reference: handleDeployToStand (defined before the
-- kandang section) refreshes an open menu after a deploy. Bound to pushKandang
-- once that function exists.
local pushKandangRef: ((Player) -> ())? = nil

-- The shared "Brainrot" collision group (no monster-vs-monster shoving) is
-- normally registered by the pack prototype; register defensively here too so
-- spawnDisplay's CollisionGroup assignment can never hit an unknown group.
pcall(function()
    game:GetService("PhysicsService"):RegisterCollisionGroup("Brainrot")
end)

-- Build a display clone and stand it on the slot plate.
--
-- KANDANG MODE (KANDANG.wanderEnabled, default): the clone comes from the
-- RIGGED FighterTemplates store so it can WALK — the kandang wander step
-- (stepKandangWander) then strolls it around the open paddock. Falls back to
-- the static store if the rigged template is missing (race at boot).
--
-- LEGACY MODE: static stripped prop standing frozen on the plate (pre-kandang
-- showroom look).
--
-- Returns the parented clone, or nil if no template is available.
-- `entry` (optional): the authoritative roster entry — supplies element +
-- evoStage for the evolution aura/scale (S2). nil = plain spawn.
local function spawnDisplay(personality: string, stand: BasePart, index: number, entry: Types.BrainrotEntry?): Model?
    local template: Instance? = nil
    local rigged = false
    if KANDANG.wanderEnabled then
        template = getFighterTemplatesFolder():FindFirstChild(personality)
        rigged = template ~= nil
    end
    if not template then
        template = getTemplatesFolder():FindFirstChild(personality)
    end
    if not template or not template:IsA("Model") then
        warn("[Deploy][server] missing template " .. personality .. " (no startup snapshot)")
        return nil
    end

    local clone = template:Clone()

    -- Place STANDING ON TOP of the slot plate, facing forward (toward -Z so it
    -- faces a player standing at the paddock gate).
    local _, size = clone:GetBoundingBox()
    local creatureHeight = size.Y
    local target = stand.Position
        + Vector3.new(0, stand.Size.Y / 2 + creatureHeight / 2 + SHOWROOM.standClearanceStuds, 0)
    clone:PivotTo(CFrame.lookAt(target, target + Vector3.new(0, 0, -1)))

    clone.Name = "Deployed_" .. tostring(index)

    if rigged then
        -- Rigged wanderer: calm walk speed, engine ground support (NOT
        -- PlatformStand — see the pack fall-through bugfix), full health so no
        -- health bar shows, shared "Brainrot" collision group so deployed
        -- monsters never shove each other (or the pack wilds).
        local humanoid = clone:FindFirstChildWhichIsA("Humanoid")
        if humanoid then
            humanoid.WalkSpeed = KANDANG.walkSpeed
            humanoid.PlatformStand = false
            humanoid.Health = humanoid.MaxHealth
            -- GROUNDING phase 1: blob-bottom near the floor, not hovering.
            local rootPart = clone.PrimaryPart
            if rootPart then
                humanoid.HipHeight = RigGrounding.initialHipHeight(clone, rootPart)
            end
        end
        for _, desc in clone:GetDescendants() do
            if desc:IsA("BasePart") then
                desc.CollisionGroup = "Brainrot"
            end
        end
        -- EVOLUTION (S2): stage-3 monsters are slightly bigger; every evolved
        -- stage carries the element-colored aura. Applied pre-parent so the
        -- grounding settle measures the FINAL size.
        if entry and (entry.evoStage or 0) >= EVOLUTION.maxStage then
            clone:ScaleTo(clone:GetScale() * EVOLUTION.stage3ScaleMult)
        end
        clone.Parent = workspace
        if entry then
            addEvoAura(clone, entry.element, entry.evoStage)
        end
        -- GROUNDING phase 2: measure + remove the residual pose gap once the
        -- physics settle.
        if humanoid then
            RigGrounding.settleToGround(clone, humanoid)
        end
        -- Server-authoritative motion (root is unanchored on the rigged rig).
        local root = clone.PrimaryPart
        if root then
            pcall(function()
                root:SetNetworkOwner(nil)
            end)
        end
    else
        clone.Parent = workspace
    end
    return clone
end

-- ── KANDANG WANDER (deployed monsters stroll the open paddock) ─────────────
-- Bounds = the Showroom model's `Floor` part, inset by KANDANG.marginStuds.
-- Resolved lazily + cached; nil (no wandering) if the floor is missing.
local kandangFloor: BasePart? = nil
local function getKandangFloor(): BasePart?
    if kandangFloor and kandangFloor.Parent ~= nil then
        return kandangFloor
    end
    local showroomModel = workspace:FindFirstChild(SHOWROOM.modelName)
    local floor = showroomModel and showroomModel:FindFirstChild("Floor")
    if floor and floor:IsA("BasePart") then
        kandangFloor = floor
        return floor
    end
    return nil
end

-- One wander step across EVERY player's deployed slots (mirrors the pack
-- prototype's stepWander, but bounded by the paddock floor instead of a slot
-- radius). Per-slot nextMoveAt gates give each monster its own pause rhythm.
local function stepKandangWander(now: number)
    if not KANDANG.wanderEnabled then
        return
    end
    local floor = getKandangFloor()
    if not floor then
        return
    end
    local margin = KANDANG.marginStuds
    local halfX = math.max(floor.Size.X / 2 - margin, 1)
    local halfZ = math.max(floor.Size.Z / 2 - margin, 1)
    local cx, cz = floor.Position.X, floor.Position.Z

    for _, state in states do
        for _, slot in state.slots do
            local model = slot.model
            if not model or model.Parent == nil then
                continue
            end
            if now < (slot.nextMoveAt or 0) then
                continue -- still pausing
            end
            local humanoid = model:FindFirstChildWhichIsA("Humanoid")
            if not humanoid or humanoid.Health <= 0 then
                continue -- legacy static clone (or dead rig): never wanders
            end
            -- Uniform target anywhere inside the inset paddock rectangle.
            local tx = cx + (math.random() * 2 - 1) * halfX
            local tz = cz + (math.random() * 2 - 1) * halfZ
            humanoid:MoveTo(Vector3.new(tx, floor.Position.Y, tz))
            local pause = KANDANG.wanderPauseMinSec
                + math.random() * (KANDANG.wanderPauseMaxSec - KANDANG.wanderPauseMinSec)
            slot.nextMoveAt = now + pause
        end
    end
end

-- Attach a "Recall" ProximityPrompt to a DEPLOYED display model so the owner can
-- undeploy it back into their inventory. Registered in deployedPromptToSlot so a
-- trigger resolves in O(1) and only the owner (matched in the handler) acts.
-- Returns false if the model has no usable anchor part.
local function addRecallPrompt(model: Model, player: Player, personality: string, index: number): boolean
    if KANDANG.menu.enabled then
        return true -- KANDANG MENU owns recall; per-monster prompts are retired
    end
    local anchor = findAnchorPart(model)
    if not anchor then
        return false
    end
    local prompt = Instance.new("ProximityPrompt")
    prompt.Name = "RecallPrompt"
    prompt.ActionText = DemoConfig.demo3d.recallActionText
    prompt.ObjectText = string.upper(personality)
    prompt.KeyboardKeyCode = Enum.KeyCode.E
    prompt.HoldDuration = DemoConfig.demo3d.recallHoldSec
    prompt.MaxActivationDistance = DemoConfig.demo3d.recallDistance
    prompt.RequiresLineOfSight = false
    prompt.Parent = anchor
    deployedPromptToSlot[prompt] = { player = player, index = index }
    return true
end

-- ── Place prompts (one per EMPTY stand) ────────────────────────────────────
-- Attach a "Place Brainrot" ProximityPrompt to an EMPTY pedestal. Triggering it
-- opens the place menu for this stand (the player then taps a caught creature).
-- Registered in placePromptToStand (+ the reverse index) so a trigger resolves
-- in O(1). Idempotent: if the stand already has a Place prompt, this no-ops.
local function addPlacePrompt(index: number)
    if KANDANG.menu.enabled then
        return -- KANDANG MENU owns placement; per-plate prompts are retired
    end
    if standToPlacePrompt[index] then
        return -- already present (idempotent)
    end
    local stand = findStand(index)
    if not stand then
        return -- pedestal missing in Workspace; degrade gracefully
    end
    local prompt = Instance.new("ProximityPrompt")
    prompt.Name = "PlacePrompt"
    prompt.ActionText = DemoConfig.demo3d.placeActionText
    prompt.ObjectText = DemoConfig.demo3d.placeObjectText
    prompt.KeyboardKeyCode = Enum.KeyCode.F
    prompt.HoldDuration = DemoConfig.demo3d.placeHoldSec
    prompt.MaxActivationDistance = DemoConfig.demo3d.placeDistance
    prompt.RequiresLineOfSight = false
    prompt.Parent = stand
    placePromptToStand[prompt] = index
    standToPlacePrompt[index] = prompt
end

-- Remove an empty stand's Place prompt (called when it becomes occupied). Safe
-- to call when no prompt exists.
local function removePlacePrompt(index: number)
    local prompt = standToPlacePrompt[index]
    if not prompt then
        return
    end
    placePromptToStand[prompt] = nil
    standToPlacePrompt[index] = nil
    prompt:Destroy()
end

-- ── Deploy to a SPECIFIC stand ─────────────────────────────────────────────
-- The player chose the podium (by triggering its Place prompt) and the creature
-- (by tapping a row in the place menu). Remove ONE caught creature of
-- `personality` from inventory and stand it on pedestal `standIndex`.
-- Server-authoritative + arg-validated + rate-limited.
local function handleDeployToStand(player: Player, standIndex: unknown, personality: unknown)
    local state = states[player]
    if not state then
        return
    end
    if not allowAction(state, "deploy", DemoConfig.rateLimits.deploy) then
        return
    end
    -- Validate the stand index: must be an integer in [1, showroomStandCount].
    if type(standIndex) ~= "number" or standIndex ~= math.floor(standIndex) then
        return -- attacker-controlled arg; reject
    end
    if standIndex < 1 or standIndex > SHOWROOM.showroomStandCount then
        return
    end
    -- Validate the personality.
    if type(personality) ~= "string" or not isValidPersonality[personality] then
        return -- attacker-controlled arg; reject
    end
    -- The stand must be FREE (no creature there already).
    if state.slots[standIndex] then
        return
    end

    -- DEPLOY stays personality-keyed (production is personality-only). Pick ANY
    -- non-deployed, non-fighting roster entry of that personality and use its id
    -- for the deployment map. Derived fresh from the authoritative roster.
    local data = PlayerDataService.getData(player)
    if not data then
        return -- profile not loaded yet
    end
    local busy: { [string]: boolean } = {}
    local b1Now = data.base.buildings[BUILDING_ID]
    if b1Now then
        for _, deployedId in b1Now.deployment do
            if deployedId ~= nil then
                busy[deployedId] = true
            end
        end
    end
    for _, record in state.fighters do
        busy[record.brainrotId] = true
    end
    local itemId: string? = nil
    for id, entry in data.roster do
        if entry.personality == personality and not busy[id] then
            itemId = id
            break
        end
    end
    if not itemId then
        return -- nothing of that personality free to deploy
    end

    local stand = findStand(standIndex)
    if not stand then
        return -- pedestal missing in Workspace
    end

    -- Pass the entry so the spawn carries the evolution aura/scale (S2).
    local model = spawnDisplay(personality, stand, standIndex, data.roster[itemId])
    if not model then
        return -- template missing; leave inventory untouched
    end

    -- PERSIST the deploy FIRST (server-authoritative). Record the roster id under
    -- this stand's slot key + bump the cached deployedCount, atomically. If the
    -- transaction fails (profile not loaded / no building), destroy the just-spawned
    -- model and bail so the live world never diverges from the persisted profile.
    local ok = PlayerDataService.update(player, function(profile)
        local b1 = profile.base.buildings[BUILDING_ID]
        if not b1 then
            error("no_building", 0)
        end
        b1.deployment[tostring(standIndex)] = itemId
        profile.base.deployedCount = (profile.base.deployedCount or 0) + 1
        return true
    end)
    if not ok then
        model:Destroy()
        return -- persistence rejected; no desync
    end

    -- The roster entry is now deployed (recorded in b1.deployment). The bag is
    -- DERIVED from the roster minus deployed/fighting ids, so pushInventory below
    -- drops it automatically — no local list to mutate.
    state.slots[standIndex] = { personality = personality, model = model, id = itemId }
    setStandLabel(stand, string.upper(personality), true)

    -- The stand is now occupied: remove its Place prompt, add the Recall prompt.
    removePlacePrompt(standIndex)
    addRecallPrompt(model, player, personality, standIndex)

    pushInventory(player)
    pushCoins(player)
    print("[Deploy] " .. player.Name .. " -> " .. personality .. " stand " .. standIndex)
    -- One-time confirmation that this slot is now producing (BUG 2 visibility).
    local rate = DemoConfig.baseRatePerSlot * prodMult(personality)
    print("[Prod] slot " .. standIndex .. " " .. personality .. " +" .. rate .. "/s")
    -- KANDANG MENU: refresh the snapshot so an open menu re-renders live.
    -- (pushKandangRef is bound after the kandang section is defined below.)
    if pushKandangRef then
        pushKandangRef(player)
    end
end

-- ── Collect (AUTO-COLLECT: deprecated no-op) ───────────────────────────────
-- Coins now rise automatically (see the production loop), so there is no manual
-- collect step. The Collect remote stays REGISTERED for back-compat but is no
-- longer wired to OnServerEvent; this no-op exists only to document the removal.
local function handleCollect(_player: Player)
    -- intentionally empty: production adds directly to state.coins.
end

-- ── Catch ────────────────────────────────────────────────────────────────
-- Remove the shared world creature, then respawn it at its original CFrame after
-- `creatureRespawnSec` with a fresh prompt so the demo is repeatable. The catch
-- is conceptually per-player but the creature is a shared object — for this
-- single-player demo, remove + respawn the shared model (kept intentionally simple).
local function respawnCreature(record: CreatureRecord, model: Model)
    task.delay(DemoConfig.demo3d.creatureRespawnSec, function()
        if model:GetAttribute("DemoCaught") ~= true then
            return -- already restored some other way; nothing to do
        end
        model:SetAttribute("DemoCaught", false)
        model:SetAttribute("InCombat", nil) -- clear any stale combat flag (Tahap 2)
        -- Restore full Health so a creature defeated in combat (Tahap 2) respawns
        -- fresh, not at 0 HP. Harmless for the catch path (caught at full Health).
        local humanoid = model:FindFirstChildWhichIsA("Humanoid")
        if humanoid then
            humanoid.Health = humanoid.MaxHealth
        end
        model:PivotTo(record.originalCFrame)
        model.Parent = workspace
        addCatchPrompt(model, record)
    end)
end

local function handleCatch(prompt: ProximityPrompt, player: Player)
    local record = promptToRecord[prompt]
    if not record then
        return -- not one of our prompts; ignore
    end
    local state = states[player]
    if not state then
        return
    end
    if not allowAction(state, "catch", DemoConfig.rateLimits.catch) then
        return
    end

    local model = prompt:FindFirstAncestorOfClass("Model")
    if not model then
        return
    end

    -- Guard against double-trigger while the catch is resolving.
    if model:GetAttribute("DemoCaught") == true then
        return
    end

    -- PERSIST FIRST (reordered for safety): mint a roster entry + commit it to the
    -- audited profile BEFORE we mutate the world. If the add is rejected
    -- (roster_full / not_loaded) we ABORT the catch — we do NOT mark the model
    -- caught, destroy its prompt, or remove it from the world, so the creature
    -- stays catchable and the world matches the (unchanged) persisted profile.
    local entry = Schema.newBrainrot({
        species = speciesByPersonality[record.personality] or 1,
        personality = record.personality :: any,
        source = "manual",
        hotspotId = "demo",
    })
    local ok = PlayerDataService.addBrainrot(player, entry)
    if not ok then
        warn("[Catch] " .. player.Name .. " add rejected for " .. record.personality)
        return
    end

    model:SetAttribute("DemoCaught", true)

    -- De-register + remove the prompt before pulling the creature from the world.
    promptToRecord[prompt] = nil
    modelToRecord[model] = nil -- no longer present/catchable (combat lookup)
    prompt:Destroy()

    -- The roster entry was just minted + persisted via addBrainrot; the bag is
    -- DERIVED fresh from the roster, so a re-push now includes the new catch.
    pushInventory(player)

    -- Remove the shared creature from the world, then schedule its respawn.
    model.Parent = nil
    respawnCreature(record, model)

    print("[Catch] " .. player.Name .. " caught " .. record.personality)
end

-- ── PACK CATCH MINT (server-side bridge for the pack prototype) ─────────────
-- The BrainrotPack prototype owns the pack wilds' WORLD lifecycle (spawn /
-- wander / respawn) but the ROSTER is owned here. This BindableFunction lets a
-- pack catch mint a REAL roster entry through the exact same audited path as
-- the original catch (Schema.newBrainrot + addBrainrot + bag re-push), without
-- the two scripts sharing any internals. Returns true IFF the entry was
-- committed — the pack only despawns the wild on true (roster_full aborts the
-- catch, mirroring handleCatch's persist-first ordering).
--
-- ELEMENT: pack wilds DISPLAY their rolled element on the overhead label, so
-- the minted entry INHERITS that element (what you see is what you catch).
-- An invalid/missing element falls back to a fresh server roll inside
-- Schema.newBrainrot — never trusted blindly.
local packCatchMint = Instance.new("BindableFunction")
packCatchMint.Name = "PackCatchMint"
packCatchMint.Parent = ServerStorage
packCatchMint.OnInvoke = function(player: Player, personality: unknown, element: unknown): boolean
    if typeof(player) ~= "Instance" or not player:IsA("Player") then
        return false
    end
    local state = states[player]
    if not state then
        return false
    end
    -- Same rate limit bucket as the original catch path.
    if not allowAction(state, "catch", DemoConfig.rateLimits.catch) then
        return false
    end
    if type(personality) ~= "string" or not isValidPersonality[personality] then
        return false
    end

    -- ECONOMY SINK (capture, economy-gdd §8.2): the first
    -- freeCapturesOnboarding catches are free (persisted counter, seeded at
    -- profile creation); after that every catch debits captureCostCoins from
    -- the live float. AFFORDABILITY FIRST: an unaffordable catch aborts with
    -- player feedback BEFORE any mutation, so the wild stays catchable.
    local data = PlayerDataService.getData(player)
    if not data then
        return false
    end
    local cost = CaptureConfig.captureCostCoins
    local usedFree = (data.freeCapturesRemaining or 0) > 0
    if not usedFree and state.coins < cost then
        DemoRemotes.Moment:FireClient(player, {
            kind = "info",
            text = ("🪙 Koin tidak cukup! Butuh %d untuk menangkap."):format(cost),
        })
        return false
    end

    local entry = Schema.newBrainrot({
        species = speciesByPersonality[personality] or 1,
        personality = personality :: any,
        -- Inherit the wild's displayed element; Schema re-rolls if invalid.
        element = if type(element) == "string" then element :: any else nil,
        source = "manual",
        hotspotId = "pack",
    })
    local ok = PlayerDataService.addBrainrot(player, entry)
    if not ok then
        warn("[Catch] " .. player.Name .. " pack add rejected for " .. personality)
        return false
    end

    -- Settle the price AFTER the add committed (a rejected add must not
    -- consume a free capture or coins).
    if usedFree then
        PlayerDataService.update(player, function(d)
            d.freeCapturesRemaining = math.max(0, (d.freeCapturesRemaining or 0) - 1)
            return true
        end)
    else
        state.coins = math.max(0, state.coins - cost)
        flushCoins(player, false)
    end
    pushCoins(player)
    pushInventory(player)
    print(
        ("[Catch] %s caught pack %s (%s) — %s"):format(
            player.Name,
            personality,
            entry.element,
            if usedFree then "FREE (onboarding)" else ("-" .. cost .. " coins")
        )
    )
    return true
end

-- ════════════════════════════════════════════════════════════════════════════
-- COMBAT (Tahap 2): SUMMON a fighter that auto-battles the nearest wild Brainrot
-- ════════════════════════════════════════════════════════════════════════════
local COMBAT = DemoConfig.combat

-- PERSONALITY-only damage scale (no level): multiply `base` by the personality's
-- prodMult (Hyper ~1.3x, Lazy ~0.5x) when personalityDamageScales is on. Used for
-- the WILD's damage back (wilds are treated as level 1 for now).
local function scaledDamage(base: number, personality: string): number
    if COMBAT.personalityDamageScales then
        return base * prodMult(personality)
    end
    return base
end

-- PROGRESSION: a FIGHTER's per-tick damage at a given level + personality
-- (battle-gdd F2): fighterBaseDamagePerTick * levelScale(level) * personalityScale
-- * rarityStatMult (rarity doc R3, moderate C 1.0 .. L 2.0; defensive 1.0 on
-- nil/invalid). LEVEL boosts damage; personality keeps its flavor multiplier.
local function fighterDamage(level: number, personality: string, rarity: any, evoStage: any): number
    local personalityMult = if COMBAT.personalityDamageScales then prodMult(personality) else 1
    return COMBAT.fighterBaseDamagePerTick
        * levelScale(level)
        * personalityMult
        * RarityConfig.statMultFor(rarity)
        * evoStatMult(evoStage)
end

-- PROGRESSION: a FIGHTER's derived Max HP at a given level (battle-gdd F2):
-- round(fighterBaseHP * levelScale(level) * rarityStatMult). LEVEL + rarity
-- boost HP; rounded to a whole HP so the built-in health bar reads cleanly.
local function fighterMaxHP(level: number, rarity: any, evoStage: any): number
    return math.round(
        COMBAT.fighterBaseHP * levelScale(level) * RarityConfig.statMultFor(rarity) * evoStatMult(evoStage)
    )
end

-- FOLLOW FORMATION: a fighter is "living" (counts toward a formation slot) iff
-- its model is still present AND its Humanoid is alive. Used to assign each active
-- fighter a DISTINCT slot index (order) among its owner's currently-living squad.
local function isLivingFighter(record: FighterRecord): boolean
    local model = record.model
    if not model or model.Parent == nil then
        return false
    end
    local humanoid = model:FindFirstChildWhichIsA("Humanoid")
    return humanoid ~= nil and humanoid.Health > 0
end

-- FOLLOW FORMATION: compute this fighter's (orderIndex, count) among the owner's
-- currently-living fighters — orderIndex is 0-based (its position counting only
-- living ones), count is the number of living fighters. Recomputed each follow
-- tick; a reshuffle when one is removed is acceptable (slots simply re-pack).
local function formationOrder(state: PlayerState, record: FighterRecord): (number, number)
    local orderIndex = 0
    local count = 0
    local seenSelf = false
    for _, other in state.fighters do
        if isLivingFighter(other) then
            if other == record then
                orderIndex = count
                seenSelf = true
            end
            count += 1
        end
    end
    if not seenSelf then
        -- This fighter is not (yet) counted living (e.g. mid-spawn): treat as the
        -- last slot of a squad that includes it so it still fans out distinctly.
        orderIndex = count
        count += 1
    end
    return orderIndex, count
end

-- FOLLOW FORMATION: the BEHIND-the-player direction for slot `orderIndex` of `count`
-- fighters, fanned evenly across COMBAT.followSpreadDegrees and centered behind the
-- player. `behind` is the flattened (XZ) behind-vector (-LookVector); if it is zero
-- (facing unavailable) a fixed world fallback is used so slots still spread. Returns
-- a unit direction on the XZ plane.
local FORMATION_FALLBACK_DIR = Vector3.new(0, 0, 1) -- world +Z when facing is unknown
local function formationDir(behind: Vector3, orderIndex: number, count: number): Vector3
    local baseDir = if behind.Magnitude > 1e-4 then behind.Unit else FORMATION_FALLBACK_DIR
    -- angle_i = (i - (n-1)/2) * (spread / max(1, n-1)); n==1 -> 0 (straight behind).
    local step = COMBAT.followSpreadDegrees / math.max(1, count - 1)
    local angleDeg = (orderIndex - (count - 1) / 2) * step
    local angleRad = math.rad(angleDeg)
    -- Rotate baseDir around the Y axis by angleRad (XZ-plane rotation).
    local cos = math.cos(angleRad)
    local sin = math.sin(angleRad)
    local x = baseDir.X * cos - baseDir.Z * sin
    local z = baseDir.X * sin + baseDir.Z * cos
    return Vector3.new(x, 0, z)
end

-- COMBAT RING: the per-fighter slot position on a ring AROUND a target wild, so
-- 2+ fighters attacking the SAME wild spread out instead of stacking on its exact
-- position. The owner's living fighters are distributed evenly across a FULL circle
-- using their formation order (i of n): angle_i = (2*pi / max(1, n)) * i. The slot
-- is flattened to the XZ plane around the target (target X/Z + ringDir * radius) and
-- keeps the FIGHTER's own Y so MoveTo behaves normally. Because the ring radius is
-- < attackRangeStuds, a fighter at its slot stays within attack range and keeps
-- dealing damage. `targetPos` is the target wild's root position; `fighterY` is the
-- fighter root's current Y.
local function combatRingSlot(state: PlayerState, record: FighterRecord, targetPos: Vector3, fighterY: number): Vector3
    local orderIndex, count = formationOrder(state, record)
    local angle = (2 * math.pi / math.max(1, count)) * orderIndex
    local ringDir = Vector3.new(math.cos(angle), 0, math.sin(angle))
    return Vector3.new(targetPos.X, fighterY, targetPos.Z) + ringDir * COMBAT.combatRingRadiusStuds
end

-- Resolve a fighter's Humanoid + root, or nil if the model is gone/unrigged.
local function fighterParts(model: Model): (Humanoid?, BasePart?)
    if not model or model.Parent == nil then
        return nil, nil
    end
    local humanoid = model:FindFirstChildWhichIsA("Humanoid")
    local root = model.PrimaryPart or model:FindFirstChild(DemoConfig.demo3d.headPartName)
    if root and not root:IsA("BasePart") then
        root = nil
    end
    return humanoid, root :: BasePart?
end

-- PET LEASH: find the NEAREST living, present, un-caught wild creature to
-- `centerPos` that is WITHIN `maxRange` studs of it. The search is PLAYER-CENTERED
-- + RANGE-LIMITED: callers pass the OWNER PLAYER's character root position as
-- `centerPos` and `COMBAT.detectionRangeStuds` as `maxRange`, so a summoned fighter
-- only ever considers wilds inside the player's radius — anything beyond it is
-- IGNORED (returns nil so the fighter falls back to following the player). Returns
-- the model + its root, or nil if no wild qualifies inside the radius. Distance is
-- measured from `centerPos` (the player), NOT the fighter, so a wild that wanders
-- out of the player's radius (or a player who walks away) naturally drops the target.
local function nearestWild(centerPos: Vector3, maxRange: number): (Model?, BasePart?)
    local best: Model? = nil
    local bestRoot: BasePart? = nil
    local bestDist = math.huge

    -- Shared candidate check (original named wilds + tagged pack wilds).
    local function consider(model: Model)
        if model:GetAttribute("DemoCaught") == true then
            return
        end
        local humanoid = model:FindFirstChildWhichIsA("Humanoid")
        local root = model.PrimaryPart
        if humanoid and humanoid.Health > 0 and root then
            local dist = (root.Position - centerPos).Magnitude
            -- RANGE GATE: reject anything beyond the player's detection radius.
            if dist <= maxRange and dist < bestDist then
                bestDist = dist
                best = model
                bestRoot = root
            end
        end
    end

    for _, creatureName in DemoConfig.demo3d.creatureNames do
        local model = workspace:FindFirstChild(creatureName)
        if model and model:IsA("Model") then
            consider(model)
        end
    end
    -- PACK WILDS (incl. 👑 bosses): the BrainrotPack prototype tags every clone
    -- with "PackWild" (CollectionService) — the single, decoupled discovery
    -- point. Pack wilds carry Personality/Element/DamageMult/etc. attributes
    -- the combat exchange + reward paths read.
    for _, inst in CollectionService:GetTagged("PackWild") do
        if inst:IsA("Model") and inst.Parent == workspace then
            consider(inst)
        end
    end
    return best, bestRoot
end

-- A wild was defeated in combat: award the owner winCoins (routed through the live
-- coin float + the existing persist path), clear its InCombat flag, then faint +
-- respawn it by REUSING the catch/respawn path (set DemoCaught, unparent its
-- prompt + model, schedule respawnCreature at its original CFrame with full HP).
local function defeatWild(player: Player, state: PlayerState, wild: Model)
    -- Award + persist coins (same path as production: live float -> flushCoins).
    -- BOSS REWARD: a pack 👑 boss stamps WinCoinsMult (e.g. 10x) on its model;
    -- regular wilds carry no attribute and default to 1.
    local coinsMult = wild:GetAttribute("WinCoinsMult")
    if type(coinsMult) ~= "number" or coinsMult <= 0 then
        coinsMult = 1
    end
    state.coins += COMBAT.winCoins * coinsMult
    pushCoins(player)
    flushCoins(player, false)

    wild:SetAttribute("InCombat", nil)

    -- PACK WILD (incl. boss): the BrainrotPack prototype owns its lifecycle —
    -- its respawn sweep sees the 0-HP corpse, arms the per-slot timer (5s
    -- minion / 30s boss), tears the corpse down, and respawns it. Do NOT run
    -- the original-wild respawn path on it.
    if CollectionService:HasTag(wild, "PackWild") then
        return
    end

    local record = modelToRecord[wild]
    if not record then
        -- No record (e.g. mid-respawn race): just remove gracefully so it cannot
        -- be fought at 0 HP. It will be re-set up by a later respawn if applicable.
        return
    end

    -- Tear down the catch prompt + de-register before unparenting (mirrors catch).
    for _, desc in wild:GetDescendants() do
        if desc:IsA("ProximityPrompt") and promptToRecord[desc] then
            promptToRecord[desc] = nil
            desc:Destroy()
        end
    end
    modelToRecord[wild] = nil
    wild:SetAttribute("DemoCaught", true)
    wild.Parent = nil
    respawnCreature(record, wild)
end

-- PROGRESSION: award XP to the SPECIFIC Brainrot (`brainrotId`) that won, atomically
-- through the audited update() transaction (the mutator is NON-yielding). XP comes
-- ONLY from a win; it may carry over multiple levels in one award. Returns
-- (leveledTo, currentLevel): `leveledTo` is the new level IFF a level-up happened
-- (else nil); `currentLevel` is the entry's level after the award (for display).
-- Persistence handles saving (update marks dirty -> autosave/leave-save).
local function awardWinXp(player: Player, brainrotId: string, xpMult: number?): (number?, number?)
    local leveledTo: number? = nil
    local currentLevel: number? = nil
    -- BOSS REWARD: a pack 👑 boss passes its XpMult (e.g. 4x); nil/invalid = 1.
    local mult = if type(xpMult) == "number" and xpMult > 0 then xpMult else 1
    PlayerDataService.update(player, function(data)
        local e = data.roster[brainrotId]
        if not e then
            return
        end
        -- BATTLES-WON tally (repurposed history.rwon for the demo): bump it in the
        -- SAME atomic mutator as the XP grant so the win count + XP move together.
        e.history.rwon += 1
        e.xp += PROGRESSION.xpPerWin * mult
        while e.level < PROGRESSION.maxLevel and e.xp >= PROGRESSION.xpCurveBase * e.level do
            e.xp -= PROGRESSION.xpCurveBase * e.level
            e.level += 1
            leveledTo = e.level
        end
        currentLevel = e.level
    end)
    return leveledTo, currentLevel
end

-- PROGRESSION: build + register a fighter for `player` from a SPECIFIC roster
-- `brainrotId` (so XP attaches to the exact individual). Validated + rate-limited:
-- the id must be a string that is in the player's roster, NOT currently deployed
-- (not a value in b1.deployment), and NOT already an active fighter; the player
-- must also be under the maxActiveFighters cap. The roster entry is NOT consumed
-- (summoning is ephemeral). HP + per-tick damage are DERIVED from the entry's
-- `level` (levelScale, battle-gdd F2), and the level is snapshot on the record.
-- Spawns the rigged clone summonOffsetStuds in front of the player, server-owned,
-- with a ⚔ label. No-op (graceful) on a bad arg / no character / missing template.
local function handleSummon(player: Player, brainrotId: unknown)
    local state = states[player]
    if not state then
        return
    end
    if not allowAction(state, "summon", DemoConfig.rateLimits.summon) then
        return
    end
    -- Validate the id (attacker-controlled arg): must be a string.
    if type(brainrotId) ~= "string" then
        return
    end
    -- Cap: bound active fighters per player.
    if #state.fighters >= COMBAT.maxActiveFighters then
        return
    end
    -- OWNERSHIP: the id must be in the player's authoritative roster.
    local data = PlayerDataService.getData(player)
    if not data then
        return
    end
    local entry = data.roster[brainrotId]
    if not entry then
        return -- not owned; reject
    end
    -- NOT DEPLOYED: the id must not be a value in this building's deployment map.
    local b1 = data.base.buildings[BUILDING_ID]
    if b1 then
        for _, deployedId in b1.deployment do
            if deployedId == brainrotId then
                return -- currently on a stand; reject
            end
        end
    end
    -- NOT ALREADY FIGHTING: the id must not be linked to a live fighter.
    for _, record in state.fighters do
        if record.brainrotId == brainrotId then
            return -- already summoned; reject
        end
    end

    local personality = entry.personality
    local level = entry.level
    -- ELEMENT: snapshot from the authoritative entry (rolled at capture mint,
    -- permanent per element doc E4) — drives this fighter's elementMod.
    local element = entry.element
    -- RARITY: snapshot likewise (rarity doc R3) — drives this fighter's statMult.
    local rarity = entry.rarity
    -- EVOLUTION: stage snapshot (S2) — drives evoStatMult + the spawn aura.
    local evoStage = entry.evoStage or 0

    -- Place in front of the player's character. Bail gracefully if no character.
    local character = player.Character
    local charRoot = character and character:FindFirstChild("HumanoidRootPart")
    if not charRoot or not charRoot:IsA("BasePart") then
        return
    end

    local folder = getFighterTemplatesFolder()
    local template = folder:FindFirstChild(personality)
    if not template or not template:IsA("Model") then
        warn("[Combat][server] missing fighter template " .. personality)
        return
    end

    local fighter = template:Clone()
    fighter.Name = "Fighter_" .. string.upper(personality)
    fighter:SetAttribute("DemoCaught", nil)
    fighter:SetAttribute("InCombat", nil)
    fighter:SetAttribute("Element", element) -- visibility/debug; combat reads the record snapshot

    local humanoid = fighter:FindFirstChildWhichIsA("Humanoid")
    local root = fighter.PrimaryPart
    if not humanoid or not root then
        fighter:Destroy()
        return
    end
    -- PROGRESSION: derive Max HP from level + rarity + evolution (F2/R3/S2).
    local maxHP = fighterMaxHP(level, rarity, evoStage)
    humanoid.WalkSpeed = COMBAT.fighterWalkSpeed
    humanoid.MaxHealth = maxHP
    humanoid.Health = maxHP
    -- GROUNDING phase 1: same rig family as the pack wilds — derive HipHeight
    -- so the fighter walks ON the ground instead of hovering ~0.75 studs.
    -- (Phase 2 settleToGround is scheduled after parenting below.)
    humanoid.HipHeight = RigGrounding.initialHipHeight(fighter, root)

    -- Spawn summonOffsetStuds in FRONT of the player (along their look vector).
    local spawnCFrame = charRoot.CFrame * CFrame.new(0, 0, -COMBAT.summonOffsetStuds)
    fighter:PivotTo(CFrame.new(spawnCFrame.Position))

    -- A small ⚔ label so it reads as the player's fighter (with its level).
    local billboard = Instance.new("BillboardGui")
    billboard.Name = "FighterLabel"
    billboard.Size = UDim2.fromOffset(120, 28)
    billboard.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
    billboard.AlwaysOnTop = true
    local labelText = Instance.new("TextLabel")
    labelText.BackgroundTransparency = 1
    labelText.Size = UDim2.fromScale(1, 1)
    labelText.Font = Enum.Font.GothamBold
    labelText.TextScaled = true
    labelText.TextColor3 = Color3.fromRGB(255, 206, 64)
    labelText.Text = ("⚔ %s Lv%d %s"):format(string.upper(personality), level, elementEmoji(element))
    labelText.Parent = billboard
    local labelAnchor = findAnchorPart(fighter)
    billboard.Parent = labelAnchor or root

    fighter.Parent = workspace
    -- EVOLUTION: stage 3 fights slightly BIGGER + every evolved stage gets the
    -- element-colored aura (S2 visual payoff).
    if evoStage >= EVOLUTION.maxStage then
        fighter:ScaleTo(fighter:GetScale() * EVOLUTION.stage3ScaleMult)
    end
    addEvoAura(fighter, element, evoStage)
    -- GROUNDING phase 2: measure + remove the residual pose gap once settled.
    RigGrounding.settleToGround(fighter, humanoid)

    -- Server-authoritative motion: claim network ownership (root is unanchored).
    pcall(function()
        root:SetNetworkOwner(nil)
    end)

    local now = os.clock()
    local record: FighterRecord = {
        personality = personality,
        brainrotId = brainrotId,
        level = level,
        element = element,
        rarity = rarity,
        evoStage = evoStage,
        model = fighter,
        nextCombatAt = 0,
        nextSeekAt = 0,
        despawnAt = now + COMBAT.fighterLifetimeSec,
        engaged = nil,
        -- Start with no jitter; re-rolled on the first follow tick (jitterAt = 0
        -- forces an immediate roll) and every followJitterPeriodSec thereafter.
        jitterOffset = Vector3.zero,
        jitterAt = 0,
    }
    table.insert(state.fighters, record)
    -- The summoned Brainrot is now BUSY (an active fighter): re-derive the bag so
    -- it drops out of the inventory list immediately.
    pushInventory(player)
    print(("[Combat] %s summoned %s Lv%d (%d active)"):format(player.Name, personality, level, #state.fighters))
end

-- Remove a fighter record at index `i` from `state.fighters`: destroy its model,
-- clear any wild it had engaged (so wander resumes), and swap-remove the record.
local function removeFighter(state: PlayerState, i: number)
    local record = state.fighters[i]
    if not record then
        return
    end
    local engaged = record.engaged
    if engaged and engaged.Parent ~= nil then
        engaged:SetAttribute("InCombat", nil)
    end
    if record.model and record.model.Parent ~= nil then
        record.model:Destroy()
    end
    -- Order-independent swap-remove (combat order does not matter).
    local n = #state.fighters
    state.fighters[i] = state.fighters[n]
    state.fighters[n] = nil
end

-- One combat step for a single fighter. Returns true if the fighter should be
-- REMOVED (KO'd, despawned, or its model vanished). Drives seek -> engage ->
-- exchange-damage, and the win/respawn on a wild defeat.
local function stepFighter(player: Player, state: PlayerState, record: FighterRecord, now: number): boolean
    -- Lifetime auto-despawn (keeps the field clean).
    if now >= record.despawnAt then
        DemoRemotes.BattleEvent:FireClient(player, { kind = "ko", personality = record.personality })
        return true
    end

    local model = record.model
    local humanoid, root = fighterParts(model)
    if not humanoid or not root then
        return true -- model gone/unrigged: remove the record
    end

    -- Fighter KO: despawn (gentle, non-destructive — the bag was never consumed).
    if humanoid.Health <= 0 then
        DemoRemotes.BattleEvent:FireClient(player, { kind = "ko", personality = record.personality })
        return true
    end

    -- PET BEHAVIOR: resolve the OWNER PLAYER's character root. If the owner has no
    -- character (respawning / just left), the fighter IDLES in place this tick — no
    -- movement, no target, no engagement change (guard against a nil owner character).
    local character = player.Character
    local playerRootInst = character and character:FindFirstChild("HumanoidRootPart")
    local playerRoot = if playerRootInst and playerRootInst:IsA("BasePart") then playerRootInst else nil
    if not playerRoot then
        return false -- owner mid-respawn / gone: idle this tick
    end
    local playerPos = playerRoot.Position

    -- Helper: drop any current engagement (clear the engaged wild's InCombat so it
    -- resumes wandering — never leave a wild stuck frozen) and FOLLOW the player in
    -- FORMATION. Each fighter gets a DISTINCT slot fanned out BEHIND the player so
    -- 2+ fighters do not stack on one follow point, plus a small re-rolling jitter
    -- so idle following looks alive. If already within followStopStuds of its OWN
    -- slot, do nothing (per-slot deadzone — avoids jitter/twitching).
    local function disengageAndFollow()
        if record.engaged and record.engaged.Parent ~= nil then
            record.engaged:SetAttribute("InCombat", nil)
        end
        record.engaged = nil

        -- This fighter's slot index among the owner's currently-living squad.
        local orderIndex, count = formationOrder(state, record)

        -- BEHIND the player = -LookVector flattened to the XZ plane. Fall back to a
        -- fixed world direction (handled in formationDir) if facing is unavailable.
        local look = playerRoot.CFrame.LookVector
        local behind = Vector3.new(-look.X, 0, -look.Z)
        local dir = formationDir(behind, orderIndex, count)

        -- Slot position = player + fanned-out direction * followDistanceStuds.
        local slotPos = playerPos + dir * COMBAT.followDistanceStuds

        -- LIVELINESS: re-roll a small horizontal jitter offset every period so the
        -- fighter shuffles subtly around its slot instead of standing frozen.
        if now >= record.jitterAt then
            record.jitterAt = now + COMBAT.followJitterPeriodSec
            local jAngle = math.random() * 2 * math.pi
            local jMag = math.random() * COMBAT.followJitterStuds
            record.jitterOffset = Vector3.new(math.cos(jAngle) * jMag, 0, math.sin(jAngle) * jMag)
        end
        slotPos += record.jitterOffset

        -- PER-SLOT DEADZONE: only move if not already at THIS slot (not the player).
        if (slotPos - root.Position).Magnitude <= COMBAT.followStopStuds then
            return -- already at its formation slot: idle (no new MoveTo)
        end
        humanoid:MoveTo(slotPos)
    end

    -- SEEK: (re)find the nearest wild on the seek cadence — PLAYER-CENTERED +
    -- RANGE-LIMITED (only wilds within detectionRangeStuds of the player qualify).
    if now >= record.nextSeekAt then
        record.nextSeekAt = now + COMBAT.seekRetargetSec
        local wild, wildRoot = nearestWild(playerPos, COMBAT.detectionRangeStuds)
        if wild and wildRoot then
            local dist = (wildRoot.Position - root.Position).Magnitude
            if dist > COMBAT.attackRangeStuds then
                -- Valid target but out of attack range: clear a stale engagement +
                -- chase the target. Move toward this fighter's DISTINCT ring slot
                -- AROUND the wild (not its exact center) so 2+ fighters approaching
                -- the same wild fan out instead of converging on one point.
                if record.engaged and record.engaged ~= wild and record.engaged.Parent ~= nil then
                    record.engaged:SetAttribute("InCombat", nil)
                end
                record.engaged = nil
                local slotPos = combatRingSlot(state, record, wildRoot.Position, root.Position.Y)
                humanoid:MoveTo(slotPos)
            end
        else
            -- No valid wild in the player's radius: FOLLOW the player (leash).
            disengageAndFollow()
        end
    end

    -- ENGAGE + EXCHANGE DAMAGE on the combat cadence. Re-evaluated PLAYER-CENTERED
    -- every tick: a wild that wanders out of detectionRangeStuds (or a player who
    -- walks away) yields no target here, so the fighter DISENGAGES + follows.
    if now >= record.nextCombatAt then
        record.nextCombatAt = now + COMBAT.combatTickSec
        local wild, wildRoot = nearestWild(playerPos, COMBAT.detectionRangeStuds)
        if not wild or not wildRoot then
            -- LEASH: nothing valid in range — disengage (clear InCombat) + follow.
            disengageAndFollow()
        else
            local dist = (wildRoot.Position - root.Position).Magnitude
            if dist <= COMBAT.attackRangeStuds then
                local wildHumanoid = wild:FindFirstChildWhichIsA("Humanoid")
                if wildHumanoid and wildHumanoid.Health > 0 then
                    -- Engage: the wild yields its movement to combat (wander skips
                    -- it via InCombat) and is told to hold position.
                    wild:SetAttribute("InCombat", true)
                    record.engaged = wild
                    wildHumanoid:MoveTo(wildRoot.Position)

                    -- RING SLOT: settle at this fighter's DISTINCT slot beside the
                    -- wild rather than stacking on its exact position. The deadzone
                    -- (followStopStuds) avoids re-issuing MoveTo every tick once the
                    -- fighter is basically at its slot. Damage below ALWAYS runs while
                    -- within attackRangeStuds (ring radius < attackRangeStuds keeps it
                    -- in range), independent of this movement.
                    local slotPos = combatRingSlot(state, record, wildRoot.Position, root.Position.Y)
                    if (slotPos - root.Position).Magnitude > COMBAT.followStopStuds then
                        humanoid:MoveTo(slotPos)
                    end

                    -- PACK WILDS carry a Personality attribute (their `Pack_<P>`
                    -- name does not match the `Brainrot_` prefix parser).
                    local attrPersonality = wild:GetAttribute("Personality")
                    local wildPersonality = (if type(attrPersonality) == "string" then attrPersonality else nil)
                        or personalityFromName(wild.Name)
                        or record.personality

                    -- ELEMENT (sandbox wiring, element doc §2): flat matchup
                    -- multiplier applied BOTH directions with the same circle.
                    -- A wild missing its attribute resolves to neutral 1.0
                    -- inside elementMod (defensive fallback, §5 #3).
                    local wildElement = wild:GetAttribute("Element")
                    local fighterVsWild = ElementConfig.elementMod(record.element, wildElement)
                    local wildVsFighter = ElementConfig.elementMod(wildElement, record.element)

                    -- 👑 BOSS: DamageMult attribute (e.g. 2.0) stamped by the
                    -- pack prototype; regular wilds default to 1.
                    local wildDamageMult = wild:GetAttribute("DamageMult")
                    if type(wildDamageMult) ~= "number" or wildDamageMult <= 0 then
                        wildDamageMult = 1
                    end

                    -- Wild takes the fighter's LEVEL+personality+rarity+evo-
                    -- scaled damage (F2 + R3 + S2) times elementMod.
                    wildHumanoid:TakeDamage(
                        fighterDamage(record.level, record.personality, record.rarity, record.evoStage) * fighterVsWild
                    )
                    -- Fighter takes the wild's (personality-only) damage back times
                    -- its DamageMult (boss) times the REVERSE elementMod; the wild
                    -- is treated as level 1 for now.
                    humanoid:TakeDamage(
                        scaledDamage(COMBAT.wildDamagePerTick, wildPersonality) * wildDamageMult * wildVsFighter
                    )

                    if wildHumanoid.Health <= 0 then
                        -- WIN: faint + respawn the wild + award coins (defeatWild
                        -- reads the boss WinCoinsMult attribute itself; mirror the
                        -- same mult here so the client banner shows the real award).
                        local xpMult = wild:GetAttribute("XpMult")
                        local coinsMult = wild:GetAttribute("WinCoinsMult")
                        if type(coinsMult) ~= "number" or coinsMult <= 0 then
                            coinsMult = 1
                        end
                        defeatWild(player, state, wild)
                        record.engaged = nil
                        -- PROGRESSION: award XP to the WINNING Brainrot (atomic +
                        -- persisted). May level it up one or more times. Boss
                        -- kills pass the XpMult attribute (e.g. 4x).
                        local leveledTo, currentLevel =
                            awardWinXp(player, record.brainrotId, if type(xpMult) == "number" then xpMult else nil)
                        -- Re-derive the bag so the new level shows immediately (the
                        -- active fighter stays excluded; recall/KO returns it later).
                        pushInventory(player)
                        DemoRemotes.BattleEvent:FireClient(player, {
                            kind = "win",
                            personality = record.personality,
                            coins = COMBAT.winCoins * coinsMult,
                            leveledTo = leveledTo,
                            level = currentLevel,
                        })
                        if leveledTo then
                            print(
                                ("[Combat] %s's %s defeated a wild -> LEVEL UP Lv%d"):format(
                                    player.Name,
                                    record.personality,
                                    leveledTo
                                )
                            )
                        else
                            print(
                                ("[Combat] %s's %s defeated a wild (+%d coins)"):format(
                                    player.Name,
                                    record.personality,
                                    COMBAT.winCoins
                                )
                            )
                        end
                    elseif humanoid.Health <= 0 then
                        -- The fighter died on this exchange: clear engagement so the
                        -- wild resumes wandering; the removal pass handles the KO event.
                        wild:SetAttribute("InCombat", nil)
                        record.engaged = nil
                    end
                end
            end
        end
    end

    return false
end

-- Combat scheduler: a Heartbeat accumulator at combatTickSec drives every active
-- fighter. Iterate each player's fighters back-to-front so a swap-remove during
-- the pass is safe. Guards against destroyed/Parent=nil models throughout.
local combatAccum = 0
local function stepCombat()
    local now = os.clock()
    for player, state in states do
        local removedAny = false
        local i = #state.fighters
        while i >= 1 do
            local record = state.fighters[i]
            if record and stepFighter(player, state, record, now) then
                removeFighter(state, i)
                removedAny = true
            end
            i -= 1
        end
        -- PROGRESSION: a removed fighter (KO/despawn) frees its Brainrot — it is no
        -- longer BUSY, so re-derive the bag once per player so it reappears (with
        -- any level it earned this run).
        if removedAny then
            pushInventory(player)
        end
    end
end

-- ── Recall (undeploy) ──────────────────────────────────────────────────────
-- Take a DEPLOYED display creature back into the owner's inventory: destroy the
-- model, free its slot, reset the pedestal label, clear the persisted deployment
-- entry, and push fresh InventoryUpdate + CoinUpdate. The bag is DERIVED from the
-- roster minus deployed/fighting ids, so clearing deployment makes it reappear.
-- Owner-only.
-- CORE recall: free slot `index` for `player` (already validated + rate-limited
-- by the caller). Shared by the legacy prompt path (handleRecall) and the
-- kandang-menu RecallDeployed remote. Returns true on success.
local function recallSlot(player: Player, index: number): boolean
    local state = states[player]
    if not state then
        return false
    end
    local slot = state.slots[index]
    if not slot then
        return false -- already freed (double-trigger / stale menu)
    end

    local personality = slot.personality
    if slot.model then
        slot.model:Destroy() -- destroys any attached prompt with it
    end
    state.slots[index] = nil

    -- PERSIST the undeploy: clear this stand's deployment-map entry + decrement
    -- the cached deployedCount (clamped >= 0), atomically. The roster entry itself
    -- stays owned (recall returns it to the bag, it is not released).
    PlayerDataService.update(player, function(data)
        local b1 = data.base.buildings[BUILDING_ID]
        if b1 then
            b1.deployment[tostring(index)] = nil
            data.base.deployedCount = math.max(0, (data.base.deployedCount or 1) - 1)
        end
        return true
    end)

    local stand = findStand(index)
    if stand then
        setStandLabel(stand, "Empty", false)
    end

    -- The stand is empty again: restore its Place prompt so it can be filled
    -- (no-op while the kandang menu owns placement).
    addPlacePrompt(index)

    -- The roster entry is no longer deployed (deployment cleared above); the bag is
    -- DERIVED from the roster, so a re-push returns it to the inventory list.
    pushInventory(player)
    pushCoins(player)
    print("[Recall] " .. player.Name .. " recalled " .. personality .. " from slot " .. index)
    return true
end

local function handleRecall(prompt: ProximityPrompt, player: Player)
    local target = deployedPromptToSlot[prompt]
    if not target then
        return -- not a recall prompt; ignore
    end
    -- Owner-only: a different player triggering this prompt is rejected.
    if target.player ~= player then
        return
    end
    local state = states[player]
    if not state then
        return
    end
    if not allowAction(state, "recall", DemoConfig.rateLimits.recall) then
        return
    end
    -- De-register the prompt first so a queued re-trigger is ignored.
    deployedPromptToSlot[prompt] = nil
    recallSlot(player, target.index)
end

-- ── Place (open the menu for a SPECIFIC empty stand) ───────────────────────
-- The player triggered an empty pedestal's Place prompt. We do NOT deploy here —
-- we ask the client to open the place menu for this stand; the client replies
-- with DeployToStand(standIndex, personality) once a creature is tapped.
local function handlePlace(prompt: ProximityPrompt, player: Player)
    local standIndex = placePromptToStand[prompt]
    if not standIndex then
        return -- not a place prompt; ignore
    end
    local state = states[player]
    if not state then
        return -- no state for this player; ignore
    end
    DemoRemotes.OpenPlaceMenu:FireClient(player, standIndex)
end

-- Single PromptTriggered dispatcher: route to catch (wild creatures), recall
-- (deployed creatures), or place (empty pedestals) by which map the prompt is
-- in. A prompt in NONE of the maps is ignored, so unrelated prompts never react.
-- ── KANDANG MENU (single F terminal at the paddock gate) ───────────────────
-- One prompt replaces the per-plate Place prompts + per-monster Recall prompts.
-- The menu is data-driven: the server snapshots the player's deployed slots +
-- free stands and the client renders taruh/ambil actions against it.

-- Build the OpenKandangMenu payload for `player` (deployed slots enriched with
-- element/level from the authoritative roster, plus the free stand indices).
local function buildKandangPayload(player: Player): { [string]: any }?
    local state = states[player]
    if not state then
        return nil
    end
    local data = PlayerDataService.getData(player)
    local deployed = {}
    local free = {}
    for index = 1, SHOWROOM.showroomStandCount do
        local slot = state.slots[index]
        if slot then
            local entry = data and data.roster[slot.id]
            table.insert(deployed, {
                index = index,
                personality = slot.personality,
                element = entry and entry.element or nil,
                rarity = entry and entry.rarity or nil,
                evoStage = entry and entry.evoStage or 0,
                level = entry and entry.level or 1,
            })
        else
            table.insert(free, index)
        end
    end
    -- ECONOMY SINK (Upgrade Kandang): ship the current level + the next cost
    -- so the menu renders the upgrade button without trusting the client.
    -- nextCost nil = level cap reached (upgradeCost returns math.huge there,
    -- which does not survive a remote cleanly).
    local level = state.factoryLevel
    local nextCost: number? = EconomyConfig.upgradeCost("factory", level)
    if nextCost == math.huge then
        nextCost = nil
    end
    return {
        capacity = SHOWROOM.showroomStandCount,
        deployed = deployed,
        free = free,
        level = level,
        nextCost = nextCost,
        bonusPerLevel = DemoConfig.kandang.upgrade.bonusPerLevel,
    }
end

-- Push a fresh kandang snapshot to `player` (open OR refresh — the client
-- decides; a closed menu ignores refreshes, an open one re-renders).
local function pushKandang(player: Player)
    local payload = buildKandangPayload(player)
    if payload then
        DemoRemotes.OpenKandangMenu:FireClient(player, payload)
    end
end
pushKandangRef = pushKandang

-- The terminal prompt instance (created at startup when the menu is enabled).
local kandangPrompt: ProximityPrompt? = nil

local function setupKandangTerminal(): boolean
    if not KANDANG.menu.enabled then
        return false
    end
    local showroomModel = workspace:FindFirstChild(SHOWROOM.modelName)
    local terminal = showroomModel and showroomModel:FindFirstChild(KANDANG.menu.terminalName)
    if not terminal or not terminal:IsA("BasePart") then
        warn("[Kandang][server] terminal part missing: " .. KANDANG.menu.terminalName)
        return false
    end
    local prompt = Instance.new("ProximityPrompt")
    prompt.Name = "KandangPrompt"
    prompt.ActionText = KANDANG.menu.actionText
    prompt.ObjectText = KANDANG.menu.objectText
    prompt.KeyboardKeyCode = Enum.KeyCode.F
    prompt.HoldDuration = KANDANG.menu.holdSec
    prompt.MaxActivationDistance = KANDANG.menu.distance
    prompt.RequiresLineOfSight = false
    prompt.Parent = terminal
    kandangPrompt = prompt
    return true
end

-- C->S: the client asks for a fresh snapshot (menu open / post-action refresh).
local function handleRequestKandang(player: Player)
    local state = states[player]
    if not state then
        return
    end
    -- Reuse the recall bucket: the menu round-trips at human tap cadence.
    if not allowAction(state, "kandang", DemoConfig.rateLimits.recall) then
        return
    end
    pushKandang(player)
end

-- C->S: recall the monster on `standIndex` back into the bag (menu "ambil").
local function handleRecallDeployed(player: Player, standIndex: unknown)
    local state = states[player]
    if not state then
        return
    end
    if not allowAction(state, "recall", DemoConfig.rateLimits.recall) then
        return
    end
    -- Validate the index (attacker-controlled arg).
    if type(standIndex) ~= "number" or standIndex ~= math.floor(standIndex) then
        return
    end
    if standIndex < 1 or standIndex > SHOWROOM.showroomStandCount then
        return
    end
    -- Ownership is implicit: recallSlot only frees THIS player's state.slots.
    if recallSlot(player, standIndex) then
        pushKandang(player)
    end
end

-- C->S: buy the next kandang (factory) level — the demo's PRIMARY coin sink.
-- Cost from the LOCKED EconomyConfig factory curve; production bonus applied
-- via state.factoryLevel (kandangBonus). PERSIST FIRST: the level bump commits
-- atomically before the float is debited.
local function handleUpgradeKandang(player: Player)
    local state = states[player]
    if not state then
        return
    end
    if not allowAction(state, "upgrade_kandang", DemoConfig.rateLimits.deploy) then
        return
    end
    local level = state.factoryLevel
    local cost = EconomyConfig.upgradeCost("factory", level)
    if cost == math.huge then
        DemoRemotes.Moment:FireClient(player, { kind = "info", text = "🏠 Kandang sudah level maksimum!" })
        return
    end
    if state.coins < cost then
        DemoRemotes.Moment:FireClient(player, {
            kind = "info",
            text = ("🪙 Koin tidak cukup! Upgrade butuh %d."):format(cost),
        })
        return
    end
    local ok = PlayerDataService.update(player, function(d)
        local b1 = d.base.buildings[BUILDING_ID]
        if not b1 then
            error("no_building", 0)
        end
        b1.factoryLevel = (b1.factoryLevel or 0) + 1
        return true
    end)
    if not ok then
        return
    end
    state.factoryLevel += 1
    state.coins = math.max(0, state.coins - cost)
    flushCoins(player, false)
    pushCoins(player) -- the new rate (with the bigger bonus) ships here
    pushKandang(player)
    local bonusPct = math.floor(DemoConfig.kandang.upgrade.bonusPerLevel * 100 + 0.5)
    DemoRemotes.Moment:FireClient(player, {
        kind = "info",
        text = ("🏠 Kandang naik ke Lv%d! Produksi +%d%% per level."):format(state.factoryLevel, bonusPct),
    })
    print(("[Upgrade] %s kandang -> Lv%d (-%d coins)"):format(player.Name, state.factoryLevel, cost))
end

-- ── EVOLUTION (sink S2): pay the activation cost to evolve a BAG monster ───
-- HYBRID gate: milestone level (free, from playing) + coins (x rarity).
-- PERSIST-FIRST: eligibility is re-validated INSIDE the atomic mutator (a
-- racing double-tap cannot double-evolve); the float is debited only after
-- the stage bump committed. The monster must be in the BAG (not deployed /
-- not fighting) so no live clone ever needs retro-fitting — the aura + stat
-- bump apply on the next spawn/summon.
local function handleEvolve(player: Player, brainrotId: unknown)
    local state = states[player]
    if not state then
        return
    end
    if not allowAction(state, "evolve", DemoConfig.rateLimits.deploy) then
        return
    end
    if type(brainrotId) ~= "string" then
        return -- attacker-controlled arg; reject
    end
    local data = PlayerDataService.getData(player)
    if not data then
        return
    end
    local entry = data.roster[brainrotId]
    if not entry then
        return -- not owned; reject
    end
    -- BUSY check: deployed or fighting monsters cannot evolve (bag only).
    local b1 = data.base.buildings[BUILDING_ID]
    if b1 then
        for _, deployedId in b1.deployment do
            if deployedId == brainrotId then
                return
            end
        end
    end
    for _, record in state.fighters do
        if record.brainrotId == brainrotId then
            return
        end
    end

    local stage = entry.evoStage or 0
    if stage >= EVOLUTION.maxStage then
        DemoRemotes.Moment:FireClient(player, { kind = "info", text = "💫 Monster ini sudah STAGE MAX!" })
        return
    end
    local milestone = EVOLUTION.levelMilestones[stage + 1]
    if entry.level < milestone then
        DemoRemotes.Moment:FireClient(player, {
            kind = "info",
            text = ("✨ Butuh Lv %d untuk evolve (sekarang Lv %d)."):format(milestone, entry.level),
        })
        return
    end
    local cost = math.floor(EVOLUTION.baseCost[stage + 1] * RarityConfig.evolveCostMultFor(entry.rarity))
    if state.coins < cost then
        DemoRemotes.Moment:FireClient(player, {
            kind = "info",
            text = ("🪙 Koin tidak cukup! Evolve butuh %d."):format(cost),
        })
        return
    end

    -- PERSIST FIRST, re-validating inside the mutator (anti double-fire).
    local newStage = stage + 1
    local ok = PlayerDataService.update(player, function(d)
        local e = d.roster[brainrotId]
        if not e then
            error("gone", 0)
        end
        local s = e.evoStage or 0
        if s ~= stage or e.level < milestone then
            error("stale", 0)
        end
        e.evoStage = s + 1
        return true
    end)
    if not ok then
        return
    end
    state.coins = math.max(0, state.coins - cost)
    flushCoins(player, false)
    pushCoins(player)
    pushInventory(player) -- stats + evolve-button data re-derive
    local stageEmoji = ({ "✨", "🌟", "💫" })[newStage] or "✨"
    DemoRemotes.Moment:FireClient(player, {
        kind = "info",
        text = ("%s %s berevolusi ke Stage %d! Stat x%.2f"):format(
            stageEmoji,
            string.upper(entry.personality),
            newStage,
            EVOLUTION.statMult[newStage]
        ),
    })
    print(
        ("[Evolve] %s %s -> stage %d (-%d coins, rarity %s)"):format(
            player.Name,
            entry.personality,
            newStage,
            cost,
            tostring(entry.rarity)
        )
    )
end

-- DEV ONLY (Studio): grant XP to a roster entry through the REAL awardWinXp
-- path so evolve milestones can be tested without 20 minutes of farming.
-- Server-side BindableFunction — unreachable from clients; no-op outside
-- Studio. Remove (or leave; it is inert in production) before launch.
if game:GetService("RunService"):IsStudio() then
    local devXp = Instance.new("BindableFunction")
    devXp.Name = "DevAwardXp"
    devXp.Parent = ServerStorage
    devXp.OnInvoke = function(player: Player, brainrotId: string, wins: number): boolean
        for _ = 1, math.clamp(wins, 1, 200) do
            awardWinXp(player, brainrotId)
        end
        pushInventory(player)
        return true
    end
end

local function onPromptTriggered(prompt: ProximityPrompt, player: Player)
    if promptToRecord[prompt] then
        handleCatch(prompt, player)
    elseif deployedPromptToSlot[prompt] then
        handleRecall(prompt, player)
    elseif placePromptToStand[prompt] then
        handlePlace(prompt, player)
    elseif kandangPrompt ~= nil and prompt == kandangPrompt then
        -- KANDANG MENU: open with a fresh snapshot.
        if states[player] then
            pushKandang(player)
        end
    end
end

-- ── Lifecycle ──────────────────────────────────────────────────────────────
-- HYDRATE the live demo world from the player's PERSISTED profile (loaded by
-- PlayerDataBootstrap on join). Rebuilds the bag (roster entries NOT currently
-- deployed) + re-spawns deployed creatures onto their saved stands, seeds the
-- live coin float from data.coins, applies any offline welcome-back bonus, then
-- flushes (clearing pendingOffline so it is never re-applied). Idempotent via the
-- states[player] guard.
local function hydrate(player: Player, data: Types_PlayerData)
    if states[player] then
        return -- already hydrated (DataLoaded + the startup sweep can both fire)
    end

    local state: PlayerState = {
        coins = data.coins, -- live float seeded from the persisted whole-coin total
        pending = 0,
        slots = {},
        rateBuckets = {},
        fighters = {}, -- no active fighters on join (ephemeral, not persisted)
        -- COINS-MADE: start the attribution window now so the first flush only
        -- credits production that happens AFTER hydrate (no offline double-count;
        -- offline coins are handled separately via pendingOffline).
        lastCoinAttributeAt = os.clock(),
        -- ECONOMY SINK: cache the persisted kandang level for the rate math.
        factoryLevel = (data.base.buildings[BUILDING_ID] and data.base.buildings[BUILDING_ID].factoryLevel) or 0,
    }
    states[player] = state

    -- Which roster ids are currently deployed, and to which stand. slotKey is the
    -- stringified stand index; map it back to a number for findStand/spawnDisplay.
    local b1 = data.base.buildings[BUILDING_ID]
    local deployedIds: { [string]: number } = {}
    if b1 then
        for slotKey, id in b1.deployment do
            local standIndex = tonumber(slotKey)
            if id ~= nil and standIndex ~= nil then
                deployedIds[id] = standIndex
            end
        end
    end

    -- BAG: the inventory is DERIVED FRESH from the roster (minus deployed/fighting
    -- ids) by pushInventory below — there is no local bag list to seed here.

    -- DEPLOYED: re-spawn each deployed creature onto its saved stand + re-attach
    -- the recall prompt. A missing stand/template is skipped gracefully (the
    -- persisted deployment entry is left intact so a later hydrate can retry).
    for id, standIndex in deployedIds do
        local entry = data.roster[id]
        if entry then
            local stand = findStand(standIndex)
            if stand then
                local model = spawnDisplay(entry.personality, stand, standIndex, entry)
                if model then
                    state.slots[standIndex] = { personality = entry.personality, model = model, id = id }
                    setStandLabel(stand, string.upper(entry.personality), true)
                    removePlacePrompt(standIndex)
                    addRecallPrompt(model, player, entry.personality, standIndex)
                end
            end
        end
    end

    -- OFFLINE: Persistence pre-computed the away earnings into pendingOffline
    -- (via our resolver) on load. Fold it into the live total ONCE, then flush
    -- with clearOffline so the bonus is persisted into data.coins and cannot be
    -- granted again on the next rejoin.
    local welcome = (data.pendingOffline and data.pendingOffline.coins) or 0
    if welcome > 0 then
        state.coins += welcome
    end
    flushCoins(player, true)

    pushInventory(player)
    pushCoins(player)

    -- Welcome-back Moment (only when something accrued). PAYLOAD SHAPE: there was
    -- no pre-existing client Moment handler, so we define a minimal, explicit one:
    --   { kind = "welcome_back", text = string, coins = number }
    -- A lightweight handler was added to DemoUI to show `text` as a transient
    -- banner; `kind`/`coins` let future moment kinds reuse the same remote.
    if welcome > 0 then
        DemoRemotes.Moment:FireClient(player, {
            kind = "welcome_back",
            text = ("Welcome back! +%d coins while away 💤"):format(welcome),
            coins = welcome,
        })
        print(("[Offline] %s welcome-back +%d coins"):format(player.Name, welcome))
    end
end

local function onPlayerRemoving(player: Player)
    -- Best-effort final coin flush BEFORE world cleanup so the latest live total
    -- is persisted (the bootstrap's PlayerRemoving force-save then writes it
    -- durably). Do not clear pendingOffline here — it was already cleared at
    -- hydrate, and the bootstrap owns the durable save/release.
    flushCoins(player, false)

    local state = states[player]
    if state then
        -- COMBAT (Tahap 2): destroy this player's active fighters + clear any wild
        -- they had engaged (so wander resumes for that wild). removeFighter both
        -- destroys the model and clears the engaged wild's InCombat flag.
        for i = #state.fighters, 1, -1 do
            removeFighter(state, i)
        end

        -- Free the Showroom: destroy this player's deployed display clones +
        -- reset their pedestal labels (single-player demo; slots are not shared).
        for index, slot in state.slots do
            if slot.model then
                slot.model:Destroy()
            end
            local stand = findStand(index)
            if stand then
                setStandLabel(stand, "Empty", false)
            end
            -- Stand is empty again: restore its Place prompt for the next player.
            addPlacePrompt(index)
        end
    end
    -- Drop any recall-prompt map entries owned by the leaving player (their
    -- deployed models were destroyed above, taking the prompts with them).
    for prompt, target in deployedPromptToSlot do
        if target.player == player then
            deployedPromptToSlot[prompt] = nil
        end
    end
    states[player] = nil
end

-- ── Startup: attach catch prompts to the placed creatures ──────────────────
local function setupCreatures(): number
    local count = 0
    for _, creatureName in DemoConfig.demo3d.creatureNames do
        local model = workspace:FindFirstChild(creatureName)
        if model then
            local personality = personalityFromName(creatureName)
            if personality then
                local anchor = findAnchorPart(model)
                if anchor then
                    local record: CreatureRecord = {
                        name = creatureName,
                        personality = personality,
                        originalCFrame = model:GetPivot(),
                    }
                    model:SetAttribute("DemoCaught", false)
                    if addCatchPrompt(model, record) then
                        count += 1
                    end
                end
            end
        end
        -- Missing / malformed creature: skipped gracefully (no error).
    end
    return count
end

-- ── Startup: attach a Place prompt to every (initially empty) pedestal ─────
-- At boot every stand is empty, so each gets a Place prompt. As stands are
-- filled / freed at runtime, handleDeployToStand + handleRecall keep this in
-- sync (occupied = Recall prompt, empty = Place prompt). Returns the count added.
local function setupPlaceStands(): number
    local count = 0
    for i = 1, SHOWROOM.showroomStandCount do
        addPlacePrompt(i)
        if standToPlacePrompt[i] then
            count += 1
        end
    end
    return count
end

-- ── Production loop (AUTO-COLLECT) ─────────────────────────────────────────
-- Heartbeat with a 1 Hz dt accumulator: each step adds DIRECTLY to the live
-- total, per player,
--   coins += Σ_slots (baseRatePerSlot * prodMult(personality)) * dt
-- (no pending/bank step — coins rise on their own). We push a CoinUpdate every
-- `coinBroadcastSec` so the client can smoothly interpolate the climb. `dt` is
-- the ACTUAL accumulated delta (frame-rate safe).
local productionAccum = 0
local broadcastAccum = 0
local flushAccum = 0
local kandangAccum = 0 -- KANDANG WANDER cadence (KANDANG.aiTickSec)
local TICK = DemoConfig.productionTickSec
local BROADCAST = DemoConfig.coinBroadcastSec
local FLUSH = DemoConfig.coinFlushSec

local function stepProduction(dt: number)
    for _, state in states do
        local rate = currentRate(state)
        if rate > 0 then
            state.coins += rate * dt
        end
    end
end

local function onHeartbeat(dt: number)
    productionAccum += dt
    if productionAccum >= TICK then
        stepProduction(productionAccum)
        productionAccum = 0
    end
    broadcastAccum += dt
    if broadcastAccum >= BROADCAST then
        broadcastAccum = 0
        for player, state in states do
            pushCoins(player)
            print(("[Coin] %s coins=%d rate=%.2f/s"):format(player.Name, math.floor(state.coins), currentRate(state)))
        end
    end
    -- PERSIST CADENCE: piggyback the heartbeat to periodically flush each player's
    -- live coin float into the audited profile (every coinFlushSec ~2s). markDirty
    -- inside update() lets the bootstrap autosave/BindToClose persist it durably,
    -- so coins survive a crash/leave even between routine autosaves. We do NOT
    -- clear pendingOffline here (that happens once, at hydrate).
    flushAccum += dt
    if flushAccum >= FLUSH then
        flushAccum = 0
        for player in states do
            flushCoins(player, false)
        end
    end
    -- COMBAT (Tahap 2): drive active fighters at combatTickSec. The per-fighter
    -- seek/combat gates are os.clock()-based, so this accumulator only bounds how
    -- often we sweep — actual damage cadence is owned by combatTickSec.
    combatAccum += dt
    if combatAccum >= COMBAT.combatTickSec then
        combatAccum = 0
        stepCombat()
    end
    -- KANDANG WANDER: stroll every deployed monster around the paddock. The
    -- per-slot nextMoveAt gates own the pause rhythm; this accumulator only
    -- bounds the sweep cadence.
    kandangAccum += dt
    if kandangAccum >= KANDANG.aiTickSec then
        kandangAccum = 0
        stepKandangWander(os.clock())
    end
end

-- ── Wire up ────────────────────────────────────────────────────────────────
-- Single dispatcher routes catch (wild) / recall (deployed) / place (empty) prompts.
ProximityPromptService.PromptTriggered:Connect(onPromptTriggered)
DemoRemotes.DeployToStand.OnServerEvent:Connect(handleDeployToStand)
-- COMBAT (Tahap 2): summon an owned Brainrot as a temporary auto-battling fighter.
DemoRemotes.SummonFighter.OnServerEvent:Connect(handleSummon)
-- KANDANG MENU: snapshot request + tap-to-recall + upgrade sink.
DemoRemotes.RequestKandang.OnServerEvent:Connect(handleRequestKandang)
DemoRemotes.RecallDeployed.OnServerEvent:Connect(handleRecallDeployed)
DemoRemotes.UpgradeKandang.OnServerEvent:Connect(handleUpgradeKandang)
-- EVOLUTION sink (S2): paid stage activation from the stat sheet.
DemoRemotes.EvolveMonster.OnServerEvent:Connect(handleEvolve)
-- AUTO-COLLECT: the Collect remote stays registered (handleCollect is a no-op)
-- but is intentionally NOT wired to OnServerEvent — coins rise automatically.
-- Reference the no-op so it is not flagged unused while documenting the removal.
local _ = handleCollect
RunService.Heartbeat:Connect(onHeartbeat)

-- HYDRATION: the world is rebuilt from the PERSISTED profile, not blank. The
-- bootstrap loads each profile on join and fires PlayerDataService.DataLoaded
-- once it is cached; we hydrate off that signal (covers the normal join race
-- where this script connected before the profile finished loading).
PlayerDataService.DataLoaded:Connect(function(player: Player, data: Types_PlayerData)
    hydrate(player, data)
end)
Players.PlayerRemoving:Connect(onPlayerRemoving)
-- Catch players whose profile was ALREADY loaded before this script connected
-- DataLoaded (e.g. a fast rejoin / script restart): hydrate them directly from
-- the cached profile. isLoaded guards against a player still mid-load (they will
-- get the DataLoaded signal above instead).
for _, player in Players:GetPlayers() do
    if PlayerDataService.isLoaded(player) and not states[player] then
        local data = PlayerDataService.getData(player)
        if data then
            hydrate(player, data)
        end
    end
end

-- Snapshot stable display templates BEFORE any catch can remove a wild creature
-- (BUG 1). Deploy clones from these, never from the live Workspace creatures.
local templateCount = buildTemplates()
print("[Demo Deploy] templates ready — " .. templateCount .. " in ServerStorage." .. TEMPLATES_FOLDER_NAME)

-- COMBAT (Tahap 2): snapshot the RIGGED fighter templates (Humanoid kept) at boot
-- too — the wild creatures are present + rigged now, before any catch removes one.
local fighterTemplateCount = buildFighterTemplates()
print(
    "[Demo Combat] fighter templates ready — "
        .. fighterTemplateCount
        .. " in ServerStorage."
        .. FIGHTER_TEMPLATES_FOLDER_NAME
)

local ready = setupCreatures()
print("[Demo Capture] ready — " .. ready .. " creatures with catch prompts")

-- Every pedestal starts empty: attach its Place prompt so the player can pick
-- which podium to fill (and which creature, via the menu the prompt opens).
local placeReady = setupPlaceStands()
print("[Demo Place] ready — " .. placeReady .. " empty stands with place prompts")

-- KANDANG MENU: one F terminal at the paddock gate replaces the per-plate /
-- per-monster prompts (those creators no-op while the menu is enabled).
if setupKandangTerminal() then
    print("[Kandang] terminal ready — menu interaction enabled")
end
