---
name: wiki-ingest
description: Integrate a new source from wiki/raw/ into the curated wiki. Reads the source, identifies affected pages, delegates updates to domain specialists, and applies a coherent changeset. Use whenever raw sources have been added (e.g., after research agents complete, or after Obsidian Web Clipper drops a new article into wiki/raw/community/articles/).
---

# /wiki-ingest — Integrate a Raw Source

## Delegate to: wiki-curator

## Arguments

- `<source>` — path to a raw source file or directory to ingest
- If no argument: scan `wiki/raw/` for new files (files not yet cited in any wiki page's `sources:` frontmatter)

## Prerequisites

- `wiki/SCHEMA.md` exists (wiki has been seeded via `/wiki-seed`)
- `wiki/index.md` exists
- The source path exists under `wiki/raw/`

## Workflow

### 1. Read the Schema
Load `wiki/SCHEMA.md` first. Every output must comply with it.

### 2. Read the Source
Read the file(s) fully. Every word. Note:
- **Source type** (check frontmatter `source_type`): official-roblox-docs, luau-spec, devforum, reddit, article, github-readme
- **Subject** (what it's about): service, concept, pattern, exploit, etc.
- **Key claims**: specific facts, numbers, APIs, patterns mentioned

### 3. Scan for Wiki Targets

Identify every entity the source touches. For each:
- **Roblox class name** → candidate page in `wiki/services/<ClassName>.md`
- **Luau feature** → candidate page in `wiki/luau/*.md`
- **Pattern name** → candidate page in `wiki/concepts/*.md` or `wiki/patterns/*.md`
- **Exploit** → candidate page in `wiki/exploits/*.md`
- **Performance topic** → candidate page in `wiki/performance/*.md`
- **Monetization concept** → candidate page in `wiki/monetization/*.md`
- **Studio/tooling** → candidate page in `wiki/studio/*.md`

Use grep/glob against `wiki/` to check which of these pages already exist.

### 4. Load Each Affected Page

For every existing page that's a candidate:
- Read its full current content
- Note its `owner:`, `status:`, `sources:` frontmatter
- Note its current Related section links

### 5. Determine Required Changes

For each page, decide:

**No change needed** — source adds nothing new beyond what's already there. Skip.

**Minor update** — add a detail, fix a small inaccuracy, update a number. Draft the specific edit.

**Significant update** — substantial new content, new code examples, new edge cases. Draft the section additions.

**New page** — source introduces a topic that has no existing page. Plan to create a stub (if minor) or complete page (if source has enough content).

**Contradiction** — source directly contradicts an existing claim. Add a `⚠️ Contradiction flagged` block to the page; do NOT silently overwrite.

### 6. Delegate Updates to Owners

For each page requiring changes, identify the `owner:` from its frontmatter. Delegate the draft to that agent by invoking them with the source content + the current page content + the proposed change description.

Wait for each owner's draft. If multiple pages share an owner, batch them.

If you are the owner (wiki-curator owns `index.md`, `log.md`, `SCHEMA.md`, `README.md`), draft the update yourself.

### 7. Assemble the Full Changeset

Collect all drafts into one package:

```markdown
# Ingest Proposal: <source filename>

**Source:** wiki/raw/<path>
**Source type:** <type>
**Captured:** <captured_at>
**Captured by:** <captured_by>

## Summary
<1-2 sentences on what the source is about>

## Pages to Update (N)

### [[Page Name]]
**Owner:** <agent>
**Change type:** minor | significant | contradiction
**Diff summary:**
<brief description of changes>

<If diff is small, include it inline. If large, summarize and show on request.>

---

### [[Another Page]]
...

## Pages to Create (N)

### [[New Page Name]]
**Type:** stub | complete
**Owner:** <agent>
**Reason:** <why this page is needed>

## Contradictions Flagged (N)

### [[Page with contradiction]]
**Current claim:** ...
**New source claims:** ...
**Resolution:** Defer to <owner> agent for review.

## Raw Source Update

The following pages will have their `sources:` frontmatter extended to cite:
- `wiki/raw/<path>`

## Estimated Scope
- Files touched: N
- Lines changed: ~N
- New pages: N
- Time to apply: <few seconds | several seconds>
```

### 8. Present to User

Show the full changeset. Wait for one of:
- **"go"** or equivalent → apply all changes
- **"skip X"** → remove X from the changeset and apply the rest
- **"cancel"** → discard and report

### 9. Apply Changes

On approval:
1. Apply all page updates in one pass (use Edit for in-place edits, Write for new files)
2. Update `sources:` in every touched page's frontmatter to include the new raw source path
3. Update `updated:` timestamp in every touched page's frontmatter to today's date
4. If any new pages were created, add them to `wiki/index.md` under the right category
5. Verify `[[wikilinks]]` — if a new link points to a page that doesn't exist, create the stub

### 10. Append to `wiki/log.md`

```markdown
## [YYYY-MM-DD] ingest | <source title>
- Source: wiki/raw/<path>
- Source type: <type>
- Updated: [[page1]], [[page2]], [[page3]]
- Created: [[new-page1]], [[new-page2]]
- Contradictions flagged: [[page4]]
- Delegated to: <list of agent names>
- Notable additions: <1-3 bullets on what the wiki now knows that it didn't before>
```

### 11. Final Check

Offer to run `/wiki-lint` as a sanity check. If the user says yes, run it and report any new issues introduced.

## Bulk Ingest Mode

If the user runs `/wiki-ingest <directory>`, iterate over all files in that directory:

1. Sort files by type (more authoritative sources first: official-docs > spec > article > devforum > reddit)
2. For each file, run the single-file workflow above
3. Batch the changesets into a single user-approval step (show all proposals together, let the user approve/skip per-file)
4. Apply approved changes
5. Write one log entry per file ingested

**Safety**: For bulk ingest with > 10 files, warn the user first: "This will touch an estimated N pages. Proceed?"

## Output to User

After completion:
- Files ingested
- Pages updated (count + list)
- Pages created (count + list)
- Contradictions flagged (count + list — these need follow-up)
- Recommendation for next step (e.g., "Run `/wiki-lint` to verify" or "Run `/wiki-ingest` on the next batch")

## Anti-Patterns

- ❌ Do not silently overwrite — always present the diff to the user first
- ❌ Do not invent content not in the source
- ❌ Do not skip frontmatter updates (`sources:` and `updated:`)
- ❌ Do not leave `[[wikilinks]]` dangling — if you link to a non-existent page, create it as a stub in the same changeset
- ❌ Do not batch > 15 page updates without breaking into smaller chunks
- ❌ Do not forget to update `wiki/index.md` when adding new pages
- ❌ Do not forget to log the ingest in `wiki/log.md`
