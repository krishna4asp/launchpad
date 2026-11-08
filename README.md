# launchpad

**A Claude Code plugin that teaches Claude to build .NET 10 applications the way a senior .NET engineer would.**

43 skills • 9 specialist agents • 10 rules • 4 project templates • quality hooks

Built for .NET 10 / C# 14, controller-based REST APIs, and AWS.

[Installation](#installation) • [Quick Start](#quick-start) • [Commands](#slash-commands) • [Skills](#knowledge-skills) • [Agents](#agents) • [Rules](#rules) • [Templates](#templates) • [Hooks](#hooks) • [Repository Layout](#repository-layout)

---

## Why launchpad?

Out of the box, Claude Code writes generic C#. It reaches for `DateTime.Now`, wraps EF Core in a repository, drops `CancellationToken`s, defines endpoints inline in `Program.cs`, and picks an architecture without asking anything about your project.

launchpad gives Claude an opinionated set of .NET conventions and workflows so the first draft is already close to what you'd merge:

- **Asks before choosing an architecture** — Vertical Slice, Clean Architecture, DDD, or Modular Monolith, based on your team and domain.
- **Controller-based REST APIs** — attribute-routed `[ApiController]` classes in feature folders, discovered by `MapControllers()`. No `Map*` calls in `Program.cs`.
- **Modern C# 14** — primary constructors, records, collection expressions, pattern matching, `sealed` and `internal` by default.
- **EF Core used directly** — `DbContext` injected as-is, compiled queries on hot paths, no generic repository wrappers.
- **Explicit errors** — Result pattern for expected failures, ProblemDetails (RFC 9457) for every HTTP error.
- **AWS-first configuration** — secrets from Systems Manager Parameter Store / Secrets Manager and the default AWS credential chain, never from source.
- **Real tests** — `WebApplicationFactory` integration tests against a relational database, never the EF Core InMemory provider.

### Before and after

```csharp
// Without launchpad
public class OrderService
{
    private readonly IOrderRepository _repo;           // needless wrapper over EF Core

    public async Task<Order> CreateOrder(CreateOrderDto dto)
    {
        var order = new Order { CreatedAt = DateTime.Now };  // untestable clock
        await _repo.AddAsync(order);                         // no CancellationToken
        return order;                                        // leaks the entity
    }
}
```

```csharp
// With launchpad
[Route("api/orders")]
[Tags("Orders")]
[Authorize]
public sealed class OrdersController(ISender sender) : ApiControllerBase
{
    [HttpPost(Name = "CreateOrder")]
    [ProducesResponseType<OrderResponse>(StatusCodes.Status201Created)]
    [ProducesResponseType<ValidationProblemDetails>(StatusCodes.Status400BadRequest)]
    public async Task<ActionResult<OrderResponse>> Create(CreateOrderRequest request, CancellationToken ct)
    {
        var result = await sender.Send(new CreateOrder.Command(request.CustomerId, request.Items), ct);
        return result.IsSuccess
            ? CreatedAtRoute("GetOrder", new { id = result.Value.Id }, result.Value)
            : ToProblemDetails(result);
    }
}

internal sealed class CreateOrderHandler(AppDbContext db, TimeProvider clock)
    : IRequestHandler<CreateOrder.Command, Result<OrderResponse>>
{
    public async ValueTask<Result<OrderResponse>> Handle(CreateOrder.Command command, CancellationToken ct)
    {
        var order = Order.Create(command.CustomerId, command.Items, clock.GetUtcNow());
        db.Orders.Add(order);
        await db.SaveChangesAsync(ct);
        return new OrderResponse(order.Id, order.Total, order.CreatedAt);
    }
}
```

Thin controller, explicit auth, OpenAPI metadata, Result pattern, injected `TimeProvider`, `DbContext` used directly, and `CancellationToken` all the way down.

---

## Installation

### Prerequisites

- [Claude Code](https://claude.com/claude-code)
- .NET 10 SDK

### Install the plugin

Inside a Claude Code session:

```
/plugin marketplace add krishna4asp/launchpad
/plugin install launchpad
```

Or load it straight from a local clone (handy while developing the plugin):

```bash
git clone https://github.com/krishna4asp/launchpad.git
claude --plugin-dir ./launchpad
```

### Add the rules to your project

Rules are not loaded by the plugin automatically. Copy them into each project where you want them always on:

```bash
mkdir -p .claude/rules
cp /path/to/launchpad/.claude/rules/*.md .claude/rules/
```

---

## Quick Start

In your project folder (new or existing), run:

```
/dotnet-init
```

- **Existing project:** detects your solution and tech stack, asks a few architecture questions, and writes a tailored `CLAUDE.md`.
- **Empty folder:** asks what you're building, scaffolds the solution (`src/`, `tests/`, `Directory.Build.props`), then writes `CLAUDE.md`.

A typical feature loop from there:

```
/spec       → agree on what to build (saved to docs/specs/)
/plan       → architecture-aware implementation plan
/scaffold   → generate the feature slice and its tests
/verify     → build, analyzers, tests, security, format
/code-review
/wrap-up    → handoff notes for the next session
```

Prefer to set things up by hand? Copy a file from [`templates/`](#templates) to your project root as `CLAUDE.md` and fill in the placeholders.

---

## Slash Commands

Workflow skills you invoke by name. Each lives in `skills/<name>/SKILL.md`.

| Command | What it does |
|---------|--------------|
| `/dotnet-init` | Sets up a new or existing project and generates `CLAUDE.md` |
| `/spec` | Turns an idea into an agreed spec with acceptance criteria |
| `/plan` | Produces an architecture-aware implementation plan |
| `/scaffold` | Generates a complete feature slice for your architecture |
| `/tdd` | Red-green-refactor with xUnit v3 |
| `/verify` | 7-phase check: build → analyzers → anti-patterns → tests → security → format → diff |
| `/build-fix` | Bounded loop that drives a broken build or failing tests to green |
| `/code-review` | Multi-dimensional review, prioritised by blast radius |
| `/arch-check` | Verifies the code still follows its declared architecture |
| `/health-check` | Graded (A–F) report card across 8 quality dimensions |
| `/security-scan` | Six-layer scan: packages, secrets, auth, OWASP and more |
| `/outdated` | Stale packages, known CVEs, and commercial-license traps |
| `/migrate` | Guided EF Core schema and .NET version migrations |
| `/de-sloppify` | Seven-step cleanup: format, usings, warnings, dead code, sealing, tokens |
| `/checkpoint` | Mid-session commit plus a short handoff note |
| `/wrap-up` | End-of-session handoff capture |

---

## Knowledge Skills

Loaded automatically when Claude sees a matching task, or on demand by name.

| Area | Skills |
|------|--------|
| **Architecture** | `architecture-advisor`, `vertical-slice`, `clean-architecture`, `ddd`, `project-structure`, `project-setup` |
| **APIs** | `controller-based-apis`, `api-versioning`, `openapi`, `scalar`, `authentication` |
| **Language & core** | `modern-csharp`, `dependency-injection`, `configuration`, `error-handling` |
| **Data** | `ef-core`, `caching` |
| **Integration** | `httpclient-factory`, `resilience`, `messaging` |
| **Observability** | `logging`, `serilog` |
| **Testing** | `testing` |
| **Working with Claude** | `convention-learner`, `instinct-system`, `workflow-mastery` |

---

## Agents

Specialists that Claude can hand work to. Defined in `agents/`.

| Agent | Use it for |
|-------|-----------|
| `dotnet-architect` | Choosing an architecture, project structure, module boundaries |
| `api-designer` | Endpoint and contract design, versioning, OpenAPI |
| `ef-core-specialist` | Schema design, migrations, query performance |
| `test-engineer` | Test strategy and integration test infrastructure |
| `security-auditor` | Auth design, secrets handling, OWASP review |
| `performance-analyst` | Hot paths, caching, async correctness, allocations |
| `code-reviewer` | PR reviews and pre-merge quality gates |
| `build-error-resolver` | Fixing compiler errors systematically |
| `refactor-cleaner` | Dead code removal and tech-debt cleanup |

---

## Rules

Always-on guidance in `.claude/rules/`, copied into your project (see [Installation](#add-the-rules-to-your-project)).

| Rule | Highlights |
|------|-----------|
| `architecture.md` | Ask before choosing an architecture; controllers in feature folders; no repository over EF Core |
| `coding-style.md` | File-scoped namespaces, primary constructors, records, `sealed`/`internal` by default |
| `error-handling.md` | Result pattern, ProblemDetails, one global exception handler |
| `security.md` | AWS Parameter Store / Secrets Manager, explicit `[Authorize]`, HTTPS, explicit CORS origins |
| `performance.md` | `CancellationToken` everywhere, `TimeProvider`, `IHttpClientFactory`, `HybridCache` |
| `testing.md` | Integration tests first, AAA, `MethodName_Scenario_ExpectedResult` naming |
| `packages.md` | Latest stable versions, Central Package Management, .NET 10 alignment |
| `git-workflow.md` | Conventional commits, atomic changes, no force-push to main |
| `hooks.md` | Respect format hooks, never `--no-verify` |
| `agents.md` | Search before reading files, subagent routing, model selection |

---

## Templates

Starter `CLAUDE.md` files in `templates/`, each with a README explaining when to use it.

| Template | For |
|----------|-----|
| `web-api` | REST APIs and backend services |
| `modular-monolith` | Several bounded contexts deployed as one unit |
| `blazor-app` | Blazor Server, WebAssembly, or Auto apps |
| `class-library` | Shared libraries, SDKs, and NuGet packages |

---

## Hooks

Shell scripts in `hooks/` that keep generated code in shape:

| Script | When it runs |
|--------|--------------|
| `pre-bash-guard.sh` | Before Bash commands — blocks destructive operations |
| `post-edit-format.sh` | After edits to `.cs` files — runs `dotnet format` on them |
| `post-scaffold-restore.sh` | After `.csproj` changes — runs NuGet restore |
| `post-test-analyze.sh` | Pipe `dotnet test` output into it for a short failure summary |
| `pre-build-validate.sh` | Before a build — checks the project structure |
| `pre-commit-format.sh` | Git pre-commit — fails if files need formatting |
| `pre-commit-antipattern.sh` | Git pre-commit — scans staged code for known anti-patterns |

---

## Repository Layout

```
launchpad/
├── .claude-plugin/     # plugin.json and marketplace.json
├── .claude/rules/      # always-on rules to copy into your project
├── agents/             # specialist agent definitions
├── skills/             # knowledge and workflow skills (SKILL.md each)
├── knowledge/          # reference docs, anti-pattern catalogue, decision records
├── templates/          # starter CLAUDE.md files per project type
└── hooks/              # format, guard, restore and pre-commit scripts
```

The `knowledge/decisions/` folder records why the defaults are what they are — for example, Vertical Slice as the default architecture, Result over exceptions, and HybridCache as the default cache.

---

## Contributing

1. Keep each skill focused on one topic, in `skills/<name>/SKILL.md` with a clear `description` so Claude knows when to load it.
2. Use controller-based REST APIs in every code sample.
3. Don't hardcode package versions — follow `.claude/rules/packages.md`.
4. Use conventional commit messages (`feat:`, `fix:`, `docs:` …).

## Acknowledgements

Inspired by [dotnet-claude-kit](https://github.com/codewithmukesh/dotnet-claude-kit), adapted for controller-based APIs and AWS.

## License

MIT
