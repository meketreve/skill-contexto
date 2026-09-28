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

Claude Code (skill):
```bash
ln -s "$PWD" ~/.claude/skills/contexto
```

opencode (skill + `/contexto` command):
```bash
mkdir -p ~/.config/opencode/skills ~/.config/opencode/commands
ln -s "$PWD" ~/.config/opencode/skills/contexto
ln -s "$PWD/commands/contexto.md" ~/.config/opencode/commands/contexto.md
# quit and restart opencode
```

## Layout

```
SKILL.md              # the skill (thin: picks tier, runs script, fills 20%)
scripts/init.sh       # zero-token scaffold (detection + auto blocks + imports)
templates/            # MAP STATUS TODO LEARNINGS (+ BUGS WORKFLOW for tier 3)
reference/tiers.md    # tiers, formats, imports, budgets (lazy load)
commands/contexto.md  # /contexto command for opencode
```

## Conventions

- Frontmatter `updated/tier` (script-owned) + `<!-- auto:start -->` blocks (script-only).
- One line per fact with tags: `- [2026-09-28] [pytest] fact — consequence`.
- `BUGS.md` is never imported — `grep` the error message.
- Budgets: STATUS/TODO 60 lines, LEARNINGS 100, MAP 60.
