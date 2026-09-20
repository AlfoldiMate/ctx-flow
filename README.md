# ctx-flow

A token-frugal `.claude` folder for Claude Code. **The main thread holds
decisions; everything else holds output.** Build logs, search results, page
snapshots and ticket records are the largest objects in a session and carry
the least information per token; ctx-flow routes each into a subagent sized
for the job, guards the reads that flood the context, and keeps durable
memory in [agmem](https://github.com/AlfoldiMate/agmem) so a session can be
cleared instead of compacted.

This branch, `sln-rust-nu-fresh-proj`, is the **seed grown for a fresh
Rust + Nushell project on GitHub** — what `/ctx-onboard` produces from the
`main` branch given that description. Use it as-is for such a project, or as
the worked example while onboarding a different stack from `main`.

## Install

```bash
git clone --branch sln-rust-nu-fresh-proj https://github.com/AlfoldiMate/ctx-flow /path/to/your-project/.claude
rm -rf /path/to/your-project/.claude/.git      # it is your project's folder now
```

The seed's three dependencies plus what onboarding added, and two registrations:

| Tool | Why | Install |
|---|---|---|
| [nu](https://www.nushell.sh) | runs the hooks and scripts; its MCP server is the structured shell | `brew install nushell` |
| [agmem](https://github.com/AlfoldiMate/agmem) ≥ 0.2.0 | memory across sessions, via its Claude Code plugin | `brew install AlfoldiMate/tap/agmem` |
| [ast-grep](https://ast-grep.github.io) | syntax-aware code search | `brew install ast-grep` |
| [gh](https://cli.github.com) | GitHub, always over the GitHub MCP server | `brew install gh && gh auth login` |
| [rtk](https://github.com/rtk-ai/rtk) | transparently compresses Bash output (hook ships here; never also `rtk init -g`) | `brew install rtk` |
| [playwright-cli](https://github.com/microsoft/playwright-cli) | browser driving as shell commands, for the `browser` agent | `npm i -g playwright-cli` |
| acli *(optional)* | Jira, for the `tracker` agent | Atlassian's installer |
| tree-sitter-cli *(optional)* | builds grammars ast-grep does not ship (`/ctx-grammar nu`) | `npm i -g tree-sitter-cli` |

```bash
claude mcp add nu -- nu --mcp
claude plugin marketplace add AlfoldiMate/agmem && claude plugin install agmem@agmem
```

You do not have to *use* Nushell as your shell; the hooks run under `nu`
whatever your terminal runs. If you do, [Nustro](https://github.com/AlfoldiMate/Nustro)
is worth installing over a bare `brew install nushell`: it is a Nushell
distro (a checkout you install, never edit) that brings the plugins and
modules `nu` on its own does not — `nu-config doctor`, pipeline-aware Tab
completion for `git`, `brew` and `cargo`, `agent` (Claude Code at the
prompt), `worktree`, and the Claude Code plugins in its `harness/`. Then, in
a session:

```
/ctx-doctor      # every row above, both registrations, the hooks, ast-grep on your language
/ctx-onboard     # re-run to adjust for your project (see Configure)
```

## What's in the box

| Path | What | Loaded |
|---|---|---|
| `CLAUDE.md` | the routing table, payload and shell discipline, what memory adds, answer shape — rules only, under 6 kB | every session |
| `output-styles/ctx-flow.md` | the ~25 lines that must survive momentum mid-task | every session, in the system prompt |
| `agents/` | seven roles — `runner`, `scout`, `researcher`, `verifier`, `focus`, `browser`, `tracker` — each a return contract plus the project body onboarding wrote | when dispatched |
| `hooks/scripts/` | `rtk hook claude` compresses every Bash result; `read-guard.nu` denies whole-file reads over 300 lines; `context-nudge.nu` says "checkpoint, then clear" at 120k tokens and per 40k after; `idiom-nudge.nu` notes once per session when `sed`/`python`/`grep` stood in for nu or ast-grep | by event |
| `skills/ctx-*` | `/ctx-doctor`, `/ctx-checkpoint`, `/ctx-grammar`, `/ctx-onboard`; `ctx-ast-grep` (rule writing) and `ctx-ast-grep-card` (preloaded into agents) | on invocation / preload |
| `scripts/` | `doctor.nu`, `doc-put.nu` (a subagent's long output → an agmem document), `usage.nu` (where past sessions spent tokens), `onboard-scan.nu`, `build-grammar.nu` + `grammars.nu` | by a skill |
| `docs/reference.md` | return-contract template, dispatch rules, the memory mapping, playbook guards, where MCP fits | on demand |

## How it works, in one screen

- **Route by information ratio.** How much output it takes to reach the
  conclusion, not what kind of task it is. Searches, suites, logs, browsers
  and trackers always delegate; the edit and the design choice never do.
- **Every agent has a return contract**: fixed keys, hard caps, a forbidden
  list. Anything longer goes to agmem as a document (`DOC: <id> <uri>`) and
  the main thread gets the address, not the body.
- **Two MCP servers, no more.** `nu --mcp` because it *is* the shell (run
  once, slice `$history` after); `agmem` because it *is* the memory. Every
  other integration is a CLI, and an MCP server a project truly needs is
  declared on the one agent that uses it.
- **Hooks enforce what prompts only suggest.** The three shipped ones came
  out of a token audit: whole-file reads were 46% of result characters, the
  longest sessions never cleared, and the house tools lost to habit on 18%
  of Bash calls.
- **Memory is addressed, not held.** `/ctx-checkpoint` at a seam, `/clear`,
  and the plugin's briefing opens the next session. Agents propose lessons
  (`LEARNED:`); the checkpoint gate decides, and dropping is normal.

Why each rule exists, at length: `docs/reference.md` and the comment
headers of the hooks.

## What onboarding added

Each row names the evidence that justified it; a re-run of `/ctx-onboard`
starts from here.

| Artifact | Evidence |
|---|---|
| `runner` filled with the cargo / clippy / fmt / nu commands, fastest first | Bash results dominated past sessions; `cargo test` output was the largest single source |
| `scout` filled with the workspace layout; memory wired (`role:scout`) | most `Read` calls preceded a symbol hunt |
| `verifier` and `focus` filled with Rust false-positive shapes and the layering rule; memory wired | wrong verdicts and plans are the expensive failures |
| `researcher` pointed at docs.rs, the Rust books and the installed `nu` | nu changes at minor versions; the binary outranks the web |
| `browser` on `playwright-cli`, `tracker` on `gh` (+ `acli`) | CLIs found on the machine; the forge is GitHub |
| `rtk hook claude` first on `PreToolUse` `Bash` | every Bash result arrives compressed; the doctor flags a doubled registration |
| doctor rows for gh, gh auth, playwright-cli, rtk, acli, tree-sitter | one row per routed tool |
| toolbox lines in `CLAUDE.md` for gh/acli, playwright-cli, rtk and Nustro's `worktree` plugin | the routing table now names them |
| `skills/rust-expert-developer` — idiomatic Rust reference (API guidelines, error handling, traits, async, unsafe, testing), loaded when writing Rust | the workspace is Rust; the reference is Nustro's, vendored here so the branch is self-contained |

Not bundled, used from [Nustro](https://github.com/AlfoldiMate/Nustro): the
`nushell` skill (deep nu reference, loaded when writing nu) and the
`worktree` plugin (bare repo + sibling worktrees, with the guard hook and
the session-start layout note).

## Configure

### The fast way: `/ctx-onboard`

Tell it how you work — stack, forge, tracker, whether there is a UI, what
wastes your time — and it scans the repo (`scripts/onboard-scan.nu`: build
system, CI, installed CLIs, ast-grep coverage) and your past sessions
(`scripts/usage.nu`: result characters per tool, recurring commands, final
context sizes), then proposes, with the evidence for each row:

1. which agent stubs to fill, and with what
2. which CLIs to route (`gh`, `glab`, `acli`, `playwright-cli`, `rtk`, …)
3. hooks, only for rules the numbers show being broken
4. skills, nu scripts, and agent-scoped MCP wrapping

Accept what you want; it writes the files, runs the hook tests and
`/ctx-doctor`, and stores the decisions in agmem so a re-run picks up where
it left off. Its references (`skills/ctx-onboard/references/`) are also the
manual for doing any of this by hand.

### By hand

| To… | Edit |
|---|---|
| fill an agent | replace its `<!-- ctx-onboard: … -->` block with the project body (`references/agents.md`) |
| add a tool | a toolbox line in `CLAUDE.md`, an `EXTRA_DEPS` record in `scripts/doctor.nu`, a row in this README |
| add a hook | a nu script in `hooks/scripts/` + a case file in `hooks/tests/` + a `settings.json` entry (`references/hooks.md`) |
| add a skill | `skills/<name>/SKILL.md`; `disable-model-invocation: true` for rituals only you run |
| tune the guards | env vars: `CTX_FLOW_READ_MAX_LINES` (300), `CTX_FLOW_READ_SMALL_BYTES` (12000), `CTX_FLOW_CONTEXT_NUDGE_TOKENS` (120000), `CTX_FLOW_CONTEXT_NUDGE_STEP` (40000) |
| teach ast-grep a language | `/ctx-grammar <lang>` — builds into `~/.cache/ctx-flow`, registers in a gitignored `sgconfig.yml` |
| keep a machine-local skill | drop it in `skills/` and list it in `.gitignore` |

## Layout

```
.claude/
├── CLAUDE.md               rules; loads every session
├── README.md               this file
├── settings.json           rtk + the three hooks, and the output style
├── .gitignore              settings.local.json, .DS_Store, your machine-local skills
├── agents/                 runner, scout, researcher, verifier, focus, browser, tracker
├── output-styles/          ctx-flow.md
├── hooks/scripts/          _common.nu, ctx-paths.nu, read-guard.nu, context-nudge.nu, idiom-nudge.nu
├── hooks/tests/            read-guard.nu, context-nudge.nu
├── scripts/                doctor.nu, doc-put.nu, usage.nu, onboard-scan.nu, build-grammar.nu, grammars.nu
├── skills/                 ctx-onboard, ctx-doctor, ctx-checkpoint, ctx-grammar, ctx-ast-grep, ctx-ast-grep-card, rust-expert-developer
└── docs/reference.md
```

MIT.
