---
name: ctx-onboard
description: Grow the ctx-flow seed into this project's own workflow — from a description of how you work, a scan of the repo and of past session transcripts, generate the agent definitions, CLI routing, agent-scoped MCP wrapping, hooks, skills and nu scripts that save the most tokens here. Re-runnable; each run proposes before it writes.
argument-hint: "[how you work: stack, forge, tracker, browser, what wastes your time]"
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, AskUserQuestion, Skill, mcp__plugin_agmem_agmem__recall, mcp__plugin_agmem_agmem__remember, mcp__plugin_agmem_agmem__context
---

# ctx-onboard

Turn the seed `.claude` into the configuration this project would have
written for itself. The seed is deliberately empty where a project differs:
agent bodies, the toolbox, the extra dependencies, the hooks that only some
stacks want. This skill fills those from evidence — what the user says, what
the repo is, what past sessions actually spent tokens on — and never from a
generic checklist.

The principle it optimises for is the framework's: **the main thread holds
decisions; everything else holds output.** Every artifact it generates
exists to move output out of the main thread or to stop it arriving at all.

References, read when the step needs them: `references/agents.md` (filling
an agent stub, tiers, memory wiring), `references/hooks.md` (writing a
hook), `references/skills-and-scripts.md` (skills, nu scripts, agent-scoped
MCP, the toolbox and doctor rows).

## 1. Listen

`$ARGUMENTS` is the user's description of how they work. If it is empty or
thin, ask once with `AskUserQuestion` — at most four questions, multi-select
where the answers are not exclusive:

- the stack and how it is built and tested (or "read it from the repo")
- where the work is tracked and reviewed: GitHub, GitLab, Jira, Linear, none
- whether the app has a UI worth driving in a browser, and how it starts
- what wastes their time in sessions today (long logs, re-explaining the
  codebase, lost context after compaction, the wrong tool getting picked)

Do not ask what the scan can answer. Do not ask about tools they have not
mentioned; propose those in step 3 instead.

## 2. Scan

```bash
nu "${CLAUDE_PROJECT_DIR:-.}/.claude/scripts/onboard-scan.nu" --table
```

One record: languages with their ast-grep status, build systems and their
test/lint commands, CI, the forge, which CLIs are installed, what `.claude`
holds today (and which stubs still carry the `<!-- ctx-onboard:` marker),
declared MCP servers, and — from `scripts/usage.nu` over the last 40
transcripts — where the tokens went: result characters per tool, recurring
Bash commands, agents dispatched, whole-file reads, final context sizes.

Read the usage numbers as the priority list. A project whose sessions spent
40% of result characters on `cargo test` output needs a filled `runner`
before anything else; one whose `Read` calls were mostly whole files needs
nothing new — the read guard already ships — but a `scout` that knows the
layout; one with six sessions over 200k tokens needs the checkpoint habit
more than any agent. No transcripts is the fresh-project case: propose from
the stack alone and say so.

Then `mcp__plugin_agmem_agmem__context` with a query naming the project —
an earlier onboarding, or facts about the workflow, may already be stored.

## 3. Propose

Build the proposal as one table and put it in front of the user with
`AskUserQuestion` (multi-select, one question per group; four groups at
most). Every row names the evidence it rests on — a usage number, a CLI
found, a sentence of theirs — and rows without evidence do not appear.

| Group | Rows come from |
|---|---|
| **Agents to fill** | the seven stubs, each with what its body will say: the runner's real commands, the scout's layout, the tracker's CLI, the browser's start command; a stub with no evidence for its role stays a stub |
| **Tools to route** | installed CLIs the scan found that the description or usage justifies: `gh`/`glab`/`acli` for the tracker, `playwright-cli` for the browser, `rtk` when Bash results dominate; each one is a toolbox line, a doctor row, and a README dependency |
| **Hooks** | only for a rule the usage shows being broken, and only where a deterministic check exists: a compressor hook (`rtk hook claude`), a layout guard, a nudge for a recurring anti-pattern the idiom nudge does not cover |
| **Skills, scripts, MCP** | a skill for a workflow they described that recurs (a release ritual, a migration check); a nu script for anything a hook or agent would otherwise re-derive; an agent-scoped `mcpServers:` entry only when a CLI genuinely does not exist for the thing |

Present the recommendation first in each group. Anything declined is
recorded in memory in step 6 so the next run does not re-propose it.

## 4. Generate

Write, in this order, so each step leaves the folder consistent:

1. **Agents** — replace each accepted stub's `<!-- ctx-onboard: … -->`
   block with the project body per `references/agents.md`; wire memory
   (`recall` tool + `mcpServers: [plugin:agmem:agmem]`) only on the agents
   whose lessons will pay for the schema. A declined stub keeps its marker.
2. **Toolbox** — replace the `<!-- ctx-onboard: … -->` marker in
   `CLAUDE.md` with the accepted tools, one line each, in the toolbox's own
   voice (what it is for, the one rule for using it). Extend the routing
   table only where a row's action changed (e.g. `gh` named where it said
   "the forge CLI").
3. **Doctor** — add one `EXTRA_DEPS` record per tool in
   `scripts/doctor.nu`, `required: false` for anything only one agent uses.
4. **Hooks** — a new hook is a nu script under `hooks/scripts/` following
   `references/hooks.md`, a case file under `hooks/tests/`, and a
   `settings.json` entry; run the test before moving on. `rtk` needs no
   script: its entry is `"command": "rtk hook claude"` on `PreToolUse`
   `Bash`, first in the list.
5. **Skills and scripts** — per `references/skills-and-scripts.md`; skill
   names are `ctx-<thing>` when they are the framework's, the project's own
   name otherwise.
6. **README** — under "What onboarding added", one line per artifact with
   the evidence that justified it. The seed's README says how to
   re-run this skill; leave that.

Edits go through nu (`open --raw f | str replace <old> <new> | save -f f`)
or `Edit`; confirm every marker was actually present before replacing it —
a missing marker means a previous run already filled that spot, and the
right move is to show the diff and ask, not to append.

## 5. Verify

```bash
nu "${CLAUDE_PROJECT_DIR:-.}/.claude/hooks/tests/read-guard.nu"
nu "${CLAUDE_PROJECT_DIR:-.}/.claude/hooks/tests/context-nudge.nu"
```

plus any test written in step 4, then `/ctx-doctor`. If a filled `runner`
exists, dispatch it once on the project's cheapest command (`cargo check`,
`npm run lint`) and confirm the reply is the contract and nothing else — a
runner that returns a log on its first run has a body that contradicts its
contract, and the body is what to fix.

## 6. Remember

One `remember` batch: the onboarding decisions as `fact`s ("the project's
tracker is Jira via acli, chosen 2026-09-20 because …"), each declined
proposal as a `fact` too (so a re-run does not re-ask), and any rule the
user stated as binding every session as an `instruction` — sparingly.
`recall` first; a re-run supersedes the previous run's facts rather than
duplicating them.

## Report

Lead with what changed: N agents filled, tools added, hooks, skills — one
line each with the evidence. Then the one next action: `/ctx-doctor` if
something needs installing, otherwise `/clear` so the new `CLAUDE.md` and
output style load. A worked example of the result for a Rust + nu project is
the `sln-rust-nu-fresh-proj` branch of the ctx-flow repository; more
`sln-*` branches are the same seed grown for other stacks.
