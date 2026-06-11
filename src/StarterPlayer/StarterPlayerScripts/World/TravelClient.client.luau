--!strict
-- StarterPlayerScripts/World/TravelClient.client.luau
--
-- Client confirm modal for cross-place travel. Listens for OpenTravelConfirm
-- (server fires it when the player triggers a travel prompt) and shows a
-- Yes/Cancel dialog. Presentation only — the server owns the destination and the
-- teleport; this just collects the player's choice and echoes ConfirmTravel /
-- CancelTravel. Built once, reused (mobile-friendly: no per-open allocation).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TravelRemotes = require(ReplicatedStorage.Shared.World.TravelRemotes)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Palette (mirrors UITheme so the modal matches the rest of the demo UI).
local COLOR = {
    backdrop = Color3.fromRGB(8, 9, 14),
    panel = Color3.fromRGB(30, 33, 46),
    accent = Color3.fromRGB(64, 156, 255),
    confirm = Color3.fromRGB(64, 214, 122),
    cancel = Color3.fromRGB(72, 84, 92),
    text = Color3.fromRGB(245, 247, 255),
    textDim = Color3.fromRGB(168, 176, 196),
    textOnBright = Color3.fromRGB(20, 16, 28),
}

local function corner(parent: Instance, radius: number)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius)
    c.Parent = parent
end

-- ── Build (once) ─────────────────────────────────────────────────────────────
local gui = Instance.new("ScreenGui")
gui.Name = "TravelConfirmUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 50
gui.Enabled = false
gui.Parent = playerGui

local backdrop = Instance.new("TextButton")
backdrop.Name = "Backdrop"
backdrop.Size = UDim2.fromScale(1, 1)
backdrop.BackgroundColor3 = COLOR.backdrop
backdrop.BackgroundTransparency = 0.4
backdrop.AutoButtonColor = false
backdrop.Text = ""
backdrop.Parent = gui

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromOffset(340, 200)
panel.BackgroundColor3 = COLOR.panel
panel.Parent = backdrop
corner(panel, 14)

local pad = Instance.new("UIPadding")
pad.PaddingTop = UDim.new(0, 18)
pad.PaddingBottom = UDim.new(0, 18)
pad.PaddingLeft = UDim.new(0, 18)
pad.PaddingRight = UDim.new(0, 18)
pad.Parent = panel

local titleLabel = Instance.new("TextLabel")
titleLabel.Name = "Title"
titleLabel.Size = UDim2.new(1, 0, 0, 34)
titleLabel.BackgroundTransparency = 1
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextSize = 24
titleLabel.TextColor3 = COLOR.text
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Text = "Travel"
titleLabel.Parent = panel

local bodyLabel = Instance.new("TextLabel")
bodyLabel.Name = "Body"
bodyLabel.Position = UDim2.fromOffset(0, 42)
bodyLabel.Size = UDim2.new(1, 0, 0, 80)
bodyLabel.BackgroundTransparency = 1
bodyLabel.Font = Enum.Font.Gotham
bodyLabel.TextSize = 16
bodyLabel.TextColor3 = COLOR.textDim
bodyLabel.TextWrapped = true
bodyLabel.TextXAlignment = Enum.TextXAlignment.Left
bodyLabel.TextYAlignment = Enum.TextYAlignment.Top
bodyLabel.Text = ""
bodyLabel.Parent = panel

local cancelBtn = Instance.new("TextButton")
cancelBtn.Name = "Cancel"
cancelBtn.AnchorPoint = Vector2.new(0, 1)
cancelBtn.Position = UDim2.fromScale(0, 1)
cancelBtn.Size = UDim2.new(0.48, 0, 0, 44)
cancelBtn.BackgroundColor3 = COLOR.cancel
cancelBtn.Font = Enum.Font.GothamBold
cancelBtn.TextSize = 18
cancelBtn.TextColor3 = COLOR.text
cancelBtn.Text = "Cancel"
cancelBtn.AutoButtonColor = true
cancelBtn.Parent = panel
corner(cancelBtn, 10)

local confirmBtn = Instance.new("TextButton")
confirmBtn.Name = "Confirm"
confirmBtn.AnchorPoint = Vector2.new(1, 1)
confirmBtn.Position = UDim2.fromScale(1, 1)
confirmBtn.Size = UDim2.new(0.48, 0, 0, 44)
confirmBtn.BackgroundColor3 = COLOR.confirm
confirmBtn.Font = Enum.Font.GothamBold
confirmBtn.TextSize = 18
confirmBtn.TextColor3 = COLOR.textOnBright
confirmBtn.Text = "Go"
confirmBtn.AutoButtonColor = true
confirmBtn.Parent = panel
corner(confirmBtn, 10)

-- ── Behavior ─────────────────────────────────────────────────────────────────
local isOpen = false

local function hide()
    if not isOpen then
        return
    end
    isOpen = false
    gui.Enabled = false
end

local function show(payload: any)
    if typeof(payload) ~= "table" then
        return
    end
    titleLabel.Text = tostring(payload.title or "Travel")
    bodyLabel.Text = tostring(payload.body or "")
    confirmBtn.Text = tostring(payload.confirmText or "Go")
    isOpen = true
    gui.Enabled = true
end

confirmBtn.Activated:Connect(function()
    if not isOpen then
        return
    end
    hide()
    TravelRemotes.ConfirmTravel:FireServer()
end)

local function dismiss()
    if not isOpen then
        return
    end
    hide()
    TravelRemotes.CancelTravel:FireServer()
end

cancelBtn.Activated:Connect(dismiss)
backdrop.Activated:Connect(dismiss)

TravelRemotes.OpenTravelConfirm.OnClientEvent:Connect(show)
