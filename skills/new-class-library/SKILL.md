---
name: new-class-library
description: >
  Bootstrap a new .NET class library / NuGet package project. Creates the
  solution structure, copies the launchpad class-library CLAUDE.md template, and
  replaces placeholders with the actual project name. Invoke as
  /new-class-library [ProjectName].
argument-hint: [ProjectName]
user_invocable: true
---

# /new-class-library — Bootstrap a Class Library / NuGet Package

Creates a new .NET 10 class library project and installs the launchpad CLAUDE.md
so Claude is pre-configured with public API conventions, NuGet packaging, XML
docs, and anti-patterns from the first prompt.

## Steps

1. **Confirm the project name.** If no argument was given, ask: "What should the
   library be called?" Use PascalCase (e.g. `Acme.Core`). Do not proceed without a name.

2. **Create the solution and projects.**

   ```bash
   mkdir <ProjectName>
   cd <ProjectName>
   dotnet new sln -n <ProjectName>
   mkdir src tests
   dotnet new classlib -n <ProjectName> -o src/<ProjectName>
   dotnet new xunit -n <ProjectName>.Tests -o tests/<ProjectName>.Tests
   dotnet sln add src/<ProjectName>/<ProjectName>.csproj
   dotnet sln add tests/<ProjectName>.Tests/<ProjectName>.Tests.csproj
   dotnet add tests/<ProjectName>.Tests/<ProjectName>.Tests.csproj reference src/<ProjectName>/<ProjectName>.csproj
   ```

3. **Copy the launchpad CLAUDE.md template.**

   Read `templates/class-library/CLAUDE.md` from the launchpad plugin root and
   write it to `<ProjectName>/CLAUDE.md` in the new project root.

4. **Replace the placeholder project name.**

   In the written `CLAUDE.md`, replace every occurrence of:
   - `[Project Name]` (with space) → actual project name
   - `[ProjectName]` (no space) → actual project name

5. **Enable XML documentation in the library csproj.**

   Add inside `<PropertyGroup>` in `src/<ProjectName>/<ProjectName>.csproj`:

   ```xml
   <GenerateDocumentationFile>true</GenerateDocumentationFile>
   <TreatWarningsAsErrors>true</TreatWarningsAsErrors>
   ```

6. **Verify the build.**

   ```bash
   dotnet build <ProjectName>/<ProjectName>.sln
   dotnet test <ProjectName>/<ProjectName>.sln
   ```

   Expected: Build succeeded with 0 errors; all tests pass. Fix any errors before
   reporting success.

7. **Confirm to the user.**

   Report: "Library `<ProjectName>` created at `./<ProjectName>/`. CLAUDE.md is
   configured. Run `dotnet pack src/<ProjectName> -c Release` to build the NuGet package."

## Notes

- The `<GenerateDocumentationFile>true</GenerateDocumentationFile>` added in step 5
  enforces XML doc requirements at build time — missing docs produce build warnings
  (and errors, with `TreatWarningsAsErrors`).
- Remind the user to add `[assembly: InternalsVisibleTo("<ProjectName>.Tests")]`
  in the library csproj if tests need access to internal types.
- Optional features (Verify snapshot testing, BenchmarkDotNet, strong naming) are
  described in `templates/class-library/README.md` — point the user there if they ask.
