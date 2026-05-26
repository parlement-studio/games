---
name: wiki-query
description: Answer a Roblox/Luau question by reading the wiki. Starts from wiki/index.md, follows wikilinks to related pages, synthesizes an answer with citations, and optionally files the answer back as a new wiki page. Use whenever you need deep knowledge about a Roblox service, a Luau feature, an exploit, a pattern — the wiki is the source of truth.
---

# /wiki-query — Ask the Wiki

## Delegate to: wiki-curator

## Arguments

- `<question>` — a natural-language question (e.g., "what's the safest way to handle trading with session locks", "how do I prevent speed hacks", "what are the DataStore budget limits")

## Prerequisites

- Wiki has been seeded (`wiki/index.md` exists)
- The question is relevant to Roblox/Luau knowledge (not project-specific — those go to domain skills)

## Workflow

### 1. Understand the Question

Parse what the user is asking:
- **Factual** (what is X?): usually answerable from a single page
- **How-to** (how do I do X?): usually answerable from a concept or pattern page
- **Comparative** (X vs Y?): requires reading multiple pages
- **Synthesis** (what's the best way to X?): requires reading multiple pages and integrating

### 2. Read the Index

Load `wiki/index.md` fully. This is the content catalog — scan for candidate pages that might contain the answer.

### 3. Identify Candidate Pages

Based on the question, pick 3-10 candidate pages from the index. Prefer:
- Direct matches (question mentions "DataStoreService" → `wiki/services/DataStoreService.md`)
- Relevant concepts (question mentions "trading" → `wiki/patterns/atomic-trading.md`, `wiki/concepts/session-locking.md`)
- Related anti-patterns or exploits (question about security → `wiki/exploits/*.md`)

### 4. Read the Candidate Pages

Read each candidate page fully. Note:
- What it answers directly
- What links it points to (for follow-up)
- What `sources:` it cites (in case the user wants to go deeper)

### 5. Follow Related Links

If a candidate page's `Related` section points to other pages that look relevant, read those too. Stop when:
- You have enough to answer the question confidently
- You've read > 10 pages (signal the question is too broad)

### 6. Synthesize the Answer

Write a focused answer that:
- **Directly addresses the question** (don't meander)
- **Cites every claim** by `[[wikilink]]` to the page where it's supported
- **Shows code** when code is the best answer (copy from the wiki page)
- **Notes uncertainty** if sources disagree or information is sparse
- **Recommends deeper reading** by listing 2-3 Related pages

Structure:

```markdown
# Answer: <short question restatement>

**Short answer:** 1-2 sentences.

## Details

<full explanation with [[wikilink]] citations to every claim>

## Code

<relevant code example from the wiki>

## Caveats

<edge cases, gotchas, "but if..." clauses>

## Sources (wiki pages read)

- [[Page 1]]
- [[Page 2]]
- [[Page 3]]

## Related (you may want to read next)

- [[Related Page 1]]
- [[Related Page 2]]
```

### 7. Handle Missing Information

If the wiki doesn't have the answer:

**Option A — partial answer + flag gap**:
> "The wiki has <partial info> from [[Page]], but doesn't cover <specific aspect>. You can either:
> - Run `/wiki-ingest` on a source that covers it (check `wiki/raw/` for candidates)
> - Create a new page via `/wiki-update`
> - Accept the partial answer"

**Option B — search raw sources**:
If `wiki/raw/` has captured sources not yet ingested, offer to read them directly (not through the curated wiki) and give the user a raw-source-backed answer with the caveat "this is from uncurated raw content."

### 8. Offer to File the Answer Back

If the answer is substantive and would be useful to someone else asking the same question in the future, offer:

> "This answer would make a good wiki page at `[[<proposed-page-name>]]`. Should I file it?"

If approved, create the new page via the `/wiki-update` workflow and log it as a query-generated contribution:

```markdown
## [YYYY-MM-DD] query | <short question>
- Pages read: [[page1]], [[page2]], [[page3]]
- Answer filed: [[new-page]]
```

This is how the wiki **compounds** — good answers become new pages.

### 9. Log the Query

Whether or not the answer was filed:

```markdown
## [YYYY-MM-DD] query | <short question>
- Pages read: [[list]]
- Answer: <1-line summary or "filed as [[new-page]]">
- Gap found: <if any — describe and recommend>
```

## Query Patterns

### "What is X?"
1. Check `wiki/services/X.md`, `wiki/concepts/x.md`, `wiki/luau/x.md`
2. Read the page → synthesize summary
3. Usually answerable from 1-2 pages

### "How do I do X safely?"
1. Check `wiki/concepts/`, `wiki/patterns/`, `wiki/anti-patterns/`, `wiki/exploits/`
2. Read 3-5 pages
3. Answer combines "the pattern to follow" + "the anti-pattern to avoid"

### "Why is X slow?"
1. Check `wiki/performance/*.md`
2. Also check `wiki/services/<X>.md` for budget/limits
3. Answer cites concrete numbers

### "Is X an exploit risk?"
1. Check `wiki/exploits/*.md`
2. Check `wiki/concepts/server-authority.md`, `wiki/concepts/rate-limiting.md`
3. Answer lists the attack vectors and mitigations

### "What does the rule `Y` mean?"
1. Read `.claude/rules/Y.md`
2. Read the wiki concept page(s) the rule points to
3. Answer explains "what the rule says" + "why it exists"

## Output Discipline

- **Short > long**: answer what was asked, not everything you know
- **Citations are mandatory**: every non-trivial claim has `[[wikilink]]`
- **Code over prose** when code is clearer
- **Honest uncertainty**: say "the wiki doesn't cover X" when it doesn't

## Anti-Patterns

- ❌ Do not fabricate Roblox APIs
- ❌ Do not answer from general Lua knowledge — use the wiki (or say you can't)
- ❌ Do not skip citations
- ❌ Do not read > 10 pages for one question (signal the question is too broad and ask user to narrow)
- ❌ Do not file every answer back — only substantive, reusable ones
- ❌ Do not silently create wiki pages without user approval
