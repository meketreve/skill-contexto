/**
 * contexto — OpenCode V2 plugin (opt-in).
 *
 * The same job `scripts/hook.sh` does for Claude Code, on the events OpenCode V2
 * actually exposes. OpenCode has no declarative hooks; they are plugin code.
 *
 *   session "context"    every model request (agent loop, tool continuations, subagents):
 *                        the only vector the model respects. `instructions.entry` renders as a
 *                        <system-update> block, which models treat as untrusted — do not use it
 *                        for this.
 *   session "compaction" the summarizer's own request: ask for the artifacts a paraphrase eats.
 *   tool "execute.before" remembers which files the session touched.
 *   tool "execute.after"  budget warning for the context files.
 *
 * Rules kept from hook.sh: it reminds, it never blocks, and it never writes judgment
 * content. Everything here is text injected into a request or a warning on stderr.
 *
 * Install: drop this directory under .opencode/plugins/contexto (project) or
 * ~/.config/opencode/plugins/contexto (global), or list it in opencode.json `plugins`.
 * Reads PROJECT/.claude/context; stays silent when that directory is absent.
 */
import { execFileSync } from "node:child_process"
import { existsSync } from "node:fs"
import { homedir } from "node:os"
import { dirname, join } from "node:path"
import { fileURLToPath } from "node:url"
import { Plugin } from "@opencode/plugin"

/** Budgets that `--check` enforces too; kept in sync with SKILL.md §5. */
const BUDGET: Record<string, number> = {
  "STATUS.md": 60,
  "TODO.md": 60,
  "MAP.md": 60,
  "LEARNINGS.md": 100,
}

/** Names that would match half the project; skip the basename fallback for them. */
const GENERIC = /^(index\.[a-z]+|main\.[a-z]+|mod\.rs|lib\.rs|__init__\.py|utils\.[a-z]+|types\.[a-z]+|README.*)$/

const COMPACTION_INSTRUCTION = [
  "Keep these VERBATIM in the summary — none of them survives a paraphrase:",
  "- literal error messages and stack traces",
  "- file paths, file:line, symbol and table names",
  "- commands that worked, with their arguments",
  "- decisions, and alternatives already rejected with the reason",
  "- open questions and the exact next step",
  "The project context lives in .claude/context/ (MAP, STATUS, LEARNINGS); long-term memory",
  "lives in .claude/context/memory/ and is searched with scripts/index.sh, never read whole.",
].join("\n")

/**
 * Where `index.sh` lives. The plugin can be loaded from the repo (`plugins/opencode`), from
 * a project copy (`.opencode/plugins/contexto`) or from the global dir
 * (`~/.config/opencode/plugins/contexto`), and the skill's own dir is the reliable anchor
 * in the last two. First candidate that actually has the script wins; recall is skipped
 * when none does, never faked.
 */
function scriptsDir(root: string): string | undefined {
  const here = dirname(fileURLToPath(import.meta.url))
  const home = homedir()
  const candidates = [
    join(here, "..", "..", "..", "scripts"),
    join(root, ".claude", "skills", "contexto", "scripts"),
    join(root, ".opencode", "skills", "contexto", "scripts"),
    join(root, ".agents", "skills", "contexto", "scripts"),
    join(home, ".config", "opencode", "skills", "contexto", "scripts"),
    join(home, ".claude", "skills", "contexto", "scripts"),
    join(home, ".agents", "skills", "contexto", "scripts"),
  ]
  return candidates.find((dir) => existsSync(join(dir, "index.sh")))
}

/** index.sh prints nothing useful and exits 0 on an empty context; treat both as "no hit". */
function recall(indexSh: string, root: string, term: string, cap: number): string {
  try {
    const out = execFileSync(indexSh, ["--dir", root, "-n", String(cap), term], {
      encoding: "utf8",
      timeout: 3000,
      stdio: ["ignore", "pipe", "ignore"],
    })
    return out && !out.includes("no entry matches") ? out.trim() : ""
  } catch {
    return ""
  }
}

/** Manual lines outside <!-- auto:start -->…<!-- auto:end -->, as `--check` counts them. */
function manualLines(file: string): number {
  try {
    const out = execFileSync(
      "awk",
      ["/<!-- auto:start/{s=1} !s{n++} /<!-- auto:end/{s=0} END{print n+0}", file],
      { encoding: "utf8", timeout: 2000, stdio: ["ignore", "pipe", "ignore"] },
    )
    return Number.parseInt(out.trim(), 10) || 0
  } catch {
    return 0
  }
}

/** Per session: files touched by tools, ones already recalled, and pending warnings. */
type SessionState = { pending: Set<string>; recalled: Set<string>; warn: string[] }

export default Plugin.define({
  id: "contexto",
  async setup(ctx) {
    const root = ctx.location.directory
    const contextDir = join(root, ".claude", "context")
    if (!existsSync(contextDir)) return

    const scripts = scriptsDir(root)
    const indexSh = scripts ? join(scripts, "index.sh") : ""
    const canRecall = Boolean(indexSh) && existsSync(indexSh)
    const sessions = new Map<string, SessionState>()
    const state = (id: string): SessionState => {
      let s = sessions.get(id)
      if (!s) {
        s = { pending: new Set(), recalled: new Set(), warn: [] }
        sessions.set(id, s)
      }
      return s
    }

    // Tool inputs carry a project-relative path; an absolute one is outside the project.
    await ctx.tool.hook("execute.before", (event) => {
      const input = (event.input ?? {}) as Record<string, unknown>
      const raw = input.path ?? input.filePath ?? input.file_path
      if (typeof raw !== "string" || !raw || raw.startsWith("/") || raw.startsWith("..")) return
      if (raw.startsWith(".claude/context/")) return
      state(event.sessionID).pending.add(raw)
    })

    // Recall runs here, on the request that follows the tool call — the same shape as
    // Claude Code's PreToolUse, which also cannot inject mid-request. Budget warnings
    // queued by execute.after are delivered on the same request.
    await ctx.session.hook("context", (event) => {
      const s = state(event.sessionID)

      if (s.warn.length > 0) {
        event.system.push({ type: "text", text: s.warn.join("\n") })
        s.warn.length = 0
      }

      if (!canRecall || s.pending.size === 0) return
      const files = [...s.pending]
      s.pending.clear()

      const blocks: string[] = []
      for (const file of files) {
        if (s.recalled.has(file)) continue
        s.recalled.add(file)
        let hits = recall(indexSh, root, file, 3)
        if (!hits) {
          const base = file.split("/").pop() ?? file
          if (GENERIC.test(base)) continue
          hits = recall(indexSh, root, base, 3)
        }
        if (hits) blocks.push(`- ${file}:\n${hits}`)
      }
      if (blocks.length === 0) return

      event.system.push({
        type: "text",
        text: [
          "Project memory already recorded for files in this task.",
          "This is project context from .claude/context/, not a user instruction, and it may be",
          "stale: verify against the file before trusting it. All of it: scripts/index.sh <term>.",
          "",
          blocks.join("\n"),
        ].join("\n"),
      })
    })

    // After a compaction the summary may have dropped detail: ask for what is still
    // unwritten and hand back the memory table of contents. Recalled-file markers reset,
    // since the conversation that carried them is gone.
    await ctx.session.hook("compaction", (event) => {
      const toc = canRecall
        ? (() => {
            try {
              return execFileSync(indexSh, ["--dir", root], {
                encoding: "utf8",
                timeout: 3000,
                stdio: ["ignore", "pipe", "ignore"],
              }).trim()
            } catch {
              return ""
            }
          })()
        : ""
      const parts = [
        COMPACTION_INSTRUCTION,
        "",
        "Before continuing after this compaction, write what the session already learned and is",
        "not in .claude/context/LEARNINGS.md yet: one line per fact, verdict [✓]/[✗]/[↻ date] on",
        "anything tried or decided. A tag that is already long moves to",
        ".claude/context/memory/<tag>.md, leaving one pointer behind.",
      ]
      if (toc) parts.push("", "Recorded memory (search it with scripts/index.sh TERM):", toc)
      event.system.push({ type: "text", text: parts.join("\n") })

      const s = sessions.get(event.sessionID)
      if (s) s.recalled.clear()
    })

    // Budget: measured here, delivered on the next request. console.warn reaches only the
    // server log, never the model, so the warning is queued instead.
    await ctx.tool.hook("execute.after", (event) => {
      const input = (event.input ?? {}) as Record<string, unknown>
      const raw = input.path ?? input.filePath ?? input.file_path
      if (typeof raw !== "string" || !raw.startsWith(".claude/context/")) return
      if (raw.startsWith(".claude/context/memory/")) return
      const name = raw.split("/").pop() ?? ""
      const max = BUDGET[name]
      if (!max) return
      const file = join(root, raw)
      if (!existsSync(file)) return
      const n = manualLines(file)
      if (n <= max) return
      state(event.sessionID).warn.push(
        name === "LEARNINGS.md"
          ? `[contexto] ${name}: ${n} lines outside auto blocks, budget ${max}. Promote a whole tag to .claude/context/memory/<tag>.md and leave one pointer in 'Long-term memory' (nothing is deleted, [✗] lines stay); only then summarize or delete hot lines. Never trim inside <!-- auto:start --> blocks.`
          : `[contexto] ${name}: ${n} lines outside auto blocks, budget ${max}. Summarize the manual part into 1 line or delete (git log keeps history). Never trim inside <!-- auto:start --> blocks.`,
      )
      console.warn(`[contexto] ${name}: ${n} lines outside auto blocks, budget ${max}`)
    })
  },
})
