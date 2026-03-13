# LegionIO: Async Job Engine and Task Framework

**Repository Level 3 Documentation**
- **Parent**: `/Users/miverso2/rubymine/legion/CLAUDE.md`

## Purpose

The primary gem for the LegionIO framework. An extensible async job engine for scheduling tasks, creating relationships between services, and running them concurrently via RabbitMQ. Orchestrates all `legion-*` gems and loads Legion Extensions (LEXs).

**GitHub**: https://github.com/LegionIO/LegionIO
**License**: Apache-2.0
**Docker**: `legionio/legion`

## Architecture

### Startup Sequence

```
Legion.start
  └── Legion::Service.new
      ├── 1. setup_logging      (legion-logging)
      ├── 2. setup_settings     (legion-settings, loads from /etc/legionio or ~/legionio)
      ├── 3. Legion::Crypt.start (legion-crypt, Vault connection)
      ├── 4. setup_transport    (legion-transport, RabbitMQ connection)
      ├── 5. require legion-cache
      ├── 6. setup_data         (legion-data, MySQL connection + migrations)
      ├── 7. setup_supervision  (process supervision)
      ├── 8. load_extensions    (discover and load LEX gems)
      └── 9. Legion::Crypt.cs   (distribute cluster secret)
```

### Module Structure

```
Legion (lib/legion.rb)
├── Service            # Orchestrator: initializes all modules, manages lifecycle
├── Process            # Daemonization: PID management, signal traps, main loop
├── Extensions         # LEX discovery, loading, and lifecycle management
│   ├── Actors/        # Actor types for extension execution
│   │   ├── Base       # Base actor class
│   │   ├── Every      # Run at interval
│   │   ├── Loop       # Continuous loop
│   │   ├── Once       # Run once
│   │   ├── Poll       # Polling actor
│   │   ├── Subscription  # AMQP subscription actor
│   │   └── Nothing    # No-op actor
│   ├── Builders/      # Extension component builders
│   │   ├── Actors     # Build actors from extension definitions
│   │   ├── Runners    # Build runners from extension definitions
│   │   └── Helpers    # Builder utilities
│   ├── Helpers/       # Extension helper mixins
│   │   ├── Cache      # Cache access helper
│   │   ├── Data       # Database access helper
│   │   ├── Logger     # Logging helper
│   │   ├── Transport  # AMQP transport helper
│   │   ├── Task       # Task management helper
│   │   └── Lex        # LEX metadata helper
│   ├── Data/          # Extension data layer
│   │   ├── Migrator   # Extension-specific migrations
│   │   └── Model      # Extension-specific models
│   └── Transport      # Extension transport setup
│
├── Events             # In-process pub/sub event bus
│                      # Lifecycle: service.ready, service.shutting_down, extension.loaded
│                      # Runner: task.completed, task.failed
│
├── Ingress            # Transport abstraction layer
│                      # Source-agnostic entry point for runner invocation
│                      # AMQP subscription, HTTP adapter (webhooks/API)
│
├── API (Sinatra)      # Webhook HTTP API (Legion::API)
│
├── Readiness          # Startup readiness tracking (replaced sleep hacks)
│
├── Runner             # Task execution engine
│   ├── Log            # Task logging
│   └── Status         # Task status tracking
│
├── Supervision        # Process supervision
├── Lex                # LEX gem discovery and loading
├── CLI (Thor)         # Unified command-line interface (Legion::CLI::Main)
│   ├── Output         # Formatter: color tables, JSON mode, status indicators
│   ├── Connection     # Lazy connection manager (only connect to what's needed)
│   ├── Start          # Daemon startup (replaces old exe/legionio OptionParser)
│   ├── Status         # Service status (probes HTTP API or shows static info)
│   ├── Lex            # Extension management: list, info, create, enable, disable
│   ├── Task           # Task management: list, show, logs, run (dot notation), purge
│   ├── Chain          # Chain management: list, create, delete
│   ├── Config         # Config tools: show (redacted), path, validate
│   └── Generate       # Code generators: runner, actor, exchange, queue, message
└── Version
```

### CLI (`legion` command)

Single unified CLI entry point. All commands support `--json` for structured output and `--no-color`.

```
legion
  version                          # Component versions + installed extension count
  start [-d] [-p PID] [-t SECS]   # Start daemon (daemonize, PID file, time limit)
  stop [-p PID]                    # Stop running daemon via PID signal
  status                           # Running status + component health (probes API)

  lex
    list [-a]                      # All extensions with version/status/runners/actors
    info <name>                    # Extension detail: runners, actors, deps, gem path
    create <name>                  # Scaffold new LEX (gemspec, specs, CI, git init)
    enable <name>                  # Enable extension in settings
    disable <name>                 # Disable extension in settings

  task
    list [-n 20] [-s status]       # Recent tasks with filters
    show <id>                      # Task detail + arguments
    logs <id> [-n 50]              # Task execution logs
    run [ext.runner.func] [k:v]    # Trigger task (dot notation, flags, or interactive)
    purge [--days 7] [-y]          # Cleanup old tasks

  chain
    list [-n 20]                   # List chains
    create <name>                  # Create chain
    delete <id> [-y]               # Delete chain (with confirmation)

  config
    show [-s section]              # Resolved config (sensitive values redacted)
    path                           # Config search paths + env vars
    validate                       # Check settings, transport, data health

  generate (alias: g)              # Must run from inside a lex-* directory
    runner <name> [--functions x]  # Add runner + spec to current LEX
    actor <name> [--type sub]      # Add actor + spec (subscription/every/poll/once/loop)
    exchange <name>                # Add transport exchange
    queue <name>                   # Add transport queue
    message <name>                 # Add transport message
```

**Key design decisions:**
- **Lazy connections**: Commands only connect to subsystems they need (no full service boot for queries)
- **JSON output**: `--json` on every command for AI agents and scripting
- **Progressive disclosure**: `legion task run` supports dot notation (`http.request.get`), flags (`-e http -r request -f get`), or interactive selection
- **Secret redaction**: `config show` auto-redacts password/token/secret/key fields

| Executable | Purpose |
|-----------|---------|
| `legion` | Unified CLI entry point (`Legion::CLI::Main`) |
| `legionio` | Legacy wrapper, delegates to `legion start` |
| `lex_gen` | Legacy wrapper, delegates to `legion lex create` / `legion generate` |

## Key Design Patterns

### Extension System (LEX)
Extensions are gems named `lex-*` that plug into the framework:
- Auto-discovered via `Gem::Specification`
- Each LEX defines runners (functions) and actors (execution modes)
- Actors determine HOW a function runs: subscription (AMQP), polling, interval, one-shot, loop
- Extensions register in the database via `legion-data` models

### Task Relationships
Tasks can be chained with conditions and transformations:
```
Task A -> [condition check] -> Task B -> [transform] -> Task C
                                      -> Task D (parallel)
```
- **Conditions**: JSON rule engine (all/any/fact/operator) via `lex-conditioner`
- **Transformations**: ERB templates via `tilt` gem for inter-service data mapping

### Daemonization
`Legion::Process` handles PID management, signal trapping (SIGINT for graceful shutdown), optional daemonization with `fork`/`setsid`, and time-limited execution.

## Dependencies

### Legion Gems (all required)
| Gem | Purpose |
|-----|---------|
| `legion-cache` (>= 0.3) | Caching (Redis/Memcached) |
| `legion-crypt` (>= 0.3) | Encryption, Vault, JWT |
| `legion-json` (>= 1.2) | JSON serialization |
| `legion-logging` (>= 0.3) | Logging |
| `legion-settings` (>= 0.3) | Configuration |
| `legion-transport` (>= 1.2) | RabbitMQ messaging |
| `lex-node` | Node identity extension |

### External Gems
| Gem | Purpose |
|-----|---------|
| `concurrent-ruby` + `ext` (>= 1.2) | Thread pool, concurrency primitives |
| `daemons` (>= 1.4) | Process daemonization |
| `oj` (>= 3.16) | Fast JSON (C extension) |
| `puma` (>= 6.0) | HTTP server for API |
| `sinatra` (>= 4.0) | HTTP API framework |
| `thor` (>= 1.3) | CLI framework |

### Dev Dependencies
| Gem | Purpose |
|-----|---------|
| `legion-data` | MySQL/SQLite persistent storage (optional at runtime) |

## Deployment

**Docker**:
```dockerfile
FROM ruby:3-alpine
RUN gem install legionio
CMD ruby --jit $(which legionio)
```

**Config Paths** (checked in order):
1. `/etc/legionio/`
2. `~/legionio/`
3. `./settings/`

## File Map

| Path | Purpose |
|------|---------|
| `lib/legion.rb` | Entry point: `Legion.start`, `.shutdown`, `.reload` |
| `lib/legion/service.rb` | Module orchestrator, startup sequence |
| `lib/legion/process.rb` | Daemon lifecycle, PID, signals |
| `lib/legion/extensions.rb` | LEX discovery and loading |
| `lib/legion/extensions/actors/` | Actor types (every, loop, once, poll, subscription) |
| `lib/legion/extensions/builders/` | Build actors, runners, and hooks from LEX definitions |
| `lib/legion/extensions/hooks/base.rb` | Webhook hook system base class |
| `lib/legion/extensions/helpers/` | Helper mixins for extensions |
| `lib/legion/events.rb` | In-process pub/sub event bus |
| `lib/legion/ingress.rb` | Transport abstraction (source-agnostic runner invocation) |
| `lib/legion/api.rb` | Sinatra webhook HTTP API |
| `lib/legion/readiness.rb` | Startup readiness tracking |
| `lib/legion/runner.rb` | Task execution engine |
| `lib/legion/supervision.rb` | Process supervision |
| **CLI v2** | |
| `lib/legion/cli.rb` | Main CLI: `Legion::CLI::Main` Thor app, global flags, version, start/stop |
| `lib/legion/cli/output.rb` | Output formatter: color, tables, JSON mode, status indicators |
| `lib/legion/cli/connection.rb` | Lazy connection manager (idempotent `ensure_*` methods) |
| `lib/legion/cli/error.rb` | CLI-specific error class |
| `lib/legion/cli/start.rb` | `legion start` command (daemon boot) |
| `lib/legion/cli/status.rb` | `legion status` command (probes API or shows static info) |
| `lib/legion/cli/lex_command.rb` | `legion lex` subcommands + `LexGenerator` scaffolding class |
| `lib/legion/cli/task_command.rb` | `legion task` subcommands (list, show, logs, run, purge) |
| `lib/legion/cli/chain_command.rb` | `legion chain` subcommands (list, create, delete) |
| `lib/legion/cli/config_command.rb` | `legion config` subcommands (show, path, validate) |
| `lib/legion/cli/generate_command.rb` | `legion generate` subcommands (runner, actor, exchange, queue, message) |
| **Legacy CLI (preserved)** | |
| `lib/legion/lex.rb` | Old `Legion::Cli::LexBuilder` (used by legacy `lex_gen`) |
| `lib/legion/cli/task.rb` | Old task commands (preserved, not loaded by new CLI) |
| `lib/legion/cli/trigger.rb` | Old trigger command (preserved, not loaded by new CLI) |
| `lib/legion/cli/lex/` | Old LEX sub-generators + ERB templates |
| **Executables** | |
| `exe/legion` | Unified CLI entry point (`Legion::CLI::Main.start`) |
| `exe/legionio` | Legacy wrapper, delegates to `legion start` |
| `exe/lex_gen` | Legacy wrapper, delegates to `legion lex create` / `legion generate` |
| `Dockerfile` | Docker build |
| `docker_deploy.rb` | Build + push Docker image |

## Example LEX Extensions

| Extension | Purpose |
|-----------|---------|
| `lex-http` | HTTP requests |
| `lex-influxdb` | InfluxDB read/write |
| `lex-ssh` | Remote SSH commands |
| `lex-redis` | Redis operations |
| `lex-scheduler` | Cron/interval scheduling |
| `lex-conditioner` | Conditional rule evaluation |
| `lex-transformation` | ERB-based data transformation |

## Related Components

| Component | Relationship |
|-----------|-------------|
| `legion-transport` | RabbitMQ messaging layer (FIFO queues for task distribution) |
| `legion-cache` | Optional caching for extension data |
| `legion-crypt` | Vault secrets + message encryption |
| `legion-data` | MySQL persistence for tasks, extensions, scheduling |
| `legion-json` | JSON serialization foundation |
| `legion-logging` | Logging foundation |
| `legion-settings` | Configuration foundation |

---

**Maintained By**: Matthew Iverson (@Esity)
