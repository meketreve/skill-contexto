# Melhorias sugeridas na skill `contexto`

Notas de uma sessão real (21/11/2026, projeto `bot-levelingidle2d`) onde a skill
foi usada de ponta a ponta: criou-se o contexto, rodou-se `--check` várias
vezes, precisou-se de `--todo` e de `--opencode` no meio da sessão, e o TODO
acabou sendo criado **meses depois** do primeiro bootstrap.

Cada item traz o sintoma observado, o ponto exato no script e uma proposta. Os
itens 1, 2 e 5 são baratos e sem falso positivo; 3, 4 e 6 mexem no `--check` e
pedem teste em alguns projetos antes de virar padrão.

---

## 1. `init.sh` diz "created/verified" e esconde o que criou

**Sintoma (21/11).** `init.sh --todo --opencode` **criou `BUGS.md`** e mudou
`tier: 2` → `tier: 3` em `MAP.md`, `STATUS.md` e `LEARNINGS.md`. A saída foi:

```
created/verified in ./.claude/context:
BUGS.md
LEARNINGS.md
...
```

Nada distingue criado de já-existente, e a mudança de tier só apareceu no diff
que o harness injetou depois.

**Onde.**
- `scripts/init.sh:1078` — `say "created/verified in $CTX:"` seguido de `ls "$CTX"`.
- `scripts/init.sh:198` — `copy_missing()` faz `[ -f "$2" ] || cp "$1" "$2"` e não devolve nada.
- `scripts/init.sh:205` — `stamp_frontmatter()` usa `sed` e não compara o valor anterior.

**Proposta.** `copy_missing` ecoa `created: <basename>`; `stamp_frontmatter`
lê a linha `tier:` antes do `sed` e ecoa `tier: 2 → 3` só quando muda. Manter o
`ls` no final como inventário, mas com o "created" antes dele.

**Aceite.** Rodar num projeto tier 2 existente com `--todo`: a saída contém
`created: BUGS.md` e `tier: 2 → 3 (3 arquivos)`; numa segunda execução, nenhuma
das duas linhas aparece.

---

## 2. Backups `*.bak-*` poluem o manifest do MAP

**Sintoma (21/11).** O `--opencode` gerou `opencode.json.bak-20261121-091831`
na raiz; ele entrou no bloco `primeiro nível` de `MAP.md` (que é gerado por
`ls`/`git ls-files`), poluindo o contexto e me obrigando a mover o arquivo
para `/tmp` à mão para limpar o diff.

**Onde.** `scripts/init.sh:139` (`SKIP_DIRS`) exclui **diretórios** apenas;
`:725` (`git ls-files --cached --others --exclude-standard`) não filtra glob de
arquivo.

**Proposta.** Excluir `*.bak*`, `*.orig` e `*~` do manifest e do bundle.

**Aceite.** Criar `x.json.bak-20260101-000000` na raiz e rodar `init.sh`:
o arquivo não aparece no bloco `primeiro nível`.

---

## 3. `--check` não vê "fila em prosa, sem TODO"

**Sintoma (21/11).** `STATUS.md` tinha **5 parágrafos de pendência**
(`Aguardando o jogo`, `Decisão do dono`, `Plano aberto`, `Bloqueios do jogo`,
`Próxima fase`) e o `TODO.md` **nunca existiu** — porque no tier 2 ele é
opt-in. A fila real (ex.: "modularizar e recarregar sem cair") vivia só na
conversa e teria se perdido. Só nasceu quando o dono perguntou.

Detalhe: `--todo --check` **antes** de criar o TODO acusou
`CLAUDE.md is missing the import @.claude/context/TODO.md` — correto, mas
confuso, porque o problema era "não há TODO", não "falta import".

**Proposta (warn-only, sem mudar exit code).**
- existe seção `Pendências|Bloqueios|Próxima fase|Next phase` no STATUS com
  ≥3 itens **e** não há `TODO.md`/`active:false` → `warn: fila em prosa, sem TODO`;
- `TODO active:true` com zero `- [ ]` → `warn: fila vazia, active:false`;
- `TODO active:false` com `- [ ]` → **erro** (item que ninguém vai ler).

**Aceite.** Projeto de teste com STATUS de 3 pendências e sem TODO: `--check`
sai 0 com o warning; com TODO `active:false` e um item, sai 1 com o erro.

---

## 4. `--check` não valida caminhos citados na prosa

**Sintoma (21/11).** `status.md` (raiz, 78 KB, 1.350 linhas) está **parado
desde 14/11** e ainda é chamado de "tracker longo" em `MAP.md:13`,
`MAP.md:55` e `bot/BOT.md:3/14/100`. O check valida ponteiro de `memory/` mas
não caminho citado no MAP/STATUS — então uma fonte morta continua sendo
apontada como viva.

**Proposta.** Extrair `[\w./-]+\.(md|py|sh|json)` das seções manuais:
- não existe → **erro** (link podre);
- existe mas `mtime` > 30 dias **e** a linha contém `fonte|tracker|atual|doc`
  → **warn**.
- whitelist: `http`, `/tmp/`, `~`, `/dev/`, `memory/` (já cobertos por outro check).

**Risco.** Caminho usado como exemplo. Mitigar com a whitelist e warn-only na
primeira versão.

---

## 5. Budget: sugerir o corte, não só acusar o estouro

**Sintoma (21/11).** MAP foi a **60/60** duas vezes e o STATUS a 59/60; a
decisão de o que comprimir foi feita por instinto, editando parágrafo a
parágrafo. O check diz `MAP: 60/60`, não "corte isto".

**Proposta.** Ao estourar, listar as 3 linhas mais antigas por data escrita no
texto (`AAAA-MM-DD` / `DD/MM`) como candidatas, e para `LEARNINGS` sugerir a
tag com mais entradas para promover a `memory/` (regra que já existe no
SKILL.md §5, mas não é aplicada).

**Aceite.** Arquivo de teste com 62 linhas e 3 datas: a saída cita as 3 linhas
mais antigas e o comando de contagem.

---

## 6. Falta `--dry-run`

**Sintoma (21/11).** Para garantir que `init.sh --todo` não mexia no
`opencode.json`, copiei o arquivo para `/tmp` e comparei depois. Metade do
`--check` já faz esse trabalho.

**Proposta.** `--dry-run` que imprime `would create / would update / untouched`
e não escreve. Reaproveitar a lógica do `--check` + a decisão de `copy_missing`.

**Aceite.** `init.sh --dry-run --todo` num projeto sem TODO imprime
`would create TODO.md` e o `ls` final mostra que o arquivo não existe.

---

## 7. Política: quem é o dono de **ativar** o TODO

**Sintoma (21/11).** O SKILL.md §3 diz "`TODO.md`: only when active" — mas
ninguém é dono de decidir ativá-lo. O agente seguiu a política e o TODO só
apareceu quando o usuário perguntou "por que não tem TODO?".

**Proposta.** Uma linha no `SKILL.md` §3 (e no `handoff.md`, se fizer sentido):

> Appeared work of 3+ steps outside the request, or an idea that needs a queue?
> Create/update `TODO.md` and say so in one line. Do not wait to be asked.

**Aceite.** Revisão de texto — nenhum código.

---

## Ordem de execução sugerida

1. **Item 2** (1 regex, zero risco).
2. **Item 7** (texto, zero risco).
3. **Item 1** (10 linhas, testável com `--todo` em projeto tier 2).
4. **Item 6** (`--dry-run`, dá rede de segurança para os seguintes).
5. **Itens 3 e 5** (`--check`, warn-only; rodar em 3-4 projetos antes).
6. **Item 4** (o mais sujeito a falso positivo; deixar por último).

## O que NÃO mexer (funciona bem)

- `--check` read-only com exit 1 e "nothing was written".
- Split script/modelo: o script nunca escreve seção manual.
- `[✗]` vitalício — é o que impede a próxima sessão de repetir o erro.
- `memory/` frio com ponteiros (teto de 15 linhas) e `index.sh` por termo.
- Carriers `--bundle` (AGENTS.md) e `--opencode` (instructions), com backup.

## Reproduzir os sintomas (projeto `bot-levelingidle2d`)

```bash
cd /mnt/HDD1T/repos/bot-levelingidle2d
# 1: criar TODO e ver a saída amalgamada + mudança de tier
/home/meketreve/.config/opencode/skills/contexto/scripts/init.sh --todo
# 2: o backup que entrou no MAP (hoje já foi movido para /tmp)
ls opencode.json*  # antes: opencode.json.bak-20261121-091831
# 4: fonte citada e parada
stat -c '%y %n' status.md
grep -rn "status.md" .claude/context/MAP.md bot/BOT.md
```
