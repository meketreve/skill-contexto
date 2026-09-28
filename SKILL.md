---
name: contexto
description: Monta contexto enxuto do projeto em 3 tiers (MAP/STATUS/TODO/LEARNINGS/BUGS/WORKFLOW) com esqueleto via script sem gastar token. Use quando o usuário pedir para preparar/iniciar o contexto, montar MAP, STATUS ou organizar memória do projeto.
---

# Contexto em 3 tiers

Fluxo: **script primeiro (sem token), modelo depois (só o que precisa de juízo).**

## 1. Decidir o tier

Rodar o script com detecção automática (ele conta arquivos, detecta monorepo e pergunta se o trabalho dura mais de uma sessão):

```bash
<skill-dir>/scripts/init.sh --tier auto
```

Regra (detalhe em `reference/tiers.md`):

- **Tier 1 — leve/one-shot, <20 arquivos:** só `MAP.md` mínimo.
- **Tier 2 — médio/multi-sessão, 50–200 arquivos:** soma `STATUS.md` + `LEARNINGS.md` (+ `TODO.md` se a tarefa tem 3+ passos sem issue tracker).
- **Tier 3 — grande/monorepo/equipe:** soma `TODO` por pacote, `WORKFLOW.md` se houver processo adotado, `BUGS.md` desmembrado só quando LEARNINGS passar de ~10 entradas de bug.

Nunca criar arquivo que o tier não pede. Decidir **não** criar é parte do trabalho.

## 2. O que o script já fez (não repetir)

O `init.sh` só cria o que falta, nunca sobrescreve, e preenche os blocos `<!-- auto:start -->` (data, `git log`, comandos do manifesto, `ls` nível 1) + garante os imports no `CLAUDE.md`. Não refazer isso à mão.

## 3. O que o modelo completa (só os ~20% manuais)

- `MAP.md`: fluxos principais (`X → Y → Z`) e o que não é óbvio pelo nome. Comandos o script já extraiu.
- `STATUS.md`: "estado atual" em 2–4 linhas e "próxima fase" com arquivo/ponto de partida. O bloco auto já tem `git log`/`git status` brutos.
- `TODO.md`: só se ativo (frontmatter `active: true`).
- `LEARNINGS.md`: uma linha por fato no formato `- [AAAA-MM-DD] [tag] fato — consequência`. Só registrar correção real, pegadinha de versão/API/CI ou decisão com porquê.
- `BUGS.md` (tier 3): um bloco por bug com a mensagem de erro literal (para o `grep` achar).
- `WORKFLOW.md` (tier 3): só se o usuário adotou um processo explícito.

## 4. Política de imports (não importar tudo)

- Sempre: `@.claude/context/STATUS.md` (tier 2+) e `@.claude/context/MAP.md`.
- `LEARNINGS.md`: importado no tier 2+; no tier 1, consultar sob demanda via grep.
- `TODO.md`: importado só enquanto `active: true`.
- `BUGS.md`: nunca importado — `grep` pela mensagem de erro quando precisar.
- `WORKFLOW.md`: importado só se existir.

No opencode, o `CLAUDE.md` da raiz é lido como fallback global; em alternativa, declarar os mesmos arquivos no campo `instructions` do `opencode.json`.

## 5. Tetos (orcamento de contexto)

- `STATUS.md` / `TODO.md`: 60 linhas max. `LEARNINGS.md`: 100. Passou disso, resumir em 1 linha ou apagar — o `git log` é a fonte da verdade.
- Terminar com lista curta do que foi criado e do que ficou em branco para o usuário completar.
