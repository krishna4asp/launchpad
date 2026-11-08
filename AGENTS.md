# Agent Routing & Orchestration

> How Claude Code routes requests to launchpad's specialist agents and skills, and how they work together.

## Agent Roster

| Agent | File | Primary Domain |
|-------|------|---------------|
| dotnet-architect | `agents/dotnet-architect.md` | Architecture, project structure, module boundaries |
| api-designer | `agents/api-designer.md` | Controller-based REST APIs, OpenAPI, versioning, auth policies |
| ef-core-specialist | `agents/ef-core-specialist.md` | Database, queries, migrations, EF Core patterns |
| test-engineer | `agents/test-engineer.md` | Test strategy, xUnit v3, WebApplicationFactory, SQLite in-memory |
| security-auditor | `agents/security-auditor.md` | Authentication, authorization, OWASP, secrets |
| performance-analyst | `agents/performance-analyst.md` | Async patterns, allocations, caching |
| code-reviewer | `agents/code-reviewer.md` | Multi-dimensional code review |
| build-error-resolver | `agents/build-error-resolver.md` | Autonomous build error fixing |
| refactor-cleaner | `agents/refactor-cleaner.md` | Systematic dead code removal and cleanup |

## Routing Table

Match user intent to an agent. When several agents could handle a request, the first match wins.

| User Intent Pattern | Primary Agent | Support Agent |
|---|---|---|
| "set up project", "folder structure", "architecture" | dotnet-architect | — |
| "choose architecture", "which architecture", "architecture decision" | dotnet-architect | — |
| "add module", "split into modules", "bounded context" | dotnet-architect | — |
| "init project", "new project", "generate CLAUDE.md" | dotnet-architect | — |
| "scaffold feature", "create feature", "add feature", "add endpoint" | dotnet-architect | api-designer, ef-core-specialist |
| "create controller", "API route", "OpenAPI", "Scalar" | api-designer | — |
| "versioning", "rate limiting", "CORS" | api-designer | — |
| "database", "migration", "query", "DbContext", "EF" | ef-core-specialist | — |
| "update packages", "upgrade NuGet", "upgrade .NET" | ef-core-specialist | — |
| "write tests", "test strategy", "coverage", "xUnit", "WebApplicationFactory" | test-engineer | — |
| "security", "authentication", "JWT", "OIDC", "authorize", "secrets" | security-auditor | — |
| "performance", "slow endpoint", "memory", "allocations" | performance-analyst | — |
| "caching", "HybridCache", "output cache" | performance-analyst | — |
| "review this code", "PR review", "review changes", "code quality" | code-reviewer | — |
| "health check", "analyze project", "project report" | code-reviewer | dotnet-architect |
| "conventions", "coding style", "detect patterns", "code consistency" | code-reviewer | — |
| "refactor" | code-reviewer | dotnet-architect |
| "build errors", "fix build", "won't compile" | build-error-resolver | — |
| "clean up", "dead code", "unused code", "de-sloppify" | refactor-cleaner | — |

## Skill Loading Order

Agents load skills in dependency order, core skills first.

### Default Load Order (All Agents)

1. `modern-csharp` — always loaded, baseline C# 14 knowledge
2. Agent-specific skills (see the map below and each agent file)

### Per-Agent Skill Maps

| Agent | Skills |
|-------|--------|
| dotnet-architect | modern-csharp, architecture-advisor, project-structure, scaffold, project-setup + conditional: vertical-slice, clean-architecture, ddd |
| api-designer | modern-csharp, controller-based-apis, api-versioning, openapi, authentication, error-handling |
| ef-core-specialist | modern-csharp, ef-core, configuration, migrate |
| test-engineer | modern-csharp, testing |
| security-auditor | modern-csharp, authentication, configuration |
| performance-analyst | modern-csharp, caching |
| code-reviewer | modern-csharp, code-review, convention-learner + contextual (skills relevant to the files under review, incl. clean-architecture, ddd) |
| build-error-resolver | modern-csharp, build-fix + contextual: ef-core, dependency-injection |
| refactor-cleaner | modern-csharp, de-sloppify + contextual: testing, ef-core |

## Tool Preferences

Agents search before they read, so they spend tokens only on the code that matters.

| Task | Use | Instead Of |
|------|-----|-----------|
| Find where a type is defined | Grep for `class Name\b` / `record Name\b`, then read that line range | Reading whole files |
| Find all usages of a type or method | Grep for the name across `*.cs` | Opening files one by one |
| Find implementations of an interface | Grep for `: IName` | Reading every service class |
| Understand project dependencies | `dotnet list <project> reference` or Grep `<ProjectReference` in `*.csproj` | Guessing from folder names |
| Check for compilation errors and warnings | `dotnet build --no-restore`, scoped to the changed project | Building the whole solution every time |
| Find unused code | IDE0051/IDE0052 build warnings + Grep confirming zero references | Manual inspection |
| Scan for .NET anti-patterns | Grep for the patterns in `knowledge/common-antipatterns.md` | Ad-hoc review |
| Map routes and their auth | Grep `[Route`, `[Http*`, `[Authorize`, `[AllowAnonymous]` in `*Controller.cs` | Reading every controller |
| Audit DI registrations | Grep `AddScoped\|AddTransient\|AddSingleton\|AddKeyed` | Reading all of `Program.cs` and its extensions |
| Audit NuGet packages | `dotnet list package --outdated / --vulnerable / --include-transitive` | Parsing `.csproj` files by hand |

## Cross-Agent Skills

These skills aren't tied to one agent. Any agent can load them when the context calls for it.

| Skill | When to Load |
|-------|-------------|
| `instinct-system` | After any user correction, when a pattern repeats across sessions, or to log a non-obvious discovery; has status/export/import modes |
| `wrap-up` | Session start (load handoff) and session end (write `.claude/handoff.md`, capture learnings) |
| `checkpoint` | Mid-session save before risky changes or task switches — commit + brief handoff |
| `workflow-mastery` | Context running low, large codebases, parallel workflows, subagent strategy |
| `convention-learner` | Detect and enforce project-specific conventions in new code |

Model selection guidance lives in the always-loaded `.claude/rules/agents.md`.

### Cross-Agent Skill Routing

| User Intent Pattern | Skill |
|---|---|
| "learn from mistakes", "remember this", "gotcha", "show instincts", "what have you learned" | instinct-system |
| "wrap up", "done for today", "handoff", "start session", "load handoff" | wrap-up |
| "save progress", "checkpoint", "pause here" | checkpoint |
| "context", "running out of tokens", "too many files" | workflow-mastery |
| "what should I review", "blast radius" | code-review |
| "fix build loop", "keep fixing", "auto-fix" | build-fix |

## Slash Commands

Each workflow skill registers its own slash command and carries its method inline.

| Command | Supporting Skills | Primary Agent | Purpose |
|---------|------------------|---------------|---------|
| `/dotnet-init` | project-setup | dotnet-architect | Interactive project initialization |
| `/spec` | — | — | Relentless questioning → agreed spec in `docs/specs/` |
| `/plan` | architecture-advisor | dotnet-architect | Architecture-aware planning (consumes approved specs) |
| `/scaffold` | — | dotnet-architect | Architecture-aware feature scaffolding |
| `/tdd` | testing | test-engineer | Red-green-refactor workflow |
| `/verify` | — | — | 7-phase verification pipeline |
| `/build-fix` | — | build-error-resolver | Bounded build-fix and test-fix loops |
| `/code-review` | convention-learner | code-reviewer | Blast-radius-prioritized code review |
| `/arch-check` | architecture-advisor | dotnet-architect | Architecture conformance check |
| `/health-check` | — | code-reviewer | Graded project health report |
| `/security-scan` | — | security-auditor | OWASP + secrets + dependency audit |
| `/outdated` | — | — | Dependency health: staleness, CVEs, license traps |
| `/migrate` | ef-core | ef-core-specialist | EF Core schema, .NET version, and NuGet migrations |
| `/de-sloppify` | — | refactor-cleaner | Systematic code cleanup |
| `/checkpoint` | — | — | Mid-session save (commit + handoff) |
| `/wrap-up` | instinct-system | — | Session handoff lifecycle (end + start) |

## Conflict Resolution

When two agents could handle a request:

1. **Architecture beats implementation** — "How should I structure the payment module?" → dotnet-architect, even though api-designer could handle the endpoint part.
2. **Specific beats general** — "How do I optimize this EF query?" → ef-core-specialist, not performance-analyst.
3. **Security is always surfaced** — Even when another agent is primary, flag security issues for the security-auditor.
4. **Code review is holistic** — The code-reviewer loads skills based on what's in the change.

## Token Budget Guidance

See the `workflow-mastery` skill for detailed context-management strategies.

- **Small requests** (one pattern or fix): load 1–2 skills; search before reading.
- **Medium requests** (a feature): load 3–4 skills; search the existing code before writing new code.
- **Large requests** (architecture review): load all relevant skills; check project references first to understand the solution's shape.

## Response Patterns

All agents should:

1. **Lead with the recommended approach** — don't list every option equally.
2. **Show code first, explain after** — developers want the solution, then the reasoning.
3. **Flag anti-patterns proactively** — if existing code has problems, say so.
4. **Point to skills** — reference the relevant skill for deeper reading.
5. **Search before reading** — use Grep/Glob to find the code before opening files.
