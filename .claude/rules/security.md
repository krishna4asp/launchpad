---
alwaysApply: true
description: >
  Enforces security best practices for .NET applications including secrets
  management, input validation, auth patterns, and OWASP compliance.
---

# Security Rules

## Secrets Management

- **Never hardcode secrets in source code.** Use `dotnet user-secrets` for local development, AWS Systems Manager Parameter Store (`SecureString`), AWS Secrets Manager, or environment variables for deployed environments. Hardcoded secrets end up in git history and are nearly impossible to fully remove.

```csharp
// DO — Parameter Store / Secrets Manager as configuration sources
// (package: Amazon.Extensions.Configuration.SystemsManager)
builder.Configuration.AddSystemsManager($"/myapp/{builder.Environment.EnvironmentName}/");
builder.Configuration.AddSystemsManager("/aws/reference/secretsmanager/myapp-production");
var conn = builder.Configuration.GetConnectionString("Default");

// DON'T
var conn = "Server=prod;Password=hunter2";
```

- **Never put AWS access keys in configuration or code.** Use the default AWS credential chain: an IAM role on ECS/EC2/Lambda, a named profile locally. Grant the app's role least-privilege access to its own parameter and secret paths only.
- **Never commit `.env` files, `appsettings.Development.json` with real credentials, `credentials.json`, or `~/.aws/credentials`.** Add them to `.gitignore`.

## Input Validation

- **Validate all external input at system boundaries.** API endpoints, message handlers, and file uploads are trust boundaries. Use FluentValidation or the built-in validation attributes before data reaches domain logic.
- **Use parameterized queries — never string concatenation for SQL.** EF Core parameterizes by default, but raw SQL, Dapper, and ADO.NET require explicit parameterization.

```csharp
// DO
db.Database.SqlQuery<Order>($"SELECT * FROM Orders WHERE Id = {id}");
// EF Core interpolation is parameterized — the above is safe

// DON'T
db.Database.ExecuteSqlRaw("SELECT * FROM Orders WHERE Id = '" + id + "'");
```

## Authentication and Authorization

- **Always add `[Authorize]` or `[AllowAnonymous]` explicitly on every controller.** Put `[Authorize]` on the controller class; opt individual actions out with `[AllowAnonymous]`. Ambiguous auth is a security hole. Never rely on a global default without also making intent explicit on the controller.

```csharp
// DO
[Route("api/admin")]
[Authorize(Policy = "AdminOnly")]
public sealed class AdminController : ApiControllerBase { }

[Route("api/catalog")]
[Authorize]
public sealed class CatalogController : ApiControllerBase
{
    [HttpGet]
    [AllowAnonymous] // explicit opt-out for a public action
    public ActionResult<IReadOnlyList<ProductResponse>> List() => Ok(Array.Empty<ProductResponse>());
}

// DON'T — unmarked controller inherits whatever the global default is
[Route("api/orders")]
public sealed class OrdersController : ApiControllerBase { }
```

## Transport and Data Protection

- **Use HTTPS everywhere.** Enforce via HSTS in production (`app.UseHsts()` + `app.UseHttpsRedirection()`). Redirect HTTP to HTTPS. No exceptions.

- **Use Data Protection API for encrypting user data at rest.** Never roll your own encryption. The Data Protection API handles key rotation and algorithm selection correctly.
- **CORS: explicit origins only, never wildcard in production.** `AllowAnyOrigin()` in production exposes your API to every domain on the internet.

```csharp
// DO
builder.Services.AddCors(o => o.AddPolicy("Web", p =>
    p.WithOrigins("https://app.example.com")
     .AllowAnyMethod()
     .AllowAnyHeader()));

// DON'T
builder.Services.AddCors(o => o.AddDefaultPolicy(p => p.AllowAnyOrigin()));
```

## Logging

- **Do not log PII at Information level or below.** Emails, names, IP addresses, and tokens must stay at `Debug` level at most, and only in development. Production log aggregators are often broadly accessible, making PII in logs a compliance liability.
