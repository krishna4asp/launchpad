---
name: error-handling
description: >
  Error handling strategy for .NET 10 applications. Covers the Result pattern,
  ProblemDetails (RFC 9457), global exception handling, FluentValidation, and
  structured error responses.
  Load this skill when implementing error handling, validation, or designing
  API error contracts, or when the user mentions "error handling", "Result pattern",
  "ProblemDetails", "exception", "validation", "FluentValidation", "error response",
  "global exception handler", "IExceptionHandler", "action filter", "ValidationProblem", or "RFC 9457".
---

# Error Handling

## Core Principles

1. **Use the Result pattern for expected failures** — Don't throw exceptions for things like "order not found" or "validation failed". These are expected outcomes, not exceptional conditions. See ADR-002.
2. **Reserve exceptions for unexpected failures** — Database connection lost, null reference bugs, network timeouts — these are truly exceptional and should propagate to the global handler.
3. **Every API error returns ProblemDetails** — RFC 9457 is the standard. Every error response has `type`, `title`, `status`, `detail`, and optionally `errors`.
4. **Validate at the boundary** — Validate incoming requests at the API layer, not deep inside business logic.
5. **REST API controllers** — All endpoint samples use attribute-routed controllers (`[ApiController]`, `ControllerBase`) — see the `controller-based-apis` skill. Build error responses with `ProblemDetailsFactory` (via `Problem()` / `ValidationProblem()`) so every error has the same shape and a `traceId`.

## Patterns

### Result Pattern

A simple, generic result type that carries either a value or errors.

```csharp
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

### Result to ProblemDetails Mapping

Put the mapping in a shared base controller so every controller returns failures the same way.

```csharp
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

// Usage in a controller action
[Route("api/orders")]
public class OrdersController(ISender sender) : ApiControllerBase
{
    [HttpPost]
    public async Task<ActionResult<OrderResponse>> Create(CreateOrder.Command command, CancellationToken ct)
    {
        var result = await sender.Send(command, ct);
        return result.IsSuccess
            ? CreatedAtAction(nameof(GetById), new { id = result.Value.Id }, result.Value)
            : ToProblemDetails(result);
    }

    [HttpGet("{id:guid}")]
    public async Task<ActionResult<OrderResponse>> GetById(Guid id, CancellationToken ct) => /* ... */ Ok();
}
```

### Global Exception Handler

Catches unexpected exceptions and converts them to ProblemDetails. Prefer `IExceptionHandler` — it is a normal DI service, so it is easy to test and writes through `IProblemDetailsService`:

```csharp
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

// Program.cs
builder.Services.AddProblemDetails();
builder.Services.AddExceptionHandler<GlobalExceptionHandler>();
// ...
app.UseExceptionHandler();
```

The inline lambda below works for simple cases:

```csharp
// Program.cs
app.UseExceptionHandler(errorApp =>
{
    errorApp.Run(async context =>
    {
        var exception = context.Features.Get<IExceptionHandlerFeature>()?.Error;
        var logger = context.RequestServices.GetRequiredService<ILogger<Program>>();

        logger.LogError(exception, "Unhandled exception for {Method} {Path}",
            context.Request.Method, context.Request.Path);

        var problem = new ProblemDetails
        {
            Title = "An unexpected error occurred",
            Status = StatusCodes.Status500InternalServerError,
            Type = "https://tools.ietf.org/html/rfc9110#section-15.6.1"
        };

        // Don't leak details in production
        if (context.RequestServices.GetRequiredService<IHostEnvironment>().IsDevelopment())
        {
            problem.Detail = exception?.Message;
        }

        context.Response.StatusCode = problem.Status.Value;
        await context.Response.WriteAsJsonAsync(problem);
    });
});
```

### FluentValidation with an Action Filter

```csharp
// Validator
public class CreateOrderValidator : AbstractValidator<CreateOrderRequest>
{
    public CreateOrderValidator()
    {
        RuleFor(x => x.CustomerId)
            .NotEmpty().WithMessage("Customer ID is required");

        RuleFor(x => x.Items)
            .NotEmpty().WithMessage("At least one item is required");

        RuleForEach(x => x.Items).ChildRules(item =>
        {
            item.RuleFor(x => x.ProductId).NotEmpty();
            item.RuleFor(x => x.Quantity).GreaterThan(0);
        });
    }
}

// One global filter validates every action argument that has a registered validator
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
builder.Services.AddValidatorsFromAssemblyContaining<CreateOrderValidator>();
builder.Services.AddControllers(options => options.Filters.Add<FluentValidationFilter>());
```

`[ApiController]` already returns a `ValidationProblemDetails` 400 for model-binding and DataAnnotations errors before this filter runs. The filter adds FluentValidation rules to the same response shape, so don't call validators by hand inside actions.

### Typed Error Results

For richer error handling, use typed error enums or error objects.

```csharp
public abstract record Error(string Code, string Message);
public record NotFoundError(string Entity, object Id)
    : Error("not_found", $"{Entity} with ID {Id} was not found");
public record ValidationError(string Field, string Message)
    : Error("validation", Message);
public record ConflictError(string Message)
    : Error("conflict", Message);

// Map to HTTP status codes — add to ApiControllerBase
protected ActionResult ToActionResult(Error error) => error switch
{
    NotFoundError => Problem(title: error.Message, statusCode: StatusCodes.Status404NotFound),
    ValidationError => Problem(title: error.Message, statusCode: StatusCodes.Status400BadRequest),
    ConflictError => Problem(title: error.Message, statusCode: StatusCodes.Status409Conflict),
    _ => Problem(title: error.Message, statusCode: StatusCodes.Status500InternalServerError)
};

// Usage in an action
[HttpGet("{id:guid}")]
public async Task<ActionResult<OrderResponse>> GetById(Guid id, CancellationToken ct)
{
    var result = await orders.GetAsync(id, ct); // returns a result carrying an Error on failure
    return result.IsSuccess ? Ok(result.Value) : ToActionResult(result.Error);
}
```

## Anti-patterns

### Don't Throw Exceptions for Flow Control

```csharp
// BAD — exceptions for expected outcomes
public Order GetOrder(Guid id)
{
    var order = db.Orders.Find(id)
        ?? throw new NotFoundException($"Order {id} not found");
    return order;
}

// GOOD — Result pattern
public Result<Order> GetOrder(Guid id)
{
    var order = db.Orders.Find(id);
    return order is not null
        ? Result.Success(order)
        : Result.Failure<Order>($"Order {id} not found");
}
```

### Don't Return Raw Error Strings from APIs

```csharp
// BAD — inconsistent error format
return BadRequest("Something went wrong");
return BadRequest(new { error = "Invalid input" });

// GOOD — always ProblemDetails (ControllerBase helpers use ProblemDetailsFactory)
return Problem(title: "Invalid input", statusCode: StatusCodes.Status400BadRequest);
return ValidationProblem(ModelState);
```

### Don't Catch and Swallow Exceptions

```csharp
// BAD — silently swallowing
try { await ProcessOrder(order); }
catch (Exception) { /* ignore */ }

// GOOD — log and handle appropriately
try { await ProcessOrder(order); }
catch (PaymentException ex)
{
    logger.LogWarning(ex, "Payment failed for order {OrderId}", order.Id);
    return Result.Failure<Order>("Payment processing failed");
}
```

## Decision Guide

| Scenario                  | Recommendation                                  |
| ------------------------- | ----------------------------------------------- |
| Expected business failure | Result pattern                                  |
| Input validation          | FluentValidation with global action filter      |
| Mapping Result in actions | `ApiControllerBase.ToProblemDetails` / `ToActionResult` |
| Unexpected crash          | `IExceptionHandler` → ProblemDetails            |
| API error format          | RFC 9457 ProblemDetails — always                |
| Validation in handler     | Return Result.Failure, don't throw              |
| External service failure  | Catch specific exception, return Result.Failure |
| Logging errors            | Structured logging with correlation ID          |
