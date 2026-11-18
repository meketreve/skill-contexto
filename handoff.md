# Handoff — estado do repo e o que ficou pendente

Escrito em 2026-11-17, ao fim da sessão que criou a memória de longo prazo (`memory/`),
o briefing de subagentes, os hooks de compaction e o plugin nativo de opencode. Este
arquivo é temporário: apague depois de resolver os itens abaixo.

## Estado

- **Commitado nesta sessão**, em quatro commits: fix de CI (`pipefail`), memória fria,
  hooks de compaction/subagentes e plugin + carrier de opencode. O push foi feito no fim.
- Suíte do CI rodada localmente com `HOME` falso (`/tmp/run_ci.py`, descartável): **12/12
  passos PASS**, incluindo `opencode carrier`, `memory`, `hook.sh` e `install.sh matrix`.
  ShellCheck **não rodou** localmente (não está instalado); o CI roda.
- Verificações de comportamento feitas contra o binário real (opencode v2.3.0), não por
  leitura de código:
  - **opencode V2 ignora `CLAUDE.md`** — marcador invisível lá, visível em `AGENTS.md` e em
    `instructions`. Daí `--opencode` (edição textual de JSONC, preserva comentários e
    entradas existentes, backup com timestamp só quando edita, valida antes de gravar) e o
    check de carrier.
  - **Recall do plugin** no layout real de instalação (cópia em `.opencode/plugins/contexto`
    + skill em `.opencode/skills/contexto`): `scriptsDir()` acha `index.sh`, `blocks=1`, o
    modelo citou a memória. No layout antigo (symlink em `scripts/`) nunca teria funcionado.
  - **Compaction**: o hook dispara e o `system.push` chega ao provider — `http.request` de
    `kind=compaction` continha o sentinela (`sentinel=true len=39985`). O modelo pode
    ignorar a ordem de formato mesmo recebendo o texto; o vetor é garantido, o efeito não.
    Controle A/B sem plugin também preservou artefatos com 2 turnos — não isola nada.
  - **EPIPE**: `hook.sh` agora não imprime ruído em `| head` (stdout igual, exit 0).

## Pendências (nada aqui bloqueia o uso)

1. **Primeiro run de verdade no GitHub Actions.** O passo `ShellCheck` nunca rodou nesta
   máquina, e o `install.sh matrix` só foi validado com `$HOME` falso.
2. **Teste real no DSH, que só o usuário pode fazer.** Projeto com `init.sh --bundle`,
   abrir sessão e conferir que o `AGENTS.md` entra. Base factual: README do
   `dsh-agent-instructions` ("`@path` imports are not interpreted"). Não testado ponta a
   ponta porque consome API.
3. **Bugs conhecidos e NÃO corrigidos** (fora do escopo):
   - `updated:` é recarimbado a cada execução, então **não mede frescor** — um STATUS parado
     há semanas mostra a data de hoje. Exigiria hash do trecho manual ou um `checked:`.
   - `--migrate` num MAP que já tem `## Comandos` deixa **dois** títulos iguais.
   - Workspace Python (uv/pyproject) com muitos arquivos resolve tier 2, não 3 — a regra
     "multi-package `[tool]`" saiu da doc porque o código nunca a implementou.
4. **`core.hooksPath` pode estar setado neste clone** (ligado em sessão anterior para testar
   o `pre-commit`). Se não quiser: `git config --unset core.hooksPath`.
5. **`AGENTS.md` continua no `.gitignore`.** O bundle é derivado e o `--check` o mantém
   honesto; se o time preferir que o contexto viaje no checkout, remover a linha e commitar.

## Onde olhar primeiro

- `plugins/opencode/index.ts` — recall por arquivo, budget e compaction; `scriptsDir(root)`
  com candidatos (repo, projeto, global). Não relê plugin sem reiniciar o servidor; use
  `opencode run --standalone` para testar.
- `scripts/hook.sh` — hooks de Claude (`PreCompact`, `SessionStart: compact`, `PreToolUse`,
  `PostToolUse`, `SubagentStop`); silencioso fora dos casos, sempre exit 0.
- `scripts/init.sh` — `--opencode`/`--bundle`, `fill_opencode`, check seção 7 (carrier).
- `.github/workflows/lint.yml` — a especificação executável. Cuidado com `pipefail`:
  `--check` sai 1 de propósito, por isso `( ... || true ) | grep -c`; nunca voltar a
  `grep -q` nos produtores (SIGPIPE mata o pipeline).
- `reference/hooks.md` — tabela de hooks do opencode V2 e os pitfalls (`system.push` é o
  único vetor obedecido; `console.warn` não chega ao modelo).

## Grão fino que economiza tempo

- Servidor de background cacheia plugin: reiniciar ou usar `opencode run --standalone`.
- API de teste: `opencode serve --hostname 127.0.0.1 --port N` imprime
  `server password <pw>` (pode demorar >7 s); auth Basic `opencode:<pw>`; POST
  `/api/session`, `/api/session/{id}/prompt`, `/api/session/{id}/compact`; GET
  `/api/session/{id}/message`. Matar servidor com `fuser -k PORT/tcp` (nunca `pkill -f`,
  que mata o próprio shell).
- Hooks de tool no opencode recebem path relativo ao projeto; absoluto, `..` e
  `.claude/context/` são ignorados pelo plugin.
- `init.sh --opencode` precisa de `python3`; sem ele, avisa e não toca no arquivo.
