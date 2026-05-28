--!strict
-- ServerStorage/Personality/PersonalityService.luau
--
-- The Personality System CORE (Creative Pillar #2), per
-- design/gdd/personality-gdd.md (v1.1). SERVER-ONLY, server-authoritative.
-- The shared MODIFIER LAYER: it stores one enum field per Brainrot (via
-- Persistence) and exposes config-driven trait queries + a tiny runtime state
-- machine (Working / OnBreak / Walkout) that consumers (Idle #3, Battle #5,
-- Raid #6, Evolution #8, Moment #12, Reroll #11) read to flavor THEIR behavior.
-- It implements NO consumer system.
--
-- ALL multipliers / probabilities / thresholds / durations are READ from
-- PersonalityConfig (§8). There are ZERO hardcoded personality numbers here —
-- a grep of this file finds none (the validator's uniform fallback also lives
-- in config). Per gameplay-systems rules: numbers in config, logic in code.
--
-- ── SIGNATURE RECONCILIATION (implementability vs GDD §2.2 prose) ───────────
-- The GDD prose lists some queries as `(id)`. But the per-Brainrot `personality`
-- enum lives in the per-PLAYER roster owned by Persistence (keyed by
-- BrainrotEntry.id), and the CALLER (Idle / Battle) already holds the
-- BrainrotEntry. So this core takes the PERSONALITY enum (pure config queries)
-- or a BrainrotEntry (production query) rather than a bare `id` it would have to
-- resolve against a player it does not own:
--   * getBattleBehavior(personality)   -> { behaviorTag, params }     (F4)
--   * isImmuneToNegative(personality)  -> boolean
--   * getMoraleAura(personality)       -> { neighborMultiplier, radiusSlots } | nil
--   * getProductionModifier(entry, ctx)-> { multiplier, paused, cycleOutcome? } (F1)
-- The runtime STATE machine is keyed by entry.id in server memory (§3.2). The
-- roll / reroll / repair paths take (player, id) and write the field through the
-- audited PlayerDataService.update() atomic path. The VALUE of `id` is unchanged
-- (the canonical GUID) — only the parameter shape is reconciled. This is a
-- naming/shape reconciliation only; behavior matches the GDD exactly.
--
-- ANTI-EXPLOIT (§4 authority rule): every roll, reroll, multiplier, and state
-- transition is computed here on the server. Consumers ignore client-supplied
-- effect values; the client receives results only for display.
--
-- INJECTION (deterministic tests): setRandom(fn) / setClock(fn) / setLogger(fn),
-- and setBattleLockChecker(fn) so Battle (#5) wires the in-battle reroll lock
-- (E4) later. Defaults: math.random, os.clock, no-op logger, "never locked".

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local PersonalityConfig = require(ReplicatedStorage.Shared.Config.PersonalityConfig)
local Signal = require(ReplicatedStorage.Packages.Signal)

local PlayerDataService = require(ServerStorage.PlayerData.PlayerDataService)

type Personality = Types.Personality
type BrainrotEntry = Types.BrainrotEntry

-- Per-Brainrot ephemeral runtime state (§3.2). Server memory only, NOT
-- persisted; re-initialized to Working on a fresh session.
export type PersonalityRuntime = {
    state: string, -- "Working" | "OnBreak" | "Walkout"   default "Working"
    stateStartedAt: number, -- clock() server timestamp; default 0
    draggedInBy: string?, -- id of the Rebel that pulled this one in; default nil
    lastCycleOutcome: string?, -- Chaotic only: "double" | "zero" | nil
}

-- A morale-aware production context the consumer (Idle #3) supplies. Idle owns
-- adjacency / occupancy; Personality owns the aura PARAMS. `hasLazyNeighbor`
-- means "this entry has >=1 eligible Lazy neighbor within the aura radius",
-- already resolved by the caller against radiusSlots from getMoraleAura.
export type ProductionContext = {
    hasLazyNeighbor: boolean?,
}

export type ProductionModifier = {
    multiplier: number,
    paused: boolean,
    cycleOutcome: string?, -- Chaotic "double" | "zero" | nil (debug / Moment)
}

export type BattleBehavior = {
    behaviorTag: string,
    params: { [string]: any },
}

-- State enum (the ONLY three production-facing states, §2.5).
local STATE_WORKING = "Working"
local STATE_ON_BREAK = "OnBreak"
local STATE_WALKOUT = "Walkout"

-- Allowed transitions (state machine, §2.5). Working <-> OnBreak (Hyper),
-- Working <-> Walkout (Rebel); reroll resets any state to Working.
local ALLOWED_TRANSITIONS: { [string]: { [string]: boolean } } = {
    [STATE_WORKING] = { [STATE_ON_BREAK] = true, [STATE_WALKOUT] = true, [STATE_WORKING] = true },
    [STATE_ON_BREAK] = { [STATE_WORKING] = true },
    [STATE_WALKOUT] = { [STATE_WORKING] = true },
}

-- momentType enum (§5.3). Exposed so consumers/tests reference the contract.
local MomentType = {
    BreakStarted = "break_started",
    WalkoutStarted = "walkout_started",
    WalkoutChained = "walkout_chained",
    ChaoticDouble = "chaotic_double",
    ChaoticZero = "chaotic_zero",
    LoyalBlocked = "loyal_blocked",
    RebelCountered = "rebel_countered",
    HyperMistarget = "hyper_mistarget",
    LazyBerserk = "lazy_berserk",
}

local PersonalityService = {}

PersonalityService.STATE_WORKING = STATE_WORKING
PersonalityService.STATE_ON_BREAK = STATE_ON_BREAK
PersonalityService.STATE_WALKOUT = STATE_WALKOUT
PersonalityService.MomentType = MomentType

-- ── Module-level Signals (internal server events, §5.3) ────────────────────
-- Cross-system decoupling per the gameplay-systems rule. Consumers Connect.
PersonalityService.PersonalityChanged = Signal.new() -- { id, oldPersonality, newPersonality }
PersonalityService.PersonalityMoment = Signal.new() -- { id, momentType, personality, payload, serverTime }
PersonalityService.WalkoutStarted = Signal.new() -- { id, draggedIds: {string} }

-- ── Injected dependencies (overridable for tests) ──────────────────────────

-- Server RNG. Default math.random; tests inject a seeded/deterministic source.
-- Contract: random() -> number in [0, 1).
local random: () -> number = math.random

-- Server clock. Default os.clock (monotonic), matching §3.2's clock-based
-- timestamps. Tests inject a controllable clock.
local clock: () -> number = os.clock

-- Structured logger (analytics incidents: personality_repaired, ...). nil-safe.
local logger: ((event: string, payload: { [string]: any }) -> ())? = nil

-- In-battle lock checker (E4). Battle (#5) installs this so a reroll is rejected
-- while the Brainrot id is a combatant in an active session. DEFAULT: never
-- locked, so the core is usable before Battle exists.
local battleLockChecker: (id: string) -> boolean = function(_id: string): boolean
    return false
end

-- ── State ──────────────────────────────────────────────────────────────────
-- Ephemeral per-Brainrot runtime, keyed by entry.id (§3.2). Lost on restart.
local runtimeState: { [string]: PersonalityRuntime } = {}

-- ── Helpers ─────────────────────────────────────────────────────────────────

local function log(event: string, payload: { [string]: any })
    if logger then
        logger(event, payload)
    end
end

-- Reads a trait sub-table for a personality, or nil for an unknown enum.
local function traitFor(personality: string): PersonalityConfig.Trait?
    return PersonalityConfig.traits[personality]
end

-- Resolves an unknown/missing personality to the config fallback for ONE
-- defensive tick (E5). A VALID enum passes through unchanged.
local function resolveOrFallback(personality: any): string
    if type(personality) == "string" and PersonalityConfig.traits[personality] ~= nil then
        return personality
    end
    return PersonalityConfig.fallbackPersonality
end

-- Returns (creating if absent) the runtime row for an id. Default Working.
local function runtimeFor(id: string): PersonalityRuntime
    local rt = runtimeState[id]
    if rt == nil then
        rt = {
            state = STATE_WORKING,
            stateStartedAt = 0,
            draggedInBy = nil,
            lastCycleOutcome = nil,
        }
        runtimeState[id] = rt
    end
    return rt
end

-- Performs a guarded state transition (returns false if disallowed, §2.5). All
-- mutation of runtime state goes through here so the machine can ONLY take the
-- documented edges.
local function transition(id: string, toState: string, now: number): boolean
    local rt = runtimeFor(id)
    local allowedFrom = ALLOWED_TRANSITIONS[rt.state]
    if allowedFrom == nil or allowedFrom[toState] ~= true then
        return false
    end
    rt.state = toState
    rt.stateStartedAt = now
    return true
end

-- Emits a PersonalityMoment with the §5.3 payload shape.
local function emitMoment(id: string, momentType: string, personality: string, payload: { [string]: any }?)
    PersonalityService.PersonalityMoment:Fire({
        id = id,
        momentType = momentType,
        personality = personality,
        payload = payload or {},
        serverTime = clock(),
    })
end

-- ── Dependency injection (tests / wiring) ──────────────────────────────────

-- Inject the server RNG (deterministic distribution + roll tests). [0,1).
function PersonalityService.setRandom(fn: () -> number)
    random = fn
end

-- Inject the server clock (deterministic state-machine timer tests).
function PersonalityService.setClock(fn: () -> number)
    clock = fn
end

-- Inject a structured logger.
function PersonalityService.setLogger(fn: (event: string, payload: { [string]: any }) -> ())
    logger = fn
end

-- Battle (#5) installs the in-battle lock checker (E4). fn(id) -> true means the
-- id is locked in an active battle and a reroll must be rejected.
function PersonalityService.setBattleLockChecker(fn: (id: string) -> boolean)
    battleLockChecker = fn
end

-- ── Pure config queries (consumers READ these) ─────────────────────────────

-- F4: the battle behavior tag + params for a personality. Battle owns the
-- mechanic; this owns the tag + numbers. An unknown enum falls back (E5).
function PersonalityService.getBattleBehavior(personality: string): BattleBehavior
    local key = resolveOrFallback(personality)
    local trait = traitFor(key) :: PersonalityConfig.Trait
    -- Build a params table per tag, copying ONLY the relevant config fields so a
    -- consumer never sees unrelated knobs (and so adding a 6th personality is a
    -- config entry + one Battle handler — §2.2 #5).
    local tag = trait.battleBehaviorTag
    local params: { [string]: any } = {}
    if tag == "act_first_mistarget" then
        params.mistargetChance = trait.mistargetChance
    elseif tag == "berserk_when_last" then
        params.defenseMultiplier = trait.defenseMultiplier
        params.berserkAttackMultiplier = trait.berserkAttackMultiplier
    elseif tag == "random_moveset" then
        params.randomFromAnyMoveset = trait.randomFromAnyMoveset
    elseif tag == "bodyguard" then
        params.bodyguardAllyHpThreshold = trait.bodyguardAllyHpThreshold
        params.bodyguardDamageTakenFraction = trait.bodyguardDamageTakenFraction
    elseif tag == "counter_double" then
        params.counterDamageMultiplier = trait.counterDamageMultiplier
    end
    return { behaviorTag = tag, params = params }
end

-- True iff this personality is immune to negative Moment/event production
-- effects (Loyal). Idle skips externally-applied negatives before F1 (§F1 note).
function PersonalityService.isImmuneToNegative(personality: string): boolean
    local trait = traitFor(resolveOrFallback(personality))
    return trait ~= nil and trait.immuneToNegativeEvents == true
end

-- The morale-aura params for a personality, or nil if it has none (only Lazy
-- emits one). The recipient applies it (E1: aura is computed by the recipient).
function PersonalityService.getMoraleAura(personality: string): PersonalityConfig.MoraleAura?
    local trait = traitFor(resolveOrFallback(personality))
    return if trait then trait.moraleAura else nil
end

-- ── Production modifier (F1) ─────────────────────────────────────────────────

-- F1: resolves the effective per-cycle production MULTIPLIER for a Brainrot.
-- Idle Production multiplies ITS own base rate by `multiplier` and respects
-- `paused`. This applies the personality factors:
--   personalityMult           = traits[p].productionMultiplier
--   chaoticCycleFactor         = Chaotic only: double or zero (per-cycle coin)
--   moraleFactor               = non-Lazy AND ctx.hasLazyNeighbor -> neighborMultiplier
--   paused                     = runtime state is OnBreak or Walkout
-- Chaotic records lastCycleOutcome and fires a chaotic_double/chaotic_zero
-- Moment (E3 single-producer is valid: per-Brainrot, not relative to others).
-- Bounds: multiplier >= 0 always (zero-floored by zeroMultiplier / paused).
function PersonalityService.getProductionModifier(entry: BrainrotEntry, context: ProductionContext?): ProductionModifier
    local ctx = context or {}
    local key = resolveOrFallback(entry.personality)
    local trait = traitFor(key) :: PersonalityConfig.Trait
    local rt = runtimeFor(entry.id)

    local paused = rt.state == STATE_ON_BREAK or rt.state == STATE_WALKOUT

    local multiplier = trait.productionMultiplier

    -- Chaotic per-cycle coin flip (F1 chaoticCycleFactor). Record the outcome +
    -- emit a Moment so a kid sees WHY a zero cycle happened (E3).
    local cycleOutcome: string? = nil
    if trait.doubleChance ~= nil and trait.doubleMultiplier ~= nil and trait.zeroMultiplier ~= nil then
        if random() < trait.doubleChance then
            multiplier *= trait.doubleMultiplier
            cycleOutcome = "double"
            emitMoment(entry.id, MomentType.ChaoticDouble, key)
        else
            multiplier *= trait.zeroMultiplier
            cycleOutcome = "zero"
            emitMoment(entry.id, MomentType.ChaoticZero, key)
        end
        rt.lastCycleOutcome = cycleOutcome
    end

    -- Morale factor (F1). The recipient (this entry) applies a Lazy neighbor's
    -- aura iff it is itself non-Lazy (Lazy never receives by default, E1) and
    -- the caller reported an eligible Lazy neighbor. The aura PARAMS come from
    -- the Lazy trait, read here from config.
    if ctx.hasLazyNeighbor == true then
        local lazyTrait = traitFor("Lazy")
        local lazyAura = if lazyTrait then lazyTrait.moraleAura else nil
        local lazyAffectsLazy = lazyTrait ~= nil and lazyTrait.moraleAuraAffectsLazy == true
        if lazyAura ~= nil and (key ~= "Lazy" or lazyAffectsLazy) then
            multiplier *= lazyAura.neighborMultiplier
        end
    end

    return {
        multiplier = multiplier,
        paused = paused,
        cycleOutcome = cycleOutcome,
    }
end

-- ── Roll / reroll (F5) ───────────────────────────────────────────────────────

-- Draws weighted from a sanitized rollWeights map over PersonalityConfig.order.
-- The caller passes the VALIDATED weights (validate() ran at boot, E6), so `sum`
-- is never 0. Server RNG only.
local function drawWeighted(weights: PersonalityConfig.RollWeights, exclude: string?): string
    local order = PersonalityConfig.order
    local sum = 0
    for _, key in ipairs(order) do
        if key ~= exclude then
            sum += (weights[key] or 0)
        end
    end
    -- Defensive: if excluding the only positive-weight key left nothing, ignore
    -- the exclusion (cannot guarantee a different result if no other has weight).
    if sum <= 0 then
        sum = 0
        for _, key in ipairs(order) do
            sum += (weights[key] or 0)
        end
        exclude = nil
    end

    local r = random() * sum
    local running = 0
    for _, key in ipairs(order) do
        if key ~= exclude then
            running += (weights[key] or 0)
            if running > r then
                return key
            end
        end
    end
    -- Floating-point fallthrough: return the last positive-weight key.
    for i = #order, 1, -1 do
        local key = order[i]
        if key ~= exclude and (weights[key] or 0) > 0 then
            return key
        end
    end
    return PersonalityConfig.fallbackPersonality
end

-- The sanitized weights, computed lazily once (validate() also runs at boot;
-- this caches the result so every roll reads identical odds). A test that mutates
-- config + wants a re-validate calls _resetValidatedWeightsForTest first.
local validatedWeights: PersonalityConfig.RollWeights? = nil

local function getValidatedWeights(): PersonalityConfig.RollWeights
    if validatedWeights == nil then
        validatedWeights = PersonalityConfig.validate(logger)
    end
    return validatedWeights :: PersonalityConfig.RollWeights
end

-- F5: roll a personality from the validated weights. Server-side RNG only; the
-- client is told the result, never the roll (§2.3).
function PersonalityService.rollPersonality(): string
    return drawWeighted(getValidatedWeights())
end

-- Resets a Brainrot's runtime to Working and clears its timers / drag / outcome
-- (used by reroll + repair, §2.4 #2 / §2.5).
function PersonalityService.resetToWorking(id: string)
    runtimeState[id] = {
        state = STATE_WORKING,
        stateStartedAt = clock(),
        draggedInBy = nil,
        lastCycleOutcome = nil,
    }
end

export type RerollOptions = {
    idempotencyKey: string?,
    guaranteeDifferent: boolean?,
}

-- F5 / §2.4 / E4 / E7: authoritative re-draw + atomic field write.
--   * Rejects with reason "in_battle" if the id is battle-locked (E4).
--   * Rejects with reason "not_found" if the player does not own the id.
--   * Re-draws from the SAME rollWeights; honors rerollGuaranteeDifferent (or an
--     opts override) — a guaranteed-different draw excludes the current value.
--   * Writes the `personality` field via PlayerDataService.update() with the
--     supplied idempotencyKey, so a retried key returns the PRIOR committed
--     result (no double-roll, no double-charge — E7). The atomic mutator is
--     NON-YIELDING: the new personality is pre-drawn BEFORE update() is called.
--   * Resets runtime to Working + clears timers; emits PersonalityChanged.
-- Cost / cap / UX are Reroll #11 (OUT OF SCOPE) — this does only the draw+write.
-- Returns (true, newPersonality) | (false, reason).
function PersonalityService.rerollPersonality(player: Player, id: string, opts: RerollOptions?): (boolean, string)
    local options = opts or {}

    -- E4: reject mid-battle BEFORE any draw so behavior tags cannot desync.
    if battleLockChecker(id) then
        return false, "in_battle"
    end

    local entry = PlayerDataService.getBrainrot(player, id)
    if entry == nil then
        return false, "not_found"
    end

    -- E7: if this idempotency key already committed, return the PRIOR result
    -- (the stored new personality) WITHOUT drawing again. update() returns the
    -- stored result on replay; we surface it so a retried reroll is a no-op.
    local idempotencyKey = options.idempotencyKey

    -- Pre-draw OUTSIDE the mutator (mutators must be non-yielding & side-effect
    -- free w.r.t. RNG so a rollback cannot "consume" a roll inconsistently).
    local guaranteeDifferent = options.guaranteeDifferent
    if guaranteeDifferent == nil then
        guaranteeDifferent = PersonalityConfig.rerollGuaranteeDifferent
    end
    local exclude: string? = nil
    if guaranteeDifferent then
        exclude = entry.personality
    end
    local newPersonality = drawWeighted(getValidatedWeights(), exclude)
    local oldPersonality = entry.personality

    local ok, result, wasDuplicate = PlayerDataService.update(player, function(data)
        local row = data.roster[id]
        if row == nil then
            error("not_found", 0)
        end
        local prior = row.personality
        row.personality = newPersonality
        -- Stored result (small, JSON-safe): the committed personality + the
        -- prior, so an E7 replay returns the SAME committed value.
        return { personality = newPersonality, old = prior }
    end, idempotencyKey)

    if not ok then
        return false, tostring(result)
    end

    local committed: string = if type(result) == "table" and result.personality ~= nil
        then result.personality
        else newPersonality

    -- Reset runtime + emit PersonalityChanged ONLY on a fresh commit. On an E7
    -- replay (wasDuplicate) the prior commit already did this; we must NOT
    -- re-fire or re-roll. Return the prior committed personality.
    if not wasDuplicate then
        PersonalityService.resetToWorking(id)
        PersonalityService.PersonalityChanged:Fire({
            id = id,
            oldPersonality = oldPersonality,
            newPersonality = committed,
        })
    end

    return true, committed
end

-- ── Load-time repair (E5) ────────────────────────────────────────────────────

-- E5: if a roster entry's `personality` is missing/empty/unknown, re-roll a
-- fresh one, write it back through PlayerDataService, log personality_repaired,
-- and emit PersonalityRevealed (via the changed signal carrying old=nil). Never
-- crashes; consumers defensively treat an unknown enum as fallbackPersonality
-- for the single tick before repair completes. Returns (repaired, personality).
function PersonalityService.validateOrRepair(player: Player, id: string, entry: BrainrotEntry): (boolean, string)
    if PersonalityConfig.traits[entry.personality] ~= nil then
        return false, entry.personality -- already valid: nothing to repair
    end

    local newPersonality = PersonalityService.rollPersonality()
    local oldValue = entry.personality

    local ok = PlayerDataService.update(player, function(data)
        local row = data.roster[id]
        if row == nil then
            error("not_found", 0)
        end
        row.personality = newPersonality
        return { personality = newPersonality }
    end)

    if not ok then
        -- Could not persist (not loaded / mutation error). Caller treats the
        -- entry as fallbackPersonality for now; repair retries on next load.
        log("personality_repair_failed", { id = id, was = tostring(oldValue) })
        return false, PersonalityConfig.fallbackPersonality
    end

    PersonalityService.resetToWorking(id)
    log("personality_repaired", { id = id, was = tostring(oldValue), now = newPersonality })
    -- PersonalityRevealed (network) is fired by the bootstrap pass-through; the
    -- internal signal carries old=nil to mark a (re)assignment, not a reroll.
    PersonalityService.PersonalityChanged:Fire({
        id = id,
        oldPersonality = nil,
        newPersonality = newPersonality,
    })
    return true, newPersonality
end

-- ── State machine: Hyper break (F2) ─────────────────────────────────────────

-- F2: per production cycle, a Working Hyper may enter OnBreak (Bernoulli vs
-- breakChance). Non-Hyper / non-Working is a no-op. Returns true iff it broke.
-- `now` is the server clock value the CALLER passes (so a tick batch shares one
-- timestamp); defaults to the injected clock.
function PersonalityService.tryStartBreak(entry: BrainrotEntry, now: number?): boolean
    local key = resolveOrFallback(entry.personality)
    local trait = traitFor(key)
    if trait == nil or trait.breakChance == nil then
        return false -- not a personality that breaks
    end
    local rt = runtimeFor(entry.id)
    if rt.state ~= STATE_WORKING then
        return false
    end
    if random() >= trait.breakChance then
        return false
    end
    local t = now or clock()
    if not transition(entry.id, STATE_ON_BREAK, t) then
        return false
    end
    emitMoment(entry.id, MomentType.BreakStarted, key, { until_ = t + (trait.breakDurationSeconds or 0) })
    return true
end

-- ── State machine: Rebel walkout + contagion (F3, E2) ───────────────────────

-- F3 / E2: a Working overworked Rebel may start a Walkout, dragging co-located
-- Working neighbors. CONTAGION IS BOUNDED + PROVABLY TERMINATING: it is rolled
-- ONCE per neighbor of the INITIATOR only (never recursively re-rolled on the
-- same target), so the loop runs at most #neighbors times.
--
-- buildingContext (caller-supplied; the caller owns adjacency / occupancy):
--   rebelCount: number       -- count of Rebels co-located in the SAME building
--   neighbors: { BrainrotEntry } -- other co-located Brainrots (n ~= entry)
--   cooldownUntil: number?   -- os.time()/clock the building's walkout cooldown
--                               ends; if now < cooldownUntil, the trigger is
--                               suppressed (E2 guard d).
-- Returns (started: boolean, draggedIds: { string }).
export type BuildingContext = {
    rebelCount: number,
    neighbors: { BrainrotEntry },
    cooldownUntil: number?,
}

function PersonalityService.tryStartWalkout(
    entry: BrainrotEntry,
    buildingContext: BuildingContext,
    now: number?
): (boolean, { string })
    local empty: { string } = {}
    local key = resolveOrFallback(entry.personality)
    local trait = traitFor(key)
    -- Only Rebel (the personality that carries walkout params) can initiate.
    if
        trait == nil
        or trait.overworkRebelCount == nil
        or trait.walkoutChance == nil
        or trait.walkoutContagionChance == nil
    then
        return false, empty
    end

    local t = now or clock()

    -- E2 guard (d): building on cooldown -> suppressed.
    local cooldownUntil = buildingContext.cooldownUntil
    if cooldownUntil ~= nil and t < cooldownUntil then
        return false, empty
    end

    local rt = runtimeFor(entry.id)
    if rt.state ~= STATE_WORKING then
        return false, empty
    end

    -- Overwork condition (F3): enough Rebels co-located.
    if buildingContext.rebelCount < trait.overworkRebelCount then
        return false, empty
    end

    -- Trigger roll (F3).
    if random() >= trait.walkoutChance then
        return false, empty
    end

    if not transition(entry.id, STATE_WALKOUT, t) then
        return false, empty
    end

    -- Contagion: ONE roll per Working neighbor (E2 — never recursive on the same
    -- target, guaranteeing termination). Cross-building drag is forbidden by
    -- construction: the caller only puts co-located neighbors in the context.
    local draggedIds: { string } = {}
    for _, neighbor in ipairs(buildingContext.neighbors) do
        if neighbor.id ~= entry.id then
            local nrt = runtimeFor(neighbor.id)
            if nrt.state == STATE_WORKING then
                if random() < trait.walkoutContagionChance then
                    if transition(neighbor.id, STATE_WALKOUT, t) then
                        nrt.draggedInBy = entry.id
                        table.insert(draggedIds, neighbor.id)
                        emitMoment(neighbor.id, MomentType.WalkoutChained, resolveOrFallback(neighbor.personality), {
                            draggedInBy = entry.id,
                        })
                    end
                end
            end
        end
    end

    PersonalityService.WalkoutStarted:Fire({ id = entry.id, draggedIds = draggedIds })
    emitMoment(entry.id, MomentType.WalkoutStarted, key, { draggedIds = draggedIds })
    return true, draggedIds
end

-- ── State machine: tick (auto-recovery, §2.5 / F2 / F3) ──────────────────────

-- Advances all runtime timers at `now` (server clock; defaults to injected):
--   * OnBreak  -> Working when now >= start + breakDurationSeconds (Hyper).
--   * Walkout  -> Working when now >= start + min(walkoutDurationSeconds,
--                 walkoutMaxDurationSeconds) (E2 duration cap), then the caller
--                 starts the building's walkoutCooldownSeconds (returned so the
--                 consumer — Idle, which owns the building record — sets it).
-- Returns a list of { id, from, to, cooldownSeconds? } transitions that fired,
-- so consumers (Idle) can react (un-pause producers, set building cooldown).
-- Durations are looked up from the entry's CURRENT personality; the per-id
-- personality is supplied by the caller via `personalityById` (Personality does
-- not own the roster). Missing -> uses fallback durations.
export type TickTransition = {
    id: string,
    from: string,
    to: string,
    cooldownSeconds: number?,
}

function PersonalityService.update(personalityById: { [string]: string }, now: number?): { TickTransition }
    local t = now or clock()
    local fired: { TickTransition } = {}

    for id, rt in pairs(runtimeState) do
        local key = resolveOrFallback(personalityById[id])
        local trait = traitFor(key)

        if rt.state == STATE_ON_BREAK then
            local duration = if trait then trait.breakDurationSeconds else nil
            if duration ~= nil and t >= rt.stateStartedAt + duration then
                if transition(id, STATE_WORKING, t) then
                    table.insert(fired, { id = id, from = STATE_ON_BREAK, to = STATE_WORKING })
                end
            end
        elseif rt.state == STATE_WALKOUT then
            local dur = if trait then trait.walkoutDurationSeconds else nil
            local maxDur = if trait then trait.walkoutMaxDurationSeconds else nil
            -- E2: bound by min(duration, maxDuration). If either is missing, use
            -- whichever exists (defensive); if both missing, do not auto-recover.
            local effective: number? = nil
            if dur ~= nil and maxDur ~= nil then
                effective = math.min(dur, maxDur)
            elseif dur ~= nil then
                effective = dur
            elseif maxDur ~= nil then
                effective = maxDur
            end
            if effective ~= nil and t >= rt.stateStartedAt + effective then
                if transition(id, STATE_WORKING, t) then
                    rt.draggedInBy = nil
                    -- Hand the building cooldown to the caller to apply (E2 guard
                    -- d). Personality reports it; Idle owns the building record.
                    table.insert(fired, {
                        id = id,
                        from = STATE_WALKOUT,
                        to = STATE_WORKING,
                        cooldownSeconds = if trait then trait.walkoutCooldownSeconds else nil,
                    })
                end
            end
        end
    end

    return fired
end

-- ── Runtime accessors ────────────────────────────────────────────────────────

-- The runtime state row for an id (read-only use by consumers / tests).
function PersonalityService.getRuntime(id: string): PersonalityRuntime
    return runtimeFor(id)
end

-- The current state string for an id (default Working).
function PersonalityService.getState(id: string): string
    return runtimeFor(id).state
end

-- ── Test support ─────────────────────────────────────────────────────────────

-- Test-only: clear all runtime state + the cached validated weights so each
-- spec starts isolated.
function PersonalityService._resetForTest()
    runtimeState = {}
    validatedWeights = nil
    battleLockChecker = function(_id: string): boolean
        return false
    end
end

-- Test-only: drop the cached validated weights so a spec that mutated config can
-- force a re-validate on the next roll.
function PersonalityService._resetValidatedWeightsForTest()
    validatedWeights = nil
end

-- Test-only: directly seed a runtime row (e.g. to set up a mid-OnBreak/Walkout
-- timer scenario without rolling for it).
function PersonalityService._setRuntimeForTest(id: string, rt: PersonalityRuntime)
    runtimeState[id] = rt
end

return PersonalityService
