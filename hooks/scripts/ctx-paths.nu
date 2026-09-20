#!/usr/bin/env nu
# Resolve the shared root and the agmem branch tag exactly the way the hooks
# and doc-put.nu resolve them.
#
# Two implementations of the slug rule drift, and when they drift they fail
# silently: on `release/v1.2.3+build`, a checkpoint that tags claims
# `branch:release-v1.2.3+build` while the briefing announces
# `branch:release-v1.2.3-build` is a checkpoint that is never recalled. One
# resolver, called by every side, is the only version that stays correct.
#
# Usage, from anywhere inside the repo:
#     nu ctx-paths.nu            # KEY=VALUE lines, shell-friendly
#     nu ctx-paths.nu --json
#     nu ctx-paths.nu --tag      # the branch tag alone; nothing on a detached HEAD
const COMMON = path self "_common.nu"
use $COMMON *

def main [--json, --tag]: nothing -> nothing {
    let r = paths { cwd: $env.PWD }
    if $tag {
        if $r.tag != null { print $r.tag }
    } else if $json {
        print ($r | to json)
    } else {
        # BRANCH and TAG come back empty on a detached HEAD.
        $r | items {|key, value| print $"($key | str uppercase)=($value | default '')" } | ignore
    }
}
