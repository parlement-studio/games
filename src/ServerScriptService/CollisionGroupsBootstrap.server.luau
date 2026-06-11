--!strict
-- ServerScriptService/CollisionGroupsBootstrap.server.luau
--
-- Central collision-group setup for the creature combat world. Two groups:
--   "Monster" — every wild / summoned fighter / deployed display rig.
--   "Players" — every player character.
--
-- Collidability matrix (everything not listed stays at the engine default of
-- collidable):
--   Monster <-> Monster = false   (blobs never shove each other)
--   Monster <-> Players = false   (a pet/wild never blocks or pushes a player)
--   Monster <-> Default = true    (monsters DO collide with terrain/walls — the
--                                  rigs set HumanoidRootPart.CanCollide=true, so
--                                  they stop at terrain instead of phasing through)
--   Players <-> Default = true    (players still collide with the world, as usual)
--
-- The "Monster" group is ALSO registered defensively by MonsterPack / DemoServer
-- (RegisterCollisionGroup is idempotent via pcall); doing it here too guarantees
-- the matrix is set even if load order changes.

local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")

local MONSTER = "Monster"
local PLAYERS = "Players"

local function register(name: string)
    -- RegisterCollisionGroup throws on a duplicate name; swallow it (idempotent).
    pcall(function()
        PhysicsService:RegisterCollisionGroup(name)
    end)
end

register(MONSTER)
register(PLAYERS)

PhysicsService:CollisionGroupSetCollidable(MONSTER, MONSTER, false)
PhysicsService:CollisionGroupSetCollidable(MONSTER, PLAYERS, false)

-- Put every BasePart of a character into the Players group (now + as limbs stream
-- in / respawn). Players keep colliding with the world (Players<->Default=true);
-- only the Monster rule above changes their behavior toward creatures.
local function assignCharacter(character: Model)
    for _, d in character:GetDescendants() do
        if d:IsA("BasePart") then
            d.CollisionGroup = PLAYERS
        end
    end
    character.DescendantAdded:Connect(function(d: Instance)
        if d:IsA("BasePart") then
            d.CollisionGroup = PLAYERS
        end
    end)
end

local function onPlayer(player: Player)
    if player.Character then
        assignCharacter(player.Character)
    end
    player.CharacterAdded:Connect(assignCharacter)
end

Players.PlayerAdded:Connect(onPlayer)
for _, player in Players:GetPlayers() do
    onPlayer(player)
end
