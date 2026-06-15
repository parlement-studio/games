--!strict
-- ServerScriptService/Demo/GroundFollow.luau
--
-- Kinematic, ground-snapping movement for creature rigs (wilds + summoned
-- fighters). REPLACES Humanoid:MoveTo: the root is ANCHORED and driven by code
-- each Heartbeat — moved horizontally toward a target and snapped vertically onto
-- the terrain via a downward raycast. The minimal 2-part blob rigs can't climb
-- ramps/stairs with the physics Humanoid (too little geometry for slope/jump), so
-- we just hug the surface instead: it rides up any incline by following the ground
-- height, no jumping needed.
--
-- The Humanoid is kept (health bar, hit detection) but no longer drives movement.
--
-- LOCOMOTION MODES (future-proofing): every entry carries a `locomotion` mode that
-- only changes how the VERTICAL is resolved. Today only "ground" (snap to terrain)
-- exists; "fly" (hold an altitude) and "mounted" (player-driven) drop in by
-- swapping the Y rule / target source without touching the horizontal mover.
--
-- TRADE-OFF: kinematic + non-colliding means a rig passes THROUGH vertical walls
-- (it only ever sticks to the ground below it). Accepted by design — terrain
-- traversal beats wall collision for these creatures.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RigGrounding = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Demo"):WaitForChild("RigGrounding"))

local GroundFollow = {}

export type Locomotion = "ground" -- future: "fly" | "mounted"

type Entry = {
    root: BasePart,
    walkSpeed: number,
    target: Vector3, -- desired destination (Y ignored in "ground" mode)
    hipOffset: number, -- root-center height above the rig's lowest point (feet)
    locomotion: Locomotion,
    facing: Vector3, -- last horizontal forward (kept while idle)
}

local entries: { [Model]: Entry } = {}

-- ── Tuning ───────────────────────────────────────────────────────────────────
local RAY_UP = 8 -- start the ground ray this far ABOVE the root (and the target)
local RAY_LEN = 64 -- how far down to search for ground BELOW the rig's own feet
local ARRIVE = 1.0 -- within this XZ distance the rig is "there" (stops moving)
-- Max studs/s the rig rises when stepping onto higher ground (smooths the climb up
-- a cliff face into the target's plateau instead of teleporting the whole height in
-- one frame).
local CLIMB_SPEED = 60

-- ── Ground ray filter ────────────────────────────────────────────────────────
-- Ignore player characters; creature parts are CanCollide=false (set on attach)
-- so the ray (RespectCanCollide) already passes through other monsters and only
-- the solid world terminates it.
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = true
rayParams.IgnoreWater = true

local function rebuildIgnore()
    local list: { Instance } = {}
    for _, p in Players:GetPlayers() do
        if p.Character then
            table.insert(list, p.Character)
        end
    end
    rayParams.FilterDescendantsInstances = list
end

Players.PlayerAdded:Connect(function(p: Player)
    p.CharacterAdded:Connect(rebuildIgnore)
    rebuildIgnore()
end)
Players.PlayerRemoving:Connect(rebuildIgnore)
rebuildIgnore()

-- ── Public API ───────────────────────────────────────────────────────────────

-- Register (or refresh) a rig for kinematic ground-follow. Idempotent: a second
-- call with the same live root just updates the walk speed. Re-attaches if the
-- model was pruned (e.g. a caught wild that respawned the same instance). Anchors
-- the root and makes every part non-colliding (we drive position by raycast).
function GroundFollow.attach(model: Model, root: BasePart, walkSpeed: number)
    local existing = entries[model]
    if existing and existing.root == root and root.Parent ~= nil then
        existing.walkSpeed = walkSpeed
        return
    end
    root.Anchored = true
    for _, d in model:GetDescendants() do
        if d:IsA("BasePart") then
            d.CanCollide = false
        end
    end
    local lowest = RigGrounding.lowestY(model)
    local hipOffset = if lowest ~= nil then math.max(root.Position.Y - lowest, 0) else 2
    entries[model] = {
        root = root,
        walkSpeed = walkSpeed,
        target = root.Position,
        hipOffset = hipOffset,
        locomotion = "ground",
        facing = root.CFrame.LookVector * Vector3.new(1, 0, 1),
    }
end

-- Set the destination for an attached rig (no-op if not attached). Only the XZ of
-- `target` is used in "ground" mode; the Y is resolved from the terrain.
function GroundFollow.setTarget(model: Model, target: Vector3)
    local e = entries[model]
    if e then
        e.target = target
    end
end

-- Stop a rig where it is (clears its move target to its current position).
function GroundFollow.stop(model: Model)
    local e = entries[model]
    if e then
        e.target = e.root.Position
    end
end

function GroundFollow.isAttached(model: Model): boolean
    return entries[model] ~= nil
end

function GroundFollow.detach(model: Model)
    entries[model] = nil
end

-- ── Driver ───────────────────────────────────────────────────────────────────
RunService.Heartbeat:Connect(function(dt: number)
    for model, e in entries do
        local root = e.root
        if root.Parent == nil or model.Parent == nil then
            entries[model] = nil -- auto-prune despawned rigs
        else
            local pos = root.Position
            local toX = e.target.X - pos.X
            local toZ = e.target.Z - pos.Z
            local horiz = math.sqrt(toX * toX + toZ * toZ)
            local newX, newZ = pos.X, pos.Z
            local faceDir = e.facing
            if horiz > ARRIVE then
                local step = math.min(e.walkSpeed * dt, horiz)
                local nx, nz = toX / horiz, toZ / horiz
                newX = pos.X + nx * step
                newZ = pos.Z + nz * step
                faceDir = Vector3.new(nx, 0, nz)
                e.facing = faceDir
            end

            -- VERTICAL per locomotion. "ground": snap the feet onto the terrain. The
            -- search CEILING is raised to the TARGET's elevation (which carries the
            -- player's Y on the follow path) so a rig can detect + climb onto ground
            -- HIGHER than RAY_UP above its current feet — e.g. follow the player up a
            -- tall boss plateau whose lip is a sheer cliff, not just gentle slopes
            -- within RAY_UP. The down-ray is lengthened so it always reaches RAY_LEN
            -- past the rig's OWN feet no matter how high the ceiling rose.
            local newY = pos.Y
            local ceilingY = math.max(pos.Y, e.target.Y) + RAY_UP
            local origin = Vector3.new(newX, ceilingY, newZ)
            local hit = Workspace:Raycast(origin, Vector3.new(0, -((ceilingY - pos.Y) + RAY_LEN), 0), rayParams)
            if hit then
                local groundY = hit.Position.Y + e.hipOffset
                -- Clamp the per-frame CLIMB so the rig rises smoothly through the
                -- cliff face into the plateau instead of popping the full height in
                -- one frame; descents (dy < 0) settle immediately (gravity-like).
                local dy = groundY - pos.Y
                local maxUp = CLIMB_SPEED * dt
                if dy > maxUp then
                    dy = maxUp
                end
                newY = pos.Y + dy
            end

            local dest = Vector3.new(newX, newY, newZ)
            if faceDir.Magnitude > 0.001 then
                root.CFrame = CFrame.lookAt(dest, dest + faceDir)
            else
                root.CFrame = CFrame.new(dest) * (root.CFrame - root.CFrame.Position)
            end
        end
    end
end)

return GroundFollow
