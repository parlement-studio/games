# Battle System GDD (Auto, Turn-Based, Spectatable — for Raid #6) — **ARCHIVED**

> ## 🚫 ARCHIVED — CANCELLED by Vision Pivot 2026-05-29
>
> **This GDD is no longer active.** It is preserved here for historical reference and audit trail integrity.
>
> **Why archived:** The Vision Pivot decision on **2026-05-29** cancelled the turn-based combat engine that this GDD specifies. All combat in the new vision is **real-time via Pet AI #25** (Vision Pivot Decision 4). Turn-based has no remaining caller — the only consumer (Raid #6 vs NPC Rival Startups) is itself cancelled and replaced by the new Boss System (3-tier, also pivoted to Pet AI engine).
>
> **What carried forward (migration to `pet-combat-gdd.md`):**
> - The `levelScale(L) = 1 + statGrowthPerLevel * (L - 1)` formula → owned by Pet AI §8 (was Battle §2.1 / §8.2 F2)
> - The 5 personality battle behavior tags (`act_first_mistarget`, `berserk_when_last`, `random_moveset`, `bodyguard`, `counter_double`) → consumed by Pet AI dispatch
> - The `KnockedOut` terminal-state vocabulary lock → Pet AI vocabulary lock
>
> **What was cancelled (no migration):**
> - The deterministic seeded RNG / event-log / spectatable replay model
> - The NPC Rival Startups (Grind Corp / Chill Collective / The Glitch Gang / Pivot Ventures) as raid targets
> - `BattleService.resolve()` signature
> - `BattleConfig` (turn engine constants)
>
> **Audit anchor:** `design/decisions/2026-05-29-vision-pivot.md` (Vision Pivot Doc).
> **Replacement systems:** `pet-combat-gdd.md` v1.0 (pillar combat engine) + `boss-system-gdd.md` (planned, 3-tier boss structure).
> **Systems-index current state:** `design/gdd/systems-index.md` v3.0 (#5 marked CANCELLED with stable identifier retention).
>
> **Do not extend, modify, or implement against this GDD.** If a future design references a concept here, source from the replacement GDDs above.
>
> ---
>
> *(Original content preserved below for historical reference.)*

**Version**: 1.3 (ARCHIVED — superseded by Vision Pivot 2026-05-29)
**Last Updated**: 2026-05-28 (pre-pivot)
**Author**: systems-designer
**Status**: ARCHIVED (was: Draft)

> **Changelog v1.3 (2026-05-28)**: **Phase A scope narrowing + cross-system contracts locked.**
> - **§1 scope narrowed:** Battle is now explicitly scoped as the **turn-based combat engine for Raid (#6)** vs NPC Rival Startups. **Field combat against wild Brainrots in the hub world is owned by Pet AI (#25)** — a separate combat layer with its own GDD (`pet-combat-gdd.md` planned). The two coexist: Battle owns Raid combat (turn-based, deterministic replay); Pet AI owns field combat (real-time, tick-based). Same roster, same personality, same `levelScale(L)` — different resolution model.
> - **Parameter rename:** `BattleConfig.statGrowth` → **`statGrowthPerLevel`** (and `statGrowthByStat` → `statGrowthPerLevelByStat`) — aligns with the demo's `DemoConfig.progression.statGrowthPerLevel` and Evolution v1.3 §8.5 naming. **No numeric change** (still 0.08 default).
> - **§2.1 / F2 levelScale formula** is now explicitly marked as a **shared cross-system contract with Pet AI #25**: `levelScale(L) = 1 + statGrowthPerLevel * (L - 1)` is **identical** in both Battle (turn-based) and Pet AI (real-time). Both consumers read `statGrowthPerLevel` + `maxLevel` from Evolution v1.3 §8.5 (single source of truth via `EvolutionConfig`). No drift permitted.
> - **§2.4 personality battle tags** marked as **shared cross-system contract**: the five tags (`act_first_mistarget` / `berserk_when_last` / `random_moveset` / `bodyguard` / `counter_double`) and their params (`mistargetChance`, `berserkAttackMultiplier`, etc.) are defined in Personality #2 §8 and consumed identically by **both** Battle (turn-based dispatch) and Pet AI (real-time AI dispatch). When Pet AI #25 wires the tags, no new tag definitions are needed; only the runtime dispatch differs (turn-tick vs damage-tick). Currently Pet AI (demo `a71e545`) only applies the damage multiplier — full tag wiring pending.
> - **§9 Integration Points** updated: added Pet AI (#25) under Depended On By with the shared-formula/shared-tag annotations; refreshed Persistence ref to v1.4.
>
> **Changelog v1.2**: `evoStageStatMultiplier` values now **sourced from `EvolutionConfig`** (`EvolutionConfig.stageMultipliers[stage].combatMultiplier`) — **FLAG-BATTLE resolved, no numeric change**. Evolution #8 (`evolution-gdd.md` ≥ v1.1) is the **single source of truth** for the per-stage combat multiplier; Battle reads it via `entry.evoStage` rather than holding an authoritative copy. Stage-1 = **1.15** is confirmed (matches Evolution's locked `combatMultiplier`); the previous `{[0]=1.0,[1]=1.15}` in `BattleConfig` is now documented as a non-authoritative reference/fallback, not a second owner. Integration Points #8 updated accordingly.

> **Changelog v1.1**: Open Questions 1–5 resolved by user. Key change: **Work-Based Evolution boosts combat** — added `evoStageStatMultiplier` (F1stats `evoMult`) to the stat-derivation formula + `BattleConfig` (placeholder values; final curve owned by Evolution #8, which must also add the parallel production multiplier to Idle #3).

> **Parent GDD**: `design/gdd/systems-index.md` — System **#5 (Battle System, P1 core combat, blocks Raid #6)**.
> **Source of Truth**: `idea/brainrotInc.md` (battle behavior per personality; "Battle is turn-based with personality-influenced skills"); locked pre-production context.
> **Governing standards (NON-NEGOTIABLE)**: `.claude/rules/design-docs.md` (9 sections, explicit formulas, ≥5 edge cases, version header), `.claude/rules/config-data.md` (commented config + ranges + version field), `.claude/rules/gameplay-systems.md` (zero magic numbers, config-driven, state machine, event-driven), `.claude/rules/server-scripts.md` (server-authoritative, never trust client, pcall, rate limit), `.claude/rules/remotes.md` (validate every handler, no C→S RemoteFunction, delta bandwidth).

> **Depends On**:
> - **#1 Data Persistence & Roster Core** (`persistence-gdd.md` v1.2) — OWNS the `id`-keyed roster, the `BrainrotEntry` shape (`id`, `species` number, `personality` enum, `level`, `xp`, `evoStage`, `history{coins,rdef,rwon,fame}`), and the atomic write path. **`iv` is DROPPED from the launch schema** — combatant stats are derived from `species` base + `level` + `personality`, NOT from IV. Battle writes `history.rwon`/`history.rdef` (and the player-level `raidsWon`/`raidsDefended`) via Persistence's atomic op.
> - **#2 Personality System** (`personality-gdd.md` v1.1) — OWNS the trait definitions and the **battle behavior tags** (`act_first_mistarget`, `berserk_when_last`, `random_moveset`, `bodyguard`, `counter_double`) + their params in `PersonalityConfig`. Battle **implements the mechanics for those tags**; Personality only supplies `{tag, params}` via `getBattleBehavior(id)`. Battle emits `PersonalityMoment` events (`hyper_mistarget`, `lazy_berserk`, `loyal_blocked`, `rebel_countered`, etc.) for clutch moments.
> - **#9 Economy** (`economy-gdd.md` v1.1) — Battle holds **NO currency**. Raid (#6) owns cost/loot. Battle returns an outcome only.

> **Depended On By**:
> - **#6 Raid v1 (NPC Rival Startups)** — the sole caller of the battle engine. Sends `attackerTeam` (3) vs a config-defined NPC `defenderTeam`; receives the outcome (winner/timeline/survivors/casualties) and owns cost/loot/target selection.
> - **#8 Work-Based Evolution** — reads `history.rwon`/`history.rdef` milestones that Battle increments (via Persistence) for raid-survival/win evolution branches.
> - **#12 Moment System** — listens to the `PersonalityMoment`/`BattleMoment` events Battle emits for clutch-win recaps.
> - **#13 UI/HUD** — owns the spectate view that replays Battle's timeline.

> **Cross-GDD consistency lock (no contradictions introduced — per `design-docs.md`):**
> - **Battle is the mechanic + stat-model + replay owner.** Raid (#6) owns cost/loot/target. Personality (#2) owns trait definitions (tags+params). Persistence (#1) owns storage + roster shape. **Species base-stat VALUES are content** (config) filled later — this GDD defines the schema and marks the numeric values **content-TBD**.
> - **No `iv`.** Persistence v1.2 §3.2 dropped `iv` from the launch schema and explicitly deferred per-Brainrot stat design "to when the Battle GDD is written." This GDD makes the launch call: **stats are derived from `species` base + `level` scaling + `personality` modifier — there is no per-Brainrot IV at launch.** (A future per-Brainrot variance roll is trivially addable via a v1→v2 `migrate()` step plus a new `BattleConfig` term — see §9 Open Questions.)
> - **Battle state is ephemeral.** Persistence v1.2 §3.2 declares "in-flight battle/raid combat state — server memory only; only *results* persist." Battle never persists combat state; only the outcome (`history.rwon`/`history.rdef`, player `raidsWon`/`raidsDefended`) is written, via Persistence's atomic path.
> - **Personality battle tags/params are read verbatim** from `PersonalityConfig.traits[*].battleBehaviorTag` + the sibling params (`mistargetChance`, `defenseMultiplier`, `berserkAttackMultiplier`, `randomFromAnyMoveset`, `bodyguardAllyHpThreshold`, `bodyguardDamageTakenFraction`, `counterDamageMultiplier`). Battle never re-defines these numbers (personality-gdd §8). Battle owns only the combat-math constants (`BattleConfig`).
> - **Compliance (locked, world-builder).** Player-facing and code-facing terminology uses **"knocked out" / "fainted" / "out of office"** — never "die/kill/blood." Cartoon style. The combatant terminal state is named **`KnockedOut`**.

---

## 1. Overview & Purpose

The Battle System is the **deterministic, turn-based combat engine** that resolves a Raid fight between two teams of Brainrots and produces a **replayable timeline**. It is not a standalone game mode: at launch its **only caller is Raid (#6)**, which sends an attacking team of 3 against an NPC Rival Startup's defending team and asks "who wins, and what happened?" Battle answers with a winner, a tick-by-tick event log, and the surviving/knocked-out rosters. The player **does not play** the battle — it is **AUTO** (no input during the fight); the player **spectates a live cartoon replay** of a fight the server already decided.

> **Scope clarification (v1.3, post-demo reconciliation 2026-05-28):** This GDD defines the **turn-based** combat engine used by Raid (#6). It is **NOT** the engine used for **real-time hub-world combat** against wild Brainrots — that is **Field Combat / Pet AI (#25)**, a separate combat layer with its own GDD (`pet-combat-gdd.md` planned; reference impl in demo `a71e545`). The two combat layers **coexist**:
>
> | | **Battle (#5, this GDD)** | **Pet AI (#25, separate GDD)** |
> |---|---|---|
> | Context | Raid (3v3 team vs NPC Rival Startup) | Field (1 summoned pet vs wild Brainrot) |
> | Resolution model | **Turn-based**, fully pre-simulated, deterministic replay | **Real-time**, tick-based damage with movement/formations |
> | Caller | Raid (#6) only | Player tap on `SummonFighter` remote |
> | Stat scaling | `levelScale(L)` — shared (this GDD §2.1) | `levelScale(L)` — **identical**, read from same param |
> | Personality battle tags | All five tags wired (§2.4) | All five tags **must be wired identically** (Pet AI obligation; currently only damage mult) |
> | Result | Persisted: `history.rwon`/`rdef`, `raidsWon`/`raidsDefended` | Persisted: `xp` (+`xpPerWin` per win — §2.7 evolution-gdd Axis B) |
>
> The shared layers (stat formula, personality tags, level cap) make a Lv50 Hyper feel like the same Brainrot in both contexts — only the resolution model differs. **Single source of truth for parameter values** is Evolution v1.3 §8.5 (Axis B Level/XP) — Battle and Pet AI both read; neither owns.

It is **P1 (core combat) and blocks Raid (#6)** because:

1. **It is the combat substrate the whole social loop rests on.** Raiding — the game's social engine — is "send a team, watch it fight, win loot." Without a correct battle engine there is no raid, no raid-survival evolution, no revenge loop (Phase 2).
2. **It is the most logic-heavy MVP system (Risk H).** Turn engine + 5 personality behavior hooks + deterministic replay is the hardest piece of MVP logic. Getting determinism right at design time prevents an entire class of desync/exploit/QA bugs later.
3. **It is where the personality pillar is felt in *fast motion*.** Idle Production (#3) surfaces personality slowly (a Hyper burns out over minutes); Battle surfaces it in seconds — "Rebel counter!", "Loyal protected the team!", "Hyper missed!" These are the screenshot-worthy clutch moments.

### Why deterministic replay (load-bearing — anti-exploit + QA)

The engine is **server-authoritative with deterministic replay**:

- The server runs the **entire** battle simulation from a **seeded RNG**, producing a deterministic **event log / timeline**. The server then sends that timeline to the client, which **replays it as animation**. The client is a **pure viewer** — it never computes damage, never rolls a die, never decides an outcome.
- **Determinism = reproducibility.** Given the same `(attackerTeam, defenderTeam, seed)`, the simulation produces the **bit-identical** timeline every time. This is required for:
  1. **Anti-exploit.** A tampered client cannot change the result because the result is computed entirely server-side before any animation plays. The worst a hacked client can do is animate the replay wrong on its own screen — the persisted outcome (loot, `history`) is the server's.
  2. **QA / TestEZ.** The whole engine is a **pure function** of its inputs. Tests assert "team A vs team B with seed 12345 → attacker wins in 7 turns, casualties = {…}" with no flakiness. Balance changes are validated by re-running fixed seeds (`/balance-check`).
  3. **Bandwidth.** We ship a compact **action log** (deltas: "combatant X uses skill S on Y for D damage"), not full state every tick — the client reconstructs state by applying the log. (§5)

**Player intent:** *"I sent my three best guys to raid Grind Corp. Now I'm watching them fight — come on, my Loyal one is tanking, the Rebel just countered for double, YES we won and stole their coins!"* The player thinks in terms of "did my team win, and did something cool happen." They never think about seeds, turns, or formulas — those are surfaced as a punchy cartoon brawl with personality callouts and a win/lose screen.

What this GDD does **NOT** do: it does not own currency, cost, loot, or target selection (Raid #6); it does not define personality traits/numbers (Personality #2); it does not own the roster shape or storage (Persistence #1); and it does not fill in species base-stat **values** (content/config, TBD). It owns *the combatant stat model, the move/skill system, the turn engine, the personality-tag mechanics, the deterministic seeded RNG, the event-log/timeline format, and the result contract.*

---

## 2. Core Mechanics

### 2.1 Combatant model (derived stats — NO `iv`)

A **Combatant** is the ephemeral in-battle representation of one Brainrot. Battle builds it at setup from the persisted `BrainrotEntry` (Persistence #1) and **derives every stat** — nothing about the combatant is persisted. Four core stats: **HP**, **ATK**, **DEF**, **SPD**.

```
Combatant <- derive( BrainrotEntry, BattleConfig )

  speciesBase = BattleConfig.species[entry.species].base   -- {hp, atk, def, spd}  (content-TBD values)
  level       = entry.level                                 -- from roster (Persistence)
  personality = entry.personality                           -- enum (Personality #2)

  -- Each stat: species base, scaled by level, then modified by personality (defense only at launch).
  HP  = floor( speciesBase.hp  * levelScale(level, "hp")  )
  ATK = floor( speciesBase.atk * levelScale(level, "atk") )
  DEF = floor( speciesBase.def * levelScale(level, "def") * personalityDefMult(personality) )
  SPD = floor( speciesBase.spd * levelScale(level, "spd") )
```

- **`species` (number)** indexes `BattleConfig.species` — the species base-stat table. **Base-stat VALUES are content (TBD)**; this GDD defines only the schema (§3.2) and a documented placeholder row so the engine compiles.
- **`level` scaling** is a single config formula (`levelScale`, Formula **F2**), the same growth applied to all four stats unless a per-stat growth override is set in config (`statGrowthPerLevelByStat` map). The formula is `levelScale(L) = 1 + statGrowthPerLevel * (L - 1)` — **identical to Pet AI #25's stat scaling** (shared cross-system contract per v1.3 §1 scope note). No IV — two same-species, same-level, same-personality Brainrots derive **identical** stats by design (variance is a Phase-2 add — see §9). **Parameter values (`statGrowthPerLevel`, `maxLevel`) are OWNED by Evolution v1.3 §8.5**; Battle reads via `EvolutionConfig` (single source of truth, mirrored optionally in `BattleConfig` for fallback only).
- **`personality` modifier at launch** affects **DEF** (Lazy's `defenseMultiplier`, default 1.75; all other personalities 1.0). All *other* personality battle effects are **behavioral** (turn order, targeting, counters, redirects, berserk) and are applied by the turn engine via tags (§2.4 / F4), not baked into the derived stat block. This keeps the stat block clean and the behaviors decoupled.
- **Derived, never stored.** The combatant block (current HP, status, the moveset instance) lives in server memory for the battle's duration only. Persistence stores only the outcome (§3.4).

### 2.2 Move / skill system (kid-simple, config-driven)

The locked context requires "simple for kids." The model: **every species has exactly two moves — a `basic` attack and one `special`** — defined in `BattleConfig.species[*].moves`. A combatant's **moveset** is `{ basic, special }`.

1. **`basic`** — always available, low-to-moderate `power`, no cooldown. The default action.
2. **`special`** — higher `power`, gated by a **cooldown** (`cooldownTurns`) so it is not spammed. Available on turn 1, then every `cooldownTurns` turns after use.
3. **Move definition** (config): `{ id, name, power, cooldownTurns, targeting }`. `power` is the damage multiplier on ATK (Formula **F1**). `targeting` is `"single"` (one enemy) at launch (AoE/heal reserved for Phase 2 — schema allows it, MVP uses `single`).
4. **Move selection per turn (the simple AI):** on a combatant's turn, the engine picks its move deterministically: **use `special` if off cooldown, else `basic`**. (This is the baseline; personality tags can override selection — Chaotic's `random_moveset`, see §2.4.) No player input, ever.
5. **Chaotic borrows movesets.** A Chaotic combatant's `random_moveset` tag makes it pick a **random move from the union of all combatants' movesets** (config `randomFromAnyMoveset = true`) using the seeded RNG — it may "use the enemy's special." This is the headline Chaotic battle moment. (§2.4 / F4)

> **Why two moves, not a full moveset:** a 10–17 audience watching an auto-battle does not parse a 6-skill rotation. Two moves (one reliable, one "big") read instantly as cartoon action and keep the content burden (per-species move tuning) tractable for a solo dev. The schema is extensible (a species *could* list 3+ moves later); MVP authors exactly two.

### 2.3 Turn order (SPD-based + Hyper act-first)

Turn order is recomputed **each round** (a "round" = every alive combatant acts once), so SPD changes from knock-outs/effects are honored.

1. **Base order = descending SPD.** Higher `SPD` acts earlier. (Formula **F3**.)
2. **Ties broken deterministically** — by a stable key (`teamSide` then `slotIndex` then `id`) so the order never depends on table iteration order (which is non-deterministic in Lua). **Critical for replay determinism.**
3. **Hyper `act_first_mistarget` priority.** A Hyper combatant gets a turn-order priority bonus (`turnPriority = +INF` per personality-gdd F4) — it acts **first** in its round regardless of SPD. If multiple Hypers exist, they sort among themselves by the same deterministic tie-break, all ahead of non-Hypers.
4. **Lazy `berserk_when_last`** does **not** change order; it changes *whether it acts* (Lazy refuses to attack until last-standing — it still takes its turn slot but the action is "pass/defend" until the berserk condition holds; F4).

### 2.4 Personality behaviors as turn-engine mechanics (the 5 tags)

Battle reads `{tag, params} = PersonalityService.getBattleBehavior(entry.id)` once at setup (the combatant is **locked** for the battle's duration — reroll mid-battle is rejected, personality-gdd E4) and implements each tag inside the turn loop. **All numbers come from `PersonalityConfig`; Battle hardcodes none.**

> **Shared cross-system contract with Pet AI (#25) — v1.3:** The five tags below (`act_first_mistarget`, `berserk_when_last`, `random_moveset`, `bodyguard`, `counter_double`) and their params (`mistargetChance`, `defenseMultiplier`, `berserkAttackMultiplier`, `randomFromAnyMoveset`, `bodyguardAllyHpThreshold`, `bodyguardDamageTakenFraction`, `counterDamageMultiplier`) are defined in Personality #2 §8 and consumed **identically** by both Battle (turn-based dispatch, this section) **and** Pet AI (real-time dispatch, `pet-combat-gdd.md` planned). When a new tag is added to Personality #2, BOTH consumers must implement it; when a param value changes, BOTH consumers respond identically — no drift permitted. The runtime dispatch differs: Battle resolves tags inside a **turn step** (§2.5); Pet AI resolves them inside a **damage tick / AI decision frame**. Same intent (e.g., Hyper "acts first" = Battle gives turn-priority; Pet AI gives the first attack window in a real-time engage). Currently Pet AI (demo `a71e545`) only applies a personality **damage multiplier** (via `prodMult`) — **full tag wiring is a pet-combat-gdd obligation**, not implemented yet.

| Personality | Tag (from #2) | Mechanic implemented by Battle | Params read (PersonalityConfig) |
|---|---|---|---|
| **Hyper** | `act_first_mistarget` | Acts first every round (turn priority). On its attack, with probability `mistargetChance` the chosen target is replaced by a **random *other* valid target** (may be an ally or wrong enemy) using seeded RNG. Emits `hyper_mistarget` Moment on a miss-redirect. | `mistargetChance` (0.20) |
| **Lazy** | `berserk_when_last` | Derived DEF already × `defenseMultiplier` (§2.1). On its turn, if `alliesAlive > 1` it **does not attack** (action = `defend/pass`). When it becomes the **last living ally** (`alliesAlive == 1`), it goes **berserk**: its attack damage is multiplied by `berserkAttackMultiplier`. Emits `lazy_berserk` Moment on the transition. | `defenseMultiplier` (1.75), `berserkAttackMultiplier` (2.50) |
| **Chaotic** | `random_moveset` | Each of its turns, instead of the default move-selection it picks a **random move** (seeded RNG) from the union of *all* combatants' movesets if `randomFromAnyMoveset`, else from its own. Emits a `chaotic_*` Moment. | `randomFromAnyMoveset` (true) |
| **Loyal** | `bodyguard` | When an **incoming single-target hit** is about to resolve on an ally whose `hpFraction < bodyguardAllyHpThreshold`, the hit is **redirected** onto the nearest living Loyal; the Loyal takes `rawDamage × bodyguardDamageTakenFraction`. Emits `loyal_blocked` Moment. Redirect is evaluated **at hit-resolution time** (so a Loyal already KnockedOut cannot block — E7). | `bodyguardAllyHpThreshold` (0.30), `bodyguardDamageTakenFraction` (1.0) |
| **Rebel** | `counter_double` | After surviving any incoming hit (`hpAfter > 0`), the Rebel **immediately counterattacks** the attacker for `Rebel.ATK × counterDamageMultiplier` (a `basic`-style retaliation, no cooldown, does not consume its next turn). A counter that knocks out the attacker is logged as a counter-KO. Emits `rebel_countered` Moment. | `counterDamageMultiplier` (2.0) |

> **Decoupling guarantee:** if Personality adds a 6th type with a new tag, Battle adds exactly one handler in this switch; if the 6th type reuses an existing tag, Battle changes nothing. Battle never branches on the personality *name* — only on the *tag*.

### 2.5 Turn resolution (one combatant's action)

Resolving a single turn, deterministically:

1. **Skip if KnockedOut.** A combatant in `KnockedOut` is removed from the round's action list.
2. **Select move** — `special` if off cooldown else `basic`; **overridden** by `random_moveset` for Chaotic (§2.4). Decrement/track cooldowns.
3. **Select target** — default = a valid living enemy chosen by the **deterministic target policy** (`targetPolicy`, default `"lowest_hp_enemy"`, config; tie-break by stable key). **Overridden** by Hyper `act_first_mistarget` (may re-roll to a random other target).
4. **Compute damage** — Formula **F1** with seeded variance.
5. **Apply Loyal redirect** (F4 `bodyguard`) at hit-resolution: if the target qualifies an ally for protection, redirect onto the Loyal.
6. **Apply damage** — `target.HP = max(0, target.HP - damage)`. If `HP == 0` → transition target to `KnockedOut`, log a knockout.
7. **Apply Rebel counter** (F4 `counter_double`) if the target survived and is a Rebel — counter the attacker immediately.
8. **Emit events** — append the corresponding entries to the timeline (action, damage, knockout, personality moment). (§3.3)

Every RNG draw in steps 2–4 (variance, mistarget roll, Chaotic move pick) comes from the **single seeded stream** (§2.7) in a **fixed call order**, which is what makes the timeline reproducible.

### 2.6 Win / lose conditions + turn cap

- **Team is defeated** when **all** its combatants are `KnockedOut`.
- **Battle resolves** when one team is fully defeated. The **other team is the `winner`**. From the *engine's* perspective `winner ∈ {"attacker", "defender"}` (Raid #6 maps that to player-facing win/lose).
- **Turn cap (anti-infinite-loop):** if neither team is defeated after `maxTurns` total turns (config), the battle ends in a **tie-break by team HP%** (Formula **F6**): the team with the higher *remaining total-HP fraction* wins; if those are equal, `tieBreakWinner` (config, default `"defender"`) wins (defender-advantage is the standard raid convention — the attacker must *earn* the win). This guarantees **every battle terminates** in a bounded number of turns. (E2)
- **Simultaneous full KO** (both teams emptied on the same action — e.g. a counter-KO that trades the last two): resolved by the **same HP%/tie-break rule** evaluated at that instant; since both are at 0 HP total, `tieBreakWinner` decides. (E1)

### 2.7 Determinism & seeded RNG (load-bearing)

- The battle uses **one seeded RNG stream**: `rng = Random.new(seed)`. **`seed` is supplied by the caller** (Raid #6) and is recorded in the timeline header so the client (and tests) can reproduce/verify.
- **All** stochastic decisions draw from this one stream **in a fixed, documented order** per turn (variance → mistarget → Chaotic-pick → contagion-style sub-rolls), so the sequence of draws is a pure function of the battle state. **No `math.random`, no `os.time()`, no `tick()`, no table-iteration-order dependence** anywhere in the sim (those are the classic determinism breakers — forbidden in the engine).
- **Tie-breaks are by stable keys** (never by `pairs()` order). Combatants are processed via **sorted arrays**, not hash maps, inside the sim.
- **Result:** `Battle.resolve(attackerTeam, defenderTeam, seed)` is a **pure function** → same inputs always yield the same timeline. The client replay derives identical state by applying the log; if a client somehow diverges, the server's persisted outcome is authoritative and the client is snapped to it (E5).

### 2.8 Sim → log → replay flow

```
 RAID (#6) calls Battle.resolve(attackerTeam, defenderTeam, seed)
        │
        ▼
 (1) SETUP   ── derive Combatants from BrainrotEntries (F1stats), read battle tags (#2),
        │        lock combatant ids (reject reroll/deploy, E4 of #2/#3), init rng=Random.new(seed)
        ▼
 (2) SIMULATE (server, headless, instant — no real-time wait) ── run the turn loop to a
        │        terminal state, appending every action/damage/KO/moment to the TIMELINE.
        │        This is the AUTHORITATIVE resolution; it completes in microseconds.
        ▼
 (3) RESULT  ── { winner, timeline, survivors, casualties } returned to Raid (#6).
        │        Raid applies loot/cost (Economy), writes history.rwon/rdef (Persistence atomic).
        ▼
 (4) REPLAY  ── server sends BattleStarted + BattleTimeline to the spectating client.
        │        Client plays the log back AT ANIMATION SPEED (the "live" spectate the player sees),
        │        reconstructing HP bars / hits / KOs / personality callouts from the deltas.
        ▼
 (5) RESULT SCREEN ── client shows win/lose after the replay (or immediately if skipped, E4-disconnect).
```

The player perceives a "live" fight, but the fight was **already fully decided** in step 2 before a single frame animated. Replay speed, skip, and pacing are presentation concerns (client), never affecting the outcome.

### 2.9 State machines

**Battle session state machine** (one per battle):

```
 [*] --> Setup : Battle.resolve called
 Setup --> InProgress : combatants derived, tags read, rng seeded, ids locked
 InProgress --> InProgress : resolve one turn (loop)
 InProgress --> Resolved : a team fully KnockedOut  OR  maxTurns reached (tie-break)
 Resolved --> [*] : ids unlocked, outcome returned, timeline handed to replay
```

Allowed transitions only: `Setup→InProgress→Resolved`. `Resolved` is terminal. The simulation (steps 1–3 above) runs entirely within `Setup→InProgress→Resolved` **server-side and synchronously**; the client-side replay is a *separate* presentation state that does not feed back into this machine.

**Combatant state machine** (one per combatant):

```
 [*] --> Active : derived at setup
 Active --> Active : takes damage but HP > 0 / acts / counters / is redirected to
 Active --> KnockedOut : HP reaches 0 ("fainted / out of office")
 KnockedOut --> [*] : terminal for this battle (no revive at launch)
```

`KnockedOut` is terminal within a battle (no revive in MVP). A `KnockedOut` combatant cannot act, cannot be targeted, cannot block (Loyal), cannot counter (Rebel). Compliance terminology: **`KnockedOut`** in code; **"fainted" / "knocked out" / "out of office"** in UI.

### 2.10 Battle flow diagram (turn loop)

```
            ┌──────────────────────────────┐
            │   SETUP (derive + lock + seed)│
            └───────────────┬──────────────┘
                            ▼
            ┌──────────────────────────────┐
            │  START ROUND                  │
            │  build action order:          │
            │   Hypers first (act_first),   │
            │   then by SPD desc,           │
            │   ties by stable key          │   ◄────────────┐
            └───────────────┬──────────────┘                │
                            ▼                                │
            ┌──────────────────────────────┐                │
            │  NEXT COMBATANT in order      │                │
            │  (skip if KnockedOut)         │                │
            └───────────────┬──────────────┘                │
                            ▼                                │
            ┌──────────────────────────────┐                │
            │  RESOLVE TURN                 │                │
            │  select move (special/basic;  │                │
            │   Chaotic=random)             │                │
            │  select target (policy;       │                │
            │   Hyper may mistarget)        │                │
            │  Lazy: pass unless last → berserk              │
            │  compute damage (F1, seeded)  │                │
            │  Loyal redirect at hit        │                │
            │  apply dmg; KO if HP=0         │                │
            │  Rebel counter if survived    │                │
            │  append timeline events       │                │
            └───────────────┬──────────────┘                │
                            ▼                                │
            ┌──────────────────────────────┐                │
            │  TEAM FULLY KNOCKED OUT?      │── no ──┐       │
            └───────────────┬──────────────┘        │       │
                   yes      │              ┌─────────▼─────┐ │
                            │              │ more in order?│─┘ (next combatant)
                            │              └─────────┬─────┘
                            │                   no   │
                            │                        ▼
                            │              ┌──────────────────┐
                            │              │ turnCount>=maxTurns? │── no ──► (start next round) ─┘
                            │              └─────────┬────────┘
                            │                   yes  │
                            ▼                        ▼
                  ┌──────────────────┐    ┌──────────────────────┐
                  │  RESOLVED: winner │    │ RESOLVED: HP% tie-break│
                  │  = surviving team │    │  (F6); tieBreakWinner  │
                  └─────────┬────────┘    └───────────┬───────────┘
                            └────────────┬─────────────┘
                                         ▼
                         { winner, timeline, survivors, casualties }
```

---

## 3. Data Schema

Battle persists **nothing about the fight** — combat state is **ephemeral** (server memory only), matching persistence-gdd v1.2 §3.2 ("in-flight battle/raid combat state — server memory only; only *results* persist"). Battle **reads** `BrainrotEntry` from the roster and **writes** only the outcome counters (`history.rwon`/`history.rdef`, player `raidsWon`/`raidsDefended`) — and those writes are performed via Raid (#6) through Persistence's atomic path, not by Battle touching DataStore.

### 3.1 Ephemeral combat state (server memory only — NOT persisted)

```lua
-- Built at Setup, lives for the battle's duration, discarded at Resolved. NEVER written to DataStore.
type Combatant = {
    -- Identity (links back to the persisted Brainrot; NOT a copy of it).
    id: string,                 -- BrainrotEntry.id (GUID). The lock key for this battle.
    species: number,            -- from BrainrotEntry.species
    personality: string,        -- enum (Personality #2); read-only for this battle (E4 lock)
    teamSide: string,           -- "attacker" | "defender"
    slotIndex: number,          -- 1..teamSize (deterministic tie-break key)

    -- Derived stats (F1stats; from species base × level scale × personality def mult). Integers.
    maxHp: number, hp: number,  -- hp starts == maxHp; current HP mutates during the fight
    atk: number, def: number, spd: number,

    -- Behavior (read once from PersonalityService.getBattleBehavior at Setup; frozen for the fight).
    behaviorTag: string,        -- "act_first_mistarget" | "berserk_when_last" | "random_moveset"
                                --   | "bodyguard" | "counter_double"
    behaviorParams: { [string]: any },  -- e.g. { mistargetChance = 0.20 } — copied from PersonalityConfig

    -- Move state.
    moveset: { Move },          -- { basic, special } resolved from BattleConfig.species[species].moves
    specialCooldownLeft: number,-- turns until `special` is available again (0 = ready)

    -- Runtime status.
    state: string,              -- "Active" | "KnockedOut"
    hasGoneBerserk: boolean,    -- Lazy: set true once berserk triggers (for one-time Moment)
}

type Move = {
    id: string, name: string,
    power: number,              -- ATK multiplier (F1)
    cooldownTurns: number,      -- 0 for basic; > 0 for special
    targeting: string,          -- "single" at launch (schema reserves "all_enemies"/"ally_heal" for P2)
}

-- The battle session container (server memory).
type BattleSession = {
    battleId: string,           -- HttpService GUID for THIS battle session (log correlation / replay key)
    seed: number,               -- the seed used (recorded for reproducibility + client verify)
    state: string,              -- "Setup" | "InProgress" | "Resolved"
    attacker: { Combatant },    -- 3 at launch (Raid sends team of 3)
    defender: { Combatant },    -- N (config-defined NPC team; typically 3)
    turnCount: number,
    timeline: BattleTimeline,   -- the event log built during simulation (§3.3)
    winner: string?,            -- set at Resolved: "attacker" | "defender"
}
```

### 3.2 `BattleConfig` species & move schema (VALUES are content-TBD)

`BattleConfig` is config-owned (commented, ranged, versioned). The **species base-stat numbers and move tuning are CONTENT, filled in later** — this GDD locks the **schema** and ships one documented placeholder so the engine compiles and tests run. (Full table in §8.)

```lua
-- src/ReplicatedStorage/Shared/Config/BattleConfig.lua  (excerpt — schema + ONE placeholder species)
-- species[*].base + moves VALUES are CONTENT-TBD (see §8 / §9 Open Questions).
return {
    version = 1,
    -- ... global combat tuning (damage, scaling, caps) — see §8 ...

    species = {
        -- KEY = numeric species id (matches BrainrotEntry.species). VALUES below are PLACEHOLDER.
        [1] = {
            name = "Placeholder Brainrot",       -- display (content)
            base = { hp = 100, atk = 20, def = 10, spd = 12 },  -- CONTENT-TBD per species
            moves = {
                basic   = { id = "b1", name = "Bonk",       power = 1.0, cooldownTurns = 0, targeting = "single" },
                special = { id = "s1", name = "Mega Bonk",  power = 2.0, cooldownTurns = 3, targeting = "single" },
            },
        },
        -- [2], [3], ... one row per species. Authored during content production.
    },
}
```

### 3.3 Event log / timeline format (what is sent to the client for replay)

The timeline is the **deterministic, compact action log** — the single artifact the client replays. It is built during simulation and shipped to the client (§5). It is a list of **typed events** plus a header. **Deltas, not full state** — the client reconstructs HP/state by applying events in order.

```lua
type BattleTimeline = {
    -- HEADER (sent once; lets client set up the scene + verify reproducibility).
    header: {
        battleId: string,
        seed: number,                       -- recorded for verify/QA (client does NOT re-simulate)
        attacker: { CombatantSummary },     -- id, species, personality, maxHp, slotIndex (for HP bars/sprites)
        defender: { CombatantSummary },
        maxTurns: number,
    },
    -- EVENTS (ordered; the replay plays these back at animation speed).
    events: { TimelineEvent },
    -- FOOTER (the resolved outcome; lets a client that SKIPS the replay jump to the result).
    result: {
        winner: string,                     -- "attacker" | "defender"
        survivors: { string },              -- combatant ids still Active
        casualties: { string },             -- combatant ids KnockedOut
        endReason: string,                  -- "team_ko" | "turn_cap_hp" | "turn_cap_tiebreak"
        turns: number,
    },
}

-- A single event. `t` (type) is a short enum; fields vary by type. Kept SMALL for bandwidth.
type TimelineEvent =
    | { t = "round_start", round: number }
    | { t = "turn",   actor: string, move: string, target: string }      -- who acts, which move, intended target
    | { t = "damage", source: string, target: string, amount: number, hpAfter: number, crit: boolean? }
    | { t = "ko",     target: string }                                   -- target KnockedOut ("fainted")
    | { t = "redirect", from: string, to: string }                       -- Loyal bodyguard took the hit
    | { t = "counter", source: string, target: string, amount: number, hpAfter: number }  -- Rebel counter
    | { t = "mistarget", actor: string, intended: string, actual: string }   -- Hyper missed
    | { t = "berserk", actor: string }                                   -- Lazy went berserk (last standing)
    | { t = "moment", momentType: string, actor: string }                -- maps to PersonalityMoment for callout UI
```

**Bandwidth note:** each event is a tiny table of strings/numbers (ids are short GUIDs or could be index-aliased to 1-byte slot indices at impl for further savings). A typical 3v3 battle resolves in well under ~60 events → a few KB total, sent **once** as one `BattleTimeline` payload — far under the 50 KB/s budget (remotes.md). No per-tick networking. (§5)

### 3.4 What persists (outcome only — via Raid + Persistence)

Battle returns the outcome; **Raid (#6)** translates it into persisted writes through **Persistence (#1)**'s atomic path. Battle itself writes nothing to DataStore.

| Persisted field (owner) | When Battle's outcome causes a write | Path |
|---|---|---|
| `BrainrotEntry.history.rwon` (Persistence) | +1 for each attacker Brainrot on a **winning** attack team | Raid → Persistence atomic `UpdateAsync` |
| `BrainrotEntry.history.rdef` (Persistence) | +1 for each defender Brainrot that participated in a **successful defense** (defender won) | Raid → Persistence atomic |
| `PlayerData.raidsWon` (Persistence) | +1 on a player win (player-level lifetime) | Raid → Persistence atomic |
| `PlayerData.raidsDefended` (Persistence) | +1 on a successful defense | Raid → Persistence atomic |

> Loot (coins) and raid send cost are **Economy/Raid**, not Battle (Battle holds no currency — economy-gdd §, locked context). Battle's `result` is the input to those writes; the atomicity/idempotency is owned by Persistence/Economy (per-raid `idemKey`).

### 3.5 Ephemeral, NOT persisted (documented explicitly)

| State | Why ephemeral |
|---|---|
| Entire `Combatant` block (derived HP/ATK/DEF/SPD, current hp, cooldowns, status) | Derived from `species`+`level`+`personality` at setup; recomputed every battle. Storing it would duplicate/contradict the roster (and there is no `iv` to store). |
| `BattleSession` (turn count, in-flight timeline, winner-before-commit) | In-flight combat state; persistence-gdd §3.2 declares it server-memory only. |
| The `seed`'s downstream RNG state | Reproducible from `seed` alone; the stream is re-derivable. |
| The shipped `BattleTimeline` on the client | Presentation artifact; discarded after the replay screen closes. |

---

## 4. Client-Server Split

| Concern | Server (authoritative) | Client (presentation only) |
|---|---|---|
| Combatant stat derivation (F1stats) | **YES** — from roster + `BattleConfig` server-side | Never; may read `BattleConfig` display fields for sprites/names only |
| Reading personality battle tags/params (#2) | **YES** — `getBattleBehavior(id)` server-side | Never |
| Seeded RNG + the **entire simulation** | **YES** — runs the full turn loop, decides every hit/KO/winner | **NEVER** — client does not roll, does not compute damage, does not decide outcomes |
| Building the `BattleTimeline` | **YES** | Receives it read-only |
| The outcome (`winner`/`survivors`/`casualties`) | **YES** — returned to Raid, drives persisted writes | Receives it; cannot alter it |
| Combatant id locking (no reroll/deploy mid-battle) | **YES** (E4 of #2/#3) | Never |
| Replaying the timeline as animation | Provides the log | **YES** — plays HP bars, hit/KO/counter animations, personality callouts, pacing, skip |
| Replay pacing / skip / camera | Provides timing hints in config (optional) | **YES** — pure presentation; does not affect outcome |

**Authority rule (locked, per `server-scripts.md` + remotes.md):** the **entire result is computed server-side before any frame animates.** The client is a **pure viewer** of a deterministic log. There is **no Client→Server remote that influences a battle's outcome** — the only C→S surface is presentation intent (skip/spectate-ack), rate-limited and outcome-irrelevant. A tampered client can mis-animate its *own* replay but cannot change loot, `history`, or the persisted winner. If the client's replayed state diverges from the log footer, the client is snapped to the authoritative result (E5).

---

## 5. RemoteEvents / Functions

All remotes registered in `ReplicatedStorage/Shared/Remotes` and documented in `design/remotes-manifest.md`. **No Client→Server `RemoteFunction`** (server-hang risk, per remotes.md). Battle is invoked **server-internally** by Raid (#6) — there is **no client remote that starts or resolves a battle** (battles only happen inside a raid, which Raid gates). The network surface is **server → client replay delivery** + a thin presentation-intent channel. Refinable by `remotes-networking-specialist`.

### 5.1 Server → Client

| Remote | Type | Payload | Purpose |
|---|---|---|---|
| `BattleStarted` | RemoteEvent | `{ battleId, header: BattleTimeline.header }` | Tells the spectating client a battle is about to replay; sends the header (combatant summaries, seed, maxTurns) so the client builds the scene + HP bars before events stream. Fired once. |
| `BattleTimeline` | RemoteEvent | `{ battleId, events: { TimelineEvent }, result }` | The **compact action log** + the resolved footer. Sent **once** (whole log; a 3v3 is a few KB) so the client can replay AND can skip-to-result. Deltas only — no full per-tick state. |
| `BattleResult` | RemoteEvent | `{ battleId, winner, survivors, casualties, endReason }` | The authoritative outcome for the result screen. Redundant with the timeline footer by design — a client that never received/played the timeline (rejoin, skip) still gets the result (E4/E5). |

> For very long/edge battles the engine could chunk `BattleTimeline.events`, but at launch (≤ `maxTurns`, 3v3) one payload is well under budget; chunking is a forward-compat impl detail, not a design requirement.

### 5.2 Client → Server

| Remote | Type | Payload | Validation |
|---|---|---|---|
| `BattleSpectateReady` | RemoteEvent | `{ battleId: string }` | Optional ack that the client is ready to receive the timeline (lets the server hold the stream briefly so the player doesn't miss the opening). Rate-limited (≤ 2/sec); `battleId` type-checked + must match a battle this player owns/spectates; **outcome-irrelevant**. |
| `BattleSkip` | RemoteEvent | `{ battleId: string }` | Player taps "Skip" to jump to the result. Rate-limited (≤ 2/sec); validated against an owned `battleId`; **purely presentational** — the server simply confirms it may send `BattleResult` early (the outcome was already decided). Cannot change anything. |

> **No C→S remote ever names a combatant action, a damage number, a target, an RNG roll, or a winner.** Battles are not initiated by clients (only by Raid server-side). Per remotes.md/server-scripts.md every handler validates types + rate-limits and the server trusts no client value. There is **no Client→Server RemoteFunction** anywhere in Battle.

### 5.3 Internal server interfaces (NOT network — cross-system decoupling per `gameplay-systems.md`)

**The Raid contract (the function Raid #6 calls) — LOCKED signature:**

```lua
-- ServerScriptService/Battle/BattleService.lua  (server-only, pure-function core)
--
-- Resolve a full battle deterministically. PURE FUNCTION of its inputs (given the same teams + seed,
-- always returns the same outcome + timeline). Does NOT touch DataStore, currency, loot, or targets.
-- Raid (#6) builds the teams (from rosters / NPC config), supplies a seed, and consumes the outcome.
--
-- @param attackerTeam  : { BrainrotEntry }   -- the raiding team (3 at launch)
-- @param defenderTeam  : { BrainrotEntry }   -- the NPC/defender team (config-defined; typically 3)
-- @param seed          : number              -- caller-supplied RNG seed (recorded for replay/QA)
-- @return BattleOutcome
function BattleService.resolve(
    attackerTeam: { BrainrotEntry },
    defenderTeam: { BrainrotEntry },
    seed: number
): BattleOutcome

type BattleOutcome = {
    winner: string,                 -- "attacker" | "defender"
    timeline: BattleTimeline,       -- the deterministic event log (header + events + result footer)
    survivors: { string },          -- combatant ids (GUIDs) still Active at the end
    casualties: { string },         -- combatant ids KnockedOut at the end
}
```

- **Raid owns** building the teams (selecting the player's 3 attackers from the roster; reading the NPC Rival Startup defender team from config), generating/recording the `seed`, applying cost+loot via Economy, and writing `history`/`raidsWon`/`raidsDefended` via Persistence's atomic op using the returned outcome.
- **Battle owns** only `resolve` (the pure sim) and shipping the timeline to the spectating client for replay.
- **Combatant lock:** before `resolve`, the caller (Raid) marks the attacker `id`s as **in-battle** (so Personality reroll is rejected with `"in_battle"`, personality-gdd E4, and Idle deploy is rejected/pauses, idle-gdd E4). Battle releases the lock when `Resolved`.

**Events Battle emits (Bindable/signal layer `GameEvents`):**

| Event | Payload | Fired When | Listened By |
|---|---|---|---|
| `PersonalityMoment` | `{ id, momentType, personality, payload, serverTime }` | A clutch personality beat resolves in-sim (`hyper_mistarget`, `lazy_berserk`, `loyal_blocked`, `rebel_countered`, plus Chaotic via the borrowed move) — reusing the **exact** `momentType` enum from personality-gdd §5.3 | Moment System #12 (primary), Fame (P2), Analytics |
| `BattleResolved` | `{ battleId, winner, attackerIds, defenderIds, endReason, turns }` | At `Resolved` | Raid #6 (apply loot/history), Evolution #8 (raid-win/survival milestone context), Moment #12 (clutch-win recap), Analytics |

> Battle **emits** `PersonalityMoment` using the contract Personality #2 defined (Personality is the contract owner; any system — including Battle — may fire a moment of a defined type). Moment #12 formats/surfaces it (one at a time).

---

## 6. Player-Facing UI

Rendered through the shared UI/HUD framework (#13); **pure presentation** that replays the server timeline and fires only presentation intents. **Mobile-first.** Cartoon style; compliance terminology only ("knocked out / fainted / out of office", never "die/kill").

1. **Spectate arena (the main view).** Two teams face off — **attacker** (player's 3) on one side, **defender** (NPC Rival Startup's team) on the other. Each combatant shows a sprite, name, **personality badge** (#2 color/icon), and an **HP bar** that drains as `damage` events replay. Simple, readable, low-poly/2D-friendly for low-end devices.
2. **Live action replay.** As the timeline plays: attack lunges/bonk effects on `turn`+`damage`, a "faint/out of office" puff on `ko`, number pop-ups for damage. Paced for clarity (one action at a time — no simultaneous chaos a kid can't follow).
3. **Personality callout banners (the viral hook).** On `moment`/`mistarget`/`berserk`/`redirect`/`counter` events, a punchy banner: **"Rebel counter — double damage!"**, **"Loyal protected the team!"**, **"Hyper missed!"**, **"Chaotic stole their move!"**, **"Lazy went BERSERK!"** Big, colorful, brief — the screenshot moment.
4. **Turn / round indicator.** A small "Round N" ticker so the fight reads as turn-based, not button-mash.
5. **Skip button.** "Skip ▶▶" jumps to the result (fires `BattleSkip`; outcome already decided). Always available — respects players who just want the result.
6. **Result screen.** Big **WIN / LOSE** (cartoon, compliance-safe: "Your team won the office showdown!" / "Your team got sent home early!"), the surviving vs fainted roster, and a handoff to Raid (#6) for the loot/reward panel (Battle shows the *fight* result; Raid shows the *loot*). A "clutch moment" highlight may replay the single best `moment` (Moment #12).
7. **Connection-safe.** If the player disconnects mid-replay, the battle is already resolved server-side; on rejoin they see only the result (no re-fight). If they never see the replay (joined late), `BattleResult` drives the screen directly (E4).

All surfaces are driven by **one timeline payload + one result** — **no per-frame networking**, safe on low-end mobile.

---

## 7. Edge Cases & Error States

Covers the `design-docs.md` checklist (zero/max/negative/rapid/lag/disconnect/datastore-down/concurrent). **Minimum 5 exceeded.** Each: trigger → defined behavior.

### E1 — Both teams fully KnockedOut on the same action (simultaneous KO / tie)
**Trigger:** the action (or a Rebel counter) that KOs the last enemy *also* leaves the actor's whole team at 0 (e.g. a counter-KO trades the last two combatants).
**Behavior:** the engine evaluates the win condition **after the full action+counter resolves**, then applies the **HP%/tie-break rule (F6)**. With both teams at 0 total HP, HP% is equal, so `tieBreakWinner` (config, default `"defender"`) wins. `endReason = "turn_cap_tiebreak"` is **not** used here (the cap wasn't hit) — `endReason = "team_ko"` with the tie-break note in the footer. Deterministic, no crash, no "no-winner" state. (Raid converts a defender-win to "raid failed.")

### E2 — Battle never ends / infinite loop (everyone too tanky, no net damage)
**Trigger:** mutual high DEF / low ATK (e.g. two Lazy tanks that won't attack until last) means neither team can finish the other before forever.
**Behavior:** the **turn cap** (`maxTurns`, config) guarantees termination. At the cap the battle resolves by **HP%/tie-break (F6)**: higher remaining total-HP fraction wins; ties → `tieBreakWinner`. `endReason = "turn_cap_hp"` (or `"turn_cap_tiebreak"` on an exact HP% tie). **Special interaction:** if the cap is hit while *all surviving combatants are Lazy and refusing to attack* (the "stalemate of tanks"), the HP% rule still produces a deterministic winner — no hang. The cap also bounds replay length (bandwidth) and animation time.

### E3 — Chaotic `random_moveset` when the moveset pool is degenerate (e.g. only one combatant left, or all enemies KO'd mid-its-turn)
**Trigger:** a Chaotic combatant takes its turn but the "any combatant" moveset union is tiny (only itself alive) or its only valid target was just KO'd earlier in the same round.
**Behavior:** the move pool is **never empty** — a combatant always has its own `{basic, special}`, so `randomFromAnyMoveset` falls back to at minimum its own moveset (the union always includes self). **Target selection** is re-validated at resolution: if no living enemy exists, the Chaotic's action is a **no-op `pass`** (logged as `turn` with no `damage`) — it cannot target a KnockedOut/absent combatant. (If no enemy is alive, the win condition already fired before this turn — so in practice the no-op only guards the within-round ordering corner.) No nil-index, no crash. Deterministic (the RNG draw for the move pick still happens in fixed order so later draws don't shift).

### E4 — Player disconnects while spectating (battle already resolved server-side)
**Trigger:** the spectating player drops connection during the replay (or before it starts).
**Behavior:** the battle was **fully resolved in the simulation step before any frame animated**, so the outcome is already final and the loot/`history` writes (owned by Raid/Persistence, atomic + idempotent per-raid `idemKey`) are unaffected by the client's presence. On rejoin, the player is **not** shown a re-fight — they see the **result** (Raid surfaces the loot recap; Moment #12 may show the clutch beat). The replay is **skippable to the result** by design, so a reconnecting client simply jumps to `BattleResult`. No coins lost, no double-resolve.

### E5 — Seed / replay mismatch (client desync; client's reconstructed state diverges from the log)
**Trigger:** a buggy or tampered client applies the timeline events and ends up with a different state than the log footer says (e.g. it mis-ordered events, dropped a packet, or was hacked).
**Behavior:** the **server result is authoritative, full stop.** The client does **not** re-simulate from the seed (the seed in the header is for *verification/QA*, not for client computation) — it replays the **server-provided log**. If the client's animated state disagrees with the footer (`result`), the client **snaps to the authoritative result** (shows the correct WIN/LOSE + survivors). Because loot/`history` were written server-side from the server outcome, a desynced client **cannot affect anything persistent** — it only mis-animated its own screen. Logged as `battle_replay_desync` analytics for QA. (This is the core anti-exploit guarantee: the result exists before the client touches it.)

### E6 — Loyal bodyguard is itself KnockedOut before the redirected hit resolves
**Trigger:** a hit would be redirected to a Loyal to protect a <30%-HP ally, but the Loyal was knocked out earlier this same round (or there are two redirect-eligible hits and the first KO'd the Loyal).
**Behavior:** the redirect is evaluated **at hit-resolution time** and **only living Loyals can absorb** (a `KnockedOut` combatant cannot block). If the would-be protector is `KnockedOut`, **no redirect happens** and the original target takes the hit normally (which may KO it). If multiple Loyals are alive, the **nearest living Loyal by deterministic key** absorbs. No "ghost block," no negative-HP protector, no crash. Deterministic.

### E7 — Empty / undersized / malformed team passed to `resolve`
**Trigger:** Raid calls `resolve` with an empty `attackerTeam`, fewer than the expected combatants, a roster entry missing/invalid (`nil` species, level 0, unknown personality), or a `species` id with no `BattleConfig` row.
**Behavior:** **defensive validation at Setup** (server-scripts.md):
  - An **empty/all-absent team** is treated as **already fully defeated** → the *other* team wins immediately (`endReason = "team_ko"`, 0 turns). If *both* teams are empty → `tieBreakWinner` wins (E1 rule). No divide-by-zero (HP% over an empty team = 0).
  - A **malformed `BrainrotEntry`** is repaired/clamped at Setup: unknown `personality` falls back to `PersonalityConfig.fallbackPersonality` (default `"Loyal"`, personality-gdd E5); `level` clamps to `[1, maxLevel]`; an **unknown `species`** uses `BattleConfig.fallbackSpecies` (a defined placeholder row) and logs `battle_unknown_species`. The sim never indexes a `nil` config row. (Raid should not send malformed teams; this is defense-in-depth.)

### E8 — `BattleConfig` invalid (species base ≤ 0, negative power, missing fallback, maxTurns ≤ 0)
**Trigger:** a designer ships a species with `hp = 0`, a `power < 0`, a missing `fallbackSpecies`, or `maxTurns ≤ 0`.
**Behavior:** a **boot-time validator** (`BattleConfig.validate()`, per gameplay-systems.md — validation in code, numbers in config) runs once: clamps each base stat to `≥ 1`, clamps `power ≥ 0`, clamps `defReductionCap` into `[0, capMax]`, forces `maxTurns ≥ 1` (else substitutes the documented default), and ensures `fallbackSpecies` resolves (else injects the placeholder species and logs critical). The sim therefore never divides by zero (DEF reduction is capped, F1) and never loops unbounded. Logged loudly so QA catches a bad content edit before players do.

### E9 — Many concurrent battles across players / a busy server (scale)
**Trigger:** many raids fire near-simultaneously, each invoking `resolve`.
**Behavior:** `resolve` is a **pure, synchronous, in-memory function** with **no shared mutable global state** and **no DataStore/yield inside the sim** — each battle owns its own `BattleSession` + `Random.new(seed)`. There is no cross-battle contention. A 3v3 resolves in microseconds (bounded by `maxTurns × teamSize`), so even a burst is cheap. The only shared resources are (a) the per-`id` in-battle **lock** (set by Raid before, released after — prevents the same Brainrot being in two battles, and is the same lock Personality/Idle honor) and (b) the **timeline send** (a few KB once per battle). Scales linearly; no per-frame work.

### E10 — Same Brainrot id pulled into two battles at once (lock contention)
**Trigger:** a player tries to raid with a Brainrot that is already locked in an in-flight battle (rapid repeated raid taps, or a deploy/raid race).
**Behavior:** the **in-battle lock is the single source of truth.** Raid checks/sets the lock on each attacker `id` **before** calling `resolve`; if any required `id` is already locked, that raid is **rejected** before the sim runs (Raid surfaces `"in_battle"`). Personality reroll (#2 E4) and Idle deploy (#3 E4) honor the **same** lock. A Brainrot is therefore never in two simulations simultaneously and its derived stats/behavior can't change mid-fight (determinism preserved). Lock is released at `Resolved` (and on a guarded error path, see E11).

### E11 — `resolve` errors mid-simulation (unexpected runtime error)
**Trigger:** an unforeseen runtime error inside the sim (should be impossible given validation, but defense-in-depth).
**Behavior:** the caller (Raid) wraps `resolve` in `pcall`. On failure: **no outcome is committed** (no loot, no `history` write — the atomic Raid/Persistence op is never reached), the in-battle **lock is released** (so the Brainrots aren't stuck), the raid is treated as a **safe no-op / "hiccup, try again"** (Raid refunds any pre-charged cost via its own idempotent path), and the error is logged `battle_resolve_error` for QA. No partial state, no stuck lock, no lost currency. (Determinism makes such errors reproducible from the logged seed.)

---

## 8. Balancing Parameters

> **This is the core of the GDD.** All values live in `BattleConfig` (commented, ranged, versioned per `config-data.md`). **Zero magic numbers in code.** Personality battle multipliers are **read from `PersonalityConfig`** (#2 §8) and are **NOT redefined here** — Battle references them. Species base-stat **VALUES are content (TBD)**; only the **schema** + a documented placeholder are locked now.
>
> **Assumptions flagged for `/balance-check`** are marked **⚠VALIDATE**.

### 8.1 `BattleConfig` (global combat tuning — master table)

```lua
-- src/ReplicatedStorage/Shared/Config/BattleConfig.lua
-- Combat math + stat scaling + species/move CONTENT. Edited by designers/content for balance.
-- Personality battle multipliers are NOT here — they live in PersonalityConfig (#2 §8) and are READ.
-- Schema version: 1
return {
    version = 1,

    -- ── TEAM ──
    -- Combatants per team. Raid sends 3 (locked context). Range 1..6 | Default 3.
    teamSize = 3,

    -- ── DAMAGE (Formula F1) ──
    -- Base random variance band applied to every hit (±). Seeded RNG, deterministic.
    -- damage *= rng-uniform in [1 - variance, 1 + variance].
    -- Range 0.0..0.30 | Default 0.10 (±10%). ⚠VALIDATE feel of variance vs. determinism-readability.
    damageVariance = 0.10,
    -- DEF reduction model: defReduction = DEF / (DEF + defScaling). Higher defScaling = DEF matters less.
    -- This is the standard "armor curve" (diminishing returns, never reaches 100%).
    -- Range 10..1000 | Default 100. ⚠VALIDATE against species base DEF magnitudes once content lands.
    defScaling = 100,
    -- Hard cap on DEF reduction so a tank can never be fully immune (avoids stalemates, E2/E8).
    -- Range 0.0..0.95 | Default 0.80 (max 80% mitigation, matching the design-docs.md example).
    defReductionCap = 0.80,
    -- Minimum damage per landed hit (so a hit always "does something" — readable for kids).
    -- Range 0..50 | Default 1.
    minDamage = 1,

    -- ── STAT SCALING PER LEVEL (Formula F2) ──
    -- stat = base * (1 + growth * (level - 1)). Linear-in-level growth (predictable, kid-clear).
    -- Range 0.0..0.50 | Default 0.08 (each level ≈ +8% of base). ⚠VALIDATE curve vs. level cap.
    -- ⚠ AUTHORITATIVE VALUE in Evolution v1.3 §8.5 (EvolutionConfig.progression.statGrowthPerLevel).
    -- BattleConfig may hold a fallback mirror for boot-resilience; if a divergence is detected at
    -- runtime, EvolutionConfig wins. Identical value also read by Pet AI #25 (shared formula contract).
    statGrowthPerLevel = 0.08,
    -- Optional PER-STAT growth overrides (else statGrowthPerLevel applies to all). Default: empty (uniform).
    -- e.g. { hp = 0.10, atk = 0.08, def = 0.06, spd = 0.04 }
    statGrowthPerLevelByStat = {},
    -- Max level a Brainrot can reach (clamps derived stats; also the roster `level` cap source).
    -- Range 1..1000 | Default 100. (Coordinate with Evolution/Persistence level cap.) ⚠VALIDATE.
    maxLevel = 100,

    -- ── EVOLUTION STAT MULTIPLIER (Formula F1stats `evoMult`) ──
    -- DECISION (user): Work-Based Evolution boosts COMBAT (this) AND production (Idle #3).
    -- Flat per-evoStage multiplier applied to ALL derived stats. evoStage 0 = unevolved = 1.0.
    -- SINGLE SOURCE OF TRUTH = Evolution #8: EvolutionConfig.stageMultipliers[stage].combatMultiplier
    --   (stage 0 = 1.00, stage 1 = 1.15; unknown stage → EvolutionConfig.unknownStageMultiplier = 1.0).
    -- Battle READS those values via entry.evoStage at Setup; it does NOT own an authoritative copy.
    -- The table below is a NON-AUTHORITATIVE reference/fallback mirror kept ONLY so the engine compiles +
    -- tests run if EvolutionConfig is unavailable; it MUST match EvolutionConfig (currently 1.15 — confirmed).
    -- To retune the curve, edit EvolutionConfig (#8), NOT this line. (FLAG-BATTLE resolved, no numeric change.)
    -- Range per entry 1.0..3.0 | Unknown stage falls back to 1.0 (E8). ⚠VALIDATE vs raid balance (power-creep risk).
    evoStageStatMultiplier = { [0] = 1.0, [1] = 1.15 },  -- reference/fallback mirror of EvolutionConfig; stage-1 = +15% (CONFIRMED, owned by #8)

    -- ── TURN ENGINE (Formulas F3/F5/F6) ──
    -- Default target policy when no personality override applies.
    -- "lowest_hp_enemy" | "highest_atk_enemy" | "first_alive_enemy".
    -- Default "lowest_hp_enemy" (focus-fire reads as "smart" and ends fights cleanly). ⚠VALIDATE.
    targetPolicy = "lowest_hp_enemy",
    -- Hard cap on total turns before tie-break resolution (guarantees termination, E2). A turn = one
    -- combatant action. Range 10..1000 | Default 60 (≈ 10 rounds of 3v3; bounds replay length too).
    maxTurns = 60,
    -- Winner when teams are tied on HP% at the cap / on simultaneous KO (E1/E2). Defender-advantage
    -- is the raid convention (attacker must EARN the win). "attacker" | "defender" | Default "defender".
    tieBreakWinner = "defender",

    -- ── DETERMINISM ──
    -- If true, the engine asserts (in Studio/test) that two runs of the same seed produce identical
    -- timelines (a self-check for QA; off in production for perf). Default true in test, false live.
    assertDeterministic_test = true,

    -- ── FALLBACKS (defensive, E7/E8) ──
    -- Species id used when an entry's species has no config row (logged). Must exist in `species`.
    fallbackSpecies = 1,

    -- ── SPECIES (CONTENT — VALUES TBD; schema locked) ──
    -- KEY = numeric species id (== BrainrotEntry.species). One row per species, authored in content.
    -- base.{hp,atk,def,spd}: integers >= 1. moves: exactly { basic, special } at launch.
    -- THE NUMBERS BELOW ARE PLACEHOLDERS so the engine compiles + tests run; real values are content.
    species = {
        [1] = {
            name = "Placeholder Brainrot",                 -- display (content)
            -- Base stats at level 1. Range per stat: hp 1..100000, atk/def/spd 1..10000. CONTENT-TBD.
            base = { hp = 100, atk = 20, def = 10, spd = 12 },
            moves = {
                -- power = ATK multiplier (F1). cooldownTurns: basic 0, special > 0.
                basic   = { id = "b1", name = "Bonk",      power = 1.0, cooldownTurns = 0, targeting = "single" },
                special = { id = "s1", name = "Mega Bonk", power = 2.0, cooldownTurns = 3, targeting = "single" },
            },
        },
        -- [2] = { ... }, [3] = { ... }, ...  ← authored during content production (one per species).
    },
}
```

> **Personality params Battle READS from `PersonalityConfig` (#2 §8) — listed here for traceability, NOT redefined:**
> `traits.Hyper.mistargetChance` (0.20) · `traits.Lazy.defenseMultiplier` (1.75) · `traits.Lazy.berserkAttackMultiplier` (2.50) · `traits.Chaotic.randomFromAnyMoveset` (true) · `traits.Loyal.bodyguardAllyHpThreshold` (0.30) · `traits.Loyal.bodyguardDamageTakenFraction` (1.0) · `traits.Rebel.counterDamageMultiplier` (2.0). Each is read via `getBattleBehavior(id).params`. **If any is missing/invalid, Personality's own validator (#2 E6) handles it — Battle uses whatever the trait table returns.**

### 8.2 Formulas (explicit, named variables)

**F1stats — Combatant stat derivation (Setup).** No IV; derived from species + level + personality + evoStage.
```
levelScale(stat, level) = 1 + growth(stat) * (level - 1)         -- F2 (linear-in-level)
  growth(stat) = statGrowthPerLevelByStat[stat]  if present, else statGrowthPerLevel     (sourced from EvolutionConfig v1.3 §8.5 — shared with Pet AI #25)

HP  = floor( species.base.hp  * levelScale("hp",  level) * evoMult )
ATK = floor( species.base.atk * levelScale("atk", level) * evoMult )
DEF = floor( species.base.def * levelScale("def", level) * personalityDefMult(personality) * evoMult )
SPD = floor( species.base.spd * levelScale("spd", level) * evoMult )

  personalityDefMult(p) = traits.Lazy.defenseMultiplier   if p == "Lazy"   (1.75, from PersonalityConfig)
                        = 1.0                              otherwise
  evoMult   = EvolutionConfig.stageMultipliers[entry.evoStage].combatMultiplier
              ?? EvolutionConfig.unknownStageMultiplier   -- = 1.0 fallback for an unknown stage (E8)
              -- SINGLE SOURCE OF TRUTH = Evolution #8 (stage 0 = 1.00, stage 1 = 1.15; evoStage 0 => no boost).
              -- DECISION (user): Work-Based Evolution boosts COMBAT (this multiplier) AND production (Idle #3).
              -- Battle reads evoStage as a flat stat multiplier; the per-stage VALUES are OWNED by Evolution #8.
              -- BattleConfig.evoStageStatMultiplier is only a non-authoritative reference/fallback mirror (§8.1).
  level     : clamp(entry.level, 1, maxLevel)
  evoStage  : entry.evoStage (0 = unevolved); unknown stage => 1.0 (validator E8 fallback).
  species   : BattleConfig.species[entry.species]  (or fallbackSpecies if missing — E7)
  Bounds: every stat >= 1 (base clamped >= 1 by validator E8; floor of a >=1 product is >= 1).
```

**F2 — Level scaling.** (Used by F1stats; surfaced separately for clarity.)
```
stat(level) = base * (1 + growth * (level - 1))
  growth : EvolutionConfig.progression.statGrowthPerLevel (default 0.08; v1.3 §8.5) or per-stat override.   level 1 => stat == base.
  At maxLevel 100, default growth 0.08 => stat ≈ base * (1 + 0.08*99) ≈ base * 8.92.   ⚠VALIDATE.
```

**F1 — Damage (one landed hit).** Seeded variance; capped DEF reduction; floored minimum.
```
rawAttack    = source.ATK * move.power
              * berserkMult(source)                 -- Lazy last-standing: berserkAttackMultiplier (#2), else 1.0
defReduction = min( target.DEF / (target.DEF + defScaling), defReductionCap )   -- armor curve, capped
variance     = rngUniform(1 - damageVariance, 1 + damageVariance)               -- SEEDED; first draw of the turn
damage       = max( minDamage, floor( rawAttack * (1 - defReduction) * variance ) )

  move.power        : BattleConfig.species[...].moves[...].power
  berserkMult(b)    : (b.personality == "Lazy" and b becameLastAlly) ? berserkAttackMultiplier : 1.0  (#2)
  defScaling, defReductionCap, damageVariance, minDamage : BattleConfig
  Bounds: 0 < damage; defReduction in [0, defReductionCap] (never 100% => no immortal tank, E2/E8).
```

> A **counter** (Rebel) uses F1 with `move.power = 1.0` (basic-style) and `source = the Rebel`, multiplied by `counterDamageMultiplier` (PersonalityConfig) instead of `move.power`:
> `counterDamage = max(minDamage, floor(rebel.ATK * counterDamageMultiplier * (1 - defReductionOf(attacker)) * variance))`.

**F3 — Turn order (per round).** Deterministic; Hyper priority overrides SPD.
```
turnKey(b) = ( hyperPriority(b), b.SPD, -slotIndexTieKey(b) )    -- sort DESCENDING by this tuple
  hyperPriority(b) = 1 if behaviorTag == "act_first_mistarget" else 0     -- Hyper acts first
  primary  : hyperPriority (Hypers before non-Hypers)
  secondary: SPD descending
  tertiary : stable key (teamSide, slotIndex, id) — NEVER pairs() order (determinism, §2.7)
Action order each round = combatants sorted by turnKey, KnockedOut skipped.
```

**F4 — Personality battle behaviors (implemented by Battle; constants from PersonalityConfig #2).**
```
-- Hyper "act_first_mistarget":
turnPriority(b) = highest (acts first, F3)
target(b)       = rngUnit() < mistargetChance ? randomOtherValidTarget(rng) : policyTarget()   -- 2nd draw

-- Lazy "berserk_when_last":
DEF(b)        already × defenseMultiplier (F1stats)
action(b)     = (alliesAlive(b) > 1) ? PASS : attack with berserkMult = berserkAttackMultiplier
becameLastAlly(b) latches true the first time alliesAlive(b) == 1 (emits "lazy_berserk" once)

-- Chaotic "random_moveset":
moveThisTurn(b) = randomFromAnyMoveset
                    ? rngPick(unionOfAllCombatantMovesets, rng)        -- includes self => never empty
                    : rngPick(b.moveset, rng)                          -- (a turn's "move" draw)

-- Loyal "bodyguard" (evaluated at hit-resolution, only LIVING Loyals — E6):
if hit targets ally a, hpFraction(a) < bodyguardAllyHpThreshold, and exists living Loyal L:
    redirect hit from a to L (nearest living Loyal by stable key)
    damage to L = rawHit * bodyguardDamageTakenFraction

-- Rebel "counter_double" (after surviving an incoming hit):
if target is Rebel and hpAfter > 0:
    counterDamage = F1 with rebel.ATK * counterDamageMultiplier vs attacker   (immediate; no turn cost)
```
All right-hand constants (`mistargetChance`, `defenseMultiplier`, `berserkAttackMultiplier`, `randomFromAnyMoveset`, `bodyguardAllyHpThreshold`, `bodyguardDamageTakenFraction`, `counterDamageMultiplier`) come from **PersonalityConfig** — Battle owns none of them.

**F5 — Move selection (default, non-Chaotic).**
```
move(b) = (b.specialCooldownLeft == 0) ? b.moveset.special : b.moveset.basic
on using special: b.specialCooldownLeft = special.cooldownTurns
each round (per combatant): specialCooldownLeft = max(0, specialCooldownLeft - 1)
```

**F6 — Win condition + tie-break.**
```
defeated(team)  = every combatant in team is KnockedOut
winner =
  defeated(defender) and not defeated(attacker) -> "attacker"   (endReason "team_ko")
  defeated(attacker) and not defeated(defender) -> "defender"   (endReason "team_ko")
  both defeated (simultaneous, E1)              -> tieBreakWinner (endReason "team_ko")
  turnCount >= maxTurns (E2):
        hpFrac(team) = Σ combatant.hp / Σ combatant.maxHp   over that team
        hpFrac(attacker) > hpFrac(defender) -> "attacker"   (endReason "turn_cap_hp")
        hpFrac(attacker) < hpFrac(defender) -> "defender"   (endReason "turn_cap_hp")
        equal                                -> tieBreakWinner (endReason "turn_cap_tiebreak")
  Bounds: hpFrac in [0, 1]; empty team => hpFrac = 0 (no divide-by-zero — guard Σmaxhp==0 => 0). 
```

### 8.3 RNG / determinism contract (config-adjacent)
```
rng = Random.new(seed)                 -- ONE stream per battle; seed from caller (Raid)
Draw order per turn (FIXED):
  1) damage variance (F1)              -- always
  2) Hyper mistarget roll (F4)         -- only if actor is Hyper
  3) Chaotic move pick (F4)            -- only if actor is Chaotic
  4) (any future sub-roll)             -- appended at the END to preserve earlier sequences
No math.random / os.time / tick / pairs-order anywhere in the sim. Sorted arrays only.
=> Battle.resolve(a, d, seed) is a PURE FUNCTION (TestEZ asserts fixed-seed outcomes).
```

### 8.4 Assumptions to validate via `/balance-check` (⚠)
1. **`statGrowthPerLevel = 0.08` → ~8.9× stats at level 100** — does that produce a satisfying power curve without trivializing low-level enemies? (Coordinate with Evolution + roster level cap; Evolution v1.3 §8.5 owns the value.)
2. **`damageVariance = 0.10`** — enough to feel "alive" without making replays read as random to a kid?
3. **`defScaling = 100` / `defReductionCap = 0.80`** — depends entirely on the (TBD) species base DEF magnitudes; revisit once content base stats are authored.
4. **`maxTurns = 60`** — long enough that real outcomes aren't decided by tie-break, short enough for a punchy replay?
5. **`targetPolicy = "lowest_hp_enemy"` + `tieBreakWinner = "defender"`** — together these set the attacker/defender win-rate baseline that Raid (#6) tunes its loot/cost against; validate the intended raid difficulty.
6. **Personality balance** (read from #2): is `berserkAttackMultiplier 2.50` + `counterDamageMultiplier 2.0` + `defenseMultiplier 1.75` a fair, fun rock-paper-scissors, or does one personality dominate auto-battles? (Joint balance-check with Personality.)

---

## 9. Integration Points

### Depends On
- **#1 Data Persistence & Roster Core** (`persistence-gdd.md` v1.4): Battle **reads** `BrainrotEntry` (`id`, `species`, `personality`, `level`, `xp`, `evoStage`) to derive combatants — **there is no `iv`**, so stats come from species base + level + personality. Battle's **outcome** is written to `history.rwon`/`history.rdef` + player `raidsWon`/`raidsDefended` via Persistence's **atomic `UpdateAsync`** path (through Raid, with a per-raid `idemKey`). Battle stores **no combat state** (ephemeral, §3.1/§3.5). **Battle also writes `xp` (+`xpPerWin`) on a winning raid** via direct `PlayerDataService.update()` per Evolution v1.3 §2.7 Axis B (no `txLog` idemKey in current contract — over-credit XP is low-stakes).
- **#2 Personality System** (`personality-gdd.md` v1.1): Battle reads `getBattleBehavior(id) -> {tag, params}` and implements the five tags (`act_first_mistarget`, `berserk_when_last`, `random_moveset`, `bodyguard`, `counter_double`) using params **from `PersonalityConfig`** (never redefined here). Battle honors the **in-battle reroll lock** (personality-gdd E4 → `"in_battle"`). Battle **emits `PersonalityMoment`** (reusing the exact `momentType` enum) for clutch beats. Decoupled: a new personality = at most one new tag handler. **Tag definitions + params are a shared cross-system contract with Pet AI #25** — see §2.4 v1.3 note.
- **#8 Work-Based Evolution + Level/XP** (`evolution-gdd.md` v1.3): Battle reads **two parameter blocks** from Evolution (single source of truth, no Battle-side authoritative copies):
  - Axis A — `EvolutionConfig.stageMultipliers[evoStage].combatMultiplier` (`evoMult` in F1stats; stage-1 = 1.15) — was FLAG-BATTLE in v1.2, fully resolved.
  - Axis B — `EvolutionConfig.progression.statGrowthPerLevel` (= 0.08) and `maxLevel` (= 100) for `levelScale(L)` in F2 — locked v1.3 §8.5. **Battle and Pet AI #25 read identically; no drift permitted.**
- **#9 Economy** (`economy-gdd.md` v1.2): Battle holds **no currency**. Cost/loot is Raid (#6) via Economy. Battle returns the outcome only.

### Depended On By
- **#6 Raid v1 (NPC Rival Startups)** — the **sole caller** of `BattleService.resolve`. Calls `BattleService.resolve(attackerTeam, defenderTeam, seed)` (§5.3 locked signature): builds the player's 3 attackers from the roster and the **NPC defender team from config (the 4 Rival Startups: Grind Corp / Chill Collective / The Glitch Gang / Pivot Ventures)**, supplies+records the `seed`, sets/clears the per-`id` in-battle lock, and on the returned outcome applies cost+loot (Economy) and writes `history`/`raidsWon`/`raidsDefended` (Persistence atomic). Defender-faction personality flavor flows entirely through Battle's tag mechanics (e.g. Grind Corp = Hyper/Loyal; Chill Collective = Lazy; The Glitch Gang = Chaotic; Pivot Ventures = Rebel/Hyper — **faction→personality mapping is Raid-owned config**, Battle just executes the tags).
- **#8 Work-Based Evolution + Level/XP** (`evolution-gdd.md` v1.3) — three-way relationship:
  - (a) **Battle supplies the events** — Evolution reads `history.rwon`/`history.rdef` milestones (which Battle's outcomes increment) for Axis A raid-win/survival evolution branches (Rebel→Revolutionary at N raids survived, Loyal→Guardian at N defends); Battle supplies the events, Evolution owns the thresholds.
  - (b) **Battle reads the Axis A combat multiplier** — F1stats `evoMult` sourced directly from `EvolutionConfig.stageMultipliers[entry.evoStage].combatMultiplier` (stage-1 = 1.15; unknown → `unknownStageMultiplier` = 1.0). Evolution #8 is single source of truth; `BattleConfig.evoStageStatMultiplier` is only a non-authoritative fallback mirror (§8.1). **FLAG-BATTLE v1.2 resolved**.
  - (c) **Battle writes Axis B XP + reads `levelScale(L)` parameters** — on a winning raid, Battle credits `+xpPerWin` to each surviving attacker's `xp` via Persistence atomic `update()` (per Evolution v1.3 §2.7 XP-write path); Battle reads `statGrowthPerLevel` (= 0.08) + `maxLevel` (= 100) from `EvolutionConfig.progression` (v1.3 §8.5) for F2 `levelScale(L)`. **No drift with Pet AI #25 permitted** (shared contract).
- **#12 Moment System** — primary listener of Battle's `PersonalityMoment` / `BattleResolved` events; formats the clutch-win recap + the in-battle callout banners (one at a time). Battle defines/fires; Moment presents.
- **#13 UI/HUD** — owns the spectate arena + result screen that **replay** Battle's timeline (§6). Battle ships the log; UI animates it.
- **#25 Field Combat / Pet AI** (`pet-combat-gdd.md` planned; demo `a71e545`) — **shared-formula consumer, not a caller of `BattleService.resolve`**. Pet AI runs its own real-time resolution loop in the hub world (separate from this turn-based engine) but READS this GDD for:
  - The `levelScale(L) = 1 + statGrowthPerLevel * (L - 1)` stat formula (§2.1 / F2). Same params (`statGrowthPerLevel`, `maxLevel`) sourced from Evolution v1.3 §8.5 — single source of truth.
  - The five personality battle behavior tags + params (§2.4 v1.3 shared-contract note). Pet AI must implement the tags identically in real-time form; **currently Pet AI applies only the damage multiplier** (demo) — full tag wiring is a pet-combat-gdd obligation.
  - The combatant terminology / "knocked out" compliance vocabulary (§Cross-GDD consistency lock).
  - On a Pet AI win, Pet AI itself (not Battle) writes `+xpPerWin` to the participating Brainrot's `xp` (same Axis B path as Battle — see Evolution v1.3 §2.7). Battle's `BattleService.resolve` is NEVER called by Pet AI.

### NPC Rival Startups (defender source)
Battle is exercised against the 4 config-defined NPC factions at launch (no live PvP — that's Phase 2 #18, which reuses this exact engine + signature). The NPC defender **teams and their personality composition are Raid-owned config**; Battle treats an NPC combatant identically to a player combatant (same `BrainrotEntry` shape — Raid builds synthetic entries from faction config). This means **PvP (Phase 2) needs zero Battle changes** — only Raid's team-source changes from NPC config to a real player's deployed roster.

### Resolution notes (no contradictions)
- **`iv` decision is *made here*, not contradicted.** Persistence v1.2 explicitly deferred IV "to when the Battle GDD is written." This GDD's launch call — **derived stats, no per-Brainrot IV** — is consistent with that deferral; it does not reintroduce a dropped field. A future variance roll is additive (v1→v2 migrate + one `BattleConfig` term).
- **Ephemeral combat state** matches persistence-gdd §3.2 exactly ("in-flight battle/raid combat state — server memory only; only results persist").
- **Personality numbers stay in `PersonalityConfig`**; Battle references them (no duplicate authoritative copy) — matches personality-gdd §8 ownership and gameplay-systems.md "single source of truth."
- **Compliance terminology** ("knocked out / fainted / out of office") matches the locked world-builder constraint; the combatant terminal state `KnockedOut` carries it into code.
- **Battle ≠ Economy** — the locked "Battle holds no currency; Raid owns cost/loot" boundary is honored (Battle returns outcome only).

### Open Questions — RESOLVED (user decisions 2026-05-26; values still subject to `/balance-check`)
1. **Per-Brainrot stat variance (`iv`-like roll)?** ✅ RESOLVED — **DEFERRED to post-launch** (consistent with the dropped-`iv` decision). Launch = pure derived stats; a future seeded variance roll is additive (v1→v2 migrate + one `BattleConfig` term).
2. **Move count per species** ✅ RESOLVED — **exactly 2 (`basic` + `special`)** at launch; a third "ultimate" is a post-launch/evolved-form add (schema already allows more).
3. **`tieBreakWinner = "defender"` (defender-advantage)** ✅ RESOLVED — **confirmed**; attacker must *earn* the win. Final loot/cost tuning owned by Raid #6.
4. **`targetPolicy = "lowest_hp_enemy"` (smart focus-fire)** ✅ RESOLVED — **confirmed** as the baseline; personality already injects the chaos.
5. **Evo effect on combat** ✅ RESOLVED — **YES, `evoStage` boosts combat stats** (Work-Based Evolution = combat + production power hook). Battle applies `evoStageStatMultiplier` (F1stats `evoMult`, §8.1) as a flat per-stage multiplier; **the per-stage VALUES are owned by Evolution #8** (current `{[0]=1.0,[1]=1.15}` is a placeholder). Evolution #8 must also wire the parallel production-side multiplier into Idle #3 (forward-flag). ⚠VALIDATE raid balance / power-creep when Evolution lands.

---

## Acceptance Criteria (system is "done")

- [ ] `BattleService.resolve(attackerTeam, defenderTeam, seed)` is a **pure function**: identical inputs → bit-identical `timeline` + outcome, asserted by TestEZ fixed-seed tests.
- [ ] Combatant stats are **derived** from `species` base × level scaling × personality DEF mult — **no `iv`, nothing persisted** about combat.
- [ ] The five personality tags (`act_first_mistarget`, `berserk_when_last`, `random_moveset`, `bodyguard`, `counter_double`) are implemented per F4 using params **read from `PersonalityConfig`**; a grep of Battle code finds **zero hardcoded personality numbers**.
- [ ] Turn order is deterministic (Hyper-first, then SPD desc, stable tie-break) with **no `pairs()`/`math.random`/`os.time` in the sim**.
- [ ] Win/lose resolves correctly for: clean team-KO, simultaneous KO (E1), and turn-cap HP% tie-break (E2) — **every battle provably terminates** within `maxTurns`.
- [ ] The `BattleTimeline` is a **compact delta log** (header + typed events + result footer); a 3v3 ships in one payload well under the bandwidth budget; the client reconstructs state by applying events.
- [ ] Client is a **pure viewer**: no C→S remote influences an outcome; a desynced/tampered client snaps to the authoritative result (E5) and cannot alter loot/`history`.
- [ ] Battle holds **no currency**; outcome is the only output; Raid (#6) applies cost/loot and writes `history.rwon`/`rdef` via Persistence's atomic path.
- [ ] In-battle **lock** prevents the same `id` in two battles and is honored by Personality reroll (E4 #2) and Idle deploy (E4 #3); released at `Resolved` and on the `pcall` error path (E11).
- [ ] `BattleConfig.validate()` boots cleanly and recovers from invalid content (E8); malformed teams are repaired defensively (E7).
- [ ] All formulas F1stats/F1/F2/F3/F4/F5/F6 implemented as written; damage never negative, DEF reduction never ≥ 100%, stats never < 1.
- [ ] `PersonalityMoment` (clutch beats) and `BattleResolved` events fire with the specified payloads and are observable by a test subscriber.
- [ ] Works on low-end mobile: one timeline payload, animation-only replay, no per-frame networking, skippable to result.
- [ ] Species base-stat **content** is authored in `BattleConfig.species` (the schema + placeholder + `fallbackSpecies` are in place now; numeric values land in content production).
