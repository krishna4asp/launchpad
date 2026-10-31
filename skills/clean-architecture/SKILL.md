---
name: clean-architecture
description: >
  Clean Architecture for .NET applications. Covers the 4-project layout (Domain,
  Application, Infrastructure, Api), dependency inversion, use case handlers,
  domain entities with behavior, and infrastructure as a plugin.
  Load this skill when building a project with Clean Architecture, discussing
  layered architecture, dependency inversion, use cases, or when the
  architecture-advisor recommends Clean Architecture.
---

# Clean Architecture

## Core Principles

1. **Dependency inversion is the foundation** — All dependencies point inward. Domain has zero project references. Application references only Domain. Infrastructure references Application and Domain. Api references all but depends on abstractions. The compiler enforces this via project references.
2. **Domain owns the rules** — Business logic lives in the Domain layer as entity methods, domain services, or specifications. The Domain layer has no knowledge of databases, HTTP, or any framework — only pure C# and .NET primitives.
3. **Use cases are the unit of work** — Each use case (command or query) is a single class in the Application layer. It orchestrates domain objects, persists through abstractions, and returns a result. No "service" classes with 20 methods.
4. **Infrastructure is a plugin** — EF Core, external APIs, email senders, file storage — all live in Infrastructure and implement interfaces defined in Application or Domain. Swap implementations without touching business logic.
5. **The API layer is thin** — Controllers map HTTP to use cases and use cases to HTTP responses. No business logic in controllers.

## Patterns

### Project Layout

```
src/
  MyApp.Domain/
    Entities/
      Order.cs                    # Entity with behavior
      OrderItem.cs
    Enums/
      OrderStatus.cs
    Exceptions/
      DomainException.cs          # Base domain exception
    Interfaces/
      IOrderRepository.cs         # Only if query needs go beyond DbSet
    Common/
      Entity.cs                   # Base entity with Id
      Result.cs                   # Result pattern type

  MyApp.Application/
    Common/
      Behaviors/
        ValidationBehavior.cs     # Mediator pipeline behavior
      Interfaces/
        IAppDbContext.cs           # DbContext abstraction (preferred over repository)
    Orders/
      Commands/
        CreateOrder/
          CreateOrderCommand.cs
          CreateOrderHandler.cs
          CreateOrderValidator.cs
      Queries/
        GetOrder/
          GetOrderQuery.cs
          GetOrderHandler.cs
          OrderDto.cs

  MyApp.Infrastructure/
    Persistence/
      AppDbContext.cs              # Implements IAppDbContext
      Configurations/
        OrderConfiguration.cs
      Migrations/
    Services/
      EmailSender.cs               # Implements IEmailSender from Application
    DependencyInjection.cs         # AddInfrastructure extension

  MyApp.Api/
    Controllers/
      OrdersController.cs          # Thin, maps HTTP ↔ use cases
    Contracts/
      Orders/
        CreateOrderRequest.cs      # HTTP request DTO, mapped to a command
    Program.cs
```

### DbContext Abstraction (Preferred Over Repository)

Define a minimal interface in Application; implement in Infrastructure:

```csharp
// Application/Common/Interfaces/IAppDbContext.cs
public interface IAppDbContext
{
    DbSet<Order> Orders { get; }
    DbSet<Product> Products { get; }
    Task<int> SaveChangesAsync(CancellationToken ct = default);
}

// Infrastructure/Persistence/AppDbContext.cs
public class AppDbContext(DbContextOptions<AppDbContext> options)
    : DbContext(options), IAppDbContext
{
    public DbSet<Order> Orders => Set<Order>();
    public DbSet<Product> Products => Set<Product>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.ApplyConfigurationsFromAssembly(typeof(AppDbContext).Assembly);
    }
}
```

Why IAppDbContext over IRepository? EF Core's DbSet already IS a repository. Adding another abstraction on top adds indirection without value in most cases.

### Use Case Handler (Command)

```csharp
// Application/Orders/Commands/CreateOrder/CreateOrderCommand.cs
public record CreateOrderCommand(
    string CustomerId,
    List<OrderItemDto> Items) : IRequest<Result<Guid>>;

public record OrderItemDto(string ProductId, int Quantity, decimal UnitPrice);

// Application/Orders/Commands/CreateOrder/CreateOrderHandler.cs — uses Mediator (source-generated, MIT)
internal sealed class CreateOrderHandler(
    IAppDbContext db,
    TimeProvider clock) : IRequestHandler<CreateOrderCommand, Result<Guid>>
{
    public async ValueTask<Result<Guid>> Handle(CreateOrderCommand request, CancellationToken ct)
    {
        var order = Order.Create(
            request.CustomerId,
            request.Items.Select(i => new OrderItem(i.ProductId, i.Quantity, i.UnitPrice)),
            clock.GetUtcNow());

        db.Orders.Add(order);
        await db.SaveChangesAsync(ct);

        return Result.Success(order.Id);
    }
}

// Application/Orders/Commands/CreateOrder/CreateOrderValidator.cs
public class CreateOrderValidator : AbstractValidator<CreateOrderCommand>
{
    public CreateOrderValidator()
    {
        RuleFor(x => x.CustomerId).NotEmpty();
        RuleFor(x => x.Items).NotEmpty();
        RuleForEach(x => x.Items).ChildRules(item =>
        {
            item.RuleFor(x => x.ProductId).NotEmpty();
            item.RuleFor(x => x.Quantity).GreaterThan(0);
            item.RuleFor(x => x.UnitPrice).GreaterThan(0);
        });
    }
}
```

### Use Case Handler (Query)

```csharp
// Application/Orders/Queries/GetOrder/GetOrderQuery.cs
public record GetOrderQuery(Guid OrderId) : IRequest<Result<OrderDto>>;

public record OrderDto(Guid Id, string CustomerId, decimal Total, string Status, DateTimeOffset CreatedAt);

// Application/Orders/Queries/GetOrder/GetOrderHandler.cs
internal sealed class GetOrderHandler(IAppDbContext db) : IRequestHandler<GetOrderQuery, Result<OrderDto>>
{
    public async ValueTask<Result<OrderDto>> Handle(GetOrderQuery request, CancellationToken ct)
    {
        var order = await db.Orders
            .Where(o => o.Id == request.OrderId)
            .Select(o => new OrderDto(o.Id, o.CustomerId, o.Total, o.Status.ToString(), o.CreatedAt))
            .FirstOrDefaultAsync(ct);

        return order is not null
            ? Result.Success(order)
            : Result.Failure<OrderDto>("Order not found");
    }
}
```

### Domain Entity with Behavior

```csharp
// Domain/Entities/Order.cs
public class Order : Entity
{
    private readonly List<OrderItem> _items = [];

    private Order() { } // EF Core

    public string CustomerId { get; private set; } = null!;
    public OrderStatus Status { get; private set; }
    public decimal Total { get; private set; }
    public DateTimeOffset CreatedAt { get; private set; }
    public IReadOnlyList<OrderItem> Items => _items.AsReadOnly();

    public static Order Create(string customerId, IEnumerable<OrderItem> items, DateTimeOffset now)
    {
        var order = new Order
        {
            Id = Guid.CreateVersion7(),
            CustomerId = customerId,
            Status = OrderStatus.Pending,
            CreatedAt = now
        };

        foreach (var item in items)
            order.AddItem(item);

        return order;
    }

    public void AddItem(OrderItem item)
    {
        _items.Add(item);
        Total = _items.Sum(i => i.Quantity * i.UnitPrice);
    }

    public Result Cancel()
    {
        if (Status is not OrderStatus.Pending)
            return Result.Failure("Only pending orders can be cancelled");

        Status = OrderStatus.Cancelled;
        return Result.Success();
    }
}
```

### Thin Controllers

Controllers inherit `ControllerBase` and use `[ApiController]` with attribute routing. Each action takes a request DTO from the `Api/Contracts` folder, maps it to a command or query, sends it through the mediator, and maps the result to an HTTP response. Keeping request DTOs separate from commands means the HTTP contract can change without touching the Application layer.

```csharp
// Api/Contracts/Orders/CreateOrderRequest.cs
public sealed record CreateOrderRequest(
    string CustomerId,
    List<OrderItemDto> Items);
```

```csharp
// Api/Controllers/OrdersController.cs
[ApiController]
[Route("api/orders")]
public sealed class OrdersController : ControllerBase
{
    private readonly ISender _mediator;

    public OrdersController(ISender mediator) => _mediator = mediator;

    [HttpPost]
    [ProducesResponseType(typeof(Guid), StatusCodes.Status201Created)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status409Conflict)]
    public async Task<IActionResult> Create(
        [FromBody] CreateOrderRequest request, CancellationToken ct)
    {
        var command = new CreateOrderCommand(request.CustomerId, request.Items);

        var result = await _mediator.Send(command, ct);

        return result.IsSuccess
            ? CreatedAtAction(nameof(GetById), new { id = result.Value }, result.Value)
            : Problem(detail: result.Error, statusCode: StatusCodes.Status400BadRequest);
    }

    [HttpGet("{id:guid}")]
    [ProducesResponseType(typeof(OrderDto), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> GetById(Guid id, CancellationToken ct)
    {
        var result = await _mediator.Send(new GetOrderQuery(id), ct);

        return result.IsSuccess
            ? Ok(result.Value)
            : NotFound();
    }

    [HttpGet]
    [ProducesResponseType(typeof(IReadOnlyList<OrderDto>), StatusCodes.Status200OK)]
    public async Task<IActionResult> List([FromQuery] ListOrdersQuery query, CancellationToken ct)
    {
        var result = await _mediator.Send(query, ct);
        return Ok(result);
    }
}
```

Register controllers in `Program.cs`:

```csharp
// Api/Program.cs
builder.Services.AddControllers();

var app = builder.Build();

app.MapControllers();
```

To return 409 (or other codes) for specific failures, map the `Result` error to a status code in one shared helper (see the **error-handling** skill) instead of branching in every action.

### Infrastructure DI Registration

```csharp
// Infrastructure/DependencyInjection.cs
public static class DependencyInjection
{
    public static IServiceCollection AddInfrastructure(
        this IServiceCollection services,
        IConfiguration config)
    {
        services.AddDbContext<AppDbContext>(options =>
            options.UseNpgsql(config.GetConnectionString("DefaultConnection")));

        services.AddScoped<IAppDbContext>(sp => sp.GetRequiredService<AppDbContext>());

        return services;
    }
}
```

## Anti-patterns

### Anemic Domain Model

```csharp
// BAD — entity is just a data bag, all logic in handler
public class Order
{
    public Guid Id { get; set; }
    public string CustomerId { get; set; } = null!;
    public decimal Total { get; set; }
    public List<OrderItem> Items { get; set; } = [];
}

// Handler sets everything directly
order.Total = order.Items.Sum(i => i.Quantity * i.UnitPrice);
order.Status = OrderStatus.Pending;

// GOOD — entity encapsulates its own rules (see Domain Entity pattern above)
var order = Order.Create(customerId, items, clock.GetUtcNow());
```

### DbContext in Domain Layer

```csharp
// BAD — Domain references EF Core
// Domain/Services/OrderService.cs
public class OrderService(AppDbContext db) { } // Domain depends on Infrastructure!

// GOOD — Domain defines interfaces, Infrastructure implements
// Domain/Interfaces/IOrderRepository.cs (only if you need query abstraction beyond DbSet)
// Application/Common/Interfaces/IAppDbContext.cs (preferred)
```

### Fat Controllers

```csharp
// BAD — business logic and DbContext in the controller
[HttpPost]
public async Task<IActionResult> Create([FromBody] CreateOrderRequest request)
{
    var order = new Order { CustomerId = request.CustomerId };
    foreach (var item in request.Items)
    {
        order.Items.Add(new OrderItem { ProductId = item.ProductId, Quantity = item.Quantity });
    }
    order.Total = order.Items.Sum(i => i.Quantity * i.UnitPrice);
    _db.Orders.Add(order);
    await _db.SaveChangesAsync();
    return Created($"/api/orders/{order.Id}", order);
}

// GOOD — controller maps the request to a command and delegates to a use case
[HttpPost]
public async Task<IActionResult> Create([FromBody] CreateOrderRequest request, CancellationToken ct)
{
    var command = new CreateOrderCommand(request.CustomerId, request.Items);

    var result = await _mediator.Send(command, ct);

    return result.IsSuccess
        ? CreatedAtAction(nameof(GetById), new { id = result.Value }, result.Value)
        : Problem(detail: result.Error, statusCode: StatusCodes.Status400BadRequest);
}
```

### Repository for Every Entity

```csharp
// BAD — repository per entity duplicates DbSet functionality
public interface IOrderRepository { Task<Order?> GetByIdAsync(Guid id); }
public interface IProductRepository { Task<Product?> GetByIdAsync(Guid id); }
public interface ICustomerRepository { Task<Customer?> GetByIdAsync(Guid id); }

// GOOD — use IAppDbContext with DbSet<T> directly
// Only create a repository interface when you have complex query logic
// that you want to test in isolation or reuse across multiple use cases
```

## Decision Guide

| Scenario                       | Recommendation                                                                     |
| ------------------------------ | ---------------------------------------------------------------------------------- |
| When to use CA over VSA        | Medium+ domain complexity, long-lived system, team familiar with layers            |
| When to add a Domain layer     | Business rules involve invariants across entity groups                             |
| IAppDbContext vs repositories  | Prefer IAppDbContext; add repository only for complex reusable queries             |
| Mediator vs raw handlers in CA | Mediator for pipeline behaviors (validation, logging); raw handlers for simplicity |
| API style                      | Controllers (`[ApiController]`, `ActionResult<T>`, `[ProducesResponseType]`) — see `controller-based-apis` |
| When to add Domain events      | When side effects (notifications, audit) should be decoupled from the main flow    |
| Evolving from VSA to CA        | When handlers start needing shared domain logic that does not belong in Common/    |
