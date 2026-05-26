---
paths:
  - "**/UI/**"
  - "**/Gui/**"
  - "**/Interface/**"
  - "src/StarterGui/**"
---

# UI Code Rules

Files matching these paths implement user interface. UI is a read-and-dispatch layer, not a state owner.

## Core Rules

1. **UI does not own game state.** It reads state and sends actions via Remotes. Server owns everything.
2. **Mobile-first responsive design.** Design for smallest screen first; scale up.
3. **All user-facing text must be localization-ready.** Don't hardcode English strings inline.
4. **Accessibility is built in, not bolted on.** Contrast, sizing, screen reader hints.
5. **Clean up UI connections when UI is destroyed.** No orphan signals.
6. **Use consistent styling.** Shared style constants module.

## Mobile-First Standards

- **Touch targets**: Minimum 44×44 pixels
- **Thumb zones**: Primary actions in reachable areas (bottom-right landscape, bottom portrait)
- **Font size**: Minimum 14pt (larger on smaller screens)
- **Contrast**: ≥ 4.5:1 (WCAG AA)
- **Safe area**: Avoid corners (notches, rounded screens on iPhone)

## Responsive Patterns

```lua
-- UIAspectRatioConstraint for maintaining proportions
local constraint = Instance.new("UIAspectRatioConstraint")
constraint.AspectRatio = 16 / 9
constraint.DominantAxis = Enum.DominantAxis.Width
constraint.Parent = frame

-- UIScale for global scale based on screen size
local scale = Instance.new("UIScale")
local function updateScale()
    local viewport = workspace.CurrentCamera.ViewportSize
    scale.Scale = math.clamp(viewport.X / 1920, 0.5, 1.5)
end
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
updateScale()
```

## State Flow

```
Server state → Remote → Client handler → UI update
Player input → UI dispatch → Remote → Server validation → Server state update
```

Never write:
```lua
-- WRONG: client mutates local game state
Players.LocalPlayer.PlayerData.Gold = 1000  -- Server owns this
```

Instead:
```lua
-- RIGHT: client dispatches action, server mutates state
Remotes.PurchaseItem:FireServer(itemId)
-- Server validates, mutates, replies
Remotes.PlayerDataUpdated.OnClientEvent:Connect(function(newData)
    updateHudDisplay(newData)
end)
```

## Cleanup Pattern

```lua
local Trove = require(game.ReplicatedStorage.Shared.Trove)

local function createShopGui(player: Player)
    local gui = Instance.new("ScreenGui")
    gui.Parent = player:WaitForChild("PlayerGui")

    local trove = Trove.new()
    trove:Add(gui)

    trove:Add(shopButton.MouseButton1Click:Connect(function()
        openShop()
    end))

    trove:Add(player.CharacterRemoving:Connect(function()
        trove:Clean()
    end))

    return trove
end
```

## Accessibility Checklist

Every UI addition must pass:
- [ ] Touch target ≥ 44×44 px
- [ ] Text contrast ≥ 4.5:1
- [ ] Text readable at device minimum (14pt scaled for viewport)
- [ ] Not color-alone (icon or shape differentiator for meaning)
- [ ] `AccessibleName` set for screen readers (where applicable)
- [ ] Reduced motion respected (if game has reduced motion toggle)

## Localization Pattern

```lua
-- NOT localization-ready:
label.Text = "You need 100 gold to buy this"

-- Localization-ready:
label.Text = Localization.get("shop.insufficient_funds", { amount = 100 })
```

## Forbidden Patterns

- ❌ UI directly mutating player data
- ❌ Hardcoded strings for user-facing text
- ❌ Font size < 14pt
- ❌ Touch targets < 44×44 px
- ❌ Color-only meaning (red/green without icons)
- ❌ Connections not cleaned up
- ❌ Per-frame UI creation (create once, reuse)
- ❌ Assuming desktop layout (test on 375×667 first)
