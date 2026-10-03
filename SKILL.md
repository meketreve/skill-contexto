---
name: contexto
description: Bootstraps lean project context in 3 tiers (MAP/STATUS/TODO/LEARNINGS/BUGS/WORKFLOW) with a zero-token script scaffold, and closes a session by updating those files. Use when the user asks to prepare/bootstrap project context, montar/iniciar o contexto, build a MAP/STATUS, organize project memory, or for a handoff — encerrar a sessão, passar o bastão, or before suggesting /clear.
---

# Tiered project context

Flow: **script first (zero tokens), model second (judgment only).**

## 1. Pick the tier

Run the script with auto-detection (it counts files — skipping tool/build dirs like `_bmad/`, `.agent/`, `node_modules/`, `build/` — detects monorepos, and for the tier 1–2 tie treats commits on 2+ distinct days as multi-session, asking only when git can't tell):

```bash
<skill-dir>/scripts/init.sh --tier auto
```

Add `--lang en` for English templates (`templates.en/`); default `auto` follows `$LANG` (`pt*` → PT-BR `templates/`, else English), overridable via `CONTEXTO_LANG`.

Rules (detail in `reference/tiers.md`):

- **Tier 1 — light/one-shot, <20 files:** minimal `MAP.md` only.
- **Tier 2 — medium/multi-session, 20–200 files:** adds `STATUS.md` + `LEARNINGS.md` (+ `TODO.md` if the task has 3+ steps and no issue tracker — only with `--todo`).
- **Tier 3 — large/monorepo/team:** adds per-package `TODO`, `WORKFLOW.md` if a process was adopted, `BUGS.md` split out only once LEARNINGS holds ~10+ bug entries.

Never create a file the tier doesn't call for. Deciding **not** to create is part of the job.

## 2. What the script already did (don't redo)

`init.sh` only creates missing files, never overwrites, and fills the `<!-- auto:start -->` blocks (date, `git log`, manifest commands, top-level `ls`) + ensures the imports in `CLAUDE.md`. Don't redo that by hand.

It warns `old format:` for a context file with no frontmatter or no auto block (written before the script) — such a file is never stamped or filled. Rerun with `--migrate` to add the template's frontmatter on top and its auto section at the end, keeping the text (backup in `FILE.bak`).

## 3. What the model fills in (only the ~20% needing judgment)

Write in the user's language (templates ship in PT-BR and English via `--lang`; keep the project's language):

- `MAP.md`: main flows (`X → Y → Z`) and whatever isn't obvious from names. Commands were already extracted by the script.
- `STATUS.md`: "current state" in 2–4 lines and "next phase" with file/entry point. The auto block already holds raw `git log`/`git status`.
- `TODO.md`: only when active (frontmatter `active: true`).
- `LEARNINGS.md`: one line per fact as `- [YYYY-MM-DD] [tag] fact — consequence`. Only real corrections, version/API/CI gotchas, or decisions with rationale. A line that records something tried or decided carries a verdict after the tag: `[✓]` tested and kept, `[✗]` tried and rejected (the reason goes after —), `[↻ YYYY-MM-DD]` superseded by that day's entry. Never delete a `[✗]`: it is what stops the next session from trying it again.
- `BUGS.md` (tier 3): one block per bug with the literal error message (so `grep` finds it).
- `WORKFLOW.md` (tier 3): only if the user adopted an explicit process. One numbered step per line, `step → verify: check`, where the check is a command or an observable result, never "it works".

## 4. Import policy (don't import everything)

- Always: `@.claude/context/STATUS.md` (tier 2+) and `@.claude/context/MAP.md`.
- `LEARNINGS.md`: imported at tier 2+; at tier 1, consult on demand via grep.
- `TODO.md`: imported only while `active: true`.
- `BUGS.md`: never imported — `grep` the error message when needed.
- Recall from anything not imported (`BUGS.md`, a big `LEARNINGS*.md`): `<skill-dir>/scripts/index.sh` first, before reading or grepping blind. No args prints a table of contents (entries per section, verdict counts, line numbers to `Read` with offset); `index.sh TERM...` lists matching **entries** — whole multi-line entries, one line each, newest first; `-x` lists only `[✗]`, what was already tried and rejected. It is printed fresh on every call and never saved, so it can't go stale. Exact error text is still a job for `grep`.
- `WORKFLOW.md`: imported only if it exists.

In opencode, root `CLAUDE.md` is read as a global fallback; alternatively, declare the same files in the `instructions` field of `opencode.json`.

## 5. Budgets (context spending)

- `STATUS.md` / `TODO.md`: 60 lines max. `LEARNINGS.md`: 100. `MAP.md`: 60. **Counted outside `<!-- auto:start -->…<!-- auto:end -->` blocks** — the auto block is the script's, so it neither counts nor gets trimmed by hand.
- Measure: `awk '/<!-- auto:start -->/{s=1} !s{n++} /<!-- auto:end -->/{s=0} END{print n+0}' FILE`.
- Past that, summarize the manual part into 1 line or delete — `git log` is the source of truth. Exception: `[✗]` lines in LEARNINGS are never deleted (shrink them to the gist instead).

## 6. Hooks (optional)

Detail in `reference/hooks.md`. Only bring them up when the user asks to automate the hygiene — they are opt-in, never part of the default scaffold.

**The rule for every layer: a hook REMINDS or refreshes `auto` blocks — it never writes a manual section** (`STATUS` state, `MAP` flows, `TODO` items, `LEARNINGS` facts). A hook that writes judgment content defeats the script-first/model-second split. Hooks always exit 0; they remind, they never block.

- **Git hook** (this repo): `.githooks/pre-commit` mirrors CI. Enable once per clone with `git config core.hooksPath .githooks` — it is not committable by design.
- **Agent hook** (per project): `SessionStart` suggests `/contexto` when `MAP.md` is missing — it never runs `init.sh` by itself, because creating files is the user's call. `PreToolUse` shows the recorded learnings/bugs that cite a file before its first edit in the session, and `PostToolUse` warns when a context file goes over budget — both through `scripts/hook.sh`, silent otherwise.

Finish with a short list of what was created and what was left blank for the user.

## 7. Closing a session (handoff)

On request only — never from a hook. Work from **this conversation**; don't re-explore the project.

1. `STATUS.md`: rewrite "current state" and "next phase" (concrete entry point and `→ verify:`), update pending items, move what finished to "done", trim "done" past ~10 items.
2. `TODO.md`: drop what finished, keep half-done work in "now", add findings to "later". Queue empty → `active: false`.
3. `LEARNINGS.md`: this session's corrections, gotchas and decisions, with the verdict (`[✓]`/`[✗]`/`[↻ date]`) on anything tried or decided. Skip if there were none.
4. `BUGS.md`: fixes that meet the rule (broken build/CI, reported bug, >2 attempts), with the literal error message.
5. `MAP.md`: paths that took more than 2–3 searches, commands discovered.

Bump `updated:` on every file touched; budgets, auto blocks and "no file the tier doesn't call for" apply as above (a missing file is created by `init.sh`, never by copying a template by hand). Don't commit unless asked. Finish with 3–5 lines: what was updated and the next phase.
