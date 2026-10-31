---
name: dependency-injection
description: >
  Dependency injection patterns for .NET 10. Covers service lifetimes, keyed
  services, the decorator pattern, factory pattern, and common DI pitfalls.
  Load this skill when registering services, resolving lifetime issues, designing
  service composition, or when the user mentions "DI", "dependency injection",
  "service registration", "AddScoped", "AddTransient", "AddSingleton", "keyed
  services", "decorator", "Scrutor", "IServiceCollection", or "captive dependency".
---

# Dependency Injection

## Core Principles

1. **Constructor injection is the default** — Inject dependencies through the constructor (primary constructors make this clean). No service locator, no property injection.
2. **Match lifetimes carefully** — A singleton must never depend on a scoped or transient service. This is the most common DI bug.
3. **Register interfaces, resolve interfaces** — Register `services.AddScoped<IOrderService, OrderService>()`, not the concrete type.
4. **Keyed services for strategy pattern** — .NET 8+ keyed services replace manual factory patterns for selecting between implementations.

## Patterns

### Keyed Services (.NET 10)

Use keyed services to register and resolve multiple implementations of the same interface.

```csharp
// Registration
builder.Services.AddKeyedScoped<INotificationService, EmailNotificationService>("email");
builder.Services.AddKeyedScoped<INotificationService, SmsNotificationService>("sms");
builder.Services.AddKeyedScoped<INotificationService, PushNotificationService>("push");

// Resolution via attribute
public class OrderHandler([FromKeyedServices("email")] INotificationService notifier)
{
    public async Task Handle(CreateOrder.Command command, CancellationToken ct)
    {
        // ... create order
        await notifier.SendAsync(notification, ct);
    }
}

// Resolution via IServiceProvider
public class NotificationRouter(IServiceProvider provider)
{
    public INotificationService GetService(string channel)
    {
        return provider.GetRequiredKeyedService<INotificationService>(channel);
    }
}
```

### Injecting into REST Controllers

Controllers are created per request, so they can take scoped services in the constructor. Use constructor injection for dependencies most actions need; use `[FromServices]` / `[FromKeyedServices]` on a single action for a dependency only that action uses.

```csharp
[ApiController]
[Route("api/[controller]")]
public class OrdersController(IOrderService orders) : ControllerBase
{
    [HttpPost]
    public async Task<IActionResult> Create(CreateOrderRequest request, CancellationToken ct)
    {
        var result = await orders.CreateAsync(request, ct);
        return result.IsSuccess
            ? CreatedAtAction(nameof(GetById), new { id = result.Value.Id }, result.Value)
            : BadRequest(result.Error);
    }

    // Action injection — only this action needs the keyed notifier
    [HttpPost("{id:guid}/notify")]
    public async Task<IActionResult> Notify(
        Guid id,
        [FromKeyedServices("sms")] INotificationService notifier,
        CancellationToken ct)
    {
        await notifier.SendAsync(new OrderNotification(id), ct);
        return Accepted();
    }

    [HttpGet("{id:guid}")]
    public async Task<IActionResult> GetById(Guid id, CancellationToken ct) => /* ... */ Ok();
}
```

Controllers are not themselves registered in the container — the framework activates them and resolves their constructor parameters. Call `AddControllers().AddControllersAsServices()` only if you need to decorate or validate controllers through DI. Keep controllers thin: inject services, not `DbContext` or `IServiceProvider`.

### Decorator Pattern

```csharp
// Base service
public interface IOrderService
{
    Task<Result<Order>> CreateAsync(CreateOrderRequest request, CancellationToken ct);
}

public class OrderService(AppDbContext db, TimeProvider clock) : IOrderService
{
    public async Task<Result<Order>> CreateAsync(CreateOrderRequest request, CancellationToken ct)
    {
        var order = Order.Create(request, clock.GetUtcNow());
        db.Orders.Add(order);
        await db.SaveChangesAsync(ct);
        return Result.Success(order);
    }
}

// Decorator — adds logging
public class LoggingOrderService(IOrderService inner, ILogger<LoggingOrderService> logger) : IOrderService
{
    public async Task<Result<Order>> CreateAsync(CreateOrderRequest request, CancellationToken ct)
    {
        logger.LogInformation("Creating order for customer {CustomerId}", request.CustomerId);
        var result = await inner.CreateAsync(request, ct);
        if (result.IsSuccess)
            logger.LogInformation("Order {OrderId} created", result.Value.Id);
        return result;
    }
}

// Registration with Scrutor
builder.Services.AddScoped<IOrderService, OrderService>();
builder.Services.Decorate<IOrderService, LoggingOrderService>();
```

### Registration by Convention (Scrutor)

```csharp
// Auto-register all services matching a convention
builder.Services.Scan(scan => scan
    .FromAssemblyOf<Program>()
    .AddClasses(classes => classes.AssignableTo<ITransientService>())
    .AsImplementedInterfaces()
    .WithTransientLifetime()
    .AddClasses(classes => classes.AssignableTo<IScopedService>())
    .AsImplementedInterfaces()
    .WithScopedLifetime());
```

### Factory Pattern

When you need runtime logic to select an implementation.

```csharp
builder.Services.AddScoped<IPaymentProcessor>(sp =>
{
    var config = sp.GetRequiredService<IOptions<PaymentOptions>>().Value;
    return config.Provider switch
    {
        "stripe" => ActivatorUtilities.CreateInstance<StripeProcessor>(sp),
        "paypal" => ActivatorUtilities.CreateInstance<PayPalProcessor>(sp),
        _ => throw new InvalidOperationException($"Unknown payment provider: {config.Provider}")
    };
});
```

### Options Registration

```csharp
// Bind configuration section to a strongly-typed options class
builder.Services.AddOptions<JwtOptions>()
    .BindConfiguration("Jwt")
    .ValidateDataAnnotations()
    .ValidateOnStart();

// Inject as IOptions<T>
public class TokenService(IOptions<JwtOptions> options)
{
    private readonly JwtOptions _jwt = options.Value;
}
```

## Anti-patterns

### Don't Capture Scoped Services in Singletons

```csharp
// BAD — DbContext is scoped, captured by singleton = memory leak + stale data
builder.Services.AddSingleton<OrderCache>(); // depends on AppDbContext

// GOOD — use IServiceScopeFactory in singleton
public class OrderCache(IServiceScopeFactory scopeFactory)
{
    public async Task<Order?> GetAsync(Guid id)
    {
        await using var scope = scopeFactory.CreateAsyncScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        return await db.Orders.FindAsync(id);
    }
}
```

### Don't Register Everything as Singleton

```csharp
// BAD — making a service singleton when it holds mutable state
builder.Services.AddSingleton<OrderService>(); // has DbContext dependency

// GOOD — match the lifetime to the service's needs
builder.Services.AddScoped<OrderService>();
```

## Decision Guide

| Scenario                         | Recommendation                                                                                |
| -------------------------------- | --------------------------------------------------------------------------------------------- |
| Stateless service                | Scoped (default) or Transient                                                                 |
| Configuration / cache            | Singleton                                                                                     |
| DbContext                        | Scoped (registered by `AddDbContext`)                                                         |
| Multiple implementations         | Keyed services (strategy pattern)                                                             |
| Cross-cutting behavior           | Decorator pattern                                                                             |
| Convention-based registration    | Scrutor                                                                                       |
| Runtime implementation selection | Factory delegate                                                                              |
| Audit existing registrations     | `get_di_registrations` MCP tool — lifetimes, duplicates, captive-dependency risks in one call |
| Strongly-typed config            | `AddOptions<T>().BindConfiguration()`                                                         |
| Dependency used by every action  | Controller constructor injection                                                              |
| Dependency used by one action    | `[FromServices]` / `[FromKeyedServices]` on the action parameter                              |
