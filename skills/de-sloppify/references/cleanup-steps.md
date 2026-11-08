# De-Sloppify — Per-Step Reference

Loaded by `/de-sloppify` Step execution. Details, safety checks, and code
examples for each of the 7 pipeline steps.

## Step 1: Format All Code

```bash
dotnet format
```

Why first: formatting touches many files. Getting it out of the way prevents
merge conflicts with subsequent steps.

Verify: `dotnet format --verify-no-changes` reports no changes.
Commit: `chore: apply dotnet format`

## Step 2: Remove Unused Usings

```bash
dotnet format analyzers --diagnostics IDE0005
```

Why second: unused usings are noise; removing them makes subsequent analysis
cleaner and reduces false positives in review.

Verify: `dotnet build`; run `dotnet test` if removal was extensive.
Commit: `chore: remove unused using statements`

## Step 3: Fix Analyzer Warnings

```
dotnet build --no-restore   # collect warnings for the whole solution
```

Triage by category, compiler warnings first:

- **Nullability (CS8600-CS8604)** — add null checks, or the null-forgiving
  operator with a comment explaining why null is impossible
- **Unused variables (CS0219)** — remove
- **Obsolete API (CS0618)** — migrate to the recommended replacement
- **IDE suggestions (IDE0xxx)** — apply if they improve readability

Verify: `dotnet build` with zero new warnings; `dotnet test` passes.
Commit: `chore: fix analyzer warnings`

## Step 4: Remove Dead Code

```
dotnet build --no-restore   # IDE0051/IDE0052 flag unused private members
Grep: each public type/member name across *.cs — zero hits outside its declaration = candidate
```

**Safety check before every removal** — a reference search cannot see string-based usage:

```
1. Grep "DeadType" across *.cs — confirm zero compile-time refs
2. Grep for string-based usage:
   - nameof(DeadType) in attributes or logging
   - Reflection: Type.GetType("DeadType"), Activator.CreateInstance
   - DI registration: services.AddScoped(typeof(IHandler<>), typeof(DeadType))
   - Serialization: [JsonDerivedType(typeof(DeadType))]
3. Check if it's a public API consumed by external packages
4. Check configuration files (appsettings.json, etc.)

ONLY remove if all checks come back clean.
```

Verify: `dotnet build` and `dotnet test` pass.
Commit: `chore: remove dead code`

## Step 5: Resolve TODOs

```bash
grep -rn "TODO\|HACK\|FIXME\|XXX" --include="*.cs"
```

For each: **fix now** (small, self-contained), **create an issue** and tag it
(`// TODO(#142): Implement retry logic`), or **remove** (stale — the work was
done or is no longer relevant).

Verify: `dotnet build` and `dotnet test` pass.
Commit: `chore: resolve TODO comments`

## Step 6: Seal Non-Inherited Classes

```
Grep: "(public|internal) class " (not sealed/static/abstract) in *.cs — candidate list
Grep: ": EachClass\b" in *.cs — check for derived types
```

Seal every class that has no derived types, is not a base class by design (no
`virtual`/`abstract` members), is not an open generic in DI registration, and
is not a test fixture base class.

Why: sealed classes enable devirtualization, communicate design intent, and
prevent accidental inheritance.

```csharp
// BEFORE
public class OrderValidator : AbstractValidator<CreateOrderCommand> { ... }

// AFTER — sealed, because nothing inherits from it
public sealed class OrderValidator : AbstractValidator<CreateOrderCommand> { ... }
```

Before sealing, also grep test projects for inheritance — a class tests derive
from must stay open:

```
Grep: ": OrderService\b" in production code → no derived types
Grep: "OrderService" in test projects → inheritance found? Skip sealing.
```

Verify: `dotnet build` and `dotnet test` pass.
Commit: `chore: seal non-inherited classes`

## Step 7: Propagate CancellationToken

```
Grep: "async Task" methods whose parameter list lacks CancellationToken
```

Trace async chains from entry points (endpoints, handlers) through services to
data access. Common propagation points:

- Controller actions: add `CancellationToken ct` parameter (bound to `HttpContext.RequestAborted`)
- Mediator handlers: already provided in `Handle(TRequest, CancellationToken)`
- EF Core: `SaveChangesAsync(ct)`, `ToListAsync(ct)`, `FindAsync([key], ct)`
- HttpClient: `GetAsync(url, ct)`, `PostAsync(url, content, ct)`

```csharp
// BEFORE — token stops at the controller action
[HttpGet("{id:guid}")]
public async Task<ActionResult<Order>> Get(Guid id)
{
    var order = await db.Orders.FindAsync(id);
    return order is not null ? Ok(order) : NotFound();
}

// AFTER — token propagated to EF Core
[HttpGet("{id:guid}")]
public async Task<ActionResult<Order>> Get(Guid id, CancellationToken ct)
{
    var order = await db.Orders.FindAsync([id], ct);
    return order is not null ? Ok(order) : NotFound();
}
```

Verify: `dotnet build` and `dotnet test` pass.
Commit: `chore: propagate CancellationToken through async chains`
