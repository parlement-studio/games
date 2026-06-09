--!strict
-- ServerScriptService/Demo/BrainrotAI.server.luau
--
-- DEMO-ONLY wild-Brainrot ROAMING AI for the "Brainrot Inc." slice.
--
-- The 5 wild creatures (`Brainrot_<P>` in the Workspace) are rigged with a
-- Humanoid + an invisible HumanoidRootPart (done once in Studio), so the SERVER
-- can walk them with Humanoid:MoveTo. This script makes each one wander randomly
-- within `wanderRadius` of the spot it spawned at ("home"), so they mill around
-- the wild area and never drift into the Showroom.
--
-- SERVER-AUTHORITATIVE: NPC movement is owned entirely by the server (network
-- owner = server, set at rig time). The client only sees the replicated motion.
-- This is the FOUNDATION for the summon-and-battle step (Tahap 2): once a
-- creature can walk to a point, it can walk to an opponent.
--
-- Isolated under Demo/. Reads DemoConfig only; independent of DemoServer (which
-- owns catch/deploy). A creature that is currently CAUGHT (DemoCaught == true) is
-- unparented by DemoServer, so it simply isn't found here until it respawns.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DemoFolder = Shared:WaitForChild("Demo")
local DemoConfig = require(DemoFolder:WaitForChild("DemoConfig"))

local WILD = DemoConfig.wild

-- Per-creature roam state, keyed by the Model instance (stable across a
-- catch/respawn cycle — DemoServer re-parents the SAME instance). `home` is the
-- anchor we wander around; `nextAt` is the os.clock() when a new target is due.
type RoamState = {
    home: Vector3,
    nextAt: number,
}
local roam: { [Model]: RoamState } = {}

-- Resolve (and lazily initialize) the roam state for a wild creature model. nil
-- until the model has BOTH a Humanoid and a PrimaryPart (the rig is complete).
-- On first sight we also stamp the config WalkSpeed so DemoConfig is the single
-- source of truth for movement speed.
local function ensureState(model: Model): RoamState?
    local existing = roam[model]
    if existing then
        return existing
    end
    local humanoid = model:FindFirstChildWhichIsA("Humanoid")
    local root = model.PrimaryPart
    if not humanoid or not root then
        return nil -- not rigged yet; skip until it is
    end
    humanoid.WalkSpeed = WILD.walkSpeed
    -- Server-authoritative motion: claim network ownership so a nearby client
    -- can't be auto-assigned the NPC and tamper with its movement (matters for
    -- the upcoming battle step). Safe: the root is unanchored.
    pcall(function()
        root:SetNetworkOwner(nil)
    end)
    local state: RoamState = { home = root.Position, nextAt = 0 }
    roam[model] = state
    return state
end

-- Pick a random point within `wanderRadius` of home, on home's ground plane
-- (Humanoid:MoveTo resolves the vertical itself). Uniform over the disc.
local function randomTarget(home: Vector3): Vector3
    local angle = math.random() * math.pi * 2
    local dist = math.sqrt(math.random()) * WILD.wanderRadius
    return home + Vector3.new(math.cos(angle) * dist, 0, math.sin(angle) * dist)
end

-- One AI step: for every wild creature currently in the world, if its next-move
-- timer is due, send it to a fresh random target near home and re-arm the timer.
local function step()
    local now = os.clock()
    for _, creatureName in DemoConfig.demo3d.creatureNames do
        local model = workspace:FindFirstChild(creatureName)
        -- Skip a creature that is CAUGHT (unparented) OR currently ENGAGED in combat
        -- (InCombat == true). Combat owns the wild's movement while engaged; wander
        -- resumes once the combat loop clears the InCombat attribute (Tahap 2).
        if
            model
            and model:IsA("Model")
            and model:GetAttribute("DemoCaught") ~= true
            and model:GetAttribute("InCombat") ~= true
        then
            local state = ensureState(model)
            if state then
                local humanoid = model:FindFirstChildWhichIsA("Humanoid")
                if humanoid and humanoid.Health > 0 and now >= state.nextAt then
                    humanoid:MoveTo(randomTarget(state.home))
                    local pause = WILD.wanderPauseMinSec
                        + math.random() * (WILD.wanderPauseMaxSec - WILD.wanderPauseMinSec)
                    state.nextAt = now + pause
                end
            end
        end
    end
end

-- Coarse scheduler: MoveTo does the per-frame walking, so we only need to
-- (re)assign targets every `aiTickSec`. A Heartbeat accumulator keeps it
-- frame-rate independent without a busy wait.
local accum = 0
RunService.Heartbeat:Connect(function(dt: number)
    accum += dt
    if accum >= WILD.aiTickSec then
        accum = 0
        step()
    end
end)

print("[Brainrot AI] wild roaming online (" .. #DemoConfig.demo3d.creatureNames .. " creatures)")
