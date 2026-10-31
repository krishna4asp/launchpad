---
name: vertical-slice
description: >
  Vertical Slice Architecture (VSA) for .NET applications — one of several
  supported architectures in dotnet-claude-kit. Covers feature folders, thin
  resource controllers, and handler patterns for Mediator, Wolverine, and raw handler classes.
  Load this skill when the architecture-advisor recommends VSA, when working in
  an existing VSA codebase, when adding features to a feature-folder project,
  or when discussing vertical slice patterns, feature folders, or handler patterns.
---

# Vertical Slice Architecture (VSA)

## Core Principles

1. **Organize by feature, not by layer** — Each operation is a self-contained vertical slice containing its handler, request/response types, and validation. The feature folder holds one thin resource controller (`OrdersController`) that dispatches HTTP requests to those slices. No layer folders like Services/ or Repositories/.
2. **Minimize cross-feature coupling** — Features should not reference each other directly. Shared concerns go in a `Common/` or `Shared/` directory.
3. **One file per operation is fine** — A simple CRUD operation doesn't need 5 files spread across layers. Start with command, handler and response in one file, plus one action on the feature's controller; extract only when complexity demands it.
4. **The handler is the unit of work** — Each handler does one thing. No god-services with 20 methods.
5. **Controllers stay thin** — An action maps HTTP to a command/query and the result back to HTTP (see the `controller-based-apis` skill). Business logic and data access live in the handler.

## Patterns

### Feature Folder Structure

```
src/
  MyApp.Api/
    Features/
      Orders/
        OrdersController.cs     # Thin HTTP entry point for the Orders slices
        CreateOrder.cs          # Command, Validator, Handler, Response — all in one file
        GetOrder.cs
        ListOrders.cs
        CancelOrder.cs
        Shared/
          OrderMapper.cs        # Shared within the Orders feature only
      Products/
        CreateProduct.cs
        GetProduct.cs
    Common/
      Behaviors/
        ValidationBehavior.cs   # Cross-cutting Mediator pipeline behavior
      Persistence/
        AppDbContext.cs
      Extensions/
        ServiceCollectionExtensions.cs
    Program.cs
```

### Pattern A: Mediator Handlers (Recommended Default)

Source-generated mediator — MIT licensed, no reflection, Native AOT compatible. Uses `IRequest<T>` / `IRequestHandler<TRequest, TResponse>` with pipeline behaviors. Near-identical API to MediatR but faster and free. Package: `Mediator.Abstractions` + `Mediator.SourceGenerator`.

```csharp
// Features/Orders/CreateOrder.cs

public static class CreateOrder
{
    public record Command(string CustomerId, List<OrderItemDto> Items) : IRequest<Result<OrderResponse>>;

    public record OrderItemDto(string ProductId, int Quantity);

    public record OrderResponse(Guid Id, decimal Total, DateTime CreatedAt);

    public class Validator : AbstractValidator<Command>
    {
        public Validator()
        {
            RuleFor(x => x.CustomerId).NotEmpty();
            RuleFor(x => x.Items).NotEmpty();
            RuleForEach(x => x.Items).ChildRules(item =>
            {
                item.RuleFor(x => x.ProductId).NotEmpty();
                item.RuleFor(x => x.Quantity).GreaterThan(0);
            });
        }
    }

    internal sealed class Handler(AppDbContext db, TimeProvider clock) : IRequestHandler<Command, Result<OrderResponse>>
    {
        public async ValueTask<Result<OrderResponse>> Handle(Command request, CancellationToken ct)
        {
            var order = Order.Create(request.CustomerId, request.Items, clock.GetUtcNow());
            db.Orders.Add(order);
            await db.SaveChangesAsync(ct);

            return Result.Success(new OrderResponse(order.Id, order.Total, order.CreatedAt));
        }
    }
}

// Registration in Program.cs or module DI
builder.Services.AddMediator();

// Features/Orders/OrdersController.cs — discovered by app.MapControllers()
[Route("api/orders")]
[Tags("Orders")]
[Authorize]
public sealed class OrdersController(ISender sender) : ApiControllerBase
{
    [HttpPost(Name = "CreateOrder")]
    [ProducesResponseType<CreateOrder.OrderResponse>(StatusCodes.Status201Created)]
    [ProducesResponseType<ValidationProblemDetails>(StatusCodes.Status400BadRequest)]
    public async Task<ActionResult<CreateOrder.OrderResponse>> Create(
        CreateOrder.Command command, CancellationToken ct)
    {
        // CreateOrder.Validator runs first via the global FluentValidationFilter (error-handling skill)
        var result = await sender.Send(command, ct);
        return result.IsSuccess
            ? CreatedAtRoute("GetOrder", new { id = result.Value.Id }, result.Value)
            : ToProblemDetails(result);
    }

    [HttpGet("{id:guid}", Name = "GetOrder")]
    [ProducesResponseType<GetOrder.OrderResponse>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    public async Task<ActionResult<GetOrder.OrderResponse>> GetById(Guid id, CancellationToken ct)
    {
        var result = await sender.Send(new GetOrder.Query(id), ct);
        return result.IsSuccess ? result.Value : ToProblemDetails(result, StatusCodes.Status404NotFound);
    }
}
```

### Pattern B: Wolverine Handlers

Convention-based — no interfaces to implement. Wolverine discovers handlers by method signature.

```csharp
// Features/Orders/CreateOrder.cs

public static class CreateOrder
{
    public record Command(string CustomerId, List<OrderItemDto> Items);

    public record OrderItemDto(string ProductId, int Quantity);

    public record OrderResponse(Guid Id, decimal Total, DateTime CreatedAt);

    // Wolverine discovers this by convention (static Handle method)
    public static async Task<Result<OrderResponse>> Handle(
        Command command,
        AppDbContext db,
        TimeProvider clock,
        CancellationToken ct)
    {
        var order = Order.Create(command.CustomerId, command.Items, clock.GetUtcNow());
        db.Orders.Add(order);
        await db.SaveChangesAsync(ct);
        return Result.Success(new OrderResponse(order.Id, order.Total, order.CreatedAt));
    }
}

// Features/Orders/OrdersController.cs — OrdersController(IMessageBus bus) : ApiControllerBase
// Dispatch through Wolverine's IMessageBus (see the messaging skill)
[HttpPost(Name = "CreateOrder")]
public async Task<ActionResult<CreateOrder.OrderResponse>> Create(CreateOrder.Command command, CancellationToken ct)
{
    var result = await bus.InvokeAsync<Result<CreateOrder.OrderResponse>>(command, ct);
    return result.IsSuccess
        ? CreatedAtRoute("GetOrder", new { id = result.Value.Id }, result.Value)
        : ToProblemDetails(result);
}
```

### Pattern C: Raw Handler Classes (No Library)

Direct handler classes with no external dependency. Good for small projects or teams that want full control.

```csharp
// Features/Orders/CreateOrder.cs

public static class CreateOrder
{
    public record Command(string CustomerId, List<OrderItemDto> Items);

    public record OrderItemDto(string ProductId, int Quantity);

    public record OrderResponse(Guid Id, decimal Total, DateTime CreatedAt);

    public sealed class Handler(AppDbContext db, TimeProvider clock) // public: injected into a public controller
    {
        public async Task<Result<OrderResponse>> ExecuteAsync(Command command, CancellationToken ct)
        {
            var order = Order.Create(command.CustomerId, command.Items, clock.GetUtcNow());
            db.Orders.Add(order);
            await db.SaveChangesAsync(ct);

            return Result.Success(new OrderResponse(order.Id, order.Total, order.CreatedAt));
        }
    }
}

// Registration
builder.Services.AddScoped<CreateOrder.Handler>();

// Features/Orders/OrdersController.cs — Result maps to HTTP response
[Route("api/orders")]
public sealed class OrdersController(CreateOrder.Handler createOrder) : ApiControllerBase
{
    [HttpPost(Name = "CreateOrder")]
    [ProducesResponseType<CreateOrder.OrderResponse>(StatusCodes.Status201Created)]
    [ProducesResponseType<ValidationProblemDetails>(StatusCodes.Status400BadRequest)]
    public async Task<ActionResult<CreateOrder.OrderResponse>> Create(
        CreateOrder.Command command, CancellationToken ct)
    {
        var result = await createOrder.ExecuteAsync(command, ct);
        return result.IsSuccess
            ? CreatedAtRoute("GetOrder", new { id = result.Value.Id }, result.Value)
            : ToProblemDetails(result);
    }
}
```

When a controller needs many handlers, inject the one only a single action uses with `[FromServices]` on that action instead of growing the constructor.

### Adding Module Boundaries (Optional)

For larger applications that grow beyond a single project, introduce module boundaries. Each module is a separate class library with its own features and DbContext.

```
src/
  MyApp.Api/                      # Host — wires modules together
    Program.cs
    Modules/
      ModuleExtensions.cs         # AddControllers().AddOrdersModule().AddCatalogModule()
  MyApp.Orders/                   # Module — own features, controllers, DbContext
    Features/
      Orders/
        OrdersController.cs
        CreateOrder.cs
    Persistence/
      OrdersDbContext.cs
    OrdersModule.cs               # Service registration + AddApplicationPart for its controllers
  MyApp.Catalog/                  # Module
    Features/
      CreateProduct.cs
    Persistence/
      CatalogDbContext.cs
    CatalogModule.cs
```

Controllers in a module's class library are not discovered by `MapControllers()` until the host adds that assembly as an application part:

```csharp
// MyApp.Orders/OrdersModule.cs
public static class OrdersModule
{
    public static IMvcBuilder AddOrdersModule(this IMvcBuilder mvc, IConfiguration config)
    {
        mvc.Services.AddDbContext<OrdersDbContext>(o => o.UseNpgsql(config.GetConnectionString("Orders")));
        mvc.AddApplicationPart(typeof(OrdersModule).Assembly); // exposes OrdersController
        return mvc;
    }
}

// MyApp.Api/Program.cs
builder.Services.AddControllers()
    .AddOrdersModule(builder.Configuration)
    .AddCatalogModule(builder.Configuration);
// ...
app.MapControllers();
```

Modules communicate via:

- **Integration events** (preferred) — async, decoupled via Wolverine or MassTransit
- **Shared contracts** — a `MyApp.Contracts` project with DTOs/interfaces (use sparingly)

### Shared Concerns

Cross-cutting concerns live outside feature folders:

```csharp
// Common/Behaviors/ValidationBehavior.cs (Mediator pipeline)
public sealed class ValidationBehavior<TRequest, TResponse>(IEnumerable<IValidator<TRequest>> validators)
    : IPipelineBehavior<TRequest, TResponse>
    where TRequest : IMessage
{
    public async ValueTask<TResponse> Handle(
        TRequest request,
        MessageHandlerDelegate<TRequest, TResponse> next,
        CancellationToken ct)
    {
        var context = new ValidationContext<TRequest>(request);
        var failures = validators
            .Select(v => v.Validate(context))
            .SelectMany(r => r.Errors)
            .Where(f => f is not null)
            .ToList();

        if (failures.Count > 0)
            throw new ValidationException(failures);

        return await next(request, ct);
    }
}
```

## Anti-patterns

### Don't Create Layered Abstractions Within a Slice

```csharp
// BAD — a feature folder with its own service layer and repository
Features/
  Orders/
    CreateOrder.cs
    IOrderService.cs         # unnecessary abstraction
    OrderService.cs          # unnecessary abstraction
    IOrderRepository.cs      # unnecessary abstraction
    OrderRepository.cs       # unnecessary abstraction

// GOOD — handler talks directly to DbContext
Features/
  Orders/
    CreateOrder.cs           # handler uses AppDbContext directly
```

### Don't Cross-reference Features Directly

```csharp
// BAD — CreateOrder directly calls GetProduct handler
var product = await _getProductHandler.Handle(new GetProduct.Query(productId));

// GOOD — query the database directly or use a shared read model
var product = await db.Products.FindAsync(productId, ct);
```

### Don't Put Everything in One God Feature File

```csharp
// BAD — 500-line file with CRUD + business logic + mapping
public static class Orders
{
    // Create, Read, Update, Delete, Cancel, Refund, Export...
}

// GOOD — one file per operation
Features/Orders/CreateOrder.cs
Features/Orders/GetOrder.cs
Features/Orders/CancelOrder.cs
```

## Decision Guide

| Scenario                               | Recommendation                                                               |
| -------------------------------------- | ---------------------------------------------------------------------------- |
| New project (default)                  | Pattern A — Mediator (source-generated, MIT, fast)                           |
| Need mediator + messaging in one lib   | Pattern B — Wolverine (also handles events/queues)                           |
| Want full control, no dependencies     | Pattern C — Raw handler classes                                              |
| Existing MediatR codebase with license | Keep MediatR if licensed; otherwise migrate to Mediator (near-identical API) |
| Monolith growing complex               | Add module boundaries, keep VSA within each module                           |
| Simple CRUD feature                    | Single file (command + handler + response) + one action on the feature's controller |
| Complex feature (saga, events)         | Multiple files in feature folder, still colocated                            |
| Sharing logic between features         | Extract to `Common/` — not to another feature                                |
