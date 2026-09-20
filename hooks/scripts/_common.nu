# Shared helpers for ctx-flow hooks.
#
# One rule governs everything here: a hook must never break a session. Every
# entry point wraps its work in `try` and exits 0, and every lookup has a
# fallback rather than a failure mode.
#
# Nushell rather than Python: JSON is a built-in format, so the payload that
# needed `json.load` is one word.

# --- payload -------------------------------------------------------------

# The hook payload as a record, or {} when stdin is absent or malformed.
export def payload []: any -> record {
    let parsed = try { $in | from json }
    if (($parsed | describe) starts-with "record") { $parsed } else { {} }
}

export def cwd-of [p: record]: nothing -> string {
    $p.cwd? | default $env.CLAUDE_PROJECT_DIR? | default $env.PWD
}

# --- git -----------------------------------------------------------------

# Trimmed stdout of a git command, or null if it failed or git is absent.
# Quote any argument starting with `-`, or the parser reads it as a flag of
# this command rather than as an argument to pass through.
def git-out [cwd: string, ...args: string]: nothing -> any {
    let r = try { ^git -C $cwd ...$args | complete }
    if ($r.exit_code? | default 1) == 0 { $r.stdout | str trim } else { null }
}

def absolute? [p: string]: nothing -> bool {
    ($p starts-with "/") or ($p =~ '^[A-Za-z]:[\\/]')
}

# Root of the MAIN worktree — shared by every linked worktree of this repo.
#
# `git rev-parse --git-common-dir` points at the one real .git directory from
# anywhere in the repo, including linked worktrees, so the framework files
# resolve to one place from every branch and every worktree — with or without
# a symlinked .claude. Outside a repo this degrades to the cwd.
export def shared-root [cwd: string]: nothing -> string {
    let common = git-out $cwd rev-parse "--git-common-dir"
    if ($common | is-empty) { return $cwd }

    let root = (if (absolute? $common) { $common } else { $cwd | path join $common }
        | path expand | path dirname)
    if ($root | path type) == "dir" { $root } else { $cwd }
}

# Current branch, or null when detached or outside a repo.
#
# `branch --show-current` rather than `rev-parse --abbrev-ref HEAD`: it resolves
# on an unborn branch — a repo initialised but not yet committed to — where
# rev-parse fails outright, and returns empty on a detached HEAD instead of the
# literal string "HEAD". The closure form of `default` keeps the fallback lazy.
export def branch-of [cwd: string]: nothing -> any {
    let b = git-out $cwd branch "--show-current"
        | default {|| git-out $cwd rev-parse "--abbrev-ref" HEAD }
    if ($b | is-empty) or $b == "HEAD" { null } else { $b }
}

# A branch name reduced to something safe to use as a tag or filename.
export def slug [b: string]: nothing -> string {
    $b
    | str replace -ra '[^A-Za-z0-9._-]+' "-"
    | str trim --char "-"
    | str substring ..<80
    | default --empty "detached"
}

# {root, branch, tag} — the shared root and the agmem branch tag, one slug
# rule for the plugin's SessionStart hook that announces it, the
# /ctx-checkpoint that writes it, and doc-put.nu that tags documents with it.
# `tag` is null on a detached HEAD.
export def paths [p: record]: nothing -> record {
    let cwd = cwd-of $p
    let branch = branch-of $cwd
    {
        root: (shared-root $cwd)
        branch: $branch
        tag: (if $branch == null { null } else { $"branch:(slug $branch)" })
    }
}

# --- tunables ------------------------------------------------------------
#
# One knob, and it is an environment variable over a built-in default. A hook
# that reads a config file has to parse it, validate it, and fall back silently
# when it is wrong — three more ways to break the session it was supposed to
# be helping.

export def env-int [name: string, fallback: int]: nothing -> int {
    try { $env | get $name | into int } catch { $fallback }
}

# --- output --------------------------------------------------------------

export def context [event: string, text: string] {
    print -n ({ hookSpecificOutput: { hookEventName: $event, additionalContext: $text } } | to json -r)
}
