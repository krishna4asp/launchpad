---
name: wrap-up
description: >
  End-of-session structured handoff. Use at the end of any working session to
  write a .claude/handoff.md that captures what was done, what is in progress,
  open decisions, blockers, and what to do next — so the next session picks up
  without re-deriving context.
user_invocable: true
---

# /wrap-up — Session Handoff

Use this skill at the **end** of a working session to write `.claude/handoff.md`
in the current project root. The file gives the next session — or a new agent —
everything it needs to continue without asking questions.

## When to use

- You are about to stop for the day
- You are handing off to a different Claude session or subagent
- A long session is about to be summarized / context-compressed

## What to write

Create or overwrite `.claude/handoff.md` with these sections:

### Status
One sentence: what state is the code in right now? (green build, failing test,
mid-refactor, etc.)

### Done this session
Bulleted list of completed work with file paths where relevant.

### In progress
Any work that was started but not finished. Include the exact file and line or
the failing test so the next session can resume precisely.

### Open decisions
Choices that were deferred: name them and note the tradeoffs considered.

### Blockers
Anything that stopped progress. External dependency, waiting for a review,
unclear requirement.

### Next steps
Ordered list: what to do first, second, third in the next session.

### Key context
Facts a new session cannot derive from the code: why something was done a
certain way, a constraint from a stakeholder, a non-obvious invariant.

## How

1. Read the current `git status` and recent `git log --oneline -10` to recall what changed.
2. Ask: "If I opened this project cold tomorrow, what would I need to know?"
3. If `.claude/` does not exist in the project root, create it first.
4. Write `.claude/handoff.md` using the sections above. Keep each section tight —
   bullet points, not paragraphs. Write "None" rather than leaving a section blank.
4. Confirm to the user: "Handoff written to `.claude/handoff.md`."
