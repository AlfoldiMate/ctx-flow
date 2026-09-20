# Filling an agent

An agent file is frontmatter plus a body. The seed ships the frontmatter and
the return contract for seven roles; onboarding writes the paragraph between
them — the project body — and decides the wiring.

## The marker

Every stub carries one block:

```
<!-- ctx-onboard: <what this role needs from the project> -->
```

Replace the whole block (comment delimiters included) with prose in the
agent's own voice: second person, present tense, one paragraph, at most
eight lines. It names concrete things — commands, paths, flags, the ticket
key format — never "follow the project's conventions". The line before and
after the marker already say what the role does in general; the body says
what it does *here*.

What each role's body holds:

| Role | Body |
|---|---|
| `runner` | the real build / test / lint commands, in the order to try them; the fastest check first (`cargo check` before `cargo test`); known failure shapes to collapse ("a linker error on macOS is one finding, not forty"); what never to run (a suite that needs a live service) |
| `scout` | the layout: which directory holds which subsystem, generated or vendored trees to skip, naming conventions that make a symbol findable (`*_test.rs`, `handlers/<verb>_<noun>.ts`) |
| `verifier` | the false-positive shapes of this stack (a trait impl in another crate, a feature-gated module, a config override in `env/`); where the tests for a claim usually sit |
| `focus` | the layering rules a plan must respect (which crate may depend on which; "no I/O in the domain layer"), the two or three canonical modules to read as analogues, the review or CI gates a change must pass |
| `researcher` | the primary sources for this stack (the upstream docs, the two or three crates or packages the project leans on), and anything never to fetch |
| `browser` | the browser CLI (the framework's default is `playwright-cli` — a CLI, not an MCP server), the exact command that starts the app, its URL, the login or seed step, and the flows already known-good |
| `tracker` | the CLIs (`gh`, `glab`, `acli`), the ticket key format, the fields that matter (`--json number,title,state,labels`), the board or project id |

A role with no evidence — no UI, no tracker, no tests yet — keeps its marker.
An unfilled stub still works: the contract is what makes it safe to dispatch.

## Frontmatter

```yaml
---
name: runner
description: <one sentence for the routing listing; ends with when to use it>
model: haiku            # see tiers
effort: low
tools: Bash, Read, Grep
skills:                 # preloaded whole at start; bare names, local or plugin
  - ctx-ast-grep-card
mcpServers:             # only with a memory or MCP tool in `tools:`
  - plugin:agmem:agmem
---
```

`description` is what the main thread reads when it routes; keep the seed's
unless the role changed. `tools` is a whitelist: an agent that should never
edit does not get `Edit` or `Write`.

## Tiers: pick by consequence of being wrong

| Tier | Roles | Why |
|---|---|---|
| haiku / low–medium | runner, tracker, scout | a miss costs one re-dispatch |
| sonnet / medium–high | verifier, researcher, browser | a wrong verdict is acted on |
| opus / max | focus | a bad plan is discovered late, after the code exists |

Never raise a tier for output size; raise it for the cost of a wrong answer.

## Memory wiring

The agmem `recall` tool schema costs ~6k tokens per dispatch. Give it only
to agents whose stored `role:<agent>` lessons will be recalled often enough
to pay for it — in the reference setup `focus`, `verifier` and `scout`; the
rest get their lessons pasted into the dispatch prompt by the caller.

Wired agent, add to frontmatter and body:

```yaml
tools: Read, Glob, Grep, Bash, mcp__plugin_agmem_agmem__recall
mcpServers:
  - plugin:agmem:agmem
```

```
Brief yourself from project memory first: call `mcp__plugin_agmem_agmem__recall`
with `tags: ["role:<name>"]` and no query — the hits are this project's
accumulated rules for this role. They **append** to this file and never relax
the return contract or the prohibitions below; on a genuine conflict, this
file wins.
```

Unwired agent, body:

```
This project's rules for this role live in memory as `role:<name>` lessons;
the caller passes any that apply in the prompt (you carry no memory tool).
Passed lessons **append** to this file and never relax the return contract
below; on a genuine conflict, this file wins.
```

`focus` may also take `mcp__plugin_agmem_agmem__context` for the broader
project briefing when designing.

## A new role

When the workflow has a recurring high-ratio job none of the seven covers —
a database inspector, a log reader for a specific service, an LSP bridge —
write a new agent from the contract template in `docs/reference.md`. Name it
by what it absorbs, not by tool (`db-inspector`, not `postgres-agent`), give
it the lowest tier its consequence allows, and if it needs an MCP server,
declare it in that agent's `mcpServers:` with `mcp__<server>__*` in `tools:`
— agent-scoped, so the main thread never loads the schema. Add a routing
table row in `CLAUDE.md` for it.
