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

Notes:

- `SessionStart` is read-only: missing context → suggest, existing → show `git status`. Never runs `init.sh` by itself (scaffolding creates files — that decision stays with the user/model).
- `PreToolUse` and `PostToolUse` both call `scripts/hook.sh`, which decides by event and path and stays silent otherwise:
  - **Recall by file** (PreToolUse, file outside `.claude/context/`): runs `index.sh` with the file's project-relative path (then its basename, unless generic like `index.ts`/`main.py`) and, when entries in `LEARNINGS*`/`BUGS*` cite it, shows up to 3 of them before the edit. Once per file per session (a marker in the session scratchpad), so repeated edits don't repeat it.
  - **Budget** (PostToolUse, `STATUS`/`TODO`/`MAP`/`LEARNINGS.md`): measures the manual part (outside auto blocks) and speaks only when it is over the budget. `init.sh --check` performs the same check portably, without depending on Claude Code.
- Output is `hookSpecificOutput.additionalContext` JSON: for tool events, plain `echo` goes only to the debug log and never reaches the model (the earlier one-liner here had that bug, and also matched a relative path against the absolute `file_path` — it never fired). `SessionStart` is the exception: its plain stdout does reach the model.
- `jq` is optional: without it, `hook.sh` parses the flat fields it needs with `sed`.
- Personal/machine-only hooks go in `.claude/settings.local.json` (gitignored), never in the committable file.

### opencode (via Claude-compatible plugin)

Stock opencode has no native declarative hooks (as of 2026-09); the
community path is a Claude-format bridge plugin (e.g.
`opencode-claude-hooks` or equivalent — verify it is maintained before
adopting). It reads `.opencode/hooks.json` (project) or
`~/.config/opencode/hooks.json` (personal) in the same shape as above:

1. Register the plugin in `opencode.json`:

```json
{ "$schema": "https://opencode.ai/config.json", "plugin": ["opencode-claude-hooks"] }
```

2. Reuse the same `SessionStart` / `PreToolUse` / `PostToolUse` JSON from the Claude
   example in `.opencode/hooks.json`. Check that the bridge forwards
   `additionalContext` to the model; if it doesn't, the two tool hooks are silent no-ops.

If the plugin is unavailable, the fallback is manual: run
`scripts/init.sh --tier auto` at session start — no automation needed.

## 3. Anti-patterns (don't)

- Auto-appending to `LEARNINGS.md` / `BUGS.md` from a hook (merges machine noise with judgment notes).
- Rewriting `STATUS.md` state or `MAP.md` flows from `SessionEnd`/`Stop`.
- Blocking hooks (`exit 2`) for context hygiene — context hooks only remind (`.githooks/pre-commit` is a lint gate and blocks on purpose).
- Timeouts above ~10s: hooks run on the critical path of every session/tool call.
- Committing personal paths, notification commands, or secrets into shared hook files.
