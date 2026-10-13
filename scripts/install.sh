#!/usr/bin/env bash
# install.sh — put this skill where your harness already looks.
# Default is symlink (tracks `git pull`); --copy freezes a version.
#
# Usage:
#   ./scripts/install.sh [--only claude,opencode,agents] [--copy] [--force] [--project] [--uninstall] [--list]
#
# Targets (global, personal):
#   claude    ~/.claude/skills/contexto                      (Claude Code skill)
#   agents    ~/.agents/skills/contexto                       (Agent Skills spec dir; opencode auto-loads it too)
#   opencode  ~/.config/opencode/skills/contexto + commands/{context,contexto}.md  (skill + /context + /contexto)
#
# By default only harnesses detected on this machine are installed
# (claude: ~/.claude exists or `claude` on PATH; opencode: ~/.config/opencode
# exists or `opencode` on PATH; agents: always — zero cost, cross-harness).
# `--only` overrides detection and forces the listed targets.
#
# --project installs copies into the current project instead:
#   .claude/skills/contexto, .agents/skills/contexto, .opencode/skills/contexto,
#   .opencode/commands/{context,contexto}.md
# --uninstall removes them again; with --project it only touches the project copies.
set -euo pipefail
# A consumer that closes the pipe early (`| head`, `| grep -q`) used to kill the install
# with SIGPIPE (exit 141). Ignore the signal; `say` swallows the resulting EPIPE errors.
trap '' PIPE

# Narration goes through say so a closed pipe can never fail an otherwise fine install.
say() { echo "$@" 2>/dev/null || true; }

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="link"
FORCE=0
ONLY="all"
PROJECT=0
UNINSTALL=0

usage() {
  say "usage: install.sh [--only claude,opencode,agents] [--copy] [--force] [--project] [--uninstall] [--list]"
  say "  default: symlink global skill into every detected harness dir"
  say "  --copy     copy files instead of symlinking (frozen version, committable)"
  say "  --force    replace existing non-symlink installs"
  say "  --project  install copies into ./.claude + ./.agents + ./.opencode (team sharing)"
  say "  --uninstall remove installed links/copies (with --project: only the project copies)"
  say "  --list     show targets and current status"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --copy) MODE="copy"; shift ;;
    --force) FORCE=1; shift ;;
    --only) ONLY="${2:-all}"; shift 2 ;;
    --project) PROJECT=1; shift ;;
    --uninstall) UNINSTALL=1; shift ;;
    --list) ONLY="list"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown arg: $1" >&2; usage; exit 1 ;;
  esac
done

want() { # name
  [ "$ONLY" = "all" ] || [ "$ONLY" = "list" ] && return 0
  case ",$ONLY," in *",${1},"*) return 0;; *) return 1;; esac
}

forced() { # name — true when the user explicitly listed this harness
  [ "$ONLY" != "all" ] && [ "$ONLY" != "list" ] && case ",$ONLY," in *",${1},"*) return 0;; esac
  return 1
}

detected() { # name
  forced "$1" && return 0
  case "$1" in
    claude) [ -d "$HOME/.claude" ] || command -v claude >/dev/null 2>&1 ;;
    opencode) [ -d "$HOME/.config/opencode" ] || command -v opencode >/dev/null 2>&1 ;;
    agents) return 0 ;;
  esac
}

skip_msg() { # name
  say "skip $1 (not detected — use --only $1 to force)"
}

status_of() { # path
  if [ -L "$1" ]; then echo "symlink -> $(readlink "$1")"
  elif [ -e "$1" ]; then echo "copy/installed"
  else echo "missing"; fi
}

put_dir() { # src dst
  local src="$1" dst="$2"
  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then say "ok   $dst"; return; fi
  if [ -e "$dst" ] && [ "$FORCE" != "1" ]; then say "skip $dst (exists, use --force)"; return; fi
  rm -rf "$dst"
  mkdir -p "$(dirname "$dst")"
  if [ "$MODE" = "copy" ]; then cp -r "$src" "$dst"; else ln -s "$src" "$dst"; fi
  say "put  $dst ($MODE)"
}

put_file() { # src dst
  local src="$1" dst="$2"
  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then say "ok   $dst"; return; fi
  if [ -e "$dst" ] && [ "$FORCE" != "1" ]; then say "skip $dst (exists, use --force)"; return; fi
  rm -f "$dst"
  mkdir -p "$(dirname "$dst")"
  if [ "$MODE" = "copy" ]; then cp "$src" "$dst"; else ln -s "$src" "$dst"; fi
  say "put  $dst ($MODE)"
}

drop() { # path
  if [ -L "$1" ] || [ -e "$1" ]; then rm -rf "$1"; echo "drop $1"; else say "---- $1 (already missing)"; fi
}

if [ "$ONLY" = "list" ]; then
  # version comes from the SKILL.md frontmatter; no line, no suffix
  VERSION="$(sed -n 's/^version:[[:space:]]*//p' "$REPO/SKILL.md" 2>/dev/null | head -n 1 || true)"
  say "repo: $REPO${VERSION:+ (v$VERSION)}"
  say "claude skill:    $HOME/.claude/skills/contexto — $(status_of "$HOME/.claude/skills/contexto")"
  say "agents skill:    $HOME/.agents/skills/contexto — $(status_of "$HOME/.agents/skills/contexto")"
  say "opencode skill:  $HOME/.config/opencode/skills/contexto — $(status_of "$HOME/.config/opencode/skills/contexto")"
  say "opencode cmd:    $HOME/.config/opencode/commands/context.md — $(status_of "$HOME/.config/opencode/commands/context.md")"
  say "opencode cmd:    $HOME/.config/opencode/commands/contexto.md — $(status_of "$HOME/.config/opencode/commands/contexto.md")"
  exit 0
fi

if [ "$UNINSTALL" = "1" ]; then
  if [ "$PROJECT" = "1" ]; then
    # --project --uninstall undoes the project copies only; $HOME stays untouched.
    want claude && drop "./.claude/skills/contexto"
    want agents && drop "./.agents/skills/contexto"
    want opencode && { drop "./.opencode/skills/contexto"; drop "./.opencode/commands/context.md"; drop "./.opencode/commands/contexto.md"; }
    exit 0
  fi
  want claude && drop "$HOME/.claude/skills/contexto"
  want agents && drop "$HOME/.agents/skills/contexto"
  want opencode && { drop "$HOME/.config/opencode/skills/contexto"; drop "$HOME/.config/opencode/commands/context.md"; drop "$HOME/.config/opencode/commands/contexto.md"; }
  exit 0
fi

if [ "$PROJECT" = "1" ]; then
  # Team sharing: always copies, so the project carries the skill in git.
  MODE_SAVED="$MODE"; MODE="copy"
  want claude && put_dir "$REPO" "./.claude/skills/contexto"
  want agents && put_dir "$REPO" "./.agents/skills/contexto"
  if want opencode; then
    put_dir "$REPO" "./.opencode/skills/contexto"
    put_file "$REPO/commands/context.md" "./.opencode/commands/context.md"
    put_file "$REPO/commands/contexto.md" "./.opencode/commands/contexto.md"
  fi
  MODE="$MODE_SAVED"
  say "project install done (copies — commit them)"
  exit 0
fi

if detected claude; then
  put_dir "$REPO" "$HOME/.claude/skills/contexto"
else
  skip_msg claude
fi
if detected agents; then
  put_dir "$REPO" "$HOME/.agents/skills/contexto"
else
  skip_msg agents
fi
if detected opencode; then
  put_dir "$REPO" "$HOME/.config/opencode/skills/contexto"
  put_file "$REPO/commands/context.md" "$HOME/.config/opencode/commands/context.md"
  put_file "$REPO/commands/contexto.md" "$HOME/.config/opencode/commands/contexto.md"
  say "note: quit and restart opencode to load the skill/command"
else
  skip_msg opencode
fi
