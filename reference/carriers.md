# Carrier reference (detail from SKILL.md §4)

This file contains the full carrier documentation moved from SKILL.md.

---

## Import policy per harness

| Harness | Mechanism | Notes |
|---------|-----------|-------|
| **Claude Code** | `@path` imports in root `CLAUDE.md` | Expands imports automatically |
| **DSH** | Reads `AGENTS.md`/`CLAUDE.md` literally | Does **not** interpret `@path` — source: `dsh-agent-instructions` README |
| **opencode V2** | Reads `AGENTS.md` + `instructions` array in `opencode.json` | **Ignores `CLAUDE.md`** (tested on v2.3.0) |

---

## Carriers for opencode

Since opencode ignores `CLAUDE.md`, you need one of these carriers:

### 1. `--bundle` (AGENTS.md mirror)

- Creates/updates `<!-- auto:start bundle -->`…`<!-- auto:end bundle -->` block in `AGENTS.md`
- Contains the exact files the import policy loads (verbatim):
  - MAP always
  - STATUS + LEARNINGS at tier 2+
  - TODO while `active: true`
  - WORKFLOW if it exists
- Each file preceded by `<!-- from .claude/context/X.md -->`
- Without flag/block → nothing created; once present, refreshed every run
- User text outside block never touched
- On existing `AGENTS.md`: appends its section; on create: writes header saying truth lives in `.claude/context/` and `--check` verifies the bundle

### 2. `--opencode` (instructions array)

- Writes the same file list into `instructions` array of `opencode.json` (or `opencode.jsonc`)
- Opt-in, backup on edit, JSONC comments preserved
- Once added, refreshed every run
- **Pick one**: both carriers duplicate the same files in the prompt and cost tokens; `--check` warns when it sees both

---

## Import policy summary

| File | Tier 1 | Tier 2+ | Tier 3 |
|------|--------|---------|--------|
| `MAP.md` | ✅ always | ✅ | ✅ |
| `STATUS.md` | ❌ | ✅ | ✅ |
| `LEARNINGS.md` | grep only | ✅ | ✅ |
| `TODO.md` | ❌ | active: true only | active: true only |
| `BUGS.md` | ❌ | ❌ | never imported (grep error text) |
| `WORKFLOW.md` | ❌ | ❌ | if exists |
| `memory/` | ❌ | never imported | never imported |

---

## Recall for non-imported files

- `BUGS.md`, `memory/*.md`, large `LEARNINGS*.md`: use `scripts/index.sh` before reading/grepping blind
- No args → table of contents (entries per section, verdict counts, line numbers)
- `index.sh TERM...` → matching **entries** (whole multi-line, one line each, newest first)
- `-x` → only `[✗]` (tried and rejected)
- Printed fresh on every call, never saved → can't go stale
- Exact error text → `grep` on `BUGS.md`

---

## Cold tier: `memory/`

- Never imported, never bundled
- Only pointers live in `LEARNINGS.md` (which is imported)
- Accessed on demand via `index.sh`

---

## Windows paths

Run scripts through `scripts/win/ctx.mjs`:
```bash
node <skill>/scripts/win/ctx.mjs init.sh --tier auto --dir C:\repo
```

- Execs script directly on POSIX, via WSL bash on Windows
- Translates Windows paths in arguments
- opencode plugin uses same launcher, counts budget lines in JS
- `install.sh` installs copies (not symlinks, which need elevated shell)