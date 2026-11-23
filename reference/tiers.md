# Tier reference (detail from SKILL.md §1)

This file contains the full tier documentation moved from SKILL.md to keep the skill file focused on the core contract.

---

## Tier detection

Run the script with auto-detection:

```bash
<skill-dir>/scripts/init.sh --tier auto
```

Add `--dir PROJECT` to scaffold a project other than the current directory.
Add `--lang en` for English templates (`templates.en/`); default `auto` follows `$LANG` (`pt*` → PT-BR `templates/`, else English), overridable via `CONTEXTO_LANG`.

---

## Tier rules

| Tier | Files | Description |
|------|-------|-------------|
| **1 — light/one-shot** | `MAP.md` only | <20 files, one-shot tasks |
| **2 — medium/multi-session** | `MAP.md`, `STATUS.md`, `LEARNINGS.md`, `TODO.md` (with `--todo`) | 20–200 files, multi-session |
| **3 — large/monorepo/team** | All tier 2 + `BUGS.md` (always), `WORKFLOW.md` (if process adopted), `TODO.md` (with `--todo`) | >200 files, monorepo, team |

**No per-package TODO** — single project-wide TODO.md.

---

## Tier 1–2 tie resolution

- `CONTEXTO_ASSUME_MULTISESSAO=1` forces tier 2, `=0` forces tier 1; both win over git.
- Commits on 2+ distinct days → tier 2.
- With no TTY (agent/CI) or with `--yes`: **does not ask**, goes to tier 2 with warning on stderr:
  ```
  no TTY: tier 1-2 tie resolved to 2 (multi-session default); force one-shot with --tier 1 or CONTEXTO_ASSUME_MULTISESSAO=0
  ```
- `--yes` no longer means "assume one-shot".
- Invalid options: `--tier 7`, `--lang xx` → error; missing value → `usage` + exit 1.

---

## File creation rules

- Never create a file the tier doesn't call for. Deciding **not** to create is part of the job.
- `init.sh` only creates missing files, never overwrites manual content.
- Auto blocks (`<!-- auto:start -->`…`<!-- auto:end -->`) are filled by the script; never edit them by hand.

---

## File detection logic

The script counts files, skipping tool/build dirs:
- `_bmad/`, `.agent/`, `node_modules/`, `build/`
- Detects monorepos (multiple packages with their own configs)
- Uses git history for tier 1–2 tie (commits on 2+ days)

---

## Tier-specific details

### Tier 1
- Minimal `MAP.md` only
- One-shot tasks, <20 files

### Tier 2
- Adds `STATUS.md` + `LEARNINGS.md`
- `TODO.md` only with `--todo` (for 3+ step task without issue tracker)
- 20–200 files, multi-session

### Tier 3
- Always includes `BUGS.md`
- `WORKFLOW.md` if a process was adopted
- `TODO.md` only with `--todo`
- No per-package TODO — single project-wide TODO.md

---

## Migration

- Old format (no frontmatter or missing auto block): script warns `old format:` and does not create missing parts.
- Rerun with `--migrate` to add template frontmatter + auto block, keeping text (backup in `FILE.bak`).