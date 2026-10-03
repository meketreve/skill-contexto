#!/usr/bin/env bash
# index.sh — compact, on-demand index of what the project learned (zero tokens to build).
# Usage: index.sh [--dir PROJECT] [-x] [-n N] [-l] [TERM...]
#   no args   table of contents: entries per file and per section, with verdict counts
#   TERM...   entries whose WHOLE text (all its lines) contains every term, one line each,
#             newest first — grep finds lines, this finds entries
#   -x        only entries marked [✗] (tried and rejected)
#   -l        list every entry (same as a search that matches all)
#   -n N      cap the listing (default 20; 0 = no cap)
# Reads .claude/context/LEARNINGS*.md and BUGS*.md. Never writes anything: printed fresh
# on every call, so it can't go stale the way a saved index does.
# An entry is a `- [YYYY-MM-DD] …` bullet (with its continuation lines), any other top-level
# bullet, or a `## YYYY-MM-DD …` heading block (BUGS). Other headings are sections.
# Case-insensitive for ASCII only: accented capitals must match as written.
set -euo pipefail
# Byte semantics in every awk (mawk, gawk): same results everywhere, and cut() never splits UTF-8.
export LC_ALL=C

DIR="."
REJ=0
ALL=0
CAP=20
TERMS=""

while [ $# -gt 0 ]; do
  case "$1" in
    --dir) DIR="${2:-.}"; shift 2 ;;
    -x) REJ=1; shift ;;
    -l) ALL=1; shift ;;
    -n) CAP="${2:-20}"; shift 2 ;;
    -h|--help) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) TERMS="$TERMS${TERMS:+ }$1"; shift ;;
  esac
done

CTX="$DIR/.claude/context"
shopt -s nullglob
FILES=("$CTX"/LEARNINGS*.md "$CTX"/BUGS*.md)
shopt -u nullglob
if [ "${#FILES[@]}" -eq 0 ]; then
  echo "no LEARNINGS*.md or BUGS*.md in $CTX" >&2
  exit 1
fi

MODE="toc"
{ [ -n "$TERMS" ] || [ "$REJ" = 1 ] || [ "$ALL" = 1 ]; } && MODE="list"

# One record per entry: date \t file:line \t section \t verdict \t summary \t text
entries() {
  awk -v OFS='\t' '
    function flush() {
      if (kind != "") print (date == "" ? "0000-00-00" : date), fname ":" start, sect, verdict(text), summ, tolower(text)
      kind = ""; text = ""
    }
    function verdict(t,   g) {
      # only in the leading [date] [tag] [verdict] run — a ✗ quoted later in the text is not one
      sub(/^- +/, "", t)
      while (match(t, /^\[[^]]*\] */)) {
        g = substr(t, 1, RLENGTH); sub(/ +$/, "", g)
        if (g == "[✗]" || g == "[✓]") return substr(g, 2, length(g) - 2)
        if (index(g, "[↻") == 1) return "↻"
        t = substr(t, RLENGTH + 1)
      }
      return ""
    }
    function summary(s,   b, e) {
      # leading [tags] stay; a **bold title** stands for the whole entry
      b = ""
      while (match(s, /^\[[^]]*\] */)) { b = b substr(s, 1, RLENGTH); s = substr(s, RLENGTH + 1) }
      if (substr(s, 1, 2) == "**") {
        e = index(substr(s, 3), "**")
        if (e > 0) s = substr(s, 3, e - 1)
      }
      return b s
    }
    FNR == 1 { flush(); fname = FILENAME; sub(/.*\//, "", fname); sect = ""; inc = 0 }
    /^<!--/ { inc = 1 }
    inc { if (/-->/) inc = 0; next }
    /^#+ / {
      flush()
      h = $0; sub(/^#+ +/, "", h)
      if ($0 ~ /^## [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/) {
        kind = "head"; start = FNR; date = substr(h, 1, 10)
        s = substr(h, 11); sub(/^[ —–-]+/, "", s); summ = summary(s); text = h
      } else sect = h
      next
    }
    kind == "head" { text = text " " $0; next }
    /^- \[(AAAA|YYYY)-/ { flush(); next } # template placeholder, not an entry
    /^- / {
      flush()
      kind = "bullet"; start = FNR; s = substr($0, 3); date = ""
      if (s ~ /^\[[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]\]/) { date = substr(s, 2, 10); s = substr(s, 13); sub(/^ +/, "", s) }
      summ = summary(s); text = $0
      next
    }
    /^[ \t]*$/ { if (kind == "bullet") flush(); next }
    kind == "bullet" && /^[ \t]/ { text = text " " $0; next }
    { if (kind == "bullet") flush() }
    END { flush() }
  ' "${FILES[@]}"
}

if [ "$MODE" = "toc" ]; then
  entries | awk -F '\t' '
    BEGIN { split("✓ ✗ ↻", vs, " ") }
    { split($2, a, ":"); f = a[1]
      if (!(f in nf)) order[++nfiles] = f
      nf[f]++
      k = f SUBSEP $3
      if (!(k in ns)) { sorder[f, ++nsec[f]] = $3; sline[k] = a[2] }
      ns[k]++
      if ($4 != "") nv[k, $4]++ }
    END {
      for (i = 1; i <= nfiles; i++) {
        f = order[i]; print f " — " nf[f] " entries"
        for (j = 1; j <= nsec[f]; j++) {
          s = sorder[f, j]; k = f SUBSEP s; v = ""
          for (m = 1; m <= 3; m++) { t = vs[m]; if (nv[k, t]) v = v (v == "" ? "" : " ") t nv[k, t] }
          printf "  L%-5s %s — %d%s\n", sline[k], (s == "" ? "(no section)" : s), ns[k], (v == "" ? "" : " (" v ")")
        }
      }
      if (nfiles == 0) print "no entries yet"
      print "search: index.sh TERM...   rejected: index.sh -x   all: index.sh -l"
    }'
  exit 0
fi

entries | awk -F '\t' -v terms="$TERMS" -v rej="$REJ" '
  BEGIN { n = split(tolower(terms), t, " ") }
  rej == 1 && $4 != "✗" { next }
  { for (i = 1; i <= n; i++) if (!index($6, t[i])) next
    print }
' | sort -t "$(printf '\t')" -k1,1r -s | awk -F '\t' -v cap="$CAP" '
  function cut(s, w) {
    if (length(s) <= w) return s
    # byte-based awk: back off so a multi-byte character is never split
    while (w > 0 && substr(s, w + 1, 1) ~ /^[\200-\277]/) w--
    return substr(s, 1, w) "…"
  }
  { total++
    if (cap > 0 && total > cap) next
    d = ($1 == "0000-00-00" ? "          " : $1)
    printf "%-26s %s  %s\n", $2, d, cut($5, 110) }
  END {
    if (total == 0) print "no entry matches"
    else if (cap > 0 && total > cap) print "… +" (total - cap) " more (-n 0 shows all)"
  }'
