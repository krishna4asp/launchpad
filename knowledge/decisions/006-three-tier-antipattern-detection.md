# ADR-006: Three-Tier Anti-Pattern Detection

## Status

Accepted

## Context

The kit watches for four anti-patterns that Claude (and people) commonly write:

| Rule  | Pattern                                             | Pre-commit hook | `/verify` | Analyzers in the build |
| ----- | --------------------------------------------------- | --------------- | --------- | ---------------------- |
| AP001 | `async void`                                        | text scan       | yes       | optional               |
| AP002 | `.Result` / `.Wait()` / `.GetAwaiter().GetResult()` | text scan       | yes       | optional               |
| AP003 | `new HttpClient()`                                  | text scan       | yes       | optional               |
| AP004 | `DateTime.Now` / `UtcNow`                           | text scan       | yes       | optional               |

The obvious question, raised in the upstream project ([issue #23]): if a compiler-backed analyzer is
strictly more precise than text matching, why does the pre-commit hook match
text at all?

The question is correct on precision. `SyntaxTree` and `SemanticModel` know
things a regex cannot: whether the receiver of `.Result` is actually a `Task<T>`
or a domain `Result<T>`; whether a token sits inside a comment, a verbatim
string, or a raw string literal; whether an `async void` method carries an
`(object, EventArgs)` event-handler signature.

The constraint is not precision — it is where each tier can run.

### Evaluation Criteria

1. **Reachability.** Can the tier run in the context where the check is needed?
2. **Latency.** Does it fit the interaction it gates?
3. **Setup cost.** What must a user install or configure before it works?
4. **Precision.** How many false positives does it produce?

### Alternatives Considered

**.NET analyzer package referenced by the user's build (`.csproj` +
`Directory.Build.props`).** Maximum precision, IDE squiggles, works in CI. But it
requires a `PackageReference` in every consuming project and a successful
compile to produce any diagnostic — which the broken-build case cannot supply.
It is the strongest option and is not ruled out; it is simply not a substitute
for a commit gate.

**Shell out to `dotnet build` from the pre-commit hook.** Reachable, but a
restore plus compile costs seconds to tens of seconds on a real solution, in
front of every single commit — and fails outright when the build is red, which
is exactly when a developer is committing work-in-progress.

**Drop the pre-commit hook entirely.** Leaves the window between "Claude wrote
it" and "it is in history" ungated for anyone not running `/verify` first.

## Decision

Keep three tiers, each scoped to what it can actually reach, with a single
shared vocabulary: **rule IDs and severities are identical across tiers.**

| Tier                                 | Where it runs              | Cost                   | Precision        | Purpose                  |
| ------------------------------------ | -------------------------- | ---------------------- | ---------------- | ------------------------ |
| 1. `hooks/pre-commit-antipattern.sh` | git pre-commit, bare shell | milliseconds, no build | high, incomplete | Last gate before history |
| 2. `/verify`                         | Claude Code session        | scoped `dotnet build`  | broad            | The review pass          |
| 3. Analyzer packages in the build    | IDE + CI                   | full compile           | exhaustive       | Team-wide enforcement    |

Tier 2 runs `dotnet build` to surface compiler and analyzer warnings, then
searches the changed files for the patterns catalogued in
`knowledge/common-antipatterns.md` and reviews each hit in context, so it can
judge cases a text scanner must skip.

Tier 1 is text-based **because it must be**, and it is written to earn that
position:

- **It scans only the lines the commit adds.** A pre-existing violation in an
  untouched line is not this commit's problem. Whole-file scanning made every
  edit to a legacy file un-committable.
- **It strips comments and string literals** with a state machine that tracks
  block comments, verbatim strings, and raw strings across line boundaries.
- **It classifies files by kind** — generated files are skipped, and each rule
  applies only to the file kinds where it is meaningful (seeders, for example,
  are exempt from AP004).
- **It stays silent when it cannot be certain.** `.Result` is reported only when
  the receiver is visibly task-like (a call expression, or an identifier ending
  in `Task`). `new HttpClient(handler)` is not reported, because it is the
  documented `IHttpClientFactory` composition pattern. Tier 1 accepts false
  negatives to guarantee zero false positives; tiers 2 and 3 catch what tier 1
  declines to guess.

### When to deviate

- **Adopting the kit on an existing codebase?** Set
  `CWM_ANTIPATTERN_WARN_ONLY=1` to report without blocking.
- **A finding is genuinely correct-by-design?** Suppress the line with
  `// cwm:ignore AP004`, not `--no-verify`.
- **Need enforcement your teammates cannot skip?** That is tier 3. A git hook
  lives in `.git/`, is not cloned, and is one `--no-verify` from irrelevant. CI
  is the only tier that binds a team.

### Adding a rule

Add it to `knowledge/common-antipatterns.md` first, so `/verify` looks for it.
Port it to tier 1 only if it can be recognized from a single sanitized line with
no semantic model. Rules that cannot meet that bar stay out of tier 1 — an
incomplete tier 1 is correct by design.

## Consequences

### Positive

- Every tier runs where it is actually reachable, at a latency that fits.
- Shared rule IDs mean a hook finding and a `/verify` finding are the same
  finding — `AP002` means one thing across the kit.
- Tier 1 needs no NuGet package, no build, and no Claude Code session.
- Diff-scoped scanning makes the hook adoptable on a legacy codebase.

### Negative

- Detection rules are described in more than one place: the awk scanner and the
  anti-pattern catalogue.
- Tier 1 has real blind spots: multi-line method signatures, `.Wait()` on a
  plainly-named `Task` variable, interpolation holes inside string literals.
- Without analyzer packages (tier 3), no tier is semantically exhaustive.
- Three tiers is more surface area to document than one.

### Mitigations

- The awk scanner and the anti-pattern catalogue share the same `APnnn` IDs, so
  drift is visible in review.
- Blind spots are deliberate and covered by tier 2, which `/verify` runs — the
  hook is a gate, never the audit.
- `hooks/README.md` carries the tier table for users who never read ADRs.

[issue #23]: https://github.com/codewithmukesh/dotnet-claude-kit/issues/23
