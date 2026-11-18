# Hooks (optional)

Two independent layers. Git hooks are recommended; agent hooks are opt-in.

Scope: the rule below and "always exit 0, never block" apply to the **context (agent) hooks**. `.githooks/pre-commit` is a lint gate: it **blocks on purpose** (`exit 1`) when a check fails.

Rule for both layers: **hooks remind or refresh `auto` blocks — they never
write manual sections** (`STATUS` state, `MAP` flows, `TODO` items,
`LEARNINGS` facts). A hook that auto-writes judgment content defeats
the script-first / model-second split. Context hooks always exit 0; they remind, they never block.

## 1. Git hooks (recommended)

Repo ships `.githooks/pre-commit` (zero dependencies, mirrors CI):

- `bash -n` on the 4 scripts (`init.sh`, `install.sh`, `index.sh`, `hook.sh`) — `.githooks/pre-commit` itself is only checked in CI
- `shellcheck` when installed, also only on the 4 scripts (CI runs it on all 5 and covers what the local hook skipped)
- `templates/` vs `templates.en/` same file set
- `commands/context.md` vs `contexto.md` identical past line 8
- frontmatter (`updated:`, `tier:`) in every template
- `git diff --cached --check` (whitespace)
- `+x` on the 4 scripts + hook, in the working tree and in the git index

Enable once per clone (not committable by design):

```bash
git config core.hooksPath .githooks
```

Bypass is `git commit --no-verify` — reserved for emergencies, not drift.

## 2. Agent hooks (opt-in, per project)

### Claude Code (native)

Personal example in `.claude/settings.local.json` (gitignored), for a skill installed at `$HOME/.claude/skills/contexto`:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "if [ ! -f .claude/context/MAP.md ]; then echo 'No project context — suggest running /contexto to scaffold (tier auto).'; else git status --short 2>/dev/null | head -20; fi",
            "timeout": 10
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "h=\"$HOME/.claude/skills/contexto/scripts/hook.sh\"; [ -x \"$h\" ] && \"$h\"; exit 0",
            "timeout": 5
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "h=\"$HOME/.claude/skills/contexto/scripts/hook.sh\"; [ -x \"$h\" ] && \"$h\"; exit 0",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

For a team, install with `install.sh --project` and keep only the `"$CLAUDE_PROJECT_DIR"` variant in the committed `.claude/settings.json` (personal paths stay in the `.local.json`):

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "h=\"$CLAUDE_PROJECT_DIR\"/.claude/skills/contexto/scripts/hook.sh; [ -x \"$h\" ] && \"$h\"; exit 0",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

(`PostToolUse` uses the same command.) The `[ -x ]` guard keeps the hook silent where the skill isn't installed.

`SubagentStop` reuses the same command, no matcher:

```json
{
  "hooks": {
    "SubagentStop": [
      { "hooks": [ { "type": "command", "command": "h=\"$HOME/.claude/skills/contexto/scripts/hook.sh\"; [ -x \"$h\" ] && \"$h\"; exit 0", "timeout": 5 } ] }
    ]
  }
}
```

Notes:

- `SessionStart` is read-only: missing context → suggest, existing → show `git status`. Never runs `init.sh` by itself (scaffolding creates files — that decision stays with the user/model).
- `PreToolUse` and `PostToolUse` both call `scripts/hook.sh`, which decides by event and path and stays silent otherwise:
  - **Recall by file** (PreToolUse, file outside `.claude/context/`): runs `index.sh` with the file's project-relative path (then its basename, unless generic like `index.ts`/`main.py`) and, when entries in `LEARNINGS*`/`BUGS*`/`memory/*` cite it, shows up to 3 of them before the edit. Once per file per agent — the marker carries `agent_id`, so a subagent gets the recall its parent already consumed.
  - **Budget** (PostToolUse, `STATUS`/`TODO`/`MAP`/`LEARNINGS.md`): measures the manual part (outside auto blocks) and speaks only when it is over the budget; on `LEARNINGS.md` it asks for a tag promotion to `memory/` before any deletion. `init.sh --check` performs the same check portably, without depending on Claude Code.
- `SubagentStop` (`"matcher"` optional, no path) makes the subagent write its findings before it dies: its transcript is not the parent's, so nothing else carries them. It fires once per agent, only if that agent touched a file, and uses `additionalContext` — the conversation continues, the subagent is not stop-blocked.
- Output is `hookSpecificOutput.additionalContext` JSON: for tool events, plain `echo` goes only to the debug log and never reaches the model (the earlier one-liner here had that bug, and also matched a relative path against the absolute `file_path` — it never fired). `SessionStart` is the exception: its plain stdout does reach the model.
- `jq` is optional: without it, `hook.sh` parses the flat fields it needs with `sed`.
- Personal/machine-only hooks go in `.claude/settings.local.json` (gitignored), never in the committable file.
- Subagent recall and the `SubagentStop` reminder only work because the marker is keyed by `session_id` + `agent_id`. Keying it by session alone makes a subagent inherit the parent's markers and silently lose the recall — the exact case it needs it.

#### Compaction (`PreCompact` + `SessionStart: compact`)

A summary keeps the narrative and drops the artifacts — literal errors, `file:line`, the command that worked, why an approach was rejected. These two hooks cost nothing and keep the split intact: neither writes manual content, both only speak.

`PreCompact` — its **plain stdout is used verbatim as instructions for the compaction summary** (not JSON; cap 10,000 characters per hook), so the hook forces the summarizer to keep what a paraphrase eats. It must be fast and static.

`SessionStart` with matcher `compact` fires right after compaction; its plain stdout does reach the model. `hook.sh` uses it to ask for what is still unwritten and to hand back the `index.sh` table of contents, so the agent recalls instead of re-guessing.

```json
{
  "hooks": {
    "PreCompact": [
      { "hooks": [ { "type": "command", "command": "h=\"$HOME/.claude/skills/contexto/scripts/hook.sh\"; [ -x \"$h\" ] && \"$h\"; exit 0", "timeout": 5 } ] }
    ],
    "SessionStart": [
      { "matcher": "compact", "hooks": [ { "type": "command", "command": "h=\"$HOME/.claude/skills/contexto/scripts/hook.sh\"; [ -x \"$h\" ] && \"$h\"; exit 0", "timeout": 10 } ] }
    ]
  }
}
```

No matcher on `PreCompact` on purpose: it must fire for `auto` too, which is the case where the agent never gets a turn to save anything.

- **Not** blocking (`exit 2`) by default. Blocking a `manual` `/compact` shows stderr and cancels it; blocking an `auto` compaction that is recovering from a context-limit error makes the current request fail. Good for a "write your learnings first" gate, bad as a default.
- The transcript path arrives in `transcript_path` (JSONL). Reading it inside the hook is the ambitious version: it can mine literal errors and edited paths, but it is noise-prone and slower. The static instruction is the cheap, reliable tier; extraction is only worth it after the static one proves insufficient.

## 3. Anti-patterns (don't)

- Auto-appending to `LEARNINGS.md` / `BUGS.md` from a hook (merges machine noise with judgment notes).
- Rewriting `STATUS.md` state or `MAP.md` flows from `SessionEnd`/`Stop`.
- Blocking hooks (`exit 2`) for context hygiene — context hooks only remind (`.githooks/pre-commit` is a lint gate and blocks on purpose).
- Timeouts above ~10s: hooks run on the critical path of every session/tool call.
- Committing personal paths, notification commands, or secrets into shared hook files.
- Trusting the compaction summary as the record: it keeps the story and drops the literal errors, paths and rejected options the next session actually needs. Wire `PreCompact` if sessions are long.
- Making `PreCompact` do work on the critical path: it runs on every compaction, so keep it static and fast (no transcript mining by default).
