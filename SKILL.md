---
name: contexto
description: Bootstraps lean project context in 3 tiers (MAP/STATUS/TODO/LEARNINGS/BUGS/WORKFLOW) with a zero-token script scaffold, and closes a session by updating those files. Use when the user asks to prepare/bootstrap project context, montar/iniciar o contexto, build a MAP/STATUS, organize project memory, or for a handoff — encerrar a sessão, passar o bastão, or before suggesting /clear.
license: MIT
version: 1.0.0
---

# Tiered project context

Flow: **script first (zero tokens), model second (judgment only).**

## 1. Pick the tier

Run the script with auto-detection (it counts files — skipping tool/build dirs like `_bmad/`, `.agent/`, `node_modules/`, `build/` — detects monorepos, and for the tier 1–2 tie treats commits on 2+ distinct days as multi-session, asking only when there is a TTY):

```bash
<skill-dir>/scripts/init.sh --tier auto
```

Add `--dir PROJECT` to scaffold a project other than the current directory.

Add `--lang en` for English templates (`templates.en/`); default `auto` follows `$LANG` (`pt*` → PT-BR `templates/`, else English), overridable via `CONTEXTO_LANG`.

Rules (detail in `reference/tiers.md`):

- **Tier 1 — light/one-shot, <20 files:** minimal `MAP.md` only.
- **Tier 2 — medium/multi-session, 20–200 files:** adds `STATUS.md` + `LEARNINGS.md` (+ `TODO.md` only with `--todo`, for a 3+ step task without an issue tracker).
- **Tier 3 — large/monorepo/team:** adds `BUGS.md` **always**, `WORKFLOW.md` if a process was adopted, and `TODO.md` only with `--todo`. There is no per-package TODO.

Tier 1–2 tie: `CONTEXTO_ASSUME_MULTISESSAO=1` forces 2 and `=0` forces 1, and both win over git; commits on 2+ days → 2. With no TTY (agent/CI) or with `--yes` the script **does not ask**: it goes to 2 with a warning on stderr (`no TTY: tier 1-2 tie resolved to 2 (multi-session default); force one-shot with --tier 1 or CONTEXTO_ASSUME_MULTISESSAO=0`). `--yes` no longer means "assume one-shot". `--tier 7` and `--lang xx` are errors; an option without a value → `usage` + exit 1.

Never create a file the tier doesn't call for. Deciding **not** to create is part of the job.

## 2. What the script already did (don't redo)

`init.sh` only creates missing files, never overwrites manual content, and fills the `<!-- auto:start -->` blocks (date, `git log`, manifest commands, top-level `ls`) + ensures the imports in `CLAUDE.md`. Don't redo that by hand.

**`--bundle` (opt-in):** creates/updates a `<!-- auto:start bundle -->`…`<!-- auto:end bundle -->` block in the target project's `AGENTS.md` with the very files the import policy loads, **verbatim** (MAP always; STATUS + LEARNINGS at tier 2+; TODO while `active: true`; WORKFLOW if it exists), each one preceded by `<!-- from .claude/context/X.md -->`. Without the flag and without the block, nothing is created; once present, it is refreshed on every run. User text outside the block is never touched: on an `AGENTS.md` that already exists the script only appends its own section (`## Project context (mirror of .claude/context/)`, or the PT equivalent under `--lang pt`), and when it creates the file it writes a header saying the truth lives in `.claude/context/` and that `--check` verifies the bundle.

**`--check` (read-only):** writes nothing in the project, does not even create `.claude/`, and never prompts; it exits 1 when it finds a problem. It checks: files the tier calls for and are missing; the manual-part budget (60/60/60/100 outside auto blocks); unbalanced `auto` markers; `updated:` still on a placeholder (`AAAA-MM-DD`/`YYYY-MM-DD`); imports missing or off-policy (TODO imported while `active: false`, BUGS imported); a stale bundle; a stale code index. It is the portable substitute for the `PostToolUse` budget warning, which only exists in Claude Code.

**Unbalanced auto block (no `end`):** the script warns and **does not touch the file** (`skipped FILE: unbalanced ...`), instead of deleting everything from the marker to EOF. Applies to the `auto` block, to `auto:start index` and to the bundle.

**Code index (opt-in):** `init.sh --index` adds a second script-owned block to `MAP.md` (`<!-- auto:start index -->`): tables with RLS on/off and policy count, SQL functions (from `migrations/*.sql`), edge functions (`supabase|netlify/functions/*`) and routes (React Router `path`, `app.get('/x')`-style handlers, SvelteKit/Next.js file routes), each with `file:line`. Once added, every run refreshes it, so it never goes stale. Offer it when the project has migrations, edge functions or routes and sessions keep searching for where they live; skip it on a tiny project, since it is imported every session. It is grep, not a graph: for call sites and definitions on demand, use the LSP tool. Labels follow the language — RLS prints as `NO-RLS` (EN) or `SEM-RLS` (PT), and the date as `date:`/`data:`. RLS is detected on a continuation line and with `FORCE`, a policy whose name contains " on " counts for the right table, edge functions print as `name  path/index.ts:1` (or the flat `netlify/functions/x.ts` form) and file-based routes as `path  file:1`.

**Old format:** the script warns `old format:` for a context file with no frontmatter or without the auto block the template has. It **does not create** what is missing — it adds neither frontmatter nor block — but it **does refresh** an auto block that already exists and stamps `updated:` when the key is there. Rerun with `--migrate` to put the template's frontmatter on top and its auto section at the end, keeping the text (backup in `FILE.bak`).

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
- `LEARNINGS.md`: imported at tier 2+ (tier 3 included); at tier 1, consult on demand via grep.
- `TODO.md`: imported only while `active: true`.
- `BUGS.md`: never imported — `grep` the error message when needed.
- Recall from anything not imported (`BUGS.md`, a big `LEARNINGS*.md`): `<skill-dir>/scripts/index.sh` first, before reading or grepping blind. No args prints a table of contents (entries per section, verdict counts, line numbers to `Read` with offset); `index.sh TERM...` lists matching **entries** — whole multi-line entries, one line each, newest first; `-x` lists only `[✗]`, what was already tried and rejected. It is printed fresh on every call and never saved, so it can't go stale. Exact error text is still a job for `grep`.
- `WORKFLOW.md`: imported only if it exists.

**Who reads what (per-harness carriers):** Claude Code expands `@path` imports in the root `CLAUDE.md`. **DSH does not interpret `@path`** — it reads the project root's `AGENTS.md`/`CLAUDE.md` literally (source: `dsh-agent-instructions` README: "`@path` imports are not interpreted") — which is what `--bundle` is for. In opencode, the canonical carrier is the `instructions` field in `opencode.json`; the root `CLAUDE.md` is the fallback.

## 5. Budgets (context spending)

- `STATUS.md` / `TODO.md`: 60 lines max. `LEARNINGS.md`: 100. `MAP.md`: 60. **Counted outside `<!-- auto:start -->…<!-- auto:end -->` blocks** — the auto block is the script's, so it neither counts nor gets trimmed by hand. (`BUGS.md` and `WORKFLOW.md` have no budget in `--check`.)
- Measure: `awk '/<!-- auto:start/{s=1} !s{n++} /<!-- auto:end/{s=0} END{print n+0}' FILE` — or let `--check` measure it for you.
- Past that, summarize the manual part into 1 line or delete — `git log` is the source of truth. Exception: `[✗]` lines in LEARNINGS are never deleted (shrink them to the gist instead).

## 6. Hooks (optional)

Detail in `reference/hooks.md`. Only bring them up when the user asks to automate the hygiene — they are opt-in, never part of the default scaffold.

**The rule for every layer: a hook REMINDS or refreshes `auto` blocks — it never writes a manual section** (`STATUS` state, `MAP` flows, `TODO` items, `LEARNINGS` facts). A hook that writes judgment content defeats the script-first/model-second split. The context (agent) hooks always exit 0; they remind, they never block. `.githooks/pre-commit` is a different thing: a lint gate that **blocks on purpose** when a check fails.

- **Git hook** (this repo): `.githooks/pre-commit` mirrors CI; enable once per clone with `git config core.hooksPath .githooks` — it is not committable by design.
- **Agent hook** (per project): `SessionStart` suggests `/contexto` when `MAP.md` is missing — it never runs `init.sh` by itself, because creating files is the user's call. `PreToolUse` shows the recorded learnings/bugs that cite a file before its first edit in the session, and `PostToolUse` warns when a context file goes over budget — both through `scripts/hook.sh`, silent otherwise. `--check` covers the budget without depending on Claude Code.

Finish with a short list of what was created and what was left blank for the user.

## 7. Closing a session (handoff)

On request only — never from a hook. Work from **this conversation**; don't re-explore the project.

1. `STATUS.md`: rewrite "current state" and "next phase" (concrete entry point and `→ verify:`), update pending items, move what finished to "done", trim "done" past ~10 items.
2. `TODO.md`: drop what finished, keep half-done work in "now", add findings to "later". Queue empty → `active: false`.
3. `LEARNINGS.md`: this session's corrections, gotchas and decisions, with the verdict (`[✓]`/`[✗]`/`[↻ date]`) on anything tried or decided. Skip if there were none.
4. `BUGS.md`: fixes that meet the rule (broken build/CI, reported bug, >2 attempts), with the literal error message.
5. `MAP.md`: paths that took more than 2–3 searches, commands discovered.

Bump `updated:` on every file touched; budgets, auto blocks and "no file the tier doesn't call for" apply as above (a missing file is created by `init.sh`, never by copying a template by hand). Don't commit unless asked. Finish with 3–5 lines: what was updated and the next phase.
