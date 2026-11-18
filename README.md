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
```

## Install

One-liner:

```bash
git clone https://github.com/meketreve/skill-contexto.git && ./skill-contexto/scripts/install.sh
```

`install.sh` symlinks the skill into the harnesses it detects on your machine (symlink = tracks `git pull`). Useful flags: `--only claude,opencode,agents` (override detection), `--copy` (frozen copy instead of link), `--force` (replace existing), `--project` (copies into `./.claude` + `./.agents` + `./.opencode` for team sharing — commit them; `--project --uninstall` removes only those copies), `--uninstall`, `--list` (prints the skill version).

| Harness | Skill path | Slash command | Notes |
|---|---|---|---|
| Claude Code | `~/.claude/skills/contexto` | n/a (skill auto-triggers) | project-level: `.claude/skills/contexto`; installed only if detected |
| opencode | `~/.config/opencode/skills/contexto` | `/context` + `/contexto` (`commands/context.md`, `commands/contexto.md` — aliases) | also installs `~/.config/opencode/plugins/contexto` (recall + compaction) and auto-loads `~/.claude/skills`/`~/.agents/skills`; restart opencode after install; installed only if detected |
| Other Agent Skills harnesses | `~/.agents/skills/contexto` | — | any harness that discovers `SKILL.md` (see `install.sh --list`) |

**Loading the context in each harness.** Claude Code expands `@path` imports in `CLAUDE.md`, so the default scaffold is enough. DSH does *not* interpret `@path` — it loads `AGENTS.md`/`CLAUDE.md` from the project root literally — so run `init.sh --bundle` to mirror the same files, verbatim, into a script-owned block in `AGENTS.md`. **opencode V2 ignores `CLAUDE.md`** (tested on v2.3.0: a marker there was invisible), so it needs its own carrier — `--bundle` (the `AGENTS.md` block it already reads) or `--opencode` (writes the `instructions` array of `opencode.json`, opt-in, timestamped backup, JSONC comments preserved). `--check` fails when the project shows opencode usage and neither carrier is present or complete.

Symlink or copy? Personal use → symlink (updates are one `git pull` away). Teams / pinned versions → `--copy` or `--project`, so the exact skill version travels with the repo — `SKILL.md` carries `version:`, so a pinned copy can be identified.

No harness at all? The skill is pure bash + markdown. Clone it anywhere and run the scaffold directly — no plugin system required:

```bash
/path/to/skill-contexto/scripts/init.sh --tier auto --dir ~/my-project
```

## Layout

```
SKILL.md              # the skill (thin: picks tier, runs script, fills 20%; carries `version:`)
scripts/init.sh       # zero-token scaffold (detection + auto blocks + imports + bundle, --lang auto|pt|en)
scripts/index.sh      # recall index: table of contents and entry search for LEARNINGS/BUGS/memory
scripts/hook.sh       # agent hook payloads: recall by file, budget warning, compaction, subagent stop
scripts/install.sh    # links/copies the skill into your harnesses
.githooks/pre-commit  # local checks mirroring CI (enable: git config core.hooksPath .githooks)
.github/workflows/lint.yml  # CI: shellcheck, sync checks, smoke tests, --check and bundle guards
templates/            # PT-BR: MAP STATUS TODO LEARNINGS (+ BUGS WORKFLOW for tier 3)
templates.en/         # English: same set
reference/tiers.md    # tiers, formats, imports, budgets (lazy load)
reference/hooks.md    # optional hooks: git (recommended) + agent hooks incl. compaction (opt-in)
reference/subagents.md # handing memory to a subagent, and taking its findings back
commands/context.md + contexto.md  # /context + /contexto for opencode (aliases, keep in sync)
plugins/opencode/     # opencode V2 plugin: recall by file, budget, compaction instruction (installed by install.sh)
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
budget and compaction through native plugin hooks; hooks remind, never auto-write).

## Conventions

- Frontmatter `updated/tier` (script-owned) + `<!-- auto:start -->` blocks (script-only).
- Optional code index in `MAP.md` (`init.sh --index`): tables + RLS, SQL functions, edge functions and routes with `file:line`, regenerated on every run — a grep index, not a graph.
- Optional `AGENTS.md` bundle (`init.sh --bundle`): verbatim mirror of the files the import policy loads (MAP always; STATUS + LEARNINGS at tier 2+; TODO while `active: true`; WORKFLOW if it exists), for harnesses that don't expand `@imports`. Opt-in, refreshed on every later run, and whatever you wrote outside the block is preserved.
- Optional `opencode.json` carrier (`init.sh --opencode`): writes the same file list into the `instructions` array — opencode V2 ignores `CLAUDE.md`. Opt-in, existing entries kept, timestamped backup, JSONC comments preserved; once present, refreshed on every run. `--check` fails when opencode is in use and neither this list nor the `AGENTS.md` bundle carries the context.
- `init.sh --check` is read-only (writes nothing) and exits 1 on: missing tier files, over-budget manual parts (including the memory pointer list), unbalanced markers, a placeholder `updated:`, a memory pointer that does not resolve, a `memory/` file imported into `CLAUDE.md`, imports missing or off-policy, a stale bundle, a stale code index, or a context invisible to opencode.
- The bundle is derived, so `AGENTS.md` is safe to gitignore (this repo does) — or commit it when the team wants the context to travel with the checkout. Same call you already make for `.claude/context/`; `--check` keeps it honest either way.
- Typing a context file by hand is the one thing that breaks the model: the script owns the `auto` blocks and refuses to touch a file whose markers are unbalanced.
- One line per fact with tags: `- [2026-09-28] [pytest] fact — consequence`.
- `BUGS.md` is never imported — `grep` the error message, or `scripts/index.sh` for a table of contents and entry-level search (`index.sh TERM...`, `index.sh -x` for what was rejected).
- `memory/` (tier 2+) is the cold tier: a tag that outgrows `LEARNINGS.md` moves there whole, verdicts included, and leaves one pointer. Never imported, searched with `index.sh`, no budget, and `--check` fails on a pointer that no longer resolves.
- Budgets: STATUS/TODO 60 lines, LEARNINGS 100 (+15 for the memory pointer list), MAP 60 — counted outside the `<!-- auto -->` blocks, which belong to the script.
