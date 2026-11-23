# Budget reference (detail from SKILL.md §5)

This file contains the full budget documentation moved from SKILL.md.

---

## Budget limits

| File | Limit | Notes |
|------|-------|-------|
| `STATUS.md` | 60 lines | |
| `TODO.md` | 60 lines | |
| `MAP.md` | 60 lines | |
| `LEARNINGS.md` | 100 lines | |
| Memory pointer list | 15 lines | Inside `LEARNINGS.md` under `## Long-term memory` |

**Counted outside `<!-- auto:start -->…<!-- auto:end -->` blocks** — the auto block is the script's, so it neither counts nor gets trimmed by hand. (`BUGS.md` and `WORKFLOW.md` have no budget in `--check`.)

---

## Measuring budget

```bash
# Manual count (lines outside auto blocks)
awk '/<!-- auto:start/{s=1} !s{n++} /<!-- auto:end/{s=0} END{print n+0}' FILE

# Or let --check measure it for you
init.sh --check
```

---

## Over budget actions

| File | Action |
|------|--------|
| `LEARNINGS.md` | **Promote whole tag to `memory/` first** (see §3) — only then summarize into 1 line or delete. `[✗]` lines are never deleted; they travel to `memory/` with their entry. A `[↻]` line left behind shrinks to its gist. |
| Other files (`STATUS`, `TODO`, `MAP`) | Summarize into 1 line or delete — `git log` is the source of truth. |

---

## `--check` over-budget behavior

`--check` does not just count — over budget it:
- Lists the **3 oldest dated lines** to cut
- For `LEARNINGS.md`, names the **tag with the most entries** to promote to `memory/`
- The decision stops being guesswork

---

## Budget counting details

- **Counted outside auto blocks only** — `<!-- auto:start -->`…`<!-- auto:end -->` are script-owned
- Auto blocks are **never trimmed by hand** — they belong to the script
- `BUGS.md` and `WORKFLOW.md` have **no budget limit** in `--check`
- Memory pointer list has its own **15-line budget** (past it, merge topics)

---

## Auto block markers

- `<!-- auto:start -->`…`<!-- auto:end -->` — main auto block (script-owned)
- `<!-- auto:start index -->`…`<!-- auto:end index -->` — code index block (opt-in with `--index`)
- `<!-- auto:start bundle -->`…`<!-- auto:end bundle -->` — AGENTS.md bundle block (opt-in with `--bundle`)

**Unbalanced auto block (no `end`):** script warns and **does not touch the file** (`skipped FILE: unbalanced ...`), instead of deleting everything from the marker to EOF. Applies to all three block types.

---

## Measuring manually

```bash
# Count manual lines outside auto blocks
awk '/<!-- auto:start/{s=1} !s{n++} /<!-- auto:end/{s=0} END{print n+0}' FILE

# --check does this for you and exits 1 if over budget
init.sh --check
```