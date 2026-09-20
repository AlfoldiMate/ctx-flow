#!/usr/bin/env nu
# Where this project's sessions actually spend tokens, read from Claude Code's
# own transcripts. /ctx-onboard runs it before proposing anything, so the
# proposal answers measured waste rather than a generic checklist: which tools
# return the most characters, which Bash commands recur, which subagents ran,
# how large the sessions grew before they were cleared.
#
# Read-only. Transcripts live under ~/.claude/projects/<encoded cwd>/, one
# .jsonl per session; a cwd encodes as its path with every non-alphanumeric
# character replaced by `-` (`/.config` → `--config`, one dash per character). Worktrees of one repo land in sibling directories, so
# `--all` folds every directory whose name starts with the project's.
#
# Usage:
#     nu .claude/scripts/usage.nu                 # this project, last 40 sessions
#     nu .claude/scripts/usage.nu --last 100 --all
#     nu .claude/scripts/usage.nu --project /path/to/repo --json
#
# A project with no transcripts prints one line and exits 0: a fresh project
# is not an error, it just has nothing to measure yet.

const PROJECTS = "~/.claude/projects"

def encode [dir: string]: nothing -> string {
    $dir | path expand | str replace -ra '[^A-Za-z0-9]' "-"
}

# The transcript files to read, newest first.
def transcripts [project: string, all: bool, last: int]: nothing -> list<string> {
    let root = $PROJECTS | path expand
    let key = encode $project
    let dirs = if $all {
        try { ls $root | where type == dir | get name | where {|d| ($d | path basename) starts-with $key } } | default []
    } else {
        let d = $root | path join $key
        if ($d | path type) == "dir" { [$d] } else { [] }
    }
    $dirs
    | each {|d| try { glob ($d + "/**/*.jsonl") } | default [] }
    | flatten
    | each {|f| { name: $f, modified: (ls -l $f | get 0.modified) } }
    | sort-by modified --reverse
    | first $last
    | get name
}

# The first word of a Bash command, ignoring `cd x &&` prefixes and env
# assignments, so `cd crates && cargo test` counts as cargo.
def bash-head [cmd: string]: nothing -> string {
    $cmd
    | split row -r '\s*(?:&&|\|\||;|\n)\s*'
    | where {|s| not ($s =~ '^\s*cd\s') }
    | first
    | default ""
    | str trim
    | split row -r '\s+'
    | where {|t| not ($t =~ '^[A-Za-z_][A-Za-z0-9_]*=') }
    | first
    | default "?"
    | path basename
}

# One session's facts: tool calls with their result sizes, subagent
# dispatches (the Agent tool's own result is a dispatch ack, so agents are
# counted, not sized), and the context the last turn was served with.
def session [file: string]: nothing -> record {
    let recs = open --raw $file | lines | each {|l| try { $l | from json } catch { null } } | compact
    let main = $recs | where {|r| not ($r.isSidechain? | default false) }

    let uses = $main
        | where type? == "assistant"
        | each {|r| $r.message?.content? | default [] }
        | flatten
        | where {|c| ($c | describe) =~ record and ($c.type? | default "") == "tool_use" }
        | each {|c| {
            id: ($c.id? | default "")
            name: ($c.name? | default "?")
            head: (if ($c.name? | default "") == "Bash" { bash-head ($c.input?.command? | default "") } else { "" })
            agent: (if ($c.name? | default "") in ["Agent" "Task"] { $c.input?.subagent_type? | default "general-purpose" } else { "" })
            windowed: (if ($c.name? | default "") == "Read" { ($c.input?.offset? != null) or ($c.input?.limit? != null) } else { true })
        } }

    let results = $main
        | where type? == "user"
        | each {|r| $r.message?.content? | default [] }
        | flatten
        | where {|c| ($c | describe) =~ record and ($c.type? | default "") == "tool_result" }
        | each {|c| {
            id: ($c.tool_use_id? | default "")
            chars: (($c.content? | default "") | to json -r | str length)
        } }

    let by_id = $results | group-by id | items {|k, v| { id: $k, chars: ($v | get chars | math sum) } }
    let calls = $uses | join -l $by_id id | default 0 chars

    let usage = $main
        | where {|r| $r.message?.usage? != null }
        | last
        | get -o message.usage
    let context = if $usage == null { 0 } else {
        [input_tokens cache_read_input_tokens cache_creation_input_tokens]
        | each {|k| $usage | get -o $k | default 0 } | math sum
    }

    {
        file: ($file | path basename)
        calls: $calls
        turns: ($main | where type? == "assistant" | length)
        context: $context
        sidechain_lines: ($recs | where {|r| $r.isSidechain? | default false } | length)
    }
}

def main [
    --project: string   # repo directory; default cwd
    --last: int = 40    # newest N sessions
    --all               # fold worktree transcripts (sibling directories) in
    --json              # machine-readable, for /ctx-onboard
]: nothing -> nothing {
    let project = $project | default $env.PWD
    let files = transcripts $project $all $last
    if ($files | is-empty) {
        print $"no transcripts under ($PROJECTS)/(encode $project) — nothing to measure yet"
        return
    }

    let sessions = $files | each {|f| session $f }
    let calls = $sessions | get calls | flatten

    let tools = $calls
        | group-by name
        | items {|name, v| {
            tool: $name
            calls: ($v | length)
            result_kchars: (($v | get chars | math sum) / 1000 | math round)
            avg_chars: (($v | get chars | math avg) | math round)
        } }
        | sort-by result_kchars --reverse

    let bash = $calls | where name == "Bash"
        | group-by head
        | items {|head, v| { command: $head, calls: ($v | length), result_kchars: (($v | get chars | math sum) / 1000 | math round) } }
        | sort-by calls --reverse
        | first 15

    let agents = $calls | where agent != ""
        | group-by agent
        | items {|a, v| { agent: $a, calls: ($v | length) } }
        | sort-by calls --reverse

    let reads = $calls | where name == "Read"
    let biggest = $calls | sort-by chars --reverse | first 10
        | select name head agent chars

    let ctx = $sessions | get context | where $it > 0
    let summary = {
        sessions: ($sessions | length)
        turns: ($sessions | get turns | math sum)
        tool_calls: ($calls | length)
        result_mchars: (($calls | get chars | math sum) / 1000000 | math round --precision 2)
        whole_file_reads: ($reads | where windowed == false | length)
        reads: ($reads | length)
        median_final_context_k: (if ($ctx | is-empty) { 0 } else { ($ctx | math median) / 1000 | math round })
        max_final_context_k: (if ($ctx | is-empty) { 0 } else { ($ctx | math max) / 1000 | math round })
        sessions_over_120k: ($ctx | where $it > 120000 | length)
        subagent_lines: ($sessions | get sidechain_lines | math sum)
    }

    let report = { summary: $summary, tools: $tools, bash: $bash, agents: $agents, biggest: $biggest }
    if $json { print ($report | to json); return }

    print $"sessions read: ($summary.sessions)  turns: ($summary.turns)  tool calls: ($summary.tool_calls)  result chars: ($summary.result_mchars)M"
    print $"whole-file reads: ($summary.whole_file_reads) of ($summary.reads)  final context: median ($summary.median_final_context_k)k, max ($summary.max_final_context_k)k, over 120k: ($summary.sessions_over_120k)"
    print ""
    print ($tools | table -i false)
    print ""
    print ($bash | table -i false)
    if ($agents | is-not-empty) { print ""; print ($agents | table -i false) }
    print ""
    print ($biggest | table -i false)
}
