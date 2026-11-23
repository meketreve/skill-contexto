#!/usr/bin/env bash
# hook.sh — Claude Code agent hook for the contexto skill (opt-in).
# Reads the hook JSON on stdin; prints hookSpecificOutput.additionalContext JSON, or
# plain text for the events where stdout reaches the model. Always exits 0: it reminds,
# it never blocks. Wiring: reference/hooks.md.
#   PreCompact,   any path:    plain stdout = instructions for the compaction summary
#                (keep errors/paths/commands/decisions verbatim) — never JSON here.
#   SessionStart, source=compact: plain stdout = write what is still unwritten, plus the
#                memory table of contents (index.sh) to recall from.
#   PreToolUse,  file outside .claude/context: entries in LEARNINGS*/BUGS*/memory/ that
#                cite the file (via index.sh), once per file per agent.
#   PostToolUse, file inside .claude/context:  budget warning, only when the manual
#                part (outside auto blocks) is over the budget.
#   SubagentStop, any path: ask the subagent to write its findings before it dies —
#                its transcript is not the parent's, and nobody else will see it.
# Parses with jq when present, falls back to sed (flat fields only).
set -uo pipefail
# A consumer that closes the pipe early (`| head`, `| grep -q`) must not turn a reminder
# into a SIGPIPE exit: this hook always exits 0.
trap '' PIPE

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IN="$(cat)"

field() { # top-level or tool_input string field
  if command -v jq >/dev/null 2>&1; then
    { printf '%s' "$IN" | jq -r --arg k "$1" '.[$k] // .tool_input[$k] // empty'; } 2>/dev/null
  else
    { printf '%s' "$IN" | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" | head -n 1; } 2>/dev/null
  fi
}

say() { # event text — emit additionalContext as JSON
  local t="$2"
  t="${t//\\/\\\\}"; t="${t//\"/\\\"}"; t="${t//$'\t'/ }"; t="${t//$'\n'/\\n}"
  # EPIPE stays silent (trap above) and never becomes an error line on stderr.
  printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"%s"}}\n' "$1" "$t" 2>/dev/null || true
}

EVENT="$(field hook_event_name)"
FILE="$(field file_path)"
PROJ="${CLAUDE_PROJECT_DIR:-$(field cwd)}"
[ -n "$PROJ" ] || PROJ="$PWD"
CTX="$PROJ/.claude/context"
[ -d "$CTX" ] || exit 0
SCRATCH="$(field scratchpad_dir)"; SCRATCH="${SCRATCH:-${TMPDIR:-/tmp}}"

# Before compaction: plain stdout is used verbatim as instructions for the summary.
# A summary keeps the story and drops the artifacts, so name the artifacts.
if [ "$EVENT" = "PreCompact" ]; then
  cat <<'EOF' 2>/dev/null || true
Keep these VERBATIM in the summary — none of them survives a paraphrase:
- literal error messages and stack traces
- file paths, file:line, symbol and table names
- commands that worked, with their arguments
- decisions, and alternatives already rejected with the reason
- open questions and the exact next step
The project context lives in .claude/context/ (MAP, STATUS, LEARNINGS); long-term memory
lives in .claude/context/memory/ and is searched with scripts/index.sh, never read whole.
EOF
  exit 0
fi

# After compaction: the summary may have dropped detail. Ask for what is still unwritten
# and hand back the memory table of contents so the agent can recall instead of re-guess.
if [ "$EVENT" = "SessionStart" ] && [ "$(field source)" = "compact" ]; then
  echo "Compaction just ran. Before continuing, write what this session already learned and is not in .claude/context/LEARNINGS.md yet: one line per fact, verdict [✓]/[✗]/[↻ date] on anything tried or decided. A tag that is already long moves to .claude/context/memory/<tag>.md, leaving one pointer behind." 2>/dev/null || true
  toc="$("$HERE/index.sh" --dir "$PROJ" 2>/dev/null)"
  case "$toc" in ""|"no entry matches") ;; *) printf '\nRecorded memory (search it with scripts/index.sh TERM):\n%s\n' "$toc" 2>/dev/null || true ;; esac
  exit 0
fi

[ -n "$FILE" ] || [ "$EVENT" = "SubagentStop" ] || exit 0
REL="${FILE#"$PROJ"/}"

# Subagent finished: its transcript dies with it, so ask it to leave the findings behind.
# The per-agent marker doubles as "this agent actually touched a file" (internal agents
# like prompt suggestions never do) and as the once-only guard, which needs no jq.
if [ "$EVENT" = "SubagentStop" ]; then
  mark="${SCRATCH:-${TMPDIR:-/tmp}}/contexto-recall-$(field session_id)-$(field agent_id)"
  [ -f "$mark" ] || exit 0
  [ -f "$mark.reminded" ] && exit 0
  : > "$mark.reminded"
  say SubagentStop "Before you finish: write down what the parent cannot see in your transcript — one line per fact in .claude/context/LEARNINGS.md with verdict [✓]/[✗]/[↻ date], or in .claude/context/memory/<tag>.md when it is more than a line. Keep literal errors, file:line and why a rejected approach failed. State the same in your final message."
  exit 0
fi

case "$REL" in
  .claude/context/memory/*) exit 0 ;; # long-term memory has no budget
  .claude/context/*)
    [ "$EVENT" = "PostToolUse" ] || exit 0
    name="${REL##*/}"
    case "$name" in
      STATUS.md|TODO.md|MAP.md) max=60 ;;
      LEARNINGS.md) max=100 ;;
      *) exit 0 ;;
    esac
    n="$(awk '/<!-- auto:start/{s=1} !s{n++} /<!-- auto:end/{s=0} END{print n+0}' "$FILE" 2>/dev/null)"
    [ "${n:-0}" -gt "$max" ] || exit 0
    if [ "$name" = "LEARNINGS.md" ]; then
      say PostToolUse "$name: $n lines outside auto blocks, budget $max. Promote a whole tag to .claude/context/memory/<tag>.md and leave one pointer in 'Long-term memory' (nothing is deleted, [✗] lines stay); only then summarize or delete hot lines. Never trim inside <!-- auto:start --> blocks."
    else
      say PostToolUse "$name: $n lines outside auto blocks, budget $max. Summarize the manual part into 1 line or delete (git log keeps history). Never trim inside <!-- auto:start --> blocks."
    fi
    ;;
  /*) exit 0 ;; # outside the project
  *)
    [ "$EVENT" = "PreToolUse" ] || exit 0
    # once per file per agent: the reminder is for the first touch, not every edit.
    # agent_id keeps a subagent from inheriting the parent's marker — a fresh context
    # is exactly the one that needs the recall.
    mark="${SCRATCH:-${TMPDIR:-/tmp}}/contexto-recall-$(field session_id)-$(field agent_id)"
    grep -qxF -- "$REL" "$mark" 2>/dev/null && exit 0
    printf '%s\n' "$REL" >> "$mark" 2>/dev/null
    base="${REL##*/}"
    hits="$("$HERE/index.sh" --dir "$PROJ" -n 3 "$REL" 2>/dev/null)"
    if [ "$hits" = "no entry matches" ] || [ -z "$hits" ]; then
      # generic names (index.ts, main.py, mod.rs…) would match half the project
      case "$base" in index.*|main.*|mod.rs|lib.rs|__init__.py|utils.*|types.*|README*) exit 0 ;; esac
      hits="$("$HERE/index.sh" --dir "$PROJ" -n 3 "$base" 2>/dev/null)"
      [ "$hits" = "no entry matches" ] || [ -z "$hits" ] && exit 0
      term="$base"
    else
      term="$REL"
    fi
    say PreToolUse "Recorded learnings/bugs cite $term — read before editing (all: index.sh $term):
$hits"
    ;;
esac
exit 0
