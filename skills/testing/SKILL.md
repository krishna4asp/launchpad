---
name: testing
description: >
  Testing strategy for .NET 10 applications. Covers xUnit v3, WebApplicationFactory
  for integration tests, SQLite in-memory for database testing, Verify for
  snapshot testing, and the AAA pattern.
  Load this skill when writing tests, setting up test infrastructure, reviewing
  test coverage, or when the user mentions "test", "xUnit", "WebApplicationFactory",
  "SQLite in-memory", "integration test", "unit test", "bUnit", "snapshot test",
  "Verify", "test coverage", "AAA pattern", "WireMock", or "FakeTimeProvider".
---

# Testing (.NET 10)

## Core Principles

1. **Integration tests are the highest-value tests** — A single `WebApplicationFactory` test covers routing, binding, validation, business logic, and persistence in one shot. Start here before writing unit tests.
2. **A relational database in tests** — Use SQLite in-memory (`Microsoft.EntityFrameworkCore.Sqlite` with `DataSource=:memory:`). It enforces constraints, transactions and foreign keys, and needs no external server. Never use the EF Core InMemory provider — it is not relational and hides real bugs.
3. **AAA pattern is mandatory** — Every test has three clearly separated sections: Arrange, Act, Assert. No mixing.
4. **Test behavior, not implementation** — Tests should survive refactoring. Test what the system does, not how it does it.

## Patterns

### xUnit v3 Basics

```csharp
public class OrderServiceTests
{
    [Fact]
    public async Task CreateOrder_WithValidItems_ReturnsSuccessResult()
    {
        // Arrange
        var db = CreateInMemoryDb();
        var clock = new FakeTimeProvider(new DateTimeOffset(2025, 1, 15, 0, 0, 0, TimeSpan.Zero));
        var service = new OrderService(db, clock);
        var request = new CreateOrderRequest("customer-1", [new("product-1", 2)]);

        // Act
        var result = await service.CreateAsync(request);

        // Assert
        Assert.True(result.IsSuccess);
        Assert.NotEqual(Guid.Empty, result.Value.Id);
        Assert.Equal(clock.GetUtcNow(), result.Value.CreatedAt);
    }

    [Theory]
    [InlineData("")]
    [InlineData(null)]
    public async Task CreateOrder_WithInvalidCustomerId_ReturnsFailure(string? customerId)
    {
        // Arrange
        var service = CreateService();

        // Act
        var result = await service.CreateAsync(new CreateOrderRequest(customerId!, []));

        // Assert
        Assert.False(result.IsSuccess);
    }
}
```

### Integration Tests with WebApplicationFactory

The highest-value test pattern. Tests the full HTTP pipeline.

```csharp
// Fixtures/ApiFixture.cs
public class ApiFixture : WebApplicationFactory<Program>, IAsyncLifetime
{
    // The in-memory database lives only while this connection stays open
    private readonly SqliteConnection _connection = new("DataSource=:memory:");

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.ConfigureServices(services =>
        {
            // Remove the app's provider registration (EF Core 9+ also registers
            // IDbContextOptionsConfiguration<T>, so remove both)
            services.RemoveAll<DbContextOptions<AppDbContext>>();
            services.RemoveAll<IDbContextOptionsConfiguration<AppDbContext>>();
            services.AddDbContext<AppDbContext>(options => options.UseSqlite(_connection));
        });
    }

    // xUnit v3: IAsyncLifetime.InitializeAsync returns ValueTask (v2 used Task)
    public async ValueTask InitializeAsync()
    {
        await _connection.OpenAsync();

        // Migrations are generated for the production provider, so build the
        // schema from the model instead
        using var scope = Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        await db.Database.EnsureCreatedAsync();
    }

    // xUnit v3: IAsyncLifetime inherits IAsyncDisposable — override the
    // ValueTask DisposeAsync that WebApplicationFactory already provides
    public override async ValueTask DisposeAsync()
    {
        await _connection.DisposeAsync();
        await base.DisposeAsync();
    }
}
```

```csharp
// Tests/Orders/CreateOrderTests.cs
public class CreateOrderTests(ApiFixture fixture) : IClassFixture<ApiFixture>
{
    private readonly HttpClient _client = fixture.CreateClient();

    [Fact]
    public async Task CreateOrder_ReturnsCreated_WithValidRequest()
    {
        // Arrange
        var request = new CreateOrderRequest("customer-1", [new("product-1", 2)]);

        // Act
        var response = await _client.PostAsJsonAsync("/api/orders", request);

        // Assert
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);

        var order = await response.Content.ReadFromJsonAsync<OrderResponse>();
        Assert.NotNull(order);
        Assert.NotEqual(Guid.Empty, order.Id);
        Assert.Contains("/api/orders/", response.Headers.Location?.ToString());
    }

    [Fact]
    public async Task CreateOrder_ReturnsValidationProblem_WithEmptyItems()
    {
        // Arrange
        var request = new CreateOrderRequest("customer-1", []);

        // Act
        var response = await _client.PostAsJsonAsync("/api/orders", request);

        // Assert
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }
}
```

### SQLite In-Memory for Database Testing

Package: `Microsoft.EntityFrameworkCore.Sqlite`. Each open connection to `DataSource=:memory:` is its own empty database, and it disappears when the connection closes.

```csharp
// Unit / handler tests — a fresh database per test
public sealed class SqliteDb : IAsyncDisposable
{
    private readonly SqliteConnection _connection = new("DataSource=:memory:");

    public AppDbContext Context { get; private set; } = null!;

    public static async Task<SqliteDb> CreateAsync()
    {
        var db = new SqliteDb();
        await db._connection.OpenAsync();
        db.Context = new AppDbContext(new DbContextOptionsBuilder<AppDbContext>()
            .UseSqlite(db._connection)
            .Options);
        await db.Context.Database.EnsureCreatedAsync();
        return db;
    }

    public async ValueTask DisposeAsync()
    {
        await Context.DisposeAsync();
        await _connection.DisposeAsync();
    }
}
```

SQLite is not your production database. Know the gaps:

- No schemas, sequences, or provider-specific column types (`jsonb`, `rowversion`). Keep those mappings out of tests or configure them conditionally.
- `DateTimeOffset` and `decimal` can't be ordered or compared in SQL. Add a value converter in tests, or keep those queries client-side.
- Raw SQL written for PostgreSQL/SQL Server won't run.
- Use `EnsureCreatedAsync()`, not `MigrateAsync()`: migrations target the production provider.

### Verify Snapshot Testing

Use Verify for complex response objects where manual assertions would be fragile.

```csharp
[Fact]
public async Task GetOrder_MatchesSnapshot()
{
    // Arrange
    await SeedOrder(fixture);

    // Act
    var response = await _client.GetAsync("/api/orders/known-id");
    var content = await response.Content.ReadAsStringAsync();

    // Assert — compares against a stored .verified.txt file
    await Verify(content);
}
```

On first run, Verify creates a `.verified.txt` file. On subsequent runs, it compares output. If the output changes, the test fails and shows a diff.

### Test Data Builders

```csharp
public class OrderBuilder
{
    private string _customerId = "default-customer";
    private List<OrderItem> _items = [new("product-1", 1, 9.99m)];
    private OrderStatus _status = OrderStatus.Pending;

    public OrderBuilder WithCustomer(string customerId)
    {
        _customerId = customerId;
        return this;
    }

    public OrderBuilder WithItems(params OrderItem[] items)
    {
        _items = [..items];
        return this;
    }

    public OrderBuilder WithStatus(OrderStatus status)
    {
        _status = status;
        return this;
    }

    public Order Build() => Order.Create(_customerId, _items, _status);
}

// Usage in tests
var order = new OrderBuilder()
    .WithCustomer("vip-customer")
    .WithStatus(OrderStatus.Confirmed)
    .Build();
```

### Testing Time-Dependent Code

Use `TimeProvider` (built into .NET 8+) and `FakeTimeProvider` from `Microsoft.Extensions.TimeProvider.Testing`.

```csharp
[Fact]
public async Task ExpireOrders_MarksOldPendingOrdersAsExpired()
{
    // Arrange
    var clock = new FakeTimeProvider(new DateTimeOffset(2025, 6, 1, 0, 0, 0, TimeSpan.Zero));
    var db = CreateDb();
    var order = Order.Create("customer-1", items, clock.GetUtcNow());
    db.Orders.Add(order);
    await db.SaveChangesAsync();

    // Advance time past expiry threshold
    clock.Advance(TimeSpan.FromDays(31));

    var handler = new ExpireOrders.Handler(db, clock);

    // Act
    await handler.Handle(new ExpireOrders.Command(), CancellationToken.None);

    // Assert
    var updated = await db.Orders.FindAsync(order.Id);
    Assert.Equal(OrderStatus.Expired, updated!.Status);
}
```

### Test Naming Convention

Use the pattern: `MethodName_StateUnderTest_ExpectedBehavior`

```csharp
[Fact] public async Task CreateOrder_WithValidItems_ReturnsSuccessResult() { }
[Fact] public async Task CreateOrder_WithEmptyItems_ReturnsValidationError() { }
[Fact] public async Task GetOrder_WithNonExistentId_ReturnsNotFound() { }
[Fact] public async Task CancelOrder_WhenAlreadyShipped_ReturnsConflict() { }
```

## Anti-patterns

### Don't Use the EF Core InMemory Provider

```csharp
// BAD — EF Core InMemory provider: not relational, no constraints or transactions
services.AddDbContext<AppDbContext>(options =>
    options.UseInMemoryDatabase("TestDb"));

// GOOD — SQLite in-memory: relational, enforces constraints and foreign keys
services.AddDbContext<AppDbContext>(options =>
    options.UseSqlite(openConnection)); // "DataSource=:memory:", kept open
```

### Don't Test Implementation Details

```csharp
// BAD — testing that a specific repository method was called
mock.Verify(x => x.AddAsync(It.IsAny<Order>()), Times.Once);
mock.Verify(x => x.SaveChangesAsync(), Times.Once);

// GOOD — test the observable outcome
var order = await db.Orders.FindAsync(orderId);
Assert.NotNull(order);
Assert.Equal(OrderStatus.Created, order.Status);
```

### Don't Share Mutable State Between Tests

```csharp
// BAD — static shared state
private static readonly AppDbContext SharedDb = CreateDb();

// GOOD — fresh state per test (or use IAsyncLifetime for shared fixtures)
private AppDbContext CreateDb() => new(new DbContextOptionsBuilder<AppDbContext>()...);
```

### Don't Write Assertion-Free Tests

```csharp
// BAD — no assertion, only checks it doesn't throw
[Fact]
public async Task CreateOrder_Works()
{
    await service.CreateAsync(request);
    // "it didn't throw, so it works!" — NO
}

// GOOD — assert the expected outcome
[Fact]
public async Task CreateOrder_PersistsOrderToDatabase()
{
    var result = await service.CreateAsync(request);

    var persisted = await db.Orders.FindAsync(result.Value.Id);
    Assert.NotNull(persisted);
    Assert.Equal(request.CustomerId, persisted.CustomerId);
}
```

## Decision Guide

| Scenario                            | Recommendation                                   |
| ----------------------------------- | ------------------------------------------------ |
| Testing an API endpoint             | `WebApplicationFactory` integration test         |
| Testing business logic in isolation | Unit test with fakes/stubs                       |
| Database-dependent tests            | SQLite in-memory (`DataSource=:memory:`)         |
| Complex response validation         | Verify snapshot testing                          |
| Time-dependent logic                | `FakeTimeProvider`                               |
| External API dependency             | `WireMock.Net` or `HttpMessageHandler` stub      |
| Parameterized test cases            | `[Theory]` with `[InlineData]` or `[MemberData]` |
| Test data setup                     | Builder pattern                                  |
| Shared expensive fixture            | `IClassFixture<T>` with `IAsyncLifetime`         |
