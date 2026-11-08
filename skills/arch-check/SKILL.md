---
name: arch-check
description: >
  Architecture conformance check: verifies an existing codebase against its
  declared architecture (VSA, Clean Architecture, DDD, Modular Monolith) —
  dependency direction, layer violations, module boundary leaks, and cycles —
  using targeted searches over project files and code. Invoke when: "check architecture",
  "architecture violations", "layer violations", "dependency direction",
  "module boundaries", "arch check", "is my architecture clean", "enforce
  architecture", "conformance check". For CHOOSING an architecture, use
  architecture-advisor instead.
---

# /arch-check

## What

Verifies that the code still matches the architecture it claims to have.
Architectures rot through small, individually-reasonable changes — a Domain
project that gains an EF Core reference, a module that reaches into a sibling's
internals, an endpoint defined outside the host. This workflow catches the rot
using project-graph and dependency analysis, not file-by-file reading.

Output: a violation report with severity, file:line evidence, and the concrete
fix — or a clean conformance pass.

## When

- "check my architecture", "are there layer violations", "dependency direction"
- Before a release or after a large feature lands
- After onboarding to an unfamiliar codebase that claims an architecture
- Recurring on teams where multiple people merge to shared modules
- NOT for choosing an architecture — that is `architecture-advisor`

## How

**Step 1: Establish the declared architecture**

In order of authority: the project's CLAUDE.md, an ADR in `docs/decisions/`,
or ask the user. Never infer silently — a wrong baseline produces a wrong
report. The four supported baselines and their rules:

| Architecture       | Rules checked                                                                                                                                |
| ------------------ | -------------------------------------------------------------------------------------------------------------------------------------------- |
| Vertical Slice     | Features don't reference sibling features; shared code only via explicitly shared folders/projects                                           |
| Clean Architecture | Domain → nothing; Application → Domain only; Infrastructure → Application; Api → Application (never Api → Infrastructure types, wiring only) |
| DDD + Clean        | Clean rules + aggregates referenced only via roots; domain events for cross-aggregate effects                                                |
| Modular Monolith   | No project references between modules except `*.Contracts`; cross-module calls via integration events or contracts                           |

**Step 2: Project-level dependency direction (cheapest, catches most)**

```
Grep "<ProjectReference" in **/*.csproj      -- or: dotnet list <project> reference
```

Map every project reference against the baseline's allowed arrows. A single
wrong reference here (Domain → Infrastructure) is a CRITICAL finding — it
makes every downstream violation possible.

**Step 3: Cycles**

```
Follow the ProjectReference edges from Step 2 and look for any path back to its start
```

Cycles are violations in every baseline. Report the full chain.

**Step 4: Namespace-level leaks (spot checks)**

Project references can be clean while code still leaks. Probe the risky edges:

```
Grep "^using (Microsoft.EntityFrameworkCore|System.Net.Http|.*Infrastructure)" in Domain/
   -- Domain types pulling in EF Core, HttpClient, or Infrastructure namespaces?
Grep <a module-internal type name> outside its module folder
   -- referenced from outside its module?
Grep for knowledge/common-antipatterns.md patterns
   -- known structural smells as supporting evidence
```

Pick probes by baseline: Clean → sample 3-5 Domain entities and Application
handlers; Modular Monolith → sample each module's internal types; VSA → sample
types inside two or three feature folders.

**Step 5: Presentation boundary**

```
Grep "\[Route|\[Http(Get|Post|Put|Patch|Delete)|\[Authorize|\[AllowAnonymous\]" in **/*Controller.cs
```

Endpoints must live only in the host/Api layer (Clean) or inside their owning
module (Modular Monolith, VSA feature folders). An endpoint defined in an
Application or shared project is a boundary violation. Unmarked auth on any
endpoint is reported as a side-finding (route to `/security-scan` for depth).

**Step 6: Report**

| Severity | Meaning                                                                           |
| -------- | --------------------------------------------------------------------------------- |
| CRITICAL | Wrong-direction project reference, module-to-module reference, cycle              |
| HIGH     | Namespace leak (Domain using Infrastructure/EF types), endpoint outside its layer |
| MEDIUM   | Shared-kernel logic creep, aggregate bypassed via direct member access            |
| INFO     | Unmarked endpoint auth, antipattern hits worth a look                             |

Each finding: evidence (file:line), why it violates the baseline, and the fix
(move the code, invert with an interface, introduce a contracts project, raise
an integration event). Offer to fix CRITICAL items immediately.

### Tools Used

- Grep `<ProjectReference` / `dotnet list reference` — reference-direction audit (the backbone)
- Walking the reference edges — cycle detection
- Grep for `using` directives and type names — namespace-level leak probes
- Grep routing and auth attributes in controllers — presentation boundary + auth posture
- Grep for known anti-patterns — supporting structural evidence

## Example

```
User: /arch-check

Claude: Baseline from CLAUDE.md: Clean Architecture (4 projects).

  Project references (*.csproj)...
  CRITICAL  Domain → Infrastructure reference (Domain.csproj:14)
            Breaks the dependency rule; makes Domain untestable in isolation.
            Fix: invert — define IEmailSender in Application, implement in
            Infrastructure.
  Cycles... none.
  Leak probes on 4 Domain entities...
  HIGH      Order.cs:8 uses Microsoft.EntityFrameworkCore (Domain must stay
            persistence-ignorant). Fix: move the [Index] config to
            OrderConfiguration in Infrastructure.
  Endpoint map... 23 endpoints, all in Api. 2 unmarked auth (side-finding —
  run /security-scan).

  Verdict: NOT conformant — 1 critical, 1 high. Fix the reference first;
  want me to do it now?
```

## Related

- `architecture-advisor` — choosing a baseline (before this skill is useful)
- `clean-architecture`, `vertical-slice`, `ddd`, `modular-monolith` template — the rules being enforced
- `/security-scan` — depth on the auth side-findings
- `/health-check` — broader report card; arch-check is its architecture dimension in depth
