# Hooks reference (detail from SKILL.md §6)

This file contains the full hook documentation moved from SKILL.md to keep the skill file focused on the core contract.

---

## The rule for every layer

A hook **REMINDS** or refreshes `auto` blocks — it **never writes a manual section** (`STATUS` state, `MAP` flows, `TODO` items, `LEARNINGS` facts). A hook that writes judgment content defeats the script-first/model-second split.

- Context (agent) hooks always exit 0; they remind, they never block.
- `.githooks/pre-commit` is a lint gate that **blocks on purpose** when a check fails.

---

## Git hook (this repo)

`.githooks/pre-commit` mirrors CI; enable once per clone with `git config core.hooksPath .githooks` — it is not committable by design.

---

## Agent hook (per project)

`SessionStart` suggests `/contexto` when `MAP.md` is missing — it never runs `init.sh` by itself, because creating files is the user's call.

`PreToolUse` shows the recorded learnings/bugs that cite a file before its first edit in the session, and `PostToolUse` warns when a context file goes over budget — both through `scripts/hook.sh`, silent otherwise. `--check` covers the budget without depending on Claude Code.

---

## opencode plugin (this repo's plugin, installed with the skill)

`plugins/opencode` registers `context`, `compaction` and tool hooks natively — the same recall, budget warning and compaction instruction as `hook.sh`, in TypeScript.

It also exposes the native tools `contexto_recall`, `contexto_brief`, `contexto_status`, `contexto_check`, `contexto_checked`, `contexto_promote` (no write tool: judgment content stays with the model). It finds `index.sh` through the skill dir and stays silent without `.claude/context/`. It runs the scripts through `scripts/win/ctx.mjs`, so the same plugin works on Windows (WSL) and POSIX.

Pitfalls:
- `event.system.push()` is the only vector the model obeys (`instructions.entry` reads as untrusted)
- `console.warn` never reaches the model
- A plugin edit needs a restart or `--standalone`

Detail in the plugin's source at `plugins/opencode/index.ts`.

---

## Compaction (`PreCompact` + `SessionStart` with matcher `compact`)

The first hook (`PreCompact`) turns a static list into instructions for the compaction summary — errors, paths, commands and decisions verbatim.

The second hook (`SessionStart` with `source: compact`), right after compaction, asks for whatever is still unwritten and hands back the `index.sh` table of contents.

This is what survives a session that compacts before it closes, which is exactly the case the handoff never reaches.

**Wire it on long sessions; keep it static and fast.** The hook should not do heavy computation on the critical path.

---

## Hook scripts

- `scripts/hook.sh` — Claude Code agent hooks (PreToolUse, PostToolUse, PreCompact, SessionStart, SubagentStop). Input/output JSON on stdin/stdout.
- `scripts/win/ctx.mjs` — Cross-platform launcher for all scripts (Windows via WSL, POSIX direct).
- `plugins/opencode/index.ts` — opencode V2 plugin with native tools and hooks.

---

## Hook input/output contracts

### PreToolUse

**Input:** `{session_id, cwd, agent_id, tool_input: {file_path}}`

**Output:** `{"hookSpecificOutput": {"additionalContext": "..."}}` — recall block for the file, or empty.

### PostToolUse

**Input:** `{session_id, cwd, agent_id, tool_input: {file_path}, status, result}`

**Output:** (none) — queues budget warning for next `context` hook.

### PreCompact

**Input:** `{session_id, cwd, hook_event_name: "PreCompact", trigger}`

**Output:** `{"hookSpecificOutput": {"additionalContext": "VERBATIM list..."}}` — static instruction block.

### SessionStart (compact)

**Input:** `{session_id, cwd, hook_event_name: "SessionStart", source: "compact"}`

**Output:** `{"hookSpecificOutput": {"additionalContext": "Compaction just ran...\nTOC..."}}` — asks for unwritten learnings + hands back TOC.

### SessionStart (startup)

**Input:** `{session_id, cwd, hook_event_name: "SessionStart", source: "startup"}`

**Output:** (empty) — no injection on fresh start.

### SubagentStop

**Input:** `{session_id, agent_id, cwd, hook_event_name: "SubagentStop"}`

**Output:** `{"hookSpecificOutput": {"additionalContext": "Before you finish..."}}` — reminder to report findings.

---

## Hook philosophy

- **Remind, don't block** — context hooks exit 0; only pre-commit blocks.
- **Never write judgment** — manual sections (`STATUS`, `MAP`, `TODO`, `LEARNINGS`) are the model's job.
- **Stay silent when irrelevant** — no context directory → no output.
- **Stateless** — no session state kept in hooks; state is in the context files.