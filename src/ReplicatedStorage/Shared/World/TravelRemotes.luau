--!strict
-- Shared/World/TravelRemotes.luau
--
-- RemoteEvent registry for the cross-place TRAVEL feature (BunkBed → private
-- Sanctuary, Sanctuary → Overworld). Same getOrCreate pattern as DemoRemotes:
-- the first requirer (server) creates the RemoteEvents as children of THIS
-- module; the client waits for + reuses them.
--
-- CONTRACT:
--   Server -> Client:  OpenTravelConfirm(payload)
--       payload = { destination: string, title: string, body: string, confirmText: string }
--       The client shows a confirm modal. The SERVER decides `destination` (set
--       when the player triggers a travel prompt) — the client only echoes the
--       confirm/cancel, so it can never pick an arbitrary teleport target.
--   Client -> Server:  ConfirmTravel()   -- player pressed "Yes": teleport the
--                                            server-chosen pending destination.
--                      CancelTravel()    -- player dismissed: clear pending.
--
-- No payload is trusted from the client (ConfirmTravel/CancelTravel carry no
-- args); the destination lives ONLY in server state.

local RunService = game:GetService("RunService")

local CLIENT_TO_SERVER = {
    "ConfirmTravel",
    "CancelTravel",
}

local SERVER_TO_CLIENT = {
    "OpenTravelConfirm",
}

export type TravelRemotes = {
    ConfirmTravel: RemoteEvent,
    CancelTravel: RemoteEvent,
    OpenTravelConfirm: RemoteEvent,
}

local container: Instance = script

local function getOrCreate(name: string): RemoteEvent
    if RunService:IsServer() then
        local existing = container:FindFirstChild(name)
        if existing and existing:IsA("RemoteEvent") then
            return existing
        end
        local remote = Instance.new("RemoteEvent")
        remote.Name = name
        remote.Parent = container
        return remote
    else
        local remote = container:WaitForChild(name, 30)
        assert(remote and remote:IsA("RemoteEvent"), "[TravelRemotes] missing RemoteEvent: " .. name)
        return remote :: RemoteEvent
    end
end

local remotes = {} :: TravelRemotes
for _, name in CLIENT_TO_SERVER do
    (remotes :: any)[name] = getOrCreate(name)
end
for _, name in SERVER_TO_CLIENT do
    (remotes :: any)[name] = getOrCreate(name)
end

return remotes
