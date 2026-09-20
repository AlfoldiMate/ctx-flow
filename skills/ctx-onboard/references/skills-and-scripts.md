# Skills, scripts, tools and MCP

## Where a piece of knowledge goes

| It is… | Put it in | Because |
|---|---|---|
| a rule every session must follow | `CLAUDE.md` | loaded every session; a rule that needs discovering sometimes isn't |
| the ~25 lines that must survive momentum mid-task | the output style | appended to the system prompt itself |
| a workflow the user runs on purpose (a release, a migration check, a triage pass) | a skill with `disable-model-invocation: true` | its description leaves the model's listing; only `/name` runs it |
| a capability the model should reach for on its own (how to query X) | a skill, model-invocable | the description line is the trigger; keep it under 300 bytes |
| knowledge one agent needs at start | `skills:` preload on that agent | full content, no discovery step, nothing else sees it |
| project facts that accumulate | agmem `lesson`s tagged `role:<agent>` | decay, provenance, and the `/ctx-checkpoint` gate |
| a deterministic computation | a nu script under `scripts/` | zero tokens; a skill or hook calls it |

## A skill

```
skills/<name>/SKILL.md
skills/<name>/references/*.md      # read on demand by the skill's own steps
skills/<name>/scripts/*.nu         # deterministic halves
```

```yaml
---
name: ctx-release            # ctx-<thing> for the framework's own; the project's name otherwise
description: <what it does and when, one sentence; the listing truncates ~1 kB across all skills>
argument-hint: "[version]"
allowed-tools: Bash, Read, AskUserQuestion
disable-model-invocation: true   # user-run rituals only
---
```

The body is numbered steps, each one bounded, the deterministic parts as
`nu` script calls, and a **Report** section that says what the reply leads
with. Anything the skill could get wrong expensively goes through
`AskUserQuestion` before it runs.

## A nu script

Scripts under `scripts/` are standalone: `path self` for siblings, `use
$COMMON [...]` for the hook helpers, `| complete` around every external,
exit 2 with a one-line stderr on a refusal. A script's `main` does not
receive stdin as pipeline input — read it with `^cat | complete | get
stdout` as `doc-put.nu` does. Print a record or table; the skill slices
it. `--json` for the machine-readable form when a skill will parse it.

The house rules for shell work apply to what the scripts do, too: edits
through `open --raw | str replace | save -f`, never `sed`; counting through
`| length`, never `grep -c`.

## Routing a CLI

A tool joins the framework in three places, together:

1. **`CLAUDE.md` toolbox** — one line: what it is for and the one rule for
   using it (`gh` — GitHub; `--json`/`--jq`, never a page of output).
2. **`scripts/doctor.nu` `EXTRA_DEPS`** — a record:
   `{ name: "gh", required: true, probe: [gh --version], fix: "brew install gh && gh auth login" }`.
   `required: false` when only one optional agent uses it.
3. **The agent that uses it** — named in its body (the tracker's tool order,
   the browser's driver).

The README's dependency table gets a row with the install command.

## Wrapping an MCP server

Only when no CLI exists for the thing — brokered OAuth, a live stateful
session. Then the server is declared on the one agent that uses it, never
globally, so its schema loads only when that agent runs:

```yaml
---
name: db-inspector
description: Answers questions against the staging database; returns verdicts, never rows
model: sonnet
effort: medium
tools: Read, mcp__postgres__*
mcpServers:
  - postgres:
      type: stdio
      command: npx
      args: ["-y", "@modelcontextprotocol/server-postgres", "postgresql://localhost/staging"]
---
```

`mcpServers` takes inline definitions (the `.mcp.json` schema; stdio and
http/sse) or the bare name of an already-registered global server.
Declaring the server does not grant its tools: list `mcp__<server>__*` in
`tools:` too. Give the agent a return contract that returns verdicts, and a
`doc-put.nu` fallback for anything longer — MCP results are the largest
objects in the system and the reason the agent exists.

Two servers stay global and are never wrapped: `nu --mcp` (it is the shell)
and `agmem` (it is the memory).

## Hiding and preloading

- Keep a skill out of the main thread's listing: `disable-model-invocation:
  true` in its frontmatter (only `/name` runs it), or `skillOverrides:
  { "<name>": "off" }` in `settings.json`.
- Guarantee an agent has it: `skills: [<name>]` in the agent's frontmatter.
  Plugin skills are referenced by bare name the same way.
- The two combine: a skill hidden by `skillOverrides` can still be
  preloaded — verify once in a scratch session after a Claude Code upgrade,
  since the interaction is undocumented.
- The zero-dependency fallback: keep the folder under `docs/skills/<name>/`
  (not discovered) and have the agent `Read` its `SKILL.md` at start.
