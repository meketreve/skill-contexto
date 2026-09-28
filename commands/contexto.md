---
description: Monta contexto enxuto do projeto em 3 tiers (MAP/STATUS/TODO/LEARNINGS) com esqueleto via script sem gastar token
---

# /contexto — $ARGUMENTS

1. Rode o esqueleto sem token (caminho da skill instalada; ajuste se for outro):
```bash
~/.config/opencode/skills/contexto/scripts/init.sh --tier auto $ARGUMENTS
# claude code: ~/.claude/skills/contexto/scripts/init.sh --tier auto $ARGUMENTS
```
Aceita `--tier 1|2|3` para forçar e `--yes` para não perguntar.

2. Com o resultado do script em mãos, complete SÓ o que precisa de juízo (regras em `SKILL.md` da skill `contexto`):
- `MAP.md`: fluxos `X → Y → Z`, o não-óbvio. Comandos o script já extraiu.
- `STATUS.md`: estado atual (2–4 linhas) + próxima fase com ponto de partida.
- `TODO.md`: ativar (`active: true`) só se houver tarefa de 3+ passos sem tracker.
- `LEARNINGS.md`: uma linha por fato `- [AAAA-MM-DD] [tag] fato — consequência`.

3. Nunca edite blocos `<!-- auto:start -->`; nunca crie arquivo que o tier não pede; respeite os tetos (STATUS/TODO 60, LEARNINGS 100).

4. Termine listando o criado e o que ficou em branco.
