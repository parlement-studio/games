--!strict
-- CatchCinematic.client.luau
--
-- Plays the CATCH CINEMATIC for the local player when the server confirms a
-- successful catch (DemoRemotes.CatchCinematic). The roster mint already
-- committed server-side; this is pure presentation on the frozen wild model.
--
-- Sequence (all client-side, timings from DemoConfig.catchCinematic):
--   1. Camera dollies in + punches FOV to frame the monster.
--   2. A 🕸️ net flies from the player's hand to the monster along a bezier arc.
--   3. Impact: an element-colored particle burst + a short camera/monster shake
--      (the monster "struggles" in the net).
--   4. Suck-in: the monster shrinks toward zero while spinning (captured!).
--   5. Poof: a final particle puff; the camera zooms back out to gameplay.
--
-- Robust by design: only one cinematic runs at a time, every step is guarded
-- against the model being destroyed early (the server destroys it after
-- holdSec regardless), and the camera is ALWAYS restored via a cleanup path.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local LocalPlayer = Players.LocalPlayer

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DemoFolder = Shared:WaitForChild("Demo")
local DemoRemotes = require(DemoFolder:WaitForChild("DemoRemotes"))
local DemoConfig = require(DemoFolder:WaitForChild("DemoConfig"))
local ElementConfig = require(Shared:WaitForChild("Config"):WaitForChild("ElementConfig"))

local CINE = DemoConfig.catchCinematic

-- Element accent color (white fallback for nil/unknown so a burst never errors).
local function elementColor(element: any): Color3
    local display = ElementConfig.display[element]
    if display then
        return Color3.fromHex(display.color)
    end
    return Color3.fromRGB(255, 255, 255)
end

-- Quadratic bezier point at t in [0,1] (straight line bowed up by a control pt).
local function bezier(p0: Vector3, p1: Vector3, p2: Vector3, t: number): Vector3
    local u = 1 - t
    return (u * u) * p0 + (2 * u * t) * p1 + (t * t) * p2
end

-- The hand (or root) the net launches from.
local function launchOrigin(): Vector3?
    local char = LocalPlayer.Character
    if not char then
        return nil
    end
    local hand = char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm")
    if hand and hand:IsA("BasePart") then
        return hand.Position
    end
    local root = char:FindFirstChild("HumanoidRootPart")
    if root and root:IsA("BasePart") then
        return (root :: BasePart).Position + Vector3.new(0, 1, 0)
    end
    return nil
end

-- Fly a 🕸️ net billboard along the arc from `from` to `to` over `dur` seconds.
-- Yields until it lands (or the run is aborted).
local function flyNet(from: Vector3, to: Vector3, dur: number)
    local net = Instance.new("Part")
    net.Name = "CatchNet"
    net.Shape = Enum.PartType.Ball
    net.Size = Vector3.new(1.6, 1.6, 1.6)
    net.Anchored = true
    net.CanCollide = false
    net.CanQuery = false
    net.Material = Enum.Material.Neon
    net.Color = Color3.fromRGB(230, 230, 240)
    net.Transparency = 0.35
    net.CFrame = CFrame.new(from)
    net.Parent = workspace

    local billboard = Instance.new("BillboardGui")
    billboard.Size = UDim2.fromOffset(70, 70)
    billboard.AlwaysOnTop = true
    billboard.Parent = net
    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Size = UDim2.fromScale(1, 1)
    label.Font = Enum.Font.GothamBold
    label.TextScaled = true
    label.Text = "🕸️"
    label.Parent = billboard

    local trail = Instance.new("Trail")
    local a0 = Instance.new("Attachment")
    a0.Position = Vector3.new(-0.4, 0, 0)
    a0.Parent = net
    local a1 = Instance.new("Attachment")
    a1.Position = Vector3.new(0.4, 0, 0)
    a1.Parent = net
    trail.Attachment0 = a0
    trail.Attachment1 = a1
    trail.Lifetime = 0.25
    trail.Transparency = NumberSequence.new(0.4, 1)
    trail.Parent = net

    local mid = (from + to) / 2 + Vector3.new(0, CINE.arcHeight, 0)
    local elapsed = 0
    while elapsed < dur do
        local dt = RunService.RenderStepped:Wait()
        elapsed += dt
        local t = math.clamp(elapsed / dur, 0, 1)
        local pos = bezier(from, mid, to, t)
        net.CFrame = CFrame.new(pos) * CFrame.Angles(0, elapsed * 12, 0)
    end
    net:Destroy()
end

-- One particle burst (element-colored) at `position`. Self-cleans.
local function burst(position: Vector3, color: Color3, rate: number, speed: number, life: number)
    local part = Instance.new("Part")
    part.Anchored = true
    part.CanCollide = false
    part.CanQuery = false
    part.Transparency = 1
    part.Size = Vector3.one
    part.CFrame = CFrame.new(position)
    part.Parent = workspace

    local attach = Instance.new("Attachment")
    attach.Parent = part

    local emitter = Instance.new("ParticleEmitter")
    emitter.Color = ColorSequence.new(color)
    emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
    emitter.Lifetime = NumberRange.new(life * 0.6, life)
    emitter.Speed = NumberRange.new(speed * 0.5, speed)
    emitter.SpreadAngle = Vector2.new(180, 180)
    emitter.Rotation = NumberRange.new(0, 360)
    emitter.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1.4),
        NumberSequenceKeypoint.new(1, 0),
    })
    emitter.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.1),
        NumberSequenceKeypoint.new(1, 1),
    })
    emitter.Parent = attach

    emitter:Emit(rate)
    Debris:AddItem(part, life + 0.5)
end

-- ── Camera ───────────────────────────────────────────────────────────────────
local camera = workspace.CurrentCamera

-- Frame the monster from the player's side: camera sits `camDistance` toward the
-- player and `camHeight` above the monster, looking at it.
local function framingCFrame(monsterPos: Vector3): CFrame
    local playerPos = monsterPos
    local char = LocalPlayer.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if root and root:IsA("BasePart") then
        playerPos = (root :: BasePart).Position
    end
    local dir = playerPos - monsterPos
    dir = Vector3.new(dir.X, 0, dir.Z)
    if dir.Magnitude < 0.1 then
        dir = Vector3.new(0, 0, 1) -- degenerate: pick an arbitrary side
    end
    dir = dir.Unit
    -- Bias to the side a touch so the shot reads 3/4, not dead-on.
    local side = Vector3.new(-dir.Z, 0, dir.X) * 0.35
    local camPos = monsterPos + dir * CINE.camDistance + side * CINE.camDistance + Vector3.new(0, CINE.camHeight, 0)
    return CFrame.lookAt(camPos, monsterPos + Vector3.new(0, 1, 0))
end

-- ── Sequence ─────────────────────────────────────────────────────────────────
local running = false

local function playCinematic(model: Model, element: any)
    -- One at a time: a second catch mid-sequence is ignored (the model still
    -- despawns server-side, just without a second overlapping shot).
    if running then
        return
    end
    if not model or not model.Parent then
        return
    end
    running = true

    -- Save + take over the camera. NOTE: if a prior cinematic was interrupted
    -- and left the camera Scriptable, we must NOT "restore" back to that — the
    -- gameplay camera in this game is Custom, so we normalize a Scriptable
    -- origType to Custom (prevents a stuck-camera cascade).
    local origType = camera.CameraType
    if origType == Enum.CameraType.Scriptable then
        origType = Enum.CameraType.Custom
    end
    local humanoid = model:FindFirstChildWhichIsA("Humanoid")
    local origFov = camera.FieldOfView
    -- The gameplay camera follows the player's Humanoid; capture it as the
    -- restore subject (fall back to the saved one).
    local restoreSubject = camera.CameraSubject
    local char = LocalPlayer.Character
    local charHumanoid = char and char:FindFirstChildWhichIsA("Humanoid")
    if charHumanoid then
        restoreSubject = charHumanoid
    end
    camera.CameraType = Enum.CameraType.Scriptable

    local monsterPos = model:GetPivot().Position
    local target = framingCFrame(monsterPos)
    local color = elementColor(element)

    -- Always-restore guard: even if any step errors or the model vanishes, the
    -- camera goes back to gameplay.
    local function restore()
        local fovTween = TweenService:Create(
            camera,
            TweenInfo.new(CINE.restoreSec, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            { FieldOfView = origFov }
        )
        fovTween:Play()
        fovTween.Completed:Wait()
        camera.CameraSubject = restoreSubject
        camera.CameraType = origType
        running = false
    end

    local ok = pcall(function()
        -- 1) Dolly-in + FOV punch (concurrent with the net throw).
        local dolly = TweenService:Create(
            camera,
            TweenInfo.new(CINE.camInSec, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            { CFrame = target, FieldOfView = CINE.fovZoom }
        )
        dolly:Play()

        -- 2) Net throw.
        local from = launchOrigin() or (monsterPos + Vector3.new(0, 6, 8))
        flyNet(from, monsterPos + Vector3.new(0, 1, 0), CINE.netFlightSec)

        -- 3) Impact: burst + camera/monster shake ("struggle").
        burst(monsterPos + Vector3.new(0, 1, 0), color, 40, 18, 0.7)
        if humanoid then
            humanoid.WalkSpeed = 0
        end
        local shakeElapsed = 0
        while shakeElapsed < CINE.shakeSec do
            local dt = RunService.RenderStepped:Wait()
            shakeElapsed += dt
            -- Camera handheld jitter.
            local mag = 0.35 * (1 - shakeElapsed / CINE.shakeSec)
            local jitter = Vector3.new(
                (math.random() - 0.5) * 2 * mag,
                (math.random() - 0.5) * 2 * mag,
                (math.random() - 0.5) * 2 * mag
            )
            camera.CFrame = target + jitter
            -- Monster wobble in the net.
            if model.Parent then
                model:PivotTo(
                    CFrame.new(monsterPos)
                        * CFrame.Angles(0, math.sin(shakeElapsed * 50) * 0.25, math.sin(shakeElapsed * 37) * 0.15)
                )
            end
        end
        camera.CFrame = target

        -- 4) Suck-in: shrink toward zero while spinning.
        if model.Parent then
            local startScale = model:GetScale()
            local shrinkElapsed = 0
            while shrinkElapsed < CINE.shrinkSec do
                local dt = RunService.RenderStepped:Wait()
                shrinkElapsed += dt
                local t = math.clamp(shrinkElapsed / CINE.shrinkSec, 0, 1)
                -- Ease-in cubic: slow start, fast vanish.
                local s = startScale * (1 - t * t * t)
                if model.Parent and s > 0.01 then
                    pcall(function()
                        model:ScaleTo(s)
                    end)
                    model:PivotTo(CFrame.new(monsterPos + Vector3.new(0, t * 1.5, 0)) * CFrame.Angles(0, t * 18, 0))
                end
            end
        end

        -- 5) Poof + zoom back out.
        burst(monsterPos + Vector3.new(0, 1, 0), color, 28, 10, 0.6)
        task.wait(0.12)
    end)

    if not ok then
        warn("[CatchCinematic] sequence error — restoring camera")
    end
    restore()
end

DemoRemotes.CatchCinematic.OnClientEvent:Connect(function(payload)
    if type(payload) ~= "table" then
        return
    end
    local model = payload.model
    if typeof(model) ~= "Instance" or not model:IsA("Model") then
        return
    end
    playCinematic(model, payload.element)
end)

print("[CatchCinematic][client] ready")
