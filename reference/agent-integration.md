# Using the skill from a coordinator agent

A coordinator owns the project context; subagents borrow it. The coordinator is the only
agent that writes `STATUS.md`, `TODO.md` and `MAP.md`, and the only one that decides what
becomes a learning. A subagent starts empty, so any knowledge it produces dies with it
unless the coordinator promotes it.

## Session start

1. If `.claude/context/` exists, do **not** run `init.sh` again: it re-stamps `updated:` and
   produces a diff. Read the files that the carrier already imported.
2. If the context is missing and the task is multi-step, run the scaffold once
   (`init.sh --tier auto`, or `/contexto`) and fill only the judgment sections.
3. Load the skill once (`skill` tool, id `contexto`) or use the opencode tools
   `contexto_recall` / `contexto_brief` / `contexto_status` / `contexto_check` / `contexto_checked`.
5. **Read `checked:` timestamps** with `contexto_checked` to gauge freshness of each context file.
   Files showing `never checked` or stale dates (>7 days) need `contexto_check` before trusting.
4. Treat `MAP.md` and `STATUS.md` as claims from another session. When they contradict the
   repo, run `contexto_check` (or `init.sh --check`) and verify the cited path before acting.

## Before delegating

Search the project memory with the task's nouns, not the whole sentence. Paste the hits into
the brief. This is the one step the automatic recall cannot do: the plugin only knows files
that a tool already touched.

- opencode: `contexto_brief({ terms: ["marketplace", "reload"] })`
- other harnesses: `index.sh --dir "$PROJECT" -n 10 marketplace reload`
- what was already rejected: add `-x` (or `rejected: true`)

## Brief template (PT-BR, trim; do not decorate)

```text
Contexto já registrado (não re-explore; pode estar desatualizado — confira no arquivo):
<saída do contexto_brief/index.sh, ou "nada registrado">

Tarefa: <um parágrafo, com o ponto de entrada arquivo:linha>

Restrições:
- não edite .claude/context/STATUS.md, TODO.md nem MAP.md — o coordenador é dono deles
- LEARNINGS.md é o arquivo quente; memory/<tag>.md é o frio. Antes de grepar no escuro,
  use o recall (contexto_recall/index.sh); erro literal continua sendo grep em BUGS.md
- no fim relate o que mudou (arquivo:linha), o que verificou (comando + resultado) e achados
  como: - [YYYY-MM-DD] [tag] [✓|✗] fato — consequência
- achado que custou mais de uma tentativa: grave você mesmo em
  .claude/context/memory/<tag>.md
```

## After it returns

Read the final message, not the transcript. Confirm before promoting:

- short/broad fact -> one line in `LEARNINGS.md`;
- long topic or a tag past ~6 lines -> `memory/<tag>.md` plus one pointer in
  `LEARNINGS.md`;
- literal error / broken build / reported bug -> a block in `BUGS.md`;
- a rejected approach keeps `[✗]` forever: it is what stops the next session from trying it
  again.

A subagent's guess is not a learning until the coordinator confirms it.

## Fan-out without collisions

Parallel subagents appending to `LEARNINGS.md` interleave lines. In parallel, give each
subagent its own `memory/<tag>.md` and let the coordinator merge the pointers, or ask them
to report only and write nothing. Only the coordinator closes the session: a subagent never
rewrites `STATUS.md`, activates `TODO.md` or trims a budget.

## Close

Facts are written when they appear; the full handoff is on request, before `/clear`, or at
the end of a multi-step task:

1. `STATUS.md`: current state, next phase with entry point and `-> verify:`.
2. `TODO.md`: drop finished, keep half-done, set `active: false` when the queue empties.
3. `LEARNINGS.md`: this session's corrections/gotchas/decisions with verdicts; promote a
   whole tag to `memory/` instead of deleting.
4. `BUGS.md`: only the fixes that meet the rule, with the literal error.
5. `MAP.md`: paths that cost 2-3 searches, commands discovered.
6. Run `contexto_check` / `init.sh --check --quiet`; fix what you can touch.
7. **`contexto_check` updates `checked:` timestamps** — the coordinator should verify the
   output shows `check: ok` so the `checked:` field in each context file reflects the
   current verification date.

## Anti-patterns

- Delegating without recall and without the forbidden-file list.
- Letting a subagent edit `STATUS.md`, `TODO.md` or `MAP.md`.
- Running `init.sh` on every session "to be safe" (re-stamps `updated:`, creates diff).
- Trusting `STATUS.md`/`MAP.md` over the code.
- Reading `memory/*.md` whole instead of searching it.
- Deleting a `[✗]` line, or trimming a `LEARNINGS` tag before promoting it.
