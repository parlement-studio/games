--!strict
-- ServerScriptService/PersonalityBootstrap.server.luau
--
-- Lifecycle WIRING for the Personality System (Creative Pillar #2), per
-- design/gdd/personality-gdd.md (v1.1) §5 / E5 / E6. Mirrors the style of
-- PlayerDataBootstrap.server.luau: this Script ONLY wires things together — no
-- game logic lives here.
--
-- Wiring:
--   boot                          -> PersonalityConfig.validate() once (E6, log)
--   PlayerDataService.DataLoaded  -> validateOrRepair every roster entry (E5)
--   PersonalityChanged signal     -> PersonalityRevealed remote (thin S->C)
--   (PersonalityStateChanged / PersonalityMomentBurst remotes are registered as
--    thin pass-throughs; full UI is consumer-side, kept minimal per §5.2.)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local HttpService = game:GetService("HttpService")

local PersonalityConfig = require(ReplicatedStorage.Shared.Config.PersonalityConfig)
local PersonalityService = require(ServerStorage.Personality.PersonalityService)
local PlayerDataService = require(ServerStorage.PlayerData.PlayerDataService)

-- Structured logger (replace with the project logger when one exists; never raw
-- print for incidents). Routed into PersonalityService.
local function structuredLog(event: string, payload: { [string]: any })
    warn(string.format("[Personality] %s %s", event, HttpService:JSONEncode(payload)))
end
PersonalityService.setLogger(structuredLog)

-- (1) Validate the trait table ONCE at boot (E6). The sanitized weights are
-- logged; PersonalityService caches them for every roll so the roller and the
-- displayed-odds UI always read identical, validated weights.
local validatedWeights = PersonalityConfig.validate(structuredLog)
structuredLog("personality_config_validated", { weights = validatedWeights })

-- ── Thin Server -> Client remotes (§5.2) ────────────────────────────────────
-- Registered here as a pass-through surface; consumer UI (Capture reveal, base
-- visuals, Moment pop-ups) listens client-side. Full UI is NOT this system's job.
local function ensureRemote(name: string): RemoteEvent
    local existing = ReplicatedStorage:FindFirstChild(name)
    if existing and existing:IsA("RemoteEvent") then
        return existing
    end
    local remote = Instance.new("RemoteEvent")
    remote.Name = name
    remote.Parent = ReplicatedStorage
    return remote
end

local personalityRevealed = ensureRemote("PersonalityRevealed")
local personalityStateChanged = ensureRemote("PersonalityStateChanged")
local personalityMomentBurst = ensureRemote("PersonalityMomentBurst")

-- (3) Load-time repair (E5): when a profile loads, walk the roster and repair
-- any missing/invalid personality enum. validateOrRepair is a no-op for valid
-- entries, so this is cheap on a healthy profile.
PlayerDataService.DataLoaded:Connect(function(player: Player, data)
    if data == nil or type(data.roster) ~= "table" then
        return
    end
    for id, entry in pairs(data.roster) do
        local repaired, personality = PersonalityService.validateOrRepair(player, id, entry)
        if repaired then
            -- E5: the player simply sees a (re)assigned trait via the reveal UI.
            personalityRevealed:FireClient(player, { id = id, personality = personality })
        end
    end
end)

-- Pass-through: a committed reroll / repair -> client reveal (§5.2). old=nil
-- marks a (re)assignment from repair; a non-nil old is a reroll result.
PersonalityService.PersonalityChanged:Connect(function(payload)
    -- payload.id may belong to any player; reveal is fired to all so a client
    -- whose roster includes the id can play the beat. (Per-owner targeting is a
    -- consumer-UI refinement; the contract here is the thin pass-through.)
    personalityRevealed:FireAllClients({ id = payload.id, personality = payload.newPersonality })
end)

-- Pass-through: a Moment occurrence -> client burst (§5.2). The Moment System
-- (#12) formats; this only forwards the typed payload.
PersonalityService.PersonalityMoment:Connect(function(payload)
    personalityMomentBurst:FireAllClients({
        id = payload.id,
        momentType = payload.momentType,
        payload = payload.payload,
    })
end)

-- Pass-through: a Walkout start -> client state visual (§5.2 / §6.4). Idle (#3)
-- owns un-pausing producers; this only surfaces the state for the protest-sign
-- visual.
PersonalityService.WalkoutStarted:Connect(function(payload)
    personalityStateChanged:FireAllClients({
        id = payload.id,
        state = PersonalityService.STATE_WALKOUT,
        draggedIds = payload.draggedIds,
    })
end)
