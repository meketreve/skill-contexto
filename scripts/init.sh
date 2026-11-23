#!/usr/bin/env bash
# init.sh — 3-tier context scaffold, zero tokens spent.
# Usage: init.sh [--tier auto|1|2|3] [--dir PROJECT] [--lang auto|pt|en] [--yes] [--todo] [--migrate] [--index] [--bundle] [--opencode] [--check] [--quiet] [--json] [--dry-run]
# Only creates missing files; never overwrites manual content.
# <!-- auto:start --> … <!-- auto:end --> blocks belong to the script.
set -euo pipefail
# A consumer that closes the pipe early (`| head`, `| grep -q`) used to kill the scaffold
# with SIGPIPE (exit 141) — sometimes mid-run, leaving half the files on disk. Ignoring the
# signal turns those writes into plain EPIPE errors, which `say` swallows.
trap '' PIPE

TIER="auto"
DIR="."
LANG_OPT="${CONTEXTO_LANG:-auto}"
ASSUME="${CONTEXTO_ASSUME_MULTISESSAO:-}"
WANT_TODO=0
MIGRATE=0
WANT_INDEX=0
WANT_BUNDLE=0
WANT_OPENCODE=0
CHECK=0
QUIET=0
JSON=0
DRY_RUN=0
ASSUME_YES=0

# Narration must never turn a finished scaffold into a failure. A consumer that closes
# the pipe early (`| head`, `| grep -q`) makes the next write fail with EPIPE, and under
# `set -e` that used to abort the run — sometimes mid-scaffold, leaving half the files.
# Every informational line goes through say; file writes are unaffected.
say() { echo "$@" 2>/dev/null || true; }

usage() {
  say "usage: init.sh [--tier auto|1|2|3] [--dir DIR] [--lang auto|pt|en] [--yes] [--todo] [--migrate] [--index] [--bundle] [--opencode] [--check] [--quiet] [--json] [--dry-run]"
  say "  --lang picks the template language (default: auto from \$LANG, pt* → pt, else en)"
  say "  --yes  never prompt (tier 1-2 tie: commits on 2+ days → 2; with no TTY the tie goes to 2,"
  say "         the multi-session default — force one-shot with --tier 1 or CONTEXTO_ASSUME_MULTISESSAO=0)"
  say "  --todo create TODO.md (tier 2+; only for a 3+ step task without an issue tracker)"
  say "  --migrate add frontmatter/auto block to old-format files, keeping the text (backup: .bak)"
  say "  --index  add a code index to MAP.md (tables/RLS, SQL functions, edge functions, routes);"
  say "           once added, every run refreshes it"
  say "  --bundle add AGENTS.md carrying the same files the import policy loads, for harnesses that"
  say "           do not expand @imports (DSH); once added, every run refreshes it"
  say "  --opencode write the same file list into the 'instructions' array of opencode.json"
  say "           (opencode V2 ignores CLAUDE.md); backup on edit, JSONC comments preserved,"
  say "           once added, every run refreshes it"
  say "  --check  read-only: report stale bundle, marker/import/budget problems and broken"
  say "           memory pointers; writes nothing, exits 1 when it finds something"
  say "  --quiet  with --check: suppress the header and the success detail, one line on success"
  say "  --json   with --check: one JSON object instead of prose (ok, tier, dir, problems, warnings, messages)"
  say "  --dry-run print would create/would update/untouched for every file, without writing"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --tier|--dir|--lang)
      [ $# -ge 2 ] || { echo "init.sh: $1 needs a value" >&2; usage; exit 1; }
      case "$1" in
        --tier) TIER="$2" ;;
        --dir) DIR="$2" ;;
        --lang) LANG_OPT="$2" ;;
      esac
      shift 2 ;;
    --yes) ASSUME_YES=1; shift ;;
    --todo) WANT_TODO=1; shift ;;
    --migrate) MIGRATE=1; shift ;;
    --index) WANT_INDEX=1; shift ;;
    --bundle) WANT_BUNDLE=1; shift ;;
    --opencode) WANT_OPENCODE=1; shift ;;
    --check) CHECK=1; shift ;;
    --quiet) QUIET=1; shift ;;
    --json) JSON=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown arg: $1" >&2; usage; exit 1 ;;
  esac
done

case "$TIER" in
  auto|1|2|3) ;;
  *) echo "init.sh: invalid --tier '$TIER' (auto|1|2|3)" >&2; exit 1 ;;
esac
case "$LANG_OPT" in
  auto|pt|en) ;;
  *) echo "init.sh: invalid --lang '$LANG_OPT' (auto|pt|en)" >&2; exit 1 ;;
esac
# --check never prompts: on a tier 1-2 tie it reports against the multi-session tier.
if [ "$CHECK" = 1 ]; then ASSUME_YES=1; fi
if [ "$DRY_RUN" = 1 ] && [ "$CHECK" = 1 ]; then
  echo "init.sh: --dry-run and --check are mutually exclusive" >&2
  exit 1
fi
# --dry-run never prompts and never touches the project.
if [ "$DRY_RUN" = 1 ]; then ASSUME_YES=1; fi

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
CTX="${CONTEXTO_DIR:-$DIR/.claude/context}"
TODAY="$(date +%F)"

# Auto-block labels follow the template language.
if [ "$LANG_N" = "en" ]; then
  L_GEN="generated on"; L_TOP="top level"; L_ACT="Action"; L_CMD="Command"
  L_TEST_ALL="Test (all)"; L_TEST_ONE="Test (single)"; L_RUN="Run"
  L_NO_COMMITS="(no commits)"; L_NO_GIT="(no git)"; L_HEAD="# Project"
  L_DATE="date"
  L_FILE="<file>"; L_FILES="<files>"
  L_IDX_HEAD="Code index (auto)"; L_IDX_TABLES="Tables"; L_IDX_FILES="files"; L_IDX_FUNCS="SQL functions"
  L_IDX_EDGE="Edge functions"; L_IDX_ROUTES="Routes"; L_IDX_RLS="rls"; L_IDX_NORLS="NO-RLS"
  L_IDX_EMPTY="(nothing detected: no migrations/*.sql, edge functions or routes)"
  L_BUNDLE_HEAD="<!-- Generated by the contexto skill (init.sh) — do not edit by hand: the truth lives in .claude/context/, and --check verifies this bundle. -->"
  L_BUNDLE_TITLE="Project context (mirror of .claude/context/)"
else
  L_GEN="gerado em"; L_TOP="primeiro nível"; L_ACT="Ação"; L_CMD="Comando"
  L_TEST_ALL="Teste (tudo)"; L_TEST_ONE="Teste (um só)"; L_RUN="Rodar"
  L_NO_COMMITS="(sem commits)"; L_NO_GIT="(sem git)"; L_HEAD="# Projeto"
  L_DATE="data"
  L_FILE="<arquivo>"; L_FILES="<arquivos>"
  L_IDX_HEAD="Índice do código (auto)"; L_IDX_TABLES="Tabelas"; L_IDX_FILES="arquivos"; L_IDX_FUNCS="Funções SQL"
  L_IDX_EDGE="Edge functions"; L_IDX_ROUTES="Rotas"; L_IDX_RLS="rls"; L_IDX_NORLS="SEM-RLS"
  L_IDX_EMPTY="(nada detectado: sem migrations/*.sql, edge functions ou rotas)"
  L_BUNDLE_HEAD="<!-- Gerado pela skill contexto (init.sh) — não editar à mão: a verdade está em .claude/context/, e o --check verifica este bundle. -->"
  L_BUNDLE_TITLE="Contexto do projeto (espelho de .claude/context/)"
fi

[ "$CHECK" = 1 ] || [ "$DRY_RUN" = 1 ] || mkdir -p "$CTX"   # --check/--dry-run write nothing, not even the directory

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

# Editor/script backups are noise: they would inflate the file count, the MAP
# listing and the code index. Matched on the basename only.
NOISE_RE='(^|/)[^/]*\.bak[^/]*$|(^|/)[^/]*\.orig$|(^|/)[^/]*~$'
skip_noise() { # name
  case "$1" in
    *.bak*|*.orig|*~) return 0 ;;
  esac
  return 1
}

nfiles() {
  local re d
  local -a prune=()
  re="(^|/)($(IFS='|'; echo "${SKIP_DIRS[*]}" | sed 's/\./\\./g'))/"
  if [ "$GIT_ROOT" = "$DIR" ]; then
    git -C "$DIR" ls-files 2>/dev/null | grep -cEv "($re)|($NOISE_RE)" || true
  else
    for d in "${SKIP_DIRS[@]}"; do prune+=(-name "$d" -o); done
    find "$DIR" \( "${prune[@]}" -false \) -prune -o -type f \
      ! -name '*.bak*' ! -name '*.orig' ! -name '*~' -print 2>/dev/null | wc -l
  fi
}

# Commits on 2+ distinct days: the work already spans sessions.
multi_day() {
  [ -n "$GIT_ROOT" ] || return 1
  [ "$(git -C "$GIT_ROOT" log -n 500 --format=%ad --date=short 2>/dev/null | sort -u | wc -l)" -ge 2 ]
}

is_monorepo() {
  # A subdirectory, not the bare name: an empty packages/ is not a monorepo.
  local d
  for d in "$DIR"/packages/*/ "$DIR"/apps/*/; do [ -d "$d" ] && return 0; done
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
  # <20 files: break the tie by duration. An explicit CONTEXTO_ASSUME_MULTISESSAO
  # answers the question outright and wins over git; 2+ commit days means the work
  # already spans sessions.
  if [ "$ASSUME" = "1" ]; then echo 2; return; fi
  if [ "$ASSUME" = "0" ]; then echo 1; return; fi
  if multi_day; then echo "git history spans 2+ days → multi-session" >&2; echo 2; return; fi
  if [ -t 0 ] && [ "$ASSUME_YES" != 1 ]; then
    read -r -p "will this last more than one session? (y/n) " r
    [ "$r" = "y" ] && echo 2 || echo 1
    return
  fi
  # No prompt available (agent/CI without a TTY, or --yes): default to the
  # multi-session tier. Quietly returning 1 used to drop STATUS/LEARNINGS on
  # projects that do span sessions — the case this skill exists for.
  [ "$QUIET" = 1 ] || echo "no TTY: tier 1-2 tie resolved to 2 (multi-session default); force one-shot with --tier 1 or CONTEXTO_ASSUME_MULTISESSAO=0" >&2
  echo 2
}

TIER_N="$(resolve_tier)"
[ "$QUIET" = 1 ] || [ "$JSON" = 1 ] || say "tier=$TIER_N lang=$LANG_N dir=$DIR"

copy_missing() { # src dst
  if [ -f "$2" ]; then return 0; fi
  cp "$1" "$2"
  say "created: ${2##*/}"
}

# Tier changes are accumulated instead of printed per file: six lines saying
# "tier: 2 → 3" hide the one thing that changed. Pairs are kept separately, so
# a mixed run still prints one line per pair.
TIER_FROM=""
TIER_TO=""
TIER_COUNT=0
flush_tier() {
  [ -n "$TIER_FROM" ] || return 0
  [ "$QUIET" = 1 ] || say "tier: $TIER_FROM → $TIER_TO ($TIER_COUNT files)"
  TIER_FROM=""
  TIER_TO=""
  TIER_COUNT=0
}

# Never touches `active:` — a re-run must not deactivate an ongoing TODO.
# Fresh TODO.md copies already ship with `active: false` from the template.
# No `sed -i` here: BSD/macOS sed takes the script as the backup suffix and aborts.
stamp_frontmatter() { # file tier
  local f="$1" t="$2" tmp old
  old="$(awk '/^tier: / { print substr($0, 7); exit }' "$f")"
  tmp="$(mktemp "${TMPDIR:-/tmp}/init.XXXXXX")"
  if ! sed -e "s/^updated: .*/updated: $TODAY/" -e "s/^tier: .*/tier: $t/" "$f" > "$tmp"; then
    rm -f "$tmp"; return 1
  fi
  cat "$tmp" > "$f"   # writing through the existing file keeps its permissions
  rm -f "$tmp"
  if [ -n "$old" ] && [ "$old" != "$t" ]; then
    if [ "$TIER_FROM" = "$old" ] && [ "$TIER_TO" = "$t" ]; then
      TIER_COUNT=$((TIER_COUNT + 1))
    else
      flush_tier
      TIER_FROM="$old"
      TIER_TO="$t"
      TIER_COUNT=1
    fi
  fi
}

# Stamp checked: updates the `checked:` field in frontmatter to current date.
# Only runs on successful --check (no problems), not on --json.
stamp_checked() { # ctx_dir
  local ctx="$1" f tmp
  for f in "$ctx"/MAP.md "$ctx"/STATUS.md "$ctx"/TODO.md "$ctx"/LEARNINGS.md "$ctx"/BUGS.md "$ctx"/WORKFLOW.md; do
    [ -f "$f" ] || continue
    tmp="$(mktemp "${TMPDIR:-/tmp}/init.XXXXXX")"
    if ! sed "s/^checked: .*/checked: $TODAY/" "$f" > "$tmp"; then
      rm -f "$tmp"; continue
    fi
    # If no checked: line exists, add it after updated: or tier:
    if ! grep -q '^checked:' "$f"; then
      sed -e "/^updated: /a checked: $TODAY" -e "/^tier: /a checked: $TODAY" "$f" > "$tmp"
    fi
    cat "$tmp" > "$f"
    rm -f "$tmp"
  done
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
  say "migrated ${f##*/}: added $miss (backup: ${f##*/}.bak)"
}

# The rewrite below drops every line between the start marker and its end marker.
# On an unbalanced file it would swallow the rest of the file silently, so the
# markers are checked first and a broken file is left untouched.
markers_balanced() { # file start end
  awk -v s="$2" -v e="$3" '
    index($0, s) { if (open) bad = 1; open = 1; next }
    index($0, e) { if (!open) bad = 1; open = 0; next }
    END { exit (open || bad) ? 1 : 0 }' "$1"
}

unbalanced() { # file start end
  echo "skipped ${1##*/}: unbalanced $2/$3 — fix the markers by hand; the file was NOT touched" >&2
}

# Replaces the auto block in the file with stdin content.
replace_auto() { # file
  local f="$1" tmp
  if ! markers_balanced "$f" "<!-- auto:start -->" "<!-- auto:end -->"; then
    cat > /dev/null   # drain stdin: an unread pipe would SIGPIPE the producer
    unbalanced "$f" "<!-- auto:start -->" "<!-- auto:end -->"
    return 0
  fi
  tmp="$(mktemp "${TMPDIR:-/tmp}/init.XXXXXX")"
  cat > "$tmp.body"
  awk -v body="$tmp.body" '
    /<!-- auto:start -->/ { print; while ((getline line < body) > 0) print line; close(body); skip=1; next }
    /<!-- auto:end -->/ { skip=0 }
    !skip { print }
  ' "$f" > "$tmp.new"
  mv "$tmp.new" "$f"
  rm -f "$tmp" "$tmp.body"
}

git_block() {
  echo "$L_DATE: $TODAY"
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
  skip_noise "$1" && return 0
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
      # jq's keys[] comes sorted (build, dev, …), so the first match has to win:
      # assigning unconditionally made `dev` be overwritten by `start`, while the
      # no-jq branch below prefers dev — the same project printed a different Run.
      for s in $(jq -r '.scripts // {} | keys[]' "$DIR/package.json" 2>/dev/null); do
        case "$s" in
          build) build="npm run build" ;;
          test) test_all="npm test" ;;
          lint) lint="npm run lint" ;;
          dev) [ -z "$run" ] && run="npm run dev" ;;
          start) [ -z "$run" ] && run="npm start" ;;
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
    # The scaffold's own instruction files are not project structure, and listing them
    # would make the block change on the very next run (the file is written after this
    # one) — a --check false positive.
    case "$b" in CLAUDE.md|AGENTS.md) continue ;; esac
    skip_top "$b" && continue
    printf '%s\n' "$b"
  done
  shopt -u nullglob
  echo '```'
}

# --- code index (opt-in: --index, then kept fresh on every run) ---
# A second auto block in MAP.md, `<!-- auto:start index -->`: where tables, SQL
# functions, edge functions and routes live, so a session finds them without a
# search. grep/awk only — never stale, never a graph to rebuild.
INDEX_START='<!-- auto:start index -->'
INDEX_END='<!-- auto:end index -->'

# --- context bundle (opt-in: --bundle, then kept fresh on every run) ---
# Harnesses that do not expand @imports (DSH reads AGENTS.md literally, opencode uses
# the `instructions` field) get the very files the import policy loads, verbatim.
# The truth stays in .claude/context/: this is a mirror, and --check verifies it.
BUNDLE_START='<!-- auto:start bundle -->'
BUNDLE_END='<!-- auto:end bundle -->'

# Files the import policy loads for this tier, in load order (SKILL.md §4).
wanted_sources() { # tier
  local t="$1"
  printf '%s\n' "$CTX/MAP.md"
  if [ "$t" -ge 2 ]; then
    # One path per line: callers read this line by line.
    printf '%s\n' "$CTX/STATUS.md" "$CTX/LEARNINGS.md"
    grep -qE '^active:[[:space:]]*true' "$CTX/TODO.md" 2>/dev/null && printf '%s\n' "$CTX/TODO.md"
  fi
  [ -f "$CTX/WORKFLOW.md" ] && printf '%s\n' "$CTX/WORKFLOW.md"
  return 0
}

bundle_body() { # tier
  local f
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    printf '<!-- from %s -->\n\n' "${f#"$DIR"/}"
    cat "$f"
    printf '\n\n'
  done < <(wanted_sources "$1")
}

# Adds the block with --bundle; once present, every run refreshes it. Whatever the
# user wrote in AGENTS.md outside the block is never touched.
fill_bundle() { # tier
  local agents="$DIR/AGENTS.md" tmp
  if [ -f "$agents" ] && grep -qF "$BUNDLE_START" "$agents" && ! markers_balanced "$agents" "$BUNDLE_START" "$BUNDLE_END"; then
    unbalanced "$agents" "$BUNDLE_START" "$BUNDLE_END"
    return 0
  fi
  if ! grep -qF "$BUNDLE_START" "$agents" 2>/dev/null; then
    [ "$WANT_BUNDLE" = 1 ] || return 0
    if [ -f "$agents" ]; then
      printf '\n## %s\n\n%s\n%s\n' "$L_BUNDLE_TITLE" "$BUNDLE_START" "$BUNDLE_END" >> "$agents"
    else
      printf '%s\n\n## %s\n\n%s\n%s\n' "$L_BUNDLE_HEAD" "$L_BUNDLE_TITLE" "$BUNDLE_START" "$BUNDLE_END" > "$agents"
      say "created $agents"
    fi
  fi
  tmp="$(mktemp "${TMPDIR:-/tmp}/init.XXXXXX")"
  bundle_body "$1" > "$tmp.body"
  awk -v body="$tmp.body" -v s="$BUNDLE_START" -v e="$BUNDLE_END" '
    index($0, s) { print; while ((getline line < body) > 0) print line; close(body); skip = 1; next }
    index($0, e) { skip = 0 }
    !skip { print }
  ' "$agents" > "$tmp.new"
  mv "$tmp.new" "$agents"
  rm -f "$tmp" "$tmp.body"
}

# --- opencode carrier (opt-in: --opencode, then kept fresh on every run) ---
# opencode V2 loads AGENTS.md and the `instructions` array of opencode.json; it does NOT
# read CLAUDE.md (tested against v2.3.0: a marker in CLAUDE.md was invisible, the same
# marker in AGENTS.md and in `instructions` was loaded). --bundle covers the first,
# --opencode the second. The edit is textual so JSONC comments survive, and the result is
# parsed before writing; a timestamped backup is kept.
opencode_conf() {
  local f
  for f in "$DIR/opencode.jsonc" "$DIR/opencode.json"; do
    [ -f "$f" ] && { printf '%s\n' "$f"; return 0; }
  done
  return 1
}

opencode_opted_in() {
  local conf
  conf="$(opencode_conf)" || return 1
  grep -qF '.claude/context/' "$conf" 2>/dev/null
}

# Entries of `instructions` that are missing, one per line.
# Exit: 0 complete, 1 no instructions key, 2 missing printed, 3 no file/unparsable.
opencode_inspect() { # file wanted...
  local conf="$1"; shift
  python3 - "$conf" "$@" <<'PY'
import json, os, re, sys

path, wanted = sys.argv[1], sys.argv[2:]
if not os.path.exists(path):
    sys.exit(3)
try:
    text = open(path, encoding="utf-8").read()
except OSError:
    sys.exit(3)

def strip_jsonc(s):
    out, i, n = [], 0, len(s)
    while i < n:
        c = s[i]
        if c == '"':
            j = i + 1
            while j < n:
                if s[j] == "\\": j += 2; continue
                if s[j] == '"': break
                j += 1
            out.append(s[i:j+1]); i = j + 1; continue
        if c == "/" and i + 1 < n and s[i+1] == "/":
            while i < n and s[i] != "\n": i += 1
            continue
        if c == "/" and i + 1 < n and s[i+1] == "*":
            i += 2
            while i + 1 < n and not (s[i] == "*" and s[i+1] == "/"): i += 1
            i += 2; continue
        out.append(c); i += 1
    return re.sub(r",(\s*[}\]])", r"\1", "".join(out))

try:
    data = json.loads(strip_jsonc(text))
except Exception:
    sys.exit(3)
if not isinstance(data, dict) or "instructions" not in data:
    sys.exit(1)
val = data["instructions"]
if isinstance(val, str):
    val = [val]
if not isinstance(val, list):
    sys.exit(1)
missing = [w for w in wanted if w not in val]
print("\n".join(missing))
sys.exit(2 if missing else 0)
PY
}

fill_opencode() { # tier
  local t="$1" conf f out
  conf="$(opencode_conf || true)"
  if [ -n "$conf" ]; then
    if [ "$WANT_OPENCODE" != 1 ] && ! opencode_opted_in; then return 0; fi
  else
    [ "$WANT_OPENCODE" = 1 ] || return 0
    conf="$DIR/opencode.json"
  fi
  command -v python3 >/dev/null 2>&1 || {
    echo "init.sh: --opencode needs python3 to edit JSONC safely" >&2
    return 0
  }
  local -a want=()
  while IFS= read -r f; do want+=("${f#"$DIR"/}"); done < <(wanted_sources "$t")
  if out="$(python3 - "$conf" "${want[@]}" <<'PY'
import json, os, re, shutil, sys, time

path, wanted = sys.argv[1], [w for w in sys.argv[2:] if w]
if not wanted:
    print("up to date")
    sys.exit(0)

def strip_jsonc(s):
    out, i, n = [], 0, len(s)
    while i < n:
        c = s[i]
        if c == '"':
            j = i + 1
            while j < n:
                if s[j] == "\\": j += 2; continue
                if s[j] == '"': break
                j += 1
            out.append(s[i:j+1]); i = j + 1; continue
        if c == "/" and i + 1 < n and s[i+1] == "/":
            while i < n and s[i] != "\n": i += 1
            continue
        if c == "/" and i + 1 < n and s[i+1] == "*":
            i += 2
            while i + 1 < n and not (s[i] == "*" and s[i+1] == "/"): i += 1
            i += 2; continue
        out.append(c); i += 1
    return re.sub(r",(\s*[}\]])", r"\1", "".join(out))

exists = os.path.exists(path)
text = open(path, encoding="utf-8").read() if exists else ""
if not text.strip():
    text = '{\n  "$schema": "https://opencode.ai/config.json"\n}\n'
try:
    data = json.loads(strip_jsonc(text))
except Exception as e:
    print("invalid JSONC: %s" % e, file=sys.stderr)
    sys.exit(1)

cur = data.get("instructions")
if isinstance(cur, str):
    cur = [cur]
if cur is None:
    cur = []
if not isinstance(cur, list):
    print('"instructions" is not an array', file=sys.stderr)
    sys.exit(1)
missing = [w for w in wanted if w not in cur]
if not missing:
    print("up to date")
    sys.exit(0)

def multiline(values, indent):
    body = "".join("\n%s  %s," % (indent, json.dumps(v)) for v in values).rstrip(",")
    return "[" + body + "\n" + indent + "]"

m = re.search(r'"instructions"\s*:\s*\[', text)
if m:
    start = text.index("[", m.start())
    depth, i, end = 0, start, None
    while i < len(text):
        c = text[i]
        if c == '"':
            i += 1
            while i < len(text):
                if text[i] == "\\": i += 2; continue
                if text[i] == '"': break
                i += 1
        elif c == "[":
            depth += 1
        elif c == "]":
            depth -= 1
            if depth == 0:
                end = i
                break
        i += 1
    if end is None:
        print("unterminated instructions array", file=sys.stderr)
        sys.exit(1)
    line_start = text.rfind("\n", 0, m.start()) + 1
    indent = re.match(r"[ \t]*", text[line_start:]).group(0)
    new_text = text[:start] + multiline(cur + missing, indent) + text[end+1:]
else:
    brace = text.find("{")
    if brace < 0:
        print("no JSON object", file=sys.stderr)
        sys.exit(1)
    indent = "  "
    block = '\n%s"instructions": %s' % (indent, multiline(wanted, indent))
    rest = text[brace+1:]
    empty = strip_jsonc(text).strip() in ("{}", "{ }")
    new_text = text[:brace+1] + block + ("" if empty else ",") + rest

try:
    check = json.loads(strip_jsonc(new_text))
    got = check.get("instructions")
    if isinstance(got, str):
        got = [got]
    assert isinstance(got, list) and all(w in got for w in wanted)
except Exception as e:
    print("edit would produce invalid JSONC: %s" % e, file=sys.stderr)
    sys.exit(1)

if exists:
    shutil.copy2(path, "%s.bak-%s" % (path, time.strftime("%Y%m%d-%H%M%S")))
with open(path, "w", encoding="utf-8") as fh:
    fh.write(new_text)
print("updated %s (+%d)" % (os.path.basename(path), len(missing)))
PY
  )"; then
    [ "$out" = "up to date" ] || say "$out"
  else
    echo "init.sh: could not update ${conf##*/} (left untouched)" >&2
  fi
}

# Source files, one relative path per line: tracked files in a repo, else find.
src_files() {
  local re d
  local -a prune=()
  re="(^|/)($(IFS='|'; echo "${SKIP_DIRS[*]}" | sed 's/\./\\./g')|dist|target|vendor)/"
  if [ "$IN_GIT_IDX" = 1 ]; then
    # tracked + new files not committed yet (never git-ignored ones)
    git -C "$DIR" ls-files --cached --others --exclude-standard 2>/dev/null | grep -Ev "($re)|($NOISE_RE)" || true
  else
    for d in "${SKIP_DIRS[@]}" dist target vendor; do prune+=(-name "$d" -o); done
    (cd "$DIR" && find . \( "${prune[@]}" -false \) -prune -o -type f \
      ! -name '*.bak*' ! -name '*.orig' ! -name '*~' -print 2>/dev/null | sed 's|^\./||')
  fi
}

# Prints at most $1 lines of stdin, then "… +N".
cap() { awk -v max="$1" 'NR <= max { print } END { if (NR > max) print "… +" NR - max }'; }

# SQL migrations: tables (first definition, RLS on?, policy count) and functions
# (last definition wins: a later migration redefines). Case-insensitive, POSIX awk.
sql_index() { # files...
  LC_ALL=C awk -v L_RLS="$L_IDX_RLS" -v L_NORLS="$L_IDX_NORLS" '
    function ident(s,   t) {
      sub(/^[ \t]*/, "", s)
      if (!match(s, /^[A-Za-z0-9_."]+/)) return ""
      t = tolower(substr(s, 1, RLENGTH)); gsub(/"/, "", t); sub(/^public\./, "", t)
      return t
    }
    function short(f,   n, p) { n = split(f, p, "/"); return p[n] }
    {
      l = tolower($0)
      if (pending && match(l, /^[ \t]*on[ \t]+/)) { pol[ident(substr($0, RSTART + RLENGTH))]++; pending = 0; next }
      if (match(l, /create[ \t]+(or[ \t]+replace[ \t]+)?function[ \t]+/)) {
        n = ident(substr($0, RSTART + RLENGTH)); if (n != "") { if (!(n in fn)) fo[++nf] = n; fn[n] = short(FILENAME) ":" FNR }
      } else if (match(l, /create[ \t]+table[ \t]+(if[ \t]+not[ \t]+exists[ \t]+)?/)) {
        n = ident(substr($0, RSTART + RLENGTH)); if (n != "" && !(n in tb)) { to[++nt] = n; tb[n] = short(FILENAME) ":" FNR }
      } else if (match(l, /create[ \t]+policy[ \t]/)) {
        # Name and target in one match: a policy name may itself contain " on "
        # (`create policy "select on own rows" on public.beta`) — matching the
        # first " on " attributed the count to a table that does not exist.
        if (match(l, /create[ \t]+policy[ \t]+("[^"]*"|[A-Za-z0-9_]+)[ \t]+on[ \t]+/)) pol[ident(substr($0, RSTART + RLENGTH))]++
        else pending = 1
      }
      # ALTER TABLE ... ENABLE|FORCE ROW LEVEL SECURITY, same line or the next.
      if (match(l, /alter[ \t]+table[ \t]+(if[ \t]+exists[ \t]+)?(only[ \t]+)?/)) {
        n = ident(substr($0, RSTART + RLENGTH))
        if (n != "") { alt = n
          if (l ~ /(enable|force)[ \t]+row[ \t]+level[ \t]+security/) { rls[alt] = 1; pg = 1 } }
      } else if (alt != "" && l ~ /^[ \t]*(enable|force)[ \t]+row[ \t]+level[ \t]+security/) {
        rls[alt] = 1; pg = 1
      }
    }
    END {
      for (n in pol) pg = 1
      # RLS/policy column only where the database has them (Postgres), not SQLite/D1.
      for (i = 1; i <= nt; i++) { n = to[i]
        if (pg) printf "T\t%s  %s %dp  %s\n", n, (n in rls) ? L_RLS : L_NORLS, pol[n], tb[n]
        else printf "T\t%s  %s\n", n, tb[n] }
      for (i = 1; i <= nf; i++) { n = fo[i]; printf "F\t%s  %s\n", n, fn[n] }
    }' "$@"
}

index_block() {
  local files sql edge routes code fsr out n f
  local -a sqlf=()
  IN_GIT_IDX=0
  git -C "$DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 && IN_GIT_IDX=1
  files="$(src_files)"
  echo "$L_GEN: $TODAY"

  # 1. Database: *.sql under a migrations/ dir, in name order (numbered).
  sql="$(printf '%s\n' "$files" | grep -E '(^|/)migrations/.*\.sql$' | sort || true)"
  if [ -n "$sql" ]; then
    while IFS= read -r f; do sqlf+=("$DIR/$f"); done <<< "$sql"
    out="$(sql_index "${sqlf[@]}")"
    n="$(printf '%s\n' "$sql" | wc -l | tr -d ' ')"
    echo ""
    echo "$L_IDX_TABLES ($(dirname "$(printf '%s\n' "$sql" | head -n 1)")/, $n $L_IDX_FILES):"
    printf '%s\n' "$out" | awk -F'\t' '$1 == "T" { print "- " $2 }' | cap 25
    if printf '%s\n' "$out" | grep -q '^F'; then
      echo "$L_IDX_FUNCS:"
      printf '%s\n' "$out" | awk -F'\t' '$1 == "F" { print "- " $2 }' | cap 25
    fi
  fi

  # 2. Edge/serverless functions: <supabase|netlify>/functions/<name>/index.* or the
  #    flat netlify form netlify/functions/<name>.*; each line carries file:line.
  edge="$(printf '%s\n' "$files" \
    | grep -E '^(supabase|netlify)/functions/[^_/][^/]*/index\.[jt]s$|^netlify/functions/[^_/][^/]*\.[jt]s$' \
    | sort -u || true)"
  if [ -n "$edge" ]; then
    echo ""
    echo "$L_IDX_EDGE:"
    printf '%s\n' "$edge" | awk '{
        n = split($0, p, "/"); name = p[n]
        if (name ~ /^index\./) name = p[n-1]; else sub(/\.[jt]s$/, "", name)
        print "- " name "  " $0 ":1"
      }' | cap 15
  fi

  # 3. Routes: React Router / route config `path:`, HTTP handlers (app.get('/x')),
  #    SvelteKit and Next.js app router by file path. Tests and stories skipped.
  code="$(printf '%s\n' "$files" | grep -E '\.(tsx?|jsx?|mjs)$' | grep -Ev '(\.test|\.spec|\.stories)\.|(^|/)(tests?|__tests__|e2e)/' || true)"
  routes=""
  if [ -n "$code" ]; then
    routes="$(cd "$DIR" && printf '%s\n' "$code" | tr '\n' '\0' | xargs -0 grep -HnE \
      "(<Route[^>]*[[:space:]]path=|^[[:space:]]+path=|[[:space:]{,]path:[[:space:]]*)[\"'][^\"']*[\"']|(app|router|api|route|server|fastify)\.(get|post|put|patch|delete|all)\([[:space:]]*[\"'\`]/" 2>/dev/null \
      | LC_ALL=C awk '{
          loc = $0; sub(/:[^:]*$/, "", loc)
          if (match(loc, /^[^:]*:[0-9]+/)) loc = substr(loc, 1, RLENGTH)
          line = $0; sub(/^[^:]*:[0-9]+:/, "", line)
          if (match(line, /\.(get|post|put|patch|delete|all)\([ \t]*["\047`]\/[^"\047`]*/)) {
            s = substr(line, RSTART + 1, RLENGTH - 1); m = toupper(substr(s, 1, index(s, "(") - 1))
            p = substr(s, index(s, "(") + 1); sub(/^[ \t]*["\047`]/, "", p); print m " " p "  " loc
          } else if (match(line, /path[ \t]*[:=][ \t]*\{?[ \t]*["\047][^"\047]*/)) {
            p = substr(line, RSTART, RLENGTH); sub(/^path[ \t]*[:=][ \t]*\{?[ \t]*["\047]/, "", p)
            if (p == "" || p == "*" || p ~ /^\./ || p ~ /\.[a-z]+$/) next
            print p "  " loc
          }
        }' || true)"
  fi
  fsr="$(printf '%s\n' "$files" | grep -E '(^|/)src/routes/(.*/)?\+(page\.svelte|server\.[jt]s)$|(^|/)app/(.*/)?(page|route)\.[jt]sx?$' \
    | awk '{
        # Leftmost match: a greedy ^.* anchors on the LAST "app" of the path,
        # which turned src/routes/(app)/+page.svelte into ")".
        if (!match($0, /(^|\/)(src\/routes|app)\//)) next
        p = "/" substr($0, RSTART + RLENGTH)
        sub(/\/[^\/]*$/, "", p); if (p == "") p = "/"
        print p "  " $0 ":1"
      }' || true)"
  routes="$(printf '%s\n%s\n' "$routes" "$fsr" | grep -v '^$' || true)"
  if [ -n "$routes" ]; then
    echo ""
    echo "$L_IDX_ROUTES:"
    printf '%s\n' "$routes" | awk '!seen[$0]++ { print "- " $0 }' | cap 30
  fi

  if [ -z "$sql$edge$routes" ]; then
    echo ""
    echo "$L_IDX_EMPTY"
  fi
}

# Adds the index block at the end of MAP.md with --index; once there, refreshes
# it on every run. Never touches the rest of the file.
fill_index() { # map
  local f="$1" tmp
  if grep -qF "$INDEX_START" "$f" && ! markers_balanced "$f" "$INDEX_START" "$INDEX_END"; then
    unbalanced "$f" "$INDEX_START" "$INDEX_END"
    return 0
  fi
  if ! grep -qF "$INDEX_START" "$f"; then
    [ "$WANT_INDEX" = 1 ] || return 0
    printf '\n## %s\n\n%s\n%s\n' "$L_IDX_HEAD" "$INDEX_START" "$INDEX_END" >> "$f"
  fi
  tmp="$(mktemp "${TMPDIR:-/tmp}/init.XXXXXX")"
  index_block > "$tmp.body"
  awk -v body="$tmp.body" -v s="$INDEX_START" -v e="$INDEX_END" '
    $0 == s { print; while ((getline line < body) > 0) print line; close(body); skip = 1; next }
    $0 == e { skip = 0 }
    !skip { print }
  ' "$f" > "$tmp.new"
  mv "$tmp.new" "$f"
  rm -f "$tmp" "$tmp.body"
}

ensure_claude_imports() { # tier
  local claude="$DIR/CLAUDE.md" t="$1" f
  local -a want=()
  while IFS= read -r f; do want+=("@${f#"$DIR"/}"); done < <(wanted_sources "$t")
  if [ ! -f "$claude" ]; then
    { echo "$L_HEAD"; echo ""; for w in "${want[@]}"; do echo "$w"; done; } > "$claude"
    say "created $claude"
    return
  fi
  for w in "${want[@]}"; do
    grep -qF "$w" "$claude" || echo "$w" >> "$claude"
  done
}

# --- --check: read-only report; writes nothing, exits 1 when it finds something ---
CHECK_BAD=0
CHECK_WARN=0
CHECK_MSGS=()   # "<kind>\t<text>", kept only for --json
json_esc() { sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }
emit_check() { # kind(problem|warn|hint|note) text
  local prefix="check: "
  case "$1" in
    warn) prefix="check: warn: " ;;
    hint) prefix="check: hint: " ;;
    note) prefix="check: note: " ;;
  esac
  if [ "$JSON" = 1 ]; then
    CHECK_MSGS+=("$1"$'\t'"$2")
  else
    echo "$prefix$2" >&2
  fi
}
check_fail() { CHECK_BAD=$((CHECK_BAD + 1)); emit_check problem "$*"; }
check_warn() { CHECK_WARN=$((CHECK_WARN + 1)); emit_check warn "$*"; }
check_hint() { emit_check hint "$*"; }
check_note() { emit_check note "$*"; }

# Oldest manual lines by the date written in the text (ISO AAAA-MM-DD, or DD/MM
# keyed as 0000-MM-DD so it never competes with ISO). Only used to suggest a cut.
oldest_lines() { # file
  LC_ALL=C awk '
    NR == 1 && $0 == "---" { fm = 1; next }
    fm && $0 == "---" { fm = 0; next }
    fm { next }
    /<!-- auto:start/ { s = 1 }
    /<!-- auto:end/ { s = 0; next }
    s { next }
    {
      line = $0; key = ""
      if (match(line, /[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/)) key = substr(line, RSTART, RLENGTH)
      else if (match(line, /[0-9][0-9]\/[0-9][0-9]/)) {
        d = substr(line, RSTART, RLENGTH)
        key = "0000-" substr(d, 4, 2) "-" substr(d, 1, 2)
      }
      if (key == "") next
      n++; k[n] = key; l[n] = line
    }
    END {
      for (i = 1; i <= n; i++)
        for (j = i + 1; j <= n; j++)
          if (k[j] < k[i]) {
            t = k[i]; k[i] = k[j]; k[j] = t
            t = l[i]; l[i] = l[j]; l[j] = t
          }
      m = n < 3 ? n : 3
      for (i = 1; i <= m; i++) {
        line = l[i]
        if (length(line) > 100) line = substr(line, 1, 100)
        if (i > 1) printf " | "
        printf "%s", line
      }
      if (m > 0) printf "\n"
    }' "$1"
}

budget_hint() { # base file
  local base="$1" f="$2" oldest max tag tab
  tab="$(printf '\t')"
  case "$base" in
    MAP.md|STATUS.md|TODO.md)
      oldest="$(oldest_lines "$f")"
      [ -n "$oldest" ] || oldest="(no dated lines)"
      check_hint "$base is over budget — oldest lines to cut: $oldest"
      ;;
    LEARNINGS.md)
      max="$(LC_ALL=C awk '
        NR == 1 && $0 == "---" { fm = 1; next }
        fm && $0 == "---" { fm = 0; next }
        fm { next }
        /<!-- auto:start/ { s = 1 }
        /<!-- auto:end/ { s = 0; next }
        s { next }
        match($0, /^- \[[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]\] \[/) {
          t = substr($0, RSTART + RLENGTH); sub(/\].*/, "", t); c[t]++
        }
        END {
          best = ""; b = 0
          for (t in c) if (c[t] > b) { b = c[t]; best = t }
          if (b >= 3) printf "%d\t%s\n", b, best
        }' "$f")"
      if [ -n "$max" ]; then
        tag="${max#*"$tab"}"
        max="${max%%"$tab"*}"
        check_hint "LEARNINGS.md: tag '$tag' has $max entries — promote it to .claude/context/memory/$tag.md and leave one pointer"
      fi
      ;;
  esac
}

# Warn-only, first version: a path cited in manual prose may be an example, so a
# dead link is reported but never changes the exit code.
check_prose_paths() { # file
  local file="$1" base="${1##*/}" path line target
  local seen=" |" stale_seen=" |"
  [ -f "$file" ] || return 0
  while IFS=$'\t' read -r path line; do
    [ -n "$path" ] || continue
    path="${path#./}"
    case "$path" in
      /*|~*|memory/*|*/memory/*|node_modules/*|.git/*) continue ;;
    esac
    # A context file is often cited by basename ("BUGS.md"); resolve it under
    # .claude/context/ before calling it a dead link.
    target="$DIR/$path"
    case "$path" in
      MAP.md|STATUS.md|TODO.md|LEARNINGS.md|BUGS.md|WORKFLOW.md)
        if [ ! -e "$target" ] && [ -e "$CTX/$path" ]; then target="$CTX/$path"; fi ;;
    esac
    case "$seen" in
      *"|$path|"*) ;;
      *)
        seen="$seen$path|"
        [ -e "$target" ] || check_warn "$base cites $path, which does not exist — stale link?"
        ;;
    esac
    [ -e "$target" ] || continue
    case "$stale_seen" in *"|$path|"*) continue ;; esac
    if [ -n "$(find "$target" -mtime +30 -print -quit 2>/dev/null)" ]; then
      case "$line" in
        *fonte*|*tracker*|*atual*|*doc*|*source*|*current*)
          stale_seen="$stale_seen$path|"
          check_warn "$base cites $path, not modified in 30+ days — still the source?"
          ;;
      esac
    fi
  done < <(LC_ALL=C awk '
    NR == 1 && $0 == "---" { fm = 1; next }
    fm && $0 == "---" { fm = 0; next }
    fm { next }
    /<!-- auto:start/ { s = 1 }
    /<!-- auto:end/ { s = 0; next }
    s { next }
    {
      line = $0
      gsub(/(https?|ftp):\/\/[^[:space:]]+/, " ", line)
      while (match(line, /(\.\/)?[~\/]?[A-Za-z0-9_.][A-Za-z0-9_.\/-]*\.(md|py|sh|jsonl|jsonc|json|ts|tsx|js|mjs|yml|yaml|toml|txt)/)) {
        m = substr(line, RSTART, RLENGTH)
        before = (RSTART > 1) ? substr(line, RSTART - 1, 1) : ""
        after = substr(line, RSTART + RLENGTH, 1)
        # Exact token only: "metricas.json" must not match inside "metricas.jsonl".
        if (before !~ /[A-Za-z0-9_.\/-]/ && after !~ /[A-Za-z0-9_.\/-]/) print m "\t" $0
        line = substr(line, RSTART + RLENGTH)
      }
    }' "$file")
}

# A prose queue in STATUS with no active TODO is a queue nobody reads; an
# inactive TODO with open items is worse (nobody will ever see them).
check_todo_queue() { # tier
  local t="$1" prose=0 open=0 active=0
  if [ -f "$CTX/STATUS.md" ]; then
    prose="$(LC_ALL=C awk '
      NR == 1 && $0 == "---" { fm = 1; next }
      fm && $0 == "---" { fm = 0; next }
      fm { next }
      /<!-- auto:start/ { s = 1 }
      /<!-- auto:end/ { s = 0; next }
      s { next }
      /^## / { insec = ($0 ~ /(Pendências|Bloqueios|Próxima fase|Pending|Blockers|Next phase)/); next }
      insec && /^[-*] / {
        item = $0; sub(/^[-*] /, "", item); gsub(/^[ \t]+|[ \t]+$/, "", item)
        if (item != "" && item != "-" && item != "*") n++
      }
      END { print n + 0 }' "$CTX/STATUS.md")"
  fi
  if [ -f "$CTX/TODO.md" ]; then
    grep -qE '^active:[[:space:]]*true' "$CTX/TODO.md" && active=1
    open="$(grep -cE '^- \[ \]' "$CTX/TODO.md" || true)"
    open="${open:-0}"
  fi
  if [ "$prose" -ge 3 ] && { [ ! -f "$CTX/TODO.md" ] || [ "$active" != 1 ]; }; then
    check_warn "STATUS.md has a prose queue ($prose items) but no active TODO.md — create/activate TODO.md or move the queue there"
  fi
  if [ -f "$CTX/TODO.md" ]; then
    if [ "$active" = 1 ] && [ "$open" -eq 0 ]; then
      check_warn "TODO.md is active: true but has no open items (- [ ]) — set active: false"
    elif [ "$active" != 1 ] && [ "$open" -gt 0 ]; then
      check_fail "TODO.md is active: false but has open items — activate it or drop them"
    fi
  fi
}

# One JSON object for a consumer that must not parse prose (plugin tool, CI job).
# Hand-rolled: the script cannot assume jq. `ok` mirrors the exit code.
json_report() { # tier
  local t="$1" first=1 item kind text
  printf '{"ok":%s,"tier":"%s","dir":"%s","problems":%d,"warnings":%d,"messages":[' \
    "$([ "$CHECK_BAD" = 0 ] && echo true || echo false)" \
    "$(printf '%s' "$t" | json_esc)" "$(printf '%s' "$DIR" | json_esc)" \
    "$CHECK_BAD" "$CHECK_WARN"
  for item in ${CHECK_MSGS+"${CHECK_MSGS[@]}"}; do
    kind="${item%%$'\t'*}"; text="${item#*$'\t'}"
    [ "$first" = 1 ] || printf ','
    first=0
    printf '{"kind":"%s","text":"%s"}' "$kind" "$(printf '%s' "$text" | json_esc)"
  done
  printf ']}\n'
}

check_mode() { # tier
  local t="$1" f base max n np tgt claude="$DIR/CLAUDE.md" agents="$DIR/AGENTS.md" tmp
  [ "$QUIET" = 1 ] || [ "$JSON" = 1 ] || say "check: dir=$DIR tier=$t lang=$LANG_N"
  # 1. The files this tier calls for.
  while IFS= read -r f; do
    [ -f "$f" ] || check_fail "missing ${f##*/} — tier $t calls for it (run init.sh)"
  done < <(wanted_sources "$t")
  # 2. Budgets, auto markers, placeholder dates, index block.
  for f in "$CTX"/MAP.md "$CTX"/STATUS.md "$CTX"/TODO.md "$CTX"/LEARNINGS.md "$CTX"/BUGS.md "$CTX"/WORKFLOW.md; do
    [ -f "$f" ] || continue
    base="${f##*/}"
    case "$base" in
      STATUS.md|TODO.md|MAP.md) max=60 ;;
      LEARNINGS.md) max=100 ;;
      *) max=0 ;;
    esac
    markers_balanced "$f" "<!-- auto:start -->" "<!-- auto:end -->" \
      || check_fail "$base: unbalanced auto markers — init.sh will not touch it until fixed"
    if grep -qF "$INDEX_START" "$f"; then
      markers_balanced "$f" "$INDEX_START" "$INDEX_END" || check_fail "$base: unbalanced index block"
    fi
    grep -qE '^updated:[[:space:]]*(AAAA|YYYY)-MM-DD' "$f" \
      && check_fail "$base: updated: is still the template placeholder"
    if [ "$max" -gt 0 ]; then
      n="$(awk '/<!-- auto:start/{s=1} !s{n++} /<!-- auto:end/{s=0} END{print n+0}' "$f")"
      if [ "$n" -gt "$max" ]; then
        check_fail "$base: $n lines outside auto blocks, budget $max — summarize into 1 line or delete"
        budget_hint "$base" "$f"
      fi
    fi
  done
  # 3. A prose queue without an active TODO, and paths cited in manual prose
  #    (warn-only: an example path is not a defect).
  check_todo_queue "$t"
  check_prose_paths "$CTX/MAP.md"
  check_prose_paths "$CTX/STATUS.md"
  # 4. Long-term memory: every pointer resolves, the pointer list has its own budget, and
  #    the folder is never imported (recall is on demand, via index.sh).
  if [ -f "$CTX/LEARNINGS.md" ]; then
    np="$(grep -cE '^- \[[0-9]{4}-[0-9]{2}-[0-9]{2}\] \[[^]]*\] → memory/' "$CTX/LEARNINGS.md" || true)"
    [ "${np:-0}" -le 15 ] || check_fail "LEARNINGS.md: ${np} memory pointers, budget 15 — merge topics into fewer files"
    while IFS= read -r tgt; do
      [ -n "$tgt" ] || continue
      [ -f "$CTX/$tgt" ] || check_fail "LEARNINGS.md: pointer to $tgt, which does not exist"
    done < <(grep -oE '^- \[[0-9]{4}-[0-9]{2}-[0-9]{2}\] \[[^]]*\] → memory/[^[:space:]]+' "$CTX/LEARNINGS.md" | sed 's/.*→ //' || true)
  fi
  if [ -d "$CTX/memory" ]; then
    for f in "$CTX"/memory/*.md; do
      [ -f "$f" ] || continue
      base="memory/${f##*/}"
      grep -qE '^updated:[[:space:]]*(AAAA|YYYY)-MM-DD' "$f" \
        && check_fail "$base: updated: is still the template placeholder"
      if [ -f "$claude" ]; then
        grep -qF "@.claude/context/$base" "$claude" \
          && check_fail "CLAUDE.md imports $base, which is never imported (recall via index.sh)"
      fi
    done
  fi
  # 5. Imports against the policy.
  if [ -f "$claude" ]; then
    while IFS= read -r f; do
      grep -qF "@${f#"$DIR"/}" "$claude" || check_fail "CLAUDE.md is missing the import @${f#"$DIR"/}"
    done < <(wanted_sources "$t")
    if grep -qF '@.claude/context/TODO.md' "$claude" && ! grep -qE '^active:[[:space:]]*true' "$CTX/TODO.md" 2>/dev/null; then
      check_fail "CLAUDE.md imports TODO.md while active: false — drop that line"
    fi
    grep -qF '@.claude/context/BUGS.md' "$claude" \
      && check_fail "CLAUDE.md imports BUGS.md, which is never imported (grep the error text instead)"
  fi
  # 6. Bundle freshness — only when the block exists, since the bundle is opt-in.
  if [ -f "$agents" ] && grep -qF "$BUNDLE_START" "$agents"; then
    if markers_balanced "$agents" "$BUNDLE_START" "$BUNDLE_END"; then
      tmp="$(mktemp "${TMPDIR:-/tmp}/init.XXXXXX")"
      bundle_body "$t" > "$tmp"
      if ! awk -v s="$BUNDLE_START" -v e="$BUNDLE_END" \
        'index($0, s) { p = 1; next } index($0, e) { p = 0; next } p' "$agents" | diff -q - "$tmp" >/dev/null 2>&1; then
        check_fail "AGENTS.md: bundle is stale — run init.sh to refresh it"
      fi
      rm -f "$tmp"
    else
      check_fail "AGENTS.md: unbalanced bundle block"
    fi
  fi
  # 7. Index freshness — same idea: --check cannot regenerate it, but it can say whether
  # the block still matches what the code says today.
  if [ -f "$CTX/MAP.md" ] && grep -qF "$INDEX_START" "$CTX/MAP.md"; then
    tmp="$(mktemp "${TMPDIR:-/tmp}/init.XXXXXX")"
    index_block > "$tmp"
    if ! awk -v s="$INDEX_START" -v e="$INDEX_END" \
      'index($0, s) { p = 1; next } index($0, e) { p = 0; next } p' "$CTX/MAP.md" | diff -q - "$tmp" >/dev/null 2>&1; then
      check_fail "MAP.md: code index is stale — run init.sh to refresh it"
    fi
    rm -f "$tmp"
  fi
  # 8. opencode carrier: V2 ignores CLAUDE.md, so the imports above never reach it.
  #    A project that shows opencode usage (config or .opencode/) is a hard failure;
  #    merely having the binary on PATH is a note, so CI and other harnesses stay green.
  local oc_conf oc_rc oc_hard=0 oc_soft=0 oc_visible=0 oc_instr=0 oc_bundle=0
  local -a oc_want=()
  if [ -f "$DIR/opencode.json" ] || [ -f "$DIR/opencode.jsonc" ] || [ -d "$DIR/.opencode" ]; then
    oc_hard=1
  elif command -v opencode >/dev/null 2>&1 || command -v opencodeoc >/dev/null 2>&1; then
    oc_soft=1
  fi
  if [ "$oc_hard" = 1 ] || [ "$oc_soft" = 1 ]; then
    oc_conf="$(opencode_conf || true)"
    while IFS= read -r f; do oc_want+=("${f#"$DIR"/}"); done < <(wanted_sources "$t")
    if [ -n "$oc_conf" ]; then
      if command -v python3 >/dev/null 2>&1; then
        oc_rc=0
        opencode_inspect "$oc_conf" "${oc_want[@]}" >/dev/null 2>&1 || oc_rc=$?
        [ "$oc_rc" = 0 ] && { oc_instr=1; oc_visible=1; }
      else
        # No python3: --opencode writes each path as a quoted JSON string, so a
        # literal grep is a safe fallback instead of a false "not visible".
        oc_instr=1
        for w in "${oc_want[@]}"; do
          grep -qF "\"$w\"" "$oc_conf" || oc_instr=0
        done
        if [ "$oc_instr" = 1 ]; then
          oc_visible=1
        else
          check_warn "opencode.json: cannot inspect instructions without python3 — verify them manually (or use --bundle)"
        fi
      fi
    fi
    if [ -f "$agents" ] && grep -qF "$BUNDLE_START" "$agents"; then
      oc_bundle=1
      oc_visible=1
    fi
    if [ "$oc_instr" = 1 ] && [ "$oc_bundle" = 1 ]; then
      check_warn "opencode carriers duplicate .claude/context (AGENTS.md bundle + opencode.json instructions) — pick one"
    fi
    if [ "$oc_visible" != 1 ]; then
      if [ "$oc_hard" = 1 ]; then
        if [ -n "$oc_conf" ] && [ "${oc_rc:-0}" = 2 ]; then
          check_fail "opencode.json: instructions is missing files — run init.sh --opencode"
        else
          check_fail "opencode will not see .claude/context (V2 ignores CLAUDE.md) — run init.sh --opencode or --bundle"
        fi
      else
        check_note "opencode is installed but nothing carries .claude/context to it (V2 ignores CLAUDE.md) — run init.sh --opencode or --bundle"
      fi
    fi
  fi
  if [ "$t" -lt 2 ] && [ -f "$CTX/STATUS.md" ]; then
    check_note "STATUS.md exists but the detected tier is $t — pass --tier 2 to manage it"
  fi
  if [ "$JSON" = 1 ]; then
    json_report "$t"
    [ "$CHECK_BAD" = 0 ]
    return
  fi
  if [ "$CHECK_BAD" = 0 ]; then
    if [ "$QUIET" = 1 ]; then
      if [ "$CHECK_WARN" -gt 0 ]; then say "check: ok ($CHECK_WARN warnings)"; else say "check: ok"; fi
    elif [ "$CHECK_WARN" -gt 0 ]; then
      if [ "$CHECK_WARN" = 1 ]; then
        say "check: ok — nothing missing, stale, over budget or off-policy (1 warning)"
      else
        say "check: ok — nothing missing, stale, over budget or off-policy ($CHECK_WARN warnings)"
      fi
    else
      say "check: ok — nothing missing, stale, over budget or off-policy"
    fi
    return 0
  fi
  # Stamp checked: timestamp in frontmatter of context files when check passes
  if [ "$CHECK_BAD" = 0 ] && [ "$JSON" != 1 ]; then
    stamp_checked "$CTX"
  fi
  return 0
}

# --- --dry-run: same decisions as the scaffold, zero writes ---
dry_file() { # file tier
  local f="$1" t="$2" b old
  b="${f##*/}"
  if [ ! -f "$f" ]; then
    say "would create: $b"
    return 0
  fi
  old="$(awk '/^tier: / { print substr($0, 7); exit }' "$f")"
  if [ -n "$old" ] && [ "$old" != "$t" ]; then
    say "would update: $b (tier $old → $t)"
  else
    say "untouched: $b"
  fi
}

dry_run_plan() { # tier
  local t="$1" f conf b tmp rc agents="$DIR/AGENTS.md" map="$CTX/MAP.md"
  local -a args=()
  say "dry-run: dir=$DIR tier=$t lang=$LANG_N"
  while IFS= read -r f; do
    dry_file "$f" "$t"
  done < <(wanted_sources "$t")
  if [ "$t" -ge 2 ] && [ "$WANT_TODO" = 1 ] \
     && ! { [ -f "$CTX/TODO.md" ] && grep -qE '^active:[[:space:]]*true' "$CTX/TODO.md"; }; then
    dry_file "$CTX/TODO.md" "$t"
  fi
  if [ "$t" -ge 3 ]; then
    dry_file "$CTX/BUGS.md" "$t"   # WORKFLOW.md is never created blank
  fi

  # opencode carrier: same inspection the --check uses.
  if [ "$WANT_OPENCODE" = 1 ] || opencode_opted_in; then
    conf="$(opencode_conf || true)"
    if [ -z "$conf" ]; then
      say "would create: opencode.json (instructions)"
    elif command -v python3 >/dev/null 2>&1; then
      args=()
      while IFS= read -r f; do args+=("${f#"$DIR"/}"); done < <(wanted_sources "$t")
      rc=0
      opencode_inspect "$conf" "${args[@]}" >/dev/null 2>&1 || rc=$?
      b="${conf##*/}"
      if [ "$rc" = 0 ]; then
        say "untouched: $b"
      else
        say "would update: $b (instructions)"
      fi
    else
      say "would update: ${conf##*/} (instructions)"
    fi
  fi

  # Bundle: only when opted in or the block already exists, like fill_bundle.
  if [ "$WANT_BUNDLE" = 1 ] || { [ -f "$agents" ] && grep -qF "$BUNDLE_START" "$agents"; }; then
    if [ ! -f "$agents" ]; then
      say "would create: AGENTS.md (bundle)"
    elif ! grep -qF "$BUNDLE_START" "$agents" \
       || ! markers_balanced "$agents" "$BUNDLE_START" "$BUNDLE_END"; then
      say "would update: AGENTS.md (bundle)"
    else
      tmp="$(mktemp "${TMPDIR:-/tmp}/init.XXXXXX")"
      bundle_body "$t" > "$tmp"
      if awk -v s="$BUNDLE_START" -v e="$BUNDLE_END" \
        'index($0, s) { p = 1; next } index($0, e) { p = 0; next } p' "$agents" \
        | diff -q - "$tmp" >/dev/null 2>&1; then
        say "untouched: AGENTS.md"
      else
        say "would update: AGENTS.md (bundle)"
      fi
      rm -f "$tmp"
    fi
  fi

  # Code index: same comparison as --check.
  if [ "$WANT_INDEX" = 1 ] || { [ -f "$map" ] && grep -qF "$INDEX_START" "$map"; }; then
    if [ ! -f "$map" ] || ! grep -qF "$INDEX_START" "$map" \
       || ! markers_balanced "$map" "$INDEX_START" "$INDEX_END"; then
      say "would update: MAP.md (code index)"
    else
      tmp="$(mktemp "${TMPDIR:-/tmp}/init.XXXXXX")"
      index_block > "$tmp"
      if awk -v s="$INDEX_START" -v e="$INDEX_END" \
        'index($0, s) { p = 1; next } index($0, e) { p = 0; next } p' "$map" \
        | diff -q - "$tmp" >/dev/null 2>&1; then
        say "untouched: MAP.md (code index)"
      else
        say "would update: MAP.md (code index)"
      fi
      rm -f "$tmp"
    fi
  fi
}

# --- files per tier ---
if [ "$CHECK" = 1 ]; then
  check_mode "$TIER_N" || exit 1
  exit 0
fi
if [ "$DRY_RUN" = 1 ]; then
  dry_run_plan "$TIER_N"
  exit 0
fi

copy_missing "$TPL/MAP.md" "$CTX/MAP.md"
check_format "$CTX/MAP.md" "$TPL/MAP.md"
stamp_frontmatter "$CTX/MAP.md" "$TIER_N"
map_cmd_block | replace_auto "$CTX/MAP.md"
fill_index "$CTX/MAP.md"

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
fi

# An existing STATUS.md is kept honest even when the tier drops to 1: the auto block is
# the script's, and leaving a stale date/git log there is worse than refreshing a file we
# already own. It is never created at tier 1 — copy_missing above is what creates it.
if [ -f "$CTX/STATUS.md" ]; then
  git_block | replace_auto "$CTX/STATUS.md"
fi

if [ "$TIER_N" -ge 3 ]; then
  copy_missing "$TPL/BUGS.md" "$CTX/BUGS.md"
  check_format "$CTX/BUGS.md" "$TPL/BUGS.md"
  stamp_frontmatter "$CTX/BUGS.md" "$TIER_N"   # BUGS was the one file left unstamped
  # WORKFLOW.md only if the user already has a process — never create blank.
  if [ -f "$CTX/WORKFLOW.md" ]; then
    check_format "$CTX/WORKFLOW.md" "$TPL/WORKFLOW.md"
    stamp_frontmatter "$CTX/WORKFLOW.md" "$TIER_N"
  fi
fi

ensure_claude_imports "$TIER_N"
fill_bundle "$TIER_N"
fill_opencode "$TIER_N"

flush_tier
say "---"
say "created/verified in $CTX:"
ls "$CTX" 2>/dev/null || true
say "---"
# Name only what this run manages: at tier 1 there is no STATUS.md to fill.
if [ "$TIER_N" -ge 2 ]; then
  say "left blank to complete: MAP (flows), STATUS (state/next phase)"
else
  say "left blank to complete: MAP (flows)"
fi
if [ -f "$DIR/AGENTS.md" ] && grep -qF "$BUNDLE_START" "$DIR/AGENTS.md"; then
  say "bundle refreshed: AGENTS.md — for harnesses that do not expand @imports (DSH)"
fi
oc_conf="$(opencode_conf || true)"
if [ -n "$oc_conf" ] && grep -qF '.claude/context/' "$oc_conf" 2>/dev/null; then
  say "opencode carrier: $(basename "$oc_conf") instructions — opencode V2 ignores CLAUDE.md"
fi
# Report the REAL flag, not a guess: a re-run over an ongoing TODO used to
# print "active: false" while the file said true, which reads as if the script
# had just deactivated it (it never touches `active:` — see copy_missing).
if [ "$TIER_N" -ge 2 ] && [ -f "$CTX/TODO.md" ]; then
  if grep -qE '^active:[[:space:]]*true' "$CTX/TODO.md"; then
    say "TODO is active: true — set it back to false when the queue empties."
  else
    say "TODO is active: false — enable for a 3+ step task."
    if grep -qF "@.claude/context/TODO.md" "$DIR/CLAUDE.md" 2>/dev/null; then
      say "CLAUDE.md still imports TODO.md — drop that line while it is inactive."
    fi
  fi
elif [ "$TIER_N" -ge 2 ]; then
  say "no TODO.md — rerun with --todo for a 3+ step task without an issue tracker."
fi
