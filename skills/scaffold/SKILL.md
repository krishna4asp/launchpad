---
name: scaffold
description: >
  Architecture-aware feature scaffolding for .NET 10 projects. Detects the
  project's architecture (VSA, Clean Architecture, DDD, Modular Monolith) and
  generates complete feature slices with all required layers: resource
  controller, handler, validator, DTOs, EF configuration, and integration tests — with
  the completeness checklist and per-architecture code templates every
  generated feature must satisfy.
  Use when: "scaffold", "create feature", "add feature", "new endpoint",
  "generate", "add entity", "scaffold a module", "add module", or when
  customizing generation templates or defining what a complete feature slice
  includes.
---

# /scaffold — Architecture-Aware Feature Scaffolding

## What

Generates a complete feature with all required files based on the project's
architecture. Never generates half a feature — every scaffold includes the
`[ApiController]` resource controller, handler, validation, DTOs, EF
configuration, and at least one integration test as a single unit, written in
modern C# 14 (primary constructors, collection expressions, records, sealed
handlers, `ActionResult<T>`).

Supported architectures (file placement maps and code shape templates live in
`references/architecture-patterns.md`):

- **Vertical Slice Architecture (VSA)** — single-file features in `Features/`
- **Clean Architecture (CA)** — files split across Domain, Application, Infrastructure, Api
- **DDD + Clean Architecture** — aggregate roots, value objects, domain events, plus CA layers
- **Modular Monolith** — self-contained modules with their own DbContext and integration events

## When

- "Scaffold a [feature name]", "create an endpoint for", "add a feature"
- "Generate CRUD for", "add entity", "new module", "scaffold a module"
- Starting a new feature after `/plan` has produced an approved plan
- Customizing generation templates or defining what a complete slice includes
- Any time the user wants a complete, working feature skeleton

## How

### Step 1: Detect Architecture

Use the `architecture-advisor` skill to determine the project's architecture:

- Examine folder structure, project references, and existing patterns
- If architecture is ambiguous, ask the user rather than guessing
- Load the matching architecture skill (vertical-slice, clean-architecture, ddd)

### Step 2: Clarify Scope

Confirm with the user before generating (skip anything the plan already answers):

1. Feature/entity name and operations needed — full CRUD or a subset?
2. Key fields and invariants for any new entity
3. Module placement (Modular Monolith only) — existing module or new one?

### Step 3: Learn Conventions

Use the `convention-learner` skill and code search to check:

- Naming patterns (`*Handler`, `*Service`, `*Controller`, `*Command`, `*Query`)
- Folder structure, file organization, access modifiers, sealed conventions
- Existing validation approach (FluentValidation, data annotations, manual)
- Test project structure and naming (`*Tests`, `*IntegrationTests`)

Match what exists. Do not impose new conventions on an established codebase.

### Step 4: Generate All Layers

Generate every file the architecture requires, following the templates in
`references/architecture-patterns.md`:

- **VSA** — read the VSA section: single-file operation + resource controller + EF config + tests
- **Clean Architecture** — read the CA section: Mediator command/handler in Application, controller in Api
- **DDD** — read the DDD section: aggregate with invariants and domain events, thin handler
- **Modular Monolith** — read the Modular Monolith section: module DbContext, DI registration, integration events

The reference also covers the shared shapes every architecture reuses
(resource controller, validator, entity + `IEntityTypeConfiguration<T>` pair,
test fixture) and the anti-patterns to avoid.

### Step 5: Completeness Checklist (MANDATORY)

Every scaffolded feature MUST include ALL nine items. Do not skip any:

- [ ] **Controller** — `[ApiController]` resource controller deriving from `ApiControllerBase`, attribute-routed, `[Authorize]` on the class, discovered by `MapControllers()`; no routes in Program.cs
- [ ] **Handler** — `public sealed` (injected into a public controller), primary constructor, one per operation
- [ ] **Validator** — FluentValidation rules with meaning (ranges, required, max lengths), run by the global `FluentValidationFilter` (`AddControllers(o => o.Filters.Add<FluentValidationFilter>())`, error-handling skill)
- [ ] **DTOs** — records shaped for the consumer, never 1:1 entity mirrors
- [ ] **EF configuration** — `IEntityTypeConfiguration<T>`; no data annotations on entities
- [ ] **Integration tests** — `WebApplicationFactory` + SQLite in-memory, DI replacement via `services.RemoveAll<DbContextOptions<T>>()` and `RemoveAll<IDbContextOptionsConfiguration<T>>()`
- [ ] **OpenAPI metadata** — `[HttpPost(Name = ...)]`, `[EndpointSummary]`, `[ProducesResponseType<T>]`, `ValidationProblemDetails` for 400, `ProblemDetails` for 404
- [ ] **CancellationToken** — on every async method and passed to every async call
- [ ] **Result pattern** — handlers return `Result<T>`; controller actions map success → `Ok`/`CreatedAtRoute`, failure → `ToProblemDetails(result)`

Also verify supporting infrastructure — scaffold it if missing: list endpoints
get bounded pagination (`page`/`pageSize`, max 50), Program.cs has
`app.UseExceptionHandler()`, and appsettings.json has a connection string.

### Step 6: Verify

Prove the scaffold works before reporting done:

```bash
dotnet build --no-restore
dotnet test --no-build --filter "FullyQualifiedName~{FeatureName}"
```

If the build or tests fail, fix and re-run before presenting results.

## Example

```
User: /scaffold a Product Catalog feature with CRUD operations

Claude: Detected architecture: Vertical Slice Architecture

Created files:
  src/Features/Products/CreateProduct.cs     -- Command + handler + validator
  src/Features/Products/GetProduct.cs        -- Query by ID + handler
  src/Features/Products/ListProducts.cs      -- Paginated list + handler
  src/Features/Products/UpdateProduct.cs     -- Command + handler + validator
  src/Features/Products/DeleteProduct.cs     -- Command + handler
  src/Features/Products/ProductsController.cs -- [ApiController] resource controller, OpenAPI metadata
  src/Features/Products/ProductConfig.cs     -- EF Core configuration
  tests/Features/Products/CreateProductTests.cs
  tests/Features/Products/GetProductTests.cs
  tests/Features/Products/ListProductsTests.cs

Checklist: 9/9 | Build: PASS | Tests: PASS

All files follow your existing conventions (sealed handlers,
primary constructors, ActionResult<T> return types).
```

## Related

- `dotnet-init` — Initialize the project and CLAUDE.md before scaffolding features
- `controller-based-apis` — Controller, routing and OpenAPI conventions every scaffold follows
- `vertical-slice` — The VSA patterns the VSA scaffold follows
- `clean-architecture` — Layering rules behind the CA scaffold
- `ddd` — Aggregate and domain-event patterns behind the DDD scaffold
- `project-structure` — Where files belong in each architecture
