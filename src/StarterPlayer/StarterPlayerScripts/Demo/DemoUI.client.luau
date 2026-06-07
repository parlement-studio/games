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
local TweenService = game:GetService("TweenService")
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

-- LY: layout constants + display registries live in ONE table instead of
-- dozens of top-level locals — Luau caps a chunk at 200 local registers and
-- this script was over it (UI failed to compile at all).
local LY = {}

-- Emoji badge for an element key; "" for nil/unknown so labels never break.
local function elementEmoji(element: any): string
    local display = ElementConfig.display[element]
    return if display then display.emoji else ""
end

-- RARITY badges (rarity doc R3). Common stays visually quiet (the default
-- look); Uncommon+ get the tier tint so a good roll reads at a glance.
LY.RARITY_FALLBACK = Color3.fromHex("#9CA3AF")

-- Tier tint as a Color3 (card stroke etc.); grey fallback on nil/unknown.
local function rarityColor(rarity: any): Color3
    local display = RarityConfig.display[rarity]
    if display then
        return Color3.fromHex(display.color)
    end
    return LY.RARITY_FALLBACK
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
LY.STAGE_EMOJI = { "✨", "🌟", "💫" }
local function stageEmoji(stage: any): string
    if type(stage) == "number" and stage >= 1 then
        return LY.STAGE_EMOJI[math.min(math.floor(stage), #LY.STAGE_EMOJI)]
    end
    return ""
end
local corner = UITheme.corner
local stroke = UITheme.stroke
local padding = UITheme.padding
local Color = UITheme.Color
local Font = UITheme.Font

-- ── Layout constants (no magic numbers buried in calls) ─────────────────────
LY.TOGGLE_KEY = Enum.KeyCode.B
LY.PANEL_WIDTH = 360
LY.PANEL_HEIGHT = 460
-- MONSTER GRID: wide rarity-bordered cards (mock), 3 per row via a scale-based
-- UIGridLayout; tapping opens the stat sheet.
LY.CARD_GAP = 8 -- spacing between cards in the grid
-- Inventory panel ✕ close button (bumped to a >=44px touch target for mobile).
LY.PANEL_CLOSE_SIZE = 44

-- ── STAT SHEET (per-monster detail modal) ──────────────────────────────────
-- A centered, closeable modal opened by tapping an inventory card. Minimalist:
-- header (emoji + name + ⭐ Lv + ✕), an XP bar, an HP/Power stat row, the effect
-- one-liner + lifetime flavor (wins / coins made), then the action buttons.
LY.SHEET_WIDTH = 380
LY.SHEET_HEIGHT = 424 -- +64 for the EVOLVE row (S2 sink) above the actions
LY.SHEET_CLOSE_SIZE = 44 -- MOBILE: >=44px touch target
LY.SHEET_HEADER_HEIGHT = 44
LY.SHEET_XP_TOP = 56 -- y of the XP bar block
LY.SHEET_XP_HEIGHT = 28 -- XP bar block height
LY.SHEET_XP_FILL_HEIGHT = 14 -- the filled track inside the XP block
LY.SHEET_STATS_TOP = 100 -- y of the HP/Power stat row
LY.SHEET_STATS_HEIGHT = 40
LY.SHEET_EFFECT_TOP = 152 -- y of the effect one-liner
LY.SHEET_EFFECT_HEIGHT = 28
LY.SHEET_FLAVOR_TOP = 184 -- y of the wins / coins-made line
LY.SHEET_FLAVOR_HEIGHT = 26
LY.SHEET_ACTIONS_HEIGHT = 52 -- height of the bottom action-button row (>=44px)
LY.SHEET_ACTION_GAP = 12 -- gap between the two action buttons
LY.SHEET_DIVIDER_HEIGHT = 2 -- thin divider rule between sections
-- EVOLVE row (S2 sink): full-width button stacked ABOVE the action row.
LY.SHEET_EVOLVE_HEIGHT = 52

-- (Mobile bag FAB constants removed with the button — the top bar is the
-- single launcher surface per owner feedback; B key remains.)

-- Place menu (modal opened from a podium's Place (F) prompt).
LY.PLACE_WIDTH = 380
LY.PLACE_HEIGHT = 480
LY.PLACE_TITLE_HEIGHT = 40
LY.PLACE_LIST_TOP = 76
LY.PLACE_CLOSE_SIZE = 44 -- MOBILE: >=44px touch target

-- Coin HUD (middle-left; top-right is the inventory button). AUTO-COLLECT: no
-- COLLECT button — just the climbing 🪙 total + a small "+N/s" rate line.
LY.HUD_WIDTH = 240
LY.HUD_HEIGHT = 72
-- How often (seconds) the climbing coin counter is refreshed from the local
-- extrapolation. ~10 Hz keeps it smooth without burning frames on mobile.
LY.HUD_REFRESH_SEC = 0.1

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
LY.TOPBAR_HEIGHT = 48
LY.TOPBAR_BTN_WIDTH = 118
LY.TOPBAR_GAP = 12 -- breathing room between launcher buttons (owner feedback)

local topBar = apply(Instance.new("Frame"), {
    Name = "TopBar",
    AnchorPoint = Vector2.new(1, 0),
    -- ABSOLUTE top-right corner (owner: "mentokin saja kanan atas") — lives on
    -- the inset-IGNORING edgeGui, so 0,0 really is the screen corner.
    Position = UDim2.fromScale(1, 0),
    Size = UDim2.fromOffset(LY.TOPBAR_BTN_WIDTH * 5 + LY.TOPBAR_GAP * 4 + 20, LY.TOPBAR_HEIGHT),
    BackgroundColor3 = Color.Panel,
    BackgroundTransparency = 0.15,
    BorderSizePixel = 0,
    ZIndex = 15,
    Parent = edgeGui,
}, { corner(14), stroke(Color.Stroke, 2), padding(6) })
apply(Instance.new("UIListLayout"), {
    FillDirection = Enum.FillDirection.Horizontal,
    SortOrder = Enum.SortOrder.LayoutOrder,
    Padding = UDim.new(0, LY.TOPBAR_GAP),
    Parent = topBar,
})

local function makeTopButton(order: number, text: string, active: boolean): TextButton
    return apply(Instance.new("TextButton"), {
        Name = "Top" .. order,
        LayoutOrder = order,
        AutoButtonColor = active,
        Size = UDim2.fromOffset(LY.TOPBAR_BTN_WIDTH, LY.TOPBAR_HEIGHT - 12),
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
    Size = UDim2.fromOffset(LY.HUD_WIDTH, LY.HUD_HEIGHT),
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
-- SUMMON STATUS PANEL — a SLIDE DRAWER on the right edge (owner request):
-- closed, only a « handle shows at the screen edge; tapping it slides the
-- panel in from the right (and the handle flips to »). The live readout
-- (nama, darah, type/elemen) reads the REPLICATED Fighter_* models directly
-- (attributes + Humanoid HP) on a 4 Hz throttle — zero extra remote traffic.
-- ════════════════════════════════════════════════════════════════════════════
LY.SUMMON_PANEL_WIDTH = 230
LY.SUMMON_ROW_HEIGHT = 64
LY.SUMMON_MAX = DemoConfig.combat.maxActiveFighters
LY.SUMMON_REFRESH_SEC = 0.25

LY.SUMMON_PANEL_FULL = 44 + (LY.SUMMON_ROW_HEIGHT + 6) * LY.SUMMON_MAX + 10
LY.SUMMON_HANDLE_WIDTH = 32 -- the « tab sticking out of the panel's left edge
LY.SUMMON_HANDLE_HEIGHT = 64 -- MOBILE: tall enough to thumb easily
LY.SUMMON_SLIDE_SEC = 0.25 -- drawer tween duration
-- Drawer X targets (AnchorPoint (1,0): position.X = the panel's RIGHT edge).
-- Closed pushes the panel fully off-screen (+2 hides its stroke too); the
-- handle is a child sticking out LEFT, so it stays visible at the edge.
LY.SUMMON_OPEN_X = 0
LY.SUMMON_CLOSED_X = LY.SUMMON_PANEL_WIDTH + 2

local summonPanel = apply(Instance.new("Frame"), {
    Name = "SummonPanel",
    AnchorPoint = Vector2.new(1, 0),
    -- Starts CLOSED (off-screen right; only the « handle shows).
    Position = UDim2.new(1, LY.SUMMON_CLOSED_X, 0, LY.TOPBAR_HEIGHT + 8),
    Size = UDim2.fromOffset(LY.SUMMON_PANEL_WIDTH, LY.SUMMON_PANEL_FULL),
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

-- SLIDE HANDLE: the « tab on the panel's LEFT edge. It is a CHILD of the
-- panel so it slides along with it — when the panel is parked off-screen the
-- handle is the only thing left peeking at the screen edge.
local summonOpen = false
local summonToggle = apply(Instance.new("TextButton"), {
    Name = "ToggleBtn",
    AnchorPoint = Vector2.new(0, 0),
    -- -8 cancels the panel's UIPadding; the tab hugs the panel's left edge.
    Position = UDim2.fromOffset(-(LY.SUMMON_HANDLE_WIDTH + 8), 8),
    Size = UDim2.fromOffset(LY.SUMMON_HANDLE_WIDTH, LY.SUMMON_HANDLE_HEIGHT),
    AutoButtonColor = true,
    BackgroundColor3 = Color.Panel,
    BackgroundTransparency = 0.1,
    BorderSizePixel = 0,
    FontFace = Font.Heavy,
    TextColor3 = Color.Text,
    TextScaled = true,
    Text = "«",
    ZIndex = 16,
    Parent = summonPanel,
}, { corner(10), stroke(Color.Stroke, 2), padding(4) })

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
for i = 1, LY.SUMMON_MAX do
    local frame = apply(Instance.new("Frame"), {
        Name = "SummonRow" .. i,
        Visible = false,
        Position = UDim2.fromOffset(0, 40 + (i - 1) * (LY.SUMMON_ROW_HEIGHT + 6)),
        Size = UDim2.new(1, 0, 0, LY.SUMMON_ROW_HEIGHT),
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
    if summonAccum < LY.SUMMON_REFRESH_SEC then
        return
    end
    summonAccum = 0
    if not summonOpen then
        return -- drawer parked off-screen: skip the scan entirely
    end
    local found = 0
    for _, m in workspace:GetChildren() do
        if found >= LY.SUMMON_MAX then
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
    for i = found + 1, LY.SUMMON_MAX do
        summonRows[i].frame.Visible = false
    end
    summonEmpty.Visible = found == 0
end))

-- Slide the drawer in/out. One reusable tween slot — starting a new slide
-- cancels the in-flight one (no tween stacking on the same property).
local summonTween: Tween? = nil

local function setSummonOpen(open: boolean)
    summonOpen = open
    summonToggle.Text = if open then "»" else "«"
    if summonTween then
        summonTween:Cancel()
    end
    local targetX = if open then LY.SUMMON_OPEN_X else LY.SUMMON_CLOSED_X
    summonTween = TweenService:Create(
        summonPanel,
        TweenInfo.new(LY.SUMMON_SLIDE_SEC, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { Position = UDim2.new(1, targetX, 0, LY.TOPBAR_HEIGHT + 8) }
    )
    summonTween:Play()
    if not open then
        -- Parked: blank the rows so the next open starts clean.
        for _, row in summonRows do
            row.frame.Visible = false
        end
        summonEmpty.Visible = false
    end
end

rootTrove:Add(summonToggle.Activated:Connect(function()
    setSummonOpen(not summonOpen)
end))

-- ════════════════════════════════════════════════════════════════════════════
-- MENU PANEL (centered — the right edge now belongs to the summon panel)
-- ════════════════════════════════════════════════════════════════════════════
local panel = apply(Instance.new("Frame"), {
    Name = "InventoryPanel",
    Visible = false,
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.fromOffset(LY.PANEL_WIDTH, LY.PANEL_HEIGHT),
    BackgroundColor3 = Color.Panel,
    BorderSizePixel = 0,
    ZIndex = 20,
    Parent = screen,
}, { corner(20), stroke(Color.Stroke, 3), padding(14) })

-- Title: reflects the ACTIVE tab (the in-panel tab bar was removed — the TOP
-- BAR launchers are the tabs now); the Monster count lives here too.
local titleLabel = apply(Instance.new("TextLabel"), {
    Name = "Title",
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(0, 0),
    Size = UDim2.new(1, -(LY.PANEL_CLOSE_SIZE + 8), 0, 40),
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
    Size = UDim2.fromOffset(LY.PANEL_CLOSE_SIZE, LY.PANEL_CLOSE_SIZE),
    BackgroundColor3 = Color.SlotEmpty,
    BorderSizePixel = 0,
    FontFace = Font.Heavy,
    TextColor3 = Color.Text,
    TextScaled = true,
    Text = "✕",
    ZIndex = 22,
    Parent = panel,
}, { corner(10), padding(8) })

-- ── Content offset (tab bar removed — the TOP BAR launchers are the tabs) ───
LY.CONTENT_TOP = 48 -- content frames start right below the title row

-- ── MONSTER tab content (per owner mock): controls row (element filter chips
-- left + sort cycle right) above a WIDE-CARD grid (3 columns).
LY.MONSTER_CONTROLS_HEIGHT = 40
LY.MONSTER_GRID_TOP = LY.CONTENT_TOP + LY.MONSTER_CONTROLS_HEIGHT + 8
LY.WIDE_CARD_HEIGHT = 116

local monsterControls = apply(Instance.new("Frame"), {
    Name = "MonsterControls",
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(0, LY.CONTENT_TOP),
    Size = UDim2.new(1, 0, 0, LY.MONSTER_CONTROLS_HEIGHT),
    ZIndex = 21,
    Parent = panel,
})

-- Filter chips (left): "Semua" + one circle per element.
local filterRow = apply(Instance.new("Frame"), {
    Name = "Filters",
    BackgroundTransparency = 1,
    Size = UDim2.new(1, -150, 1, 0),
    ZIndex = 22,
    Parent = monsterControls,
})
apply(Instance.new("UIListLayout"), {
    FillDirection = Enum.FillDirection.Horizontal,
    SortOrder = Enum.SortOrder.LayoutOrder,
    Padding = UDim.new(0, 8),
    Parent = filterRow,
})

LY.FILTER_ACTIVE = Color3.fromRGB(59, 130, 246) -- mock: blue highlight
local monsterFilter: string = "All"
local monsterSort: string = "level" -- "level" | "rarity" | "new"
local filterButtons: { [string]: TextButton } = {}

local function makeFilterChip(order: number, key: string, text: string, width: number): TextButton
    local chip = apply(Instance.new("TextButton"), {
        Name = "Filter" .. key,
        LayoutOrder = order,
        AutoButtonColor = true,
        Size = UDim2.fromOffset(width, LY.MONSTER_CONTROLS_HEIGHT - 4),
        BackgroundColor3 = Color.SlotEmpty,
        BorderSizePixel = 0,
        FontFace = Font.Heavy,
        TextColor3 = Color.Text,
        TextScaled = true,
        Text = text,
        ZIndex = 23,
        Parent = filterRow,
    }, { corner(18), padding(6) })
    filterButtons[key] = chip
    return chip
end
makeFilterChip(1, "All", "Semua", 86)
for i, elementKey in ipairs(ElementConfig.order) do
    makeFilterChip(1 + i, elementKey, ElementConfig.display[elementKey].emoji, 44)
end

-- Sort cycle button (right): Level ↓ -> Rarity ↓ -> Terbaru -> ...
local sortBtn = apply(Instance.new("TextButton"), {
    Name = "SortBtn",
    AnchorPoint = Vector2.new(1, 0),
    Position = UDim2.fromScale(1, 0),
    Size = UDim2.fromOffset(140, LY.MONSTER_CONTROLS_HEIGHT - 4),
    AutoButtonColor = true,
    BackgroundColor3 = Color.SlotEmpty,
    BorderSizePixel = 0,
    FontFace = Font.Heavy,
    TextColor3 = Color.Text,
    TextScaled = true,
    Text = "Level ↓",
    ZIndex = 23,
    Parent = monsterControls,
}, { corner(10), padding(6) })

local list = apply(Instance.new("ScrollingFrame"), {
    Name = "List",
    Position = UDim2.fromOffset(0, LY.MONSTER_GRID_TOP),
    Size = UDim2.new(1, 0, 1, -LY.MONSTER_GRID_TOP),
    BackgroundColor3 = Color.SlotEmpty,
    BackgroundTransparency = 0.5,
    BorderSizePixel = 0,
    ScrollBarThickness = 6,
    CanvasSize = UDim2.new(),
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
    ZIndex = 21,
    Parent = panel,
}, { corner(12), padding(8) })

-- WIDE-CARD GRID (mock): 3 columns, scale-based cells so the 80% panel fills.
apply(Instance.new("UIGridLayout"), {
    CellSize = UDim2.new(1 / 3, -LY.CARD_GAP, 0, LY.WIDE_CARD_HEIGHT),
    CellPadding = UDim2.fromOffset(LY.CARD_GAP, LY.CARD_GAP),
    FillDirection = Enum.FillDirection.Horizontal,
    HorizontalAlignment = Enum.HorizontalAlignment.Left,
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
    Position = UDim2.new(0.5, 0, 0, LY.CONTENT_TOP + 16),
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
    Position = UDim2.fromOffset(0, LY.CONTENT_TOP),
    Size = UDim2.new(1, 0, 1, -LY.CONTENT_TOP),
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
    Position = UDim2.fromOffset(0, LY.CONTENT_TOP),
    Size = UDim2.new(1, 0, 1, -LY.CONTENT_TOP),
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
local currentTab = "monsters"

-- DISPLAY cap = the REAL persistence roster cap (200), not the legacy demo
-- crate guard (DemoConfig.rosterCap = 30) — the bag showed "(35/30)" once a
-- player owned more than 30 monsters.
local PersistenceConfig = require(Shared:WaitForChild("Config"):WaitForChild("PersistenceConfig"))
local ROSTER_CAP = PersistenceConfig.rosterCap

-- The Monster count lives in the panel title now (the tab bar is gone).
local function monsterTitle(): string
    return string.format("🐾 Monster (%d/%d)", #DemoClient.Inventory, ROSTER_CAP)
end

local function setTab(which: string)
    currentTab = which
    local isItems = which == "items"
    local isMonsters = which == "monsters"
    local isSkills = which == "skills"
    titleLabel.Text = if isItems then "🎒 Inventory" elseif isMonsters then monsterTitle() else "🌟 Skill"
    -- MOCK: the Monster tab takes ~80% of the screen with a semi-transparent
    -- backdrop; the other tabs keep the compact opaque panel.
    if isMonsters then
        panel.Size = UDim2.fromScale(0.8, 0.8)
        panel.BackgroundTransparency = 0.25
    else
        panel.Size = UDim2.fromOffset(LY.PANEL_WIDTH, LY.PANEL_HEIGHT)
        panel.BackgroundTransparency = 0
    end
    monsterControls.Visible = isMonsters
    itemsList.Visible = isItems
    list.Visible = isMonsters
    emptyLabel.Visible = isMonsters and emptyLabel.Visible -- re-evaluated by render()
    skillsList.Visible = isSkills
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
setTab("monsters") -- default tab

-- A reusable trove for the rendered cards so we cleanly clear + rebuild each update.
local cardsTrove = rootTrove:Extend()

-- Build one tappable GRID CARD into `parent` (the inventory grid): a square,
-- personality-COLOR tile with the personality EMOJI, its short name, and a ⭐ Lv N
-- badge. The whole card is a TextButton; tapping it calls `onTap` (which opens the
-- stat sheet for this item). `trove` owns the card so the caller controls lifetime;
-- `zBase` is the card's ZIndex (children sit at zBase+1). Cards are display-only —
-- the actual Summon/Deploy actions live in the stat sheet.
-- WIDE CARD (per owner mock): rarity-tinted border + dark body; element chip
-- top-left, evo badge top-right, BIG element emoji center, personality
-- small-caps + species name + Lv bottom-left, rarity-colored XP bar along the
-- bottom, status icon (🏠/⚔) bottom-right when not in the bag.
local function buildCard(
    parent: Instance,
    trove: typeof(rootTrove),
    item: DemoClient.InventoryItem,
    order: number,
    zBase: number,
    onTap: () -> ()
)
    local childZ = zBase + 1
    local rColor = rarityColor(item.rarity)

    local card = trove:Add(apply(Instance.new("TextButton"), {
        Name = "Card",
        LayoutOrder = order,
        AutoButtonColor = true,
        Text = "",
        BackgroundColor3 = Color.PanelLight,
        BackgroundTransparency = 0.25, -- semi-transparent body (mock)
        BorderSizePixel = 0,
        ZIndex = zBase,
        Parent = parent,
    }, { corner(12), stroke(rColor, 2), padding(8) }))
    trove:Add(card.Activated:Connect(onTap))

    -- Element chip (top-left, small circle).
    apply(Instance.new("TextLabel"), {
        Name = "ElementChip",
        BackgroundColor3 = Color.Panel,
        BackgroundTransparency = 0.2,
        Size = UDim2.fromOffset(28, 28),
        FontFace = Font.Regular,
        TextColor3 = Color.Text,
        TextScaled = true,
        Text = elementEmoji(item.element),
        ZIndex = childZ,
        Parent = card,
    }, { corner(14), padding(3) })

    -- Evo badge (top-right) — only when evolved.
    if (item.evoStage or 0) > 0 then
        apply(Instance.new("TextLabel"), {
            Name = "EvoBadge",
            AnchorPoint = Vector2.new(1, 0),
            Position = UDim2.fromScale(1, 0),
            BackgroundColor3 = Color.Panel,
            BackgroundTransparency = 0.2,
            Size = UDim2.fromOffset(28, 28),
            FontFace = Font.Regular,
            TextColor3 = Color.Text,
            TextScaled = true,
            Text = stageEmoji(item.evoStage),
            ZIndex = childZ,
            Parent = card,
        }, { corner(14), padding(3) })
    end

    -- BIG element emoji, centered (model ViewportFrame replaces this later).
    apply(Instance.new("TextLabel"), {
        Name = "Portrait",
        AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.new(0.5, 0, 0, 2),
        Size = UDim2.fromOffset(48, 48),
        BackgroundTransparency = 1,
        FontFace = Font.Regular,
        TextColor3 = Color.Text,
        TextScaled = true,
        Text = elementEmoji(item.element),
        ZIndex = childZ,
        Parent = card,
    })

    -- Bottom-left text block: PERSONALITY (small caps dim) / SpeciesName / Lv.
    apply(Instance.new("TextLabel"), {
        Name = "Personality",
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.new(0, 0, 1, -42),
        Size = UDim2.new(0.7, 0, 0, 12),
        BackgroundTransparency = 1,
        FontFace = Font.Bold,
        TextColor3 = Color.TextDim,
        TextScaled = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        Text = string.upper(item.personality),
        ZIndex = childZ,
        Parent = card,
    })
    apply(Instance.new("TextLabel"), {
        Name = "SpeciesName",
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.new(0, 0, 1, -24),
        Size = UDim2.new(0.7, 0, 0, 18),
        BackgroundTransparency = 1,
        FontFace = Font.Heavy,
        TextColor3 = Color.Text,
        TextScaled = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        Text = DemoConfig.speciesNames[item.element] or string.upper(item.personality),
        ZIndex = childZ,
        Parent = card,
    })
    apply(Instance.new("TextLabel"), {
        Name = "Level",
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.new(0, 0, 1, -10),
        Size = UDim2.new(0.5, 0, 0, 12),
        BackgroundTransparency = 1,
        FontFace = Font.Bold,
        TextColor3 = Color.TextDim,
        TextScaled = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        Text = ("Lv %d"):format(item.level),
        ZIndex = childZ,
        Parent = card,
    })

    -- XP bar along the bottom (fill tinted by rarity, per mock).
    local xpTrack = apply(Instance.new("Frame"), {
        Name = "XpTrack",
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.fromScale(0, 1),
        Size = UDim2.new(1, -32, 0, 5),
        BackgroundColor3 = Color.SlotEmpty,
        BorderSizePixel = 0,
        ZIndex = childZ,
        Parent = card,
    }, { corner(3) })
    local denom = if item.xpToNext > 0 then item.xpToNext else 1
    apply(Instance.new("Frame"), {
        Name = "XpFill",
        Size = UDim2.fromScale(math.clamp(item.xp / denom, 0, 1), 1),
        BackgroundColor3 = rColor,
        BorderSizePixel = 0,
        ZIndex = childZ + 1,
        Parent = xpTrack,
    }, { corner(3) })

    -- Status icon bottom-right (🏠 kandang / ⚔ summon); bag = clean.
    if item.status == "kandang" or item.status == "summon" then
        apply(Instance.new("TextLabel"), {
            Name = "Status",
            AnchorPoint = Vector2.new(1, 1),
            Position = UDim2.fromScale(1, 1),
            Size = UDim2.fromOffset(24, 24),
            BackgroundTransparency = 1,
            FontFace = Font.Regular,
            TextColor3 = Color.Text,
            TextScaled = true,
            Text = if item.status == "kandang" then "🏠" else "⚔",
            ZIndex = childZ,
            Parent = card,
        })
    end
end

-- Build one creature ROW into `parent` (used by the PLACE MENU, which keeps its
-- list style): emoji + name + color-coded personality badge. Tappable; `onTap`
-- fires on tap. `trove` owns the row; `zBase` is the row ZIndex (children +1).
LY.PLACE_ROW_HEIGHT = 56
LY.PLACE_ROW_BADGE_WIDTH = 78
LY.PLACE_ROW_BADGE_GAP = 6
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
        Size = UDim2.new(1, 0, 0, LY.PLACE_ROW_HEIGHT),
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
        Size = UDim2.new(0, LY.PLACE_ROW_HEIGHT - 12, 1, 0),
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
        Position = UDim2.new(0, LY.PLACE_ROW_HEIGHT, 0.5, 0),
        Size = UDim2.new(1, -LY.PLACE_ROW_HEIGHT - LY.PLACE_ROW_BADGE_WIDTH - LY.PLACE_ROW_BADGE_GAP, 1, -12),
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
        Size = UDim2.fromOffset(LY.PLACE_ROW_BADGE_WIDTH, LY.PLACE_ROW_HEIGHT - 18),
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
    Size = UDim2.fromOffset(LY.SHEET_WIDTH, LY.SHEET_HEIGHT),
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
    Size = UDim2.new(1, -(LY.SHEET_CLOSE_SIZE + 8), 0, LY.SHEET_HEADER_HEIGHT),
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
    Size = UDim2.fromOffset(LY.SHEET_CLOSE_SIZE, LY.SHEET_CLOSE_SIZE),
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
    Position = UDim2.fromOffset(0, LY.SHEET_XP_TOP + LY.SHEET_XP_HEIGHT / 2),
    Size = UDim2.new(0.55, 0, 0, LY.SHEET_XP_FILL_HEIGHT),
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
    Position = UDim2.new(1, 0, 0, LY.SHEET_XP_TOP + LY.SHEET_XP_HEIGHT / 2),
    Size = UDim2.new(0.4, 0, 0, LY.SHEET_XP_HEIGHT),
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
    Position = UDim2.fromOffset(0, LY.SHEET_STATS_TOP - 8),
    Size = UDim2.new(1, 0, 0, LY.SHEET_DIVIDER_HEIGHT),
    BackgroundColor3 = Color.Stroke,
    BorderSizePixel = 0,
    ZIndex = 52,
    Parent = sheetPanel,
})

-- HP / Power stat row (two halves).
local sheetHp = apply(Instance.new("TextLabel"), {
    Name = "Hp",
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(0, LY.SHEET_STATS_TOP),
    Size = UDim2.new(0.5, 0, 0, LY.SHEET_STATS_HEIGHT),
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
    Position = UDim2.new(1, 0, 0, LY.SHEET_STATS_TOP),
    Size = UDim2.new(0.5, 0, 0, LY.SHEET_STATS_HEIGHT),
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
    Position = UDim2.fromOffset(0, LY.SHEET_EFFECT_TOP),
    Size = UDim2.new(1, 0, 0, LY.SHEET_EFFECT_HEIGHT),
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
    Position = UDim2.fromOffset(0, LY.SHEET_FLAVOR_TOP),
    Size = UDim2.new(0.5, 0, 0, LY.SHEET_FLAVOR_HEIGHT),
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
    Position = UDim2.new(1, 0, 0, LY.SHEET_FLAVOR_TOP),
    Size = UDim2.new(0.5, 0, 0, LY.SHEET_FLAVOR_HEIGHT),
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
    Position = UDim2.new(0, 0, 1, -(LY.SHEET_ACTIONS_HEIGHT + LY.SHEET_ACTION_GAP + LY.SHEET_EVOLVE_HEIGHT + 8)),
    Size = UDim2.new(1, 0, 0, LY.SHEET_DIVIDER_HEIGHT),
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
    Position = UDim2.new(0, 0, 1, -(LY.SHEET_ACTIONS_HEIGHT + LY.SHEET_ACTION_GAP)),
    Size = UDim2.new(1, 0, 0, LY.SHEET_EVOLVE_HEIGHT),
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
    Size = UDim2.new(0.5, -LY.SHEET_ACTION_GAP / 2, 0, LY.SHEET_ACTIONS_HEIGHT),
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
    Size = UDim2.new(0.5, -LY.SHEET_ACTION_GAP / 2, 0, LY.SHEET_ACTIONS_HEIGHT),
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

    -- STATUS: only "bag" monsters can act — kandang/summon open READ-ONLY
    -- (the list shows everyone now; actions dim with a reason).
    local inBag = item.status == "bag" or item.status == nil
    sheetSummon.AutoButtonColor = inBag
    sheetSummon.BackgroundTransparency = if inBag then 0 else 0.5
    sheetDeploy.AutoButtonColor = inBag
    sheetDeploy.BackgroundTransparency = if inBag then 0 else 0.5

    -- EVOLVE button state (data from the server payload; server re-validates).
    if not inBag then
        sheetEvolve.Text = if item.status == "kandang" then "🏠 Sedang di Kandang" else "⚔ Sedang Bertarung"
        sheetEvolve.BackgroundColor3 = Color.SlotEmpty
        sheetEvolve.AutoButtonColor = false
    elseif item.evolveCost == nil then
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
    if not item or (item.status ~= nil and item.status ~= "bag") then
        return -- busy monsters are read-only
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
    if item.status ~= nil and item.status ~= "bag" then
        return -- busy monsters are read-only
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
    if not item or (item.status ~= nil and item.status ~= "bag") then
        return -- busy monsters are read-only
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
-- RENDER (Monster tab: filter -> sort -> wide-card grid)
-- ════════════════════════════════════════════════════════════════════════════

-- Rarity rank for the sort (ascending index in the canonical order).
local rarityRank: { [string]: number } = {}
for i, r in ipairs(RarityConfig.order) do
    rarityRank[r] = i
end

LY.SORT_LABELS = { level = "Level ↓", rarity = "Rarity ↓", new = "Terbaru" }

local function render(inventory: DemoClient.Inventory)
    cardsTrove:Clean()

    local n = #inventory
    print(("[Inv][ui] render count=%d"):format(n))
    if currentTab == "monsters" then
        titleLabel.Text = monsterTitle()
    end

    -- Filter chip highlight state.
    for key, chip in filterButtons do
        chip.BackgroundColor3 = if key == monsterFilter then LY.FILTER_ACTIVE else Color.SlotEmpty
    end
    sortBtn.Text = LY.SORT_LABELS[monsterSort] or "Level ↓"

    -- FILTER (element) then SORT (per the controls row).
    local shown: { DemoClient.InventoryItem } = {}
    for _, item in inventory do
        if monsterFilter == "All" or item.element == monsterFilter then
            table.insert(shown, item)
        end
    end
    table.sort(shown, function(a, b)
        if monsterSort == "rarity" then
            local ra = rarityRank[a.rarity] or 0
            local rb = rarityRank[b.rarity] or 0
            if ra ~= rb then
                return ra > rb
            end
            return a.level > b.level
        elseif monsterSort == "new" then
            return (a.capturedAt or 0) > (b.capturedAt or 0)
        end
        if a.level ~= b.level then
            return a.level > b.level
        end
        return (rarityRank[a.rarity] or 0) > (rarityRank[b.rarity] or 0)
    end)

    -- The empty-state belongs to the MONSTER tab only.
    emptyLabel.Visible = list.Visible and #shown == 0
    for i, item in shown do
        -- Each card is tap-to-open: tapping opens the STAT SHEET for this item,
        -- where the Summon / Deploy actions live.
        buildCard(list, cardsTrove, item, i, 22, function()
            print("[Inv][ui] open sheet " .. item.personality .. " id=" .. item.id)
            openSheet(item)
        end)
    end
end

-- Controls: filter chips re-render on tap; the sort button CYCLES modes.
for key, chip in filterButtons do
    rootTrove:Add(chip.Activated:Connect(function()
        monsterFilter = key
        render(DemoClient.Inventory)
    end))
end
LY.SORT_CYCLE = { "level", "rarity", "new" }
rootTrove:Add(sortBtn.Activated:Connect(function()
    local idx = table.find(LY.SORT_CYCLE, monsterSort) or 1
    monsterSort = LY.SORT_CYCLE[(idx % #LY.SORT_CYCLE) + 1]
    render(DemoClient.Inventory)
end))

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
    if input.KeyCode == LY.TOGGLE_KEY then
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
    Size = UDim2.fromOffset(LY.PLACE_WIDTH, LY.PLACE_HEIGHT),
    BackgroundColor3 = Color.Panel,
    BorderSizePixel = 0,
    ZIndex = 31,
    Parent = placeBackdrop,
}, { corner(20), stroke(Color.Stroke, 3), padding(14) })

local placeTitle = apply(Instance.new("TextLabel"), {
    Name = "Title",
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(0, 0),
    Size = UDim2.new(1, -(LY.PLACE_CLOSE_SIZE + 8), 0, LY.PLACE_TITLE_HEIGHT),
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
    Size = UDim2.fromOffset(LY.PLACE_CLOSE_SIZE, LY.PLACE_CLOSE_SIZE),
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
    Position = UDim2.fromOffset(0, LY.PLACE_LIST_TOP),
    Size = UDim2.new(1, 0, 1, -LY.PLACE_LIST_TOP),
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

    local order = 0
    for _, item in inventory do
        if item.status == nil or item.status == "bag" then -- busy excluded
            order += 1
            local itemId = item.id -- ID-KEYED deploy (the exact tapped monster)
            local personality = item.personality
            buildRow(placeList, placeRowsTrove, item, order, 32, function()
                print("[Place] chose " .. personality .. " (" .. itemId .. ") for stand " .. standIndex)
                DemoClient.deployToStand(standIndex, itemId)
                closePlaceMenu()
            end)
        end
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

LY.KANDANG_WIDTH = 420
LY.KANDANG_HEIGHT = 560
LY.KANDANG_TITLE_HEIGHT = 44
LY.KANDANG_CAP_TOP = 48 -- capacity bar row (under the title)
LY.KANDANG_CAP_HEIGHT = 26
LY.KANDANG_UPGRADE_TOP = LY.KANDANG_CAP_TOP + LY.KANDANG_CAP_HEIGHT + 8
LY.KANDANG_UPGRADE_HEIGHT = 48 -- the upgrade-button row (>=44px tap)
LY.KANDANG_LIST_TOP = LY.KANDANG_UPGRADE_TOP + LY.KANDANG_UPGRADE_HEIGHT + 10
LY.KANDANG_CLOSE_SIZE = 44 -- MOBILE: >=44px touch target
LY.KANDANG_ROW_HEIGHT = 56
LY.KANDANG_SECTION_HEIGHT = 30
LY.KANDANG_BADGE_WIDTH = 86
LY.KANDANG_LV_PILL_WIDTH = 72

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
    Size = UDim2.fromOffset(LY.KANDANG_WIDTH, LY.KANDANG_HEIGHT),
    BackgroundColor3 = Color.Panel,
    BorderSizePixel = 0,
    ZIndex = 41,
    Parent = kandangBackdrop,
}, { corner(20), stroke(Color.Stroke, 3), padding(14) })

apply(Instance.new("TextLabel"), {
    Name = "Title",
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(0, 0),
    Size = UDim2.new(1, -(LY.KANDANG_CLOSE_SIZE + LY.KANDANG_LV_PILL_WIDTH + 16), 0, LY.KANDANG_TITLE_HEIGHT),
    FontFace = Font.Heavy,
    TextColor3 = Color.Text,
    TextScaled = true,
    TextXAlignment = Enum.TextXAlignment.Left,
    Text = "🏠 KANDANG",
    ZIndex = 42,
    Parent = kandangPanel,
})

-- Level pill (between the title and the close button): "⬆ Lv3".
local kandangLvPill = apply(Instance.new("TextLabel"), {
    Name = "LevelPill",
    AnchorPoint = Vector2.new(1, 0),
    Position = UDim2.new(1, -(LY.KANDANG_CLOSE_SIZE + 8), 0, 6),
    Size = UDim2.fromOffset(LY.KANDANG_LV_PILL_WIDTH, LY.KANDANG_TITLE_HEIGHT - 12),
    BackgroundColor3 = Color3.fromRGB(42, 157, 113),
    BorderSizePixel = 0,
    FontFace = Font.Heavy,
    TextColor3 = Color.TextOnBright,
    TextScaled = true,
    Text = "Lv 0",
    ZIndex = 42,
    Parent = kandangPanel,
}, { corner(10), padding(6) })

-- Capacity bar: green fill = occupied stands; centered "n/cap slot terisi".
local kandangCapTrack = apply(Instance.new("Frame"), {
    Name = "CapTrack",
    Position = UDim2.fromOffset(0, LY.KANDANG_CAP_TOP),
    Size = UDim2.new(1, 0, 0, LY.KANDANG_CAP_HEIGHT),
    BackgroundColor3 = Color.SlotEmpty,
    BorderSizePixel = 0,
    ZIndex = 42,
    Parent = kandangPanel,
}, { corner(8) })

local kandangCapFill = apply(Instance.new("Frame"), {
    Name = "CapFill",
    Size = UDim2.fromScale(0, 1),
    BackgroundColor3 = Color3.fromRGB(42, 157, 113),
    BorderSizePixel = 0,
    ZIndex = 43,
    Parent = kandangCapTrack,
}, { corner(8) })

local kandangCapText = apply(Instance.new("TextLabel"), {
    Name = "CapText",
    BackgroundTransparency = 1,
    Size = UDim2.fromScale(1, 1),
    FontFace = Font.Bold,
    TextColor3 = Color.Text,
    TextScaled = true,
    Text = "0/6 slot terisi",
    ZIndex = 44,
    Parent = kandangCapTrack,
}, { padding(4) })

local kandangClose = apply(Instance.new("TextButton"), {
    Name = "Close",
    AnchorPoint = Vector2.new(1, 0),
    Position = UDim2.fromScale(1, 0),
    Size = UDim2.fromOffset(LY.KANDANG_CLOSE_SIZE, LY.KANDANG_CLOSE_SIZE),
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
    Position = UDim2.fromOffset(0, LY.KANDANG_UPGRADE_TOP),
    Size = UDim2.new(1, 0, 0, LY.KANDANG_UPGRADE_HEIGHT),
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

-- (The Capture Net shop row moved to the MERCHANT NPC modal — see below.)

local kandangList = apply(Instance.new("ScrollingFrame"), {
    Name = "List",
    Position = UDim2.fromOffset(0, LY.KANDANG_LIST_TOP),
    Size = UDim2.new(1, 0, 1, -LY.KANDANG_LIST_TOP),
    BackgroundColor3 = Color.SlotEmpty,
    BackgroundTransparency = 0.5, -- airy: rows carry the visual weight
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

-- Menu state: the last server snapshot + open flag. Opening is EXPLICIT now —
-- only a payload with `open = true` (the gate terminal prompt) pops the menu;
-- every other push is a silent refresh (so catching never opens it).
local kandangOpen = false
local kandangLast: DemoClient.KandangPayload? = nil

local function closeKandangMenu()
    kandangOpen = false
    kandangBackdrop.Visible = false
    kandangRowsTrove:Clean()
end

-- One section header line ("DI KANDANG — tap untuk ambil") with a small
-- colored accent strip on the left (red = ambil section, green = taruh).
local function kandangSection(text: string, order: number, accent: Color3?)
    local header = kandangRowsTrove:Add(apply(Instance.new("TextLabel"), {
        Name = "Section",
        LayoutOrder = order,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, LY.KANDANG_SECTION_HEIGHT),
        FontFace = Font.Heavy,
        TextColor3 = Color.TextDim,
        TextScaled = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        Text = if accent then "      " .. text else text,
        ZIndex = 43,
        Parent = kandangList,
    }))
    if accent then
        apply(Instance.new("Frame"), {
            Name = "Accent",
            AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.fromScale(0, 0.5),
            Size = UDim2.new(0, 6, 1, -10),
            BackgroundColor3 = accent,
            BorderSizePixel = 0,
            ZIndex = 44,
            Parent = header,
        }, { corner(3) })
    end
end

-- One tappable row: personality emoji tile + label + action badge. The row
-- border is tinted by RARITY (same language as the monster cards).
-- `badgeColor` nil = personality color; `onTap` nil = inert (e.g. PENUH).
local function kandangRow(
    order: number,
    personality: string,
    label: string,
    badgeText: string,
    badgeColor: Color3?,
    onTap: (() -> ())?,
    rarity: any?
)
    local theme = UITheme.personality(personality)
    local row = kandangRowsTrove:Add(apply(Instance.new("TextButton"), {
        Name = "Row",
        LayoutOrder = order,
        AutoButtonColor = onTap ~= nil,
        Text = "",
        Size = UDim2.new(1, 0, 0, LY.KANDANG_ROW_HEIGHT),
        BackgroundColor3 = Color.PanelLight,
        BackgroundTransparency = if onTap then 0 else 0.4,
        BorderSizePixel = 0,
        ZIndex = 42,
        Parent = kandangList,
    }, { corner(10), stroke(rarityColor(rarity), 2), padding(6) }))
    if onTap then
        kandangRowsTrove:Add(row.Activated:Connect(onTap))
    end

    apply(Instance.new("TextLabel"), {
        Name = "Emoji",
        BackgroundTransparency = 1,
        Size = UDim2.new(0, LY.KANDANG_ROW_HEIGHT - 12, 1, 0),
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
        Position = UDim2.new(0, LY.KANDANG_ROW_HEIGHT, 0.5, 0),
        Size = UDim2.new(1, -LY.KANDANG_ROW_HEIGHT - LY.KANDANG_BADGE_WIDTH - 8, 1, -16),
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
        Size = UDim2.fromOffset(LY.KANDANG_BADGE_WIDTH, LY.KANDANG_ROW_HEIGHT - 20),
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

LY.AMBIL_COLOR = Color3.fromRGB(231, 111, 81) -- warm red: take OUT
LY.TARUH_COLOR = Color3.fromRGB(42, 157, 113) -- green: put IN

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
    kandangLvPill.Text = string.format("Lv %d", level)
    kandangCapFill.Size = UDim2.fromScale(if capacity > 0 then deployedCount / capacity else 0, 1)
    kandangCapText.Text = string.format("%d/%d slot terisi", deployedCount, capacity)

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
    kandangSection("DI KANDANG — tap untuk ambil", nextOrder(), LY.AMBIL_COLOR)
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
        kandangRow(nextOrder(), slot.personality, label, "AMBIL", LY.AMBIL_COLOR, function()
            DemoClient.recallDeployed(index)
        end, slot.rarity)
    end

    -- ── DI TAS ──
    kandangSection("DI TAS — tap untuk taruh", nextOrder(), LY.TARUH_COLOR)
    local inventory = DemoClient.Inventory
    if #inventory == 0 then
        kandangSection("   (tas kosong — pergi tangkap monster!)", nextOrder())
    end
    local firstFree: number? = payload.free[1]
    for _, item in inventory do
        if item.status ~= nil and item.status ~= "bag" then
            continue -- busy monsters can't be placed (list shows everyone now)
        end
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
            kandangRow(nextOrder(), personality, label, "TARUH", LY.TARUH_COLOR, function()
                DemoClient.deployToStand(target, itemId)
            end, item.rarity)
        else
            kandangRow(nextOrder(), personality, label, "PENUH", nil, nil, item.rarity)
        end
    end
end

-- Snapshot arrives: refresh if open; otherwise open ONLY on an explicit
-- open-intent payload (the gate terminal). Background refreshes (post-catch
-- net spend, post-action pushes) just update the cache silently.
DemoClient.KandangUpdated:Connect(function(payload)
    kandangLast = payload
    if kandangOpen then
        renderKandang()
        return
    end
    if payload.open ~= true then
        return -- live refresh while closed; cache only
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

-- ════════════════════════════════════════════════════════════════════════════
-- MERCHANT SHOP (modal) — opened by the Merchant NPC's Belanja prompt.
-- One item card (Capture Net) + two buy buttons. Counts ride BackpackUpdate
-- (DemoClient.Items), prices come from the replicated CaptureConfig, and the
-- server re-validates funds on every tap (the buttons are intents, not truth).
-- ════════════════════════════════════════════════════════════════════════════

LY.SHOP_WIDTH = 360
LY.SHOP_HEIGHT = 330
LY.SHOP_TITLE_HEIGHT = 44
LY.SHOP_GREET_TOP = 50
LY.SHOP_GREET_HEIGHT = 24
LY.SHOP_CARD_TOP = LY.SHOP_GREET_TOP + LY.SHOP_GREET_HEIGHT + 10
LY.SHOP_CARD_HEIGHT = 96
LY.SHOP_BTN_TOP = LY.SHOP_CARD_TOP + LY.SHOP_CARD_HEIGHT + 12
LY.SHOP_BTN_HEIGHT = 52 -- MOBILE: >=44px touch target

local shopBackdrop = apply(Instance.new("TextButton"), {
    Name = "ShopBackdrop",
    Visible = false,
    Size = UDim2.fromScale(1, 1),
    BackgroundColor3 = Color.Backdrop,
    BackgroundTransparency = 0.4,
    BorderSizePixel = 0,
    AutoButtonColor = false,
    Text = "",
    ZIndex = 44,
    Parent = screen,
})

local shopPanel = apply(Instance.new("TextButton"), {
    Name = "ShopPanel",
    AutoButtonColor = false,
    Text = "",
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.fromOffset(LY.SHOP_WIDTH, LY.SHOP_HEIGHT),
    BackgroundColor3 = Color.Panel,
    BorderSizePixel = 0,
    ZIndex = 45,
    Parent = shopBackdrop,
}, { corner(20), stroke(Color3.fromRGB(255, 206, 64), 3), padding(14) })

apply(Instance.new("TextLabel"), {
    Name = "Title",
    BackgroundTransparency = 1,
    Size = UDim2.new(1, -52, 0, LY.SHOP_TITLE_HEIGHT),
    FontFace = Font.Heavy,
    TextColor3 = Color.Text,
    TextScaled = true,
    TextXAlignment = Enum.TextXAlignment.Left,
    Text = "🛒 MERCHANT",
    ZIndex = 46,
    Parent = shopPanel,
})

local shopClose = apply(Instance.new("TextButton"), {
    Name = "Close",
    AnchorPoint = Vector2.new(1, 0),
    Position = UDim2.fromScale(1, 0),
    Size = UDim2.fromOffset(44, 44),
    BackgroundColor3 = Color.SlotEmpty,
    BorderSizePixel = 0,
    FontFace = Font.Heavy,
    TextColor3 = Color.Text,
    TextScaled = true,
    Text = "✕",
    ZIndex = 47,
    Parent = shopPanel,
}, { corner(10), padding(8) })

apply(Instance.new("TextLabel"), {
    Name = "Greeting",
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(0, LY.SHOP_GREET_TOP),
    Size = UDim2.new(1, 0, 0, LY.SHOP_GREET_HEIGHT),
    FontFace = Font.Bold,
    TextColor3 = Color.TextDim,
    TextScaled = true,
    TextXAlignment = Enum.TextXAlignment.Left,
    Text = "Perlengkapan hunter — bayar pakai koin!",
    ZIndex = 46,
    Parent = shopPanel,
})

-- Item card: big net icon + name + owned count.
local shopCard = apply(Instance.new("Frame"), {
    Name = "NetCard",
    Position = UDim2.fromOffset(0, LY.SHOP_CARD_TOP),
    Size = UDim2.new(1, 0, 0, LY.SHOP_CARD_HEIGHT),
    BackgroundColor3 = Color.PanelLight,
    BorderSizePixel = 0,
    ZIndex = 46,
    Parent = shopPanel,
}, { corner(12), padding(10) })

apply(Instance.new("TextLabel"), {
    Name = "Icon",
    BackgroundTransparency = 1,
    Size = UDim2.new(0, 64, 1, 0),
    FontFace = Font.Regular,
    TextColor3 = Color.Text,
    TextScaled = true,
    Text = "🕸️",
    ZIndex = 47,
    Parent = shopCard,
})

apply(Instance.new("TextLabel"), {
    Name = "ItemName",
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(76, 6),
    Size = UDim2.new(1, -80, 0.5, -6),
    FontFace = Font.Heavy,
    TextColor3 = Color.Text,
    TextScaled = true,
    TextXAlignment = Enum.TextXAlignment.Left,
    Text = "Capture Net",
    ZIndex = 47,
    Parent = shopCard,
})

local shopOwned = apply(Instance.new("TextLabel"), {
    Name = "Owned",
    BackgroundTransparency = 1,
    AnchorPoint = Vector2.new(0, 1),
    Position = UDim2.new(0, 76, 1, -6),
    Size = UDim2.new(1, -80, 0.5, -6),
    FontFace = Font.Bold,
    TextColor3 = Color.TextDim,
    TextScaled = true,
    TextXAlignment = Enum.TextXAlignment.Left,
    Text = "Punya: ×0",
    ZIndex = 47,
    Parent = shopCard,
})

-- Buy buttons (green when affordable, dim when not — server still re-checks).
local shopBuyOne = apply(Instance.new("TextButton"), {
    Name = "BuyOne",
    Position = UDim2.fromOffset(0, LY.SHOP_BTN_TOP),
    Size = UDim2.new(0.5, -6, 0, LY.SHOP_BTN_HEIGHT),
    AutoButtonColor = true,
    BackgroundColor3 = Color3.fromRGB(42, 157, 113),
    BorderSizePixel = 0,
    FontFace = Font.Heavy,
    TextColor3 = Color.TextOnBright,
    TextScaled = true,
    Text = "Beli 1",
    ZIndex = 46,
    Parent = shopPanel,
}, { corner(12), padding(8) })

local shopBuyBundle = apply(Instance.new("TextButton"), {
    Name = "BuyBundle",
    AnchorPoint = Vector2.new(1, 0),
    Position = UDim2.new(1, 0, 0, LY.SHOP_BTN_TOP),
    Size = UDim2.new(0.5, -6, 0, LY.SHOP_BTN_HEIGHT),
    AutoButtonColor = true,
    BackgroundColor3 = Color3.fromRGB(42, 157, 113),
    BorderSizePixel = 0,
    FontFace = Font.Heavy,
    TextColor3 = Color.TextOnBright,
    TextScaled = true,
    Text = "Paket 10",
    ZIndex = 46,
    Parent = shopPanel,
}, { corner(12), padding(8) })

local shopOpen = false

-- Re-paint the dynamic bits: owned count + price labels + affordability tint.
local function renderShop()
    local netDef = CaptureConfig.items.capture_net
    local owned = DemoClient.Items.capture_net or 0
    local coins = DemoClient.getDisplayCoins()
    shopOwned.Text = ("Punya: ×%d"):format(owned)
    shopBuyOne.Text = ("Beli 1 — %d 🪙"):format(netDef.price)
    shopBuyBundle.Text = ("Paket %d — %d 🪙"):format(netDef.bundleCount, netDef.bundlePrice)
    shopBuyOne.BackgroundColor3 = if coins >= netDef.price then Color3.fromRGB(42, 157, 113) else Color.SlotEmpty
    shopBuyBundle.BackgroundColor3 = if coins >= netDef.bundlePrice
        then Color3.fromRGB(42, 157, 113)
        else Color.SlotEmpty
end

local function closeShop()
    shopOpen = false
    shopBackdrop.Visible = false
end

-- NPC prompt triggered: render fresh + open.
DemoClient.ShopRequested:Connect(function()
    shopOpen = true
    renderShop()
    shopBackdrop.Visible = true
end)

-- Live refresh while open: item counts (purchase/consumption) + coin ticks.
DemoClient.ItemsChanged:Connect(function()
    if shopOpen then
        renderShop()
    end
end)
DemoClient.CoinsChanged:Connect(function()
    if shopOpen then
        renderShop()
    end
end)

rootTrove:Add(shopClose.Activated:Connect(closeShop))
rootTrove:Add(shopBackdrop.Activated:Connect(closeShop))
rootTrove:Add(shopBuyOne.Activated:Connect(function()
    if shopOpen then
        DemoClient.buyCaptureItem(false)
    end
end))
rootTrove:Add(shopBuyBundle.Activated:Connect(function()
    if shopOpen then
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

-- Drive the counter every frame, throttled to ~LY.HUD_REFRESH_SEC, so it ticks up
-- continuously without burning frames (mobile-friendly).
local refreshAccum = 0
rootTrove:Add(RunService.Heartbeat:Connect(function(dt: number)
    refreshAccum += dt
    if refreshAccum < LY.HUD_REFRESH_SEC then
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
