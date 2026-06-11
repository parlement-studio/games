--!strict
-- ServerScriptService/World/TravelBootstrap.server.luau
--
-- Wires the cross-place TRAVEL feature. SAME script runs in every place; it gates
-- on WorldConfig.currentPlaceKind():
--   overworld -> attach the BunkBed prompt (Camping Cabin) that offers travel to
--                the player's PRIVATE Sanctuary.
--   kandang   -> spawn the return portal pad that offers travel back to Overworld.
--
-- SECURITY: the player NEVER tells the server where to go. Triggering a prompt
-- sets pendingTravel[player] = <server-chosen destination> and opens the confirm
-- modal; the client's ConfirmTravel just says "yes" and the server teleports the
-- pending destination. A spoofed ConfirmTravel with no pending = no-op.

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local Workspace = game:GetService("Workspace")

local WorldConfig = require(ReplicatedStorage.Shared.Config.WorldConfig)
local TravelConfig = require(ReplicatedStorage.Shared.Config.TravelConfig)
local TravelRemotes = require(ReplicatedStorage.Shared.World.TravelRemotes)
local WorldService = require(ServerScriptService.World.WorldService)
-- Reuse the existing Moment toast channel for travel feedback (present in every
-- place — DemoServer creates it on boot). Keeps WorldService UI-agnostic.
local DemoRemotes = require(ReplicatedStorage.Shared.Demo.DemoRemotes)

WorldService.setNotifier(function(player: Player, text: string)
    DemoRemotes.Moment:FireClient(player, { kind = "info", text = text })
end)

-- Server-authoritative pending destination per player (set on prompt trigger).
local pendingTravel: { [Player]: string } = {}

local function openConfirm(player: Player, destKey: string)
    local destCfg = TravelConfig.destinations[destKey]
    if destCfg == nil then
        return
    end
    pendingTravel[player] = destKey
    TravelRemotes.OpenTravelConfirm:FireClient(player, {
        destination = destKey,
        title = destCfg.title,
        body = destCfg.body,
        confirmText = destCfg.confirmText,
    })
end

-- ── BunkBed prompt (overworld) ───────────────────────────────────────────────
local function setupBunkBedPrompt(): boolean
    local cfg = TravelConfig.bunkBed
    local cabin = Workspace:FindFirstChild(cfg.modelName) or Workspace:WaitForChild(cfg.modelName, 10)
    if cabin == nil then
        warn("[Travel][overworld] cabin model missing: " .. cfg.modelName)
        return false
    end
    local bed = cabin:FindFirstChild(cfg.bedName, true)
    if bed == nil or not bed:IsA("Model") then
        warn("[Travel][overworld] BunkBed model missing inside " .. cfg.modelName)
        return false
    end

    -- Invisible host part at the bed pivot (idempotent across reboots).
    local host = bed:FindFirstChild(cfg.promptHostName)
    if host == nil or not host:IsA("BasePart") then
        local part = Instance.new("Part")
        part.Name = cfg.promptHostName
        part.Anchored = true
        part.CanCollide = false
        part.CanQuery = false
        part.CanTouch = false
        part.Transparency = 1
        part.Size = Vector3.new(1, 1, 1)
        part.CFrame = bed:GetPivot() * CFrame.new(0, cfg.promptYOffset, 0)
        part.Parent = bed
        host = part
    end

    local prompt = host:FindFirstChildOfClass("ProximityPrompt")
    if prompt == nil then
        local p = Instance.new("ProximityPrompt")
        p.ActionText = cfg.actionText
        p.ObjectText = cfg.objectText
        p.KeyboardKeyCode = Enum.KeyCode.E
        p.HoldDuration = cfg.holdSec
        p.MaxActivationDistance = cfg.distance
        p.RequiresLineOfSight = false
        p.Parent = host
        prompt = p
    end

    prompt.Triggered:Connect(function(player: Player)
        openConfirm(player, "kandang")
    end)
    return true
end

-- ── Return portal (sanctuary) ────────────────────────────────────────────────
local function setupReturnPortal(): boolean
    local cfg = TravelConfig.returnPortal

    -- Position: in front of the Sanctuary SpawnLocation, else the fixed fallback.
    local spawn = Workspace:FindFirstChildWhichIsA("SpawnLocation", true)
    local cframe = if spawn ~= nil then spawn.CFrame * CFrame.new(cfg.spawnOffset) else CFrame.new(cfg.fallbackPosition)

    local pad = Workspace:FindFirstChild(cfg.name)
    if pad == nil or not pad:IsA("BasePart") then
        local part = Instance.new("Part")
        part.Name = cfg.name
        part.Anchored = true
        part.CanCollide = false
        part.Material = Enum.Material.Neon
        part.Parent = Workspace
        pad = part
    end
    pad.Size = cfg.padSize
    pad.Color = cfg.padColor
    pad.CFrame = cframe

    if pad:FindFirstChildOfClass("PointLight") == nil then
        local light = Instance.new("PointLight")
        light.Color = cfg.padColor
        light.Range = 16
        light.Brightness = 2
        light.Parent = pad
    end

    if pad:FindFirstChild("PortalLabel") == nil then
        local billboard = Instance.new("BillboardGui")
        billboard.Name = "PortalLabel"
        billboard.Size = UDim2.fromOffset(200, 36)
        billboard.StudsOffset = Vector3.new(0, 3, 0)
        billboard.AlwaysOnTop = true
        billboard.MaxDistance = 80
        local label = Instance.new("TextLabel")
        label.BackgroundTransparency = 1
        label.Size = UDim2.fromScale(1, 1)
        label.Font = Enum.Font.GothamBold
        label.TextScaled = true
        label.TextColor3 = Color3.fromRGB(245, 247, 255)
        label.Text = cfg.labelText
        label.Parent = billboard
        billboard.Parent = pad
    end

    local prompt = pad:FindFirstChildOfClass("ProximityPrompt")
    if prompt == nil then
        local p = Instance.new("ProximityPrompt")
        p.ActionText = cfg.actionText
        p.ObjectText = cfg.objectText
        p.KeyboardKeyCode = Enum.KeyCode.E
        p.HoldDuration = cfg.holdSec
        p.MaxActivationDistance = cfg.distance
        p.RequiresLineOfSight = false
        p.Parent = pad
        prompt = p
    end

    prompt.Triggered:Connect(function(player: Player)
        openConfirm(player, "overworld")
    end)
    return true
end

-- ── Confirm wiring (all places) ──────────────────────────────────────────────
TravelRemotes.ConfirmTravel.OnServerEvent:Connect(function(player: Player)
    local dest = pendingTravel[player]
    if dest == nil then
        return
    end
    pendingTravel[player] = nil
    WorldService.travel(player, dest)
end)

TravelRemotes.CancelTravel.OnServerEvent:Connect(function(player: Player)
    pendingTravel[player] = nil
end)

Players.PlayerRemoving:Connect(function(player: Player)
    pendingTravel[player] = nil
    WorldService.clearPlayer(player)
end)

-- Async teleport failures (after TeleportAsync returned) surface here.
TeleportService.TeleportInitFailed:Connect(function(player: Player, _result, errorMessage: string)
    warn("[Travel] TeleportInitFailed for " .. player.Name .. ": " .. tostring(errorMessage))
    DemoRemotes.Moment:FireClient(player, { kind = "info", text = "Teleport gagal — coba lagi sebentar." })
end)

-- ── Boot (place-gated) ───────────────────────────────────────────────────────
local kind = WorldConfig.currentPlaceKind()
if kind == "overworld" then
    if setupBunkBedPrompt() then
        print("[Travel] BunkBed → private Sanctuary prompt ready")
    end
elseif kind == "kandang" then
    if setupReturnPortal() then
        print("[Travel] Sanctuary → Overworld return portal ready")
    end
else
    warn("[Travel] place kind '" .. kind .. "' has no travel interactions wired")
end
