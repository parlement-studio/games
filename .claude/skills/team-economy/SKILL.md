---
name: team-economy
description: Multi-agent orchestration for economy features. Coordinates economy-designer, monetization-lead, systems-designer, datastore-architect, ui-programmer, and exploit-security-specialist.
---

# /team-economy — Economy Feature Team

## Orchestration Flow

Economy features have the highest stakes — mistakes can cause inflation, exploits, or monetization disasters.

### Phase 1: Design
1. **economy-designer**: Design the feature's currency flow (faucets, sinks, pacing)
2. **monetization-lead**: If Robux is involved, design GamePass/DevProduct
3. **systems-designer**: Spec the feature in detail

### Phase 2: Architecture
4. **datastore-architect**: Design the data model changes
5. **remotes-networking-specialist**: Design remote contracts
6. **exploit-security-specialist**: Review for duplication, replay, negative value exploits
7. **technical-director** (escalation): Verify atomicity of any transactions

### Phase 3: Implementation
8. **luau-gameplay-programmer**: Implement feature logic
9. **ui-programmer**: Build shop/trade/transaction UI

### Phase 4: Balance
10. **economy-designer**: Tune values (prices, drop rates, earn rates)
11. **analytics-retention-specialist**: Add telemetry events to track economy health

### Phase 5: Quality
12. **qa-tester**: Test edge cases (zero balance, max balance, race conditions)
13. **exploit-security-specialist**: Final security pass

## Steps

### 1. Gather Context
- "What economy feature?" (new currency, shop, trading, cosmetic, etc.)
- "What's the player value?"
- "What's the intended earn rate / spend rate?"
- "Is this F2P-friendly or does it require Robux?"

### 2. Design Phase
- economy-designer drafts the feature
- If monetized, monetization-lead joins
- systems-designer details the spec
- User approves before architecture

### 3. Architecture Phase
- datastore-architect designs data changes (schema update with migration)
- remotes-networking-specialist designs remote contracts
- exploit-security-specialist reviews — THIS IS CRITICAL for economy features
- User approves the architecture (especially the security review)

### 4. Implementation Phase
- Implement with atomic operations where needed
- Transaction tracking with unique IDs
- Server-side validation on every step
- pcall around DataStore
- Idempotency for MarketplaceService.ProcessReceipt

### 5. Balance Phase
- Run `/balance-check` on the new feature
- Model projected economy impact over 30 days
- Tune values based on projections

### 6. Quality Phase
- Test: buy with exact balance, with insufficient balance, with max items
- Test: rapid repeated purchase (debouncing)
- Test: disconnect mid-purchase
- Test: trade with another player (if applicable), trade during mid-save
- Test: transaction while DataStore is slow

## Output
A complete economy feature: design → data model → atomic implementation → secure → balanced → tested.

## Quality Checks
- [ ] No duplication vectors
- [ ] No negative value exploits
- [ ] Atomic transactions
- [ ] Idempotent purchase processing
- [ ] Schema migration (if needed) tested
- [ ] `/economy-audit` passes
- [ ] `/exploit-check` passes
- [ ] Telemetry events added
- [ ] Balance modeled and reasonable
