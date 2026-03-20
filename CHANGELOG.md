# Legion Changelog

## [1.4.77] - 2026-03-19

### Added
- Hardcoded deny list in `Extensions::Permissions` blocking access to `~/.ssh`, `~/.gnupg`, `~/.aws/credentials`
- Deny list overrides all other permission checks including explicit approvals

## [1.4.76] - 2026-03-19

### Added
- `Hooks::Base.mount(path)` DSL for extension-derived URL suffixes (e.g., `/callback`)
- `GET /api/hooks/lex/*` splat route for hook discovery via GET requests
- `POST /api/hooks/lex/*` splat route with `route_path`-based hook dispatch
- `Legion::API.find_hook_by_path(path)` for direct route-path lookup in hook registry
- `route_path` field stored in hook registry entries and returned in `GET /api/hooks` listing
- Runner-controlled responses: `result[:response]` hash with `:status`, `:content_type`, `:body`
- `build_payload`, `dispatch_hook`, `render_custom_response` extracted helpers in Routes::Hooks

### Changed
- `register_hook` now accepts `route_path:` keyword; defaults to `lex_name/hook_name` if omitted
- `builders/hooks.rb` computes `route_path` from `extension_name/hook_name + mount_path`
- `extensions/core.rb` passes `route_path:` when calling `Legion::API.register_hook`
- `GET /api/hooks` listing now includes `route_path` and updated `endpoint` field
- Removed `Routes::OAuth` (moved OAuth callback to lex-microsoft_teams hook with mount path)
- `handle_hook_request` refactored into smaller helpers to stay within complexity limits

## [1.4.75] - 2026-03-19

### Added
- `Legion::Extensions::Catalog` singleton state machine tracking extension lifecycle (registered/loaded/starting/running/stopping/stopped)
- `Legion::Extensions::Permissions` three-layer file permission model (sandbox, declared paths, auto-approve globs)
- `GET /api/catalog` and `GET /api/catalog/:name` extension capability manifest endpoints
- Tier 0 routing in `POST /api/llm/chat` via `Legion::MCP::TierRouter` for LLM-free cached responses
- Data::Local migrations for extension_catalog and extension_permissions tables
- Catalog lifecycle wired into extension loader (register/loaded/running/stopping/stopped transitions)

## [1.4.74] - 2026-03-19

### Changed
- Extracted `Legion::MCP` to dedicated `legion-mcp` gem (v0.1.0)
- Replaced `mcp` gem dependency with `legion-mcp`

## [1.4.73] - 2026-03-19

### Added
- TBI Phase 3: semantic tool retrieval via embedding vectors
- `Legion::MCP::EmbeddingIndex` module: in-memory embedding cache with pure-Ruby cosine similarity
- `ContextCompiler` semantic score blending: 60% semantic + 40% keyword when embeddings available, keyword-only fallback
- `Server.populate_embedding_index`: auto-populates tool embeddings on MCP server build (no-op if LLM unavailable)
- `legion observe embeddings` subcommand: index size, coverage, and populated status
- 61 new specs (1666 total): EmbeddingIndex unit, ContextCompiler semantic blending, integration wiring, CLI

## [1.4.72] - 2026-03-19

### Added
- TBI Phase 0+2: MCP tool observation pipeline and usage-based filtering
- `Legion::MCP::Observer` module: in-memory tool call recording with counters, ring buffer, and intent tracking
- `Legion::MCP::UsageFilter` module: scores tools by frequency, recency, and keyword match; prunes dead tools
- MCP `instrumentation_callback` wiring: automatically records all `tools/call` invocations via Observer
- MCP `tools_list_handler` wiring: dynamically filters and ranks tools per-request based on usage data
- `legion observe` CLI command: `stats`, `recent`, `reset` subcommands for MCP tool usage inspection
- 96 new specs covering Observer, UsageFilter, CLI command, and integration wiring

## [1.4.71] - 2026-03-19

### Added
- `POST /api/llm/chat` daemon endpoint with async (202) and sync (201) response paths
- `ContextCompiler` module: categorizes 35 MCP tools into 9 groups with keyword matching
- `legion.do` meta-tool: natural language intent routing to best-matching MCP tool
- `legion.tools` meta-tool: compressed catalog, category browsing, and intent-matched discovery

### Fixed
- `ContextCompiler.build_tool_index` now handles `MCP::Tool::InputSchema` objects (not just hashes)

## [1.4.70] - 2026-03-19

### Added
- GAIA cognitive layer as a core boot phase: `setup_gaia` runs between LLM and telemetry in the startup sequence
- Two-phase extension loading: all extensions are fully loaded (require + autobuild) before any actors are hooked (AMQP subscriptions, timers, etc.), preventing race conditions during boot
- `gaia: true` parameter on `Service.new` to control GAIA initialization
- GAIA graceful shutdown and reload support (shuts down before extensions, restarts after data)

### Changed
- Boot order is now deterministic: Logging -> Settings -> Crypt -> Transport -> Cache -> Data -> RBAC -> LLM -> GAIA -> Telemetry -> Extensions -> API
- Extension actors are collected into `@pending_actors` during `load_extensions`, then started all at once via `hook_all_actors`

## [1.4.69] - 2026-03-19

### Fixed
- Constant resolution bug in transport/subscription layers: `const_defined?` and `const_get` now pass `inherit: false` to prevent Ruby from finding top-level gem constants (`::Redis`, `::Vault`, `::Data`) through `Object` when checking dynamically created `Module.new` namespaces (`Transport::Exchanges`, `Transport::Queues`)
- `Subscription#queue` now uses `queues.const_get(actor_const, false)` instead of `Kernel.const_get(queue_string)` to search only the Queues module's own constants
- Added `llm-gateway` to `core_extension_names` so it is included under `:core` role profile
- `build_extension_entry` now forces nesting for multi-segment gem names (e.g. `lex-llm-gateway`) to produce correct require paths regardless of call-site `nesting:` argument

## [1.4.68] - 2026-03-19

### Added
- `legionio llm` subcommand for LLM provider diagnostics
  - `llm status` (default) — show LLM state, enabled providers, routing, system memory
  - `llm providers` — list all providers with enabled/disabled and reachability status
  - `llm models` — list available models per enabled provider (Ollama discovery + cloud defaults)
  - `llm ping` — test connectivity to each enabled provider with latency measurement
  - All subcommands support `--json` output
- `legionio version` now shows legion-llm, legion-gaia, and legion-tty in components list
- `legionio version --json` now includes components hash and extension count

### Fixed
- `legionio update` now correctly detects gem version changes (was showing "already latest" for every gem due to stale in-memory gem spec cache after subprocess install)

## [1.4.67] - 2026-03-18

### Added
- `legionio detect` subcommand — scan environment and recommend extensions (requires lex-detect gem)
  - `detect scan` (default) — show detected software and recommended extensions
  - `detect catalog` — show full detection catalog
  - `detect missing` — list extensions that should be installed
  - `--install` flag to install missing extensions after scan
  - `--json` output mode
- `legionio update` now suggests new extensions via lex-detect after updating gems

## [1.4.66] - 2026-03-18

### Fixed
- Doctor config check now looks in `~/.legionio/settings` (the actual default settings directory)
- Doctor permissions check now checks `~/.legionio/` directories instead of `/var/run`

## [1.4.65] - 2026-03-18

### Fixed
- Remove local path references from Gemfile (40 sibling repo paths)

## [1.4.64] - 2026-03-18

### Fixed
- Remove legacy `exe/legion-tty` from legionio gem (conflicts with legion-tty gem executable)
- Explicitly list executables as `legion` and `legionio` in gemspec instead of glob pattern

## [1.4.63] - 2026-03-18

### Added
- `legionio config import SOURCE` command for importing config from URL or local file
- Supports raw JSON and base64-encoded JSON payloads
- Deep merges with existing `~/.legionio/settings/imported.json` (or `--force` to overwrite)
- Displays imported sections and vault cluster count

## [1.4.62] - 2026-03-18

### Added
- `legionio` binary for daemon and operational CLI
- `Legion::CLI::Interactive` Thor class for dev-workflow commands (chat, commit, pr, review, memory, plan, init, tty)
- `legion-tty` as runtime dependency
- Shell completions for both `legion` and `legionio` binaries

### Changed
- `exe/legion` now routes bare invocation to TTY shell, args to Interactive CLI
- `exe/legionio` handles all daemon and operational commands

## [1.4.61] - 2026-03-18

### Added
- Chat persistent settings defaults via `Legion::Settings` (issue #5)
- `chat_setting(*keys)` helper for centralized settings access with error handling
- Settings priority chain: CLI flag > `Legion::Settings.dig(:chat, ...)` > hardcoded default
- Configurable via settings: model, provider, personality, permissions, markdown, incognito, max_budget_usd, subagent concurrency/timeout, headless max_turns
- `chat` subsystem added to `config scaffold` with full template
- `Subagent.configure_from_settings` reads concurrency and timeout from settings
- 22 new specs (19 settings integration + 3 subagent settings)

## [1.4.60] - 2026-03-18

### Fixed
- Empty Enter in chat REPL no longer exits the session; returns empty string instead of nil to disambiguate from Ctrl+D (EOF)

## [1.4.59] - 2026-03-17

### Added
- `remote_invocable?` flag for LEX extensions: when `false`, the auto-generated Subscription actor is skipped (no RabbitMQ queue, no thread pool, no AMQP binding)
- 5-level resolution order: per-runner settings, extension settings, runner class method, extension module method, default `true`
- `@local_tasks` list tracks subscription actors skipped due to `remote_invocable? false` for introspection
- `remote_invocable?` default method added to `Legion::Extensions::Core` and `Legion::Extensions::Actors::Base`
- Fully backward compatible — all existing extensions unaffected

## [1.4.58] - 2026-03-17

### Added
- `legion lex list` now groups output by category (tier order) by default.
- `legion lex list CATEGORY` filters the list to a specific category (e.g., `legion lex list agentic`).
- `--flat` option to `legion lex list` restores the original flat table without grouping.
- `category` and `tier` columns added to the extension table in all display modes.
- `discover_all` now includes `:category` and `:tier` keys in each extension info hash,
  derived via `Legion::Extensions::Helpers::Segments.categorize_gem`.
- Results sorted by tier then name for deterministic ordering.

## [1.4.57] - 2026-03-17

### Added
- `--category` option to `legion lex create`: generates categorized extension gems with nested module
  declarations, nested directory structure, and correct `VERSION` constant paths.
  Example: `legion lex create cognitive-anchor --category agentic` produces gem `lex-agentic-cognitive-anchor`
  with module `Legion::Extensions::Agentic::Cognitive::Anchor`.
- `LexGenerator` now accepts `gem_name:` keyword argument and uses `Legion::Extensions::Helpers::Segments`
  to derive all namespace, const, and require-path values for both flat and nested extensions.
- `legion lex create` emits a warning via `Legion::Extensions.check_reserved_words` when reserved
  category prefixes or framework words are used in the gem name.

## [1.4.56] - 2026-03-17

### Fixed
- `lex_class` now returns the full extension module constant by walking the namespace up to the first `NAMESPACE_BOUNDARIES` word, instead of always stopping at index 2. For nested extensions (`Legion::Extensions::Agentic::Cognitive::Anchor`), this returns `Legion::Extensions::Agentic::Cognitive::Anchor` rather than the incorrect `Legion::Extensions::Agentic`.
- `lex_const` now derives from `lex_class.to_s.split('::').last` so it returns the extension's root constant name (`Anchor`) rather than always returning the third element of the namespace array.
- `full_path` now builds the gem name from dash-joined segments (`lex-agentic-cognitive-anchor`) instead of underscore-joined `lex_name`, so `Gem::Specification.find_by_name` works for nested extensions.

## [1.4.55] - 2026-03-17

### Changed
- `build_default_exchange` now sets `exchange_name` on dynamically created exchange classes to return `amqp_prefix` (dot-joined segments with `legion.` prefix) instead of defaulting to the parent class behavior
- `auto_create_exchange` now derives `exchange_name` from `amqp_prefix` + the exchange's own downcased class name, replacing the index-based `split('::')[5].downcase` extraction that broke for nested extension namespaces

### Fixed
- `legion config scaffold` now writes to `~/.legionio/settings/` by default instead of `./settings/`
- Removed Thor `default: './settings'` that shadowed the Ruby fallback in `ConfigScaffold.run`
- Added `~/.legionio/settings` to `legion config path` search paths to match `Service#default_paths`

## [1.4.54] - 2026-03-17

### Changed
- `Helpers::Logger#log` now passes `lex_segments:` array to `Legion::Logging::Logger` when the object responds to `:segments`
- Falls back to `lex:` string for legacy flat extensions that do not implement `:segments`

## [1.4.53] - 2026-03-17

### Fixed
- Extension discovery now correctly parses multi-hyphenated gem names (e.g., `lex-cognitive-reappraisal`)
- `gem_names_for_discovery` returns structured data instead of ambiguous `name-version` strings
- Updated fallback path to use `Gem::Specification.latest_specs` instead of `all_names`

## [1.4.52] - 2026-03-17

### Added
- `legion dashboard`: TUI operational dashboard with auto-refresh polling
- `Dashboard::DataFetcher`: polls REST API for workers, health, and recent events
- `Dashboard::Renderer`: terminal-based dashboard rendering with sections for workers, events, health
- Configurable API URL (`--url`) and refresh interval (`--refresh`)

## [1.4.51] - 2026-03-17

### Added
- `Legion::TraceSearch`: natural language to safe JSON filter translation via legion-llm structured output
- `legion trace search "query"`: CLI command for NL trace search
- Column allowlist enforcement for query safety (no eval, JSON-only filter DSL)
- Schema-aware prompt for metering_records table

## [1.4.50] - 2026-03-17

### Added
- `Legion::Graph::Builder`: builds task relationship graph from relationships table with chain/worker filtering
- `Legion::Graph::Exporter`: renders graphs to Mermaid and DOT (Graphviz) formats
- `legion graph show`: CLI command with `--format mermaid|dot`, `--chain`, `--worker`, `--output`, `--limit` options

## [1.4.49] - 2026-03-17

### Added
- `Legion::TenantContext`: thread-local tenant context propagation (set, clear, with block)
- `Legion::Tenants`: tenant CRUD, suspension, and quota enforcement
- `Middleware::Tenant`: extracts tenant_id from JWT/header, sets TenantContext per request
- `GET/POST /api/tenants`: tenant listing and provisioning endpoints
- `POST /api/tenants/:id/suspend`: tenant suspension
- `GET /api/tenants/:id/quota/:resource`: quota check endpoint

## [1.4.48] - 2026-03-17

### Added
- `Legion::Capacity::Model`: workforce capacity calculation (throughput, utilization, forecast, per-worker stats)
- `GET /api/capacity`: aggregate capacity across active workers
- `GET /api/capacity/forecast`: projected capacity with configurable growth rate and period
- `GET /api/capacity/workers`: per-worker capacity breakdown

## [1.4.47] - 2026-03-17

### Fixed
- `gem_load` rescue block referenced undefined `gem_path` variable, causing secondary NameError that masked original LoadError
- `meta_actors` type guard checked `is_a?(Array)` but called `each_value` (Hash method), so meta actors were never hooked
- `build_actor_list` crashed entire extension load when actor file didn't define expected constant (now skips gracefully)
- `build_transport` raised NoMethodError on extensions with custom Transport modules missing `build` (now falls back to auto-generate)

## [1.4.46] - 2026-03-17

### Added
- `Legion::Telemetry.configure_exporter`: OTLP and console span exporters
- OTLP exporter uses BatchSpanProcessor for production performance
- Settings: `telemetry.tracing.exporter`, `endpoint`, `headers`, `batch_size`
- Graceful fallback when opentelemetry-exporter-otlp gem absent

## [1.4.45] - 2026-03-17

### Added
- `GET /api/auth/authorize`: redirects to Entra authorization endpoint for browser-based OAuth2 login
- `GET /api/auth/callback`: exchanges authorization code for tokens, validates id_token via JWKS, maps claims, issues Legion human JWT
- Auth middleware SKIP_PATHS now includes `/api/auth/authorize` and `/api/auth/callback`

## [1.4.44] - 2026-03-17

### Added
- `POST /api/auth/worker-token`: Entra client credentials token exchange endpoint (validates client_credentials grant via JWKS, looks up worker by appid, issues scoped Legion worker JWT)
- Auth middleware SKIP_PATHS now includes `/api/auth/token` and `/api/auth/worker-token`

## [1.4.43] - 2026-03-17

### Fixed
- Auth token exchange route used `Legion::Settings.dig` which doesn't exist — replaced with bracket access
- Auth spec required `legion/rbac` gem directly — replaced with inline stub for standalone test execution

## [1.4.42] - 2026-03-17

### Added
- `POST /api/auth/token`: Entra ID token exchange endpoint (validates external JWT via JWKS, maps claims via EntraClaimsMapper, issues Legion token)

## [1.4.41] - 2026-03-17

### Added
- `Legion::CLI::LexTemplates`: extension template registry (basic, llm-agent, service-integration, scheduled-task, webhook-handler)
- `Legion::Docs::SiteGenerator`: documentation site generation from existing markdown files

## [1.4.40] - 2026-03-17

### Added
- `Legion::Guardrails`: embedding similarity and RAG relevancy safety checks
- `Legion::Context`: session/user tracking with thread-local `SessionContext`
- `Legion::Catalog`: AI catalog registration for MCP tools and workers

## [1.4.39] - 2026-03-17

### Added
- `Legion::Webhooks`: outbound webhook dispatcher with HMAC-SHA256 signing
- Webhook registration, delivery tracking, and dead letter queue
- API routes: `GET/POST/DELETE /api/webhooks`

## [1.4.38] - 2026-03-17

### Added
- `Legion::Isolation`: per-agent data and tool access enforcement with thread-local context
- `Isolation::Context`: tool allowlist, data filter, and risk tier per agent

## [1.4.37] - 2026-03-17

### Added
- `POST /api/channels/teams/webhook`: Bot Framework activity delivery to GAIA sensory buffer

## [1.4.36] - 2026-03-17

### Added
- `Audit::HashChain`: SHA-256 hash chain for tamper-evident audit records
- `Audit::SiemExport`: SIEM-compatible JSON and NDJSON export with integrity metadata
- `Audit::HashChain.verify_chain` validates hash chain between records

## [1.4.35] - 2026-03-17

### Added
- `Chat::Team`: multi-user context tracking with thread-local user, env detection
- `Chat::ProgressBar`: progress indicator for long-running operations with ETA
- `legion notebook read/export`: Jupyter notebook reading and export (markdown/script)

## [1.4.34] - 2026-03-17

### Added
- `Legion::Registry`: central extension metadata store with search, risk tier filtering, AIRB status
- `Legion::Sandbox`: capability-based extension sandboxing with enforcement toggle
- `Legion::Registry::SecurityScanner`: naming convention, checksum, and gemspec metadata validation
- `legion marketplace`: CLI for search, info, list, scan operations

## [1.4.33] - 2026-03-17

### Added
- `legion cost summary`: overall cost summary (today/week/month)
- `legion cost worker <id>`: per-worker cost breakdown
- `legion cost top`: top cost consumers ranked by spend
- `legion cost export`: export cost data as JSON or CSV
- `Legion::CLI::CostData::Client`: API client for cost data retrieval

### Fixed
- `Connection.resolve_config_dir` spec now correctly stubs `~/.legionio/settings` path

## [1.4.32] - 2026-03-17

### Fixed
- `NotificationBridge` missing `require_relative 'notification_queue'` causing `NameError` on `legion chat`

## [1.4.31] - 2026-03-16

### Added
- Skills system: `.legion/skills/` and `~/.legionio/skills/` YAML frontmatter markdown files
- `Legion::Chat::Skills`: discovery, parsing, and find for skill files
- `/skill-name` invocation in chat resolves user-defined skills
- `legion skill list`, `legion skill show`, `legion skill create`, `legion skill run` CLI subcommands

## [1.4.30] - 2026-03-16

### Added
- `MCP::Auth`: token-based MCP authentication (JWT + API key)
- `MCP::ToolGovernance`: risk-tier-aware tool filtering and invocation audit
- `MCP.server_for(token:)` builds identity-scoped MCP server instances
- HTTP transport auth: Bearer token validation with 401 response on failure
- MCP settings: `mcp.auth.enabled`, `mcp.auth.allowed_api_keys`, `mcp.governance.enabled`, `mcp.governance.tool_risk_tiers`

## [1.4.29] - 2026-03-16

### Added
- `legion init`: one-command workspace setup with environment detection
- `InitHelpers::EnvironmentDetector`: checks for RabbitMQ, database, Vault, Redis, git, existing config
- `InitHelpers::ConfigGenerator`: ERB template-based config generation, `.legion/` workspace scaffolding
- `--local` flag for zero-dependency development mode
- `--force` flag to overwrite existing config files

## [1.4.28] - 2026-03-16

### Added
- `Legion::Telemetry` module: opt-in OpenTelemetry tracing with `with_span` wrapper
- `setup_telemetry` in Service: initializes OTel SDK with OTLP exporter when `telemetry.enabled: true`
- `sanitize_attributes` helper for safe OTel attribute conversion
- `record_exception` helper for span error recording

## [1.4.27] - 2026-03-16

### Added
- `legion update` CLI command: updates all Legion gems (`legionio`, `legion-*`, `lex-*`) using the current Ruby's gem binary
- `--dry-run` flag to check available updates without installing
- `--json` flag for machine-readable output
- Updates install into the running Ruby's GEM_HOME (safe for Homebrew bundled installs)

## [1.4.26] - 2026-03-16

### Added
- `Legion::Metrics` module: opt-in Prometheus metrics via `prometheus-client` gem
- `GET /metrics` endpoint returning Prometheus text-format output
- 9 metrics: uptime, active_workers, tasks_total, tasks_per_second, error_rate, consent_violations, llm_requests, llm_tokens
- Event-driven counters + pull-based gauge refresh on scrape
- `/metrics` added to Auth middleware SKIP_PATHS
- Wired into Service startup and shutdown

## [1.4.25] - 2026-03-16

### Added
- `Legion::Chat::NotificationQueue`: thread-safe priority queue for background notifications
- `Legion::Chat::NotificationBridge`: event-driven bridge matching Legion events to chat notifications
- Chat REPL displays pending notifications before each prompt (critical in red, info in yellow)
- Configurable notification patterns via `chat.notifications.patterns` setting

## [1.4.24] - 2026-03-16

### Added
- `Legion::Audit.recent_for` — query audit records by principal and time window
- `Legion::Audit.count_for` — count audit records by principal and time window
- `Legion::Audit.failure_count_for` / `success_count_for` — convenience wrappers
- `Legion::Audit.resources_for` — distinct resources invoked by a principal
- `Legion::Audit.recent` — most recent N records with optional filters
- All query methods return safe defaults (`[]` or `0`) when legion-data is unavailable

## [1.4.23] - 2026-03-16

### Added
- `Middleware::BodyLimit`: request body size limit (1MB max, returns 413)
- `API::Validators` helper module: `validate_required!`, `validate_string_length!`, `validate_enum!`, `validate_uuid!`, `validate_integer!`
- Ingress payload validation: 512KB size limit, runner_class/function format checks

### Security
- Ingress validates runner_class format before `Kernel.const_get` to prevent arbitrary constant resolution
- Ingress validates function format before `.send` to prevent method injection

## [1.4.22] - 2026-03-16

### Added
- `Legion::Alerts`: configurable alerting rules engine with event pattern matching
- `Alerts::Engine`: count-based conditions, cooldown deduplication, multi-channel dispatch
- 4 default rules: consent_violation, extinction_trigger, error_spike, budget_exceeded
- Channel dispatch: events (via `Legion::Events`), log (via `Legion::Logging`), webhook
- Settings: `alerts.enabled`, `alerts.rules`
- Wired into `Service` startup (opt-in via `alerts.enabled: true`)

## [1.4.21] - 2026-03-16

### Added
- `Middleware::ApiVersion`: rewrites `/api/v1/` paths to `/api/` for future versioned API support
- Deprecation headers (`Deprecation`, `Sunset`, `Link`) on unversioned `/api/` paths
- `X-API-Version` request header set for versioned paths
- Skip paths: `/api/health`, `/api/ready`, `/api/openapi.json`, `/metrics`

## [1.4.20] - 2026-03-16

### Added
- `Middleware::RateLimit`: sliding-window rate limiting with per-IP, per-agent, per-tenant tiers
- In-memory store (default) with lazy reap; distributed store via `Legion::Cache` when available
- Standard headers: `X-RateLimit-Limit`, `X-RateLimit-Remaining`, `X-RateLimit-Reset`, `Retry-After` (429 only)
- Skip paths: `/api/health`, `/api/ready`, `/api/metrics`, `/api/openapi.json`

## [1.4.19] - 2026-03-16

### Added
- Local development mode: `LEGION_LOCAL=true` env var or `local_mode: true` in settings
- Auto-configures in-memory transport, mock Vault, and dev settings

## [1.4.18] - 2026-03-16

### Added
- `legion config scaffold` auto-detects environment variables and enables providers
- Detects: AWS_BEARER_TOKEN_BEDROCK, ANTHROPIC_API_KEY, OPENAI_API_KEY, GEMINI_API_KEY, VAULT_TOKEN, RABBITMQ_USER/PASSWORD
- Detects running Ollama on localhost:11434
- First detected LLM provider becomes the default; credentials use `env://` references
- JSON output includes `detected` array for automation

## [1.4.17] - 2026-03-16

### Added
- `Legion::Audit` publisher module for immutable audit logging via AMQP
- Audit hook in `Runner.run` records every runner execution (event_type, duration, status)
- Audit hook in `DigitalWorker::Lifecycle.transition!` records state transitions
- `GET /api/audit` endpoint with filters (event_type, principal_id, source, status, since, until)
- `GET /api/audit/verify` endpoint for hash chain integrity verification
- `legion audit list` and `legion audit verify` CLI commands
- Silent degradation: audit never interferes with normal operation (triple guard + rescue)

## [1.4.16] - 2026-03-16

### Added
- `legion worker create NAME` CLI command: provisions digital worker in bootstrap state with DB record + optional Vault secret storage

## [1.4.15] - 2026-03-16

### Added
- RAI invariant #2: Ingress.run calls Registry.validate_execution! when worker_id is present
- Unregistered or inactive workers are blocked with structured error (no exception propagation)
- Registration check fires before RBAC authorization (registration precedes permission)

## [1.4.14] - 2026-03-16

### Added
- Optional RBAC integration via legion-rbac gem (`if defined?(Legion::Rbac)` guards)
- `GET /api/workers/:id/health` endpoint returns worker health status with node metrics
- `health_status` query filter on `GET /api/workers`
- Thread-safe local worker tracking in `DigitalWorker::Registry` for heartbeat reporting
- `Legion::DigitalWorker.active_local_ids` delegate method
- `setup_rbac` lifecycle hook in Service (after setup_data)
- `authorize_execution!` guard in Ingress for task execution
- Rack middleware registration in API when legion-rbac loaded
- REST API routes for RBAC management (roles, assignments, grants, cross-team grants, check)
- `legion rbac` CLI subcommand (roles, show, assignments, assign, revoke, grants, grant, check)
- MCP tools: legion.rbac_check, legion.rbac_assignments, legion.rbac_grants

## [1.4.13] - 2026-03-16

### Changed
- SIGHUP signal now triggers `Legion.reload` instead of logging only

## [1.4.12] - 2026-03-16

### Added
- `--http-port` CLI flag for `legion start` to override API port without editing settings
- `apply_cli_overrides` method in `Service` applies CLI-provided overrides after settings load

## [1.4.11] - 2026-03-16

### Fixed
- Sinatra and Puma no longer write startup banners directly to stdout
- API logging routed through `Legion::Logging` for consistent log format
- Puma log writer silenced via `StringIO` redirect in `setup_api`

## [1.4.10] - 2026-03-16

### Fixed
- API startup no longer crashes when port is already in use (rolling restart support)
- `setup_api` retries binding up to 10 times with 3s wait (configurable via `api.bind_retries` and `api.bind_retry_wait`)
- Port bind failure after retries marks API as not-ready instead of killing the thread

## [1.4.9] - 2026-03-16

### Added
- YJIT enabled at process start for 15-30% runtime throughput improvement (Ruby 3.1+ builds)
- GC tuning ENV defaults for large gem count workloads (overridable via environment)
- bootsnap bytecode and load-path caching at `~/.legionio/cache/bootsnap/`
- Role-based extension profiles: nil (all), core, cognitive, service, dev, custom
- Extension discovery uses Bundler specs when available for faster boot

### Changed
- `find_extensions` uses `Bundler.load.specs` instead of `Gem::Specification.all_names` under Bundler
- `lex-` prefix check uses `start_with?` instead of string slicing

## v1.4.8

### Fixed
- Relationships API routes now fully functional (removed 501 stub guards, backed by legion-data migration)
- Relationships MCP tool no longer checks for missing model
- Gaia API route returns 503 instead of 500 when `Legion::Gaia` is defined but lacks `started?` method

## v1.4.7

### Added
- Extension-powered chat tools: LEX extensions can ship optional `tools/` directories with `RubyLLM::Tool` subclasses
- `ExtensionToolLoader` lazily discovers extension tools at chat startup
- `permission_tier` DSL for extension tools (`:read`, `:write`, `:shell`) with settings override
- Session mode ceiling: read_only blocks write/shell extension tools regardless of tool declaration
- Plan mode uses tier-based filtering (no longer hardcoded tool list)
- `legion generate tool <name>` scaffolds tool + spec in current LEX
- `legion lex create` now includes empty `tools/` directory
- Tab completion updated for `legion generate tool`
- `Permissions.register_extension_tier` and `Permissions.clear_extension_tiers!` for extension tool tier management
- System prompt includes extension tool names when available

## v1.4.6

### Added
- `legion doctor` CLI command diagnoses the LegionIO environment and prescribes fixes
- 10 environment checks: Ruby version, bundle status, config files, RabbitMQ, database, cache, Vault, extensions, PID files, permissions
- `--fix` flag for auto-remediation of fixable issues (stale PIDs, missing gems, missing config)
- `--json` flag for machine-readable diagnosis output with pass/fail/warn/skip per check
- `Doctor::Result` value object with status, message, prescription, and auto_fixable fields
- Exit code 1 when any check fails, 0 when all checks pass or warn

## v1.4.5

### Added
- `legion openapi generate` CLI command outputs OpenAPI 3.1.0 spec JSON to stdout or file (-o)
- `legion openapi routes` CLI command lists all API routes with HTTP method and summary
- `GET /api/openapi.json` endpoint serves the full OpenAPI 3.1.0 spec at runtime (auth skipped)
- `Legion::API::OpenAPI` module with `.spec` (returns Hash) and `.to_json` class methods
- OpenAPI spec covers all 44 routes across 16 resource groups with request/response schemas
- Auth middleware SKIP_PATHS updated to include `/api/openapi.json`

## v1.4.4

### Added
- `legion completion bash` subcommand outputs bash tab completion script
- `legion completion zsh` subcommand outputs zsh tab completion script
- `legion completion install` subcommand prints shell-specific installation instructions
- `completions/legion.bash` bash completion script with full command tree coverage
- `completions/_legion` zsh completion script with descriptions for all commands and flags
- `legion lex create` now scaffolds a standalone `Client` class in new extensions

## v1.4.3

### Added
- `legion gaia status` CLI subcommand (probes GET /api/gaia/status, shows cognitive layer health)
- `GET /api/gaia/status` API route returns GAIA boot state, active channels, heartbeat health
- `legion schedule` CLI subcommand (list, show, add, remove, logs) wrapping /api/schedules
- `/commit` chat slash command (AI-generated commit message from staged changes)
- `/workers` chat slash command (list digital workers from running daemon)
- `/dream` chat slash command (trigger dream cycle on running daemon)

## v1.4.2

### Added
- Multiline input support in chat REPL via backslash continuation (end a line with `\` to continue)
- Continuation prompt (`...`) for multiline input lines
- Specs for `read_user_input` method (12 examples)

## v1.4.1

### Added
- CLI status indicators using TTY::Spinner for chat REPL
- Session lifecycle events (:llm_start, :llm_first_token, :llm_complete, :tool_start, :tool_complete)
- StatusIndicator class subscribes to session events and manages spinner display
- Purple-themed braille dot spinner with phase labels (thinking..., running tool_name...)
- Tool counter prefix ([1/3]) for multi-tool loops
- Graceful degradation for non-TTY output (piped, redirected)

## v1.4.0

### Added
- File edit checkpointing system with `/rewind` to undo edits (per-edit, N steps, or per-file)
- Persistent memory system (`/memory`, `.legion/memory.md`, `~/.legion/memory/global.md`)
- `legion memory` CLI subcommand for managing persistent memory entries
- Web search via DuckDuckGo HTML scraping (`/search` slash command)
- Background subagent spawning via headless subprocess (`/agent`, `SpawnAgent` tool)
- Custom agent definitions (`.legion/agents/*.json` or `.yaml`) with `@name` delegation
- Plan mode toggle (`/plan`) — restricts tools to read-only for exploration
- `legion plan` CLI subcommand for standalone read-only exploration sessions
- Multi-agent swarm orchestration (`/swarm`, `legion swarm` CLI subcommand)
- `SaveMemory` and `SearchMemory` LLM tools for auto-remembering
- `WebSearch` LLM tool for web search during conversations
- Checkpoint integration in `WriteFile` and `EditFile` tools (auto-save before writes)

### Changed
- Rubocop exclusions added for plan_command.rb and swarm_command.rb (BlockLength)
- Rubocop exclusions added for chat_command.rb (MethodLength, CyclomaticComplexity)

## v1.3.0

### Added
- `legion chat` interactive REPL and headless prompt mode with LLM integration
- `legion commit` command for AI-generated commit messages
- `legion pr` command for AI-generated pull request descriptions
- `legion review` command for AI-powered code review
- `/fetch` slash command for injecting web page context into chat sessions
- Chat permission system with read/write/shell tiers and auto-approve mode
- Chat session persistence (save/load/list) and `/compact` context compression
- `--max-budget-usd` cost cap for chat sessions
- `--incognito` mode to disable automatic session history saving
- Markdown rendering for chat responses (via rouge)
- Purple palette theme, orbital ASCII banner, and branded CLI output
- Chat logger for structured debug/info logging

### Changed
- Worker lifecycle CLI passes `authority_verified`/`governance_override` flags
- Worker API accepts governance flags from request body
- Config `path` command now respects `--config-dir` option

### Fixed
- Config `sensitive_key?` false positive: `cluster_secret_timeout` no longer redacted
- `check_command` now rescues `LoadError` (missing gems no longer crash the check run)
- Config `show`/`path`/`validate` commands call `Connection.shutdown` in ensure blocks
- Config `path` and `validate` rescue `CLI::Error` properly
- Worker CLI/API handle `GovernanceRequired` and `AuthorityRequired` exceptions
- Removed unused `--json`/`--no-color` class_options from generate and mcp commands

## v1.2.1
* Updating LEX CLI templates
* Fixing issue with LEX schema migrator

## v1.2.0
Moving from BitBucket to GitHub. All git history is reset from this point on
