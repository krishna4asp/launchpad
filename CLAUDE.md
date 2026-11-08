# launchpad — Development Instructions

> These instructions are for developing THIS repository. For files users drop into their own projects, see `templates/`.

## Repository Purpose

launchpad is a Claude Code plugin for .NET developers. It ships skills, agents, rules, templates, knowledge documents and hooks that make Claude Code write modern .NET 10 / C# 14 code: controller-based REST APIs, EF Core used directly, the Result pattern, and AWS-first configuration.

## Where Things Live

| Path | What | Format |
|------|------|--------|
| `skills/<name>/SKILL.md` | Knowledge and workflow (slash-command) skills | [Skills](docs/authoring.md#skills), [Workflow Skills](docs/authoring.md#workflow-skills-slash-commands) |
| `agents/<name>.md` | Specialist agents | [Agents](docs/authoring.md#agent-structure) |
| `.claude/rules/*.md` | Always-on rules users copy into their projects | [Rules](docs/authoring.md#rule-structure) |
| `templates/<name>/` | Drop-in `CLAUDE.md` + `README.md` per project type | [Templates](docs/authoring.md#templates) |
| `knowledge/` | Reference docs and ADRs (`decisions/`) | [Knowledge](docs/authoring.md#knowledge-documents) |
| `hooks/` | Claude Code hooks (`hooks.json`) and git pre-commit scripts | [Hooks](docs/authoring.md#hooks) |
| `AGENTS.md` | Agent routing table and per-agent skill maps | — |

**Read `docs/authoring.md` before creating or restructuring any of these files.**

## Philosophy

- **Guided over prescriptive** — ask the right questions, then recommend one approach with a clear rationale.
- **Modern .NET only** — .NET 10 and C# 14. No legacy patterns, no .NET Framework compatibility.
- **Architecture-aware** — VSA, Clean Architecture, DDD and Modular Monolith, with `architecture-advisor` choosing the fit (ADR-005).
- **Controller-based APIs** — every HTTP sample uses attribute-routed `[ApiController]` classes. No Minimal API samples.
- **AWS for cloud concerns** — Systems Manager Parameter Store / Secrets Manager for secrets. No Azure-specific guidance.
- **Token-conscious** — knowledge skills ≤ 400 lines, workflow skills ≤ 200, rules ≤ 100, `CLAUDE.md` files ≤ 200.
- **Practical over theoretical** — every recommendation has a code example and a "why".

## Hard Rules

- No `commands/` directory — slash commands are workflow skills.
- Plugin agents never declare `permissionMode`, `hooks` or `mcpServers`.
- Model references use tier aliases (`fable`, `opus`, `sonnet`, `haiku`), never pinned version IDs.
- Don't hardcode package versions — follow `.claude/rules/packages.md`.

## Workflow Standards

- **Plan before building** — plan any non-trivial change (3+ steps or a structural decision); if it goes sideways, stop and re-plan.
- **Keep things in sync** — when adding, renaming or removing a skill or agent, update `README.md` (lists and counts) and `AGENTS.md` (routing and skill maps).
- **Verify before done:**
  - every cross-reference resolves (skills → skills, agents → skills, `AGENTS.md` → real files);
  - `bash -n hooks/*.sh` passes after editing hooks;
  - `hooks/hooks.json` and `.claude-plugin/*.json` parse as JSON.
- **Learn from corrections** — record any user correction in auto memory so it doesn't recur.
- **Commits** — conventional prefixes (`feat:`, `fix:`, `docs:`, `refactor:`, `chore:`), one logical change each.
