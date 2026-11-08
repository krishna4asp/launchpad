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

### Feature Files

Each operation is one file: a static class holding its `Command`/`Query`, `Response`, `Validator` and `internal` handler (see the `vertical-slice` skill).

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
        await db.SaveChangesAsync(ct); // handle the event, then persist
    }
}
```

### Database Isolation

Each module owns its DbContext, its schema (`modelBuilder.HasDefaultSchema("orders")`) and its migrations. No module reads another module's tables.

## Coding Standards

- **C# 14** — primary constructors, collection expressions, records, pattern matching; file-scoped namespaces always
- **Naming** — PascalCase for public members, camelCase for locals and parameters, `Async` suffix on async methods; no `_` prefix when using primary constructors
- **Comments explain "why", never "what"** — no regions
- **Module prefix** — namespace module types under `[ProjectName].Modules.[Module]`
- **Internal by default** — handlers, consumers and DbContexts are `internal`; only the module registration extension and controllers are `public` (MVC only discovers public controllers)

## Skills

Load these launchpad skills for context:

- **Core:** `modern-csharp`, `architecture-advisor` (choose each module's internal architecture), `project-structure`
- **Module internals:** `vertical-slice`, `clean-architecture` or `ddd` (whichever each module uses)
- **APIs & data:** `controller-based-apis`, `ef-core` (one DbContext per module), `error-handling`, `configuration`, `dependency-injection`
- **Between modules:** `messaging` — integration events and the transactional outbox
- **Quality:** `testing`, `logging`
- **Session:** `workflow-mastery`, `instinct-system`, `wrap-up`

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

# Format check
dotnet format --verify-no-changes
```

## Workflow

- **Plan first** — plan any non-trivial task (3+ steps or an architecture decision) before writing code; if it goes sideways, stop and re-plan.
- **Verify before done** — run `dotnet build` and `dotnet test` after changes. Ask: "Would a staff engineer approve this?"
- **Fix bugs autonomously** — investigate logs, errors and failing tests, then resolve them.
- **Use subagents** for research and parallel analysis, one task each; capture user corrections in memory.

## Anti-patterns

Do NOT generate code that:

- Defines endpoints in Program.cs — use `[ApiController]` controllers in each module, discovered by `app.MapControllers()`
- Puts business logic or `DbContext` calls in controllers — keep actions thin and dispatch to a handler
- Returns domain entities or untyped `IActionResult` — return response DTOs via `ActionResult<T>` with `[ProducesResponseType]`
- Creates repository abstractions over EF Core, or a single "god" DbContext — each module uses its own DbContext directly
- Uses `DateTime.Now`, `new HttpClient()`, `async void`, `.Result`/`.Wait()`, or bare `catch (Exception)` — use `TimeProvider`, `IHttpClientFactory`, `Task`, `await`, and the global handler
- Uses string interpolation in log messages — use structured logging templates
- Uses the EF Core InMemory provider for tests — use SQLite in-memory
- References another module's DbContext, internal types or handlers — communicate via integration events only
- Shares database tables between modules — each module owns its schema
- Puts business logic in the Shared project — the shared kernel holds only contracts, primitives and cross-cutting infrastructure
- Publishes events without the transactional outbox — use Wolverine's outbox or MassTransit's `AddEntityFrameworkOutbox`
