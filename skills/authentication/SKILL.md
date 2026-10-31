---
name: authentication
description: >
  Authentication and authorization for ASP.NET Core. Covers JWT bearer tokens,
  OpenID Connect, ASP.NET Identity, authorization policies, role and claim-based
  authorization, and API key authentication.
  Load this skill when implementing login, protecting endpoints, designing
  authorization rules, or when the user mentions "auth", "JWT", "bearer token",
  "OIDC", "OpenID Connect", "Cognito", "Identity", "claims", "roles", "authorize",
  "[Authorize]", "AllowAnonymous", "RequireAuthorization", "API key", or "cookie auth".
---

# Authentication & Authorization

## Core Principles

1. **Use ASP.NET Identity for user management** — Don't build your own user store. Identity handles password hashing, lockout, two-factor, email confirmation, and (since .NET 10) built-in passkey/WebAuthn support for passwordless login.
2. **JWT for APIs, cookies for web apps** — APIs use Bearer token authentication; Blazor/MVC apps use cookie authentication.
3. **Policy-based authorization over roles** — Named policies (`[Authorize(Policy = "AdminOnly")]`) are testable, composable, and more expressive than `[Authorize(Roles = "Admin")]`.
4. **Never store secrets in code** — Use user secrets in development. In production use AWS Systems Manager Parameter Store (SecureString) or AWS Secrets Manager, loaded through the configuration system (see the `configuration` skill), or environment variables.
5. **REST API controllers** — All endpoint samples use attribute-routed controllers (`[ApiController]`, `ControllerBase`, `[Authorize]`, `[AllowAnonymous]`), not Minimal APIs. Put `[Authorize]` on the controller class so every action inherits it, then tighten or relax individual actions.

## Patterns

### JWT Bearer Authentication

```csharp
// Program.cs
// Jwt:Key is a secret: user secrets in development, Parameter Store SecureString
// (e.g. /OrdersApi/Production/Jwt/Key) in production. Issuer/Audience can live in appsettings.json.
builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidateAudience = true,
            ValidateLifetime = true,
            ValidateIssuerSigningKey = true,
            ValidIssuer = builder.Configuration["Jwt:Issuer"],
            ValidAudience = builder.Configuration["Jwt:Audience"],
            IssuerSigningKey = new SymmetricSecurityKey(
                Encoding.UTF8.GetBytes(builder.Configuration["Jwt:Key"]!)),
            ClockSkew = TimeSpan.Zero
        };
    });

builder.Services.AddAuthorization();
builder.Services.AddControllers();

var app = builder.Build();

// WebApplication adds authentication/authorization middleware automatically when
// the services are registered. Call them explicitly only if you need to control
// ordering (e.g. after UseCors or a custom tenant-resolution middleware).
app.UseAuthentication();
app.UseAuthorization();

app.MapControllers();
```

### Token Generation

Use `JsonWebTokenHandler` from `Microsoft.IdentityModel.JsonWebTokens` — it is the maintained, span-based handler that ASP.NET Core itself validates with. `JwtSecurityTokenHandler` (System.IdentityModel.Tokens.Jwt) is the legacy stack.

```csharp
public sealed class TokenService(IConfiguration config, TimeProvider clock)
{
    private static readonly JsonWebTokenHandler TokenHandler = new();

    public string GenerateToken(User user, IEnumerable<string> roles)
    {
        var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(config["Jwt:Key"]!));
        var now = clock.GetUtcNow();

        var descriptor = new SecurityTokenDescriptor
        {
            Issuer = config["Jwt:Issuer"],
            Audience = config["Jwt:Audience"],
            IssuedAt = now.UtcDateTime,
            Expires = now.AddHours(1).UtcDateTime,
            Claims = new Dictionary<string, object>
            {
                [JwtRegisteredClaimNames.Sub] = user.Id,
                [JwtRegisteredClaimNames.Email] = user.Email!,
                [JwtRegisteredClaimNames.Name] = user.UserName!,
                ["roles"] = roles.ToArray()
            },
            SigningCredentials = new SigningCredentials(key, SecurityAlgorithms.HmacSha256)
        };

        return TokenHandler.CreateToken(descriptor);
    }
}
```

Expose it through a login action on a controller:

```csharp
public sealed record LoginRequest(string Email, string Password);
public sealed record TokenResponse(string AccessToken);

[ApiController]
[Route("api/auth")]
public sealed class AuthController(UserManager<User> users, TokenService tokens) : ControllerBase
{
    [HttpPost("login")]
    [AllowAnonymous]
    [ProducesResponseType<TokenResponse>(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    public async Task<ActionResult<TokenResponse>> Login(LoginRequest request)
    {
        var user = await users.FindByEmailAsync(request.Email);
        if (user is null || !await users.CheckPasswordAsync(user, request.Password))
        {
            return Unauthorized();
        }

        var roles = await users.GetRolesAsync(user);
        return Ok(new TokenResponse(tokens.GenerateToken(user, roles)));
    }
}

// Program.cs
builder.Services.AddSingleton(TimeProvider.System);
builder.Services.AddScoped<TokenService>();
```

### Policy-Based Authorization

```csharp
// Define policies
builder.Services.AddAuthorizationBuilder()
    .AddPolicy("AdminOnly", policy => policy.RequireRole("Admin"))
    .AddPolicy("CanManageOrders", policy => policy
        .RequireAuthenticatedUser()
        .RequireClaim("permission", "orders:write"))
    .AddPolicy("MinimumAge", policy => policy
        .AddRequirements(new MinimumAgeRequirement(18)));

// Custom requirement + handler
public class MinimumAgeRequirement(int minimumAge) : IAuthorizationRequirement
{
    public int MinimumAge => minimumAge;
}

public class MinimumAgeHandler(TimeProvider clock) : AuthorizationHandler<MinimumAgeRequirement>
{
    protected override Task HandleRequirementAsync(
        AuthorizationHandlerContext context,
        MinimumAgeRequirement requirement)
    {
        var dateOfBirthClaim = context.User.FindFirst("date_of_birth");
        if (dateOfBirthClaim is not null &&
            DateOnly.TryParse(dateOfBirthClaim.Value, out var dob) &&
            dob.AddYears(requirement.MinimumAge) <= DateOnly.FromDateTime(clock.GetUtcNow().DateTime))
        {
            context.Succeed(requirement);
        }
        return Task.CompletedTask;
    }
}
```

### Protecting Endpoints

```csharp
// Protect an entire controller; every action inherits the policy
[ApiController]
[Route("api/admin")]
[Authorize(Policy = "AdminOnly")]
public sealed class AdminController : ControllerBase
{
    // Actions omitted
}

// Require an authenticated user for the controller, then tighten individual actions
[ApiController]
[Route("api/orders")]
[Authorize]
public sealed class OrdersController(IOrderService orders) : ControllerBase
{
    [HttpGet]
    public async Task<ActionResult<IReadOnlyList<OrderDto>>> GetOrders(CancellationToken ct)
        => Ok(await orders.GetAllAsync(ct));

    // Attributes stack: authenticated (class) AND CanManageOrders (action)
    [HttpPost]
    [Authorize(Policy = "CanManageOrders")]
    public async Task<ActionResult<OrderDto>> CreateOrder(CreateOrderRequest request, CancellationToken ct)
    {
        var order = await orders.CreateAsync(request, ct);
        return CreatedAtAction(nameof(GetOrders), new { id = order.Id }, order);
    }

    // Opt out of the controller's requirement
    [HttpGet("public-info")]
    [AllowAnonymous]
    public ActionResult<PublicInfoDto> GetPublicInfo() => Ok(orders.GetPublicInfo());
}
```

To require authentication everywhere by default, set a fallback policy and opt out with `[AllowAnonymous]`:

```csharp
builder.Services.AddAuthorizationBuilder()
    .SetFallbackPolicy(new AuthorizationPolicyBuilder()
        .RequireAuthenticatedUser()
        .Build());
```

### OpenID Connect (External Identity Provider)

Amazon Cognito user pools are a standard OIDC provider, so the generic handler works unchanged.

```csharp
builder.Services.AddAuthentication(options =>
{
    options.DefaultScheme = CookieAuthenticationDefaults.AuthenticationScheme;
    options.DefaultChallengeScheme = OpenIdConnectDefaults.AuthenticationScheme;
})
.AddCookie()
.AddOpenIdConnect(options =>
{
    // Cognito: https://cognito-idp.{region}.amazonaws.com/{userPoolId}
    options.Authority = builder.Configuration["Oidc:Authority"];
    options.ClientId = builder.Configuration["Oidc:ClientId"];
    // Secret: user secrets in development, Parameter Store / Secrets Manager in production
    options.ClientSecret = builder.Configuration["Oidc:ClientSecret"];
    options.ResponseType = "code";
    options.SaveTokens = true;
    options.Scope.Add("openid");
    options.Scope.Add("profile");
    options.Scope.Add("email");
});
```

### Accessing Current User

```csharp
// Controllers expose the current user through ControllerBase.User (HttpContext.User)
[ApiController]
[Route("api/me")]
[Authorize]
public sealed class MeController : ControllerBase
{
    [HttpGet]
    public IActionResult Get()
    {
        var userId = User.FindFirstValue(ClaimTypes.NameIdentifier);
        var email = User.FindFirstValue(ClaimTypes.Email);
        return Ok(new { userId, email });
    }
}
```

## Anti-patterns

### Don't Use Role Strings Everywhere

```csharp
// BAD — magic role strings duplicated across controllers; hard to refactor, not testable
[Authorize(Roles = "Admin,SuperAdmin,Manager")]
public sealed class ReportsController : ControllerBase { }

// GOOD — one named policy, referenced by name
builder.Services.AddAuthorizationBuilder()
    .AddPolicy("AdminAccess", p => p.RequireRole("Admin", "SuperAdmin", "Manager"));

[ApiController]
[Route("api/reports")]
[Authorize(Policy = "AdminAccess")]
public sealed class ReportsController : ControllerBase { }
```

### Don't Store Secrets in appsettings.json

```json
// BAD — committed to source control
{
  "Jwt": {
    "Key": "super-secret-key-12345"
  }
}
```

```bash
# GOOD — development: user secrets (stored outside the repo)
dotnet user-secrets set "Jwt:Key" "<at-least-32-random-characters>"

# GOOD — production: Parameter Store SecureString, read at startup via AddSystemsManager
# (path /{ApplicationName}/{EnvironmentName}/ maps Jwt/Key → Jwt:Key)
aws ssm put-parameter --name "/OrdersApi/Production/Jwt/Key" \
  --type SecureString --value "<at-least-32-random-characters>"
```

### Don't Skip Token Validation

```csharp
// BAD — disabling validation
options.TokenValidationParameters = new TokenValidationParameters
{
    ValidateIssuer = false,      // DON'T
    ValidateAudience = false,    // DON'T
    ValidateLifetime = false,    // DEFINITELY DON'T
};

// GOOD — validate everything (see JWT Bearer Authentication pattern above for full setup)
```

## Decision Guide

| Scenario                   | Recommendation                                               |
| -------------------------- | ------------------------------------------------------------ |
| REST API (controllers)     | JWT Bearer authentication                                    |
| Blazor Server / MVC        | Cookie authentication                                        |
| External identity provider | OpenID Connect (e.g. Amazon Cognito user pool)               |
| User registration / login  | ASP.NET Identity                                             |
| Passwordless login         | ASP.NET Identity passkeys (WebAuthn, built-in since .NET 10) |
| Permission checking        | Policy-based authorization                                   |
| Multi-tenant API           | Claims-based with tenant claim                               |
| API-to-API communication   | Client credentials (OAuth 2.0), e.g. Cognito app client      |
| Storing signing keys/secrets | Parameter Store SecureString or Secrets Manager            |
| Simple API keys            | Custom `AuthenticationHandler<T>`                            |
