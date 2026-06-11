--!strict
-- Shared/Demo/DemoConfig.luau
--
-- DEMO-ONLY tunables for the "Monster Relic" playable vertical slice.
-- This is the ROUGH PROTOTYPE config (briefing demo). It is intentionally
-- isolated under the `Demo/` namespace and is NOT the production config — the
-- real systems read PersonalityConfig / IdleConfig (see design/gdd/*). Values
-- here are flavored from idea/monsterInc.md + personality-gdd + idle-production-gdd
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
    -- Coins/sec produced by ONE deployed Monster at baseline (before any
    -- personality multiplier or moment factor). Range: 0.1-100 | Default: 2
    baseRatePerSlot = 2,
    -- Crate cost in coins. FREE for the demo so players can spam-open and feel
    -- the personality variety immediately. Range: 0-1e6 | Default: 0
    crateCost = 0,
    -- Roster cap (how many owned Monsters before OpenCrate is refused).
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
    -- Minimum seconds between two Moments emitted by the SAME Monster. Throttles
    -- moment spam so pop-ups stay readable. Range: 1-30 | Default: 4
    momentCooldownSec = 4,

    -- ── SPECIES DISPLAY NAMES (demo flavor; real species catalog comes with
    -- Capture v2 / world-universe). One name per ELEMENT — the demo's models
    -- are identical blobs, so the element drives the "species" identity on
    -- the Monster-tab cards (mock: "BlazeHound", "TideShell", ...).
    speciesNames = {
        Fire = "BlazeHound",
        Water = "TideShell",
        Volt = "ThunderPaw",
        Nature = "LeafyBug",
        Wind = "GaleWing",
    },

    -- ── CAPTURE MODE (S4 item flow vs legacy coin debit) ─────────────────
    -- true (S4-locked direction): a catch CONSUMES one Capture Net from the
    -- persisted backpack (profile.items; bought in the Kandang menu shop).
    -- false (FALLBACK SWITCH): revert to the direct coin debit in one line if
    -- the item flow misbehaves — the player must never be unable to catch.
    -- Boolean | Default: true
    captureUsesItems = true,

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
    -- are Models pre-placed in workspace, named EXACTLY `Monster_<P>` where
    -- <P> is an UPPERCASE personality id (HYPER/LAZY/CHAOTIC/LOYAL/REBEL). The
    -- server finds them by name each tick (it does NOT manage the Workspace).
    demo3d = {
        -- Prefix + the exact in-workspace model names the server scans for. The
        -- personality is the suffix (mapped case-insensitively to personalityOrder).
        creaturePrefix = "Monster_",
        creatureNames = {
            "Monster_HYPER",
            "Monster_LAZY",
            "Monster_CHAOTIC",
            "Monster_LOYAL",
            "Monster_REBEL",
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
        -- Monster to deploy it there (server-authoritative). A stand has EITHER
        -- a Place prompt (empty) OR a Recall prompt (occupied) — never both.
        -- How long the player must HOLD the place key (ProximityPrompt
        -- HoldDuration, seconds). 0 = instant tap. Range: 0-3 | Default: 0
        placeHoldSec = 0,
        -- Max distance (studs) the place prompt is activatable from
        -- (ProximityPrompt MaxActivationDistance). Range: 4-32 | Default: 12
        placeDistance = 12,
        -- ActionText shown on the place ProximityPrompt. String | Default: "Place Monster"
        placeActionText = "Place Monster",
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
    -- "DisplayStand1".."DisplayStand6"). A deployed Monster stands on TOP of a
    -- free pedestal and produces coins over time. The server finds stands by
    -- name; it does NOT manage / create the Workspace geometry.
    showroom = {
        -- How many display pedestals the Showroom exposes (must match the count
        -- of `DisplayStandN` parts built in Studio). Range: 1-12 | Default: 6
        showroomStandCount = 6,
        -- Exact name prefix of each pedestal Part. The stand index is the
        -- numeric suffix (1..showroomStandCount). String | Default: "DisplayStand"
        showroomStandPrefix = "DisplayStand",
        -- Name of the base Model in the Workspace (the "Cage" / Sanctuary base
        -- where deployed monsters live). Renamed from "Showroom" → "Cage"
        -- (2026-06-09). String | Default: "Cage"
        modelName = "Cage",
        -- Vertical clearance (studs) added above the pedestal top so the placed
        -- creature's feet clear the glowing `Top` child. Range: 0-4 | Default: 0.4
        standClearanceStuds = 0.4,
    },

    -- ── KANDANG (deployed monsters wander the open paddock) ────────────────
    -- The Showroom is visually a fenced open paddock ("Kandang"): deployed
    -- monsters are RIGGED clones (FighterTemplates) that wander freely inside
    -- the paddock floor instead of standing frozen on a pedestal. Production
    -- mechanics are UNCHANGED (the deployment map + rates are exactly the
    -- same) — this is presentation only. The paddock bounds are derived from
    -- the Showroom model's `Floor` part at runtime.
    kandang = {
        -- Master switch: false = legacy static display clones on the plates.
        -- Boolean | Default: true
        wanderEnabled = true,
        -- WalkSpeed for deployed wanderers (calm; slower than wilds so the
        -- kandang reads as a home, not a hunt zone). Range: 1-12 | Default: 4
        walkSpeed = 4,
        -- Random pause (seconds) between wander moves, drawn in [min, max].
        -- Range: 0.5-20
        wanderPauseMinSec = 2.0,
        wanderPauseMaxSec = 5.0,
        -- How often (seconds) the kandang AI scheduler ticks. Coarse — MoveTo
        -- does the per-frame walking. Range: 0.1-2 | Default: 0.5
        aiTickSec = 0.5,
        -- Inset (studs) from the paddock Floor edge when picking wander
        -- targets, so monsters do not hug/clip the fence. Range: 0-8 | Default: 2.5
        marginStuds = 2.5,

        -- ── KANDANG UPGRADE (the demo's PRIMARY coin sink) ─────────────────
        -- Buying kandang levels multiplies ALL deployed production. Costs come
        -- from the LOCKED EconomyConfig factory curve (200 * 1.35^n, cap 30) —
        -- this section owns only the demo-side production bonus.
        upgrade = {
            -- Production multiplier gained per kandang level:
            -- rate = baseRate * prodMult * (1 + bonusPerLevel * factoryLevel).
            -- Payback check @4 deployed (~8/s): Lv1 costs 200, grants ~+1.2/s
            -- -> ~3 min payback; the geometric cost curve stretches that fast.
            -- Range: 0.05-0.5 | Default: 0.15
            bonusPerLevel = 0.15,
        },

        -- ── KANDANG MENU (single F interaction at the gate terminal) ───────
        -- One ProximityPrompt on the `KandangTerminal` part replaces BOTH the
        -- per-plate Place prompts AND the per-monster Recall prompts: it opens
        -- a unified menu where the player places bag monsters into the
        -- first free slot and recalls (collect) deployed ones with a tap.
        menu = {
            -- Master switch: false = legacy per-plate/per-monster prompts.
            -- Boolean | Default: true
            enabled = true,
            -- Name of the invisible anchored Part (child of the Showroom
            -- model, placed at the gate in Studio) that anchors the prompt.
            -- String | Default: "KandangTerminal"
            terminalName = "KandangTerminal",
            -- Prompt strings (player-facing). ActionText | ObjectText.
            actionText = "Open Sanctuary",
            objectText = "",
            -- Hold duration on the prompt (seconds). Range: 0-2 | Default: 0
            holdSec = 0,
            -- Max activation distance (studs). Range: 4-32 | Default: 14
            distance = 14,
        },
    },

    -- ── MERCHANT NPC (item shop) ─────────────────────────────────────────────
    -- The item shop lives on a world NPC, not inside the kandang menu: the
    -- server finds `npcName` (renaming a leftover `legacyName` model if that is
    -- what the place still has), tags it with an overhead label, and attaches
    -- a ProximityPrompt that opens the client's shop modal.
    merchant = {
        -- Master switch: false = no shop NPC (purchases only via remotes).
        -- Boolean | Default: true
        enabled = true,
        -- Workspace model names: the NPC we want, and the legacy model to
        -- rename if the place hasn't been migrated yet.
        npcName = "Merchant",
        legacyName = "Noob",
        -- Overhead label above the NPC head (BillboardGui).
        labelText = "🛒 Merchant",
        -- Prompt strings (player-facing). ActionText | ObjectText.
        actionText = "Shop",
        objectText = "Merchant",
        -- Hold duration on the prompt (seconds). Range: 0-2 | Default: 0
        holdSec = 0,
        -- Max activation distance (studs). Range: 4-32 | Default: 12
        distance = 12,
    },

    -- ── CATCH CINEMATIC (client presentation on a successful catch) ─────────
    -- The server freezes the caught wild for `holdSec` and fires
    -- CatchCinematic at the catcher; the client plays: camera dolly-in →
    -- net throw (bezier arc) → impact burst → shake → suck-in shrink →
    -- poof → camera restore. Pure presentation — the mint already committed.
    catchCinematic = {
        -- Master switch (false = instant despawn, old behavior).
        -- Boolean | Default: true
        enabled = true,
        -- How long the SERVER keeps the frozen model before destroying it.
        -- Must outlast the whole client sequence. Range: 1-6 | Default: 3.0
        holdSec = 3.0,
        -- Net projectile flight time (player hand -> monster). Range: 0.2-1
        netFlightSec = 0.45,
        -- Struggle shake after the net lands. Range: 0.2-1 | Default: 0.45
        shakeSec = 0.45,
        -- Suck-in shrink (scale -> ~0) duration. Range: 0.3-1.2 | Default: 0.6
        shrinkSec = 0.6,
        -- Camera: dolly-in time, framing distance/height, zoom FOV, restore time.
        camInSec = 0.35,
        camDistance = 9, -- studs from the monster (toward the player side)
        camHeight = 2.5, -- studs above the monster pivot
        fovZoom = 55, -- punched-in FOV during the sequence (default cam ~70)
        restoreSec = 0.4,
        -- Net arc height (studs above the straight line). Range: 1-8 | Default: 4
        arcHeight = 4,
        -- THROW ANIMATION (Jalur A): a keyframe throw plays on the catcher's
        -- right arm via the Animator. Leave throwAnimationId = "" to use the
        -- code-authored KeyframeSequence (ThrowAnimation.luau) registered at
        -- runtime; set it to a published "rbxassetid://…" to use an uploaded
        -- asset instead. throwReleaseSec = when (into the anim) the net leaves
        -- the hand — the projectile launches at that moment.
        throwEnabled = true,
        throwAnimationId = "",
        throwReleaseSec = 0.2,
        -- FAIL VARIANT (catch missed): the same throw + net flight plays, then
        -- the net BOUNCES OFF and the monster stays (no shrink/poof). These tune
        -- the bounce-back beat.
        -- Net bounce-back flight time (monster -> back toward the player).
        -- Range: 0.15-0.6 | Default: 0.3
        failBounceSec = 0.3,
        -- Camera shake on the miss (shorter/softer than the success struggle).
        -- Range: 0.15-0.6 | Default: 0.3
        failShakeSec = 0.3,
    },

    -- ── CATCH RATE (capture can FAIL) ───────────────────────────────────────
    -- A capture attempt is no longer a guaranteed catch. The SERVER rolls the
    -- monster's hidden rarity first, derives a success probability from it, then
    -- rolls success. Rarer monsters are harder (RarityConfig.catchRateMult).
    -- A consecutive-fail "pity" bonus (anti-frustration) raises the odds each
    -- time you miss the SAME personality and resets on a catch. Everything here
    -- is applied SERVER-SIDE ONLY (the client never sees or supplies the roll).
    --   catchRate = clamp(
    --       baseCatchRate * RarityConfig.catchRateMult[rarity]
    --           + failStreak * pityStepPerFail,
    --       minCatchRate, maxCatchRate)
    catch = {
        -- Master switch. false = legacy behavior (every attempt always catches).
        -- Boolean | Default: true
        enabled = true,
        -- Base success probability for a Common monster before pity/clamp.
        -- Range: 0.1-1.0 | Default: 0.7
        baseCatchRate = 0.7,
        -- Hard clamp on the FINAL per-attempt rate. minCatchRate is the floor so
        -- a Legendary on a fresh streak is never literally 0% (kid-friendly);
        -- maxCatchRate keeps even a long pity streak from being a guaranteed
        -- catch on the rarest tiers. Range: 0-1 | Defaults: 0.15 / 0.95
        minCatchRate = 0.15,
        maxCatchRate = 0.95,
        -- PITY: probability ADDED per consecutive failed attempt on the SAME
        -- personality (resets to 0 on a successful catch of it). A handful of
        -- misses ramps the odds toward maxCatchRate so a player is never stuck.
        -- Range: 0-0.5 | Default: 0.12 (≈ 3-4 misses to climb a full tier)
        pityStepPerFail = 0.12,
        -- Consume the Capture Net (or coin/free cost) even when the catch FAILS.
        -- LOCKED true: a failed throw still spends the attempt — real risk + a
        -- consistent economy sink. Boolean | Default: true
        consumeNetOnFail = true,
        -- Cooldown (seconds) before the SAME wild can be re-attempted after a
        -- miss. Covers the fail cinematic so a spam-retry can't double-trigger.
        -- Range: 0.5-5 | Default: 1.5
        failCooldownSec = 1.5,
    },

    -- ── WILD MONSTER AI (server-authoritative roaming) ─────────────────────
    -- The wild creatures (Monster_<P>) are rigged with a Humanoid + an
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

    -- ── COMBAT (Phase 2: SUMMON a fighter that auto-battles a wild Monster) ──
    -- A player summons an OWNED Monster from their bag as a TEMPORARY field
    -- FIGHTER (the bag is NOT consumed — summoning is ephemeral). The fighter
    -- roams to the NEAREST wild `Monster_<P>` and auto-battles it in real time.
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
        -- Fighter Lv1 BASE Max HP (the level-1 baseline; the actual summoned HP is
        -- this scaled by progression.levelScale(level) — see PROGRESSION below).
        -- Matches the wild MaxHealth of 100 so a Lv1 fight reads cleanly on the
        -- built-in health bar. Range: 1-1000 | Default: 100
        fighterBaseHP = 100,
        -- Wild Monster Max HP (the wild Humanoid MaxHealth). Wilds are treated as
        -- level 1 for now, so this is also their effective HP. Kept here for
        -- symmetry with fighterBaseHP. Range: 1-1000 | Default: 100
        wildBaseHP = 100,
        -- Distance (studs) at which a fighter stops chasing and starts dealing
        -- damage to the wild it is engaging. Range: 2-16 | Default: 6
        attackRangeStuds = 6,
        -- COMBAT RING: how far (studs) from the TARGET wild each attacking fighter
        -- stands. When 2+ fighters engage the SAME wild they each take a DISTINCT
        -- slot on a ring around it (angle from their formation order) instead of
        -- piling onto the wild's exact position, so they do not stack/clip. MUST be
        -- < attackRangeStuds so a fighter at its ring slot is still within attack
        -- range and keeps dealing damage. Range: 1-attackRangeStuds | Default: 4
        combatRingRadiusStuds = 4,
        -- PET LEASH: a wild is only a valid target if it is within this distance
        -- of the OWNER PLAYER's character (HumanoidRootPart) — NOT the fighter's
        -- position, and NOT unbounded. A summoned Monster behaves like a pet: it
        -- only engages wilds inside this radius centered on the player, and follows
        -- the player otherwise. Range: 8-120 | Default: 30
        detectionRangeStuds = 30,
        -- FOLLOW: when no enemy is in the detection radius, the fighter walks to
        -- roughly this far from the player so it TRAILS rather than stacking on
        -- them (the follow point is this far from the player toward the fighter).
        -- Range: 2-20 | Default: 8
        followDistanceStuds = 8,
        -- FOLLOW DEADZONE: if the fighter is already within this of its OWN
        -- formation slot, it does NOT issue a new follow MoveTo (prevents
        -- jitter/twitching when already at its slot). Range: 1-15 | Default: 5
        followStopStuds = 5,
        -- FORMATION SPREAD (degrees): total arc, centered BEHIND the player,
        -- across which the active fighters fan out into a little squad so 2+ of
        -- them do not stack on the same follow point. With 1 fighter the angle is
        -- 0 (straight behind); with N they spread evenly across this arc.
        -- Range: 0-180 | Default: 90
        followSpreadDegrees = 90,
        -- FORMATION JITTER (studs): magnitude of a small random horizontal offset
        -- added to each fighter's formation slot so idle following looks organic
        -- (fighters shuffle subtly instead of standing frozen). Range: 0-6 | Default: 1.5
        followJitterStuds = 1.5,
        -- FORMATION JITTER PERIOD (seconds): how often each fighter re-rolls its
        -- jitter offset. Range: 0.5-10 | Default: 2.0
        followJitterPeriodSec = 2.0,
        -- Combat tick interval (seconds): one exchange of damage per tick while
        -- engaged. Drives both the seek cadence and the damage cadence.
        -- Range: 0.1-2 | Default: 0.5
        combatTickSec = 0.5,
        -- Fighter Lv1 BASE damage to the wild per combat tick (the level-1
        -- baseline; the actual per-tick damage is this scaled by
        -- progression.levelScale(level) and then by personality — see PROGRESSION).
        -- Range: 1-100 | Default: 12
        fighterBaseDamagePerTick = 12,
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
        -- ── MOVEMENT (stairs / island slopes) ───────────────────────────────
        -- Summoned fighters AND wilds path with Humanoid:MoveTo (no navmesh). By
        -- default a Humanoid refuses slopes steeper than ~45° and never hops a
        -- ledge, so blobs get stuck at stairs / island ramps. These two knobs let
        -- them climb + auto-hop small steps without a full PathfindingService pass.
        -- Auto-hop small ledges/steps. Boolean | Default: true
        autoJump = true,
        -- Max walkable slope angle (degrees). 89 ≈ near-vertical; 75 climbs steep
        -- island ramps + most stairs while still refusing walls. Range: 45-89 | Default: 75
        maxSlopeAngle = 75,
        -- ── SAFE ZONE / SUMMON GATING ───────────────────────────────────────
        -- CollectionService tag marking a Workspace BasePart as a safe zone (the
        -- Hunter Camp, merchant area, checkpoints). Monsters may only be SUMMONED
        -- inside one; the whole Sanctuary place is implicitly safe. String.
        safeZoneTag = "SafeZone",
        -- When true, a NEW summon is refused outside a safe zone (recall is always
        -- allowed, anywhere). Boolean | Default: true
        summonRequiresSafeZone = true,
        -- When true, a summoned fighter is a PERSISTENT companion: it follows the
        -- player until it dies or is recalled (re-summoning the same Monster toggles
        -- it off), ignoring the fighterLifetimeSec auto-despawn above.
        -- Boolean | Default: true
        fighterPersistent = true,
        -- Default combat stance for a new session: "attack" (fighters proactively
        -- hunt wilds within detectionRangeStuds) or "defense" (fighters only
        -- retaliate against a wild that attacks them — see wild aggro). Toggled by
        -- the player via the HUD stance button. String | Default: "attack"
        defaultStance = "attack",
    },

    -- ── EVOLUTION (sink S2, decisions/2026-06-07-economy-sinks-fase0.md) ────
    -- HYBRID: milestone level (FREE, from playing) gates eligibility; a coin
    -- ACTIVATION COST (x RarityConfig.evolveCostMult) triggers the evolve.
    -- evoStage persists on the roster entry (schema field shipped with
    -- Persistence #1). Combat payoff = statMult below; visual payoff = an
    -- element-colored aura (placeholder VFX until real art).
    evolution = {
        -- Activation cost per target stage (basis Common; x evolveCostMult).
        -- LOCKED S2 values — changing them is a design decision.
        baseCost = { 2500, 30000, 300000 },
        -- Level milestone required to evolve INTO stage i (same for every
        -- rarity — scarcity is already paid via the coin multiplier).
        -- LOCKED S2 values: Lv 5 / 15 / 30.
        levelMilestones = { 5, 15, 30 },
        -- ABSOLUTE combat stat multiplier at stage i (not stacked): a stage-2
        -- monster fights at x1.5, not x1.25*1.5. Stage 0 = x1.0.
        -- LOCKED S2 values. Range per value: 1.0-3.0
        statMult = { 1.25, 1.5, 2.0 },
        -- Hard stage ceiling. Range: 1-3 | Default: 3
        maxStage = 3,
        -- Extra uniform model scale at the FINAL stage only ("slightly
        -- bigger", decision doc S2 table). Range: 1.0-1.3 | Default: 1.1
        stage3ScaleMult = 1.1,
        -- AURA placeholder tuning per stage (ParticleEmitter on the root,
        -- color = ElementConfig.display[element].color).
        aura = {
            -- Particles/sec per stage (sparse glow -> dense swirl).
            -- Range per value: 1-60 | Defaults: 6 / 14 / 28
            rates = { 6, 14, 28 },
            -- Particle size (studs) per stage. Range: 0.1-2 | Defaults below.
            sizes = { 0.35, 0.5, 0.7 },
        },
    },

    -- ── PROGRESSION (LEVEL / XP — battle-gdd v1.2 F2) ────────────────────────
    -- XP comes ONLY from WINNING battles; LEVEL boosts ONLY combat stats
    -- (HP / ATK / damage), NEVER coin production (production stays personality-
    -- only). XP + level persist on the individual roster entry (the data fields
    -- already exist — see Schema.newMonster mints level=1, xp=0).
    progression = {
        -- XP a fighter's specific Monster gains each time it defeats a wild.
        -- Range: 1-1000 | Default: 50
        xpPerWin = 50,
        -- XP curve base. xpToNext(level) = xpCurveBase * level, so Lv1->2 = 100,
        -- Lv2->3 = 200, Lv3->4 = 300, … (linearly steeper). Range: 10-1000 | Default: 100
        xpCurveBase = 100,
        -- Per-level combat-stat growth (battle-gdd F2): a stat at `level` is
        -- base * (1 + statGrowthPerLevel * (level - 1)). 0.08 = +8% per level.
        -- Range: 0.0-1.0 | Default: 0.08
        statGrowthPerLevel = 0.08,
        -- Hard level ceiling (battle-gdd F2). A Monster never levels past this.
        -- Range: 1-1000 | Default: 100
        maxLevel = 100,
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
