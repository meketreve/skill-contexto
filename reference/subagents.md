# Subagents

A subagent starts with a fresh context and cannot see the parent's transcript; its own transcript is not read by the parent either. Project memory does not reach it by itself — the skill has to hand it over, in both directions.

## Before spawning

1. Turn the task into search terms and run `<skill-dir>/scripts/index.sh --dir PROJECT TERM...` — the task's nouns, the file it touches, the library involved. Paste the hits into the brief.
2. Say which context files the subagent must not edit (`STATUS.md`, `TODO.md`, `MAP.md` belong to the parent, which holds the whole session).
3. Ask for the findings in entry format in the final message, so the parent can judge and promote them.

Brief template — trim, don't decorate:

```text
Context for this task, already recorded (don't re-explore it):
<index.sh output, or "nothing recorded">

Task: <one paragraph, naming the entry point file:line>

Constraints:
- don't edit .claude/context/STATUS.md, TODO.md or MAP.md — the parent owns them
- .claude/context/LEARNINGS.md is the hot file, .claude/context/memory/<tag>.md is cold;
  run scripts/index.sh <term> before grepping blind, and grep BUGS.md on the error text
- report what you changed (file:line), what you verified (command + result), and findings as
  `- [YYYY-MM-DD] [tag] [✓|✗] fact — consequence`; write the ones that cost more than one
  attempt to .claude/context/memory/<tag>.md yourself
```

## After it returns

Read the final message, not the transcript. Promote each finding: a line in `LEARNINGS.md` for something broad or short, `memory/<tag>.md` plus a pointer for anything long, a `BUGS.md` block when it meets the rule (literal error message). Discard the rest — a subagent's guesses are not learnings until the parent confirms them.

## Hooks that make it automatic

Both live in `scripts/hook.sh` and are wired in `reference/hooks.md`:

- `PreToolUse` fires inside subagents too, with `agent_id` in the input. The recall marker includes it, so a subagent gets the recall the parent already consumed.
- `SubagentStop` asks the subagent to write its findings before it dies, once per agent, only if it touched a file (internal agents never do). `additionalContext` continues the conversation instead of forcing a stop-block.

## Limits

- Parallel subagents editing `LEARNINGS.md` interleave lines. For fan-out, give each one its own `memory/<tag>.md` and let the parent merge the pointers.
- The parent is the only one that may close the session: a subagent never rewrites `STATUS.md` or trims a budget.
- Nothing here replaces `--check`: a subagent's pointer is still verified by it.
