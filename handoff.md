# Handoff — estado do repo e o que ficou pendente

Escrito em 2026-10-13, ao fim da sessão que implementou as Fases 0–3 (bugs do `init.sh`,
bundle `AGENTS.md`, `--check`, drifts de doc, `install.sh --project`, CI). Este arquivo é
temporário: apague depois de resolver os itens abaixo.

## Estado

- Tudo o que a sessão se propôs a fazer está **implementado e verificado**; o commit foi
  feito nesta mesma sessão (ver `git log -1`).
- Suíte do CI rodada localmente: **todos os passos PASS**, incluindo ShellCheck. Os passos
  `Install shellcheck` e `install.sh matrix` aparecem como SKIP no runner local por desenho
  (o segundo mexe no `$HOME` real).
- Verificador próprio da sessão: **40/40 ok** (cada bug da auditoria com repro + os extras).
  O script ficou em `/tmp/final-verify.sh` e o runner do CI em `/tmp/run-lint2.py` — ambos
  descartáveis; o CI de verdade é `.github/workflows/lint.yml`.

## Pendências (nada aqui bloqueia o uso)

1. **`core.hooksPath` ficou setado neste clone.** Foi ligado para testar o `pre-commit`.
   Se não quiser: `git config --unset core.hooksPath`.
2. **Teste real no DSH, que só o usuário pode fazer.** Num projeto com `init.sh --bundle`,
   abrir uma sessão ali (ou `dsh headless "…"`) e conferir que o `AGENTS.md` entra no
   contexto. A base factual é o README do `dsh-agent-instructions`: *"`@path` imports are
   not interpreted"*. Não foi testado de ponta a ponta porque consome API.
3. **opencode: nada foi verificado contra o binário.** Os detalhes de `instructions` no
   `opencode.json`, `.opencode/hooks.json` e o plugin `opencode-claude-hooks` vieram da doc
   antiga e seguem **não confirmados** (só o binário v2.0.27 está instalado; não há config).
4. **Passo `install.sh matrix` do CI nunca rodou de verdade.** Foi validado por leitura do
   YAML + execução do corpo com `$HOME` falso; o `--uninstall --project` foi testado isolado
   em `/tmp`. Vale olhar o primeiro run no GitHub Actions.
5. **SIGPIPE: `index.sh` e `hook.sh` não receberam `trap '' PIPE`.** Medi os dois com pipe
   fechado e ambos saíram 0, então não mexi — mas o `init.sh` e o `install.sh` só ficaram
   seguros porque o trap foi adicionado. Se algum dia um deles for usado em pipeline com
   `pipefail`, revisar.
6. **Bugs conhecidos e NÃO corrigidos** (fora do escopo desta sessão):
   - `updated:` é recarimbado a cada execução, então ele **não mede frescor** — um STATUS
     parado há semanas mostra a data de hoje. Corrigir exigiria carimbar só quando o trecho
     manual mudar (hash) ou separar um `checked:`.
   - `--migrate` num MAP que já tem `## Comandos` deixa **dois** títulos iguais (o do usuário
     e o do template).
   - A regra "multi-package `[tool]`" saiu da doc porque o código nunca a implementou:
     workspace Python (uv/pyproject) com muitos arquivos resolve tier 2, não 3.
7. **Decisões de produto em aberto** (tomadas nesta sessão para destravar, revise se
   discordar): tier 3 embarca `BUGS.md` **sempre**; **não existe** TODO por pacote (a
   promessa saiu do `SKILL.md` e do `reference/tiers.md`); o instruction layer
   (`SKILL.md`, `README.md`, `commands/*`, `reference/*`) é **inglês**, com PT-BR só nos
   `templates/` — foi o commit `2d66b52` que decidiu isso, e um subagente desta sessão
   chegou a traduzir tudo para PT-BR por engano (corrigido).
8. **`AGENTS.md` continua no `.gitignore`.** O bundle é derivado e o `--check` o mantém
   honesto; se o time preferir que o contexto viaje no checkout, é remover a linha do
   `.gitignore` e commitar o arquivo.

## Onde olhar primeiro

- `scripts/init.sh` — mudou muito (+355 linhas): `markers_balanced`, `say`, `wanted_sources`,
  `fill_bundle`, `check_mode`, `resolve_tier`.
- `.github/workflows/lint.yml` — passo novo `init.sh guards`, que é a especificação
  executável de tudo o que foi corrigido.
- `SKILL.md` §2/§4 e `reference/tiers.md` — comportamento novo (bundle, `--check`, carriers).
