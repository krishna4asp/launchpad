# [Project Name] — Modular Monolith

> Copy this file into your project root and customize the sections below.

## Project Context

This is a .NET 10 modular monolith with each module using its own internal architecture (VSA, Clean Architecture, or DDD — run the `architecture-advisor` skill per module if needed). The application is composed of independent modules that run in a single deployable unit (the Host) but maintain strict boundaries — each module owns its features, data, and domain logic. Modules communicate through integration events, never by direct cross-module method calls or shared database tables.

## Tech Stack

- **.NET 10** / C# 14
- **ASP.NET Core controllers** — one `[ApiController]` per resource inside each module, registered with `AddApplicationPart` and discovered by `app.MapControllers()`
- **Entity Framework Core** — one DbContext per module, PostgreSQL/SQL Server
- **Wolverine** (or MassTransit) — inter-module messaging via integration events, transactional outbox
- **Mediator** (source-generated, MIT) or Wolverine or raw handlers — intra-module command/query dispatch
- **FluentValidation** — request validation
- **Serilog** — structured logging
- **xUnit v3** + **SQLite in-memory** — testing

## Architecture

```
src/
  [ProjectName].Host/                    # Startup host — wires all modules together
    Program.cs                           # Service registration, middleware, module mapping
    appsettings.json

  [ProjectName].Shared/                  # Shared kernel (thin!)
    Contracts/
      Events/                            # Integration event records (pure data)
    Common/
      Result.cs                          # Result pattern
      Behaviors/                         # Mediator pipeline behaviors
      Extensions/                        # Shared extension methods

  Modules/
    [Module]/                            # e.g., Orders, Catalog, Identity
      [ProjectName].Modules.[Module]/
        Features/
          [Feature]/
            [Feature]Controller.cs       # Thin controller dispatching to the slices
            [Operation].cs               # Command/Query + Handler + Response
        Persistence/
          [Module]DbContext.cs            # Module-scoped DbContext
          Configurations/                # EF entity configurations
          Migrations/                    # Module-scoped migrations
        Consumers/                       # Wolverine/MassTransit event consumers
        [Module]Module.cs                # DI registration + AddApplicationPart for its controllers

tests/
  Modules/
    [ProjectName].Modules.[Module].Tests/
      Features/
        [Feature]/
          [Operation]Tests.cs
      Fixtures/
        [Module]Fixture.cs               # WebApplicationFactory scoped to module
  [ProjectName].Integration.Tests/       # Cross-module integration tests
    Fixtures/
      AppFixture.cs                      # WebApplicationFactory + SQLite in-memory
```

### Module Structure Convention

Each module is a standalone class library that exposes a single registration extension. It also adds the module assembly as an MVC application part so its controllers are found:

```csharp
// Modules/Orders/[ProjectName].Modules.Orders/OrdersModule.cs
public static class OrdersModule
{
    public static IMvcBuilder AddOrdersModule(this IMvcBuilder mvc, IConfiguration config)
    {
        mvc.Services.AddDbContext<OrdersDbContext>(options =>
            options.UseNpgsql(config.GetConnectionString("OrdersDb")));

        mvc.Services.AddMediator(); // source-generated, registers handlers from this assembly
        mvc.Services.AddValidatorsFromAssembly(typeof(OrdersModule).Assembly);

        mvc.AddApplicationPart(typeof(OrdersModule).Assembly); // exposes this module's controllers
        return mvc;
    }
}

// [ProjectName].Host/Program.cs
builder.Services.AddControllers().AddOrdersModule(builder.Configuration);
// ...
app.MapControllers();

// Modules/Orders/[ProjectName].Modules.Orders/Features/Orders/OrdersController.cs
// Must be public — MVC only discovers public controllers
[Route("api/orders")]
[Tags("Orders")]
public sealed class OrdersController(ISender sender) : ApiControllerBase
{
    [HttpPost(Name = "CreateOrder")]
    [ProducesResponseType<CreateOrder.Response>(StatusCodes.Status201Created)]
    [ProducesResponseType<ValidationProblemDetails>(StatusCodes.Status400BadRequest)]
    public async Task<ActionResult<CreateOrder.Response>> Create(CreateOrder.Command command, CancellationToken ct)
    {
        var result = await sender.Send(command, ct);
        return result.IsSuccess
            ? StatusCode(StatusCodes.Status201Created, result.Value)
            : ToProblemDetails(result);
    }
}
```

### Feature File Convention

Each feature operation lives in a single file using a static class wrapper:

```csharp
public static class CreateOrder
{
    public record Command(...) : IRequest<Result<Response>>;
    public record Response(...);
    public class Validator : AbstractValidator<Command> { }
    internal class Handler(OrdersDbContext db, IMessageBus bus, TimeProvider clock)
        : IRequestHandler<Command, Result<Response>> { }
}
```

### Module Communication

Modules communicate exclusively through integration events in the Shared contracts project:

```csharp
// Shared/Contracts/Events/OrderCreated.cs — pure data, no behavior
public record OrderCreated(Guid OrderId, string CustomerId, decimal Total, DateTimeOffset CreatedAt);

// Orders module publishes
await bus.PublishAsync(new OrderCreated(order.Id, order.CustomerId, order.Total, clock.GetUtcNow()));

// Notifications module consumes — convention-based handler, no interface needed
public static class OrderCreatedHandler
{
    public static async Task HandleAsync(
        OrderCreated message, NotificationsDbContext db, CancellationToken ct)
    {
        // Handle event...
        await db.SaveChangesAsync(ct);
    }
}
```

### Database Isolation

Each module owns its own DbContext targeting a separate schema (or separate database):

```csharp
public class OrdersDbContext(DbContextOptions<OrdersDbContext> options) : DbContext(options)
{
    public DbSet<Order> Orders => Set<Order>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.HasDefaultSchema("orders");
        modelBuilder.ApplyConfigurationsFromAssembly(typeof(OrdersDbContext).Assembly);
    }
}
```

## Coding Standards

- **C# 14 features** — Use primary constructors, collection expressions, `field` keyword, records, pattern matching
- **File-scoped namespaces** — Always
- **`var` for obvious types** — Use explicit types when the type isn't clear from context
- **Naming** — PascalCase for public members, `_camelCase` for private fields, suffix async methods with `Async`
- **No regions** — Ever
- **No comments for obvious code** — Only comment "why", never "what"
- **Module prefix** — Namespace all module types under `[ProjectName].Modules.[Module]`
- **Internal by default** — Module handlers, consumers, and DbContexts should be `internal` where possible; expose only the module registration extension and controllers as `public` (MVC only discovers public controllers)

## Skills

Load these dotnet-claude-kit skills for context:

- `modern-csharp` — C# 14 language features and idioms
- `architecture-advisor` — Choose the internal architecture for each module
- `vertical-slice` — Feature folder structure and handler patterns (if using VSA)
- `clean-architecture` — Layered project structure with dependency inversion (if using CA)
- `ddd` — Aggregates, value objects, domain events (if using DDD)
- `project-structure` — Solution layout and project references
- `controller-based-apis` — `[ApiController]` controllers, attribute routing, `ActionResult<T>`, OpenAPI metadata
- `ef-core` — DbContext patterns, query optimization, migrations (one DbContext per module)
- `messaging` — Wolverine/MassTransit, transactional outbox, integration events between modules
- `dependency-injection` — Service registration patterns, module-scoped DI
- `error-handling` — Result pattern, ProblemDetails
- `testing` — xUnit v3, WebApplicationFactory, SQLite in-memory
- `configuration` — Options pattern, per-module configuration sections
- `logging` — Serilog, structured logging, OpenTelemetry
- `workflow-mastery` — Parallel worktrees, verification loops, subagent patterns, context discipline
- `instinct-system` — Capture corrections, instincts, and discoveries as persistent learning
- `wrap-up` — Structured session handoff to `.claude/handoff.md`

## MCP Tools

> **Setup:** Install once globally with `dotnet tool install -g CWM.RoslynNavigator` and register with `claude mcp add --scope user cwm-roslyn-navigator -- cwm-roslyn-navigator --solution ${workspaceFolder}`. After that, these tools are available in every .NET project.

Use `cwm-roslyn-navigator` tools to minimize token consumption:

- **Before modifying a type** — Use `find_symbol` to locate it, `get_public_api` to understand its surface
- **Before adding a reference** — Use `find_references` to understand existing usage
- **To understand architecture** — Use `get_project_graph` to see project dependencies and verify module boundaries
- **To find implementations** — Use `find_implementations` instead of grep for interface/abstract class implementations
- **To check for errors** — Use `get_diagnostics` after changes
- **To verify module isolation** — Use `get_project_graph` to confirm modules do not reference each other directly

## Commands

```bash
# Run the host (development)
dotnet run --project src/[ProjectName].Host

# Run all tests
dotnet test

# Run tests for a specific module
dotnet test tests/Modules/[ProjectName].Modules.[Module].Tests

# Add EF migration for a specific module
dotnet ef migrations add [Name] \
  --project src/Modules/[Module]/[ProjectName].Modules.[Module] \
  --startup-project src/[ProjectName].Host \
  --context [Module]DbContext

# Apply migrations for a specific module
dotnet ef database update \
  --project src/Modules/[Module]/[ProjectName].Modules.[Module] \
  --startup-project src/[ProjectName].Host \
  --context [Module]DbContext

# Format check
dotnet format --verify-no-changes
```

## Workflow

- **Plan first** — Enter plan mode for any non-trivial task (3+ steps or architecture decisions). Iterate until the plan is solid before writing code.
- **Verify before done** — Run `dotnet test` after changes. Use `get_diagnostics` via MCP to catch warnings. Ask: "Would a staff engineer approve this?"
- **Fix bugs autonomously** — When given a bug report, investigate and fix it without hand-holding. Check logs, errors, failing tests — then resolve them.
- **Stop and re-plan** — If implementation goes sideways, STOP and re-plan. Don't push through a broken approach.
- **Use subagents** — Offload research, exploration, and parallel analysis to subagents. One task per subagent for focused execution.
- **Learn from corrections** — After any correction, capture the pattern in memory so the same mistake never recurs.

## Anti-patterns

Do NOT generate code that:

- Defines endpoints in Program.cs — use `[ApiController]` controllers in each module, discovered by `app.MapControllers()`; Program.cs should never change when adding endpoints
- Puts business logic or `DbContext` calls in controllers — keep actions thin and dispatch to a handler
- Uses `DateTime.Now` — use `TimeProvider` injection instead
- Creates `new HttpClient()` — use `IHttpClientFactory`
- Uses `async void` — always return `Task`
- Blocks with `.Result` or `.Wait()` — await instead
- Returns untyped `IActionResult` without `[ProducesResponseType]` — use `ActionResult<T>` for OpenAPI
- Returns domain entities from endpoints — always map to response DTOs
- Creates repository abstractions over EF Core — use the module's DbContext directly
- Uses the EF Core InMemory provider for tests — use SQLite in-memory
- Catches bare `Exception` — catch specific types, let the global handler catch the rest
- Uses string interpolation in log messages — use structured logging templates
- References another module's DbContext or internal types — communicate via integration events only
- Shares database tables between modules — each module owns its schema
- Calls another module's handler directly — use Wolverine or MassTransit publish/send for cross-module communication
- Puts business logic in the Shared project — the shared kernel contains only contracts, primitives, and cross-cutting infrastructure
- Creates a single "god" DbContext for the entire application — each module gets its own DbContext
- Publishes events without the transactional outbox — use Wolverine's built-in outbox or MassTransit's `AddEntityFrameworkOutbox` for reliability
