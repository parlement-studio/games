--!strict
-- Shared/Demo/DemoConfig.luau
--
-- DEMO-ONLY tunables for the "Brainrot Inc." playable vertical slice.
-- This is the ROUGH PROTOTYPE config (briefing demo). It is intentionally
-- isolated under the `Demo/` namespace and is NOT the production config — the
-- real systems read PersonalityConfig / IdleConfig (see design/gdd/*). Values
-- here are flavored from idea/brainrotInc.md + personality-gdd + idle-production-gdd
-- but simplified for fast iteration (in-memory state, no DataStore).
--
-- Every tunable is commented with a range/default per .claude/rules/config-data.md.
-- Safe to replicate read-only: the SERVER is authoritative; the client only uses
-- display fields (names/colors/emoji/blurbs) and may mirror rates for prediction.
--
-- Schema version: 1 (demo)

export type PersonalityId = "Hyper" | "Lazy" | "Chaotic" | "Loyal" | "Rebel"

return {
    version = 1,

    -- ── PRODUCTION CORE ──────────────────────────────────────────────────
    -- Number of factory worker slots a player has in the demo. Fixed (no
    -- upgrades in the slice). Range: 1-12 | Default: 6
    factorySlots = 6,
    -- Coins/sec produced by ONE deployed Brainrot at baseline (before any
    -- personality multiplier or moment factor). Range: 0.1-100 | Default: 2
    baseRatePerSlot = 2,
    -- Crate cost in coins. FREE for the demo so players can spam-open and feel
    -- the personality variety immediately. Range: 0-1e6 | Default: 0
    crateCost = 0,
    -- Roster cap (how many owned Brainrots before OpenCrate is refused).
    -- Demo guard so memory + UI lists stay sane. Range: 1-500 | Default: 30
    rosterCap = 30,

    -- ── TICK / SYNC CADENCE ──────────────────────────────────────────────
    -- Production tick interval (seconds). Accrual uses ACTUAL delta-time via an
    -- accumulator; this is just how often the 1 Hz logic step runs.
    -- Range: 0.25-5 | Default: 1
    productionTickSec = 1,
    -- How often a full StateUpdate is pushed to each player so the live-ticking
    -- `pending` is visible even without client prediction. Range: 0.5-5 | Default: 1.5
    stateBroadcastSec = 1.5,
    -- How often the server broadcasts the AUTO-COLLECT coin snapshot ({coins, rate})
    -- so the client can smoothly interpolate the climbing total between pushes.
    -- Range: 0.25-2 | Default: 0.5
    coinBroadcastSec = 0.5,
    -- How often (seconds) the server FLUSHES each player's live coin float into the
    -- audited persisted profile (PlayerDataService.update -> markDirty), so coins
    -- survive a crash/leave between routine autosaves. Keep this small relative to
    -- the autosave interval but well above a frame. Range: 1-10 | Default: 2
    coinFlushSec = 2,
    -- Minimum seconds between two Moments emitted by the SAME Brainrot. Throttles
    -- moment spam so pop-ups stay readable. Range: 1-30 | Default: 4
    momentCooldownSec = 4,

    -- ── RATE LIMITS (server-enforced; client cannot bypass) ──────────────
    rateLimits = {
        -- Max OpenCrate requests honored per second per player. Range: 1-20 | Default: 4
        openCrate = 4,
        -- Max Collect requests honored per second per player. Range: 1-20 | Default: 4
        collect = 4,
        -- Max Deploy/Undeploy requests honored per second per player. Range: 1-20 | Default: 8
        deploy = 8,
        -- Max Catch (ProximityPrompt) triggers honored per second per player.
        -- Range: 1-20 | Default: 6
        catch = 6,
        -- Max Recall (ProximityPrompt undeploy) triggers honored per second per
        -- player. Range: 1-20 | Default: 6
        recall = 6,
        -- Max SummonFighter requests honored per second per player. Summoning is
        -- ephemeral (does not consume the bag) so keep it modest. Range: 1-20 | Default: 4
        summon = 4,
    },

    -- ── PERSONALITIES ────────────────────────────────────────────────────
    -- Canonical display order + the only valid personality keys. The server
    -- rolls uniformly across these (20% each — see rollWeights). Each entry
    -- holds a production multiplier + the behavior flags the server's moment
    -- engine reads. `prodMult` matches the source doc (+30% Hyper / -50% Lazy /
    -- 1.0 the rest); the "moment" sub-tables drive the visible behaviors.
    personalityOrder = { "Hyper", "Lazy", "Chaotic", "Loyal", "Rebel" },

    -- Roll weights for OpenCrate's personality draw. Relative; probability =
    -- weight / sum(weights). Uniform 20% each by default. Range per: 0-1000.
    personalityRollWeights = {
        Hyper = 20,
        Lazy = 20,
        Chaotic = 20,
        Loyal = 20,
        Rebel = 20,
    },

    personalities = {
        Hyper = {
            -- Display
            name = "Hyper",
            -- One-line blurb shown on the crate reveal card.
            blurb = "Works fast, burns out faster.",
            -- Steady production multiplier. Range: 0.0-3.0 | Default: 1.30 (+30%)
            prodMult = 1.30,
            -- BEHAVIOR: periodically takes a "break" (produces 0) then a "zoom" burst.
            -- Per-tick chance to START a break while Working. Range: 0.0-1.0 | Default: 0.08
            breakChance = 0.08,
            -- How long a break lasts (produces 0). Range: 1-30 | Default: 3
            breakDurationSec = 3,
            -- Output multiplier applied for one tick right after a break ends (the "zoom").
            -- Range: 1.0-5.0 | Default: 2.5
            zoomMult = 2.5,
        },

        Lazy = {
            name = "Lazy",
            blurb = "Slow worker. Naps on the job.",
            -- Range: 0.0-3.0 | Default: 0.50 (-50%)
            prodMult = 0.50,
            -- BEHAVIOR: occasional "Zzz" flavor moment (no extra production penalty;
            -- the -50% is the whole effect — Zzz is cosmetic). Per-tick chance.
            -- Range: 0.0-1.0 | Default: 0.06
            zzzChance = 0.06,
        },

        Chaotic = {
            name = "Chaotic",
            blurb = "Genius or disaster, never both.",
            -- Base multiplier; the per-cycle flip below multiplies on top.
            -- Range: 0.0-3.0 | Default: 1.0
            prodMult = 1.0,
            -- BEHAVIOR: each ~cycle randomly DOUBLES or ZEROES output.
            -- Per-tick chance to RESOLVE a flip at all (else steady this tick).
            -- Range: 0.0-1.0 | Default: 0.5
            flipChance = 0.5,
            -- Of the flips that resolve, chance the outcome is DOUBLE (else ZERO).
            -- Range: 0.0-1.0 | Default: 0.5 (fair coin)
            doubleChance = 0.5,
            -- Output multiplier on a "double" cycle. Range: 1.0-4.0 | Default: 2.0
            doubleMult = 2.0,
            -- Output multiplier on a "zero" cycle. Range: 0.0-1.0 | Default: 0.0
            zeroMult = 0.0,
        },

        Loyal = {
            name = "Loyal",
            blurb = "Dependable. Steady as a rock.",
            -- Range: 0.0-3.0 | Default: 1.0 (steady, never negative)
            prodMult = 1.0,
            -- BEHAVIOR: occasional "steady" reassurance moment (purely cosmetic).
            -- Per-tick chance. Range: 0.0-1.0 | Default: 0.04
            steadyChance = 0.04,
        },

        Rebel = {
            name = "Rebel",
            blurb = "Won't be overworked. Walks out sometimes.",
            -- Range: 0.0-3.0 | Default: 1.0 (normal unless on walkout)
            prodMult = 1.0,
            -- BEHAVIOR: occasionally "walks out" (produces 0 for a few sec).
            -- Per-tick chance to START a walkout while Working. Range: 0.0-1.0 | Default: 0.05
            walkoutChance = 0.05,
            -- How long a walkout lasts (produces 0). Range: 1-30 | Default: 5
            walkoutDurationSec = 5,
        },
    },

    -- ── SPECIES (placeholders) ───────────────────────────────────────────
    -- 5 meme-y, chat-safe generic species. Each has a distinct color so the UI
    -- can tint the reveal card / slot. `emoji` is a quick visual placeholder.
    -- color is {r, g, b} in 0-255; the client builds Color3.fromRGB(r, g, b).
    speciesOrder = { "sigma_sloth", "gigachad_goose", "boombox_bear", "rizz_raccoon", "skillissue_squid" },

    -- Roll weights for the species draw (uniform by default). Range per: 0-1000.
    speciesRollWeights = {
        sigma_sloth = 20,
        gigachad_goose = 20,
        boombox_bear = 20,
        rizz_raccoon = 20,
        skillissue_squid = 20,
    },

    species = {
        sigma_sloth = {
            id = "sigma_sloth",
            name = "Sigma Sloth",
            color = { 120, 180, 90 }, -- mossy green
            emoji = "🦥",
        },
        gigachad_goose = {
            id = "gigachad_goose",
            name = "Gigachad Goose",
            color = { 240, 240, 230 }, -- marble white
            emoji = "🪿",
        },
        boombox_bear = {
            id = "boombox_bear",
            name = "Boombox Bear",
            color = { 150, 90, 60 }, -- brown
            emoji = "🐻",
        },
        rizz_raccoon = {
            id = "rizz_raccoon",
            name = "Rizz Raccoon",
            color = { 110, 120, 140 }, -- slate gray
            emoji = "🦝",
        },
        skillissue_squid = {
            id = "skillissue_squid",
            name = "Skill-Issue Squid",
            color = { 230, 90, 200 }, -- hot pink
            emoji = "🦑",
        },
    },

    -- ── MOMENT TEXT ──────────────────────────────────────────────────────
    -- Player-facing one-liners per moment kind. The server picks the text and
    -- ships it in the Moment payload so the client just displays it. Kept inline
    -- here for the demo (production would centralize in a localization file).
    momentText = {
        hyper_break = "is taking a quick break...",
        hyper_zoom = "is BACK — zooming! ⚡",
        lazy_zzz = "dozed off... zzz 😴",
        chaotic_double = "went off — DOUBLE output! 🎲",
        chaotic_zero = "fumbled the cycle — zero output. 🎲",
        loyal_steady = "keeps grinding, steady as ever. 💪",
        rebel_walkout = "walked out in protest! ✊",
    },

    -- ── 3D SCENE DEMO ────────────────────────────────────────────────────
    -- Tunables specific to the PLAYABLE 3D-scene slice. The 5 deployed workers
    -- are Models pre-placed in workspace, named EXACTLY `Brainrot_<P>` where
    -- <P> is an UPPERCASE personality id (HYPER/LAZY/CHAOTIC/LOYAL/REBEL). The
    -- server finds them by name each tick (it does NOT manage the Workspace).
    demo3d = {
        -- Prefix + the exact in-workspace model names the server scans for. The
        -- personality is the suffix (mapped case-insensitively to personalityOrder).
        creaturePrefix = "Brainrot_",
        creatureNames = {
            "Brainrot_HYPER",
            "Brainrot_LAZY",
            "Brainrot_CHAOTIC",
            "Brainrot_LOYAL",
            "Brainrot_REBEL",
        },
        -- Name of the head part to anchor the catch prompt to. Falls back to the
        -- model PrimaryPart, then the first BasePart found. String | Default: "Head"
        headPartName = "Head",
        -- Flat coin bonus awarded by OpenCrate (a "reveal teaser" in this fixed-5
        -- demo — it does NOT add workers). Range: 0-1000 | Default: 25
        crateRevealBonus = 25,

        -- ── CAPTURE LOOP (the demo's star) ───────────────────────────────
        -- How long the player must HOLD the catch key (ProximityPrompt
        -- HoldDuration, seconds). Range: 0-3 | Default: 0.6
        catchHoldSec = 0.6,
        -- Max distance (studs) the catch prompt is activatable from
        -- (ProximityPrompt MaxActivationDistance). Range: 4-32 | Default: 12
        catchDistance = 12,
        -- Seconds before a caught creature respawns at its original CFrame so the
        -- demo is repeatable. Range: 1-60 | Default: 6
        creatureRespawnSec = 6,
        -- ActionText shown on the catch ProximityPrompt. String | Default: "Catch"
        catchActionText = "Catch",

        -- ── RECALL (undeploy a Showroom creature back into inventory) ────
        -- How long the player must HOLD the recall key on a deployed creature
        -- (ProximityPrompt HoldDuration, seconds). Range: 0-3 | Default: 0.5
        recallHoldSec = 0.5,
        -- Max distance (studs) the recall prompt is activatable from
        -- (ProximityPrompt MaxActivationDistance). Range: 4-32 | Default: 12
        recallDistance = 12,
        -- ActionText shown on the recall ProximityPrompt. String | Default: "Recall"
        recallActionText = "Recall",

        -- ── PLACE (pick which creature stands on a SPECIFIC empty podium) ──
        -- Every EMPTY DisplayStand carries a "Place" ProximityPrompt. Triggering
        -- it opens the place menu for THAT stand; the player taps a caught
        -- Brainrot to deploy it there (server-authoritative). A stand has EITHER
        -- a Place prompt (empty) OR a Recall prompt (occupied) — never both.
        -- How long the player must HOLD the place key (ProximityPrompt
        -- HoldDuration, seconds). 0 = instant tap. Range: 0-3 | Default: 0
        placeHoldSec = 0,
        -- Max distance (studs) the place prompt is activatable from
        -- (ProximityPrompt MaxActivationDistance). Range: 4-32 | Default: 12
        placeDistance = 12,
        -- ActionText shown on the place ProximityPrompt. String | Default: "Place Brainrot"
        placeActionText = "Place Brainrot",
        -- ObjectText shown on the place ProximityPrompt (kept empty — the stand
        -- index is conveyed by the menu the prompt opens). String | Default: ""
        placeObjectText = "",

        -- Name of the BillboardGui on wild creatures stripped from display
        -- templates (the floating persona label). String | Default: "PersonaLabel"
        personaLabelName = "PersonaLabel",
    },

    -- ── SHOWROOM (deploy → display → idle-production → collect) ───────────
    -- The Showroom Model lives in the Workspace (built in Studio; Argon does
    -- NOT manage Workspace). It holds N display pedestals named
    -- `<showroomStandPrefix><i>` for i = 1..showroomStandCount (e.g.
    -- "DisplayStand1".."DisplayStand6"). A deployed Brainrot stands on TOP of a
    -- free pedestal and produces coins over time. The server finds stands by
    -- name; it does NOT manage / create the Workspace geometry.
    showroom = {
        -- How many display pedestals the Showroom exposes (must match the count
        -- of `DisplayStandN` parts built in Studio). Range: 1-12 | Default: 6
        showroomStandCount = 6,
        -- Exact name prefix of each pedestal Part. The stand index is the
        -- numeric suffix (1..showroomStandCount). String | Default: "DisplayStand"
        showroomStandPrefix = "DisplayStand",
        -- Name of the Showroom Model in the Workspace. String | Default: "Showroom"
        modelName = "Showroom",
        -- Vertical clearance (studs) added above the pedestal top so the placed
        -- creature's feet clear the glowing `Top` child. Range: 0-4 | Default: 0.4
        standClearanceStuds = 0.4,
    },

    -- ── WILD BRAINROT AI (server-authoritative roaming) ─────────────────────
    -- The wild creatures (Brainrot_<P>) are rigged with a Humanoid + an
    -- (invisible) HumanoidRootPart so the server can walk them via Humanoid:MoveTo.
    -- The AI keeps each one near its SPAWN ("home") so they mill around the wild
    -- area without invading the Showroom. The server OWNS this (NetworkOwner=server).
    wild = {
        -- Walk speed applied to each wild Humanoid on first sight (overrides the
        -- rig value so this config is the single source). Range: 1-16 | Default: 6
        walkSpeed = 6,
        -- How far (studs) from its home a wild creature may pick a wander target.
        -- Keep small so they stay clustered at the spawn. Range: 2-40 | Default: 10
        wanderRadius = 10,
        -- Random pause (seconds) between reaching a target and picking the next.
        -- A fresh target is drawn uniformly in [min, max]. Range: 0.5-15
        wanderPauseMinSec = 1.5,
        wanderPauseMaxSec = 4.0,
        -- How often (seconds) the AI scheduler ticks to (re)assign wander targets.
        -- Coarse on purpose — MoveTo does the per-frame walking. Range: 0.1-1 | Default: 0.4
        aiTickSec = 0.4,
    },

    -- ── COMBAT (Tahap 2: SUMMON a fighter that auto-battles a wild Brainrot) ──
    -- A player summons an OWNED Brainrot from their bag as a TEMPORARY field
    -- FIGHTER (the bag is NOT consumed — summoning is ephemeral). The fighter
    -- roams to the NEAREST wild `Brainrot_<P>` and auto-battles it in real time.
    -- Win = owner gets coins, the wild faints + respawns (reuses the catch path).
    -- Fighter KO = it despawns (gentle, non-destructive — never owned the bag).
    -- The Humanoid's built-in over-head health bar is the combat HP display.
    -- The SERVER owns all of this (NetworkOwner=server on fighter roots).
    combat = {
        -- How far (studs) IN FRONT of the summoning player the fighter spawns.
        -- Range: 2-12 | Default: 5
        summonOffsetStuds = 5,
        -- WalkSpeed applied to a summoned fighter (a touch faster than the wild
        -- walkSpeed=6 so it can close distance). Range: 1-24 | Default: 10
        fighterWalkSpeed = 10,
        -- Fighter starting/Max HP (matches the wild MaxHealth of 100 so fights are
        -- readable on the built-in health bar). Range: 1-1000 | Default: 100
        fighterMaxHP = 100,
        -- Distance (studs) at which a fighter stops chasing and starts dealing
        -- damage to the wild it is engaging. Range: 2-16 | Default: 6
        attackRangeStuds = 6,
        -- Combat tick interval (seconds): one exchange of damage per tick while
        -- engaged. Drives both the seek cadence and the damage cadence.
        -- Range: 0.1-2 | Default: 0.5
        combatTickSec = 0.5,
        -- Damage the FIGHTER deals to the wild per combat tick (before any
        -- personality scale). Range: 1-100 | Default: 12
        fighterDamagePerTick = 12,
        -- Damage the WILD deals back to the fighter per combat tick (before any
        -- personality scale). Lower than the fighter's so summoning usually wins
        -- a 1v1 but is not free. Range: 1-100 | Default: 6
        wildDamagePerTick = 6,
        -- Coins awarded to the OWNER each time their fighter defeats a wild.
        -- Routed through the live coin float + the existing flush path.
        -- Range: 0-1000 | Default: 25
        winCoins = 25,
        -- Max simultaneously-active fighters per player (field stays readable +
        -- bounds the combat loop cost). Range: 1-10 | Default: 3
        maxActiveFighters = 3,
        -- How often (seconds) a fighter re-evaluates its nearest target while not
        -- yet engaged. Coarse — MoveTo does the per-frame walking. Range: 0.1-2 | Default: 0.5
        seekRetargetSec = 0.5,
        -- Auto-despawn a fighter this many seconds after it is summoned so the
        -- field self-cleans even if it never finds/finishes a fight.
        -- Range: 10-300 | Default: 60
        fighterLifetimeSec = 60,
        -- When true, multiply a combatant's per-tick damage by prodMult(personality)
        -- so a Hyper fighter hits ~1.3x and a Lazy one ~0.5x (reuses the existing
        -- production multiplier as a combat flavor knob). Boolean | Default: true
        personalityDamageScales = true,
    },

    -- ── CLIENT-ONLY COSMETICS (display values; server never reads these) ─────
    -- Moment label float over a creature's head (pop -> rise -> fade).
    -- studsRise: how far up the label drifts. Range: 0-20 | Default: 4
    momentFloatRiseStuds = 4,
    -- How long the moment label lives before it is destroyed (seconds).
    -- Range: 0.5-4 | Default: 1.1
    momentFloatLifeSec = 1.1,
    -- Idle "bob": cosmetic vertical sine on each creature so it looks alive.
    -- amplitude in studs. Range: 0-2 | Default: 0.35
    idleBobAmplitudeStuds = 0.35,
    -- Idle bob period (seconds for a full up/down cycle). Range: 0.5-8 | Default: 2.4
    idleBobPeriodSec = 2.4,
}
