#!/usr/bin/env bash
# init.sh — 3-tier context scaffold, zero tokens spent.
# Usage: init.sh [--tier auto|1|2|3] [--dir PROJECT] [--lang auto|pt|en] [--yes] [--todo] [--migrate]
# Only creates missing files; never overwrites manual content.
# <!-- auto:start --> … <!-- auto:end --> blocks belong to the script.
set -euo pipefail

TIER="auto"
DIR="."
LANG_OPT="${CONTEXTO_LANG:-auto}"
ASSUME="${CONTEXTO_ASSUME_MULTISESSAO:-}"
WANT_TODO=0
MIGRATE=0

usage() {
  echo "usage: init.sh [--tier auto|1|2|3] [--dir DIR] [--lang auto|pt|en] [--yes] [--todo] [--migrate]"
  echo "  --lang picks the template language (default: auto from \$LANG, pt* → pt, else en)"
  echo "  --yes  never prompt (tier 1-2 tie: commits on 2+ days → 2, else 1)"
  echo "  --todo create TODO.md (tier 2+; only for a 3+ step task without an issue tracker)"
  echo "  --migrate add frontmatter/auto block to old-format files, keeping the text (backup: .bak)"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --tier) TIER="${2:-auto}"; shift 2 ;;
    --dir) DIR="${2:-.}"; shift 2 ;;
    --lang) LANG_OPT="${2:-auto}"; shift 2 ;;
    --yes) ASSUME="0"; shift ;;
    --todo) WANT_TODO=1; shift ;;
    --migrate) MIGRATE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown arg: $1" >&2; usage; exit 1 ;;
  esac
done

resolve_lang() {
  case "$LANG_OPT" in
    pt|en) echo "$LANG_OPT"; return ;;
  esac
  case "${LANG:-en}" in
    pt*) echo "pt" ;;
    *) echo "en" ;;
  esac
}

LANG_N="$(resolve_lang)"
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ "$LANG_N" = "en" ]; then TPL="$SKILL_DIR/templates.en"; else TPL="$SKILL_DIR/templates"; fi
CTX="$DIR/.claude/context"
TODAY="$(date +%F)"

# Auto-block labels follow the template language.
if [ "$LANG_N" = "en" ]; then
  L_GEN="generated on"; L_TOP="top level"; L_ACT="Action"; L_CMD="Command"
  L_TEST_ALL="Test (all)"; L_TEST_ONE="Test (single)"; L_RUN="Run"
  L_NO_COMMITS="(no commits)"; L_NO_GIT="(no git)"; L_HEAD="# Project"
  L_FILE="<file>"; L_FILES="<files>"
else
  L_GEN="gerado em"; L_TOP="primeiro nível"; L_ACT="Ação"; L_CMD="Comando"
  L_TEST_ALL="Teste (tudo)"; L_TEST_ONE="Teste (um só)"; L_RUN="Rodar"
  L_NO_COMMITS="(sem commits)"; L_NO_GIT="(sem git)"; L_HEAD="# Projeto"
  L_FILE="<arquivo>"; L_FILES="<arquivos>"
fi

mkdir -p "$CTX"

# The project's repo: DIR itself (or a worktree/subdir of one), else the only
# repo one level down — a plain folder wrapping the real repo.
GIT_ROOT=""
if command -v git >/dev/null 2>&1; then
  if git -C "$DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    GIT_ROOT="$DIR"
  else
    shopt -s nullglob
    subs=("$DIR"/*/.git)
    shopt -u nullglob
    [ "${#subs[@]}" -eq 1 ] && GIT_ROOT="${subs[0]%/.git}"
  fi
fi

# Tool/agent/build dirs: hundreds of files that say nothing about project size.
SKIP_DIRS=(.git _bmad .agent .claude .wolf node_modules build .cxx __pycache__ .venv)

nfiles() {
  local re d
  local -a prune=()
  re="(^|/)($(IFS='|'; echo "${SKIP_DIRS[*]}" | sed 's/\./\\./g'))/"
  if [ "$GIT_ROOT" = "$DIR" ]; then
    git -C "$DIR" ls-files 2>/dev/null | grep -cEv "$re" || true
  else
    for d in "${SKIP_DIRS[@]}"; do prune+=(-name "$d" -o); done
    find "$DIR" \( "${prune[@]}" -false \) -prune -o -type f -print 2>/dev/null | wc -l
  fi
}

# Commits on 2+ distinct days: the work already spans sessions.
multi_day() {
  [ -n "$GIT_ROOT" ] || return 1
  [ "$(git -C "$GIT_ROOT" log -n 500 --format=%ad --date=short 2>/dev/null | sort -u | wc -l)" -ge 2 ]
}

is_monorepo() {
  [ -d "$DIR/packages" ] || [ -d "$DIR/apps" ] && return 0
  [ -f "$DIR/package.json" ] && grep -q '"workspaces"' "$DIR/package.json" 2>/dev/null && return 0
  [ -f "$DIR/Cargo.toml" ] && grep -q '\[workspace\]' "$DIR/Cargo.toml" 2>/dev/null && return 0
  return 1
}

resolve_tier() {
  local t="$TIER" n mono=0
  is_monorepo && mono=1
  n="$(nfiles | tr -d ' ')"
  case "$t" in
    1|2|3) echo "$t"; return ;;
  esac
  if [ "$mono" = 1 ] || [ "${n:-0}" -gt 200 ]; then echo 3; return; fi
  if [ "${n:-0}" -ge 20 ]; then echo 2; return; fi
  # <20 files: break the tie by duration
  if [ "$ASSUME" = "1" ]; then echo 2; return; fi
  if multi_day; then echo "git history spans 2+ days → multi-session" >&2; echo 2; return; fi
  if [ "$ASSUME" = "0" ]; then echo 1; return; fi
  if [ -t 0 ]; then
    read -r -p "will this last more than one session? (y/n) " r
    [ "$r" = "y" ] && echo 2 || echo 1
  else
    echo 1
  fi
}

TIER_N="$(resolve_tier)"
echo "tier=$TIER_N lang=$LANG_N dir=$DIR"

copy_missing() { # src dst
  [ -f "$2" ] || cp "$1" "$2"
}

# Never touches `active:` — a re-run must not deactivate an ongoing TODO.
# Fresh TODO.md copies already ship with `active: false` from the template.
stamp_frontmatter() { # file tier
  local f="$1" t="$2"
  if grep -q '^updated:' "$f"; then
    sed -i "s/^updated: .*/updated: $TODAY/" "$f"
  fi
  if grep -q '^tier:' "$f"; then
    sed -i "s/^tier: .*/tier: $t/" "$f"
  fi
}

# Old format (no frontmatter, or no auto block where the template has one):
# nothing gets stamped or filled. Warn; --migrate wraps the manual text with
# what is missing — the template's frontmatter on top, its auto section at the end.
check_format() { # file template
  local f="$1" tpl="$2" fm=1 au=1 miss
  [ "$(head -n 1 "$f")" = "---" ] || fm=0
  if grep -q '<!-- auto:start -->' "$tpl" && ! grep -q '<!-- auto:start -->' "$f"; then au=0; fi
  [ "$fm$au" = 11 ] && return 0
  miss=""
  if [ "$fm" = 0 ]; then miss="frontmatter"; fi
  if [ "$au" = 0 ]; then miss="${miss:+$miss + }auto block"; fi
  if [ "$MIGRATE" != 1 ]; then
    echo "old format: ${f##*/} has no $miss — add it by hand or rerun with --migrate (keeps the text, backup in .bak)" >&2
    return 0
  fi
  cp "$f" "$f.bak"
  {
    if [ "$fm" = 0 ]; then awk 'NR == 1 && $0 != "---" { exit } { print } NR > 1 && $0 == "---" { exit }' "$tpl"; echo ""; fi
    cat "$f"
    if [ "$au" = 0 ]; then
      echo ""
      awk '/^## / { h = $0 } /<!-- auto:start -->/ { print h; exit }' "$tpl"
      printf '\n<!-- auto:start -->\n<!-- auto:end -->\n'
    fi
  } > "$f.new"
  mv "$f.new" "$f"
  echo "migrated ${f##*/}: added $miss (backup: ${f##*/}.bak)"
}

# Replaces the auto block in the file with stdin content.
replace_auto() { # file
  local f="$1" tmp
  tmp="$(mktemp)"
  cat > "$tmp.body"
  awk -v body="$tmp.body" '
    /<!-- auto:start -->/ { print; while ((getline line < body) > 0) print line; close(body); skip=1; next }
    /<!-- auto:end -->/ { skip=0 }
    !skip { print }
  ' "$f" > "$tmp.new"
  mv "$tmp.new" "$f"
  rm -f "$tmp.body"
}

git_block() {
  echo "data: $TODAY"
  echo ""
  echo '```'
  if [ -n "$GIT_ROOT" ]; then
    [ "$GIT_ROOT" = "$DIR" ] || echo "repo: ${GIT_ROOT#"$DIR"/}/"
    # Short on purpose: the block is imported every session; `git log` has the rest.
    git -C "$GIT_ROOT" log --oneline -8 2>/dev/null || echo "$L_NO_COMMITS"
    echo "--- status ---"
    git -C "$GIT_ROOT" status --short 2>/dev/null | awk 'NR<=10 { print } END { if (NR > 10) print "... +" NR-10 }' || true
  else
    echo "$L_NO_GIT"
  fi
  echo '```'
}

# Picks a CMake configure preset for this host and prints
# "configure<TAB>build-cmd<TAB>test-cmd". python3 parses the JSON; prints nothing
# without python3 or a usable preset. Skips hidden presets and presets whose
# ${hostSystemName} condition (own or inherited) excludes this host.
cmake_preset_cmds() { # host-system-name
  command -v python3 >/dev/null 2>&1 || return 0
  python3 - "$DIR/CMakePresets.json" "$1" 2>/dev/null <<'EOF' || true
import json, sys
path, host = sys.argv[1], sys.argv[2]
d = json.load(open(path))
cfg = {p["name"]: p for p in d.get("configurePresets", [])}

def field(p, key, seen=()):
    if key in p:
        return p[key]
    inh = p.get("inherits", [])
    for parent in [inh] if isinstance(inh, str) else inh:
        if parent in cfg and parent not in seen:
            v = field(cfg[parent], key, seen + (parent,))
            if v is not None:
                return v
    return None

def host_ok(c):
    if not isinstance(c, dict) or c.get("lhs") != "${hostSystemName}":
        return True
    if c.get("type") == "equals":
        return c.get("rhs") == host
    if c.get("type") == "notEquals":
        return c.get("rhs") != host
    return True

for name, p in cfg.items():
    if p.get("hidden") or not host_ok(field(p, "condition")):
        continue
    bdir = (field(p, "binaryDir") or "build").replace("${sourceDir}/", "").replace("${presetName}", name)
    bld = next((b["name"] for b in d.get("buildPresets", [])
                if b.get("configurePreset") == name and not b.get("hidden")), None)
    tst = next((t["name"] for t in d.get("testPresets", [])
                if t.get("configurePreset") == name and not t.get("hidden")), None)
    build = "cmake --build --preset " + bld if bld else "cmake --build " + bdir + " -j"
    test = "ctest --preset " + tst if tst else "ctest --test-dir " + bdir + " --output-on-failure"
    print("cmake --preset " + name + "\t" + build + "\t" + test)
    break
EOF
}

cmake_cmds() { # fills build/test_all/lint of the caller (map_cmd_block)
  local host line="" cfg bcmd tcmd
  case "$(uname -s 2>/dev/null)" in
    Darwin) host="Darwin" ;;
    MINGW*|MSYS*|CYGWIN*) host="Windows" ;;
    *) host="Linux" ;;
  esac
  [ -f "$DIR/CMakePresets.json" ] && line="$(cmake_preset_cmds "$host")"
  if [ -n "$line" ]; then
    IFS=$'\t' read -r cfg bcmd tcmd <<< "$line"
    build="$cfg && $bcmd"
  else
    build="cmake -S . -B build && cmake --build build -j"
    tcmd="ctest --test-dir build --output-on-failure"
  fi
  # ctest only when some CMakeLists.txt registers tests.
  if [ -z "$test_all" ] && find "$DIR" -name CMakeLists.txt -not -path "$DIR/build*" -not -path "$DIR/.git/*" \
      -exec grep -Eqi 'enable_testing|add_test|include\(CTest\)' {} + 2>/dev/null; then
    test_all="$tcmd"
  fi
  if [ -z "$lint" ]; then
    [ -f "$DIR/.clang-format" ] && lint="clang-format -i $L_FILES"
    [ -f "$DIR/.gersemirc" ] && lint="${lint:+$lint · }gersemi -i CMakeLists.txt"
  fi
  return 0
}

# Build/output dirs and anything git-ignored stay out of the top-level listing.
# Output-dir names only count for directories with no tracked files, so
# source like build-aux/ or buildspec.json still shows up.
skip_top() { # name
  case "$1" in
    .git|.claude|__pycache__|node_modules|.venv) return 0 ;;
    build*|out|dist|target)
      if [ -d "$DIR/$1" ]; then
        [ "$IN_GIT" = 1 ] || return 0
        [ -z "$(git -C "$DIR" ls-files -- "$1" 2>/dev/null | head -n 1)" ] && return 0
      fi ;;
  esac
  [ "$IN_GIT" = 1 ] && git -C "$DIR" check-ignore -q -- "$1" 2>/dev/null
}

map_cmd_block() {
  echo "$L_GEN: $TODAY"
  echo ""
  local build="" test_all="" test_one="" lint="" run="" row
  if [ -f "$DIR/package.json" ]; then
    if command -v jq >/dev/null 2>&1; then
      for s in $(jq -r '.scripts // {} | keys[]' "$DIR/package.json" 2>/dev/null); do
        case "$s" in
          build) build="npm run build" ;;
          test) test_all="npm test" ;;
          lint) lint="npm run lint" ;;
          start|dev) run="npm run $s" ;;
        esac
      done
    else
      grep -q '"build"' "$DIR/package.json" && build="npm run build"
      grep -q '"test"' "$DIR/package.json" && test_all="npm test"
      grep -q '"lint"' "$DIR/package.json" && lint="npm run lint"
      grep -q '"dev"' "$DIR/package.json" && run="npm run dev"
      grep -q '"start"' "$DIR/package.json" && [ -z "$run" ] && run="npm start"
    fi
  fi
  # CMake before Makefile: a root Makefile next to CMakeLists.txt is often an in-source build.
  [ -f "$DIR/CMakeLists.txt" ] && [ -z "$build" ] && cmake_cmds
  if [ -f "$DIR/Makefile" ] && [ -z "$build" ]; then
    if grep -Eq '^build:' "$DIR/Makefile"; then build="make build"
    elif grep -Eq '^all:' "$DIR/Makefile"; then build="make"
    fi
  fi
  [ -f "$DIR/Cargo.toml" ] && { [ -z "$build" ] && build="cargo build"; [ -z "$test_all" ] && test_all="cargo test"; }
  [ -f "$DIR/pyproject.toml" ] && [ -z "$test_all" ] && test_one="pytest -q $L_FILE" && test_all="pytest -q"
  # Undetected rows are left out; no table at all when nothing was detected.
  local -a rows=()
  [ -n "$build" ] && rows+=("| Build | $build |")
  [ -n "$test_all" ] && rows+=("| $L_TEST_ALL | $test_all |")
  [ -n "$test_one" ] && rows+=("| $L_TEST_ONE | $test_one |")
  [ -n "$lint" ] && rows+=("| Lint/format | $lint |")
  [ -n "$run" ] && rows+=("| $L_RUN | $run |")
  if [ "${#rows[@]}" -gt 0 ]; then
    echo "| $L_ACT | $L_CMD |"
    echo "|---|---|"
    for row in "${rows[@]}"; do echo "$row"; done
    echo ""
  fi
  echo "$L_TOP:"
  echo ""
  echo '```'
  IN_GIT=0
  git -C "$DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 && IN_GIT=1
  shopt -s nullglob
  for e in "$DIR"/*; do
    b="${e##*/}"
    skip_top "$b" && continue
    printf '%s\n' "$b"
  done
  shopt -u nullglob
  echo '```'
}

ensure_claude_imports() { # tier
  local claude="$DIR/CLAUDE.md" t="$1"
  local -a want=("@.claude/context/MAP.md")
  if [ "$t" -ge 2 ]; then
    want+=("@.claude/context/STATUS.md" "@.claude/context/LEARNINGS.md")
    # TODO only while active (SKILL.md §4); an inactive one is read on demand.
    if grep -qE '^active:[[:space:]]*true' "$DIR/.claude/context/TODO.md" 2>/dev/null; then
      want+=("@.claude/context/TODO.md")
    fi
  fi
  [ -f "$DIR/.claude/context/WORKFLOW.md" ] && want+=("@.claude/context/WORKFLOW.md")
  if [ ! -f "$claude" ]; then
    { echo "$L_HEAD"; echo ""; for w in "${want[@]}"; do echo "$w"; done; } > "$claude"
    echo "created $claude"
    return
  fi
  for w in "${want[@]}"; do
    grep -qF "$w" "$claude" || echo "$w" >> "$claude"
  done
}

# --- files per tier ---
copy_missing "$TPL/MAP.md" "$CTX/MAP.md"
check_format "$CTX/MAP.md" "$TPL/MAP.md"
stamp_frontmatter "$CTX/MAP.md" "$TIER_N"
map_cmd_block | replace_auto "$CTX/MAP.md"

if [ "$TIER_N" -ge 2 ]; then
  copy_missing "$TPL/STATUS.md" "$CTX/STATUS.md"
  # TODO.md only on request: it is for a 3+ step task without an issue tracker.
  if [ "$WANT_TODO" = 1 ]; then copy_missing "$TPL/TODO.md" "$CTX/TODO.md"; fi
  copy_missing "$TPL/LEARNINGS.md" "$CTX/LEARNINGS.md"
  for f in STATUS TODO LEARNINGS; do
    [ -f "$CTX/$f.md" ] || continue
    check_format "$CTX/$f.md" "$TPL/$f.md"
    stamp_frontmatter "$CTX/$f.md" "$TIER_N"
  done
  git_block | replace_auto "$CTX/STATUS.md"
fi

if [ "$TIER_N" -ge 3 ]; then
  copy_missing "$TPL/BUGS.md" "$CTX/BUGS.md"
  check_format "$CTX/BUGS.md" "$TPL/BUGS.md"
  # WORKFLOW.md only if the user already has a process — never create blank.
  if [ -f "$CTX/WORKFLOW.md" ]; then
    check_format "$CTX/WORKFLOW.md" "$TPL/WORKFLOW.md"
    stamp_frontmatter "$CTX/WORKFLOW.md" "$TIER_N"
  fi
fi

ensure_claude_imports "$TIER_N"

echo "---"
echo "created/verified in $CTX:"
ls "$CTX"
echo "---"
echo "left blank to complete: MAP (flows), STATUS (state/next phase)"
# Report the REAL flag, not a guess: a re-run over an ongoing TODO used to
# print "active: false" while the file said true, which reads as if the script
# had just deactivated it (it never touches `active:` — see copy_missing).
if [ "$TIER_N" -ge 2 ] && [ -f "$CTX/TODO.md" ]; then
  if grep -qE '^active:[[:space:]]*true' "$CTX/TODO.md"; then
    echo "TODO is active: true — set it back to false when the queue empties."
  else
    echo "TODO is active: false — enable for a 3+ step task."
    if grep -qF "@.claude/context/TODO.md" "$DIR/CLAUDE.md" 2>/dev/null; then
      echo "CLAUDE.md still imports TODO.md — drop that line while it is inactive."
    fi
  fi
elif [ "$TIER_N" -ge 2 ]; then
  echo "no TODO.md — rerun with --todo for a 3+ step task without an issue tracker."
fi
