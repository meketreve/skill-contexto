# skill-contexto

Lean project context in **3 tiers** for Claude Code and opencode. The script scaffolds everything mechanical with zero tokens; the model fills in only what needs judgment.

## Tiers

| Tier | When | Creates |
|---|---|---|
| 1 | one-shot, <20 files | `MAP.md` |
| 2 | 20–200 files or 2+ sessions | + `STATUS.md`, `LEARNINGS.md`, and `TODO.md` only with `--todo` (3+ steps, no tracker) |
| 3 | monorepo / team | + `BUGS.md` (always), `WORKFLOW.md` if adopted |

Tier comes from the file count (tool/build dirs skipped) and the monorepo shape (`packages/*/`, `apps/*/`, `"workspaces"` in `package.json`, `[workspace]` in `Cargo.toml`). On a tier 1–2 tie, commits on 2+ days mean multi-session; with no TTY (agent/CI) or `--yes` the tie goes to **tier 2**, the multi-session default — `CONTEXTO_ASSUME_MULTISESSAO=1`/`=0` forces it and beats git.

Detail in `reference/tiers.md`. Templates ship in PT-BR (`templates/`) and English (`templates.en/`); `--lang auto|pt|en` picks (`auto` follows `$LANG`).

## Quick use

```bash
./scripts/init.sh --tier auto   # inside the project
./scripts/init.sh --tier 2 --lang en --yes
./scripts/init.sh --bundle      # mirror the imported files into AGENTS.md
./scripts/init.sh --opencode    # write the same list into opencode.json `instructions`
./scripts/init.sh --check       # read-only report; exits 1 on any problem
./scripts/init.sh --check --quiet  # one line on success (agent session start/close)
./scripts/index.sh --brief mercado  # paste-ready block for a subagent brief
./scripts/init.sh --dry-run     # would create/update/untouched, writes nothing
```

## Install

One-liner:

```bash
git clone https://github.com/meketreve/skill-contexto.git && ./skill-contexto/scripts/install.sh
```

`install.sh` symlinks the skill into the harnesses it detects on your machine (symlink = tracks `git pull`). Useful flags: `--only claude,opencode,agents` (override detection), `--copy` (frozen copy instead of link), `--force` (replace existing), `--project` (copies into `./.claude` + `./.agents` + `./.opencode` for team sharing — commit them; `--project --uninstall` removes only those copies), `--uninstall`, `--list` (prints the skill version).

**Windows.** There is normally no `bash` on a Windows PATH, so the skill ships a launcher, `scripts/win/ctx.mjs`, that runs the very same bash scripts through WSL's bash (or `CONTEXTO_BASH`/`CONTEXTO_WSL_DISTRO`) and translates the Windows paths it passes. Use it whenever you would run a script directly:

```powershell
node "$HOME\.config\opencode\skills\contexto\scripts\win\ctx.mjs" init.sh --tier auto --check
node "$HOME\.config\opencode\skills\contexto\scripts\win\ctx.mjs" index.sh --dir D:\repos\app mercado
```

`install.sh` under Git Bash/MSYS2/Cygwin detects Windows, resolves `%USERPROFILE%` and installs **copies** (symlinks there need an elevated shell), so `git config core.hooksPath` style tracking does not apply — rerun it after `git pull`. The opencode plugin uses the launcher too, and counts the budget lines in JS, so recall, compaction and budget warnings all work on Windows without `awk`.

| Harness | Skill path | Slash command | Notes |
|---|---|---|---|
| Claude Code | `~/.claude/skills/contexto` | n/a (skill auto-triggers) | project-level: `.claude/skills/contexto`; installed only if detected |
| opencode | `~/.config/opencode/skills/contexto` | `/context` + `/contexto` (`commands/context.md`, `commands/contexto.md` — aliases) | also installs `~/.config/opencode/plugins/contexto` (recall + compaction) and auto-loads `~/.claude/skills`/`~/.agents/skills`; restart opencode after install; installed only if detected |
| Other Agent Skills harnesses | `~/.agents/skills/contexto` | — | any harness that discovers `SKILL.md` (see `install.sh --list`) |

**Loading the context in each harness.** Claude Code expands `@path` imports in `CLAUDE.md`, so the default scaffold is enough. DSH does *not* interpret `@path` — it loads `AGENTS.md`/`CLAUDE.md` from the project root literally — so run `init.sh --bundle` to mirror the same files, verbatim, into a script-owned block in `AGENTS.md`. **opencode V2 ignores `CLAUDE.md`** (tested on v2.3.0: a marker there was invisible), so it needs its own carrier — `--bundle` (the `AGENTS.md` block it already reads) or `--opencode` (writes the `instructions` array of `opencode.json`, opt-in, timestamped backup, JSONC comments preserved). `--check` fails when the project shows opencode usage and neither carrier is present or complete. Pick one: `--bundle` and `--opencode` together duplicate the same files in the prompt, and `--check` now warns about it.

## Using from a coordinator

The skill is built for a primary agent that delegates. `reference/agent-integration.md` has the
contract: session start, recall with the task's terms before spawning a subagent, the PT-BR
brief template, promotion of the subagent's findings, and the close/handoff. In opencode, the
plugin also exposes `contexto_recall` and `contexto_brief`, so the coordinator does not build a
Windows/WSL path by hand; `contexto_status` and `contexto_check` cover the read-only hygiene.

Symlink or copy? Personal use → symlink (updates are one `git pull` away). Teams / pinned versions → `--copy` or `--project`, so the exact skill version travels with the repo — `SKILL.md` carries `version:`, so a pinned copy can be identified.

No harness at all? The skill is pure bash + markdown. Clone it anywhere and run the scaffold directly — no plugin system required:

```bash
/path/to/skill-contexto/scripts/init.sh --tier auto --dir ~/my-project
```

## Layout

```
SKILL.md              # the skill (thin: picks tier, runs script, fills 20%; carries `version:`)
scripts/init.sh       # zero-token scaffold (detection + auto blocks + imports + bundle, --lang auto|pt|en, --check, --dry-run)
scripts/index.sh      # recall index: table of contents and entry search for LEARNINGS/BUGS/memory
scripts/hook.sh       # agent hook payloads: recall by file, budget warning, compaction, subagent stop
scripts/win/ctx.mjs   # Windows launcher: runs those scripts through WSL (or CONTEXTO_BASH), translating paths
scripts/install.sh    # links/copies the skill into your harnesses (Windows: copies, no symlinks)
.githooks/pre-commit  # local checks mirroring CI (enable: git config core.hooksPath .githooks)
.github/workflows/lint.yml  # CI: shellcheck, sync checks, smoke tests, --check and bundle guards
templates/            # PT-BR: MAP STATUS TODO LEARNINGS (+ BUGS WORKFLOW for tier 3)
templates.en/         # English: same set
reference/tiers.md    # tiers, formats, imports, budgets (lazy load)
reference/hooks.md    # optional hooks: git (recommended) + agent hooks incl. compaction (opt-in)
reference/subagents.md # handing memory to a subagent, and taking its findings back
reference/agent-integration.md # coordinator contract + PT-BR subagent brief template
commands/context.md + contexto.md  # /context + /contexto for opencode (aliases, keep in sync)
plugins/opencode/     # opencode V2 plugin: recall, budget, compaction, native contexto_* tools (installed by install.sh)
```

## Hooks

Git (recommended, zero deps, mirrors CI):

```bash
git config core.hooksPath .githooks
```

Agent hooks are opt-in per project — see `reference/hooks.md`
(Claude Code native `SessionStart` + `PreToolUse` + `PostToolUse` + `SubagentStop` +
`PreCompact`; `PreToolUse` recalls the recorded learnings/bugs that cite a file before its
first edit in the session, `PostToolUse` warns when a context file goes over budget,
`PreCompact` feeds the compaction summary the facts a paraphrase eats, `SubagentStop` makes
a subagent write its findings before it dies — all through `scripts/hook.sh`, silent
otherwise; opencode uses `plugins/opencode`, installed by `install.sh`, with the same recall,
budget and compaction through native plugin hooks plus the read-only tools
`contexto_recall`, `contexto_brief`, `contexto_status` and `contexto_check`; hooks remind,
never auto-write).

## Conventions

- Frontmatter `updated/tier` (script-owned) + `<!-- auto:start -->` blocks (script-only).
- Optional code index in `MAP.md` (`init.sh --index`): tables + RLS, SQL functions, edge functions and routes with `file:line`, regenerated on every run — a grep index, not a graph.
- Optional `AGENTS.md` bundle (`init.sh --bundle`): verbatim mirror of the files the import policy loads (MAP always; STATUS + LEARNINGS at tier 2+; TODO while `active: true`; WORKFLOW if it exists), for harnesses that don't expand `@imports`. Opt-in, refreshed on every later run, and whatever you wrote outside the block is preserved.
- Optional `opencode.json` carrier (`init.sh --opencode`): writes the same file list into the `instructions` array — opencode V2 ignores `CLAUDE.md`. Opt-in, existing entries kept, timestamped backup, JSONC comments preserved; once present, refreshed on every run. `--check` fails when opencode is in use and neither this list nor the `AGENTS.md` bundle carries the context.
- `init.sh --check` is read-only (writes nothing) and exits 1 on: missing tier files, over-budget manual parts (including the memory pointer list), unbalanced markers, a placeholder `updated:`, a memory pointer that does not resolve, a `memory/` file imported into `CLAUDE.md`, imports missing or off-policy, a stale bundle, a stale code index, a `TODO.md` with `active: false` and open items, or a context invisible to opencode. It warns without failing on a STATUS prose queue without an active TODO, an active TODO with no open items, both opencode carriers duplicating the context, and `MAP`/`STATUS` paths that are missing or 30+ days stale (exact token match, so `metricas.json` does not match inside `metricas.jsonl`); over budget it names the 3 oldest dated lines (and the `LEARNINGS` tag to promote). `--check --quiet` prints one line on success.
- `init.sh --dry-run` reports `would create` / `would update` / `untouched` for the files the run would touch, including tier changes, carriers, bundle and code index, and writes nothing. Mutually exclusive with `--check`.
- Backups (`*.bak*`, `*.orig`, `*~`) are filtered from the file count, the MAP top-level listing and the code index.
- The bundle is derived, so `AGENTS.md` is safe to gitignore (this repo does) — or commit it when the team wants the context to travel with the checkout. Same call you already make for `.claude/context/`; `--check` keeps it honest either way.
- Typing a context file by hand is the one thing that breaks the model: the script owns the `auto` blocks and refuses to touch a file whose markers are unbalanced.
- One line per fact with tags: `- [2026-09-28] [pytest] fact — consequence`.
- `BUGS.md` is never imported — `grep` the error message, or `scripts/index.sh` for a table of contents and entry-level search (`index.sh TERM...`, `index.sh -x` for what was rejected, `index.sh --brief TERM...` for a paste-ready block).
- `memory/` (tier 2+) is the cold tier: a tag that outgrows `LEARNINGS.md` moves there whole, verdicts included, and leaves one pointer. Never imported, searched with `index.sh`, no budget, and `--check` fails on a pointer that no longer resolves.
- Budgets: STATUS/TODO 60 lines, LEARNINGS 100 (+15 for the memory pointer list), MAP 60 — counted outside the `<!-- auto -->` blocks, which belong to the script.
