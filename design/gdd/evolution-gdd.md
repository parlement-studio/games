# Work-Based Evolution + Level/XP Progression GDD

**Version**: 1.3
**Last Updated**: 2026-05-28
**Author**: systems-designer
**Status**: Draft

> **Changelog v1.3 (2026-05-28)**: **Phase A reconciliation — added Axis B: Level/XP Progression** as a *descriptive* lock of the demo work (commit `36724cf`, demo's `DemoConfig.progression` block + `DemoServer` battle-resolution path). Per the systems-index 2026-05-28 update, system #8 now covers **two orthogonal progression axes**:
> - **Axis A — Work-Based Evolution** (transformative milestone, unchanged in v1.3): one-shot, per-personality, flips identity (`evoStage 0 → 1`) — everything §2.1–§2.6 / §3.2 / §8.1–§8.4 describes.
> - **Axis B — Level/XP Progression** (gradual combat power, new in v1.3): per-Brainrot Level/XP system already shipped in demo. **New § added:** §2.7 (mechanics + shared `levelScale(L)` contract); §3.1 schema rows for `level`/`xp` updated; new §8.5 locks the demo curve values (`xpPerWin=50`, `xpCurveBase=100`, `statGrowthPerLevel=0.08`, `maxLevel=100`); new F-LEVELUP formula in §8.3; §9 Integration adds Pet AI #25 as an XP source and notes the shared `levelScale(L)` formula with Battle #5.
>
> **What this changelog does NOT do (locked, descriptive-only scope per user direction):** v1.3 does **not** prescribe a new XP-write architecture. Demo currently has Battle/Pet AI **directly increment `xp`/`level` via Persistence's atomic `update()` path** (no event-listener pattern yet); v1.3 documents that as the current path. Routing XP writes via an Evolution-service event listener (`battle_win` → Evolution listens → applies XP/level) is noted as a **future refactor option** in §9, NOT prescribed here. Same for **work-based Axis A milestone wiring**: demo skips it entirely; v1.3 leaves §2.1–§2.6 as the design target without claiming it is implemented. Status of Axis A in code = **not started** (per systems-index §8 status note).
> **Changelog v1.2**: FLAG-BATTLE and FLAG-IDLE (§9) ✅ RESOLVED — the consumers are now wired: Battle **v1.2** reads `combatMultiplier` (1.15) from `EvolutionConfig` (single source of truth); Idle **v1.2** multiplies `productionMultiplier` (1.20) into `effectiveRate` + offline path. Evolution remains the owner of both VALUES. No numeric change.
> **Changelog v1.1**: Open Question #2 (reroll-after-evolve) ✅ RESOLVED — user confirmed: a rerolled evolved Brainrot **KEEPS its evolved status** (`evoStage` is NOT reset by reroll); only the evolved-form **look/name is re-derived from the new personality** (E3 rule confirmed). No schema or formula change — confirms the locked behavior.

> **Parent GDD**: `design/gdd/systems-index.md` — System **#8 (Work-Based Evolution, P2 — the 3rd MVP pillar, long-term hook)**.
> **Source of Truth**: `idea/brainrotInc.md` §"Work-Based Evolution" ("Brainrots evolve based on what they **do**, not just items they consume"; "attention shapes them"; "Show me your evolved Brainrot"); locked pre-production context.
> **Governing standards (NON-NEGOTIABLE)**: `.claude/rules/design-docs.md` (9 sections, explicit formulas, ≥5 edge cases, version header), `.claude/rules/config-data.md` (commented config + ranges + version field), `.claude/rules/gameplay-systems.md` (zero magic numbers, config-driven, event-driven, state machine), `.claude/rules/server-scripts.md` (server-authoritative, never trust client, pcall, rate limit).

> **Depends On**:
> - **#1 Data Persistence & Roster Core** (`persistence-gdd.md` v1.2) — OWNS the `id`-keyed roster, the `BrainrotEntry` shape (incl. `evoStage: number` default 0, and the lifetime-counter block `history{coins, rdef, rwon, fame}` + `capturedAt`), the player-level lifetime counters (`raidsWon`, `raidsDefended`, `stats.totalCoinsEarned`, `stats.lifetimeCaptures`), and the **atomic mutation path + idempotency log (`txLog`)**. Evolution writes `evoStage` via Persistence's atomic `UpdateAsync` with an idempotency key. Evolution touches **no** DataStore directly.
> - **#2 Personality System** (`personality-gdd.md` v1.1) — OWNS the `personality` enum + the trait table. Evolution is **per-personality**: which milestone + which evolved form applies is keyed by `entry.personality`. Evolution listens to `PersonalityChanged` (reroll) for the reroll-after-evolve rule (E3).
> - **#3 Idle Production** (`idle-production-gdd.md` v1.2) — supplies the `history.coins` lifetime-production milestone source (Idle bumps `history.coins` on Collect, idle §2.9) and fires `CoinsCollected`. **Evolution defines the production multiplier per evoStage; Idle v1.2 multiplies it into `effectiveRate` + offline path (✅ wired — FLAG-IDLE §9).**
> - **#5 Battle System** (`battle-gdd.md` v1.2) — reads `entry.evoStage` and applies the combat multiplier (F1stats `evoMult`), now sourced from `EvolutionConfig.stageMultipliers[*].combatMultiplier` (✅ single source of truth — FLAG-BATTLE §9). **The per-stage VALUES are OWNED here** (`[1].combatMultiplier = 1.15`). Battle fires `BattleResolved` (raid-win context).
> - **#6 Raid v1 (NPC Rival Startups)** — supplies the `history.rwon` (raids **won** as attacker) milestone source. Raid writes `history.rwon` via Persistence's atomic op on a winning raid and fires the per-raid outcome Evolution checks against.

> **Depended On By**:
> - **#12 Moment System** — an evolution is a **big Moment** (`EvolutionOccurred`); Moment surfaces the "your Brainrot evolved!" celebration + recap.
> - **#17 Daily Quests** — the "evolve 1 Brainrot" objective consumes Evolution's `EvolutionOccurred` event.
> - **#13 UI/HUD** — owns the progress bar / evolve animation / evolved-form display surface (Evolution supplies the data).
> - **#20 Multi-Branch Evolution (Phase 2)** — extends this single-stage model into multiple branches; cheap **only because** the lifetime counters were wired day-1 (persistence #1).

> **Cross-GDD consistency lock (no contradictions introduced — per `design-docs.md`):**
> - **Evolution OWNS** the milestone definitions (metric + threshold per personality), the evolved-form definitions (name + flavor + visual asset reference), and the per-stage **multiplier VALUES** (`combatMultiplier` that Battle reads + `productionMultiplier` that Idle reads). It does **NOT** own the combat mechanic (Battle #5) or the production mechanic (Idle #3) — it owns only the *values those mechanics multiply by* and *when a Brainrot advances `evoStage`*.
> - **No new persisted schema.** Evolution uses the existing `evoStage` + `history` + player-level counters from persistence v1.2. It adds **no** field to `PlayerData`/`BrainrotEntry`. (Multi-branch P2 may add a `evoPath` field via a v1→v2 `migrate()` step — out of scope here.)
> - **`evoStage` is written via Persistence's atomic path + idempotency key** (persistence §2.3) — exactly like reroll/capture commits. Idempotency is what makes evolution un-double-triggerable (E2).
> - **Compliance / world-builder.** "attention shapes them" — evolution is framed as a Brainrot growing into a recognized role through its work, not "leveling up a stat." Cartoon, kid-safe. No gacha/loot-box framing (evolution is **earned by play history**, never paid for — zero-P2W, systems-index #15).

---

## 1. Overview & Purpose

Work-Based Evolution + Level/XP Progression (System #8) is the game's **long-term hook** — the third MVP pillar. System #8 covers **two orthogonal progression axes** on every Brainrot:

- **Axis A — Work-Based Evolution** (`evoStage`): a one-shot, per-personality **identity transformation** when a Brainrot crosses a work-history milestone. A Hyper that has produced enough lifetime coins becomes a **"Senior Hyper"** (tie + coffee mug); a Rebel that has won enough raids becomes a **"Revolutionary"** (protest banner); a Loyal that has carried the factory becomes a **"Guardian"** (shield). The evolved form is a **visible record of how that specific Brainrot was used** — and because no two players play the same way, **no two players have the same evolved roster.** That is the USP this pillar delivers: *"Show me your evolved Brainrot"* becomes a social question with a real, personal answer.
- **Axis B — Level/XP Progression** (`level` / `xp`, §2.7, demo-validated `36724cf`): a continuous, **gradual combat-power ramp** earned from combat wins. A Brainrot fought into Lv50 is meaningfully harder-hitting and harder to kill than the same Brainrot at Lv1, via the shared `levelScale(L)` stat-scaling formula (Battle #5 + Pet AI #25 read it identically). **Level is *combat power*; Evolution is *identity*** — different rewards for different progressions, deliberately not merged into one system.

The two axes are **independent** (§2.7 / §2.8): a Brainrot can be Lv50-unevolved or Lv1-evolved; reroll preserves both; level doesn't affect Idle Production (locked decision — Axis B is pure combat).

It is **P2 (long-term hook)** because:

1. **It is the weeks-long retention reason.** Idle Production (#3) and Raid (#6) drive the daily/weekly loop; Evolution gives players a reason to keep that loop going for *weeks* — "I want to see what my best guy becomes." It is the collection depth Pet Simulator 99 lacks: not *having* the pet, but *what your pet became*.
2. **It is a POWER hook, not just cosmetic (locked user decision).** Evolution is the one progression lever that makes a *specific* Brainrot meaningfully stronger in **both** of the game's effort surfaces: it **boosts combat** (Battle reads `evoStageStatMultiplier`) **and** boosts **production** (Idle reads a parallel production multiplier), plus a **cosmetic visual upgrade**. This is what makes the milestone worth grinding toward and turns a favorite worker into a long-term investment.
3. **It is the felt payoff of the "lifetime counters wired day-1" investment** (persistence #1 / systems-index notes). The whole reason `history.coins`/`history.rwon` exist from the first commit is so this system — and Phase-2 multi-branch evolution — can read real play history that was impossible to backfill later.

**Player intent:** *"My Hyper guy has made me a TON of coins, and the game says he's almost a 'Senior Hyper' — I want to keep him deployed so he hits the milestone and gets the tie and the boost. My Rebel keeps winning raids and he's about to become a Revolutionary. Everyone's evolved guys look different — mine show what I actually did."* The player thinks in terms of "keep using my best guys and they grow into something special." They never think about `evoStage` integers, idempotency keys, or multipliers — those surface as a **progress bar toward evolution**, a big **evolve animation**, and a visibly different **evolved sprite**.

What this GDD does **NOT** do: it does not implement combat math (Battle #5), production math (Idle #3), or storage (Persistence #1); it does not author the **visual asset content** (cosmetic models/accessories are content-TBD); it does not own personality definitions (Personality #2) or raid/loot (Raid #6). It owns *the milestone definitions, the evolved-form definitions, the evolve trigger + idempotent state advance, and the per-stage multiplier VALUES the other systems read.*

---

## 2. Core Mechanics

### 2.1 The model: milestone-driven, event-checked, idempotent

1. **One milestone per personality (MVP).** Each of the 5 personalities has **exactly one** evolution milestone: a `(metric, threshold)` pair. Reaching the threshold on the right metric evolves the Brainrot from **stage 0 (unevolved)** to **stage 1 (evolved)**. Multi-branch / multi-stage is Phase 2 (#20).
2. **The metric is read from the Brainrot's own lifetime history** (persistence-owned, monotonic, never decremented). The available v1 metrics are: `history.coins` (lifetime coins this Brainrot produced), `history.rwon` (raids this Brainrot won as an attacker), and `entry.level` (progression). **Constraint v1 (critical): `history.rdef` — raids *defended* — is `0` at launch** because Raid v1 is offense-only vs NPCs (no PvP defense until Phase 2). Milestones therefore **do not** use `rdef` in v1 (see §2.4).
3. **Event-driven checks (not polling).** Evolution never scans the roster on a timer. It runs a milestone check **only on the relevant event**, for **only the affected Brainrot(s)**:
   - on `CoinsCollected` (Idle #3) → check the personalities whose metric is `lifetimeCoins`, for the Brainrots that contributed coins this collect;
   - on a **winning raid** (Raid #6 / `BattleResolved` attacker-win) → check the personalities whose metric is `raidsWon`, for the attacking team's Brainrots;
   - on `level-up` (Battle/XP) → check the personalities whose metric is `level`, for that Brainrot;
   - on **login** (after load+migrate) → a **one-time backfill check** of every owned Brainrot, so a milestone reached while offline (or before this system shipped) evolves on next login (E1).
4. **Idempotent advance.** When a check passes, Evolution performs an **atomic `evoStage` advance via Persistence** (`UpdateAsync` + idempotency key `evo:<id>:<targetStage>`). The transform is a **no-op if `entry.evoStage >= targetStage` already** (or if the idempotency key is already in `txLog`), so the same Brainrot can never double-evolve from a duplicate event / retry / race (E2).
5. **On a committed evolution**, Evolution: sets `entry.evoStage = 1`; fires `EvolutionOccurred` (Moment #12, Daily Quests #17); and replicates the new stage to the client (which plays the evolve animation + swaps to the evolved sprite). The **combat** boost applies the next time the Brainrot is built into a Combatant (Battle reads the new `evoStage`); the **production** boost applies on the next production tick (Idle reads the new `evoStage`).

### 2.2 Why event-driven + login-backfill (not a timer)

A per-frame or per-second roster scan at roster cap 200 is wasteful and pointless: the only thing that changes a milestone metric is a coin collect, a raid win, or a level-up — all of which are **already events**. So Evolution **subscribes to those events** and checks **only the Brainrot(s) the event touched**. The single exception is **login**, where a one-time pass over the roster catches anything that crossed a threshold while the player was offline, while the system was being rolled out, or via a metric that was bumped by a path Evolution didn't observe. This is O(roster) once per session — trivial — and guarantees no milestone is ever silently missed.

### 2.3 The 5 evolved forms (MVP — 1 stage each)

Each row defines the **personality → evolved form**, the **v1 milestone metric + threshold**, the locked **combat** and **production** multipliers (§8), and the flavor. **Visual assets are content-TBD** (the accessory/model is named for direction; the `assetId` is filled during content production).

| Personality | Evolved form (stage 1) | v1 milestone metric | Threshold (config) | Visual direction (content-TBD) | Flavor ("attention shaped it into…") |
|---|---|---|---|---|---|
| **Hyper** | **Senior Hyper** | `lifetimeCoins` (`history.coins`) | **10,000** coins | tie + desk + coffee mug | "Worked so hard for so long it got *promoted*. Same chaotic energy, now with a job title." |
| **Rebel** | **Revolutionary** | `raidsWon` (`history.rwon`) | **5** raids won | protest banner accessory | "Won enough fights that the others started following it. A movement, not just an employee." |
| **Loyal** | **Guardian** | `lifetimeCoins` (`history.coins`) **[REDESIGNED — see §2.4]** | **8,000** coins | shield visual | "Held the line at the factory day after day. The one everyone counts on — now it carries a shield." |
| **Lazy** | **Consultant** | `lifetimeCoins` (`history.coins`) | **6,000** coins | reclining chair + clipboard | "Did so little, so effectively, that it 'consults' now. Slacked its way to seniority." |
| **Chaotic** | **Wildcard** | `raidsWon` (`history.rwon`) | **4** raids won | glitch-aura / mismatched-suit visual | "Caused enough beautiful disasters in the field to become legend. Nobody knows what it'll do next — and that's the point." |

> **Per-Brainrot metric, not per-player.** `history.coins` / `history.rwon` are **per-Brainrot** counters (persistence §3.2), so the milestone is about *this specific Brainrot's* work — exactly the "what your pet *became*" promise. Two Hypers in the same roster evolve independently based on how much **each** produced.

### 2.4 Milestone REDESIGN for v1 (no `rdef`) — explicit

The idea doc specifies **Loyal → Guardian at "defend 3 raids"** and **Rebel → Revolutionary at "survive 5 raids."** Both depend on a **defense** signal. **In Raid v1, defense does not exist:** raids are **offense-only vs NPC Rival Startups** (systems-index #6), so `history.rdef` (raids defended) is **`0` for every Brainrot at launch** — it is a Phase-2 PvP signal. Building a milestone on `rdef` in v1 would make those evolutions **literally unreachable**. The redesign keeps the *spirit* of each form using a metric that is **achievable in v1**:

| Form | idea-doc (Phase-2 / defense-based) | v1 milestone (this GDD) | Why this metric in v1 |
|---|---|---|---|
| **Revolutionary** (Rebel) | "**survive** 5 raids" | "**win** 5 raids" (`history.rwon`) | v1 raids are offense; "won 5 raids" is the closest achievable analogue to "survived 5 raids" and reads identically to a kid ("my Rebel keeps winning"). Same number (5), metric swapped survive→win. |
| **Guardian** (Loyal) | "**defend** 3 raids" | "produced **8,000** lifetime coins" (`history.coins`) | Loyal's defining v1 behavior is **steady, reliable production** (Personality: "steady production, never affected by negative events"). A Guardian "held the line at the factory" maps cleanly to a **production** milestone — the one thing a Loyal *does* in v1. It is achievable, on-theme ("the one everyone counts on"), and avoids the dead `rdef` metric. |

> **Phase-2 forward note (not a v1 requirement):** when PvP raids (#18) ship and `history.rdef` becomes real, Multi-Branch Evolution (#20) can add a **defense-based branch** (e.g. Loyal → *Guardian (Defense path)* at `rdef >= 3`) **alongside** the v1 production path — the lifetime `rdef` counter exists day-1 specifically so that branch is cheap to add. This GDD does **not** wire it; it just leaves the door open. The v1 Guardian milestone stays `lifetimeCoins` regardless.

### 2.5 State machine (per Brainrot)

```
   [*] --> Unevolved(evoStage=0) : minted at capture (persistence Schema.newBrainrot)
   Unevolved --> Evolving        : milestone check passes (atomic advance requested)
   Evolving  --> Evolved(evoStage=1) : Persistence commits evoStage=1 (idempotent)
   Evolving  --> Unevolved        : commit FAILS (DataStore down) — retried later (E5); no partial state
   Evolved   --> Evolved          : further milestone checks are NO-OPs (stage already >= 1) — idempotent (E2)
```

- **`Evolving`** is a transient in-memory marker only (not persisted) covering the window between "check passed" and "Persistence commit returned"; it prevents a second concurrent check from racing the same advance (the idempotency key is the durable guarantee, this is the cheap in-memory guard — E2).
- **`Evolved` is terminal in MVP** (one stage). Multi-stage (`evoStage = 2…`) is Phase 2; the schema (`evoStage: number`) and the `targetStage` parameterization already support it, so no rework is needed later.
- **A `KnockedOut` Brainrot in battle never evolves mid-fight** — evolution checks run on the *outcome* event (`BattleResolved` / a winning raid), after the combatant lock is released, never inside the turn loop (E4).

### 2.6 Trigger flow diagram

```
  RELEVANT EVENT (one of):
    CoinsCollected{contributors}  | RaidWon{attackerIds}  | LevelUp{id}  | Login{roster}
        │
        ▼
  ┌─────────────────────────────────────────────┐
  │ FOR EACH affected Brainrot id:               │
  │   entry = roster[id]                          │
  │   if entry.evoStage >= 1 -> skip (idempotent) │  ── already evolved ──► (no-op)
  │   rule = EvolutionConfig.byPersonality[ entry.personality ]
  │   metricValue = readMetric(entry, rule.milestoneMetric)   (F-METRIC)
  │   if metricValue >= rule.threshold -> ADVANCE │
  └───────────────────┬─────────────────────────┘
                      ▼ (threshold met)
  ┌─────────────────────────────────────────────┐
  │ ATOMIC ADVANCE via Persistence (#1):          │
  │   idemKey = "evo:"..id..":1"                  │
  │   UpdateAsync transform (NON-YIELDING):       │
  │     if entry.evoStage >= 1 -> no-op (return prior)
  │     if txLog has idemKey  -> no-op (return prior)
  │     else entry.evoStage = 1; append idemKey   │
  └───────────────────┬─────────────────────────┘
                      ▼ (commit ok)
  ┌─────────────────────────────────────────────┐
  │ fire EvolutionOccurred{id, personality,       │
  │      fromStage=0, toStage=1, evolvedName}     │──► Moment #12 (big celebration)
  │ replicate EvolutionResult (S→C) -> animation  │──► Daily Quests #17 ("evolve 1")
  │ combat boost: next Combatant build (Battle)   │──► UI #13 (evolve anim + new sprite)
  │ production boost: next tick (Idle)            │
  └─────────────────────────────────────────────┘
```

### 2.7 Axis B: Level/XP Progression (orthogonal, gradual; demo-validated)

**Status:** Axis B is **shipped in demo** (commit `36724cf`); this section describes the demo's locked mechanics. Axis A (§2.1–§2.6 work-based milestone) is **independent** — a Brainrot's `level` and `evoStage` are separate fields that progress on different signals.

**Player intent:** *"My Hyper has won a few raids and he's gotten stronger — his bar shows 80 XP toward Level 4, and when he hits Level 4 his HP and damage go up a notch. Same Brainrot, just more capable."* The player thinks in "Brainrot gets better the more I use it in combat." Distinct from Axis A's "Brainrot becomes something else." Level is *combat power*; Evolution is *identity*.

**Model — XP-on-win, threshold-cross levels up, shared stat scaling:**

1. **XP is earned on a combat win** — both Raid Battle (#5) and Field Combat / Pet AI (#25) award `xpPerWin` to each participating Brainrot on a winning outcome. **Losses award no XP** (demo behavior). XP **only** comes from combat wins in v1; no idle XP, no quest XP, no capture XP (those are Axis A milestone-feeders / coin rewards, not XP).
2. **Level-up is threshold-driven.** A Brainrot levels up when its cumulative `xp` reaches the threshold for its next level (F-LEVELUP, §8.3). On level-up, `level += 1`, and `xp` rolls into the residual (subtracts the threshold; the overflow carries forward — no XP lost). Level is **capped at `maxLevel`** (config; demo locks 100).
3. **Combat stat scaling is shared with Battle.** A Brainrot's HP / damage in combat are scaled by **`levelScale(L) = 1 + statGrowthPerLevel * (L - 1)`** — Lv1 = ×1.00, Lv100 = ×8.92 at the demo's `statGrowthPerLevel = 0.08`. This formula is **defined in battle-gdd v1.3 §2.1 / §8.2 F2** and is **identical** in Pet AI (#25); Evolution v1.3 does not re-define it, only references it for context.
4. **Axis B does NOT affect Idle Production** (locked design decision, 2026-05-28). `levelScale(L)` applies to **combat stats only** (HP/damage); idle production rate is unaffected by `level`. Rationale: keeps Axis B as a pure *combat* hook orthogonal to Idle's *production* hooks (personality `prodMult` + factory `factoryLevel` + storage). Documented in idle-production-gdd v1.3 §2.2 as a non-interaction.

**XP-write path (descriptive, current demo behavior — locked as v1):**

```
COMBAT WIN (one of):
  Raid Battle resolved with player attacker-win (Battle #5, planned)
  Pet AI fighter killed a wild Brainrot (Pet AI #25, demo a71e545)
      │
      ▼
FOR EACH winning Brainrot id on the player's side:
  PlayerDataService.update(player, function(data)
    local entry = data.roster[id]
    if not entry then return UNCHANGED end
    entry.xp = entry.xp + Config.xpPerWin
    while entry.xp >= xpToNext(entry.level) and entry.level < maxLevel do
      entry.xp = entry.xp - xpToNext(entry.level)
      entry.level = entry.level + 1
      -- (level-up moment fires here in demo via inline replicate)
    end
    return CHANGED
  end)
```

> **No idempotency key in the current demo path** (the in-session `txLog` is not used for XP increments). This is acceptable for v1 because (a) the combat-win event is fired once by the resolution code (no replay), and (b) over-crediting XP is a low-stakes failure mode (it costs nothing real, unlike a duplicated currency credit). **Future refactor option** (§9): route XP via an Evolution-service event listener (`battle_win` → Evolution applies XP/level + fires `LevelUp`) — would centralize Axis B logic and add idempotency by reusing `txLog`. **Not prescribed in v1.3** — current demo path is the v1 contract.

**State machine (per Brainrot, Axis B):**

```
   [Lv 1, xp=0] --on combat win--> [xp += xpPerWin]
        │                                  │
        ▼                                  ▼
   xp < threshold(L+1) ──► (stay at L, persist xp)
        │
        ▼
   xp >= threshold(L+1) AND L < maxLevel ──► level += 1; xp -= threshold(L+1)
                                              fire LevelUp{id, fromLevel, toLevel}
        │
        ▼
   L == maxLevel ──► (xp clamped or discarded; LEVEL CAP)
```

- Level-up can **cascade** if a single XP grant crosses multiple thresholds (low-XP grants don't, but a future `xpPerWin` bump could) — the `while` loop above handles it. Each level boundary fires its own `LevelUp` event (one per level crossed), so Moments don't get coalesced.
- `LevelUp` is **transient** (server-fires, replicated to client for UI bump, NOT persisted as an "achievement" record — the only persistent record is the new `level` value).

**Interaction with Axis A (work-based Evolution):**

- **Axis A and Axis B are independent.** A Brainrot can be Lv50 unevolved (a lot of combat wins, hasn't hit the work-based threshold) or Lv1 evolved (rare — would require evolving with no combat history, possible via `lifetimeCoins` form on a deployed-but-unfought Brainrot). Most Brainrots progress on both axes over time.
- A milestone metric `"level"` is **available** (Axis A `EvolutionConfig.byPersonality[*].milestoneMetric = "level"`) but **no v1 evolved form uses it**. F-METRIC supports `"level"` for forward-compat (Phase-2 or rebalanced forms can opt in).
- **Reroll** (Personality #2) does NOT reset Axis B — `level`/`xp` are kept across reroll, identical to how Axis A's `evoStage` is kept (E3 logic). The player's combat investment in a Brainrot persists through identity changes.

### 2.8 Why Axis A + Axis B (not one progression system)

Two axes deliberately solve different player questions:

| | Axis A — Evolution (§2.1–§2.6) | Axis B — Level/XP (§2.7) |
|---|---|---|
| **Player Q answered** | "What did my Brainrot *become*?" | "How *strong* is my Brainrot?" |
| **Cadence** | One-shot per Brainrot (single milestone, single transform) | Continuous (every combat win) |
| **Effect** | Identity flip (name/visual/role) + flat multiplier ×1.15 combat, ×1.20 production | Gradual stat scaling (`levelScale(L)`) on HP/damage only |
| **Signal** | Specific work-history metric (coins or wins, per personality) | Generic combat win |
| **Surface** | Big celebration Moment (one per evolve) | Small Moment / number tick (one per level) |
| **Idle relevance** | ✅ Production multiplier (×1.20 at evoStage 1) | ❌ Idle unaffected — combat only (§2.7) |
| **Reset on reroll** | ❌ Stage kept; form re-derives (E3) | ❌ Level/XP kept |
| **Implementation status (2026-05-28)** | **Not started** — formal Axis A service pending | **Shipped (demo)** — direct write via `update()` |

The two axes share **nothing structural** except the roster entry they both annotate — and that is correct: they are different reward shapes for different progressions.

---

## 3. Data Schema

Evolution **adds NO new persisted field.** It reads/writes only structures owned by Persistence #1 (v1.2). The only new artifact Evolution introduces is its **config table** (`EvolutionConfig`, §3.2 / §8) — pure data, not persisted player state.

### 3.1 Persisted fields Evolution reads / writes (all owned by Persistence #1)

| Field (owner) | Type | Default | Evolution's use | Mutated by Evolution? |
|---|---|---|---|---|
| `roster[id].evoStage` (Persistence) | number | 0 | The evolution stage. `0` = unevolved, `1` = evolved (MVP). | **YES** — set to 1 on a committed evolution, via Persistence's atomic `UpdateAsync` + idempotency key. The *only* field Evolution writes. |
| `roster[id].personality` (Personality) | enum | rolled | Selects which `EvolutionConfig` rule (metric + threshold + evolved form) applies. | No (read-only). |
| `roster[id].history.coins` (Persistence; Idle bumps) | number | 0 | `lifetimeCoins` milestone metric (Hyper, Loyal, Lazy). | No (read-only). |
| `roster[id].history.rwon` (Persistence; Raid bumps) | number | 0 | `raidsWon` milestone metric (Rebel, Chaotic). | No (read-only). |
| `roster[id].history.rdef` (Persistence; Raid) | number | 0 | **NOT used as a v1 milestone** (offense-only raids → always 0 in v1). Reserved for Phase-2 defense branch (#20). | No. |
| `roster[id].level` (Persistence; **Battle #5 + Pet AI #25 write via direct `update()`**) | number | 1 | **Axis B (§2.7).** The per-Brainrot level reached via XP. Scales combat stats in **both** Battle (#5, turn-based Raid) and Pet AI (#25, real-time field) via the shared `levelScale(L)` formula. Available as an Axis A milestone metric (`level`), though no v1 evolved form uses it. | No (read-only here — written by Axis B XP system; see §2.7 for the write path). |
| `roster[id].xp` (Persistence; **Battle #5 + Pet AI #25 write via direct `update()`**) | number | 0 | **Axis B (§2.7).** Accumulated XP on this Brainrot (monotonic between level-ups; rolls into next-level threshold per F-LEVELUP). Never decrements outside the level-up roll. | No (read-only here — written by Axis B XP system; see §2.7 for the write path). |
| `PlayerData.txLog` (Persistence) | { [string] = any } | {} | Holds the `evo:<id>:1` idempotency key (anti-double-evolve, Axis A). Owned/managed by Persistence's atomic path. **Axis B XP increments do NOT use `txLog`** (the demo's current path is direct `update()` without an idempotency key — see §2.7 / §9 "future refactor"). | Indirectly (append happens inside Persistence's atomic transform). |

> **Ephemeral, NOT persisted (server memory only):** the transient `Evolving` marker per `id` (race guard, §2.5); the per-session "login backfill already run" flag; any cached `EvolutionConfig` lookups. None of these are save-worthy — the durable truth is `evoStage` + `txLog`.

### 3.2 `EvolutionConfig` — per-personality rule + multiplier VALUES (commented + ranged)

`EvolutionConfig` is config-owned (commented, ranged, versioned per `config-data.md`). It is the **single source of truth** for: which form each personality evolves into, the v1 milestone metric + threshold, and the **`combatMultiplier` (Battle reads)** + **`productionMultiplier` (Idle reads)** per evolved stage. **Zero magic numbers** live in code. Display strings (`evolvedName`, `flavor`) are client-mirrorable for UI; thresholds/multipliers are **read server-side only** for resolution (a tampered client cannot self-evolve).

```lua
-- src/ReplicatedStorage/Shared/Config/EvolutionConfig.lua
--
-- Work-Based Evolution definitions. Edited by designers for balance/content.
-- OWNS: milestone (metric+threshold) per personality, evolved-form names/flavor/visual,
--       and the per-stage combat + production MULTIPLIER VALUES that Battle (#5) and Idle (#3) read.
-- Does NOT own: combat math (Battle), production math (Idle), storage (Persistence).
-- Schema version: 1
return {
    version = 1,

    -- ── GLOBAL ──
    -- The highest evoStage reachable in MVP. 1 = single evolved stage per personality.
    -- Phase 2 (#20) raises this for multi-stage; the engine is parameterized by targetStage already.
    -- Range: 1..5 | Default: 1
    maxEvoStage = 1,

    -- Fallback combat/production multiplier for an UNKNOWN evoStage (defense-in-depth, E6/E7).
    -- MUST be 1.0 so an unrecognized stage NEVER silently buffs/nerfs.
    -- Range: fixed 1.0 | Default: 1.0
    unknownStageMultiplier = 1.0,

    -- ── PER-EVOSTAGE MULTIPLIERS (the VALUES Battle #5 and Idle #3 READ) ──
    -- evoStage 0 = unevolved = 1.0 (no boost). evoStage 1 = evolved.
    -- combatMultiplier  : flat multiplier on ALL derived combat stats (Battle F1stats `evoMult`).
    --                     Battle's BattleConfig.evoStageStatMultiplier MUST equal this map (FLAG-BATTLE §9).
    -- productionMultiplier : flat multiplier on effectiveRate (Idle must multiply this in — FLAG-IDLE §9).
    -- MODEST values (locked decision): evolution is a meaningful but NOT runaway power hook, to limit
    --   raid power-creep. ⚠VALIDATE both via /balance-check + raid balance (§8.4) once content lands.
    -- Range per multiplier: 1.0..2.0 | Defaults below.
    stageMultipliers = {
        [0] = { combatMultiplier = 1.00, productionMultiplier = 1.00 },  -- unevolved: no boost
        [1] = { combatMultiplier = 1.15, productionMultiplier = 1.20 },  -- evolved: +15% combat, +20% production
    },

    -- ── PER-PERSONALITY EVOLUTION RULE (MVP: one milestone -> stage 1) ──
    -- metric values: "lifetimeCoins" (history.coins) | "raidsWon" (history.rwon) | "level" (entry.level).
    --   NOTE: "raidsDefended" (history.rdef) is DELIBERATELY ABSENT as a v1 metric — Raid v1 is
    --   offense-only, so rdef is always 0 (see §2.4). Phase-2 defense branches add it then.
    -- threshold: the metric value at/above which the Brainrot evolves (inclusive).
    -- evolvedName / flavor: display (client-mirrorable). visualAssetId: CONTENT-TBD (cosmetic).
    byPersonality = {
        Hyper = {
            evolvedName    = "Senior Hyper",
            flavor         = "Worked so hard for so long it got promoted.",
            milestoneMetric= "lifetimeCoins",   -- history.coins
            -- Per idea doc (10k coins). Range: 100..10,000,000 | Default: 10000
            threshold      = 10000,
            visualAssetId  = "",                 -- CONTENT-TBD: tie + desk + coffee mug
        },
        Rebel = {
            evolvedName    = "Revolutionary",
            flavor         = "Won enough fights that the others started following it.",
            milestoneMetric= "raidsWon",         -- history.rwon  (REDESIGN: idea doc said "survive 5"; v1 = win 5)
            -- Range: 1..1000 | Default: 5  (idea-doc number 5, metric swapped survive->win for v1)
            threshold      = 5,
            visualAssetId  = "",                 -- CONTENT-TBD: protest banner
        },
        Loyal = {
            evolvedName    = "Guardian",
            flavor         = "Held the line at the factory day after day.",
            milestoneMetric= "lifetimeCoins",    -- REDESIGN: idea doc said "defend 3 raids"; v1 has no
                                                 -- defense metric, so use steady-production (Loyal's v1 role).
            -- Range: 100..10,000,000 | Default: 8000  (slightly under Hyper — Loyal is steady, not fast)
            threshold      = 8000,
            visualAssetId  = "",                 -- CONTENT-TBD: shield
        },
        Lazy = {
            evolvedName    = "Consultant",
            flavor         = "Slacked its way to seniority.",
            milestoneMetric= "lifetimeCoins",    -- Lazy produces -50%, so a LOWER threshold keeps the
                                                 -- grind comparable in wall-clock time to other forms.
            -- Range: 100..10,000,000 | Default: 6000  (lower because Lazy's rate is ~half)
            threshold      = 6000,
            visualAssetId  = "",                 -- CONTENT-TBD: reclining chair + clipboard
        },
        Chaotic = {
            evolvedName    = "Wildcard",
            flavor         = "Caused enough beautiful disasters to become legend.",
            milestoneMetric= "raidsWon",         -- history.rwon (a Chaotic that survives the field is a story)
            -- Range: 1..1000 | Default: 4  (one under Rebel — Chaotic's combat is unreliable, reward sooner)
            threshold      = 4,
            visualAssetId  = "",                 -- CONTENT-TBD: glitch-aura / mismatched suit
        },
    },
}
```

> **`EvolutionConfig.validate()` (boot-time, per `gameplay-systems.md`):** runs once on server start. Asserts every personality in the enum has a `byPersonality` entry (else logs critical + injects a safe no-op rule whose threshold is `math.huge` so that personality simply never evolves rather than crashing — E6); asserts each `milestoneMetric` is one of the known metrics (else treats the rule as never-reachable + logs); clamps each `stageMultipliers[*]` into `[1.0, 2.0]`; forces `stageMultipliers[0] = {1.0, 1.0}`; ensures `unknownStageMultiplier == 1.0`. Numbers live in config; validation lives in code.

### 3.3 Resolution Notes (cross-GDD consistency)

1. **`evoStage` is the canonical field** (persistence v1.2 §3.2: `evoStage: number, default 0`). Evolution advances it; Battle reads it (`evoMult`); Idle will read it (FLAG-IDLE). One field, three consumers, one owner (Persistence storage).
2. **`history.coins` / `history.rwon` are per-Brainrot and monotonic** (persistence §3.2; bumped by Idle §2.9 / Raid). Evolution only **reads** them — it never increments a history counter (avoids double-attribution).
3. **`combatMultiplier` here ≡ Battle's `evoMult`.** Battle **v1.2** §8.1 reads `combatMultiplier` from `EvolutionConfig` (single source of truth); `BattleConfig.evoStageStatMultiplier {[0]=1.0,[1]=1.15}` is a non-authoritative fallback mirror that matches the locked `[1].combatMultiplier = 1.15`. (FLAG-BATTLE §9 ✅ resolved.)
4. **`productionMultiplier` is consumed by Idle v1.2** — Idle's `effectiveRate` (F1) + offline path now multiply in `evoProductionMult(b)` reading `EvolutionConfig.stageMultipliers[b.evoStage].productionMultiplier` (`1.20` at stage 1). This GDD owns the value; Idle owns the mechanic. (FLAG-IDLE §9 ✅ resolved.)

---

## 4. Client-Server Split

| Concern | Server (authoritative) | Client (presentation only) |
|---|---|---|
| Reading the milestone metric (`history.coins`/`rwon`/`level`) | **YES** — from the server roster | Never; sees a replicated progress value for the bar |
| Threshold comparison + decision to evolve | **YES** — server compares against `EvolutionConfig` (server-side numbers) | **NEVER** — client cannot decide it evolved |
| Advancing `evoStage` (atomic + idempotency key) | **YES** — via Persistence `UpdateAsync` | Never touches DataStore |
| `EvolutionConfig` thresholds/multipliers (resolution) | **YES** — read server-side only | May mirror **display** fields (`evolvedName`, `flavor`, icon) for UI only |
| Firing `EvolutionOccurred` + replicating result | **YES** | Receives `EvolutionResult`; plays animation + swaps sprite |
| Progress-bar percentage | Computes the canonical % (F-PROGRESS) and replicates it | Renders the bar; may smoothly interpolate between updates |
| Evolve animation / evolved-form visuals | (Provides the `evolvedName` + visual asset reference) | **YES** — plays the burst, swaps to the evolved model/accessory |

**Authority rule (locked, per `server-scripts.md`):** the **server decides every evolution** and is the only writer of `evoStage`. The client **never** sends "I evolved" — it sends, at most, a benign "show me my evolution progress" read intent (rate-limited; outcome-irrelevant). A tampered client can mis-animate its own screen but **cannot** change `evoStage`, multipliers, loot, or any persisted state. Thresholds/multipliers used for resolution are read **server-side only**; the client's mirrored copy is display-only.

---

## 5. RemoteEvents / Functions

All remotes registered in `ReplicatedStorage/Shared/Remotes` and documented in the remotes manifest. **No Client→Server `RemoteFunction`** (server-hang risk, per project policy). Evolution is fundamentally **server-driven** — it happens automatically when a milestone is crossed; **there is no remote that lets a client cause or claim an evolution.** Refinable by `remotes-networking-specialist`.

### 5.1 Server → Client

| Remote | Type | Payload | Purpose |
|---|---|---|---|
| `EvolutionProgress` | RemoteEvent | `{ id: string, metric: string, current: number, threshold: number, pct: number }` | Updates the per-Brainrot progress bar toward its evolution. Sent **event-driven** when the metric meaningfully changes (on `CoinsCollected` for that Brainrot, on a raid win, on level-up) and on initial load — **not** per-frame. `pct` is the server-computed canonical value (F-PROGRESS). Only sent for **unevolved** Brainrots (an evolved one shows the badge, not a bar). |
| `EvolutionResult` | RemoteEvent | `{ id, personality, fromStage, toStage, evolvedName, visualAssetId }` | Fired **once** when an evolution commits. Triggers the client's evolve animation (burst/glow), the celebratory notification, and the swap to the evolved sprite/accessory. The big payoff moment. |

### 5.2 Client → Server

| Remote | Type | Payload | Validation |
|---|---|---|---|
| `RequestEvolutionProgress` | RemoteEvent | `{ id: string }` (optional — for the roster-detail panel) | **Optional / convenience only.** Rate-limited (≤ 3/sec); server verifies the caller owns `id`; replies with one `EvolutionProgress` for that Brainrot. **Outcome-irrelevant** — it cannot cause an evolution, only re-send the read the client already has. If progress is already proactively pushed, this remote may be omitted entirely (decision below). |

> **DECISION — no "claim evolution" remote; evolution is fully automatic.** Two options were weighed:
> - **(A) Automatic** — the moment the milestone is crossed server-side (on the relevant event), the server evolves the Brainrot and pushes `EvolutionResult`. No player action.
> - **(B) Claim** — the milestone unlocks a "Evolve!" button; the player taps to claim (a C→S `ClaimEvolution{id}` remote).
>
> **Chosen: (A) Automatic.** Rationale: (1) **"attention shapes them"** — the fantasy is the Brainrot *growing through its work*, not the player pressing a button; an automatic transform is more magical and on-theme. (2) **Kid-simple** — no extra step to understand or miss; the celebration just *happens* (and is a bigger Moment for it). (3) **Exploit surface is smaller** — there is no claim remote to spam/forge; the server is the sole trigger. (4) The "evolve 1 Brainrot" Daily Quest (#17) fires naturally off the automatic `EvolutionOccurred`. The trade-off (B's "anticipation of pressing the button") is better served by the **progress bar** (`EvolutionProgress`), which already gives the player the "almost there!" anticipation without a claim step. `RequestEvolutionProgress` remains the only (optional) C→S surface and is purely a read.

### 5.3 Internal server events (NOT network — cross-system decoupling per `gameplay-systems.md`)

Bindable/signal layer (`GameEvents`):

| Event | Payload | Fired When | Listened By |
|---|---|---|---|
| `EvolutionOccurred` | `{ player, id, personality, fromStage, toStage, evolvedName, serverTime }` | An evolution commits (atomic `evoStage` write succeeded) | **Moment #12** (big "your Brainrot evolved!" celebration — primary), **Daily Quests #17** ("evolve 1 Brainrot" objective), Analytics, Fame (P2) |

> **Consumed (not emitted) by Evolution:** `CoinsCollected` (Idle #3 — check `lifetimeCoins` forms for the contributing Brainrots), the winning-raid outcome / `BattleResolved` attacker-win (Raid #6 — check `raidsWon` forms for the attacking team), a level-up event (check `level` forms — none in v1 but wired), and the **login-complete** signal from Persistence (run the one-time backfill scan, §2.2 / E1). Evolution **emits** only `EvolutionOccurred`.

---

## 6. Player-Facing UI

Rendered through the shared UI/HUD framework (#13); **pure presentation** (reads replicated state, plays the server-driven evolve event). Mobile-first. Cartoon, kid-safe, on-theme ("attention shapes them").

1. **Evolution progress bar (per Brainrot).** In the roster/management panel and the deploy picker, each **unevolved** Brainrot shows a slim progress bar toward its evolution: *"Senior Hyper — 6,400 / 10,000 coins (64%)"* (label is the **evolved-form name** so the player anticipates the reward, the metric is shown in plain terms). Driven by `EvolutionProgress`; `pct` is server-computed (F-PROGRESS). A near-complete bar (e.g. ≥ 90%) may pulse to create "almost there!" anticipation.
2. **Evolve animation + notification (the payoff).** On `EvolutionResult`: a punchy, celebratory burst — glow/sparkle around the Brainrot, the old sprite morphs/swaps to the **evolved form**, a big banner: *"Your Hyper became a SENIOR HYPER!"* with the new accessory shown. Brief, colorful, screenshot-friendly (the viral "show me your evolved Brainrot" moment). Surfaced as a top-priority Moment (#12 — one at a time, kid-clarity).
3. **Evolved-form display (the visible record).** An evolved Brainrot shows its **evolved sprite/accessory** everywhere it appears (factory slot, roster, battle arena, deploy picker) and an **evolved badge** (a small icon distinct from the personality badge) so it reads at a glance as "this one evolved." Tapping it in the roster shows its evolved name + flavor ("Held the line at the factory day after day").
4. **Roster filter/sort hook (data only).** Evolution supplies `evoStage` + `evolvedName` so the roster panel (UI #13) can let players filter/sort by "evolved." (Panel owned by UI; Evolution provides the data.)
5. **No "Evolve!" button.** Per the §5.2 decision, evolution is automatic — there is no claim button. The bar fills; the transform happens; the celebration plays. (If a player is offline at the moment of crossing, the celebration plays on next login after the backfill check — E1.)

All surfaces are **event-driven** (progress updates + one result event); **no per-frame networking** — safe on low-end mobile.

---

## 7. Edge Cases & Error States

Covers the `design-docs.md` checklist (zero/max/negative/rapid/lag/disconnect/datastore-down/concurrent). **Minimum 5 exceeded.** Each: trigger → defined behavior.

### E1 — Milestone reached while OFFLINE (or before this system shipped)
**Trigger:** a Brainrot crosses its threshold while the player is offline (e.g. offline-accrued coins, on Collect, push `history.coins` past 10,000), or it was already past-threshold on a roster that predates Evolution's rollout.
**Behavior:** evolution checks are **event-driven online**, but on **login** (after load+migrate completes, persistence lifecycle step 4–5) Evolution runs a **one-time backfill scan** over the whole roster (§2.2): any unevolved Brainrot whose metric already `>= threshold` is evolved immediately via the same atomic+idempotent advance, and its `EvolutionResult` celebration plays on entry (sequenced through Moment #12 one at a time). No milestone is ever silently missed; offline progress is honored. The scan is O(roster ≤ 200) once per session — trivial. (Note: offline coins land in `pendingOffline` and only bump `history.coins` on **Collect** per idle §2.9, so the typical path is "collect on login → `CoinsCollected` event → check"; the login scan is the belt-and-suspenders catch.)

### E2 — Double-trigger / duplicate event / concurrent race (idempotency)
**Trigger:** the same milestone-crossing event is delivered twice (retry, re-fire), or two checks race the same Brainrot (e.g. a raid-win event and the login scan fire near-simultaneously), or a `CollectRequest` is retried.
**Behavior:** the advance is **idempotent at two layers.** (a) The atomic transform first checks `if entry.evoStage >= targetStage then no-op` — once evolved, every later check is a no-op. (b) The transform carries idempotency key `evo:<id>:1`; Persistence's `txLog` check (persistence §2.3) makes a re-fire with the same key return the prior result without a second write. The transient in-memory `Evolving` marker (§2.5) additionally prevents two concurrent checks from both *requesting* the advance in the same tick. **A Brainrot can never double-evolve, never fire two `EvolutionResult` events, never double-apply the multiplier.** This is the same anti-dupe machinery reroll/capture use.

### E3 — Brainrot is REROLLED to a new personality AFTER it evolved
**Trigger:** a player rerolls (Personality #2) an **already-evolved** Brainrot (e.g. a Senior Hyper) into a different personality (e.g. Loyal).
**Behavior (LOCKED decision — evolution is *kept*, not reset, but does NOT re-fit the new personality):**
- `evoStage` is **NOT reset** by a reroll — the Brainrot **stays evolved** (`evoStage` stays 1). The reroll changes `personality`, not the work-history it earned. The **multiplier boosts (combat + production) are stage-keyed, not personality-keyed**, so an evolved Brainrot keeps its `combatMultiplier`/`productionMultiplier` regardless of its current personality.
- The **evolved-form identity** (`evolvedName`/visual) is **resolved live from the *current* personality's rule** for *display*. So a Senior Hyper rerolled to Loyal will display as the **Loyal evolved form (Guardian)** *because it is already at `evoStage = 1`* — its current personality determines which evolved *look/name* it wears, but it does not lose its evolved status.
- **Rationale:** (1) Resetting `evoStage` on reroll would make reroll **punishing** (you'd lose weeks of progress), which is anti-player and would make players afraid to reroll an evolved Brainrot — bad for the reroll monetization surface. (2) Re-deriving the look from current personality keeps the visual **consistent with what the Brainrot *is now*** without erasing the achievement. (3) It is simple + idempotent (no special-case counter math). The work-history counters (`history.coins`/`rwon`) are unchanged by reroll, so if the new personality's metric/threshold differs, the Brainrot is simply **already past it** (stays evolved) — never "un-evolved." A subsequent milestone check for the new personality is a no-op (already `evoStage >= 1`, E2).
- **Reroll mid-battle is rejected** by the existing in-battle lock (personality E4) — orthogonal to evolution.
- (Phase-2 multi-stage note: when `maxEvoStage > 1`, a reroll still keeps the earned stage; only the *form identity* re-derives. No change needed to this rule.)

### E4 — Milestone crossed WHILE the Brainrot is in an active battle/raid
**Trigger:** a raid win pushes `history.rwon` to the threshold for a Brainrot whose `id` is still locked in the just-resolved battle, or a coin collect crosses a threshold during a concurrent raid.
**Behavior:** evolution checks run on the **outcome event** (`BattleResolved` / winning-raid commit), which fires **after** the combatant lock is released (battle §2.9 / §5.3, lock released at `Resolved`). Evolution therefore never advances `evoStage` *inside* the turn loop — the stat boost can never change mid-fight (Battle derives stats at Setup and locks them, battle E4/E10). The Brainrot evolves cleanly **after** the fight it just won; the celebration plays post-result (sequenced after the battle result screen via Moment #12). If a coin-collect check fires while a *different* Brainrot of the same player is mid-raid, that is unrelated — the in-raid Brainrot's `id` is locked, but evolution only writes `evoStage` (not combat state) and does so via the atomic path, so there is no contention with the battle (which holds no DataStore lock — battle E9).

### E5 — DataStore unavailable at the evolve commit
**Trigger:** the atomic `UpdateAsync` advancing `evoStage` fails (DataStore down / budget exhausted) at the moment the milestone is checked.
**Behavior:** the commit is `pcall`-wrapped by Persistence; on failure **nothing mutates** (`evoStage` stays 0, no `EvolutionResult` fired, no Moment) and the check returns "not yet." Because the **milestone metric is monotonic** (`history.coins`/`rwon` never decrease), the Brainrot is still past-threshold, so the **next relevant event OR the next login backfill (E1) re-attempts** the evolution — it is naturally retried with no special retry queue needed. No partial state (no "boost applied but stage not written"), no lost evolution. The player simply evolves a moment later. (Same discipline as idle E11 / persistence E3.)

### E6 — `EvolutionConfig` invalid (missing personality rule, unknown metric, bad multiplier)
**Trigger:** a designer ships a config where a personality has no `byPersonality` entry, a `milestoneMetric` is misspelled (not a known metric), a `threshold` is ≤ 0 or negative, or a `stageMultipliers` value is out of range / `[0]` ≠ 1.0.
**Behavior:** `EvolutionConfig.validate()` runs once at boot (per `gameplay-systems.md`): a **missing personality rule** gets a safe injected rule with `threshold = math.huge` (that personality simply **never evolves**, rather than crashing) + a critical log; an **unknown metric** makes the rule treated as never-reachable + logged; a **threshold ≤ 0** is clamped to `1` (so it doesn't evolve on a fresh 0-history Brainrot by accident) + logged; each `stageMultipliers[*]` is clamped into `[1.0, 2.0]`, `[0]` is **forced** to `{1.0, 1.0}`, and `unknownStageMultiplier` is forced to `1.0`. The system degrades to "no evolution for the bad entry" rather than mis-evolving or crashing. Logged loudly so QA catches it pre-players.

### E7 — `evoStage` is an UNKNOWN value at Battle/Idle read time (forward-compat / corruption)
**Trigger:** a Brainrot's `evoStage` is a value with no `stageMultipliers` entry (e.g. a Phase-2 record with `evoStage = 2` loaded on a v1 build, or a corrupt value).
**Behavior:** **both consumers fall back to `1.0`** — Battle's `evoMult` already documents "unknown stage => 1.0" (battle §8.1/§8.2, E8) and Idle's read must do the same (FLAG-IDLE specifies the same fallback). `EvolutionConfig.unknownStageMultiplier = 1.0` is the single source for this fallback. An unknown stage therefore **never silently buffs or breaks** — it is treated as "no evolution boost" until the config knows the stage. (This is what makes the v1→Phase-2 multi-stage rollout forward-safe: an old client/server gracefully ignores a stage it doesn't recognize.)

### E8 — Zero-input / fresh Brainrot (no history yet)
**Trigger:** a just-captured Brainrot (`history.coins = 0`, `history.rwon = 0`, `evoStage = 0`) is checked (e.g. an empty collect, or the login scan on a brand-new roster).
**Behavior:** `metricValue (0) >= threshold (>0)` is **false** for every rule (validate() guarantees `threshold >= 1`), so no evolution — correct. Progress bar shows 0%. No divide-by-zero (F-PROGRESS guards `threshold > 0`, guaranteed by validate()). A roster of all-fresh Brainrots produces zero evolutions and zero spurious events.

### E9 — Max-input / metric far exceeds threshold (caught up late)
**Trigger:** a Brainrot's metric is **far** past threshold when first checked (e.g. login backfill on a Brainrot that produced 50,000 coins while the system was disabled, threshold 10,000).
**Behavior:** the check is `>=`, so it evolves to stage 1 on the first check regardless of how far past it is (there is **only one stage** in MVP — it cannot "skip" to a higher stage because none exists). `pct` for an evolved Brainrot is not shown (badge instead). When Phase-2 multi-stage lands, the advance is still **one stage per check** (advance to `min(currentStage+1, eligibleStage)`), and the next event/login advances the next stage — no unbounded multi-jump in a single commit (keeps each evolution a distinct, celebrated Moment). No overflow (thresholds are bounded by config ranges; `history` counters are integers well under number limits).

### E10 — Rapid repeated milestone-relevant events (spam collects / rapid raids)
**Trigger:** a player spams Collect or fires raids rapidly, each emitting a check for the same near-threshold Brainrot.
**Behavior:** Collect is rate-limited (idle 1/sec) and raids gated by Raid #6; each check is cheap (one comparison per affected Brainrot). The **first** check that crosses the threshold evolves; **every subsequent check is a no-op** (`evoStage >= 1`, E2). No work amplification, no duplicate events. The check loop touches only the Brainrots an event actually affected (the collect's contributors / the raid team), never the whole roster (except the one-time login scan).

---

## 8. Balancing Parameters

> **This is the core of the GDD.** All values in `EvolutionConfig` (commented, ranged, versioned — §3.2). **Zero magic numbers in code.** The combat multiplier is **read by Battle** (#5) and the production multiplier is **read by Idle** (#3); this GDD is the **owner of those VALUES** (FLAG-BATTLE / FLAG-IDLE §9).
>
> **Assumptions flagged for `/balance-check`** are marked **⚠VALIDATE**.

### 8.1 Locked multiplier VALUES (the cross-system contract)

| evoStage | `combatMultiplier` (Battle reads) | `productionMultiplier` (Idle reads) | Notes |
|---|---|---|---|
| 0 (unevolved) | **1.00** | **1.00** | No boost. |
| 1 (evolved) | **1.15** | **1.20** | Evolution = +15% combat **and** +20% production, plus the cosmetic. **MODEST by design** (locked) to limit power-creep. |
| unknown | **1.00** | **1.00** | Fallback (`unknownStageMultiplier`); E7. |

**Why these magnitudes (not magic numbers):**
- **`combatMultiplier = 1.15` (matches Battle's placeholder exactly).** A flat +15% on all four derived stats is a **meaningful but not dominant** edge — it does not let an evolved 3-team trivialize an un-evolved-equivalent NPC team, so raid difficulty tuning (Raid #6) stays in Raid's hands rather than being warped by evolution. Stacking across a 3-Brainrot team is the realistic ceiling; +15% per member is felt without being a "must-evolve-or-lose" wall. ⚠VALIDATE against NPC defender team strength + raid win-rate targets once Battle species base stats land.
- **`productionMultiplier = 1.20` (slightly higher than combat).** Production is the **safer** surface to reward (it is not zero-sum / PvP-balance-sensitive in v1 — it is a faucet), and a +20% on a *single evolved worker* is a clear, satisfying bump that justifies keeping a favorite deployed long enough to evolve it, **without** breaking Economy's geometric treadmill (it is a flat per-worker factor, not a compounding rate change). ⚠VALIDATE against Economy faucet/treadmill (idle §8.7) — confirm a fully-evolved roster doesn't outpace the cost curves.
- **Production > Combat (20% vs 15%) on purpose:** production is the zero-P2W-safe, balance-tolerant lever, so it carries slightly more of the reward weight; combat is kept the more conservative of the two to protect raid balance (the PvP-bound surface in Phase 2).

### 8.2 Locked threshold VALUES (the v1 milestones)

| Personality → Form | Metric | Threshold | Justification (not magic) |
|---|---|---|---|
| Hyper → Senior Hyper | `lifetimeCoins` | **10,000** | **Direct from the idea doc.** Hyper produces fastest (+30%), so 10k is the "anchor" pace — the benchmark the others are tuned around. At a starting ~0.5 coins/sec/worker (idle §8.1), a Hyper worker (~0.65/sec after +30%) reaches 10k in a few real hours of deployment — a multi-session goal, exactly the "long-term hook" intent. |
| Rebel → Revolutionary | `raidsWon` | **5** | **idea-doc number (5), metric swapped survive→win (§2.4).** 5 raid wins is a several-session combat goal (raids are gated by cost/cooldown, Raid #6). |
| Loyal → Guardian | `lifetimeCoins` | **8,000** | **REDESIGN (no rdef, §2.4).** Slightly under Hyper's 10k because Loyal is *steady* (×1.0) not *fast* (×1.3) — 8k keeps the wall-clock grind in the same ballpark as a Hyper hitting 10k. |
| Lazy → Consultant | `lifetimeCoins` | **6,000** | Lazy produces at ×0.5, so a flat 10k would take ~2× as long as Hyper. 6k compensates so the *time-to-evolve* is roughly comparable across forms (fairness), while staying the lowest coin bar (it's the slacker's path). |
| Chaotic → Wildcard | `raidsWon` | **4** | One under Rebel's 5: Chaotic's combat output is **unreliable** (random moveset, can whiff), so a slightly lower bar compensates for the higher variance of *winning* with a Chaotic on the team. |

> **⚠VALIDATE all thresholds via `/balance-check`:** confirm the **time-to-first-evolution** for each form lands in the intended "first evolution within the first week of regular play" window, and that the production-metric forms (Hyper/Loyal/Lazy) and the raid-metric forms (Rebel/Chaotic) reach evolution on a comparable **wall-clock** schedule (so no personality feels strictly faster/slower to evolve than the design intends). Re-tune once real idle rates + raid cadence are measured.

### 8.3 Formulas (explicit, named variables)

**F-METRIC — read the milestone metric for a Brainrot.**
```
readMetric(entry, metric):
  if metric == "lifetimeCoins" then return entry.history.coins        -- per-Brainrot, monotonic (idle §2.9)
  if metric == "raidsWon"      then return entry.history.rwon         -- per-Brainrot, monotonic (Raid #6)
  if metric == "level"         then return entry.level                -- progression (no v1 form uses it)
  -- "raidsDefended"/history.rdef is intentionally NOT a v1 metric (always 0, §2.4)
  else return 0   -- unknown metric => never reachable (validate() logs this, E6)
```

**F-MILESTONE — does this Brainrot qualify to evolve to stage 1?**
```
shouldEvolve(entry):
  if entry.evoStage >= EvolutionConfig.maxEvoStage then return false        -- already maxed (E2/E9)
  rule = EvolutionConfig.byPersonality[entry.personality]                    -- E6 guarantees a rule exists
  return readMetric(entry, rule.milestoneMetric) >= rule.threshold          -- inclusive >=
  -- threshold guaranteed >= 1 by validate() => a fresh (0-history) Brainrot never qualifies (E8)
```

**F-PROGRESS — progress % toward evolution (server-computed, replicated for the bar).**
```
progressPct(entry):
  if entry.evoStage >= 1 then return 100                                     -- evolved: bar full / show badge
  rule = EvolutionConfig.byPersonality[entry.personality]
  current   = readMetric(entry, rule.milestoneMetric)
  threshold = max(rule.threshold, 1)                                         -- guard /0 (validate() ensures >=1)
  return clamp( floor( current / threshold * 100 ), 0, 100 )                 -- 0..100, integer for UI
  Bounds: 0 <= pct <= 100; never divides by zero (threshold >= 1).
```

**F-ADVANCE — the atomic, idempotent stage advance (the only mutation).**
```
advanceEvoStage(player, id, targetStage):                                    -- targetStage = 1 in MVP
  idemKey = "evo:" .. id .. ":" .. targetStage
  -- via Persistence atomic UpdateAsync (NON-YIELDING transform), idempotency-keyed (persistence §2.3):
  transform(data):
     entry = data.roster[id]
     if entry == nil then return UNCHANGED                                   -- released/invalid id, safe no-op
     if entry.evoStage >= targetStage then return UNCHANGED                  -- idempotent (E2)
     if txLog_contains(data, idemKey) then return UNCHANGED                  -- idempotent (E2)
     entry.evoStage = targetStage
     txLog_append(data, idemKey)
     return CHANGED
  on CHANGED: fire EvolutionOccurred + replicate EvolutionResult (§5)
  on UNCHANGED/idempotent: no event, no animation (already evolved)
```

**Multiplier reads (defined here, applied by the consumers — NOT re-implemented here):**
```
combatMult(entry)     = EvolutionConfig.stageMultipliers[entry.evoStage].combatMultiplier
                        ?? EvolutionConfig.unknownStageMultiplier   (= 1.0, E7)   -- Battle F1stats `evoMult`
productionMult(entry) = EvolutionConfig.stageMultipliers[entry.evoStage].productionMultiplier
                        ?? EvolutionConfig.unknownStageMultiplier   (= 1.0, E7)   -- Idle effectiveRate factor (FLAG-IDLE)
```

**F-LEVELUP — XP threshold for the next level + apply XP grant (Axis B, §2.7).**
```
xpToNext(L):                                                                     -- XP needed to reach level L+1
  return xpCurveBase * L                                                          -- demo: linear curve (xpCurveBase=100):
                                                                                   --   Lv1→2 = 100, Lv2→3 = 200, ..., Lv99→100 = 9900
  Bounds: L in [1, maxLevel-1]; threshold = 100..9900 at demo defaults.

applyXpGrant(entry, xpAmount):                                                    -- called from combat-win path (§2.7)
  if entry.level >= maxLevel then return UNCHANGED                                -- level cap; XP simply not credited
  entry.xp = entry.xp + xpAmount
  levelsGained = 0
  while entry.xp >= xpToNext(entry.level) and entry.level < maxLevel do
    entry.xp    = entry.xp - xpToNext(entry.level)                                -- roll residual into next bucket
    entry.level = entry.level + 1                                                 -- one level boundary crossed
    levelsGained = levelsGained + 1
    -- fire LevelUp{id, fromLevel = entry.level - 1, toLevel = entry.level} per boundary
  end
  return CHANGED  if (xpAmount > 0 or levelsGained > 0)  else UNCHANGED
  Notes:
   - Cascade-safe (handles a single grant that crosses multiple thresholds).
   - At cap: XP grants beyond maxLevel are discarded (no overflow xp persisted).
   - Demo path: this runs INSIDE PlayerDataService.update(...) (no separate idemKey in v1).
   - Future-refactor path (§9): same logic moved into an Evolution event listener with txLog idempotency.

levelScale(L) = 1 + statGrowthPerLevel * (L - 1)
  Shared with Battle #5 (battle-gdd v1.3 §2.1 / §8.2 F2) and Pet AI #25.
  Defined HERE (Evolution OWNS the parameter value via §8.5); applied by combat consumers.
  Bounds: L in [1, maxLevel]; at demo defaults (statGrowthPerLevel = 0.08, maxLevel = 100): Lv1 = 1.00, Lv50 = 4.92, Lv100 = 8.92.
```

### 8.4 Assumptions to validate via `/balance-check` + raid-balance coordination (⚠)
1. **`combatMultiplier = 1.15`** — ⚠VALIDATE that a 3-member evolved team vs the NPC Rival Startup defender teams (Raid #6) does not warp the intended raid win-rate; coordinate with **Raid #6** loot/difficulty tuning and **Battle #5** species base stats. **Power-creep watch:** +15% combat is intentionally modest precisely to keep evolution *additive*, not *mandatory*, for raid success.
2. **`productionMultiplier = 1.20`** — ⚠VALIDATE against **Economy/Idle** treadmill (idle §8.7): a fully-evolved roster of deployed workers must not outpace the geometric upgrade cost curves (factory 200/1.35 etc.). Confirm it stays a satisfying bump, not an inflation break.
3. **All 5 thresholds (10k/5/8k/6k/4)** — ⚠VALIDATE time-to-first-evolution + cross-form wall-clock parity (§8.2 note) once real idle rates and raid cadence exist.
4. **`maxEvoStage = 1` ceiling** — confirm the single-stage feel is "rewarding enough" to be a weeks-long hook in playtesting; if too thin, Phase-2 multi-stage (#20) is the planned extension (the engine is already parameterized for it).

### 8.5 Locked Level/XP VALUES (Axis B — the demo-validated contract)

These are the demo's currently-shipping values (`DemoConfig.progression`, commit `36724cf`), locked as v1 by this GDD. They will graduate from `DemoConfig` into a production `EvolutionConfig.progression` block (or equivalent) without value changes when the formal Evolution service ships. Battle (#5) and Pet AI (#25) read `statGrowthPerLevel` + `maxLevel` for `levelScale(L)`; Evolution owns the values.

| Parameter | Locked value | Range (config) | Source | Notes |
|---|---|---|---|---|
| `xpPerWin` | **50** | 1..1000 | `DemoConfig.progression.xpPerWin` | XP awarded per combat win, per participating Brainrot. Shared by Battle (#5) raid-win path + Pet AI (#25) field-win path. **⚠VALIDATE** vs. raid cadence (Raid #6) and field-combat density (Pet AI #25) — the *time-to-first-levelup* should land around 2 combat wins for a fresh Lv1 (matches the demo: 2 × 50 = 100 = Lv2 threshold). Re-tune if level-up cadence feels too fast/slow once both consumers exist. |
| `xpCurveBase` | **100** | 10..10000 | `DemoConfig.progression.xpCurveBase` | XP curve scalar; `xpToNext(L) = xpCurveBase × L` (linear). At demo defaults: Lv1→2 = 100 XP, Lv50→51 = 5000 XP, Lv99→100 = 9900 XP. **Curve is intentionally linear (not geometric)** so leveling stays paced across the cap; geometric curves would gate Lv100 behind an unreasonable late-game grind for a 100-level cap. |
| `statGrowthPerLevel` | **0.08** (= +8% per level) | 0.01..0.50 | `DemoConfig.progression.statGrowthPerLevel` | The per-level combat-stat multiplier increment in `levelScale(L)`. At Lv1 = ×1.00; at Lv100 = ×8.92. **MODEST by design** to keep raid balance from being warped by Lv100 outliers (a Lv100 team is ~9× a Lv1 team in stats — significant but not gamebreaking for a long-term hook). ⚠VALIDATE in coordination with Raid #6 difficulty + Battle #5 species base stats. |
| `maxLevel` | **100** | 10..500 | `DemoConfig.progression.maxLevel` | Hard cap on `level`. XP grants beyond cap are discarded (no overflow persists). Demo locks 100 as a multi-week ceiling that respects the linear curve (total XP to cap = `Σ(xpCurveBase × L for L=1..99)` ≈ 495,000 XP ≈ 9,900 combat wins at `xpPerWin=50`). |

> **Where these values LIVE in code today:** `src/ReplicatedStorage/Shared/Demo/DemoConfig.luau` §progression (demo). On graduation to production, they move to `EvolutionConfig.progression` (or `src/ReplicatedStorage/Shared/Config/EvolutionConfig.luau` Axis B sub-block) with identical values and the same range comments.

> **Cross-system contract (locked):** Battle #5 and Pet AI #25 BOTH read `statGrowthPerLevel` and `maxLevel` for `levelScale(L)`; neither holds its own copy. If a future tuning pass changes `statGrowthPerLevel`, **both consumers respond identically** (no drift). Evolution owns the value; combat systems own the application.

---

## 9. Integration Points

### Depends On
- **#1 Data Persistence & Roster Core** (`persistence-gdd.md` v1.4): owns `evoStage` (the field Axis A writes via the **atomic `UpdateAsync` + idempotency key** path, §2.3) AND `level` / `xp` (the fields Axis B writes via direct `update()` from combat consumers, §2.7), the per-Brainrot `history{coins, rwon, rdef, fame}` counters (milestone sources for Axis A), and the player-level lifetime counters. Evolution adds **no** schema. The `txLog` guarantees idempotent (un-double-triggerable) Axis A evolution; Axis B does not currently use `txLog` (acceptable per §2.7 risk analysis).
- **#2 Personality System** (`personality-gdd.md` v1.1): owns the `personality` enum that **keys** which evolution rule (metric/threshold/form) applies. Evolution listens to `PersonalityChanged` for the reroll-after-evolve rule (E3 — evolved status is *kept*, form *re-derives* from current personality). Reroll also preserves Axis B `level`/`xp` (§2.7).
- **#3 Idle Production** (`idle-production-gdd.md` v1.2): bumps `history.coins` on Collect (idle §2.9) — the `lifetimeCoins` milestone source — and fires `CoinsCollected` (Evolution's Axis A check trigger). **➡ See FLAG-IDLE below.** Axis B `level` has **no idle effect** (locked 2026-05-28, §2.7).
- **#5 Battle System** (`battle-gdd.md` v1.2 / v1.3): **Axis A** — reads `entry.evoStage` and applies `evoStageStatMultiplier` (`evoMult`) as a flat combat-stat multiplier; fires `BattleResolved` (raid-win context). **➡ See FLAG-BATTLE below.** **Axis B** — Battle is an XP source: on a winning raid, Battle writes `+xpPerWin` to each participating Brainrot's `xp` and applies F-LEVELUP via Persistence's atomic `update()` (§2.7 XP-write path). Battle reads `statGrowthPerLevel` + `maxLevel` from Evolution's §8.5 for `levelScale(L)`.
- **#6 Raid v1** (`raid-gdd.md` v1.1): bumps `history.rwon` on a winning raid (the `raidsWon` milestone source, offense-only in v1) and provides the winning-raid outcome event Evolution checks against. (Raid v1 leaves `history.rdef = 0` — the reason for the §2.4 milestone redesign.) Raid is also indirectly an Axis B XP source (raids resolve via Battle #5, which writes XP).
- **#25 Field Combat / Pet AI** (`pet-combat-gdd.md` planned; demo `a71e545`): **Axis B XP source** — on a Pet AI fighter winning a field combat, Pet AI writes `+xpPerWin` to the participating Brainrot's `xp` via the same Persistence atomic `update()` path Battle uses (§2.7). Pet AI also reads `statGrowthPerLevel` + `maxLevel` for `levelScale(L)` — **identical** application to Battle, no drift. **Axis A** — Pet AI does NOT trigger Axis A milestones in v1 (no per-Brainrot `history.rwon` bump from field combat; only raid-win bumps `rwon`); a future rebalance may unify field+raid `rwon` accounting if Rebel/Chaotic Axis A timings drift.

### Depended On By
- **#12 Moment System**: primary listener of `EvolutionOccurred` — surfaces the big "your Brainrot evolved!" celebration (one Moment at a time). **Evolution emits a Moment on every evolve.**
- **#17 Daily Quests**: the "evolve 1 Brainrot" objective increments off `EvolutionOccurred`.
- **#13 UI/HUD**: owns the progress-bar / evolve-animation / evolved-form-display surface (§6); Evolution supplies `EvolutionProgress`/`EvolutionResult` + the data (`evoStage`, `evolvedName`, `visualAssetId`).
- **#20 Multi-Branch Evolution (Phase 2)**: extends this single-stage model; cheap **only because** lifetime counters + `evoStage: number` (multi-stage-ready) + the `targetStage`-parameterized advance already exist.

### ⚠ CROSS-SYSTEM ACTIONS (for the owners to reconcile — Evolution owns the VALUES, not the mechanics)

> **FLAG-BATTLE — ✅ RESOLVED (Battle v1.2).** Battle now sources `evoMult` from `EvolutionConfig.stageMultipliers[entry.evoStage].combatMultiplier` (single source of truth); `BattleConfig.evoStageStatMultiplier {[0]=1.0,[1]=1.15}` is demoted to a non-authoritative reference/fallback mirror that matches the locked value (1.15). Unknown stage → `unknownStageMultiplier = 1.0` (E7) on both sides. No numeric change — confirmation only.

> **FLAG-IDLE — ✅ RESOLVED (Idle v1.2).** Idle `effectiveRate` (F1) and the offline path (`computeOfflineRate`) now multiply in `evoProductionMult(b) = EvolutionConfig.stageMultipliers[b.evoStage].productionMultiplier (?? unknownStageMultiplier = 1.0)`, reading `b.evoStage` from the roster. Idle holds no copy of the value (`1.20`) — it reads `EvolutionConfig`. This GDD owns the VALUE; Idle owns the mechanic of multiplying it in. Final inserted formula:
> `effectiveRate(b) = (baseRatePerWorker + levelRateBonus*(b.level-1)) * personalityMult(b) * chaoticCycleFactor(b) * moraleFactor(b) * evoProductionMult(b) * (paused(b) ? 0 : 1)`

> **Note on ownership boundary (locked):** Evolution owns the **milestones + evolved forms + multiplier VALUES** and the **decision to advance `evoStage`**. **Battle** owns the combat mechanic (how `evoMult` is applied to stats). **Idle** owns the production mechanic (how `productionMultiplier` enters the rate). Neither consumer re-defines the numbers; both read them from `EvolutionConfig` (the single source of truth) with a `1.0` fallback for unknown stages.

---

## Open Questions

1. **Visual asset content (TBD).** Every `visualAssetId` is empty pending content production (the tie/banner/shield/chair/glitch-aura models + accessories). **Does the evolve animation need per-form bespoke art, or a shared "evolution burst" + accessory swap?** (Recommend shared burst + per-form accessory for solo-dev scope.) → content-director / artist.
2. ✅ **RESOLVED — Reroll-after-evolve (E3): KEEP evolved status; re-derive look from current personality.** User confirmed: a reroll does **NOT** reset `evoStage` — the Brainrot stays evolved (the stage-keyed combat + production multipliers persist), and only the evolved-form **look/name** re-derives from the *new* personality (a Senior Hyper rerolled to Loyal displays as the Loyal evolved form, still at `evoStage = 1`). The alternative ("freeze the look at personality-at-evolve-time") is rejected — re-derive is simpler, needs no extra stored field, and is the locked E3 behavior.
3. **`combatMultiplier` single-source vs mirrored copy (FLAG-BATTLE).** Should Battle read `EvolutionConfig` directly, or keep a synced copy in `BattleConfig`? (Recommend direct read for one source of truth.) → lead-programmer + Battle owner.
4. **Time-to-first-evolution targets (⚠ §8.4).** The thresholds assume an intended "first evolution within ~the first week of regular play." Needs a measured target from playtest/economy modelling to lock. → economy-designer / game-designer + `/balance-check`.
5. **Should `level` ever be a v1 milestone?** No v1 form uses it (the config supports it). If a 6th "leveling" form or a secondary milestone is wanted, the metric is ready. → game-designer.
