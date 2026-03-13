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
├── CLI (Thor)         # Command-line interface
│   ├── cohort         # Cohort management
│   ├── function       # Function operations
│   ├── relationship   # Relationship CRUD
│   ├── task           # Task CRUD
│   ├── chain          # Chain management
│   ├── trigger        # Send tasks to workers
│   └── lex/           # LEX management (actors, exchanges, messages, queues, runners)
└── Version
```

### CLIs

| Executable | Purpose |
|-----------|---------|
| `legionio` | Start the LegionIO daemon |
| `legion` | Thor-based CLI for managing tasks, relationships, functions, LEXs |
| `lex_gen` | Generate new Legion Extension scaffolding |

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
| `legion-cache` (>= 0.2.0) | Caching (Redis/Memcached) |
| `legion-crypt` (>= 0.2.0) | Encryption and Vault |
| `legion-json` (>= 0.2.0) | JSON serialization |
| `legion-logging` (>= 0.2.0) | Logging |
| `legion-settings` (>= 0.2.0) | Configuration |
| `legion-transport` (>= 1.1.9) | RabbitMQ messaging |
| `lex-node` | Node identity extension |

### External Gems
| Gem | Purpose |
|-----|---------|
| `concurrent-ruby` + `ext` | Thread pool, concurrency primitives |
| `daemons` | Process daemonization |
| `oj` | Fast JSON (C extension) |
| `thor` | CLI framework |

### Dev Dependencies
| Gem | Purpose |
|-----|---------|
| `legion-data` | MySQL persistent storage (optional at runtime) |

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
| `lib/legion/cli.rb` | Thor CLI (legion command) |
| `lib/legion/lex.rb` | LEX gem discovery |
| `lib/legion/supervision.rb` | Process supervision |
| `exe/legionio` | Start daemon |
| `exe/legion` | CLI entry point |
| `exe/lex_gen` | Extension generator |
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
