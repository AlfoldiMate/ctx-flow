#!/usr/bin/env nu
# ctx-flow doctor: verify the dependencies the framework leans on, and whether
# ast-grep can parse what this project is written in. Read-only.
#
# Prints two tables: one row per dependency with a fix hint, then the project's
# top source extensions and which ast-grep grammar handles each — built in,
# buildable from a tree-sitter repo, or absent.
# The /ctx-doctor skill runs this and interprets the result.
#
# The seed framework depends on three tools: nu, agmem and ast-grep. Anything
# /ctx-onboard adds for this project (gh, playwright-cli, rtk, acli, ...) goes
# in EXTRA_DEPS below — one row per tool, and the doctor reports it like the
# rest.

# Project-specific tools added by /ctx-onboard, one record per tool:
#     { name: "gh", required: true, probe: [gh --version], fix: "brew install gh" }
# `probe` is the command and arguments whose exit 0 means "installed";
# `required: false` prints "missing (optional)" instead of "MISSING".
const EXTRA_DEPS = []

# First line of a command's stdout if it exits 0, else null.
def probe [cmd: string, ...args: string]: nothing -> any {
    let r = try { ^$cmd ...$args | complete }
    if ($r.exit_code? | default 1) == 0 {
        $r.stdout | str trim | lines | first | default ""
    } else { null }
}

def dep [name: string, required: bool, found: any, fix: string]: nothing -> record {
    {
        dep: $name
        status: (if $found != null { "ok" } else if $required { "MISSING" } else { "missing (optional)" })
        detail: ($found | default "")
        fix: (if $found == null { $fix } else { "" })
    }
}

const GRAMMARS = path self "grammars.nu"
use $GRAMMARS *

# agmem's version string under-reports (a build can carry space derivation
# while still saying 0.1.0), so probe behaviour, not the version: --doctor
# logs the space it derived for this directory. A binary without derivation
# lands every project in the literal space `default` — silently, collapsing
# per-project memory into one bucket, which is why this row exists.
def agmem-row []: nothing -> record {
    let bins = try { which -a agmem } | default []
    if ($bins | is-empty) {
        return { dep: "agmem", status: "MISSING", detail: ""
            fix: "brew install AlfoldiMate/tap/agmem; then: claude plugin marketplace add AlfoldiMate/agmem && claude plugin install agmem@agmem" }
    }

    # The plugin's hooks are `agmem hook <event>`, a subcommand that arrived in
    # 0.1.10; an older binary serves MCP fine and answers every hook with a
    # usage error, so the briefing never arrives and nothing says why. Probe
    # the subcommand, not the version: a build from the branch carries it
    # under the previous version string.
    let hook = (try { ^agmem hook --help | complete | get exit_code } | default 1)
    if $hook != 0 {
        let v = (try { ^agmem --version | complete | get stdout | str trim } | default "unknown version")
        return { dep: "agmem", status: "OLD", detail: $"($v), no `agmem hook`"
            fix: "brew upgrade agmem — without `agmem hook` (0.1.10+) the plugin's hooks are silent" }
    }

    # Subagents hand back long output as documents through `agmem doc put`
    # (scripts/doc-put.nu); without the subcommand every such write fails and
    # the agent falls back to a /tmp path nothing else reads.
    let doc = (try { ^agmem doc --help | complete | get exit_code } | default 1)
    if $doc != 0 {
        let v = (try { ^agmem --version | complete | get stdout | str trim } | default "unknown version")
        return { dep: "agmem", status: "OLD", detail: $"($v), no `agmem doc`"
            fix: "brew upgrade agmem — without `agmem doc` (0.2.0+) subagents cannot write documents" }
    }

    let r = try { ^agmem --doctor | complete }
    let m = ($"($r.stdout? | default '')\n($r.stderr? | default '')"
        | parse -r 'space=(?<s>[A-Za-z0-9_-]+)')
    let space = if ($m | is-empty) { "" } else { $m | first | get s }
    let extra = if ($bins | length) > 1 { $", ($bins | length) binaries on PATH" } else { "" }

    if $space == "" {
        { dep: "agmem", status: "BROKEN", detail: "--doctor reports no space"
          fix: "run `agmem --doctor` by hand and read its log" }
    } else if $space == "default" and ($env.PWD | path basename) != "default" {
        { dep: "agmem", status: "STALE", detail: $"derived space: default($extra)"
          fix: ("no space derivation — needs >= v0.1.1: brew upgrade agmem, and check "
              + "`which -a agmem` for a stale duplicate earlier on PATH") }
    } else {
        { dep: "agmem", status: "ok", detail: $"space=($space)($extra)"
          fix: (if $extra == "" { "" } else {
              "keep one binary — `which -a agmem`; a stale extra silently loses space derivation" }) }
    }
}

# Memory reaches a session through the agmem plugin — its SessionStart hook
# injects the briefing, its PostToolUse hook logs recalls and nudges at seams.
# This framework registers none of that itself, so a missing plugin is a
# session with no memory in front of it and nothing to say so.
def agmem-plugin-row []: nothing -> record {
    let listing = (try { ^claude plugin list | complete | get stdout } | default "")
    if ($listing | str contains "agmem") {
        { dep: "agmem plugin", status: "ok", detail: "claude plugin list shows it", fix: "" }
    } else {
        { dep: "agmem plugin", status: "MISSING", detail: ""
          fix: "claude plugin marketplace add AlfoldiMate/agmem && claude plugin install agmem@agmem" }
    }
}

def extra-rows []: nothing -> list<record> {
    $EXTRA_DEPS | each {|d|
        let cmd = $d.probe | first
        let args = $d.probe | skip 1
        dep $d.name $d.required (probe $cmd ...$args) $d.fix
    }
}

def main []: nothing -> nothing {
    let nu_mcp = (try { ^nu --help | complete | get stdout } | default "" | str contains "--mcp")

    let deps = [
        (dep "nu" true (version).version "brew install nushell")
        (dep "nu --mcp" true (if $nu_mcp { "supported" } else { null })
            "nu too old for MCP — upgrade: brew upgrade nushell; then register: claude mcp add nu -- nu --mcp")
        (dep "ast-grep" true (probe ast-grep "--version") "brew install ast-grep")
        (agmem-row)
        (agmem-plugin-row)
    ] | append (extra-rows)

    let langs = project-langs

    print ($deps | table -i false --width 160)
    print ""
    print ($langs | rename extension files ast-grep | table -i false --width 160)
}
