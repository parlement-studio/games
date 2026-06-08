--!strict
-- ServerScriptService/Demo/BrainrotPack.server.luau
--
-- PROTOTYPE: per-type clustered respawns ("packs") for wild Brainrots.
--
-- The 5 personality types each get ONE pack spawn point. Each pack holds
-- `PackConfig.count` (3) brainrots of the SAME type clustered around the
-- pack center. Pack members wander near their own slot, get caught via a
-- pack-local ProximityPrompt, and respawn into the SAME slot after
-- `PackConfig.respawnSec` (5s). The 5 pack centers are placed on a
-- half-circle arc around the Showroom.
--
-- SCOPE — what this script OWNS:
--   * 20 simultaneous wild monsters (5 packs × [3 minion slots + 1 BOSS slot])
--   * per-slot wander AI (Humanoid:MoveTo inside a small radius of the slot)
--   * per-slot respawn timer (5s minion / 30s boss after a slot empties)
--   * a pack-local "Catch" ProximityPrompt on every MINION clone (the boss is
--     NOT catchable — it must be defeated via summon combat)
--   * a 👑 BOSS per pack at the pack center: scaled up, HP/damage multiplied,
--     reward multipliers stamped as attributes for DemoServer's combat loop
--   * per-wild Element roll (element doc E3) + overhead label with the emoji
--   * the CollectionService tag "PackWild" on every clone so DemoServer's
--     summon combat can target pack wilds without coupling to this script
--
-- SCOPE — what this script does NOT touch (intentionally):
--   * the player's roster / inventory (catching a pack member just removes
--     the model and starts the respawn timer — no addBrainrot, no economy,
--     no deploy, no combat, no persistence). The existing DemoServer catch
--     flow is left untouched.
--   * the existing 5 wild brainrots' templates (this script snapshots its
--     OWN template store, ServerStorage.WildPackTemplates, from the live
--     workspace models, then deletes the originals).
--
-- WHY independent from DemoServer: the existing catch path is a
-- catch → roster → deploy → combat → economy chain with a real persistence
-- integration. Wiring a prototype spawner into that would require touching
-- DemoConfig, DemoServer, the promptToRecord map, and the nearestWild search.
-- Out of scope; the user explicitly asked for a respawn prototype.
--
-- ORDERING: this script runs alongside DemoServer. It snapshots the 5
-- originals BEFORE deleting them, so DemoServer's buildTemplates() and
-- buildFighterTemplates() may find fewer source models (they each gracefully
-- skip missing ones). The result: DemoServer's static + fighter template
-- stores end up with at most 0-5 entries depending on which script finished
-- first — harmless because the pack script does not use those stores.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local RunService = game:GetService("RunService")
local PhysicsService = game:GetService("PhysicsService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DemoFolder = Shared:WaitForChild("Demo")
local PackConfig = require(DemoFolder:WaitForChild("PackConfig"))
local RigGrounding = require(DemoFolder:WaitForChild("RigGrounding"))
local ElementConfig = require(Shared:WaitForChild("Config"):WaitForChild("ElementConfig"))
-- ECONOMY SINK: the catch price shown on the prompt (the DemoServer mint
-- bridge applies the same authoritative values).
local CaptureConfig = require(Shared:WaitForChild("Config"):WaitForChild("CaptureConfig"))
local DemoConfig = require(DemoFolder:WaitForChild("DemoConfig"))
local DemoRemotes = require(DemoFolder:WaitForChild("DemoRemotes"))

-- The CollectionService tag DemoServer's summon-combat target search reads.
-- Single decoupling point between this prototype and the combat loop.
local PACK_WILD_TAG = "PackWild"

-- ── Personality resolution (mirrors DemoServer) ─────────────────────────────
-- The name suffix after `creaturePrefix` is the personality (UPPERCASE in the
-- world). Map it case-insensitively to the canonical key in personalityOrder so
-- `Brainrot_LAZY` -> "Lazy" and `Brainrot_lazy` -> "Lazy" both work.
local PREFIX = PackConfig.creaturePrefix
local personalityByUpper: { [string]: string } = {}
for _, key in PackConfig.personalityOrder do
    personalityByUpper[string.upper(key)] = key
end

local function personalityFromName(modelName: string): string?
    if string.sub(modelName, 1, #PREFIX) ~= PREFIX then
        return nil
    end
    local suffix = string.sub(modelName, #PREFIX + 1)
    return personalityByUpper[string.upper(suffix)]
end

local function sourceNameFor(personality: string): string
    return PREFIX .. string.upper(personality)
end

-- ── State ───────────────────────────────────────────────────────────────────
-- One slot = one position in a pack. The pack script owns 5 packs ×
-- `PackConfig.count` slots. Each slot tracks:
--   * `cframe`  — its fixed world CFrame (the slot's anchor on the arc)
--   * `nextAt`  — os.clock() at which a respawn becomes due (0 = ready now)
--   * `nextMoveAt` — wander-AI target re-arm timer
--   * `model`   — the live Model currently occupying the slot, or nil
--   * `personality` — the personality this slot is dedicated to
type Slot = {
    personality: string,
    cframe: CFrame,
    model: Model?,
    nextAt: number,
    nextMoveAt: number,
    -- BOSS slot: one per pack, sits at the PACK CENTER. Scaled model, HP/dmg
    -- multipliers, longer respawn, no catch prompt (must be defeated).
    isBoss: boolean,
    -- Per-slot respawn delay (seconds): PackConfig.respawnSec for minions,
    -- PackConfig.boss.respawnSec for the boss.
    respawnSec: number,
    -- CAPTURE FAIL cooldown: os.clock() until which this wild ignores catch
    -- triggers + wander after a MISSED catch (covers the fail cinematic so a
    -- spam-retry can't double-fire). nil = not cooling down.
    cooldownUntil: number?,
}

local slots: { Slot } = {}

-- Pack-local prompt -> slot map (so a catch routes to OUR handler, not
-- DemoServer's). DemoServer's onPromptTriggered will see a prompt it does
-- not know and ignore it (its own map check fails first).
local packPromptToRecord: { [ProximityPrompt]: Slot } = {}

-- Fast lookup of valid personalities for the source-name iteration.
local isValidPersonality: { [string]: boolean } = {}
for _, key in PackConfig.personalityOrder do
    isValidPersonality[key] = true
end

-- ── Collision group ─────────────────────────────────────────────────────────
-- The originals use the "Brainrot" collision group (added during the dynamic
-- physics pass) so brainrots do not shove each other. Re-register + mirror the
-- "no self-collision" rule here so the freshly-spawned pack clones inherit the
-- same behavior, even if the original setup is gone. Idempotent: Register errors
-- on duplicates and we swallow the error.
pcall(function()
    PhysicsService:RegisterCollisionGroup("Brainrot")
end)
PhysicsService:CollisionGroupSetCollidable("Brainrot", "Brainrot", false)

-- ── Template store ──────────────────────────────────────────────────────────
-- Snapshot each `Brainrot_<P>` from the Workspace into ServerStorage.WildPackTemplates
-- at boot. Strips the existing catch ProximityPrompt + the persona BillboardGui
-- but KEEPS the Humanoid rig (so clones can walk). Idempotent — if the folder
-- already has a template for a personality, skip. Returns the count built.
local function getTemplatesFolder(): Folder
    local folder = ServerStorage:FindFirstChild(PackConfig.templateFolderName)
    if folder and folder:IsA("Folder") then
        return folder
    end
    local created = Instance.new("Folder")
    created.Name = PackConfig.templateFolderName
    created.Parent = ServerStorage
    return created
end

local function buildTemplates(): number
    local folder = getTemplatesFolder()
    local built = 0
    for _, personality in PackConfig.personalityOrder do
        if folder:FindFirstChild(personality) then
            continue -- already snapshotted (idempotent)
        end
        local source = workspace:FindFirstChild(sourceNameFor(personality))
        if not source or not source:IsA("Model") then
            warn("[Pack] missing source " .. sourceNameFor(personality) .. " in Workspace; cannot template")
            continue
        end
        local template = source:Clone()
        template.Name = personality -- canonical key, e.g. "Lazy"
        template:SetAttribute("DemoCaught", nil)
        -- Strip ONLY the catch prompt + persona label; KEEP the Humanoid + parts
        -- so clones can walk and use the built-in health bar. We also want a
        -- fresh Full-Health start (the source may be at 0 if it was fought).
        for _, desc in template:GetDescendants() do
            local isPrompt = desc:IsA("ProximityPrompt")
            local isPersonaLabel = desc:IsA("BillboardGui") and desc.Name == PackConfig.personaLabelName
            if isPrompt or isPersonaLabel then
                desc:Destroy()
            end
        end
        local humanoid = template:FindFirstChildWhichIsA("Humanoid")
        if humanoid then
            -- Reset Health to MaxHealth on the template so every clone starts
            -- at full HP. (MaxHealth itself is preserved from the source rig;
            -- only Health is forced to the cap.)
            humanoid.Health = humanoid.MaxHealth
        end
        template.Parent = folder
        built += 1
    end
    return built
end

-- Remove the 5 originals from the Workspace so the pack's clones are the only
-- wild brainrots the player sees. Idempotent — missing models are skipped.
local function removeOriginals(): number
    local removed = 0
    for _, personality in PackConfig.personalityOrder do
        local source = workspace:FindFirstChild(sourceNameFor(personality))
        if source then
            source:Destroy()
            removed += 1
        end
    end
    return removed
end

-- ── Spawn points ────────────────────────────────────────────────────────────
-- One invisible Part per personality in `Workspace.<PackConfig.spawnFolderName>`,
-- placed on a half-circle arc around the Showroom. Each Part is tagged with
-- `Attribute("BrainrotType", "<P>")` so the slot table can be rebuilt from the
-- scene if needed. Returns the array of marker Parts.
local function buildSpawnPoints(): { Part }
    -- Place a folder at the showroom so the markers are visually grouped.
    local folder = workspace:FindFirstChild(PackConfig.spawnFolderName)
    if folder and not folder:IsA("Folder") then
        folder:Destroy()
        folder = nil
    end
    if not folder then
        folder = Instance.new("Folder")
        folder.Name = PackConfig.spawnFolderName
        folder.Parent = workspace
    end

    -- Arc center = Showroom pivot (Z = 26 in the current build; works for any
    -- showroom position). If the showroom is missing, fall back to the world
    -- origin so the prototype still runs.
    local arcCenter: Vector3
    local showroom = workspace:FindFirstChild("Showroom")
    if showroom and showroom:IsA("Model") then
        arcCenter = showroom:GetPivot().Position
    else
        warn("[Pack] Showroom missing; falling back to (0, 0, 0) as the arc center")
        arcCenter = Vector3.zero
    end
    local arcY = arcCenter.Y + PackConfig.packCenterYOffset

    local markers: { Part } = {}
    local n = #PackConfig.personalityOrder
    local angleStart = math.rad(PackConfig.arcAngleStartDeg)
    local angleEnd = math.rad(PackConfig.arcAngleEndDeg)
    -- Even spacing across the arc; n=1 lands at the midpoint.
    for i, personality in PackConfig.personalityOrder do
        local t = if n == 1 then 0.5 else (i - 1) / (n - 1)
        local angle = angleStart + (angleEnd - angleStart) * t
        local offset =
            Vector3.new(math.cos(angle) * PackConfig.arcRadiusStuds, 0, math.sin(angle) * PackConfig.arcRadiusStuds)
        local pos = Vector3.new(arcCenter.X + offset.X, arcY, arcCenter.Z + offset.Z)

        local marker = Instance.new("Part")
        marker.Name = "PackCenter_" .. personality
        marker.Anchored = true
        marker.CanCollide = false
        marker.Transparency = 1
        marker.Size = Vector3.one
        marker.CFrame = CFrame.new(pos)
        marker:SetAttribute("BrainrotType", personality)
        marker.Parent = folder
        markers[#markers + 1] = marker
    end
    return markers
end

-- ── Slot geometry ───────────────────────────────────────────────────────────
-- For a given pack center, return 3 slot CFrames arranged as a small triangle
-- at `PackConfig.slotSpreadStuds` from the center, on the XZ plane. The
-- triangle is oriented so it sits on the ground (no Y component beyond the
-- center's Y). Reused by the per-pack init pass.
local function computeSlotCFrames(center: CFrame, count: number): { CFrame }
    local frames: { CFrame } = {}
    local r = PackConfig.slotSpreadStuds
    for i = 0, count - 1 do
        -- Evenly distribute `count` slots around the pack center on the XZ plane.
        -- For 3 slots this lands at 0°, 120°, 240°; the cluster is symmetric
        -- around the center and reads as a "pack".
        local angle = (i / count) * math.pi * 2
        local dx = math.cos(angle) * r
        local dz = math.sin(angle) * r
        local pos = center.Position + Vector3.new(dx, 0, dz)
        frames[#frames + 1] = CFrame.new(pos)
    end
    return frames
end

-- ── Overhead label ──────────────────────────────────────────────────────────
-- The pack templates strip the authored PersonaLabel, so every pack wild gets
-- its own tiny billboard: "<PERSONALITY> <emoji>" for minions and
-- "👑 <PERSONALITY> BOSS <emoji>" for the boss. The element emoji on the BOSS
-- is the counter-pick telegraph (element doc: boss element is shown).
local function elementEmoji(element: any): string
    local display = ElementConfig.display[element]
    return if display then display.emoji else ""
end

local function addPackLabel(anchor: BasePart, slot: Slot, element: string)
    local labelCfg = PackConfig.label
    if not labelCfg.enabled then
        return
    end
    local billboard = Instance.new("BillboardGui")
    billboard.Name = "PackLabel"
    billboard.Size = UDim2.fromOffset(labelCfg.widthPx, labelCfg.heightPx)
    local offsetY = labelCfg.offsetYStuds + (if slot.isBoss then labelCfg.bossExtraYStuds else 0)
    billboard.StudsOffsetWorldSpace = Vector3.new(0, offsetY, 0)
    billboard.AlwaysOnTop = true
    local text = Instance.new("TextLabel")
    text.BackgroundTransparency = 1
    text.Size = UDim2.fromScale(1, 1)
    text.Font = Enum.Font.GothamBold
    text.TextScaled = true
    if slot.isBoss then
        text.TextColor3 = Color3.fromRGB(255, 96, 64)
        text.Text = ("👑 %s BOSS %s"):format(string.upper(slot.personality), elementEmoji(element))
    else
        text.TextColor3 = Color3.fromRGB(235, 235, 235)
        text.Text = ("%s %s"):format(string.upper(slot.personality), elementEmoji(element))
    end
    text.Parent = billboard
    billboard.Parent = anchor
end

-- ── Per-slot spawn ──────────────────────────────────────────────────────────
-- Clone the personality's template, drop it in from `PackConfig.spawnDropStuds`
-- above the slot (so physics has a clean fall), mirror the original's collision
-- group / WalkSpeed, and return the parented Model. The slot's `model` field is
-- updated by the caller. Returns nil on a missing template.
--
-- BOSS slots additionally: Model:ScaleTo(boss.scale), Max HP * boss.hpMult,
-- WalkSpeed * boss.walkSpeedMult, and the reward/damage multipliers stamped as
-- attributes for DemoServer's combat loop.
--
-- EVERY pack wild gets: a server-side Element roll (element doc E3) stored as
-- an attribute (combat reads it for elementMod), a Personality attribute (the
-- model name `Pack_<P>` does not match DemoServer's `Brainrot_` prefix parser),
-- the PACK_WILD_TAG CollectionService tag (combat target discovery), and an
-- overhead label.
local function spawnSlot(slot: Slot, templateFolder: Folder): Model?
    local template = templateFolder:FindFirstChild(slot.personality)
    if not template or not template:IsA("Model") then
        warn("[Pack] no template for " .. slot.personality .. "; skipping slot")
        return nil
    end
    local clone = template:Clone()
    clone.Name = (if slot.isBoss then "PackBoss_" else "Pack_") .. slot.personality

    -- Drop in via physics: lift the spawn point by `spawnDropStuds` so the
    -- HumanoidRootPart starts ABOVE the ground and falls into place. Final Y
    -- is decided by physics (no hard-coded Position.Y land).
    local root = clone.PrimaryPart or clone:FindFirstChild("HumanoidRootPart")
    if not root or not root:IsA("BasePart") then
        clone:Destroy()
        warn("[Pack] template " .. slot.personality .. " has no HumanoidRootPart")
        return nil
    end
    root.CFrame = slot.cframe + Vector3.new(0, PackConfig.spawnDropStuds, 0)

    -- Mirror the dynamic-physics config the originals were given: collide,
    -- non-anchored, PlatformStand so they don't run, named collision group so
    -- they don't shove each other.
    clone.PrimaryPart = root
    for _, desc in clone:GetDescendants() do
        if desc:IsA("BasePart") then
            desc.CollisionGroup = "Brainrot"
        end
    end
    -- BOSS: scale the whole rig up BEFORE placement so the drop height and
    -- label offset see the final size. NOTE: Model:ScaleTo is ABSOLUTE (vs the
    -- model's authored size) and the snapshotted templates already carry a
    -- non-1 base scale (~1.87 from the original world models), so multiply the
    -- CURRENT scale — `ScaleTo(boss.scale)` alone only grew the boss ~1.07x.
    if slot.isBoss then
        clone:ScaleTo(clone:GetScale() * PackConfig.boss.scale)
    end

    local humanoid = clone:FindFirstChildWhichIsA("Humanoid")
    if humanoid then
        local walkSpeed = PackConfig.walkSpeed * (if slot.isBoss then PackConfig.boss.walkSpeedMult else 1)
        humanoid.WalkSpeed = walkSpeed
        -- BUGFIX (fall-through): PlatformStand=true DISABLES the engine's
        -- humanoid ground support. The template's parts are all
        -- CanCollide=false (standard humanoid rig), so under PlatformStand
        -- nothing collided and every clone fell through the baseplate to
        -- FallenPartsDestroyHeight (-500), despawned, respawned, and fell
        -- again — the packs were never visible at their spots. Normal humanoid
        -- states make the engine support the root, exactly how the original
        -- wilds stand. (Humanoid:MoveTo also only walks when NOT
        -- PlatformStanding, so the wander AI needs this too.)
        humanoid.PlatformStand = false
        -- GROUNDING phase 1: spawn-time HipHeight from the (already scaled)
        -- geometry so the blob lands near the floor instead of hovering
        -- ~0.75 studs (boss: ~1.5 after 2x scale) in the air. Phase 2
        -- (settleToGround, scheduled after parenting below) measures + removes
        -- the residual pose gap.
        humanoid.HipHeight = RigGrounding.initialHipHeight(clone, root)
        -- BOSS: multiply the rig's Max HP (ScaleTo does not touch Humanoid HP).
        if slot.isBoss then
            humanoid.MaxHealth = humanoid.MaxHealth * PackConfig.boss.hpMult
            humanoid.Health = humanoid.MaxHealth
        end
        -- Lock the Neck so the head stays rigid during the drop + wander.
        local neck = root:FindFirstChild("Neck")
        if neck and neck:IsA("Motor6D") then
            neck.MaxVelocity = 0
        end
    end

    -- ELEMENT (element doc E3): every pack wild rolls its element server-side
    -- at spawn. Combat reads the attribute for elementMod both directions.
    local element = ElementConfig.rollElement()
    clone:SetAttribute("Element", element)
    -- Personality attribute: `Pack_<P>` / `PackBoss_<P>` names do not match
    -- DemoServer's `Brainrot_` prefix parser, so combat reads this instead.
    clone:SetAttribute("Personality", slot.personality)
    -- Combat multipliers (read by DemoServer; default 1 when absent).
    if slot.isBoss then
        clone:SetAttribute("IsBoss", true)
        clone:SetAttribute("DamageMult", PackConfig.boss.damageMult)
        clone:SetAttribute("WinCoinsMult", PackConfig.boss.winCoinsMult)
        clone:SetAttribute("XpMult", PackConfig.boss.xpMult)
    end
    -- Target-discovery tag for DemoServer's summon combat (decoupled).
    CollectionService:AddTag(clone, PACK_WILD_TAG)

    -- Overhead label (the snapshot stripped the authored PersonaLabel).
    local labelAnchor = clone:FindFirstChild("Head")
    local anchorPart = if labelAnchor and labelAnchor:IsA("BasePart") then labelAnchor else root
    addPackLabel(anchorPart, slot, element)

    -- Server owns the network so a nearby client can't tamper with the clone.
    pcall(function()
        root:SetNetworkOwner(nil)
    end)

    clone.Parent = workspace
    -- GROUNDING phase 2: after the drop settles, measure the real remaining
    -- hover gap with a monster-transparent raycast and remove it.
    if humanoid then
        RigGrounding.settleToGround(clone, humanoid)
    end
    slot.model = clone
    -- Wander is due on the next AI tick (no immediate move on spawn).
    slot.nextMoveAt = 0
    return clone
end

-- ── Catch prompt ────────────────────────────────────────────────────────────
-- Attach a pack-local "Hold F to Catch" ProximityPrompt to the clone's head
-- (or PrimaryPart fallback). Registers the prompt -> slot in OUR map only.
-- DemoServer's onPromptTriggered will see a prompt it does not know and ignore
-- it; the pack's listener will route to handlePackCatch.
local function addPackCatchPrompt(model: Model, slot: Slot): boolean
    local head = model:FindFirstChild("Head")
    local anchor = if head and head:IsA("BasePart")
        then head
        else (model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart"))
    if not anchor then
        return false
    end
    local prompt = Instance.new("ProximityPrompt")
    prompt.Name = "PackCatchPrompt"
    prompt.ActionText = PackConfig.catchActionText
    -- Price hint on the prompt: ITEM MODE shows the net cost ("HYPER · 🕸️1"),
    -- legacy mode shows coins. The server authorizes every catch either way.
    if DemoConfig.captureUsesItems then
        prompt.ObjectText = ("%s · 🕸️1"):format(string.upper(slot.personality))
    else
        prompt.ObjectText = ("%s · %d🪙"):format(string.upper(slot.personality), CaptureConfig.captureCostCoins)
    end
    prompt.KeyboardKeyCode = Enum.KeyCode.F
    prompt.HoldDuration = PackConfig.catchHoldSec
    prompt.MaxActivationDistance = PackConfig.catchDistance
    prompt.RequiresLineOfSight = false
    prompt.Parent = anchor
    packPromptToRecord[prompt] = slot
    return true
end

-- Catch handler. A pack catch now MINTS a real roster entry through
-- DemoServer's audited path via the ServerStorage.PackCatchMint
-- BindableFunction (persist-FIRST: if the mint is rejected — roster full /
-- profile not loaded / rate-limited — the catch ABORTS and the wild stays).
-- The minted entry INHERITS the element shown on the wild's overhead label.
-- Falls back to the old isolated despawn-only behavior if the bridge is
-- absent (DemoServer not running).
-- A MISSED catch (catch-rate roll failed server-side). The roster owner has
-- already charged the attempt + toasted "Lolos"; here we keep the wild in the
-- world but briefly FREEZE it so the fail cinematic's net-bounce reads cleanly
-- and a spam-retry can't double-fire, then restore it after the cooldown. The
-- catch prompt is NEVER removed — the wild stays catchable for the next try.
local function handlePackCatchFail(slot: Slot, player: Player, element: any)
    local model = slot.model
    if not model or model.Parent == nil then
        return
    end
    local catchCfg = DemoConfig.catch
    local cooldown = (catchCfg and catchCfg.failCooldownSec) or 1.5
    slot.cooldownUntil = os.clock() + cooldown

    local humanoid = model:FindFirstChildWhichIsA("Humanoid")
    if humanoid then
        humanoid:MoveTo(model:GetPivot().Position)
        humanoid.WalkSpeed = 0
        humanoid.AutoRotate = false
    end

    local cine = DemoConfig.catchCinematic
    if cine and cine.enabled then
        DemoRemotes.CatchCinematic:FireClient(player, {
            model = model,
            personality = slot.personality,
            element = element,
            success = false,
        })
    end

    -- Un-freeze after the cooldown (only if this exact wild is still around —
    -- it may have been defeated in combat / respawned in the meantime).
    task.delay(cooldown, function()
        if slot.model == model and model.Parent then
            local h = model:FindFirstChildWhichIsA("Humanoid")
            if h then
                h.WalkSpeed = PackConfig.walkSpeed * (if slot.isBoss then PackConfig.boss.walkSpeedMult else 1)
                h.AutoRotate = true
            end
        end
        if slot.cooldownUntil and os.clock() >= slot.cooldownUntil then
            slot.cooldownUntil = nil
        end
    end)
end

local function handlePackCatch(prompt: ProximityPrompt, player: Player)
    local slot = packPromptToRecord[prompt]
    if not slot then
        return -- not one of our prompts
    end
    -- Guard against a re-trigger on a model that's already been queued for
    -- respawn (slot.model might already be nil or the model might be marked).
    if not slot.model or slot.model.Parent == nil then
        return -- already gone; the respawn loop will refill
    end
    -- Ignore triggers while this wild is mid fail-cinematic (cooldown active).
    if slot.cooldownUntil and os.clock() < slot.cooldownUntil then
        return
    end

    -- RESOLVE the attempt through the roster owner: affordability + the hidden
    -- rarity roll + the catch-rate success roll all happen SERVER-SIDE there.
    -- The result table tells us how to treat the world model. The element is
    -- snapshotted from the wild's label BEFORE any mutation.
    local element = slot.model:GetAttribute("Element")
    local outcome = "success"
    local mint = ServerStorage:FindFirstChild("PackCatchMint")
    if mint and mint:IsA("BindableFunction") then
        local invoked, res = pcall(function()
            return mint:Invoke(player, slot.personality, element)
        end)
        if not invoked then
            warn("[Pack] PackCatchMint invoke failed: " .. tostring(res))
            return
        end
        -- Tolerate the legacy boolean return as well as the new result table.
        if type(res) == "table" then
            outcome = tostring(res.outcome)
        elseif res == true then
            outcome = "success"
        else
            outcome = "rejected"
        end
    end

    if outcome == "rejected" then
        return -- nothing minted/charged (roster full / can't afford / limited): wild stays
    end
    if outcome == "fail" then
        handlePackCatchFail(slot, player, element)
        return -- MISSED: wild kept in the world, fail cinematic plays
    end

    -- SUCCESS. Detach the model from the live loops IMMEDIATELY (so wander/respawn
    -- and a re-trigger all treat it as gone) but DEFER the destroy: the catcher
    -- plays a cinematic on it first.
    local caughtModel = slot.model
    slot.model = nil
    -- Tear the prompt out of our map; ProximityPromptService retains a stale
    -- reference until the prompt is destroyed, which happened with the model.
    packPromptToRecord[prompt] = nil
    -- Arm the respawn timer. The respawn loop checks `slot.model == nil` AND
    -- `os.clock() >= slot.nextAt`; setting nextAt = now + delay starts the
    -- countdown. (Per-slot delay: minions vs boss differ — though a boss never
    -- reaches this handler since it gets no catch prompt.)
    slot.nextAt = os.clock() + slot.respawnSec

    local cine = DemoConfig.catchCinematic
    if cine and cine.enabled and caughtModel and caughtModel.Parent then
        -- FREEZE the wild so it holds still for the sequence: kill its AI inputs
        -- (anchor parts, stop the Humanoid) and strip the catch prompt + label
        -- so nothing re-triggers or floats during the shot.
        local humanoid = caughtModel:FindFirstChildWhichIsA("Humanoid")
        if humanoid then
            humanoid:MoveTo(caughtModel:GetPivot().Position)
            humanoid.WalkSpeed = 0
            humanoid.AutoRotate = false
        end
        for _, desc in caughtModel:GetDescendants() do
            if desc:IsA("ProximityPrompt") or desc:IsA("BillboardGui") then
                desc:Destroy()
            elseif desc:IsA("BasePart") then
                desc.Anchored = true
            end
        end
        -- Tell the CATCHER to play the cinematic on this exact model.
        DemoRemotes.CatchCinematic:FireClient(player, {
            model = caughtModel,
            personality = slot.personality,
            element = element,
            success = true,
        })
        -- Destroy after the client has had the full hold window (the client
        -- sequence is shorter than holdSec — see DemoConfig.catchCinematic).
        task.delay(cine.holdSec, function()
            if caughtModel and caughtModel.Parent then
                caughtModel:Destroy()
            end
        end)
    else
        caughtModel:Destroy()
    end
    print(("[Pack] %s caught %s — respawn in %ds"):format(player.Name, slot.personality, slot.respawnSec))
end

-- ── Wander AI ───────────────────────────────────────────────────────────────
-- One wander step per slot, gated by the slot's own `nextMoveAt` (so each pack
-- member pauses between moves independently). When due, pick a random point on
-- the XZ plane within `wanderRadiusStuds` of the slot and Humanoid:MoveTo it.
-- This mirrors the existing BrainrotAI.wild loop but is keyed by slot, not by
-- a top-level creature name list — so pack members are first-class roamers.
local function stepWander(now: number)
    for _, slot in slots do
        local model = slot.model
        if not model or model.Parent == nil then
            continue -- respawn loop will refill
        end
        if slot.cooldownUntil and now < slot.cooldownUntil then
            continue -- frozen mid fail-cinematic; don't issue wander moves
        end
        if now < slot.nextMoveAt then
            continue -- still pausing
        end
        local humanoid = model:FindFirstChildWhichIsA("Humanoid")
        local root = model.PrimaryPart
        if not humanoid or not root then
            continue -- shouldn't happen for a freshly-spawned clone
        end
        if humanoid.Health <= 0 then
            continue -- let the respawn loop see 0-HP and tear it down
        end
        if model:GetAttribute("InCombat") == true then
            continue -- engaged by a summoned fighter (DemoServer combat owns
            -- its movement: the engage path issues a hold-position MoveTo);
            -- wandering here would fight that command every tick
        end
        -- Uniform sample in a disc of the slot's wander radius (bosses pace a
        -- smaller area so they read as anchored to the pack).
        local radius = PackConfig.wanderRadiusStuds * (if slot.isBoss then PackConfig.boss.wanderRadiusMult else 1)
        local angle = math.random() * math.pi * 2
        local dist = math.sqrt(math.random()) * radius
        local target = slot.cframe.Position + Vector3.new(math.cos(angle) * dist, 0, math.sin(angle) * dist)
        humanoid:MoveTo(target)
        -- Re-arm the per-slot pause so this member does not move every tick.
        local pause = PackConfig.wanderPauseMinSec
            + math.random() * (PackConfig.wanderPauseMaxSec - PackConfig.wanderPauseMinSec)
        slot.nextMoveAt = now + pause
    end
end

-- ── Respawn loop ────────────────────────────────────────────────────────────
-- The template folder CACHED at init (set in initPacks) so the heartbeat
-- respawn path does no per-tick folder lookups. nil until init finishes; the
-- respawn sweep skips (and retries next sweep) while it is unset.
local cachedTemplateFolder: Folder? = nil

-- One respawn step. For every slot, if the model is missing OR the model
-- exists but its Humanoid is at 0 HP (defeated in combat / fell off the map),
-- ARM the slot's respawn timer once (tearing the corpse down immediately), then
-- spawn a fresh clone when the timer is due. The two-phase shape means a
-- combat DEATH waits the same per-slot delay as a catch (it used to respawn
-- instantly because nextAt was still 0). Uses the CACHED template folder
-- captured at init (see initPacks) so the heartbeat does no per-tick lookups.
local function stepRespawn(now: number)
    local templateFolder = cachedTemplateFolder
    if not templateFolder then
        return -- init not finished yet; the next sweep retries
    end
    for _, slot in slots do
        local needsRespawn = false
        local model = slot.model
        if not model or model.Parent == nil then
            needsRespawn = true
        else
            local humanoid = model:FindFirstChildWhichIsA("Humanoid")
            if humanoid and humanoid.Health <= 0 then
                needsRespawn = true
            end
        end
        if not needsRespawn then
            continue
        end
        -- Phase 1: first sweep that SEES the empty/dead slot arms the timer +
        -- removes the corpse. nextAt == 0 means "not armed yet" (the catch
        -- handler arms it itself before clearing slot.model).
        if slot.nextAt == 0 then
            if model and model.Parent ~= nil then
                model:Destroy()
            end
            slot.model = nil
            slot.nextAt = now + slot.respawnSec
            continue
        end
        -- Phase 2: timer armed — wait it out, then spawn.
        if now < slot.nextAt then
            continue -- still waiting
        end
        slot.model = nil
        slot.nextAt = 0
        local fresh = spawnSlot(slot, templateFolder)
        -- Minions are catchable; the BOSS is not (it must be defeated —
        -- PackConfig.boss.catchable gates a future change of heart).
        if fresh and (not slot.isBoss or PackConfig.boss.catchable) then
            addPackCatchPrompt(fresh, slot)
        end
    end
end

-- ── Heartbeat wiring ───────────────────────────────────────────────────────
-- Two independent accumulators keep the AI cadence (aiTickSec) and the
-- respawn cadence (cheap at 0.5s) frame-rate independent. Both are
-- `function(dt) accum += dt; if accum >= period then ...` patterns.
local wanderAccum = 0
local respawnAccum = 0
local RESPAWN_PERIOD = 0.5

local function onHeartbeat(dt: number)
    local now = os.clock()
    wanderAccum += dt
    if wanderAccum >= PackConfig.aiTickSec then
        wanderAccum = 0
        stepWander(now)
    end
    respawnAccum += dt
    if respawnAccum >= RESPAWN_PERIOD then
        respawnAccum = 0
        stepRespawn(now)
    end
end

-- ── Lifecycle ───────────────────────────────────────────────────────────────
-- 1. Snapshot the 5 originals into the template store.
-- 2. Remove the originals (the pack's clones will be the only wilds).
-- 3. Build the 5 pack-center markers on the arc.
-- 4. For each pack, compute the slot CFrames and add an entry to `slots`.
-- 5. Spawn the initial 15 clones (3 per pack) + attach a catch prompt each.
-- 6. Connect the heartbeat + catch listener.
-- Each step logs a [Pack] line so the operator can see the boot sequence.
local function initPacks()
    -- 1) Templates
    local built = buildTemplates()
    print(("[Pack] templates ready — %d in ServerStorage.%s"):format(built, PackConfig.templateFolderName))

    -- 1b) ORDERING FIX: wait until DemoServer has snapshotted its OWN template
    -- stores (static display + RIGGED fighter templates) from the same source
    -- models BEFORE we delete them. Without this, whichever script lost the
    -- race booted with 0 templates — summoning was impossible ("no Workspace
    -- source to fighter-template" warnings) and deploys had nothing to clone.
    -- Bounded wait so a missing DemoServer can never deadlock the prototype.
    do
        local deadline = os.clock() + 10
        local fighterFolder = ServerStorage:FindFirstChild("FighterTemplates")
        while os.clock() < deadline do
            fighterFolder = fighterFolder or ServerStorage:FindFirstChild("FighterTemplates")
            if fighterFolder and #fighterFolder:GetChildren() >= #PackConfig.personalityOrder then
                break
            end
            task.wait(0.25)
        end
        local count = if fighterFolder then #fighterFolder:GetChildren() else 0
        print(
            ("[Pack] DemoServer fighter templates seen: %d (waited for snapshot before removing originals)"):format(
                count
            )
        )
    end

    -- 2) Remove originals (after snapshotting, so DemoServer can also use them
    -- if it races us here — missing source = graceful skip).
    local removed = removeOriginals()
    print(("[Pack] removed %d original wild monsters from Workspace"):format(removed))

    -- 3) Pack centers on the arc
    local markers = buildSpawnPoints()
    print(("[Pack] %d pack centers placed on the arc"):format(#markers))

    -- 4-5) Build slots + spawn initial clones + attach prompts. Cache the
    -- template folder for the respawn loop so it does no per-tick lookups.
    local templateFolder = getTemplatesFolder()
    cachedTemplateFolder = templateFolder
    local initialSpawned = 0
    for _, marker in markers do
        local personality = marker:GetAttribute("BrainrotType")
        if not personality or not isValidPersonality[personality] then
            continue
        end
        local slotCFrames = computeSlotCFrames(marker.CFrame, PackConfig.count)
        for _, slotCFrame in slotCFrames do
            local slot: Slot = {
                personality = personality,
                cframe = slotCFrame,
                model = nil,
                nextAt = 0, -- ready to spawn now
                nextMoveAt = 0,
                isBoss = false,
                respawnSec = PackConfig.respawnSec,
            }
            slots[#slots + 1] = slot
            local fresh = spawnSlot(slot, templateFolder)
            if fresh then
                addPackCatchPrompt(fresh, slot)
                initialSpawned += 1
            end
        end

        -- 👑 BOSS slot: one per pack, at the PACK CENTER (the minion triangle
        -- rings around it). Longer respawn, no catch prompt (must be defeated).
        if PackConfig.boss.enabled then
            local bossSlot: Slot = {
                personality = personality,
                cframe = marker.CFrame,
                model = nil,
                nextAt = 0,
                nextMoveAt = 0,
                isBoss = true,
                respawnSec = PackConfig.boss.respawnSec,
            }
            slots[#slots + 1] = bossSlot
            local boss = spawnSlot(bossSlot, templateFolder)
            if boss then
                if PackConfig.boss.catchable then
                    addPackCatchPrompt(boss, bossSlot)
                end
                initialSpawned += 1
            end
        end
    end

    print(
        ("[Pack] ready — %d monsters (incl. %d bosses) in %d packs"):format(
            initialSpawned,
            if PackConfig.boss.enabled then #markers else 0,
            #markers
        )
    )

    -- 6) Wire up the heartbeat + catch listener. Both are best-effort — if
    -- something blows up here, the slots are already in the world.
    RunService.Heartbeat:Connect(onHeartbeat)
    ProximityPromptService.PromptTriggered:Connect(handlePackCatch)
end

-- Run the init now. WaitForChild covers the case where Rojo is still syncing
-- the script (PackConfig may not be ready the instant the script runs).
task.spawn(initPacks)
