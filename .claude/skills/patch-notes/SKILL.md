---
name: patch-notes
description: Generate player-facing patch notes from changelog. Friendly tone, organized by category, acknowledges community feedback.
---

# /patch-notes — Player-Facing Patch Notes

## Delegate to: community-manager (with writer for final polish)

## Purpose
Patch notes are NOT a technical changelog. They're marketing and community communication. The audience is players, not developers.

## Steps

### 1. Source Material
- Technical changelog (from `/changelog`)
- Design docs for new features
- Screenshots or videos of new content (if available)
- Community feedback that shaped changes (credit your community!)

### 2. Translation Rules
Convert technical language to player language:

| Technical | Player |
|-----------|--------|
| "Fixed race condition in DataStore" | "Fixed a bug that sometimes lost items on disconnect" |
| "Refactored combat hit detection" | "Combat feels more responsive" |
| "Rebalanced weapon damage curves" | "Rebalanced weapons — see table below" |
| "Added rate limiting to remote" | (don't mention — it's invisible to players) |

### 3. Structure
Use categories with emojis (players love them, and Roblox's audience responds to visual punctuation):

```markdown
# [Game Name] Update v[X.Y.Z] — [Theme Name]

## ✨ New Content
- **Feature Name**: Short description, 1-2 sentences. Include screenshot if possible.

## ⚔️ Balance Changes
- **Item Name**: What changed. "Buffed" or "Nerfed" framing.

## 🐛 Bug Fixes
- Fixed [player-facing description]
- Fixed [player-facing description] (thanks @PlayerName for the report!)

## 📋 Known Issues
- [Known issue players should know about] (being worked on)

## 🎁 Free Gift
- Log in this week to receive [reward]!

Thank you for playing! — [Studio]
```

### 4. Tone Guidelines
- **Friendly**: Like talking to friends, not a corporate announcement
- **Enthusiastic but honest**: Don't overpromise; don't undersell
- **Credit the community**: Name contributors when possible
- **Positive framing**: "Improved" > "Fixed broken"
- **Transparent**: Admit mistakes, explain fixes
- **Forward-looking**: Tease what's coming next if appropriate

### 5. Platform Considerations
- **Length**: Keep under 500 words (attention spans are short)
- **Images**: Pair each new content item with an image if possible
- **Roblox-specific**: Mention in-game items by name, use Roblox terminology
- **Social sharing**: Structure so it can be tweeted/shared in chunks

### 6. Example Output

```markdown
# MyGame Update v1.3 — The Winter Festival ❄️

## ✨ New Content
- **Winter Event**: Visit the new Winter Village for seasonal quests (ends Jan 15)
- **New Cosmetics**: Arctic Fox pet, Penguin companion, Snowflake Crown
- **New Mini-Game**: Snowball fight arena — compete in 4v4 matches!

## ⚔️ Balance Changes
- **Fire Sword**: Damage increased from 50 → 65 (you asked, we delivered!)
- **Dragon Boss**: HP reduced by 15% (was too tanky after last patch)
- **XP Boost**: Daily XP boost now stacks with 2x XP GamePass

## 🐛 Bug Fixes
- Fixed: Players occasionally lost inventory on disconnect (big thanks to @PlayerName for the detailed report!)
- Fixed: Shop prices sometimes displayed wrong
- Fixed: Daily reward occasionally not claiming

## 📋 Known Issues
- Some players report lag in the new arena — we're investigating
- If you find anything odd, report it in our Discord!

## 🎁 Free Gift
- Log in before Jan 10 to claim a free **Winter Gift Box** containing 100 gems!

Thank you for playing! We read every piece of feedback.
— FoG Studios
```

### 7. Distribution
On approval, save to `production/releases/patch-notes-<version>.md`.
Offer to format for:
- Discord announcement
- In-game MOTD
- Twitter/X thread
- Roblox group announcement
