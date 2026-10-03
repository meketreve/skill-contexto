#!/usr/bin/env bash
# hook.sh — Claude Code agent hook for PreToolUse/PostToolUse on Write|Edit (opt-in).
# Reads the hook JSON on stdin; prints hookSpecificOutput.additionalContext JSON or
# nothing. Always exits 0: it reminds, it never blocks. Wiring: reference/hooks.md.
#   PreToolUse,  file outside .claude/context: entries in LEARNINGS*/BUGS* that cite
#                the file (via index.sh), once per file per session.
#   PostToolUse, file inside .claude/context:  budget warning, only when the manual
#                part (outside auto blocks) is over the budget.
# Parses with jq when present, falls back to sed (flat fields only).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IN="$(cat)"

field() { # top-level or tool_input string field
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$IN" | jq -r --arg k "$1" '.[$k] // .tool_input[$k] // empty' 2>/dev/null
  else
    printf '%s' "$IN" | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" | head -n 1
  fi
}

say() { # event text — emit additionalContext as JSON
  local t="$2"
  t="${t//\\/\\\\}"; t="${t//\"/\\\"}"; t="${t//$'\t'/ }"; t="${t//$'\n'/\\n}"
  printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"%s"}}\n' "$1" "$t"
}

EVENT="$(field hook_event_name)"
FILE="$(field file_path)"
[ -n "$FILE" ] || exit 0
PROJ="${CLAUDE_PROJECT_DIR:-$(field cwd)}"
[ -n "$PROJ" ] || PROJ="$PWD"
REL="${FILE#"$PROJ"/}"
CTX="$PROJ/.claude/context"
[ -d "$CTX" ] || exit 0

case "$REL" in
  .claude/context/*)
    [ "$EVENT" = "PostToolUse" ] || exit 0
    name="${REL##*/}"
    case "$name" in
      STATUS.md|TODO.md|MAP.md) max=60 ;;
      LEARNINGS.md) max=100 ;;
      *) exit 0 ;;
    esac
    n="$(awk '/<!-- auto:start -->/{s=1} !s{n++} /<!-- auto:end -->/{s=0} END{print n+0}' "$FILE" 2>/dev/null)"
    [ "${n:-0}" -gt "$max" ] || exit 0
    say PostToolUse "$name: $n lines outside auto blocks, budget $max. Summarize the manual part into 1 line or delete (git log keeps history); [✗] lines in LEARNINGS only shrink. Never trim inside <!-- auto:start --> blocks."
    ;;
  /*) exit 0 ;; # outside the project
  *)
    [ "$EVENT" = "PreToolUse" ] || exit 0
    # once per file per session: the reminder is for the first touch, not every edit
    mark="$(field scratchpad_dir)"; mark="${mark:-${TMPDIR:-/tmp}}/contexto-recall-$(field session_id)"
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
