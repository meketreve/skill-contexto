---
name: contexto
description: Bootstraps lean project context in 3 tiers (MAP/STATUS/TODO/LEARNINGS/BUGS/WORKFLOW) with a zero-token script scaffold. Use when the user asks to prepare/bootstrap project context, montar/iniciar o contexto, build a MAP/STATUS, or organize project memory.
---

# Tiered project context

Flow: **script first (zero tokens), model second (judgment only).**

## 1. Pick the tier

Run the script with auto-detection (it counts files, detects monorepos, and asks whether the work spans more than one session):

```bash
<skill-dir>/scripts/init.sh --tier auto
```

Add `--lang en` for English templates (`templates.en/`); default `auto` follows `$LANG` (`pt*` → PT-BR `templates/`, else English), overridable via `CONTEXTO_LANG`.

Rules (detail in `reference/tiers.md`):

- **Tier 1 — light/one-shot, <20 files:** minimal `MAP.md` only.
- **Tier 2 — medium/multi-session, 20–200 files:** adds `STATUS.md` + `LEARNINGS.md` (+ `TODO.md` if the task has 3+ steps and no issue tracker).
- **Tier 3 — large/monorepo/team:** adds per-package `TODO`, `WORKFLOW.md` if a process was adopted, `BUGS.md` split out only once LEARNINGS holds ~10+ bug entries.

Never create a file the tier doesn't call for. Deciding **not** to create is part of the job.

## 2. What the script already did (don't redo)

`init.sh` only creates missing files, never overwrites, and fills the `<!-- auto:start -->` blocks (date, `git log`, manifest commands, top-level `ls`) + ensures the imports in `CLAUDE.md`. Don't redo that by hand.

## 3. What the model fills in (only the ~20% needing judgment)

Write in the user's language (templates ship in PT-BR and English via `--lang`; keep the project's language):

- `MAP.md`: main flows (`X → Y → Z`) and whatever isn't obvious from names. Commands were already extracted by the script.
- `STATUS.md`: "current state" in 2–4 lines and "next phase" with file/entry point. The auto block already holds raw `git log`/`git status`.
- `TODO.md`: only when active (frontmatter `active: true`).
- `LEARNINGS.md`: one line per fact as `- [YYYY-MM-DD] [tag] fact — consequence`. Only real corrections, version/API/CI gotchas, or decisions with rationale.
- `BUGS.md` (tier 3): one block per bug with the literal error message (so `grep` finds it).
- `WORKFLOW.md` (tier 3): only if the user adopted an explicit process.

## 4. Import policy (don't import everything)

- Always: `@.claude/context/STATUS.md` (tier 2+) and `@.claude/context/MAP.md`.
- `LEARNINGS.md`: imported at tier 2+; at tier 1, consult on demand via grep.
- `TODO.md`: imported only while `active: true`.
- `BUGS.md`: never imported — `grep` the error message when needed.
- `WORKFLOW.md`: imported only if it exists.

In opencode, root `CLAUDE.md` is read as a global fallback; alternatively, declare the same files in the `instructions` field of `opencode.json`.

## 5. Budgets (context spending)

- `STATUS.md` / `TODO.md`: 60 lines max. `LEARNINGS.md`: 100. Past that, summarize into 1 line or delete — `git log` is the source of truth.
- Finish with a short list of what was created and what was left blank for the user.
