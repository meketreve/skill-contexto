# skill-contexto

Lean project context in **3 tiers** for Claude Code and opencode. The script scaffolds everything mechanical with zero tokens; the model fills in only what needs judgment.

## Tiers

| Tier | When | Creates |
|---|---|---|
| 1 | one-shot, <20 files | `MAP.md` |
| 2 | 20–200 files or 2+ sessions | + `STATUS.md`, `LEARNINGS.md`, `TODO.md` (3+ steps, no tracker) |
| 3 | monorepo / team | + on-demand `BUGS.md`, `WORKFLOW.md` if adopted |

Detail in `reference/tiers.md`. Templates ship in PT-BR (`templates/`) and English (`templates.en/`); `--lang` picks (`auto` follows `$LANG`).

## Quick use

```bash
./scripts/init.sh --tier auto   # inside the project
./scripts/init.sh --tier 2 --lang en --yes
```

## Install

One-liner:

```bash
git clone https://github.com/meketreve/skill-contexto.git && ./skill-contexto/scripts/install.sh
```

`install.sh` symlinks the skill into the harnesses it detects on your machine (symlink = tracks `git pull`). Useful flags: `--only claude,opencode,agents` (override detection), `--copy` (frozen copy instead of link), `--force` (replace existing), `--project` (copies into `./.claude` + `./.opencode` for team sharing — commit them), `--uninstall`, `--list`.

| Harness | Skill path | Slash command | Notes |
|---|---|---|---|
| Claude Code | `~/.claude/skills/contexto` | n/a (skill auto-triggers) | project-level: `.claude/skills/contexto`; installed only if detected |
| opencode | `~/.config/opencode/skills/contexto` | `/context` + `/contexto` (`commands/context.md`, `commands/contexto.md` — aliases) | also auto-loads `~/.claude/skills` and `~/.agents/skills`; restart opencode after install; installed only if detected |
| Other Agent Skills harnesses | `~/.agents/skills/contexto` | — | any harness that discovers `SKILL.md` (see `install.sh --list`) |

Symlink or copy? Personal use → symlink (updates are one `git pull` away). Teams / pinned versions → `--copy` or `--project`, so the exact skill version travels with the repo.

No harness at all? The skill is pure bash + markdown. Clone it anywhere and run the scaffold directly — no plugin system required:

```bash
/path/to/skill-contexto/scripts/init.sh --tier auto --dir ~/my-project
```

## Layout

```
SKILL.md              # the skill (thin: picks tier, runs script, fills 20%)
scripts/init.sh       # zero-token scaffold (detection + auto blocks + imports, --lang en|pt)
scripts/install.sh    # links/copies the skill into your harnesses
.githooks/pre-commit  # local checks mirroring CI (enable: git config core.hooksPath .githooks)
templates/            # PT-BR: MAP STATUS TODO LEARNINGS (+ BUGS WORKFLOW for tier 3)
templates.en/         # English: same set
reference/tiers.md    # tiers, formats, imports, budgets (lazy load)
reference/hooks.md    # optional hooks: git (recommended) + agent SessionStart/PostToolUse (opt-in)
commands/context.md + contexto.md  # /context + /contexto for opencode (aliases, keep in sync)
```

## Hooks

Git (recommended, zero deps, mirrors CI):

```bash
git config core.hooksPath .githooks
```

Agent hooks are opt-in per project — see `reference/hooks.md`
(Claude Code native `SessionStart` + `PostToolUse` reminder;
opencode via Claude-compatible plugin; hooks remind, never auto-write).

## Conventions

- Frontmatter `updated/tier` (script-owned) + `<!-- auto:start -->` blocks (script-only).
- One line per fact with tags: `- [2026-09-28] [pytest] fact — consequence`.
- `BUGS.md` is never imported — `grep` the error message, or `scripts/index.sh` for a table of contents and entry-level search (`index.sh TERM...`, `index.sh -x` for what was rejected).
- Budgets: STATUS/TODO 60 lines, LEARNINGS 100, MAP 60 — counted outside the `<!-- auto -->` blocks, which belong to the script.
