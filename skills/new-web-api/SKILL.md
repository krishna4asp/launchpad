---
name: new-web-api
description: >
  Bootstrap a new ASP.NET Core Web API project. Creates the solution, copies the
  launchpad web-api CLAUDE.md template into the project root, and replaces
  placeholders with the actual project name. Invoke as /new-web-api [ProjectName].
argument-hint: [ProjectName]
user_invocable: true
---

# /new-web-api — Bootstrap a Web API Project

Creates a new .NET 10 ASP.NET Core Web API project and installs the launchpad
CLAUDE.md so Claude is pre-configured with the right stack, patterns, and
anti-patterns from the first prompt.

## Steps

1. **Confirm the project name.** If no argument was given, ask: "What should the
   project be called?" Use PascalCase (e.g. `OrderService`). Do not proceed without a name.

2. **Create the solution and project.**

   ```bash
   mkdir <ProjectName>
   cd <ProjectName>
   dotnet new sln -n <ProjectName>
   mkdir src tests
   dotnet new webapi -n <ProjectName>.Api -o src/<ProjectName>.Api
   dotnet sln add src/<ProjectName>.Api/<ProjectName>.Api.csproj
   ```

3. **Copy the launchpad CLAUDE.md template.**

   Read `templates/web-api/CLAUDE.md` from the launchpad plugin root and write it
   to `<ProjectName>/CLAUDE.md` in the new project root.

4. **Replace the placeholder project name.**

   In the written `CLAUDE.md`, replace every occurrence of:
   - `[Project Name]` (with space) → actual project name
   - `[ProjectName]` (no space) → actual project name

5. **Verify the build.**

   ```bash
   dotnet build <ProjectName>/<ProjectName>.sln
   ```

   Expected: Build succeeded with 0 errors. Fix any build errors before reporting success.

6. **Confirm to the user.**

   Report: "Project `<ProjectName>` created at `./<ProjectName>/`. CLAUDE.md is
   configured. Run `dotnet run --project src/<ProjectName>.Api` to start."

## Notes

- The template CLAUDE.md instructs Claude to run `architecture-advisor` before
  writing any feature code. Remind the user to do this when they open the project.
- The `dotnet new webapi` template defaults to minimal APIs on .NET 8+, matching
  the anti-patterns in the CLAUDE.md template. Do not pass `--no-openapi` or
  switch to controllers.
- Delete the architecture options (A/B/C) from CLAUDE.md that won't be used, or
  leave them for the user to choose — ask if unsure.
