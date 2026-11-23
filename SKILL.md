---
name: contexto
description: Project memory for multi-session work: recall recorded learnings, bugs and decisions before acting or delegating; record findings as they appear; keep MAP/STATUS/TODO/LEARNINGS within budget; close with a handoff. Use when starting or resuming a project, before spawning subagents, before /clear or compaction, when a context file contradicts the repo, or when the user asks o que já sabemos / montar ou atualizar contexto / passar o bastão. Skip one-shot edits.
license: MIT
version: 1.4.0
---

# Tiered project context

Flow: **script first (zero tokens), model second (judgment only).**

## 0. Agent quick path (coordinator / opencode)

`.claude/context/` reaches the model through `AGENTS.md` or the `instructions` array; the skill is for the **cycle**, not for reading STATUS. Load it once at the start of a multi-step task; skip it for a one-shot edit.

- **Recall before acting or delegating** — search the task's nouns, not the whole sentence: `index.sh --dir "$PWD" -n 10 TERM...` (or `--brief` for a paste-ready block). `-x` shows what was already tried and rejected. Never read `memory/*.md` whole.
- **Brief a subagent** — paste the hits, name the entry point `file:line`, forbid editing `STATUS.md`/`TODO.md`/`MAP.md`, and ask for findings as `- [YYYY-MM-DD] [tag] [✓|✗] fact — consequence`. Template in `reference/agent-integration.md`.
- **Promote on return** — confirm first, then write `LEARNINGS.md` (short/broad), `memory/<tag>.md` + a pointer (long), or `BUGS.md` (literal error). A subagent's guess is not a learning.
- **Close** — update `STATUS.md`/`LEARNINGS.md` as facts appear; full handoff on request or at the end of a multi-step task (§7). `--check` is read-only; `--check --quiet` is the one-line version.
- **Windows** — every script goes through `scripts/win/ctx.mjs`. On opencode the installed plugin also exposes `contexto_recall`, `contexto_brief`, `contexto_status` and `contexto_check`, so the agent does not build a path or a shell line.

**Automatic vs. your job.** The hooks/plugin recall entries when a tool touches a file, warn about budget, ask for what compaction is about to drop, and fire inside each subagent. They never know your task terms and never write judgment content. So:

| Automatic | Your job |
|---|---|
| Recall when a file is touched | Recall by **task terms** before delegating |
| Budget warning after a context edit | Decide the promotion to `memory/` and the trim |
| Compaction nudge | Write the fact when it appears |
| Recall inside each subagent (own session) | The brief and the promotion of its findings |
| Markers/imports/carriers checked by `--check` | MAP flows, STATUS state, TODO queue, LEARNINGS facts |

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

**`--check` (read-only):** writes nothing in the project, does not even create `.claude/`, and never prompts; it exits 1 when it finds a problem. It checks: files the tier calls for and are missing; the manual-part budget (60/60/60/100 outside auto blocks, and 15 for the `LEARNINGS.md` memory pointer list); unbalanced `auto` markers; `updated:` still on a placeholder (`AAAA-MM-DD`/`YYYY-MM-DD`); a `memory/` pointer whose file no longer exists; a `memory/` file imported into `CLAUDE.md`; imports missing or off-policy (TODO imported while `active: false`, BUGS imported); a stale bundle; a stale code index; a `TODO.md` with `active: false` and open items (error). It also warns, without changing the exit code, when `STATUS.md` carries a prose queue (3+ items under a pendências/bloqueios/próxima fase heading) but no active TODO, when an active TODO has no open items, and when `MAP`/`STATUS` cite a path that does not exist or is 30+ days stale (warn-only for now). Over budget, it names the 3 oldest dated lines to cut and, for `LEARNINGS.md`, the tag to promote to `memory/`. It is the portable substitute for the `PostToolUse` budget warning, which only exists in Claude Code.

**`--dry-run`:** prints `would create` / `would update` / `untouched` for every file the run would touch and writes nothing — not even `.claude/`. It reports file creation, tier changes, carrier/instructions and bundle/code-index freshness; it does not diff the daily `auto` blocks byte by byte. Mutually exclusive with `--check`.

**Unbalanced auto block (no `end`):** the script warns and **does not touch the file** (`skipped FILE: unbalanced ...`), instead of deleting everything from the marker to EOF. Applies to the `auto` block, to `auto:start index` and to the bundle.

**Code index (opt-in):** `init.sh --index` adds a second script-owned block to `MAP.md` (`<!-- auto:start index -->`): tables with RLS on/off and policy count, SQL functions (from `migrations/*.sql`), edge functions (`supabase|netlify/functions/*`) and routes (React Router `path`, `app.get('/x')`-style handlers, SvelteKit/Next.js file routes), each with `file:line`. Once added, every run refreshes it, so it never goes stale. Offer it when the project has migrations, edge functions or routes and sessions keep searching for where they live; skip it on a tiny project, since it is imported every session. It is grep, not a graph: for call sites and definitions on demand, use the LSP tool. Labels follow the language — RLS prints as `NO-RLS` (EN) or `SEM-RLS` (PT), and the date as `date:`/`data:`. RLS is detected on a continuation line and with `FORCE`, a policy whose name contains " on " counts for the right table, edge functions print as `name  path/index.ts:1` (or the flat `netlify/functions/x.ts` form) and file-based routes as `path  file:1`.

**Old format:** the script warns `old format:` for a context file with no frontmatter or without the auto block the template has. It **does not create** what is missing — it adds neither frontmatter nor block — but it **does refresh** an auto block that already exists and stamps `updated:` when the key is there. Rerun with `--migrate` to put the template's frontmatter on top and its auto section at the end, keeping the text (backup in `FILE.bak`).

## 3. What the model fills in (only the ~20% needing judgment)

Write in the user's language (templates ship in PT-BR and English via `--lang`; keep the project's language):

- `MAP.md`: main flows (`X → Y → Z`) and whatever isn't obvious from names. Commands were already extracted by the script.
- `STATUS.md`: "current state" in 2–4 lines and "next phase" with file/entry point. The auto block already holds raw `git log`/`git status`.
- `TODO.md`: only when active (frontmatter `active: true`). **You own activating it.** Appeared work of 3+ steps outside the request, or an idea that needs a queue? Create/update `TODO.md`, set `active: true`, and say so in one line. Do not wait to be asked.
- `LEARNINGS.md`: one line per fact as `- [YYYY-MM-DD] [tag] fact — consequence`. Only real corrections, version/API/CI gotchas, or decisions with rationale. A line that records something tried or decided carries a verdict after the tag: `[✓]` tested and kept, `[✗]` tried and rejected (the reason goes after —), `[↻ YYYY-MM-DD]` superseded by that day's entry. Never delete a `[✗]`: it is what stops the next session from trying it again.
- **Write the line when the fact appears, not only at the handoff.** A session that compacts before closing takes unwritten knowledge with it; the file is the only memory that survives compaction.
- **Long-term memory (`memory/`, tier 2+):** hot facts stay in `LEARNINGS.md`. When a tag grows past a handful of lines, or the file nears its budget, move that whole tag — verbatim, verdicts included — to `.claude/context/memory/<tag>.md` and leave one pointer under `## Long-term memory`: `- [YYYY-MM-DD] [tag] → memory/<tag>.md — N entries: gist`. The pointer list has its own 15-line budget; past it, merge topics. `memory/` is never imported — it is reached through `index.sh`, and `--check` verifies the pointers still resolve.
- **Trust and cadence:** `MAP.md`/`STATUS.md` are claims from another session, not truth. If the narrative contradicts the repo, run `--check` and verify the cited path before acting. `updated:` is re-stamped by `init.sh`, so it is not a freshness signal — use `git log -- .claude/context/STATUS.md` or a `checked:` note. Update facts incrementally as they appear; the full handoff (§7) is on request or at the end of a multi-step task.
- `BUGS.md` (tier 3): one block per bug with the literal error message (so `grep` finds it).
- `WORKFLOW.md` (tier 3): only if the user adopted an explicit process. One numbered step per line, `step → verify: check`, where the check is a command or an observable result, never "it works".

## 4. Import policy (don't import everything)

- Always: `@.claude/context/STATUS.md` (tier 2+) and `@.claude/context/MAP.md`.
- `LEARNINGS.md`: imported at tier 2+ (tier 3 included); at tier 1, consult on demand via grep.
- `TODO.md`: imported only while `active: true`.
- `BUGS.md`: never imported — `grep` the error message when needed.
- Recall from anything not imported (`BUGS.md`, `memory/*.md`, a big `LEARNINGS*.md`): `<skill-dir>/scripts/index.sh` first, before reading or grepping blind. No args prints a table of contents (entries per section, verdict counts, line numbers to `Read` with offset); `index.sh TERM...` lists matching **entries** — whole multi-line entries, one line each, newest first; `-x` lists only `[✗]`, what was already tried and rejected. It is printed fresh on every call and never saved, so it can't go stale. Exact error text is still a job for `grep`.
- `memory/` is **never** imported and never bundled: it is the cold tier. Only its pointers live in `LEARNINGS.md`, which is imported.
- `WORKFLOW.md`: imported only if it exists.

**Who reads what (per-harness carriers):** Claude Code expands `@path` imports in the root `CLAUDE.md`. **DSH does not interpret `@path`** — it reads the project root's `AGENTS.md`/`CLAUDE.md` literally (source: `dsh-agent-instructions` README: "`@path` imports are not interpreted") — which is what `--bundle` is for. **opencode V2 ignores `CLAUDE.md`** (tested on v2.3.0) and reads `AGENTS.md` plus the `instructions` array of `opencode.json`; use `--bundle` (mirrors into `AGENTS.md`) or `--opencode` (writes `instructions`, opt-in, backup, JSONC preserved). **Pick one**: both carriers duplicate the same files in the prompt and cost tokens; `--check` warns when it sees both. `--check` fails when opencode is in use and neither carrier reaches the context.

**Windows (no bash on PATH):** run the scripts through `scripts/win/ctx.mjs` — `node <skill>/scripts/win/ctx.mjs init.sh --tier auto --dir C:\repo`. It execs the script directly on POSIX and through WSL's bash (`CONTEXTO_BASH`/`CONTEXTO_WSL_DISTRO` override) on Windows, translating the Windows paths in its arguments. The opencode plugin goes through the same launcher and counts budget lines in JS, so nothing needs `awk` or `bash` on PATH; `install.sh` installs copies there because symlinks require an elevated shell.

## 5. Budgets (context spending)

- `STATUS.md` / `TODO.md`: 60 lines max. `LEARNINGS.md`: 100. `MAP.md`: 60. **Counted outside `<!-- auto:start -->…<!-- auto:end -->` blocks** — the auto block is the script's, so it neither counts nor gets trimmed by hand. (`BUGS.md` and `WORKFLOW.md` have no budget in `--check`.)
- Measure: `awk '/<!-- auto:start/{s=1} !s{n++} /<!-- auto:end/{s=0} END{print n+0}' FILE` — or let `--check` measure it for you.
- Past that: in `LEARNINGS.md`, promote a whole tag to `memory/` first (see §3) — only then summarize into 1 line or delete. `[✗]` lines are never deleted; they travel to `memory/` with their entry, and a `[↻]` line left behind shrinks to its gist. In the other files, summarize or delete — `git log` is the source of truth.
- `--check` does not just count: over budget it lists the 3 oldest dated lines to cut and, for `LEARNINGS.md`, the tag with the most entries to promote — the decision stops being guesswork.

## 6. Hooks (optional)

Detail in `reference/hooks.md`. Only bring them up when the user asks to automate the hygiene — they are opt-in, never part of the default scaffold.

**The rule for every layer: a hook REMINDS or refreshes `auto` blocks — it never writes a manual section** (`STATUS` state, `MAP` flows, `TODO` items, `LEARNINGS` facts). A hook that writes judgment content defeats the script-first/model-second split. The context (agent) hooks always exit 0; they remind, they never block. `.githooks/pre-commit` is a different thing: a lint gate that **blocks on purpose** when a check fails.

- **Git hook** (this repo): `.githooks/pre-commit` mirrors CI; enable once per clone with `git config core.hooksPath .githooks` — it is not committable by design.
- **Agent hook** (per project): `SessionStart` suggests `/contexto` when `MAP.md` is missing — it never runs `init.sh` by itself, because creating files is the user's call. `PreToolUse` shows the recorded learnings/bugs that cite a file before its first edit in the session, and `PostToolUse` warns when a context file goes over budget — both through `scripts/hook.sh`, silent otherwise. `--check` covers the budget without depending on Claude Code.
- **opencode** (this repo's plugin, installed with the skill): `plugins/opencode` registers `context`, `compaction` and tool hooks natively — the same recall, budget warning and compaction instruction as `hook.sh`, in TypeScript. It also exposes the native tools `contexto_recall`, `contexto_brief`, `contexto_status` and `contexto_check` (no write tool: judgment content stays with the model). It finds `index.sh` through the skill dir and stays silent without `.claude/context/`. It runs the scripts through `scripts/win/ctx.mjs`, so the same plugin works on Windows (WSL) and POSIX. Pitfalls: `event.system.push()` is the only vector the model obeys (`instructions.entry` reads as untrusted), `console.warn` never reaches the model, and a plugin edit needs a restart or `--standalone`. Detail in `reference/hooks.md`.
- **Compaction** (`PreCompact` + `SessionStart` with matcher `compact`): the first turns a static list into instructions for the compaction summary — errors, paths, commands and decisions verbatim; the second, right after, asks for whatever is still unwritten and hands back the `index.sh` table of contents. This is what survives a session that compacts before it closes, which is exactly the case the handoff never reaches. Wire it on long sessions; keep it static and fast.

Finish with a short list of what was created and what was left blank for the user.

## 7. Closing a session (handoff)

Incremental updates happen when a fact appears (§3); the **full handoff** below runs on request, at the end of a multi-step task, or before `/clear` — never from a hook. Work from **this conversation**; don't re-explore the project.

1. `STATUS.md`: rewrite "current state" and "next phase" (concrete entry point and `→ verify:`), update pending items, move what finished to "done", trim "done" past ~10 items.
2. `TODO.md`: drop what finished, keep half-done work in "now", add findings to "later". Queue empty → `active: false`.
3. `LEARNINGS.md`: this session's corrections, gotchas and decisions, with the verdict (`[✓]`/`[✗]`/`[↻ date]`) on anything tried or decided. Over budget, or with a tag past ~6 lines: promote that tag to `memory/<tag>.md` and leave the pointer — don't delete. Skip if there were none.
4. `BUGS.md`: fixes that meet the rule (broken build/CI, reported bug, >2 attempts), with the literal error message.
5. `MAP.md`: paths that took more than 2–3 searches, commands discovered.

Bump `updated:` on every file touched; budgets, auto blocks and "no file the tier doesn't call for" apply as above (a missing file is created by `init.sh`, never by copying a template by hand). Don't commit unless asked. Finish with 3–5 lines: what was updated and the next phase.

## 8. Subagents

A subagent sees nothing of this conversation and its transcript is not read back. Hand memory over explicitly, both ways — detail and template in `reference/subagents.md`:

- **Before:** search the memory with `index.sh` using the task's terms and paste the hits into the brief; forbid it from editing `STATUS.md`/`TODO.md`/`MAP.md`; ask for findings in the `- [YYYY-MM-DD] [tag] [✓|✗] fact — consequence` format.
- **After:** read its final message and promote what holds — `LEARNINGS.md` for the short and broad, `memory/<tag>.md` plus a pointer for the long, `BUGS.md` for anything with a literal error. Its guesses are not learnings until you confirm them.
- **Automatic half:** `PreToolUse` recall already fires inside subagents (the marker carries `agent_id`, so it does not inherit yours), and `SubagentStop` asks for the findings once per agent. For fan-out, give each subagent its own `memory/<tag>.md` — parallel appends to `LEARNINGS.md` interleave.
- **Coordinator contract:** the ready-to-paste session-start / pre-delegation / post-return / close rules and the PT-BR brief template live in `reference/agent-integration.md`.
