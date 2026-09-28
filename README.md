# skill-contexto

Lean project context in **3 tiers** for Claude Code and opencode. The script scaffolds everything mechanical with zero tokens; the model fills in only what needs judgment.

## Tiers

| Tier | When | Creates |
|---|---|---|
| 1 | one-shot, <20 files | `MAP.md` |
| 2 | 50–200 files or 2+ sessions | + `STATUS.md`, `LEARNINGS.md`, `TODO.md` (3+ steps, no tracker) |
| 3 | monorepo / team | + on-demand `BUGS.md`, `WORKFLOW.md` if adopted |

Detail in `reference/tiers.md`. Bundled `templates/` are PT-BR (project memory stays in the user's language); all instruction layers are English.

## Quick use

```bash
./scripts/init.sh --tier auto   # inside the project
./scripts/init.sh --tier 2 --yes
```

## Install

One-liner:

```bash
git clone https://github.com/meketreve/skill-contexto.git && ./skill-contexto/scripts/install.sh
```

`install.sh` symlinks the skill into every harness dir it knows (symlink = tracks `git pull`). Useful flags: `--only claude,opencode,agents`, `--copy` (frozen copy instead of link), `--force` (replace existing), `--project` (copies into `./.claude` + `./.opencode` for team sharing — commit them), `--uninstall`, `--list`.

| Harness | Skill path | Slash command | Notes |
|---|---|---|---|
| Claude Code | `~/.claude/skills/contexto` | n/a (skill auto-triggers) | project-level: `.claude/skills/contexto` |
| opencode | `~/.config/opencode/skills/contexto` | `~/.config/opencode/commands/contexto.md` → `/contexto` | also auto-loads `~/.claude/skills` and `~/.agents/skills`; restart opencode after install |
| Other Agent Skills harnesses | `~/.agents/skills/contexto` | — | any harness that discovers `SKILL.md` (see `install.sh --list`) |

Symlink or copy? Personal use → symlink (updates are one `git pull` away). Teams / pinned versions → `--copy` or `--project`, so the exact skill version travels with the repo.

No harness at all? The skill is pure bash + markdown. Clone it anywhere and run the scaffold directly — no plugin system required:

```bash
/path/to/skill-contexto/scripts/init.sh --tier auto --dir ~/my-project
```

## Layout

```
SKILL.md              # the skill (thin: picks tier, runs script, fills 20%)
scripts/init.sh       # zero-token scaffold (detection + auto blocks + imports)
scripts/install.sh    # links/copies the skill into your harnesses
templates/            # MAP STATUS TODO LEARNINGS (+ BUGS WORKFLOW for tier 3)
reference/tiers.md    # tiers, formats, imports, budgets (lazy load)
commands/contexto.md  # /contexto command for opencode
```

## Conventions

- Frontmatter `updated/tier` (script-owned) + `<!-- auto:start -->` blocks (script-only).
- One line per fact with tags: `- [2026-09-28] [pytest] fact — consequence`.
- `BUGS.md` is never imported — `grep` the error message.
- Budgets: STATUS/TODO 60 lines, LEARNINGS 100, MAP 60.
