--!strict
-- UITheme.luau
--
-- Shared style tokens + tiny UI builder helpers for the Brainrot Inc. demo UI.
-- Pure presentation: colors, fonts, sizes, personality color-coding, and a few
-- ergonomic Instance.new wrappers. No game state, no remotes.
--
-- Style brief: bright, playful, high-contrast meme-startup vibe. Placeholder art
-- is colored frames + emoji + text (no external assets).

local UITheme = {}

-- ── Palette ────────────────────────────────────────────────────────────────
UITheme.Color = {
    -- Backdrops
    Backdrop = Color3.fromRGB(18, 20, 28),
    Panel = Color3.fromRGB(30, 33, 46),
    PanelLight = Color3.fromRGB(44, 48, 66),
    SlotEmpty = Color3.fromRGB(38, 41, 56),

    -- Accents
    Coin = Color3.fromRGB(255, 206, 64),
    CrateButton = Color3.fromRGB(255, 92, 168),
    Collect = Color3.fromRGB(64, 214, 122),
    CollectDim = Color3.fromRGB(72, 84, 92),

    -- Text
    Text = Color3.fromRGB(245, 247, 255),
    TextDim = Color3.fromRGB(168, 176, 196),
    TextOnBright = Color3.fromRGB(20, 16, 28),

    -- Outlines
    Stroke = Color3.fromRGB(12, 13, 18),
}

-- Personality color-coding. Consistent everywhere a badge or tint appears.
-- Hyper=orange, Lazy=blue, Chaotic=purple, Loyal=green, Rebel=red.
UITheme.Personality = {
    Hyper = { color = Color3.fromRGB(255, 138, 38), emoji = "⚡" },
    Lazy = { color = Color3.fromRGB(64, 156, 255), emoji = "😴" },
    Chaotic = { color = Color3.fromRGB(176, 92, 255), emoji = "🎲" },
    Loyal = { color = Color3.fromRGB(64, 204, 120), emoji = "🛡️" },
    Rebel = { color = Color3.fromRGB(240, 72, 72), emoji = "🔥" },
}

local FALLBACK_PERSONALITY = { color = Color3.fromRGB(150, 150, 160), emoji = "❓" }

function UITheme.personality(name: string?): { color: Color3, emoji: string }
    if name == nil then
        return FALLBACK_PERSONALITY
    end
    return UITheme.Personality[name] or FALLBACK_PERSONALITY
end

-- ── Fonts ──────────────────────────────────────────────────────────────────
UITheme.Font = {
    Heavy = Font.fromEnum(Enum.Font.GothamBold),
    Bold = Font.fromEnum(Enum.Font.GothamMedium),
    Regular = Font.fromEnum(Enum.Font.Gotham),
}

-- ── Builder helpers ──────────────────────────────────────────────────────────
-- Apply a property dictionary to any instance and return it. Children, if any,
-- are passed as a separate array and parented in order. Keeping props and
-- children separate avoids selene's mixed_table lint and reads clearly.
function UITheme.apply<T>(inst: T, props: { [string]: any }?, children: { Instance }?): T
    local instance = inst :: any
    if props then
        for key, value in props do
            instance[key] = value
        end
    end
    if children then
        for _, child in children do
            child.Parent = instance
        end
    end
    return inst
end

function UITheme.new(className: string, props: { [string]: any }?, children: { Instance }?): Instance
    return UITheme.apply(Instance.new(className), props, children)
end

-- Rounded corners.
function UITheme.corner(radius: number): UICorner
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius)
    return c
end

-- Solid outline.
function UITheme.stroke(color: Color3, thickness: number): UIStroke
    local s = Instance.new("UIStroke")
    s.Color = color
    s.Thickness = thickness
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    return s
end

function UITheme.padding(px: number): UIPadding
    local p = Instance.new("UIPadding")
    p.PaddingTop = UDim.new(0, px)
    p.PaddingBottom = UDim.new(0, px)
    p.PaddingLeft = UDim.new(0, px)
    p.PaddingRight = UDim.new(0, px)
    return p
end

return UITheme
