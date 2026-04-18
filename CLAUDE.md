# LegionIO: Async Job Engine and Task Framework

**Repository Level 3 Documentation**
- **Parent**: `../CLAUDE.md`

## Purpose

The primary gem for the LegionIO framework. An extensible async job engine for scheduling tasks, creating relationships between services, and running them concurrently via RabbitMQ. Orchestrates all `legion-*` gems and loads Legion Extensions (LEXs).

**GitHub**: https://github.com/LegionIO/LegionIO
**Gem**: `legionio`
**Version**: 1.8.12
**License**: Apache-2.0
**Docker**: `legionio/legion`
**Ruby**: >= 3.4

## Binary Split

| Binary | Purpose |
|--------|---------|
| `legion` | Interactive TTY shell + dev-workflow commands (chat, commit, review, plan, memory, init) |
| `legionio` | Daemon lifecycle + all operational commands (start, stop, lex, task, config, mcp, etc.) |

`legion` with no args launches the TTY interactive shell. With args, it routes to dev-workflow subcommands.
`legionio` is the full operational CLI — all 40+ subcommands.

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
      ├── 1.  setup_logging      (legion-logging)
      ├── 2.  setup_settings     (legion-settings, loads /etc/legionio, ~/legionio, ./settings)
      ├── 3.  Legion::Crypt.start (legion-crypt, Vault connection)
      ├── 4.  setup_transport    (legion-transport, RabbitMQ connection)
      ├── 5.  require legion-cache
      ├── 6.  setup_data         (legion-data, MySQL/SQLite + migrations, optional)
      ├── 7.  setup_rbac         (legion-rbac, optional)
      ├── 8.  setup_llm          (legion-llm, AI provider setup + routing, optional)
      ├── 9.  setup_apollo       (legion-apollo, shared + local knowledge store, optional)
      ├── 10. setup_gaia         (legion-gaia, cognitive coordination layer, optional)
      ├── 11. setup_telemetry    (OpenTelemetry, optional)
      ├── 12. setup_supervision  (process supervision)
      ├── 13. load_extensions    (multi-phase: phase 0 (identity providers) loads and hooks actors first, then phase 1 (everything else))
      ├── 14. Legion::Crypt.cs   (distribute cluster secret)
      └── 15. setup_api          (start Sinatra/Puma on port 4567)
```

Each phase calls `Legion::Readiness.mark_ready(:component)`. All phases are individually toggleable via `Service.new(transport: false, ...)`.

Extension loading is multi-phase and parallel: `hook_extensions` calls `group_by_phase` to partition discovered extensions by phase number (from the category registry), then iterates phases sequentially. Phase 0 contains identity providers (`lex-identity-*` gems, category `:identity`, tier 0); phase 1 contains all other extensions. Within each phase, extensions are `require`d and `autobuild` runs concurrently on a `Concurrent::FixedThreadPool(min(count, extensions.parallel_pool_size))`, collecting actors into a thread-safe `Concurrent::Array` of `@pending_actors`. Pool size defaults to 24, configurable via `Legion::Settings[:extensions][:parallel_pool_size]`. After each phase's extensions are loaded, `hook_phase_actors` starts AMQP subscriptions, timers, and other actor types for that phase sequentially — ensuring identity providers are fully running before any other extension boots. Catalog transitions (`transition(:running)` and `flush_persisted_transitions`) happen after all phases complete. Thread safety relies on ThreadLocal AMQP channels, per-extension Settings keys, and sequential post-processing of Catalog transitions and Registry writes.

### Reload Sequence

`Legion.reload` shuts down all subsystems in reverse order, waits for them to drain, then re-runs setup from settings onward. Extensions and API are re-loaded fresh.

### Module Structure

```
Legion (lib/legion.rb)
├── Service            # Orchestrator: initializes all modules, manages lifecycle
│                      # Entry points: Legion.start, .shutdown, .reload
├── Process            # Daemonization: PID management, signal traps (SIGINT=quit), main loop
├── Readiness          # Startup readiness tracking
│                      # COMPONENTS: settings, crypt, transport, cache, data, gaia, extensions, api
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
│   ├── Core           # Mixin: data_required?, cache_required?, crypt_required?, mcp_tools?, mcp_tools_deferred?, etc.
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
│   │   ├── Runners    # Build runners from extension definitions; exposes `runner_modules` accessor for Discovery
│   │   ├── Helpers    # Builder utilities
│   │   ├── Hooks      # Webhook hook system builder
│   │   └── Routes     # Auto-route builder: introspects runners, registers POST /api/extensions/* routes
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
│   │   ├── Relationships # CRUD (backed by legion-data migration 013)
│   │   ├── Chains     # Stub (501) - no data model yet
│   │   ├── Settings   # Read/write settings with redaction + readonly guards
│   │   ├── Events     # SSE stream (sinatra stream) + ring buffer polling fallback
│   │   ├── Transport  # Connection status, exchanges, queues, publish
│   │   ├── Hooks      # List + trigger registered extension hooks
│   │   ├── LexDispatch # Dispatch: `POST /api/extensions/:lex/:type/:component/:method` + discovery GET
│   │   ├── Workers    # Digital worker lifecycle (`/api/workers/*`) + team routes (`/api/teams/*`)
│   │   ├── Coldstart  # `POST /api/coldstart/ingest` — trigger lex-coldstart ingest from API
│   │   ├── Capacity   # Aggregate, forecast, per-worker capacity endpoints
│   │   ├── Tenants    # Tenant listing, provisioning, suspension, quota
│   │   ├── Audit      # Audit log query: list, show, count, export
│   │   ├── Rbac       # RBAC: role listing, permission grants, access checks
│   │   ├── Webhooks   # Webhook subscription CRUD + delivery status
│   │   └── Validators # Request body schema validation helpers
│   ├── Middleware/
│   │   ├── Auth       # JWT Bearer auth middleware (real validation, skip paths for health/ready)
│   │   ├── Tenant     # Tenant extraction from JWT/header, sets TenantContext
│   │   ├── ApiVersion # `/api/v1/` rewrite, Deprecation/Sunset headers
│   │   ├── BodyLimit  # Request body size limit (1MB max, returns 413)
│   │   └── RateLimit  # Sliding-window rate limiting with per-IP/agent/tenant tiers
│   └── router         # Class-level Router: extension_names, find_extension_route, registered_routes
│                      # Populated by Builders::Routes during autobuild via LexDispatch
│
├── MCP (legion-mcp gem)  # Extracted to standalone gem — see legion-mcp/CLAUDE.md
│   └── (tools, 2 resources, TierRouter, PatternStore, ContextGuard, Observer, EmbeddingIndex)
│
├── Tools              # Canonical tool layer — replaces Extensions::Capability and Catalog::Registry
│   ├── Base           # Base class for all framework tools (Do, Status, Config are built-in statics)
│   ├── Registry       # always/deferred classification for all tools; replaces Catalog::Registry
│   │                  # Extensions declare tools via `mcp_tools?` / `mcp_tools_deferred?` DSL on Core
│   ├── Discovery      # Auto-discovers tools from extension runner modules at boot
│   │                  # `runner_modules` accessor on Builders::Runners feeds Discovery
│   │                  # `loaded_extension_modules` on Extensions exposes the full set
│   └── EmbeddingCache # 5-tier persistent embedding cache:
│                      #   L0 in-memory hash → L1 Cache::Local → L2 Cache → L3 Data::Local → L4 Data
│
├── DigitalWorker      # Digital worker platform (AI-as-labor governance)
│   ├── Lifecycle      # Worker state machine (active/paused/retired/terminated)
│   ├── Registry       # In-process worker registry
│   ├── RiskTier       # AIRB risk tier classification + governance constraints
│   └── ValueMetrics   # Token/cost/latency value tracking
│
├── Graph              # Task relationship visualization
│   ├── Builder        # Builds adjacency graph from relationships table (chain/worker filtering)
│   └── Exporter       # Renders to Mermaid and DOT (Graphviz) formats
│
├── TraceSearch        # Natural language trace search via LLM structured output
│                      # Translates NL queries to safe JSON filter DSL (column allowlist)
│                      # Uses Legion::LLM.structured for JSON extraction
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
    ├── Lex                # `legion lex` - list, info, create, enable, disable, exec/invoke_ext + LexGenerator
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
    │   ├── ToolRegistry   # Chat tool discovery and registration (40 built-in tools + extension tools)
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
    │                      #   save_memory, search_memory, web_search, spawn_agent,
    │                      #   search_traces, query_knowledge, ingest_knowledge,
    │                      #   consolidate_memory, relate_knowledge, knowledge_maintenance,
    │                      #   knowledge_stats, summarize_traces, list_extensions,
    │                      #   manage_tasks, system_status, view_events
    ├── Memory             # `legion memory` - persistent memory CLI (list/add/forget/search)
    ├── Plan               # `legion plan` - read-only exploration mode
    ├── Swarm              # `legion swarm` - multi-agent workflow orchestration
    ├── Commit             # `legion commit` - AI-generated commit messages via LLM
    ├── Pr                 # `legion pr` - AI-generated PR title and description via LLM
    ├── Review             # `legion review` - AI code review with severity levels
    ├── Gaia               # `legion gaia` - Gaia status
    ├── Llm                # `legion llm` - LLM subsystem status and provider health
    ├── Detect             # `legion detect scan` - scan environment and recommend extensions
    ├── Observe            # `legion observe stats` - MCP tool usage statistics from Observer
    ├── Tty                # `legion tty interactive` - launch rich terminal UI (legion-tty)
    ├── Graph              # `legion graph show` - task relationship graph (mermaid/dot)
    ├── Trace              # `legion trace search` - NL trace search via LLM
    ├── Dashboard          # `legion dashboard` - TUI operational dashboard with auto-refresh
    │   ├── DataFetcher    # Polls REST API for workers, health, events
    │   └── Renderer       # Terminal-based dashboard rendering
    ├── Cost               # `legion cost` - cost summary, worker, team, top, budget, export
    │   └── DataClient     # API client for cost data aggregation
    ├── Skill              # `legion skill` - list, show, create, run skill files
    ├── Audit              # `legion audit` - query audit log (list, show, count, export)
    ├── Rbac               # `legion rbac` - role management, permission grants, access check
    ├── Init               # `legion init` - interactive project setup wizard
    │   ├── ConfigGenerator    # Generates starter config files from templates
    │   └── EnvironmentDetector # Detects runtime environment (Docker, CI, services)
    ├── Marketplace        # `legion marketplace` - extension marketplace (search, install, publish)
    ├── Notebook           # `legion notebook` - interactive task notebook REPL
    ├── Update             # `legion update` - self-update via Homebrew or gem
    ├── Schedule           # `legion schedule` - schedule list/show/add/remove/logs
    └── Completion         # `legion completion` - bash/zsh tab completion scripts
```

### Extension Discovery

`Legion::Extensions.find_extensions` discovers lex-* gems via `Bundler.load.specs` (when running under Bundler) or falls back to `Gem::Specification.all_names`. It also processes `Legion::Settings[:extensions]` for explicitly configured extensions, attempting `Gem.install` for missing ones if `auto_install` is enabled.

**Category registry**: Extensions are classified by `categorize_and_order` using `default_category_registry`. Each category has a `type` (`:list` or `:prefix`), `tier` (load order within a phase), and `phase`:

| Category | Type | Tier | Phase | Matches |
|----------|------|------|-------|---------|
| `identity` | prefix | 0 | 0 | `lex-identity-*` gems |
| `core` | list | 1 | 1 | explicitly listed core extensions |
| `ai` | list | 2 | 1 | explicitly listed AI provider extensions |
| `gaia` | list | 3 | 1 | explicitly listed GAIA extensions |
| `agentic` | prefix | 4 | 1 | `lex-agentic-*` gems |

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
    create <name> --entra_app_id ID --owner_msid EMAIL --extension NAME [--team T] [--client_secret S]
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
    # Slash commands: /save (writes plan to docs/work/planning/), /help, /quit

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

  openapi
    generate [-o FILE]               # output OpenAPI 3.1.0 spec JSON
    routes                           # list all API routes with HTTP method + summary

  doctor [--fix] [--json]            # diagnose environment, suggest/apply fixes
                                     # checks: Ruby, bundle, config, RabbitMQ, DB, cache, Vault,
                                     #   extensions, PID files, permissions
                                     # exit 0=all pass, 1=any fail

  telemetry
    stats [SESSION_ID]               # aggregate or per-session telemetry stats
    ingest PATH                      # manually ingest a session log file

  graph
    show [--chain ID] [--worker ID]  # display task relationship graph
    [--format mermaid|dot] [--output FILE] [--limit N]

  trace
    search QUERY [--limit N]         # natural language trace search via LLM

  dashboard
    start [--url URL] [--refresh N]  # TUI operational dashboard with auto-refresh

  cost
    summary                          # overall cost summary (today/week/month)
    worker <id>                      # per-worker cost breakdown
    team <name>                      # per-team cost attribution
    top [--limit 10]                 # top cost consumers
    budget                           # budget status
    export [--format csv|json]       # export cost data

  skill
    list                             # list discovered skills
    show <name>                      # display skill definition
    create <name>                    # scaffold new skill file
    run <name> [args]                # run skill outside of chat

  audit
    list [--entity TYPE] [--action ACT] [--limit N]
    show <id>
    count [--entity TYPE] [--since TIME]
    export [--format json|csv]

  rbac
    roles                            # list roles
    grants <identity>                # list grants for identity
    check <identity> <resource> <action>  # check access

  init                               # interactive project setup wizard
    [--dir PATH] [--template NAME]

  marketplace
    search QUERY                     # search extension marketplace
    install NAME                     # install extension
    publish                          # publish current extension

  notebook                           # interactive task notebook REPL

  update                             # self-update via Homebrew or gem

  auth
    teams [--tenant-id ID] [--client-id ID]  # browser OAuth flow for Microsoft Teams
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

Extracted to the `legion-mcp` gem (v0.7.3). See `legion-mcp/CLAUDE.md` for full architecture.

- `Legion::MCP.server` is memoized singleton — call `Legion::MCP.reset!` in tests
- Tool naming: `legion.snake_case_name` (dot namespace, not slash)
- Tier 0 routing: PatternStore + TierRouter + ContextGuard for LLM-free cached responses

### Lite Mode

`LEGION_MODE=lite` (or `--lite` CLI flag, or `:lite` ProcessRole) launches LegionIO without RabbitMQ, Redis, or Memcached:

- `legion-transport` activates the `InProcess` adapter (stub Session/Channel/Exchange/Queue/Consumer that delegate to `Transport::Local` in-memory pub/sub)
- `legion-cache` activates the `Memory` adapter (pure in-memory cache with TTL expiry and Mutex synchronization)
- Useful for single-machine development, CI, and testing without infrastructure dependencies
- Detection: `Connection.lite_mode?` checks `TYPE == 'local'`; cache checks `LEGION_MODE=lite` env var

### `legion do`

Natural-language intent router at the CLI level:

```bash
legion do "list all running tasks"
legion do "start the email extension"
```

Resolves free-text intent to Capability Registry entries. If the daemon is running, delegates to the MCP `legion.do` tool (Tier 0 fast path). If no daemon, runs in-process. Returns the runner's response.

### `legion mind-growth`

CLI for the autonomous cognitive architecture expansion system (`lex-mind-growth`). 10 subcommands:

```bash
legion mind-growth status           # current growth cycle state
legion mind-growth analyze          # gap analysis against 5 reference models
legion mind-growth propose          # propose a new concept
legion mind-growth evaluate <id>    # evaluate a proposal
legion mind-growth build <id>       # run staged build pipeline
legion mind-growth list             # list proposals
legion mind-growth approve <id>     # manually approve
legion mind-growth reject <id>      # manually reject
legion mind-growth profile          # cognitive profile across all models
legion mind-growth health           # extension fitness validation
```

Requires `lex-mind-growth` to be loaded. Also exposes 6 MCP tools in the `legion.mind_growth_*` namespace via `legion-mcp`.

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
| `rackup` (>= 2.0) | Rack server launcher for MCP HTTP transport |
| `legion-mcp` (>= 0.5) | MCP server + Tier 0 routing (extracted gem) |
| `reline` (>= 0.5) | Interactive line editing for chat REPL |
| `rouge` (>= 4.0) | Syntax highlighting for chat markdown rendering |
| `tty-spinner` (~> 0.9) | Spinner animation for CLI loading states |
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
| `lib/legion/extensions.rb` | LEX discovery, loading, actor hooking, shutdown; exposes `loaded_extension_modules` for Tools::Discovery |
| `lib/legion/extensions/core.rb` | Extension mixin (requirement flags, autobuild) |
| `lib/legion/extensions/actors/` | Actor types: base, every, loop, once, poll, subscription, nothing, defaults |
| `lib/legion/extensions/builders/` | Build actors, runners, helpers, hooks, routes from definitions |
| `lib/legion/extensions/helpers/` | Mixins: base, core, cache, data, logger, transport, task, lex |
| `lib/legion/extensions/data/` | Extension-level migrator and model |
| `lib/legion/extensions/hooks/base.rb` | Webhook hook base class |
| `lib/legion/extensions/transport.rb` | Extension transport setup |
| `lib/legion/graph/builder.rb` | Graph builder: adjacency list from relationships table with chain/worker filtering |
| `lib/legion/graph/exporter.rb` | Graph exporter: renders to Mermaid (`graph TD`) and DOT (Graphviz `digraph`) formats |
| `lib/legion/trace_search.rb` | NL trace search: LLM structured output to JSON filter DSL with column allowlist |
| `lib/legion/guardrails.rb` | Input validation guardrails for runner payloads |
| `lib/legion/isolation.rb` | Process isolation for untrusted extension execution |
| `lib/legion/sandbox.rb` | Sandboxed execution environment for extensions |
| `lib/legion/context.rb` | Thread-local execution context (request tracing, tenant) |
| `lib/legion/catalog.rb` | Extension catalog: registry of available extensions with metadata (Catalog::Registry removed — replaced by Tools::Registry) |
| `lib/legion/tools.rb` | Tools module entry point |
| `lib/legion/tools/base.rb` | Tools::Base — canonical base class for all tools |
| `lib/legion/tools/registry.rb` | Tools::Registry — always/deferred classification, replaces Catalog::Registry |
| `lib/legion/tools/discovery.rb` | Tools::Discovery — auto-discovers tools from extension runner_modules at boot |
| `lib/legion/tools/embedding_cache.rb` | Tools::EmbeddingCache — 5-tier persistent embedding cache (L0–L4) |
| `lib/legion/registry.rb` | Extension registry with security scanning |
| `lib/legion/registry/security_scanner.rb` | Gem security scanner (CVE checks, signature verification) |
| `lib/legion/webhooks.rb` | Webhook delivery system: HTTP POST with retry, HMAC signing |
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
| `lib/legion/api/relationships.rb` | Relationships: CRUD (backed by legion-data migration 013) |
| `lib/legion/api/chains.rb` | Chains: stub (501, no data model yet) |
| `lib/legion/api/settings.rb` | Settings: read/write with redaction + readonly guards |
| `lib/legion/api/events.rb` | Events: SSE stream + polling fallback (ring buffer) |
| `lib/legion/api/transport.rb` | Transport: status, exchanges, queues, publish |
| `lib/legion/api/lex_dispatch.rb` | LexDispatch: `POST /api/extensions/:lex/:type/:component/:method` dispatch + `GET` discovery; remote AMQP forwarding, hook-aware routing via `Routes::LexDispatch` |
| `lib/legion/api/workers.rb` | Workers + Teams: digital worker lifecycle REST endpoints (`/api/workers/*`) and team cost endpoints (`/api/teams/*`) |
| `lib/legion/api/coldstart.rb` | Coldstart: `POST /api/coldstart/ingest` — triggers lex-coldstart ingest runner (requires lex-coldstart + lex-memory) |
| `lib/legion/api/gaia.rb` | Gaia: system status endpoints |
| `lib/legion/api/token.rb` | Token: JWT token issuance endpoint |
| `lib/legion/api/openapi.rb` | OpenAPI: `Legion::API::OpenAPI.spec` / `.to_json`; also served at `GET /api/openapi.json` |
| `lib/legion/api/capacity.rb` | Capacity: aggregate, forecast, and per-worker capacity endpoints |
| `lib/legion/api/tenants.rb` | Tenants: listing, provisioning, suspension, quota check |
| `lib/legion/api/catalog.rb` | Catalog: extension catalog with metadata endpoints |
| `lib/legion/api/llm.rb` | LLM: provider status and routing configuration endpoints |
| `lib/legion/api/audit.rb` | Audit: list, show, count, export audit log entries |
| `lib/legion/api/auth.rb` | Auth: combined token exchange endpoint (`POST /api/auth/token` — JWKS verify + RBAC claims mapper) |
| `lib/legion/api/auth_human.rb` | Auth: human user authentication endpoints |
| `lib/legion/api/auth_worker.rb` | Auth: digital worker authentication endpoints |
| `lib/legion/api/rbac.rb` | RBAC: role listing, permission grants, access checks |
| `lib/legion/api/validators.rb` | Request validators: schema validation helpers for API inputs |
| `lib/legion/api/webhooks.rb` | Webhooks: CRUD for webhook subscriptions + delivery status |
| `lib/legion/audit.rb` | Audit logging: AMQP publish + query layer (recent_for, count_for, resources_for, recent) backed by AuditLog model |
| `lib/legion/audit/hash_chain.rb` | Tamper-evident hash chain for audit entries |
| `lib/legion/audit/siem_export.rb` | SIEM export: format audit entries for Splunk/ELK ingestion |
| `lib/legion/alerts.rb` | Configurable alerting rules engine: pattern matching, count conditions, cooldown dedup |
| `lib/legion/telemetry.rb` | Opt-in OpenTelemetry tracing: `with_span` wrapper, `sanitize_attributes`, `record_exception` |
| `lib/legion/metrics.rb` | Opt-in Prometheus metrics: event-driven counters, pull-based gauges, `prometheus-client` guarded |
| `lib/legion/api/metrics.rb` | `GET /metrics` Prometheus text-format endpoint with gauge refresh |
| `lib/legion/api/stats.rb` | `GET /api/stats` comprehensive daemon runtime stats (extensions, gaia, transport, cache, llm, data, api) |
| `lib/legion/chat/notification_queue.rb` | Thread-safe priority queue for background notifications (critical/info/debug) |
| `lib/legion/chat/notification_bridge.rb` | Event-driven bridge: matches Legion events to chat notifications via fnmatch patterns |
| `lib/legion/api/middleware/auth.rb` | Auth: JWT Bearer auth middleware (real token validation, skip paths for health/ready) |
| `lib/legion/api/middleware/api_version.rb` | ApiVersion: rewrites `/api/v1/` to `/api/`, adds Deprecation/Sunset headers on unversioned paths |
| `lib/legion/api/middleware/body_limit.rb` | BodyLimit: request body size limit (1MB max, returns 413) |
| `lib/legion/api/middleware/rate_limit.rb` | RateLimit: sliding-window rate limiting with per-IP/agent/tenant tiers |
| `lib/legion/api/middleware/tenant.rb` | Tenant: extracts tenant_id from JWT/header, sets TenantContext per request |
| `lib/legion/tenant_context.rb` | Thread-local tenant context propagation (set, clear, with block) |
| `lib/legion/tenants.rb` | Tenant CRUD, suspension, quota enforcement |
| `lib/legion/capacity/model.rb` | Workforce capacity calculation (throughput, utilization, forecast, per-worker) |
| **MCP** (extracted to `legion-mcp` gem) | |
| `lib/legion/digital_worker.rb` | DigitalWorker module entry point |
| `lib/legion/digital_worker/lifecycle.rb` | Worker state machine |
| `lib/legion/digital_worker/registry.rb` | In-process worker registry |
| `lib/legion/digital_worker/risk_tier.rb` | AIRB risk tier + governance constraints |
| `lib/legion/digital_worker/value_metrics.rb` | Token/cost/latency tracking |
| **CLI v2** | |
| `lib/legion/cli.rb` | `Legion::CLI::Main` Thor app, global flags, version, start/stop/status/check |
| `lib/legion/cli/output.rb` | `Output::Formatter`: color, tables, JSON mode, ANSI stripping |
| `lib/legion/cli/connection.rb` | Lazy connection manager (`ensure_settings`, `ensure_transport`, etc.) |
| `lib/legion/cli/error.rb` | `CLI::Error` exception class |
| `lib/legion/cli/start.rb` | `legion start` — boots Legion::Process |
| `lib/legion/cli/status.rb` | `legion status` — probes API or returns static info |
| `lib/legion/cli/check_command.rb` | `legion check` — 3-level smoke test, exit code 0/1 |
| `lib/legion/cli/lex_command.rb` | `legion lex` subcommands + LexGenerator scaffolding + `invoke_ext`/`exec` dispatch via LexCliManifest |
| `lib/legion/cli/lex_cli_manifest.rb` | JSON manifest cache for LEX CLI commands (alias resolution, staleness check) |
| `lib/legion/cli/task_command.rb` | `legion task` subcommands (list, show, logs, trigger/run, purge) |
| `lib/legion/cli/chain_command.rb` | `legion chain` subcommands (list, create, delete) |
| `lib/legion/cli/config_command.rb` | `legion config` subcommands (show, path, validate, scaffold) |
| `lib/legion/cli/config_scaffold.rb` | `legion config scaffold` — generates starter JSON config files per subsystem |
| `lib/legion/cli/generate_command.rb` | `legion generate` subcommands (runner, actor, exchange, queue, message) |
| `lib/legion/cli/mcp_command.rb` | `legion mcp` subcommand (stdio + HTTP transports) |
| `lib/legion/cli/worker_command.rb` | `legion worker` subcommands (list, show, create, pause, retire, terminate, activate, costs) |
| `lib/legion/cli/coldstart_command.rb` | `legion coldstart` subcommands (ingest, preview, status) |
| `lib/legion/cli/chat_command.rb` | `legion chat` — interactive AI REPL + headless prompt mode |
| `lib/legion/cli/chat/session.rb` | Chat session: multi-turn conversation, streaming, tool use |
| `lib/legion/cli/chat/session_store.rb` | Session persistence: save, load, list, resume, fork |
| `lib/legion/cli/chat/permissions.rb` | Tool permission model (interactive/auto_approve/read_only) |
| `lib/legion/cli/chat/tool_registry.rb` | Chat tool discovery and registration (40 tools) |
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
| `lib/legion/cli/chat/context_manager.rb` | Context window management: dedup, compression, summarization strategies |
| `lib/legion/cli/chat/progress_bar.rb` | Progress bar rendering for long operations |
| `lib/legion/cli/chat/status_indicator.rb` | Status indicator (spinner, checkmark, cross) |
| `lib/legion/cli/chat/team.rb` | Multi-user team support for chat sessions |
| `lib/legion/cli/chat/tools/` | 40 built-in tools: read_file, write_file, edit_file, search_files, search_content, run_command, save_memory, search_memory, web_search, spawn_agent, search_traces, query_knowledge, ingest_knowledge, consolidate_memory, relate_knowledge, knowledge_maintenance, knowledge_stats, summarize_traces, list_extensions, manage_tasks, system_status, view_events, cost_summary, reflect, manage_schedules, worker_status, detect_anomalies, view_trends, trigger_dream, generate_insights, budget_status, provider_health, model_comparison, shadow_eval_status, entity_extract, arbitrage_status, escalation_status, graph_explore, scheduling_status, memory_status |
| `lib/legion/chat/skills.rb` | Skill discovery: parses `.legion/skills/` and `~/.legionio/skills/` YAML frontmatter files |
| `lib/legion/cli/graph_command.rb` | `legion graph` subcommands (show with --format mermaid\|dot, --chain, --output) |
| `lib/legion/cli/trace_command.rb` | `legion trace search` — NL trace search via LLM |
| `lib/legion/cli/dashboard_command.rb` | `legion dashboard` — TUI operational dashboard |
| `lib/legion/cli/dashboard/data_fetcher.rb` | Dashboard API poller: workers, health, events |
| `lib/legion/cli/dashboard/renderer.rb` | Dashboard terminal renderer with sections |
| `lib/legion/cli/cost_command.rb` | `legion cost` — cost summary, worker, team, top, budget, export |
| `lib/legion/cli/cost/data_client.rb` | Cost data aggregation API client |
| `lib/legion/cli/skill_command.rb` | `legion skill` — list, show, create, run skill files |
| `lib/legion/cli/audit_command.rb` | `legion audit` — query audit log (list, show, count, export) |
| `lib/legion/cli/rbac_command.rb` | `legion rbac` — role management, permission grants, access checks |
| `lib/legion/cli/init_command.rb` | `legion init` — interactive project setup wizard |
| `lib/legion/cli/init/config_generator.rb` | Config file generation from templates |
| `lib/legion/cli/init/environment_detector.rb` | Runtime environment detection (Docker, CI, services) |
| `lib/legion/cli/marketplace_command.rb` | `legion marketplace` — extension search, install, publish |
| `lib/legion/cli/notebook_command.rb` | `legion notebook` — interactive task notebook REPL |
| `lib/legion/cli/update_command.rb` | `legion update` — self-update via Homebrew or gem |
| `lib/legion/cli/lex_templates.rb` | LEX scaffold templates for generator |
| `lib/legion/cli/version.rb` | CLI version display helper |
| `lib/legion/docs/site_generator.rb` | Static documentation site generator |
| `lib/legion/cli/memory_command.rb` | `legion memory` subcommands (list, add, forget, search, clear) |
| `lib/legion/cli/plan_command.rb` | `legion plan` — read-only exploration mode with /save to docs/work/planning/ |
| `lib/legion/cli/swarm_command.rb` | `legion swarm` — multi-agent workflow orchestration from `.legion/swarms/` |
| `lib/legion/cli/commit_command.rb` | `legion commit` — AI-generated commit messages via LLM |
| `lib/legion/cli/pr_command.rb` | `legion pr` — AI-generated PR title + description via LLM |
| `lib/legion/cli/review_command.rb` | `legion review` — AI code review with severity levels (CRITICAL/WARNING/SUGGESTION/NOTE) |
| `lib/legion/cli/gaia_command.rb` | `legion gaia` subcommands (status) |
| `lib/legion/cli/llm_command.rb` | `legion llm` subcommands (status) — LLM subsystem status and provider health |
| `lib/legion/cli/detect_command.rb` | `legion detect scan` — scan environment and recommend extensions |
| `lib/legion/cli/observe_command.rb` | `legion observe stats` — MCP tool usage statistics from Observer |
| `lib/legion/cli/tty_command.rb` | `legion tty interactive` — launch rich terminal UI (legion-tty interactive shell) |
| `lib/legion/cli/interactive.rb` | `Interactive` Thor class — shared CLI module for `legion` binary entry point |
| `lib/legion/cli/config_import.rb` | `legion config import` — import config from external sources |
| `lib/legion/cli/schedule_command.rb` | `legion schedule` subcommands (list, show, add, remove, logs) |
| `lib/legion/cli/completion_command.rb` | `legion completion` subcommands (bash, zsh, install) |
| `lib/legion/cli/openapi_command.rb` | `legion openapi` subcommands (generate, routes); also `GET /api/openapi.json` endpoint |
| `lib/legion/cli/doctor_command.rb` | `legion doctor` — 11-check environment diagnosis; `Doctor::Result` value object with status/message/prescription/auto_fixable |
| `lib/legion/cli/doctor/` | Individual check modules: ruby_version, bundle, config, rabbitmq, database, cache, vault, extensions, pid, permissions, plus result.rb |
| `lib/legion/cli/telemetry_command.rb` | `legion telemetry` subcommands (stats, ingest) — session log analytics |
| `lib/legion/cli/auth_command.rb` | `legion auth` subcommands (teams) — delegated OAuth browser flow for external services |
| `lib/legion/cli/admin_command.rb` | `legion admin` subcommands (purge-topology) — ops tooling for v2.0 AMQP topology cleanup |
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
bundle exec rspec       # ~3500+ examples, 0 failures
bundle exec rubocop     # 0 offenses
```

**Always run a full `bundle exec rspec` and `bundle exec rubocop -A` and fix all errors before committing.**

Specs use `rack-test` for API testing. `Legion::JSON.load` returns symbol keys — use `body[:data]` not `body['data']` in specs.

---

**Maintained By**: Matthew Iverson (@Esity)
