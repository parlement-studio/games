# Raid v1 GDD (vs NPC Rival Startups)

**Version**: 1.2
**Last Updated**: 2026-05-29
**Author**: systems-designer
**Status**: Draft

> **Changelog v1.2 (2026-05-29)**: **`raidLootPct` lowered from 0.25 to 0.20** per economy-designer circulation analysis (owner sign-off). Rationale: at 0.25 a tier-3 raid (Pivot Ventures) outputs `floor(7500·0.28) = 2100` loot at ~5-min cooldown ≈ 25K coins/hour — that's competitive with idle's primary faucet at comparable upgrade level, breaking the "raid = secondary engagement faucet ≤30% of idle" rule (same rule applied to `field_combat_win` Pet AI #25). With **global default 0.20**, tier-3 raid loot stays bounded at the desired "engagement reward, not coin printer" level; per-rival overrides remain a design lever (Pivot's `lootPct = 0.28` preserved as intentional tier-3 bonus — see §8.3). **Side effect surfaced**: at tier-1 (Grind Corp, new player) `loot = floor(640·0.20) = 128`, break-even win rate rises to 78.1% (vs prior 62.5% at 0.25). At the "fair-skill" 75% benchmark, EV is **slightly negative (-4 coins/raid)** for an absolute new player — this is documented in §8.5 + flagged as Open Question #5 (whether to (a) ship as-is with first-raid-free Daily Quest offset, (b) bump Grind Corp `poolBase` 600→700, or (c) add per-rival override `Grind Corp.lootPct = 0.25` to preserve tier-1 break-even). **Open Question #2** (raidSendCost/raidLootPct lock) is **REVISED**: locked at 100 / **0.20**, replacing the prior 100 / 0.25.
> **Changelog v1.1**: Open Question #1 (Raid Shield #7 re-scope) ✅ RESOLVED — user confirmed Raid Shield → Phase 2 (offense-only Raid v1 has no shield function); systems-index #7 moved to Phase 2 (number retained as stable identifier). Raid v1's "Depends On" no longer lists Raid Shield as an MVP dependency; the header re-scope FLAG is marked resolved.

> **Parent GDD**: `design/gdd/systems-index.md` — System **#6 (Raid v1 vs NPC Rival Startups, P1 — social-engine surrogate at launch)**.
> **Source of Truth**: `idea/brainrotInc.md` → "2. Raid & Defend (Social Asymmetric Conflict)"; locked pre-production context + the world backdrop (4 NPC Rival Startups; Burnout Inc. = Phase 2).
> **Governing standards (NON-NEGOTIABLE)**: `.claude/rules/design-docs.md` (9 sections, explicit formulas, ≥5 edge cases, version header), `.claude/rules/config-data.md` (commented config + ranges + version field), `.claude/rules/gameplay-systems.md` (zero magic numbers, config-driven, state machine, event-driven), `.claude/rules/server-scripts.md` (server-authoritative, never trust client, pcall, rate limit), `.claude/rules/remotes.md` (validate every handler, no C→S RemoteFunction, rate limit, delta bandwidth).

> **Depends On**:
> - **#5 Battle System** (`battle-gdd.md` v1.1) — OWNS combat resolution. Raid calls the **LOCKED signature** `BattleService.resolve(attackerTeam, defenderTeam, seed) -> { winner, timeline, survivors, casualties }` (pure, synchronous, server-only). Raid builds both teams, supplies the seed, consumes the outcome, and ships the returned `BattleTimeline` to the spectating client. Raid does **not** compute damage, turn order, or any combat math.
> - **#9 Economy** (`economy-gdd.md` v1.2) — OWNS the wallet API. Raid spends the send cost via `Economy.spend(player, raidSendCost, "raid_send", idemKey)` and awards loot via `Economy.award(player, loot, "raid_loot", idemKey)`. Economy marked `raidSendCost` (~100) and `raidLootPct` (~0.20, revised v1.2 from 0.25 per circulation analysis) as **placeholders Raid owns**; this GDD **locks** those values (§8) and reconciles the EV against Economy §8.3.
> - **#3 Idle Production** (`idle-production-gdd.md` v1.1) — OWNS the per-player factory, the pending pool, and the in-battle/away-on-raid pause behavior (idle E4). Raid coordinates the **per-`id` in-battle lock** with Idle and Personality. **Loot basis decision (locked here, §9):** for **NPC** targets the lootable pool is a **config-defined NPC pool**, NOT another player's `pendingOffline`. (Stealing a real player's uncollected pending is **PvP, Phase 2**.)
> - **#2 Personality System** (`personality-gdd.md` v1.1) — OWNS trait definitions + battle behavior tags. Both the player's attack team and the NPC defender team carry personalities; their battle effects flow through Battle's tag handlers (F4). Raid never re-implements personality math.
> - **#1 Data Persistence & Roster Core** (`persistence-gdd.md` v1.2) — OWNS the `id`-keyed roster, the `BrainrotEntry` shape, the atomic `UpdateAsync` path + `txLog` idempotency, and the counters Raid writes: per-Brainrot `history.rwon`/`history.rdef`, player `raidsWon`/`raidsDefended`. Raid reads `roster` to build the attack team; it persists only **results** via Persistence's atomic op.

> **Depended On By**:
> - **#8 Work-Based Evolution** — reads per-Brainrot `history.rwon` (raids won) milestones that Raid increments. At v1, only `rwon` is produced by NPC offense; `rdef` stays **0 until Phase 2** (no being-raided events in v1).
> - **#17 Daily Quests** — listens to Raid's `RaidWon` event for the "menang M raid" objective.
> - **#12 Moment System** — listens to Raid's `RaidResolved` / clutch-win signal for the raid-win recap (and re-uses Battle's `PersonalityMoment`).
> - **#13 UI/HUD** — owns the surfaces Raid drives (target select, team select, spectate via Battle's timeline, result/loot screen, Defense Rating display).
> - **Phase 2 (#18 PvP Raids, #19 Revenge, #7 Raid Shield)** — v1 is the de-risking runway; Phase 2 hooks are forward-looking only (§9).

> **Cross-GDD consistency lock (no contradictions introduced — per `design-docs.md`):**
> - **Raid owns target + cost + loot + flow.** Battle (#5) owns resolution; Economy (#9) owns currency; Personality (#2) owns trait values; Persistence (#1) owns storage. This GDD defines the **NPC target model, the cost/loot values + formulas, the raid state machine, and the orchestration** — and references (never redefines) the owned values of neighbors.
> - **Locked scope: OFFENSE-ONLY vs NPC.** The player **attacks** NPC Rival Startups; the player is **NOT attacked** by anyone in v1. Being-raided, defense events, Raid Shield function, raid mailbox, Revenge, PvP matchmaking, and the Burnout Inc. boss are **Phase 2** and are only referenced as forward-looking hooks (§9), never designed here.
> - **Defense Rating is display-only in v1.** A "Defense Rating" score is computed from the player's deployed roster as Phase-2 preparation and a flex/progression number — there is **no real being-raided event** behind it at launch (§2.7).
> - **`raidSendCost` (100) & `raidLootPct` (0.20) locked here (v1.2 revised from 0.25).** Economy §8.3 / Open Question #2 recommended these as placeholders Raid owns; this GDD locks them in `RaidConfig` and proves the EV is net-positive at fair skill at tier 2+ (with a tier-1 caveat — see §8.5).
> - **Compliance (locked, world-builder).** Cartoon, kid-safe terminology: combatants are "knocked out / fainted / out of office" (never die/kill); raids are an "office showdown" against rival startups; loot is "swiped Meme Coins / scooped their stash," not theft framed darkly.

> **✅ RESOLVED — RE-SCOPE (systems-index #7 Raid Shield → Phase 2):** User confirmed. Raid Shield (#7) has been **moved to Phase 2** in `systems-index.md` (paired with #18 PvP), with its system number retained as a stable identifier. The recommendation below stands as the rationale of record.
> Raid Shield (#7) was originally MVP P2, justified as "build the loop/UX now so PvP slots in cleanly." **This GDD recommended DEFERRING #7 entirely to Phase 2 — now done.** In a strictly offense-only-vs-NPC v1, **a shield protects against nothing** — there is no being-raided event, so a shield timer has no function, no trigger, and no UX surface to attach to. Building it now adds MemoryStore cross-server expiry plumbing, a config, and a GamePass surface with **zero live behavior** to exercise — it cannot be playtested because nothing it guards against can happen. It belongs with the systems it actually protects (#18 PvP Raids). **Recommendation: move #7 to Phase 2, paired with #18.** The user owns the index update; this is a flag, not a unilateral change.

---

## 1. Overview & Purpose

Raid v1 is the **social-engine surrogate** for launch. The pillar's social loop is *"send your team, watch them fight, win loot, get a story to share"* (`idea/brainrotInc.md` §2). Real PvP — raiding live player bases, being raided back, revenge — is the highest-value, highest-risk piece (matchmaking, fairness, griefing, offline-defense correctness), so it is **deferred to Phase 2 (#18)**. To still ship the *full raid feeling* at launch without that risk, **Raid v1 lets the player attack four config-defined NPC "Rival Startups"** (Grind Corp, Chill Collective, The Glitch Gang, Pivot Ventures). The player picks a rival, pays a Meme-Coins send cost, sends a team of 3 from their roster, watches the auto-battle replay (Battle #5), and on a win **scoops a slice of that rival's Meme-Coins stash** (loot). On a loss, they lose the send cost — the risk that makes a win feel earned.

It is **P1 (social-engine surrogate)** because:

1. **It is the retention/story engine, de-risked.** The shareable beat ("my Loyal one tanked their whole team and we stole 4K coins!") lands at launch using NPC targets, while matchmaking/griefing/offline-defense are kept out of the critical path. Raid v1 is the **runway** that proves the cost → battle → loot → persistence pipeline so Phase 2 PvP slots in by swapping the *target source* (NPC config → live player snapshot) without re-plumbing the loop.
2. **It exercises every dependency end-to-end.** It is the **sole caller** of Battle (#5), a major Economy (#9) sink **and** faucet, the producer of Evolution (#8) raid-win milestones, a Daily Quests (#17) objective source, and a Moment (#12) source. If the raid loop is right, the combat/economy/persistence spine is validated for real.
3. **It is where the player spends idle coins on a chance at *more* coins.** It closes the loop: idle earns → raid risks some of it → a win compounds it. This gives idle coins a *use* beyond the upgrade treadmill and a reason to build a good combat team (not just good workers).

### Why offense-only vs NPC at v1 (load-bearing scope lock)

- **PvP = matchmaking + fairness + griefing + offline-defense.** Each is a hard, risky system on its own. Shipping all four at launch (solo dev, July 2026) is the single biggest schedule/quality risk in the social layer. NPC targets remove **all four** while preserving the loop.
- **NPC targets are *content*, not live data.** A rival's defender team and lootable pool come from `RaidConfig` (tuned, fair, predictable), so balance is authored, not emergent — no "I got farmed by a whale" feel-bad, no offline-defense correctness bug class, no exploit surface around another player's state.
- **The loot is the NPC's own config pool, not a real player's pending.** The idea-doc "steal % of uncollected idle" is the **PvP Phase-2** mechanic. In v1, the lootable pool is a **config-defined NPC pool** that scales with the rival's difficulty tier and (lightly) with the player's power so the reward stays meaningful as the player grows. **No real player loses anything in v1.** (§2.5, §9.)
- **Defense exists only as a display number.** So the player understands "your base would defend like this" (a progression flex + Phase-2 teaser) without any real being-raided event.

**Player intent:** *"I've got a pile of coins and three tough guys. Let me go hit Grind Corp — pay the entry fee, send my Loyal tank, my Rebel, and my Hyper, watch them brawl, and come back richer. If I lose I'm out the fee, so I'd better bring my best."* The player thinks "pick a rival, send my best team, watch the fight, get loot." They never think about seeds, EV, or NPC pool formulas — those surface as a rival-select screen with a difficulty badge and a "loot up to X" estimate, a punchy spectate brawl (Battle's replay), and a win/loot screen.

What this GDD does **NOT** do: it does not resolve combat (Battle #5), does not mutate the wallet directly (Economy #9), does not define personality numbers (Personality #2), does not implement storage/atomicity (Persistence #1), and does not design any Phase-2 PvP/shield/revenge/mailbox/matchmaking/boss system. It owns *the NPC target model, the send-cost + loot values & formulas, the raid state machine, the validation gauntlet, the Defense Rating display formula, the spectate hand-off, and the result/persistence orchestration.*

---

## 2. Core Mechanics

### 2.1 The raid loop (end-to-end flow)

```
 1. SELECT TARGET   player opens Raid screen → sees 4 NPC Rival Startups as cards,
                    each with a difficulty tier badge, unlock state (level-gated),
                    and an estimated loot range. Picks one UNLOCKED rival.
        │
 2. SELECT TEAM     player picks EXACTLY 3 Brainrots from their roster for the attack team.
                    Each must be owned, not already deployed-and-locked-in-another-raid,
                    not currently in a battle. (Deployed-in-factory is allowed; the raid
                    PAUSES that worker — idle E4 — for the raid's duration.)
        │
 3. CONFIRM + PAY   player confirms → server runs the VALIDATION GAUNTLET (§5.2): balance
                    >= raidSendCost, team valid/owned/unlocked-tier, ids not locked, rate
                    limit. ALL pass → server SPENDS raidSendCost (Economy, idemKey) and
                    LOCKS the 3 attacker ids in-battle. Any fail → reject, NOTHING charged.
        │
 4. RESOLVE         server picks a seed, builds attackerTeam (the 3 BrainrotEntries) and
                    defenderTeam (the rival's config team), calls BattleService.resolve(...)
                    (pure, synchronous, microseconds). Gets { winner, timeline, survivors,
                    casualties }. This is AUTHORITATIVE — decided before any frame animates.
        │
 5. SPECTATE        server sends the BattleTimeline to the client; client replays the brawl
                    "live" (Battle #5 owns the replay). Player watches; may Skip to result.
        │
 6. RESULT          - WIN  (winner == "attacker"): compute loot = floor(pool * raidLootPct);
                      Economy.award(loot, "raid_loot", idemKey); write history.rwon +1 per
                      attacker Brainrot + raidsWon +1 (Persistence atomic, same idemKey);
                      emit RaidWon. Result screen shows "+loot".
                    - LOSS (winner == "defender"): no loot. The send cost (step 3) is the
                      loss. emit RaidResolved(won=false). Result screen shows "no loot,
                      better luck next time" (kind, kid-safe).
        │
 7. UNLOCK / RESET  attacker ids unlocked (paused factory workers resume); raid returns to
                    Idle state; per-target cooldown (if any, §2.6) starts. Player may raid
                    again (subject to cooldown + send cost + the EV being their choice).
```

**Authority guarantee:** the outcome is computed in step 4, **server-side, before any animation**. The spectate (step 5) is pure presentation of a decided fight (Battle's deterministic-replay guarantee). A disconnect during spectate does not change the result (already committed in step 6's atomic op) — see E5.

### 2.2 NPC TARGET model (the four Rival Startups)

An NPC Rival Startup is **content (config), not persisted player data**. Each rival entry in `RaidConfig.rivals` defines:

```
RivalStartup (config) = {
    id, name, personalityTheme, difficultyTier, unlockLevel,
    defenderTeam = { N combatant specs },     -- each: { species, personality, levelOffset }
    poolBase, poolPlayerScale,                -- the lootable Meme-Coins pool formula inputs (§2.5 / F-POOL)
    lootPct (optional per-rival override of the global raidLootPct),
    cooldownSeconds (optional per-rival),
}
```

The four launch rivals (themes locked by the world backdrop; **numeric VALUES below are placeholders in §8 — tuned during content/`/balance-check`**):

| Rival | Personality theme | Difficulty tier | Unlock level | Defender team flavor |
|---|---|---|---|---|
| **Grind Corp** | Hyper-Loyal (the over-achiever sweatshop) | 1 (easiest) | 1 | Loyal tanks + a Hyper striker; steady, fair intro fight |
| **Chill Collective** | Lazy (the do-nothings) | 2 | tier-gated (§8) | Lazy high-DEF wall; slow but tanky — teaches the player to bring damage |
| **The Glitch Gang** | Chaotic (the unpredictable) | 3 | tier-gated | Chaotic random-moveset chaos; high-variance fight, screenshot moments |
| **Pivot Ventures** | Rebel-Hyper (the disruptors) | 4 (hardest at launch) | tier-gated | Rebel counter-double + Hyper act-first; punishes a glass-cannon team |

- **Defender team = personality-flavored, level-scaled.** Each rival's `defenderTeam` is a list of combatant specs (`species`, `personality`, `levelOffset`). At resolve time, Raid builds the defender `BrainrotEntry[]` for Battle by taking each spec's `species`/`personality` and setting `level = clamp(playerPowerLevel + levelOffset, 1, maxLevel)` (F-DEF-LEVEL, §8.4). This makes the **defender scale to the player's power** so the fight stays fair-but-challenging as the player levels — a level-1 player meets a level-1-ish Grind Corp; a level-30 player meets a level-30-ish one. The **tier** sets the *baseline difficulty* (levelOffset magnitude + team composition); the player's power sets the *absolute* level.
- **Defender personalities drive real battle behavior.** Grind Corp's Loyals bodyguard; Chill Collective's Lazies wall + go berserk when last; Glitch Gang's Chaotics steal movesets; Pivot Ventures' Rebels counter for double. This is Personality (#2) flowing through Battle (#5) — Raid only supplies the team; Battle applies F4.
- **NPC defenders are NOT persisted Brainrots.** They have no `id` in the player's roster, no `history`, no DataStore footprint. Raid synthesizes ephemeral `BrainrotEntry`-shaped tables for Battle's `resolve` (Battle E7 tolerates synthesized entries; species/personality/level are all Battle needs). They never lock anything and never appear in the roster.
- **Fairness clamp.** Defender level and team size are clamped to config bounds so a tier-4 rival can never become unbeatable for a player who has unlocked it (the unlock gate already ensures the player is at a sane level). §8.4.

### 2.3 Difficulty tier gating (which rivals are available)

A rival is **selectable** only if the player meets its `unlockLevel` (a player-power gate, §2.4 defines "player power"). This:

1. **Paces the content.** Grind Corp (tier 1) is available immediately (the FTUE soft-raid intro, systems-index #14). Higher tiers unlock as the player grows, giving a progression ladder ("I can finally take on Pivot Ventures").
2. **Keeps fights fair.** Because the defender scales to player power *and* the rival is unlock-gated, the player never faces a tier they are wildly under-powered for, and never trivially farms a tier far below them for outsized loot (higher tiers have bigger pools — §2.5 — so the player is *incentivized* to climb, not farm the bottom).
3. **Is purely a UI/availability gate.** A locked rival's card shows "Unlocks at power X" and cannot be selected (server re-validates the gate, E8 — never trust a client claiming it unlocked the tier).

### 2.4 "Player power" (the scaling + gating input)

Raid needs a single scalar for (a) tier-gating and (b) scaling the defender level. **Player power** is config-defined (§8) and at v1 is the **highest deployed/roster Brainrot level** (simple, legible, and the thing the player most directly controls), optionally blended with roster size. Formula F-POWER (§8.4). It is computed server-side from the roster (Persistence) — never client-supplied. Keeping it config-driven means the exact blend can be tuned (or swapped to an average / sum) without code change.

### 2.5 Loot model (NPC pool — NOT another player's pending)

> **LOOT BASIS DECISION (LOCKED — resolves the idea-doc "steal % uncollected" ambiguity):**
> The idea doc's *"win = steal a percentage of their uncollected idle resources"* is the **PvP Phase-2** mechanic (stealing a **real player's** `pendingOffline`). **In v1 (NPC targets), the lootable pool is a CONFIG-DEFINED NPC POOL**, NOT any player's pending. **No real player loses coins in v1.** This is the single most important loot-model lock and the cleanest PvP-vs-NPC boundary.

**The NPC pool formula (F-POOL):**

```
pool(rival, player) = floor( rival.poolBase + rival.poolPlayerScale * playerPower )

loot(rival, player) = floor( pool(rival, player) * lootPct )
   where lootPct = rival.lootPct (per-rival override) or RaidConfig.raidLootPct (global default 0.20, v1.2)
```

- **`poolBase`** sets the rival's baseline stash (higher tier = bigger base). **`poolPlayerScale`** makes the pool grow lightly with player power so the reward stays meaningful as the player's send cost / opportunity cost grows — a level-30 player raiding Grind Corp gets a bigger pool than a level-1 player did, but the *fraction stolen* is the same `lootPct`. (Tuned so it never out-earns the idle faucet — Economy §8.9 inflation lock; §8.5 here.)
- **`lootPct`** (default **0.20**, locked v1.2 — down from 0.25, owned by Raid) is the fraction scooped on a **WIN**. Sized to keep raid loot a **secondary, engagement-bounded faucet** at ≤30% of idle's hourly rate at comparable upgrade level — matches the same ceiling rule applied to `field_combat_win` (Pet AI #25). Per-rival override allowed (e.g. Pivot Ventures keeps `lootPct = 0.28` as an intentional tier-3 bonus, see §8.3).
- **Loot is awarded only on a WIN**, via `Economy.award(player, loot, "raid_loot", idemKey)`. Economy bumps `coins` + `totalCoinsEarned` (so a raid win climbs the Richest-Manager leaderboard). Idempotent by the per-raid `idemKey` (a re-fired result cannot double-pay — Economy E5).
- **The NPC pool does NOT deplete persistently.** Because it is config-derived (not a stored balance), each raid recomputes `pool` from config + current player power. There is no "I drained Grind Corp dry" persisted state at v1. Optional per-target **cooldown** (§2.6) provides the "leave it worth raiding again" pacing instead of pool depletion. (Persisted pool depletion is a Phase-2 PvP concern where the pool is a *real* player's pending.)

### 2.6 Per-target cooldown (optional pacing lever)

To prevent instant re-farming of one rival and to give the four-rival roster rotation purpose, each rival may carry a `cooldownSeconds` (config, default **0 = no cooldown at launch**; provisioned for tuning). If set, after a raid (win or loss) that rival is on cooldown for the player (a server-clock timestamp; ephemeral session state or a light persisted field if cross-session cooldown is desired — **at launch, default 0 means no cooldown state is stored**). The send cost itself is the primary spam-gate; cooldown is the secondary lever flagged for `/balance-check`.

### 2.7 Defense Rating (DISPLAY ONLY — v1 has no real defense event)

> **DEFENSE RATING LOCK:** In v1 there is **no being-raided event**. "Defense Rating" is a **computed display score** derived from the player's currently-deployed roster, shown as (a) a progression flex ("my base would defend at 4,200") and (b) a Phase-2 teaser (it is the number that *will* matter when PvP ships). **It triggers nothing, gates nothing, and is never used in any battle at v1.**

**Defense Rating formula (F-DEFRATING, display-only):**

```
DefenseRating(player) = floor( Σ over deployed Brainrots d of
                               ( speciesDefenseWeight(d) * levelFactor(d.level)
                                 * personalityDefenseWeight(d.personality) ) )
   where
     speciesDefenseWeight(d)        = RaidConfig.defRating.speciesWeightBase (uniform at launch; per-species later)
     levelFactor(level)             = 1 + RaidConfig.defRating.levelWeight * (level - 1)
     personalityDefenseWeight(p)    = RaidConfig.defRating.personalityWeight[p]   (Loyal/Lazy high, others ~1.0)
```

- It rewards the *defensive* personalities (Loyal bodyguard, Lazy high-DEF) so the player intuits "these are good defenders" — **prepping the Phase-2 mental model** while being harmless at v1.
- It is **purely display**: computed server-side from the deployed roster, replicated read-only to the client for the HUD/base panel. No client trust, but also no stakes — it cannot be exploited because it does nothing.
- It updates whenever deployment changes (Raid listens to Idle's `BrainrotDeployed`/`BrainrotUndeployed`, idle §5.3, and recomputes).

### 2.8 State machine — a raid attempt

```
 [*] --> Idle : Raid screen open, no active raid

 Idle      --> Selecting  : player opens target/team selection
 Selecting --> Idle       : player cancels
 Selecting --> Resolving  : player confirms AND validation gauntlet PASSES + cost spent + ids locked
 Selecting --> Selecting  : validation FAILS (reject reason shown; nothing charged, no lock)

 Resolving --> Spectating : BattleService.resolve returned an outcome; timeline sent to client
 Resolving --> Result     : resolve errored (pcall) -> safe no-op, cost refunded, ids unlocked (E? E11-Battle)

 Spectating --> Result    : replay finished OR player tapped Skip
 Spectating --> Result    : player disconnected (result already committed server-side; jump to Result on rejoin)

 Result    --> Idle       : player closes result; ids unlocked; cooldown (if any) started
```

- Allowed transitions only. `Resolving` is **server-only and synchronous** (the whole `resolve` happens here, in microseconds); `Spectating` is **client presentation** of an already-decided fight.
- **The cost-spend + id-lock happens exactly once, on the `Selecting → Resolving` edge, atomically.** The loot-award + history-write happens exactly once, on the win path into `Result`, atomically + idempotently. There is no edge where cost is charged twice or loot awarded twice (E5, E6).
- A raid **always reaches `Result`** (win, loss, skip, disconnect, or a guarded resolve-error refund) — there is no stuck state. Battle's turn cap (battle §2.6) guarantees `resolve` itself always terminates.

### 2.9 Raid flow diagram (orchestration)

```
        ┌──────────────────────────────────────────────┐
        │  CLIENT: pick rival (unlocked) + 3 Brainrots   │
        │  fire StartRaid { targetId, teamIds[3] }       │
        └───────────────────────┬────────────────────────┘
                                 ▼
        ┌──────────────────────────────────────────────┐
        │  SERVER: VALIDATION GAUNTLET (§5.2)            │
        │  rate-limit | team size==3 | own all ids |     │
        │  ids not in-battle/locked | rival unlocked |   │
        │  balance >= raidSendCost                       │── any FAIL ──► RaidResult{ok=false,reason}
        └───────────────────────┬────────────────────────┘                (NOTHING charged, NO lock)
                       all PASS  │
                                 ▼
        ┌──────────────────────────────────────────────┐
        │  SERVER: Economy.spend(raidSendCost,"raid_send",idemKey)  (atomic)
        │  LOCK attacker ids in-battle (Idle/Personality honor it)  │
        └───────────────────────┬────────────────────────┘
                                 ▼
        ┌──────────────────────────────────────────────┐
        │  SERVER: seed = freshSeed()                    │
        │  attackerTeam = roster entries for teamIds     │
        │  defenderTeam = build from rival config (F-DEF)│
        │  pcall( BattleService.resolve(att,def,seed) )  │── error ──► refund raid_send (idemKey),
        └───────────────────────┬────────────────────────┘            unlock ids, RaidResult{ok=false,
                       outcome   │                                     reason="hiccup"} (Battle E11)
                                 ▼
        ┌──────────────────────────────────────────────┐
        │  SERVER: send RaidTimeline { battleId,header,  │
        │   events, result } to client (Battle's payload)│ ───► CLIENT spectates replay (Battle #5)
        └───────────────────────┬────────────────────────┘
                                 ▼
        ┌──────────────────────────────────────────────┐
        │  SERVER: branch on outcome.winner              │
        │  WIN(attacker): loot=floor(pool*lootPct);      │
        │    ATOMIC { Economy.award(loot,"raid_loot",ik) │
        │      ; history.rwon+1 per attacker ; raidsWon+1}│
        │    emit RaidWon                                 │
        │  LOSS(defender): no loot; emit RaidResolved     │
        │  unlock attacker ids ; start cooldown(if any)  │
        └───────────────────────┬────────────────────────┘
                                 ▼
                 RaidResult { ok=true, won, loot, survivors, casualties }
                 ───► CLIENT result/loot screen
```

---

## 3. Data Schema

Raid persists **nothing about the in-flight raid** — combat/raid state is **ephemeral** (server memory only), matching persistence-gdd v1.2 §3.2 ("in-flight battle/raid combat state — server memory only; only *results* persist"). Raid **reads** `roster` (to build the attack team) and **writes** only **results** via Persistence's atomic path. The NPC targets are **config (content), not player data**.

### 3.1 What Raid READS (owned by other systems)

| Field / source (owner) | Type | Raid's use |
|---|---|---|
| `roster[id]` → `BrainrotEntry` (Persistence #1) | map | Build the 3-Brainrot `attackerTeam` for Battle; validate ownership; compute player power + Defense Rating. |
| `roster[id].level` / `.personality` / `.species` (Persistence/Personality) | number/enum/number | Battle needs them (it derives combat stats); also feed F-POWER, F-DEF-LEVEL, F-DEFRATING. |
| `coins` (Economy #9, owned by Persistence) | number | Affordability pre-check (advisory); the authoritative check is inside `Economy.spend`. |
| `base.deployment` (Idle #3) | map | Which Brainrots are deployed (for Defense Rating + to coordinate the away-on-raid pause). |
| `RaidConfig.rivals[*]` (this GDD, config) | table | The NPC target definitions (defender team, pool formula, tier, unlock, lootPct, cooldown). |

### 3.2 What Raid WRITES (results only — via Persistence atomic path)

| Persisted field (owner: Persistence #1) | When Raid writes it | How |
|---|---|---|
| `BrainrotEntry.history.rwon` | **+1 for each attacker Brainrot on a WINNING raid** | Persistence atomic `UpdateAsync`, same op as the loot award, keyed by the per-raid `idemKey`. |
| `PlayerData.raidsWon` | **+1 on a player win** (player-level lifetime) | Same atomic op. |
| `coins` + `stats.totalCoinsEarned` | **+loot on a WIN** | `Economy.award(player, loot, "raid_loot", idemKey)` (Economy composes the atomic credit). |
| `BrainrotEntry.history.rdef` | **NOT written in v1** — stays **0** (no being-raided event). | Phase 2 (#18) only. |
| `PlayerData.raidsDefended` | **NOT written in v1** — stays **0**. | Phase 2 only. |

> **Idempotency lock:** the loot award, `history.rwon` increments, and `raidsWon` increment for a single won raid are committed **atomically and idempotently under one per-raid `idemKey`** (Persistence §2.3 `txLog`). A re-fired result (lag/retry) is a no-op returning the prior result — never double-loot, never double-counted milestones (E5/E6). The send-cost spend carries its **own** `idemKey` (a distinct key for the spend, committed on the `Selecting→Resolving` edge) so a retried StartRaid cannot double-charge (E6).

### 3.3 Ephemeral raid state (server memory only — NOT persisted)

```lua
-- One per in-flight raid attempt; lives from "Resolving" to "Result", then discarded.
type RaidSession = {
    raidId: string,            -- HttpService GUID for THIS raid attempt (the idemKey root for loot + spend)
    player: Player,
    targetId: string,          -- which RivalStartup (RaidConfig.rivals key)
    teamIds: { string },       -- the 3 attacker BrainrotEntry ids (locked in-battle)
    seed: number,              -- the seed passed to BattleService.resolve (recorded for QA/replay)
    state: string,             -- "Resolving" | "Spectating" | "Result"
    sendCostCharged: boolean,  -- true once the raid_send spend committed (guards refund-on-error)
    outcome: BattleOutcome?,   -- set after resolve: { winner, timeline, survivors, casualties }
    lootAwarded: number,       -- 0 until the win-path award commits (guards double-award)
}
```

| Ephemeral state | Why not persisted |
|---|---|
| `RaidSession` (target, team, seed, in-flight outcome) | In-flight raid/combat state; persistence §3.2 declares it server-memory only. Only the *result* (loot, `history.rwon`, `raidsWon`) persists. |
| The synthesized NPC `defenderTeam` `BrainrotEntry[]` | Built from config each raid; never stored, never a roster entry, no `id` in DataStore. |
| The per-`id` in-battle lock | Set on the `Selecting→Resolving` edge, released at `Result`; the same lock Battle/Personality/Idle honor (battle E10, personality E4, idle E4). |
| Defense Rating value | Recomputed server-side from deployment on change; replicated read-only for display. |
| Per-target cooldown (if `cooldownSeconds > 0`) | Session-level by default at launch (`cooldownSeconds = 0` → not stored). A cross-session cooldown would be a light persisted field, deferred unless tuning needs it. |

### 3.4 `RaidConfig` schema (VALUES tuned in §8; shape locked here)

The full commented config is in §8. The NPC target shape:

```lua
type RivalDefenderSpec = {
    species: number,        -- indexes BattleConfig.species (content-TBD values; Battle owns)
    personality: string,    -- "Hyper"|"Lazy"|"Chaotic"|"Loyal"|"Rebel" (drives Battle F4)
    levelOffset: number,    -- added to playerPower to set this defender's level (F-DEF-LEVEL)
}
type RivalStartup = {
    id: string, name: string, personalityTheme: string,
    difficultyTier: number, unlockLevel: number,
    defenderTeam: { RivalDefenderSpec },   -- typically 3 (BattleConfig.teamSize)
    poolBase: number, poolPlayerScale: number,
    lootPct: number?,                       -- per-rival override of RaidConfig.raidLootPct
    cooldownSeconds: number?,               -- per-rival override of RaidConfig.targetCooldownSeconds
}
```

---

## 4. Client-Server Split

| Concern | Server (authoritative) | Client (presentation only) |
|---|---|---|
| Target list + unlock state | **YES** — reads `RaidConfig`, computes player power, decides which rivals are unlocked. | Renders the 4 cards from a replicated read-only `RaidConfig` display copy; shows lock state from server. |
| Validation gauntlet (balance / team / lock / tier / rate) | **YES** — every check server-side, before any state change. | May *hint* (grey out "send" if it thinks balance is low) — never the gate. |
| Send-cost spend | **YES** — `Economy.spend` inside the atomic edge; reads `raidSendCost` from config. | Sees the deduction via `BalanceChanged`; never names an amount. |
| Seed selection | **YES** — server-chosen fresh seed; recorded. | Never. The client cannot influence the seed (anti-exploit). |
| Building both teams + calling `BattleService.resolve` | **YES** — attacker from roster, defender from config; pure synchronous resolve. | Never — client does not resolve combat (Battle authority lock). |
| The outcome (winner / loot / survivors) | **YES** — decided before any frame animates; drives all persisted writes. | Receives it; cannot alter it. |
| Loot computation + award + `history.rwon`/`raidsWon` write | **YES** — atomic, idempotent. | Sees "+loot" on the result screen. |
| Spectate replay | Provides the `BattleTimeline` (once). | **YES** — replays the brawl (Battle #5 owns this presentation). |
| Defense Rating | **YES** — computed from deployed roster server-side. | Read-only display. |
| In-battle id lock | **YES** — set/release; coordinated with Idle/Personality/Battle. | Never. |

**Authority rule (locked, per `server-scripts.md` + `remotes.md`):** the client sends only **intents** — "raid this rival with these three ids." It **never** sends a loot amount, a winner, a seed, a cost, an "I unlocked this tier" boolean, or an "I won" flag. The server runs the entire gauntlet, spends, resolves, and commits results from its **own** computation. A tampered client can mis-animate its own spectate (Battle E5) but **cannot change loot, `history`, the persisted winner, or the send cost charged.** There is **no Client→Server `RemoteFunction`** anywhere in Raid (server-hang risk).

---

## 5. RemoteEvents / Functions

All remotes registered in `ReplicatedStorage/Shared/Remotes` and documented in the remotes manifest. **No Client→Server `RemoteFunction`** (server-hang risk, per `remotes.md`). Every handler validates types + ownership, is rate-limited, and trusts no client value. Refinable by `remotes-networking-specialist`. The spectate stream itself is **Battle's** `BattleStarted`/`BattleTimeline`/`BattleResult` (battle §5.1); Raid wraps the start (`StartRaid`) and the raid-specific result (`RaidResult`).

### 5.1 Client → Server

| Remote | Type | Payload | Validation (the gauntlet, §5.2) |
|---|---|---|---|
| `StartRaid` | RemoteEvent | `{ targetId: string, teamIds: { string } }` | The full §5.2 gauntlet. On pass: spend + lock + resolve + (timeline) + result. On fail: `RaidResult{ ok=false, reason }`, **nothing charged, no lock**. |
| `RaidSkip` | RemoteEvent | `{ raidId: string }` | Optional — jump the spectate to the result. Rate-limited (≤2/sec); `raidId` must match this player's in-flight raid; **purely presentational** (outcome already decided). Mirrors Battle's `BattleSkip`. |

> **No `RaidResult` RemoteFunction.** Result delivery is a server→client **Event** (below). The client never *requests* a result synchronously (no server-hang surface).

### 5.2 Validation gauntlet (server-side, on `StartRaid` — the security spine)

Evaluated **in order**; the FIRST failure rejects with a specific `reason` and **mutates nothing** (no spend, no lock, no resolve):

1. **Rate limit** — `StartRaid` ≤ `RaidConfig.rateLimits.startRaid` per second per player (default 1/sec). Excess → `reason="rate_limited"`. (Anti-spam; also see E6 idempotency.)
2. **Payload shape** — `targetId` is a string; `teamIds` is a list of **exactly `RaidConfig.attackTeamSize` (3)** distinct strings. Bad shape → `reason="bad_request"`.
3. **Target exists + unlocked** — `targetId` ∈ `RaidConfig.rivals`; player power ≥ `rival.unlockLevel`. Else → `reason="target_locked"` (or `"no_such_target"`).
4. **Team ownership** — every id in `teamIds` is in the player's `roster`. Any not owned → `reason="not_owned"`.
5. **Team availability** — no id is currently **locked in-battle/another raid** (the shared lock). Any locked → `reason="in_battle"`. (A *deployed-in-factory* Brainrot is allowed; it will be paused — idle E4 — not rejected.)
6. **Affordability** — `Economy.canAfford(player, raidSendCost)` advisory pre-check; the **authoritative** check is the `Economy.spend` itself (which rejects atomically if balance dropped meanwhile, E1). Pre-fail → `reason="insufficient_coins"`.
7. **Cooldown** (if `cooldownSeconds > 0`) — target not on cooldown for this player. On cooldown → `reason="cooldown"`.

Only when **all** pass does the server, in order: `Economy.spend(raidSendCost,"raid_send", spendIdemKey)` → lock the 3 ids → resolve → stream timeline → commit result. The spend is the **last** gate (so a balance race is caught atomically) and the **lock is set only after the spend commits**, so a failed spend never leaves a dangling lock.

### 5.3 Server → Client

| Remote | Type | Payload | Purpose |
|---|---|---|---|
| `RaidTimeline` | RemoteEvent | `{ raidId, battleId, header, events, result }` (Battle's `BattleTimeline` payload, raid-tagged) | The spectate stream — the deterministic action log the client replays as the brawl. Sent **once** (a 3v3 is a few KB, battle §3.3). Re-uses Battle's `BattleStarted`/`BattleTimeline` contract; Raid just correlates it with `raidId`. |
| `RaidResult` | RemoteEvent | `{ raidId, ok: boolean, won: boolean?, loot: number?, survivors: {string}?, casualties: {string}?, reason: string? }` | The authoritative raid outcome for the result/loot screen. `ok=false` carries a `reason` (validation/hiccup); `ok=true` carries `won` + `loot` (0 on loss). Redundant-by-design with the timeline footer so a client that skipped/disconnected still gets the result (E5). |
| `DefenseRatingUpdate` | RemoteEvent | `{ rating: number }` | Pushes the recomputed Defense Rating when deployment changes (display only). |

> **No S→C remote ever lets the client *decide* anything.** `RaidResult` and `RaidTimeline` are read-only projections of server truth. The client cannot send back a winner, a loot value, or a "claim" — all writes already happened server-side before `RaidResult` is sent.

### 5.4 Internal server interfaces (NOT network — cross-system decoupling per `gameplay-systems.md`)

**Calls Raid MAKES:**
- `BattleService.resolve(attackerTeam, defenderTeam, seed) -> BattleOutcome` (Battle #5, LOCKED signature). Wrapped in `pcall` (Battle E11): on error → refund `raid_send` (idempotent), unlock ids, `RaidResult{ok=false, reason="hiccup"}`.
- `Economy.spend(player, raidSendCost, "raid_send", spendIdemKey)` and, on win, `Economy.award(player, loot, "raid_loot", lootIdemKey)` (Economy #9).
- Persistence atomic `UpdateAsync` (via Persistence's path) to increment `history.rwon` per attacker + `raidsWon`, **composed into the same atomic op as the loot award**, keyed by `lootIdemKey`.
- Reads `PersonalityService`/roster only indirectly — Battle derives combat stats from the `BrainrotEntry[]` Raid passes; Raid does not query personality math.

**Events Raid EMITS (Bindable/signal layer `GameEvents`):**

| Event | Payload | Fired When | Listened By |
|---|---|---|---|
| `RaidWon` | `{ player, targetId, loot, attackerIds, raidId, serverTime }` | On a committed **winning** raid (after loot + history written) | **Daily Quests #17** ("menang M raid" progress), **Moment #12** (raid-win recap), **Evolution #8** (raid-win milestone context; the persisted source is `history.rwon`), Analytics |
| `RaidResolved` | `{ player, targetId, won: boolean, loot: number, raidId, endReason, serverTime }` | On **every** resolved raid (win or loss) | Moment #12 (story beat either way), Analytics |

> Battle also emits its own `PersonalityMoment` (clutch beats: "Rebel countered!", "Loyal protected!") during the resolved fight (battle §5.3) — Moment #12 surfaces those for the spectate/recap. Raid does not re-emit them; it emits only the raid-domain outcome events above.

---

## 6. Player-Facing UI

Rendered through the shared UI/HUD framework (#13); **pure presentation** (reads replicated state, fires intents). **Mobile-first.** Cartoon, compliance-safe ("office showdown", "knocked out / out of office", "scooped their stash" — never die/kill/steal-framed-darkly).

1. **Raid hub / target-select screen.** Four **Rival Startup cards** (Grind Corp / Chill Collective / The Glitch Gang / Pivot Ventures), each with: name + themed art, a **difficulty tier badge** (1–4, color-coded), the rival's personality theme icon(s), an **estimated loot range** ("Loot: up to ~X"), and lock state. A **locked** card is dimmed with "Unlocks at power {N}". An unlocked card is tappable → opens team select. The current **send cost** ("Send: 100") is shown clearly so the cost is never a surprise.
2. **Team-select screen.** A roster list filtered to **eligible** Brainrots (owned, not in-battle/another-raid); the player picks **exactly 3**. Each shows personality badge (#2) + level so the choice is strategic (bring a Loyal tank, a Rebel, a damage dealer). Deployed-in-factory Brainrots are pickable but flagged "will pause from work during the raid" (kind heads-up, idle E4). A clear "Send Raid (−100)" confirm button; disabled until 3 are chosen.
3. **Spectate screen (Battle's replay).** Hands off to Battle's spectate arena (battle §6): the player's 3 vs the rival's defenders, HP bars draining, attack/KO animations, **personality callout banners** ("Rebel counter — double damage!", "Loyal protected the team!", "Glitch Gang stole your move!"). A **Skip ▶▶** button (fires `RaidSkip`). This is the screenshot moment — the core of the social hook.
4. **Result / loot screen.** Big cartoon **WIN / LOSS**: on win — "You raided {Rival}! Scooped **+{loot}** Meme Coins!" with the coin-burst into the HUD wallet (Economy §6), surviving vs fainted roster, and an optional "clutch moment" replay (Moment #12). On loss — kind framing: "Your team got sent home early. You're out the entry fee — bring your best next time!" (no loot; the send cost was the stake). Never punishing-toned.
5. **Validation reject toasts.** On `RaidResult{ok=false}`: a clear, kind message keyed to `reason` — `insufficient_coins` → "Not enough Meme Coins for the entry fee (need {cost})"; `in_battle` → "One of those Brainrots is busy in a fight"; `target_locked` → "You're not strong enough for {Rival} yet (power {N})"; `cooldown` → "{Rival} needs a breather — try again soon"; `rate_limited`/`hiccup` → "Hold on a sec — try again." Always actionable, never a dead end.
6. **Defense Rating display.** A "Your Base Defense: {rating}" stat on the Raid hub / base panel, with a small Phase-2 teaser tooltip ("This is how well your deployed team would defend — defense raids coming soon!"). Updates on deployment change (`DefenseRatingUpdate`). It is a flex number, clearly informational.
7. **Connection-safe.** Disconnect mid-spectate → the raid was already resolved + committed server-side; on rejoin the player sees the **result** (loot is already in their wallet if they won), never a re-fight (E5).

All surfaces are driven by replicated state + one timeline payload + one result — **no per-frame networking**, safe on low-end mobile.

---

## 7. Edge Cases & Error States

Covers the `design-docs.md` checklist (zero/max/negative/rapid/lag/disconnect/datastore-down/concurrent). **Minimum 5 exceeded.** Each: trigger → defined behavior.

### E1 — Insufficient balance for the send cost (rejected BEFORE resolve)
**Trigger:** player confirms a raid with `coins < raidSendCost` (or a concurrent spend drained the balance after the advisory pre-check).
**Behavior:** the gauntlet's advisory pre-check (`canAfford`) catches the common case → `RaidResult{ok=false, reason="insufficient_coins"}`. If balance dropped between pre-check and the atomic `Economy.spend`, the **spend itself rejects atomically** (Economy E1/E3) → the raid is aborted **before** any lock or resolve, nothing is charged, no ids locked. The player keeps everything; a kind "Not enough Meme Coins" toast nudges them to collect/earn. No partial state.

### E2 — Team size ≠ 3, or a team member is in-battle / another raid / invalid
**Trigger:** `teamIds` has < 3 or > 3 ids, duplicate ids, an id the player doesn't own, an id with a malformed roster entry, or an id currently **locked in-battle/another raid**.
**Behavior:** gauntlet steps 2/4/5 reject **before** any spend/lock: wrong count/duplicate → `bad_request`; not owned → `not_owned`; locked → `in_battle`. **A deployed-in-factory Brainrot is NOT rejected** — it is allowed and will be **paused (produces 0) for the raid duration** (idle E4), resuming on `Result`. A malformed `BrainrotEntry` that slips through to `resolve` is defended in Battle E7 (repair/clamp); but the gauntlet's ownership check is the primary guard. Nothing charged on any rejection.

### E3 — All attacker Brainrots knocked out but the team still WINS (Battle tie-break / HP%)
**Trigger:** Battle resolves with `winner == "attacker"` even though some/all attackers are in `casualties` (e.g. a turn-cap HP% tie-break, battle §2.6 F6, or a trade that empties the defender first).
**Behavior:** **Raid trusts Battle's `winner`, full stop.** Raid does **not** re-derive win/loss from survivor counts — `winner == "attacker"` ⇒ the player **WINS** and **gets loot**, regardless of how many attackers fainted (fainting in a raid is ephemeral — combatant KO is in-battle only, battle §2.9; the roster Brainrots are not lost or harmed). `history.rwon` is incremented for **all 3 attackers** (they were on the winning team), per the Battle→Persistence contract (battle §3.4). The result screen shows the win + loot and the fainted roster (cosmetic — "they fought hard!"). Symmetrically, a defender-win (even a tie-break defender-win) is a **loss** with no loot. This honors Battle's tie-break authority and avoids a contradictory double-source-of-truth for "who won."

### E4 — Player disconnects mid-spectate (or before the replay starts)
**Trigger:** the player drops connection during the spectate replay, or right after `StartRaid` but before the timeline arrives.
**Behavior:** the raid was **fully resolved AND its result committed (loot awarded, `history.rwon`/`raidsWon` written, ids unlocked) server-side before the spectate is mere presentation** — the outcome does not depend on the client being present (Battle's resolve-before-animate guarantee + Raid's commit on the win path). On rejoin: the player is **not** shown a re-fight; if they won, the loot is already in their wallet (persisted) and a recap/Moment may surface; if they lost, the send cost was already the stake. The spectate is skippable-to-result by design, so a reconnecting client effectively jumps to `RaidResult`. **No coins lost beyond the (already-charged) send cost, no loot lost, no double-resolve.**

### E5 — Spammed `StartRaid` / retried after lag (no double-charge, no double-loot)
**Trigger:** the player taps "Send Raid" rapidly, or a laggy `StartRaid` is re-fired by the client, or the network re-delivers it.
**Behavior:** three layers: (1) **rate limit** (gauntlet step 1, ≤1/sec) drops the obvious spam → `rate_limited`. (2) **The in-battle lock**: once a raid's 3 ids are locked, a second `StartRaid` reusing any of them fails the availability check (`in_battle`) — you cannot send the same team twice concurrently (Battle E10). (3) **Idempotency keys**: the send-cost spend carries `spendIdemKey` and the loot award + history writes carry `lootIdemKey` (per-raid, derived from `raidId`); a re-fired commit is a `txLog` no-op returning the prior result (Economy E5, Persistence §2.3). **Net:** a given raid charges its cost **exactly once** and awards its loot **exactly once**, no matter how many times the remote fires. No double-charge, no double-loot, no double-milestone.

### E6 — `BattleService.resolve` errors mid-simulation (resolve hiccup)
**Trigger:** an unexpected runtime error inside `resolve` (should be impossible given Battle's validation, but defense-in-depth — Battle E11).
**Behavior:** Raid wraps `resolve` in `pcall`. On failure: **no outcome is committed** (no loot, no `history` write — the win-path atomic op is never reached); the already-charged `raid_send` is **refunded** via an idempotent `Economy.award(player, raidSendCost, "raid_send_refund", refundIdemKey)` (or an idempotent reversal — the refund carries its own key so it cannot double-refund); the in-battle **lock is released** (so the Brainrots aren't stuck); the raid is a **safe no-op** → `RaidResult{ok=false, reason="hiccup"}` ("Hold on — try again"). No partial state, no stuck lock, no lost currency. Determinism makes the error reproducible from the logged `seed` for QA.

### E7 — NPC pool is 0 / loot computes to 0 (degenerate config)
**Trigger:** a rival's `poolBase = 0` and `poolPlayerScale = 0` (mis-tuned), or `lootPct` rounds the loot to 0 (`floor(pool * lootPct) == 0` for a tiny pool).
**Behavior:** a **boot-time validator** (`RaidConfig.validate()`, per `gameplay-systems.md`) clamps `poolBase ≥ 0`, `poolPlayerScale ≥ 0`, and `lootPct ∈ [0, lootPctMax]`, and **warns loudly** if any rival's *minimum* loot (at the unlock-level player power) is `< RaidConfig.minLootWarn` (default 1) so QA catches a worthless rival before players do. At runtime, `loot = floor(...)` is **never negative** and a 0-loot win is handled gracefully: the player still **wins** (history.rwon/raidsWon still increment — the *fight* was won), but the loot screen shows "+0 Meme Coins" honestly (no crash, no negative award; `Economy.award(0,...)` is a clean no-op credit). This makes a mis-tuned rival visibly bad (so it gets fixed), not exploitable or crash-prone.

### E8 — Target tier locked / client claims it unlocked a tier it hasn't
**Trigger:** the player selects a rival they have not unlocked (`playerPower < unlockLevel`), or a tampered client sends `StartRaid` for a locked `targetId` claiming it is unlocked.
**Behavior:** the server **re-computes player power from the roster** (F-POWER, never trusts a client-supplied power or unlock claim) and re-checks the gate in gauntlet step 3 → `reason="target_locked"` if not met. The client cannot bypass the gate by lying — the gate is purely server-side. UI shows "Unlocks at power {N}". Nothing charged.

### E9 — Many players raid simultaneously (scale)
**Trigger:** a full server, many `StartRaid` near-simultaneously.
**Behavior:** each raid is **per-player, independent**. `BattleService.resolve` is a pure, synchronous, in-memory function with no shared mutable global state (Battle E9) — a 3v3 resolves in microseconds. Economy/Persistence writes route through the **per-profile atomic path** (serialized per player, no cross-player contention — Persistence E9). The only shared resources are the per-`id` lock (per-player ids, no global lock) and the one-time timeline send (a few KB per raid). Scales linearly; no per-frame work; no DataStore call inside the sim.

### E10 — DataStore unavailable at the loot-commit (win path)
**Trigger:** the underlying `UpdateAsync` fails (DataStore down) when committing loot + `history.rwon` + `raidsWon` on a winning raid.
**Behavior:** the commit is `pcall`-wrapped by Persistence/Economy; on failure **nothing mutates** (no loot, no history, no raidsWon) and the op returns `false`. Raid surfaces a gentle "Hiccup — your loot didn't save, try the raid again!" and treats the raid as **not-committed** (the send cost: because the spend committed earlier, on a *persistent* commit failure of the loot the fair behavior is to **refund the send cost** via the idempotent refund path, mirroring E6, so the player is made whole and can retry). The dirty-flag retry discipline re-attempts the save of already-committed state; a commit that never ran simply did not happen. No partial state, no phantom loot, no lost net coins.

### E11 — Reroll/deploy race on a locked attacker (lock contention)
**Trigger:** while a raid is in `Resolving`/`Spectating` (ids locked), the player (or another path) tries to reroll a personality (#11/#2) or deploy/undeploy (#3) one of the locked attacker ids.
**Behavior:** the **in-battle lock is the single source of truth**, honored identically by all three systems: Personality reroll is rejected with `"in_battle"` (personality E4), Idle deploy/undeploy is rejected/paused with `"in_battle"` (idle E4), and a second raid using the id is rejected (E5). The Brainrot's stats/behavior therefore **cannot change mid-raid** (preserving Battle's determinism) and it can never be in two raids at once. The lock releases at `Result`; queued operations may then proceed. No desync, no stuck lock (released even on the guarded error path, E6).

---

## 8. Balancing Parameters

> **This is the core of the GDD.** All values live in `RaidConfig` (commented, ranged, versioned per `config-data.md`). **Zero magic numbers in code.** Values owned elsewhere are **referenced, never redefined contradictorily**: personality multipliers come from `PersonalityConfig` (#2); species base stats + combat math from `BattleConfig` (#5); the wallet from `EconomyConfig` (#9, which marked `raidSendCost`/`raidLootPct` as **Raid-owned placeholders** — **locked here**). NPC defender team composition + tier difficulty + pool magnitudes are **content tuned via `/balance-check`** — this GDD locks the **schema + the cost/loot/EV math** and ships documented placeholders.
>
> **Assumptions flagged for `/balance-check`** are marked **⚠VALIDATE**.

### 8.1 `RaidConfig` (master table — schema + locked values + placeholder content)

```lua
-- src/ReplicatedStorage/Shared/Config/RaidConfig.lua
-- Raid v1 (vs NPC Rival Startups). Display fields are SAFE to replicate read-only so the
-- rival cards render; the SERVER re-reads authoritative values (cost, unlock, pool) at raid time
-- (client never trusts cost/loot/unlock — §4/E8). Edited by designers/content for balance.
-- Schema version: 1
return {
    version = 1,

    -- ── TEAM ──
    -- Attacker team size the player sends. Locked to Battle's teamSize (3). Range 1..6 | Default 3.
    attackTeamSize = 3,

    -- ── COST (LOCKED here; Economy §8.3 marked this a Raid-owned placeholder) ──
    -- Meme Coins to send one raid team (per attempt). The stake that makes a win earned and
    -- gates spam. Spent via Economy.spend(...,"raid_send",idemKey) on the Selecting->Resolving edge.
    -- Range: 0..100000 | Default: 100  (LOCKED — reconciled with Economy.raidSendCostCoins=100)
    raidSendCost = 100,

    -- ── LOOT (LOCKED here; Economy §8.3 marked this a Raid-owned placeholder) ──
    -- Global fraction of the NPC pool scooped on a WIN. Per-rival lootPct may override.
    -- A meaningful-but-not-total steal so the rival is worth raiding again.
    -- Range: 0.10..0.40 | Default: 0.20  (LOCKED v1.2 — revised from 0.25 per circulation analysis)
    raidLootPct = 0.20,
    -- Hard cap on lootPct after any per-rival override (validator clamp; anti-misconfig).
    -- Range: 0.25..0.75 | Default: 0.50
    lootPctMax = 0.50,
    -- Warn at boot if a rival's MIN loot (at its unlock-level player power) is below this (E7).
    -- Range: 0..1000 | Default: 1
    minLootWarn = 1,

    -- ── PLAYER POWER (F-POWER): the scaling + tier-gating scalar ──
    powerModel = {
        -- "highest_level" (default, v1) | "avg_level" | "sum_level" (tunable, no code change).
        mode = "highest_level",
        -- Optional small additive bonus per owned Brainrot (rewards roster growth). Default 0 at v1.
        -- Range: 0..1 | Default: 0
        rosterSizeWeight = 0,
        -- Player power is clamped to this for sane defender scaling. Range: 1..200 | Default: 60
        maxPower = 60,
    },

    -- ── DEFENDER SCALING (F-DEF-LEVEL): keep NPC fights fair as the player grows ──
    -- Defender level = clamp(playerPower + spec.levelOffset, defenderLevelMin, defenderLevelMax).
    defenderLevelMin = 1,    -- Range: 1..50  | Default: 1
    defenderLevelMax = 50,   -- Range: 1..200 | Default: 50  (⚠VALIDATE vs BattleConfig maxLevel)

    -- ── PER-TARGET COOLDOWN (secondary pacing lever; send cost is the primary gate) ──
    -- Global default; per-rival may override. 0 = NO cooldown at launch (no cooldown state stored).
    -- Range: 0..86400 | Default: 0  (⚠VALIDATE — turn on only if farming one rival is a problem)
    targetCooldownSeconds = 0,

    -- ── RATE LIMITS (server-enforced, per server-scripts.md / remotes.md) ──
    rateLimits = {
        startRaid = 1,   -- StartRaid: max 1/sec per player
        raidSkip  = 2,   -- RaidSkip:  max 2/sec
    },

    -- ── DEFENSE RATING (display-only, F-DEFRATING; v1 has NO real defense event, §2.7) ──
    defRating = {
        -- Base per-Brainrot defensive weight (uniform at launch; per-species later).
        -- Range: 1..1000 | Default: 50
        speciesWeightBase = 50,
        -- Added weight per level above 1 (levelFactor = 1 + levelWeight*(level-1)).
        -- Range: 0..1 | Default: 0.10
        levelWeight = 0.10,
        -- Per-personality defensive weight (Loyal/Lazy reward defense; others ~1.0). DISPLAY math only.
        -- Range each: 0.5..3.0
        personalityWeight = {
            Loyal = 1.50, Lazy = 1.40, Hyper = 1.00, Chaotic = 1.00, Rebel = 1.10,
        },
    },

    -- ── NPC RIVAL STARTUPS (CONTENT — themes locked by world backdrop; NUMBERS placeholder/⚠VALIDATE) ──
    -- defenderTeam species index BattleConfig.species (content-TBD); personality drives Battle F4.
    -- pool(rival,player) = floor(poolBase + poolPlayerScale * playerPower);  loot = floor(pool * lootPct).
    rivals = {
        grind_corp = {
            id = "grind_corp", name = "Grind Corp", personalityTheme = "Hyper-Loyal",
            difficultyTier = 1, unlockLevel = 1,                       -- available immediately (FTUE intro)
            defenderTeam = {                                            -- ⚠VALIDATE species ids when content lands
                { species = 1, personality = "Loyal", levelOffset = -1 },
                { species = 1, personality = "Loyal", levelOffset =  0 },
                { species = 1, personality = "Hyper", levelOffset =  0 },
            },
            poolBase = 600, poolPlayerScale = 40,                       -- ⚠VALIDATE (EV math §8.5)
            -- lootPct omitted -> uses global 0.20 (v1.2)
        },
        chill_collective = {
            id = "chill_collective", name = "Chill Collective", personalityTheme = "Lazy",
            difficultyTier = 2, unlockLevel = 8,                        -- ⚠VALIDATE gate
            defenderTeam = {
                { species = 1, personality = "Lazy", levelOffset = 0 },
                { species = 1, personality = "Lazy", levelOffset = 1 },
                { species = 1, personality = "Loyal", levelOffset = 0 },
            },
            poolBase = 1200, poolPlayerScale = 60,
        },
        glitch_gang = {
            id = "glitch_gang", name = "The Glitch Gang", personalityTheme = "Chaotic",
            difficultyTier = 3, unlockLevel = 18,
            defenderTeam = {
                { species = 1, personality = "Chaotic", levelOffset = 0 },
                { species = 1, personality = "Chaotic", levelOffset = 1 },
                { species = 1, personality = "Rebel",   levelOffset = 0 },
            },
            poolBase = 2200, poolPlayerScale = 90,
        },
        pivot_ventures = {
            id = "pivot_ventures", name = "Pivot Ventures", personalityTheme = "Rebel-Hyper",
            difficultyTier = 4, unlockLevel = 30,
            defenderTeam = {
                { species = 1, personality = "Rebel", levelOffset = 1 },
                { species = 1, personality = "Hyper", levelOffset = 1 },
                { species = 1, personality = "Rebel", levelOffset = 0 },
            },
            poolBase = 3600, poolPlayerScale = 130,
            lootPct = 0.28,                                             -- hardest rival pays slightly more
        },
        -- Burnout Inc. (boss) = Phase 2 (#18). NOT defined here.
    },
}
```

### 8.2 Formulas (explicit, named variables)

**F-POWER — player power (scaling + gating input).**
```
playerPower(player) =
   if powerModel.mode == "highest_level":  max over roster of entry.level
   elif "avg_level":                       round( mean over roster of entry.level )
   elif "sum_level":                        Σ entry.level
   then  + powerModel.rosterSizeWeight * rosterCount
   clamped to [1, powerModel.maxPower]
  Where: roster from Persistence (#1); computed SERVER-side (never client-supplied, E8).
  Bounds: >= 1 (a new player with one level-1 Brainrot has power 1).
```

**F-DEF-LEVEL — NPC defender level (fairness scaling).**
```
defenderLevel(spec, player) = clamp( playerPower(player) + spec.levelOffset,
                                     defenderLevelMin, defenderLevelMax )
  Each rival defender spec gets this level; species + personality come from the spec.
  Effect: a level-L player meets a ~level-L rival (tier sets levelOffset spread + composition).
```

**F-POOL — NPC lootable pool + loot (NPC config, NOT a player's pending).**
```
pool(rival, player) = floor( rival.poolBase + rival.poolPlayerScale * playerPower(player) )
lootPct(rival)      = clamp( rival.lootPct or RaidConfig.raidLootPct, 0, lootPctMax )
loot(rival, player) = floor( pool(rival, player) * lootPct(rival) )
  On WIN:  Economy.award(player, loot, "raid_loot", lootIdemKey)   -- idempotent
  On LOSS: 0   (and raidSendCost was already spent — the stake)
  Bounds: loot >= 0 always (floor of a non-negative product); a 0-loot win is graceful (E7).
```

**F-DEFRATING — Defense Rating (DISPLAY ONLY).**
```
DefenseRating(player) = floor( Σ over deployed Brainrots d of
   defRating.speciesWeightBase
   * (1 + defRating.levelWeight * (d.level - 1))
   * defRating.personalityWeight[d.personality] )
  Computed server-side from base.deployment (Idle #3); replicated read-only.
  Triggers nothing, gates nothing, used in no battle at v1. Phase-2 teaser + progression flex.
```

### 8.3 Worked loot examples (placeholder content; reconcile via `/balance-check`)

Using the §8.1 placeholders and `raidLootPct = 0.20` (v1.2; Pivot keeps its 0.28 override as an intentional tier-3 bonus):

| Rival | unlockLevel | example playerPower | pool = poolBase + scale·power | loot = floor(pool·lootPct) |
|---|---|---|---|---|
| Grind Corp | 1 | 1 (new player) | 600 + 40·1 = 640 | floor(640·0.20) = **128** |
| Grind Corp | 1 | 10 | 600 + 40·10 = 1,000 | **200** |
| Chill Collective | 8 | 8 | 1,200 + 60·8 = 1,680 | **336** |
| Glitch Gang | 18 | 18 | 2,200 + 90·18 = 3,820 | **764** |
| Pivot Ventures | 30 | 30 | 3,600 + 130·30 = 7,500 | floor(7,500·0.28) = **2,100** |

The loot climbs with both rival tier and player power, always staying a single-raid reward (low hundreds → low thousands), bounded **well below** a typical idle-collect haul late-game (so raids *pace/compound*, never *replace*, idle as the primary faucet — Economy §8.9). The v1.2 lowering from 0.25 → 0.20 keeps tier-3 raid (Pivot 2,100 loot) below ~25K/hour at 5-min cooldown — the locked "engagement faucet ≤30% of idle" ceiling.

### 8.4 Reconciliation with Battle, Personality, Economy, Idle

- **Battle (#5):** `attackTeamSize = 3 == BattleConfig.teamSize`. Defender team size matches per-rival `defenderTeam` length (typically 3). `defenderLevelMax` must be ≤ `BattleConfig` max level (⚠VALIDATE when Battle's level table lands). Raid passes synthesized `BrainrotEntry`-shaped defenders; Battle E7 tolerates them. **Raid defines no combat math** — all damage/turn/personality-tag math is Battle's.
- **Personality (#2):** rival defender `personality` values are read by Battle's F4 tag handlers (Loyal bodyguard, Lazy berserk, Chaotic random-moveset, Rebel counter, Hyper act-first/mistarget). Raid hardcodes no personality numbers; the rival *themes* are just which personalities populate `defenderTeam`.
- **Economy (#9):** `raidSendCost = 100` reconciles with `EconomyConfig.raidSendCostCoins = 100`; `raidLootPct = 0.20` (v1.2) reconciles with Economy §8.3's revised recommendation 0.20 (post circulation-analysis lock). **Raid is the authoritative owner of both** (Economy referenced them as Raid-owned placeholders — Economy Open Question #2 is hereby answered: **accepted, locked at 100 / 0.20**, replacing the prior 100 / 0.25). Loot flows through `Economy.award(...,"raid_loot",idemKey)`; cost through `Economy.spend(...,"raid_send",idemKey)`; both bump/respect the wallet per Economy's atomic+idempotent path.
- **Idle (#3):** loot basis is the **NPC config pool (F-POOL)**, explicitly **not** a player's `pendingOffline` (that is Phase-2 PvP). A deployed-in-factory Brainrot sent on a raid is **paused (produces 0)** for the raid duration via the shared lock (idle E4), then resumes — never double-counted as both producing and fighting.

### 8.5 Expected Value (EV) reconciliation — net-positive but not a coin printer

> **Requested analysis.** The locked design intent: a fair-skill raid is **net-positive** (worth doing) but **not** a free coin machine (so it complements, not replaces, idle). EV per raid attempt (Economy §8.3 F-FAUCET-RAID):

```
EV(raid) = winRate * loot - raidSendCost
         = winRate * floor(pool * lootPct) - raidSendCost
```

**Worked (Grind Corp, ABSOLUTE NEW player power-1, loot = 128, cost = 100):**
- Break-even win rate: `winRate_be = raidSendCost / loot = 100 / 128 ≈ 78.1%`.
- At a **fair-skill 75% win rate**: `EV = 0.75·128 - 100 = -4` per raid — **slightly NEGATIVE** at the absolute starting power. v1.2 surfaces this as a **deliberate tradeoff** (vs prior 0.25 = +20 EV): the lower loot pct prevents tier-3 raid from becoming a coin printer, but at the cost of making absolute-tier-1 raids unprofitable for raw beginners until they reach power-10. **Mitigation options (Open Question #5)**: (a) ship as-is with a "first raid free" Daily Quest offset, (b) bump Grind Corp `poolBase` 600→700 (loot at power-1 = floor(740·0.20) = 148, break-even = 67.6%, EV at 75% = +11), or (c) add per-rival override `Grind Corp.lootPct = 0.25` to preserve tier-1 break-even at 62.5%. Decision deferred to playtest.

**Worked (Grind Corp, PROGRESSED player power-10, loot = 200, cost = 100):**
- Break-even win rate: `100 / 200 = 50%`. At fair-skill 75%: `EV = 0.75·200 - 100 = +50` per raid. Tier-1 becomes clearly profitable once player power crosses ~5–7, restoring the intended "win a fair fight → net positive" feeling.

**Worked (Pivot Ventures, power-30 player, loot = 2,100, cost = 100):**
- Break-even win rate: `100 / 2,100 ≈ 4.8%` — at high tiers the loot dwarfs the flat cost, so the constraint becomes **can you win the hard fight**, not the entry fee. This is intended: the send cost is a **spam gate + a beginner risk**, and the *difficulty of the fight* is the real gate at high tiers (you bring a strong, well-composed team or you lose). At 5-min cooldown ≈ 25K/hour ≈ ~30% of idle hourly at comparable upgrade level — exactly the "engagement faucet ceiling" Economy §8.9 targets.

**Why this is net-positive (at appropriate progression) but not a printer:**
1. **Flat cost vs scaling loot** means absolute-new raids are a *gamble* (v1.2 makes tier-1-at-power-1 explicitly risky), teaching the player to build a good team — and late raids are gated by **fight difficulty**, not the trivial fee.
2. **Loot stays a single-raid reward** (low hundreds → low thousands, §8.3), bounded at ~30% of idle hourly at comparable progression (Economy §8.9) — so the *primary* faucet stays idle; raids are the **secondary, skill-gated, risk-bearing** faucet.
3. **No persisted pool depletion at v1** but loot does not scale with *repetition* (it scales with player power + tier), so spamming one rival yields a steady-but-bounded trickle gated by the send cost and (optionally) cooldown — never an exponential exploit.
4. **v1.2 ceiling proof:** tier-3 Pivot at 0.28 override × 7,500 pool = 2,100 loot/raid. At 5-min cooldown that's 25,200/hour. Idle's hourly at factory n=10 + 7 workers ≈ 40K/hour (idle-gdd §8.3). Raid is ~63% of idle at THIS specific snapshot — slightly above the 30% target, indicating that Pivot's 0.28 override may need to drop to ~0.22-0.24 in a future tuning pass. Flagged in Open Question #5 for the same playtest cycle.
4. **Tunable levers, no code change:** `raidSendCost` (raise to make raids riskier), `raidLootPct` / per-rival `lootPct` (lower to reduce reward), `poolBase`/`poolPlayerScale` (shape the curve), `targetCooldownSeconds` (throttle farming). All flagged for `/balance-check` against Idle #3's real rates.

**⚠VALIDATE assumptions for `/balance-check`:** (a) the placeholder pool magnitudes vs Idle #3's real coin/sec; (b) the assumed ~75% fair-skill win rate vs tier-1 (depends on Battle's stat curve + personality balance — re-run fixed seeds); (c) that a full session of raiding cannot out-earn a session of idle+upgrade play; (d) `unlockLevel` gates vs the real leveling curve.

### 8.6 Acceptance-relevant invariants (no magic numbers)

- `attackTeamSize`, `raidSendCost`, `raidLootPct`, every pool/tier/unlock/defender number, and every Defense-Rating weight is read from `RaidConfig` — a grep of Raid code finds **zero** hardcoded raid numbers.
- All combat math is read from `BattleConfig`/`PersonalityConfig` via Battle — Raid adds none.
- `RaidConfig.validate()` runs at boot: clamps `lootPct ∈ [0, lootPctMax]`, `poolBase/poolPlayerScale ≥ 0`, `defenderLevel*` sane, `attackTeamSize == BattleConfig.teamSize`; warns on a worthless rival (E7) and a too-high unlock gate.

---

## 9. Integration Points

Raid is the orchestrator that ties combat + currency + persistence into the social-surrogate loop. **Reads** = Raid consumes; **Writes** = Raid causes a persisted change via the owner's API.

| System | Direction | Interaction |
|---|---|---|
| **#5 Battle System** | Raid → it (sole caller) | Calls the LOCKED `BattleService.resolve(attackerTeam, defenderTeam, seed) -> {winner, timeline, survivors, casualties}` (pure, synchronous, `pcall`-wrapped, E6). Raid builds both teams (attacker from roster, defender from `RaidConfig`), supplies the seed, **trusts `winner` absolutely** (E3), and ships the returned `BattleTimeline` to the client for spectate (re-using Battle's `BattleStarted`/`BattleTimeline`/`BattleResult`, tagged with `raidId`). Raid sets/releases the per-`id` in-battle lock around `resolve`. **Battle owns ALL combat resolution; Raid owns target/cost/loot/flow.** |
| **#9 Economy** | both (SINK + FAUCET) | SINK: `Economy.spend(player, raidSendCost(100), "raid_send", spendIdemKey)` on the Selecting→Resolving edge (atomic, idempotent). FAUCET: on win, `Economy.award(player, loot, "raid_loot", lootIdemKey)` where `loot = floor(pool * lootPct)` (F-POOL). **Raid OWNS `raidSendCost` (100) & `raidLootPct` (0.20, v1.2)** — locked here, answering Economy Open Question #2 (accepted with v1.2 revision from 0.25 → 0.20). On a guarded error (E6/E10), an idempotent `raid_send` refund makes the player whole. |
| **#3 Idle Production** | Raid ↔ it | **Loot basis lock:** for NPC targets the lootable pool is the **NPC config pool (F-POOL)**, **NOT** any player's `pendingOffline` — stealing real pending is **Phase-2 PvP**. A deployed Brainrot sent on a raid is **paused (produces 0)** for the raid via the shared in-battle lock (idle E4), resuming on `Result`. Raid reads `base.deployment` for Defense Rating + listens to `BrainrotDeployed`/`BrainrotUndeployed` (idle §5.3) to recompute it. |
| **#2 Personality** | Raid → it (via Battle) | Both teams carry personalities; their battle effects flow through Battle's F4 tag handlers (Loyal/Lazy/Chaotic/Loyal/Rebel). Rival *themes* (Grind Corp = Hyper-Loyal, etc.) are just which personalities populate `defenderTeam`. Raid re-implements no personality math; honors the in-battle reroll lock (personality E4 / E11 here). |
| **#1 Data Persistence** | Raid → it | Reads `roster` (build attack team, F-POWER, F-DEFRATING). Writes **results only**, atomically + idempotently (one per-raid `idemKey`): per-attacker `history.rwon +1` and player `raidsWon +1` on a win (persistence §9 #6 row), composed into the same op as the loot credit. **`history.rdef`/`raidsDefended` are NOT written in v1 (stay 0 — no being-raided event).** No in-flight raid state persists. |
| **#8 Work-Based Evolution** | it → Raid (via Persistence) | Reads per-Brainrot `history.rwon` (raids won) as a milestone source (e.g. Rebel → Revolutionary at N raids won — the idea-doc "survives 5 raids" becomes "won N raids" at v1 since there is no survive-a-defense event yet). **At v1 only `rwon` is produced; `rdef` = 0 until Phase 2**, so any defense-survival evolution branch is dormant/forward-compat until #18 ships. Raid emits `RaidWon` for milestone *context*; the persisted truth is `history.rwon`. |
| **#17 Daily Quests** | it → Raid | Listens to Raid's **`RaidWon`** event for the **"menang M raid"** objective (systems-index #17; Economy `quest_daily` faucet `win_raids` range 150–300, Economy §8.2). Event-driven (not polling). |
| **#12 Moment System** | it → Raid | Listens to **`RaidResolved`** (story beat win or loss) + **`RaidWon`** (clutch-win recap) and re-uses Battle's `PersonalityMoment` (clutch battle beats during spectate). Raid emits the raid-domain outcome events; Battle emits the in-fight personality moments; Moment surfaces one at a time. |
| **#13 UI/HUD** | Raid ↔ it | Drives the target-select (4 cards + tier + loot estimate + lock), team-select (3 from roster), spectate (Battle's replay), result/loot screen, validation toasts, and the Defense Rating display. Reads replicated `RaidConfig` display fields + `DefenseRatingUpdate`; fires `StartRaid`/`RaidSkip`. Pure presentation. |
| **#14 Onboarding/FTUE** | it → Raid | The FTUE "soft raid intro" (systems-index #14) uses **Grind Corp** (tier 1, unlockLevel 1) as the guided first raid — available immediately so the social hook is taught in session one. |

### Phase 2 forward-looking hooks (NOT designed here — referenced for clean slot-in)

| Phase-2 system | How v1 Raid is the runway (forward-looking only) |
|---|---|
| **#18 PvP Raids (+ Burnout Inc. boss)** | Swap the **target source**: NPC `RaidConfig.rivals` → a live player snapshot (MemoryStore matchmaking pool); the loop (cost → resolve → spectate → loot → persist) is unchanged. **Loot basis flips** from the NPC config pool to the target's **real `pendingOffline`** (the idea-doc "steal % uncollected"). Burnout Inc. is a boss-tier target added to the same target model. |
| **#7 Raid Shield** | **✅ RESOLVED — deferred to Phase 2** with #18 (user-confirmed; systems-index #7 moved to Phase 2, number retained). A shield protects against nothing in offense-only v1, so it has no MVP function. When PvP ships, the gauntlet gains a "target not shielded" check (MemoryStore-authoritative expiry). |
| **#19 Revenge System** | When a player is raided (Phase 2), set `revengeTarget`/`revengeUntil` (persistence fields already provisioned) → a 2x-reward counter-raid quest. v1 writes neither (no being-raided event). |
| **Being-raided / defense events** | v1's **Defense Rating** (display-only) is the mental-model teaser; Phase 2 turns it into a real defending team in the same `resolve` call (the player's deployed roster becomes a `defenderTeam`), writing `history.rdef`/`raidsDefended` (currently always 0). |
| **Raid mailbox / matchmaking** | MemoryStore plumbing (persistence provisions it) for offline-target results + the matchmaking pool — none needed at v1 (NPC targets are config, always "available," never offline). |

### Resolution notes (no contradictions)
- **Loot basis** is explicitly the NPC config pool at v1 (not a player's pending) — the idea-doc "steal % uncollected" is correctly scoped to Phase-2 PvP. No contradiction with `idea/brainrotInc.md`; the v1 surrogate is documented as such.
- **`raidSendCost`/`raidLootPct`** are locked here at 100 / **0.20** (v1.2, revised from 0.25), the values Economy recommended after circulation analysis — Economy Open Question #2 resolved with the v1.2 revision, no divergence.
- **Battle's `winner` is the single source of truth** for win/loss (E3); Raid never re-derives it — no double-source-of-truth.
- **`rdef`/`raidsDefended` = 0 at v1** is consistent with persistence-gdd (the fields exist; Raid simply doesn't write them until Phase 2) and with the offense-only scope lock.

---

## Open Questions (for user / game-designer / economy-designer)

1. ✅ **RESOLVED — Raid Shield (#7) re-scoped to Phase 2.** User confirmed deferring #7 to Phase 2 (paired with #18 PvP), since a shield guards against nothing in offense-only-vs-NPC v1 (header FLAG). systems-index #7 has been moved to Phase 2 (system number retained as a stable identifier); the extended-shield SKU follows to Phase 2.
2. ✅ **REVISED & LOCKED v1.2 — `raidSendCost = 100` / `raidLootPct = 0.20`** (down from 0.25). Owner-approved 2026-05-29 per economy-designer circulation analysis. At 0.20 the tier-3 raid ceiling stays under the "engagement faucet ≤30% of idle hourly" rule. Side effect at tier-1 (Grind Corp absolute new player) is flagged as Open Question #5.
3. **Player power model (F-POWER).** Default `highest_level`. Is "highest deployed/roster level" the right scaling+gating scalar, or should it be average / sum / a roster-size blend? Tunable in config; flagging the design choice. Reconcile against the real leveling curve (Battle/Evolution).
4. **NPC pool magnitudes + unlock gates (§8.1 placeholders).** `poolBase`/`poolPlayerScale`/`unlockLevel` per rival are placeholders flagged ⚠VALIDATE — must be reconciled against Idle #3's real coin rates so loot stays a *secondary* faucet (below idle) and unlock gates match the leveling pace. Lock during `/balance-check`.
5. **Tier-1 (Grind Corp) EV at absolute power-1 with `lootPct = 0.20` (v1.2 side effect).** At power-1, loot = 128, break-even = 78.1%, fair-skill 75% EV = −4 (slightly negative). Three mitigation paths under playtest review: (a) ship as-is with a "first raid free" Daily Quest offset, (b) bump Grind Corp `poolBase` 600→700 (loot at power-1 = 148, EV at 75% = +11), or (c) add per-rival override `Grind Corp.lootPct = 0.25` (preserves prior tier-1 break-even at 62.5%). Decision deferred to first playtest cycle; revisit alongside the Pivot 0.28 override re-check (it currently puts tier-3 raid at ~63% of idle hourly, above the 30% target).
6. **Per-target cooldown (`targetCooldownSeconds`).** Default 0 (send cost is the only spam gate at launch). Turn on (and pick a value) only if telemetry shows farming one rival is a problem. Confirm 0-at-launch is acceptable.
6. **Defender team size / composition.** Placeholders use 3-combatant teams (= attacker size) with single-species rows (species index `1`, content-TBD). Confirm rivals should be same-size 3v3 at launch (simplest/fairest), and finalize species/personality composition when Battle's species content lands.
7. **Evolution "raids won" milestone semantics.** v1 maps the idea-doc Rebel "survives 5 raids" → "won N raids" (`history.rwon`) since there is no survive-a-defense event yet. Confirm Evolution (#8) uses `rwon` for the relevant branches at v1, with the defense-survival branch dormant until Phase 2 produces `rdef`.

---

## Acceptance Criteria (system is "done")

- [ ] Player can open the Raid hub, see exactly 4 NPC Rival Startups (Grind Corp / Chill Collective / The Glitch Gang / Pivot Ventures) with tier badge, lock state, and a loot estimate; locked rivals cannot be selected and the gate is re-validated server-side (E8).
- [ ] Selecting an unlocked rival + exactly 3 owned, available Brainrots and confirming runs the full validation gauntlet (§5.2) **in order**; the FIRST failure rejects with a specific reason and **charges nothing / locks nothing**.
- [ ] On all-pass: `Economy.spend(raidSendCost=100,"raid_send",idemKey)` commits atomically, the 3 attacker ids are locked in-battle, and `BattleService.resolve(attackerTeam, defenderTeam, seed)` is called with a server-chosen seed (defender team built from `RaidConfig` via F-DEF-LEVEL).
- [ ] The client spectates the returned `BattleTimeline` (Battle's replay) and can Skip; the outcome is computed server-side **before** any frame animates.
- [ ] On `winner=="attacker"`: `loot = floor(pool * lootPct)` (F-POOL) is awarded via `Economy.award(...,"raid_loot",idemKey)` and, in the **same atomic + idempotent op**, `history.rwon +1` per attacker and `raidsWon +1` are written (Persistence). On `winner=="defender"`: no loot; the send cost stands.
- [ ] **Raid trusts Battle's `winner` absolutely** — a win where all attackers fainted still awards loot + increments milestones (E3); win/loss is never re-derived from survivor counts.
- [ ] **No real player loses coins** in any v1 raid; loot comes from the NPC config pool (F-POOL), never another player's pending; `history.rdef`/`raidsDefended` are never written (stay 0).
- [ ] Send cost is charged **exactly once** and loot awarded **exactly once** per raid under spam/retry/lag (rate limit + lock + dual idempotency keys, E5); a resolve/commit error refunds the send cost and releases the lock (E6/E10).
- [ ] Disconnect mid-spectate never changes the result, never loses loot, never double-resolves (E4); the result is available on rejoin.
- [ ] Defense Rating (F-DEFRATING) is computed server-side from the deployed roster, displayed read-only, updates on deployment change, and **triggers/gates nothing** in v1.
- [ ] All raid numbers (team size, cost 100, lootPct 0.20, pools, tiers, unlocks, defense weights) live in `RaidConfig`; a grep of Raid code finds **zero** hardcoded raid numbers; `RaidConfig.validate()` boots cleanly and warns on a worthless rival (E7).
- [ ] `RaidWon` and `RaidResolved` events fire with the specified payloads and are observable by a test subscriber (Daily Quests / Moment / Evolution consume them).
- [ ] Works on low-end mobile: one timeline payload + one result + event-driven Defense Rating updates; no per-frame networking.
- [ ] No Client→Server `RemoteFunction` anywhere in Raid; the client never sends a winner, loot, cost, seed, or unlock claim.
```