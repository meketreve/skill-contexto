# Hooks (optional)

Two independent layers. Git hooks are recommended; agent hooks are opt-in.

Rule for both: **hooks remind or refresh `auto` blocks — they never
write manual sections** (`STATUS` state, `MAP` flows, `TODO` items,
`LEARNINGS` facts). A hook that auto-writes judgment content defeats
the script-first / model-second split. Hooks always exit 0 (never block).

## 1. Git hooks (recommended)

Repo ships `.githooks/pre-commit` (zero dependencies, mirrors CI):

- `bash -n` on scripts + hook itself
- `shellcheck` when installed (CI enforces when local skips)
- `templates/` vs `templates.en/` same file set
- `commands/context.md` vs `contexto.md` identical past line 8
- frontmatter (`updated:`, `tier:`) in every template
- `git diff --cached --check` (whitespace)
- `+x` on `scripts/*.sh` + hook

Enable once per clone (not committable by design):

```bash
git config core.hooksPath .githooks
```

Bypass is `git commit --no-verify` — reserved for emergencies, not drift.

## 2. Agent hooks (opt-in, per project)

### Claude Code (native)

Project file `.claude/settings.json` (committable, team-shared):

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
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "input=$(cat); f=$(echo \"$input\" | jq -r '.tool_input.file_path // empty' 2>/dev/null); case \"$f\" in .claude/context/*) echo 'Reminder: respect budgets outside auto blocks (STATUS/TODO/MAP 60, LEARNINGS 100) and never edit <!-- auto:start --> blocks by hand.' ;; esac; exit 0",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

Notes:

- `SessionStart` is read-only: missing context → suggest, existing → show `git status`. Never runs `init.sh` by itself (scaffolding creates files — that decision stays with the user/model).
- `PostToolUse` fires only for edits under `.claude/context/`; everything else exits silently. Requires `jq` for stdin parsing — without `jq` the `f` extraction fails empty and the hook stays silent, which is the safe default.
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

2. Reuse the same `SessionStart` / `PostToolUse` JSON from the Claude
   example in `.opencode/hooks.json`.

If the plugin is unavailable, the fallback is manual: run
`scripts/init.sh --tier auto` at session start — no automation needed.

## 3. Anti-patterns (don't)

- Auto-appending to `LEARNINGS.md` / `BUGS.md` from a hook (merges machine noise with judgment notes).
- Rewriting `STATUS.md` state or `MAP.md` flows from `SessionEnd`/`Stop`.
- Blocking hooks (`exit 2`) for context hygiene — reminders only.
- Timeouts above ~10s: hooks run on the critical path of every session/tool call.
- Committing personal paths, notification commands, or secrets into shared hook files.
