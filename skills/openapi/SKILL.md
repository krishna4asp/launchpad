---
name: openapi
description: >
  Built-in OpenAPI support for .NET 10 controller-based REST APIs. Covers
  document generation, transformers, controller metadata (ActionResult<T>,
  [ProducesResponseType], [EndpointSummary]), security schemes, XML comments,
  build-time generation, and multiple document support. No Swashbuckle needed.
  Load this skill when setting up API documentation, customizing OpenAPI output,
  adding security schemes to docs, or when the user mentions "OpenAPI",
  "AddOpenApi", "MapOpenApi", "document transformer", "operation transformer",
  "schema transformer", "OpenAPI 3.1", "API documentation", "Swashbuckle
  replacement", "ProducesResponseType", "EndpointSummary", "EndpointDescription",
  "ApiExplorerSettings", "ProblemDetails", "Kiota", or "client generation".
---

# OpenAPI

## Core Principles

1. **Built-in, not Swashbuckle** — .NET 10 ships `Microsoft.AspNetCore.OpenApi` as the official, framework-maintained OpenAPI solution. Swashbuckle was removed from templates in .NET 9 and is no longer recommended.
2. **`ActionResult<T>` + `[ProducesResponseType]` drive the schema** — `ActionResult<T>` gives the success schema. `[ProducesResponseType<T>(status)]` declares every other status (201, 400, 404). An untyped `IActionResult` with no attributes leaves the spec without response schemas.
3. **Transformers over workarounds** — Document, operation, and schema transformers compose cleanly. Use them for security schemes, global responses, and schema customization.
4. **Metadata on every action** — Give every action a route `Name` (it becomes the `operationId`), `[EndpointSummary]` and, where useful, `[EndpointDescription]`. Put `[Tags]` on the controller. This metadata feeds directly into the OpenAPI spec and client generators. Controller conventions live in the `controller-based-apis` skill.

## Patterns

### Basic Setup

```csharp
var builder = WebApplication.CreateBuilder(args);
builder.Services.AddControllers(); // registers ApiExplorer — no AddEndpointsApiExplorer needed
builder.Services.AddOpenApi();

var app = builder.Build();

if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();  // Serves at /openapi/v1.json
}

app.MapControllers();
```

### Action Metadata

```csharp
[Route("api/orders")]
[Tags("Orders")]
[Authorize]
public sealed class OrdersController(ISender sender) : ApiControllerBase
{
    [HttpPost(Name = "CreateOrder")] // operationId: CreateOrder
    [EndpointSummary("Create a new order")]
    [EndpointDescription("Creates a new order for the specified customer.")]
    [ProducesResponseType<OrderResponse>(StatusCodes.Status201Created)]
    [ProducesResponseType<ValidationProblemDetails>(StatusCodes.Status400BadRequest)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status500InternalServerError)]
    public async Task<ActionResult<OrderResponse>> Create(CreateOrderRequest request, CancellationToken ct)
    {
        var result = await sender.Send(new CreateOrder.Command(request), ct);
        return result.IsSuccess
            ? CreatedAtRoute("GetOrder", new { id = result.Value.Id }, result.Value)
            : ToProblemDetails(result);
    }

    [HttpGet("{id:guid}", Name = "GetOrder")]
    [EndpointSummary("Get an order by ID")]
    [ProducesResponseType<OrderResponse>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    public async Task<ActionResult<OrderResponse>> GetById(Guid id, CancellationToken ct)
    {
        var result = await sender.Send(new GetOrder.Query(id), ct);
        return result.IsSuccess ? result.Value : ToProblemDetails(result, StatusCodes.Status404NotFound);
    }
}
```

`ApiControllerBase` and `ToProblemDetails` come from the `error-handling` skill. To avoid repeating the 500 response on every action, put `[ProducesResponseType<ProblemDetails>(500)]` on `ApiControllerBase` or add it globally with `AddControllers(o => o.Filters.Add(new ProducesResponseTypeAttribute<ProblemDetails>(500)))`.

### Bearer Token Security Scheme

```csharp
builder.Services.AddOpenApi(options =>
{
    options.AddDocumentTransformer<BearerSecuritySchemeTransformer>();
});

internal sealed class BearerSecuritySchemeTransformer(
    IAuthenticationSchemeProvider authSchemeProvider) : IOpenApiDocumentTransformer
{
    public async Task TransformAsync(OpenApiDocument document,
        OpenApiDocumentTransformerContext context, CancellationToken ct)
    {
        var schemes = await authSchemeProvider.GetAllSchemesAsync();
        if (!schemes.Any(s => s.Name == "Bearer"))
            return;

        document.Components ??= new OpenApiComponents();
        document.Components.SecuritySchemes = new Dictionary<string, IOpenApiSecurityScheme>
        {
            ["Bearer"] = new OpenApiSecurityScheme
            {
                Type = SecuritySchemeType.Http,
                Scheme = "bearer",
                BearerFormat = "JWT",
                In = ParameterLocation.Header
            }
        };

        foreach (var operation in document.Paths.Values.SelectMany(p => p.Operations))
        {
            operation.Value.Security ??= [];
            operation.Value.Security.Add(new OpenApiSecurityRequirement
            {
                [new OpenApiSecuritySchemeReference("Bearer", document)] = []
            });
        }
    }
}
```

### Document Info Transformer

```csharp
builder.Services.AddOpenApi(options =>
{
    options.AddDocumentTransformer((document, context, ct) =>
    {
        document.Info = new()
        {
            Title = "Checkout API",
            Version = "v1",
            Description = "API for processing orders and payments."
        };
        return Task.CompletedTask;
    });
});
```

### Multiple OpenAPI Documents

```csharp
builder.Services.AddOpenApi("v1");
builder.Services.AddOpenApi("internal", options =>
{
    options.AddDocumentTransformer<BearerSecuritySchemeTransformer>();
});

// Controllers choose their document via ApiExplorer group name
[ApiExplorerSettings(GroupName = "v1")]
[Route("api/catalog")]
public sealed class CatalogController : ApiControllerBase { /* ... */ }

[ApiExplorerSettings(GroupName = "internal")]
[Route("api/admin")]
public sealed class AdminController : ApiControllerBase { /* ... */ }

[ApiExplorerSettings(IgnoreApi = true)] // excluded from every document
public sealed class LegacyCallbackController : ControllerBase { /* ... */ }
```

Controllers without a group name appear in all documents. For one document per API version, let Asp.Versioning set the group names (`AddApiExplorer(o => o.GroupNameFormat = "'v'VVV")`) instead of hand-writing `GroupName`. See the `api-versioning` skill.

### XML Documentation Comments (.NET 10)

Enable in the project file — the source generator extracts `<summary>`, `<param>`, `<response>` tags automatically:

```xml
<PropertyGroup>
    <GenerateDocumentationFile>true</GenerateDocumentationFile>
</PropertyGroup>
```

```csharp
/// <summary>Retrieves a project board by ID.</summary>
/// <param name="id">The project board ID.</param>
/// <response code="200">Returns the project board.</response>
/// <response code="404">Board not found.</response>
[HttpGet("{id:int}", Name = "GetBoard")]
[ProducesResponseType<Board>(StatusCodes.Status200OK)]
[ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
public async Task<ActionResult<Board>> GetBoard(int id, CancellationToken ct)
{
    var board = await db.Boards.FindAsync([id], ct);
    return board is not null ? board : Problem(statusCode: StatusCodes.Status404NotFound);
}
```

Use either XML comments or `[EndpointSummary]` for a given action, not both, so the summary has one source of truth.

### Schema Transformer

```csharp
options.AddSchemaTransformer((schema, context, ct) =>
{
    if (context.JsonTypeInfo.Type == typeof(decimal))
    {
        schema.Format = "decimal";
    }
    return Task.CompletedTask;
});
```

### Operation Transformer: Deprecated Actions

```csharp
builder.Services.AddOpenApi(options =>
{
    options.AddOperationTransformer((operation, context, ct) =>
    {
        // [Obsolete] on a controller or action marks the operation deprecated
        if (context.Description.ActionDescriptor.EndpointMetadata.OfType<ObsoleteAttribute>().Any())
        {
            operation.Deprecated = true;
        }
        return Task.CompletedTask;
    });
});

[HttpGet("legacy", Name = "GetLegacyOrders")]
[Obsolete("Use GET /api/orders instead.")]
public ActionResult<List<OrderResponse>> GetLegacy() => /* ... */;
```

To apply a transformer to every controller action without a document-level registration, use `app.MapControllers().AddOpenApiOperationTransformer(...)`. For whole API versions, use `[ApiVersion(1.0, Deprecated = true)]` (see the `api-versioning` skill).

### Build-Time Document Generation

```xml
<PackageReference Include="Microsoft.Extensions.ApiDescription.Server" Version="*" />
<PropertyGroup>
    <OpenApiDocumentsDirectory>.</OpenApiDocumentsDirectory>
</PropertyGroup>
```

The spec file is generated in the output directory during build.

### YAML Endpoint (.NET 10)

```csharp
app.MapOpenApi("/openapi/{documentName}.yaml");
```

## Anti-patterns

### Don't Use Swashbuckle for New Projects

```csharp
// BAD — removed from .NET 9+ templates, maintenance concerns
builder.Services.AddSwaggerGen();
app.UseSwagger();
app.UseSwaggerUI();

// GOOD — built-in OpenAPI
builder.Services.AddOpenApi();
app.MapOpenApi();
```

### Don't Use Swashbuckle Annotations

```csharp
// BAD — Swashbuckle.AspNetCore.Annotations; ignored by Microsoft.AspNetCore.OpenApi
[SwaggerOperation(Summary = "Create a new order")]
[SwaggerResponse(201, "Created", typeof(OrderResponse))]
public async Task<IActionResult> Create(CreateOrderRequest request) { /* ... */ }

// GOOD — framework attributes the built-in generator reads
[EndpointSummary("Create a new order")]
[ProducesResponseType<OrderResponse>(StatusCodes.Status201Created)]
public async Task<ActionResult<OrderResponse>> Create(CreateOrderRequest request, CancellationToken ct) { /* ... */ }
```

### Don't Use Untyped Results

```csharp
// BAD — IActionResult with no attributes: the spec has no response schema
[HttpGet("{id:guid}")]
public async Task<IActionResult> GetOrder(Guid id)
{
    var order = await db.Orders.FindAsync(id);
    return order is not null ? Ok(order) : NotFound();
}

// GOOD — ActionResult<T> for the success schema, attributes for the rest
[HttpGet("{id:guid}", Name = "GetOrder")]
[ProducesResponseType<OrderResponse>(StatusCodes.Status200OK)]
[ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
public async Task<ActionResult<OrderResponse>> GetOrder(Guid id, CancellationToken ct)
{
    var order = await db.Orders.FindAsync([id], ct);
    return order is not null ? order.ToResponse() : Problem(statusCode: StatusCodes.Status404NotFound);
}
```

### Don't Skip the Route Name

```csharp
// BAD — client generators produce poor method names without operationId
[HttpGet("{id:guid}")]
public async Task<ActionResult<OrderResponse>> GetById(Guid id, CancellationToken ct) => /* ... */;

// GOOD — route Name becomes the operationId and feeds generated client method names
[HttpGet("{id:guid}", Name = "GetOrder")]
public async Task<ActionResult<OrderResponse>> GetById(Guid id, CancellationToken ct) => /* ... */;
```

### Don't Use OpenApiAny in .NET 10

```csharp
// BAD — OpenApiAny types removed in Microsoft.OpenApi v2.x
schema.Example = new OpenApiString("2025-01-01");

// GOOD — use JsonNode from System.Text.Json.Nodes
schema.Example = JsonValue.Create("2025-01-01");
```

## Decision Guide

| Scenario | Recommendation |
|----------|---------------|
| New API project | `AddControllers()` + `AddOpenApi()` + `MapOpenApi()` (built-in) |
| API documentation UI | Scalar (`MapScalarApiReference()`) — see `scalar` skill |
| Security schemes in docs | Document transformer with `IOpenApiDocumentTransformer` |
| Response documentation | `ActionResult<T>` + `[ProducesResponseType<T>(status)]` |
| Summaries and operationIds | `[EndpointSummary]` + route `Name` on every action |
| XML doc integration | `<GenerateDocumentationFile>true</GenerateDocumentationFile>` |
| Separate public/internal docs | Multiple `AddOpenApi("name")` + `[ApiExplorerSettings(GroupName = "name")]` |
| Multiple API versions | Asp.Versioning ApiExplorer group names + `AddOpenApi("v1")`, `AddOpenApi("v2")` — see `api-versioning` |
| Hide a controller from docs | `[ApiExplorerSettings(IgnoreApi = true)]` |
| Deprecated action | `[Obsolete]` + operation transformer setting `Deprecated = true` |
| Client code generation | Kiota (Microsoft recommended) or NSwag |
| Build-time spec | `Microsoft.Extensions.ApiDescription.Server` package |
| OpenAPI version | 3.1 (default in .NET 10), force 3.0 if consumers require it |

## Related

- `controller-based-apis` — controller, routing and `ActionResult<T>` conventions
- `api-versioning` — per-version OpenAPI documents
- `scalar` — the API reference UI over these documents
- `error-handling` — `ApiControllerBase`, `ToProblemDetails`, ProblemDetails responses
