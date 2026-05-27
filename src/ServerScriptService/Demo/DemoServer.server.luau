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
local PlayerDataService = require(ServerStorage:WaitForChild("PlayerData"):WaitForChild("PlayerDataService"))
local Schema = require(ServerStorage:WaitForChild("PlayerData"):WaitForChild("Schema"))

type Types_PlayerData = Types.PlayerData

-- The single MVP building this demo persists deploys into.
local BUILDING_ID = "b1"

-- species id = 1-based index of the personality in DemoConfig.personalityOrder
-- (the persisted roster entry stores a numeric species; the demo only has the 5
-- personality archetypes, so personality order IS the species mapping). Fallback 1.
local speciesByPersonality: { [string]: number } = {}
for index, key in DemoConfig.personalityOrder do
    speciesByPersonality[key] = index
end

-- ── Types ────────────────────────────────────────────────────────────────
-- One caught creature in a player's inventory. `id` is the PERSISTED roster GUID
-- (server-internal: it ties this bag item back to its data.roster entry so deploy
-- can write the deployment map). The CLIENT contract is unchanged — pushInventory
-- strips `id` and sends only { name, personality }.
type InventoryItem = {
    id: string, -- persisted roster GUID (server-internal; stripped before the client push)
    name: string, -- display name, e.g. "HYPER Brainrot"
    personality: string, -- canonical key: "Hyper" | "Lazy" | "Chaotic" | "Loyal" | "Rebel"
}

-- One occupied Showroom pedestal: which personality stands there + its clone +
-- the persisted roster GUID of the deployed creature (so recall can clear the
-- deployment map entry for the right id).
type DeployedSlot = {
    personality: string,
    model: Model,
    id: string, -- persisted roster GUID of the deployed creature
}

-- One ACTIVE summoned fighter (Tahap 2). Ephemeral field combatant — it is NOT a
-- bag item (summoning never consumes the bag), just a live model the combat loop
-- drives. `model` is the rigged clone; `nextCombatAt`/`nextSeekAt` are os.clock()
-- gates so we tick damage at combatTickSec and re-target at seekRetargetSec;
-- `despawnAt` is the auto-cleanup deadline; `engaged` is the wild it is currently
-- fighting (so we can clear that wild's InCombat flag if the fighter dies/despawns).
type FighterRecord = {
    personality: string,
    model: Model,
    nextCombatAt: number,
    nextSeekAt: number,
    despawnAt: number,
    engaged: Model?,
}

type PlayerState = {
    inventory: { InventoryItem },
    -- ── Showroom / idle-production (server-authoritative) ────────────────
    coins: number, -- live coin total (AUTO-COLLECT: production adds here directly)
    pending: number, -- UNUSED (kept = 0 for back-compat; auto-collect removed the bank step)
    slots: { [number]: DeployedSlot }, -- standIndex (1..showroomStandCount) -> slot
    rateBuckets: { [string]: { count: number, windowStart: number } },
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

-- Current AUTO-COLLECT production rate (coins/sec) for a player: the sum over
-- every deployed slot of baseRatePerSlot * prodMult(personality). 0 if nothing
-- is deployed. Shipped alongside the live total so the client can interpolate.
local function currentRate(state: PlayerState): number
    local rate = 0
    for _, slot in state.slots do
        rate += DemoConfig.baseRatePerSlot * prodMult(slot.personality)
    end
    return rate
end

-- OFFLINE RESOLVER (installed BEFORE any profile loads). Persistence owns the
-- clock + the clamped `elapsed`; we own the RATE. The rate mirrors currentRate
-- but is computed from the PERSISTED roster + deployment map (the live `state`
-- does not exist yet at load time): sum over each deployed roster id of
-- baseRatePerSlot * prodMult(entry.personality). Returns integer coins. PURE +
-- non-yielding (it runs inside the load path).
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
    return math.floor(rate * elapsed)
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

-- Display name for a caught creature. Keep it simple: "<UPPER> Brainrot".
local function displayName(personality: string): string
    return string.format("%s Brainrot", string.upper(personality))
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
    end
    return true
end

-- ── Inventory ──────────────────────────────────────────────────────────────
local function pushInventory(player: Player)
    local state = states[player]
    if not state then
        warn("[Inv][server] pushInventory: NO STATE for " .. player.Name)
        return
    end
    -- CLIENT CONTRACT (unchanged): the client only ever sees { name, personality }.
    -- We STRIP the server-internal roster `id` here so DemoClient/DemoUI need no
    -- changes. Build a fresh display list each push (do not leak the id field).
    local payload: { { name: string, personality: string } } = {}
    for _, item in state.inventory do
        table.insert(payload, { name = item.name, personality = item.personality })
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
    PlayerDataService.update(player, function(data)
        data.coins = math.floor(state.coins)
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
            -- Full Health on the template so every clone starts fresh.
            local humanoid = template:FindFirstChildWhichIsA("Humanoid")
            if humanoid then
                humanoid.MaxHealth = DemoConfig.combat.fighterMaxHP
                humanoid.Health = DemoConfig.combat.fighterMaxHP
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

-- Build a display clone from the STABLE template store and stand it on the
-- pedestal TOP. Returns the parented clone, or nil if the template is missing.
local function spawnDisplay(personality: string, stand: BasePart, index: number): Model?
    local folder = getTemplatesFolder()
    local template = folder:FindFirstChild(personality)
    if not template or not template:IsA("Model") then
        warn("[Deploy][server] missing template " .. personality .. " (no startup snapshot)")
        return nil
    end

    local clone = template:Clone()
    -- Template was already stripped to a static prop at build time; clone is clean.

    -- Place STANDING ON TOP of the pedestal, facing forward (toward -Z so it
    -- faces a player standing in front of the Showroom).
    local _, size = clone:GetBoundingBox()
    local creatureHeight = size.Y
    local target = stand.Position
        + Vector3.new(0, stand.Size.Y / 2 + creatureHeight / 2 + SHOWROOM.standClearanceStuds, 0)
    clone:PivotTo(CFrame.lookAt(target, target + Vector3.new(0, 0, -1)))

    clone.Name = "Deployed_" .. tostring(index)
    clone.Parent = workspace
    return clone
end

-- Attach a "Recall" ProximityPrompt to a DEPLOYED display model so the owner can
-- undeploy it back into their inventory. Registered in deployedPromptToSlot so a
-- trigger resolves in O(1) and only the owner (matched in the handler) acts.
-- Returns false if the model has no usable anchor part.
local function addRecallPrompt(model: Model, player: Player, personality: string, index: number): boolean
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

    -- Find a matching caught item.
    local itemIndex: number? = nil
    for i, item in state.inventory do
        if item.personality == personality then
            itemIndex = i
            break
        end
    end
    if not itemIndex then
        return -- nothing of that personality to deploy
    end
    local itemId = state.inventory[itemIndex].id

    local stand = findStand(standIndex)
    if not stand then
        return -- pedestal missing in Workspace
    end

    local model = spawnDisplay(personality, stand, standIndex)
    if not model then
        return -- template missing; leave inventory untouched
    end

    -- PERSIST the deploy FIRST (server-authoritative). Record the roster id under
    -- this stand's slot key + bump the cached deployedCount, atomically. If the
    -- transaction fails (profile not loaded / no building), destroy the just-spawned
    -- model and bail so the live world never diverges from the persisted profile.
    local ok = PlayerDataService.update(player, function(data)
        local b1 = data.base.buildings[BUILDING_ID]
        if not b1 then
            error("no_building", 0)
        end
        b1.deployment[tostring(standIndex)] = itemId
        data.base.deployedCount = (data.base.deployedCount or 0) + 1
        return true
    end)
    if not ok then
        model:Destroy()
        return -- persistence rejected; no desync
    end

    table.remove(state.inventory, itemIndex)
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

    -- SERVER-AUTHORITATIVE inventory add (carries the persisted roster id).
    table.insert(state.inventory, {
        id = entry.id,
        name = displayName(record.personality),
        personality = record.personality,
    })
    pushInventory(player)

    -- Remove the shared creature from the world, then schedule its respawn.
    model.Parent = nil
    respawnCreature(record, model)

    print("[Catch] " .. player.Name .. " caught " .. record.personality)
end

-- ════════════════════════════════════════════════════════════════════════════
-- COMBAT (Tahap 2): SUMMON a fighter that auto-battles the nearest wild Brainrot
-- ════════════════════════════════════════════════════════════════════════════
local COMBAT = DemoConfig.combat

-- Damage a combatant deals per tick, optionally scaled by its personality's
-- prodMult (Hyper ~1.3x, Lazy ~0.5x) when personalityDamageScales is on.
local function scaledDamage(base: number, personality: string): number
    if COMBAT.personalityDamageScales then
        return base * prodMult(personality)
    end
    return base
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

-- Find the NEAREST living, present, un-caught, un-engaged-by-others wild creature
-- to `fromPos`. Returns the model + its root, or nil if none is available. A wild
-- already InCombat is still a valid target only for the fighter already on it; we
-- let any fighter engage the nearest free OR same-target wild (combat is shared).
local function nearestWild(fromPos: Vector3): (Model?, BasePart?)
    local best: Model? = nil
    local bestRoot: BasePart? = nil
    local bestDist = math.huge
    for _, creatureName in DemoConfig.demo3d.creatureNames do
        local model = workspace:FindFirstChild(creatureName)
        if model and model:IsA("Model") and model:GetAttribute("DemoCaught") ~= true then
            local humanoid = model:FindFirstChildWhichIsA("Humanoid")
            local root = model.PrimaryPart
            if humanoid and humanoid.Health > 0 and root then
                local dist = (root.Position - fromPos).Magnitude
                if dist < bestDist then
                    bestDist = dist
                    best = model
                    bestRoot = root
                end
            end
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
    state.coins += COMBAT.winCoins
    pushCoins(player)
    flushCoins(player, false)

    wild:SetAttribute("InCombat", nil)

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

-- Build + register a fighter for `player` from `personality`. The player must OWN
-- >=1 of that personality (NOT consumed) and be under the maxActiveFighters cap.
-- Validated + rate-limited. Spawns the rigged clone summonOffsetStuds in front of
-- the player's character, server-owned, with a ⚔ label. No-op (graceful) if the
-- player has no character / the template is missing.
local function handleSummon(player: Player, personality: unknown)
    local state = states[player]
    if not state then
        return
    end
    if not allowAction(state, "summon", DemoConfig.rateLimits.summon) then
        return
    end
    -- Validate the personality (attacker-controlled arg).
    if type(personality) ~= "string" or not isValidPersonality[personality] then
        return
    end
    -- Cap: bound active fighters per player.
    if #state.fighters >= COMBAT.maxActiveFighters then
        return
    end
    -- OWNERSHIP: must hold >=1 of this personality in the bag (NOT consumed —
    -- summoning is an ephemeral field action; the roster/bag is untouched).
    local owns = false
    for _, item in state.inventory do
        if item.personality == personality then
            owns = true
            break
        end
    end
    if not owns then
        return
    end

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

    local humanoid = fighter:FindFirstChildWhichIsA("Humanoid")
    local root = fighter.PrimaryPart
    if not humanoid or not root then
        fighter:Destroy()
        return
    end
    humanoid.WalkSpeed = COMBAT.fighterWalkSpeed
    humanoid.MaxHealth = COMBAT.fighterMaxHP
    humanoid.Health = COMBAT.fighterMaxHP

    -- Spawn summonOffsetStuds in FRONT of the player (along their look vector).
    local spawnCFrame = charRoot.CFrame * CFrame.new(0, 0, -COMBAT.summonOffsetStuds)
    fighter:PivotTo(CFrame.new(spawnCFrame.Position))

    -- A small ⚔ label so it reads as the player's fighter.
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
    labelText.Text = "⚔ " .. string.upper(personality)
    labelText.Parent = billboard
    local labelAnchor = findAnchorPart(fighter)
    billboard.Parent = labelAnchor or root

    fighter.Parent = workspace

    -- Server-authoritative motion: claim network ownership (root is unanchored).
    pcall(function()
        root:SetNetworkOwner(nil)
    end)

    local now = os.clock()
    local record: FighterRecord = {
        personality = personality,
        model = fighter,
        nextCombatAt = 0,
        nextSeekAt = 0,
        despawnAt = now + COMBAT.fighterLifetimeSec,
        engaged = nil,
    }
    table.insert(state.fighters, record)
    print(("[Combat] %s summoned %s (%d active)"):format(player.Name, personality, #state.fighters))
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

    -- SEEK: (re)find the nearest wild on the seek cadence.
    if now >= record.nextSeekAt then
        record.nextSeekAt = now + COMBAT.seekRetargetSec
        local wild, wildRoot = nearestWild(root.Position)
        if wild and wildRoot then
            local dist = (wildRoot.Position - root.Position).Magnitude
            if dist > COMBAT.attackRangeStuds then
                -- Out of range: clear any prior engagement + chase.
                if record.engaged and record.engaged ~= wild and record.engaged.Parent ~= nil then
                    record.engaged:SetAttribute("InCombat", nil)
                end
                record.engaged = nil
                humanoid:MoveTo(wildRoot.Position)
            end
        else
            -- No wild available: idle near the player (gentle wander toward them).
            if record.engaged and record.engaged.Parent ~= nil then
                record.engaged:SetAttribute("InCombat", nil)
            end
            record.engaged = nil
            local character = player.Character
            local charRoot = character and character:FindFirstChild("HumanoidRootPart")
            if charRoot and charRoot:IsA("BasePart") then
                humanoid:MoveTo(charRoot.Position)
            end
        end
    end

    -- ENGAGE + EXCHANGE DAMAGE on the combat cadence.
    if now >= record.nextCombatAt then
        record.nextCombatAt = now + COMBAT.combatTickSec
        local wild, wildRoot = nearestWild(root.Position)
        if wild and wildRoot then
            local dist = (wildRoot.Position - root.Position).Magnitude
            if dist <= COMBAT.attackRangeStuds then
                local wildHumanoid = wild:FindFirstChildWhichIsA("Humanoid")
                if wildHumanoid and wildHumanoid.Health > 0 then
                    -- Engage: the wild yields its movement to combat (wander skips
                    -- it via InCombat) and is told to hold position.
                    wild:SetAttribute("InCombat", true)
                    record.engaged = wild
                    wildHumanoid:MoveTo(wildRoot.Position)

                    local wildPersonality = personalityFromName(wild.Name) or record.personality

                    -- Wild takes the fighter's (scaled) damage.
                    wildHumanoid:TakeDamage(scaledDamage(COMBAT.fighterDamagePerTick, record.personality))
                    -- Fighter takes the wild's (scaled) damage back.
                    humanoid:TakeDamage(scaledDamage(COMBAT.wildDamagePerTick, wildPersonality))

                    if wildHumanoid.Health <= 0 then
                        -- WIN: award + faint + respawn the wild, notify the owner.
                        defeatWild(player, state, wild)
                        record.engaged = nil
                        DemoRemotes.BattleEvent:FireClient(player, {
                            kind = "win",
                            personality = record.personality,
                            coins = COMBAT.winCoins,
                        })
                        print(
                            ("[Combat] %s's %s defeated a wild (+%d coins)"):format(
                                player.Name,
                                record.personality,
                                COMBAT.winCoins
                            )
                        )
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
        local i = #state.fighters
        while i >= 1 do
            local record = state.fighters[i]
            if record and stepFighter(player, state, record, now) then
                removeFighter(state, i)
            end
            i -= 1
        end
    end
end

-- ── Recall (undeploy) ──────────────────────────────────────────────────────
-- Take a DEPLOYED display creature back into the owner's inventory: destroy the
-- model, free its slot, reset the pedestal label, re-add the personality to the
-- inventory, and push fresh InventoryUpdate + CoinUpdate. Owner-only.
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

    local index = target.index
    local slot = state.slots[index]
    if not slot then
        -- Slot already freed (e.g. double-trigger). De-register defensively.
        deployedPromptToSlot[prompt] = nil
        return
    end

    -- De-register the prompt first so a queued re-trigger is ignored.
    deployedPromptToSlot[prompt] = nil

    local personality = slot.personality
    local itemId = slot.id
    if slot.model then
        slot.model:Destroy() -- destroys the prompt with it
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

    -- The stand is empty again: restore its Place prompt so it can be filled.
    addPlacePrompt(index)

    -- SERVER-AUTHORITATIVE inventory add (the creature returns to the bag, still
    -- carrying its persisted roster id so it can be re-deployed later).
    table.insert(state.inventory, {
        id = itemId,
        name = displayName(personality),
        personality = personality,
    })

    pushInventory(player)
    pushCoins(player)
    print("[Recall] " .. player.Name .. " recalled " .. personality .. " from slot " .. index)
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
local function onPromptTriggered(prompt: ProximityPrompt, player: Player)
    if promptToRecord[prompt] then
        handleCatch(prompt, player)
    elseif deployedPromptToSlot[prompt] then
        handleRecall(prompt, player)
    elseif placePromptToStand[prompt] then
        handlePlace(prompt, player)
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
        inventory = {},
        coins = data.coins, -- live float seeded from the persisted whole-coin total
        pending = 0,
        slots = {},
        rateBuckets = {},
        fighters = {}, -- no active fighters on join (ephemeral, not persisted)
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

    -- BAG: every owned roster entry that is NOT currently on a stand.
    for id, entry in data.roster do
        if not deployedIds[id] then
            table.insert(state.inventory, {
                id = id,
                name = displayName(entry.personality),
                personality = entry.personality,
            })
        end
    end

    -- DEPLOYED: re-spawn each deployed creature onto its saved stand + re-attach
    -- the recall prompt. A missing stand/template is skipped gracefully (the
    -- persisted deployment entry is left intact so a later hydrate can retry).
    for id, standIndex in deployedIds do
        local entry = data.roster[id]
        if entry then
            local stand = findStand(standIndex)
            if stand then
                local model = spawnDisplay(entry.personality, stand, standIndex)
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
end

-- ── Wire up ────────────────────────────────────────────────────────────────
-- Single dispatcher routes catch (wild) / recall (deployed) / place (empty) prompts.
ProximityPromptService.PromptTriggered:Connect(onPromptTriggered)
DemoRemotes.DeployToStand.OnServerEvent:Connect(handleDeployToStand)
-- COMBAT (Tahap 2): summon an owned Brainrot as a temporary auto-battling fighter.
DemoRemotes.SummonFighter.OnServerEvent:Connect(handleSummon)
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
