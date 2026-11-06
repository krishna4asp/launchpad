# Common Infrastructure

> Copy-paste implementations for infrastructure types that skills reference. Add these to your `Shared` or `Common` project and register them in `Program.cs`.

## Result Pattern

```csharp
// Result.cs
public class Result
{
    public bool IsSuccess { get; }
    public bool IsFailure => !IsSuccess;
    public List<string> Errors { get; }

    protected Result(bool isSuccess, List<string>? errors = null)
    {
        IsSuccess = isSuccess;
        Errors = errors ?? [];
    }

    public static Result Success() => new(true);
    public static Result Failure(params string[] errors) => new(false, [..errors]);
    public static Result<T> Success<T>(T value) => new(value);
    public static Result<T> Failure<T>(params string[] errors) => new(errors);
}

public class Result<T> : Result
{
    public T Value { get; }

    internal Result(T value) : base(true) => Value = value;
    internal Result(IEnumerable<string> errors) : base(false, [..errors]) => Value = default!;
}
```

## ApiControllerBase (Result to ProblemDetails)

Shared base controller so every controller returns failures the same way.

```csharp
// ApiControllerBase.cs
[ApiController]
public abstract class ApiControllerBase : ControllerBase
{
    protected ActionResult ToProblemDetails(Result result, int statusCode = StatusCodes.Status400BadRequest)
    {
        // ProblemDetailsFactory adds traceId and applies AddProblemDetails() customisation
        var problem = ProblemDetailsFactory.CreateProblemDetails(
            HttpContext, statusCode, title: "One or more errors occurred");
        problem.Extensions["errors"] = result.Errors;

        return new ObjectResult(problem) { StatusCode = statusCode };
    }
}
```

## Validation Action Filter

One global FluentValidation filter for every controller action.

```csharp
// FluentValidationFilter.cs
// Validates every action argument that has a registered validator
public sealed class FluentValidationFilter(ProblemDetailsFactory problems) : IAsyncActionFilter
{
    public async Task OnActionExecutionAsync(ActionExecutingContext context, ActionExecutionDelegate next)
    {
        foreach (var argument in context.ActionArguments.Values)
        {
            if (argument is null) continue;

            var validatorType = typeof(IValidator<>).MakeGenericType(argument.GetType());
            if (context.HttpContext.RequestServices.GetService(validatorType) is not IValidator validator)
                continue;

            var result = await validator.ValidateAsync(
                new ValidationContext<object>(argument), context.HttpContext.RequestAborted);

            foreach (var error in result.Errors)
                context.ModelState.AddModelError(error.PropertyName, error.ErrorMessage);
        }

        if (!context.ModelState.IsValid)
        {
            var problem = problems.CreateValidationProblemDetails(context.HttpContext, context.ModelState);
            context.Result = new BadRequestObjectResult(problem); // 400 application/problem+json
            return;
        }

        await next();
    }
}

// Registration — applies to every controller action
builder.Services.AddControllers(options => options.Filters.Add<FluentValidationFilter>());
```

`[ApiController]` already returns a `ValidationProblemDetails` 400 for model-binding and DataAnnotations errors before this filter runs. The filter adds FluentValidation rules to the same response shape, so don't call validators by hand inside actions.

## Global Exception Handler

Modern `IExceptionHandler` implementation (preferred over inline `UseExceptionHandler` lambda).

```csharp
// GlobalExceptionHandler.cs
public sealed class GlobalExceptionHandler(
    IProblemDetailsService problemDetails,
    IHostEnvironment env,
    ILogger<GlobalExceptionHandler> logger) : IExceptionHandler
{
    public async ValueTask<bool> TryHandleAsync(
        HttpContext context, Exception exception, CancellationToken ct)
    {
        logger.LogError(exception, "Unhandled exception for {Method} {Path}",
            context.Request.Method, context.Request.Path);

        context.Response.StatusCode = StatusCodes.Status500InternalServerError;
        return await problemDetails.TryWriteAsync(new ProblemDetailsContext
        {
            HttpContext = context,
            Exception = exception,
            ProblemDetails =
            {
                Title = "An unexpected error occurred",
                Status = StatusCodes.Status500InternalServerError,
                Detail = env.IsDevelopment() ? exception.Message : null // don't leak details in production
            }
        });
    }
}
```

## Controllers

Controllers are discovered automatically by `AddControllers()` + `MapControllers()` — no manual registration per feature. Keep one thin controller per resource that only dispatches to handlers.

```csharp
// Features/Orders/OrdersController.cs
[Route("api/orders")]
[Tags("Orders")]
public sealed class OrdersController(ISender sender) : ApiControllerBase
{
    [HttpGet(Name = "ListOrders")]
    [ProducesResponseType<PagedList<OrderResponse>>(StatusCodes.Status200OK)]
    public async Task<ActionResult<PagedList<OrderResponse>>> List(
        [FromQuery] PaginationQuery pagination, CancellationToken ct)
    {
        var result = await sender.Send(new ListOrders.Query(pagination), ct);
        return Ok(result);
    }

    [HttpPost(Name = "CreateOrder")]
    [ProducesResponseType<OrderResponse>(StatusCodes.Status201Created)]
    [ProducesResponseType<ValidationProblemDetails>(StatusCodes.Status400BadRequest)]
    public async Task<ActionResult<OrderResponse>> Create(CreateOrderRequest request, CancellationToken ct)
    {
        var result = await sender.Send(new CreateOrder.Command(request), ct);
        return result.IsSuccess
            ? CreatedAtAction(nameof(GetById), new { id = result.Value.Id }, result.Value)
            : ToProblemDetails(result);
    }

    [HttpGet("{id:guid}", Name = "GetOrderById")]
    [ProducesResponseType<OrderResponse>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    public async Task<ActionResult<OrderResponse>> GetById(Guid id, CancellationToken ct)
    {
        var result = await sender.Send(new GetOrder.Query(id), ct);
        return result.IsSuccess ? Ok(result.Value) : ToProblemDetails(result, StatusCodes.Status404NotFound);
    }
}
```

## Pagination

```csharp
// PaginationQuery.cs
public sealed record PaginationQuery(int Page = 1, int PageSize = 20)
{
    public int Skip => (Page - 1) * PageSize;
}

// PagedList.cs
public sealed record PagedList<T>(
    List<T> Items,
    int TotalCount,
    int Page,
    int PageSize)
{
    public int TotalPages => (int)Math.Ceiling(TotalCount / (double)PageSize);
    public bool HasPrevious => Page > 1;
    public bool HasNext => Page < TotalPages;

    public static async Task<PagedList<T>> CreateAsync(
        IQueryable<T> query, PaginationQuery pagination, CancellationToken ct)
    {
        var totalCount = await query.CountAsync(ct);
        var items = await query
            .Skip(pagination.Skip)
            .Take(pagination.PageSize)
            .ToListAsync(ct);

        return new PagedList<T>(items, totalCount, pagination.Page, pagination.PageSize);
    }
}
```

## Quick Setup Checklist

Register everything in `Program.cs`:

```csharp
// Services
builder.Services.AddControllers(options => options.Filters.Add<FluentValidationFilter>());
builder.Services.AddProblemDetails();
builder.Services.AddExceptionHandler<GlobalExceptionHandler>();
builder.Services.AddValidatorsFromAssemblyContaining<Program>();

// Middleware (order matters)
app.UseExceptionHandler();
app.UseHttpsRedirection();

// Controllers
app.MapControllers();
```

Required NuGet packages:

```bash
dotnet add package FluentValidation.DependencyInjectionExtensions
```
