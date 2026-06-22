# claude-governance — Build Specification

A self-contained brief sufficient for another Claude instance (with no access
to the source repo) to recreate this project from scratch. Read top-to-bottom
before writing any code; everything below is load-bearing.

---

## 1. What this project is, in one paragraph

**claude-governance** is an opinionated governance system that wraps AI-assisted
software development with Claude. It classifies every proposed change by tier
(T3 obligation / T2 standard / T1 preference), enforces T3 mechanically at
two floors (CI and the Claude Code CLI PreToolUse hooks), surfaces T2 as
overridable advisories with logged rationale, and emits a single append-only
audit log that captures every block, advisory, override, approval, and plan.
It ships the same business logic to three delivery surfaces (MCP server, CI
binding, CLI plugin) from one canonical Python package. The system is
**voluntary inside the assistant's session** (the MCP server cannot intercept
tool calls) and **mechanical at the boundary** (CI fails the merge on T3 and
PreToolUse hooks exit non-zero in the CLI).

## 2. The bet (the design's whole reason for existing)

Throughput from Claude comes from autonomy. Autonomy is only safe in proportion
to *trust*. Trust comes from controls that sit **outside** the model and make
catastrophic mistakes mechanically impossible. So the controls in this system
are not a tax on speed; they are what *buys* speed. The more bulletproof the
non-negotiable floor, the more rope Claude gets everywhere else.

Three derived axioms guide every design decision:

1. **Assume the prompt may be trying to slip something past.** Don't trust
   the in-session surface alone. Bind the floor at CI, where code *moves*,
   not where it is *typed*.
2. **Make risk legible in the user's language.** Surface the business
   consequence (PII exposure, billing impact, SOC2 control failure), never
   the diff. Block at the request, immediately.
3. **One source of truth for business logic.** Three delivery surfaces share
   the same rule packs, the same matching engine, and the same audit-log
   shape. Divergence between surfaces is the failure mode.

## 3. The seven principles (the authority document)

These are encoded in the system; they are not optional. Tests, rules, and
audits trace back to specific principle numbers.

1. **Contain by default; danger requires escalation.** Default mode is cheap,
   isolated, reversible: feature branch, preview env, flag-gated. Anything
   outside the sandbox is a deliberate, gated act.
2. **Reversibility beats correctness.** Messy-but-reversible is survivable;
   the un-undoable mistake is the enemy. Flags carry mandatory lifecycle;
   migrations expand/contract; APIs stay backward-compatible.
3. **Friction scales with consequence.** Three tiers; T2/T3 line is the
   entire control.
4. **Make risk legible in the user's language.** Plain-language consequence
   text, not rule ids, surfaced before the change.
5. **Quality floor is automated and non-bypassable.** Tests, lint, SAST,
   secret-scanning ride on CI. Never depend on humans for the load-bearing
   path.
6. **Default to existing patterns; novelty is a gate.** New dependencies,
   IAM changes, infrastructure changes are first-class novelty events that
   hard-stop and route to the accountable role.
7. **Compliance and quality promises are policy-as-code.** Customer
   commitments become declarative rules enforced at the boundary, not prose
   in context.
8. **Pre-flight enforcement; named accountability at the queue gate.** The
   agent transcribes prompts into discrete tasks with conservative defaults;
   the user approves task-by-task; each approval attaches a name to the
   change. Execution after approval is mechanical because the moment of
   moral commitment already happened.

## 4. Architecture: three surfaces × four zones

### 4.1 Delivery surfaces (in priority of investment)

| Surface | Where it runs | Floor type |
|---|---|---|
| **MCP server** (`governance_mcp/`) | Claude Cowork / Desktop / Cloud Agents (primary) | Voluntary — assistant chooses to call the tools |
| **CI binding** (`.github/workflows/`) | GitHub Actions on every PR | **Mechanical** — T3 fails the merge |
| **CLI plugin** (`plugins/claude-code-cli/`) | Claude Code in terminal (secondary) | Mechanical — PreToolUse hooks exit non-zero on T3 |

**All three surfaces import from the same Python package** (`governance_mcp/modules/`).
The CI scanner and the CLI hook scripts are *thin shims*. If you find yourself
writing governance logic in either of them, stop — the right home is
`governance_mcp/modules/`.

### 4.2 Zones (logical responsibilities, not deployment units)

- **Zone A — Inputs (opinionated):** rule packs, contracts, provenance, tier
  model. Encodes "what should be true." Reads principles. Reads contracts.
  Reads `.claude-governance.toml`.
- **Zone B — Outputs (blind):** reporters that observe "what is true now"
  (test coverage, watchdog signals for bypassed hooks, suppression directives,
  edits to principles). **Never** reads the principles or contracts —
  structural isolation prevents the "LLM grading an LLM" failure mode.
- **Zone C — Synthesis (pure presentation):** the PR digest reads both A and B,
  renders one Markdown digest per PR. Counts, arranges, links — never derives
  new opinions, applies weights, or drops "uninteresting" findings.
- **Zone D — Pre-flight (default-deny task approval):** the plan gate. Before
  any change is touched, prompts are decomposed into tasks, classified, and
  surfaced for explicit user approval per task.

**Critical:** Zone B never reads Zone A's content, and Zone C is mechanical
synthesis only. If a future change tempts you to let one zone see another to
"make the report smarter" — that's the failure mode.

### 4.3 Three operating modes

| Mode | When | T2 behavior | `plan_approve` |
|---|---|---|---|
| `interactive` (default) | User present | Advisory (surfaced, requires explicit approval to proceed) | Allowed |
| `agent_unattended` | Cloud Agents, scheduled tasks | T2 with `agent_disposition: block` → escalates to block. T2 with `agent_disposition: advisory` → logs and proceeds (hygiene rules). | **Rejected** — agents cannot self-approve |
| `exploration` | User is thinking, not changing | `check_change` short-circuits to `proceed` unconditionally; classification still runs | n/a |

Mode resolution precedence:
`per-call mode arg` → `.claude-governance.toml [mode] default` →
`GOVERNANCE_MODE` env var → autodetect (looks at `CLAUDE_SCHEDULED_TASK`,
`COWORK_SCHEDULED`, etc.) → `interactive`.

## 5. Tech stack & non-functional requirements

### 5.1 Stack

- **Language:** Python 3.11+ (uses `tomllib`).
- **MCP framework:** `mcp.server.fastmcp.FastMCP` (the official Anthropic MCP
  Python SDK). Tools registered via `@app.tool()`, resources via
  `@app.resource("governance://...")`.
- **No web framework in the primary path.** The MCP server runs over stdio.
  A separate hosted HTTP variant (FastAPI / Starlette) exists as a Cloud-Agent
  prototype but is not the primary surface.
- **CLI plugin runtime:** plain Python scripts; communicates with Claude Code
  via stdin/stdout JSON protocol (PreToolUse / PostToolUse / SessionStart /
  UserPromptSubmit hooks).
- **CI binding:** GitHub Actions reusable workflow + a single Python scanner
  script. No third-party action dependencies beyond `actions/checkout`,
  `actions/setup-python`, `actions/upload-artifact`, and
  `marocchino/sticky-pull-request-comment`.
- **Storage:** append-only JSONL audit log on the local filesystem
  (`<project>/.governance/audit-log.jsonl` per-project + a global
  `~/.claude/governance-mcp/audit-log.jsonl`). Hosted variant uses a
  pluggable `Storage` ABC and adds hash-chained tamper evidence.
- **Plan store:** JSON files in `<project>/.governance/plans/` and
  `~/.claude/governance-mcp/plans/`.
- **Config:** TOML at `<project>/.claude-governance.toml` (loaded with
  `tomllib`).
- **Rule packs / triggers:** JSON files in `governance_mcp/assets/`.
- **Tests:** stdlib `unittest`. ~180+ unit tests across modules; one file
  per module under `governance_mcp/tests/test_<module>.py`.

### 5.2 Non-functional requirements

| NFR | Specification |
|---|---|
| **Latency budget — PreToolUse hooks** | ≤ 10s timeout configured in `hooks.json`; scripts should finish in well under 1s for typical edits |
| **Latency budget — SessionStart / UserPromptSubmit** | ≤ 5s timeout |
| **Audit log durability** | Append-only JSONL; never truncated except by rotation. Rotated to `<stem>-archives/<YYYY-MM>.jsonl` when file > 10 MB **or** on month boundary |
| **Audit log format stability** | Writers conform strictly to the schema; readers skip malformed lines forgivingly. Adding new event types/rules must not break old readers |
| **Audit log tamper-evidence (hosted only)** | Each event carries `prev_hash` = SHA-256 of canonical (sorted-key, no-whitespace) JSON of the previous event. Off-disk archive of the latest hash detects any retroactive rewrite |
| **Determinism** | Rule matching is pure regex over file content / bash command; no LLM in the gating path. "Same prompt anywhere" — toolchain pinned, rule packs versioned alongside code |
| **No business logic outside `governance_mcp/modules/`** | CLI scripts and CI scanner import; they never reimplement |
| **Idempotency** | `prompt_classify` hook fingerprints its previous injection per session and suppresses identical re-injections (saves ~300 tokens of context per turn) |
| **Voluntary-gate honesty** | Cowork/Desktop/Cloud Agents cannot mechanically block; the design assumes the assistant may be non-compliant. `governance.compliance.gap` events detect file edits without a preceding `check_change` |
| **Schema versioning** | `obligations.json`, `standards.json`, `risk-triggers.json` each carry `"schema_version": 1`. Audit events carry `"schema_version": 1`. `.claude-governance.toml` carries `schema_version = 1` |
| **Mode awareness** | Every gating tool must resolve mode via `_lib.resolve_mode` and document its per-mode behavior in its docstring |
| **Token discipline** | Tool descriptions are load-bearing (the model reads them at conversation start). One-paragraph max per tool. Resource URIs preferred for long content |
| **Reader robustness** | `read_audit` skips malformed JSONL lines; `load_json` returns `{}` on any read failure |
| **Plugin isolation (Zone B)** | Reporter scripts must not import from `governance.*`, `policy.*`, or read principle/contract/provenance/config files. Tested via AST grep, not just import scan |
| **Cross-platform paths** | All file operations use `pathlib.Path`. Glob matching uses `**`-aware semantics shared between MCP modules and CLI plugins |

## 6. File system layout

Recreate exactly this structure:

```
ai-governance/
├── CLAUDE.md                    # Repo conventions, loaded by Claude Code
├── README.md                    # Slim, points to docs/
├── LICENSE
├── CHANGELOG.md                 # Material changes between versions
├── pyproject.toml               # pytest config + mcp dependency
├── Dockerfile                   # Cloud Agent container (Python 3.11-slim)
├── install_test.py              # Smoke installer test
├── .gitignore
│
├── governance_mcp/              # THE CANONICAL PACKAGE — all business logic
│   ├── __init__.py              # __version__
│   ├── server.py                # Thin: imports MODULES, creates FastMCP, runs
│   ├── storage.py               # Storage ABC + LocalFilesystemStorage + hash-chain utils
│   ├── CLAUDE.md                # Package-internal conventions
│   ├── modules/                 # The 5 modules
│   │   ├── __init__.py          # MODULES list
│   │   ├── _lib.py              # Shared: audit I/O, project resolve, mode resolve, glob
│   │   ├── _constants.py        # Tunable thresholds (rotation size, etc.)
│   │   ├── governance_core.py   # session_init / status / session_end / scope_check
│   │   ├── policy_enforcement.py# check_change / record_override / rule engine
│   │   ├── plan_gate.py         # plan_submit / plan_approve / plan_next_task ...
│   │   └── prompt_triage.py     # triage_prompt + folded-in risk classifier
│   ├── assets/                  # Rule packs and operating instructions
│   │   ├── obligations.json     # T3 rule pack
│   │   ├── standards.json       # T2 rule pack
│   │   ├── risk-triggers.json   # Keyword/phrase triggers for the classifier
│   │   ├── operating-instructions.md       # Generic Desktop/Cloud Agents protocol
│   │   ├── cowork-skill.md      # Cowork SKILL.md template (auto-attached)
│   │   ├── cloud-agent-system-prompt.md    # Cloud Agent system-prompt fragment
│   │   ├── principles.md        # Full principles doc (~4,400 tokens)
│   │   └── principles-creed.md  # Short-form principles (~500 tokens)
│   └── tests/                   # stdlib unittest, one file per module
│       ├── __init__.py
│       ├── test_lib.py
│       ├── test_governance_core.py
│       ├── test_policy_enforcement.py
│       ├── test_plan_gate.py
│       ├── test_prompt_triage.py
│       └── test_risk_classifier.py
│
├── .github/workflows/           # CI binding — mechanical T3 floor
│   ├── governance-check.yml     # Reusable workflow consumed by every repo
│   └── scan.py                  # Python scanner; imports policy_enforcement
│
├── plugins/                     # Delivery-surface adapters
│   ├── claude-code-cli/         # The CLI surface (terminal Claude Code)
│   │   ├── .claude-plugin/      # Plugin manifest (if needed by host)
│   │   ├── CLAUDE.md            # Surface-specific conventions
│   │   ├── README.md
│   │   ├── hooks/hooks.json     # SessionStart / UserPromptSubmit / PreToolUse wiring
│   │   ├── scripts/
│   │   │   ├── _hook_io.py      # Shared stdin/stdout JSON helpers
│   │   │   ├── session_init.py  # SessionStart shim
│   │   │   ├── prompt_classify.py # UserPromptSubmit shim
│   │   │   ├── pre_edit.py      # PreToolUse Edit|Write|MultiEdit shim
│   │   │   ├── pre_bash.py      # PreToolUse Bash shim
│   │   │   └── statusbar.py     # Single-line statusbar renderer
│   │   └── commands/            # User-invocable slash commands
│   │       ├── governance-status.md
│   │       └── override-record.md
│   └── (optional stack plugins: react-canonical, rails-canonical, python-canonical)
│
├── docs/                        # All human-facing documentation
│   └── system/
│       ├── principles.md        # Authority document (mirrored in assets/)
│       ├── architecture/architecture.md
│       └── reference/
│           ├── reference.md     # Audit shape, rule prefixes, MCP catalog
│           └── trust-model.md   # What enforces vs. voluntary
│
├── examples/
│   └── claude-governance.toml   # Per-repo config template (commented)
│
├── inputs/                      # Per-org content (kept in a private repo IRL)
│   ├── contracts/               # Customer-commitment markdown files
│   └── provenance/              # Decision-records that justified each opinion
│
├── outputs/                     # Generated artifacts (gitignored except .gitkeep)
│   ├── reports/<sha>/           # One dir per PR sha — reporter outputs
│   └── digests/<sha>.md         # One synthesizer digest per PR sha
│
└── .claude-plugin/marketplace.json  # Marketplace manifest for plugin distribution
```

## 7. Module-by-module specification

The package contains **exactly five modules** in `governance_mcp/modules/`.
Each exports `do_*` pure-Python functions and a `register(app, lib)` entry
point that adds MCP tools/resources.

### 7.1 `_lib.py` — shared helpers (imported by everyone, imports no module)

Implement these helpers; nothing here is governance-specific:

- `PLUGIN = "governance-mcp"` — written into every audit event's `plugin` field.
- `INSTALL_ROOT` / `ASSETS_DIR` — derived from `__file__`.
- `GLOBAL_GOV_DIR` — `~/.claude/governance-mcp` (overridable by
  `GOVERNANCE_RUNTIME_DIR`).
- `GLOBAL_AUDIT_LOG` — `<GLOBAL_GOV_DIR>/audit-log.jsonl` (overridable by
  `GOVERNANCE_AUDIT_LOG_PATH`).
- `AGENT_ID` / `TASK_ID` / `DEPLOYMENT_ID` — env-var-populated identity
  injected into every audit event's `context` when present (Cloud Agent
  correlation).
- `now_iso()` → UTC ISO8601 with trailing `Z`.
- `new_id()` → `uuid.uuid4()` as string.
- `load_json(path)` → dict or `{}` on any failure.
- `load_text(path)` → string or `""` on any failure.
- `resolve_project(project_path: str | None)` → `Path | None`. Returns None
  unless the path is absolute and is an existing directory.
- `Mode` literal: `"interactive" | "agent_unattended" | "exploration"`.
- `resolve_mode(per_call, project_path)` → resolved mode by the precedence
  in §4.3.
- `_autodetect_agent_mode()` → True if any of `CLAUDE_SCHEDULED_TASK`,
  `COWORK_SCHEDULED`, `COWORK_AGENT_MODE`, `CLAUDE_AGENT_UNATTENDED` env
  vars are set.
- Request-scoped project context overrides (`contextvars`-based) for the
  hosted HTTP variant — push/pop/get of `{project_id, config, rule_overrides}`.
  Falls through to filesystem reads when unset.
- `project_config_toml(project_path)` → dict from `.claude-governance.toml`,
  or `{}` on any error. Respects active context overrides.
- `write_audit(project_path, event)` — sets `ts`, `plugin`, `schema_version`,
  injects `AGENT_ID`/`TASK_ID`/`DEPLOYMENT_ID` if set, then delegates to
  `storage.get_storage().write_audit`.
- `read_audit(project_path, limit)` → list[dict], newest first.
- `audit_log_path(project_path)` → Path.
- `path_matches(path, globs)` — `**`-aware glob matcher with .gitignore-like
  semantics (`**` consumes 0+ segments; patterns without `/` match basename;
  segments fnmatched individually).
- `rule_applies(rule, file_path)` — True iff the rule should be evaluated
  against this path, honoring `applies_to` / `exclude` and the special
  `trigger: bash | manifest-add` semantics.

### 7.2 `_constants.py` — tunable thresholds

A handful of magic numbers documented in one place. The currently-used ones:

- `AUDIT_ROTATE_SIZE_BYTES = 10 * 1024 * 1024`
- `BRANCH_DEFAULT_THRESHOLD_DAYS = 5`
- `FLAG_EXPIRY_WARN_DAYS = 30`
- `DIGEST_DEFAULT_LOOKBACK_SECONDS = 86400`

Don't redefine inline; modules import from here.

### 7.3 `governance_core.py` — session lifecycle & discovery

#### Tools

| Name | Signature | Returns |
|---|---|---|
| `governance_session_init` | `(project_path: str \| None = None, mode: str \| None = None) -> str` (JSON) | `{session_id, mode, project_path, ambient, in_scope, rules: {T3_obligations, T2_standards, tier_overrides_active}, protocol, refuse_work, refuse_reason?, out_of_scope_warning?, session_advisories[]}` |
| `governance_status` | `(project_path: str \| None) -> str` | `{project_path, ambient, audit_log, last_24h: {blocks, advisories, overrides}, tier_overrides, approvers}` |
| `governance_session_end` | `(session_id, project_path?, summary?) -> str` | `{closed, session_id, counts, triggered_rules_breakdown, markdown, closing_event_id}` — also writes the closing event |

#### Resources

- `governance://operating-instructions` → contents of `assets/operating-instructions.md`
- `governance://principles` → contents of `assets/principles.md` (~4,400 tokens)
- `governance://principles-creed` → contents of `assets/principles-creed.md` (~500 tokens)
- `governance://cloud-agent-system-prompt` → contents of `assets/cloud-agent-system-prompt.md`

#### Scope check (Cowork-specific best-effort)

`do_session_init` reads `~/Library/Application Support/Claude/claude_desktop_config.json`
to find `coworkUserFilesPath`. If the project is outside that root (and not
under `$HOME` in `scan-mode=home`), it returns `refuse_work: true` plus
verbatim `out_of_scope_warning` Markdown that the assistant must surface as
the first thing in chat. Skip the scope check (return `(True, "")`) when the
config file is missing — that's a Cloud Agent / headless CI environment.

#### Session-start advisories

Best-effort detectors that ride on session_init's response:

- `no_ci_binding` — `.github/workflows/governance-check.yml` missing.
- `on_default_branch` — `git rev-parse --abbrev-ref HEAD` is one of
  `main`, `master`, `develop`, `trunk`.

Each detector returns `{id, severity, title, body, fix}` or `None`. They
land under `session_advisories[]` on the response, and the Cowork SKILL.md
plus the CLI SessionStart hook tell the assistant to surface each verbatim
in the opening reply.

#### Session-end aggregation

Walks the audit log, filters by `session_id`, counts: `check_change`,
`blocks`, `advisories`, `overrides`, `honored_blocks`, `compliance_gaps`,
`plans_submitted`, `plans_approved`. Renders a Markdown summary suitable
for a Cowork artifact.

### 7.4 `policy_enforcement.py` — the gate + regex engine

#### Tools

| Name | Returns |
|---|---|
| `check_change(intent, kind, project_path?, file_path?, content?, command?, package?, session_id?, mode?, provenance?)` | `{decision: "block"\|"advisory"\|"proceed", tier, triggered[], approver, guidance, event_id, session_id, mode, escalated_t2_to_block, project_path}` |
| `record_override(event_id, rule_id, rationale, project_path?, session_id?)` | `{recorded, event_id, references}` |

`kind` is `"file_edit" \| "file_create" \| "bash_command" \| "dependency_add" \| "iam_change" \| "other"`.
`provenance` is `"web" \| "user" \| "model"` — `"web"` **elevates triggered findings one tier**
(content from search results gets stricter treatment).

#### Resources

- `governance://rule-packs/obligations` → contents of `assets/obligations.json`
- `governance://rule-packs/standards` → contents of `assets/standards.json`

#### Rule-pack loading

```python
def project_rules(project_path):
    packs = {
        "obligations": load(ASSETS_DIR / "obligations.json")["rules"],
        "standards":   load(ASSETS_DIR / "standards.json")["rules"],
    }
    # Layer per-project rules from <project>/.governance/rules.json on top.
    # Bucket by rule.tier == "T3" → obligations, else standards.
    return packs
```

#### Tier overrides & approvers

`.claude-governance.toml` carries `[tier_overrides]` (rule_id → tier) and
`[approvers]` (rule_id-prefix → approver string). `approver_for(rule_id,
approvers)` looks up by longest-prefix match, falling back to
`approvers["default"]`.

#### The match engine

```python
def match_rule(rule, content, file_path, command):
    if rule.trigger == "bash":
        # run each pattern.regex against `command`
        ...
    if rule.trigger == "manifest-add":
        # fires when file_path basename is one of:
        # package.json, pyproject.toml, requirements.txt, Gemfile, go.mod, Cargo.toml
        ...
    # Default: regex over `content`, gated by applies_to / exclude globs.
    ...
```

Always continue past `re.error` rather than failing — a single malformed regex
must not prevent the rest of the pack from scanning.

#### Decision resolution

1. Collect all triggered rules (run every pattern; tier-elevate by one
   step when `provenance == "web"`).
2. For `kind == "dependency_add"`, if no rule already matched, synthesize a
   trigger for `standard.dependency.new-package`.
3. Decision:
   - Any T3 triggered → `block`.
   - Any T2 triggered →
     - If mode is `agent_unattended` and ≥1 triggered T2 has
       `agent_disposition == "block"` (the default), escalate to `block`.
     - Else `advisory`.
   - Else → `proceed`.
4. In `exploration` mode, short-circuit immediately to `proceed` and emit
   a `governance.check.exploration` info event with a load-bearing guidance
   string telling the assistant exploration is OFF for real changes.

#### Guidance strings (load-bearing — the assistant reads them)

The exact text matters; do not paraphrase:

- **T3 block:** "HARD BLOCK (T3). Tier-3 obligations are not user-overridable.
  Stop the proposed change. Tell the user what triggered, the consequence,
  and that the named approver is the only escalation path."
- **T2 escalated in agent mode:** "BLOCKED (T2-escalated). Mode is
  agent_unattended — no human is in the loop to approve overrides. Stop the
  change. Report the rule, consequence, and queued state via your normal
  output channel for later human review."
- **T2 advisory:** "TIER-2 ADVISORY. Surface the consequence text to the
  user verbatim and ask explicitly whether to proceed. Do not infer consent
  from silence. If approved, call record_override with the event_id and the
  user's rationale verbatim."
- **Proceed:** "No governance rules tripped. Proceed normally."

#### `record_override`

Writes an `event` of type `"override"` with `tier: "T2"`, `rule: <rule_id>`,
`message: <rationale[:1000]>`, `context: {references_event: <event_id from
check_change>}`. T3 cannot be overridden; the engine never returns an event
that calls record_override against a T3 rule_id.

### 7.5 `plan_gate.py` — Zone D pre-flight approval

#### Tools

| Name | Purpose |
|---|---|
| `plan_submit(tasks: list, project_path?, session_id?, summary?)` | Decompose into tasks; pre-check each via `do_check_change`; aggregate. Any T3 in any task → status `rejected_at_submit`. Returns plan + Markdown for artifact rendering |
| `plan_approve(plan_id, approver_note?, project_path?, session_id?)` | Mark approved. **Rejects in `agent_unattended` mode** ("agents cannot self-approve"). Rejects if plan has T3 |
| `plan_reject(plan_id, reason?, project_path?, session_id?)` | Mark rejected |
| `plan_next_task(plan_id, project_path?, session_id?)` | Return next `pending` task; mark `in_progress`; advance plan to `in_progress`/`completed` |
| `plan_complete_task(plan_id, task_id, result?, project_path?, session_id?)` | Mark task `completed` |
| `plan_status(plan_id, project_path?)` | Read-only fetch + Markdown render |
| `plan_list(project_path?, status_filter?)` | Browse plans |

#### Task schema (input to `plan_submit`)

```json
{
  "description": "edit /path/to/foo.py to add bar()",
  "kind": "file_edit",
  "file_path": "/path/to/foo.py",
  "content": "...",
  "command": "...",
  "package": "..."
}
```

#### Per-task enrichment (output)

```json
{
  "task_id": "<uuid>",
  "description": "...",
  "kind": "...",
  "file_path": "...",
  "status": "pending|in_progress|completed",
  "pre_check": {
    "decision": "block|advisory|proceed",
    "tier": "T1|T2|T3",
    "triggered": [...],
    "event_id": "...",
    "approver": "..."
  }
}
```

#### Plan storage

- Per-project: `<project>/.governance/plans/<plan_id>.json`
- Global mirror: `~/.claude/governance-mcp/plans/<plan_id>.json`

Save to both on every write. Load tries project-local first, then global.

#### Plan Markdown rendering

Suitable for a Cowork artifact. Shows the plan id (first 8 chars), status,
summary, tier banner (⛔ rejected / ⚠ T2 present / no banner), then a
numbered list of tasks with marker (⛔/⚠/·), tier, description, kind, and
any triggered consequence text. Closes with "To proceed:" instructions
(approve / engage approver / abandon).

### 7.6 `prompt_triage.py` — natural-language → tier + scaffolding

Folds in the former `risk_classifier` module. One module with two `do_*` functions:

- `do_classify_intent(prompt, project_path?, session_id?)` — internal
  classifier. Tokenizes the prompt (word regex), counts keyword hits
  (single-word match by token) and phrase hits (multi-word substring on
  lowercased text), scores `kw + 2*phrase`, picks the highest-tier group of
  matched triggers, writes an audit event (`risk.classify.<tier>` or the
  trigger's `rule`), returns `{tier, triggers[], guidance, prompt_excerpt}`.
- `do_triage_prompt(prompt, project_path?, session_id?)` — the public tool.
  Runs `do_classify_intent`, then computes deterministic facts:
  - `file_paths_mentioned` — regex over the prompt for file extensions in
    a known list (`py, js, jsx, ts, tsx, rb, go, java, kt, swift, md, json,
    yaml, yml, toml, css, scss, html, sql, sh, tf`)
  - `imperative_count` — distinct hits against a curated verb set
    (`add, create, build, fix, refactor, remove, run, deploy, ...`)
  - `prompt_length_chars`
  - `scope_hint` — `single-file | single-module | cross-module | cross-service | unknown`
    by keyword presence
  - `queue_context` — pulls the latest approved plan via `plan_gate.do_plan_list`
    and returns `{active_plan_id, queued_tasks[<=10]}`
  - `signals` — `{triage_needed: bool, reasons: []}` — fires when tier is T2/T3,
    imperative_count > 1, or prompt > 280 chars.
  - `schema_for_claude` — a static schema the assistant fills in
    (task_type, scope, effort_estimate, proposed_tasks, queue_recommendation,
    clarifications_needed).
  - `instructions` — verbatim prompt-triage protocol (read facts → fill
    schema → if triage_needed, present to user as one paragraph and wait
    → on confirm, either submit-as-plan or single-step).

Tool: `triage_prompt(prompt, project_path?, session_id?) -> str`.

### 7.7 Module registration

`modules/__init__.py` exports:

```python
from . import governance_core, policy_enforcement, plan_gate, prompt_triage
MODULES = [governance_core, policy_enforcement, plan_gate, prompt_triage]
```

`server.py`:

```python
from mcp.server.fastmcp import FastMCP
from governance_mcp.modules import MODULES, _lib
app = FastMCP("governance")
for m in MODULES:
    m.register(app, _lib)
app.run()
```

Order matters: `plan_gate` imports `policy_enforcement` directly (the plan
gate's `do_plan_submit` calls `pe.do_check_change` on each task).

## 8. Audit log schema

Every event landing in the JSONL log conforms to this shape. The writer is
strict; the reader is forgiving.

```json
{
  "ts": "2026-06-11T14:23:00Z",
  "plugin": "governance-mcp",
  "schema_version": 1,
  "session_id": "<uuid>",
  "event_id": "<uuid>",
  "event": "block | advisory | override | approval | info",
  "tier": "T1 | T2 | T3",
  "rule": "<dotted.id>",
  "file": "/abs/path or empty",
  "command": "<command text or empty>",
  "message": "<short, [:240] for intents, [:1000] for rationales>",
  "context": {
    "kind": "...",
    "mode": "interactive|agent_unattended|exploration",
    "triggered": ["rule_id", ...],
    "escalated_t2_to_block": false,
    "provenance": "",
    "elevated_by_provenance": false,
    "agent_id": "...",
    "task_id": "...",
    "deployment_id": "..."
  }
}
```

### Five event types

| Event | Emitter | Carries |
|---|---|---|
| `block` | `do_check_change` (T3 or escalated T2), `do_plan_submit` (T3 in scope), CLI hooks | A T3-equivalent stop |
| `advisory` | `do_check_change` (T2), `do_classify_intent` (T2 prompt) | A T2 advisory |
| `override` | `do_record_override` after explicit user OK | T2 user override with rationale; `context.references_event` links the originating event |
| `approval` | `do_plan_approve` | Plan approved for execution; `context.note` carries the approver_note |
| `info` | Everywhere else | Lifecycle, status, classification-without-trip. The `rule` field disambiguates |

### Rule-id prefix convention

Format: `<tier-prefix>.<category>.<specific>`

| Prefix | Default tier |
|---|---|
| `obligation.*` | T3 |
| `standard.*` | T2 |
| `preference.*` | T1 |
| `governance.session.*` | info (lifecycle) |
| `governance.plan.*` | info / approval |
| `governance.check.*` | info (check_change with no rule match) |
| `governance.triage.prompt` | info |
| `governance.compliance.gap` | advisory — file edits without preceding check_change |
| `risk.classify.<tier>` | info / advisory (from prompt_triage classifier) |

### Storage backend

`storage.Storage` is an ABC with `write_audit`, `read_audit`, `audit_log_path`.
`LocalFilesystemStorage` is the default and writes to *both* the per-project
log and the global log. `set_storage(...)` swaps in alternative backends (the
hosted variant uses one with hash-chain support and no global log).

### Rotation

Before each append, if the log is > 10 MB or the first line's `ts[:7]`
(YYYY-MM) doesn't match this month, move the file to
`<stem>-archives/<YYYY-MM>.jsonl` and start fresh.

### Hash chain (hosted only)

Each event's `prev_hash` is the SHA-256 hex of the previous event's canonical
JSON (`json.dumps(event, sort_keys=True, separators=(",", ":"))`). The
verifier walks the log, recomputes, and returns
`{verified, events_checked, first_break_at, v1_events_skipped}`. v1 events
(no `prev_hash`) are skipped but still hashed so the chain bridges schema
upgrades.

## 9. Rule pack schema

Two files in `governance_mcp/assets/`. Both share this shape; only the rules
differ in tier and intent.

```json
{
  "schema_version": 1,
  "description": "Human-readable purpose of this pack",
  "rules": [
    {
      "id": "obligation.security.example-rule",
      "tier": "T3",
      "title": "Short human-readable title",
      "consequence": "Plain-language business consequence. Quote regulations and SOC 2 controls where relevant. Surfaced verbatim to the user.",
      "applies_to": ["*"],
      "exclude": [
        "**/.governance/**",
        "**/tests/**",
        "**/fixtures/**",
        "**/*.md",
        "governance_mcp/assets/**"
      ],
      "patterns": [
        {"regex": "<python regex>", "label": "human-readable label"}
      ],
      "trigger": "bash | manifest-add | (omit for content scan)",
      "agent_disposition": "block | advisory"
    }
  ]
}
```

Field meanings:

- `id` — dotted prefix sets default tier; `[tier_overrides]` can promote/demote.
- `consequence` — plain-language, **business-language**, surfaced verbatim. No
  rule ids, no diff. Stakeholders read this.
- `applies_to` / `exclude` — `**`-aware globs. Default `applies_to: ["*"]`
  (everything). Always exclude `**/.governance/**` and `governance_mcp/assets/**`
  (don't scan governance's own fixtures). Markdown files (`**/*.md`) should
  also typically be excluded so that documentation describing patterns
  doesn't itself trip the rule.
- `patterns` — list of `{regex, label}`. Use raw-string-style escaping (the
  JSON encodes the backslashes). `(?i)` for case-insensitive, `\b` for word
  boundaries, `(?<![\w.])` for negative-lookbehind to avoid matching method
  calls.
- `trigger` — usually omitted (means content-scan). Two special values:
  - `bash`: run patterns against `command` argument (not `content`); fires
    only when `command` is supplied.
  - `manifest-add`: fires when `file_path.name` is one of the package-manager
    manifest files (`package.json`, `pyproject.toml`, `requirements.txt`,
    `Gemfile`, `go.mod`, `Cargo.toml`). Patterns are typically empty.
- `agent_disposition` — for T2 rules, decides agent-mode behavior:
  - `block` (default for security/destructive-bash/dep-add) → escalates in agent mode.
  - `advisory` (for hygiene rules: debug statements, TODOs, large files) → logs but proceeds.

### Required T3 obligations to ship (minimum bar)

Each one is a `tier: "T3"` rule with the regex patterns described below.
Authoritative regex text lives in `obligations.json` in the source repo;
recreate from the descriptions:

1. **`obligation.security.secret-in-source`** — detect committed credentials.
   Regex patterns target: AWS access-key-id prefix `AKIA` + 16 uppercase
   alphanumerics; GitHub personal/OAuth/Apps/fine-grained tokens by their
   documented prefix shapes; Slack token prefix `xox` + suffix character +
   alphanumeric tail; Stripe live secret/restricted keys by prefix; Google
   API keys by prefix; Google OAuth bearer prefix; Twilio account-SID
   contexts; PEM private-key block markers (`-----BEGIN ... PRIVATE KEY-----`);
   a generic catch-all for `api[_-]?key|secret|token|password|passwd` followed
   by `=`/`:` and a long quoted literal. Exclude `**/*.md`, tests, fixtures,
   examples, governance assets.
2. **`obligation.security.disable-tls-verify`** — detect any code or shell
   construct that turns off TLS / certificate verification. Patterns cover
   the equivalent of: Python `requests` verify-kwarg set falsy; Node.js TLS
   reject-unauthorized flag set false; the `NODE_TLS_REJECT_UNAUTHORIZED`
   environment variable set to a zero value; Go `InsecureSkipVerify` set
   true; Python `ssl.SSLContext` constructed with `CERT_NONE`; `curl`
   invocations using either the short insecure flag or its long form. The
   regex bodies live in the rule pack; do not enumerate them in
   human-facing docs (they themselves trigger this rule).
3. **`obligation.security.eval-dynamic`** — detect dynamic code evaluation
   from non-literal input. Patterns target: `eval(` followed by a variable
   identifier (negative-lookbehind to skip method calls like `foo.eval`);
   `exec(` followed by a variable identifier; the `new Function(`
   constructor; the timer functions (`setTimeout`/`setInterval`) called with
   a string argument. Applies to JS/TS/Python/Ruby/PHP source extensions.
4. **`obligation.security.raw-sql-concat`** — detect SQL injection vectors.
   Patterns target the canonical statement keywords (`SELECT`/`INSERT`/
   `UPDATE`/`DELETE`) followed by a quoted string concatenation with a
   variable, template-literal interpolation with a variable, or Python
   f-string interpolation with a variable. Applies to source extensions;
   excludes `**/migrations/**`.
5. **`obligation.privacy.pii-in-logs`** — detect probable PII written to
   logs. Pattern: a logger call (`console.log`, `logger.{info,debug,warn,error}`,
   `log.{info,...}`, `print`) whose argument list references a PII-named
   field (`email`, `password`, `ssn`, `social_security`, `credit_card`,
   `card_number`, `cvv`, `date_of_birth`, `dob`, `phone_number`). Applies to
   source extensions.
6. **`obligation.security.broad-iam-grant`** — detect overly broad IAM grants.
   Patterns target: AWS IAM JSON `Action` field set to wildcard; AWS IAM
   `Resource` wildcard combined with `Effect: Allow`; Kubernetes RBAC `verbs`
   or `resources` arrays containing the wildcard string. Applies to `.tf`,
   `.tfvars`, `.yaml`, `.yml`, `.json`, `policy*.json`.

### Required T2 standards to ship (minimum bar)

1. **`standard.quality.debug-statement`** — language-specific debug calls
   (JS console-log, JS `debugger` statement, Python module-scope `print`,
   Ruby `pp`/`binding.pry`/`byebug`). Negative-lookbehind avoids matching
   method calls. `agent_disposition: advisory`.
2. **`standard.quality.todo-without-ticket`** — comment-style `TODO`/
   `FIXME`/`XXX`/`HACK` markers not followed by a ticket identifier
   (`UPPER-1234`, `#123`, or an `https://` link). Excludes Markdown.
   `agent_disposition: advisory`.
3. **`standard.testing.skipped-test`** — `.skip`/`xit`/`xdescribe` for JS
   test runners; `@pytest.mark.skip`/`@pytest.mark.xfail` for Python.
   `agent_disposition: block` (silent test loss is too important to merely
   advise).
4. **`standard.dependency.new-package`** — `trigger: "manifest-add"`, no
   patterns. Fires on edits to package manager manifests.
   `agent_disposition: block`.
5. **`standard.quality.dangerous-bash`** — `trigger: "bash"`, applies to
   `command`. Patterns target: recursive force-delete at filesystem root /
   home / wildcard; `git push --force` without `--force-with-lease`;
   `git reset --hard`; `git clean --force`; wide-open chmod modes; `dd if=`;
   direct writes to block devices. `agent_disposition: block`.

### Optional T2 standards (recommended)

`standard.quality.large-file` (size threshold), `standard.quality.cyclomatic-complexity`,
`standard.quality.function-length`, `standard.performance.n-plus-one-query`,
`standard.i18n.hardcoded-text`, `standard.i18n.directional-css`,
`standard.i18n.manual-plural`, `standard.money.float-currency`,
`standard.typescript.any-type`. See the source repo's `standards.json` for
the regex bodies — most are heuristic and accept logged overrides freely.

## 10. Risk triggers (prompt classifier)

`governance_mcp/assets/risk-triggers.json`:

```json
{
  "schema_version": 1,
  "description": "Prompt-level risk triggers used by the classifier",
  "triggers": [
    {
      "id": "trigger.security",
      "tier": "T3",
      "rule": "obligation.security",
      "category": "Security posture",
      "consequence": "Touches the security posture (auth, secrets, encryption, IAM). ...",
      "keywords": ["secret", "credential", "token", "api key", "password", "auth"],
      "phrases": ["disable verification", "bypass auth", "store the password"]
    }
  ]
}
```

Ship triggers for: `security`, `privacy`, `compliance`, `billing`,
`data-deletion`, `iam-infra`, `new-dependency`, `cost`, `pattern-novelty`,
`flag-experiment`, `testing-required`, `migration`, `observability`.

Per-project additions can be layered via `<project>/.governance/triggers.json`.

Scoring: `score = keyword_hits + 2 * phrase_hits`. Single-word keywords match
by tokenization (so `auth` in `authentication` is *not* a hit); multi-word
keywords and phrases match by lowercased substring.

## 11. Per-project configuration (`.claude-governance.toml`)

```toml
schema_version = 1

[org]
name = "Example Co"
contact = "@platform-eng"

[mode]
default = "interactive"   # or "agent_unattended" / "exploration"

[approvers]
default                  = "@security-team"
"obligation.security"    = "@security-team"
"obligation.privacy"     = "@privacy-team"
"obligation.compliance"  = "@compliance-team"
"obligation.billing"     = "@finance-controls"

[tier_overrides]
# "standard.dependency.new-package" = "T3"

[features]
statusbar          = true
policy_enforcement = true

[branches]
warn_age_days = 5

[novelty]
manifest_files = ["package.json", "pyproject.toml", "requirements.txt"]
lockfiles      = ["package-lock.json", "poetry.lock"]
iac_paths      = ["infra/", "terraform/", "k8s/"]
```

Approver lookup is longest-prefix match against rule id; falls back to
`default`.

## 12. CI binding (the mechanical T3 floor)

### 12.1 Reusable workflow

`.github/workflows/governance-check.yml` — consumer repos call this with:

```yaml
jobs:
  check:
    uses: <org>/ai-governance/.github/workflows/governance-check.yml@main
    with:
      base: ${{ github.event.pull_request.base.sha }}
```

The workflow:

1. Checks out the PR.
2. Checks out `<org>/ai-governance@main` to `.governance-tooling/`.
3. Sets up Python 3.11.
4. Determines the diff base (input → PR base → `merge-base HEAD origin/main`).
5. Runs `python3 .governance-tooling/.github/workflows/scan.py
   --base $BASE_SHA --repo $(pwd)
   --rule-packs .governance-tooling/governance_mcp/assets
   --output governance-report.json --summary governance-summary.md`.
6. Uploads the report as an artifact.
7. Posts/updates a sticky PR comment (via `marocchino/sticky-pull-request-comment`).
8. **Fails the check if `governance-report.json` contains any `"tier": "T3"`.**

### 12.2 The scanner

`scan.py` is a thin shim. It must `from governance_mcp.modules import
policy_enforcement as pe` and call `pe.match_rule(...)` — the engine
lives in exactly one place.

Logic:

1. `git diff --name-only $BASE_SHA...HEAD` → changed files.
2. For each file, read contents, run every obligation + every standard
   via `pe.match_rule`. Recompute line numbers from each pattern's
   first regex match position.
3. Run the diff-aware TDD check:
   - For each source file in the diff (suffix `.py | .rb | .js | .jsx |
     .ts | .tsx | .go`) that isn't itself a test (paths matching
     `test_*.py|*_test.py|*.test.ts|*.spec.ts|/tests/|/spec/|/e2e/|/playwright/|*.feature`)
     and isn't TDD-exempt (manifests/lockfiles, `/docs/`, `/.github/`,
     `/db/migrate/`, generated/`vendor/`/`node_modules/`/etc.),
     check whether any test file in the diff has a matching stem
     (`test_<stem>`, `<stem>_test`, `<stem>.test`, `<stem>.spec`,
     `<stem>_spec`) or sits under a parallel package path after
     stripping `app/|src/|lib/|internal/|pkg/|tests/|spec/|__tests__/`.
   - If none, emit a `standard.testing.code-without-tests` T2 advisory
     pointing at the source file.
4. Emit `governance-report.json` (the structured report) and
   `governance-summary.md` (the human-readable summary appended to
   `$GITHUB_STEP_SUMMARY` and used as the sticky PR comment).
5. Optional cross-surface reconciliation: when env vars
   `GOVERNANCE_HOSTED_URL` and `GOVERNANCE_PROJECT_ID` are both set,
   GET `<URL>/v1/audit/<project_id>?limit=1000`, compute which PR-changed
   files lack a corresponding `check_change` event, and include it in
   the summary as **informational only** (not build-failing).

## 13. CLI plugin

`plugins/claude-code-cli/` ships four hook scripts plus a statusbar and two
slash commands. **Every script is a thin shim** that imports from
`governance_mcp.modules` — no business logic here.

### 13.1 Hook wiring (`hooks/hooks.json`)

```json
{
  "hooks": {
    "SessionStart":      [{"hooks": [{"type": "command",
                            "command": "python3 \"${CLAUDE_PLUGIN_ROOT}/scripts/session_init.py\"",
                            "timeout": 5}]}],
    "UserPromptSubmit":  [{"hooks": [{"type": "command",
                            "command": "python3 \"${CLAUDE_PLUGIN_ROOT}/scripts/prompt_classify.py\"",
                            "timeout": 5}]}],
    "PreToolUse": [
      {"matcher": "Edit|Write|MultiEdit",
       "hooks": [{"type": "command",
                  "command": "python3 \"${CLAUDE_PLUGIN_ROOT}/scripts/pre_edit.py\"",
                  "timeout": 10}]},
      {"matcher": "Bash",
       "hooks": [{"type": "command",
                  "command": "python3 \"${CLAUDE_PLUGIN_ROOT}/scripts/pre_bash.py\"",
                  "timeout": 10}]}
    ]
  }
}
```

### 13.2 Hook I/O protocol (`_hook_io.py`)

- Read JSON from stdin. Fields used:
  `tool_name, tool_input{file_path, path, content, new_string, command},
   session_id, hook_event_name, prompt, cwd`.
- Write a decision via stdout or exit codes:
  - **Block**: write `reason` to stderr, exit 2. (Claude Code's block convention.)
  - **Advisory / passthrough**: write JSON envelope to stdout with
    `{"hookSpecificOutput": {"hookEventName": "PostToolUse",
    "additionalContext": "<text the model will see>"}}`, exit 0.
- Add the repo root to `sys.path` so `from governance_mcp.modules import ...`
  works.

### 13.3 Each script

- **`session_init.py`** — call `gc.do_session_init(project_path=cwd)`.
  Surface `refuse_work` text (with a "STOP all work" prefix), each session
  advisory verbatim, and a baseline session banner. Pass everything through
  `additionalContext`.
- **`prompt_classify.py`** — call `pt.do_triage_prompt(prompt, project_path, session_id)`.
  Build per-tier blocks: T3 (consequence + escalate-not-negotiate),
  T2 (consequence + override-with-rationale), and a triage block when
  `signals.triage_needed`. **Idempotency:** fingerprint `(tier, sorted trigger
  ids, triage_needed)`, store at `~/.claude/governance-mcp/triage-state.json`
  per session, suppress re-injection on identical fingerprint. Cap state at
  32 sessions.
- **`pre_edit.py`** — call `pe.do_check_change(intent="edit/write
  <basename>", kind="file_edit", project_path=cwd, file_path, content,
  session_id)`. On `block` → write reason and exit 2. On `advisory` →
  write the T2 consequence list via additionalContext. On `proceed` → no-op.
- **`pre_bash.py`** — same shape, `kind="bash_command"`, pass `command`.
- **`statusbar.py`** — read last-24h audit log from `_lib.audit_log_path`,
  count blocks/advisories, render `<verdict> · <branch> · T3:<n> T2:<n>` with
  ANSI color (red T3 / yellow T2 / green ok).

### 13.4 Slash commands

- `/governance-status` — read-only: reads `.claude-governance.toml`,
  last 10 audit lines, and the deviation profile if present. Reports a
  one-screen summary.
- `/override-record <rule-id> <justification>` — refuses non-T2 rules,
  refuses speed/urgency-style justifications, then invokes
  `pe.do_record_override`.

## 14. Cowork SKILL.md and Cloud Agent system prompt

These two assets are the *only* way the assistant learns the protocol in
surfaces without PreToolUse hooks. Treat their text as production code —
the model is literally executing the protocol from them.

### 14.1 Cowork SKILL.md (`assets/cowork-skill.md`)

YAML frontmatter:

```yaml
name: governance
description: Governance protocol for Cowork — call governance_session_init first,
             prefer plan_submit for multi-step work, check_change before any file
             write or shell command, governance_session_end at conversation close.
```

Body, in order:

1. "Open every conversation with `governance_session_init(project_path)`."
2. "If `refuse_work: true`, STOP. Surface `refuse_reason` and
   `out_of_scope_warning` verbatim as the first thing in chat."
3. "If `session_advisories` is non-empty, surface each in your opening reply
   verbatim — title, body, fix."
4. "For multi-step work, use the plan flow: decompose → `plan_submit` →
   render the returned markdown as a Cowork artifact → ask user explicitly →
   `plan_approve` with verbatim approver_note → execute tasks."
5. "For each gated action: `check_change` first. block → stop and surface;
   advisory → surface verbatim, ask, on yes call `record_override` with
   verbatim rationale; proceed → carry on."
6. "Close every conversation with `governance_session_end` and render the
   summary markdown as a Cowork artifact."
7. Mode descriptions (interactive / agent_unattended / exploration).
8. T3-never-overridable, T2-overridable-with-logged-rationale, T1-free.

### 14.2 Cloud Agent system prompt (`assets/cloud-agent-system-prompt.md`)

For environments without SKILL.md auto-attachment. Same protocol, but
explicit that:
- Mode is `agent_unattended` and T2 with `agent_disposition: block` halts the agent.
- `plan_approve` will be rejected.
- The agent must surface blocks to its reviewer channel (Slack / dashboard /
  PR comment) with rule + consequence + approver + event_id.
- The audit log is the source of truth — the reviewer trusts it over
  the agent's narration.

## 15. Marketplace manifest

`.claude-plugin/marketplace.json`:

```json
{
  "name": "claude-governance",
  "owner": {"name": "...", "url": "..."},
  "metadata": {
    "description": "Production-grade governance for AI-assisted development. ...",
    "version": "3.0.0",
    "homepage": "..."
  },
  "plugins": [
    {
      "name": "claude-code-cli",
      "source": "./plugins/claude-code-cli",
      "description": "Claude Code (terminal) surface — PreToolUse hooks, ...",
      "version": "0.2.0",
      "category": "surface",
      "tags": ["cli", "hooks", "statusbar"]
    }
  ]
}
```

Additional stack-specific plugins (`react-canonical`, `rails-canonical`,
`python-canonical`) ship the same way — each with its own skill teaching the
canonical pattern and a PostToolUse hook catching mechanical violations.

## 16. Docker / Cloud Agent packaging

```dockerfile
FROM python:3.11-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    GOVERNANCE_MODE=agent_unattended \
    GOVERNANCE_RUNTIME_DIR=/var/governance
RUN mkdir -p /var/governance
WORKDIR /app
COPY pyproject.toml README.md ./
COPY governance_mcp ./governance_mcp
RUN pip install --no-cache-dir .
RUN useradd --create-home --uid 1000 governance \
    && chown -R governance:governance /var/governance /app
USER governance
ENTRYPOINT ["python", "-m", "governance_mcp.server"]
```

The agent connects via the MCP stdio transport. Mount a volume at
`/var/governance` to persist audit/plans across runs.

## 17. Tests

`governance_mcp/tests/test_<module>.py` — one file per module. Use stdlib
`unittest`. Exercise `do_*` functions directly (not through FastMCP). Each
module gets:

- A happy-path smoke test per tool.
- T1 / T2 / T3 edge cases.
- Mode interaction tests (use `os.environ["GOVERNANCE_MODE"]` with
  `try/finally del` for cleanup — env-var precedence is part of the contract).
- For state-touching tests, redirect `_lib.GLOBAL_GOV_DIR` and the module's
  `PLANS_DIR_GLOBAL` to `tempfile.mkdtemp(...)` in `setUp` and restore in
  `tearDown`.

**Test-fixture secret trap:** if a test asserts that the secret-in-source rule
fires, do NOT embed a real-shaped secret as a literal string — your own
governance system will block your edit. Build the fixture at runtime by
concatenating a known prefix with synthesized character runs at test time
rather than as a source-level literal.

Run all: `python3 -m unittest discover -s governance_mcp -p "test_*.py"`.

## 18. Recommended build order

To recreate from scratch, build in this order — each step is independently
testable:

1. **`_lib.py`** with `now_iso`, `new_id`, glob matchers, `resolve_project`,
   `resolve_mode`. Tests for glob semantics first (they're the trickiest).
2. **`storage.py`** with `LocalFilesystemStorage`. Tests: write → read → rotate.
3. **`_lib.write_audit` / `read_audit`** delegating through storage.
4. **`assets/obligations.json`** and **`assets/standards.json`** with the
   minimal rule set from §9.
5. **`policy_enforcement.py`** — rule loading, `match_rule`, decision
   resolution, `do_check_change`, `do_record_override`. Test each tier
   transition and the agent_disposition behavior.
6. **`risk-triggers.json`** + classifier helpers in `prompt_triage.py`.
7. **`prompt_triage.py`** full module including the deterministic facts and
   `_read_queue_context` (with a try/except — circular imports possible).
8. **`plan_gate.py`** — depends on `policy_enforcement`. Test the
   submit/approve/next/complete lifecycle plus T3-at-submit rejection plus
   agent-mode `plan_approve` refusal.
9. **`governance_core.py`** — session lifecycle + scope check + advisories.
10. **`modules/__init__.py`** with the `MODULES` list.
11. **`server.py`** thin loader.
12. **`assets/operating-instructions.md`**, **`cowork-skill.md`**,
    **`cloud-agent-system-prompt.md`**, **`principles.md`**,
    **`principles-creed.md`**. These are production text — write them
    carefully.
13. **`pyproject.toml`** with `mcp` as a dependency.
14. **CI binding**: `governance-check.yml` + `scan.py` (imports
    `policy_enforcement`). Test with a fixture repo that has a T3 violation
    constructed at test time (see §17).
15. **CLI plugin**: `_hook_io.py`, four hook scripts, `hooks.json`,
    `statusbar.py`. Each script ≤ 80 LOC.
16. **Slash commands**: two Markdown files in `commands/`.
17. **Marketplace manifest** + **Dockerfile**.

## 19. Things to NOT do

- **Don't put business logic in `plugins/*/scripts/` or `.github/workflows/scan.py`.**
  These are adapters. Logic lives in `governance_mcp/modules/`.
- **Don't bypass `_lib.resolve_mode` in gating tools.** Mode awareness is
  a per-tool contract. Document the per-mode behavior in the docstring.
- **Don't write to disk outside `_lib.write_audit` and module-specific stores**
  (plans dir, triage state). Audit log is the single accountability surface.
- **Don't add a repo-level opt-out for T3.** "It's just a prototype" is how
  PII reaches unguarded repos. Prototypes become production. T3 holds
  everywhere; T2 has the per-change bypass.
- **Don't add LLM judgment to the gating path.** The auto-reviewer for the
  safety tier is the deterministic policy layer — an LLM approving an LLM
  shares the same blind spots (tautology trap).
- **Don't let Zone B (reporters) see Zone A (principles/contracts/rule packs).**
  Test the isolation by AST grep. Structural impossibility, not norm-enforced.
- **Don't paraphrase the guidance text** the engine returns to the assistant
  (the `_GUIDANCE_BLOCK_T3` / `_GUIDANCE_ADVISORY` constants). Those exact
  words are part of the protocol.
- **Don't break the audit-log shape.** Add fields freely; never remove. The
  reader is forgiving, but downstream tooling expects every documented field.
- **Don't add features beyond what §7 specifies in v1.** The v3.6.16
  simplification (11 modules → 5) is the current shape. Resist re-adding
  `containment`, `watchdog`, `digest`, `improvement_loop` until there is a
  concrete use case — their audit-event ids are reserved.
- **Don't enumerate disallowed regex literals in human-facing documents.**
  Documenting a TLS-verify-off pattern, for example, by writing the pattern
  out verbatim will trip the very rule the document describes. Use prose
  descriptions of what each pattern catches instead.

## 20. Definition of done

The system is "complete" for v1 when:

- [ ] All 5 modules exist and pass their unit tests (~180+ tests).
- [ ] `python -m governance_mcp.server` launches a FastMCP stdio server.
- [ ] A test harness can call `governance_session_init`, `check_change`,
      `plan_submit`, `plan_approve`, `record_override`, `governance_session_end`
      in sequence and produce a clean audit log.
- [ ] `python3 scan.py --base <sha> --repo <path> --rule-packs <dir>
      --output report.json --summary summary.md` runs without `governance_mcp`
      installed elsewhere on the system (paths resolved via `sys.path` insert).
- [ ] A fixture file containing a runtime-constructed AWS-access-key-shaped
      string fails the CI scanner with a T3 finding.
- [ ] The CLI plugin's PreToolUse Edit hook exits 2 with a non-empty stderr
      when fed a JSON payload describing an Edit that would write a
      TLS-verify-disabling construct.
- [ ] The MCP server in `agent_unattended` mode returns `decision: "block"`
      for a T2 rule with `agent_disposition: "block"`, and `advisory` for one
      with `agent_disposition: "advisory"`.
- [ ] `plan_submit` with a task that triggers T3 returns
      `status: "rejected_at_submit"` and writes a `block` event with
      `rule: "governance.plan.submit"`.
- [ ] `plan_approve` in `agent_unattended` mode returns `approved: false`
      with the canned reason.
- [ ] The audit log rotates when it crosses 10 MB.
- [ ] The Dockerfile builds and the container runs the server with no
      filesystem writes outside `/var/governance`.

That's the system. Everything else — hosted HTTP variant, watchdog reporters,
PR digest synthesizer, improvement-loop telemetry, stack-specific plugins — is
**out of scope for v1**. Ship the floor first.
