---
name: controller-based-apis
description: >
  .NET 10 controller-based REST APIs — the default for building HTTP endpoints in
  this codebase. Covers [ApiController] controllers, attribute routing,
  ActionResult<T>, ProducesResponseType and OpenAPI metadata, parameter binding,
  action filters, rate limiting, and output caching.
  Load this skill when creating or changing API endpoints, configuring routing,
  setting up OpenAPI documentation, or when the user mentions "endpoint",
  "controller", "ApiController", "ControllerBase", "HttpGet", "HttpPost",
  "ActionResult", "route", "REST API", "OpenAPI", "swagger", "rate limiting", or
  "output caching" — even if they only say "add an endpoint", since controllers
  are the standard here.
---

# Controller-Based REST APIs (.NET 10)

## Core Principles

1. **Controllers are the default** — Every HTTP endpoint lives in an attribute-routed `[ApiController]` class, discovered by `MapControllers()`. One style keeps routing, filters, auth and OpenAPI consistent.
2. **One controller per resource, thin actions** — An action maps HTTP to a command or query (`ISender`, a service, or `IMessageBus`) and maps the result back to HTTP. Business logic and data access stay out of controllers.
3. **`ActionResult<T>` plus `[ProducesResponseType]`** — `ActionResult<T>` gives the success type to OpenAPI and the compiler; `[ProducesResponseType]` documents every other status code the action can return. `IActionResult` alone documents nothing.
4. **Attributes are the metadata** — `[HttpPost(Name = ...)]`, `[Tags]`, `[EndpointSummary]` and `[ProducesResponseType]` feed the OpenAPI document. Prefer them over XML comments.
5. **Errors are always ProblemDetails** — Derive from `ApiControllerBase` (see the **error-handling** skill) and use its `ToProblemDetails` / `ToActionResult` helpers, or `Problem()` / `ValidationProblem()`.

## Patterns

### Program.cs Setup

`MapControllers()` discovers every controller in the assembly, so **Program.cs never changes when you add a controller.**

```csharp
// Program.cs
builder.Services.AddControllers(options =>
    options.Filters.Add<FluentValidationFilter>()); // global validation (error-handling skill)
builder.Services.AddProblemDetails();
builder.Services.AddOpenApi();

var app = builder.Build();

app.UseExceptionHandler();
app.UseAuthentication();
app.UseAuthorization();

if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();
}

app.MapControllers(); // discovers all [ApiController] classes
app.Run();
```

### A Resource Controller

```csharp
// Features/Orders/OrdersController.cs — one controller per resource
[Route("api/orders")]          // explicit route: renaming the class won't change the URL
[Tags("Orders")]
[Authorize]                    // every action requires auth unless it opts out
[Produces("application/json")]
public sealed class OrdersController(ISender sender) : ApiControllerBase
{
    [HttpPost(Name = "CreateOrder")]
    [EndpointSummary("Create a new order")]
    [ProducesResponseType<OrderResponse>(StatusCodes.Status201Created)]
    [ProducesResponseType<ValidationProblemDetails>(StatusCodes.Status400BadRequest)]
    public async Task<ActionResult<OrderResponse>> Create(CreateOrderRequest request, CancellationToken ct)
    {
        var result = await sender.Send(new CreateOrder.Command(request.CustomerId, request.Items), ct);
        return result.IsSuccess
            ? CreatedAtRoute("GetOrder", new { id = result.Value.Id }, result.Value)
            : ToProblemDetails(result);
    }

    [HttpGet("{id:guid}", Name = "GetOrder")]
    [ProducesResponseType<OrderResponse>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    public async Task<ActionResult<OrderResponse>> GetById(Guid id, CancellationToken ct)
    {
        var result = await sender.Send(new GetOrder.Query(id), ct);
        return result.IsSuccess
            ? result.Value                 // implicit 200 OK via ActionResult<T>
            : Problem(title: $"Order {id} was not found", statusCode: StatusCodes.Status404NotFound);
    }

    [HttpGet(Name = "ListOrders")]
    [AllowAnonymous]
    [ProducesResponseType<PagedList<OrderResponse>>(StatusCodes.Status200OK)]
    public async Task<ActionResult<PagedList<OrderResponse>>> List(
        [FromQuery] ListOrdersQuery query, CancellationToken ct)
        => await sender.Send(query, ct);
}
```

Why `[ApiController]` (inherited from `ApiControllerBase`): it turns on attribute-routing requirements, automatic 400 `ValidationProblemDetails` for invalid models, binding-source inference, and ProblemDetails for error status codes. Without it you end up writing `if (!ModelState.IsValid)` in every action.

### ActionResult&lt;T&gt; for Type-Safe Responses

```csharp
// GOOD — success type is known to the compiler and to OpenAPI
[HttpGet("{id:guid}")]
[ProducesResponseType<ProductResponse>(StatusCodes.Status200OK)]
[ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
public async Task<ActionResult<ProductResponse>> GetById(Guid id, CancellationToken ct)
{
    var product = await products.GetAsync(id, ct);
    return product is not null ? product : NotFound();
}
```

Return the value directly for 200, and use `CreatedAtRoute` / `CreatedAtAction` for 201 (it sets the `Location` header). Use `NoContent()` for successful updates and deletes, and `Accepted()` for queued work.

### Parameter Binding

`[ApiController]` infers where each parameter comes from. Add attributes only when the inference is wrong or unclear.

```csharp
// Route — any parameter named in the route template
[HttpGet("{id:guid}")]
public Task<ActionResult<OrderResponse>> GetById(Guid id, CancellationToken ct) => ...;

// Query — simple types not in the route (nullable = optional)
[HttpGet]
public Task<ActionResult<PagedList<OrderResponse>>> List(int page = 1, int? pageSize = null, string? status = null) => ...;

// Complex query object — [FromQuery] is required, otherwise it's treated as the body
public record ListOrdersQuery(int Page = 1, int PageSize = 20, string? Status = null);
[HttpGet]
public Task<ActionResult<PagedList<OrderResponse>>> List([FromQuery] ListOrdersQuery query) => ...;

// Header
[HttpGet]
public IActionResult Get([FromHeader(Name = "X-Correlation-Id")] string? correlationId) => ...;

// Body — complex types are inferred as [FromBody]; only one body parameter per action
[HttpPost]
public Task<ActionResult<OrderResponse>> Create(CreateOrderRequest request) => ...;

// Services — constructor injection by default; [FromServices] for a dependency only one action uses
[HttpPost("{id:guid}/notify")]
public Task<IActionResult> Notify(Guid id, [FromKeyedServices("sms")] INotificationService notifier) => ...;
```

### Action Filters

Use action filters for cross-cutting concerns like validation, logging and idempotency checks.

The canonical `FluentValidationFilter` (validates every action argument that has a registered validator, returns `ValidationProblemDetails`) lives in the **error-handling** skill. Register it globally in `AddControllers` — don't re-implement it per project, and don't call validators by hand in actions.

```csharp
// Global — every action in the app
builder.Services.AddControllers(options => options.Filters.Add<FluentValidationFilter>());

// One controller or action — resolve the filter from DI so it can take dependencies
builder.Services.AddScoped<IdempotencyFilter>();

[HttpPost]
[ServiceFilter<IdempotencyFilter>]
public Task<ActionResult<OrderResponse>> Create(CreateOrderRequest request, CancellationToken ct) => ...;
```

### OpenAPI Configuration

.NET 10 has built-in OpenAPI support (`Microsoft.AspNetCore.OpenApi`). Use it instead of Swashbuckle.

```csharp
// Program.cs
builder.Services.AddOpenApi();
// ...
if (app.Environment.IsDevelopment())
{
    app.MapOpenApi(); // /openapi/v1.json
}

// Attributes on the action enrich the spec
[HttpPost(Name = "CreateOrder")]                       // operationId
[EndpointSummary("Create a new order")]
[EndpointDescription("Creates a new order for the specified customer with the given line items.")]
[ProducesResponseType<OrderResponse>(StatusCodes.Status201Created)]
[ProducesResponseType<ValidationProblemDetails>(StatusCodes.Status400BadRequest)]
[ProducesResponseType<ProblemDetails>(StatusCodes.Status500InternalServerError)]
public async Task<ActionResult<OrderResponse>> Create(CreateOrderRequest request, CancellationToken ct) => ...;
```

### Rate Limiting

```csharp
builder.Services.AddRateLimiter(options =>
{
    options.AddFixedWindowLimiter("api", opt =>
    {
        opt.PermitLimit = 100;
        opt.Window = TimeSpan.FromMinutes(1);
    });
});
// ...
app.UseRateLimiter(); // after UseRouting/auth, before MapControllers

// Apply to a controller (all actions) and opt individual actions out
[Route("api/orders")]
[EnableRateLimiting("api")]
public sealed class OrdersController(ISender sender) : ApiControllerBase
{
    [HttpGet("status")]
    [DisableRateLimiting] // cheap, frequently polled action
    public IActionResult Status() => Ok();
}
```

### Output Caching

```csharp
builder.Services.AddOutputCache(options =>
{
    options.AddBasePolicy(policy => policy.Expire(TimeSpan.FromMinutes(5)));
    options.AddPolicy("ByIdCache", policy => policy
        .Expire(TimeSpan.FromMinutes(10))
        .SetVaryByRouteValue("id"));
});
// ...
app.UseOutputCache(); // after UseCors/UseAuthorization, before MapControllers

[HttpGet("{id:guid}", Name = "GetOrder")]
[OutputCache(PolicyName = "ByIdCache")]
public async Task<ActionResult<OrderResponse>> GetById(Guid id, CancellationToken ct) => ...;
```

## Anti-patterns

### Don't Use Conventional Routing for APIs

```csharp
// BAD — conventional routing: URLs depend on class/method names and OpenAPI can't describe them
app.MapControllerRoute("default", "{controller}/{action}/{id?}");

// GOOD — attribute-routed controllers, discovered automatically
app.MapControllers();
```

### Don't Return Untyped, Undocumented Results

```csharp
// BAD — IActionResult with no metadata: OpenAPI shows no response schema
[HttpGet("{id}")]
public async Task<IActionResult> Get(Guid id)
{
    var order = await orders.GetAsync(id);
    return order is not null ? Ok(order) : NotFound();
}

// GOOD — ActionResult<T> + ProducesResponseType for the other status codes
[HttpGet("{id:guid}")]
[ProducesResponseType<OrderResponse>(StatusCodes.Status200OK)]
[ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
public async Task<ActionResult<OrderResponse>> Get(Guid id, CancellationToken ct)
{
    var order = await orders.GetAsync(id, ct);
    return order is not null ? order : NotFound();
}
```

### Don't Put Business Logic or Data Access in Controllers

```csharp
// BAD — fat controller: queries, rules and persistence inside the action
public sealed class OrdersController(AppDbContext db) : ApiControllerBase
{
    [HttpPost]
    public async Task<ActionResult<Order>> Create(Order order)
    {
        if (order.Items.Count == 0) return BadRequest("No items");
        order.Total = order.Items.Sum(i => i.Price * i.Quantity);
        db.Orders.Add(order);
        await db.SaveChangesAsync();
        return order;
    }
}

// GOOD — the action translates HTTP; the handler owns the logic
[HttpPost(Name = "CreateOrder")]
public async Task<ActionResult<OrderResponse>> Create(CreateOrderRequest request, CancellationToken ct)
{
    var result = await sender.Send(new CreateOrder.Command(request.CustomerId, request.Items), ct);
    return result.IsSuccess
        ? CreatedAtRoute("GetOrder", new { id = result.Value.Id }, result.Value)
        : ToProblemDetails(result);
}
```

### Don't Return Domain Entities Directly

```csharp
// BAD — leaks internal structure, can't evolve independently
[HttpGet("{id:guid}")]
public async Task<ActionResult<Order>> Get(Guid id) =>
    await db.Orders.Include(o => o.Items).FirstOrDefaultAsync(o => o.Id == id);

// GOOD — map to a response DTO (projection in the query handler)
[HttpGet("{id:guid}")]
public async Task<ActionResult<OrderResponse>> Get(Guid id, CancellationToken ct)
{
    var result = await sender.Send(new GetOrder.Query(id), ct); // projects to OrderResponse
    return result.IsSuccess ? result.Value : NotFound();
}
```

## Decision Guide

| Scenario                     | Recommendation                                                            |
| ---------------------------- | ------------------------------------------------------------------------- |
| New HTTP API                 | One `[ApiController]` per resource deriving `ApiControllerBase` + `MapControllers()` |
| Route naming                 | Explicit `[Route("api/orders")]`, constraints like `{id:guid}`             |
| Response types               | `ActionResult<T>` + `[ProducesResponseType]` for non-success codes         |
| OpenAPI documentation        | `AddOpenApi()` + `[HttpX(Name = ...)]`, `[Tags]`, `[EndpointSummary]`      |
| Error responses              | ProblemDetails via `ApiControllerBase` helpers (error-handling skill)      |
| Request validation           | Global `FluentValidationFilter` (error-handling skill)                     |
| Authentication/authorization | `[Authorize]` / `[Authorize(Policy = "...")]` on the controller, `[AllowAnonymous]` per action |
| Rate limiting                | `AddRateLimiter` + `[EnableRateLimiting("policy")]`                        |
| Response caching             | `AddOutputCache` + `[OutputCache(PolicyName = "...")]`                     |
| Complex query parameters     | `[FromQuery]` on a record type                                            |
| Cross-cutting per action     | `[ServiceFilter<T>]` action filter                                        |
