# Blazor Application Template

## When to Use

Use this template when you're building:

- A Blazor Server application with interactive server-side rendering
- A Blazor WebAssembly (WASM) application running entirely in the browser
- A Blazor Auto application that starts with Server interactivity and transitions to WASM
- A Blazor app that mixes static SSR pages with selectively interactive components

## How to Use

1. Copy `CLAUDE.md` into the root of your Blazor project
2. Replace `[ProjectName]` with your actual project name
3. Choose your render mode and update the **Project Context** section:
   - **Server** — All interactivity runs on the server over SignalR
   - **WebAssembly** — Interactivity runs in the browser via WASM
   - **Auto** — Server-rendered initially, transitions to WASM after the runtime downloads
4. Update the **Tech Stack** section to match your dependencies
5. If you don't have a separate `.Client` project (Server-only mode), remove the `[ProjectName].Client/` section from the Architecture diagram
6. Remove any skills references that don't apply to your project

## What's Included

This template configures Claude Code to:

- Organize components by feature under `Components/Pages/`
- Apply render modes at the component level, not globally
- Use a service layer between components and data access (no DbContext in components)
- Follow .NET 10 / C# 14 modern patterns
- Use ASP.NET Core Identity for authentication
- Write component tests with bUnit and integration tests with WebApplicationFactory
- Avoid common Blazor pitfalls like unnecessary JS interop and render mode confusion
- Use structured logging with Serilog

## Customization

### Choosing a Render Mode

**Server only:** Best for intranet apps, admin dashboards, and apps with sensitive data that should stay on the server. Remove the `.Client` project from the architecture diagram.

**WebAssembly only:** Best for public-facing apps that need offline support or minimal server load. Note that initial load is slower due to the .NET runtime download.

**Auto (recommended default):** Best for most apps. Users get immediate interactivity via Server, then seamlessly transition to WASM on subsequent visits. Requires both server and client projects.

### Adding API Endpoints

If your Blazor app also exposes API endpoints (common for WASM/Auto apps that need server-side data access), add the `controller-based-apis` skill to the skills list, create a `Controllers/` folder with `[ApiController]` classes in the architecture section, and register them with `builder.Services.AddControllers()` and `app.MapControllers()`.

### Without Entity Framework Core

If your app uses a different data access strategy (Dapper, HTTP APIs, etc.), remove `ef-core` from the skills list and update the Tech Stack accordingly.

### Adding Real-time Features

For apps using SignalR hubs beyond Blazor's built-in circuit, add hub classes to a `Hubs/` folder and document the hub contracts in the architecture section.
