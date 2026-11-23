#!/usr/bin/env node
/**
 * ctx.mjs — run the skill's bash scripts on Windows, where there is no bash.
 *
 * The scripts (init.sh, index.sh, hook.sh) stay the single source of truth; this launcher
 * only changes the engine: on Windows it hands the script to WSL's bash, translating the
 * Windows paths it passes as arguments. On POSIX it execs the script directly, so the
 * opencode plugin can call this one entry point on every platform.
 *
 * Usage:
 *   node scripts/win/ctx.mjs <script> [args...]
 *   node scripts/win/ctx.mjs index.sh --dir C:\proj -n 5 stamina
 *   node scripts/win/ctx.mjs init.sh --tier auto --opencode --check
 *
 * Env:
 *   CONTEXTO_WSL_DISTRO   WSL distro to use (default: the default distro)
 *   CONTEXTO_BASH         bash executable to use on Windows instead of WSL
 *
 * Exit code and stdout/stderr are the script's own.
 */
import { spawnSync } from "node:child_process"
import { existsSync } from "node:fs"
import { basename, isAbsolute, join, resolve } from "node:path"
import { fileURLToPath } from "node:url"

const HERE = fileURLToPath(new URL(".", import.meta.url))
const SCRIPTS = resolve(HERE, "..")

/** C:\Users\me\x → /mnt/c/Users/me/x ; \\wsl.localhost\Ubuntu\home\me → /home/me */
export function wslPath(p) {
  if (!p) return p
  const drive = /^([A-Za-z]):(?:[\\/](.*))?$/.exec(p)
  if (drive) return `/mnt/${drive[1].toLowerCase()}/${(drive[2] ?? "").replace(/\\/g, "/")}`
  const unc = /^\\\\wsl(?:\.localhost|\$)\\[^\\]+\\(.*)$/.exec(p)
  if (unc) return `/${unc[1].replace(/\\/g, "/")}`
  return p
}

function resolveScript(name) {
  const candidates = isAbsolute(name)
    ? [name]
    : [join(SCRIPTS, name), join(SCRIPTS, basename(name)), resolve(name)]
  const found = candidates.find((file) => existsSync(file))
  if (!found) {
    process.stderr.write(`ctx: script not found: ${name} (looked in ${SCRIPTS})\n`)
    process.exit(1)
  }
  return found
}

const [name, ...args] = process.argv.slice(2)
if (!name || name === "-h" || name === "--help") {
  process.stdout.write(
    "usage: node scripts/win/ctx.mjs <init.sh|index.sh|hook.sh> [args...]\n" +
      "runs the skill's bash script directly on POSIX and through WSL's bash on Windows\n",
  )
  process.exit(name ? 0 : 1)
}

const script = resolveScript(name)

/** On Windows, only translate arguments that are actually Windows paths. */
const translate = (arg) => (process.platform === "win32" ? wslPath(arg) : arg)

let command = script
let argv = args
let label = script

if (process.platform === "win32") {
  const bash = process.env.CONTEXTO_BASH
  const distro = process.env.CONTEXTO_WSL_DISTRO
  argv = [wslPath(script), ...args.map(translate)]
  if (bash) {
    command = bash
    label = `${bash} ${argv[0]}`
  } else {
    // Use full path to wsl.exe to avoid PATH issues when spawned from Node
    const wslExe = join(process.env.SystemRoot ?? "C:\\Windows", "System32", "wsl.exe")
    command = existsSync(wslExe) ? wslExe : "wsl.exe"
    argv = distro ? ["-d", distro, "-e", "bash", ...argv] : ["-e", "bash", ...argv]
    label = `wsl.exe -e bash ${wslPath(script)}`
  }
}

/** On Windows, keep cwd as Windows path; the script translates its own arguments.
 *  Passing a WSL path as cwd causes ENOENT because Windows can't resolve it. */
const spawnCwd = process.cwd()

const result = spawnSync(command, argv, {
  cwd: spawnCwd,
  stdio: "inherit",
  // A cold WSL VM takes seconds; the script itself is fast once it is up.
  timeout: Number(process.env.CONTEXTO_TIMEOUT_MS || 120000),
})

if (result.error) {
  process.stderr.write(`ctx: could not run ${label}: ${result.error.message}\n`)
  if (process.platform === "win32" && !process.env.CONTEXTO_BASH) {
    process.stderr.write(
      "ctx: install WSL (wsl --install) or point CONTEXTO_BASH at a bash.exe (Git for Windows, MSYS2)\n",
    )
  }
  process.exit(1)
}
if (result.signal) {
  process.stderr.write(`ctx: ${label} killed by ${result.signal}\n`)
  process.exit(1)
}
process.exit(result.status ?? 1)
