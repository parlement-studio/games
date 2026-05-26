---
name: wiki-lint
description: Health-check the Roblox/Luau wiki. Scans all pages for frontmatter validity, broken wikilinks, orphans, stale stubs, stale content, bidirectional link consistency, required sections, unresolved contradictions, index drift, and uncovered raw sources. Runs periodically or on demand.
---

# /wiki-lint — Wiki Health Check

## Delegate to: wiki-curator

## Prerequisites

- Wiki has been seeded (`wiki/index.md` exists)
- `wiki/SCHEMA.md` exists

## Workflow

### 1. Read the Schema
Load `wiki/SCHEMA.md` to know what "valid" means for each page type.

### 2. Enumerate All Wiki Files

```bash
find wiki/ -name "*.md" -not -path "wiki/raw/*" -type f
```

This gives every curated wiki page (Layer 2), excluding raw sources (Layer 1).

### 3. Run Each Check

For each check, collect findings into categorized buckets: **Critical** (blocks other operations), **Error** (invalid state), **Warning** (should fix), **Info** (nice to address).

#### Check 1: Frontmatter Validity (Critical → Error)

For each page, verify:
- [ ] File has frontmatter (`---` block at top)
- [ ] `title:` present and non-empty
- [ ] `type:` present and is one of: service, concept, luau-feature, anti-pattern, exploit, performance, monetization, studio, pattern
- [ ] `category:` present
- [ ] `owner:` present and refers to an agent that exists in `.claude/agents/`
- [ ] `status:` present and is one of: stub, draft, complete, needs-review, superseded
- [ ] `created:` present and is valid YYYY-MM-DD
- [ ] `updated:` present and is valid YYYY-MM-DD
- [ ] `updated` >= `created`

Failures: Critical.

#### Check 2: H1 Matches Title (Error)

First `#` heading must match `title:` in frontmatter (case-insensitive, ignoring trailing punctuation).

#### Check 3: Wikilink Integrity (Error)

Extract every `[[Page Title]]` or `[[filename|Display]]` wikilink. For each:
- Resolve to an actual file in `wiki/` (try: exact filename match, title-to-slug match, case-insensitive match)
- If it doesn't resolve, record as broken link
- Distinguish `[[wikilinks]]` (internal to wiki/) from `[text](path)` markdown links (can point anywhere)

Broken wikilinks: Error.

#### Check 4: Orphan Pages (Warning)

A page is an **orphan** if no other page in `wiki/` links to it via wikilink.

Exceptions:
- `wiki/index.md`, `wiki/log.md`, `wiki/SCHEMA.md`, `wiki/README.md` — root files, not orphans
- Pages listed in `wiki/index.md` with an explicit "orphan OK" flag

Orphan warning: Warning.

#### Check 5: Bidirectional Link Consistency (Warning)

For each page A, for each `[[Page B]]` link in A's `## Related` section, verify Page B also has `[[Page A]]` in its `## Related` section.

Missing back-links: Warning. Offer to auto-fix.

#### Check 6: Required Sections (Warning → Error)

For each page, based on its `type:`, verify it has the required sections from `wiki/SCHEMA.md` section 4.

- `service` requires: Summary, API Surface, Budgets and Limits (optional for some), Common Patterns, Pitfalls, Related, Sources
- `concept` requires: What It Is, When to Use It, Implementation, Pitfalls, Related, Sources
- `luau-feature` requires: Syntax, Semantics, Examples, Pitfalls, Related, Sources
- `anti-pattern` requires: What It Looks Like, Why It's Bad, How to Fix It, Detection, Related, Sources
- `exploit` requires: Attack Vector, Affected Systems, Impact, Mitigation, Detection, Related, Sources
- etc.

Pages with `status: stub` are allowed to have a reduced section set: Summary + TODO + Related + Sources. No error for stubs missing other sections.

Missing required sections on non-stub pages: Error.

#### Check 7: Stale Stubs (Warning)

A stub is stale if:
- `status: stub`
- `created` > 30 days ago
- Not touched by any ingest since `created` (check `wiki/log.md`)

Stale stub warning: Warning. List the stubs.

#### Check 8: Stale Content (Info)

A complete page is stale if:
- `status: complete`
- `updated` > 180 days ago

Stale content: Info. List the pages.

#### Check 9: Contradiction Blocks (Error)

Search all pages for `⚠️ Contradiction flagged` blocks. Each unresolved contradiction is an Error — needs human review.

#### Check 10: Missing Cross-References (Info)

For each page, scan its body text for mentions of:
- Other existing pages (by title) that it doesn't link to in `## Related`
- Roblox class names that have their own service pages
- Concepts that have their own concept pages

Suggest adding those cross-references.

#### Check 11: Index Drift (Critical)

Compare:
- Set of pages that exist on disk (`find wiki/ -name "*.md" -not -path "wiki/raw/*"`)
- Set of pages listed in `wiki/index.md`

Report:
- Pages on disk but not in index (→ add to index)
- Pages in index but not on disk (→ remove from index or recreate the page)

Drift: Critical.

#### Check 12: Uncovered Raw Sources (Info)

Enumerate all files in `wiki/raw/`. For each, check if any wiki page's `sources:` frontmatter or body cites it. Raw files with zero citations in curated pages are "uncovered" — they're candidates for `/wiki-ingest`.

Uncovered raw: Info. List them.

#### Check 13: Owner Agent Validity (Error)

For each page's `owner:` field, verify the owner exists in `.claude/agents/`:
```bash
test -f .claude/agents/<owner>.md
```

Invalid owner: Error.

#### Check 14: Empty Related Section (Warning)

Pages with an empty `## Related` section (or no `## Related` at all) — warn unless the page is genuinely isolated (rare).

#### Check 15: Source Citation (Warning)

Pages with empty `sources:` frontmatter and no `## Sources` section — warn. Every page should cite at least one raw source.

### 4. Compile Report

Format:

```markdown
# Wiki Lint Report

**Date:** YYYY-MM-DD
**Pages checked:** N
**Raw sources checked:** M

## Summary
- Critical: X
- Error: X
- Warning: X
- Info: X

## Critical Issues

### Index Drift (X issues)
- `wiki/services/FooService.md` exists but not in index
- `wiki/concepts/bar-pattern.md` is in index but file missing

### Frontmatter Validity (X issues)
- `wiki/services/BazService.md`: missing `owner:` field

## Errors

### Broken Wikilinks (X issues)
- `wiki/concepts/session-locking.md` links to [[non-existent-page]]
- ...

### Required Sections (X issues)
- `wiki/exploits/speed-hack.md` missing "Mitigation" section
- ...

### Unresolved Contradictions (X issues)
- `wiki/services/DataStoreService.md` has contradiction block from 2026-04-14

### Invalid Owner (X issues)
- `wiki/services/Foo.md` owner "nonexistent-agent" not in .claude/agents/

## Warnings

### Orphan Pages (X)
- ...

### Missing Back-links (X)
- Page A → B but B doesn't link back to A

### Stale Stubs (X)
- `wiki/concepts/new-concept.md` stub since 2026-03-01 (45 days)

### Missing Cross-References (X)
- `wiki/services/DataStoreService.md` mentions `[[session-locking]]` but doesn't link it

## Info

### Stale Content (X)
- `wiki/services/HttpService.md` last updated 2025-10-05 (190+ days)

### Uncovered Raw Sources (X)
- `wiki/raw/community/articles/new-datastore-article.md` — candidate for /wiki-ingest

## Recommendations

1. Fix critical issues first (index drift, missing owners)
2. Resolve contradictions (delegate to owner agents)
3. Add missing back-links (batch-fix via /wiki-update)
4. Ingest uncovered raw sources via /wiki-ingest
5. Update stale content (review with domain owners)

## Next Steps

Run `/wiki-update <page>` to fix specific issues, or `/wiki-lint --fix` to auto-fix safe issues (back-links, cross-references, index drift) in a single pass.
```

### 5. Append to log

```markdown
## [YYYY-MM-DD] lint
- Pages checked: N
- Critical: X
- Errors: X
- Warnings: X
- Info: X
- Top issues: <1-3 bullets>
```

### 6. Auto-Fix Mode (Optional)

If the user runs `/wiki-lint --fix`, offer to automatically fix these safe issues:

1. **Index drift** — regenerate `wiki/index.md` from disk state
2. **Missing back-links** — add missing bidirectional Related links
3. **Missing cross-references** — add wikilinks where the body mentions an existing page by name
4. **Frontmatter `updated:` sync** — if a page body was modified more recently than `updated:` claims, update it (requires git knowledge)

Auto-fix does NOT:
- Resolve contradictions
- Create missing pages
- Remove orphans
- Change page content beyond frontmatter and Related sections
- Modify raw sources

Always present the auto-fix plan before applying, and require user approval.

## Anti-Patterns

- ❌ Do not silently fix anything without user approval
- ❌ Do not flag every possible issue — prioritize by severity
- ❌ Do not treat stubs as broken (stubs are first-class)
- ❌ Do not fail if a check can't run — skip with a warning
- ❌ Do not edit raw sources (Layer 1 is immutable)
