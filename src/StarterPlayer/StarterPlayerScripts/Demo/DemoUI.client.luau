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
-- ElementConfig is replicated read-only: the UI reads ONLY the display table
-- (emoji badge per element). Resolution values (mods/beats) are server-applied.
local ElementConfig = require(Shared:WaitForChild("Config"):WaitForChild("ElementConfig"))
-- RarityConfig likewise: the UI reads ONLY the display table (name + tier tint
-- per rarity doc R3). statMult/evolveCostMult are server-applied.
local RarityConfig = require(Shared:WaitForChild("Config"):WaitForChild("RarityConfig"))
-- CaptureConfig: shop DISPLAY prices for the Capture Net rows (S4). The
-- server re-validates funds + applies the authoritative price on every tap.
local CaptureConfig = require(Shared:WaitForChild("Config"):WaitForChild("CaptureConfig"))

local UITheme = require(script.Parent:WaitForChild("UITheme"))
local DemoClient = require(script.Parent:WaitForChild("DemoClient"))

local apply = UITheme.apply

-- Emoji badge for an element key; "" for nil/unknown so labels never break.
local function elementEmoji(element: any): string
    local display = ElementConfig.display[element]
    return if display then display.emoji else ""
end

-- RARITY badges (rarity doc R3). Common stays visually quiet (the default
-- look); Uncommon+ get the tier tint so a good roll reads at a glance.
local RARITY_FALLBACK = Color3.fromHex("#9CA3AF")

-- Tier tint as a Color3 (card stroke etc.); grey fallback on nil/unknown.
local function rarityColor(rarity: any): Color3
    local display = RarityConfig.display[rarity]
    if display then
        return Color3.fromHex(display.color)
    end
    return RARITY_FALLBACK
end

-- RichText suffix for row labels: "" for Common/unknown (quiet), a colored
-- "◆Rare"-style tag for Uncommon+. Callers must set RichText = true.
local function rarityTag(rarity: any): string
    if rarity == nil or rarity == "Common" then
        return ""
    end
    local display = RarityConfig.display[rarity]
    if not display then
        return ""
    end
    return (' <font color="%s">◆%s</font>'):format(display.color, display.name)
end

-- EVOLUTION stage badge (S2): "" at stage 0, ✨/🌟/💫 for stages 1-3.
local STAGE_EMOJI = { "✨", "🌟", "💫" }
local function stageEmoji(stage: any): string
    if type(stage) == "number" and stage >= 1 then
        return STAGE_EMOJI[math.min(math.floor(stage), #STAGE_EMOJI)]
    end
    return ""
end
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
local SHEET_HEIGHT = 424 -- +64 for the EVOLVE row (S2 sink) above the actions
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
-- EVOLVE row (S2 sink): full-width button stacked ABOVE the action row.
local SHEET_EVOLVE_HEIGHT = 52

-- (Mobile bag FAB constants removed with the button — the top bar is the
-- single launcher surface per owner feedback; B key remains.)

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

-- EDGE-FLUSH layer (owner feedback: "mentokin saja kanan atas") — a SEPARATE
-- ScreenGui that IGNORES the safe insets so the top bar + summon panel can sit
-- at the absolute top-right corner of the screen. Everything else stays on the
-- inset-respecting `screen` gui.
local edgeGui = rootTrove:Add(Instance.new("ScreenGui"))
edgeGui.Name = "BrainrotDemoEdgeUI"
edgeGui.ResetOnSpawn = false
edgeGui.IgnoreGuiInset = true
edgeGui.ScreenInsets = Enum.ScreenInsets.None
edgeGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
edgeGui.DisplayOrder = 11
edgeGui.Parent = playerGui

-- ── Responsive scale ─────────────────────────────────────────────────────────
-- Laid out against a ~1280x720 reference; a viewport-driven UIScale keeps it from
-- clipping / looking oversized on other resolutions + small play windows.
local uiScale = Instance.new("UIScale")
uiScale.Parent = screen
local edgeScale = Instance.new("UIScale")
edgeScale.Parent = edgeGui

local function updateScale()
    local cam = workspace.CurrentCamera
    if not cam then
        return
    end
    local vp = cam.ViewportSize
    if vp.X < 1 or vp.Y < 1 then
        return
    end
    local s = math.clamp(math.min(vp.X / 1280, vp.Y / 720), 0.45, 1.15)
    uiScale.Scale = s
    edgeScale.Scale = s
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
    Text = "Walk up to a Monster and hold [F] to catch it!",
    Parent = screen,
}, { corner(12), stroke(Color.Stroke, 2), padding(10) })

-- ════════════════════════════════════════════════════════════════════════════
-- TOP BAR (top right) — per the owner's layout mock: a horizontal row of
-- launcher buttons. Inventory / Monster / Skill open the tabbed menu panel
-- straight onto their tab; Galery / Mission are PLACEHOLDERS (visible, dimmed,
-- no handler — "taruh saja tetapi tidak perlu di-on togglenya").
-- ════════════════════════════════════════════════════════════════════════════
local TOPBAR_HEIGHT = 48
local TOPBAR_BTN_WIDTH = 118
local TOPBAR_GAP = 12 -- breathing room between launcher buttons (owner feedback)

local topBar = apply(Instance.new("Frame"), {
    Name = "TopBar",
    AnchorPoint = Vector2.new(1, 0),
    -- ABSOLUTE top-right corner (owner: "mentokin saja kanan atas") — lives on
    -- the inset-IGNORING edgeGui, so 0,0 really is the screen corner.
    Position = UDim2.fromScale(1, 0),
    Size = UDim2.fromOffset(TOPBAR_BTN_WIDTH * 5 + TOPBAR_GAP * 4 + 20, TOPBAR_HEIGHT),
    BackgroundColor3 = Color.Panel,
    BackgroundTransparency = 0.15,
    BorderSizePixel = 0,
    ZIndex = 15,
    Parent = edgeGui,
}, { corner(14), stroke(Color.Stroke, 2), padding(6) })
apply(Instance.new("UIListLayout"), {
    FillDirection = Enum.FillDirection.Horizontal,
    SortOrder = Enum.SortOrder.LayoutOrder,
    Padding = UDim.new(0, TOPBAR_GAP),
    Parent = topBar,
})

local function makeTopButton(order: number, text: string, active: boolean): TextButton
    return apply(Instance.new("TextButton"), {
        Name = "Top" .. order,
        LayoutOrder = order,
        AutoButtonColor = active,
        Size = UDim2.fromOffset(TOPBAR_BTN_WIDTH, TOPBAR_HEIGHT - 12),
        BackgroundColor3 = if active then Color.CrateButton else Color.SlotEmpty,
        BackgroundTransparency = if active then 0 else 0.4,
        BorderSizePixel = 0,
        FontFace = Font.Heavy,
        TextColor3 = if active then Color.Text else Color.TextDim,
        TextScaled = true,
        Text = text,
        ZIndex = 16,
        Parent = topBar,
    }, { corner(10), padding(4) })
end
local topInventory = makeTopButton(1, "🎒 Inventory", true)
local topMonster = makeTopButton(2, "🐾 Monster", true) -- static label (no count, owner feedback)
local topSkill = makeTopButton(3, "🌟 Skill", true)
makeTopButton(4, "🖼️ Galery", false) -- placeholder (inert)
makeTopButton(5, "📜 Mission", false) -- placeholder (inert)

-- ════════════════════════════════════════════════════════════════════════════
-- COIN HUD (MIDDLE LEFT) — AUTO-COLLECT: climbing 🪙 total + "+N/s" rate line
-- ════════════════════════════════════════════════════════════════════════════
-- Per the layout mock: TOP-LEFT (was middle-left).
local coinHud = apply(Instance.new("Frame"), {
    Name = "CoinHud",
    AnchorPoint = Vector2.new(0, 0),
    Position = UDim2.fromOffset(16, 16),
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

-- (The old bottom-right mobile bag FAB was REMOVED per owner feedback — the
-- top bar is the single launcher surface now; the B key shortcut remains.)

-- ════════════════════════════════════════════════════════════════════════════
-- SUMMON STATUS PANEL (right, under the top bar) — per the layout mock: the
-- live "monster yg di summon" readout (nama, darah, type/elemen). Reads the
-- REPLICATED Fighter_* models directly (attributes + Humanoid HP) on a 4 Hz
-- throttle — zero extra remote traffic, presentation only.
-- ════════════════════════════════════════════════════════════════════════════
local SUMMON_PANEL_WIDTH = 230
local SUMMON_ROW_HEIGHT = 64
local SUMMON_MAX = DemoConfig.combat.maxActiveFighters
local SUMMON_REFRESH_SEC = 0.25

local SUMMON_PANEL_FULL = 44 + (SUMMON_ROW_HEIGHT + 6) * SUMMON_MAX + 10
local SUMMON_PANEL_COLLAPSED = 48 -- header-only height when hidden

local summonPanel = apply(Instance.new("Frame"), {
    Name = "SummonPanel",
    AnchorPoint = Vector2.new(1, 0),
    Position = UDim2.new(1, 0, 0, TOPBAR_HEIGHT + 8), -- flush right, under the bar
    Size = UDim2.fromOffset(SUMMON_PANEL_WIDTH, SUMMON_PANEL_FULL),
    BackgroundColor3 = Color.Panel,
    BackgroundTransparency = 0.1,
    BorderSizePixel = 0,
    ZIndex = 14,
    Parent = edgeGui,
}, { corner(14), stroke(Color.Stroke, 2), padding(8) })

apply(Instance.new("TextLabel"), {
    Name = "Title",
    BackgroundTransparency = 1,
    Size = UDim2.new(1, -40, 0, 32),
    FontFace = Font.Heavy,
    TextColor3 = Color.Text,
    TextScaled = true,
    TextXAlignment = Enum.TextXAlignment.Left,
    Text = "⚔ Summon",
    ZIndex = 15,
    Parent = summonPanel,
})

-- HIDE/SHOW toggle (owner request): collapses the panel to its header. The
-- updater keeps painting rows only while expanded.
local summonCollapsed = false
local summonToggle = apply(Instance.new("TextButton"), {
    Name = "ToggleBtn",
    AnchorPoint = Vector2.new(1, 0),
    Position = UDim2.fromScale(1, 0),
    Size = UDim2.fromOffset(32, 32),
    AutoButtonColor = true,
    BackgroundColor3 = Color.SlotEmpty,
    BorderSizePixel = 0,
    FontFace = Font.Heavy,
    TextColor3 = Color.Text,
    TextScaled = true,
    Text = "▲",
    ZIndex = 16,
    Parent = summonPanel,
}, { corner(8), padding(4) })

local summonEmpty = apply(Instance.new("TextLabel"), {
    Name = "EmptySummon",
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(0, 40),
    Size = UDim2.new(1, 0, 0, 36),
    FontFace = Font.Bold,
    TextColor3 = Color.TextDim,
    TextScaled = true,
    Text = "Belum ada summon",
    ZIndex = 15,
    Parent = summonPanel,
})

-- Pre-built fixed rows (NO per-frame allocations — mobile rules): each shows
-- name+badges on top and an HP bar + numbers below; hidden when unused.
type SummonRow = { frame: Frame, name: TextLabel, hpFill: Frame, hpText: TextLabel }
local summonRows: { SummonRow } = {}
for i = 1, SUMMON_MAX do
    local frame = apply(Instance.new("Frame"), {
        Name = "SummonRow" .. i,
        Visible = false,
        Position = UDim2.fromOffset(0, 40 + (i - 1) * (SUMMON_ROW_HEIGHT + 6)),
        Size = UDim2.new(1, 0, 0, SUMMON_ROW_HEIGHT),
        BackgroundColor3 = Color.PanelLight,
        BorderSizePixel = 0,
        ZIndex = 15,
        Parent = summonPanel,
    }, { corner(10), padding(6) })
    local nameLabel = apply(Instance.new("TextLabel"), {
        Name = "FighterName",
        BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 0.5),
        FontFace = Font.Bold,
        TextColor3 = Color.Text,
        TextScaled = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        Text = "",
        ZIndex = 16,
        Parent = frame,
    })
    local hpTrack = apply(Instance.new("Frame"), {
        Name = "HpTrack",
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.new(0, 0, 1, -2),
        Size = UDim2.new(1, 0, 0, 12),
        BackgroundColor3 = Color.SlotEmpty,
        BorderSizePixel = 0,
        ZIndex = 16,
        Parent = frame,
    }, { corner(6) })
    local hpFill = apply(Instance.new("Frame"), {
        Name = "HpFill",
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Color3.fromRGB(231, 76, 60),
        BorderSizePixel = 0,
        ZIndex = 17,
        Parent = hpTrack,
    }, { corner(6) })
    local hpText = apply(Instance.new("TextLabel"), {
        Name = "HpText",
        BackgroundTransparency = 1,
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.new(0, 0, 1, -16),
        Size = UDim2.new(1, 0, 0, 16),
        FontFace = Font.Bold,
        TextColor3 = Color.TextDim,
        TextScaled = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        Text = "",
        ZIndex = 16,
        Parent = frame,
    })
    summonRows[i] = { frame = frame, name = nameLabel, hpFill = hpFill, hpText = hpText }
end

-- 4 Hz updater: scan the replicated Fighter_* models and paint the rows.
local summonAccum = 0
rootTrove:Add(RunService.Heartbeat:Connect(function(dt: number)
    summonAccum += dt
    if summonAccum < SUMMON_REFRESH_SEC then
        return
    end
    summonAccum = 0
    if summonCollapsed then
        return -- hidden: skip the scan entirely (rows already blanked)
    end
    local found = 0
    for _, m in workspace:GetChildren() do
        if found >= SUMMON_MAX then
            break
        end
        if m:IsA("Model") and m.Name:match("^Fighter_") then
            local humanoid = m:FindFirstChildWhichIsA("Humanoid")
            if humanoid and humanoid.Health > 0 then
                found += 1
                local row = summonRows[found]
                local personality = m:GetAttribute("Personality") or m.Name:gsub("^Fighter_", "")
                row.name.Text = ("%s %s%s"):format(
                    string.upper(tostring(personality)),
                    elementEmoji(m:GetAttribute("Element")),
                    stageEmoji(m:GetAttribute("EvoStage"))
                )
                local hp = math.max(humanoid.Health, 0)
                local maxHp = math.max(humanoid.MaxHealth, 1)
                row.hpText.Text = ("❤ %d/%d"):format(math.floor(hp + 0.5), math.floor(maxHp + 0.5))
                row.hpFill.Size = UDim2.fromScale(math.clamp(hp / maxHp, 0, 1), 1)
                row.frame.Visible = true
            end
        end
    end
    for i = found + 1, SUMMON_MAX do
        summonRows[i].frame.Visible = false
    end
    summonEmpty.Visible = found == 0
end))

-- Collapse/expand the summon panel (▲ shown = expanded, ▼ = collapsed).
rootTrove:Add(summonToggle.Activated:Connect(function()
    summonCollapsed = not summonCollapsed
    summonToggle.Text = if summonCollapsed then "▼" else "▲"
    summonPanel.Size =
        UDim2.fromOffset(SUMMON_PANEL_WIDTH, if summonCollapsed then SUMMON_PANEL_COLLAPSED else SUMMON_PANEL_FULL)
    if summonCollapsed then
        for _, row in summonRows do
            row.frame.Visible = false
        end
        summonEmpty.Visible = false
    end
end))

-- ════════════════════════════════════════════════════════════════════════════
-- MENU PANEL (centered — the right edge now belongs to the summon panel)
-- ════════════════════════════════════════════════════════════════════════════
local panel = apply(Instance.new("Frame"), {
    Name = "InventoryPanel",
    Visible = false,
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.fromOffset(PANEL_WIDTH, PANEL_HEIGHT),
    BackgroundColor3 = Color.Panel,
    BorderSizePixel = 0,
    ZIndex = 20,
    Parent = screen,
}, { corner(20), stroke(Color.Stroke, 3), padding(14) })

-- Title: the panel is now a TABBED MENU (Item / Monster / Skill) — the count
-- lives on the Monster tab's label, so the title is static (no handle needed).
apply(Instance.new("TextLabel"), {
    Name = "Title",
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(0, 0),
    Size = UDim2.new(1, -(PANEL_CLOSE_SIZE + 8), 0, 40),
    FontFace = Font.Heavy,
    TextColor3 = Color.Text,
    TextScaled = true,
    TextXAlignment = Enum.TextXAlignment.Left,
    Text = "📦 MENU",
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

-- ── TAB BAR (Item / Monster / Skill) ────────────────────────────────────────
local TAB_BAR_TOP = 44
local TAB_BAR_HEIGHT = 40
local CONTENT_TOP = TAB_BAR_TOP + TAB_BAR_HEIGHT + 8 -- content frames start here

local tabBar = apply(Instance.new("Frame"), {
    Name = "Tabs",
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(0, TAB_BAR_TOP),
    Size = UDim2.new(1, 0, 0, TAB_BAR_HEIGHT),
    ZIndex = 21,
    Parent = panel,
})
apply(Instance.new("UIListLayout"), {
    FillDirection = Enum.FillDirection.Horizontal,
    SortOrder = Enum.SortOrder.LayoutOrder,
    Padding = UDim.new(0, 6),
    Parent = tabBar,
})

local TAB_ACTIVE = Color3.fromRGB(42, 157, 113)
local function makeTab(order: number, text: string): TextButton
    return apply(Instance.new("TextButton"), {
        Name = "Tab" .. order,
        LayoutOrder = order,
        AutoButtonColor = true,
        Size = UDim2.new(1 / 3, -4, 1, 0),
        BackgroundColor3 = Color.SlotEmpty,
        BorderSizePixel = 0,
        FontFace = Font.Heavy,
        TextColor3 = Color.Text,
        TextScaled = true,
        Text = text,
        ZIndex = 22,
        Parent = tabBar,
    }, { corner(10), padding(6) })
end
local tabItems = makeTab(1, "🎒 Item")
local tabMonsters = makeTab(2, "🐾 Monster")
local tabSkills = makeTab(3, "🌟 Skill")

-- ── MONSTER tab content: the original card grid ─────────────────────────────
local list = apply(Instance.new("ScrollingFrame"), {
    Name = "List",
    Position = UDim2.fromOffset(0, CONTENT_TOP),
    Size = UDim2.new(1, 0, 1, -CONTENT_TOP),
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
    Position = UDim2.new(0.5, 0, 0, CONTENT_TOP + 16),
    Size = UDim2.new(1, -16, 0, 40),
    FontFace = Font.Bold,
    TextColor3 = Color.TextDim,
    TextScaled = true,
    Text = "Empty — go catch some!",
    Visible = false,
    ZIndex = 22,
    Parent = panel,
})

-- ── ITEM tab content: the persisted backpack (DemoClient.Items) ─────────────
local itemsList = apply(Instance.new("ScrollingFrame"), {
    Name = "ItemsList",
    Visible = false,
    Position = UDim2.fromOffset(0, CONTENT_TOP),
    Size = UDim2.new(1, 0, 1, -CONTENT_TOP),
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
    Parent = itemsList,
})

-- Item display registry (icon + name + blurb per itemId). New items only need
-- a row here; counts come from the server push.
local ITEM_DISPLAY: { [string]: { icon: string, name: string, blurb: string } } = {
    capture_net = {
        icon = "🕸️",
        name = CaptureConfig.items.capture_net.name,
        blurb = "Dipakai 1× per tangkapan. Beli di menu Kandang.",
    },
}

local itemsTrove = rootTrove:Extend()
local function renderItems()
    itemsTrove:Clean()
    local order = 0
    local shown = 0
    for itemId, count in DemoClient.Items do
        local display = ITEM_DISPLAY[itemId]
        if display and count > 0 then
            order += 1
            shown += 1
            local row = itemsTrove:Add(apply(Instance.new("Frame"), {
                Name = "ItemRow",
                LayoutOrder = order,
                BackgroundColor3 = Color.PanelLight,
                BorderSizePixel = 0,
                Size = UDim2.new(1, 0, 0, 64),
                ZIndex = 22,
                Parent = itemsList,
            }, { corner(10), padding(8) }))
            apply(Instance.new("TextLabel"), {
                Name = "Icon",
                BackgroundTransparency = 1,
                Size = UDim2.new(0, 48, 1, 0),
                FontFace = Font.Regular,
                TextColor3 = Color.Text,
                TextScaled = true,
                Text = display.icon,
                ZIndex = 23,
                Parent = row,
            })
            apply(Instance.new("TextLabel"), {
                Name = "Name",
                BackgroundTransparency = 1,
                Position = UDim2.fromOffset(56, 0),
                Size = UDim2.new(1, -56 - 80, 0.55, 0),
                FontFace = Font.Bold,
                TextColor3 = Color.Text,
                TextScaled = true,
                TextXAlignment = Enum.TextXAlignment.Left,
                Text = display.name,
                ZIndex = 23,
                Parent = row,
            })
            apply(Instance.new("TextLabel"), {
                Name = "Blurb",
                BackgroundTransparency = 1,
                AnchorPoint = Vector2.new(0, 1),
                Position = UDim2.new(0, 56, 1, 0),
                Size = UDim2.new(1, -56 - 80, 0.4, 0),
                FontFace = Font.Bold,
                TextColor3 = Color.TextDim,
                TextScaled = true,
                TextXAlignment = Enum.TextXAlignment.Left,
                Text = display.blurb,
                ZIndex = 23,
                Parent = row,
            })
            apply(Instance.new("TextLabel"), {
                Name = "Count",
                AnchorPoint = Vector2.new(1, 0.5),
                Position = UDim2.fromScale(1, 0.5),
                Size = UDim2.fromOffset(72, 36),
                BackgroundColor3 = Color.Panel,
                BackgroundTransparency = 0.15,
                FontFace = Font.Heavy,
                TextColor3 = Color.Text,
                TextScaled = true,
                Text = "×" .. count,
                ZIndex = 23,
                Parent = row,
            }, { corner(8), padding(4) })
        end
    end
    if shown == 0 then
        itemsTrove:Add(apply(Instance.new("TextLabel"), {
            Name = "EmptyItems",
            LayoutOrder = 1,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 40),
            FontFace = Font.Bold,
            TextColor3 = Color.TextDim,
            TextScaled = true,
            Text = "Backpack kosong — beli Capture Net di Kandang!",
            ZIndex = 22,
            Parent = itemsList,
        }))
    end
end

-- ── SKILL tab content: placeholder (S5 deferred — bundled with boss HP
-- scaling). Locked previews only; no server logic.
local skillsList = apply(Instance.new("ScrollingFrame"), {
    Name = "SkillsList",
    Visible = false,
    Position = UDim2.fromOffset(0, CONTENT_TOP),
    Size = UDim2.new(1, 0, 1, -CONTENT_TOP),
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
    Parent = skillsList,
})
do
    local SKILL_PREVIEWS = {
        { icon = "⚔", name = "Slot Summon ke-4", cost = "25K 🪙" },
        { icon = "⚔", name = "Slot Summon ke-5", cost = "250K 🪙" },
        { icon = "✨", name = "Efek Summon", cost = "???" },
    }
    for i, def in SKILL_PREVIEWS do
        local row = apply(Instance.new("Frame"), {
            Name = "SkillRow",
            LayoutOrder = i,
            BackgroundColor3 = Color.PanelLight,
            BackgroundTransparency = 0.4, -- locked: dim
            BorderSizePixel = 0,
            Size = UDim2.new(1, 0, 0, 56),
            ZIndex = 22,
            Parent = skillsList,
        }, { corner(10), padding(8) })
        apply(Instance.new("TextLabel"), {
            Name = "Label",
            BackgroundTransparency = 1,
            Size = UDim2.new(1, -90, 1, 0),
            FontFace = Font.Bold,
            TextColor3 = Color.TextDim,
            TextScaled = true,
            TextXAlignment = Enum.TextXAlignment.Left,
            Text = ("%s %s — %s"):format(def.icon, def.name, def.cost),
            ZIndex = 23,
            Parent = row,
        })
        apply(Instance.new("TextLabel"), {
            Name = "Lock",
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.fromScale(1, 0.5),
            Size = UDim2.fromOffset(80, 32),
            BackgroundColor3 = Color.Panel,
            BackgroundTransparency = 0.15,
            FontFace = Font.Heavy,
            TextColor3 = Color.TextDim,
            TextScaled = true,
            Text = "🔒 Segera",
            ZIndex = 23,
            Parent = row,
        }, { corner(8), padding(4) })
    end
    apply(Instance.new("TextLabel"), {
        Name = "Note",
        LayoutOrder = 99,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 36),
        FontFace = Font.Bold,
        TextColor3 = Color.TextDim,
        TextScaled = true,
        Text = "Skill tree menyusul bersama balance boss 👑",
        ZIndex = 22,
        Parent = skillsList,
    })
end

-- ── Tab switching ───────────────────────────────────────────────────────────
local function setTab(which: string)
    local isItems = which == "items"
    local isMonsters = which == "monsters"
    local isSkills = which == "skills"
    itemsList.Visible = isItems
    list.Visible = isMonsters
    emptyLabel.Visible = isMonsters and emptyLabel.Visible -- re-evaluated by render()
    skillsList.Visible = isSkills
    tabItems.BackgroundColor3 = if isItems then TAB_ACTIVE else Color.SlotEmpty
    tabMonsters.BackgroundColor3 = if isMonsters then TAB_ACTIVE else Color.SlotEmpty
    tabSkills.BackgroundColor3 = if isSkills then TAB_ACTIVE else Color.SlotEmpty
    if isMonsters then
        -- emptyLabel visibility belongs to the monster grid only.
        emptyLabel.Visible = #DemoClient.Inventory == 0
    else
        emptyLabel.Visible = false
    end
    if isItems then
        renderItems()
    end
end
rootTrove:Add(tabItems.Activated:Connect(function()
    setTab("items")
end))
rootTrove:Add(tabMonsters.Activated:Connect(function()
    setTab("monsters")
end))
rootTrove:Add(tabSkills.Activated:Connect(function()
    setTab("skills")
end))
setTab("monsters") -- default tab

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
        -- RARITY (R3): the card BORDER carries the tier tint — Common reads
        -- like the old neutral stroke, Uncommon+ pop their color at a glance.
    }, { corner(12), stroke(rarityColor(item.rarity), 3), padding(4) }))
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
        Text = string.format("⭐ Lv%d %s%s", item.level, elementEmoji(item.element), stageEmoji(item.evoStage)),
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
        RichText = true, -- RARITY tag is a colored <font> span
        Text = string.format(
            "%s Monster %s ⭐ Lv%d%s",
            string.upper(item.personality),
            elementEmoji(item.element),
            item.level,
            rarityTag(item.rarity)
        ),
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
-- DISPLAY cap = the REAL persistence roster cap (200), not the legacy demo
-- crate guard (DemoConfig.rosterCap = 30) — the bag showed "(35/30)" once a
-- player owned more than 30 monsters.
local PersistenceConfig = require(Shared:WaitForChild("Config"):WaitForChild("PersistenceConfig"))
local ROSTER_CAP = PersistenceConfig.rosterCap
local STAND_COUNT = DemoConfig.showroom.showroomStandCount
local MAX_LEVEL = DemoConfig.progression.maxLevel

-- Build the one-line EFFECT string for a personality, client-side from DemoConfig:
-- a short coin/combat hint derived from prodMult, plus the flavor blurb. Kept to
-- one line. Display-only — the server owns the actual multipliers.
local function effectLine(personality: string): string
    local def = DemoConfig.personalities[personality]
    if not def then
        return "A mysterious Monster."
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
    RichText = true, -- RARITY tag is a colored <font> span
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

-- Divider above the EVOLVE + action rows.
apply(Instance.new("Frame"), {
    Name = "Divider2",
    AnchorPoint = Vector2.new(0, 1),
    Position = UDim2.new(0, 0, 1, -(SHEET_ACTIONS_HEIGHT + SHEET_ACTION_GAP + SHEET_EVOLVE_HEIGHT + 8)),
    Size = UDim2.new(1, 0, 0, SHEET_DIVIDER_HEIGHT),
    BackgroundColor3 = Color.Stroke,
    BorderSizePixel = 0,
    ZIndex = 52,
    Parent = sheetPanel,
})

-- EVOLVE button (S2 sink): full-width, stacked above Summon/Deploy. Text +
-- color are data-driven per item in openSheet (ready / level-gated / broke /
-- MAX); the SERVER re-validates every tap and answers with a Moment banner.
local sheetEvolve = apply(Instance.new("TextButton"), {
    Name = "EvolveBtn",
    AnchorPoint = Vector2.new(0, 1),
    Position = UDim2.new(0, 0, 1, -(SHEET_ACTIONS_HEIGHT + SHEET_ACTION_GAP)),
    Size = UDim2.new(1, 0, 0, SHEET_EVOLVE_HEIGHT),
    AutoButtonColor = true,
    BackgroundColor3 = Color.PanelLight,
    BorderSizePixel = 0,
    FontFace = Font.Heavy,
    TextColor3 = Color.Text,
    TextScaled = true,
    Text = "✨ EVOLVE",
    ZIndex = 52,
    Parent = sheetPanel,
}, { corner(12), padding(8) })

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

    sheetHeader.Text = string.format(
        "%s %s %s%s ⭐ Lv%d%s",
        theme.emoji,
        string.upper(item.personality),
        elementEmoji(item.element),
        stageEmoji(item.evoStage),
        item.level,
        rarityTag(item.rarity)
    )

    -- EVOLVE button state (data from the server payload; server re-validates).
    if item.evolveCost == nil then
        sheetEvolve.Text = "💫 STAGE MAX"
        sheetEvolve.BackgroundColor3 = Color.SlotEmpty
        sheetEvolve.AutoButtonColor = false
    elseif item.level < (item.evolveMilestone or math.huge) then
        sheetEvolve.Text = string.format("✨ Evolve terbuka di Lv %d", item.evolveMilestone or 0)
        sheetEvolve.BackgroundColor3 = Color.SlotEmpty
        sheetEvolve.AutoButtonColor = false
    else
        sheetEvolve.Text =
            string.format("✨ EVOLVE ke Stage %d — %d 🪙", (item.evoStage or 0) + 1, item.evolveCost)
        sheetEvolve.AutoButtonColor = true
        if DemoClient.getDisplayCoins() >= item.evolveCost then
            sheetEvolve.BackgroundColor3 = Color3.fromRGB(168, 85, 247) -- ready: evolution purple
        else
            sheetEvolve.BackgroundColor3 = Color.SlotEmpty -- broke: dim (server still answers)
        end
    end

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

-- ✨ Evolve (S2 sink): send the intent; the server validates milestone + funds
-- (x rarity) and answers via a Moment banner + InventoryUpdate. Close so the
-- re-opened sheet shows the fresh stage/stats.
rootTrove:Add(sheetEvolve.Activated:Connect(function()
    local item = sheetItem
    if not item or item.evolveCost == nil then
        return -- MAX stage: inert
    end
    if item.level < (item.evolveMilestone or math.huge) then
        return -- level-gated: inert (button already reads "terbuka di Lv N")
    end
    print("[Evolve][ui] evolve " .. item.personality .. " id=" .. item.id)
    DemoClient.evolve(item.id)
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
    print("[Deploy][ui] deploy-from-sheet " .. item.personality .. " id=" .. item.id)
    -- ID-KEYED: try every stand for THIS monster; the server accepts the first
    -- free one and rejects the rest (the id turns busy after the first).
    for standIndex = 1, STAND_COUNT do
        DemoClient.deployToStand(standIndex, item.id)
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
    -- (Top-bar Monster label stays static per owner feedback — count removed.)
    -- TABBED MENU: the count lives on the Monster tab; the title stays put.
    tabMonsters.Text = string.format("🐾 Monster (%d/%d)", n, ROSTER_CAP)

    -- The empty-state belongs to the MONSTER tab only.
    emptyLabel.Visible = list.Visible and n == 0
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

-- TOP BAR launchers: open the panel STRAIGHT onto the matching tab; tapping
-- the same launcher again while open closes the panel (feels like a toggle).
local function openAt(tab: string)
    if isOpen then
        setOpen(false)
        return
    end
    setTab(tab)
    setOpen(true)
end
rootTrove:Add(topInventory.Activated:Connect(function()
    openAt("items")
end))
rootTrove:Add(topMonster.Activated:Connect(function()
    openAt("monsters")
end))
rootTrove:Add(topSkill.Activated:Connect(function()
    openAt("skills")
end))
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
    Text = "Tap a Monster to place it here",
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
    Text = "No Monsters yet — go catch some!",
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
        local itemId = item.id -- ID-KEYED deploy (the exact tapped monster)
        local personality = item.personality
        buildRow(placeList, placeRowsTrove, item, i, 32, function()
            print("[Place] chose " .. personality .. " (" .. itemId .. ") for stand " .. standIndex)
            DemoClient.deployToStand(standIndex, itemId)
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
-- KANDANG MENU (modal) — opened by the single F terminal at the paddock gate.
-- Two sections in one clean panel:
--   DI KANDANG: deployed monsters — tap a row to AMBIL (recall to bag)
--   DI TAS:     bag monsters       — tap a row to TARUH (deploy to the first
--               free slot; rows show PENUH and stop responding when full)
-- Server-authoritative: every tap is just an intent; the server validates and
-- replies with a fresh snapshot (KandangUpdated) that re-renders the menu live.
-- ════════════════════════════════════════════════════════════════════════════

local KANDANG_WIDTH = 420
local KANDANG_HEIGHT = 560
local KANDANG_TITLE_HEIGHT = 44
local KANDANG_UPGRADE_HEIGHT = 48 -- the upgrade-button row under the title (>=44px tap)
local KANDANG_SHOP_HEIGHT = 48 -- the Capture Net shop row under the upgrade button
local KANDANG_LIST_TOP = 56 + KANDANG_UPGRADE_HEIGHT + 8 + KANDANG_SHOP_HEIGHT + 8
local KANDANG_CLOSE_SIZE = 44 -- MOBILE: >=44px touch target
local KANDANG_ROW_HEIGHT = 56
local KANDANG_SECTION_HEIGHT = 30
local KANDANG_BADGE_WIDTH = 86

local kandangBackdrop = apply(Instance.new("TextButton"), {
    Name = "KandangBackdrop",
    Visible = false,
    Size = UDim2.fromScale(1, 1),
    BackgroundColor3 = Color.Backdrop,
    BackgroundTransparency = 0.4,
    BorderSizePixel = 0,
    AutoButtonColor = false,
    Text = "",
    ZIndex = 40,
    Parent = screen,
})

local kandangPanel = apply(Instance.new("TextButton"), {
    Name = "KandangPanel",
    AutoButtonColor = false,
    Text = "",
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.fromOffset(KANDANG_WIDTH, KANDANG_HEIGHT),
    BackgroundColor3 = Color.Panel,
    BorderSizePixel = 0,
    ZIndex = 41,
    Parent = kandangBackdrop,
}, { corner(20), stroke(Color.Stroke, 3), padding(14) })

local kandangTitle = apply(Instance.new("TextLabel"), {
    Name = "Title",
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(0, 0),
    Size = UDim2.new(1, -(KANDANG_CLOSE_SIZE + 8), 0, KANDANG_TITLE_HEIGHT),
    FontFace = Font.Heavy,
    TextColor3 = Color.Text,
    TextScaled = true,
    TextXAlignment = Enum.TextXAlignment.Left,
    Text = "🏠 KANDANG (0/6)",
    ZIndex = 42,
    Parent = kandangPanel,
})

local kandangClose = apply(Instance.new("TextButton"), {
    Name = "Close",
    AnchorPoint = Vector2.new(1, 0),
    Position = UDim2.fromScale(1, 0),
    Size = UDim2.fromOffset(KANDANG_CLOSE_SIZE, KANDANG_CLOSE_SIZE),
    BackgroundColor3 = Color.SlotEmpty,
    BorderSizePixel = 0,
    FontFace = Font.Heavy,
    TextColor3 = Color.Text,
    TextScaled = true,
    Text = "✕",
    ZIndex = 43,
    Parent = kandangPanel,
}, { corner(10), padding(8) })

-- ECONOMY SINK: the Upgrade Kandang button (under the title, above the list).
-- Text/color are data-driven from the server snapshot in renderKandang():
-- green when affordable, dim when not, grey MAX at the level cap. Tapping
-- sends the intent; the SERVER validates funds/cap and replies with a fresh
-- snapshot + a Moment banner.
local kandangUpgradeBtn = apply(Instance.new("TextButton"), {
    Name = "Upgrade",
    Position = UDim2.fromOffset(0, 56),
    Size = UDim2.new(1, 0, 0, KANDANG_UPGRADE_HEIGHT),
    BackgroundColor3 = Color.PanelLight,
    BorderSizePixel = 0,
    AutoButtonColor = true,
    FontFace = Font.Heavy,
    TextColor3 = Color.Text,
    TextScaled = true,
    Text = "⬆️ Upgrade Kandang",
    ZIndex = 42,
    Parent = kandangPanel,
}, { corner(12), padding(8) })

-- SHOP row (S4): Capture Net counter + two buy buttons (single / 10-bundle).
-- Prices come from the replicated CaptureConfig (display only — the server
-- re-validates funds on every tap).
local kandangShopRow = apply(Instance.new("Frame"), {
    Name = "Shop",
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(0, 56 + KANDANG_UPGRADE_HEIGHT + 8),
    Size = UDim2.new(1, 0, 0, KANDANG_SHOP_HEIGHT),
    ZIndex = 42,
    Parent = kandangPanel,
})

local kandangNetCount = apply(Instance.new("TextLabel"), {
    Name = "NetCount",
    BackgroundTransparency = 1,
    Size = UDim2.new(0.3, -4, 1, 0),
    FontFace = Font.Heavy,
    TextColor3 = Color.Text,
    TextScaled = true,
    TextXAlignment = Enum.TextXAlignment.Left,
    Text = "🕸️ ×0",
    ZIndex = 43,
    Parent = kandangShopRow,
})

local kandangBuyOne = apply(Instance.new("TextButton"), {
    Name = "BuyOne",
    AnchorPoint = Vector2.new(0, 0),
    Position = UDim2.new(0.3, 4, 0, 0),
    Size = UDim2.new(0.35, -8, 1, 0),
    AutoButtonColor = true,
    BackgroundColor3 = Color3.fromRGB(42, 157, 113),
    BorderSizePixel = 0,
    FontFace = Font.Heavy,
    TextColor3 = Color.TextOnBright,
    TextScaled = true,
    Text = "Beli 1 — 25 🪙",
    ZIndex = 43,
    Parent = kandangShopRow,
}, { corner(10), padding(6) })

local kandangBuyBundle = apply(Instance.new("TextButton"), {
    Name = "BuyBundle",
    AnchorPoint = Vector2.new(1, 0),
    Position = UDim2.fromScale(1, 0),
    Size = UDim2.new(0.35, -8, 1, 0),
    AutoButtonColor = true,
    BackgroundColor3 = Color3.fromRGB(42, 157, 113),
    BorderSizePixel = 0,
    FontFace = Font.Heavy,
    TextColor3 = Color.TextOnBright,
    TextScaled = true,
    Text = "Paket 10 — 225 🪙",
    ZIndex = 43,
    Parent = kandangShopRow,
}, { corner(10), padding(6) })

-- Price labels from the replicated config (single source of display truth).
do
    local netDef = CaptureConfig.items.capture_net
    kandangBuyOne.Text = ("Beli 1 — %d 🪙"):format(netDef.price)
    kandangBuyBundle.Text = ("Paket %d — %d 🪙"):format(netDef.bundleCount, netDef.bundlePrice)
end

local kandangList = apply(Instance.new("ScrollingFrame"), {
    Name = "List",
    Position = UDim2.fromOffset(0, KANDANG_LIST_TOP),
    Size = UDim2.new(1, 0, 1, -KANDANG_LIST_TOP),
    BackgroundColor3 = Color.SlotEmpty,
    BorderSizePixel = 0,
    ScrollBarThickness = 6,
    CanvasSize = UDim2.new(),
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
    ZIndex = 42,
    Parent = kandangPanel,
}, { corner(12), padding(8) })

apply(Instance.new("UIListLayout"), {
    FillDirection = Enum.FillDirection.Vertical,
    SortOrder = Enum.SortOrder.LayoutOrder,
    Padding = UDim.new(0, 6),
    Parent = kandangList,
})

-- Trove for the menu's rows (cleared + rebuilt on every snapshot).
local kandangRowsTrove = rootTrove:Extend()

-- Menu state: the last server snapshot + open flag. `kandangClosedAt` guards
-- against a stale post-action refresh re-opening a just-closed menu.
local kandangOpen = false
local kandangLast: DemoClient.KandangPayload? = nil
local kandangClosedAt = 0

local function closeKandangMenu()
    kandangOpen = false
    kandangClosedAt = os.clock()
    kandangBackdrop.Visible = false
    kandangRowsTrove:Clean()
end

-- One section header line ("DI KANDANG — tap untuk ambil").
local function kandangSection(text: string, order: number)
    kandangRowsTrove:Add(apply(Instance.new("TextLabel"), {
        Name = "Section",
        LayoutOrder = order,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, KANDANG_SECTION_HEIGHT),
        FontFace = Font.Heavy,
        TextColor3 = Color.TextDim,
        TextScaled = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        Text = text,
        ZIndex = 43,
        Parent = kandangList,
    }))
end

-- One tappable row: personality emoji tile + label + action badge.
-- `badgeColor` nil = personality color; `onTap` nil = inert (e.g. PENUH).
local function kandangRow(
    order: number,
    personality: string,
    label: string,
    badgeText: string,
    badgeColor: Color3?,
    onTap: (() -> ())?
)
    local theme = UITheme.personality(personality)
    local row = kandangRowsTrove:Add(apply(Instance.new("TextButton"), {
        Name = "Row",
        LayoutOrder = order,
        AutoButtonColor = onTap ~= nil,
        Text = "",
        Size = UDim2.new(1, 0, 0, KANDANG_ROW_HEIGHT),
        BackgroundColor3 = Color.PanelLight,
        BackgroundTransparency = if onTap then 0 else 0.4,
        BorderSizePixel = 0,
        ZIndex = 42,
        Parent = kandangList,
    }, { corner(10), padding(6) }))
    if onTap then
        kandangRowsTrove:Add(row.Activated:Connect(onTap))
    end

    apply(Instance.new("TextLabel"), {
        Name = "Emoji",
        BackgroundTransparency = 1,
        Size = UDim2.new(0, KANDANG_ROW_HEIGHT - 12, 1, 0),
        FontFace = Font.Regular,
        TextColor3 = Color.Text,
        TextScaled = true,
        Text = theme.emoji,
        ZIndex = 43,
        Parent = row,
    })

    apply(Instance.new("TextLabel"), {
        Name = "Label",
        BackgroundTransparency = 1,
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, KANDANG_ROW_HEIGHT, 0.5, 0),
        Size = UDim2.new(1, -KANDANG_ROW_HEIGHT - KANDANG_BADGE_WIDTH - 8, 1, -16),
        FontFace = Font.Bold,
        TextColor3 = Color.Text,
        TextScaled = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        RichText = true, -- RARITY tag is a colored <font> span
        Text = label,
        ZIndex = 43,
        Parent = row,
    })

    apply(Instance.new("TextLabel"), {
        Name = "Badge",
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.fromScale(1, 0.5),
        Size = UDim2.fromOffset(KANDANG_BADGE_WIDTH, KANDANG_ROW_HEIGHT - 20),
        BackgroundColor3 = badgeColor or theme.color,
        BackgroundTransparency = if onTap then 0 else 0.5,
        BorderSizePixel = 0,
        FontFace = Font.Heavy,
        TextColor3 = Color.TextOnBright,
        TextScaled = true,
        Text = badgeText,
        ZIndex = 43,
        Parent = row,
    }, { corner(8), padding(6) })
end

local AMBIL_COLOR = Color3.fromRGB(231, 111, 81) -- warm red: take OUT
local TARUH_COLOR = Color3.fromRGB(42, 157, 113) -- green: put IN

-- Render the whole menu from the last snapshot + the live bag.
local function renderKandang()
    local payload = kandangLast
    if not payload then
        return
    end
    kandangRowsTrove:Clean()

    local capacity = payload.capacity or 6
    local deployedCount = #payload.deployed
    local level = payload.level or 0
    kandangTitle.Text = string.format("🏠 KANDANG Lv%d (%d/%d)", level, deployedCount, capacity)

    -- SHOP (S4): owned Capture Nets counter.
    kandangNetCount.Text = string.format("🕸️ ×%d", payload.nets or 0)

    -- Upgrade button (data-driven; the server re-validates every tap).
    local nextCost = payload.nextCost
    if nextCost == nil then
        kandangUpgradeBtn.Text = "🏠 Kandang Lv MAX"
        kandangUpgradeBtn.BackgroundColor3 = Color.SlotEmpty
        kandangUpgradeBtn.AutoButtonColor = false
    else
        local bonusPct = math.floor((payload.bonusPerLevel or 0) * 100 + 0.5)
        kandangUpgradeBtn.Text =
            string.format("⬆️ Upgrade ke Lv%d (+%d%% produksi) — %d 🪙", level + 1, bonusPct, nextCost)
        kandangUpgradeBtn.AutoButtonColor = true
        if DemoClient.getDisplayCoins() >= nextCost then
            kandangUpgradeBtn.BackgroundColor3 = Color3.fromRGB(42, 157, 113) -- affordable: green
        else
            kandangUpgradeBtn.BackgroundColor3 = Color.SlotEmpty -- not yet: dim
        end
    end

    local order = 0
    local function nextOrder()
        order += 1
        return order
    end

    -- ── DI KANDANG ──
    kandangSection("DI KANDANG — tap untuk ambil", nextOrder())
    if deployedCount == 0 then
        kandangSection("   (kosong — taruh monster dari tasmu)", nextOrder())
    end
    for _, slot in payload.deployed do
        local index = slot.index
        local label = string.format(
            "%s %s%s  ⭐ Lv%d%s",
            string.upper(slot.personality),
            elementEmoji(slot.element),
            stageEmoji(slot.evoStage),
            slot.level or 1,
            rarityTag(slot.rarity)
        )
        kandangRow(nextOrder(), slot.personality, label, "AMBIL", AMBIL_COLOR, function()
            DemoClient.recallDeployed(index)
        end)
    end

    -- ── DI TAS ──
    kandangSection("DI TAS — tap untuk taruh", nextOrder())
    local inventory = DemoClient.Inventory
    if #inventory == 0 then
        kandangSection("   (tas kosong — pergi tangkap monster!)", nextOrder())
    end
    local firstFree: number? = payload.free[1]
    for _, item in inventory do
        local personality = item.personality
        local label = string.format(
            "%s %s%s  ⭐ Lv%d%s",
            string.upper(personality),
            elementEmoji(item.element),
            stageEmoji(item.evoStage),
            item.level,
            rarityTag(item.rarity)
        )
        if firstFree then
            local target = firstFree
            local itemId = item.id -- ID-KEYED deploy (the exact tapped monster)
            kandangRow(nextOrder(), personality, label, "TARUH", TARUH_COLOR, function()
                DemoClient.deployToStand(target, itemId)
            end)
        else
            kandangRow(nextOrder(), personality, label, "PENUH", nil, nil)
        end
    end
end

-- Snapshot arrives: refresh if open; open if this is a fresh user intent
-- (suppress the stale post-action push that can trail a just-closed menu).
DemoClient.KandangUpdated:Connect(function(payload)
    kandangLast = payload
    if kandangOpen then
        renderKandang()
        return
    end
    if os.clock() - kandangClosedAt < 1 then
        return -- trailing refresh after close; ignore
    end
    kandangOpen = true
    renderKandang()
    kandangBackdrop.Visible = true
end)

-- The bag changed while the menu is open (deploy/recall round-trip landed):
-- ask the server for a fresh slot snapshot so both sections stay in sync.
DemoClient.InventoryChanged:Connect(function()
    if kandangOpen then
        DemoClient.requestKandang()
    end
end)

rootTrove:Add(kandangClose.Activated:Connect(closeKandangMenu))
rootTrove:Add(kandangBackdrop.Activated:Connect(closeKandangMenu))
-- Upgrade tap: send the intent; the server replies with a snapshot (button +
-- title re-render) plus a Moment banner (success / not-enough / max).
rootTrove:Add(kandangUpgradeBtn.Activated:Connect(function()
    if kandangOpen then
        DemoClient.upgradeKandang()
    end
end))
-- SHOP taps (S4): buy 1 / buy the bundle. Server validates + banners.
rootTrove:Add(kandangBuyOne.Activated:Connect(function()
    if kandangOpen then
        DemoClient.buyCaptureItem(false)
    end
end))
rootTrove:Add(kandangBuyBundle.Activated:Connect(function()
    if kandangOpen then
        DemoClient.buyCaptureItem(true)
    end
end))

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

-- BACKPACK (S4): live-refresh the Item tab whenever a count changes.
DemoClient.ItemsChanged:Connect(function()
    if itemsList.Visible then
        renderItems()
    end
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
