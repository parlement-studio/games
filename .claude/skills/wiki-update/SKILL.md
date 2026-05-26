---
name: wiki-update
description: Targeted update to a single wiki page (not source-driven like /wiki-ingest). Use when you need to edit, correct, expand, or restructure a specific page based on user feedback or newly-discovered information. Reads the page and its Related links, drafts the change, presents the diff, and applies on approval.
---

# /wiki-update — Targeted Page Edit

## Delegate to: wiki-curator (which may delegate to the page's owner)

## Arguments

- `<page>` — wiki page path (e.g., `wiki/services/DataStoreService.md` or just `DataStoreService`)
- `[note]` — optional reason or description of the change

## When to Use

- User spotted an inaccuracy on a page
- Owner agent wants to refine their page without a new source
- Schema change requires touching multiple pages
- Contradiction resolution
- Adding missing cross-references
- Upgrading a stub to complete status

## When NOT to Use

- Ingesting a new raw source → use `/wiki-ingest` instead
- Fixing lint issues → use `/wiki-lint --fix`
- Creating a brand-new page for a topic from scratch with no source → write a proper page via `/wiki-ingest` with a raw source first

## Workflow

### 1. Resolve the Page

If argument is a full path, use it directly. Otherwise, search for the page:

```bash
find wiki/ -name "*<arg>*.md" -not -path "wiki/raw/*"
```

Handle ambiguity: if multiple matches, list them and ask user to disambiguate.

If the page doesn't exist, offer to:
1. Create it as a stub (if user wants to start a new page)
2. Check if it should be elsewhere (maybe user meant a different category)

### 2. Read the Page

Load the full page. Note:
- `owner:`, `status:`, `sources:`, `updated:` from frontmatter
- Current structure (which sections exist)
- Current `Related` links

### 3. Read Related Pages

Read every page referenced in the `## Related` section. Skim their content to understand the context.

Also load `wiki/SCHEMA.md` to ensure the edit complies with the schema.

### 4. Understand the Requested Change

Parse the user's intent:
- **Correction** — "this is wrong, fix it"
- **Expansion** — "add info about X"
- **Restructure** — "split this page" or "merge these sections"
- **Cross-reference** — "link to Y"
- **Status upgrade** — "this stub should be complete now"
- **Schema conformance** — "add missing required sections"

### 5. Delegate to Owner (If Appropriate)

If the page has an `owner:` other than `wiki-curator`, and the edit is domain-specific, delegate to the owner agent for a draft. Pass the owner:
- The current page content
- The requested change
- Any relevant Related page content
- The schema section for the page type

Wait for the owner's draft.

If the edit is purely structural (formatting, cross-references, frontmatter), `wiki-curator` can handle it directly.

### 6. Draft the Change

Produce the edit. Options:

**In-place edit**: For small changes, use `Edit` with `old_string` → `new_string`.

**Section rewrite**: For larger changes within a section, present the new section content.

**Full page rewrite**: For major restructures, present the full new page content.

### 7. Validate Against Schema

Before presenting the change, verify:
- Frontmatter still valid (all required fields present)
- H1 still matches `title:`
- Required sections still present (unless converting to stub)
- No new broken `[[wikilinks]]` introduced
- `updated:` timestamp will be bumped to today

### 8. Update Related Links

If the edit adds or removes cross-references:
- For each added link: verify the target page exists (create stub if needed)
- For each added link: add reverse link in the target's Related section
- For each removed link: remove reverse link in the target's Related section

### 9. Present Diff to User

```markdown
# Update Proposal: [[<Page Title>]]

**Reason:** <user's note>
**Owner:** <agent>
**Change size:** <small | medium | large>
**Schema check:** ✅ valid

## Diff

<show the before/after — for small edits, inline; for large, in a code fence>

## Side Effects

- Related page `[[X]]` will get a new back-link in its Related section
- Frontmatter `updated:` will change from 2026-03-10 → 2026-04-16
- `sources:` will <be unchanged | gain a new citation>

## Approval needed

Proceed?
```

### 10. Wait for Approval

On approval, apply the change and any side effects.

### 11. Apply the Update

1. Edit the target page
2. Bump `updated:` in frontmatter to today
3. Apply Related link side effects on other pages
4. Update `wiki/index.md` if the page's `status` changed (stub → complete, etc.) or title changed

### 12. Append to Log

```markdown
## [YYYY-MM-DD] update | [[<Page Title>]]
- Reason: <note>
- Change: <one-line summary>
- Status: <old status> → <new status> (if changed)
- Side effects: <pages with added/removed back-links>
```

### 13. Run a Mini-Lint

After the update, run a quick sanity check on the affected pages:
- Frontmatter still valid
- Required sections still present
- All wikilinks resolve

If any issues, report them and offer to fix in a follow-up update.

## Batch Updates

If the user requests updates to multiple pages (e.g., "add `[[trove-cleanup]]` to Related on all combat pages"), batch them:

1. Collect all target pages
2. Draft changes for each (in parallel if simple, delegated if complex)
3. Present combined diff
4. One approval, one application pass
5. One log entry per page, or one grouped entry if the changes are uniform

## Stub → Complete Upgrade Pattern

A common update: converting a stub page to a complete page, usually after a new source was ingested.

Workflow:
1. Read the stub
2. Read the raw source(s) that justified the upgrade
3. Write the full content per the schema's required sections
4. Change `status: stub` → `status: complete`
5. Add `sources:` citations
6. Run the standard diff/approval flow

## Anti-Patterns

- ❌ Do not edit a page without reading it fully first
- ❌ Do not break wikilinks (either resolve new links to real pages or create stubs)
- ❌ Do not skip the Related link side-effects (bidirectional links must stay consistent)
- ❌ Do not forget to bump `updated:`
- ❌ Do not merge domain-specific edits without delegating to the owner
- ❌ Do not silently resolve contradictions — those require explicit approval
