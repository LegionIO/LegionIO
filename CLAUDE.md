# LegionIO: Async Job Engine and Task Framework

**Repository Level 3 Documentation**
- **Parent**: `/Users/miverso2/rubymine/legion/CLAUDE.md`

## Purpose

The primary gem for the LegionIO framework. An extensible async job engine for scheduling tasks, creating relationships between services, and running them concurrently via RabbitMQ. Orchestrates all `legion-*` gems and loads Legion Extensions (LEXs).

**GitHub**: https://github.com/LegionIO/LegionIO
**Gem**: `legionio`
**Version**: 1.4.13
**License**: Apache-2.0
**Docker**: `legionio/legion`
**Ruby**: >= 3.4

## Architecture

### Boot Sequence (exe/legion)

Before any Legion code loads, `exe/legion` applies three performance optimizations:

1. **YJIT** — `RubyVM::YJIT.enable` for 15-30% runtime throughput (guarded with `if defined?`)
2. **GC tuning** — pre-allocates 600k heap slots, raises malloc limits (all `||=` so ENV overrides are respected)
3. **bootsnap** — caches YARV bytecodes and `$LOAD_PATH` resolution at `~/.legionio/cache/bootsnap/`

### Startup Sequence

```
Legion.start
  └── Legion::Service.new
      ├── 1. setup_logging      (legion-logging)
      ├── 2. setup_settings     (legion-settings, loads /etc/legionio, ~/legionio, ./settings)
      ├── 3. Legion::Crypt.start (legion-crypt, Vault connection)
      ├── 4. setup_transport    (legion-transport, RabbitMQ connection)
      ├── 5. require legion-cache
      ├── 6. setup_data         (legion-data, MySQL/SQLite + migrations, optional)
      ├── 7. setup_llm          (legion-llm, optional)
      ├── 8. setup_supervision  (process supervision)
      ├── 9. load_extensions    (discover + load LEX gems, filtered by role profile)
      ├── 10. Legion::Crypt.cs  (distribute cluster secret)
      └── 11. setup_api         (start Sinatra/Puma on port 4567)
```

Each phase calls `Legion::Readiness.mark_ready(:component)`. All phases are individually toggleable via `Service.new(transport: false, ...)`.

### Reload Sequence

`Legion.reload` shuts down all subsystems in reverse order, waits for them to drain, then re-runs setup from settings onward. Extensions and API are re-loaded fresh.

### Module Structure

```
Legion (lib/legion.rb)
├── Service            # Orchestrator: initializes all modules, manages lifecycle
│                      # Entry points: Legion.start, .shutdown, .reload
├── Process            # Daemonization: PID management, signal traps (SIGINT=quit), main loop
├── Readiness          # Startup readiness tracking
│                      # COMPONENTS: settings, crypt, transport, cache, data, extensions, api
│                      # Readiness.ready? checks all; /api/ready returns JSON status
├── Events             # In-process pub/sub event bus
│                      # Events.on(name) / .emit(name, **payload) / .once / .off
│                      # Wildcard '*' listener supported
│                      # Lifecycle: service.ready, service.shutting_down, service.shutdown
│                      # Extension: extension.loaded
│                      # Runner: ingress.received
├── Ingress            # Universal entry point for runner invocation
│                      # Sources: amqp, http, cli, api — all normalize through here
│                      # Ingress.run(payload:, runner_class:, function:, source:)
│                      # Ingress.normalize returns message hash without executing
├── Extensions         # LEX discovery, loading, and lifecycle management
│   ├── Core           # Mixin: data_required?, cache_required?, crypt_required?, etc.
│   ├── Actors/        # Actor execution modes
│   │   ├── Base       # Base actor class
│   │   ├── Every      # Run at interval (timer)
│   │   ├── Loop       # Continuous loop
│   │   ├── Once       # Run once at startup
│   │   ├── Poll       # Polling actor
│   │   ├── Subscription  # AMQP subscription (FixedThreadPool per worker count)
│   │   └── Nothing    # No-op actor
│   ├── Builders/      # Build actors and runners from LEX definitions
│   │   ├── Actors     # Build actors from extension definitions
│   │   ├── Runners    # Build runners from extension definitions
│   │   ├── Helpers    # Builder utilities
│   │   └── Hooks      # Webhook hook system builder
│   ├── Helpers/       # Helper mixins for extensions
│   │   ├── Base       # Base helper mixin
│   │   ├── Core       # Core helper mixin
│   │   ├── Cache      # Cache access helper
│   │   ├── Data       # Database access helper
│   │   ├── Logger     # Logging helper
│   │   ├── Transport  # AMQP transport helper
│   │   ├── Task       # Task management helper (generate_task_id)
│   │   └── Lex        # LEX metadata helper
│   ├── Data/          # Extension data layer
│   │   ├── Migrator   # Extension-specific migrations
│   │   └── Model      # Extension-specific models
│   ├── Hooks/
│   │   └── Base       # Webhook hook system base class
│   └── Transport      # Extension transport setup
│
├── API (Sinatra)      # Full REST API under /api/ prefix, served by Puma
│   ├── Helpers        # json_response, json_collection, json_error, pagination, redact_hash
│   │                  # parse_request_body, paginate dataset
│   ├── Routes/
│   │   ├── Tasks      # CRUD + trigger via Ingress, task logs
│   │   ├── Extensions # Nested: extensions/runners/functions + invoke
│   │   ├── Nodes      # List/show nodes (filterable by active/status)
│   │   ├── Schedules  # CRUD for lex-scheduler schedules + logs
│   │   ├── Relationships # Stub (501) - no data model yet
│   │   ├── Chains     # Stub (501) - no data model yet
│   │   ├── Settings   # Read/write settings with redaction + readonly guards
│   │   ├── Events     # SSE stream (sinatra stream) + ring buffer polling fallback
│   │   ├── Transport  # Connection status, exchanges, queues, publish
│   │   ├── Hooks      # List + trigger registered extension hooks
│   │   ├── Workers    # Digital worker lifecycle (`/api/workers/*`) + team routes (`/api/teams/*`)
│   │   └── Coldstart  # `POST /api/coldstart/ingest` — trigger lex-coldstart ingest from API
│   ├── Middleware/
│   │   └── Auth       # JWT Bearer auth middleware (real validation, skip paths for health/ready)
│   └── hook_registry  # Class-level registry: register_hook, find_hook, registered_hooks
│                      # Populated by extensions via Legion::API.register_hook(...)
│
├── MCP (mcp gem)      # MCP server for AI agent integration
│   ├── MCP.server     # Singleton factory: Legion::MCP.server returns MCP::Server instance
│   ├── Server         # MCP::Server builder, tool/resource registration
│   ├── Tools/         # 30 MCP::Tool subclasses (legion.* namespace)
│   │   ├── RunTask         # Agentic: dot notation task execution
│   │   ├── DescribeRunner  # Agentic: runner/function discovery
│   │   ├── List/Get/Delete Task + GetTaskLogs
│   │   ├── List/Create/Update/Delete Chain
│   │   ├── List/Create/Update/Delete Relationship
│   │   ├── List/Get/Enable/Disable Extension
│   │   ├── List/Create/Update/Delete Schedule
│   │   ├── GetStatus, GetConfig
│   │   └── ListWorkers, ShowWorker, WorkerLifecycle, WorkerCosts, TeamSummary, RoutingStats
│   └── Resources/
│       ├── RunnerCatalog   # legion://runners - all ext.runner.func paths
│       └── ExtensionInfo   # legion://extensions/{name} - extension detail template
│
├── DigitalWorker      # Digital worker platform (AI-as-labor governance)
│   ├── Lifecycle      # Worker state machine (active/paused/retired/terminated)
│   ├── Registry       # In-process worker registry
│   ├── RiskTier       # AIRB risk tier classification + governance constraints
│   └── ValueMetrics   # Token/cost/latency value tracking
│
├── Runner             # Task execution engine
│   ├── Log            # Task logging
│   └── Status         # Task status tracking
│
├── Supervision        # Process supervision
├── Lex                # Legacy LEX gem discovery (see Extensions for current code)
│
└── CLI (Thor)         # Unified CLI: exe/legion -> Legion::CLI::Main
    ├── Output::Formatter  # color tables, JSON mode, status indicators, ANSI stripping
    ├── Theme              # Purple palette, orbital ASCII banner, branded CLI output
    ├── Connection         # Lazy connection manager (ensure_settings, ensure_transport, etc.)
    ├── Error              # CLI-specific error class
    ├── Start              # `legion start` - daemon boot via Legion::Process
    ├── Status             # `legion status` - probes API or shows static info
    ├── Check              # `legion check` - smoke-test subsystems, 3 depth levels
    ├── Lex                # `legion lex` - list, info, create, enable, disable + LexGenerator
    ├── Task               # `legion task` - list, show, logs, trigger (mapped as run), purge
    ├── Chain              # `legion chain` - list, create, delete
    ├── Config             # `legion config` - show (redacted), path, validate, scaffold
    ├── ConfigScaffold     # `legion config scaffold` - generates starter JSON config files
    ├── Generate           # `legion generate` - runner, actor, exchange, queue, message
    ├── Mcp                # `legion mcp` - stdio (default) or HTTP transport
    ├── Worker             # `legion worker` - digital worker lifecycle management
    ├── Coldstart          # `legion coldstart` - ingest CLAUDE.md/MEMORY.md into lex-memory
    ├── Chat               # `legion chat` - interactive AI REPL + headless prompt mode
    │   ├── Session        # Multi-turn chat session with streaming
    │   ├── SessionStore   # Persistent session save/load/list/resume/fork
    │   ├── Permissions    # Tool permission model (interactive/auto_approve/read_only)
    │   ├── ToolRegistry   # Chat tool discovery and registration (10 built-in + extension tools)
    │   ├── ExtensionTool    # permission_tier DSL module for LEX chat tools (:read/:write/:shell)
    │   ├── ExtensionToolLoader # Lazy discovery of tools/ directories from loaded extensions
    │   ├── Context        # Project awareness (git, language, instructions, extra dirs)
    │   ├── MarkdownRenderer # Terminal markdown rendering with syntax highlighting
    │   ├── WebFetch       # /fetch slash command for web page context injection
    │   ├── WebSearch      # DuckDuckGo HTML scraping search engine
    │   ├── Checkpoint     # File edit checkpointing with /rewind undo
    │   ├── MemoryStore    # Persistent memory (project + global scopes, markdown files)
    │   ├── Subagent       # Background subagent spawning via headless subprocess
    │   ├── AgentRegistry  # Custom agent definitions from .legion/agents/ (JSON/YAML)
    │   ├── AgentDelegator # @name at-mention parsing and agent dispatch
    │   ├── ChatLogger     # Chat-specific logging
    │   └── Tools/         # Built-in tools: read_file, write_file, edit_file,
    │                      #   search_files, search_content, run_command,
    │                      #   save_memory, search_memory, web_search, spawn_agent
    ├── Memory             # `legion memory` - persistent memory CLI (list/add/forget/search)
    ├── Plan               # `legion plan` - read-only exploration mode
    ├── Swarm              # `legion swarm` - multi-agent workflow orchestration
    ├── Commit             # `legion commit` - AI-generated commit messages via LLM
    ├── Pr                 # `legion pr` - AI-generated PR title and description via LLM
    ├── Review             # `legion review` - AI code review with severity levels
    ├── Gaia               # `legion gaia` - Gaia status
    ├── Schedule           # `legion schedule` - schedule list/show/add/remove/logs
    └── Completion         # `legion completion` - bash/zsh tab completion scripts
```

### Extension Discovery

`Legion::Extensions.find_extensions` discovers lex-* gems via `Bundler.load.specs` (when running under Bundler) or falls back to `Gem::Specification.all_names`. It also processes `Legion::Settings[:extensions]` for explicitly configured extensions, attempting `Gem.install` for missing ones if `auto_install` is enabled.

**Role-based filtering**: After discovery, `apply_role_filter` prunes extensions based on `Legion::Settings[:role][:profile]`:

| Profile | What loads |
|---------|-----------|
| `nil` (default) | Everything — no filtering |
| `:core` | 14 core operational extensions only |
| `:cognitive` | core + all agentic extensions |
| `:service` | core + service + other integrations |
| `:dev` | core + AI + essential agentic (~20 extensions) |
| `:custom` | only what's listed in `role[:extensions]` |

Configure via settings JSON: `{"role": {"profile": "dev"}}`

Loader checks per extension:
- `data_required?` — skipped if legion-data not connected
- `cache_required?` — skipped if legion-cache not connected
- `crypt_required?` — skipped if cluster secret not available
- `vault_required?` — skipped if Vault not connected
- `llm_required?` — skipped if legion-llm not connected

After loading, each extension calls `autobuild` then publishes a `LexRegister` message to RabbitMQ to persist runners in the database.

### CLI Details

```
legion
  version                           # Component versions + installed extension count
  start [-d] [-p PID] [-l LOG] [-t SECS] [--log-level info] [--http-port PORT]
  stop [-p PID] [--signal INT]
  status
  check [--extensions] [--full]     # exit code 0/1

  lex
    list [-a]
    info <name>
    create <name>
    enable <name>
    disable <name>

  task
    list [-n 20] [-s status] [-e extension]
    show <id>
    logs <id> [-n 50]
    run <ext.runner.func> [key:val ...]  # 'run' is mapped to trigger method
    purge [--days 7] [-y]

  chain
    list [-n 20]
    create <name>
    delete <id> [-y]

  config
    show [-s section]
    path
    validate
    scaffold [--dir ./settings] [--only transport,data,...] [--full] [--force]

  generate (alias: g)
    runner <name> [--functions x]
    actor <name> [--type sub]
    exchange <name>
    queue <name>
    message <name>
    tool <name>

  mcp
    stdio                            # default
    http [--port 9393] [--host localhost]

  worker
    list [-s status] [-t risk_tier]
    show <id>
    pause <id>
    activate <id>
    retire <id>
    terminate <id>
    costs [--days 30]

  coldstart
    ingest <path>                    # file or directory, parses CLAUDE.md / MEMORY.md
    preview <path>                   # dry-run, shows traces without storing
    status

  chat                               # interactive AI REPL (requires legion-llm)
    prompt <text>                    # headless single-prompt mode (also accepts stdin pipe)
    [--model MODEL] [--provider PROVIDER]
    [--no_markdown] [--incognito]
    [--max_budget_usd N] [--auto_approve / -y]
    [--add_dir DIR ...] [--personality STYLE]
    [--continue / -c] [--resume NAME] [--fork NAME]
    # Slash commands:
    #   /help, /quit, /cost, /status, /clear, /new
    #   /save NAME, /load NAME, /sessions, /compact
    #   /fetch URL, /search QUERY, /diff, /copy
    #   /rewind [N|FILE], /memory [add TEXT]
    #   /agent TASK, /agents, /plan, /swarm NAME
    #   /review [SCOPE], /permissions [MODE], /personality STYLE
    #   /model X, /edit (open $EDITOR)
    #   /commit, /workers, /dream
    # Bang commands: !<shell command> (quick shell exec with context injection)
    # At-mentions: @agent_name <task> (delegate to custom agent)

  memory                             # persistent memory management
    list [--global]
    add TEXT [--global]
    forget INDEX [--global]
    search QUERY
    clear [--global] [-y]

  plan                               # read-only exploration mode (no writes/edits/shell)
    [--model MODEL] [--provider PROVIDER]
    # Slash commands: /save (writes plan to docs/plans/), /help, /quit

  swarm                              # multi-agent workflow orchestration
    start NAME                       # run a workflow from .legion/swarms/NAME.json
    list                             # list available workflows
    show NAME                        # show workflow details
    [--model MODEL]

  commit                             # AI-generated commit message via LLM
    [--model MODEL] [--provider PROVIDER]

  pr                                 # AI-generated PR title + description via LLM
    [--model MODEL] [--provider PROVIDER]
    [--base BRANCH] [--draft]

  review [FILES...]                  # AI code review with severity levels
    [--model MODEL] [--provider PROVIDER]
    [--diff]                         # review staged/unstaged diff instead of files

  gaia
    status                           # show Gaia system status

  schedule
    list
    show <id>
    add <name> <cron> <runner>
    remove <id>
    logs <id>

  completion
    bash                             # output bash completion script
    zsh                              # output zsh completion script
    install                          # print installation instructions
```

**CLI design rules:**
- Thor 1.5+ reserves `run` as a method name - use `map 'run' => :trigger` in Task subcommand
- `::Process` must be explicit inside `Legion::` namespace (resolves to `Legion::Process` otherwise)
- `Connection` is a module with class-level `ensure_*` methods, not instance-based
- All commands support `--json` and `--no-color` at the class_option level
- `::JSON` must be explicit inside `Legion::` namespace (resolves to `Legion::JSON` otherwise) — affects `pretty_generate` in config scaffold

### API Design

- Base class: `Legion::API < Sinatra::Base`
- All routes registered via `register Routes::ModuleName`
- Requires `set :host_authorization, permitted: :any` (Sinatra 4.0+, else all requests get 403)
- Response format: `{ data: ..., meta: { timestamp:, node: } }`
- Error format: `{ error: { code:, message: }, meta: { timestamp:, node: } }`
- `Legion::JSON.dump` takes exactly 1 positional arg — wrap kwargs in explicit `{}`
- `Legion::JSON.load` returns symbol keys
- Settings write: `Legion::Settings.loader.settings[:key] = value`
- `Legion::Settings.loader.to_hash` for full settings hash

### MCP Design

- Uses `mcp` gem (~> 0.8): `MCP::Server`, `MCP::Tool`, `MCP::Resource`
- Transports: `MCP::Server::Transports::StdioTransport`, `MCP::Server::Transports::StreamableHTTPTransport`
- HTTP transport uses rackup + puma
- `Legion::MCP.server` is memoized singleton — call `Legion::MCP.reset!` in tests
- Tool naming: `legion.snake_case_name` (dot namespace, not slash)

## Dependencies

### Runtime Gems
| Gem | Purpose |
|-----|---------|
| `legion-cache` (>= 0.3) | Caching (Redis/Memcached) |
| `legion-crypt` (>= 0.3) | Encryption, Vault, JWT |
| `legion-json` (>= 1.2) | JSON serialization (multi_json wrapper) |
| `legion-logging` (>= 0.3) | Logging |
| `legion-settings` (>= 0.3) | Configuration + schema validation |
| `legion-transport` (>= 1.2) | RabbitMQ AMQP messaging |
| `lex-node` | Node identity extension |
| `concurrent-ruby` + `ext` (>= 1.2) | Thread pool, concurrency primitives |
| `daemons` (>= 1.4) | Process daemonization |
| `bootsnap` (>= 1.18) | YARV bytecode + load-path caching |
| `oj` (>= 3.16) | Fast JSON (C extension) |
| `puma` (>= 6.0) | HTTP server for API |
| `mcp` (~> 0.8) | MCP server SDK |
| `reline` (>= 0.5) | Interactive line editing for chat REPL |
| `rouge` (>= 4.0) | Syntax highlighting for chat markdown rendering |
| `sinatra` (>= 4.0) | HTTP API framework |
| `thor` (>= 1.3) | CLI framework |

### Optional at Runtime (loaded dynamically)
| Gem | Purpose |
|-----|---------|
| `legion-data` | MySQL/SQLite persistence (tasks, extensions, scheduling) |
| `legion-llm` | LLM integration (Bedrock, Anthropic, OpenAI, Gemini, Ollama) |

### Dev Dependencies
```
rack-test, rake, rspec, rubocop, rubocop-rspec, simplecov
```

## File Map

| Path | Purpose |
|------|---------|
| `lib/legion.rb` | Entry point: `Legion.start`, `.shutdown`, `.reload` |
| `lib/legion/version.rb` | `Legion::VERSION` constant |
| `lib/legion/service.rb` | Module orchestrator, startup + shutdown + reload sequences |
| `lib/legion/process.rb` | Daemon lifecycle: PID management, daemonize, signal traps, main loop |
| `lib/legion/readiness.rb` | Component readiness tracking (COMPONENTS constant, `ready?`, `to_h`) |
| `lib/legion/events.rb` | In-process pub/sub: `on`, `emit`, `once`, `off`, wildcard `*` |
| `lib/legion/ingress.rb` | Universal runner invocation: `normalize`, `run` |
| `lib/legion/extensions.rb` | LEX discovery, loading, actor hooking, shutdown |
| `lib/legion/extensions/core.rb` | Extension mixin (requirement flags, autobuild) |
| `lib/legion/extensions/actors/` | Actor types: base, every, loop, once, poll, subscription, nothing, defaults |
| `lib/legion/extensions/builders/` | Build actors, runners, helpers, hooks from definitions |
| `lib/legion/extensions/helpers/` | Mixins: base, core, cache, data, logger, transport, task, lex |
| `lib/legion/extensions/data/` | Extension-level migrator and model |
| `lib/legion/extensions/hooks/base.rb` | Webhook hook base class |
| `lib/legion/extensions/transport.rb` | Extension transport setup |
| `lib/legion/runner.rb` | Task execution engine |
| `lib/legion/runner/log.rb` | Task logging |
| `lib/legion/runner/status.rb` | Task status tracking |
| `lib/legion/supervision.rb` | Process supervision |
| `lib/legion/lex.rb` | Legacy `Legion::Cli::LexBuilder` (preserved, not used by new CLI) |
| **API** | |
| `lib/legion/api.rb` | Sinatra base app, health/ready routes, error handlers, hook registry |
| `lib/legion/api/helpers.rb` | json_response, json_collection, json_error, pagination, redact_hash |
| `lib/legion/api/tasks.rb` | Tasks: list, create (via Ingress), show, delete, logs |
| `lib/legion/api/extensions.rb` | Extensions: nested REST (extensions/runners/functions + invoke) |
| `lib/legion/api/nodes.rb` | Nodes: list (filterable), show |
| `lib/legion/api/schedules.rb` | Schedules: CRUD + logs (requires lex-scheduler) |
| `lib/legion/api/relationships.rb` | Relationships: stub (501, no data model yet) |
| `lib/legion/api/chains.rb` | Chains: stub (501, no data model yet) |
| `lib/legion/api/settings.rb` | Settings: read/write with redaction + readonly guards |
| `lib/legion/api/events.rb` | Events: SSE stream + polling fallback (ring buffer) |
| `lib/legion/api/transport.rb` | Transport: status, exchanges, queues, publish |
| `lib/legion/api/hooks.rb` | Hooks: list registered + trigger via Ingress |
| `lib/legion/api/workers.rb` | Workers + Teams: digital worker lifecycle REST endpoints (`/api/workers/*`) and team cost endpoints (`/api/teams/*`) |
| `lib/legion/api/coldstart.rb` | Coldstart: `POST /api/coldstart/ingest` — triggers lex-coldstart ingest runner (requires lex-coldstart + lex-memory) |
| `lib/legion/api/gaia.rb` | Gaia: system status endpoints |
| `lib/legion/api/token.rb` | Token: JWT token issuance endpoint |
| `lib/legion/api/middleware/auth.rb` | Auth: JWT Bearer auth middleware (real token validation, skip paths for health/ready) |
| **MCP** | |
| `lib/legion/mcp.rb` | Entry point: `Legion::MCP.server` singleton factory |
| `lib/legion/mcp/server.rb` | MCP::Server builder, TOOL_CLASSES array, instructions |
| `lib/legion/digital_worker.rb` | DigitalWorker module entry point |
| `lib/legion/digital_worker/lifecycle.rb` | Worker state machine |
| `lib/legion/digital_worker/registry.rb` | In-process worker registry |
| `lib/legion/digital_worker/risk_tier.rb` | AIRB risk tier + governance constraints |
| `lib/legion/digital_worker/value_metrics.rb` | Token/cost/latency tracking |
| `lib/legion/mcp/tools/` | 30 MCP::Tool subclasses |
| `lib/legion/mcp/resources/runner_catalog.rb` | `legion://runners` resource |
| `lib/legion/mcp/resources/extension_info.rb` | `legion://extensions/{name}` resource template |
| **CLI v2** | |
| `lib/legion/cli.rb` | `Legion::CLI::Main` Thor app, global flags, version, start/stop/status/check |
| `lib/legion/cli/output.rb` | `Output::Formatter`: color, tables, JSON mode, ANSI stripping |
| `lib/legion/cli/connection.rb` | Lazy connection manager (`ensure_settings`, `ensure_transport`, etc.) |
| `lib/legion/cli/error.rb` | `CLI::Error` exception class |
| `lib/legion/cli/start.rb` | `legion start` — boots Legion::Process |
| `lib/legion/cli/status.rb` | `legion status` — probes API or returns static info |
| `lib/legion/cli/check_command.rb` | `legion check` — 3-level smoke test, exit code 0/1 |
| `lib/legion/cli/lex_command.rb` | `legion lex` subcommands + LexGenerator scaffolding |
| `lib/legion/cli/task_command.rb` | `legion task` subcommands (list, show, logs, trigger/run, purge) |
| `lib/legion/cli/chain_command.rb` | `legion chain` subcommands (list, create, delete) |
| `lib/legion/cli/config_command.rb` | `legion config` subcommands (show, path, validate, scaffold) |
| `lib/legion/cli/config_scaffold.rb` | `legion config scaffold` — generates starter JSON config files per subsystem |
| `lib/legion/cli/generate_command.rb` | `legion generate` subcommands (runner, actor, exchange, queue, message) |
| `lib/legion/cli/mcp_command.rb` | `legion mcp` subcommand (stdio + HTTP transports) |
| `lib/legion/cli/worker_command.rb` | `legion worker` subcommands (list, show, pause, retire, terminate, activate, costs) |
| `lib/legion/cli/coldstart_command.rb` | `legion coldstart` subcommands (ingest, preview, status) |
| `lib/legion/cli/chat_command.rb` | `legion chat` — interactive AI REPL + headless prompt mode |
| `lib/legion/cli/chat/session.rb` | Chat session: multi-turn conversation, streaming, tool use |
| `lib/legion/cli/chat/session_store.rb` | Session persistence: save, load, list, resume, fork |
| `lib/legion/cli/chat/permissions.rb` | Tool permission model (interactive/auto_approve/read_only) |
| `lib/legion/cli/chat/tool_registry.rb` | Chat tool discovery and registration (10 tools) |
| `lib/legion/cli/chat/extension_tool.rb` | permission_tier DSL module for extension chat tools |
| `lib/legion/cli/chat/extension_tool_loader.rb` | Lazy discovery engine: scans loaded extensions for tools/ directories |
| `lib/legion/cli/chat/context.rb` | Project awareness: git info, language detection, instructions, extra dirs |
| `lib/legion/cli/chat/markdown_renderer.rb` | Terminal markdown rendering with Rouge syntax highlighting |
| `lib/legion/cli/chat/web_fetch.rb` | `/fetch` slash command: fetches web page, extracts text for context |
| `lib/legion/cli/chat/web_search.rb` | DuckDuckGo HTML scraping search (parse results, extract URLs, auto-fetch) |
| `lib/legion/cli/chat/checkpoint.rb` | File edit checkpointing: save prior state, rewind (N steps, per-file) |
| `lib/legion/cli/chat/memory_store.rb` | Persistent memory: project (`.legion/memory.md`) + global (`~/.legion/memory/`) |
| `lib/legion/cli/chat/subagent.rb` | Background subagent spawning via `Open3.capture3` to `legion chat prompt` |
| `lib/legion/cli/chat/agent_registry.rb` | Custom agent definitions from `.legion/agents/*.json` and `.yaml` |
| `lib/legion/cli/chat/agent_delegator.rb` | `@name` at-mention parsing and dispatch via Subagent |
| `lib/legion/cli/chat/chat_logger.rb` | Chat-specific logging |
| `lib/legion/cli/chat/tools/` | Built-in tools: read_file, write_file, edit_file (string + line-number mode), search_files, search_content, run_command, save_memory, search_memory, web_search, spawn_agent |
| `lib/legion/cli/memory_command.rb` | `legion memory` subcommands (list, add, forget, search, clear) |
| `lib/legion/cli/plan_command.rb` | `legion plan` — read-only exploration mode with /save to docs/plans/ |
| `lib/legion/cli/swarm_command.rb` | `legion swarm` — multi-agent workflow orchestration from `.legion/swarms/` |
| `lib/legion/cli/commit_command.rb` | `legion commit` — AI-generated commit messages via LLM |
| `lib/legion/cli/pr_command.rb` | `legion pr` — AI-generated PR title + description via LLM |
| `lib/legion/cli/review_command.rb` | `legion review` — AI code review with severity levels (CRITICAL/WARNING/SUGGESTION/NOTE) |
| `lib/legion/cli/gaia_command.rb` | `legion gaia` subcommands (status) |
| `lib/legion/cli/schedule_command.rb` | `legion schedule` subcommands (list, show, add, remove, logs) |
| `lib/legion/cli/completion_command.rb` | `legion completion` subcommands (bash, zsh, install) |
| `completions/legion.bash` | Bash tab completion script |
| `completions/_legion` | Zsh tab completion script |
| `lib/legion/cli/theme.rb` | Purple palette, orbital ASCII banner, branded CLI output |
| **Legacy CLI (preserved, not loaded by new CLI)** | |
| `lib/legion/cli/task.rb` | Old task commands |
| `lib/legion/cli/trigger.rb` | Old trigger command |
| `lib/legion/cli/chain.rb` | Old chain commands |
| `lib/legion/cli/cohort.rb` | Old cohort commands |
| `lib/legion/cli/function.rb` | Old function commands |
| `lib/legion/cli/relationship.rb` | Old relationship commands |
| `lib/legion/cli/lex/` | Old LEX sub-generators + ERB templates (still used by LexGenerator) |
| **Executables** | |
| `exe/legion` | Executable: YJIT, GC tuning, bootsnap, then `Legion::CLI::Main.start(ARGV)` |
| `Dockerfile` | Docker build |
| `docker_deploy.rb` | Build + push Docker image |
| **Specs** | |
| `spec/spec_helper.rb` | RSpec configuration |

## Known Stubs / TODO

| Area | Status |
|------|--------|
| `API::Routes::Relationships` | Fully implemented (backed by legion-data migration 013) |
| `API::Routes::Chains` | 501 stub - no data model |
| `API::Middleware::Auth` | JWT Bearer auth middleware — real token validation and API key (`X-API-Key` header) auth both implemented |
| `legion-data` chains/relationships models | Not yet implemented |

## Rubocop Notes

- `.rubocop.yml` excludes `spec/**/*`, `legionio.gemspec`, `chat_command.rb`, `plan_command.rb`, `swarm_command.rb`, and `schedule_command.rb` from `Metrics/BlockLength`
- `chat_command.rb` also excluded from `Metrics/AbcSize`, `Metrics/MethodLength`, and `Metrics/CyclomaticComplexity` (large REPL loop + slash command dispatch)
- Hash alignment: `table` style enforced for both rocket and colon
- `Naming/PredicateMethod` disabled

## Development

```bash
bundle install
bundle exec rspec       # 880 examples, 0 failures
bundle exec rubocop     # 0 offenses
```

Specs use `rack-test` for API testing. `Legion::JSON.load` returns symbol keys — use `body[:data]` not `body['data']` in specs.

---

**Maintained By**: Matthew Iverson (@Esity)
