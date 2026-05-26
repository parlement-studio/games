---
name: perf-profile
description: Performance profiling guide — what to measure, how to use MicroProfiler, and common Roblox bottlenecks. Use when debugging performance issues.
---

# /perf-profile — Performance Profiling Guide

## Delegate to: performance-analyst

## When to Use
- Game feels laggy on mobile
- Server frame time is high
- Memory usage growing over session
- Network bandwidth high
- Any specific performance concern reported by users

## Steps

### 1. Define the Problem
Ask:
- "What's the symptom?" (FPS drop, memory growth, lag spike, high network)
- "When does it happen?" (always, combat, crowded servers, specific action)
- "What devices?" (mobile, PC, console, specific model)
- "What was the baseline?" (was this working before a change?)

### 2. Pick the Right Tool

#### MicroProfiler (primary tool)
- Server: Ctrl+F6 in Studio
- Client: Ctrl+Alt+F6 during playtest
- Shows per-frame breakdown — find what's eating the frame

#### Developer Console (F9)
- Stats tab for general metrics
- Log tab for errors

#### Script Profiler (Ctrl+Alt+F5)
- Per-script CPU usage
- Heap usage per script

#### Network Tab
- Bandwidth breakdown per remote

### 3. Common Server Bottlenecks

#### Heartbeat Time > 33ms
Check:
- Scripts in heavy loops over many instances
- DataStore calls not yielding
- Synchronous operations that should be async

#### Memory Growth
Check:
- Tables accumulating without cleanup
- Connections not disconnected
- Instances created without Destroy()

#### DataStore Budget Exhausted
Check:
- Save frequency too high
- Not debouncing saves
- Retries running too often on failure

### 4. Common Client Bottlenecks

#### FPS Drop on Mobile
Check:
- Transparency overdraw (stacked transparent parts)
- Particle rates too high
- Dynamic lights > 8 visible
- Post-processing stack (Bloom, DepthOfField)
- Part count in visible area

#### Lag Spikes
Check:
- Tweens starting and stopping (allocations)
- Large table creations per frame
- Heavy operations in Heartbeat

#### Memory Growth (Client)
Check:
- UI connections not cleaned up on PlayerGui destruction
- Image/sound caching without eviction
- Accumulating local state

### 5. Profiling Walkthrough

#### Measure Baseline
1. Open Studio
2. Play Solo or Team Test
3. Let game run for 30 seconds
4. Open MicroProfiler (Ctrl+F6 or Ctrl+Alt+F6)
5. Note: Heartbeat time, Script time, Render time

#### Identify the Spike
1. Trigger the suspected issue (e.g., start combat)
2. Watch MicroProfiler for the frame time spike
3. Click on the spike bar to drill down
4. Find the specific label/category consuming time

#### Optimize and Re-measure
1. Apply the fix
2. Re-run the same test
3. Verify the time decreased
4. Document the improvement

### 6. Output
```markdown
# Performance Profile: [Problem]

## Environment
- Device: [device]
- Scene: [what was happening]
- Player count: [N]

## Measurements
| Metric | Before | After | Delta |
|--------|--------|-------|-------|
| Server Heartbeat | 45ms | 28ms | -17ms ✅ |
| Client FPS | 22 | 48 | +26 ✅ |
| Memory | 1.8GB | 1.6GB | -200MB ✅ |

## Root Cause
[What was causing the issue]

## Fix Applied
- [File path]: [what changed]

## Remaining Concerns
- [Anything that could improve further]
```

Present to user. Offer to delegate fix implementation to relevant programmer specialist.
