---
name: llm-wiki
description: "Build and maintain a persistent, compounding knowledge base as interlinked markdown files. Based on Karpathy's LLM Wiki pattern. Unlike traditional RAG (which rediscovers knowledge from scratch), the wiki compiles knowledge once and keeps it current."
version: 2.1.0
triggers:
  - Creating or initializing a wiki
  - Ingesting a new source document
  - Querying the wiki for information
  - Running a wiki health check or lint
  - Cross-referencing existing pages
  - Checking for stale content
  - Adding a new page type or tag
---

# LLM Wiki — Persistent Knowledge Compilation

Based on [Andrej Karpathy's LLM Wiki pattern](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f).

Unlike traditional RAG (which rediscovers knowledge from scratch per query), the wiki compiles knowledge once and keeps it current. Cross-references are already there. Contradictions have already been flagged. Synthesis reflects everything ingested.

**Division of labor:** The human curates sources and directs analysis. The agent summarizes, cross-references, files, and maintains consistency.

## Directory Structure

```
$WIKI_ROOT/
├── SCHEMA.md           # Conventions, structure rules, domain config
├── index.md            # Sectioned content catalog with one-line summaries
├── log.md              # Chronological action log (append-only, rotated yearly)
├── raw/                # Layer 1: Immutable source material
│   ├── articles/       # Web articles, clippings
│   ├── papers/         # PDFs, arxiv papers
│   ├── transcripts/    # Meeting notes, interviews
│   └── assets/         # Images, diagrams referenced by sources
├── concepts/           # Layer 2: Extracted ideas and patterns
├── entities/           # Layer 2: Concrete things (tools, models, projects, people)
├── comparisons/        # Layer 2: Side-by-side analyses
└── _archive/           # Deprecated pages
```

## Resuming an Existing Wiki

**Always orient yourself before doing anything:**

1. Read `SCHEMA.md` — understand the domain, conventions, and tag taxonomy
2. Read `index.md` — learn what pages exist and their summaries
3. Scan recent `log.md` — last 20-30 entries for recent activity

This prevents creating duplicate pages, missing cross-references, contradicting the schema, and repeating work already logged.

## Ingesting a Source

1. **Capture the raw source**
   - URL → use `web_extract`, save to `raw/articles/` with frontmatter
   - PDF → use `web_extract` (handles PDFs), save to `raw/papers/`
   - Pasted text → save to appropriate `raw/` subdirectory
   - GitHub repo → clone with `--depth 1`, combine READMEs into single raw file

2. **Orient** — re-read SCHEMA.md + index.md + log.md

3. **Search existing pages** — find entities/concepts already covered

4. **Write or update wiki pages**
   - New entities/concepts: create when mentioned with detail (not passing mentions)
   - Existing pages: add new information, bump `updated` date
   - Cross-reference: every new/updated page must link to 2+ others via `[[wikilinks]]`
   - Tags: only from the SCHEMA.md taxonomy

5. **Update navigation**
   - Add new pages to `index.md` under correct section
   - Update "Total pages" count and "Last updated" date
   - Append to `log.md`: `## [YYYY-MM-DD] ingest | Source Title`

6. **Report what changed** — list every file created or updated

## Page Quality Standards

Every wiki page must have:

- Valid YAML frontmatter: `title`, `type`, `tags`, `sources`, `created`, `updated`
- At least one `[[wikilink]]` to another page
- A one-line summary (used in index.md)
- `confidence`: high, medium, or low (optional but recommended)
- Tags from the closed taxonomy in SCHEMA.md

## Lint / Health Check

Run these checks:

1. **Orphan pages** — pages with zero inbound `[[wikilinks]]`
2. **Broken wikilinks** — `[[links]]` pointing to nonexistent pages
3. **Index completeness** — every file in `entities/`, `concepts/`, `comparisons/` must appear in index.md
4. **Frontmatter validation** — all required fields present; tags in taxonomy
5. **Stale content** — pages whose `updated` date is >90 days older than the most recent source mentioning the same entities
6. **Contradictions** — pages with `contested: true` or `contradictions:` frontmatter
7. **Quality signals** — `confidence: low` pages flagged for review
8. **Page size** — pages over 200 lines are candidates for splitting
9. **Tag audit** — list tags in use but not in SCHEMA.md taxonomy
10. **Log rotation** — if log.md exceeds 500 entries, rotate it

## Frontmatter Template

```yaml
---
title: Page Title
created: YYYY-MM-DD
updated: YYYY-MM-DD
type: concept          # concept | entity | comparison | query | summary
tags: [tag1, tag2]
sources: [raw/articles/source-name.md]
confidence: high       # high | medium | low
contested: false       # true if this page has unresolved contradictions
contradictions: []     # pages this one conflicts with
---
```

## Pitfalls

- **Never modify files in `raw/`** — sources are immutable. Corrections go in wiki pages
- **Always orient first** — reading SCHEMA + index + log before any operation prevents duplicates
- **Always update index.md and log.md** — skipping these causes the wiki to degrade
- **Don't create pages for passing mentions** — a name appearing once in a footnote doesn't warrant an entity page
- **Don't create pages without cross-references** — isolated pages are invisible
- **Tags must come from taxonomy** — freeform tags decay into noise. Add new tags to SCHEMA.md first
- **Handle contradictions explicitly** — note both claims with dates and sources, mark in frontmatter
- **Rotate the log** — when log.md exceeds 500 entries, rename it `log-YYYY.md` and start fresh
- **Wiki Agent and Vault Curator are different scheduled tasks** — Wiki Agent creates pages; Vault Curator enriches frontmatter + adds semantic links to existing files
