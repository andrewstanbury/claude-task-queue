#!/usr/bin/env node
// companion-mcp — wraps the companion's bin/ scripts as MCP tools. Reuses their tested CLI logic
// verbatim; this file only translates MCP tool calls into subprocess invocations and back. No
// business logic is reimplemented here (see docs/adr/README.md R100 — Pass 1 built tq_*, Pass 5a
// expanded coverage to the rest of bin/ for parity with a future non-Claude-Code client).

import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { mkdtemp, writeFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";

const execFileAsync = promisify(execFile);
const __dirname = dirname(fileURLToPath(import.meta.url));

// tq requires a session id for every call (bin/tq:18-19), even reads. Respect one already in the
// environment (Claude Code sets CLAUDE_CODE_SESSION_ID for the whole session; the CLAUDE_COMPANION_
// TASKS_DIR-override branch that bats tests use partitions its store BY session id, so overriding
// it unconditionally would silently split the MCP server onto a different store than the CLI —
// only synthesize one as a last resort, for standalone/manual runs with no session id at all).
const FALLBACK_SESSION_ID = "mcp-server";

function tqPath() {
  // ${CLAUDE_PLUGIN_ROOT} is what hooks.json uses for the same purpose; fall back to a path
  // relative to this file so the server also runs standalone (manual testing, outside Claude Code).
  const root = process.env.CLAUDE_PLUGIN_ROOT || join(__dirname, "..");
  return join(root, "bin", "tq");
}

function projectDir() {
  // Claude Code documents CLAUDE_PROJECT_DIR as available specifically so plugin-bundled MCP
  // servers don't have to depend on process.cwd(), which is not guaranteed to be the project root.
  return process.env.CLAUDE_PROJECT_DIR || process.cwd();
}

async function runTq(args) {
  try {
    const sid = process.env.CLAUDE_COMPANION_SESSION_ID || process.env.CLAUDE_CODE_SESSION_ID || FALLBACK_SESSION_ID;
    const { stdout } = await execFileAsync(tqPath(), args, {
      cwd: projectDir(),
      env: { ...process.env, CLAUDE_COMPANION_SESSION_ID: sid },
    });
    return { content: [{ type: "text", text: stdout.trimEnd() }] };
  } catch (err) {
    // tq writes errors to stderr and exits non-zero; execFile puts both on the error object.
    const text = [err.stderr, err.stdout].filter(Boolean).join("\n").trim() || err.message;
    return { content: [{ type: "text", text }], isError: true };
  }
}

function checkSecretsPath() {
  const root = process.env.CLAUDE_PLUGIN_ROOT || join(__dirname, "..");
  return join(root, "bin", "check-secrets.sh");
}

async function runCheckSecrets(content, path) {
  // check-secrets.sh reads content on stdin (R100/Pass 3 — no more hook JSON to parse), so this
  // needs the ChildProcess handle promisify(execFile) exposes on the returned promise, not just
  // the options object (execFile has no stdin-string option the way execFileSync does).
  const args = path ? ["--path", path] : [];
  try {
    const promise = execFileAsync(checkSecretsPath(), args, { cwd: projectDir() });
    promise.child.stdin.end(content);
    const { stdout } = await promise;
    return { content: [{ type: "text", text: stdout.trim() || "clean — no credential shape detected" }] };
  } catch (err) {
    // Exit 2 is check-secrets.sh's BLOCK verdict — a successful classification, not a tool
    // failure (and not an enforcement action either: nothing here can stop the write).
    if (err.code === 2) {
      return { content: [{ type: "text", text: (err.stdout || "").trim() }] };
    }
    const text = [err.stderr, err.stdout].filter(Boolean).join("\n").trim() || err.message;
    return { content: [{ type: "text", text }], isError: true };
  }
}

function binPath(name) {
  const root = process.env.CLAUDE_PLUGIN_ROOT || join(__dirname, "..");
  return join(root, "bin", name);
}

// Generic subprocess wrapper for the Pass 5a scripts below — same shape as runTq/runCheckSecrets,
// generalized since these don't share tq's session-id precondition. `okExitCodes` lists exit codes
// that are a meaningful VERDICT, not a failure (e.g. burn-down.sh's should-burn: 1 means "hold",
// not "broke") — those still surface their text (several of these scripts, like should-burn and
// da-gate, write the reason to stderr specifically) without isError.
async function runBin(name, args, { okExitCodes = [], cwd, env } = {}) {
  try {
    const { stdout } = await execFileAsync(binPath(name), args, { cwd: cwd || projectDir(), env: env || process.env });
    return { content: [{ type: "text", text: stdout.trimEnd() }] };
  } catch (err) {
    const text = [err.stdout, err.stderr].filter(Boolean).join("\n").trim() || err.message;
    if (okExitCodes.includes(err.code)) return { content: [{ type: "text", text }] };
    return { content: [{ type: "text", text }], isError: true };
  }
}

const server = new McpServer({ name: "companion-tq", version: "0.1.0" });

server.tool(
  "tq_add",
  "Add one or more tasks to companion's task queue.",
  {
    subjects: z.array(z.string().min(1)).min(1).describe("One or more task subjects; all share the same done/context if given."),
    done: z.string().optional().describe("Acceptance criterion for the added task(s)."),
    context: z.string().optional().describe("Files/flows load-bearing for the added task(s)."),
  },
  async ({ subjects, done, context }) => {
    const args = ["add", ...subjects];
    if (done) args.push("--done", done);
    if (context) args.push("--context", context);
    return runTq(args);
  },
);

server.tool(
  "tq_doing",
  "Mark a task in progress, with an optional crash-resume breadcrumb.",
  {
    id: z.string().min(1),
    breadcrumb: z.string().optional(),
  },
  async ({ id, breadcrumb }) => runTq(breadcrumb ? ["doing", id, breadcrumb] : ["doing", id]),
);

server.tool(
  "tq_note",
  "Append a breadcrumb note to a task.",
  { id: z.string().min(1), text: z.string().min(1) },
  async ({ id, text }) => runTq(["note", id, text]),
);

server.tool(
  "tq_done_when",
  "Set or replace a task's done-when acceptance criterion.",
  { id: z.string().min(1), acceptance: z.string().min(1) },
  async ({ id, acceptance }) => runTq(["done-when", id, acceptance]),
);

server.tool(
  "tq_context",
  "Set or replace what's load-bearing (files/flows) for a task.",
  { id: z.string().min(1), files: z.string().min(1) },
  async ({ id, files }) => runTq(["context", id, files]),
);

server.tool(
  "tq_done",
  "Mark a task completed; returns the full queue report (the completion boundary).",
  { id: z.string().min(1) },
  async ({ id }) => runTq(["done", id]),
);

server.tool(
  "tq_cancel",
  "Retract a mis-queued task (cancelled; kept for audit, excluded from counts).",
  { id: z.string().min(1) },
  async ({ id }) => runTq(["cancel", id]),
);

server.tool(
  "tq_list",
  "Terse one-line-each queue listing, every status included.",
  {},
  async () => runTq(["list"]),
);

server.tool(
  "tq_report",
  "Full grouped queue status (in-progress/pending/parked/blocked/ruled-out/done + next pointer).",
  {},
  async () => runTq(["report"]),
);

server.tool(
  "check_for_secrets",
  "Advisory scan for hardcoded-credential shapes before a risky write. Nothing calls this " +
    "automatically and nothing it returns can block the write (R100 retired the enforced secret " +
    "gate) — call it yourself before writing content you're unsure about. Returns a BLOCK verdict " +
    "for high-confidence credential shapes (AWS/GitHub/Slack/Stripe/Google keys, private key " +
    "blocks), a WARN for a lower-confidence name=value literal, or a clean result.",
  {
    content: z.string().describe("The exact text about to be written."),
    path: z.string().optional().describe("The file path it's headed for (enables the per-repo secret=off opt-out)."),
  },
  async ({ content, path }) => runCheckSecrets(content, path),
);

server.tool(
  "resume",
  "The ONLY way session context reaches a session now (R100/Pass 2) — prints the STEERING core, " +
    "this repo's LESSONS, a version-lag warning, recent out-of-band changes, recorded rework, and " +
    "carried-over open tasks. Also disarms autopilot (announced) so a resumed decision comes back " +
    "to you, not the next drain. Call it yourself; nothing calls it automatically.",
  {},
  async () => runBin("resume.sh", []),
);

server.tool(
  "autopilot_toggle",
  "Toggle a companion mode flag (autopilot/ship/decisive/sweep/burndown) for this repo, or " +
    "pause/resume autopilot around a review. Advisory only (R100) — nothing enforces the flag, " +
    "STEERING reads it.",
  {
    mode: z.enum(["autopilot", "ship", "decisive", "sweep", "burndown"]).default("autopilot"),
    action: z.enum(["on", "off", "status", "pause", "resume"]).describe("pause/resume only apply to mode=autopilot"),
  },
  async ({ mode, action }) => runBin("autopilot.sh", mode === "autopilot" ? [action] : [mode, action]),
);

server.tool(
  "ship_checkpoint",
  "Ship-mode's commit-to-a-throwaway-branch: captures current uncommitted work as a reversible " +
    "commit on a non-default 'autopilot/*' branch — never the default branch, never a push. " +
    "Silent no-op if ship-mode is off, the tree is clean, or the repo has no commits yet.",
  {},
  async () => runBin("ship-checkpoint.sh", []),
);

server.tool(
  "board",
  "Human-facing visual queue render — untruncated subjects, done_when/context shown, plus a " +
    "read-only 'beyond the queue' section from the candidates tool. Never injected, always explicitly invoked.",
  {},
  async () => runBin("board.sh", []),
);

server.tool(
  "burn_down",
  "Whether autopilot may GENERATE work from recorded signals — refuses far more often than it " +
    "agrees, and never invents while any recorded signal remains. 'status' explains the verdict " +
    "in prose; 'should_burn' is the same decision as a terse HOLD/BURN (a HOLD is a normal " +
    "result, not a tool failure).",
  { action: z.enum(["status", "should_burn"]).default("status") },
  async ({ action }) => runBin("burn-down.sh", [action === "should_burn" ? "should-burn" : "status"], { okExitCodes: [1] }),
);

server.tool(
  "candidates",
  "What burn-down is allowed to build, ranked highest-signal first: a parked decision carrying " +
    "rec: > an unchecked ROADMAP item > a TODO/FIXME in tracked source > a contract flow with no " +
    "referenced test > a rework-ledger repeat-failure > invent (last resort, labelled). Empty " +
    "output means nothing to do.",
  { limit: z.number().int().positive().optional().describe("Caps how many candidates print (CANDIDATES_LIMIT).") },
  async ({ limit }) => runBin("candidates.sh", [], { env: limit ? { ...process.env, CANDIDATES_LIMIT: String(limit) } : undefined }),
);

server.tool(
  "burndown_branch",
  "Container lifecycle for burn-down-generated work: start/list/show/discard. Branches off the " +
    "default, never on it; refuses a dirty tree; never merges, never pushes.",
  {
    action: z.enum(["start", "list", "show", "discard"]),
    candidate: z.string().optional().describe("Required for action=start — a '<rank>|<source>|<text>' line from the candidates tool."),
    slug: z.string().optional().describe("Required for action=show/discard."),
  },
  async ({ action, candidate, slug }) => {
    const args = action === "start" ? ["start", candidate ?? ""]
      : action === "list" ? ["list"]
      : [action, slug ?? ""];
    return runBin("burndown-branch.sh", args);
  },
);

server.tool(
  "ship_preflight",
  "Verify-before-ship: runs the project's gate, checks contract drift, prints a summary. No " +
    "commit, no merge, no push.",
  { gate: z.array(z.string()).optional().describe("Gate command + args; defaults to the project's own detected gate.") },
  async ({ gate }) => runBin("ship.sh", ["preflight", ...(gate ?? [])]),
);

server.tool(
  "ship_land",
  "Commit, ff-merge to the default branch, push, prune the shipped branch — the deterministic " +
    "rail under /companion:ship-it. Re-runs the gate on the exact tree being shipped first. HIGH " +
    "BLAST RADIUS: performs real git commit/merge/push operations.",
  {
    message: z.string().min(1).describe("The commit message."),
    gate: z.array(z.string()).optional(),
    da: z.string().optional().describe("The devil's-advocate finding — required for changes touching a declared critical path (.companion/da-paths)."),
    pruneAll: z.boolean().optional().describe("Also sweep other already-merged branches (list-only without this)."),
  },
  async ({ message, gate, da, pruneAll }) => {
    const dir = await mkdtemp(join(tmpdir(), "companion-ship-"));
    const msgfile = join(dir, "message.txt");
    try {
      await writeFile(msgfile, message, "utf8");
      const args = ["land", "-F", msgfile];
      if (da) args.push("--da", da);
      if (pruneAll) args.push("--prune-all");
      if (gate && gate.length) args.push("--gate", ...gate); // must come last — ship.sh slurps everything after it
      return await runBin("ship.sh", args);
    } finally {
      await rm(dir, { recursive: true, force: true });
    }
  },
);

server.tool(
  "ship_handoff",
  "Checkpoint mid-flight work to a pushed branch for another machine: commits the working tree " +
    "(to wip/* if on the default branch), refuses a staged credential shape. HIGH BLAST RADIUS: " +
    "performs real git commit/push operations.",
  {},
  async () => runBin("ship.sh", ["handoff"]),
);

server.tool(
  "rework",
  "The rework ledger (R94) — record a failure event, or report the current defect rate. Counts " +
    "FAILURE events, never touch-counts; three failures against one file offers a redesign.",
  {
    action: z.enum(["record", "report"]),
    label: z.string().optional().describe("Required for action=record: owner-supplied | gate-fail | ci-red | hole | free text."),
    files: z.array(z.string()).optional().describe("Files implicated, for action=record."),
    days: z.number().int().positive().optional().describe("Window for action=report (default 14)."),
  },
  async ({ action, label, files, days }) => {
    const args = action === "record" ? ["record", label ?? "", ...(files ?? [])] : ["report", ...(days ? [String(days)] : [])];
    return runBin("rework.sh", args);
  },
);

// A PROMPT, not a tool (R100/Pass 5c): the decomposition discipline is judgment text for whichever
// model is driving, not a deterministic operation — an MCP tool that ran an LLM call server-side
// to do this would reason with only the raw string, worse than the host model reasoning with full
// conversation context, and would break the thin-wrapper-only rule every tool above follows. A
// prompt just centralizes the INSTRUCTION so any MCP client that supports fetching prompts (Claude
// Code and, per Cursor's own docs, Cursor too) pulls the same text instead of each host carrying
// its own hand-copied version that drifts. STEERING.md still carries this for Claude Code's
// injected core; this is the portable copy for a client that has no equivalent injection.
server.prompt(
  "decompose_into_tasks",
  "Guidance for breaking an ambitious or ambiguous request into companion tq tasks before " +
    "starting work — call this before diving into a large ask, on any MCP-capable client.",
  {},
  async () => ({
    messages: [
      {
        role: "user",
        content: {
          type: "text",
          text: [
            "Before starting an ambitious, multi-step, or ambiguous request, decompose it into",
            "the task queue instead of diving straight into implementation:",
            "",
            "1. Restate the goal in one line.",
            "2. Break it into the smallest independently-completable units — one tq_add call each,",
            "   `subject` naming the concrete deliverable, `done` naming its acceptance test where",
            "   one is obvious.",
            "3. Classify each item as you add it, never leave one unmarked:",
            "   - a plain doable task -> subject as-is.",
            "   - a decision that's genuinely yours to make (which approach, which UX) -> prefix",
            "     `❓ [parked] <the choice + options + your recommendation>`.",
            "   - something only the owner can do (an approval, a purchase, physical access) ->",
            "     prefix `⏳ [blocked] <the action>`.",
            "   An unmarked subject reads as pre-cleared, doable work -- that's how a decision",
            "   silently gets made for the owner instead of asked.",
            "4. Drain plain items in order. Parked/blocked items go through a review step (ask the",
            "   owner, recommendation-first) before being treated as decided.",
            "5. Skip all of this for a small, obvious, single-step ask -- decomposition earns its",
            "   keep on genuinely ambitious requests, not as a ritual on every message.",
          ].join("\n"),
        },
      },
    ],
  }),
);

const transport = new StdioServerTransport();
await server.connect(transport);
