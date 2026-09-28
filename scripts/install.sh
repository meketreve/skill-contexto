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
#   .claude/skills/contexto, .opencode/skills/contexto, .opencode/commands/{context,contexto}.md
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="link"
FORCE=0
ONLY="all"
PROJECT=0
UNINSTALL=0

usage() {
  echo "usage: install.sh [--only claude,opencode,agents] [--copy] [--force] [--project] [--uninstall] [--list]"
  echo "  default: symlink global skill into every detected harness dir"
  echo "  --copy     copy files instead of symlinking (frozen version, committable)"
  echo "  --force    replace existing non-symlink installs"
  echo "  --project  install copies into ./.claude + ./.opencode (team sharing)"
  echo "  --uninstall remove installed links/copies"
  echo "  --list     show targets and current status"
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
  echo "skip $1 (not detected — use --only $1 to force)"
}

status_of() { # path
  if [ -L "$1" ]; then echo "symlink -> $(readlink "$1")"
  elif [ -e "$1" ]; then echo "copy/installed"
  else echo "missing"; fi
}

put_dir() { # src dst
  local src="$1" dst="$2"
  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then echo "ok   $dst"; return; fi
  if [ -e "$dst" ] && [ "$FORCE" != "1" ]; then echo "skip $dst (exists, use --force)"; return; fi
  rm -rf "$dst"
  mkdir -p "$(dirname "$dst")"
  if [ "$MODE" = "copy" ]; then cp -r "$src" "$dst"; else ln -s "$src" "$dst"; fi
  echo "put  $dst ($MODE)"
}

put_file() { # src dst
  local src="$1" dst="$2"
  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then echo "ok   $dst"; return; fi
  if [ -e "$dst" ] && [ "$FORCE" != "1" ]; then echo "skip $dst (exists, use --force)"; return; fi
  rm -f "$dst"
  mkdir -p "$(dirname "$dst")"
  if [ "$MODE" = "copy" ]; then cp "$src" "$dst"; else ln -s "$src" "$dst"; fi
  echo "put  $dst ($MODE)"
}

drop() { # path
  if [ -L "$1" ] || [ -e "$1" ]; then rm -rf "$1"; echo "drop $1"; else echo "---- $1 (already missing)"; fi
}

if [ "$ONLY" = "list" ]; then
  echo "repo: $REPO"
  echo "claude skill:    $HOME/.claude/skills/contexto — $(status_of "$HOME/.claude/skills/contexto")"
  echo "agents skill:    $HOME/.agents/skills/contexto — $(status_of "$HOME/.agents/skills/contexto")"
  echo "opencode skill:  $HOME/.config/opencode/skills/contexto — $(status_of "$HOME/.config/opencode/skills/contexto")"
  echo "opencode cmd:    $HOME/.config/opencode/commands/context.md — $(status_of "$HOME/.config/opencode/commands/context.md")"
  echo "opencode cmd:    $HOME/.config/opencode/commands/contexto.md — $(status_of "$HOME/.config/opencode/commands/contexto.md")"
  exit 0
fi

if [ "$UNINSTALL" = "1" ]; then
  want claude && drop "$HOME/.claude/skills/contexto"
  want agents && drop "$HOME/.agents/skills/contexto"
  want opencode && { drop "$HOME/.config/opencode/skills/contexto"; drop "$HOME/.config/opencode/commands/context.md"; drop "$HOME/.config/opencode/commands/contexto.md"; }
  exit 0
fi

if [ "$PROJECT" = "1" ]; then
  # Team sharing: always copies, so the project carries the skill in git.
  MODE_SAVED="$MODE"; MODE="copy"
  want claude && put_dir "$REPO" "./.claude/skills/contexto"
  if want opencode; then
    put_dir "$REPO" "./.opencode/skills/contexto"
    put_file "$REPO/commands/context.md" "./.opencode/commands/context.md"
    put_file "$REPO/commands/contexto.md" "./.opencode/commands/contexto.md"
  fi
  MODE="$MODE_SAVED"
  echo "project install done (copies — commit them)"
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
  echo "note: quit and restart opencode to load the skill/command"
else
  skip_msg opencode
fi
