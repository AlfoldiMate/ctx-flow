# Writing a hook

A hook is deterministic work that costs zero tokens and happens *every*
time, which no prompt instruction achieves. Write one only for a rule the
usage numbers show being broken, and only where a script can check it
without judgement. A rule that needs judgement belongs in `CLAUDE.md`; a
rule that is usually irrelevant belongs in a hook that fires only when it
applies.

## The shape

Every ctx-flow hook is a nu script under `hooks/scripts/` with this
skeleton:

```nu
#!/usr/bin/env nu
# <Event>(<matcher>): <what it checks and why — cite the number that
# justified it>. Same safety rule as every hook here: wrapped in try,
# exit 0 — a bug costs one missed nudge, never a broken session.
const COMMON = path self "_common.nu"
use $COMMON *

def main []: any -> nothing {
    let p = $in | payload
    try {
        let cmd = $p.tool_input?.command? | default ""
        # ... the check ...
        context "PostToolUse" "one factual sentence"
    }
}
```

`_common.nu` gives you `payload` (stdin as a record, `{}` on garbage),
`cwd-of`, `shared-root`, `branch-of`, `paths` (root, branch, `branch:<slug>`
tag), `env-int` (an env-var knob with a default), and `context` (the
`additionalContext` reply). Read the three shipped hooks before writing a
fourth: `read-guard.nu` denies, `context-nudge.nu` gates once per level,
`idiom-nudge.nu` gates once per session with a temp-dir marker.

## Rules that keep hooks from being switched off

- **Fail open, always.** Wrap in `try`, exit 0, and pass on anything you
  cannot resolve — a path through a variable, a file that does not exist
  yet. A hook that denies on doubt costs more turns than it saves.
- **Factual, never imperative.** "This project reads structured output
  through the nu MCP server" lands as context; "You must use nu" trips the
  prompt-injection defences and gets surfaced as suspicious.
- **Once.** A nudge fires once per session (or once per level, for a
  growing quantity), gated by a marker in `$nu.temp-dir` keyed on
  `session_id`. Repetition is what gets a hook disabled.
- **Deny only what is measured.** The read guard denies whole-file reads
  because an audit showed them at 46% of result characters. A deny without
  a number behind it is a guess enforced at every turn.
- **Knobs are env vars** (`env-int CTX_FLOW_<NAME> <default>`), never a
  config file the hook has to parse.

## Events and payloads

| Event | Payload fields used | Reply |
|---|---|---|
| `UserPromptSubmit` | `session_id`, `transcript_path`, `prompt` | `additionalContext` |
| `PreToolUse` | `tool_name`, `tool_input` (`command` for Bash, `file_path`/`offset`/`limit` for Read) | `permissionDecision: deny` + reason, or nothing |
| `PostToolUse` | `tool_name`, `tool_input`, `tool_response` | `additionalContext` |
| `SessionStart` | `source` (startup / resume / clear / compact) | `additionalContext` |
| `Stop` | `stop_hook_active` | nothing, or a block with a reason (avoid: it fires mid-investigation) |

Register in `settings.json`; the command is always
`nu --stdin "$CLAUDE_PROJECT_DIR/.claude/hooks/scripts/<name>.nu"` with a
`timeout` of 5–10 seconds. A `matcher` takes a regex over tool names
(`"Bash|Read"`).

## The test

Every hook has a case file under `hooks/tests/<name>.nu` that pipes
synthetic payloads through the script exactly as Claude Code would and
checks the reply — see `read-guard.nu` and `context-nudge.nu` for the
pattern: build fixtures in `$nu.temp-dir`, a table of `[name, result,
expect]`, print `ok`/`FAIL` per row, exit 1 on any failure, clean up. Run it
before registering the hook.

## Hooks that need no script

- `rtk hook claude` on `PreToolUse` `Bash`, first in the list: compresses
  every Bash result transparently. Only when `rtk` is installed, and never
  alongside `rtk init -g` (every call would be rewritten twice).
- The memory hooks — briefing, seam nudges, the recall log — are the agmem
  plugin's. Never register `agmem context` here; it would brief twice.
- A worktree-layout guard ships with Nustro's `worktree` plugin; use that
  rather than writing one.
