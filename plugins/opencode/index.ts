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
 *   tools contexto_recall/brief/status/check/promote: recall by task terms before delegating,
 *                        read-only health check, and promote verified findings to long-term memory.
 *                        They never write judgment content unprompted.
 *
 * Rules kept from hook.sh: it reminds, it never blocks, and it never writes judgment
 * content. Everything here is text injected into a request or a warning on stderr.
 *
 * Install: drop this directory under .opencode/plugins/contexto (project) or
 * ~/.config/opencode/plugins/contexto (global), or list it in opencode.json `plugins`.
 * Reads PROJECT/.claude/context; stays silent when that directory is absent.
 *
 * Cross-platform: the shell scripts stay the source of truth, but they are reached through
 * `scripts/win/ctx.mjs`, which execs them directly on POSIX and through WSL's bash on
 * Windows (where there is no bash on PATH). The budget count is pure JS, so no `awk`.
 */
import { execFile } from "node:child_process"
import { existsSync, readFileSync } from "node:fs"
import { appendFile } from "node:fs/promises"
import { homedir } from "node:os"
import { dirname, join } from "node:path"
import { fileURLToPath } from "node:url"
import { promisify } from "node:util"
import { Plugin } from "@opencode/plugin"

const run = promisify(execFile)

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

/**
 * One entry point for the scripts on every platform. `ctx.mjs` is a launcher, not a port:
 * it runs the very same bash script, through WSL on Windows. Without it (an install from
 * before the launcher existed) the script is exec'd directly, which is the POSIX behaviour.
 */
type RunResult = { stdout: string; stderr: string; code: number }
type Runner = {
  text: (script: string, args: string[]) => Promise<string>
  raw: (script: string, args: string[]) => Promise<RunResult>
}

function makeRunner(scripts: string): Runner {
  const launcher = join(scripts, "win", "ctx.mjs")
  const hasLauncher = existsSync(launcher)
  // A cold WSL VM takes seconds; the script itself is fast once the VM is up.
  const timeout = process.platform === "win32" ? 20_000 : 3_000
  const raw = async (script: string, args: string[]): Promise<RunResult> => {
    const [command, argv] = hasLauncher
      ? [process.execPath, [launcher, script, ...args]]
      : [join(scripts, script), args]
    try {
      const { stdout, stderr } = await run(command, argv, { timeout, encoding: "utf8", windowsHide: true })
      return { stdout: stdout ?? "", stderr: stderr ?? "", code: 0 }
    } catch (error) {
      const e = error as { stdout?: string; stderr?: string; code?: number | string }
      return {
        stdout: e.stdout ?? "",
        stderr: e.stderr ?? "",
        code: typeof e.code === "number" ? e.code : 1,
      }
    }
  }
  return { text: async (script, args) => (await raw(script, args)).stdout, raw }
}

/** Manual lines outside <!-- auto:start -->…<!-- auto:end -->, as `--check` counts them. */
export function manualLines(file: string): number {
  let text: string
  try {
    text = readFileSync(file, "utf8")
  } catch {
    return 0
  }
  const lines = text.split(/\r?\n/)
  // awk reads one record per newline-terminated line, so a trailing newline is no extra line
  if (lines.length > 0 && lines[lines.length - 1] === "") lines.pop()
  let inside = false
  let count = 0
  for (const line of lines) {
    if (line.includes("<!-- auto:start")) {
      inside = true
      continue
    }
    if (!inside) count++
    if (line.includes("<!-- auto:end")) inside = false
  }
  return count
}

/** Per session: files touched by tools, ones already recalled, and pending warnings. */
type SessionState = { pending: Set<string>; recalled: Set<string>; warn: string[] }

export default Plugin.define({
  id: "contexto",
  async setup(ctx) {
    const root = ctx.location.directory
    const contextDir = process.env.CONTEXTO_DIR
      ? join(root, process.env.CONTEXTO_DIR)
      : join(root, ".claude", "context")
    if (!existsSync(contextDir)) return

    const scripts = scriptsDir(root)
    const runner = scripts ? makeRunner(scripts) : undefined

    /** Whole entries matching every term; empty string when there is no runner or no hit. */
    const search = async (terms: string[], cap: number, rejected = false): Promise<string> => {
      if (!runner || terms.length === 0) return ""
      const args = ["--dir", root, "-n", String(cap)]
      if (rejected) args.push("-x")
      args.push(...terms)
      const out = (await runner.text("index.sh", args)).trim()
      return out && !out.includes("no entry matches") ? out : ""
    }

    /** index.sh prints nothing useful and exits 0 on an empty context; treat both as "no hit". */
    const recall = async (term: string, cap: number): Promise<string> => search([term], cap)

    // Native tools: the coordinator can recall by task terms before delegating, without
    // building a script path or a shell command. They never write context content.
    await ctx.tool.transform((editor) => {
      editor.namespace({ name: "contexto", description: "Project memory stored in .claude/context" })

      /** `--check --json` parsed once, so the tools never parse prose. */
      const checkJson = async (args: string[]) => {
        const { stdout, stderr, code } = await runner!.raw("init.sh", [...args, "--check", "--json"])
        try {
          return { ok: true as const, report: JSON.parse(stdout.trim()) as {
            ok: boolean
            tier: string
            dir: string
            problems: number
            warnings: number
            messages: { kind: string; text: string }[]
          } }
        } catch {
          const text = [stdout.trim(), stderr.trim()].filter(Boolean).join("\n")
          return { ok: false as const, code, text }
        }
      }

      const render = (report: { ok: boolean; problems: number; warnings: number; messages: { kind: string; text: string }[] }) => {
        const lines = report.messages.map((m) =>
          m.kind === "problem" ? `check: ${m.text}` : `check: ${m.kind}: ${m.text}`,
        )
        const verdict = report.ok
          ? report.warnings > 0
            ? `check: ok (${report.warnings} warning${report.warnings === 1 ? "" : "s"})`
            : "check: ok"
          : `check: ${report.problems} problem(s) — nothing was written`
        return [...lines, verdict].join("\n")
      }

      editor.add({
        name: "recall",
        description:
          "Search recorded project learnings, bugs and decisions by task terms. Use before delegating, before grepping blind, or when a file has history. Returns whole entries with file:line, newest first.",
        input: {
          type: "object",
          properties: {
            terms: {
              type: "array",
              items: { type: "string" },
              description: "Task nouns; entries must contain every term",
            },
            limit: { type: "number", description: "Max entries (default 10; 0 = no cap)" },
            rejected: { type: "boolean", description: "Only entries marked [✗], already tried and rejected" },
          },
          required: ["terms"],
          additionalProperties: false,
        },
        options: { namespace: "contexto", codemode: true },
        execute: async (input) => {
          const { terms, limit = 10, rejected = false } = input as {
            terms: string[]
            limit?: number
            rejected?: boolean
          }
          const out = await search(terms, limit, rejected)
          return {
            content: out
              ? `Recorded context (may be stale; verify in the file):\n${out}`
              : "no recorded entry matches",
          }
        },
      })

      editor.add({
        name: "brief",
        description:
          "Return a paste-ready 'recorded context' block for a subagent brief, from task terms.",
        input: {
          type: "object",
          properties: {
            terms: { type: "array", items: { type: "string" } },
            limit: { type: "number", description: "Max entries (default 10; 0 = no cap)" },
            rejected: { type: "boolean", description: "Only entries marked [✗]" },
          },
          required: ["terms"],
          additionalProperties: false,
        },
        options: { namespace: "contexto", codemode: true },
        execute: async (input) => {
          const { terms, limit = 10, rejected = false } = input as {
            terms: string[]
            limit?: number
            rejected?: boolean
          }
          if (!runner) return { content: "contexto: scripts not found; use the skill's index.sh" }
          const args = ["--dir", root, "--brief", "-n", String(limit)]
          if (rejected) args.push("-x")
          args.push(...terms)
          const { stdout, stderr, code } = await runner.raw("index.sh", args)
          const text = [stdout.trim(), stderr.trim()].filter(Boolean).join("\n")
          return { content: text || (code === 0 ? "Recorded context:\n- nothing recorded" : `contexto: index.sh exited ${code}`) }
        },
      })

      editor.add({
        name: "status",
        description:
          "One-line read-only health check of the project context: missing files, budgets, carriers and stale bundle/index.",
        input: { type: "object", properties: {}, additionalProperties: false },
        options: { namespace: "contexto", codemode: true },
        execute: async () => {
          if (!runner) return { content: "contexto: scripts not found; use the skill's init.sh --check" }
          const res = await checkJson(["--dir", root, "--quiet"])
          if (!res.ok) return { content: res.text || `check: failed (exit ${res.code})` }
          const r = res.report
          return {
            content: r.ok
              ? `check: ok — tier ${r.tier}${r.warnings > 0 ? ` (${r.warnings} warning${r.warnings === 1 ? "" : "s"})` : ""}`
              : `check: ${r.problems} problem(s) — ${r.messages.filter((m) => m.kind === "problem").map((m) => m.text).join("; ") || "see contexto_check"}`,
          }
        },
      })

      editor.add({
        name: "check",
        description:
          "Full read-only context report: missing files, budgets, markers, imports, carriers, stale bundle and code index. The text says which command fixes each problem.",
        input: {
          type: "object",
          properties: {
            tier: { type: "string", enum: ["1", "2", "3"], description: "Optional tier to check against" },
          },
          additionalProperties: false,
        },
        options: { namespace: "contexto", codemode: true },
        execute: async (input) => {
          if (!runner) return { content: "contexto: scripts not found; use the skill's init.sh --check" }
          const { tier } = input as { tier?: string }
          const args = ["--dir", root]
          if (tier) args.push("--tier", tier)
          const res = await checkJson(args)
          if (!res.ok) return { content: res.text || `check: failed (exit ${res.code})` }
          return { content: render(res.report) }
        },
      })

      // checked: read the `checked:` timestamp from context file frontmatter
      // Returns when each file was last verified (not just updated)
      editor.add({
        name: "checked",
        description:
          "Read the 'checked:' timestamp from context file frontmatter. Shows when each file was last verified by --check. Use at session start to gauge freshness.",
        input: { type: "object", properties: {}, additionalProperties: false },
        options: { namespace: "contexto", codemode: true },
        execute: async () => {
          if (!runner) return { content: "contexto: scripts not found; use the skill's init.sh --check" }
          const ctxDir = process.env.CONTEXTO_DIR
            ? join(root, process.env.CONTEXTO_DIR)
            : join(root, ".claude", "context")
          const files = ["MAP.md", "STATUS.md", "TODO.md", "LEARNINGS.md", "BUGS.md", "WORKFLOW.md"]
          const lines: string[] = []
          for (const f of files) {
            const path = join(ctxDir, f)
            if (!existsSync(path)) continue
            const content = readFileSync(path, "utf8")
            const m = content.match(/^checked:\s*(.+)$/m)
            lines.push(`${f}: ${m ? m[1].trim() : "never checked"}`)
          }
          if (lines.length === 0) return { content: "contexto: no context files found" }
          return { content: lines.join("\n") }
        },
      })

      // promote: write a confirmed finding to LEARNINGS.md (hot), memory/<tag>.md (cold), or BUGS.md
      // The coordinator calls this after verifying a subagent's finding. Never call from a hook.
      editor.add({
        name: "promote",
        description:
          "Promote a verified finding to long-term memory. Writes to LEARNINGS.md (short/broad), memory/<tag>.md (long) + pointer, or BUGS.md (literal error). Use after confirming a subagent's finding.",
        input: {
          type: "object",
          properties: {
            tag: { type: "string", description: "Tag/category (e.g., 'net', 'market', 'ui')" },
            fact: { type: "string", description: "The finding: what happened, consequence, command that verified it" },
            verdict: { type: "string", enum: ["✓", "✗", "↻"], description: "✓ kept/works, ✗ rejected/failed, ↻ superseded (date in note)" },
            note: { type: "string", description: "Optional extra detail (e.g., superseded date, command output)" },
            target: { type: "string", enum: ["learnings", "memory", "bugs"], description: "Where to write: learnings (default, hot), memory (cold, creates file + pointer), bugs (literal error block)" },
          },
          required: ["tag", "fact", "verdict"],
          additionalProperties: false,
        },
        options: { namespace: "contexto", codemode: true },
        execute: async (input) => {
          const { tag, fact, verdict, note, target = "learnings" } = input as {
            tag: string
            fact: string
            verdict: "✓" | "✗" | "↻"
            note?: string
            target?: "learnings" | "memory" | "bugs"
          }
          if (!runner) return { content: "contexto: scripts not found; use the skill's scripts" }

          const date = new Date().toISOString().slice(0, 10)
          const verdictStr = verdict === "↻" && note ? `↻ ${note}` : verdict
          const line = `- [${date}] [${tag}] [${verdictStr}] ${fact}`

          if (target === "bugs") {
            // BUGS.md: one block per bug with literal error
            const block = `## ${date} — ${tag}\n\n\`\`\`\n${fact}\n\`\`\`\n`
            await appendFile(join(root, ".claude", "context", "BUGS.md"), block + "\n")
            return { content: `promoted to BUGS.md:\n${block}` }
          }

          if (target === "memory") {
            // memory/<tag>.md: cold storage, create if needed, append entry
            const memDir = join(root, ".claude", "context", "memory")
            await runner.raw("mkdir", ["-p", memDir])
            const memFile = join(memDir, `${tag}.md`)
            const entry = `${line}\n`
            await appendFile(memFile, entry)
            // Also add pointer in LEARNINGS.md
            const pointer = `- [${date}] [${tag}] → memory/${tag}.md — 1 entry: ${fact.slice(0, 80)}${fact.length > 80 ? "…" : ""}\n`
            await appendFile(join(root, ".claude", "context", "LEARNINGS.md"), pointer)
            return { content: `promoted to memory/${tag}.md + pointer in LEARNINGS.md:\n${entry}${pointer}` }
          }

          // default: LEARNINGS.md (hot)
          await appendFile(join(root, ".claude", "context", "LEARNINGS.md"), line + "\n")
          return { content: `promoted to LEARNINGS.md:\n${line}` }
        },
      })
    })

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
      if (typeof raw !== "string" || !raw) return
      // Windows tools report absolute paths too; accept one that lives inside the project.
      const relative = raw.startsWith(root)
        ? raw.slice(root.length).replace(/^[\\/]+/, "").replace(/\\/g, "/")
        : raw
      if (relative.startsWith("/") || relative.startsWith("..")) return
      if (relative.startsWith(".claude/context/")) return
      state(event.sessionID).pending.add(relative)
    })

    // Recall runs here, on the request that follows the tool call — the same shape as
    // Claude Code's PreToolUse, which also cannot inject mid-request. Budget warnings
    // queued by execute.after are delivered on the same request.
    await ctx.session.hook("context", async (event) => {
      const s = state(event.sessionID)

      if (s.warn.length > 0) {
        event.system.push({ type: "text", text: s.warn.join("\n") })
        s.warn.length = 0
      }

      if (!runner || s.pending.size === 0) return
      const files = [...s.pending]
      s.pending.clear()

      const blocks: string[] = []
      for (const file of files) {
        if (s.recalled.has(file)) continue
        s.recalled.add(file)
        let hits = await recall(file, 3)
        if (!hits) {
          const base = file.split("/").pop() ?? file
          if (GENERIC.test(base)) continue
          hits = await recall(base, 3)
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
    await ctx.session.hook("compaction", async (event) => {
      let toc = ""
      if (runner) {
        try {
          toc = (await runner.text("index.sh", ["--dir", root])).trim()
        } catch {
          toc = ""
        }
      }
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

    // Task-aware recall for child sessions (subagents).
    // When a new session starts with source="subagent", extract key terms from the first
    // user message and inject up to 3 relevant memory entries. This runs before the agent
    // acts, so the subagent starts with relevant context instead of discovering it blindly.
    await ctx.session.hook("context", async (event) => {
      const meta = event.metadata ?? {}
      const source = meta.source as string | undefined
      if (source !== "subagent") return

      // Only inject once per child session
      const key = `subagent-recall-${event.sessionID}`
      if (sessions.has(key)) return
      sessions.set(key, { pending: new Set(), recalled: new Set(), warn: [] })

      if (!runner) return

      // Extract nouns from the first user message (heuristic: capitalized words, camelCase, snake_case)
      const firstMsg = event.messages.find((m) => m.role === "user")
      if (!firstMsg) return
      const text = typeof firstMsg.content === "string" ? firstMsg.content : ""
      const terms = Array.from(
        new Set(
          text
            .match(/\b[A-Z][a-z]+(?:\.[A-Z][a-z]+)*\b|\b[a-z]+(?:_[a-z]+)+\b|\b[a-z]+(?:-[a-z]+)+\b/g) || [],
        ),
      ).slice(0, 5)
      if (terms.length === 0) return

      const hits = await search(terms, 3, false)
      if (!hits) return

      event.system.push({
        type: "text",
        text: [
          "Project memory relevant to this task (auto-injected for subagent):",
          "This is from .claude/context/, may be stale — verify before trusting.",
          "",
          hits,
        ].join("\n"),
      })
    })

    // Budget: measured here, delivered on the next request. console.warn reaches only the
    // server log, never the model, so the warning is queued instead.
    await ctx.tool.hook("execute.after", (event) => {
      const input = (event.input ?? {}) as Record<string, unknown>
      const raw = input.path ?? input.filePath ?? input.file_path
      if (typeof raw !== "string" || !raw) return
      const relative = raw.startsWith(root)
        ? raw.slice(root.length).replace(/^[\\/]+/, "").replace(/\\/g, "/")
        : raw
      if (!relative.startsWith(".claude/context/")) return
      if (relative.startsWith(".claude/context/memory/")) return
      const name = relative.split("/").pop() ?? ""
      const max = BUDGET[name]
      if (!max) return
      const file = join(root, ...relative.split("/"))
      if (!existsSync(file)) return
      const n = manualLines(file)
      if (n <= max) return
      const message =
        name === "LEARNINGS.md"
          ? `[contexto] ${name}: ${n} lines outside auto blocks, budget ${max}. Promote a whole tag to .claude/context/memory/<tag>.md and leave one pointer in 'Long-term memory' (nothing is deleted, [✗] lines stay); only then summarize or delete hot lines. Never trim inside <!-- auto:start --> blocks.`
          : `[contexto] ${name}: ${n} lines outside auto blocks, budget ${max}. Summarize the manual part into 1 line or delete (git log keeps history). Never trim inside <!-- auto:start --> blocks.`
      // Two edits to the same file in one turn must not queue the same warning twice.
      const queued = state(event.sessionID).warn
      if (queued.includes(message)) return
      queued.push(message)
      console.warn(`[contexto] ${name}: ${n} lines outside auto blocks, budget ${max}`)
    })
  },
})
