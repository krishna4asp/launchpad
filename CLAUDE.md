# launchpad — Development Instructions

> These instructions are for developing THIS repository. For files users drop into their own projects, see `templates/`.

## Repository Purpose

launchpad is a Claude Code plugin for .NET developers. It ships skills, agents, rules, templates, knowledge documents and hooks that make Claude Code write modern .NET 10 / C# 14 code: controller-based REST APIs, EF Core used directly, the Result pattern, and AWS-first configuration.

See `AGENTS.md` for agent routing and skill maps, and `README.md` for the user-facing overview.

## Philosophy

- **Guided over prescriptive** — ask the right questions, then recommend one approach with a clear rationale.
- **Modern .NET only** — target .NET 10 and C# 14. No legacy patterns, no .NET Framework compatibility.
- **Architecture-aware** — support VSA, Clean Architecture, DDD and Modular Monolith, with `architecture-advisor` choosing the fit (see ADR-005).
- **Controller-based APIs** — every HTTP sample uses attribute-routed `[ApiController]` classes. No Minimal API samples.
- **AWS for cloud concerns** — secrets and configuration come from Systems Manager Parameter Store / Secrets Manager. No Azure-specific guidance.
- **Token-conscious** — every file respects context limits (see the line budgets below).
- **Practical over theoretical** — every recommendation has a code example and a "why".

## Skill Structure

Each skill lives at `skills/<skill-name>/SKILL.md`.

### Frontmatter (required)

```yaml
---
name: skill-name           # kebab-case, matches the directory name
description: >
  What this skill does and when Claude should load it.
  Include trigger keywords and specific scenarios.
---
```

### Required sections

1. **Core Principles** — 3–5 numbered, opinionated defaults with rationale
2. **Patterns** — each with a descriptive heading, working modern C#, and a short "why"
3. **Anti-patterns** — what not to do, as BAD/GOOD code comparisons
4. **Decision Guide** — a table of Scenario → Recommendation

### Quality standards

- **Maximum 400 lines.** Every line must earn its place.
- **Every recommendation has a "why".** No bare rules.
- **Modern C# in every example** — primary constructors, collection expressions, file-scoped namespaces, records.
- **Built-in OpenAPI only** — no Swashbuckle.
- **No repository pattern over EF Core** — use `DbContext` directly.
- **`TimeProvider` over `DateTime.Now`** — always.
- **Tests use SQLite in-memory** for the database — never the EF Core InMemory provider.

## Workflow Skills (slash commands)

Workflow skills such as `/verify`, `/scaffold` and `/tdd` are ordinary skills at `skills/<name>/SKILL.md`; each registers `/name` automatically. There is no `commands/` directory — never create one.

### Frontmatter (required)

```yaml
---
name: workflow-name        # kebab-case, matches the directory name; registers /workflow-name
description: >
  What this workflow does and its trigger phrases.
# Optional: disable-model-invocation: true — for explicit /name invocation only
---
```

### Required sections

1. **What** — what the workflow does
2. **When** — when to use it (trigger phrases)
3. **How** — step-by-step flow (which skills and agents it uses)
4. **Example** — sample output or usage
5. **Related** — related workflows

### Quality standards

- **Maximum 200 lines.** Workflows are not encyclopedias.
- **One skill per concern.** A workflow carries its method inline; never add a separate knowledge "twin" for it.
- **Deep reference material goes in `references/`** — e.g. `skills/<name>/references/<topic>.md`, linked from SKILL.md and loaded only on demand.
- **Clear trigger phrases.** When merging skills, the surviving description absorbs the other's triggers.

## Agent Structure

Agents live at `agents/<agent-name>.md`.

### Frontmatter (required)

```yaml
---
name: agent-name           # kebab-case, matches the file name
description: >
  What this agent is an expert in and when Claude should delegate to it.
  Include concrete trigger scenarios — Claude routes work based on this.
model: sonnet              # optional — tier alias only (fable/opus/sonnet/haiku), never a pinned version ID
memory: project            # optional — persistent agent memory
disallowedTools: Write, Edit  # optional — e.g. keeps review agents read-only
isolation: worktree        # optional — run in an isolated git worktree
---
```

Plugin agents must NOT declare `permissionMode`, `hooks` or `mcpServers`; those fields are reserved for user- and project-level agents.

### Required sections

1. **Role** — what this agent is an expert in
2. **Skill dependencies** — which skills it loads, by name (keep `AGENTS.md` in sync)
3. **Tool usage** — how it searches the code (Grep/Glob, scoped `dotnet build`, `dotnet list`) before reading files
4. **Response patterns** — how it structures guidance
5. **Boundaries** — what it does NOT handle

## Rule Structure

Rules live at `.claude/rules/<rule-name>.md` and are always loaded into the user's context.

```yaml
---
alwaysApply: true
description: >
  What this rule enforces.
---
```

- **Maximum 100 lines per rule**, and keep all rules combined lean (~650 lines) — they cost tokens in every session.
- **DO/DON'T format** with a short rationale for each.

## Templates

Each template at `templates/<name>/` has:

- `CLAUDE.md` — the drop-in file for a user's project
- `README.md` — when and how to use the template

Templates reference skills by name and must stand alone: a user copies only `CLAUDE.md`.

## Knowledge Documents

Files in `knowledge/` are reference material, not skills, and don't use skill frontmatter.

- `dotnet-whats-new.md` — updated per .NET release
- `common-antipatterns.md` — patterns Claude must never generate (rule IDs shared with the hooks)
- `package-recommendations.md` — vetted NuGet packages
- `breaking-changes.md` — migration gotchas
- `decisions/*.md` — ADRs, using `knowledge/template.md`

## Hooks

Scripts live in `hooks/`; `hooks/hooks.json` wires the Claude Code ones and `hooks/README.md` documents all of them.

- Scripts must be bash, keep LF line endings (enforced by `.gitattributes`), and pass `bash -n`.
- Claude Code hooks read the event JSON from stdin, exit `0` to allow and `2` to block, and write block reasons to stderr.
- Anti-pattern rule IDs (AP001…) must match `knowledge/common-antipatterns.md` and ADR-006.

## Workflow Standards

### Plan before building

- Plan any non-trivial change (3+ steps or a structural decision) before editing.
- If an approach goes sideways, stop and re-plan instead of pushing through.

### Verify before done

- Check that every cross-reference resolves: skills → skills, agents → skills, `AGENTS.md` → agents and skills, README counts → real files.
- Run `bash -n hooks/*.sh` after editing hooks, and validate `hooks/hooks.json` and `.claude-plugin/*.json` as JSON.
- Ask: "Would a staff .NET engineer approve this?" If not, iterate.

### Learn from corrections

- After any correction from the user, record the pattern in auto memory so it doesn't recur.

## Contribution Checklist

1. Follow the skill, workflow, agent, rule and template structures above.
2. Keep knowledge skills under 400 lines, workflow skills under 200, and rules under 100.
3. Every new pattern gets a BAD/GOOD comparison in Anti-patterns.
4. Keep `README.md` and `AGENTS.md` in sync when adding, renaming or removing skills and agents.
5. Don't hardcode package versions — follow `.claude/rules/packages.md`.
6. Use conventional commit messages (`feat:`, `fix:`, `docs:`, `refactor:`, `chore:`).
