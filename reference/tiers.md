# Tiers, formats, and import policy

## Tiers

| Tier | When | Creates | Always imports |
|---|---|---|---|
| 1 — light | one-shot, <20 files, single session | minimal `MAP.md` | `MAP.md` |
| 2 — medium | 50–200 files **or** 2+ sessions | + `STATUS.md`, `LEARNINGS.md`, `TODO.md` if 3+ steps without tracker | `STATUS + MAP + LEARNINGS` |
| 3 — large | monorepo (`packages/*/`, `apps/*/`, workspaces), team | + per-package `TODO`, `WORKFLOW.md` if adopted, `BUGS.md` once LEARNINGS >10 bugs | `STATUS + MAP`, rest lazy |

Auto-detection (`scripts/init.sh --tier auto`):
1. Counts files: `git ls-files | wc -l` (fallback: `find . -type f -not -path './.git/*' | wc -l`).
2. Detects monorepo: `packages/*/`, `apps/*/` dirs, or `workspaces` in `package.json`, multi-package `[tool]`, `Cargo.toml` with `[workspace]`.
3. `<20` files and no monorepo → suggests tier 1; `20–200` or multi-session → tier 2; monorepo or `>200` → tier 3. With `--tier auto` the script asks "will this last more than one session? (y/n)" to break the 1-vs-2 tie, unless `CONTEXTO_ASSUME_MULTISESSAO=1` / `=0`.

## File format

All files carry YAML frontmatter (the script reads/writes it with zero tokens) + a short markdown body:

```markdown
---
updated: 2026-09-28
tier: 2
---
```

- `TODO.md` adds `active: true|false` — import only while active.
- `<!-- auto:start --> … <!-- auto:end -->` blocks belong to the script (date, `git log`, commands, `ls`). The model never edits inside them by hand; the script never touches anything outside them.
- One line per fact, with greppable tags: `- [2026-09-28] [pytest] fact — consequence`. Fill in the user's language (bundled templates are PT-BR).
- `BUGS.md`: each block opens with `## YYYY-MM-DD — short title` and contains the literal error message.

## Imports (opencode and claude)

- Claude Code: `@.claude/context/STATUS.md` etc. in the root `CLAUDE.md`.
- opencode: root `CLAUDE.md` is read as a fallback; the canonical alternative is the `instructions` field in `opencode.json`:
  ```json
  { "$schema": "https://opencode.ai/config.json",
    "instructions": [".claude/context/STATUS.md", ".claude/context/MAP.md"] }
  ```
- `BUGS.md` never goes into imports — recipe: `grep -i "<error excerpt>" .claude/context/BUGS.md`.

## Budgets

- `STATUS.md` / `TODO.md`: 60 lines. `LEARNINGS.md`: 100. `MAP.md`: 60.
- Past the budget: summarize "Done" into 1 line or delete; `git log` keeps the rest.
