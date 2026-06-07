--!strict
-- Shared/Demo/RigGrounding.luau
--
-- Grounding helpers for the demo blob rigs (pack wilds, bosses, kandang
-- wanderers, summoned fighters).
--
-- THE PROBLEM: the engine holds the HumanoidRootPart's BOTTOM exactly
-- HipHeight above the floor — but these rigs' visible mesh hangs HIGHER than
-- the root's bottom, so with the authored HipHeight (2.0) every clone hovers
-- ~0.75 studs in the air (scaled clones hover proportionally more: a 2x boss
-- floats ~1.5).
--
-- THE FIX is two-phase:
--   1. initialHipHeight() — at spawn, derive HipHeight from the clone's
--      CURRENT geometry so the lowest point lands near the ground:
--        HipHeight = (rootCenterY - modelLowestY) - rootSize.Y/2
--      This is pose-dependent (the template pose differs slightly from the
--      physics-settled pose, ~0.15 x scale), so a small residual remains.
--   2. settleToGround() — shortly AFTER spawn, raycast straight down from the
--      model's lowest point and subtract the MEASURED residual gap from
--      HipHeight. The ray uses RespectCanCollide so it passes through other
--      monsters (their parts are all CanCollide=false) and only hits real
--      ground — neighbor blobs can never poison the measurement.
--
-- Pure helpers + one task.delay; no state. Server-only callers in practice,
-- but the module holds no secrets so ReplicatedStorage placement is fine
-- (shared-modules rules).

local RigGrounding = {}

-- Seconds after spawn before the settle correction measures the real gap.
-- Long enough for the spawn drop + humanoid balance to come to rest.
-- Range: 0.3-3 | Default: 1.0
local SETTLE_DELAY_SEC = 1.0

-- Residual gaps smaller than this are left alone (invisible; avoids jitter).
-- Range: 0.01-0.2 | Default: 0.05
local GAP_EPSILON = 0.05

-- Sanity clamp: a measured |gap| beyond this means the ray hit something
-- unrelated (ledge edge, mid-fall) — skip the correction rather than yank.
-- Range: 1-6 | Default: 3
local GAP_SANE_MAX = 3

-- Lowest Y of any BasePart in the model (world space), or nil if part-less.
function RigGrounding.lowestY(model: Model): number?
    local minY = math.huge
    for _, d in model:GetDescendants() do
        if d:IsA("BasePart") then
            minY = math.min(minY, d.Position.Y - d.Size.Y / 2)
        end
    end
    if minY == math.huge then
        return nil
    end
    return minY
end

-- Phase 1: spawn-time HipHeight from the clone's current geometry. Call AFTER
-- the clone is positioned + scaled (the root-to-lowest offset must be final).
function RigGrounding.initialHipHeight(model: Model, root: BasePart): number
    local minY = RigGrounding.lowestY(model)
    if minY == nil then
        return 2 -- defensive: geometry-less rig, keep the authored default
    end
    return math.max((root.Position.Y - minY) - root.Size.Y / 2, 0)
end

-- Phase 2: post-settle correction. Schedules a one-shot measurement that
-- subtracts the real remaining hover gap from HipHeight. Safe to call on any
-- freshly-parented rig; silently no-ops if the model despawned meanwhile.
function RigGrounding.settleToGround(model: Model, humanoid: Humanoid)
    task.delay(SETTLE_DELAY_SEC, function()
        if model.Parent == nil or humanoid.Parent == nil then
            return -- despawned / recalled before the correction fired
        end
        local root = model.PrimaryPart
        if not root then
            return
        end
        local minY = RigGrounding.lowestY(model)
        if minY == nil then
            return
        end
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = { model }
        -- Pass through every other monster (their parts are CanCollide=false);
        -- only real, collidable ground can terminate the ray.
        params.RespectCanCollide = true
        local origin = Vector3.new(root.Position.X, minY + 0.5, root.Position.Z)
        local hit = workspace:Raycast(origin, Vector3.new(0, -20, 0), params)
        if not hit then
            return -- nothing below (mid-air over void); leave as-is
        end
        local gap = minY - hit.Position.Y
        if math.abs(gap) <= GAP_EPSILON or math.abs(gap) > GAP_SANE_MAX then
            return
        end
        humanoid.HipHeight = math.max(humanoid.HipHeight - gap, 0)
    end)
end

return RigGrounding
