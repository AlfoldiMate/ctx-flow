#!/usr/bin/env nu
# Everything /ctx-onboard can learn about a project without asking: languages
# and their ast-grep status, the build system, CI, the forge, the CLIs already
# on this machine, what the .claude folder holds today (and which agent stubs
# are still unfilled), any MCP servers the project declares, and — through
# usage.nu — where past sessions actually spent their tokens.
#
# Read-only, deterministic, one JSON record on stdout. The skill reads it and
# proposes; nothing here decides anything. A fresh project with no history
# and no .claude beyond the seed is the normal case, not an error.
#
# Usage, from the project root:
#     nu .claude/scripts/onboard-scan.nu            # JSON
#     nu .claude/scripts/onboard-scan.nu --table    # the same, readable
const GRAMMARS = path self "grammars.nu"
const USAGE = path self "usage.nu"
use $GRAMMARS [project-langs]

# Build systems by their marker file, first match wins per row.
const BUILD_MARKERS = [
    [file, system, test, lint];
    ["Cargo.toml"        rust     "cargo test --workspace"      "cargo clippy --workspace --all-targets && cargo fmt --check"]
    ["package.json"      node     "npm test"                    "npm run lint"]
    ["pyproject.toml"    python   "pytest"                      "ruff check ."]
    ["go.mod"            go       "go test ./..."               "go vet ./..."]
    ["*.sln"             dotnet   "dotnet test"                 "dotnet format --verify-no-changes"]
    ["*.csproj"          dotnet   "dotnet test"                 "dotnet format --verify-no-changes"]
    ["build.gradle"      gradle   "./gradlew test"              "./gradlew check"]
    ["build.gradle.kts"  gradle   "./gradlew test"              "./gradlew check"]
    ["pom.xml"           maven    "mvn test"                    "mvn verify"]
    ["mix.exs"           elixir   "mix test"                    "mix format --check-formatted"]
    ["CMakeLists.txt"    cmake    "ctest --test-dir build"      ""]
    ["Makefile"          make     "make test"                   "make lint"]
    ["justfile"          just     "just test"                   "just lint"]
]

# CLIs the framework knows how to route through, with what each one is for.
const CLIS = [
    [cli, role];
    [gh              "GitHub forge — tracker agent, PR/issue reads via --json"]
    [glab            "GitLab forge — tracker agent"]
    [acli            "Jira — tracker agent"]
    [jira            "Jira (alt CLI) — tracker agent"]
    [playwright-cli  "browser driving as shell commands — browser agent"]
    [rtk             "compresses Bash output through a PreToolUse hook"]
    [cargo           "Rust build/test — runner agent"]
    [npm             "Node build/test — runner agent"]
    [pnpm            "Node build/test — runner agent"]
    [bun             "Node build/test — runner agent"]
    [uv              "Python env/test — runner agent"]
    [pytest          "Python tests — runner agent"]
    [go              "Go build/test — runner agent"]
    [dotnet          ".NET build/test — runner agent"]
    [docker          "containers — runner agent"]
    [kubectl         "clusters — a dedicated agent if used"]
    [just            "task runner — runner agent"]
    [make            "task runner — runner agent"]
    [nvim            "editor bridge — LSP diagnostics via a dedicated agent"]
    [tree-sitter     "grammar builds — /ctx-grammar"]
]

def exists-glob [pat: string]: nothing -> bool {
    (try { glob --depth 1 $pat } | default [] | is-not-empty)
}

def build-systems []: nothing -> table {
    $BUILD_MARKERS | where {|m| exists-glob $m.file } | select system test lint | uniq-by system
}

def ci []: nothing -> list<string> {
    [
        [".github/workflows" "github-actions"]
        [".gitlab-ci.yml" "gitlab-ci"]
        ["azure-pipelines.yml" "azure-pipelines"]
        [".circleci" "circleci"]
        ["Jenkinsfile" "jenkins"]
        [".buildkite" "buildkite"]
    ] | where {|p| $p.0 | path exists } | each {|p| $p.1 }
}

def forge []: nothing -> record {
    let url = try { ^git remote get-url origin | complete | get stdout | str trim } | default ""
    let host = if ($url | str contains "github.com") { "github"
        } else if ($url | str contains "gitlab") { "gitlab"
        } else if ($url | str contains "bitbucket") { "bitbucket"
        } else if ($url | str contains "dev.azure.com") { "azure"
        } else if ($url | is-empty) { "none" } else { "other" }
    let layout = try { ^git rev-parse --git-common-dir | complete | get stdout | str trim | path basename } | default ""
    { remote: $url, host: $host, bare_worktree_layout: ($layout == ".bare") }
}

def clis []: nothing -> table {
    $CLIS | insert installed {|c| (which $c.cli | is-not-empty) }
}

# What the .claude folder already holds, and which stubs still carry the
# `<!-- ctx-onboard:` marker the seed ships with.
def claude-dir []: nothing -> record {
    let root = ".claude"
    if ($root | path expand | path type) != "dir" { return { present: false } }  # `.claude` may be a symlink
    let agents = try { glob ($root | path join "agents" "*.md") } | default []
    let stubs = $agents | where {|f| open --raw $f | str contains "<!-- ctx-onboard:" } | each {|f| $f | path parse | get stem }
    let skills = try { ls ($root | path join "skills") | where type == dir | get name | each {|d| $d | path basename } } | default []
    let hooks = try { open ($root | path join "settings.json") | get -o hooks | default {} | items {|ev, hs| { event: $ev, n: ($hs | each {|h| $h.hooks | length } | math sum) } } } | default []
    let claude_md = try { open --raw ($root | path join "CLAUDE.md") | str length } | default 0
    let markers = try { open --raw ($root | path join "CLAUDE.md") | str contains "<!-- ctx-onboard:" } | default false
    {
        present: true
        agents: ($agents | each {|f| $f | path parse | get stem })
        unfilled_stubs: $stubs
        skills: $skills
        hooks: $hooks
        claude_md_bytes: $claude_md
        claude_md_has_marker: $markers
        scripts: (try { glob ($root | path join "scripts" "*.nu") | each {|f| $f | path basename } } | default [])
    }
}

def mcp []: nothing -> list<string> {
    try { open ".mcp.json" | get -o mcpServers | default {} | columns } | default []
}

def main [--table]: nothing -> nothing {
    let usage = try { ^nu $USAGE --all --json | complete | get stdout | from json } catch { null }
    let scan = {
        project: ($env.PWD | path basename)
        languages: (project-langs)
        build: (build-systems)
        ci: (ci)
        forge: (forge)
        clis: (clis)
        claude: (claude-dir)
        mcp_servers: (mcp)
        usage: $usage
    }
    if $table {
        print $"project: ($scan.project)   forge: ($scan.forge.host)   ci: ($scan.ci | str join ', ')   bare layout: ($scan.forge.bare_worktree_layout)"
        print ($scan.languages | table -i false)
        print ($scan.build | table -i false)
        print ($scan.clis | where installed | table -i false)
        print ($scan.claude | table -e -i false)
        if ($usage | describe) == "record" { print ($usage.summary | table -e -i false); print ($usage.tools | first 8 | table -i false) }
    } else {
        print ($scan | to json)
    }
}
