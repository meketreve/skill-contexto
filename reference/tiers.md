# Tiers, formats, and import policy

## Tiers

| Tier | When | Creates | Always imports |
|---|---|---|---|
| 1 — light | one-shot, <20 files, single session | minimal `MAP.md` | `MAP.md` |
| 2 — medium | 20–200 files **or** 2+ sessions | + `STATUS.md`, `LEARNINGS.md`, `TODO.md` only with `--todo` (3+ steps without tracker) | `STATUS + MAP + LEARNINGS` |
| 3 — large | monorepo (`packages/*/`, `apps/*/`, workspaces), team | + `BUGS.md` (always), `WORKFLOW.md` if adopted, `TODO.md` only with `--todo` | `STATUS + MAP + LEARNINGS` |

`BUGS.md` is never imported at any tier — it ships in the tier 3 scaffold, but access is via `grep`/`index.sh`. The TODO is a single file, created only with `--todo`: there is no per-package TODO.

Auto-detection (`scripts/init.sh --tier auto`):

1. Counts files: `git ls-files | wc -l` (fallback: `find . -type f -not -path './.git/*' | wc -l`), skipping tool/build dirs (`.git`, `_bmad`, `.agent`, `.claude`, `.wolf`, `node_modules`, `build`, `.cxx`, `__pycache__`, `.venv`).
2. Detects monorepo: a subdirectory under `packages/` or `apps/` (an empty dir does **not** count), `"workspaces"` in `package.json`, `[workspace]` in `Cargo.toml`. There is no `pyproject.toml` detection.
3. `<20` files and no monorepo → tier 1–2 tie; `20–200` → tier 2; monorepo or `>200` → tier 3.
4. Tier 1–2 tie: `CONTEXTO_ASSUME_MULTISESSAO=1` → 2 and `=0` → 1, and both win over git; commits on 2+ distinct days → 2 (warning on stderr); with a TTY and no `--yes` the script asks `will this last more than one session? (y/n)`; with no TTY (agent/CI) or with `--yes` → 2 with the warning `no TTY: tier 1-2 tie resolved to 2 (multi-session default); force one-shot with --tier 1 or CONTEXTO_ASSUME_MULTISESSAO=0`. `--yes` only means "never prompt", not "one-shot": force `--tier 1` or `CONTEXTO_ASSUME_MULTISESSAO=0` for a single-session project.

`--tier 1|2|3` forces the tier. `--tier 7` and `--lang xx` are errors, and an option without a value (`--tier` at the end of the line) prints `usage` and exits 1.

Template language (`--lang auto|pt|en`, or `CONTEXTO_LANG`): `auto` follows `$LANG` (`pt*` → PT-BR `templates/`, anything else → `templates.en/`). The auto-block labels follow the language too — the date prints as `date:` (EN) / `data:` (PT) and the index as `NO-RLS` (EN) / `SEM-RLS` (PT) — so generated content always matches the template.

## File format

All files carry YAML frontmatter (the script reads/writes it with zero tokens) + a short markdown body:

```markdown
---
updated: 2026-09-28
tier: 2
---
```

- `TODO.md` adds `active: true|false` — import only while active. `init.sh` creates it only with `--todo`. **The model owns activating it:** appeared work of 3+ steps outside the request, or an idea that needs a queue → create/update `TODO.md`, set `active: true`, and say so in one line. `--check` warns when `STATUS.md` has a 3+ item prose queue with no active TODO, and when an active TODO has no open items; an inactive TODO with open items is an error.
- `<!-- auto:start --> … <!-- auto:end -->` blocks belong to the script (date, `git log`, commands, `ls`). The model never edits inside them by hand; the script never touches anything outside them. An unbalanced marker (no `end`) → the script warns `skipped FILE: unbalanced …` and **does not touch the file**.
- `MAP.md` may carry a second script block, `<!-- auto:start index -->…<!-- auto:end index -->` (opt-in with `init.sh --index`, refreshed on every run once present): tables (RLS, policies), SQL functions, edge functions, routes — each item `name  file:line`, capped per section. Same rule as any auto block: never edited by hand, never counted in the budget. Not a tier of its own — it fits tier 2 and 3 equally; on tier 1 it usually costs more than it saves. `--check` verifies both the balance and the freshness of this block: it regenerates it in memory and diffs, writing nothing.
- One line per fact, with greppable tags: `- [2026-09-28] [pytest] fact — consequence`. Fill in the user's language (templates ship in PT-BR and English).
- Verdict, on lines that record something tried or decided (plain facts like preferences and gotchas go without): `[✓]` tested and kept, `[✗]` tried and rejected — the reason after the dash, `[↻ YYYY-MM-DD]` superseded by that day's entry. Symbols, not words, so the same grep works in both languages:
  - what failed before: `grep -n '\[✗\]' .claude/context/LEARNINGS*.md`
  - what holds today in an area: `grep -n '\[rede\] \[✓\]' .claude/context/LEARNINGS*.md`
  - what changed: `grep -n '\[↻' .claude/context/LEARNINGS*.md`
- Entry-level recall: `scripts/index.sh` (table of contents), `index.sh TERM...` (matching entries, all their lines, newest first), `index.sh -x` (only `[✗]`), `index.sh --brief TERM...` (a paste-ready block for a subagent brief). Reads `LEARNINGS*.md`, `BUGS*.md` and `memory/*.md`, writes nothing.
- Long-term memory (`.claude/context/memory/<tag>.md`, tier 2+): cold storage for the same entry format as `LEARNINGS.md`, frontmatter with `updated:` on top. A tag that outgrows the hot file moves there **whole**, verdicts included, and leaves one pointer in `LEARNINGS.md` under `## Long-term memory` (`## Long-term memory` / `## Memória de longo prazo`, following the template language): `- [YYYY-MM-DD] [tag] → memory/<tag>.md — N entries: gist`. Nothing is deleted. Files appear on first promotion (`mkdir -p`), are never scaffolded by `init.sh`, never imported and never bundled; `--check` only verifies that each pointer resolves and that the pointer list stays inside 15 lines.
- Superseding: mark the old line `[↻ date]` and write the new one; don't edit the old line into the new decision, or the history of why is lost. At the budget, a `[↻]` line can shrink to its gist — a `[✗]` line stays.
- `BUGS.md`: each block opens with `## YYYY-MM-DD — short title` and contains the literal error message. Its `updated:` is stamped like every other file.
- Old format (no frontmatter, or no auto block where the template has one): the script warns `old format:` and **does not create** what is missing — it adds neither frontmatter nor block — but it **does refresh** an auto block that already exists and stamps `updated:` when the key is there. `--migrate` puts the template's frontmatter on top and its auto section at the end, keeping the text (backup in `FILE.bak`).

## Imports (who reads what)

- Claude Code: `@.claude/context/STATUS.md` etc. in the root `CLAUDE.md` — `@path` imports are expanded.
- **DSH does not interpret `@path`**; it reads the project root's `AGENTS.md`/`CLAUDE.md` literally (source: `dsh-agent-instructions` README: "`@path` imports are not interpreted"). For it, use `init.sh --bundle`, which mirrors the import policy's files into `AGENTS.md`, verbatim.
- opencode (V2): reads `AGENTS.md` (the global `~/.config/opencode/AGENTS.md` plus every `AGENTS.md` from the workspace up to the project root) and the `instructions` array of `opencode.json`/`opencode.jsonc`. **It does not read `CLAUDE.md`** — tested on v2.3.0: a marker in `CLAUDE.md` was invisible, the same marker in `AGENTS.md` and in `instructions` was loaded. Two carriers, pick one:
  - `init.sh --bundle` mirrors the imported files into `AGENTS.md` (no config edit);
  - `init.sh --opencode` writes the same list into `instructions` (opt-in; timestamped backup, JSONC comments preserved, existing entries kept):
  ```jsonc
  { "$schema": "https://opencode.ai/config.json",
    "instructions": [".claude/context/MAP.md", ".claude/context/STATUS.md"] }
  ```
  `--check` fails when the project shows opencode usage (an `opencode.json*` or a `.opencode/` dir) and neither carrier is present or complete. Pick one carrier: when both the `AGENTS.md` bundle and the `opencode.json` instructions carry the same files, `--check` warns about the duplicated context (it costs tokens).
- Per tier: `MAP` always; `STATUS` and `LEARNINGS` at tier 2+ (tier 3 included); `TODO` only while `active: true`; `WORKFLOW` only if it exists.
- `BUGS.md` and `memory/*.md` never go into imports — recipes: `grep -i "<error excerpt>" .claude/context/BUGS.md`, and `scripts/index.sh <term>` for memory.

## Budgets

- `STATUS.md` / `TODO.md`: 60 lines. `LEARNINGS.md`: 100, plus 15 for its `Long-term memory` pointer list. `MAP.md`: 60 — all counted **outside the auto blocks**. The script owns what is inside `<!-- auto:start -->…<!-- auto:end -->`; it does not count toward the budget and is never trimmed by hand (it would come back on the next `init.sh` run anyway). `BUGS.md`, `WORKFLOW.md` and `memory/*.md` have no budget in `--check`.
- Measure the manual part: `awk '/<!-- auto:start/{s=1} !s{n++} /<!-- auto:end/{s=0} END{print n+0}' FILE` — or run `init.sh --check`, which measures the budgets for you and also checks missing files, markers, the `updated:` placeholder, off-policy imports, a stale bundle, the TODO/prose-queue state and paths cited in `MAP`/`STATUS` (read-only, exits 1 when it finds something; the path checks and the prose-queue/empty-active-TODO checks are warnings, while an inactive TODO with open items is an error). `init.sh --check --quiet` prints one line on success, for a session-start or closing ritual.
- Over budget, `--check` also suggests the cut: the 3 oldest dated lines and, for `LEARNINGS.md`, the tag with the most entries to promote to `memory/<tag>.md`.
- Past the budget: promote a whole `LEARNINGS` tag to `memory/<tag>.md` and leave the pointer (the only step that keeps knowledge); only then summarize "Done" into 1 line or delete — `git log` keeps the rest. `[✗]` lines are the exception — they travel to `memory/` with their entry, and shrink but are never deleted. `memory/` itself has no budget.
