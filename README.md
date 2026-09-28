# skill-contexto

Skill de contexto enxuto em **3 tiers** para Claude Code e opencode. O script gera o esqueleto sem gastar token; o modelo completa só o que precisa de juízo.

## Tiers

| Tier | Quando | Cria |
|---|---|---|
| 1 | one-shot, <20 arquivos | `MAP.md` |
| 2 | 50–200 arquivos ou 2+ sessões | + `STATUS.md`, `LEARNINGS.md`, `TODO.md` (se 3+ passos sem tracker) |
| 3 | monorepo / equipe | + `BUGS.md` sob demanda, `WORKFLOW.md` se adotado |

Detalhe em `reference/tiers.md`.

## Uso rápido

```bash
./scripts/init.sh --tier auto   # dentro do projeto
./scripts/init.sh --tier 2 --yes
```

## Instalar

Claude Code (skill):
```bash
ln -s "$PWD" ~/.claude/skills/contexto
```

opencode (skill + comando `/contexto`):
```bash
mkdir -p ~/.config/opencode/skills ~/.config/opencode/commands
ln -s "$PWD" ~/.config/opencode/skills/contexto
ln -s "$PWD/commands/contexto.md" ~/.config/opencode/commands/contexto.md
# sair e reiniciar o opencode
```

## Layout

```
SKILL.md              # a skill (fina: decide tier, chama script, completa 20%)
scripts/init.sh       # esqueleto sem token (detecção + blocos auto + imports)
templates/            # MAP STATUS TODO LEARNINGS (+ BUGS WORKFLOW p/ tier 3)
reference/tiers.md    # tiers, formatos, imports, tetos (carga lazy)
commands/contexto.md  # comando /contexto p/ opencode
```

## Convenções

- Frontmatter `updated/tier` (script) + blocos `<!-- auto:start -->` (só o script toca).
- Uma linha por fato com tags: `- [2026-09-28] [pytest] fato — consequência`.
- `BUGS.md` nunca é importado — `grep` pela mensagem de erro.
- Tetos: STATUS/TODO 60 linhas, LEARNINGS 100, MAP 60.
