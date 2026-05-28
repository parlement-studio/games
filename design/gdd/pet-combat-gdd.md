# Field Combat / Pet AI GDD (Real-Time Hub Combat)

**Version**: 1.0
**Last Updated**: 2026-05-29
**Author**: systems-designer
**Status**: Draft (descriptive lock of demo reference impl `a71e545`)

> **Changelog**
> - **1.0 (2026-05-29)** — Initial GDD. Locks the demo reference implementation (`a71e545` `feat(demo): summoned-fighter pet AI`) as the v1 contract for System #25 Field Combat / Pet AI. **Descriptive scope:** documents the demo's mechanics, formulas, schema, and the cross-system contracts already locked in Phase B (`battle-gdd` v1.3 §2.4 shared personality tags; `evolution-gdd` v1.3 §2.7 Axis B XP write; `economy-gdd` v1.2 F-FAUCET-FIELDCOMBAT). **NOT prescribed in v1.0:** full personality battle-tag wiring (demo only applies `personalityDamageScales × prodMult` damage multiplier — full tag wiring is a v1.1 work item, flagged in §2.8 / Open Question #1).

> **Parent GDD**: `design/gdd/systems-index.md` — System **#25 (Field Combat / Pet AI, MVP, P2)**.
> **Source of Truth**: demo `a71e545`:
> - `src/ReplicatedStorage/Shared/Demo/DemoConfig.luau` §combat (lines 337–430) + §progression (lines 432–451) — the 24 tuning knobs + 4 progression params (graduate to `PetCombatConfig` on production move).
> - `src/ServerScriptService/Demo/DemoServer.server.luau` §fighter logic (`FighterRecord`, `stepFighter`, `formationOrder`, `combatRingSlot`, summon/seek/engage/despawn — lines ~103–1300).
> - `src/ServerScriptService/Demo/BrainrotAI.server.luau` — wild Brainrot wander/InCombat AI (114 lines).
> - `src/ReplicatedStorage/Shared/Demo/DemoRemotes.luau` — `SummonFighter` (C→S), `BattleEvent` (S→C) contracts.
> **Governing standards (NON-NEGOTIABLE)**: `.claude/rules/design-docs.md` (9 sections, explicit formulas, ≥5 edge cases, version header), `.claude/rules/gameplay-systems.md` (zero magic numbers, config-driven, state machine, delta-time, event-driven), `.claude/rules/server-scripts.md` (server-authoritative, never trust client, pcall, rate limit), `.claude/rules/remotes.md` (validate every handler, no Client→Server RemoteFunction, rate-limit), `.claude/rules/config-data.md` (commented config + ranges + version field).

> **Depends On**:
> - **#1 Data Persistence & Roster Core** (`persistence-gdd.md` v1.4.1) — OWNS `roster`, the `BrainrotEntry` shape (`id`, `personality`, `level`, `xp`, `evoStage`), and the atomic `update()` mutation path. Pet AI reads `roster[id]` to derive a fighter at summon, and writes `+xpPerWin` to `xp` (and cascading `level`) on a win via the **same direct `update()` path** Battle uses for Axis B. **No new persisted field** introduced by Pet AI.
> - **#2 Personality System** (`personality-gdd.md` v1.1.1) — OWNS the 5-personality trait table, the battle behavior tags + params (`act_first_mistarget` / `berserk_when_last` / `random_moveset` / `bodyguard` / `counter_double`), and `getBattleBehavior(id) → {tag, params}`. Pet AI is a **shared-contract consumer** with Battle (see §2.8). Pet AI also reads `prodMult(personality)` for the v1 damage-multiplier path (the production multiplier reused as a combat flavor knob — `personalityDamageScales = true`).
> - **#4 Capture** (`capture-gdd.md` v1.3) — supplies the roster the player summons from. A Brainrot must be in the roster (and not deployed in the showroom — see #26) to be eligible for summon. Capture has no direct call into Pet AI; it grows the supply only.
> - **#5 Battle System** (`battle-gdd.md` v1.3) — SHARES the `levelScale(L) = 1 + statGrowthPerLevel*(L-1)` stat-scaling formula (Battle §2.1 / §8.2 F2) AND the five personality battle-behavior tags (Battle §2.4). Pet AI implements **identical** tag intent in real-time dispatch (damage-tick) where Battle uses turn-step dispatch. **No param drift permitted** — both consumers read `statGrowthPerLevel` + `maxLevel` from `EvolutionConfig.progression` (Evolution v1.3 §8.5, single source of truth). Battle and Pet AI **never call each other**; they coexist as parallel combat layers (turn-based Raid vs real-time field).
> - **#8 Work-Based Evolution + Level/XP** (`evolution-gdd.md` v1.3) — OWNS the Axis B Level/XP curve VALUES (`xpPerWin` = 50, `xpCurveBase` = 100, `statGrowthPerLevel` = 0.08, `maxLevel` = 100, §8.5). Pet AI WRITES `+xpPerWin` on a win via the §2.7 XP-write path; Evolution OWNS the formula `xpToNext(L)` + `applyXpGrant`. Pet AI does **not** trigger Axis A milestones in v1 (no `history.rwon` bump from field combat — only raid wins bump `rwon`); a future rebalance may unify field+raid `rwon` accounting if Rebel/Chaotic Axis A timings drift.
> - **#9 Economy / Currency (Meme Coins)** (`economy-gdd.md` v1.2) — OWNS the `Economy.award` API. Pet AI calls `Economy.award(player, PetCombatConfig.winCoins, "field_combat_win", idemKey)` on a winning engagement per F-FAUCET-FIELDCOMBAT (§8.3). `idemKey = "fcw:"..fighterId..":"..wildId`. Pet AI owns the `winCoins` VALUE (25); Economy owns the credit + idempotency layer.

> **Depended On By**:
> - **#12 Moment System** — listens to Pet AI's `BattleEvent` (`win`/`ko`/`levelUp`) for celebratory banner/recap; Moment owns the presentation surface.
> - **#13 UI/HUD** — owns the summon button, active-fighter count display, the per-fighter health bar (Roblox `Humanoid` built-in over-head bar in v1), and the `BattleEvent` feedback banner formatting. Pet AI supplies state; UI renders.
> - **#17 Daily Quests** — the "menang M field battle" objective consumes Pet AI's `BattleEvent{kind="win"}`.
> - **#26 Base / Showroom Spatial Layer** — Pet AI **reads** `base.buildings[*].deployment` to exclude **currently-deployed** Brainrots from the summon-eligibility set (a Brainrot working on a showroom pedestal cannot also be summoned as a field fighter — single-use invariant, §2.1).

> **Cross-GDD consistency lock (no contradictions introduced — per `design-docs.md`):**
> - **Pet AI OWNS**: real-time field-combat resolution (summon → seek → engage → damage tick → win/KO/despawn), formation math (FOLLOW + COMBAT slot assignment), the wild-Brainrot AI (`BrainrotAI.server.luau` roaming + `InCombat` flag), the `winCoins` VALUE, all 24 `PetCombatConfig` knobs.
> - **Pet AI does NOT OWN**: combat math for Raid (Battle #5), persistence (#1), personality definitions or behavior-tag params (#2), economy values/wallet API (#9, Pet AI only consumes `Economy.award`), the Level/XP curve VALUES (Evolution #8 §8.5; Pet AI reads), `BrainrotEntry` shape (#1).
> - **Pet AI is real-time; Battle is turn-based.** Both consume the same roster + personality + level state. Both apply `levelScale(L)`. Both implement the five personality tags (Pet AI tag-wiring partial in v1 — see §2.8). Neither calls the other; both are server-authoritative; both run their own resolution loop.
> - **Pet AI is ephemeral.** A summoned fighter is a temporary clone of the owned Brainrot — the bag/roster is **NOT consumed** by summoning. The fighter `Model` lives in server memory + replicates to clients; only the **outcome** (XP grant, coins credit) persists.
> - **Compliance terminology (locked).** "Knocked out / fainted" — never "die/kill." Cartoon style. Fighter terminal state is `KnockedOut` (matches Battle §Cross-GDD lock).
> - **Zero pay-to-win.** Pet AI has **no Robux-only acceleration** in v1; no send cost (`costToSummon = 0`); a future "+1 max active fighter" GamePass is the only conceivable monetization hook and is deferred to Monetization #15. Field-combat rewards are engagement-only.

---

## 1. Overview & Purpose

Field Combat / Pet AI is the **real-time hub-world combat layer** — the manual, interactive counterpart to Idle Production (#3)'s ambient idle loop and Battle (#5)'s scheduled turn-based Raid. A player taps to summon one of their caught Brainrots as a **temporary field fighter**; the fighter follows the player as a pet, automatically engages **wild Brainrots** that come within range, and awards coins + XP on a win. After ~60 seconds the fighter auto-despawns. The original Brainrot in the bag is **never consumed** — summons are ephemeral clones with the persisted Brainrot's `level`/`personality` baked in at summon time.

It is **P2 (MVP-supporting, field activity layer)** because:

1. **It is the manual-action coverage of the core loop.** Idle Production gives the player a number to watch. Capture gives the player a chase. Pet AI gives the player a **moment-by-moment** thing to *do* in the hub: walk around, point at a wild, watch the fight, collect. Without it, the hub is a passive lobby; with it, the hub is a playground.
2. **It exercises the level + personality systems in *fast* feedback.** Battle (#5) is the *deep* combat surface (turn-based Raid), but it only fires when the player chooses to raid. Pet AI fires every time a wild walks within 30 studs of the player's pet — small, frequent personality moments ("my Hyper goes first!", "my Lazy got tough!") build the pillar's *felt* layer.
3. **It is the demo-validated reference impl.** Shipped in `a71e545`; this GDD locks the demo's mechanics as the v1 contract. The implementation already proves: server-authoritative AI, owner-centered detection (no infinite pursuit), multi-fighter formations (no clipping), real-time damage tick, win → coin/XP flow.

**Player intent:** *"I tap my Hyper-summon button. He pops up next to me and follows me around. I walk into a clump of wilds and he zooms over and starts smacking one. The wild's HP bar drops, the fighter wins, I get 25 coins, the wild faints and respawns somewhere else. After a minute he poofs and I can summon another. If I summon three at once they fan out behind me — looks cool."* The player thinks in terms of "summon, walk, watch, collect." They never think about formation slots, tick rates, or atomic XP writes — those are surfaced as a pet that follows, a fight that resolves quickly, and a number that goes up.

What this GDD does **NOT** do: it does not define Raid Battle math (Battle #5 / turn-based), does not author personality VALUES (Personality #2), does not own the wallet (Economy #9), does not define the Level/XP curve VALUES (Evolution #8 §8.5), does not own roster storage (Persistence #1). It owns *the summon contract, the per-fighter state machine, the AI seek + formation math, the real-time damage-tick model, the wild-Brainrot wander AI, and the win-credit hook into Economy + Evolution Axis B.*

---

## 2. Core Mechanics

### 2.1 Summon — ephemeral, server-authoritative, owner-leashed

A summon is a **server-side spawn** of a new `Model` clone built from the owned Brainrot's persistent state. The bag is **not consumed**.

1. **Client sends intent.** `SummonFighter(brainrotId)` C→S (DemoRemotes; rate-limited). In v1 demo the payload is `personality` (the server picks an owned Brainrot of that personality) — `brainrotId` is the **production migration target** so the server unambiguously summons a specific Brainrot (avoids "which Hyper am I summoning?"). See Open Question #2.
2. **Server validates.**
   - Owner has a Brainrot matching the intent in `roster` (not currently deployed in the showroom #26; not currently summoned as another fighter).
   - Owner's active-fighter count `< maxActiveFighters` (default 3, §8.1 E2).
   - Rate limit OK (per-player `summonRatePerSec`, §8.1).
3. **Server spawns.** Clone the species model template, parent into `workspace`, position `summonOffsetStuds` in front of the owner's HumanoidRootPart. Set `NetworkOwner = nil` on the root (server controls all motion — `.claude/rules/server-scripts.md`). Set Humanoid `WalkSpeed = fighterWalkSpeed`. Set Humanoid `MaxHealth = fighterBaseHP × levelScale(level)` and `Health = MaxHealth`.
4. **Server creates `FighterRecord`** (§3.3) — personality, brainrotId, level, model, timing deadlines, formation jitter, despawn timer.
5. **Server fires `BattleEvent{kind="summon", personality, brainrotId}`** for UI feedback (optional — demo currently silent on summon; may add for polish).
6. **Cost: 0 coins (v1).** `costToSummon = 0` — the engagement is free. Summon failures (no matching Brainrot, cap reached, rate-limited) return a `BattleEvent{kind="error", reason}` toast.

### 2.2 Per-fighter state machine

Each `FighterRecord` cycles through these **transient server-memory** states:

```
   [*] --> SEEKING : on summon (no target yet)
   SEEKING --> ENGAGED : a valid wild appears in detection
   SEEKING --> FOLLOWING : no valid wild in detection (formation idle)
   FOLLOWING --> ENGAGED : a valid wild enters detection
   ENGAGED --> FOLLOWING : owner walks out of range OR wild leaves OR wild despawns/captured
   ENGAGED --> WON : wild HP <= 0 (this fighter's tick crossed it)
   ENGAGED --> KNOCKED_OUT : fighter HP <= 0
   any --> DESPAWNING : despawnAt reached (fighterLifetimeSec elapsed)
   DESPAWNING --> [*]   : model destroyed; record removed
   WON --> SEEKING : next tick (looks for another target)
   KNOCKED_OUT --> [*] : gentle KO + remove
```

- **SEEKING vs FOLLOWING distinction (subtle):** "SEEKING" is the conceptual "I have no current target, I'll look on the next `seekRetargetSec`"; "FOLLOWING" is the executed walk to its formation slot. The two run in the same `stepFighter` loop; the demo's `nextSeekAt` deadline is the trigger to re-scan for targets.
- **No mid-fight kept after WON.** A fighter that just killed a wild becomes available the next tick — no kill-streak buff (yet).
- The state is **server-memory only** (`FighterRecord` is not persisted). On owner disconnect: all fighters despawn (E3).

### 2.3 Detection — owner-centered (LOCKED design decision)

**Detection radius is centered on the OWNER PLAYER, NOT the fighter.** This is the critical design choice that makes the summon feel like a *pet*, not a runaway tracker:

```
isValidTarget(wild, owner, ownerHRP) =
       wild.Humanoid.Health > 0
   AND wild.parent == workspace               -- not currently caught
   AND wild:GetAttribute("DemoCaught") ~= true
   AND (wild:GetAttribute("InCombat") == false OR engagedBy(wild) == thisFighter)
   AND distance(ownerHRP.Position, wild.PrimaryPart.Position) <= detectionRangeStuds
```

- The **owner-centered range** (default `detectionRangeStuds = 30`) means: if the player walks away from a fight, the fighter **auto-disengages and follows** (E4). No infinite pursuit, no fighter running off into the map.
- The **InCombat attribute** prevents multiple fighters from racing to the same wild *while another player's fighter is already engaging it* (multiplayer-aware lock; in v1 single-player demo all fighters are the owner's so co-engagement is allowed via the COMBAT ring formation — see §2.4).
- **Target selection: nearest valid wild** to the fighter's current position (not the owner's). Demo iterates `DemoConfig.demo3d.creatureNames`; production should iterate workspace tagged wilds via `CollectionService`.

### 2.4 Formations — multi-fighter coordination

When the owner has 2–3 active fighters, they must not stack. Two formation systems:

**FOLLOW formation** (when no target engaged) — fan-out arc **BEHIND** the player:

```
F-FORMATION-FOLLOW(N, fighterIndex)

  N = count of living fighters owned by this player
  i = this fighter's 0-based order index (0..N-1)
  half = followSpreadDegrees / 2                       -- demo: 90/2 = 45
  if N == 1 then angleOffset = 0
  else angleOffset = -half + (followSpreadDegrees * i / (N-1))     -- spread evenly across the arc

  baseDir = -ownerHRP.LookVector                       -- BEHIND the player
  if baseDir is near-zero, use FORMATION_FALLBACK_DIR  -- world +Z
  rotated = rotateY(baseDir, angleOffset)              -- rotation around vertical axis
  slotPos = ownerHRP.Position + rotated * followDistanceStuds + jitterOffset(this fighter)
```

- **Jitter:** each fighter rolls a small random horizontal offset (`followJitterStuds`, default 1.5) every `followJitterPeriodSec` (default 2.0s) so idle formation looks organic, not frozen.
- **Deadzone:** if the fighter is within `followStopStuds` (default 5) of its slot, skip the `MoveTo` (prevents jitter twitching).
- **Order index** is the fighter's position in the owner's `fighters` table — stable across a single summon's lifetime; reassigned when fighters despawn (so the remaining N-1 fan out cleanly).

**COMBAT ring** (when multiple fighters engage the same wild) — distinct slots on a circle around the target:

```
F-FORMATION-COMBAT(N_engagers, fighterIndex_among_engagers, targetPos, fighterY)

  N_eng = count of this owner's fighters currently engaging this wild
  j     = this fighter's 0-based index among co-engagers
  ringAngle = (2 * π * j) / N_eng                      -- even angular spacing
  ringOffset = Vector3.new(cos(ringAngle), 0, sin(ringAngle)) * combatRingRadiusStuds
  slotPos = targetPos + ringOffset    (with y = fighterY, server fixes ground)
```

- **`combatRingRadiusStuds < attackRangeStuds`** is REQUIRED (default 4 < 6) — a fighter at its ring slot is still within attack range of the target, so all co-engaging fighters keep dealing damage simultaneously.
- This prevents the "pile on the wild's exact position" clipping that the demo's earlier version had.

### 2.5 Combat tick — real-time damage exchange

Per `combatTickSec` (default 0.5s), each ENGAGED fighter executes one **damage exchange**:

1. **Verify still engaged.** If target is dead / out of detection / wild despawned: transition to FOLLOWING (clear wild's `InCombat`).
2. **Move toward ring slot.** `MoveTo(combatRingSlot(...))` — server-driven Humanoid step.
3. **If within `attackRangeStuds` of target:** deal damage.
   ```
   F-DAMAGE-FIGHTER (per tick)

     dmg = fighterBaseDamagePerTick                                -- demo: 12
         × levelScale(fighter.level)                                -- shared with Battle F2
         × (personalityDamageScales ? prodMult(fighter.personality) : 1)
                                                                    -- v1: damage mult only;
                                                                    -- v1.1: full tag wiring (§2.8)
     wild.Humanoid.Health = max(0, wild.Humanoid.Health - dmg)
   ```
4. **If target survived:** the wild deals damage back to the fighter.
   ```
   F-DAMAGE-WILD (per tick)

     dmg = wildDamagePerTick                                       -- demo: 6 (constant; no scaling in v1)
     fighter.Humanoid.Health = max(0, fighter.Humanoid.Health - dmg)
   ```
5. **Knockout check.** If wild Health hit 0 → §2.7 WIN path; if fighter Health hit 0 → KO path (§2.7).
6. **`nextCombatAt = now + combatTickSec`.**

> **`levelScale(L) = 1 + statGrowthPerLevel × (L - 1)`** — **identical to Battle (#5) F2** (`battle-gdd` v1.3 §2.1 / §8.2). Both consumers read `statGrowthPerLevel` (= 0.08) and `maxLevel` (= 100) from `EvolutionConfig.progression` (Evolution v1.3 §8.5). **No drift permitted** — if a future tuning pass changes `statGrowthPerLevel`, both Battle and Pet AI respond identically.

### 2.6 Wild Brainrot AI (`BrainrotAI.server.luau`)

The 5 wild creatures roam **independently of Pet AI** via a separate server script. Pet AI consumes the wilds via two `Model` attributes:

- **`InCombat: boolean`** — set `true` when Pet AI engages this wild; set `false` when Pet AI disengages or the wild is KO'd. While `InCombat == true`, `BrainrotAI` **skips** this wild (does not issue new `MoveTo`s — combat owns its movement).
- **`DemoCaught: boolean`** — set `true` by Capture when the wild is caught (the `Model` is unparented from `workspace`). `BrainrotAI` skips caught creatures (they're not in the world); Pet AI's detection check (§2.3) also excludes them.

The wild AI itself is simple wander:

```
F-WILD-WANDER (BrainrotAI.server.luau)

  every aiTickSec (default 0.5):
    for each wild in workspace not(InCombat or DemoCaught):
      if now >= state.nextAt and Humanoid.Health > 0:
        target = randomPointInDisc(state.home, wanderRadius)
        Humanoid:MoveTo(target)
        state.nextAt = now + uniform(wanderPauseMinSec, wanderPauseMaxSec)
```

- `state.home` is the wild's spawn position (claimed on first sight); wanders within `wanderRadius` of home so they don't drift into the showroom.
- **Server-authoritative motion**: `root:SetNetworkOwner(nil)` claims server ownership so clients can't be auto-assigned NPCs.

Pet AI and BrainrotAI **coordinate** only through the `InCombat` attribute — there is no direct call. This decoupling means BrainrotAI can be rewritten (or replaced with a behavior tree) without Pet AI changes.

### 2.7 Win / KO paths

**WIN (wild HP hits 0 due to this fighter's tick):**

1. Wild Humanoid → `Health = 0`. Wild's Humanoid emits `Died` (Roblox built-in).
2. Pet AI catches `Died` (or detects in next tick): fire the WIN flow:
   ```
   F-WIN

     -- Economy credit (idempotent per economy-gdd v1.2 F-FAUCET-FIELDCOMBAT):
     idemKey = "fcw:" .. fighter.brainrotId .. ":" .. wild.id            -- v1.1; v1 demo: no idemKey
     Economy.award(owner, PetCombatConfig.winCoins, "field_combat_win", idemKey)

     -- XP grant (per evolution-gdd v1.3 §2.7 Axis B):
     PlayerDataService.update(owner, function(data)
       local entry = data.roster[fighter.brainrotId]
       if not entry then return UNCHANGED end
       applyXpGrant(entry, PetCombatConfig.progression.xpPerWin)         -- F-LEVELUP (Evolution §8.3)
       return CHANGED
     end)

     -- Fire client feedback:
     BattleEvent{kind="win", personality, brainrotId, coins=winCoins, leveledTo?, level?}

     -- Respawn the wild via the catch path (reuses existing despawn-respawn machinery):
     wild.Humanoid.Health = wildBaseHP                                    -- restore
     wild:SetAttribute("InCombat", false)
     -- BrainrotAI resumes wandering automatically next tick
   ```
3. Fighter transitions back to SEEKING; on next tick scans for a new target.

**KO (fighter HP hits 0):**

1. Fighter Humanoid → `Health = 0`. Fighter emits `Died`.
2. Pet AI catches `Died`:
   ```
   F-KO

     -- Clear the wild's lock (it can be engaged again):
     if fighter.engaged ~= nil:
       fighter.engaged:SetAttribute("InCombat", false)

     -- Fire client feedback (a gentle "out of office"):
     BattleEvent{kind="ko", personality, brainrotId}

     -- Despawn the fighter Model gently:
     fade out or simply Destroy() after a brief delay
     remove FighterRecord from owner state

     -- No XP, no coin penalty (the bag is intact — Brainrot itself is unaffected).
   ```

### 2.8 Personality battle tags — v1 partial, v1.1 full (cross-system contract)

Personality #2 §2.1 defines five **battle behavior tags** (`act_first_mistarget` / `berserk_when_last` / `random_moveset` / `bodyguard` / `counter_double`) + their params. Per `battle-gdd` v1.3 §2.4 and `personality-gdd` v1.1.1 §9, these tags are a **shared cross-system contract** — both Battle (turn-based, for Raid) and Pet AI (real-time, this GDD) implement them identically.

**v1 (demo) — DAMAGE MULTIPLIER ONLY.** The demo currently applies only:

```
personalityDamageScales = true
=> per-tick fighter damage gets ×prodMult(personality)
   (Hyper 1.3, Lazy 0.5, Chaotic/Loyal/Rebel 1.0)
```

This is a useful shortcut (reuses the existing production multiplier as a combat flavor knob) but it does **NOT** implement the actual battle tags. **A Hyper does not act-first, a Loyal does not bodyguard, a Rebel does not counter** in v1 Pet AI.

**v1.1 (target) — FULL TAG WIRING (per Battle §2.4 shared contract).** Real-time dispatch equivalents:

| Tag | Battle (turn-based) | Pet AI (real-time) v1.1 target |
|---|---|---|
| `act_first_mistarget` (Hyper) | First-priority turn order; `mistargetChance` to re-roll target | First fighter to enter detection wins the **engage race** even if another was closer; `mistargetChance` per tick to attack the wrong target (a co-fighter or another wild) |
| `berserk_when_last` (Lazy) | Skip turn if `alliesAlive > 1`; berserk damage when alone | Reduce damage tick by 50% (or skip ticks) while another fighter is alive; double damage when sole survivor |
| `random_moveset` (Chaotic) | Random move per turn | Per-tick random damage variance ×[0.5, 2.0] (instead of `prodMult` 1.0) |
| `bodyguard` (Loyal) | Redirect hit if ally HP fraction < threshold | When co-engaging, ABSORB damage destined for an ally fighter at `bodyguardDamageTakenFraction` (Loyal's tick takes the hit instead) |
| `counter_double` (Rebel) | Counter immediately on surviving incoming hit | After taking a damage tick that didn't KO, retaliate with `counterDamageMultiplier × fighter damage` in the *same* tick |

**v1.1 is NOT in scope for this GDD.** The wiring is a work item flagged in §9 + Open Questions #1. Until v1.1, the v1 damage-multiplier path stands.

### 2.9 Auto-despawn

A fighter despawns `fighterLifetimeSec` (default 60s) after summon, regardless of state:

```
F-DESPAWN-CHECK (every stepFighter call)

  if now >= record.despawnAt:
    if record.engaged ~= nil:
      record.engaged:SetAttribute("InCombat", false)  -- release the wild gently
    BattleEvent{kind="despawn", personality, brainrotId}
    fighter.Model:Destroy()
    state.fighters.remove(record)
    return                                             -- exit step early; do not tick further
```

- **No grace period on engaged fighters.** A fighter mid-fight that hits its lifetime simply disengages and despawns — the wild lives. This keeps the field self-cleaning even if the player goes AFK.
- Despawn fires `BattleEvent{kind="despawn"}` for UI feedback (optional in v1; demo currently silent).

---

## 3. Data Schema

Pet AI introduces **no persisted player-data field.** It reads from existing Persistence fields and writes only Axis B XP/level (via Evolution §2.7's XP-write path). All Pet AI runtime state is **ephemeral server-memory only**.

### 3.1 Persisted fields READ by Pet AI (all owned by Persistence #1)

| Field | Owner | Pet AI use |
|---|---|---|
| `roster[id].personality` | Personality #2 + Persistence | Damage multiplier (v1) + tag selection (v1.1); UI label |
| `roster[id].level` | Persistence (write-owned by Battle + Pet AI via Axis B) | `levelScale(L)` on `fighterBaseHP` + `fighterBaseDamagePerTick` |
| `roster[id].xp` | Persistence (write-owned by Battle + Pet AI via Axis B) | Read for UI bar; INCREMENTED by Pet AI on win (§2.7 F-WIN) |
| `roster[id].evoStage` | Evolution #8 / Persistence | (Future) future combat multiplier mirror — v1 NOT applied to field combat damage |
| `base.buildings[*].deployment` | Idle #3 / Persistence | EXCLUDE deployed Brainrots from summon-eligibility set (a Brainrot at work can't be summoned) |

### 3.2 Persisted fields WRITTEN by Pet AI

| Field | Path | When | Idempotency |
|---|---|---|---|
| `roster[id].xp` | direct `PlayerDataService.update()` (per Evolution v1.3 §2.7) | On `F-WIN`: `applyXpGrant(entry, xpPerWin)` | **v1: none** (low-stakes; over-credit XP is non-monetary). v1.1: optional `txLog` idemKey `"fcw_xp:"..fighterId..":"..wildId` if abuse vector found. |
| `roster[id].level` | implicit (set by `applyXpGrant` cascade) | When `xp ≥ xpToNext(level)` | Same as `xp` write. |
| `coins` | via `Economy.award(...)` (#9 owns) | On `F-WIN` | **v1.1: REQUIRED** — `idemKey = "fcw:"..fighterId..":"..wildId` per F-FAUCET-FIELDCOMBAT (economy-gdd v1.2). |

> **v1 demo path:** the demo writes `xp`/`level` via `PlayerDataService.update()` and credits coins via the live-coin float + flush path. **Production v1.1 requires** the `Economy.award` idempotency key to land before Monetization #15 (no real-money exposure, but consistent with the locked F-FAUCET-FIELDCOMBAT contract).

### 3.3 Ephemeral server state — `FighterRecord` + `PlayerState.fighters`

Server memory only; never persisted. Re-initialized empty on profile load (player joins with zero active fighters).

```lua
-- Per-fighter record (one per active summoned fighter).
type FighterRecord = {
    -- Identity (the summon source — links back to roster[id]).
    personality: string,         -- "Hyper" | "Lazy" | "Chaotic" | "Loyal" | "Rebel"
    brainrotId: string,          -- the roster id this is a temporary clone of
    level: number,               -- snapshot at summon time (Lv1-capped scaling is server-evaluated)

    -- The world body.
    model: Model,                -- the spawned fighter Model in workspace

    -- Tick deadlines (os.clock-based).
    nextCombatAt: number,        -- next damage-tick eligibility
    nextSeekAt: number,          -- next re-scan-for-target eligibility (when not engaged)
    despawnAt: number,           -- absolute deadline (summon time + fighterLifetimeSec)

    -- Current engagement.
    engaged: Model?,             -- the wild Model currently being attacked (or nil = not engaged)

    -- FORMATION JITTER for organic FOLLOW look (re-rolled every followJitterPeriodSec).
    jitterOffset: Vector3,       -- small horizontal offset added to slot position
    jitterAt: number,            -- os.clock deadline for next jitter re-roll
}

-- Per-player fighter list (the "active summons" set).
PlayerState.fighters: { FighterRecord }   -- length 0..maxActiveFighters (default 3)
```

> **Why no per-fighter `currentHP` in `FighterRecord`?** Because the spawned `Model`'s `Humanoid.Health` IS the HP — Roblox's built-in over-head health bar reads it directly, and `Humanoid.Died` is the KO trigger. Storing a parallel `currentHP` field would risk drift; the demo (correctly) makes `Humanoid` the single source of truth for HP during a fighter's lifetime.

### 3.4 Wild-Brainrot world-state attributes (set by Pet AI / BrainrotAI)

These are Roblox `Attribute`s on the wild `Model` instance — server-memory state with replication-by-default to clients. **No persistence.**

| Attribute | Owner | Meaning |
|---|---|---|
| `InCombat: boolean` | Pet AI sets/clears | While `true`, BrainrotAI skips wander; another player's fighter cannot engage. |
| `DemoCaught: boolean` | Capture sets/clears (demo) | While `true`, the `Model` is unparented; Pet AI's detection skips it via the model.Parent check anyway. |
| `engagedBy: ObjectValue` *(v1.1 candidate)* | Pet AI (proposed) | Which fighter is currently engaging (to enable PvP-safe co-engagement rules). Not in v1 — single-player demo allows owner's co-engagement freely. |

---

## 4. Client-Server Split

**Server-authoritative for everything that matters.** Client is a viewer for combat results.

| Concern | Server (authoritative) | Client (presentation only) |
|---|---|---|
| Fighter spawn + parent | **YES** — `Instance.new` / clone, parent to workspace | Renders the model (auto-replicated) |
| Fighter movement (MoveTo) | **YES** — `NetworkOwner=nil`, Humanoid:MoveTo from server | Renders the walk animation (auto-replicated) |
| Combat tick (`combatTickSec`) | **YES** — server's `RunService.Heartbeat`-accumulator + per-fighter `nextCombatAt` | Sees the Humanoid Health drop, the over-head bar updates |
| Damage calculation (F-DAMAGE-FIGHTER/WILD) | **YES** — server reads `PetCombatConfig` + `level` + `personality` | Never computes damage; cannot influence |
| WIN credit (`Economy.award`, `applyXpGrant`) | **YES** — via Persistence's atomic `update()` + Economy API | Sees `BattleEvent{kind="win", coins, level?}` — renders banner |
| KO check (`Humanoid.Died`) | **YES** — server connects `Died` and triggers F-WIN or F-KO | Sees the dead Humanoid; renders fade |
| Detection / target selection | **YES** — server iterates wilds, applies F-DETECTION centered on owner | Never queries; cannot redirect |
| Formation slot assignment | **YES** — server computes F-FORMATION-FOLLOW / F-FORMATION-COMBAT | Sees fighter at slot (auto-replicated motion) |
| Despawn (lifetime / disconnect) | **YES** — server destroys the Model + removes the FighterRecord | Sees the model disappear |
| Health bar | (server is the Health authority) | **YES** — Roblox's built-in over-head Humanoid health bar renders |
| `BattleEvent` feedback banner | (server fires) | **YES** — renders cartoon banner ("Your Hyper won! +25 coins") via Moment #12 |

**Authority rule (locked, per `server-scripts.md`):** Pet AI is **server-driven**. The only Client→Server intent is `SummonFighter`. A tampered client **cannot**:
- Self-spawn a fighter (server is the spawner).
- Self-deal damage (server is the damage-tick authority, NetworkOwner=server).
- Self-credit coins (server fires `Economy.award`; client only displays the result).
- Bypass `maxActiveFighters` (server's count check is the gate).
- Extend `fighterLifetimeSec` (server's `despawnAt` is the deadline).

The worst a hacked client can do is animate its own screen weirdly — server state, persistence, and rewards are untouched.

---

## 5. RemoteEvents / Functions

All remotes registered in `ReplicatedStorage/Shared/Remotes` (v1.1 production) — currently in `ReplicatedStorage/Shared/Demo/DemoRemotes` (demo). Documented in `design/remotes-manifest.md` on graduation. **No Client→Server `RemoteFunction`** (server-hang risk per project policy). Refinable by `remotes-networking-specialist`.

### 5.1 Server → Client

| Remote | Type | Payload | Purpose |
|---|---|---|---|
| `BattleEvent` | RemoteEvent | `{ kind: "summon" | "win" | "ko" | "despawn" | "levelUp" | "error", personality?: string, brainrotId?: string, coins?: number, leveledTo?: number, level?: number, reason?: string }` | Transient combat feedback for the client UI. Renders via Moment #12 banner. `summon`/`despawn` may be silent in v1; `win`/`ko`/`levelUp` are the felt beats. `error` carries a reason for failed summons (`"no_match"`, `"cap_reached"`, `"rate_limited"`). |

### 5.2 Client → Server

| Remote | Type | Payload | Validation |
|---|---|---|---|
| `SummonFighter` | RemoteEvent | **v1 demo:** `(personality: string)` (server picks first owned Brainrot of that personality). **v1.1 production target:** `(brainrotId: string)` (server validates the player owns this id and it's not deployed/in another fight). | Server validates: (a) rate limit `summonRatePerSec` (default 2/sec), (b) caller owns the Brainrot, (c) Brainrot not deployed in showroom (#26), (d) Brainrot not in another fighter record, (e) caller's active-fighter count < `maxActiveFighters`. Reject with `BattleEvent{kind="error", reason}` toast on any failure. |

> **Decision (locked v1):** there is **NO client-side recall remote.** Fighters auto-despawn at `fighterLifetimeSec` (default 60s). Rationale: keeps the contract small (one C→S intent), prevents the player from "stockpiling" summons by recalling and re-summoning to bypass rate limits, and the 60s lifetime is short enough that "recall" isn't felt as a missing feature. Open Question #3 covers a future on-demand recall if playtesting shows the lifetime is too short.

### 5.3 Internal server events (NOT network — cross-system decoupling per `gameplay-systems.md`)

Bindable / signal layer (`GameEvents`):

| Event | Payload | Fired When | Listened By |
|---|---|---|---|
| `FieldCombatWon` | `{ player, brainrotId, personality, wildSpecies?, coins, leveledTo?, fromLevel?, toLevel?, xpAfter, serverTime }` | A fighter wins (F-WIN flow committed Economy + Persistence) | **#12 Moment** (presentation), **#17 Daily Quests** (`win N field battle` objective), Analytics, Future Achievement system |
| `FieldCombatKO` | `{ player, brainrotId, personality, byWildSpecies?, serverTime }` | A fighter is KO'd (F-KO flow) | **#12 Moment** (a gentle "out of office" beat), Analytics |
| `FighterSummoned` | `{ player, brainrotId, personality, atPosition, serverTime }` | Server completes a summon | **#12 Moment** (optional), Analytics |
| `FighterDespawned` | `{ player, brainrotId, personality, reason: "lifetime" | "ko" | "disconnect", serverTime }` | Server destroys the fighter Model + removes FighterRecord | Analytics |

> **Consumed (not emitted) by Pet AI:** `RosterChanged` (a captured Brainrot becomes summon-eligible immediately; a released one cannot be summoned). No event from Idle / Capture / Economy directly drives Pet AI's tick — the tick is owned by Pet AI's own `Heartbeat` accumulator.

---

## 6. Player-Facing UI

Rendered through the shared UI/HUD framework (#13); pure presentation (reads replicated state, fires intents). Mobile-first. Cartoon, kid-safe.

1. **Summon button + bag-row "Summon" affordance.** The roster/bag panel (#13) shows each owned, non-deployed Brainrot with an inline **"Summon"** chip when the player has room (`active < maxActiveFighters`). Tapping it fires `SummonFighter(brainrotId)`. Chip is greyed when the Brainrot is already summoned, deployed (#26), or the active-fighter cap is reached.
2. **Active-fighter count indicator.** A small HUD pill: *"Fighters: 2 / 3"* (the `maxActiveFighters` cap, §8.1). Reads the client's mirror of `PlayerState.fighters` length. Updates live as fighters spawn/despawn.
3. **Per-fighter HP bar.** Roblox's **built-in over-head Humanoid health bar** is the HP display in v1 — minimal UI work, low overhead. Open Question #5 covers a richer per-fighter HUD pip if requested.
4. **`BattleEvent` feedback banners.** Surfaced via Moment #12 (one at a time, kid-clarity):
   - `win` → *"YOUR HYPER WON! +25 Meme Coins"* (with the personality color/icon)
   - `levelUp` (subsequent to a `win` if F-LEVELUP cascaded) → *"YOUR HYPER LEVELED UP! Lv5"*
   - `ko` → *"Your Lazy fainted — out of office"* (cartoon, never "died")
   - `despawn` → silent or *"Your Hyper headed back to the bag"* (low-priority)
   - `error` → toast: *"No Lazy in your bag yet!"* / *"Max 3 fighters out — wait for one to despawn"*
5. **Personality + level mini-badge over the fighter (optional polish).** A small floating tag during combat: *"Hyper · Lv5"*. Cosmetic only; the demo currently shows nothing extra over the spawned model. Polish item, post-v1.
6. **Formation hint (debug / playtest, NOT shipped).** During development, render the formation slot positions as visible markers — useful for tuning `followSpreadDegrees` / `combatRingRadiusStuds`. Hidden in shipped builds.

All surfaces are **event-driven** (one `BattleEvent` per transition); **no per-frame networking** — safe on low-end mobile.

---

## 7. Edge Cases & Error States

Covers the `design-docs.md` checklist (zero / max / negative / rapid / lag / disconnect / datastore-down / concurrent). **Minimum 5 exceeded (10 documented).**

### E1 — Player tries to summon a personality they don't own

**Trigger:** v1 demo `SummonFighter(personality)` where the player has zero Brainrots of that personality (e.g. they captured only Lazy + Hyper, tap "Summon Loyal").
**Behavior:** Server's roster scan returns nil → reject with `BattleEvent{kind="error", reason="no_match"}`. Client shows toast: *"No Loyal in your bag yet!"*. No state change, no rate-limit penalty (a benign mis-tap).

### E2 — Active-fighter cap reached

**Trigger:** Player has `maxActiveFighters` (default 3) fighters already active and taps Summon.
**Behavior:** Server rejects with `BattleEvent{kind="error", reason="cap_reached"}`. Client toast: *"Max 3 fighters out — wait for one to despawn"*. No spawn, no rate penalty.

### E3 — Owner disconnects mid-fight

**Trigger:** `Players.PlayerRemoving` fires while the player has 1–3 active fighters (engaged or not).
**Behavior:** Pet AI iterates `state.fighters`, for each: clears the engaged wild's `InCombat = false` (wild resumes wandering), destroys the fighter `Model`, removes the `FighterRecord`. No XP grant for any mid-fight engagement (server has not yet detected a KO). The owner profile is saved by Persistence's normal `PlayerRemoving` flow — Pet AI's despawn is independent of save. No orphan models, no leaked wilds in `InCombat`.

### E4 — Owner walks out of `detectionRangeStuds` while a fighter is engaging

**Trigger:** Fighter is mid-combat (ENGAGED on wild W); owner walks away; the wild's distance from owner exceeds `detectionRangeStuds`.
**Behavior:** Pet AI's per-tick `isValidTarget` check fails (the owner-centered range guard). Fighter clears `wild.InCombat = false`, releases the wild, transitions to FOLLOWING, walks to the formation slot behind the now-distant owner. The wild resumes wandering immediately (BrainrotAI re-acquires it next tick). **No leashing chase** — the fighter does not run after the player + the wild simultaneously; "the player is the boss" wins.

### E5 — Wild is captured (`DemoCaught = true`) mid-fight

**Trigger:** A different player's Capture flow (or this player's, when Capture lands in production) catches the wild while a fighter is engaging it.
**Behavior:** Pet AI's `isValidTarget` check fails on the next tick (`DemoCaught` filter). Fighter releases the engagement (`InCombat` no longer relevant — the wild is unparented), transitions to SEEKING. The wild's `Model` is removed from workspace by Capture's flow. No double-grant: there is no XP/coin from "engaging a wild that someone else caught."

### E6 — `fighterLifetimeSec` reached during an active engagement

**Trigger:** Fighter's `despawnAt` deadline elapses while still ENGAGED.
**Behavior:** Per F-DESPAWN-CHECK (§2.9), the fighter clears the wild's `InCombat = false` and despawns gently. The wild resumes wandering. **No "almost won" grace period** — even at 1 HP remaining on the wild, despawn wins. Player sees the despawn (silent or `BattleEvent{kind="despawn"}`). The wild does not heal; another fighter can engage immediately.

### E7 — Two of the SAME owner's fighters engage the SAME wild

**Trigger:** Owner has 2+ active fighters; both detect the same nearest wild simultaneously.
**Behavior:** Both transition to ENGAGED on the same target. Pet AI's `combatRingSlot` (§2.4 F-FORMATION-COMBAT) assigns each fighter a **distinct angular slot** on the ring around the wild — no clipping. Both deal damage per tick (damage stacks). First fighter whose tick crosses the wild's HP to 0 fires F-WIN — its `brainrotId` gets the XP grant + Economy credit. The "loser" fighter (whose tick was second) simply finds the wild dead next tick and transitions to SEEKING. **No double-credit** because F-WIN runs on a single tick boundary.

### E8 — Wild moves outside `attackRangeStuds` during the engagement (but still inside owner detection)

**Trigger:** Wild's `MoveTo` carries it temporarily out of `attackRangeStuds` of the fighter, but still within owner detection.
**Behavior:** Fighter remains ENGAGED, `MoveTo`s toward the wild's current position (server reads `wild.PrimaryPart.Position` each tick). Damage tick does not deal damage on a tick where `distance(fighter, target) > attackRangeStuds`. This is "chase the wild a few studs" — natural; resolves in 1–2 ticks at the demo speed/range numbers. No oscillation because the fighter only re-issues `MoveTo` once per tick (not per frame).

### E9 — Personality is unrecognized (corrupt data, future-personality, post-Phase-2 expansion)

**Trigger:** `roster[id].personality` is a value not in the v1 enum (e.g. data corruption, a Phase-2 6th personality loaded on a v1 server).
**Behavior:** `prodMult(unknown)` returns `1.0` (Personality #2 §F1 fallback). Pet AI applies it as the damage multiplier — fighter fights at baseline. No crash. `BattleEvent{kind="win"}` still fires; the client renders the personality string verbatim (UI may show a generic icon for unknown personality). Logged loudly for QA. (Same defensive pattern as Battle E8 / Personality E6.)

### E10 — XP / coin write fails (DataStore down, lock-fence mismatch)

**Trigger:** A fighter wins; Pet AI calls `PlayerDataService.update(...)` + `Economy.award(...)`; one or both calls fail (DataStore unavailable, save fenced out by lock-gen mismatch per persistence-gdd §2.1).
**Behavior:** Per persistence's standard discipline (`pcall` + dirty flag + retry on next autosave tick), the in-memory mutation that committed via `update()` is **still in memory**; the next save retries. If `update()` itself failed (the mutator threw), no in-memory mutation — same as Evolution E5 and Idle E11. **The wild stays dead** (the Humanoid Health = 0 transition is local to the world model, not gated on the save) — the next time the wild's spawn timer fires it respawns regardless. **No double-credit** because `update()`'s mutator is idempotent on the `xp` write (the cascade level-up uses the in-memory state). The player may briefly see "+25 coins" in the wallet mirror that doesn't persist if a hard server crash hits before save — same risk profile as Idle Collect (acceptable for v1; receipts are Monetization's concern, not field combat). v1.1 may add the `Economy.award` idempotency key (`"fcw:"..fighterId..":"..wildId`) to harden against any future retry-on-failure flow.

---

## 8. Balancing Parameters

> **This is the core tuning surface of Pet AI.** All values in `PetCombatConfig` (v1.1 production location) — currently in `DemoConfig.combat` (v1 demo). **Zero magic numbers in code.** Each value commented + ranged per `config-data.md`. Refinable by `economy-designer` (income side) + `qa-tester` (feel side) + `/balance-check`.
> **⚠ VALIDATE** items are flagged for `/balance-check` / playtest.

### 8.1 `PetCombatConfig` — the 24-knob master table (demo-locked values)

Sourced from `src/ReplicatedStorage/Shared/Demo/DemoConfig.luau` §combat. On graduation: rename `DemoConfig.combat` → `PetCombatConfig` (same shape, same values).

| Knob | Locked v1 value | Range | Purpose | ⚠VALIDATE? |
|---|---|---|---|---|
| `summonOffsetStuds` | **5** | 2..12 | How far in front of the owner the fighter spawns | playtest readability |
| `fighterWalkSpeed` | **10** | 1..24 | WalkSpeed applied to summoned fighters (a touch > wild's 6 so it can close distance) | |
| `fighterBaseHP` | **100** | 1..1000 | Lv1 base MaxHealth (actual MaxHealth = this × `levelScale(level)`) | ⚠ vs `wildDamagePerTick` (survival rate) |
| `wildBaseHP` | **100** | 1..1000 | Wild Humanoid MaxHealth (wilds are effectively Lv1 in v1) | |
| `attackRangeStuds` | **6** | 2..16 | Range at which fighter stops chasing and starts damage-ticking | |
| `combatRingRadiusStuds` | **4** | 1..attackRangeStuds | Per-fighter ring slot radius around target (MUST be < `attackRangeStuds`) | |
| `detectionRangeStuds` | **30** | 8..120 | OWNER-centered radius for valid targets (the "pet leash" radius) | ⚠ mobile readability + leash feel |
| `followDistanceStuds` | **8** | 2..20 | FOLLOW: distance behind owner the fighter trails | |
| `followStopStuds` | **5** | 1..15 | FOLLOW deadzone (no `MoveTo` if within this of slot — prevents jitter) | |
| `followSpreadDegrees` | **90** | 0..180 | FORMATION arc behind owner (across which N fighters fan out) | |
| `followJitterStuds` | **1.5** | 0..6 | Per-fighter random horizontal offset (organic look) | |
| `followJitterPeriodSec` | **2.0** | 0.5..10 | Jitter re-roll cadence | |
| `combatTickSec` | **0.5** | 0.1..2 | One damage exchange per tick | ⚠ feel + DPS curve |
| `fighterBaseDamagePerTick` | **12** | 1..100 | Lv1 base fighter damage (actual = this × `levelScale(level)` × personality mult) | ⚠ time-to-kill at Lv1 |
| `wildDamagePerTick` | **6** | 1..100 | Wild's return damage (constant in v1; no scaling) | ⚠ fighter survival |
| `winCoins` | **25** | 0..1000 | Coins awarded on a win (Economy faucet `field_combat_win`) | ⚠ vs idle hourly (<30% target) |
| `maxActiveFighters` | **3** | 1..10 | Per-player active-fighter cap | ⚠ UI clutter + readability |
| `seekRetargetSec` | **0.5** | 0.1..2 | Re-scan cadence when not engaged | |
| `fighterLifetimeSec` | **60** | 10..300 | Auto-despawn deadline | ⚠ engagement-density feel |
| `personalityDamageScales` | **true** | bool | v1: multiply damage by `prodMult(personality)`. v1.1: superseded by full tag wiring (§2.8). | |
| `summonRatePerSec` (proposed v1.1) | **2** | 0.5..10 | Per-player summon rate limit | |
| `costToSummon` | **0** | 0..1000 | Coins charged on summon (v1: free engagement reward) | locked free for v1 |

Plus the 4-knob `PetCombatConfig.progression` block — but **VALUES are owned by Evolution v1.3 §8.5**. Pet AI **reads** them from `EvolutionConfig.progression` (single source of truth). Listed here only for clarity:

| Progression knob | Value | Owner | Pet AI use |
|---|---|---|---|
| `xpPerWin` | 50 | Evolution v1.3 §8.5 | XP grant on F-WIN |
| `xpCurveBase` | 100 | Evolution v1.3 §8.5 | F-LEVELUP `xpToNext(L)` |
| `statGrowthPerLevel` | 0.08 | Evolution v1.3 §8.5 | `levelScale(L)` for HP/damage |
| `maxLevel` | 100 | Evolution v1.3 §8.5 | Hard cap on `level` writes |

### 8.2 Formulas (explicit, named variables)

```
F-DETECTION                 valid wild for engagement
  isValidTarget(wild, owner) =
    Humanoid.Health > 0
    AND model.Parent == workspace
    AND model:GetAttribute("DemoCaught") ~= true
    AND model:GetAttribute("InCombat") ~= true
    AND distance(owner.HRP, wild.PrimaryPart) <= detectionRangeStuds
```

```
F-FORMATION-FOLLOW(N, i)    fighter slot position when not engaged (i = 0..N-1)
  half        = followSpreadDegrees / 2
  angleDeg    = (N == 1) ? 0 : -half + (followSpreadDegrees * i / (N - 1))
  baseDir     = -owner.HRP.LookVector                          -- BEHIND
  baseDir     = baseDir.Magnitude > 1e-4 ? baseDir.Unit : (0, 0, 1)
  dir         = rotateY(baseDir, deg2rad(angleDeg))
  slotPos     = owner.HRP.Position + dir * followDistanceStuds + jitterOffset
  return slotPos
  Notes:
   - jitterOffset is re-rolled per `followJitterPeriodSec` per fighter (independent jitter).
   - If owner faces a wall, fighters tunnel toward the wall — acceptable in MVP (Roblox MoveTo handles collision).
```

```
F-FORMATION-COMBAT(N_eng, j, targetPos, fighterY)
                              fighter slot on the combat ring (j = 0..N_eng-1 among co-engagers)
  ringAngle   = (2 * π * j) / N_eng
  ringOffset  = (cos(ringAngle), 0, sin(ringAngle)) * combatRingRadiusStuds
  slotPos     = (targetPos.x + ringOffset.x, fighterY, targetPos.z + ringOffset.z)
  return slotPos
  Bounds: combatRingRadiusStuds < attackRangeStuds (enforced by config validate()).
```

```
F-DAMAGE-FIGHTER (per combat tick)
  hpAfterScaling = fighterBaseHP * levelScale(fighter.level)      -- set at summon time
  dmg_per_tick   = fighterBaseDamagePerTick
                 * levelScale(fighter.level)                       -- Battle/Pet AI shared (Evolution §8.5)
                 * (personalityDamageScales ? prodMult(fighter.personality) : 1.0)
                                                                   -- v1: damage mult; v1.1: full tag wiring (§2.8)
  wild.Humanoid.Health = max(0, wild.Humanoid.Health - dmg_per_tick)
```

```
F-DAMAGE-WILD (per combat tick, applied AFTER F-DAMAGE-FIGHTER if wild survived)
  dmg_per_tick = wildDamagePerTick                                 -- constant in v1
  fighter.Humanoid.Health = max(0, fighter.Humanoid.Health - dmg_per_tick)
```

```
F-WIN (wild HP hit 0 this tick)
  idemKey = "fcw:" .. fighter.brainrotId .. ":" .. wild.id          -- v1.1 production; v1 demo: omit
  Economy.award(owner, PetCombatConfig.winCoins, "field_combat_win", idemKey)
  PlayerDataService.update(owner, function(data)
    local entry = data.roster[fighter.brainrotId]
    if not entry then return UNCHANGED end
    applyXpGrant(entry, EvolutionConfig.progression.xpPerWin)        -- Evolution §8.3 F-LEVELUP cascades level-up
    return CHANGED
  end)
  fire BattleEvent{kind="win", personality, brainrotId, coins=winCoins, leveledTo?, level?}
  fire GameEvents.FieldCombatWon(...)                                -- §5.3 internal
  -- respawn the wild via the catch-path machinery:
  wild.Humanoid.Health = wildBaseHP
  wild:SetAttribute("InCombat", false)
  fighter.engaged = nil
  fighter.state -> SEEKING
```

```
F-KO (fighter HP hit 0 this tick)
  if fighter.engaged ~= nil:
    fighter.engaged:SetAttribute("InCombat", false)
  fire BattleEvent{kind="ko", personality, brainrotId}
  fire GameEvents.FieldCombatKO(...)
  destroy fighter.model (after brief fade for UX)
  remove FighterRecord from owner.state.fighters
```

```
F-DESPAWN-CHECK (every stepFighter call)
  if os.clock() >= fighter.despawnAt:
    if fighter.engaged ~= nil:
      fighter.engaged:SetAttribute("InCombat", false)
    fire BattleEvent{kind="despawn", personality, brainrotId}
    fire GameEvents.FighterDespawned{ reason = "lifetime" }
    fighter.model:Destroy()
    remove FighterRecord
    return (do not tick further this step)
```

### 8.3 Balancing assumptions to validate via `/balance-check` + playtest

1. **`winCoins = 25` vs idle hourly income.** ⚠VALIDATE: field-combat income (computed from typical engagement density: `wildsInRange × winRate × ticksPerKill × winCoins`) should stay **<30% of idle's primary faucet** at comparable upgrade level (economy-gdd v1.2 §9 row #25). Re-tune `winCoins` (or `fighterLifetimeSec`) if the per-hour total dwarfs idle.
2. **Fighter survival rate at Lv1.** ⚠VALIDATE: `fighterBaseDamagePerTick` (12) vs `wildDamagePerTick` (6) at `fighterBaseHP = wildBaseHP = 100` means the fighter wins a 1v1 with ~50% HP remaining (`100 / 12 = 9 ticks to kill wild` × `6 = 54 dmg taken` — survives). Confirm this **wins-feel** at Lv1 (player gets the reward) without being a free coin printer.
3. **Lv50 / Lv100 wins are trivial.** Expected per `levelScale`: a Lv100 fighter deals `12 × 8.92 = ~107 dmg/tick`, one-shots a wild. Acceptable — the long Lv-up grind is the reward, late-game field combat is supposed to feel easy. ⚠VALIDATE the **boredom threshold**: does a Lv100 player still summon, or does the wild-pool become irrelevant? May suggest scaling wilds by player level in a future pass (out of v1 scope).
4. **`detectionRangeStuds = 30` mobile readability.** ⚠VALIDATE: 30 studs is roughly a screen width on mobile portrait. Confirm the player can tell which wilds are "in range" without an explicit indicator.
5. **`maxActiveFighters = 3` UI clutter.** ⚠VALIDATE: 3 fighters fanned across 90° is readable; 5+ would crowd. Confirm 3 is the right cap for mobile screens, and that the FORMATION arc reads cleanly with 1 / 2 / 3 fighters.
6. **`fighterLifetimeSec = 60` engagement density.** ⚠VALIDATE: 60s is short enough that the player engages 3–5 wilds per summon (assuming typical wild density). If wilds are sparse, lifetime may need a bump (or `costToSummon` may stay 0 forever).
7. **`combatTickSec = 0.5` feel.** ⚠VALIDATE: 0.5s tick is fast enough to read each exchange but slow enough that personality mults (Hyper 1.3, Lazy 0.5) produce visibly different TTKs. Don't go below 0.2 (per-frame thrash on mobile).
8. **v1.1 personality tag-wiring impact.** When `act_first_mistarget` / `berserk_when_last` / etc. land, ⚠VALIDATE that the resulting personality DPS variance (Hyper +20% miss; Lazy berserk when alone; Rebel counter ×2) doesn't break the `<30% of idle` income target. May require winCoins re-tune at v1.1.

### 8.4 `PetCombatConfig.validate()` (boot-time, per `gameplay-systems.md`)

Runs once on server start:
- Asserts every numeric value is in its declared range; clamps + logs a warning on out-of-range.
- Asserts `combatRingRadiusStuds < attackRangeStuds` (else clamps `combatRingRadiusStuds = attackRangeStuds - 1`).
- Asserts `followStopStuds < followDistanceStuds` (else clamps).
- Reads `EvolutionConfig.progression` (Evolution v1.3 §8.5) and ensures `xpPerWin` / `xpCurveBase` / `statGrowthPerLevel` / `maxLevel` are present; logs critical if Evolution config is missing (Pet AI cannot apply F-LEVELUP without those values).
- Asserts `prodMult(personality)` is defined for all 5 personalities (Personality #2 §8); falls back to `1.0` for any unknown.

---

## 9. Integration Points

Pet AI is a **consumer of state** (#1, #2, #4, #8 read; #26 read for exclusion) and a **producer of events / persisted writes** (#9 Economy, #8 Evolution Axis B, #12 Moment, #17 Daily Quests, #13 UI).

### Depends On

- **#1 Data Persistence & Roster Core** (`persistence-gdd.md` v1.4.1) — Pet AI reads `roster[id].{personality, level, xp, evoStage}` and writes `xp`/`level` via direct `PlayerDataService.update()` (Axis B path per Evolution v1.3 §2.7). **No new schema field.** v1.4.1 §9 documents Pet AI as a consumer.
- **#2 Personality System** (`personality-gdd.md` v1.1.1) — Pet AI reads `personality` enum + `getBattleBehavior(id) → {tag, params}` (same API Battle uses; the five battle behavior tags are a **shared cross-system contract** per §2.4 in `battle-gdd` v1.3 and §9 in `personality-gdd` v1.1.1). v1 demo only applies `prodMult(personality)` damage scaling; v1.1 wires the full tag dispatch (§2.8).
- **#4 Capture** (`capture-gdd.md` v1.3) — supplies the roster Pet AI summons from. No direct API call.
- **#5 Battle System** (`battle-gdd.md` v1.3) — shares the `levelScale(L)` formula (Battle §2.1 / §8.2 F2; both consumers read `statGrowthPerLevel` + `maxLevel` from EvolutionConfig — no drift) AND the five personality behavior tags (Battle §2.4). Battle and Pet AI **never call each other**; both are server-authoritative parallel combat layers.
- **#8 Work-Based Evolution + Level/XP** (`evolution-gdd.md` v1.3) — OWNS the Axis B Level/XP curve VALUES (§8.5) and the `applyXpGrant` / `xpToNext` formulas (§8.3 F-LEVELUP). Pet AI calls these on F-WIN. Pet AI does NOT trigger Axis A milestones in v1 (no `history.rwon` bump from field combat — that stays raid-only).
- **#9 Economy** (`economy-gdd.md` v1.2) — Pet AI calls `Economy.award(player, winCoins, "field_combat_win", idemKey)` on F-WIN. `winCoins` value owned by THIS GDD (§8.1); `Economy.award` API + the `field_combat_win` faucet metadata owned by #9.

### Depended On By

- **#12 Moment System** — primary listener of `FieldCombatWon` / `FieldCombatKO` / `FighterSummoned` (§5.3 internal events). Surfaces the celebratory banner on a win, the "out of office" beat on a KO. Pet AI defines/fires; Moment presents.
- **#13 UI/HUD** — owns the summon-from-bag chips, the "Fighters: N/3" pill, the `BattleEvent` banner formatting. Pet AI ships state + intents + events; UI animates them.
- **#17 Daily Quests** — the "menang M field battle" objective increments on `FieldCombatWon`.
- **#26 Base / Showroom Spatial Layer** — Pet AI reads `base.buildings[*].deployment` to **exclude** currently-deployed Brainrots from the summon-eligibility set. A Brainrot at work on a showroom pedestal cannot also be summoned as a field fighter (single-use invariant).

### ⚠ Cross-system actions (for owners to reconcile)

> **FLAG-PETAI-TAGS — v1.1 obligation.** Pet AI v1 only applies the personality damage multiplier (`prodMult`). The full five behavior tags (`act_first_mistarget` / `berserk_when_last` / `random_moveset` / `bodyguard` / `counter_double`) are defined in Personality #2 and dispatch-tested in Battle #5; Pet AI must implement the **real-time dispatch equivalents** (§2.8 table) before claiming feature parity with Battle. Coordination: `personality-gdd` v1.1.1 §9 lists Pet AI as a consumer; `battle-gdd` v1.3 §2.4 marks the tags as a shared contract. **No personality config change required** — Pet AI wires existing params into a real-time runtime.

> **FLAG-PETAI-IDEMPOTENCY — v1.1 obligation.** Pet AI's `Economy.award(... "field_combat_win", ...)` call must carry `idemKey = "fcw:" .. fighterId .. ":" .. wildId` per `economy-gdd` v1.2 F-FAUCET-FIELDCOMBAT. The v1 demo path omits this (acceptable: no real-money exposure, no retry-on-fail flow). Lock the idemKey before Monetization #15 lands so the faucet ledger has the same idempotency discipline as `raid_loot`, `quest_daily`, and `devproduct_pack`.

> **FLAG-PETAI-BRAINROTID — v1.1 production migration.** v1 demo accepts `SummonFighter(personality)` (server picks any owned Brainrot of that personality). Production should accept `SummonFighter(brainrotId)` (server unambiguously summons a specific Brainrot, validates ownership). The UI affordance (§6 item 1) already shows per-Brainrot summon chips, so the client-side switch is small; the server-side validation gauntlet (§5.2) is the substantive change.

---

## Acceptance Criteria (system is "done")

- [ ] **GDD merged** as `design/gdd/pet-combat-gdd.md` v1.0 (this document); systems-index #25 status moves from "In design" to "In implementation" once production code lands.
- [ ] **PetCombatConfig** (renamed from `DemoConfig.combat`) is the **sole** source of all 24 tuning values; grep of production code finds **zero hardcoded** combat numbers.
- [ ] **Server-authoritative motion**: every fighter root carries `NetworkOwner = nil`; a client cannot influence Humanoid:MoveTo or Health.
- [ ] **Damage tick is server-driven**: `RunService.Heartbeat` accumulator + per-fighter `nextCombatAt` deadline; no client tick.
- [ ] **F-DAMAGE-FIGHTER reads `statGrowthPerLevel` from `EvolutionConfig.progression`** (Evolution v1.3 §8.5) — not from a local mirror; if Evolution's value changes, Pet AI responds without code change.
- [ ] **`levelScale(L)` is identical to Battle's F2** — TestEZ asserts both produce bit-equal outputs for L = 1..100.
- [ ] **F-WIN credits Economy via `Economy.award(... "field_combat_win", idemKey)`** with the locked idemKey contract (v1.1 obligation).
- [ ] **F-WIN grants XP via `applyXpGrant`** (Evolution v1.3 §8.3 F-LEVELUP); cascade level-ups produce per-level `BattleEvent{kind="levelUp"}` events (one per boundary).
- [ ] **`Humanoid.Died` is the KO trigger** for both fighter and wild — no parallel health field.
- [ ] **Detection is owner-centered** (F-DETECTION): a fighter does NOT engage a wild outside the OWNER's `detectionRangeStuds`, regardless of the fighter's own distance.
- [ ] **Formations are deterministic**: F-FORMATION-FOLLOW and F-FORMATION-COMBAT produce stable, non-overlapping slots for N = 1, 2, 3 fighters.
- [ ] **Wild AI (`BrainrotAI.server.luau`) and Pet AI coordinate only via `InCombat` attribute** — no direct call.
- [ ] **`SummonFighter` remote is rate-limited and fully validated** (rate, ownership, deployment-exclusion, fighter-cap); rejects with `BattleEvent{kind="error", reason}`.
- [ ] **`fighterLifetimeSec` auto-despawn fires regardless of state**; despawn cleans `InCombat` on any engaged wild.
- [ ] **`PlayerRemoving` despawns all of the leaving player's fighters** and clears their engaged-wild locks — no orphan models, no leaked `InCombat = true` wilds.
- [ ] **TestEZ coverage**: F-DETECTION, F-FORMATION-FOLLOW(N=1/2/3), F-FORMATION-COMBAT(N=1/2/3), F-DAMAGE-FIGHTER at Lv1/Lv50/Lv100, F-WIN's Economy + Persistence write, F-KO's `InCombat` cleanup, all 10 edge cases E1–E10.
- [ ] **`/balance-check` passes** the §8.3 ⚠VALIDATE items — especially the **<30% of idle's primary faucet** income cap.
- [ ] **`/exploit-check` passes** — no double-credit via rapid summon/despawn, no `InCombat` desync exploit, no XP grant without a corresponding KO event.
- [ ] **Works on low-end mobile** — server-side AI (no client tick), one `BattleEvent` per transition (no per-frame networking), Humanoid built-in health bar (no custom over-head UI per fighter).

---

## Open Questions (for user / game-designer / qa-tester)

1. **Personality battle-tag wiring (FLAG-PETAI-TAGS) — v1.1 priority?** v1 ships damage-multiplier only. Wiring the full five tags (§2.8) is feature-parity with Battle but adds complexity (state per fighter for `berserk_when_last`, multi-fighter coordination for `bodyguard`). When does v1.1 land — before Monetization #15? Before launch? Post-launch polish? → game-designer + lead-programmer.
2. **`SummonFighter` payload — `personality` (v1 demo) vs `brainrotId` (v1.1 target).** The id-keyed payload is unambiguous but requires the bag UI to surface per-Brainrot summon affordances. v1.1 production migration locks the switch; confirm. → ui-designer + lead-programmer.
3. **On-demand recall remote?** v1 has no `RecallFighter` — fighters auto-despawn at 60s. If playtests show players want to "cancel a summon early" (e.g. wrong personality picked, or moving to a new area), add `RecallFighter(brainrotId)` C→S. Rate-limit + ownership check; same despawn flow. → qa-tester.
4. **Wild scaling for late-game (Lv50+ fighters trivialize Lv1 wilds).** Should wilds also scale (`wildBaseHP × wildLevelMult`)? Or accept that field combat is a low-level activity that fades as raids/Evolution take over? Phase-2 consideration. → game-designer.
5. **Per-fighter HUD richer than Humanoid health bar.** v1 uses Roblox's built-in over-head HP. If readability is poor (mobile + 3 fighters + a wild = 4 HP bars overlapping), consider a dedicated screen-space HUD pip per fighter. → ui-designer + accessibility-specialist.
6. **Field combat as a Daily Quest source — quest example wording.** Daily Quests (#17) lists "menang M field battle" as a candidate; lock M and the reward range. → game-designer + economy-designer (alignment with §17 reward pool).
7. **PvP collision (Phase 2).** If two players' fighters target the same wild, the v1 `InCombat = true` flag locks the wild to the first owner — the second player's fighter cannot engage. Acceptable for single-player demo and v1 launch; PvP raids (#18) may want a co-engage rule. Out of v1 scope. → game-designer (Phase 2).
8. **Summon cost (`costToSummon`) — locked at 0 for v1, but a future GamePass-gated "double summons" or "+1 max active fighter" is a candidate monetization hook. Coordinate with Monetization #15. → monetization-lead.
