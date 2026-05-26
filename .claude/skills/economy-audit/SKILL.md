---
name: economy-audit
description: Audit the in-game economy for balance, sustainability, and exploit resistance. Checks currency sinks vs. faucets, inflation risk, pricing consistency, and Robux monetization alignment.
---

# /economy-audit — Economy Balance Audit

## Delegate to: economy-designer (with monetization-lead for Robux items)

## Steps:

### 1. Map Currency Flows
- Identify all currencies (soft currency, premium currency, tokens, etc.)
- List all faucets (sources of currency): quest rewards, daily rewards, drops, etc.
- List all sinks (drains of currency): purchases, upgrades, repairs, etc.
- Calculate theoretical income/spend rates per session

### 2. Balance Analysis
- Is there net inflation or deflation over time?
- Are there adequate sinks to absorb faucet output?
- Is the time-to-earn reasonable for key purchases?
- Does premium currency (Robux purchases) offer fair value?

### 3. GamePass/DevProduct Review
- List all GamePasses with prices and benefits
- List all DevProducts with prices and effects
- Check for pay-to-win concerns
- Verify pricing follows Roblox conventions (clean Robux values)
- Estimate conversion rates and ARPDAU impact

### 4. Trading System (if exists)
- Check for duplication vectors
- Check for market manipulation potential
- Verify atomic swap implementation
- Check tax/fee mechanism (currency sink)

### 5. Progression Pacing
- Map the progression curve (time to reach each milestone)
- Identify any walls where free players stall
- Verify paying players don't skip meaningful content

## Output:
Generate an economy report with balance assessment and recommendations:

```markdown
# Economy Audit

## Currency Inventory
- **Gold** (soft): Earned through gameplay
- **Gems** (premium): Earned rarely / purchased
- **Event Points** (seasonal): Earned during events only

## Faucets (Income Sources)
| Source | Amount | Frequency | Rate/Hour |
|--------|--------|-----------|-----------|
| Quests | 50-200 | ~1/10 min | ~750 |
| Drops | 5-25   | ~1/30s   | ~900 |
| Daily  | 500    | 1/day    | ~21/hr avg |

## Sinks (Drain Sources)
| Sink | Cost | Frequency | Drain/Hour |
|------|------|-----------|------------|
| Shop Items | 100-5000 | varies | ~300 |
| Upgrades | 1000-10000 | slow | ~200 |
| Repair | 50 | frequent | ~150 |

## Balance
- Net: +1000 gold/hour — **INFLATIONARY**
- Recommendation: Add hard sinks (prestige items, consumables)

## GamePass Analysis
| Name | Price | Benefit | Pay-to-win? | Expected Conversion |
|------|-------|---------|-------------|---------------------|
| VIP  | 499 R$ | +10% gold, chat color | No | 3% |
| 2x XP | 799 R$ | Double XP forever | Borderline | 2% |

## Concerns
- 2x XP GamePass may feel necessary for progression — reconsider balance
- No sinks for premium currency — add premium shop

## Recommendations
1. Add prestige system to absorb late-game gold
2. Add cosmetic shop for premium currency
3. Reduce XP grind so 2x XP is a luxury, not necessity
```
