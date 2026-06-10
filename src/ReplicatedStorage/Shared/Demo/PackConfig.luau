--!strict
-- Shared/Demo/PackConfig.luau
--
-- PROTOTYPE config for the "Monster Pack" spawner (5 packs of 3 around the
-- showroom). This is ISOLATED from DemoConfig on purpose: the pack spawner is a
-- pure prototype that does its own spawn/respawn/wander/catch and does NOT touch
-- the existing catch/roster/economy/combat/persistence systems. The 5 packs
-- REPLACE the existing 5 wild monsters in the showroom row (the showroom itself
-- stays as the deploy building).
--
-- Replicates the DemoConfig style: every tunable is a literal, every magic
-- number has a default + range comment. Safe to read on the server.
--
-- Schema version: 1 (prototype)

return {
    version = 1,

    -- ── IDENTITY ─────────────────────────────────────────────────────────
    -- The 5 personalities the pack spawner handles, in canonical order. Each
    -- pack slot will spawn a clone of the matching personality (a pack of 3
    -- "Lazy" monsters, 3 "Hyper" monsters, …). Mirrors DemoConfig.personalityOrder
    -- so the visible identity lines up with the rest of the demo. The pack
    -- script resolves each personality to a Monster_<P> source in the Workspace
    -- (case-insensitive) at template-build time.
    personalityOrder = { "Hyper", "Lazy", "Chaotic", "Loyal", "Rebel" },

    -- ── PACK COMPOSITION ─────────────────────────────────────────────────
    -- How many monsters of the same type live in ONE pack. 5 types × count = the
    -- total simultaneous wild population. Range: 1-10 | Default: 3
    count = 3,
    -- The Source-of-truth Workspace name for each pack type (DemoConfig calls
    -- this `creaturePrefix + UPPER(personality)` — keep the prefix in sync with
    -- DemoConfig.demo3d.creaturePrefix if you ever change it). Read-only here.
    creaturePrefix = "Monster_",

    -- ── TEMPLATE STORE ──────────────────────────────────────────────────
    -- Name of the ServerStorage folder the pack script snapshots the 5
    -- Monster_<P> source models into (cloned at boot). Strips the existing
    -- catch ProximityPrompt + the floating persona label, KEEPS the Humanoid
    -- rig so clones can walk + show the built-in health bar. String.
    templateFolderName = "WildPackTemplates",
    -- Name of the Workspace folder that holds the (invisible) pack-center
    -- marker Parts. One Part per personality, each tagged with
    -- Attribute("MonsterType", "<P>") so the pack script can find it.
    -- String.
    spawnFolderName = "MonsterPacks",
    -- Name of the BillboardGui that exists on the original 5 (the floating
    -- persona label). Stripped from the snapshot so clones start clean. The
    -- pack script does NOT add a label back (prototype scope). String.
    personaLabelName = "PersonaLabel",

    -- ── SPAWN MARKERS (World Universe build) ─────────────────────────────
    -- Wild spawns are now AUTHOR-PLACED: the spawner reads Parts named these
    -- from the Workspace as spawn points (instead of the old arc around the
    -- Cage, which now lives in a separate place). Each is hidden at boot
    -- (Transparency=1, CanCollide/Query/Touch=false) so it never shows as a
    -- block or blocks the rig. Personality is assigned round-robin across
    -- personalityOrder so every type appears.
    -- Part name = one wild SPAWN spot. String | Default: "spawn-monster"
    spawnMarkerName = "spawn-monster",
    -- Part name = one BOSS spot. String | Default: "boss-monster"
    bossMarkerName = "boss-monster",
    -- DEFAULT wild count per spawn-monster marker (clustered around the marker).
    -- A marker can OVERRIDE this per-spot with a numeric Attribute named
    -- `spawnCountAttribute` — in Studio: select the Part, Attributes panel, add
    -- "Count" = 5 — so SOME spots are denser than others. Range: 1-maxPerSpawnMarker
    -- | Default: 1
    monstersPerSpawnMarker = 1,
    -- Attribute name read off a spawn-monster marker for its per-spot count.
    -- Absent/invalid falls back to monstersPerSpawnMarker. String | Default: "Count"
    spawnCountAttribute = "Count",
    -- Hard cap on any single marker's count (guards a typo like Count=500 from
    -- spawning a lag-bomb of rigs). Range: 1-50 | Default: 20
    maxPerSpawnMarker = 20,

    -- ── ARC LAYOUT (LEGACY — unused since the marker-driven rewrite) ─────
    -- Kept for reference; the spawner no longer computes an arc.
    -- ── ARC LAYOUT (5 packs in a half-circle around the showroom) ────────
    -- The pack centers are placed on an arc of `arcRadiusStuds` centered on
    -- the Showroom's pivot, sweeping from `arcAngleStartDeg` to
    -- `arcAngleEndDeg`. Default (0..180) puts the packs BEHIND the showroom
    -- (the player's first view of the showroom is from -Z, so the back half
    -- is +Z). Invert the range to put packs in front. Range: 0-360 each.
    -- (Bumped 30 -> 48 for the Kandang v3 open-field expansion: the paddock
    -- floor is now 60x36 centered on the Showroom pivot, so packs must sit
    -- OUTSIDE the perimeter fence.)
    arcRadiusStuds = 48,
    arcAngleStartDeg = 0,
    arcAngleEndDeg = 180,
    -- How high above the showroom's pivot Y each pack center sits. The arc is
    -- computed in the XZ plane only; +Y is just the drop height so the
    -- slot markers sit at a sensible height for the script. Range: 0-20 | Default: 0.4
    packCenterYOffset = 0.4,
    -- Slot offsets inside ONE pack form a small triangle of side
    -- `slotSpreadStuds` around the pack center, so 3 same-type monsters
    -- cluster visibly without overlapping. Range: 0.5-10 | Default: 2.0
    slotSpreadStuds = 2.0,

    -- ── RESPAWN ─────────────────────────────────────────────────────────
    -- Seconds a slot waits AFTER it goes empty (model destroyed / Health <= 0)
    -- before spawning a fresh clone. Range: 0.5-60 | Default: 5
    respawnSec = 5,
    -- How high (studs) above the slot center a fresh clone is dropped so
    -- physics has a clean fall onto the ground (matches the showroom-platform
    -- approach: no hard-coded final Y, physics decides). Range: 1-20 | Default: 5
    spawnDropStuds = 5,

    -- ── WANDER (per-slot) ───────────────────────────────────────────────
    -- How far (studs) from its SLOT a pack member may pick a wander target.
    -- Kept small so the pack reads as a cluster, not 3 independent roamers.
    -- Range: 1-30 | Default: 6
    wanderRadiusStuds = 6,
    -- Random pause (seconds) between reaching a target and picking the next.
    -- Re-rolled each pause completion in [min, max]. Range: 0.5-15
    wanderPauseMinSec = 1.5,
    wanderPauseMaxSec = 4.0,
    -- How often (seconds) the AI scheduler ticks to (re)assign wander targets.
    -- Coarse on purpose — Humanoid:MoveTo handles the per-frame walking.
    -- Range: 0.1-2 | Default: 0.4
    aiTickSec = 0.4,
    -- Walk speed applied to each pack member's Humanoid on first sight
    -- (overrides any rig value so this config is the single source).
    -- Range: 1-16 | Default: 6
    walkSpeed = 6,

    -- ── CATCH (pack-local; does NOT route into the existing roster) ─────
    -- Hold duration on the ProximityPrompt (seconds). Range: 0-3 | Default: 0.6
    catchHoldSec = 0.6,
    -- Max activation distance for the catch prompt (studs). Range: 4-32 | Default: 12
    catchDistance = 12,
    -- ActionText on the catch prompt. String | Default: "Catch"
    catchActionText = "Catch",

    -- ── BOSS (1 per pack, stands at the PACK CENTER; minions ring around) ──
    -- Prototype of the Tier-1 Colony Boss (systems-index #6 Tier 1): one
    -- oversized pack leader per pack. NOT catchable — it must be DEFEATED via
    -- summon combat (DemoServer reads the mult attributes the pack stamps on
    -- the boss model). Calibration target: a trio of Lv1 fighters loses a
    -- NEUTRAL-element fight narrowly, so the boss pushes level-ups and
    -- element counter-picking (elementMod ±25%) — soloable by mid-level roster
    -- per Vision Pivot Decision 5.
    boss = {
        -- Whether each pack spawns its boss. Boolean | Default: true
        enabled = true,
        -- Uniform model scale applied via Model:ScaleTo. Reads as "boss" from
        -- afar without clipping the minion ring. Range: 1.2-3.0 | Default: 2.0
        scale = 2.0,
        -- Boss Max HP = rig MaxHealth (100) * this. Range: 2-25 | Default: 6
        hpMult = 6,
        -- Boss damage = COMBAT.wildDamagePerTick * this (consumed by DemoServer
        -- via the DamageMult attribute). Range: 1-6 | Default: 2.0
        damageMult = 2.0,
        -- Boss WalkSpeed = walkSpeed * this (slow + heavy). Range: 0.3-1.5 | Default: 0.7
        walkSpeedMult = 0.7,
        -- Seconds the boss slot waits after death before respawning (longer
        -- than the minion respawnSec so a boss kill feels earned).
        -- Range: 5-300 | Default: 30
        respawnSec = 30,
        -- Owner coin reward on a boss kill = COMBAT.winCoins * this (consumed
        -- by DemoServer via the WinCoinsMult attribute). Range: 1-50 | Default: 10
        winCoinsMult = 10,
        -- XP to the winning fighter = PROGRESSION.xpPerWin * this (consumed by
        -- DemoServer via the XpMult attribute). Range: 1-20 | Default: 4
        xpMult = 4,
        -- Whether the boss gets a catch prompt. Default false: per the Colony
        -- Boss design the boss DROPS rewards on defeat, it is never captured.
        -- Boolean | Default: false
        catchable = false,
        -- Boss wander radius mult vs wanderRadiusStuds (bosses pace a smaller
        -- area so they read as anchored to the pack). Range: 0.2-2 | Default: 0.5
        wanderRadiusMult = 0.5,
    },

    -- ── LABELS (overhead billboards built by the pack script) ───────────
    -- The pack snapshots strip the authored PersonaLabel, so the pack builds
    -- its own tiny billboard per wild: "<PERSONALITY> <elementEmoji>" for
    -- minions, "👑 <PERSONALITY> BOSS <elementEmoji>" for the boss. Element
    -- shown on the BOSS is the counter-pick hook (element doc: boss element
    -- is telegraphed); minions show it too so matchups are learnable.
    label = {
        -- Build the overhead labels at all. Boolean | Default: true
        enabled = true,
        -- Max camera distance (studs) the name label is visible from. Beyond
        -- this the BillboardGui hides itself, so names only appear as the player
        -- APPROACHES a monster instead of cluttering the whole island from afar.
        -- Range: 15-200 | Default: 60
        maxDistanceStuds = 60,
        -- Label height above the model's label anchor (studs). Range: 1-10 | Default: 3
        offsetYStuds = 3,
        -- Billboard size (pixels). Ranges: 60-300 x 14-60 | Defaults: 150 x 24
        widthPx = 150,
        heightPx = 24,
        -- Extra Y offset for the BOSS label (it is taller after ScaleTo).
        -- Range: 0-10 | Default: 2
        bossExtraYStuds = 2,
    },
}
