# Hooks

Shell scripts that keep code generated with launchpad in shape. They fall into three groups:

1. **Claude Code hooks**, which run automatically while Claude works (wired in `hooks.json`).
2. **Git pre-commit hooks**, which you install in your project's repository.
3. **Manual helpers**, which you run when you need them.

All scripts need `bash`. On Windows, use Git Bash. `jq` is optional: the scripts use it to read hook input when it's installed and fall back to `sed` when it isn't.

## 1. Claude Code hooks

These are registered in [`hooks.json`](hooks.json) and load with the plugin. There's nothing to set up.

| Script | Event | What it does |
|--------|-------|--------------|
| `pre-bash-guard.sh` | `PreToolUse` on `Bash` | Blocks destructive commands before they run: force push, `git reset --hard`, `git clean -f`, `git checkout .`, and `rm -rf` in a project directory. The reason is sent back to Claude. |
| `post-edit-format.sh` | `PostToolUse` on `Edit\|Write` | Runs `dotnet format` on the `.cs` file that was just edited. Ignores other file types. |
| `post-scaffold-restore.sh` | `PostToolUse` on `Edit\|Write` | Runs `dotnet restore` after a `.csproj` file is created or changed. |

Exit codes follow Claude Code conventions: `0` allows the action and `2` blocks it.

## 2. Git pre-commit hooks

Git hooks run outside Claude Code, so you install them per repository. Copy the scripts into your project, keeping `lib/` next to `pre-commit-antipattern.sh`:

```bash
mkdir -p tools/hooks/lib
cp /path/to/launchpad/hooks/pre-commit-format.sh       tools/hooks/
cp /path/to/launchpad/hooks/pre-commit-antipattern.sh  tools/hooks/
cp /path/to/launchpad/hooks/lib/antipattern-scan.awk   tools/hooks/lib/
```

Then create `.git/hooks/pre-commit`:

```bash
#!/usr/bin/env bash
set -e
bash tools/hooks/pre-commit-format.sh
bash tools/hooks/pre-commit-antipattern.sh
```

```bash
chmod +x .git/hooks/pre-commit
```

| Script | What it does |
|--------|--------------|
| `pre-commit-format.sh` | Runs `dotnet format --verify-no-changes` and fails the commit if any files need formatting. |
| `pre-commit-antipattern.sh` | Scans only the lines the commit **adds** to `.cs` files for anti-patterns AP001–AP004 (see below). Comments and string literals are ignored, and generated files are skipped. |

### Anti-pattern rules

| Rule | Pattern | Severity |
|------|---------|----------|
| AP001 | `async void` (except event handlers) | error |
| AP002 | Blocking on async work (`.Result`, `.Wait()`, `.GetAwaiter().GetResult()`) | error |
| AP003 | `new HttpClient()` instead of `IHttpClientFactory` | warning |
| AP004 | `DateTime.Now` / `DateTime.UtcNow` instead of `TimeProvider` | warning |

To suppress a single line, add `// cwm:ignore` or `// cwm:ignore AP004` at its end. To report findings without blocking the commit, set `CWM_ANTIPATTERN_WARN_ONLY=1`.

Exit codes: `0` means no issues, `1` blocks the commit, and `2` means the hook couldn't run (for example, `lib/` is missing).

Don't bypass these hooks with `--no-verify`. Fix what they report (see `.claude/rules/hooks.md`).

## 3. Manual helpers

| Script | Usage | What it does |
|--------|-------|--------------|
| `post-test-analyze.sh` | `dotnet test 2>&1 \| bash hooks/post-test-analyze.sh` | Sums passed, failed and skipped tests across projects and lists the failures. |
| `pre-build-validate.sh` | `bash hooks/pre-build-validate.sh [solution-dir]` | Checks the solution layout: `.sln`/`.slnx`, `Directory.Build.props`, `global.json`, `.editorconfig`, test projects, and consistent target frameworks. |

## Detection tiers

Anti-patterns are caught at three levels, and the rule IDs are the same in each (see [ADR-006](../knowledge/decisions/006-three-tier-antipattern-detection.md)):

| Tier | Where it runs | Cost | Purpose |
|------|---------------|------|---------|
| 1. `pre-commit-antipattern.sh` | git pre-commit | milliseconds, no build | Last gate before history |
| 2. `/verify` | Claude Code session | scoped `dotnet build` | The review pass |
| 3. Analyzer packages in the build | IDE + CI | full compile | Team-wide enforcement |
