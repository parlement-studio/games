--!strict
-- ThrowAnimation.luau
--
-- JALUR A (keyframe animation, played through an Animator) for the catch
-- cinematic's net throw. The throw is authored in code as a KeyframeSequence
-- (an overhand toss on the right arm: wind-up high, whip forward-down, return)
-- and registered at runtime via KeyframeSequenceProvider — no asset upload
-- needed, and it still works in a published game.
--
-- For PRODUCTION you may publish this KeyframeSequence once (Studio: right-click
-- a built sequence -> Save to Roblox, or the Animation Editor) and set
-- DemoConfig.catchCinematic.throwAnimationId to the resulting rbxassetid://…;
-- getAnimation() prefers that id and skips runtime registration.
--
-- R15 only (the rig this game uses). Poses are nested by the rig hierarchy:
--   HumanoidRootPart > LowerTorso > UpperTorso > RightUpperArm > RightLowerArm
-- Each Pose.CFrame is that joint's animation Transform (offset on the default).
-- The timing was tuned by sampling the right-hand trajectory (up+forward peak
-- ~0.15s, release ~0.20s, follow-through to ~0.55s).

local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")

local ThrowAnimation = {}

-- Net leaves the hand at this point in the animation (seconds) — the catch
-- cinematic launches the projectile here so it reads as "thrown".
ThrowAnimation.releaseSec = 0.20

local function rad(x: number): number
    return math.rad(x)
end

-- Build one Keyframe: identity poses for the chain, with the right arm + torso
-- set from the passed CFrames (nil = identity).
local function makeKeyframe(time: number, rua: CFrame?, rla: CFrame?, torso: CFrame?): Keyframe
    local k = Instance.new("Keyframe")
    k.Time = time

    local root = Instance.new("Pose")
    root.Name = "HumanoidRootPart"
    root.CFrame = CFrame.identity

    local lower = Instance.new("Pose")
    lower.Name = "LowerTorso"
    lower.CFrame = CFrame.identity

    local upper = Instance.new("Pose")
    upper.Name = "UpperTorso"
    upper.CFrame = torso or CFrame.identity

    local upperArm = Instance.new("Pose")
    upperArm.Name = "RightUpperArm"
    upperArm.CFrame = rua or CFrame.identity

    local lowerArm = Instance.new("Pose")
    lowerArm.Name = "RightLowerArm"
    lowerArm.CFrame = rla or CFrame.identity

    upperArm:AddSubPose(lowerArm)
    upper:AddSubPose(upperArm)
    lower:AddSubPose(upper)
    root:AddSubPose(lower)
    k:AddPose(root)
    return k
end

-- Build the throw KeyframeSequence (Action priority so it overrides idle/walk).
function ThrowAnimation.build(): KeyframeSequence
    local kseq = Instance.new("KeyframeSequence")
    kseq.Name = "CatchThrow"
    kseq.Priority = Enum.AnimationPriority.Action
    kseq.Loop = false

    -- neutral
    kseq:AddKeyframe(makeKeyframe(0.0))
    -- wind-up: arm high (over the head) + bent elbow + torso coiled
    kseq:AddKeyframe(
        makeKeyframe(
            0.15,
            CFrame.Angles(rad(-160), 0, rad(-15)),
            CFrame.Angles(rad(-90), 0, 0),
            CFrame.Angles(0, rad(20), 0)
        )
    )
    -- release/whip: arm forward-down, elbow extended, torso uncoils forward
    kseq:AddKeyframe(
        makeKeyframe(
            0.30,
            CFrame.Angles(rad(55), 0, rad(-10)),
            CFrame.Angles(rad(-10), 0, 0),
            CFrame.Angles(0, rad(-15), 0)
        )
    )
    -- return to neutral
    kseq:AddKeyframe(makeKeyframe(0.55))
    return kseq
end

-- Cached Animation instance (built once per client session).
local cachedAnimation: Animation? = nil

-- Get a ready-to-load Animation for the throw. Prefers a published id when
-- `publishedId` is a non-empty rbxassetid://… string; otherwise registers the
-- code-authored KeyframeSequence at runtime (session-local, works live too).
-- Returns nil if registration fails (caller should no-op the arm motion).
function ThrowAnimation.getAnimation(publishedId: string?): Animation?
    if cachedAnimation then
        return cachedAnimation
    end

    local anim = Instance.new("Animation")
    anim.Name = "CatchThrowAnimation"

    if publishedId and publishedId ~= "" then
        anim.AnimationId = publishedId
        cachedAnimation = anim
        return anim
    end

    local kseq = ThrowAnimation.build()
    local ok, idOrErr = pcall(function()
        return KeyframeSequenceProvider:RegisterKeyframeSequence(kseq)
    end)
    kseq:Destroy() -- the registered copy is independent
    if not ok then
        warn("[ThrowAnimation] RegisterKeyframeSequence failed: " .. tostring(idOrErr))
        anim:Destroy()
        return nil
    end
    anim.AnimationId = idOrErr
    cachedAnimation = anim
    return anim
end

return ThrowAnimation
