# Domain Docs

How the engineering skills should consume this repo's domain documentation when exploring the codebase.

## Before exploring, read these

- **`CONTEXT.md`** at the repo root, or
- **`CONTEXT-MAP.md`** at the repo root if it exists: it points at one `CONTEXT.md` per context. Read each one relevant to the topic.
- **`doc/adr/`**: read ADRs that touch the area you're about to work in. In multi-context repos, also check `src/<context>/doc/adr/` for context-scoped decisions.

If any of these files don't exist, **proceed silently**. Don't flag their absence; don't suggest creating them upfront. The `/domain-modeling` skill (reached via `/grill-with-docs` and `/improve-codebase-architecture`) creates them lazily when terms or decisions actually get resolved.

## File structure

Single-context repo (most repos):

```
/
├── CONTEXT.md
├── doc/adr/
│   ├── 0001-event-sourced-orders.md
│   └── 0002-postgres-for-write-model.md
└── src/
```

Multi-context repo (presence of `CONTEXT-MAP.md` at the root):

```
/
├── CONTEXT-MAP.md
├── doc/adr/                          ← system-wide decisions
└── src/
    ├── ordering/
    │   ├── CONTEXT.md
    │   └── doc/adr/                  ← context-specific decisions
    └── billing/
        ├── CONTEXT.md
        └── doc/adr/
```

## The vendored skills say `docs/adr/`

This repo uses `doc/adr/`, as the trees above show. The vendored `domain-modeling` skill says the opposite — "ADRs live in `docs/adr/`" (`dist/agents/skills/domain-modeling/ADR-FORMAT.md`) — and every other vendored file that mentions the directory agrees with it rather than with us. They are not edited: they are third-party content installed by the pinned `skills` CLI and recorded in `skills-lock.json`, which `SKILLS.md` describes as pinning them by content hash, so a local edit is an undeclared divergence that the next `npx skills update` can overwrite. This document is read *before exploring* (see the top of this file), so an agent gets the correct path first, and a `docs/adr/` that appears anyway belongs at `doc/adr/`.

The numbering width is a separate question and is still open: the examples above show `0001-`, no `doc/adr/` exists in this repo yet, and whoever writes the first ADR here settles it.

## Use the glossary's vocabulary

When your output names a domain concept (in an issue title, a refactor proposal, a hypothesis, a test name), use the term as defined in `CONTEXT.md`. Don't drift to synonyms the glossary explicitly avoids.

If the concept you need isn't in the glossary yet, that's a signal: either you're inventing language the project doesn't use (reconsider) or there's a real gap (note it for `/domain-modeling`).

## Flag ADR conflicts

If your output contradicts an existing ADR, surface it explicitly rather than silently overriding:

> _Contradicts ADR-0007 (event-sourced orders), but worth reopening because…_
