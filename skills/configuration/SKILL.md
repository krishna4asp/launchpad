---
name: configuration
description: >
  Configuration patterns for .NET 10 applications. Covers the Options pattern,
  IOptionsSnapshot vs IOptions, secrets management, and environment-based
  configuration, including AWS Systems Manager Parameter Store and Secrets Manager.
  Load this skill when setting up application configuration, managing secrets,
  binding configuration sections, or when the user mentions "configuration",
  "appsettings", "Options pattern", "IOptions", "IOptionsSnapshot", "secrets",
  "user secrets", "environment variables", "connection string", "config binding",
  "AWS Parameter Store", "AWS Secrets Manager", or "SSM".
---

# Configuration

## Core Principles

1. **Options pattern always** — Never read `IConfiguration` directly in services. Bind configuration sections to strongly-typed classes with validation.
2. **Validate on startup** — Use `ValidateDataAnnotations()` and `ValidateOnStart()` to catch misconfiguration before the first request.
3. **Secrets never in source** — Use user secrets in development, AWS Systems Manager Parameter Store / Secrets Manager or environment variables in production. Never commit secrets to git.
4. **Configuration layering** — `appsettings.json` → `appsettings.{Environment}.json` → environment variables → user secrets. Later sources override earlier ones.

## Patterns

### Options Pattern

```csharp
// Options class with validation attributes
public class DatabaseOptions
{
    public const string SectionName = "Database";

    [Required]
    public required string ConnectionString { get; init; }

    [Range(1, 100)]
    public int MaxRetryCount { get; init; } = 3;

    [Range(1, 60)]
    public int CommandTimeoutSeconds { get; init; } = 30;
}

// Registration with validation
builder.Services.AddOptions<DatabaseOptions>()
    .BindConfiguration(DatabaseOptions.SectionName)
    .ValidateDataAnnotations()
    .ValidateOnStart(); // Fails at startup if configuration is invalid
```

```json
// appsettings.json
{
  "Database": {
    "ConnectionString": "",
    "MaxRetryCount": 3,
    "CommandTimeoutSeconds": 30
  }
}
```

### Injecting Options

```csharp
// IOptions<T> — singleton, read once at startup, doesn't change
public class OrderService(IOptions<DatabaseOptions> options)
{
    private readonly DatabaseOptions _db = options.Value;
}

// IOptionsSnapshot<T> — scoped, re-reads per request (for reloadable config)
public class OrderService(IOptionsSnapshot<DatabaseOptions> options)
{
    private readonly DatabaseOptions _db = options.Value;
}

// IOptionsMonitor<T> — singleton, actively watches for changes
public class BackgroundWorker(IOptionsMonitor<WorkerOptions> options)
{
    public void DoWork()
    {
        var current = options.CurrentValue; // Always latest
    }
}
```

### Using Options in REST Controllers

```csharp
[ApiController]
[Route("api/[controller]")]
public class OrdersController(IOptionsSnapshot<OrderOptions> options) : ControllerBase
{
    [HttpGet("limits")]
    public ActionResult<OrderLimitsResponse> GetLimits()
    {
        var o = options.Value; // strongly typed, validated at startup
        return Ok(new OrderLimitsResponse(o.MaxItemsPerOrder, o.MaxOrderValue));
    }
}
```

Inject options into the controller (or the service it calls) — never `IConfiguration`. Keep controllers thin: most options belong in services, not controllers.

### Custom Validation (Complex Rules)

```csharp
builder.Services.AddOptions<JwtOptions>()
    .BindConfiguration("Jwt")
    .Validate(options =>
    {
        if (string.IsNullOrEmpty(options.Key) || options.Key.Length < 32)
            return false;
        if (options.ExpirationMinutes <= 0)
            return false;
        return true;
    }, "JWT key must be at least 32 characters and expiration must be positive")
    .ValidateOnStart();
```

### AWS Parameter Store and Secrets Manager (Production)

Package: `Amazon.Extensions.Configuration.SystemsManager`. Credentials come from the default AWS credential chain (IAM role on ECS/EC2/Lambda, a profile locally) — never put AWS access keys in configuration.

```csharp
// Program.cs — add Parameter Store as a configuration source
if (builder.Environment.IsProduction())
{
    // /myapp/Production/Database/ConnectionString  →  Database:ConnectionString
    builder.Configuration.AddSystemsManager(
        $"/myapp/{builder.Environment.EnvironmentName}/",
        reloadAfter: TimeSpan.FromMinutes(5)); // pairs with IOptionsSnapshot/IOptionsMonitor

    // Secrets Manager secrets via the Parameter Store reference path.
    // A JSON secret's keys become configuration keys (e.g. "Jwt:Key").
    builder.Configuration.AddSystemsManager(config =>
    {
        config.Path = "/aws/reference/secretsmanager/myapp-production";
        config.Optional = false;
    });
}
```

Store secrets as `SecureString` parameters or in Secrets Manager, and grant the app's IAM role only `ssm:GetParametersByPath` / `secretsmanager:GetSecretValue` on its own paths.

### Configuration for Multiple Environments

```csharp
// Named options — different config per named instance
builder.Services.AddOptions<SmtpOptions>("internal")
    .BindConfiguration("Smtp:Internal");
builder.Services.AddOptions<SmtpOptions>("customer")
    .BindConfiguration("Smtp:Customer");

// Usage
public class EmailService(IOptionsSnapshot<SmtpOptions> options)
{
    public async Task SendInternalEmail(string to, string body)
    {
        var smtp = options.Get("internal");
        // ...
    }
}
```

## Anti-patterns

### Don't Read IConfiguration Directly

```csharp
// BAD — stringly-typed, no validation, hard to test
public class OrderService(IConfiguration config)
{
    public void Process()
    {
        var timeout = int.Parse(config["Database:CommandTimeout"]!);
    }
}

// GOOD — strongly-typed options
public class OrderService(IOptions<DatabaseOptions> options)
{
    public void Process()
    {
        var timeout = options.Value.CommandTimeoutSeconds;
    }
}
```

### Don't Put Secrets in appsettings.json

```json
// BAD — committed to source control
{
  "Jwt": { "Key": "super-secret-key" },
  "Database": { "ConnectionString": "Server=prod;Password=secret" }
}

// GOOD — appsettings.json has defaults/structure only
{
  "Jwt": { "Key": "", "Issuer": "myapp", "Audience": "myapp" },
  "Database": { "ConnectionString": "" }
}
// Secrets provided via user-secrets (dev) or env vars / AWS Parameter Store / Secrets Manager (prod)
```

### Don't Skip Startup Validation

```csharp
// BAD — misconfiguration discovered at runtime
builder.Services.Configure<JwtOptions>(builder.Configuration.GetSection("Jwt"));

// GOOD — fail fast at startup
builder.Services.AddOptions<JwtOptions>()
    .BindConfiguration("Jwt")
    .ValidateDataAnnotations()
    .ValidateOnStart();
```

## Decision Guide

| Scenario                           | Recommendation                                     |
| ---------------------------------- | -------------------------------------------------- |
| Binding config to class            | Options pattern with `BindConfiguration`           |
| Simple, immutable config           | `IOptions<T>`                                      |
| Config that changes per request    | `IOptionsSnapshot<T>`                              |
| Background service watching config | `IOptionsMonitor<T>`                               |
| Development secrets                | `dotnet user-secrets`                              |
| Production secrets                 | AWS Secrets Manager / Parameter Store or env vars  |
| Options in API endpoints           | Inject `IOptionsSnapshot<T>` into the controller   |
| Validating config                  | `ValidateDataAnnotations()` + `ValidateOnStart()`  |
| Multiple configs of same type      | Named options with `IOptionsSnapshot<T>.Get(name)` |
