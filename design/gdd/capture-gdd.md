# Capture System GDD (Explore + Manual Catch)

**Version**: 1.2
**Last Updated**: 2026-05-26
**Author**: systems-designer
**Status**: Draft

> **Changelog**
> - **1.2 (2026-05-26)** — Cross-GDD schema reconciliation (persistence-gdd v1.1 owns the canonical shapes):
>   - **`BrainrotEntry.guid → id`.** Renamed the per-Brainrot GUID field from `guid` to `id` for consistency with the canonical Persistence schema (`id` is also the roster map key). Updated the `BrainrotEntry` contract (§3.3) and the `CaptureResult.entry` payload (§5). Same value, canonical name.
>   - **`freeCapturesOnboarding` is the canonical single source of truth.** `CaptureConfig.freeCapturesOnboarding` (§8.2) is the one authoritative definition; Persistence only READS/seeds the persisted `freeCapturesRemaining` counter from it (no duplicate value in `PersistenceConfig`). Clarified in §3.3.1 and §9.
> - **1.1 (2026-05-26)** — Resolved open questions #1 and #2.
>   - **Capture cost:** capture is no longer free. It now costs a small, config-driven amount of Meme Coins (`captureCostCoins`), debited server-side and atomically on SUCCESS only. First few captures are subsidized free for FTUE (`freeCapturesOnboarding`). Adds Economy (System #9) as a dependency. (§2.1, §2.4, §3, §5, §8.2, §9)
>   - **Roster-full behavior:** a catch attempted with a full roster (200) is now REJECTED with a clear warning and the wild creature is NOT despawned — it lives out its normal lifetime so the player can free a slot and retry. Roster-full check now runs BEFORE the coin debit (never charge then reject). (§2.4, §6, §7.1)

> **Parent GDD**: `design/gdd/systems-index.md` — System #4 (Capture, P1, core-loop entry point).
> **Source of Truth**: `idea/brainrotInc.md` (creative direction).
> **Dependencies**: System #1 Data Persistence & Roster, System #2 Personality, System #9 Economy (Meme Coins debit).
> **Depended On By**: Idle Production (#3), Battle (#5), Raid (#6), Evolution (#8), Auto-Catch (#10).

---

## 1. Overview & Purpose

Capture is the **front half of the core loop** and the player's first hands-on action: they walk into the city, find a wild Brainrot loafing at an "attention hotspot," tap it, nail a timing mini-game, and the creature joins their roster with a freshly rolled personality. It is the single moment where "the surprise" (a personality reveal) is delivered, which is the game's viral pillar.

This system exists to (a) grow the player's roster (which feeds every downstream system: Idle Production, Battle, Raid, Evolution), and (b) deliver the **personality-reveal delight beat** described in the creative pillar — "every capture feels different." It is intentionally scoped tight for a solo dev: **one** explorable hub zone with config-driven spawns, server-authoritative resolution, and a documented fallback to a crate/encounter UI if schedule slips.

Capture is **server-authoritative**. The client expresses intent and plays animation/feedback only. The server owns spawn state, validates the timing result, rolls species and personality, mints the GUID, and writes to the roster.

---

## 2. Core Mechanics

### 2.1 The flow a kid understands in under 30 seconds

> **One-line rule shown in FTUE:** "See a glowing Brainrot → walk up → tap → stop the bar on green → it's yours!"

1. **See it** — Wild Brainrots appear at glowing hotspots around Downtown Scroll. They bounce and emote so they are obviously "catchable."
2. **Walk up** — Get close (inside the catch radius). The Brainrot shows a "Tap to Catch!" prompt (Roblox ProximityPrompt-style, mobile-friendly).
3. **Tap** — Tapping opens the timing mini-game: a moving marker sweeps left↔right across a bar with a green zone.
4. **Stop on green** — Tap again to stop the marker. Land inside green = catch. Miss = the Brainrot gets startled (short stun), you can retry until it despawns.
5. **Reveal** — On success the screen shows a Catch Card: art + name + personality + one funny line. (This is the payoff moment.)
6. **It's yours** — The new Brainrot is added to your roster. From the roster you later deploy it to your base (handled by Idle Production / base systems, not here).

**Capture costs a small Meme Coin fee** (`CaptureConfig.captureCostCoins`, default 25 — a light, config-driven sink). The fee is **charged only on a successful catch** (see §2.4 rationale), so missing the timing never costs coins. The player's **first few captures are free** (`CaptureConfig.freeCapturesOnboarding`, default 3) so FTUE friction is zero — a brand-new player completes the guided first catches without ever touching the wallet, then the cost kicks in once the loop is understood. The skill "cost" (find it, time the tap) still applies on top.

### 2.2 Spawn model (config-driven hotspots)

- Downtown Scroll contains **N hotspots** (CONFIG-DRIVEN, `SpawnConfig.hotspots`). Each hotspot is a fixed world position with its own **spawn table** (a list of `{species, weight}` entries + a `rarityTier`).
- A global server **spawn director** keeps the number of live wild Brainrots between `minConcurrent` and `maxConcurrent`. On a timer (`spawnIntervalSec` ± jitter) it picks an empty hotspot and spawns one Brainrot whose species is rolled from that hotspot's spawn table by weight.
- Each spawned Brainrot has a **server-side spawn record** (the authoritative object): `spawnId` (GUID), `hotspotId`, `species`, `rarityTier`, `state`, `position`, `spawnedAt`, `claimedBy` (Player or nil), `claimLockUntil`.
- Spawns are server-owned; the client renders them from replicated state and never creates them.

### 2.3 Spawn State Machine

States: `Idle` (hotspot empty, no creature) → `Spawned` (creature present, claimable) → `Contested` (a player has a short claim lock while resolving) → `Captured` (terminal-success) / `Despawn` (terminal-timeout/cleanup, returns hotspot to `Idle`).

```
                  spawn director picks empty hotspot
        ┌────────┐  ───────────────────────────────►  ┌──────────┐
        │  Idle  │                                     │ Spawned  │
        └────────┘  ◄───────────────────────────────  └────┬─────┘
            ▲          hotspot freed (after Despawn)        │
            │                                               │ valid CaptureAttempt
            │                                               │ (in-range, first claimer)
            │                                               ▼
            │                                        ┌──────────────┐
            │   claim lock expires / timing FAIL ───►│  Contested   │
            │   (return to Spawned, retry allowed)   │ (claimLock by │
            │                                        │  one player)  │
            │                                        └──────┬───┬────┘
            │                                               │   │
            │                       timing SUCCESS (server  │   │ lifetimeSec elapsed
            │                       validates window) ──────┘   │ in any non-terminal state
            │                                               │   ▼
            │                                               ▼  ┌──────────┐
            │                                        ┌──────────┐ │ Despawn │
            └────────────────────────────────────── │ Captured │ │(timeout/ │
                       (Captured frees hotspot too)  │(terminal)│ │ cleanup) │
                                                     └──────────┘ └────┬─────┘
                                                                       │
                                                                  free hotspot → Idle
```

**Transition rules (server-enforced):**

| From | To | Trigger / Guard |
|------|----|-----------------|
| Idle | Spawned | Director timer fires AND live count < `maxConcurrent` AND hotspot empty |
| Spawned | Contested | Valid `CaptureAttempt` from an in-range player; `claimedBy` set, `claimLockUntil = now + claimLockSec` |
| Contested | Spawned | Timing FAIL, OR `claimLockUntil` elapsed without a result → claim released, retry allowed |
| Contested | Captured | Timing SUCCESS validated server-side by the claiming player within claim lock |
| Spawned | Despawn | `now - spawnedAt > lifetimeSec` (no one engaged) |
| Contested | Despawn | `now - spawnedAt > lifetimeSec` (lifetime is absolute, claim does not extend life) |
| Captured | (cleanup) | Creature removed; hotspot returns to Idle next director tick |
| Despawn | Idle | Cleanup complete; hotspot eligible again |

`Contested` is a **soft, short lock** (default 3s) so two players cannot both resolve the same creature; it is NOT a permanent reservation. First valid attempt wins the lock; others get a "Someone's grabbing this one!" rejection (see Edge Cases).

### 2.4 Server resolution sequence (the authoritative path)

When a player taps "stop":

1. Client fires `CaptureResolveRequest(spawnId, stopOffset)` (RemoteEvent, C→S).
2. Server runs the validation gauntlet (rate limit → types → spawn exists & in `Contested` by this player → claim not expired → range re-check → timing window check). Any failure → `CaptureResult{ ok=false, reason }`.
3. On pass: server computes `success` from the timing formula (§8.4). Failure path: state → `Spawned`, return `CaptureResult{ ok=false, reason="missed" }`.
4. On timing success: server **rolls species** from the hotspot spawn table (the species was actually fixed at spawn time — see note below) and **rolls personality** via `Personality.roll()`.
5. Server checks **roster cap** (200) FIRST (before any economy work). If full → abort, **leave the creature in the world** (state returns to `Spawned`, lifetime continues normally), return `CaptureResult{ ok=false, reason="roster_full" }`. **No coins are charged, no GUID minted.** UI shows the roster-full warning. The wild Brainrot is NOT despawned, so the player can free a slot and tap it again before its lifetime elapses. (Order matters: roster check precedes the coin debit so we never charge a player for a catch we then reject.)
6. Server resolves the **capture cost** (`CaptureConfig.captureCostCoins`):
   - If the player still has free onboarding captures remaining (`profile.freeCapturesRemaining > 0`), the cost is **0** for this catch; decrement the counter inside the same atomic op as the roster write.
   - Otherwise the server reads the player's authoritative Meme Coin balance from Economy (System #9). If `balance < captureCostCoins` → abort, **leave the creature in the world** (state → `Spawned`, normal lifetime), return `CaptureResult{ ok=false, reason="insufficient_coins" }`. No GUID minted, no debit. UI shows "Not enough Meme Coins" with the amount needed.
7. If room AND cost is affordable (or free): server performs an **atomic transaction** — in one Persistence/Economy operation it (a) debits `captureCostCoins` from the balance (or decrements `freeCapturesRemaining`), AND (b) builds a `BrainrotEntry` (GUID, species, personality, level=1, history seeded) and appends it to the roster. Either both succeed or neither does — no race where coins are taken without a Brainrot, or a Brainrot is granted without payment, or two concurrent resolves double-spend the same balance. If the atomic op fails (e.g. DataStore hiccup), nothing is committed and the creature returns to `Spawned` for retry (see §7.8).
8. State → `Captured`; creature removed from world; hotspot freed.
9. Server fires `CaptureResult{ ok=true, entry=<revealPayload>, coinsSpent=<amount> }` to the capturing client → triggers the Reveal Card (and a coin-spend feedback if `coinsSpent > 0`).

> **Charge on SUCCESS, not on ATTEMPT (design decision).** The fee is debited only when the catch actually lands (step 7), never when the player misses the timing. Rationale: charging per attempt would double-punish a player who has bad luck with latency/timing and would make a tight Legendary green zone feel predatory; it also conflicts with "retry is instant, no penalty" (§2.1 / §6). Charging on success keeps the cost a clean per-Brainrot sink that scales with how many creatures you actually own. **Anti-spam note:** because attempts are free, spam protection comes from the rate limit (4/sec, §5.1), the claim lock, and absolute `lifetimeSec` — not from a per-attempt fee. A player cannot brute-force value: every successful catch is paid for exactly once, atomically.

> **Species: rolled at spawn, not at catch.** To keep replication honest (the client sees the actual creature art before catching) species is rolled **when the creature spawns** and stored on the spawn record. The "roll" at capture time is just reading that stored species. Personality is rolled at capture time (it is hidden until reveal — that is the surprise). This is an explicit design decision; if a future design wants species hidden too, move the species roll to step 4.

### 2.5 Auto-Catch hook (interface only — do NOT design Auto-Catch here)

Capture resolution is exposed as a single server-side function so Auto-Catch (System #10) can reuse the exact same authoritative path:

```lua
-- ServerStorage: CaptureService
-- Resolves a capture authoritatively. Used by both the manual remote handler
-- AND (later) by Auto-Catch. source = "manual" | "auto".
function CaptureService.resolveCapture(
    player: Player,
    spawnId: string,
    stopOffset: number?,   -- nil when source == "auto" (auto skips timing, see below)
    source: string
): CaptureResult
```

- When `source == "manual"`: full timing validation runs.
- When `source == "auto"`: timing is bypassed and success is computed by Auto-Catch's own success model (defined in the Auto-Catch GDD) — but **species roll, personality roll, GUID mint, roster cap check, coin cost debit, and roster write all go through this same function**, guaranteeing one source of truth. Auto-Catch supplies a pre-validated spawn target; this function still re-checks roster cap, ownership, and Meme Coin balance, and performs the same atomic debit-plus-write. (Whether Auto-Catch should pay the same `captureCostCoins`, a different rate, or be free is an Auto-Catch design decision; this function exposes the cost as a parameter/hook so Auto-Catch can choose — the *mechanism* is shared, the *value* is its call.)

---

## 3. Data Schema

### 3.1 Spawn hotspot config (server-read, see §8 for the live table)

```lua
type RarityTier = "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary"

type SpawnTableEntry = {
    species: number,   -- species id (matches BrainrotEntry.species; numeric per Persistence schema)
    weight: number,    -- relative weight within this hotspot (>0)
}

type Hotspot = {
    hotspotId: string,           -- stable unique id, e.g. "downtown_fountain"
    displayName: string,         -- "The Algorithm Fountain"
    position: {x: number, y: number, z: number},  -- world anchor for spawn
    rarityTier: RarityTier,      -- drives green-zone width (rarer = harder, §8.4)
    spawnTable: {SpawnTableEntry}, -- weighted species list for this hotspot
}
```

### 3.2 Spawn record (server-only, ephemeral — never persisted, never DataStore)

```lua
type SpawnState = "Idle" | "Spawned" | "Contested" | "Captured" | "Despawn"

type SpawnRecord = {
    spawnId: string,          -- GUID for this live spawn instance (not the Brainrot GUID)
    hotspotId: string,
    species: number,          -- rolled from spawnTable at spawn time
    rarityTier: RarityTier,
    state: SpawnState,
    position: Vector3,
    spawnedAt: number,        -- os.clock() at spawn
    claimedBy: Player?,       -- set during Contested
    claimLockUntil: number,   -- os.clock() deadline for the active claim
}
```

This lives only in server memory (ephemeral). Nothing about a live spawn touches DataStore. Only the *result* (a `BrainrotEntry`) persists.

### 3.3 Roster write (the persisted output — owned by Persistence, System #1)

Capture does NOT define the roster schema; it conforms to the `BrainrotEntry` contract from the Persistence GDD. Capture produces a new entry and hands it to the Persistence service to append:

```lua
-- Contract assumed from design/gdd/persistence-gdd.md (System #1). Canonical field names: id + history.
type BrainrotEntry = {
    id: string,          -- unique per Brainrot, minted at capture (HttpService:GenerateGUID(false)); also the roster map key
    species: number,     -- copied from spawn record
    personality: string, -- enum from Personality.roll(): "Hyper"|"Lazy"|"Chaotic"|"Loyal"|"Rebel"
    level: number,       -- starts at 1
    history: {           -- lifetime counters (wired day-1 per Persistence notes; Evolution reads these)
        capturedAt: number,    -- os.time() (server clock)
        captureSource: string, -- "manual" | "auto"
        hotspotId: string,     -- where it was caught (flavor + analytics)
        -- lifetime production / raids survived / defends etc. owned & zero-init by their systems
    },
}
```

Capture writes the entry via the Persistence/Economy atomic path (see §2.4 step 7) — conceptually `RosterService.addEntry(player, entry)` plus an Economy debit committed together. The roster cap (200) is enforced **inside** that service AND re-checked by Capture before minting (defense in depth). Capture **does** touch the economy: it debits `captureCostCoins` Meme Coins (owned by Economy, System #9) in the same atomic operation as the roster append. It also reads/decrements the player's `freeCapturesRemaining` onboarding counter (see §3.3.1).

#### 3.3.1 Onboarding free-capture counter (persisted, owned by Persistence/Economy)

```lua
-- Field on the player profile (Persistence GDD, System #1). Capture reads & decrements it.
freeCapturesRemaining: number  -- starts at CaptureConfig.freeCapturesOnboarding (default 3),
                               -- decremented by 1 on each FREE successful capture, floored at 0.
                               -- When 0, captures cost captureCostCoins.
```

This counter is **persisted** (so the free captures survive a relog and aren't farmable by rejoining) and is initialized when the profile is first created, using **`CaptureConfig.freeCapturesOnboarding` as the single source of truth** for the seed value. Persistence reads that one canonical value to seed `freeCapturesRemaining`; it does NOT keep a second copy in `PersistenceConfig` (so the two can never drift). It is decremented inside the same atomic op as the roster write so a free capture can never be granted without consuming a free slot (no dupe).

### 3.4 What persists vs. ephemeral

| Data | Where | Persisted? |
|------|-------|-----------|
| Hotspot config | `ReplicatedStorage/Shared/Config/SpawnConfig` | Static (ships with game) |
| Capture tuning | `ReplicatedStorage/Shared/Config/CaptureConfig` | Static (ships with game) |
| Live spawn records | Server memory (CaptureService) | No (ephemeral) |
| New `BrainrotEntry` | DataStore via Persistence | **Yes** |
| Lifetime catch counter (for Auto-Catch unlock @ ~50) | Persistence player profile | **Yes** (incremented by Capture, owned by Persistence) |
| Meme Coin balance (debited on paid capture) | DataStore via Economy (#9) | **Yes** (owned by Economy; Capture debits via atomic op) |
| `freeCapturesRemaining` onboarding counter | Persistence player profile | **Yes** (seeded from `freeCapturesOnboarding`, decremented by Capture) |

---

## 4. Client-Server Split

| Concern | Client | Server (authoritative) |
|---------|--------|------------------------|
| Spawn existence & position | Renders from replicated spawn state | Owns spawn records, spawns/despawns, state machine |
| "In range" check | Shows prompt (UX only) | Re-validates distance on every attempt (authoritative) |
| Timing mini-game bar | Animates the marker locally for feel | Defines window params; validates `stopOffset` against window |
| Stop result (`stopOffset`) | Captures the player's tap timing, sends it | **Recomputes success**; never trusts client's "I caught it" |
| Species selection | Receives final species in result | Rolls/stores at spawn; reads at capture |
| Personality roll | Receives in reveal payload | Calls `Personality.roll()` — client never sees odds-affecting logic |
| GUID mint | Never | `HttpService:GenerateGUID(false)` server-side |
| Capture cost / Meme Coin balance | May *show* current balance & the cost (read-only HUD); never debits | Reads authoritative balance, checks affordability, **debits atomically** with roster write (§2.4). Client's claimed balance is never trusted. |
| Free-capture (onboarding) counter | May *show* "free catches left" (read-only) | Authoritative read/decrement of `freeCapturesRemaining`; decides free vs. paid |
| Roster write & cap | Never | `RosterService.addEntry` (atomic, capped) |
| Reveal Card | Plays animation/art/sound | Sends the reveal payload that authorizes it |
| Catch animation/VFX | Plays locally (and cosmetic broadcast) | N/A (cosmetic only) |

**Streaming**: Downtown Scroll uses `StreamingEnabled`. Spawn *logic and records are server-side and stream-independent*; only the *visual model* is subject to streaming. If a client has not streamed in a hotspot's region, it simply will not see/prompt that spawn — which is correct and harmless (see Edge Case §7.6).

---

## 5. RemoteEvents / Functions

Per `remotes.md`: **no Client→Server RemoteFunction** (server-hang risk). All client→server traffic is RemoteEvents with full validation + rate limiting. Spawn state replication is server→client.

All remotes are created centrally in `ReplicatedStorage/Shared/Remotes` and `require`d by both sides.

| Name | Type | Direction | Args | Validation | Rate Limit |
|------|------|-----------|------|------------|------------|
| `SpawnStateSync` | RemoteEvent | S→C | `(diffs: {SpawnDiff})` | N/A (server-authored) | Server-batched (~2/sec) |
| `CaptureAttempt` | RemoteEvent | C→S | `(spawnId: string)` | type=string, len≤64, spawn exists & `Spawned`, player in range, not rate-limited | 4 / sec |
| `CaptureResolveRequest` | RemoteEvent | C→S | `(spawnId: string, stopOffset: number)` | types ok, `spawnId` len≤64, `stopOffset` finite & within `[-1,1]`, spawn `Contested` by this player, claim not expired, in range | 4 / sec |
| `CaptureResult` | RemoteEvent | S→C | `(result: CaptureResult)` | N/A (server-authored) | n/a |
| `CaptureCancel` | RemoteEvent | C→S | `(spawnId: string)` | type=string, len≤64, spawn `Contested` by this player | 4 / sec |

```lua
type SpawnDiff = {
    spawnId: string,
    op: string,            -- "add" | "update" | "remove"
    hotspotId: string?,
    species: number?,      -- so client renders correct art
    rarityTier: string?,
    position: {number}?,   -- {x,y,z}; sent on add only
    state: string?,        -- "Spawned" | "Contested" | etc. (Idle/Captured/Despawn collapse to "remove")
}

type CaptureResult = {
    ok: boolean,
    reason: string?,       -- "missed" | "roster_full" | "insufficient_coins" | "out_of_range" | "claimed" | "expired" | "invalid"
    spawnId: string,
    coinsNeeded: number?,  -- present when reason == "insufficient_coins": captureCostCoins (so UI can show the shortfall)
    -- present only when ok == true:
    entry: {
        id: string,          -- canonical Brainrot id (GUID); matches BrainrotEntry.id (§3.3)
        species: number,
        personality: string,
        level: number,
    }?,
    coinsSpent: number?,   -- present when ok == true: Meme Coins actually debited (0 if it was a free onboarding capture)
    revealLine: string?,   -- 1-sentence plain-text flavor (server picks from localized table)
}
```

### 5.1 Server validation gauntlet (applies to `CaptureResolveRequest` — the security-critical one)

```
1. Rate limit (4/sec/player, sliding window per remotes.md). Over → drop silently.
2. typeof(spawnId)=="string" and #spawnId<=64.                  else → invalid
3. typeof(stopOffset)=="number" and stopOffset==stopOffset      -- NaN guard
   and math.abs(stopOffset) <= 1.                                else → invalid
4. record = spawns[spawnId]; record exists.                      else → invalid
5. record.state == "Contested".                                  else → expired/claimed
6. record.claimedBy == player.                                   else → claimed (someone else)
7. os.clock() <= record.claimLockUntil.                          else → expired
8. distance(player.character, record.position) <= catchRadius
   * radiusGrace.                                                else → out_of_range
9. timing success := abs(stopOffset) <= greenZoneHalfWidth(rarity)  (§8.4)
10. on success, in this exact order:
    a. ROSTER CAP CHECK (RosterService reports < 200).      else → roster_full; creature stays Spawned, NOT despawned, NO charge.
    b. roll species (read stored) + roll personality.
    c. COST RESOLUTION:
       - if profile.freeCapturesRemaining > 0 → cost = 0 (free onboarding capture).
       - else cost = CaptureConfig.captureCostCoins; require Economy balance >= cost.
                                                            else → insufficient_coins; creature stays Spawned, NOT despawned, NO charge.
    d. ATOMIC COMMIT (single op): debit cost from Meme Coins
       OR decrement freeCapturesRemaining, AND mint GUID + append BrainrotEntry to roster.
       If the atomic op fails → nothing committed; creature → Spawned for retry (§7.8).
    e. state → Captured; creature removed; hotspot freed.
    on fail (timing)   → state back to Spawned (retry allowed until despawn). No charge.
```

> **Charge ordering rule:** The roster-cap check (10a) runs BEFORE any cost work (10c/10d). A full roster is rejected with the creature left alive and the player's wallet untouched — never "charge then reject." The Meme Coin debit and the roster write happen in ONE atomic operation (10d): no path exists where coins leave the wallet without a Brainrot being added, and concurrent resolves on the same player (e.g. manual + auto, or remote spam that slips past the rate limit) cannot double-spend — the atomic op serializes them and the loser sees `insufficient_coins` or `roster_full` cleanly.

> **Anti-exploit core rule:** the server NEVER receives or trusts a boolean "I caught it." It receives only `stopOffset` and recomputes success against the **server's own** green-zone width for that rarity. The marker's speed/period and the window are server-defined config; even a perfect-bot client can do no better than landing in the legitimately-sized green zone. Sending `stopOffset` outside `[-1,1]` or NaN is rejected as invalid. Rapid spam is rate-limited and claim-locked.

---

## 6. Player-Facing UI

1. **World prompt** — A bouncing wild Brainrot with a glow + floating "Tap to Catch!" prompt when in range. Big tap target (mobile-first).
2. **Timing mini-game** — A horizontal bar with a green zone; a marker sweeps left↔right. One big "STOP" button (or tap-anywhere) below it. Clear, high-contrast, no text needed. Rarer creatures show a visibly narrower green zone (telegraphs difficulty honestly).
3. **Hit/Miss feedback** — Green flash + "ding" on hit; gray flash + "boing" + brief Brainrot startle on miss. Retry is instant (no penalty beyond the time pressure of despawn).
4. **Reveal Card** — Full-screen-ish card: species art, name, personality badge (color-coded by type), and one funny plain-text line (e.g., "Tralalero Tralala showed up. It's Chaotic. Good luck."). "Add to Roster" / auto-dismiss. If `coinsSpent > 0`, a small "−25 Meme Coins" tick animates off the wallet HUD. If it was a free onboarding capture (`coinsSpent == 0`), show a light "Free catch! (N left)" tag instead.
5. **Roster-full prompt** — If at 200, a clear modal: **"Roster penuh! Kosongkan slot dulu."** ("Your roster is full (200/200). Free up a slot to catch more.") with a shortcut to the roster manager. **The wild Brainrot stays in the world** (it is not consumed), so the player can free a slot and tap it again before its lifetime runs out. No coins are charged. The catch simply doesn't complete.
6. **Insufficient-coins prompt** — If the player can't afford the catch, a clear toast/modal: "Not enough Meme Coins — you need {coinsNeeded}." The creature stays in the world; the player can earn coins (idle production, etc.) and retry while it's still alive. No partial charge.
7. **Toast on edge cases** — "Someone grabbed this one!" (contested), "Too far — get closer!" (range), "It got away!" (despawn mid-attempt).

UI is pure presentation: reads replicated spawn state, fires intent remotes, plays the reveal the server authorizes. Reuses the shared UI/HUD framework (System #13).

---

## 7. Edge Cases & Error States

### 7.1 Roster full (200) at moment of catch
Server reaches resolution step 5/10a, `RosterService` reports full. Server aborts the catch, **does NOT despawn the creature, and does NOT charge any Meme Coins**, returning `CaptureResult{ ok=false, reason="roster_full" }`. Client shows the roster-full warning ("Roster penuh! Kosongkan slot dulu."). **No partial state**: no GUID minted, no entry half-written, no coin debited. The wild Brainrot **remains in the world and continues its normal `lifetimeSec`**, so the player can open the roster manager, free a slot, and tap the same creature again before it despawns. This is a deliberate change from the earlier despawn-on-full design: rejecting-without-consuming is more player-friendly and the abuse it was guarding against (camping a Legendary while juggling space) is acceptable — the absolute `lifetimeSec` already caps how long any creature can be parked, and the `Contested` claim lock is short so a full-roster player cannot indefinitely block others either (a failed/blocked resolve releases the claim back to `Spawned`). The roster-cap check runs BEFORE the coin debit specifically so a full-roster player is never charged for a catch that is then rejected.

### 7.1b Insufficient Meme Coins at moment of catch
Player passes timing and roster-cap but has `balance < captureCostCoins` and no free onboarding captures left (step 10c). Server aborts, **does NOT despawn the creature, and does NOT charge** (it can't — the debit is part of the atomic commit that never runs), returning `CaptureResult{ ok=false, reason="insufficient_coins", coinsNeeded=<captureCostCoins> }`. Client shows the insufficient-coins prompt. The creature stays alive for its normal lifetime so the player may earn coins and retry. No partial charge is possible because the debit and roster write are one atomic op (§5.1 step 10d) — a failure in either rolls back both. New players are insulated from this entirely until `freeCapturesRemaining` hits 0.

### 7.2 Two players contest the same Brainrot
First valid `CaptureAttempt` transitions `Spawned → Contested` and sets `claimedBy`. A second player's `CaptureAttempt` on a `Contested` spawn is rejected with `reason="claimed"` ("Someone's grabbing this one!"). If the first player fails/cancels/expires, state returns to `Spawned` and it's fair game again. The claim lock (`claimLockSec`, default 3s) is short so a hesitating player can't hog it; `lifetimeSec` is absolute and not extended by claims.

### 7.3 Disconnect mid-mini-game
`Players.PlayerRemoving` fires. CaptureService releases any spawn `claimedBy` that player (`Contested → Spawned`) so it isn't locked forever. No roster write occurred (resolution never completed), so there is no orphaned entry. The spawn lives out its normal `lifetimeSec`.

### 7.4 Client sends a fake/forged timing result (anti-exploit)
Covered by §5.1. The server ignores any client claim of success; it recomputes from `stopOffset` against its own green-zone width. Out-of-range/NaN `stopOffset` → `invalid`. Spamming `CaptureResolveRequest` → rate-limited (4/sec) and gated by the claim lock (only the claiming player, only while `Contested`, only once per claim — a second resolve on an already-resolved/expired claim fails). Forging a `spawnId` for a non-existent or already-captured spawn → `invalid`. Personality and species rolls happen entirely server-side; the client cannot bias them. Net: the best an exploiter can do is reliably land in a legitimately-sized green zone, i.e. play perfectly — which is allowed and harmless (success still yields a *random* personality).

### 7.5 Spawns exhausted / hotspot empty
If the director cannot find an empty hotspot (all occupied) it simply does not spawn that tick; live count is capped at `maxConcurrent` by design. If every spawn is mid-`Contested`, new players see no catchable creatures — acceptable; the director catches up as locks resolve/despawn. There is always at least `minConcurrent` targeted, so the world is never empty for long (director prioritizes refilling toward `minConcurrent`). Zero-input case: a player who taps nothing simply never opens the mini-game; no state changes.

### 7.6 StreamingEnabled hasn't streamed in part of the map
Spawn records are server-side and stream-independent, but a client that hasn't streamed in a hotspot region won't render or prompt that creature. This is correct: the player literally isn't near it (range check would fail anyway). When they walk over and the region streams in, `SpawnStateSync` ensures the client sees current spawns (server sends a full add-diff for in-region spawns on stream-in / on a periodic reconcile). No catch can succeed against an unstreamed spawn because the server range check (§5.1 step 8) requires the player's character to be physically within `catchRadius`.

### 7.7 Network lag mid-transaction (latency between attempt and resolve)
The claim lock (`claimLockSec`) gives a lag-tolerant window for the resolve to arrive. If the resolve arrives after `claimLockUntil`, it's rejected with `reason="expired"` and the spawn has already returned to `Spawned` (or despawned). The client shows "It got away!" and can retry if it's still alive. Because the server timestamps everything with `os.clock()`, no client-supplied time is trusted. `SpawnStateSync` ordering is not assumed (per remotes.md) — diffs are idempotent by `spawnId`+`op`.

### 7.8 DataStore / Economy unavailable at the atomic commit
The atomic debit-plus-roster-write (§5.1 step 10d) is `pcall`-wrapped (Persistence/Economy's responsibility). On failure it returns an error and **rolls back both halves** — neither the coin debit nor the roster append is committed. Capture returns `CaptureResult{ ok=false, reason="invalid" }` with a player-facing "Hiccup — try again!" toast, and **does not** despawn the creature (it returns to `Spawned` so the player can retry once the store recovers). No GUID is committed to memory, and **no coins are deducted**, without a successful (or session-cached, per Persistence policy) write. This guarantees the invariant: a player is never charged Meme Coins without receiving the Brainrot, and never receives a Brainrot without being charged (or consuming a free onboarding slot). Same rollback applies to the `freeCapturesRemaining` decrement on a free capture.

---

## 8. Balancing Parameters

All values config-driven. **Zero magic numbers in code.** Two configs:

### 8.1 `SpawnConfig` (director + hotspots)

```lua
-- ReplicatedStorage/Shared/Config/SpawnConfig.lua
-- Wild Brainrot spawning for Downtown Scroll. Designer-tuned. Schema version: 1
return {
    version = 1,

    -- DIRECTOR (global pacing of wild spawns)
    director = {
        -- Seconds between director spawn attempts.
        -- Range: 2-30 | Default: 6 (lively but not cluttered on mobile)
        spawnIntervalSec = 6,
        -- Random +/- jitter applied to interval (seconds) so spawns feel organic.
        -- Range: 0-5 | Default: 2
        spawnIntervalJitterSec = 2,
        -- Minimum live wild Brainrots the director targets.
        -- Range: 1-30 | Default: 6 (world never feels empty)
        minConcurrent = 6,
        -- Hard cap on live wild Brainrots (mobile perf + replication budget).
        -- Range: 1-40 | Default: 12 (StreamingEnabled + low-end mobile safe)
        maxConcurrent = 12,
        -- Seconds a wild Brainrot lives before despawning if not captured.
        -- Range: 15-300 | Default: 45 (long enough to find+catch, short enough to refresh)
        lifetimeSec = 45,
        -- Seconds a claim (Contested) holds before auto-release.
        -- Range: 1-10 | Default: 3 (covers latency, prevents hogging)
        claimLockSec = 3,
    },

    -- CATCH GEOMETRY
    -- Max distance (studs) a player may be from the spawn to attempt/resolve.
    -- Range: 5-30 | Default: 14
    catchRadius = 14,
    -- Multiplier applied to catchRadius on the SERVER re-check to forgive latency/movement.
    -- Range: 1.0-1.5 | Default: 1.15
    radiusGrace = 1.15,

    -- HOTSPOTS (config-driven; each has its own weighted spawn table + rarity)
    hotspots = {
        {
            hotspotId = "downtown_fountain",
            displayName = "The Algorithm Fountain",
            position = {x = 0, y = 5, z = 0},
            rarityTier = "Common",
            -- weight = relative chance within THIS hotspot; weights need not sum to 1.
            spawnTable = {
                {species = 1, weight = 50}, -- common meme creature
                {species = 2, weight = 35},
                {species = 3, weight = 15},
            },
        },
        {
            hotspotId = "neon_alley",
            displayName = "Neon Alley",
            position = {x = 120, y = 5, z = -40},
            rarityTier = "Rare",
            spawnTable = {
                {species = 4, weight = 60},
                {species = 5, weight = 30},
                {species = 6, weight = 10}, -- rarer pull
            },
        },
        {
            hotspotId = "viral_rooftop",
            displayName = "Viral Rooftop",
            position = {x = -80, y = 30, z = 90},
            rarityTier = "Legendary",
            spawnTable = {
                {species = 7, weight = 80},
                {species = 8, weight = 18},
                {species = 9, weight = 2},  -- the dream pull
            },
        },
    },
}
```

### 8.2 `CaptureConfig` (mini-game tuning)

```lua
-- ReplicatedStorage/Shared/Config/CaptureConfig.lua
-- Timing mini-game tuning. Designer-tuned. Schema version: 1
return {
    version = 1,

    -- Marker sweep period (seconds for a full left->right->left cycle).
    -- Lower = faster = harder. CLIENT animates to this; SERVER does not depend on it
    -- for success (success is purely stopOffset vs green-zone width).
    -- Range: 0.6-3.0 | Default: 1.4
    sweepPeriodSec = 1.4,

    -- Green-zone HALF-width as a fraction of the bar half-span, per rarity.
    -- Bar is modeled as offset in [-1, 1]; success if |stopOffset| <= halfWidth.
    -- Rarer = narrower = harder. Range each: 0.02-0.5
    greenZoneHalfWidth = {
        Common    = 0.30,  -- forgiving (FTUE, common hotspots)
        Uncommon  = 0.24,
        Rare      = 0.18,
        Epic      = 0.12,
        Legendary = 0.07,  -- tight; the skill flex
    },

    -- Meme Coin cost charged per SUCCESSFUL capture (light economy sink).
    -- Charged on success only (never on a missed timing), debited server-side and
    -- atomically with the roster write (§2.4, §5.1). Kept small so it is a gentle
    -- per-Brainrot sink, not a gate: at default it is trivially covered by early idle
    -- production, but it gives Meme Coins a constant outflow as the roster grows.
    -- Range: 0-1000 | Default: 25 (light sink; 0 would make capture free again)
    captureCostCoins = 25,

    -- Number of FREE captures a brand-new player gets before captureCostCoins applies.
    -- SINGLE SOURCE OF TRUTH for this value: Persistence READS this to seed the persisted
    -- profile.freeCapturesRemaining counter on first profile creation (no duplicate in PersistenceConfig).
    -- Guarantees zero wallet friction during FTUE so the first catches are pure delight.
    -- Set to 0 to charge from the very first catch; raise to subsidize more of onboarding.
    -- Range: 0-20 | Default: 3 (covers the guided FTUE catches with headroom)
    freeCapturesOnboarding = 3,

    -- Max attempts the design ALLOWS per spawn lifetime (soft; really bounded by lifetimeSec).
    -- 0 = unlimited retries until despawn. Range: 0-10 | Default: 0
    maxAttemptsPerSpawn = 0,

    -- Lifetime catch count at which basic Auto-Catch unlocks (read by Auto-Catch, mirrored here for clarity).
    -- Range: 10-200 | Default: 50 (per systems-index #10)
    autoCatchUnlockCatches = 50,
}
```

### 8.3 Spawn species roll formula (weighted pick, at spawn time)

```
Given hotspot.spawnTable = [{species_i, weight_i}], i = 1..k
  total = Σ weight_i
  r = random_int(1, total)                  -- server RNG, integer
  walk entries accumulating weight; pick first species_i where running_sum >= r

P(species_i) = weight_i / total
```
Example (neon_alley): P(s4)=60/100=0.60, P(s5)=0.30, P(s6)=0.10.

### 8.4 Capture timing success formula (server-authoritative)

```
SUCCESS  iff  |stopOffset| <= greenZoneHalfWidth[rarityTier]

Where:
  stopOffset           : number in [-1, 1]  -- player's marker position when they tapped STOP;
                                               0 = dead-center of the bar. Client-reported,
                                               server-validated (finite, in range, NaN-rejected).
  greenZoneHalfWidth[r]: config per rarity (§8.2). Rarer tier => smaller => harder.

Notes:
- This is fully deterministic from a single client input + server config. No RNG in the
  success check itself (RNG lives only in species/personality rolls). This makes it
  testable and exploit-resistant: the server's green-zone width is the only thing that
  matters, and the client cannot change it.
- "Effective catch chance" for a player of skill s (their typical |stopOffset| distribution)
  is the probability mass of that distribution within [-halfWidth, +halfWidth] — i.e.
  better timing = higher real-world success. Difficulty is tuned via halfWidth alone.
```

### 8.5 Personality roll (delegated to Personality System)

```
personality = Personality.roll()   -- server-side, System #2

Default weighting per systems-index #2 / lock context: uniform 20% each across
{Hyper, Lazy, Chaotic, Loyal, Rebel}. Capture does NOT own these weights — they live
in PersonalityConfig. Capture only consumes the returned enum. If Personality later
introduces rarity-weighted personalities, Capture needs no change.
```

### 8.6 Capture cost formula (server-authoritative, charged on SUCCESS only)

```
cost = (profile.freeCapturesRemaining > 0)
         and 0
         or  CaptureConfig.captureCostCoins

ALLOWED iff  cost == 0  OR  Economy.getBalance(player) >= cost     -- checked at step 10c

On atomic commit (step 10d):
  if cost == 0 then
      profile.freeCapturesRemaining = max(0, profile.freeCapturesRemaining - 1)
  else
      Economy.debit(player, cost)        -- balance -= cost, never below 0 (pre-checked)
  end
  RosterService.addEntry(player, entry)  -- same atomic transaction as the line above

Where:
  captureCostCoins        : config, Range 0-1000, Default 25 (§8.2)
  freeCapturesRemaining   : persisted profile counter, seeded = freeCapturesOnboarding (Default 3), floored at 0
  Economy.getBalance/debit: System #9 authoritative wallet API (server-side)

Notes:
- The charge is per SUCCESSFUL capture. A missed timing costs nothing (§2.4 rationale).
- Roster-cap (10a) is evaluated BEFORE cost (10c): a full roster is rejected with no charge.
- Debit + roster append are ONE atomic op (10d): no double-spend, no charge-without-Brainrot,
  no Brainrot-without-charge. Failure rolls back both (§7.8).
- Free vs. paid is decided purely by freeCapturesRemaining; once it reaches 0, every catch
  costs captureCostCoins until a config change.
```

---

## 9. Integration Points

| System | Direction | Interaction |
|--------|-----------|-------------|
| #1 Data Persistence & Roster | Capture → it | Mints GUID; calls `RosterService.addEntry(player, entry)`; relies on it to enforce roster cap 200 atomically; increments lifetime catch counter (for Auto-Catch unlock). Conforms to `BrainrotEntry` schema. |
| #2 Personality | Capture → it | Calls `Personality.roll()` at capture success; puts result in the entry + reveal. Does not own weights. |
| #9 Economy | Capture → it | **Debits `captureCostCoins` Meme Coins on each paid successful catch**, atomically with the roster write (§2.4 step 7, §5.1 step 10d). Reads the authoritative balance to check affordability before committing. Economy owns the wallet API (`getBalance` / `debit`) and the persisted balance; Capture only consumes it as a sink. Capture does NOT define coin earn rates. |
| #3 Idle Production | it → Capture (indirect) | New roster members become deployable workers. Capture grows the supply; no direct call. |
| #5 Battle / #6 Raid / #8 Evolution | downstream | Consume roster members Capture produces; Evolution reads `history` (seeded here at capture). No direct calls. |
| #10 Auto-Catch | it → Capture | Reuses `CaptureService.resolveCapture(player, spawnId, nil, "auto")`. Capture exposes the hook; Auto-Catch is designed separately. |
| #13 UI/HUD | Capture ↔ it | Capture's prompts, mini-game, reveal card, and edge-case toasts render through the shared UI framework. |
| #14 Onboarding/FTUE | Capture ↔ it | FTUE scripts the guided first capture; relies on Capture's prompt/mini-game/reveal existing. Capture must work before Auto-Catch (manual experienced first). **Capture's `freeCapturesOnboarding` (default 3) guarantees the FTUE catches cost zero Meme Coins** — a new player completes the guided catches before the wallet is ever touched. The free-capture counter (`freeCapturesRemaining`) is seeded on first profile creation (Persistence/Onboarding) and decremented by Capture. Onboarding may surface "free catches left" but does not own the cost logic. |
| Remotes (Shared) | Capture → it | Registers `CaptureAttempt`, `CaptureResolveRequest`, `CaptureCancel`, `CaptureResult`, `SpawnStateSync`; documented in `design/remotes-manifest.md`. |

**Events emitted (event-driven, per gameplay-systems.md):**
- `GameEvents.BrainrotCaptured:Fire({player, entry, source})` — so Onboarding, Analytics, Auto-Catch-unlock counter, and Moment System can react without Capture knowing about them.

---

## 10. Fallback Plan

> **Per systems-index #4 scope-risk note: explore-map capture is the single highest-effort MVP item. This section is mandatory.**

**Trigger (lock by build step 5, per systems-index build order):** If, at the Capture milestone, the explorable hub + `StreamingEnabled` + world-spawn pipeline is not demonstrably working and stable within the remaining schedule (e.g., streaming pop-in, mobile frame drops with `maxConcurrent` creatures, or director/state-machine bugs blocking a clean first-capture FTUE), **fall back to a crate/encounter UI**. This is a go/no-go decision made at step 5, not a mid-implementation pivot.

**What the fallback KEEPS (unchanged):**
- The **exact same timing mini-game** (§8.2, §8.4) — bar, green zone, rarity-narrowing.
- The **exact same server resolution** — `CaptureService.resolveCapture` (the hook from §2.5), species roll, `Personality.roll()`, GUID mint, roster cap, roster write.
- The **reveal card moment** (§6) — the viral pillar payoff is preserved 100%.
- The same remotes (`CaptureResolveRequest`/`CaptureResult`) and validation gauntlet.
- The same `SpawnConfig.hotspots` data, reused as **encounter pools** (a "tap an encounter button → server picks a hotspot's spawn table → presents one encounter").

**What the fallback DROPS (cost saved):**
- Free-roam exploration of Downtown Scroll, `StreamingEnabled` for spawns, world-positioned ProximityPrompts, the catch-radius/range checks, and the live spawn director/concurrency model.
- `SpawnStateSync` replication (no world creatures to replicate).
- Range-based edge cases (§7.6 streaming, §7.5 director exhaustion) become N/A; contested (§7.2) becomes N/A (encounters are per-player).

**Fallback flow:** Player taps an "Encounter" button (or NPC) → server (rate-limited) picks an encounter pool, rolls species at that moment, returns it → client shows the creature + opens the **same** mini-game → `CaptureResolveRequest(encounterId, stopOffset)` → same resolution + reveal. Encounters can be free (button) or gated by a cooldown/cost (designer choice — flag below). The hub still exists as the social/base space (it just isn't where you catch).

**Why this is safe:** because resolution, rolls, reveal, and persistence are already routed through one server function and one remote contract, the fallback is a **front-end swap** (how you encounter a creature), not a redesign of the authoritative core. The Auto-Catch hook (§2.5) is unaffected either way.

---

## Open Questions (for user / game-designer)

1. ~~**Roster-full behavior (§7.1):**~~ **RESOLVED (v1.1):** Catch is REJECTED with a clear warning and the wild creature is NOT despawned — it lives out its normal lifetime so the player can free a slot and retry. Roster-cap check runs before any coin charge. See §2.4 step 5, §7.1, §6 item 5.
2. ~~**Capture cost:**~~ **RESOLVED (v1.1):** Capture costs a small config-driven Meme Coin fee (`captureCostCoins`, default 25), charged on SUCCESS only, debited server-side and atomically with the roster write. First `freeCapturesOnboarding` (default 3) catches are free for zero FTUE friction. Adds Economy (#9) as a dependency. See §2.1, §2.4, §8.2, §8.6, §9.
3. **Fallback encounter gating:** If we ship the crate/encounter fallback, are encounters free-on-tap, on a cooldown, or cost Meme Coins? (Now partly informed by #2: the same `captureCostCoins` would apply on the fallback's successful catch, since cost lives in `resolveCapture`. Open part: any *additional* per-encounter gating/cooldown.) Balance + monetization decision.
4. ~~**Species hidden vs. visible pre-catch (§2.4 note):**~~ **CONFIRMED (v1.1):** Keep as specced — species is rolled at spawn so the world shows the real creature; personality stays secret until the reveal (the surprise). No change needed.
5. **Hotspot count N for launch:** Spec ships 3 example hotspots (Common/Rare/Legendary). What is the actual launch count, and is rarity tied to map *location* (e.g., rooftops = rarer) for environmental storytelling?
