--!strict
-- ServerScriptService/MonsterRigsBootstrap.server.luau
--
-- MONSTER RIG SOURCE (multi-place). The monster visual rigs (`Monster_<P>`) are
-- a published Roblox MODEL ASSET — the Roblox equivalent of a Unity prefab. This
-- script LOADS that asset at runtime into `ServerStorage.MonsterRigs` so EVERY
-- place (Overworld, Sanctuary, …) gets the rigs WITHOUT manually copying 3D models
-- per place. The asset is the single source of truth; this is code (Argon-synced),
-- so it runs in all places automatically.
--
-- Why an asset (not Workspace models): 3D content lives in each place's .rbxl and
-- does NOT sync via Argon/source, so copies drift / get lost on restructure. An
-- asset loaded by code is shared + survives restructure.
--
-- The deploy / wild / combat template builders snapshot from
-- `ServerStorage.MonsterRigs` (they WaitForChild it, so the async LoadAsset here
-- can finish first).

local InsertService = game:GetService("InsertService")
local ServerStorage = game:GetService("ServerStorage")

-- Published "MonsterRigs" model asset (a Folder of Monster_<P> rigs).
-- Update this if the asset is re-published under a new id.
-- 114660620638886: rigs cleanly renamed to Monster_<P> (the legacy-prefix
-- normalization below is now a no-op but kept as a safety net).
local MONSTER_RIGS_ASSET_ID = 114660620638886

-- Defensive: strip stray meshes that make a rig render as a plain box (e.g. a
-- leftover SpecialMesh with MeshType=Torso or an empty MeshId shadowing the real
-- FileMesh). Keeps the valid FileMesh. Lets a slightly-broken asset still load OK.
local function stripStrayMeshes(root: Instance)
    for _, c in root:GetDescendants() do
        if c:IsA("SpecialMesh") and (c.MeshType == Enum.MeshType.Torso or c.MeshId == "") then
            c:Destroy()
        end
    end
end

local function loadRigs()
    -- Build the folder DETACHED, fill it, THEN parent it whole — so when
    -- `ServerStorage.MonsterRigs` appears it is already populated (the template
    -- builders WaitForChild it, so they never see a half-filled folder).
    local rigsFolder = Instance.new("Folder")
    rigsFolder.Name = "MonsterRigs"

    local ok, loaded = pcall(function()
        return InsertService:LoadAsset(MONSTER_RIGS_ASSET_ID)
    end)
    local n = 0
    if ok and typeof(loaded) == "Instance" then
        local container = loaded:FindFirstChild("MonsterRigs") or loaded
        stripStrayMeshes(container)
        for _, c in container:GetChildren() do
            if c:IsA("Model") then
                -- LEGACY: the currently-published asset still names its rigs
                -- "Brainrot_<P>" (pre-rebrand). Normalize to the canonical
                -- "Monster_<P>" so the config (Monster_) matches until the asset
                -- is re-published. Idempotent: an already-"Monster_" name is kept.
                if c.Name:sub(1, 9) == "Brainrot_" then
                    c.Name = "Monster_" .. c.Name:sub(10)
                end
                c.Parent = rigsFolder
                n += 1
            end
        end
        loaded:Destroy()
    else
        warn("[MonsterRigs] LoadAsset(" .. MONSTER_RIGS_ASSET_ID .. ") failed: " .. tostring(loaded))
    end

    -- Replace any prior folder, then publish the populated one atomically.
    local prior = ServerStorage:FindFirstChild("MonsterRigs")
    if prior then
        prior:Destroy()
    end
    rigsFolder.Parent = ServerStorage
    print(("[MonsterRigs] loaded %d rigs into ServerStorage.MonsterRigs"):format(n))
end

loadRigs()
