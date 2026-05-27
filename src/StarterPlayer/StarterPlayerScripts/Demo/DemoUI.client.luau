--!strict
-- DemoUI.client.luau
--
-- Client UI for the "Brainrot Inc." CAPTURE + INVENTORY demo.
--
-- The 5 creatures are Models pre-placed in the Workspace (`Brainrot_HYPER` ..
-- `Brainrot_REBEL`); each carries a server-built "Hold F to Catch" ProximityPrompt
-- whose built-in prompt UI shows automatically near the creature. This script
-- does NOT build that prompt — it renders:
--   1. A bottom-center HINT: "Walk up to a Brainrot and hold [F] to catch it!".
--   2. A top-right 🎒 INVENTORY (N) button. Click it OR press B to TOGGLE a panel.
--   3. The INVENTORY PANEL (read-only): a scrolling list of caught creatures
--      (emoji + name + color-coded personality badge), a count, a ✕ close
--      button, and an "Empty — go catch some!" state. Updates live on
--      InventoryUpdate. Placement is NOT done from here anymore (see #5).
--   4. A MIDDLE-LEFT COIN HUD: 🪙 coins (AUTO-COLLECT — the total climbs on its
--      own) + a small "+N/s" rate line. The counter is driven every frame
--      (throttled) from DemoClient.getDisplayCoins() so it rises continuously.
--   5. The PLACE MENU (modal): opened by DemoClient.PlaceMenuRequested when the
--      player triggers an EMPTY podium's "Place Brainrot" (F) prompt. Lists the
--      player's caught Brainrots as TAPPABLE rows; tapping one sends
--      DeployToStand(standIndex, personality) and closes the menu. The player
--      picks the podium (which prompt) AND the creature (which row).
--
-- Presentation only: it never owns the inventory. The server is authoritative and
-- DemoClient is the single source of truth (DemoClient.Inventory).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Trove = require(Packages:WaitForChild("Trove"))

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DemoRemotes = require(Shared:WaitForChild("Demo"):WaitForChild("DemoRemotes"))

local UITheme = require(script.Parent:WaitForChild("UITheme"))
local DemoClient = require(script.Parent:WaitForChild("DemoClient"))

local apply = UITheme.apply
local corner = UITheme.corner
local stroke = UITheme.stroke
local padding = UITheme.padding
local Color = UITheme.Color
local Font = UITheme.Font

-- ── Layout constants (no magic numbers buried in calls) ─────────────────────
local TOGGLE_KEY = Enum.KeyCode.B
local PANEL_WIDTH = 360
local PANEL_HEIGHT = 460
local ROW_HEIGHT = 56
local ROW_BADGE_WIDTH = 78
local ROW_BADGE_GAP = 6 -- gap between the name and the right-edge badge
-- COMBAT (Tahap 2): a per-row "⚔ Summon" button on the inventory panel rows.
local ROW_SUMMON_WIDTH = 96 -- width of the Summon button
local ROW_SUMMON_GAP = 6 -- gap between the Summon button and the badge
-- MOBILE: comfortable finger target for the row Summon button (>=44px tall).
local ROW_SUMMON_HEIGHT = 44
-- Inventory panel ✕ close button (bumped to a >=44px touch target for mobile).
local PANEL_CLOSE_SIZE = 44

-- MOBILE BAG TOGGLE: an on-screen button that opens/closes the inventory panel
-- (same path as the B key). Anchored bottom-RIGHT but offset UP so it clears
-- Roblox's default jump button (bottom-right) and never overlaps it.
local BAG_SIZE = 56
local BAG_MARGIN_X = 16
local BAG_MARGIN_Y = 150 -- lifted above the default mobile jump button

-- Place menu (modal opened from a podium's Place (F) prompt).
local PLACE_WIDTH = 380
local PLACE_HEIGHT = 480
local PLACE_TITLE_HEIGHT = 40
local PLACE_LIST_TOP = 76
local PLACE_CLOSE_SIZE = 44 -- MOBILE: >=44px touch target

-- Coin HUD (middle-left; top-right is the inventory button). AUTO-COLLECT: no
-- COLLECT button — just the climbing 🪙 total + a small "+N/s" rate line.
local HUD_WIDTH = 240
local HUD_HEIGHT = 72
-- How often (seconds) the climbing coin counter is refreshed from the local
-- extrapolation. ~10 Hz keeps it smooth without burning frames on mobile.
local HUD_REFRESH_SEC = 0.1

-- ── Top-level lifetime ───────────────────────────────────────────────────────
local rootTrove = Trove.new()

local playerGui = LocalPlayer:WaitForChild("PlayerGui")

local screen = rootTrove:Add(Instance.new("ScreenGui"))
screen.Name = "BrainrotDemoUI"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true
-- MOBILE SAFE AREA: keep HUD out from under notches / the home indicator. With
-- CoreUISafeInsets, anchored elements (corners, edges) are inset by the device's
-- safe-area so nothing important hides behind hardware cutouts on phones.
screen.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.DisplayOrder = 10
screen.Parent = playerGui

-- ── Responsive scale ─────────────────────────────────────────────────────────
-- Laid out against a ~1280x720 reference; a viewport-driven UIScale keeps it from
-- clipping / looking oversized on other resolutions + small play windows.
local uiScale = Instance.new("UIScale")
uiScale.Parent = screen

local function updateScale()
    local cam = workspace.CurrentCamera
    if not cam then
        return
    end
    local vp = cam.ViewportSize
    if vp.X < 1 or vp.Y < 1 then
        return
    end
    uiScale.Scale = math.clamp(math.min(vp.X / 1280, vp.Y / 720), 0.45, 1.15)
end

updateScale()
do
    local cam = workspace.CurrentCamera
    if cam then
        rootTrove:Add(cam:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale))
    end
    rootTrove:Add(workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
        local newCam = workspace.CurrentCamera
        if newCam then
            rootTrove:Add(newCam:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale))
            updateScale()
        end
    end))
end

-- ════════════════════════════════════════════════════════════════════════════
-- HINT (bottom center)
-- ════════════════════════════════════════════════════════════════════════════
apply(Instance.new("TextLabel"), {
    Name = "Hint",
    AnchorPoint = Vector2.new(0.5, 1),
    Position = UDim2.new(0.5, 0, 1, -16),
    Size = UDim2.fromOffset(560, 48),
    BackgroundColor3 = Color.Panel,
    BackgroundTransparency = 0.15,
    BorderSizePixel = 0,
    FontFace = Font.Bold,
    TextColor3 = Color.Text,
    TextScaled = true,
    Text = "Walk up to a Brainrot and hold [F] to catch it!",
    Parent = screen,
}, { corner(12), stroke(Color.Stroke, 2), padding(10) })

-- ════════════════════════════════════════════════════════════════════════════
-- INVENTORY BUTTON (top right)
-- ════════════════════════════════════════════════════════════════════════════
local inventoryButton = apply(Instance.new("TextButton"), {
    Name = "InventoryButton",
    AnchorPoint = Vector2.new(1, 0),
    Position = UDim2.new(1, -16, 0, 16),
    Size = UDim2.fromOffset(220, 56),
    AutoButtonColor = true,
    BackgroundColor3 = Color.CrateButton,
    BorderSizePixel = 0,
    FontFace = Font.Heavy,
    TextColor3 = Color.Text,
    TextScaled = true,
    Text = "🎒 INVENTORY (0)",
    Parent = screen,
}, { corner(14), stroke(Color.Stroke, 2), padding(10) })

-- ════════════════════════════════════════════════════════════════════════════
-- COIN HUD (MIDDLE LEFT) — AUTO-COLLECT: climbing 🪙 total + "+N/s" rate line
-- ════════════════════════════════════════════════════════════════════════════
local coinHud = apply(Instance.new("Frame"), {
    Name = "CoinHud",
    AnchorPoint = Vector2.new(0, 0.5),
    Position = UDim2.new(0, 16, 0.5, 0),
    Size = UDim2.fromOffset(HUD_WIDTH, HUD_HEIGHT),
    BackgroundColor3 = Color.Panel,
    BorderSizePixel = 0,
    Parent = screen,
}, { corner(14), stroke(Color.Stroke, 2), padding(10) })

local coinLabel = apply(Instance.new("TextLabel"), {
    Name = "Coins",
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(0, 0),
    Size = UDim2.new(1, 0, 0, 30),
    FontFace = Font.Heavy,
    TextColor3 = Color.Coin,
    TextScaled = true,
    TextXAlignment = Enum.TextXAlignment.Left,
    Text = "🪙 0",
    Parent = coinHud,
})

local rateLabel = apply(Instance.new("TextLabel"), {
    Name = "Rate",
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(0, 32),
    Size = UDim2.new(1, 0, 0, 18),
    FontFace = Font.Bold,
    TextColor3 = Color.TextDim,
    TextScaled = true,
    TextXAlignment = Enum.TextXAlignment.Left,
    Text = "+0/s",
    Parent = coinHud,
})

-- ════════════════════════════════════════════════════════════════════════════
-- BAG TOGGLE BUTTON (bottom-right, lifted) — MOBILE entry point to the inventory
-- panel. Toggles the SAME panel as the B key (both call toggle() below). Anchored
-- bottom-right but offset UP via BAG_MARGIN_Y so it clears Roblox's default mobile
-- jump button. Shown on all platforms; on PC the B shortcut still works too.
-- ════════════════════════════════════════════════════════════════════════════
local bagButton = apply(Instance.new("TextButton"), {
    Name = "BagButton",
    AnchorPoint = Vector2.new(1, 1),
    Position = UDim2.new(1, -BAG_MARGIN_X, 1, -BAG_MARGIN_Y),
    Size = UDim2.fromOffset(BAG_SIZE, BAG_SIZE),
    AutoButtonColor = true,
    BackgroundColor3 = Color.CrateButton,
    BorderSizePixel = 0,
    FontFace = Font.Heavy,
    TextColor3 = Color.Text,
    TextScaled = true,
    Text = "🎒",
    ZIndex = 15,
    Parent = screen,
}, { corner(16), stroke(Color.Stroke, 2), padding(8) })

-- ════════════════════════════════════════════════════════════════════════════
-- INVENTORY PANEL (centered-right)
-- ════════════════════════════════════════════════════════════════════════════
local panel = apply(Instance.new("Frame"), {
    Name = "InventoryPanel",
    Visible = false,
    AnchorPoint = Vector2.new(1, 0.5),
    Position = UDim2.new(1, -16, 0.5, 0),
    Size = UDim2.fromOffset(PANEL_WIDTH, PANEL_HEIGHT),
    BackgroundColor3 = Color.Panel,
    BorderSizePixel = 0,
    ZIndex = 20,
    Parent = screen,
}, { corner(20), stroke(Color.Stroke, 3), padding(14) })

apply(Instance.new("TextLabel"), {
    Name = "Title",
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(0, 0),
    Size = UDim2.new(1, -(PANEL_CLOSE_SIZE + 8), 0, 40),
    FontFace = Font.Heavy,
    TextColor3 = Color.Text,
    TextScaled = true,
    TextXAlignment = Enum.TextXAlignment.Left,
    Text = "INVENTORY",
    ZIndex = 21,
    Parent = panel,
})

local countLabel = apply(Instance.new("TextLabel"), {
    Name = "Count",
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(0, 44),
    Size = UDim2.new(1, 0, 0, 24),
    FontFace = Font.Bold,
    TextColor3 = Color.TextDim,
    TextScaled = true,
    TextXAlignment = Enum.TextXAlignment.Left,
    Text = "0 caught",
    ZIndex = 21,
    Parent = panel,
})

local closeButton = apply(Instance.new("TextButton"), {
    Name = "Close",
    AnchorPoint = Vector2.new(1, 0),
    Position = UDim2.fromScale(1, 0),
    Size = UDim2.fromOffset(PANEL_CLOSE_SIZE, PANEL_CLOSE_SIZE),
    BackgroundColor3 = Color.SlotEmpty,
    BorderSizePixel = 0,
    FontFace = Font.Heavy,
    TextColor3 = Color.Text,
    TextScaled = true,
    Text = "✕",
    ZIndex = 22,
    Parent = panel,
}, { corner(10), padding(8) })

local list = apply(Instance.new("ScrollingFrame"), {
    Name = "List",
    Position = UDim2.fromOffset(0, 76),
    Size = UDim2.new(1, 0, 1, -76),
    BackgroundColor3 = Color.SlotEmpty,
    BorderSizePixel = 0,
    ScrollBarThickness = 6,
    CanvasSize = UDim2.new(),
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
    ZIndex = 21,
    Parent = panel,
}, { corner(12), padding(8) })

apply(Instance.new("UIListLayout"), {
    FillDirection = Enum.FillDirection.Vertical,
    SortOrder = Enum.SortOrder.LayoutOrder,
    Padding = UDim.new(0, 6),
    Parent = list,
})

local emptyLabel = apply(Instance.new("TextLabel"), {
    Name = "Empty",
    BackgroundTransparency = 1,
    Size = UDim2.new(1, 0, 0, 40),
    FontFace = Font.Bold,
    TextColor3 = Color.TextDim,
    TextScaled = true,
    Text = "Empty — go catch some!",
    Visible = false,
    ZIndex = 21,
    Parent = list,
})

-- A reusable trove for the rendered rows so we cleanly clear + rebuild each update.
local rowsTrove = rootTrove:Extend()

-- Build one creature row into `parent`: emoji + name + color-coded personality
-- badge. Shared by the read-only INVENTORY panel and the tappable PLACE MENU.
--   * `trove` owns the row (so the caller controls its lifetime).
--   * `zBase` is the row's ZIndex (children sit at zBase+1).
--   * `onTap` (optional) makes the whole row a TextButton; tapping calls it. When
--     nil, the row is a plain Frame (read-only inventory view).
--   * `onSummon` (optional) adds a small "⚔ Summon" button before the badge
--     (used only by the read-only INVENTORY panel rows). Tapping it calls onSummon.
local function buildRow(
    parent: Instance,
    trove: typeof(rootTrove),
    item: DemoClient.InventoryItem,
    order: number,
    zBase: number,
    onTap: (() -> ())?,
    onSummon: (() -> ())?
)
    local theme = UITheme.personality(item.personality)
    local childZ = zBase + 1
    -- Reserve horizontal space for the Summon button when present so the Name
    -- never overlaps it.
    local summonReserve = if onSummon then ROW_SUMMON_WIDTH + ROW_SUMMON_GAP else 0

    local rowProps = {
        Name = "Row",
        LayoutOrder = order,
        Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
        BackgroundColor3 = Color.PanelLight,
        BorderSizePixel = 0,
        ZIndex = zBase,
        Parent = parent,
    }

    local row: Instance
    if onTap then
        rowProps.AutoButtonColor = true
        local button = trove:Add(apply(Instance.new("TextButton"), rowProps, { corner(10), padding(6) }))
        button.Text = ""
        trove:Add(button.Activated:Connect(onTap))
        row = button
    else
        row = trove:Add(apply(Instance.new("Frame"), rowProps, { corner(10), padding(6) }))
    end

    apply(Instance.new("TextLabel"), {
        Name = "Emoji",
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(0, 0),
        Size = UDim2.new(0, ROW_HEIGHT - 12, 1, 0),
        FontFace = Font.Regular,
        TextColor3 = Color.Text,
        TextScaled = true,
        Text = theme.emoji,
        ZIndex = childZ,
        Parent = row,
    })

    apply(Instance.new("TextLabel"), {
        Name = "Name",
        BackgroundTransparency = 1,
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, ROW_HEIGHT, 0.5, 0),
        Size = UDim2.new(1, -ROW_HEIGHT - ROW_BADGE_WIDTH - ROW_BADGE_GAP - summonReserve, 1, -12),
        FontFace = Font.Bold,
        TextColor3 = Color.Text,
        TextScaled = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        Text = item.name,
        ZIndex = childZ,
        Parent = row,
    })

    -- COMBAT (Tahap 2): the "⚔ Summon" button (inventory rows only). Sits just to
    -- the LEFT of the right-edge badge. Tapping it summons this Brainrot as a
    -- temporary fighter (the server validates ownership; the bag is NOT consumed).
    if onSummon then
        local summonButton = trove:Add(apply(Instance.new("TextButton"), {
            Name = "Summon",
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -(ROW_BADGE_WIDTH + ROW_SUMMON_GAP), 0.5, 0),
            Size = UDim2.fromOffset(ROW_SUMMON_WIDTH, ROW_SUMMON_HEIGHT),
            AutoButtonColor = true,
            BackgroundColor3 = Color.Collect,
            BorderSizePixel = 0,
            FontFace = Font.Heavy,
            TextColor3 = Color.TextOnBright,
            TextScaled = true,
            Text = "⚔ Summon",
            ZIndex = childZ,
            Parent = row,
        }, { corner(8), padding(6) }))
        trove:Add(summonButton.Activated:Connect(onSummon))
    end

    -- Personality badge sits at the right edge.
    apply(Instance.new("TextLabel"), {
        Name = "Badge",
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.fromScale(1, 0.5),
        Size = UDim2.fromOffset(ROW_BADGE_WIDTH, ROW_HEIGHT - 18),
        BackgroundColor3 = theme.color,
        BorderSizePixel = 0,
        FontFace = Font.Heavy,
        TextColor3 = Color.TextOnBright,
        TextScaled = true,
        Text = string.upper(item.personality),
        ZIndex = childZ,
        Parent = row,
    }, { corner(8), padding(6) })
end

-- ════════════════════════════════════════════════════════════════════════════
-- RENDER
-- ════════════════════════════════════════════════════════════════════════════
local function render(inventory: DemoClient.Inventory)
    rowsTrove:Clean()

    local n = #inventory
    print(("[Inv][ui] render count=%d"):format(n))
    inventoryButton.Text = string.format("🎒 INVENTORY (%d)", n)
    countLabel.Text = if n == 1 then "1 caught" else string.format("%d caught", n)

    emptyLabel.Visible = n == 0
    for i, item in inventory do
        -- Read-only inventory rows (no onTap): placement happens via the podium
        -- Place (F) prompt -> place menu, not from this panel. The row DOES get a
        -- "⚔ Summon" button (Tahap 2) to send this Brainrot out to auto-battle.
        local personality = item.personality
        buildRow(list, rowsTrove, item, i, 22, nil, function()
            print("[Combat][ui] summon " .. personality)
            DemoClient.summon(personality)
        end)
    end
end

-- ════════════════════════════════════════════════════════════════════════════
-- TOGGLE
-- ════════════════════════════════════════════════════════════════════════════
local isOpen = false

local function setOpen(open: boolean)
    isOpen = open
    panel.Visible = open
    print("[UI] inventory toggled", isOpen)
end

local function toggle()
    setOpen(not isOpen)
end

rootTrove:Add(inventoryButton.Activated:Connect(toggle))
-- Mobile on-screen Bag button shares the EXACT same toggle path as the B key.
rootTrove:Add(bagButton.Activated:Connect(toggle))
rootTrove:Add(closeButton.Activated:Connect(function()
    setOpen(false)
end))

rootTrove:Add(UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
    if processed then
        return
    end
    if input.KeyCode == TOGGLE_KEY then
        toggle()
    end
end))

-- ════════════════════════════════════════════════════════════════════════════
-- PLACE MENU (modal) — opened from a podium's "Place Brainrot" (F) prompt.
-- Lists the player's caught Brainrots as TAPPABLE rows; tapping one sends
-- DeployToStand(standIndex, personality) and closes the menu. Separate from the
-- B inventory panel (which is now read-only).
-- ════════════════════════════════════════════════════════════════════════════

-- Full-screen backdrop: dims the scene + closes the menu when tapped outside.
local placeBackdrop = apply(Instance.new("TextButton"), {
    Name = "PlaceBackdrop",
    Visible = false,
    Size = UDim2.fromScale(1, 1),
    BackgroundColor3 = Color.Backdrop,
    BackgroundTransparency = 0.4,
    BorderSizePixel = 0,
    AutoButtonColor = false,
    Text = "",
    ZIndex = 30,
    Parent = screen,
})

-- A TextButton (not a Frame) so taps ON the panel are ABSORBED here and do NOT
-- fall through to the backdrop button beneath it (which would close the menu).
-- The handler is a no-op; only the backdrop / ✕ / rows act.
local placePanel = apply(Instance.new("TextButton"), {
    Name = "PlacePanel",
    AutoButtonColor = false,
    Text = "",
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.fromOffset(PLACE_WIDTH, PLACE_HEIGHT),
    BackgroundColor3 = Color.Panel,
    BorderSizePixel = 0,
    ZIndex = 31,
    Parent = placeBackdrop,
}, { corner(20), stroke(Color.Stroke, 3), padding(14) })

local placeTitle = apply(Instance.new("TextLabel"), {
    Name = "Title",
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(0, 0),
    Size = UDim2.new(1, -(PLACE_CLOSE_SIZE + 8), 0, PLACE_TITLE_HEIGHT),
    FontFace = Font.Heavy,
    TextColor3 = Color.Text,
    TextScaled = true,
    TextXAlignment = Enum.TextXAlignment.Left,
    Text = "Place on Podium",
    ZIndex = 32,
    Parent = placePanel,
})

apply(Instance.new("TextLabel"), {
    Name = "Subtitle",
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(0, 44),
    Size = UDim2.new(1, 0, 0, 24),
    FontFace = Font.Bold,
    TextColor3 = Color.TextDim,
    TextScaled = true,
    TextXAlignment = Enum.TextXAlignment.Left,
    Text = "Tap a Brainrot to place it here",
    ZIndex = 32,
    Parent = placePanel,
})

local placeClose = apply(Instance.new("TextButton"), {
    Name = "Close",
    AnchorPoint = Vector2.new(1, 0),
    Position = UDim2.fromScale(1, 0),
    Size = UDim2.fromOffset(PLACE_CLOSE_SIZE, PLACE_CLOSE_SIZE),
    BackgroundColor3 = Color.SlotEmpty,
    BorderSizePixel = 0,
    FontFace = Font.Heavy,
    TextColor3 = Color.Text,
    TextScaled = true,
    Text = "✕",
    ZIndex = 33,
    Parent = placePanel,
}, { corner(10), padding(8) })

local placeList = apply(Instance.new("ScrollingFrame"), {
    Name = "List",
    Position = UDim2.fromOffset(0, PLACE_LIST_TOP),
    Size = UDim2.new(1, 0, 1, -PLACE_LIST_TOP),
    BackgroundColor3 = Color.SlotEmpty,
    BorderSizePixel = 0,
    ScrollBarThickness = 6,
    CanvasSize = UDim2.new(),
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
    ZIndex = 32,
    Parent = placePanel,
}, { corner(12), padding(8) })

apply(Instance.new("UIListLayout"), {
    FillDirection = Enum.FillDirection.Vertical,
    SortOrder = Enum.SortOrder.LayoutOrder,
    Padding = UDim.new(0, 6),
    Parent = placeList,
})

local placeEmptyLabel = apply(Instance.new("TextLabel"), {
    Name = "Empty",
    BackgroundTransparency = 1,
    Size = UDim2.new(1, 0, 0, 40),
    FontFace = Font.Bold,
    TextColor3 = Color.TextDim,
    TextScaled = true,
    Text = "No Brainrots yet — go catch some!",
    Visible = false,
    ZIndex = 33,
    Parent = placeList,
})

-- Trove for the place menu's rows (cleared + rebuilt each time it opens).
local placeRowsTrove = rootTrove:Extend()

local function closePlaceMenu()
    placeBackdrop.Visible = false
    placeRowsTrove:Clean()
end

-- Open the place menu for `standIndex` and render the current inventory as
-- tappable rows. Tapping a row deploys THAT creature on THIS stand, then closes.
local function openPlaceMenu(standIndex: number)
    print("[Place] menu for stand " .. standIndex)
    placeRowsTrove:Clean()

    placeTitle.Text = string.format("Place on Podium #%d", standIndex)

    local inventory = DemoClient.Inventory
    local n = #inventory
    placeEmptyLabel.Visible = n == 0

    for i, item in inventory do
        local personality = item.personality
        buildRow(placeList, placeRowsTrove, item, i, 32, function()
            print("[Place] chose " .. personality .. " for stand " .. standIndex)
            DemoClient.deployToStand(standIndex, personality)
            closePlaceMenu()
        end)
    end

    placeBackdrop.Visible = true
end

rootTrove:Add(placeClose.Activated:Connect(closePlaceMenu))
-- Backdrop tap (outside the panel) closes the menu. Taps on the panel are NOT
-- forwarded to the backdrop button, so this only fires for outside taps.
rootTrove:Add(placeBackdrop.Activated:Connect(closePlaceMenu))

DemoClient.PlaceMenuRequested:Connect(openPlaceMenu)

-- ════════════════════════════════════════════════════════════════════════════
-- COIN HUD render (AUTO-COLLECT) — the total climbs continuously on its own
-- ════════════════════════════════════════════════════════════════════════════

-- Paint the climbing total + the "+N/s" rate line. Reads the local extrapolation
-- (DemoClient.getDisplayCoins) so the number rises smoothly between server pushes.
local lastShownCoins = -1

local function paintCoins()
    local coins = DemoClient.getDisplayCoins()
    if coins ~= lastShownCoins then
        lastShownCoins = coins
        coinLabel.Text = string.format("🪙 %d", coins)
    end
    rateLabel.Text = string.format("+%d/s", math.floor(DemoClient.getRate() + 0.5))
end

-- Drive the counter every frame, throttled to ~HUD_REFRESH_SEC, so it ticks up
-- continuously without burning frames (mobile-friendly).
local refreshAccum = 0
rootTrove:Add(RunService.Heartbeat:Connect(function(dt: number)
    refreshAccum += dt
    if refreshAccum < HUD_REFRESH_SEC then
        return
    end
    refreshAccum = 0
    paintCoins()
end))

-- A server push re-anchors the extrapolation: repaint immediately so the rate
-- line + total reflect the new snapshot without waiting for the next tick.
DemoClient.CoinsChanged:Connect(paintCoins)

-- ════════════════════════════════════════════════════════════════════════════
-- MOMENT BANNER (S->C) — a transient top-center toast. Used by the server's
-- WELCOME-BACK offline-earnings message on rejoin. PAYLOAD: { kind, text, coins };
-- this handler displays `text` and ignores the rest (forward-compatible). The
-- server is authoritative for the coin number; this is presentation only.
-- ════════════════════════════════════════════════════════════════════════════
type MomentPayload = {
    kind: string,
    text: string,
    coins: number?,
}

local momentBanner = apply(Instance.new("TextLabel"), {
    Name = "MomentBanner",
    Visible = false,
    AnchorPoint = Vector2.new(0.5, 0),
    Position = UDim2.new(0.5, 0, 0, 88),
    Size = UDim2.fromOffset(520, 52),
    BackgroundColor3 = Color.Panel,
    BackgroundTransparency = 0.1,
    BorderSizePixel = 0,
    FontFace = Font.Heavy,
    TextColor3 = Color.Coin,
    TextScaled = true,
    Text = "",
    ZIndex = 40,
    Parent = screen,
}, { corner(12), stroke(Color.Stroke, 2), padding(10) })

-- Monotonic token so a newer Moment cancels the previous one's hide timer (no
-- stacking / no premature hide of a fresh banner).
local momentToken = 0
local MOMENT_LIFE_SEC = 4

local function showMoment(payload: MomentPayload)
    if type(payload) ~= "table" or type(payload.text) ~= "string" then
        return
    end
    momentToken += 1
    local myToken = momentToken
    momentBanner.Text = payload.text
    momentBanner.Visible = true
    task.delay(MOMENT_LIFE_SEC, function()
        if momentToken == myToken then
            momentBanner.Visible = false
        end
    end)
end

rootTrove:Add(DemoRemotes.Moment.OnClientEvent:Connect(showMoment))

-- COMBAT (Tahap 2): show battle win/KO feedback via the SAME transient banner.
-- DemoClient translates the BattleEvent into a banner-ready { kind, text, coins }.
DemoClient.BattleFeedback:Connect(showMoment)

-- ════════════════════════════════════════════════════════════════════════════
-- WIRE SIGNALS + INIT
-- ════════════════════════════════════════════════════════════════════════════
print("[Inv][ui] wiring InventoryChanged signal...")
DemoClient.InventoryChanged:Connect(function(inventory)
    render(inventory)
end)

-- Tear everything down if the ScreenGui is destroyed (respawn-safe + leave-safe).
screen.AncestryChanged:Connect(function(_, parent)
    if parent == nil then
        rootTrove:Destroy()
    end
end)

print("[Inv][ui] calling DemoClient.init()")
DemoClient.init()
render(DemoClient.Inventory)
paintCoins()
print("[Inv][ui] startup complete")
