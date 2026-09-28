# Tiers, formatos e política de imports

## Tiers

| Tier | Quando | Cria | Importa sempre |
|---|---|---|---|
| 1 — leve | one-shot, <20 arquivos, sessão única | `MAP.md` mínimo | `MAP.md` |
| 2 — médio | 50–200 arquivos **ou** 2+ sessões | + `STATUS.md`, `LEARNINGS.md`, `TODO.md` se 3+ passos sem tracker | `STATUS + MAP + LEARNINGS` |
| 3 — grande | monorepo (`packages/*/`, `apps/*/`, workspaces), equipe | + `TODO` por pacote, `WORKFLOW.md` se adotado, `BUGS.md` se LEARNINGS >10 bugs | `STATUS + MAP`, resto lazy |

Detecção automática (`scripts/init.sh --tier auto`):
1. Conta arquivos: `git ls-files | wc -l` (fallback: `find . -type f -not -path './.git/*' | wc -l`).
2. Detecta monorepo: dirs `packages/*/`, `apps/*/`, ou `workspaces` em `package.json`, `[tool]` multi-pacote, `Cargo.toml` com `[workspace]`.
3. `<20` arquivos e sem monorepo → sugere tier 1; `20–200` ou multi-sessão → tier 2; monorepo ou `>200` → tier 3. Com `--tier auto` o script pergunta "vai durar mais de uma sessão? (s/n)" para desempatar 1 vs 2, salvo `CONTEXTO_ASSUME_MULTISESSAO=1` / `=0`.

## Formato dos arquivos

Todos têm frontmatter YAML (o script lê/escreve sem token) + corpo curto em markdown:

```markdown
---
updated: 2026-09-28
tier: 2
---
```

- `TODO.md` soma `active: true|false` — import só se ativo.
- Blocos `<!-- auto:start --> … <!-- auto:end -->` pertencem ao script (data, `git log`, comandos, `ls`). O modelo nunca edita dentro deles à mão; o script nunca toca fora deles.
- Uma linha por fato, com tags grepáveis: `- [2026-09-28] [pytest] fato — consequência`.
- `BUGS.md`: cada bloco abre com `## AAAA-MM-DD — título` e contém a mensagem de erro literal.

## Imports (opencode e claude)

- Claude Code: `@.claude/context/STATUS.md` etc. no `CLAUDE.md` da raiz.
- opencode: o `CLAUDE.md` da raiz é lido como fallback; alternativa canônica é o campo `instructions` do `opencode.json`:
  ```json
  { "$schema": "https://opencode.ai/config.json",
    "instructions": [".claude/context/STATUS.md", ".claude/context/MAP.md"] }
  ```
- `BUGS.md` nunca vai para imports — receita: `grep -i "<trecho do erro>" .claude/context/BUGS.md`.

## Tetos

- `STATUS.md` / `TODO.md`: 60 linhas. `LEARNINGS.md`: 100. `MAP.md`: 60.
- Passou do teto: resumir "Concluído" em 1 linha ou apagar; `git log` guarda o resto.
