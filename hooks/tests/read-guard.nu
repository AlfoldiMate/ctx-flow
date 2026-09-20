#!/usr/bin/env nu
# Cases for read-guard.nu, run from anywhere:
#
#     nu .claude/hooks/tests/read-guard.nu
#
# Each case pipes a PreToolUse payload through the hook exactly as Claude Code
# would and checks whether it came back with a deny. The files are synthetic:
# `big.rs` (900 lines, ~30 kB) is a flood, `small.toml` is not. Exits 1 on
# the first mismatch, so it can sit in a pre-push check.
const HOOK = path self "../scripts/read-guard.nu"

def hook [cwd: string, tool: string, input: record]: nothing -> record {
    let payload = { session_id: "t", cwd: $cwd, tool_name: $tool, tool_input: $input } | to json -r
    let out = $payload | nu --stdin $HOOK | complete
    let denied = ($out.stdout | str contains '"deny"')
    let reason = try { $out.stdout | from json | get hookSpecificOutput.permissionDecisionReason } catch { "" }
    { denied: $denied, reason: $reason, exit: $out.exit_code, stderr: $out.stderr }
}

def main [] {
    let dir = $nu.temp-dir | path join "ctx-flow-test-read-guard"
    rm -rf $dir
    mkdir ($dir | path join "src")
    (1..900 | each {|i| $"fn f($i)\(\) -> u32 { ($i) } // padding to keep every line comfortably wide" }
        | str join "\n" | save -f ($dir | path join "big.rs"))
    "[package]\nname = \"x\"\nversion = \"0.1.0\"\n" | save -f ($dir | path join "small.toml")
    let BIG = "big.rs"

    let read = {|file, rest| hook $dir Read ({ file_path: ($dir | path join $file) } | merge $rest) }
    let bash = {|command| hook $dir Bash { command: $command } }

    let cases = [
        # --- Read ---
        [name, result, expect];
        ["bare Read of big.rs"                   (do $read big.rs {})                          true]
        ["Read big.rs with offset+limit"         (do $read big.rs {offset: 40, limit: 120})    false]
        ["Read big.rs with limit only"           (do $read big.rs {limit: 2000})               false]
        ["bare Read of small.toml"               (do $read small.toml {})                      false]
        ["bare Read of a missing file"           (do $read does/not/exist.rs {})               false]
        ["bare Read of a png"                    (hook $dir Read {file_path: "/tmp/x.png"})    false]
        # --- Bash ---
        ["cat big.rs"                            (do $bash $"cat ($BIG)")                      true]
        ["cat small.toml"                        (do $bash "cat small.toml")                   false]
        ["cat big.rs | wc -l"                    (do $bash $"cat ($BIG) | wc -l")              false]
        ["cat with a quoted path"                (do $bash $"cat '($BIG)'")                    true]
        ["cd then cat big.rs"                    (do $bash $"cd src && cat ../($BIG)")         false]
        ["sed -n windowed"                       (do $bash $"sed -n '40,120p' ($BIG)")         false]
        ["sed -n wide window"                    (do $bash $"sed -n '1,900p' ($BIG)")          true]
        ["sed -n to end"                         (do $bash $"sed -n '10,$p' ($BIG)")           true]
        ["sed -n regex print"                    (do $bash $"sed -n '/fn /p' ($BIG)")          false]
        ["sed substitution preview"              (do $bash $"sed 's/a/b/' ($BIG)")             true]
        ["sed -i edit"                           (do $bash $"sed -i '' 's/a/b/' ($BIG)")       false]
        ["head default"                          (do $bash $"head ($BIG)")                     false]
        ["head -n 50"                            (do $bash $"head -n 50 ($BIG)")               false]
        ["head -500"                             (do $bash $"head -500 ($BIG)")                true]
        ["tail -n 20"                            (do $bash $"tail -n 20 ($BIG)")               false]
        ["tail -n +1"                            (do $bash $"tail -n +1 ($BIG)")               true]
        ["heredoc write"                         (do $bash $"cat > /tmp/x.rs <<'EOF'\nfn main\(\) {}\nEOF")  false]
        ["redirect"                              (do $bash $"cat ($BIG) > /tmp/copy.rs")       false]
        ["cat via variable"                      (do $bash 'cat "$CLAUDE_PROJECT_DIR/big.rs"')  false]
        ["grep unaffected"                       (do $bash $"grep -n fn ($BIG)")               false]
    ]

    mut failed = 0
    for c in $cases {
        let ok = ($c.result.denied == $c.expect) and ($c.result.exit == 0)
        if not $ok { $failed += 1 }
        let mark = if $ok { "ok  " } else { "FAIL" }
        print $"($mark) ($c.name)  → denied=($c.result.denied) expected=($c.expect)"
        if not $ok and ($c.result.stderr | is-not-empty) { print $"     stderr: ($c.result.stderr)" }
        if $c.result.denied and ($c.result.reason | str length) > 200 {
            $failed += 1
            print $"FAIL ($c.name): reason is (($c.result.reason | str length)) chars \(cap 200\)"
        }
    }
    rm -rf $dir
    if $failed > 0 { print $"($failed) failure\(s\)"; exit 1 }
    print $"all (($cases | length)) cases pass"
}
