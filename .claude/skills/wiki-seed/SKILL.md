---
name: wiki-seed
description: One-time bootstrap of the Roblox/Luau wiki from existing repo content. Extracts Luau/Roblox knowledge from .claude/agents/, .claude/rules/, and .claude/docs/ and generates initial wiki pages with proper frontmatter, cross-references, and ownership. Run ONCE at project setup; subsequent updates use /wiki-ingest.
disable-model-invocation: true
---

# /wiki-seed — Wiki Bootstrap

## Delegate to: wiki-curator

## When to Use
- **Exactly once**, when first setting up the wiki for a project that already has FoG-Roblox-Studio-Command content in `.claude/`
- Never run a second time — use `/wiki-ingest` for ongoing updates

If `wiki/services/` already contains files, refuse to run and tell the user "Wiki already seeded. Use /wiki-ingest to add new content or /wiki-update to edit."

## Prerequisite Files
Before running, verify these exist:
- `wiki/SCHEMA.md` — the schema (read it first)
- `wiki/README.md` — the entry point
- Empty `wiki/services/`, `wiki/concepts/`, `wiki/luau/`, `wiki/anti-patterns/`, `wiki/exploits/`, `wiki/performance/`, `wiki/monetization/`, `wiki/studio/`, `wiki/patterns/`

## Workflow

### 1. Read the Schema
Load `wiki/SCHEMA.md` fully. Every page created must comply with it.

### 2. Inventory Source Material
Read these existing repo files (in order):

**Prescriptive rules (for anti-patterns and required patterns):**
- `.claude/rules/server-scripts.md`
- `.claude/rules/client-scripts.md`
- `.claude/rules/shared-modules.md`
- `.claude/rules/datastores.md`
- `.claude/rules/remotes.md`
- `.claude/rules/ui-code.md`
- `.claude/rules/gameplay-systems.md`
- `.claude/rules/design-docs.md`
- `.claude/rules/tests.md`
- `.claude/rules/prototypes.md`
- `.claude/rules/config-data.md`

**Architecture and language docs:**
- `.claude/docs/roblox-architecture-guide.md`
- `.claude/docs/luau-style-guide.md`
- `.claude/docs/coding-standards.md`

**Agent prompts (for Roblox-specific knowledge sections):**
- `.claude/agents/datastore-architect.md`
- `.claude/agents/remotes-networking-specialist.md`
- `.claude/agents/exploit-security-specialist.md`
- `.claude/agents/analytics-retention-specialist.md`
- `.claude/agents/live-ops-specialist.md`
- `.claude/agents/monetization-lead.md`
- `.claude/agents/performance-analyst.md`
- `.claude/agents/technical-director.md`
- `.claude/agents/lead-programmer.md`
- `.claude/agents/luau-gameplay-programmer.md`
- `.claude/agents/luau-systems-programmer.md`
- `.claude/agents/ui-programmer.md`
- `.claude/agents/art-director.md`
- `.claude/agents/audio-director.md`
- `.claude/agents/sound-designer.md`
- `.claude/agents/level-designer.md`
- `.claude/agents/technical-artist.md`
- `.claude/agents/roblox-studio-specialist.md`
- `.claude/agents/devops-engineer.md`

### 3. Extract Knowledge by Category

Scan all sources and extract (don't duplicate across categories):

**Services** (each becomes a `wiki/services/<ClassName>.md` page):
Every Roblox class mentioned by name. Priority order: DataStoreService, MemoryStoreService, OrderedDataStore, RemoteEvent, RemoteFunction, UnreliableRemoteEvent, MarketplaceService, Players, TextChatService, MessagingService, TweenService, TeleportService, HttpService, SoundService, CollectionService, ContextActionService, UserInputService, ProximityPrompt, RunService, Lighting, Humanoid, and every other class-name referenced in agent prompts.

**Concepts** (`wiki/concepts/*.md`):
- session-locking
- server-authority
- client-server-split
- bind-to-close
- schema-versioning
- trove-maid-cleanup
- signal-pattern
- service-pattern
- rate-limiting
- streaming-enabled
- module-lazy-loading
- atomic-trading
- cross-server-events
- feature-flags
- code-redemption
- ftue-design
- core-loop

**Luau features** (`wiki/luau/*.md`):
- type-annotations
- strict-vs-nonstrict
- task-library
- export-type
- pcall-xpcall
- table-library
- string-library
- math-library
- buffer-type
- generic-types
- coroutines
- metatables
- require-pattern
- module-scripts

**Anti-patterns** (`wiki/anti-patterns/*.md`):
- deprecated-wait
- deprecated-spawn
- deprecated-delay
- client-trust
- magic-numbers
- no-pcall
- no-session-lock
- instance-in-remote
- client-to-server-remote-function
- player-name-as-key
- missing-schema-version
- print-in-production
- no-rate-limit
- unvalidated-remote-args
- string-concat-in-loop
- direct-cross-system-coupling

**Exploits** (`wiki/exploits/*.md`):
- speed-hack
- teleport-hack
- fly-hack
- noclip
- remote-spam
- argument-spoofing
- item-duplication
- negative-purchase
- transaction-replay
- localscript-injection
- memory-editing
- bind-to-close-skip
- session-hijack

**Performance** (`wiki/performance/*.md`):
- heartbeat-budget
- client-fps-targets
- server-memory-budget
- network-bandwidth-budget
- microprofiler
- developer-console-stats
- script-profiler
- object-pooling
- throttling-pattern
- caching-references
- string-concat-tableconcat
- overdraw-transparency
- particle-budget
- dynamic-lights-budget
- streaming-performance
- datastore-budget-management

**Monetization** (`wiki/monetization/*.md`):
- game-pass
- dev-product
- process-receipt-idempotency
- premium-benefits
- engagement-based-payouts
- robux-price-tiers
- developer-exchange
- ethical-monetization
- gamepass-detection
- purchase-funnel

**Studio** (`wiki/studio/*.md`):
- rojo-mapping
- argon-mapping
- wally-packages
- collection-service-tags
- attributes
- play-solo-team-test
- device-emulator
- studio-plugins
- open-cloud-api
- rbxl-vs-rbxlx

**Patterns** (`wiki/patterns/*.md`):
- daily-rewards
- code-redemption-system
- quest-system
- inventory-pattern
- trading-system
- party-system
- friends-system
- leaderboard-pattern
- onboarding-tutorial

### 4. Create Pages

For each extracted topic:

1. **Write a complete page** (`status: complete`) IF:
   - The existing repo content has enough material for a substantial page (≥3 paragraphs of relevant content + code examples)
   - This is a core topic the rules or agents deeply cover

2. **Write a stub** (`status: stub`) IF:
   - The topic is only briefly mentioned in existing content
   - It deserves its own page but needs more source material

Target distribution for medium-depth seed:
- **~35-45 complete pages** (the rules and architecture guide provide enough content for these)
- **~80-90 stub pages** (so nothing is a dangling reference, but fleshing out waits for `/wiki-ingest` from the raw sources layer)

### 5. Cross-Reference

After creating all pages, do a second pass:
- Add `[[wikilinks]]` in every `Related` section
- Ensure bidirectional links (if A's Related includes B, B's Related should include A)
- Link from concept pages to service pages they use, and back
- Link from anti-pattern pages to the rule file that enforces the rule (use markdown link for rules, wikilink for wiki pages)
- Link from exploit pages to the concepts that defend against them

### 6. Write `wiki/index.md`

Full content catalog, grouped by category, with one-line summary and `status` per page.

### 7. Write `wiki/log.md`

First entry:
```markdown
# Wiki Log

## [YYYY-MM-DD] seed | Initial wiki bootstrap
- Seeded from: .claude/agents/ (33 files), .claude/rules/ (11 files), .claude/docs/ (3 files)
- Pages created: <N total>
  - Complete: <N>
  - Stub: <N>
- Categories:
  - services: <N>
  - concepts: <N>
  - luau: <N>
  - anti-patterns: <N>
  - exploits: <N>
  - performance: <N>
  - monetization: <N>
  - studio: <N>
  - patterns: <N>
- Owners assigned per schema ownership table
- Cross-references: <N total wikilinks>
- Next: /wiki-ingest the raw sources captured by research agents
```

### 8. Final Check

Run `/wiki-lint` automatically after seeding to verify:
- All frontmatter valid
- No broken links
- All pages in index.md
- No unexpected orphans

Report the lint result to the user alongside the seed summary.

## Output to User

After completion, report:
- Total pages created (complete + stub)
- Breakdown by category
- Any skipped topics and why
- Lint report summary
- Recommended next step: "Run /wiki-ingest on raw sources captured by research agents"

## Anti-Patterns for the Seeder

- ❌ Do not write pages longer than the source material justifies (better to stub and extend later)
- ❌ Do not invent Roblox APIs or behaviors not in the source material
- ❌ Do not create pages for topics you couldn't find any source content on (defer until a source arrives)
- ❌ Do not overwrite existing wiki files if any somehow exist (fail instead — the user needs to clear them)
- ❌ Do not skip the index.md or log.md — those are required outputs
- ❌ Do not create circular Related links that don't actually relate (only link pages that are genuinely connected)
