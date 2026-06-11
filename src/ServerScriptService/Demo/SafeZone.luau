--!strict
-- ServerScriptService/Demo/SafeZone.luau
--
-- SERVER-ONLY safe-zone test for the battle system. A "safe zone" is any
-- Workspace BasePart tagged `DemoConfig.combat.safeZoneTag` (CollectionService) —
-- the Hunter Camp, merchant area, checkpoints, etc. Inside one, a player may
-- SUMMON a monster fighter; outside, summoning is refused (recall is exempt). The
-- whole private Sanctuary (kandang) place is implicitly safe.
--
-- Pure query helper (no state beyond the cached tag string). The box test runs in
-- each zone part's LOCAL space, so rotated zone parts work and the part's Size is
-- the zone's full extent.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DemoConfig = require(Shared:WaitForChild("Demo"):WaitForChild("DemoConfig"))
local WorldConfig = require(Shared:WaitForChild("Config"):WaitForChild("WorldConfig"))

local SafeZone = {}

local TAG: string = DemoConfig.combat.safeZoneTag

-- True iff `position` lies inside any Workspace BasePart tagged SafeZone. The
-- entire Sanctuary (kandang) place counts as safe regardless of tagged parts.
function SafeZone.contains(position: Vector3): boolean
    if WorldConfig.currentPlaceKind() == "kandang" then
        return true
    end
    for _, part in CollectionService:GetTagged(TAG) do
        if part:IsA("BasePart") then
            local lp = part.CFrame:PointToObjectSpace(position)
            local half = part.Size * 0.5
            if math.abs(lp.X) <= half.X and math.abs(lp.Y) <= half.Y and math.abs(lp.Z) <= half.Z then
                return true
            end
        end
    end
    return false
end

return SafeZone
