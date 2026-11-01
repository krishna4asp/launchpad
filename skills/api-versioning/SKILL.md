---
name: api-versioning
description: >
  API versioning strategies for ASP.NET Core controller-based REST APIs. Covers
  Asp.Versioning.Mvc ([ApiVersion] on [ApiController] classes), URL segment,
  header, and query string strategies, version deprecation, and OpenAPI integration.
  Load this skill when adding versioning to an API, evolving an API with breaking
  changes, or when the user mentions "API version", "versioning", "v1/v2",
  "Asp.Versioning", "deprecation", "breaking change", or "backward compatibility".
---

# API Versioning

## Core Principles

1. **Version from day one** — Adding versioning later is painful. Start with a version in the URL even if you only have v1.
2. **URL segment versioning is the default** — `/api/v1/orders` is the most discoverable and cache-friendly strategy.
3. **Never break existing versions** — Add a new version for breaking changes. Deprecate the old version with a timeline.
4. **Version the API, not individual actions** — Every action on a versioned controller shares that controller's version number.
5. **REST API controllers** — Endpoints are attribute-routed `[ApiController]` classes (see the `controller-based-apis` skill), versioned with `[ApiVersion]` from `Asp.Versioning.Mvc`.

## Patterns

### Setup with Asp.Versioning

```csharp
// Program.cs — packages: Asp.Versioning.Mvc, Asp.Versioning.Mvc.ApiExplorer
builder.Services.AddControllers();

builder.Services.AddApiVersioning(options =>
{
    options.DefaultApiVersion = new ApiVersion(1, 0);
    options.AssumeDefaultVersionWhenUnspecified = true;
    options.ReportApiVersions = true;
    options.ApiVersionReader = new UrlSegmentApiVersionReader();
})
.AddMvc() // required for controllers — without it [ApiVersion] is ignored
.AddApiExplorer(options =>
{
    options.GroupNameFormat = "'v'VVV";
    options.SubstituteApiVersionInUrl = true;
});

var app = builder.Build();
app.MapControllers();
```

### URL Segment Versioning (Recommended)

```csharp
// The controller declares its version; the route template carries it
[ApiVersion(1.0)]
[Route("api/v{version:apiVersion}/orders")]
[Tags("Orders")]
public sealed class OrdersController(ISender sender) : ApiControllerBase { /* v1 actions */ }

// Client calls: GET /api/v1/orders/{id}
```

### Header Versioning (Alternative)

```csharp
options.ApiVersionReader = new HeaderApiVersionReader("X-Api-Version");

// Controller route drops the segment: [Route("api/orders")]
// Client sends: X-Api-Version: 2.0
```

### Deprecating a Version

```csharp
[ApiVersion(1.0, Deprecated = true)]
[Route("api/v{version:apiVersion}/orders")]
public sealed class OrdersController(ISender sender) : ApiControllerBase { /* v1 actions */ }

// Response headers will include: api-deprecated-versions: 1.0
```

### Version-Specific Controllers

One controller per major version, in a version namespace. Both keep the name `OrdersController`, so they are the same resource and differ only by version.

```csharp
// Features/Orders/V1/OrdersController.cs
namespace MyApp.Api.Features.Orders.V1;

[ApiVersion(1.0)]
[Route("api/v{version:apiVersion}/orders")]
[Tags("Orders")]
public sealed class OrdersController(ISender sender) : ApiControllerBase
{
    [HttpGet("{id:guid}", Name = "GetOrderV1")]
    [ProducesResponseType<OrderResponseV1>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    public async Task<ActionResult<OrderResponseV1>> GetById(Guid id, CancellationToken ct)
    {
        // V1 response shape
        var result = await sender.Send(new GetOrder.Query(id), ct);
        return result.IsSuccess
            ? result.Value.ToV1()
            : ToProblemDetails(result, StatusCodes.Status404NotFound);
    }
}

// Features/Orders/V2/OrdersController.cs
namespace MyApp.Api.Features.Orders.V2;

[ApiVersion(2.0)]
[Route("api/v{version:apiVersion}/orders")]
[Tags("Orders")]
public sealed class OrdersController(ISender sender) : ApiControllerBase
{
    [HttpGet("{id:guid}", Name = "GetOrderV2")]
    [ProducesResponseType<OrderResponseV2>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    public async Task<ActionResult<OrderResponseV2>> GetById(Guid id, CancellationToken ct)
    {
        // V2 response shape — includes new fields
        var result = await sender.Send(new GetOrder.Query(id), ct);
        return result.IsSuccess
            ? result.Value.ToV2()
            : ToProblemDetails(result, StatusCodes.Status404NotFound);
    }
}
```

Route names must be unique across versions (`GetOrderV1`, `GetOrderV2`). When a version adds just one action, keep a single controller with `[ApiVersion(1.0)]` and `[ApiVersion(2.0)]`, and put `[MapToApiVersion(2.0)]` on the new action.

## Anti-patterns

### Don't Version Individual Actions

```csharp
// BAD — hard-coded, inconsistent versions within one controller
[Route("api")]
public sealed class OrdersController : ApiControllerBase
{
    [HttpGet("v1/orders")]      public ActionResult<List<OrderResponseV1>> List() => /* ... */;
    [HttpGet("v2/orders/{id}")] public ActionResult<OrderResponseV2> GetById(Guid id) => /* ... */; // V2 only here?
}

// GOOD — version the entire controller
[ApiVersion(2.0)]
[Route("api/v{version:apiVersion}/orders")]
public sealed class OrdersController(ISender sender) : ApiControllerBase { /* all v2 actions */ }
```

### Don't Use Query String Versioning as Default

```csharp
// BAD for REST APIs — version hidden in query string, not cache-friendly
GET /api/orders?api-version=2.0

// GOOD — version in URL, discoverable and cacheable
GET /api/v2/orders
```

## Decision Guide

| Scenario                       | Recommendation                                            |
| ------------------------------ | --------------------------------------------------------- |
| New public API                 | URL segment versioning from day one                       |
| Internal API between services  | Header versioning (cleaner URLs)                          |
| Breaking response shape change | New version — new `V2/OrdersController`                   |
| One new action in next version | Same controller + `[MapToApiVersion(2.0)]` on that action |
| Adding new optional fields     | Same version (backwards compatible)                       |
| Deprecating a version          | `[ApiVersion(1.0, Deprecated = true)]`, set sunset date, document migration path |
