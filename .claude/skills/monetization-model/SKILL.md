---
name: monetization-model
description: Guides through designing or auditing the monetization model. Creates GamePass/DevProduct catalog, pricing strategy, and revenue projections.
---

# /monetization-model — Monetization Design Workflow

## Delegate to: monetization-lead (with economy-designer for currency flow)

## Steps

### 1. Context Gathering
Ask:
- "What game stage are we in?" (pre-launch / launched / live-ops)
- "What's the player audience skew?" (age, platform)
- "What are the creative pillars? (can't contradict them)"
- "What's the target: revenue, retention, engagement?"

### 2. Ethical Review (NON-NEGOTIABLE)
Before designing, confirm:
- [ ] No loot boxes with real-money purchase (Roblox ToS)
- [ ] No pay-to-win that makes F2P feel unable to compete
- [ ] No FOMO targeting young players
- [ ] No misleading pricing
- [ ] Free players have a complete, enjoyable experience

### 3. Design the Catalog

#### GamePasses (permanent purchases)
For each proposed GamePass:
- Name
- Price (Robux) — use clean values: 49, 99, 199, 299, 499, 799, 999, 1499, 2499
- What it grants
- Target player type (new player / mid game / whale)
- Pay-to-win check

Example:
| Name | Price | Grants | Target | P2W? |
|------|-------|--------|--------|------|
| VIP | 499 | Chat color, +5% coins, VIP room | Engaged player | No |
| Double Inventory | 299 | 2x inventory slots | Mid-game | No |
| Auto-Farm | 799 | Passive resource generation | Whale | Borderline — balance |

#### DevProducts (consumable purchases)
For each proposed DevProduct:
- Name
- Price (Robux)
- What it grants
- How often players buy (expected frequency)
- Is it pay-to-win?

Example:
| Name | Price | Grants | Frequency | P2W? |
|------|-------|--------|-----------|------|
| 1000 Gems | 99 | 1000 premium currency | Variable | No (gems buy cosmetics) |
| Revive Token | 25 | Revive at death | Per-death | Soft |
| XP Boost 2x 1hr | 49 | 2x XP for 1 hour | Occasional | Soft |

### 4. Pricing Strategy
- **Entry Price Point**: At least one item at 25-49 R$ (almost everyone has this)
- **Mid Tier**: 199-499 R$ (engaged players)
- **Premium**: 999+ R$ (whales)
- **Comparable Items**: Reference 3-5 successful similar Roblox games' pricing

### 5. Funnel Design
How does a player discover and decide to buy?
- **Touchpoint 1**: First mention (tutorial hint, menu badge, etc.)
- **Touchpoint 2**: Consideration (shop browse, see other players using)
- **Touchpoint 3**: Decision (purchase prompt with clear value proposition)
- **Touchpoint 4**: Post-purchase reinforcement (confirmation, immediate use)

### 6. Revenue Projection
Rough model:
```
DAU × Conversion Rate × Avg Purchase × Dev Exchange = Revenue

1000 DAU × 3% × 300 R$ × $0.0035 = $31.50/day from conversions
```

### 7. Generate Plan Document
Save to `design/monetization-plan.md` using `.claude/docs/templates/monetization-plan-template.md`.

## Output
Present the full plan for user review and approval.
Never implement changes without explicit sign-off.
