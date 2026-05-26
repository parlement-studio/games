---
paths:
  - "src/StarterGui/**"
  - "src/StarterPlayer/**"
  - "src/ReplicatedFirst/**"
---

# Client Scripts Rules

Files matching these paths are **client-side** code. These run on each player's device.

## Core Rules

1. **Client code is presentation-only.** Never mutate game state — just display it and collect input.
2. **No direct DataStore access.** DataStoreService calls from client are not possible; don't try to work around this.
3. **No ServerStorage or ServerScriptService references.** Those don't exist on the client.
4. **All player actions must go through RemoteEvents to the server.** The server decides if the action succeeds.
5. **Optimize for low-end mobile.** Minimize allocations per frame, especially in Heartbeat handlers.
6. **Clean up connections.** On character death, player leaving, or UI destruction, disconnect all signals.

## What Client CAN Do

- Render UI and HUD
- Play local sounds and animations
- Show visual effects (particles, beams, trails)
- Predict movement (rubber-banded to server authoritative state)
- Collect and transmit input
- Cache visual state for smoothness
- Handle local-only settings (graphics quality, audio volume)

## What Client CANNOT Do

- Change currency values (display only — server owns the truth)
- Award items, badges, or XP
- Access other players' data
- Persist anything to DataStore
- Call server-only services

## Mobile-First Performance

- **Heartbeat loops**: Throttle expensive work (10Hz, not 60Hz, when possible)
- **UI allocations**: Reuse instances; don't create new UI every frame
- **Tween stacking**: Cancel tweens when starting new ones on the same property
- **Particle rates**: Cap emission rates — mobile dies with thousands of particles
- **Model streaming**: Respect `StreamingEnabled`; don't assume parts exist

## Cleanup Pattern (Trove)

```lua
local Trove = require(game.ReplicatedStorage.Shared.Trove)
local trove = Trove.new()

trove:Add(someSignal:Connect(function(...)
    -- handle
end))

trove:Add(Instance.new("Part"))

-- On cleanup
trove:Clean()
```

## Input Handling

- Use `UserInputService` or `ContextActionService`
- Support touch, mouse, keyboard, gamepad, VR
- Handle device changes mid-session (user plugging in a gamepad)
- Respect platform conventions (back button on mobile, B on controller)

## Forbidden Patterns

- ❌ Direct `LocalPlayer.Data.Gold += 100` — server owns this
- ❌ Reading `ServerStorage.SecretConfig` — doesn't exist on client
- ❌ `Humanoid.Health = 100` in client code — server should set this
- ❌ Loops without throttling — kills mobile FPS
- ❌ Creating new tables/instances every frame
- ❌ Forgetting to disconnect signals on character respawn
