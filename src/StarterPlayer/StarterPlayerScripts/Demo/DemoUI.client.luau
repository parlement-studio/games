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
local DemoFolder = Shared:WaitForChild("Demo")
local DemoRemotes = require(DemoFolder:WaitForChild("DemoRemotes"))
-- DemoConfig is replicated read-only: the stat sheet reads the personality blurb /
-- prodMult to build the EFFECT one-liner client-side, and the showroom stand count
-- to drive the deploy-from-sheet sweep. Display/tuning values only — the server
-- stays authoritative for all game state.
local DemoConfig = require(DemoFolder:WaitForChild("DemoConfig"))

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
-- INVENTORY GRID: finger-sized cards laid out by a UIGridLayout that reflows.
-- A card is a square personality-color tile (emoji + short name + ⭐ Lv badge);
-- tapping it opens the stat sheet. >=72px keeps a comfortable tap target.
local CARD_SIZE = 84 -- square card edge (>=72px finger target)
local CARD_GAP = 8 -- spacing between cards in the grid
local CARD_EMOJI_HEIGHT = 40 -- height of the big emoji block at the card top
local CARD_NAME_HEIGHT = 16 -- personality short-name line under the emoji
local CARD_BADGE_HEIGHT = 18 -- ⭐ Lv N badge line at the card bottom
-- Inventory panel ✕ close button (bumped to a >=44px touch target for mobile).
local PANEL_CLOSE_SIZE = 44

-- ── STAT SHEET (per-monster detail modal) ──────────────────────────────────
-- A centered, closeable modal opened by tapping an inventory card. Minimalist:
-- header (emoji + name + ⭐ Lv + ✕), an XP bar, an HP/Power stat row, the effect
-- one-liner + lifetime flavor (wins / coins made), then the action buttons.
local SHEET_WIDTH = 380
local SHEET_HEIGHT = 360
local SHEET_CLOSE_SIZE = 44 -- MOBILE: >=44px touch target
local SHEET_HEADER_HEIGHT = 44
local SHEET_XP_TOP = 56 -- y of the XP bar block
local SHEET_XP_HEIGHT = 28 -- XP bar block height
local SHEET_XP_FILL_HEIGHT = 14 -- the filled track inside the XP block
local SHEET_STATS_TOP = 100 -- y of the HP/Power stat row
local SHEET_STATS_HEIGHT = 40
local SHEET_EFFECT_TOP = 152 -- y of the effect one-liner
local SHEET_EFFECT_HEIGHT = 28
local SHEET_FLAVOR_TOP = 184 -- y of the wins / coins-made line
local SHEET_FLAVOR_HEIGHT = 26
local SHEET_ACTIONS_HEIGHT = 52 -- height of the bottom action-button row (>=44px)
local SHEET_ACTION_GAP = 12 -- gap between the two action buttons
local SHEET_DIVIDER_HEIGHT = 2 -- thin divider rule between sections

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

-- Title doubles as the count header: "🎒 Brainrots (N/cap)".
local titleLabel = apply(Instance.new("TextLabel"), {
    Name = "Title",
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(0, 0),
    Size = UDim2.new(1, -(PANEL_CLOSE_SIZE + 8), 0, 40),
    FontFace = Font.Heavy,
    TextColor3 = Color.Text,
    TextScaled = true,
    TextXAlignment = Enum.TextXAlignment.Left,
    Text = "🎒 Brainrots (0)",
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

-- GRID: cards reflow across the panel width and wrap to new rows; the scroll +
-- AutomaticCanvasSize handle many monsters. Centered horizontally so a partial
-- last row stays balanced.
apply(Instance.new("UIGridLayout"), {
    CellSize = UDim2.fromOffset(CARD_SIZE, CARD_SIZE),
    CellPadding = UDim2.fromOffset(CARD_GAP, CARD_GAP),
    FillDirection = Enum.FillDirection.Horizontal,
    HorizontalAlignment = Enum.HorizontalAlignment.Center,
    SortOrder = Enum.SortOrder.LayoutOrder,
    Parent = list,
})

-- Empty-state label is a SIBLING of the grid (parented to the panel, not `list`)
-- so the UIGridLayout never tries to size it into an 84px cell. Centered over the
-- scroll area; shown only when the bag is empty.
local emptyLabel = apply(Instance.new("TextLabel"), {
    Name = "Empty",
    BackgroundTransparency = 1,
    AnchorPoint = Vector2.new(0.5, 0),
    Position = UDim2.new(0.5, 0, 0, 92),
    Size = UDim2.new(1, -16, 0, 40),
    FontFace = Font.Bold,
    TextColor3 = Color.TextDim,
    TextScaled = true,
    Text = "Empty — go catch some!",
    Visible = false,
    ZIndex = 22,
    Parent = panel,
})

-- A reusable trove for the rendered cards so we cleanly clear + rebuild each update.
local cardsTrove = rootTrove:Extend()

-- Build one tappable GRID CARD into `parent` (the inventory grid): a square,
-- personality-COLOR tile with the personality EMOJI, its short name, and a ⭐ Lv N
-- badge. The whole card is a TextButton; tapping it calls `onTap` (which opens the
-- stat sheet for this item). `trove` owns the card so the caller controls lifetime;
-- `zBase` is the card's ZIndex (children sit at zBase+1). Cards are display-only —
-- the actual Summon/Deploy actions live in the stat sheet.
local function buildCard(
    parent: Instance,
    trove: typeof(rootTrove),
    item: DemoClient.InventoryItem,
    order: number,
    zBase: number,
    onTap: () -> ()
)
    local theme = UITheme.personality(item.personality)
    local childZ = zBase + 1

    local card = trove:Add(apply(Instance.new("TextButton"), {
        Name = "Card",
        LayoutOrder = order,
        AutoButtonColor = true,
        Text = "",
        BackgroundColor3 = theme.color,
        BorderSizePixel = 0,
        ZIndex = zBase,
        Parent = parent,
    }, { corner(12), stroke(Color.Stroke, 2), padding(4) }))
    trove:Add(card.Activated:Connect(onTap))

    -- Big personality emoji at the top of the card.
    apply(Instance.new("TextLabel"), {
        Name = "Emoji",
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(0, 0),
        Size = UDim2.new(1, 0, 0, CARD_EMOJI_HEIGHT),
        FontFace = Font.Regular,
        TextColor3 = Color.TextOnBright,
        TextScaled = true,
        Text = theme.emoji,
        ZIndex = childZ,
        Parent = card,
    })

    -- Personality short name under the emoji.
    apply(Instance.new("TextLabel"), {
        Name = "Name",
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(0, CARD_EMOJI_HEIGHT),
        Size = UDim2.new(1, 0, 0, CARD_NAME_HEIGHT),
        FontFace = Font.Heavy,
        TextColor3 = Color.TextOnBright,
        TextScaled = true,
        Text = string.upper(item.personality),
        ZIndex = childZ,
        Parent = card,
    })

    -- ⭐ Lv N badge pinned to the card bottom.
    apply(Instance.new("TextLabel"), {
        Name = "Level",
        AnchorPoint = Vector2.new(0.5, 1),
        Position = UDim2.fromScale(0.5, 1),
        Size = UDim2.new(1, 0, 0, CARD_BADGE_HEIGHT),
        BackgroundColor3 = Color.Panel,
        BackgroundTransparency = 0.15,
        FontFace = Font.Bold,
        TextColor3 = Color.Text,
        TextScaled = true,
        Text = string.format("⭐ Lv%d", item.level),
        ZIndex = childZ,
        Parent = card,
    }, { corner(6) })
end

-- Build one creature ROW into `parent` (used by the PLACE MENU, which keeps its
-- list style): emoji + name + color-coded personality badge. Tappable; `onTap`
-- fires on tap. `trove` owns the row; `zBase` is the row ZIndex (children +1).
local PLACE_ROW_HEIGHT = 56
local PLACE_ROW_BADGE_WIDTH = 78
local PLACE_ROW_BADGE_GAP = 6
local function buildRow(
    parent: Instance,
    trove: typeof(rootTrove),
    item: DemoClient.InventoryItem,
    order: number,
    zBase: number,
    onTap: () -> ()
)
    local theme = UITheme.personality(item.personality)
    local childZ = zBase + 1

    local row = trove:Add(apply(Instance.new("TextButton"), {
        Name = "Row",
        LayoutOrder = order,
        AutoButtonColor = true,
        Text = "",
        Size = UDim2.new(1, 0, 0, PLACE_ROW_HEIGHT),
        BackgroundColor3 = Color.PanelLight,
        BorderSizePixel = 0,
        ZIndex = zBase,
        Parent = parent,
    }, { corner(10), padding(6) }))
    trove:Add(row.Activated:Connect(onTap))

    apply(Instance.new("TextLabel"), {
        Name = "Emoji",
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(0, 0),
        Size = UDim2.new(0, PLACE_ROW_HEIGHT - 12, 1, 0),
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
        Position = UDim2.new(0, PLACE_ROW_HEIGHT, 0.5, 0),
        Size = UDim2.new(1, -PLACE_ROW_HEIGHT - PLACE_ROW_BADGE_WIDTH - PLACE_ROW_BADGE_GAP, 1, -12),
        FontFace = Font.Bold,
        TextColor3 = Color.Text,
        TextScaled = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        Text = string.format("%s Brainrot  ⭐ Lv%d", string.upper(item.personality), item.level),
        ZIndex = childZ,
        Parent = row,
    })

    apply(Instance.new("TextLabel"), {
        Name = "Badge",
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.fromScale(1, 0.5),
        Size = UDim2.fromOffset(PLACE_ROW_BADGE_WIDTH, PLACE_ROW_HEIGHT - 18),
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
-- STAT SHEET (per-monster detail modal) — opened by tapping an inventory card.
-- Minimalist: header (emoji + name + ⭐ Lv + ✕), XP bar, HP/Power row, the effect
-- one-liner + lifetime flavor (wins / coins made), then ⚔ Summon / ▶ Deploy.
-- All data comes from the item payload; the effect text comes from DemoConfig.
-- ════════════════════════════════════════════════════════════════════════════
local ROSTER_CAP = DemoConfig.rosterCap
local STAND_COUNT = DemoConfig.showroom.showroomStandCount
local MAX_LEVEL = DemoConfig.progression.maxLevel

-- Build the one-line EFFECT string for a personality, client-side from DemoConfig:
-- a short coin/combat hint derived from prodMult, plus the flavor blurb. Kept to
-- one line. Display-only — the server owns the actual multipliers.
local function effectLine(personality: string): string
    local def = DemoConfig.personalities[personality]
    if not def then
        return "A mysterious Brainrot."
    end
    local mult = def.prodMult or 1
    local pct = math.floor((mult - 1) * 100 + 0.5)
    local hint: string
    if pct > 0 then
        hint = string.format("+%d%% coins, hits ~%.1f×", pct, mult)
    elseif pct < 0 then
        hint = string.format("%d%% coins, hits ~%.1f×", pct, mult)
    else
        hint = "steady coins & damage"
    end
    return string.format("%s — %s", hint, def.blurb or "")
end

-- Full-screen backdrop: dims the scene + closes the sheet when tapped outside.
local sheetBackdrop = apply(Instance.new("TextButton"), {
    Name = "SheetBackdrop",
    Visible = false,
    Size = UDim2.fromScale(1, 1),
    BackgroundColor3 = Color.Backdrop,
    BackgroundTransparency = 0.4,
    BorderSizePixel = 0,
    AutoButtonColor = false,
    Text = "",
    ZIndex = 50,
    Parent = screen,
})

-- The sheet panel itself (a TextButton so taps on it are absorbed and do NOT fall
-- through to the backdrop, which would close it). The no-op handler is intentional.
local sheetPanel = apply(Instance.new("TextButton"), {
    Name = "StatSheet",
    AutoButtonColor = false,
    Text = "",
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.fromOffset(SHEET_WIDTH, SHEET_HEIGHT),
    BackgroundColor3 = Color.Panel,
    BorderSizePixel = 0,
    ZIndex = 51,
    Parent = sheetBackdrop,
}, { corner(20), stroke(Color.Stroke, 3), padding(14) })

-- Header: emoji + name on the left, ⭐ Lv badge, then the ✕ close button.
local sheetHeader = apply(Instance.new("TextLabel"), {
    Name = "Header",
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(0, 0),
    Size = UDim2.new(1, -(SHEET_CLOSE_SIZE + 8), 0, SHEET_HEADER_HEIGHT),
    FontFace = Font.Heavy,
    TextColor3 = Color.Text,
    TextScaled = true,
    TextXAlignment = Enum.TextXAlignment.Left,
    Text = "🔥 HYPER  ⭐ Lv1",
    ZIndex = 52,
    Parent = sheetPanel,
})

local sheetClose = apply(Instance.new("TextButton"), {
    Name = "Close",
    AnchorPoint = Vector2.new(1, 0),
    Position = UDim2.fromScale(1, 0),
    Size = UDim2.fromOffset(SHEET_CLOSE_SIZE, SHEET_CLOSE_SIZE),
    BackgroundColor3 = Color.SlotEmpty,
    BorderSizePixel = 0,
    FontFace = Font.Heavy,
    TextColor3 = Color.Text,
    TextScaled = true,
    Text = "✕",
    ZIndex = 53,
    Parent = sheetPanel,
}, { corner(10), padding(8) })

-- XP bar: a track with a filled portion = xp / xpToNext, plus the fraction label.
local sheetXpTrack = apply(Instance.new("Frame"), {
    Name = "XpTrack",
    AnchorPoint = Vector2.new(0, 0.5),
    Position = UDim2.fromOffset(0, SHEET_XP_TOP + SHEET_XP_HEIGHT / 2),
    Size = UDim2.new(0.55, 0, 0, SHEET_XP_FILL_HEIGHT),
    BackgroundColor3 = Color.SlotEmpty,
    BorderSizePixel = 0,
    ZIndex = 52,
    Parent = sheetPanel,
}, { corner(8) })

local sheetXpFill = apply(Instance.new("Frame"), {
    Name = "XpFill",
    Position = UDim2.fromScale(0, 0),
    Size = UDim2.fromScale(0, 1),
    BackgroundColor3 = Color.Collect,
    BorderSizePixel = 0,
    ZIndex = 53,
    Parent = sheetXpTrack,
}, { corner(8) })

local sheetXpLabel = apply(Instance.new("TextLabel"), {
    Name = "XpLabel",
    BackgroundTransparency = 1,
    AnchorPoint = Vector2.new(1, 0.5),
    Position = UDim2.new(1, 0, 0, SHEET_XP_TOP + SHEET_XP_HEIGHT / 2),
    Size = UDim2.new(0.4, 0, 0, SHEET_XP_HEIGHT),
    FontFace = Font.Bold,
    TextColor3 = Color.TextDim,
    TextScaled = true,
    TextXAlignment = Enum.TextXAlignment.Right,
    Text = "XP 0 / 100",
    ZIndex = 52,
    Parent = sheetPanel,
})

-- Divider above the stat row.
apply(Instance.new("Frame"), {
    Name = "Divider1",
    Position = UDim2.fromOffset(0, SHEET_STATS_TOP - 8),
    Size = UDim2.new(1, 0, 0, SHEET_DIVIDER_HEIGHT),
    BackgroundColor3 = Color.Stroke,
    BorderSizePixel = 0,
    ZIndex = 52,
    Parent = sheetPanel,
})

-- HP / Power stat row (two halves).
local sheetHp = apply(Instance.new("TextLabel"), {
    Name = "Hp",
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(0, SHEET_STATS_TOP),
    Size = UDim2.new(0.5, 0, 0, SHEET_STATS_HEIGHT),
    FontFace = Font.Heavy,
    TextColor3 = Color.Text,
    TextScaled = true,
    TextXAlignment = Enum.TextXAlignment.Left,
    Text = "❤️ HP 100",
    ZIndex = 52,
    Parent = sheetPanel,
})

local sheetPower = apply(Instance.new("TextLabel"), {
    Name = "Power",
    BackgroundTransparency = 1,
    AnchorPoint = Vector2.new(1, 0),
    Position = UDim2.new(1, 0, 0, SHEET_STATS_TOP),
    Size = UDim2.new(0.5, 0, 0, SHEET_STATS_HEIGHT),
    FontFace = Font.Heavy,
    TextColor3 = Color.Text,
    TextScaled = true,
    TextXAlignment = Enum.TextXAlignment.Right,
    Text = "⚔️ Power 12",
    ZIndex = 52,
    Parent = sheetPanel,
})

-- Effect one-liner.
local sheetEffect = apply(Instance.new("TextLabel"), {
    Name = "Effect",
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(0, SHEET_EFFECT_TOP),
    Size = UDim2.new(1, 0, 0, SHEET_EFFECT_HEIGHT),
    FontFace = Font.Bold,
    TextColor3 = Color.Text,
    TextScaled = true,
    TextXAlignment = Enum.TextXAlignment.Left,
    Text = "😜 Hyper — +30% coins, hits ~1.3×",
    ZIndex = 52,
    Parent = sheetPanel,
})

-- Lifetime flavor: wins (left) + coins made (right).
local sheetWins = apply(Instance.new("TextLabel"), {
    Name = "Wins",
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(0, SHEET_FLAVOR_TOP),
    Size = UDim2.new(0.5, 0, 0, SHEET_FLAVOR_HEIGHT),
    FontFace = Font.Bold,
    TextColor3 = Color.TextDim,
    TextScaled = true,
    TextXAlignment = Enum.TextXAlignment.Left,
    Text = "🏆 0 menang",
    ZIndex = 52,
    Parent = sheetPanel,
})

local sheetCoins = apply(Instance.new("TextLabel"), {
    Name = "CoinsMade",
    BackgroundTransparency = 1,
    AnchorPoint = Vector2.new(1, 0),
    Position = UDim2.new(1, 0, 0, SHEET_FLAVOR_TOP),
    Size = UDim2.new(0.5, 0, 0, SHEET_FLAVOR_HEIGHT),
    FontFace = Font.Bold,
    TextColor3 = Color.Coin,
    TextScaled = true,
    TextXAlignment = Enum.TextXAlignment.Right,
    Text = "🪙 0 dibuat",
    ZIndex = 52,
    Parent = sheetPanel,
})

-- Divider above the actions.
apply(Instance.new("Frame"), {
    Name = "Divider2",
    AnchorPoint = Vector2.new(0, 1),
    Position = UDim2.new(0, 0, 1, -(SHEET_ACTIONS_HEIGHT + 8)),
    Size = UDim2.new(1, 0, 0, SHEET_DIVIDER_HEIGHT),
    BackgroundColor3 = Color.Stroke,
    BorderSizePixel = 0,
    ZIndex = 52,
    Parent = sheetPanel,
})

-- Action buttons (finger-sized, >=44px): ⚔ Summon (left) / ▶ Deploy (right).
local sheetSummon = apply(Instance.new("TextButton"), {
    Name = "SummonBtn",
    AnchorPoint = Vector2.new(0, 1),
    Position = UDim2.fromScale(0, 1),
    Size = UDim2.new(0.5, -SHEET_ACTION_GAP / 2, 0, SHEET_ACTIONS_HEIGHT),
    AutoButtonColor = true,
    BackgroundColor3 = Color.Collect,
    BorderSizePixel = 0,
    FontFace = Font.Heavy,
    TextColor3 = Color.TextOnBright,
    TextScaled = true,
    Text = "⚔ Summon",
    ZIndex = 52,
    Parent = sheetPanel,
}, { corner(12), padding(8) })

local sheetDeploy = apply(Instance.new("TextButton"), {
    Name = "DeployBtn",
    AnchorPoint = Vector2.new(1, 1),
    Position = UDim2.fromScale(1, 1),
    Size = UDim2.new(0.5, -SHEET_ACTION_GAP / 2, 0, SHEET_ACTIONS_HEIGHT),
    AutoButtonColor = true,
    BackgroundColor3 = Color.CrateButton,
    BorderSizePixel = 0,
    FontFace = Font.Heavy,
    TextColor3 = Color.Text,
    TextScaled = true,
    Text = "▶ Deploy",
    ZIndex = 52,
    Parent = sheetPanel,
}, { corner(12), padding(8) })

-- The item the sheet is currently showing (so the action buttons act on it).
local sheetItem: DemoClient.InventoryItem? = nil

local function closeSheet()
    sheetBackdrop.Visible = false
    sheetItem = nil
end

-- Paint the sheet for `item` and show it. Pure presentation from the payload +
-- DemoConfig (effect text); no server reads.
local function openSheet(item: DemoClient.InventoryItem)
    sheetItem = item
    local theme = UITheme.personality(item.personality)

    sheetHeader.Text = string.format("%s %s  ⭐ Lv%d", theme.emoji, string.upper(item.personality), item.level)

    -- XP bar: fill = xp / xpToNext clamped 0..1; "MAX" at the level ceiling.
    if item.level >= MAX_LEVEL then
        sheetXpFill.Size = UDim2.fromScale(1, 1)
        sheetXpLabel.Text = "MAX"
    else
        local denom = if item.xpToNext > 0 then item.xpToNext else 1
        local frac = math.clamp(item.xp / denom, 0, 1)
        sheetXpFill.Size = UDim2.fromScale(frac, 1)
        sheetXpLabel.Text = string.format("XP %d / %d", item.xp, item.xpToNext)
    end

    sheetHp.Text = string.format("❤️ HP %d", item.hp)
    sheetPower.Text = string.format("⚔️ Power %d", item.power)
    sheetEffect.Text = string.format("%s %s", theme.emoji, effectLine(item.personality))
    sheetWins.Text = string.format("🏆 %d menang", item.wins)
    sheetCoins.Text = string.format("🪙 %d dibuat", item.coinsMade)

    sheetBackdrop.Visible = true
end

rootTrove:Add(sheetClose.Activated:Connect(closeSheet))
rootTrove:Add(sheetBackdrop.Activated:Connect(closeSheet))

-- ⚔ Summon: send THIS Brainrot (by roster id) out to auto-battle, then close.
rootTrove:Add(sheetSummon.Activated:Connect(function()
    local item = sheetItem
    if not item then
        return
    end
    print("[Combat][ui] summon " .. item.personality .. " id=" .. item.id)
    DemoClient.summon(item.id)
    closeSheet()
end))

-- ▶ Deploy: reuse the existing deploy path. The current flow deploys a personality
-- onto a SPECIFIC stand index; from the sheet there is no chosen podium, so we
-- sweep every stand index and let the SERVER place it on the first FREE one (it
-- silently rejects occupied/duplicate stands + rate-limits, so this stays safe and
-- server-authoritative — the client never tracks occupancy). Then close the sheet.
rootTrove:Add(sheetDeploy.Activated:Connect(function()
    local item = sheetItem
    if not item then
        return
    end
    print("[Deploy][ui] deploy-from-sheet " .. item.personality)
    for standIndex = 1, STAND_COUNT do
        DemoClient.deployToStand(standIndex, item.personality)
    end
    closeSheet()
end))

-- ════════════════════════════════════════════════════════════════════════════
-- RENDER (grid of cards)
-- ════════════════════════════════════════════════════════════════════════════
local function render(inventory: DemoClient.Inventory)
    cardsTrove:Clean()

    local n = #inventory
    print(("[Inv][ui] render count=%d"):format(n))
    inventoryButton.Text = string.format("🎒 INVENTORY (%d)", n)
    titleLabel.Text = string.format("🎒 Brainrots (%d/%d)", n, ROSTER_CAP)

    emptyLabel.Visible = n == 0
    for i, item in inventory do
        -- Each card is tap-to-open: tapping opens the STAT SHEET for this item,
        -- where the Summon / Deploy actions live.
        buildCard(list, cardsTrove, item, i, 22, function()
            print("[Inv][ui] open sheet " .. item.personality .. " id=" .. item.id)
            openSheet(item)
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
