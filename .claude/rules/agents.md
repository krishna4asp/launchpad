---
alwaysApply: true
description: >
  Enforces search-before-read tool usage, subagent routing for parallel work,
  and agent selection guidance for .NET projects.
---

# Agent & Tool Usage Rules

## Search Before Reading Files

- **DO** use Grep and Glob to locate types, members, and usages before reading source files.
  Rationale: Search results are focused and cheap. Reading full files wastes context window.

- **DO** check project references (`dotnet list <project> reference` or `<ProjectReference>` entries) before making any structural changes (new projects, moved references).
  Rationale: Understanding the dependency tree prevents circular references and misplaced code.

- **DO** run `dotnet build` scoped to the changed project after modifications.
  Rationale: A scoped build surfaces compiler errors and analyzer warnings quickly without building the whole solution.

- **DON'T** read entire files to find a single method or type. Grep for the declaration, then read only that range.
  Rationale: A 500-line file costs tokens. A targeted search costs almost nothing.

## Subagent Routing

- **DO** use subagents for parallel research, exploration, and independent tasks.
  Rationale: Subagents keep the main context window clean and enable concurrent work.

- **DO** assign one task per subagent for focused execution.
  Rationale: Mixed-task subagents produce unfocused results and harder-to-review outputs.

- **DO** route to specialist agents for domain-specific work. Check AGENTS.md for the routing table.
  Rationale: Specialist agents carry pre-loaded skills and domain context that generalists lack.

- **DON'T** use subagents for trivial, single-step tasks. The overhead is not worth it.
  Rationale: Spawning a subagent for a one-liner adds latency without benefit.

## Model Selection

- **DO** use Sonnet for routine tasks: formatting, simple refactors, test generation, boilerplate.
  Rationale: Sonnet is faster and cheaper for well-defined, low-ambiguity work.

- **DO** use Opus for complex architecture decisions, design reviews, and multi-system analysis.
  Rationale: Opus handles nuance, trade-offs, and large context better for high-stakes decisions.

- **DO** escalate to Fable for the highest-stakes work: greenfield architecture for long-lived systems, or problems that resisted an Opus pass.
  Rationale: Fable is the frontier tier above Opus. Reserve it for decisions where a mistake is very expensive.

- **DO** use model aliases (`fable`, `opus`, `sonnet`, `haiku`) in agent frontmatter and configs — never pinned version IDs.
  Rationale: Aliases track the latest version of each tier; pinned IDs rot when new versions ship.

## Skill Loading

- **DO** load relevant skills before starting work. Check AGENTS.md skill maps for the current task domain.
  Rationale: Skills carry opinionated patterns and anti-patterns that prevent common mistakes.

- **DON'T** start implementation without checking if a relevant skill exists.
  Rationale: Re-discovering best practices wastes time when they are already codified.
