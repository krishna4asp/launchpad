---
alwaysApply: true
description: >
  Enforces dependency direction, feature organization, and module boundary
  rules for .NET solution architecture.
---

# Architecture Rules

## Ask First, Recommend Second

- **Never assume an architecture — use the architecture-advisor skill.** Every project has different constraints. Ask about team size, domain complexity, and deployment model before recommending Clean Architecture, VSA, DDD, or Modular Monolith.

## Data Access

- **No repository pattern over EF Core.** `DbContext` is already a Unit of Work + Repository. Wrapping it adds indirection with no value and prevents access to EF Core features like change tracking, batching, and compiled queries.

```csharp
// DO — inject DbContext directly
public sealed class OrderService(AppDbContext db)
{
    public Task<Order?> GetAsync(Guid id, CancellationToken ct) =>
        db.Orders.FindAsync([id], ct).AsTask();
}

// DON'T — generic repository wrapping EF
public interface IRepository<T> { Task<T?> GetByIdAsync(Guid id); }
```

## Endpoint Organization

- **Every endpoint lives in an attribute-routed `[ApiController]` class.** One controller per resource, in its own `*Controller.cs` file inside the feature folder. Never define endpoints inline in `Program.cs`.
- **Use `app.MapControllers()` for discovery.** Program.cs calls `builder.Services.AddControllers()` and `app.MapControllers()` once. Program.cs never changes when adding new controllers or actions.
- **Never add `Map*` endpoint calls (`MapGet`, `MapPost`, `MapGroup`) to Program.cs.** Minimal API endpoints alongside controllers split routing, filters, auth, and OpenAPI metadata across two styles. Controllers are the only accepted pattern (see the **controller-based-apis** skill).
- **Keep actions thin.** An action maps HTTP to a command or query (`ISender`, a service, or `IMessageBus`) and maps the result back to HTTP. Business logic and data access stay out of controllers.

```csharp
// DO — attribute-routed controller in its feature folder, discovered by MapControllers()
[Route("api/orders")]
[Tags("Orders")]
[Authorize]
public sealed class OrdersController(ISender sender) : ApiControllerBase
{
    [HttpGet(Name = "ListOrders")]
    [ProducesResponseType<IReadOnlyList<OrderResponse>>(StatusCodes.Status200OK)]
    public async Task<ActionResult<IReadOnlyList<OrderResponse>>> List(CancellationToken ct) =>
        Ok(await sender.Send(new ListOrders.Query(), ct));

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

// DON'T — Minimal API endpoints wired in Program.cs
app.MapGet("/api/orders", ListOrders);
app.MapGroup("/api/products").MapProductEndpoints();
```

## Project Organization

- **Feature folders over layer folders.** Vertical slices keep related code together, reducing the number of files you touch per feature. Controllers live with their feature, not in a top-level `Controllers/` folder.

```
# DO                          # DON'T
Features/                     Controllers/
  Orders/                       OrdersController.cs
    CreateOrder.cs              ProductsController.cs
    OrdersController.cs       Services/
  Products/                     OrderService.cs
    CreateProduct.cs            ProductService.cs
    ProductsController.cs     Models/
                                CreateOrderRequest.cs
```

- **Dependency direction is inward.** Domain depends on nothing. Application depends on Domain. Infrastructure depends on Application. Presentation depends on Application. Never reverse these arrows.
- **Module boundaries enforced through project references.** If two modules should not couple, they must not have a project reference. Use integration events or a shared contracts project for cross-module communication.

## Shared Kernel

- **Shared kernel contains only contracts, never business logic.** Shared projects hold interfaces, DTOs, and integration event definitions. Domain logic belongs in the owning module. Leaking logic into shared projects creates hidden coupling.

```csharp
// DO — shared kernel has contracts
public interface IOrderPlaced
{
    Guid OrderId { get; }
    DateTimeOffset OccurredAt { get; }
}

// DON'T — shared kernel has domain logic
public static class PricingCalculator { /* business rules */ }
```
