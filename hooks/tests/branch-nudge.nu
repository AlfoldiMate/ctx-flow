#!/usr/bin/env nu
# Cases for branch-nudge.nu, run from anywhere:
#
#     nu .claude/hooks/tests/branch-nudge.nu
#
# Fixtures are three repos in $nu.temp-dir: a bare `origin`, and clones `a`
# and `b`. `a` is the other developer — it pushes; `b` is where the session
# starts, and the hook is fired with `b` (or a branch of it) as the cwd. Every
# fetch is a file:// fetch, so the cases run offline. Checks: silent when
# current, the upstream count after `a` pushes, the base count on a feature
# branch main has moved past, "no upstream" on a local-only branch, silence
# on a detached HEAD, outside a repo, on compact, and with unpushed work
# only; a skipped fetch (`CTX_FLOW_BRANCH_FETCH_SECS=0`) reports the last
# fetch; the line stays under 160 chars.
const HOOK = path self "../scripts/branch-nudge.nu"

def git [dir: string, ...args: string] {
    let r = ^git -C $dir ...$args | complete
    if $r.exit_code != 0 { error make { msg: $"git ($args | str join ' ') in ($dir): ($r.stderr)" } }
    $r.stdout | str trim
}

def commit [dir: string, name: string] {
    $name | save -f ($dir | path join $name)
    git $dir add "-A"
    git $dir "-c" "user.name=t" "-c" "user.email=t@t" commit "-q" "-m" $name
}

def fire [cwd: string, source: string = "startup", env_: record = {}]: nothing -> record {
    let out = with-env $env_ {
        { session_id: "bntest", source: $source, cwd: $cwd, hook_event_name: "SessionStart" }
            | to json -r | nu --stdin $HOOK | complete
    }
    let text = try { $out.stdout | from json | get hookSpecificOutput.additionalContext } catch { "" }
    { nudged: ($text | is-not-empty), text: $text, exit: $out.exit_code, stderr: $out.stderr }
}

def main [] {
    let root = $nu.temp-dir | path join "ctx-flow-test-branch"
    rm -rf $root
    mkdir $root
    let origin = $root | path join "origin"
    let a = $root | path join "a"
    let b = $root | path join "b"
    git $root init "-q" "--bare" "--initial-branch=main" $origin
    git $root clone "-q" $origin $a
    commit $a one
    git $a push "-q" "-u" origin main
    git $root clone "-q" $origin $b                 # sets origin/HEAD → main

    mut cases = []

    # 1. current: b is at origin/main, nothing to say.
    $cases ++= [["current, silent" (fire $b) false ""]]

    # 2. a pushes; b is one behind its upstream (which is also the base).
    commit $a two
    git $a push "-q" origin main
    $cases ++= [["behind upstream" (fire $b) true "1 commit behind origin/main (fetched now)"]]
    git $b pull "-q" "--ff-only"

    # 3. a feature branch on b, pushed, then main moves on: behind the base only.
    git $b checkout "-q" "-b" feat
    commit $b feat1
    git $b push "-q" "-u" origin feat
    commit $a three
    commit $a four
    git $a push "-q" origin main
    $cases ++= [["behind base" (fire $b) true "2 commits behind origin/main (fetched now)"]]

    # 4. unpushed work only: not a nudge.
    commit $b feat2
    git $b push "-q" origin feat
    git $b pull "-q" "--no-rebase" origin main      # now current with main
    git $b push "-q" origin feat
    commit $b feat3                                 # one unpushed, nothing behind
    $cases ++= [["unpushed only, silent" (fire $b) false ""]]

    # 5. behind upstream on the feature branch AND unpushed: both in one line.
    git $a fetch "-q" origin
    git $a checkout "-q" "-b" feat origin/feat
    commit $a feat-from-a
    git $a push "-q" origin feat
    $cases ++= [["behind upstream, unpushed" (fire $b) true "1 commit behind origin/feat, 1 commit unpushed (fetched now)"]]

    # 6. fetch skipped: the same counts, from the fetch case 5 already did.
    $cases ++= [["fetch skipped" (fire $b "startup" { CTX_FLOW_BRANCH_FETCH_SECS: "0" }) true "(not fetched)"]]

    # 7. a local-only branch has no upstream.
    git $b checkout "-q" "-b" local
    $cases ++= [["no upstream" (fire $b) true "no upstream"]]

    # 8. detached HEAD, compact, outside a repo: silent.
    git $b checkout "-q" "--detach"
    $cases ++= [["detached, silent" (fire $b) false ""]]
    git $b checkout "-q" feat
    $cases ++= [["compact, silent" (fire $b "compact") false ""]]
    $cases ++= [["not a repo, silent" (fire $root) false ""]]

    mut failed = 0
    for c in $cases {
        let name = $c.0
        let r = $c.1
        let expect = $c.2
        let needle = $c.3
        let ok = ($r.nudged == $expect) and ($r.exit == 0) and ($r.text | str contains $needle)
        if not $ok { $failed += 1 }
        print $"(if $ok { 'ok  ' } else { 'FAIL' }) ($name)  → ($r.text | default --empty '<silent>')"
        if not $ok and ($r.stderr | is-not-empty) { print $"     stderr: ($r.stderr)" }
        if $r.nudged and ($r.text | str length) > 160 {
            $failed += 1
            print $"FAIL ($name): text is (($r.text | str length)) chars \(cap 160\)"
        }
    }
    rm -rf $root
    if $failed > 0 { print $"($failed) failure\(s\)"; exit 1 }
    print $"all (($cases | length)) cases pass"
}
