# Worker Service Template

## When to Use

Use this template when you are building:

- A headless background process with no HTTP endpoints
- A message consumer for RabbitMQ or Azure Service Bus (via Wolverine or MassTransit)
- A service that runs scheduled or recurring jobs
- A hosted service that performs periodic work (polling, syncing, cleanup)

## How to Use

1. Copy `CLAUDE.md` into the root of your .NET Worker Service project
2. Replace `[ProjectName]` with your actual project name
3. Update the **Tech Stack** section to match your actual dependencies
4. Remove any optional items (Hangfire, Entity Framework Core) that do not apply
5. Remove any skills references that are not relevant to your project

## What's Included

This template configures Claude Code to:

- Build workers on `BackgroundService` / `IHostedService`
- Create a DI scope per iteration via `IServiceScopeFactory` — never inject scoped services into a worker directly
- Pass `CancellationToken` through every call and shut down gracefully
- Consume messages with Wolverine (or MassTransit)
- Handle transient failures with Polly resilience policies
- Use .NET 10 / C# 14 modern patterns
- Write tests with xUnit v3, SQLite in-memory for database code, and the messaging library's in-memory test harness for consumers
- Follow structured logging with Serilog

## Customization

### Switching Messaging

The template defaults to Wolverine (MIT licensed). To use MassTransit instead, swap the consumer classes to implement `IConsumer<T>` and see the `messaging` skill. Note: MassTransit requires a commercial license from v9.

### Adding Scheduled Jobs

For recurring or scheduled jobs, add Hangfire and place job classes in the `Jobs/` folder. For simple fixed-interval work, a `BackgroundService` with `PeriodicTimer` is enough — no extra library needed.

### Adding Data Access

If the worker reads or writes a database, add Entity Framework Core, put the `DbContext` under `Common/Persistence/`, and resolve it from a scope created per iteration. Add the `ef-core` skill to the skills list.

### Adding Health Checks

If the worker needs liveness/readiness probes, add the ASP.NET Core health check endpoints and see the `logging` skill.
