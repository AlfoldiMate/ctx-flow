#!/usr/bin/env nu
# SessionStart: the freshness check. Git state is not in the context a
# session opens with, so a session that starts on a branch behind its
# upstream, or behind the base branch, spends its first hour on stale ground
# — the fix is already on origin, the conflict is already waiting, and
# neither the model nor the user sees it until a push is refused. This hook
# fetches the branch's remote, counts what HEAD is behind, and says so in one
# factual line. It never pulls, merges or rebases: what to do about it is the
# user's call, and saying it is the whole job.
#
# What it reports, and only that:
#
# - HEAD behind its upstream (`@{u}`): commits on the remote branch not here.
# - HEAD behind the base branch: commits on `origin/main` (whatever
#   `origin/HEAD` points at; `CTX_FLOW_BASE_BRANCH` overrides) not merged in.
#   Skipped on the base branch itself.
# - A branch with no upstream, when the repo has a remote — nothing for it
#   to be up to date with, which is its own kind of stale.
#
# Unpushed commits ride along in the same line: the same rev-list call gives
# them for free, and they are the other half of "in sync" — but unpushed work
# alone does not fire the line. Nothing at all is said when the branch is
# current: a hook that speaks every session is the hook that gets switched off.
#
# The fetch is bounded. It runs in a background job and `job recv --timeout`
# gives up at FETCH_SECS (`CTX_FLOW_BRANCH_FETCH_SECS`; 0 skips it); on a
# timeout or a failure the counts come from the last fetch and the line says
# so. `GIT_TERMINAL_PROMPT=0` so a credential prompt cannot hang it. Fires on
# startup, resume and clear, not on compact — the session already knows.
# Same safety rule as every hook here: wrapped in try, exit 0 — a bug costs a
# missing line, never a broken session.
const COMMON = path self "_common.nu"
use $COMMON *

# Seconds the fetch may take before the counts fall back to the last one.
const FETCH_SECS = 6

# Fetch `remote` in a background job; "fetched", "failed" or "timed out".
def fetch [cwd: string, remote: string, secs: int]: nothing -> string {
    if $secs <= 0 { return "skipped" }
    let id = job spawn {
        let r = with-env { GIT_TERMINAL_PROMPT: "0" } { ^git -C $cwd fetch --quiet $remote | complete }
        $r.exit_code | job send 0
    }
    let code = try { job recv --timeout ($secs * 1sec) } catch { null }
    if $code == null { try { job kill $id }; return "timed out" }
    if $code == 0 { "fetched" } else { "failed" }
}

# The remote the branch pushes to, or the first remote, or null.
def remote-of [cwd: string, branch: string]: nothing -> any {
    git-out $cwd config $"branch.($branch).remote"
        | default {|| git-out $cwd remote | default "" | lines | get 0 -o }
        | default --empty null
}

# The base ref: the knob, else what `<remote>/HEAD` points at, else the
# first of `<remote>/main`, `<remote>/master`, `main`, `master` that exists.
def base-of [cwd: string, remote: string]: nothing -> any {
    let knob = $env.CTX_FLOW_BASE_BRANCH? | default ""
    if ($knob | is-not-empty) { return $knob }
    let head = git-out $cwd symbolic-ref "-q" "--short" $"refs/remotes/($remote)/HEAD"
    if ($head | is-not-empty) { return $head }
    [$"($remote)/main" $"($remote)/master" main master]
        | where {|c| (git-out $cwd rev-parse "--verify" "-q" $"($c)^{commit}") != null }
        | get 0 -o
}

# {ahead, behind} of HEAD against `ref`, or null when either is unresolvable.
def counts [cwd: string, ref: string]: nothing -> any {
    let out = git-out $cwd rev-list "--left-right" "--count" $"HEAD...($ref)"
    if ($out | is-empty) { return null }
    let n = $out | split row "\t" | each { into int }
    { ahead: $n.0, behind: $n.1 }
}

def plural [n: int, word: string]: nothing -> string {
    $"($n) ($word)(if $n == 1 { '' } else { 's' })"
}

def main []: any -> nothing {
    let p = $in | payload
    try {
        if ($p.source? | default "startup") == "compact" { return }
        let cwd = cwd-of $p
        let branch = branch-of $cwd
        if $branch == null { return }
        let remote = remote-of $cwd $branch
        if $remote == null { return }                          # local-only repo: nothing to compare

        let status = fetch $cwd $remote (env-int CTX_FLOW_BRANCH_FETCH_SECS $FETCH_SECS)
        let upstream = git-out $cwd rev-parse "--abbrev-ref" "--symbolic-full-name" "@{u}"
        let base = base-of $cwd $remote
        let on_base = $base != null and (($base == $"($remote)/($branch)") or ($base == $branch))

        mut parts = []
        if ($upstream | is-empty) {
            $parts ++= ["no upstream"]
        } else {
            let u = counts $cwd $upstream
            if $u != null and $u.behind > 0 { $parts ++= [$"(plural $u.behind commit) behind ($upstream)"] }
            if $u != null and $u.ahead > 0 { $parts ++= [$"(plural $u.ahead commit) unpushed"] }
        }
        if $base != null and not $on_base and $base != $upstream {
            let b = counts $cwd $base
            if $b != null and $b.behind > 0 { $parts ++= [$"(plural $b.behind commit) behind ($base)"] }
        }
        if ($parts | where {|s| not ($s ends-with "unpushed") } | is-empty) { return }

        let note = match $status {
            "fetched" => "fetched now"
            "skipped" => "not fetched"
            "timed out" => "fetch timed out, counts from the last fetch"
            _ => "fetch failed, counts from the last fetch"
        }
        context "SessionStart" $"Branch ($branch): ($parts | str join ', ') \(($note)\)."
    }
}
