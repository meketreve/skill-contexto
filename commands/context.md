---
description: Bootstrap lean project context in 3 tiers (MAP/STATUS/TODO/LEARNINGS) with a zero-token script scaffold
---

# /context — $ARGUMENTS

<!-- Alias of contexto.md (same instructions, English name). Keep both files in sync. -->

1. Run the zero-token scaffold (path of the installed skill; adjust if different):
```bash
~/.config/opencode/skills/contexto/scripts/init.sh --tier auto $ARGUMENTS
# claude code: ~/.claude/skills/contexto/scripts/init.sh --tier auto $ARGUMENTS
```
Accepts `--tier 1|2|3` to force, `--lang en|pt`, and `--yes` to never prompt.

2. With the script output in hand, fill in ONLY what needs judgment (`contexto` skill `SKILL.md` rules, in the user's language):
- `MAP.md`: `X → Y → Z` flows, the non-obvious. Commands were already extracted.
- `STATUS.md`: current state (2–4 lines) + next phase with entry point.
- `TODO.md`: set (`active: true`) only for a 3+ step task without tracker.
- `LEARNINGS.md`: one line per fact `- [YYYY-MM-DD] [tag] fact — consequence`.

3. Never edit `<!-- auto:start -->` blocks; never create a file the tier doesn't call for; respect budgets, counted outside auto blocks (STATUS/TODO/MAP 60, LEARNINGS 100).

4. Finish by listing what was created and what was left blank.
