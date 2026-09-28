#!/usr/bin/env bash
# init.sh — esqueleto de contexto em 3 tiers, sem gastar token.
# Uso: init.sh [--tier auto|1|2|3] [--dir PROJETO] [--yes]
# Só cria o que falta; nunca sobrescreve conteúdo manual.
# Blocos <!-- auto:start --> … <!-- auto:end --> pertencem ao script.
set -euo pipefail

TIER="auto"
DIR="."
ASSUME="${CONTEXTO_ASSUME_MULTISESSAO:-}"

usage() {
  echo "uso: init.sh [--tier auto|1|2|3] [--dir DIR] [--yes]"
  echo "  --yes  não pergunta nada (auto decide 1 sessão p/ tier 1-2)"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --tier) TIER="${2:-auto}"; shift 2 ;;
    --dir) DIR="${2:-.}"; shift 2 ;;
    --yes) ASSUME="0"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "arg desconhecido: $1" >&2; usage; exit 1 ;;
  esac
done

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TPL="$SKILL_DIR/templates"
CTX="$DIR/.claude/context"
TODAY="$(date +%F)"

mkdir -p "$CTX"

nfiles() {
  if [ -d "$DIR/.git" ] && command -v git >/dev/null 2>&1; then
    git -C "$DIR" ls-files 2>/dev/null | wc -l
  else
    find "$DIR" -type f -not -path "$DIR/.git/*" -not -path "$DIR/.claude/*" -not -path "*/node_modules/*" 2>/dev/null | wc -l
  fi
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
  # <20 arquivos: desempata por duração
  if [ "$ASSUME" = "1" ]; then echo 2; return; fi
  if [ "$ASSUME" = "0" ]; then echo 1; return; fi
  if [ -t 0 ]; then
    read -r -p "vai durar mais de uma sessão? (s/n) " r
    [ "$r" = "s" ] && echo 2 || echo 1
  else
    echo 1
  fi
}

TIER_N="$(resolve_tier)"
echo "tier=$TIER_N dir=$DIR"

copy_missing() { # src dst
  [ -f "$2" ] || cp "$1" "$2"
}

stamp_frontmatter() { # file tier
  local f="$1" t="$2"
  if grep -q '^updated:' "$f"; then
    sed -i "s/^updated: .*/updated: $TODAY/" "$f"
  fi
  if grep -q '^tier:' "$f"; then
    sed -i "s/^tier: .*/tier: $t/" "$f"
  fi
  if grep -q '^active:' "$f"; then
    sed -i "s/^active: .*/active: false/" "$f"
  fi
}

# Substitui o bloco auto no arquivo pelo conteúdo do stdin.
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
  if [ -d "$DIR/.git" ]; then
    git -C "$DIR" log --oneline -15 2>/dev/null || echo "(sem commits)"
    echo "--- status ---"
    git -C "$DIR" status --short 2>/dev/null || true
  else
    echo "(sem git)"
  fi
  echo '```'
}

map_cmd_block() {
  echo "gerado em: $TODAY"
  echo ""
  echo "| Ação | Comando |"
  echo "|---|---|"
  local build="" test_all="" test_one="" lint="" run=""
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
  [ -f "$DIR/Makefile" ] && [ -z "$build" ] && grep -Eq '^(build|all):' "$DIR/Makefile" && build="make build"
  [ -f "$DIR/Cargo.toml" ] && { [ -z "$build" ] && build="cargo build"; [ -z "$test_all" ] && test_all="cargo test"; }
  [ -f "$DIR/pyproject.toml" ] && [ -z "$test_all" ] && test_one="pytest -q <arquivo>" && test_all="pytest -q"
  echo "| Build | $build |"
  echo "| Teste (tudo) | $test_all |"
  echo "| Teste (um só) | $test_one |"
  echo "| Lint/format | $lint |"
  echo "| Rodar | $run |"
  echo ""
  echo "primeiro nível:"
  echo ""
  echo '```'
  ls -1 "$DIR" 2>/dev/null | grep -v -E '^(\.git|\.claude|node_modules|target|__pycache__)$' || true
  echo '```'
}

ensure_claude_imports() { # tier
  local claude="$DIR/CLAUDE.md" t="$1"
  local -a want=("@.claude/context/MAP.md")
  if [ "$t" -ge 2 ]; then
    want+=("@.claude/context/STATUS.md" "@.claude/context/TODO.md" "@.claude/context/LEARNINGS.md")
  fi
  [ -f "$DIR/.claude/context/WORKFLOW.md" ] && want+=("@.claude/context/WORKFLOW.md")
  if [ ! -f "$claude" ]; then
    { echo "# Projeto"; echo ""; for w in "${want[@]}"; do echo "$w"; done; } > "$claude"
    echo "criado $claude"
    return
  fi
  for w in "${want[@]}"; do
    grep -qF "$w" "$claude" || echo "$w" >> "$claude"
  done
}

# --- arquivos por tier ---
copy_missing "$TPL/MAP.md" "$CTX/MAP.md"
stamp_frontmatter "$CTX/MAP.md" "$TIER_N"
map_cmd_block | replace_auto "$CTX/MAP.md"

if [ "$TIER_N" -ge 2 ]; then
  copy_missing "$TPL/STATUS.md" "$CTX/STATUS.md"
  copy_missing "$TPL/TODO.md" "$CTX/TODO.md"
  copy_missing "$TPL/LEARNINGS.md" "$CTX/LEARNINGS.md"
  stamp_frontmatter "$CTX/STATUS.md" "$TIER_N"
  stamp_frontmatter "$CTX/TODO.md" "$TIER_N"
  stamp_frontmatter "$CTX/LEARNINGS.md" "$TIER_N"
  git_block | replace_auto "$CTX/STATUS.md"
fi

if [ "$TIER_N" -ge 3 ]; then
  copy_missing "$TPL/BUGS.md" "$CTX/BUGS.md"
  # WORKFLOW.md só se o usuário já tiver processo — não criar vazio.
  [ -f "$CTX/WORKFLOW.md" ] && stamp_frontmatter "$CTX/WORKFLOW.md" "$TIER_N" || true
fi

ensure_claude_imports "$TIER_N"

echo "---"
echo "criados/verificados em $CTX:"
ls "$CTX"
echo "---"
echo "em branco p/ completar: MAP (fluxos), STATUS (estado/próxima fase)"
[ "$TIER_N" -ge 2 ] && echo "TODO está active: false — ativar quando houver tarefa de 3+ passos."
