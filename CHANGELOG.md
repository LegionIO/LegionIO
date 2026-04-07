# Legion Changelog

## [1.7.25] - 2026-04-06

### Added
- Wire Format Phase 3 Group 2: `Identity::Request::SOURCE_NORMALIZATION` constant — maps middleware-emitted source values (`:api_key`, `:local`, `:jwt`, `:kerberos`, `:system`) to canonical credential enum at `from_auth_context` construction time
- Wire Format Phase 3 Group 2: `response_meta` in `API::Helpers` now includes `caller` block (`canonical_name`, `kind`, `source`) when the request is authenticated and `env['legion.principal']` is set by `Identity::Middleware`
- Wire Format Phase 3 Group 2: `POST /api/llm/inference` wires `to_caller_hash` from the authenticated principal into the pipeline `caller:` field, replacing the hardcoded `{ type: :user, credential: :api }` fallback

## [1.7.24] - 2026-04-06

### Fixed
- `Routes::Events` SSE stream: qualify `stream_queue` call with `Routes::Events.` to fix NoMethodError on Legion::API instance

### Added
- `Identity::Process.source` accessor — exposes provider source in identity hash (Wire Format Phase 3)
- `source:` key in `Identity::Process.identity_hash`, `bind!`, `bind_fallback!`, and `EMPTY_STATE`

## [1.7.22] - 2026-04-06
### Added
- Elastic APM integration for Sinatra API via `elastic-apm` gem
- Full APM config under `api.elastic_apm` settings: server_url, api_key, secret_token, api_buffer_size, api_request_size, api_request_time, capture_body, capture_headers, capture_env, disable_send, enabled, environment, hostname, ignore_url_patterns, pool_size, service_name, service_node_name, service_version, sample_rate
- `setup_apm` / `shutdown_apm` lifecycle in Service (boot, shutdown, reload)
- `ElasticAPM::Middleware` wired into API when available
- Health/ready endpoints excluded from APM tracing by default

## [1.7.21] - 2026-04-06
### Fixed
- Optional components (rbac, llm, apollo, gaia) no longer block readiness when not installed
- Split `Readiness::COMPONENTS` into `REQUIRED_COMPONENTS` and `OPTIONAL_COMPONENTS`
- Added `Readiness.mark_skipped` for components that are absent or disabled
- Reload path now correctly marks optional components as skipped when not loaded

## [1.7.20] - 2026-04-06
### Added
- `Legion::Mode` module with `LEGACY_MAP`, ENV/Settings fallback chain, `agent?`/`worker?`/`infra?`/`lite?` predicates
- `Legion.instance_id` — UUID computed at load time, ENV override via `LEGIONIO_INSTANCE_ID`
- `Legion::Identity::Process` singleton — process identity with `bind!`, `bind_fallback!`, `queue_prefix` per-mode, `AtomicReference` thread safety
- `Legion::Identity::Request` — per-request immutable identity with `from_env`, `from_auth_context`, `to_caller_hash`, `to_rbac_principal`
- `Legion::Identity::Lease` — credential lease value object with `expired?`, `stale?` (50% TTL), `ttl_seconds`, `valid?`
- `Legion::Identity::LeaseRenewer` — background thread per provider, 50% TTL renewal, cooperative shutdown (no `Thread#kill`)
- `Legion::Identity::Broker` — provider management with groups cache (60s TTL, single-flight CAS), `token_for`, `credentials_for`, `shutdown`
- `Legion::Identity::Middleware` — Rack middleware bridging `legion.auth` to `legion.principal` (`Identity::Request`)
- `setup_identity` boot step 9 — parallel provider resolution via `Concurrent::Promises`, fallback to `ENV['USER']`
- Extension publish suppression — defers `LexRegister.publish` until identity resolves, `flush_pending_registrations!`
- Identity provider auto-registration during phased extension load (`identity_provider?` duck-type check)
- `GET /api/identity/audit` route with principal and duration filtering
- `legion doctor` checks: `ApiBindCheck` (non-loopback without auth), `ModeCheck` (no explicit process.mode)

### Changed
- `Readiness.status` upgraded to `Concurrent::Hash` for thread safety; `:identity` added to `COMPONENTS`
- `READONLY_SECTIONS` extended with `:identity`, `:rbac`, `:api`
- Default API bind changed from `0.0.0.0` to `127.0.0.1`
- `ProcessRole` delegates `.current` to `Mode.current`; added `:agent` and `:infra` role entries
- `lite_mode?` delegates to `Mode.lite?`
- Reload path adds `Identity::Process.refresh_credentials` after transport reconnect
- Shutdown adds cooperative `Identity::Broker.shutdown` and JWKS background refresh stop

## [1.7.19] - 2026-04-06

### Added
- `ALWAYS_LOADED` constant in `Tools::Discovery` — pins apollo/knowledge and eval/evaluation runners to always-loaded regardless of extension DSL
- `always_loaded_names` method on `Tools::Registry` returning names of all non-deferred registered tools

### Changed
- Tool name format changed from dot-separated to dash-separated (`legion-ext-runner-func`) for LLM provider compatibility
- Reduced noisy debug logging in `Tools::Discovery` and `Tools::Registry`

## [1.7.18] - 2026-04-06

### Added
- Multi-phase extension loading: identity providers (`lex-identity-*`) load in phase 0 before all other extensions in phase 1
- `identity` category in extension registry with prefix matching for `lex-identity-*` gems at tier 0, phase 0
- `group_by_phase` method groups discovered extensions by phase from the category registry
- `load_phase_extensions` replaces `load_extensions` — scopes parallel loading to a subset of entries per phase
- `hook_phase_actors` replaces `hook_all_actors` — hooks deferred actors after each phase completes
- Per-phase logging during extension loading shows cumulative actor counts

### Changed
- `hook_extensions` now iterates phases sequentially (phase 0 then phase 1), running full load+hook cycle per phase
- `default_category_registry` includes `phase:` key on all categories; all non-identity categories default to phase 1
- Catalog transitions (`transition(:running)` + `flush_persisted_transitions`) happen after all phases complete
- Reserved prefixes list now includes `identity`

### Added
- `Legion::Tools::Base` - canonical tool base class with DSL
- `Legion::Tools::Registry` - always/deferred tool classification
- `Legion::Tools::Discovery` - auto-discovers tools from extension runners with hierarchical DSL
- `Legion::Tools::EmbeddingCache` - 5-tier persistent embedding cache (L0 memory + Cache + Data)
- `mcp_tools?` and `mcp_tools_deferred?` extension Core DSL
- `runner_modules` accessor on extension builders
- `loaded_extension_modules` accessor on `Legion::Extensions`
- Static tools: `Do`, `Status`, `Config` with `Legion::Logging::Helper`

### Changed
- Boot registers tools into Tools::Registry after extension load
- Embedding index build is async (non-blocking)
- API inference reads from Tools::Registry instead of MCP
- Capability registration methods are now no-ops (replaced by Tools::Discovery)

### Removed
- Direct MCP dependency for tool access in API inference

## [1.7.16] - 2026-04-03

### Fixed
- Inference endpoint now injects daemon MCP tools alongside client tools via class-level cached adapters
- MCP server pre-warmed in background thread during boot to avoid blocking first inference
- Gaia ticks route added to fallback API routes
- Reload endpoint disabled (418) to prevent accidental restart loops

## [1.7.15] - 2026-04-03

### Added
- Every actors now support `delay` method to defer timer start (used by lex-microsoft_teams)
- Request logger emits `[api][request-start]` on inbound, warns on responses > 5s

### Changed
- `/api/reload` disabled (returns 418) to prevent accidental full-restart loops

## [1.7.14] - 2026-04-03

### Fixed
- Actor boot ordering: once → poll → every → loop → subscriptions, preventing timer actors from competing with AMQP channel setup
- Builder now respects `remote_invocable? false` and skips auto-generated subscription actors for local-only extensions
- Catalog exchange cached and reused instead of creating a new channel + exchange_declare per transition
- Catalog SQLite persists batched into a single transaction at end of boot instead of per-transition writes from concurrent threads

## [1.7.13] - 2026-04-03

### Changed
- Bump legion-crypt >= 1.5.1, legion-transport >= 1.4.14, legion-cache >= 1.3.22

## [1.7.12] - 2026-04-03

### Fixed
- Fixes #110: normal daemon boot now prefers library-owned LLM and Apollo API routes, `/api/tenants` uses canonical JSON parsing with correct status codes, SSE listeners drain worker threads on disconnect, paginated collections avoid unconditional `COUNT(*)` unless explicitly requested, and service startup skips duplicate settings loads once configuration is already bootstrapped

## [1.7.11] - 2026-04-02

### Fixed
- Fixes #113: webhook deliveries now retry non-2xx responses and transport exceptions up to `max_retries`, record per-attempt delivery rows, dead-letter terminal failures, and cache active webhook pattern matching to reduce per-event dispatch overhead

## [1.7.10] - 2026-04-02

### Changed
- Bumped minimum dependency floors for Legion core gems, including `legion-logging >= 1.5.0`, `legion-settings >= 1.3.25`, and updated transport, data, cache, crypt, Apollo, and MCP minimums
- Stabilized the `LegionIO` spec suite by fixing the OAuth callback, catalog, and service shutdown regression specs
- CLI startup now honors settings-driven log levels, normalizes `start --help` into the standard Thor help flow, and routes chat/error logging through the newer helper-backed logger path
- `Legion::Service`, telemetry, and webhook runtime paths now use structured helper logging more consistently, respect configured logging when no CLI override is passed, and avoid brittle settings reads during boot
- Extension runtime wiring now deep-dups merged settings, lazily registers the local `extension_catalog` migration, publishes catalog transitions directly to transport, and surfaces auto-binding failures more clearly
- Secret, region, and task-outcome helpers now use canonical Vault connectivity checks, cache metadata misses more safely, and create meta-learning domains on demand before recording learning episodes

## [1.7.8] - 2026-04-01

### Added
- `Legion::API::Settings` module with registered defaults via `merge_settings('api', ...)`, matching the pattern used by all other LegionIO gems
- Puma `persistent_timeout` (20s) and `first_data_timeout` (30s) now configurable via `Settings[:api][:puma]`

### Changed
- Removed all inline `||` and `.fetch(..., default)` fallbacks for API settings in `service.rb` and `check_command.rb` — defaults now guaranteed by `merge_settings`

## [1.7.7] - 2026-04-01

### Changed
- Integrated legion-logging 1.4.3 Helper refactor: all log output now uses structured segment tagging, colored exception output, and thread-local task context
- Slimmed `Extensions::Helpers::Logger` to thin override; `derive_component_type`, `lex_gem_name`, `gem_spec_for_lex`, `log_lex_name` now live in legion-logging gem
- Added `handle_runner_exception` for runner-specific exception handling (TaskLog publish + HandledTask raise)
- Added `Legion::Context.with_task_context` and `.current_task_context` for thread-local task propagation
- Wrapped all 5 dispatch paths (Runner.run, Subscription#dispatch_runner, Base#runner, Ingress local/remote) with context propagation
- Migrated 13 `log.log_exception` call sites to `handle_exception` across actors, core, transport, and task helpers

## [1.7.6] - 2026-04-01

### Changed
- `POST /api/llm/inference` now routes through `Legion::LLM::Pipeline::Executor` instead of raw `Legion::LLM.chat` session, enabling the full 18-step pipeline (RBAC, RAG context, MCP discovery, metering, audit, knowledge capture)
- GAIA bridge added: user prompt from `/api/llm/inference` is pushed as an `InputFrame` to the GAIA sensory buffer when GAIA is started
- SSE streaming support added: `stream: true` + `Accept: text/event-stream` returns `text/event-stream` with `text-delta`, `tool-call`, `enrichment`, and `done` events
- `build_client_tool` renamed to `build_client_tool_class`; now returns a `Class` (not an instance) so the pipeline can inject it correctly via `tool.is_a?(Class)` check
- Typed error mapping added: `AuthError` → 401, `RateLimitError` → 429, `TokenBudgetExceeded` → 413, `ProviderDown`/`ProviderError` → 502

## [1.7.5] - 2026-04-01

### Added
- `POST /api/reload` endpoint to trigger daemon reload from CLI mode command
- `GET /api/mesh/status` and `GET /api/mesh/peers` endpoints with 10s cache
- `GET /api/metering`, `/api/metering/rollup`, `/api/metering/by_model` endpoints wired to lex-metering
- `GET /api/webhooks` and `GET /api/tenants` routes registered (were defined but never mounted)
- Knowledge monitor v2/v3 route aliases for Interlink compatibility
- Server-side MCP tool injection into `/api/llm/inference` via `McpToolAdapter` (64 tools)
- Deferred tool loading: 18 always-loaded tools, ~46 on-demand (cuts inference from 24s to 6-9s)
- Client-side tools (`sh`, `file_read`, `list_directory`, etc.) now execute server-side in the inference endpoint

### Fixed
- Knowledge ingest API route calls `ingest_content` instead of `ingest_file` when `content` body param is present
- Catalog API queries `extensions.name` instead of non-existent `gem_name` column
- Inference endpoint tool declarations use `RubyLLM::Tool` subclass with proper `name` instance method
- Prompts API guards against missing `prompts` table (returns 503 instead of 500)
- All API rescue blocks use `Legion::Logging.log_exception` instead of swallowing errors

## [1.7.0] - 2026-03-31

### Added
- `Legion::Provider` base class with DAG-ordered registry for boot lifecycle (#71)
- `TaskOutcomeObserver` wires task completion to reflection and learning persistence (#70)
- GenAI semantic convention attributes (`gen_ai.*`) on OpenInference spans (#69)
- `legionio doctor` scored audit report with weighted health score and letter grades (#77)
- Local skill drop-in directory with `.rb` and `.md` support and execution (#76)
- Dynamic gem sources for extension installs via `extensions.sources` setting (#52)
- `legionio mode` CLI command for profile and process role switching (#72)
- Cross-project session resume with CWD context and `--resume-latest` flag (#105)
- Away summary recap via LLM when user returns after idle period (#100)
- Wire `LexCliManifest.write_manifest` into extension autobuild pipeline (#97)
- Inbound webhook normalizer and HTTP-to-AMQP event bridge (`Legion::Trigger`) (#74)
- Interrupt detection and session recovery for chat resume (#98)
- Configurable output styles for LLM responses via `.legionio/output-styles/` (#103)
- Route RunCommand through lex-exec sandbox when `chat.sandboxed_commands.enabled` is true (#96)
- Cross-session memory consolidation with 3-gate trigger system (#99)
- Per-model `/cost` breakdown with token counts, cache hits, and `CostEstimator` pricing (#102)
- Team memory sync via Apollo knowledge store with repo-scoped tags (#104)

### Fixed
- Puma no longer steals SIGINT/SIGTERM traps, preventing graceful shutdown (#91)

## [1.6.47] - 2026-03-31

### Added
- CLI chat identity wiring: `DaemonChat` generates stable `conversation_id` and resolves user identity into `caller_context` (Kerberos principal -> ENV['USER'] fallback)
- `DaemonChat` forwards `caller` and `conversation_id` to daemon inference endpoint
- GAIA observation hook in `chat_command.rb`: `setup_gaia_observation` registers an `:llm_complete` callback that ingests user messages into GAIA's observation pipeline
- `:llm_complete` session event now includes `user_message` in payload

## [1.6.46] - 2026-03-31

### Fixed
- `write_pack_marker` no longer uses `FileUtils.touch` — avoids `EPERM` (`Operation not permitted @ apply2files`) on macOS Sequoia when marker file already exists

## [1.6.45] - 2026-03-31

### Added
- `Legion::CLI::ApiClient` shared module — extracts api_get/api_post/api_put/api_delete helpers into a reusable mixin for all CLI commands that talk to the daemon API
- `/api/knowledge/*` API routes — query, retrieve, ingest, status, health, maintain, quality, and monitor CRUD endpoints for lex-knowledge

### Changed
- `legionio knowledge` commands now route through the local API instead of loading extension classes directly (fixes NameError when daemon not running)
- `legionio schedule` commands now route through the existing `/api/schedules/*` API instead of querying Sequel models directly
- `legionio codegen` commands now route through the existing `/api/codegen/*` API instead of checking `defined?` guards that always fail in CLI context
- `legionio absorb` commands now use the shared `ApiClient` module instead of inline HTTP helpers

## [1.6.44] - 2026-03-31

### Added
- `legionio setup <pack>` now writes `~/.legionio/.packs/<name>` marker file and `~/.legionio/settings/packs.json` on successful install, enabling automatic pack reinstall after `brew upgrade` (companion to homebrew-tap#19)

## [1.6.43] - 2026-03-31

### Added
- `POST /api/absorbers/dispatch` API endpoint for async absorber dispatch — CLI no longer loads extension classes directly
- Absorb dispatch runs in a background thread, returning job ID immediately

### Changed
- `legionio absorb url` now routes through the local API instead of loading extension classes in-process (fixes `NameError` when extensions not loaded in CLI context)
- CLI absorb output updated to show async dispatch status with job ID

## [1.6.42] - 2026-03-31

### Fixed
- `Every` and `Poll` actors now guard against overlapping executions using `Concurrent::AtomicBoolean` — if the previous tick is still running when the next interval fires, the new tick is skipped with a debug log instead of stacking up concurrent executions

## [1.6.41] - 2026-03-30

### Fixed
- Add missing `info` method to `Legion::CLI::Output::Formatter` — `auth teams` command called `out.info(...)` but the method did not exist, raising `NoMethodError`

## [1.6.40] - 2026-03-30

### Fixed
- `Helpers::Lex` now includes Cache, Transport, Task, and Data helpers so all actors, runners, absorbers, and hooks automatically get `cache_connected?`, `transport_connected?`, `data_connected?`, `generate_task_id`, and related methods
- `Absorbers::Base` now includes `Helpers::Lex` (previously included zero helpers, causing `NoMethodError` for `log`, `cache_connected?`, etc.)

## [1.6.39] - 2026-03-30

### Added
- `legionio config reset` subcommand to wipe all JSON config files from settings directory (#88)
- `legionio bootstrap --clean` flag to clear settings before import (#88)

### Changed
- `legionio bootstrap` no longer runs `ConfigScaffold` when a source is provided — scaffolded empty files were conflicting with imported config (#88)

## [1.6.38] - 2026-03-30

### Removed
- Remove deprecated `lex-cortex` from agentic setup pack (replaced by legion-gaia)

## [1.6.37] - 2026-03-30

### Added
- TBI Patterns API: `POST /api/tbi/patterns/export`, `GET /api/tbi/patterns`, `GET /api/tbi/patterns/:id`, `PATCH /api/tbi/patterns/:id/score`, `GET /api/tbi/patterns/discover` (501 stub)
- TBI Pattern model and local migration (`create_tbi_patterns`)
- OpenInference telemetry integration (`Legion::Telemetry::OpenInference`)

### Fixed
- Governance lifecycle integration specs expanded and hardened

## [1.6.36] - 2026-03-29

### Added
- Knowledge helper: `knowledge_connected?`, `knowledge_global_connected?`, `knowledge_local_connected?` status methods
- Knowledge helper: `knowledge_default_scope` and `knowledge_default_tags` LEX-overridable layered defaults
- LLM helper: now includes `Legion::LLM::Helper` following cache/transport pattern (with LoadError guard)
- Wrapper specs for cache and data helpers

### Fixed
- Logger helper: add missing `include Base` (was relying on transitive inclusion via Lex)
- Task helper: add missing `include Base`
- Knowledge helper: add missing `include Base`, `knowledge_default_tags` auto-merged into `ingest_knowledge`

## [1.6.35] - 2026-03-29

### Added
- `Legion::Workflow::Manifest` — YAML workflow manifest parser with validation
- `Legion::Workflow::Loader` — installs/uninstalls workflow chains via lex-lex registry
- `legion workflow` CLI — install, list, uninstall, status subcommands
- `workflows/autonomous-github-lifecycle.yml` — sample workflow manifest for codegen pipeline

## [1.6.34] - 2026-03-29

### Fixed
- `POST /api/logs` no longer raises `NoMethodError: undefined method 'values' for nil` — replaced `Legion::Transport::Messages::Dynamic.new(...).publish` with a direct `Legion::Transport::Exchanges::Logging` publish call; `Dynamic` requires a `function_id` for database lookup which log payloads do not have
- `legion knowledge` CLI commands (`require_monitor!`, `require_knowledge!`, `require_ingest!`, `require_maintenance!`) now use `Connection.ensure_knowledge` to dynamically load `lex-knowledge` when not yet loaded, instead of raising a generic error

### Added
- `Connection.ensure_knowledge` — lazily loads the `lex-knowledge` gem on demand, consistent with `ensure_llm` and other lazy loaders

## [1.6.33] - 2026-03-28

### Added
- `knowledge` registered as top-level CLI subcommand (previously only accessible via `legionio ai knowledge`). Fixes knowledge capture hooks that call `legionio knowledge capture commit/transcript`.

### Fixed
- Claude Code hook format in `setup claude-code`: PostToolUse and Stop hooks now emit the new `hooks` array wrapper format with `type: command` entries. Detection supports both old and new formats via `hook_commands` helper.

## [1.6.32] - 2026-03-28

### Added
- `POST /api/logs` endpoint (`Routes::Logs`) — accepts `error`/`warn` level messages from CLI, normalizes with server-side metadata (timestamp, node, legion_versions, ruby_version, pid), computes `error_fingerprint` via `EventBuilder.fingerprint` when `exception_class` is present, and publishes to the `legion.logging` exchange with routing key `legion.logging.exception.{level}.cli.{source}` or `legion.logging.log.{level}.cli.{source}`
- `Legion::CLI::ErrorForwarder` module — fire-and-forget HTTP helper that POSTs CLI errors/warnings to the daemon API; silently swallows all failures so daemon unavailability never crashes the CLI
- `ErrorForwarder.forward_error` wired into both rescue blocks in `CLI::Main.start` (fires before `exit(1)`)

## [1.6.31] - 2026-03-28

### Fixed
- `build_hook_list` in `Builders::Hooks` now calls `runner_class` on a hook instance (instance method) instead of the class, preventing the `TypeError: no implicit conversion of nil into String` boot crash caused by `Helpers::Base#runner_class` being inherited at the class level and calling `sub!` on a string that contains no `'Actor'` substring
- `Helpers::Base#runner_class` changed `sub!` to `sub` (non-destructive) as a defensive fix — `sub!` returns `nil` when no substitution is made, which caused `Kernel.const_get(nil)` to raise `TypeError`
- Runner reference returned by `hook_class.new.runner_class` is now resolved safely: string class names are resolved via `Kernel.const_defined?` + `Kernel.const_get`; Class objects are used directly; `nil` falls back to `hook_class`

## [1.6.30] - 2026-03-28

### Fixed
- `Legion::Extensions::Hooks::Base` now defines the `mount(path)` DSL method and `mount_path` reader — fixes `NoMethodError` boot crash in any extension hook that calls `mount` (e.g. `lex-microsoft_teams` `Hooks::Auth`)

## [1.6.29] - 2026-03-28

### Removed
- `ClassMethods` module (`expose_as_mcp_tool`, `mcp_tool_prefix`) from `Legion::Extensions::Helpers::Lex` — deprecated since the definition DSL was introduced; zero extensions use them

### Fixed
- Fallback route guards in `api.rb` now check `router.library_names.include?` instead of `defined?` — prevents 404s when gem modules are loaded but routes are not yet mounted (fixes #53)

## [1.6.28] - 2026-03-28

### Fixed
- `legion lex list` now displays extensions in clean aligned tables with Name, Version, Status, Runners, Actors columns
- Grouped view drops redundant category/tier columns from rows (already shown in group header); sorts alphabetically within each group
- Flat/category-filtered view uses Name, Version, Category, Status, Runners, Actors columns; sorts alphabetically
- Runners and actors are formatted as comma-joined names (up to 3) or a count summary instead of raw `Array#to_s` output
- JSON output for both flat and grouped list modes is now handled directly in the render methods

## [1.6.27] - 2026-03-28

### Fixed
- `Connection.ensure_crypt` now calls `resolve_secrets!` a second time after `Legion::Crypt.start` so that `lease://` URI refs are resolved once the LeaseManager is running (closes #50)

## [1.6.26] - 2026-03-28

### Added
- Absorber Router registration: `builders/absorbers.rb` now registers absorbers with `Legion::API.router` for v3.0 API discovery and dispatch (component_type: `absorbers`)
- Hook-aware LexDispatch: `POST /api/extensions/:lex/hooks/:name/:method` applies verify/route/transform lifecycle for `Hooks::Base` subclasses; auto-generated hooks pass through unchanged
- Transport message auto-generation: `auto_generate_messages` in `extensions/transport.rb` creates `Legion::Transport::Message` subclasses from runner definitions with inputs at boot time; explicit classes always take precedence
- `legion broker purge-topology` CLI command: detects old v2.0 AMQP exchanges (`legion.*`) that have v3.0 counterparts (`lex.*`) and optionally deletes them via RabbitMQ management API; defaults to `--dry-run`
- `spec/api/lex_dispatch_spec.rb`: 10-example spec covering v3.0 LexDispatch routes (replaces old lex_spec.rb)
- `spec/api/lex_dispatch_hooks_spec.rb`: 5-example spec for hook-aware dispatch (401/422/success/passthrough)
- `spec/api/old_systems_removed_spec.rb`: 10-example spec verifying old registries are gone
- `spec/cli/admin_command_spec.rb`: 21-example spec for topology detection logic
- `spec/extensions/builders/absorbers_spec.rb`: 10-example spec for absorber builder + Router registration
- `spec/extensions/transport_auto_messages_spec.rb`: 14-example spec for message auto-generation
- `unless defined?` guards on `Routes::Gaia`, `Routes::Transport`, `Routes::Rbac` registration for library gem self-registration

### Removed
- `Routes::Lex` (`api/lex.rb`): old `/api/lex/*` wildcard dispatcher — use `/api/extensions/:lex/runners/:name/:method`
- `Routes::Hooks` (`api/hooks.rb`): old `/api/hooks/lex/*` handler — use `/api/extensions/:lex/hooks/:name/:method`
- `Legion::API.hook_registry`, `.register_hook`, `.find_hook`, `.find_hook_by_path`, `.registered_hooks` — hooks auto-register via builder
- `Legion::API.route_registry`, `.register_route`, `.find_route_by_path`, `.registered_routes` — routes auto-register via builder

### Changed
- Routes builder log message now uses v3.0 path format (`/api/extensions/...` instead of `/api/lex/...`)

## [1.6.25] - 2026-03-28

### Added
- `Legion::Extensions::Absorbers::Dispatch`: module-function dispatch pipeline — `dispatch(input, context:)`, depth limiting, cycle detection via ancestor_chain, `dispatch_children`, `extract_urls`, thread-safe `@dispatched` registry
- `Legion::Extensions::Absorbers::PatternMatcher`: URL/file pattern registry — `register(absorber_class)`, `resolve(input)`, priority-ordered matching, `reset!`
- `Legion::Extensions::Absorbers::Transport`: v3.0 AMQP topology — `publish_absorb_request`, `build_message`, `lex_name_from_absorber_class`, `absorber_name_from_class`; exchanges named `lex.{lex_name}`, routing keys `lex.{lex_name}.absorbers.{name}.absorb`
- `Legion::Extensions::Absorbers::Base`: updated with `TokenRevocationError`, `TokenUnavailableError`, and `with_token(provider:, &block)` helper for OAuth-gated absorbers
- `Legion::Extensions::Absorbers::Matchers::File`: file-path pattern matcher using `File.fnmatch`
- `Legion::Auth::OauthCallback`: ephemeral TCP server for OAuth redirect callback — `wait_for_callback`, `parse_callback`; per-port lifecycle
- `Legion::Auth::TokenManager`: `TokenExpiredError`, `mark_revoked!`, `revoked?` for token lifecycle and revocation detection
- `Legion::CLI::ConnectCommand`: `legion connect microsoft`, `legion connect github`, `legion connect status`, `legion connect disconnect` — browser OAuth flow entry points registered as `legion connect` subcommand
- Chat URL detection: `Session#check_for_absorbable_urls` auto-dispatches matched URLs after each user message
- `spec/integration/absorber_pipeline_spec.rb`: 12-example end-to-end integration spec covering PatternMatcher resolution, Dispatch routing, transport suppression in lite mode, absorber → Apollo.ingest pipeline, depth/cycle guards

## [1.6.24] - 2026-03-28

### Added
- `Legion::API.register_library_routes(gem_name, routes_module)` class method: library gems self-register their Sinatra route modules at boot via `router.register_library` + Sinatra `register`. Implemented in `lib/legion/api/library_routes.rb`.
- `Legion::API::SyncDispatch.dispatch(exchange_name, routing_key, payload, envelope, timeout:)`: synchronous AMQP dispatch using a temporary exclusive reply_to queue with configurable timeout (default 30s). Implemented in `lib/legion/api/sync_dispatch.rb`.
- Remote dispatch in `LexDispatch`: when a registered extension route's runner class is not loaded in the current process, the request is forwarded via AMQP — async (202) by default or sync (blocks on reply queue) when `X-Legion-Sync: true` header is present. Returns 403 when `definition[:remote_invocable] == false`.
- `Routes::Llm` and `Routes::Apollo` registration now guarded: skipped in `api.rb` when `Legion::LLM::Routes` / `Legion::Apollo::Routes` are already defined (i.e. self-registered by the library gem).

### Changed
- `api.rb`: requires `api/library_routes` and `api/sync_dispatch`; LLM and Apollo route registration conditional on gem self-registration not already having run.

## [1.6.23] - 2026-03-28

### Added
- `Legion::Extensions::Definitions` mixin: class-level `definition` DSL for method contracts (`desc`, `inputs`, `outputs`, `remote_invocable`, `mcp_exposed`, `idempotent`, `risk_tier`, `tags`, `requires`). Auto-extended onto every runner module at boot by the builder.
- `Legion::Extensions::Actors::Dsl` mixin: `define_dsl_accessor` generates class-level getter/setter DSL with inheritance and instance delegation. Wired into all actor base classes (`Every`, `Poll`, `Subscription`, `Once`, `Base`).
- `Absorbers::Base#absorb`: canonical entry point replacing `handle`. `alias handle absorb` preserves backward compatibility.

### Changed
- `Builders::Runners#build_runner_list`: auto-extends `Legion::Extensions::Definitions` onto every discovered runner module unless it already responds to `:definition`.
- `Hooks::Base`: extended with `Definitions` mixin; `mount` DSL removed (paths fully derived from naming).
- `Absorbers::Base`: extended with `Definitions` mixin.
- `AbsorberDispatch`: calls `absorber.absorb` instead of `absorber.handle`.
- `Helpers::Lex`: all `function_*` helpers and `expose_as_mcp_tool`/`mcp_tool_prefix` marked `@deprecated` — use `definition` DSL instead.

## [1.6.22] - 2026-03-27

### Added
- `POST /api/llm/inference` daemon endpoint: accepts a full messages array plus optional tool schemas, runs a single LLM completion pass, and returns `{ content, tool_calls, stop_reason, model, input_tokens, output_tokens }` — the client owns the tool execution loop
- `Legion::CLI::Chat::DaemonChat` adapter: drop-in replacement for the `RubyLLM::Chat` object that routes all inference through the daemon, executes tool calls locally, and loops until the LLM produces a final text response
- `spec/legion/api/llm_inference_spec.rb`: 12 examples covering the new `/api/llm/inference` endpoint
- `spec/legion/cli/chat/daemon_chat_spec.rb`: 25 examples covering `DaemonChat` initialization, tool registration, tool execution loop, streaming, and error handling

### Changed
- `legion chat setup_connection`: replaced `Connection.ensure_llm` (local LLM boot) with a daemon availability check via `Legion::LLM::DaemonClient.available?` — **hard fails with a descriptive error if the daemon is not running**
- `legion chat create_chat`: now returns a `DaemonChat` instance instead of a direct `RubyLLM::Chat` object; all LLM calls route through the daemon

## [1.6.21] - 2026-03-27

### Added
- `legionio knowledge capture transcript` CLI command: ingests Claude Code session transcripts into Apollo knowledge store
- Stop hook for automatic transcript capture at session end (installed via `legion setup claude-code`)

## [1.6.20] - 2026-03-27

### Changed
- Bump `legion-logging` dependency to `>= 1.4.0` (required for `log_exception`, writer lambdas)

### Fixed
- `subscription.rb` (both `on_delivery` and `subscribe` blocks): initialize `fn = nil` before `process_message` so the rescue interpolation never raises `NameError` if message processing fails before `fn` is assigned
- `Helpers::Logger#lex_name` removed to avoid overriding `Helpers::Base#lex_name` (underscore contract used by settings/routing); renamed to private `log_lex_name` used only within this module for gem name derivation
- `Helpers::Logger#handle_exception`: use `spec&.version&.to_s` so nil spec version produces `nil` rather than `""` in structured log output
- README: update version badge from `v1.6.18` to `v1.6.20`

## [1.6.19] - 2026-03-27

### Fixed
- `teardown_logging_transport`: rescue block in `setup_logging_transport` now calls `teardown_logging_transport` to clean up any partially-created `@log_session` on failure
- `teardown_logging_transport`: guard `open?` call with `respond_to?(:open?)` check to avoid `NoMethodError` on session objects that do not implement the method
- `service_logging_transport_spec`: early-return specs now assert `create_dedicated_session` was not called and `@log_session` remains nil, rather than the vacuous `respond_to(:call)` check
- `service_logging_transport_spec`: replaced vacuous `not_to eq(owner)` assertion with `have_received(:create_dedicated_session)` to verify the dedicated session was actually created

## [1.6.18] - 2026-03-27

### Added
- `setup_logging_transport`: dedicated AMQP session for log and exception forwarding, replacing the previous `register_logging_hooks` approach; writer lambda wiring is gated by `Settings[:logging][:transport]` feature flags
- `teardown_logging_transport`: cleanly shuts down the dedicated logging AMQP session during the shutdown sequence

### Changed
- Split `log.error(e.message); log.error(e.backtrace)` patterns replaced with `log.log_exception` across 14 files for structured, single-call exception logging
- `Extensions::Helpers::Logger#handle_exception` rewritten to use `log.log_exception` with full lex context

### Fixed
- `legionio pipeline image analyze`: `call_llm` no longer passes unsupported `messages:` keyword to `Legion::LLM.chat`; now creates a chat object and sends multimodal content via `chat.ask`, returning a plain hash with `:content` and `:usage` keys
- `legionio ai trace search/summarize`: both commands now call `setup_connection` before invoking `TraceSearch`, ensuring `Legion::LLM` is booted so `TraceSearch.generate_filter` can use structured LLM output instead of returning "no filter generated"; added `class_option :config_dir` and `class_option :verbose` to `TraceCommand`

## [1.6.17] - 2026-03-27

### Fixed
- `legionio check`: `resolve_secrets!` is now called after a successful crypt check so `lease://`, `vault://`, and `env://` credential URIs are resolved before transport/data checks attempt to connect
- `legionio check transport`: raises an early descriptive error when transport credentials are still unresolved URI references (Vault lease pending), instead of failing with a confusing connection error
- `legionio check data`: raises an early descriptive error when database credentials are still unresolved URI references (Vault lease pending)
- `legionio llm status/providers/models`: `boot_llm_settings` now calls `resolve_secrets!` so `env://` and `vault://` API key references are resolved before provider enabled-state is evaluated
- `legionio llm providers`: providers with unresolved credential URIs are now shown as `deferred (credentials pending Vault)` in yellow instead of incorrectly `disabled`
- `Connection.ensure_settings`: calls `resolve_secrets!` after loading settings so `env://` references are resolved in all CLI commands that use the lazy connection manager

## [1.6.16] - 2026-03-27

### Fixed
- `config validate` transport host check now reads from `transport.connection.host` instead of `transport.host` (correct config nesting)
- `doctor diagnose` now loads settings via `Connection.ensure_settings` before running checks, so cache/database/vault/extensions checks no longer skip due to `Legion::Settings` being undefined; also adds `ensure Connection.shutdown` for clean teardown

## [1.6.15] - 2026-03-27

### Added
- Absorbers: new LEX component type for pattern-matched content acquisition
- `Absorbers::Base` class with `pattern`/`description` DSL and knowledge helpers (`absorb_to_knowledge`, `absorb_raw`, `translate`, `report_progress`)
- `Absorbers::Matchers::Base` auto-registering matcher interface with `Matchers::Url` for URL glob matching
- `Absorbers::PatternMatcher` for thread-safe input-to-absorber resolution with priority-based dispatch
- `Builders::Absorbers` for auto-discovery of absorber classes during extension boot
- `Capability.from_absorber` factory method for Capability Registry integration
- `AbsorberDispatch` module for pattern resolution and handler execution
- `legionio absorb` CLI command with `url`, `list`, and `resolve` subcommands
- `legionio dev generate absorber` scaffolding template

## [1.6.14] - 2026-03-27

### Added
- `Legion::Compliance` module rewritten with DEFAULTS hash, `merge_settings` registration, and clean API
- `Compliance.setup` registers max-classification defaults: PHI, PCI, PII, FedRAMP all enabled by default
- `Compliance.enabled?`, `.phi_enabled?`, `.pci_enabled?`, `.pii_enabled?`, `.fedramp_enabled?` convenience methods
- `Compliance.classification_level` returns `'confidential'` by default (highest level)
- `Compliance.profile` returns a hash with all compliance flags for downstream consumers
- `setup_compliance` wired into Service boot sequence after settings load
- Compliance profile spec (8 examples)

### Changed
- `Compliance.phi_enabled?` now uses `Settings.dig(:compliance, :phi_enabled)` instead of chaining `[]` calls
- Existing PhiTag and PhiAccessLog specs updated to use `merge_settings` instead of stubbing `Settings.[]`

## [1.6.13] - 2026-03-27

### Added
- `DigitalWorker.heartbeat` method for updating worker health status and last heartbeat timestamp
- `DigitalWorker.detect_orphans` method to find workers with stale or nil heartbeats
- `DigitalWorker.pause_orphans!` method to auto-pause orphaned workers with event emission
- Consent tier sync on lifecycle transitions: `worker.update` now includes `consent_tier` from `CONSENT_MAPPING`
- `Lifecycle.sync_consent_tier` calls `lex-consent` runner when available, graceful degradation when not
- Per-worker SSE events at `/api/workers/:id/events?stream=true` with queue-per-client filtering
- Polling fallback for per-worker events via ring buffer filtering (default mode)

## [1.6.11] - 2026-03-26

### Added
- `Legion::Dispatch` module with pluggable strategy interface and `Local` implementation using `Concurrent::FixedThreadPool`
- Local dispatch wiring in `extensions.rb`: `dispatch_local_actors` registers non-remote extensions in thread pool
- `Ingress.local_runner?` short-circuit: runners for `remote_invocable? false` extensions skip AMQP round-trip
- `setup_dispatch` in `Service` boot sequence with graceful shutdown
- `legion broker stats` and `legion broker cleanup` CLI commands for RabbitMQ management
- End-to-end integration test for TBI Phase 5 self-generating functions loop (9 examples)
- Test dependencies: lex-codegen, lex-eval added to Gemfile for integration testing
- Specs for `legion codegen` CLI subcommand (8 subcommands, 22 examples)
- Specs for `/api/codegen/*` API routes (8 routes, 20 examples)
- Specs for `setup_generated_functions` boot loading in Service (4 examples)

### Fixed
- Guard `Legion::Transport::Messages::Dynamic` stub definition in integration spec with `unless defined?` to prevent redefinition conflicts when real implementations are present
- Wrap `lex-codegen` and `lex-eval` requires in `LoadError` rescue guards in integration spec; sets `LEGION_CODEGEN_EXTENSION_AVAILABLE` / `LEGION_EVAL_EXTENSION_AVAILABLE` flags and skips entire example group via `before(:all)` when extensions are unavailable
- Move `Legion::LLM.chat` stub to `RSpec.configure before(:each)` block so it always intercepts regardless of whether the real `legion-llm` gem is loaded, preventing external LLM calls in integration tests
- Fix `service_setup_apollo_spec` "starts Apollo::Local" example: stub `Legion::Apollo.start` to prevent internal double-call of `Apollo::Local.start`

## [1.6.10] - 2026-03-26

### Changed
- `ConfigImport.write_config` now splits recognized subsystem keys (`microsoft_teams`, `rbac`, `api`, `logging`, `gaia`, `extensions`, `llm`, `data`, `cache_local`, `cache`, `transport`, `crypt`, `role`) into individual `{key}.json` files
- Remaining unrecognized keys written to `bootstrapped_settings.json` (replaces `imported.json`)
- Subsystem files are always overwritten on bootstrap; remainder file respects `--force` for merge behavior
- `write_config` returns an array of written paths instead of a single path
- `legion bootstrap` and `legion config import` updated to display per-file write confirmations

## [1.6.9] - 2026-03-26

### Added
- `Helpers::Secret` mixin with `SecretAccessor` for per-user and per-lex Vault KV v2 secret access
- Identity resolution chain: Kerberos principal -> Entra UPN -> explicit user -> ENV['USER']
- `secret[:name]` / `secret[:name] = { ... }` / `secret.write` / `secret.exist?` / `secret.delete`
- `shared: true` option for extension-scoped (non-user) secrets

## [1.6.8] - 2026-03-26

### Added
- `legionio bootstrap SOURCE` command: combines `config import`, `config scaffold`, and `setup agentic` into one command
- Pre-flight checks for klist (Kerberos ticket), brew availability, and legionio binary
- `--skip-packs`, `--start`, `--force`, `--json` flags for bootstrap command
- Self-awareness system prompt enrichment: `Context.to_system_prompt` appends live metacognition self-narrative from `lex-agentic-self` when loaded; guarded with `defined?()` and `rescue StandardError`

## [1.6.7] - 2026-03-26

### Fixed
- `setup_generated_functions` now runs only when `extensions: true` (inside the extensions gate) preventing unexpected boot side-effects in CLI flows that disable extensions
- Consumer tag entropy upgraded from `SecureRandom.hex(4)` (32-bit) to `SecureRandom.uuid` (122-bit) in both `prepare` and `subscribe` paths of subscription actor, eliminating the theoretical RabbitMQ `NOT_ALLOWED` tag collision

## [1.6.4] - 2026-03-26

### Fixed
- fix consumer tag collision on boot: subscription actors using `Thread.current.object_id` produced duplicate tags when `FixedThreadPool` reused threads, causing RabbitMQ `NOT_ALLOWED` connection kill and cascading errors; replaced with `SecureRandom.hex(4)`

## [1.6.3] - 2026-03-26

### Changed
- `legionio update` now uses `gem outdated` instead of custom HTTP client to check rubygems.org
- Remove `concurrent-ruby`, `net/http`, `json` dependencies from update command
- 4 persistent keep-alive connections replaced by single `gem outdated` call (~8s, 100% reliable)

## [1.6.2] - 2026-03-26

### Fixed
- `legionio update` remote check failed for all gems due to TCP connection exhaustion (24 parallel SSL connections to rubygems.org)
- Replace thread pool with 4 batched threads using persistent HTTP keep-alive connections (55 gems in ~4s)

## [1.6.1] - 2026-03-26

### Fixed
- `legionio update` now shows "(remote check failed)" instead of "(already latest)" when rubygems.org fetch fails
- Add HTTP timeouts (5s connect, 10s read) to remote version checks to prevent thread pool exhaustion
- Install failures now show "(install may have failed)" instead of "(already latest)"
- Distinct statuses: current, check_failed, installed, failed (was single ambiguous "updated" for all)

## [1.6.0] - 2026-03-26

### Added
- `legion codegen` CLI subcommand (status, list, show, approve, reject, retry, gaps, cycle)
- `/api/codegen/*` API routes for generated function management
- Boot loading for generated functions via GeneratedRegistry
- Function metadata DSL (function_outputs, function_category, function_tags, function_risk_tier, function_idempotent, function_requires, function_expose)
- ClassMethods for MCP tool exposure (expose_as_mcp_tool, mcp_tool_prefix)
- End-to-end integration test for self-generating functions
- `legion knowledge monitor add/list/remove/status` — multi-directory corpus monitor management
- `legion knowledge capture commit` — capture git commit as knowledge (hook-compatible)
- `legion knowledge capture session` — capture session summary as knowledge (hook-compatible)
- `legion setup claude-code` now installs write-back hooks for automatic knowledge capture
- `resolve_corpus_path` falls back to first registered monitor when no explicit path given

## [1.5.23] - 2026-03-26

### Changed
- Remove all lex-memory references from service.rb, API coldstart, and OpenAPI docs; use lex-agentic-memory namespace everywhere

## [1.5.22] - 2026-03-26

### Fixed
- `coldstart ingest` no longer crashes when lex-memory is absent; uses lex-agentic-memory trace store instead

### Changed
- Consolidate 48 root CLI commands into 7 groups + 19 root commands
- New groups: `ai`, `git`, `pipeline`, `ops`, `serve`, `admin`, `dev`
- `ai`: chat, llm, gaia, apollo, knowledge, memory, mind-growth, swarm, plan, trace
- `git`: commit, pr, review
- `pipeline`: skill, prompt, eval, dataset, image, notebook
- `ops`: telemetry, observe, detect, cost, payroll, audit, debug, failover
- `serve`: mcp, acp
- `admin`: rbac, auth, worker, team
- `dev`: generate, docs, openapi, completion, marketplace, features
- Root keepers: start, stop, status, version, check, doctor, setup, update, config, init, lex, task, chain, schedule, coldstart, tty, do, ask, dream, tree

## [1.5.21] - 2026-03-26

### Changed
- `legionio setup agentic` now installs the full cognitive stack (63 gems): core libs, all agentic domains, all AI providers, and key operational extensions
- Added `brains` and `give-me-all-the-brains` as aliases for the `agentic` subcommand

## [1.5.20] - 2026-03-26

### Added
- `legion knowledge health` — local/Apollo/sync health report
- `legion knowledge maintain` — orphan chunk detection and cleanup (dry-run by default)
- `legion knowledge quality` — hot/cold/low-confidence chunk quality report

## [1.5.19] - 2026-03-26

### Added
- `legion knowledge` CLI subcommand: query, retrieve, ingest, status (closes #36)
  - `legion knowledge query QUESTION` — synthesized LLM answer + ranked source chunks
  - `legion knowledge retrieve QUESTION` — raw source chunks without synthesis
  - `legion knowledge ingest PATH` — ingest file or directory corpus
  - `legion knowledge status` — show corpus file count and size

## [1.5.18] - 2026-03-25

### Added
- `scope:` parameter on `Helpers::Knowledge` (`ingest_knowledge` and `query_knowledge`)
- Scope routing: `:local` -> `Apollo::Local`, `:global` -> `Apollo`, `:all` -> both with local-first dedup
- Default query scope configurable via `Settings[:apollo][:local][:default_query_scope]`
- `setup_apollo` now starts `Apollo::Local` when available

## [1.5.17] - 2026-03-25

### Added
- `Helpers::Knowledge` — universal `ingest_knowledge` and `query_knowledge` mixin for all extensions; included automatically in `Extensions::Core`
- Automatic file extraction via `Legion::Data::Extract` when a file path is passed to `ingest_knowledge`
- Graceful degradation when `Legion::Apollo` or `Legion::Data::Extract` are not available
- `setup_apollo` in `Service` boot sequence (between LLM and GAIA); wires `Legion::Apollo.start` with `LoadError`/`StandardError` rescue
- `:apollo` added to `Readiness::COMPONENTS` between `:llm` and `:gaia`
- `legion-apollo >= 0.2.1` dependency in gemspec
- `Helpers::LLM#llm_embed` in LegionIO now forwards all keyword arguments (`provider:`, `dimensions:`, etc.) via anonymous `**` forwarding

## [1.5.15] - 2026-03-25

### Removed
- CLI chat Apollo writeback prototype (replaced by pipeline step 19 in legion-llm)

## [1.5.14] - 2026-03-25

### Fixed
- Shutdown no longer hangs when network is unreachable — all component shutdowns wrapped in bounded timeouts via `shutdown_component` helper (#30)
- Reload path also wrapped with same timeout guards to prevent hangs during network-triggered reload (#30)

### Added
- Network watchdog: background `Concurrent::TimerTask` monitors transport/data/cache connectivity, pauses actors after sustained failures, triggers `Legion.reload` when network restores (#30)
- `Legion::Extensions.pause_actors` suspends all `Every` timer tasks without destroying instances (#30)
- Watchdog is feature-flagged via `network.watchdog.enabled` (default: false), configurable threshold and interval (#30)

## [1.5.13] - 2026-03-25

### Fixed
- API startup no longer spams Puma banner on port conflict — pre-checks port with lightweight TCP probe before attempting Puma boot
- Reduced API bind retries from 10 to 3 (6s total vs 30s) so boot completes quickly when port is occupied
- Daemon remains fully functional (shutdown, Ctrl+C) even when API fails to bind

## [1.5.12] - 2026-03-25

### Added
- `GET /api/stats` endpoint — comprehensive daemon runtime stats: extensions (loaded/actor counts), gaia (status/channels/phases), transport (session/channels), cache/cache_local (pool stats), llm (provider health/routing), data/data_local (pool/tuning via legion-data stats), api (puma threads/routes)

### Changed
- Bumped gemspec dependency: legion-data >= 1.6.0 (required for `Legion::Data.stats`)

## [1.5.11] - 2026-03-25

### Added
- `legionio debug` command — full diagnostic dump (16 sections: versions, doctor, config, gems, extensions, RBAC, LLM, GAIA, transport, events, Apollo, remote/local Redis, PostgreSQL, RabbitMQ, API health) output as markdown or JSON, suitable for piping to an LLM session
- `legionio update --cleanup` flag — removes old gem versions after update via `Gem::Uninstaller` (default: no cleanup)

### Fixed
- `update_command.rb` `snapshot_versions` now uses `find_all_by_name` + max version instead of `find_by_name`, which returned the already-activated (potentially stale) gem version
- `service.rb` `setup_api` guard prevents duplicate Puma start when `@api_thread` is already alive

### Changed
- Bumped gemspec dependencies: legion-data >= 1.5.3, legion-gaia >= 0.9.24, legion-llm >= 0.5.8, legion-tty >= 0.4.35

## [1.5.10] - 2026-03-25

### Changed
- Guard bootsnap behind `LEGION_BOOTSNAP=true` env var in `exe/legion` and `exe/legionio`, default to disabled
- Bootsnap also requires `~/.legionio` to exist (prevents premature directory creation on first run)

## [1.5.9] - 2026-03-25

### Fixed
- `Subscription#activate` nil guard — skip activate when `@consumer` is nil (prepare failed silently)
- `Extensions#shutdown` tracks real actor instances in `@running_instances`, cancels them with deadline-based drain
- `Extensions::Helpers::Base` runner_class derivation improvements for self-contained actors

### Changed
- Bumped gemspec dependencies: legion-cache >= 1.3.16, legion-settings >= 1.3.19, legion-transport >= 1.4.0, legion-mcp >= 0.5.1

## [1.5.8] - 2026-03-24

### Added
- `Legion::Compliance::PhiTag` — PHI data classification tagging with `phi?`, `tag`, `tagged_cache_key` methods; gated by `compliance.phi_enabled` setting
- `Legion::Compliance::PhiAccessLog` — PHI access audit bridge that calls `Legion::Audit.record` with `event_type: 'phi_access'`; gated by `compliance.phi_enabled` setting
- `Legion::Compliance::PhiErasure` — orchestrates cryptographic erasure via `Legion::Crypt::Erasure`, cache key purge, access log, and verification; all steps guarded by `defined?` checks

## [1.5.7] - 2026-03-24

### Added
- `Legion::Audit::Archiver` — tiered hot/warm/cold audit retention orchestrator; delegates hot→warm to `Legion::Data::Retention`, exports warm→cold as compressed JSONL via `ColdStorage`, records manifests, verifies hash chain after each run
- `Legion::Audit::ColdStorage` — upload/download abstraction with `:local` (filesystem) and `:s3` (aws-sdk-s3, optional) backends; raises `BackendNotAvailableError` when aws-sdk-s3 not installed
- `Legion::Audit::ArchiverActor` — thread-based weekly scheduled actor with hour/day-of-week cron guard; started by `Service#setup_audit_archiver` after telemetry
- `legion audit archive --dry-run / --execute` — preview or execute tiered archival from CLI
- `legion audit verify_chain --tier --start --end` — direct hash chain integrity check for hot or warm tier
- `legion audit restore --date` — restore cold JSONL archives back to warm tier for querying
- Feature flag: `audit.retention.enabled` (default `false`); settings: `hot_days`, `warm_days`, `cold_years`, `cold_storage`, `cold_backend`, `archive_schedule`, `verify_on_archive`

### Changed
- `Legion::Service` starts `CertRotation` after `Crypt.start` when `security.mtls.enabled: true`
- `Legion::Service#shutdown` stops `CertRotation` before `Crypt.shutdown`
- `setup_mtls_rotation` gracefully handles missing mtls support in older `legion-crypt` versions via `LoadError` rescue

## [1.5.6] - 2026-03-24

### Changed
- `Service#register_logging_hooks` uses dedicated `log_channel` from `Connection` instead of shared channel; passes `channel:` to `Exchanges::Logging` to avoid contention
- `Service#reload` re-setup sequence now includes `register_logging_hooks`, cache re-setup, and guarded `setup_rbac`/`setup_llm`/`setup_gaia` calls
- `Readiness::COMPONENTS` expanded with `:rbac` and `:llm` for accurate startup tracking
- LLM and GAIA boot blocks gated so `mark_ready` only fires on success path
- `Cache` and `Data` boot blocks wrap remote failures with graceful fallback to local adapters

## [1.5.5] - 2026-03-24

### Added
- `Legion::Service#setup_api`: optional Puma TLS via `api.tls.enabled` feature flag (default false); falls back to plain HTTP if cert/key missing
- `Legion::CLI::Doctor::TlsCheck`: `legion doctor` check for TLS configuration across all components (transport, data, api)
- `config/tls/settings-tls.json`: complete TLS settings template for all components
- `config/tls/generate-certs.sh`: dev self-signed CA + server/client cert generator
- `config/tls/README.md`: TLS setup and validation instructions

## [1.5.4] - 2026-03-24

### Added
- `Cluster::Leader` wired into `Service` boot behind `cluster.leader_election` feature flag (default: off)
- `Actors::Singleton` upgraded to dual-backend (Redis + PG advisory locks via `Cluster::Lock`)
- `Singleton` gating controlled by `cluster.singleton_enabled` feature flag (default: off — every node runs, no behavior change)
- `Cluster::Lock.extend_lock` method (Redis: Lua TTL extend; PG: always true; none: false)
- `Singleton` mixin added to lex-health watchdog and lex-metering cleanup/cost_optimizer actors

### Changed
- `@cluster_leader.stop` called on `Service#shutdown` (before extensions shutdown)

## [1.5.3] - 2026-03-24

### Added
- Extinction escalation verification in lifecycle integration tests (stub_const approach)
- De-escalation on worker resume: `transition!` calls `Client#deescalate` when extinction level decreases
- Credential revocation on worker termination: calls `VaultSecrets.delete_client_secret` guarded by `defined?`
- Ownership transfer integration tests with event and audit verification
- Retirement cycle integration tests with full audit chain and extinction L3/L4 coverage

## [1.5.2] - 2026-03-24

### Fixed
- `check_cache_local` in CLI now reads display values from `Legion::Settings[:cache_local]` instead of static code defaults

## [1.5.1] - 2026-03-24

### Added
- Wire lex-extinction into digital worker lifecycle transitions
- `EXTINCTION_MAPPING` maps lifecycle states to containment levels (0-4)
- Guarded `Client#escalate` call during `transition!` when containment level increases

## [1.5.0] - 2026-03-24

### Added
- `legion setup agentic` — install full cognitive stack (legion-gaia + legion-llm + all transitive deps) in one command
- `legion setup llm` — install LLM routing only
- `legion setup channels` — install channel adapters (lex-slack, lex-microsoft_teams)
- `legion setup packs` — show installed/missing feature packs
- `--dry-run` flag on all pack install commands
- `legion detect` now recommends `legion setup agentic` when legion-gaia or legion-llm are missing
- `legionio version --full` displays all installed lex-* extension versions
- `legionio version` now lists all 13 legion-* gems with `(not installed)` for missing ones

### Changed
- Overhaul `legionio check` with proper namespace labels (Legion::Settings, Legion::Transport, etc.)
- Each check returns connection detail strings (config dir, amqp:// URL, driver -> servers, adapter -> host:port/db)
- Add Legion::Cache::Local and Legion::Data::Local checks with dependency chaining
- Fix dependency skip logic to cascade through transitive dependencies (skip-on-skip, not just skip-on-fail)
- Add privacy mode sub-check (`legionio check --privacy`)
- Comment out Bootsnap.setup in exe/legion (matching exe/legionio)
- Bump gemspec minimum: legion-data >= 1.5.0

### Fixed
- Runner log output now tagged with extension name (e.g. `[mesh][Runner]` instead of bare `[Runner]`)
- Extension Transport and Routes builders use tagged `log` helper instead of bare `Legion::Logging`
- Runner.run now sets `status = 'task.exception'` before calling `handle_exception`, preventing null function/result in CheckSubtask messages when handle_exception raises

## [1.4.198] - 2026-03-24

### Changed
- Comment out Bootsnap.setup in exe/legion (matching exe/legionio)

## [1.4.198] - 2026-03-24

### Changed
- Bump gemspec minimum: legion-transport >= 1.3.11 (InProcess adapter, shutdown hang fix, Helper mixin)
- Bump gemspec minimum: legion-tty >= 0.4.34 (latest fixes)

## [1.4.197] - 2026-03-24

### Changed
- Add debug logging to 8 swallowed `rescue StandardError` blocks in chat tools and session store: ModelComparison, SystemStatus (fetch_health, fetch_ready), SessionStore (generate_summary, read_session_meta), SaveMemory (ingest_to_apollo), GenerateInsights (scheduling_status, llm_status)

## [1.4.196] - 2026-03-24

### Added
- LLM fallback in `legion do` command: when keyword matching (`find_by_intent`) returns no results, classifies intent via `Legion::LLM.ask` against the full Capability Registry catalog
- Graceful degradation: LLM path only activates when both `Legion::LLM` and `Catalog::Registry` are loaded; errors fall through silently

## [1.4.195] - 2026-03-24

### Added
- `legion do "TEXT"` CLI command: natural language intent router that matches free-text to Capability Registry entries and dispatches via daemon API or in-process Ingress
- `DoCommand` module with two resolution paths: daemon HTTP dispatch (like `dream`) and in-process `Registry.find_by_intent` + `Ingress.run` fallback

## [1.4.194] - 2026-03-24

### Added
- `--lite` flag on `legion start` command: sets `LEGION_MODE=lite` and `LEGION_LOCAL=true` env vars, assigns `:lite` process role
- `:lite` process role in `ProcessRole::ROLES`: all subsystems enabled except `crypt: false` (Vault not needed in lite mode)
- `Service#lite_mode?` checks `LEGION_MODE` env var and `settings[:mode]`
- `setup_local_mode` handles lite mode: sets dev flag, loads Transport::Local, loads mock_vault if Crypt is defined

## [1.4.193] - 2026-03-24

### Added
- `legion mind-growth` CLI subcommand with 10 commands: status, propose, approve, reject, build, proposals, profile, health, report, history
- Delegates to `Legion::Extensions::MindGrowth::Client` (lex-mind-growth extension)
- Guards with `require_mind_growth!` — raises `CLI::Error` when extension is not loaded
- Supports `--json` and `--no-color` class options on all subcommands

## [1.4.192] - 2026-03-24

### Fixed
- fix `undefined method 'key?' for module Legion::Settings` in extension loader — use `Legion::Settings[:llm].nil?` instead of `.key?(:llm)` since Settings is a module with `[]` accessor, not a Hash

## [1.4.191] - 2026-03-23

### Changed
- Add `caller: { source: 'cli', command: 'chat' }` to `Legion::LLM.chat` call in `CLI::ChatCommand#create_chat`, completing Wave 5 consumer migration

## [1.4.190] - 2026-03-23

### Changed
- Migrate `Guardrails::RAGRelevancy` to use `Legion::LLM.chat` (public API) instead of the private `chat_single` method
- Add `Guardrails::SYSTEM_CALLER` constant with system pipeline identity to prevent infinite recursion when guardrails calls the LLM through the pipeline
- The `:system` profile skips governance steps (rbac, classification, billing, gaia_advisory, rag_context, context_load) — guardrails is internal infrastructure, not a user request
- Add specs covering `SYSTEM_CALLER` structure and LLM call behavior in `RAGRelevancy`

## [1.4.189] - 2026-03-23

### Changed
- Add `caller:` identity to all LLM calls in API, CLI, extensions, and internal modules
  - `API::Routes::Llm` sync path: `caller: { source: 'api', path: request.path }`
  - `API::Routes::Prompts`: `caller: { source: 'api', endpoint: 'prompts' }`
  - `CLI::Commit`, `CLI::Pr`, `CLI::Review`, `CLI::Prompt`, `CLI::Image`: `caller: { source: 'cli', command: '<cmd>' }`
  - `Notebook::Generator`: `caller: { source: 'cli', command: 'notebook' }`
  - `TraceSearch`: `caller: { source: 'cli', command: 'trace' }`
  - `Extensions` inline LLM runners: `caller: { source: 'extension', command: 'llm_runner' }`

## [1.4.188] - 2026-03-23

### Changed
- Bump legion-mcp dependency to >= 0.5.1
- Bump legion-data dependency to >= 1.4.19

## [1.4.187] - 2026-03-23

### Added
- `Legion::Extensions::Capability` Data.define struct for extension capability registration
- `Legion::Extensions::Catalog::Registry` in-memory capability registry with register, find, find_by_intent, for_mcp, for_override, find_by_mcp_name
- `register_capabilities` populates Catalog::Registry from extension runners at boot
- `unregister_capabilities` removes capabilities from Catalog on extension unload
- `Catalog::Registry.on_change` callback for notifying consumers on registry changes

## [1.4.186] - 2026-03-23

### Fixed
- `CLI::Connection#resolve_config_dir` expands tilde in user-provided `config_dir` before existence check (#25)
- `.github/CODEOWNERS` combined duplicate `*` patterns so both teams are applied (#25)

### Added
- `Service#setup_settings` spec coverage for canonical directory filtering (#25)
- `CLI::Connection` spec for tilde expansion in `config_dir` (#25)

## [1.4.185] - 2026-03-23

### Fixed
- Restrict settings search paths to canonical directories (`~/.legionio/settings`, `/etc/legionio/settings`) (#25)
- Remove broken/dead paths from `Service#default_paths` (`~/legionio`, `$home/legionio`, `./settings`)
- `CLI::Connection#resolve_config_dir` now delegates to `Loader.default_directories` instead of hardcoded list
- Add `legion-settings` local path to Gemfile for development

### Changed
- `Service#setup_settings` loads all matching directories via `config_dirs:` instead of first-match-wins

## [1.4.184] - 2026-03-23

### Added
- MemoryStatus chat tool: shows persistent memory entries, Apollo knowledge store stats, and saved session overview
- Supports "overview", "memories", "apollo", and "sessions" actions
- 40th built-in chat tool registered in ToolRegistry

## [1.4.183] - 2026-03-23

### Added
- ContextManager: conversation context window management with dedup, compression, and summarization strategies
- `/compact [strategy]` now supports auto, dedup, and summarize strategies (was LLM-only)
- `/context` slash command shows message count, estimated tokens, and auto-compact status
- Integrates with Legion::LLM::Compressor for Jaccard deduplication and stopword compression

## [1.4.182] - 2026-03-23

### Changed
- GenerateInsights now includes Apollo graph topology, LLM scheduling status, escalation count, and shadow eval count
- Insights report provides a more comprehensive system overview

## [1.4.181] - 2026-03-23

### Added
- SchedulingStatus chat tool: view LLM peak/off-peak scheduling and batch queue state
- Supports "overview", "scheduling" (detail), and "batch" (queue detail) actions
- 39th built-in chat tool registered in ToolRegistry

## [1.4.180] - 2026-03-23

### Added
- GraphExplore chat tool: explore Apollo knowledge graph topology, agent expertise, and disputed entries
- Apollo API endpoints: GET /api/apollo/graph (topology) and GET /api/apollo/expertise (expertise map)
- 38th built-in chat tool registered in ToolRegistry

## [1.4.179] - 2026-03-23

### Added
- EscalationStatus chat tool: show model escalation history and upgrade frequency
- Supports "summary" (by reason, target model, recent entries) and "rate" (escalation frequency) actions
- 37th built-in chat tool registered in ToolRegistry

## [1.4.178] - 2026-03-23

### Added
- ArbitrageStatus chat tool: view LLM cost arbitrage table, cheapest model per capability tier
- Supports overview mode (full cost table + tier picks) and per-tier detail mode
- 36th built-in chat tool registered in ToolRegistry

## [1.4.177] - 2026-03-23

### Added
- EntityExtract chat tool: extract named entities (people, services, repos, concepts) from text via Apollo
- Supports entity type filtering and configurable confidence thresholds
- Groups results by type with confidence percentages
- 35th built-in chat tool registered in ToolRegistry

## [1.4.176] - 2026-03-23

### Added
- ShadowEvalStatus chat tool: view shadow evaluation results comparing primary vs cheaper models
- Supports "summary" (cost savings, length ratios) and "history" (recent comparisons) actions
- 34th built-in chat tool registered in ToolRegistry

## [1.4.175] - 2026-03-23

### Added
- ModelComparison chat tool: compare LLM model pricing side-by-side with cost projections
- Supports filtering by model name, custom token count estimates, and price ratio analysis
- Uses CostTracker pricing when available, falls back to built-in defaults
- 33rd built-in chat tool registered in ToolRegistry

## [1.4.174] - 2026-03-23

### Added
- REST API endpoints for LLM provider health: GET /api/llm/providers and GET /api/llm/providers/:name
- Returns circuit breaker state, health status, routing adjustments, and circuit summary
- 4 new specs covering gateway unavailable, health report, and single provider detail

## [1.4.173] - 2026-03-23

### Added
- ProviderHealth chat tool: displays LLM provider circuit breaker state, health status, and routing adjustments
- Supports all-provider report and single-provider detail views
- 33rd built-in chat tool registered in ToolRegistry

## [1.4.172] - 2026-03-23

### Added
- BudgetStatus chat tool: shows session cost budget status, spending, remaining, and per-model breakdown
- Works locally via in-memory CostTracker (no daemon required)
- Supports "status" and "summary" actions
- 32nd built-in chat tool registered in ToolRegistry

## [1.4.171] - 2026-03-23

### Added
- SearchTraces chat tool: natural language search across cognitive memory traces (people, conversations, meetings)
- Person name variant matching, fuzzy search, keyword ranking, and structured field extraction
- 11th built-in chat tool registered in ToolRegistry

## [1.4.170] - 2026-03-23

### Added
- Costs REST API: GET /api/costs/summary, /api/costs/workers, /api/costs/extensions
- Aggregates metering_records cost_usd by time period, worker, and extension
- 8 specs with in-memory SQLite for realistic query testing

## [1.4.169] - 2026-03-23

### Fixed
- TraceSearch column name mismatches: `created_at` to `recorded_at`, `tokens_in` to `input_tokens`, `tokens_out` to `output_tokens` to match metering_records schema
- SCHEMA_TEMPLATE and ALLOWED_COLUMNS now reference correct database column names

## [1.4.168] - 2026-03-23

### Added
- GenerateInsights chat tool: combines anomaly detection, trends, Apollo stats, and worker health into actionable report
- Automatic recommendations based on detected anomalies and trend patterns
- 7 specs covering comprehensive report generation, anomaly details, recommendations, and error handling
- Chat tool registry now has 30 built-in tools

## [1.4.167] - 2026-03-23

### Added
- TriggerDream chat tool: trigger dream cycles on daemon and view latest dream journal entries
- Searches gem path, project, and user directories for dream journal markdown files
- 6 specs covering trigger, journal, error handling, truncation, and connection refused
- Chat tool registry now has 29 built-in tools

## [1.4.166] - 2026-03-23

### Added
- ViewTrends chat tool: tabular trend visualization with direction indicators (rising/falling/stable)
- Shows cost, latency, volume, and failure rate trends over configurable time ranges
- 6 specs covering trend formatting, direction labels, empty data, API errors, and connection handling
- Chat tool registry now has 28 built-in tools

## [1.4.165] - 2026-03-23

### Added
- TraceSearch.trend: time-bucketed metrics trend analysis over configurable time ranges
- GET /api/traces/trend endpoint with hours and buckets parameters
- 7 new specs covering trend data structure, bucket contents, defaults, and API endpoint

## [1.4.164] - 2026-03-23

### Added
- DetectAnomalies chat tool: proactive anomaly detection via daemon API with configurable threshold
- Reports cost spikes, latency increases, and failure rate changes with severity levels
- 6 specs covering healthy system, anomaly detection, custom threshold, API errors, connection refused, and singular grammar
- Chat tool registry now has 27 built-in tools

## [1.4.163] - 2026-03-23

### Added
- Traces REST API: POST /api/traces/search, POST /api/traces/summary, GET /api/traces/anomalies
- require_trace_search! API helper guards routes when LLM subsystem is unavailable
- SearchTraces chat tool for natural language memory trace search via lex-agentic-memory
- 10 new API specs covering all trace endpoints with availability guards and parameter handling

## [1.4.162] - 2026-03-23

### Added
- TraceSearch.detect_anomalies: compares last-hour metrics against 24h baseline to detect cost, latency, and failure rate spikes
- Anomaly detection uses configurable threshold (default 2x) with severity levels (warning/critical)
- 4 new TraceSearch specs covering anomaly report structure, cost spike detection, normal metrics, and zero baseline handling

## [1.4.161] - 2026-03-23

### Added
- WorkerStatus chat tool: list digital workers, show details, and health summary via daemon API
- WorkerStatus spec with 7 examples covering list, filter, show, health, empty state, and connection errors
- Chat tool registry now has 26 built-in tools

## [1.4.160] - 2026-03-23

### Added
- ManageSchedules chat tool: list, show, logs, and create scheduled tasks via daemon API
- ManageSchedules spec with 10 examples covering all actions, validation, empty states, and connection errors
- Chat tool registry now has 25 built-in tools

## [1.4.159] - 2026-03-23

### Added
- Reflect chat tool: extracts key learnings from conversation text using LLM, ingests into Apollo knowledge graph and project memory
- Reflect spec with 5 examples covering raw text ingest, LLM extraction, Apollo-down fallback, no entries, and domain passthrough
- Chat tool registry now has 24 built-in tools

## [1.4.158] - 2026-03-23

### Added
- CostSummary chat tool: query cost/token usage from daemon (summary, top consumers, per-worker)
- CostSummary spec with 7 examples covering summary, top, worker, missing worker_id, empty workers, daemon down, API errors
- Chat tool registry now has 23 built-in tools

## [1.4.157] - 2026-03-23

### Added
- ViewEvents chat tool: view recent events from the Legion event bus ring buffer with count control
- ViewEvents spec with 7 examples covering formatted output, empty events, count parameter, clamping, connection refused, API errors, and events without details
- Chat tool registry now has 22 built-in tools

## [1.4.156] - 2026-03-23

### Changed
- Session store now saves summary (first user message, truncated to 120 chars), message count, and model in session metadata
- Session list includes summary, message_count, and model for at-a-glance session browsing
- 4 new session_store specs covering message count, summary generation, long summary truncation, and list metadata

## [1.4.155] - 2026-03-23

### Changed
- SaveMemory tool now auto-ingests entries into Apollo knowledge graph when daemon is running
- Apollo ingest includes type (memory), source (chat:project/global), and tags for categorization
- Updated save_memory specs with 6 examples covering apollo integration, confirmation, and fallback

## [1.4.154] - 2026-03-23

### Changed
- SearchMemory tool now also queries Apollo knowledge graph when available, combining file-based memory with semantic knowledge
- Apollo results include type, content, and confidence score for richer context retrieval
- Updated search_memory specs with 6 examples covering combined memory+apollo, apollo-only, memory-only, and error handling

## [1.4.153] - 2026-03-23

### Changed
- TraceSearch schema context now injects current date/time dynamically for accurate time-relative queries
- Added guidance for "today", "last hour", "this week", "yesterday" relative time references in LLM prompt
- 2 new trace_search specs covering schema_context current date injection and relative time guidance

## [1.4.152] - 2026-03-23

### Added
- Daemon awareness in chat context: system prompt now includes running daemon version and port when healthy
- daemon_hint method probes /api/health with 1-second timeout for non-blocking detection
- 5 new context specs covering daemon hint and cognitive awareness with daemon running

## [1.4.151] - 2026-03-23

### Added
- SystemStatus chat tool: check daemon health, component readiness, uptime, version, and extension count from chat
- SystemStatus spec with 6 examples covering full status, daemon down, endpoints failing, uptime formatting, and empty components
- Chat tool registry now has 21 built-in tools

## [1.4.150] - 2026-03-23

### Added
- ManageTasks chat tool: list, show, logs, and trigger tasks through the Legion Ingress pipeline with metering data display
- ManageTasks spec with 15 examples covering list/show/logs/trigger actions, validation, filters, payload forwarding, and error handling
- Chat tool registry now has 20 built-in tools

## [1.4.149] - 2026-03-23

### Added
- ListExtensions chat tool: discover loaded extensions and their runners/functions via REST API with active filtering and detail views
- ListExtensions spec with 7 examples covering list, empty, active_only filter, detail with runners, no runners, connection refused, and API errors
- Chat tool registry now has 19 built-in tools

## [1.4.148] - 2026-03-23

### Added
- Cognitive awareness in chat context: system prompt now includes memory entry counts and Apollo knowledge graph status when available
- Context cognitive_awareness, memory_hint, and apollo_hint methods with 1-second timeout for non-blocking probes
- 8 new context specs covering cognitive awareness, memory hints, and apollo availability detection

## [1.4.147] - 2026-03-23

### Added
- SummarizeTraces chat tool: aggregate metering database analytics with token usage, cost, latency, status breakdown, and top extensions/workers via natural language queries
- SummarizeTraces spec with 5 examples covering formatted output, error handling, empty data, and unavailable dependencies
- Chat tool registry now has 18 built-in tools

## [1.4.146] - 2026-03-23

### Added
- KnowledgeStats chat tool: inspect Apollo knowledge graph health with entry counts, status/type breakdowns, recent activity, and average confidence
- KnowledgeStats spec with 5 examples covering formatted output, empty breakdowns, API errors, connection refused, and missing fields
- Chat tool registry now has 17 built-in tools

## [1.4.145] - 2026-03-23

### Added
- KnowledgeMaintenance chat tool: trigger Apollo knowledge graph decay cycles and corroboration checks from chat sessions
- KnowledgeMaintenance spec with 8 examples covering decay, corroboration, invalid actions, API errors, and edge cases
- Chat tool registry now has 16 built-in tools

## [1.4.144] - 2026-03-23

### Added
- RelateKnowledge chat tool: find related entries in the Apollo knowledge graph with depth traversal, relation type filtering, and confidence scoring
- RelateKnowledge spec with 7 examples covering formatted results, empty results, API errors, connection refused, depth clamping, and relation type passthrough
- SearchTraces chat tool registered in tool registry (15 built-in tools)

## [1.4.143] - 2026-03-23

### Added
- TraceSearch.summarize: aggregate statistics for trace queries (total cost, tokens, latency, status breakdown, top extensions/workers)
- `legion trace summarize` CLI subcommand with formatted output and JSON mode
- Trace command spec expanded with 8 summarize examples

## [1.4.142] - 2026-03-23

### Added
- ConsolidateMemory chat tool: LLM-powered memory consolidation that deduplicates, merges related entries, and cleans up cluttered memory files with dry-run preview support
- ConsolidateMemory spec with 10 examples covering consolidation, dry-run, global scope, LLM unavailable, and error handling
- Task command spec with 13 examples covering list, show, logs, purge, and helper methods
- Chain command spec with 6 examples covering list, create, delete, and confirmation flow
- Generate command spec with 14 examples covering runner, actor, exchange, queue, message, and tool scaffolding
- Audit command spec with 6 examples covering list filters, JSON output, and chain verification
- RBAC command spec with 9 examples covering roles, show, assignments, assign, revoke, and access check

## [1.4.141] - 2026-03-23

### Added
- IngestKnowledge chat tool: save facts, observations, concepts, procedures, and decisions to the Apollo knowledge graph from within chat sessions
- IngestKnowledge spec with 9 examples covering success, content types, tags, API errors, and daemon unavailability
- Extension tool loader spec with 13 examples covering discovery, permission tiers, and tool collection
- Skill command spec with 14 examples covering list, show, create, and run
- Swarm command spec with 16 examples covering list, show, start, and pipeline failures
- Graph command, builder, and exporter specs with 37 examples covering mermaid/dot rendering, filters, and empty graphs
- Cost command spec with 16 examples covering summary, worker, top, and export

## [1.4.140] - 2026-03-23

### Added
- SearchTraces chat tool: search cognitive memory traces for Teams messages, conversations, meetings, and people with keyword ranking, person name variants, and fuzzy matching
- SearchTraces spec with 15 examples covering keyword search, person/domain/type filters, payload parsing, age formatting, and limit clamping
- TraceSearch spec expanded from 8 to 20 examples: `.search` entry point, `.apply_date_filters`, `.apply_ordering` (ascending/descending), `.safe_parse_time` edge cases, `FILTER_SCHEMA` properties

## [1.4.139] - 2026-03-23

### Added
- Gaia API: `GET /api/gaia/channels`, `GET /api/gaia/buffer`, `GET /api/gaia/sessions` endpoints
- Gaia CLI: `legion gaia channels`, `legion gaia buffer`, `legion gaia sessions` subcommands
- Gaia spec coverage expanded from 12 to 25 examples

## [1.4.138] - 2026-03-23

### Added
- QueryKnowledge chat tool: query Apollo knowledge graph from chat sessions for facts, concepts, and observations
- QueryKnowledge spec with 11 examples covering results, errors, filters, and limit clamping

## [1.4.137] - 2026-03-23

### Changed
- Rewrite `legion trace search` with formatter support, JSON mode, truncation display, detailed output (cost, tokens, wall clock, worker)
- Register trace subcommand in main CLI (`legion trace search QUERY`)

### Added
- Trace command spec with 13 examples covering all output paths

## [1.4.136] - 2026-03-23

### Added
- Apollo CLI command: `legion apollo status`, `stats`, `query`, `ingest`, `maintain` subcommands
- SearchTraces chat tool for natural language trace search within chat sessions

## [1.4.135] - 2026-03-23

### Added
- Apollo maintenance endpoint: `POST /api/apollo/maintenance` triggers decay_cycle or corroboration check
- Apollo maintenance in OpenAPI spec with action validation

## [1.4.134] - 2026-03-23

### Added
- Apollo stats endpoint: `GET /api/apollo/stats` returns entry counts by status, content type, 24h activity, and average confidence
- Apollo stats in OpenAPI spec

## [1.4.133] - 2026-03-23

### Changed
- TraceSearch: add safe date coercion via `Time.parse` with fallback for unparseable LLM-generated date strings
- TraceSearch: add `total` and `truncated` fields to response when results exceed limit
- Extract `apply_date_filters`, `safe_parse_time`, and `apply_ordering` helpers from `execute_filter`

## [1.4.132] - 2026-03-23

### Added
- Apollo knowledge graph REST API: status, query, ingest, and related entries endpoints
- Apollo API spec with 11 examples covering all routes and parameter passing

## [1.4.131] - 2026-03-23

### Changed
- Add logging to Every actor tick cycle and Subscription actor message processing
- Add logging to actor builder discovery
- Register SearchTraces tool with LLM ToolRegistry via API llm routes
- Comment out bootsnap setup in legionio executable for local development

## [1.4.130] - 2026-03-22

### Changed
- `Extensions::Helpers::Data` now delegates to `Legion::Data::Helper` from legion-data gem
- `Extensions::Helpers::Transport` now delegates to `Legion::Transport::Helper` from legion-transport gem
- `Extensions::Helpers::Lex` now includes `Legion::JSON::Helper` for `json_load`/`json_dump` convenience methods
- Require legion-data >= 1.4.17, legion-json >= 1.2.1, legion-transport >= 1.3.9

## [1.4.129] - 2026-03-22

### Added
- SearchTraces chat tool for querying cognitive memory traces (Teams messages, conversations, meetings, people)
- Keyword-ranked search with person, domain, and trace type filtering
- Structured output formatting with age, strength, and domain tag metadata

## [1.4.128] - 2026-03-22

### Changed
- `Extensions::Helpers::Cache` now delegates to `Legion::Cache::Helper` from legion-cache gem
- Require legion-cache >= 1.3.11 and legion-crypt >= 1.4.9

## [1.4.127] - 2026-03-22

### Changed
- `Extensions::Helpers::Core` now delegates `settings` to `Legion::Settings::Helper` from legion-settings gem
- Require legion-settings >= 1.3.14 for the new Helper module

## [1.4.126] - 2026-03-22

### Changed
- `Extensions::Helpers::Logger` now delegates `log` to `Legion::Logging::Helper` from legion-logging gem
- Require legion-logging >= 1.3.2 for the new Helper module

## [1.4.125] - 2026-03-22

### Changed
- Parallelize update command version checks using RubyGems HTTP API and concurrent-ruby thread pool
- Skip `gem install` entirely when all gems are already at latest version
- Only install gems that are actually outdated instead of reinstalling all gems

## [1.4.124] - 2026-03-22

### Changed
- Update gemspec dependency version constraints for all legion-* gems to match current releases

## [1.4.123] - 2026-03-22

### Changed
- Add logging to silent rescue blocks: all rescue blocks now capture the exception variable and emit `Legion::Logging.debug` or `.warn` calls so errors are visible in logs rather than silently swallowed

## [1.4.122] - 2026-03-22

### Added
- GraphQL API via `graphql-ruby` gem: `POST /api/graphql` endpoint alongside existing REST API
- Schema types: QueryType, WorkerType, TaskType, ExtensionType, TeamType with field-level resolvers
- Resolver modules for workers, tasks, extensions, and teams (safe stubs with `defined?` guards)
- 45 new specs for GraphQL schema, queries, and error handling

## [1.4.121] - 2026-03-22

### Added
- Route `/api/llm/chat` through full Legion pipeline (Ingress -> RBAC -> Events -> Task -> Gateway metering -> LLM) when `lex-llm-gateway` is loaded
- `gateway_available?` helper to detect gateway runner presence
- Proper result extraction from `ingress_result[:result]` with support for RubyLLM response objects, error hashes, and plain strings
- Error logging in async LLM rescue block (previously silent)

## [1.4.120] - 2026-03-22

### Added
- Comprehensive logging throughout the framework: 55 files, 443 lines of `.info`, `.warn`, `.error`, `.debug` calls
- API routes: every non-2xx response logs at warn (4xx) or error (5xx), every mutation logs at info, debug for request entry
- Core framework: ingress, runner, extensions, actors, service lifecycle, readiness, events all log state transitions
- Extension system: autobuild, actor hooking, transport setup, builder phases all log at debug/info
- Digital worker lifecycle, capacity model, catalog, guardrails, webhooks, alerts, audit, telemetry all instrumented
- CLI error handler logs matched patterns (warn) and unhandled errors (error)

## [1.4.119] - 2026-03-22

### Added
- `legion setup claude-code` installs Legion MCP server entry into `~/.claude/settings.json` and writes the `/legion` slash command skill to `~/.claude/commands/legion.md`
- `legion setup cursor` installs Legion MCP server entry into `.cursor/mcp.json` in the current project directory
- `legion setup vscode` installs Legion MCP server entry into `.vscode/mcp.json` using the VS Code stdio server format
- `legion setup status` shows which platforms (Claude Code, Cursor, VS Code) have Legion MCP configured
- All `legion setup` subcommands support `--force` to overwrite existing entries and `--json` for machine-readable output
- MCP installs merge with existing server configs rather than overwriting unrelated entries

## [1.4.118] - 2026-03-22

### Added
- `legion detect --install` interactive extension picker: multi-select via tty-prompt (when available) or numbered list fallback
- `legion detect --install-all` for non-interactive bulk install of all missing extensions
- Signal context shown in picker (e.g., which app/formula triggered the recommendation)

## [1.4.117] - 2026-03-22

### Added
- `Legion::CLI::Error` gains `suggestions`, `code` attributes and `.actionable` factory method
- `Legion::CLI::ErrorHandler` module: 6-pattern matcher maps common exceptions (RabbitMQ, DB, extensions, permissions, data, Vault) to actionable errors with fix suggestions
- `ErrorHandler.wrap` wraps any `StandardError` into a `CLI::Error` with suggestions when a pattern matches
- `ErrorHandler.format_error` prints suggestions below the error line when the error is actionable
- `Legion::CLI::Main.start` overrides Thor's entry point to wrap unhandled exceptions through `ErrorHandler` before exiting

## [1.4.116] - 2026-03-22

### Added
- `legion detect scan --format sarif|markdown|json` option for CI-friendly output formats

## [1.4.115] - 2026-03-22

### Changed
- Extension parallel pool size now reads from `Legion::Settings[:extensions][:parallel_pool_size]` (default: 24) instead of hardcoded 4
- Significantly faster boot with many extensions: all load concurrently instead of in batches of 4

## [1.4.114] - 2026-03-22

### Changed
- Parallelize extension loading using Concurrent::Promises thread pool (4 workers)
- Use Concurrent::Array for thread-safe pending_actors during parallel load
- ~4x faster boot: extensions load concurrently instead of serially

## [1.4.112] - 2026-03-21

### Added
- `Legion::Lock` distributed locking module (Redis SET NX PX acquire, Lua compare-and-delete release)
- `Legion::Leader` leader election module with periodic renewal via distributed lock
- `Legion::Extensions::Actors::Singleton` mixin for singleton actor enforcement (one instance per cluster)
- `Legion::Leader.reset!` called in shutdown sequence to release leadership before process exit

## [1.4.111] - 2026-03-21

### Added
- Register logging hooks in boot sequence: fatal/error/warn published to `legion.logging` RMQ exchange
- Routing key pattern: `legion.<source>.<level>` (e.g., `legion.core.fatal`, `legion.lex-slack.error`)
- `Legion::Region` module: cloud metadata detection (AWS IMDSv2, Azure IMDS), region affinity routing
- `Legion::Region::Failover`: promote regions with replication lag checks, --dry-run, --force
- `legion failover` CLI: promote and status subcommands for region failover management

## [1.4.110] - 2026-03-21

### Added
- Domain restrictions in extension Sandbox (allowed_domains on Policy, domain_allowed? check)
- Sandbox.allowed? class method for combined capability + domain checks

## [1.4.109] - 2026-03-21

### Added
- `Legion::Cluster::Lock` Redis backend: SETNX + TTL acquire, Lua compare-and-delete release, thread-safe token storage via `Concurrent::Map`
- `Legion::Cluster::Lock.backend` auto-detection: `:redis` (preferred), `:postgres` (advisory locks), or `:none`
- `Legion::ProcessRole` module: role presets (full, api, worker, router) controlling which Service subsystems start
- `Legion::Service#initialize` role integration: `role:` parameter resolves via `ProcessRole`, explicit kwargs override role defaults
- 24 new specs (2404 total, 0 failures)

## [1.4.108] - 2026-03-21

### Added
- `Legion::Registry::SecurityScanner` static analysis check — detects dangerous Ruby patterns (eval, system, exec, backtick, IO.popen, Open3) in extension source files
- `Legion::Registry::Persistence` module — syncs in-memory registry with `extensions_registry` DB table (load at boot, persist on register/update)
- Boot-time auto-population of `Legion::Registry` from discovered extensions with gemspec capability reading
- `Legion::Sandbox` auto-wiring from gemspec `legion.capabilities` metadata at extension load
- `legion marketplace install NAME` command — validates lex- naming, installs gem, registers in registry
- `legion marketplace publish` command — full pipeline: rspec, rubocop, gem build, gem push, security scan, register
- `Legion::Registry::Governance` module — naming convention enforcement, auto-approve by risk tier, review requirements via `Legion::Settings`
- 65 new specs (2380 total, 0 failures)

## [1.4.107] - 2026-03-21

### Added
- `Legion::Docs::SiteGenerator` — full static site generator with kramdown + rouge syntax highlighting
- Converts markdown guides to HTML with navigation sidebar and styled template
- CLI reference auto-generation via Thor command introspection
- Extension reference auto-generation via Bundler gem discovery
- `Legion::CLI::Docs` — `legion docs generate` and `legion docs serve` subcommands
- 39 new specs (2248 total, 0 failures)

## [1.4.106] - 2026-03-21

### Added
- `Legion::DigitalWorker::Registration` module with full approval workflow: `register`, `approve`, `reject`, `pending_approvals`, `approval_required?`, and `escalate`
- Workers with `high` or `critical` risk tiers are created in `pending_approval` state instead of `bootstrap`, triggering an AIRB intake
- `Legion::DigitalWorker::Airb` module for AIRB integration: `create_intake`, `check_status`, `sync_status` (mock API by default; live API activated via `Legion::Settings.dig(:airb)`)
- New lifecycle states `pending_approval` and `rejected` in `Lifecycle::TRANSITIONS`, with appropriate `EXTINCTION_MAPPING` and `CONSENT_MAPPING` entries
- Transition rules: `pending_approval -> active` (approve), `pending_approval -> rejected` (reject)
- CLI subcommands: `legion worker approvals`, `legion worker approve ID [--notes TEXT]`, `legion worker reject ID --reason TEXT`
- API routes: `GET /api/workers/approvals`, `POST /api/workers/:id/approve`, `POST /api/workers/:id/reject`
- 37 new specs across `registration_spec.rb` (28 examples) and `airb_spec.rb` (9 examples)
- `Legion::Phi` module — HIPAA/BAA PHI tagging and tracking: `PHI_TAG`, `tag`, `tagged?`, `phi_fields`, `redact`, `erase`, `auto_detect_fields`
- `Legion::Phi::AccessLog` module — PHI access audit trail: `log_access`, `log_access!`, `recent_access`; integrates with `Legion::Audit` when available, falls back to `Legion::Logging`
- `Legion::Phi::Erasure` module — cryptographic erasure: `erase_record` (AES-256-GCM with throwaway key), `erase_for_subject` (HIPAA right to deletion), `erasure_log`
- Pattern-based auto-detection of PHI fields (ssn, mrn, dob, patient_name, phone, email, address, diagnosis, npi, insurance_id, etc.) via configurable regex patterns in `legion-settings` at `phi.field_patterns`
- `Legion::Crypt` guarded throughout — falls back to stdlib OpenSSL when `legion-crypt` is not loaded
- 59 new specs across `phi_spec.rb` (30 examples), `phi/access_log_spec.rb` (15 examples), `phi/erasure_spec.rb` (14 examples)
- `Legion::API::Routes::GraphQL` — GraphQL API layer using graphql-ruby (optional dependency, guarded with `defined?(GraphQL)`)
- `POST /api/graphql` — executes GraphQL queries; parses `query`, `variables`, `operationName` from JSON body
- `GET /api/graphql` — serves GraphiQL browser IDE for interactive introspection
- `Legion::API::GraphQL::Schema` — root schema with `max_depth: 10`, `max_complexity: 200`
- `Legion::API::GraphQL::Types::QueryType` — root query with `workers`, `worker`, `extensions`, `extension`, `tasks`, `node` fields and filtering arguments
- `Legion::API::GraphQL::Types::WorkerType`, `ExtensionType`, `TaskType`, `NodeType` — field definitions for each domain object
- Data resolution falls back gracefully: uses `Legion::Data` models when connected, falls back to `Legion::DigitalWorker::Registry` / `Legion::Registry` in-memory stores otherwise
- 45 new specs in `spec/legion/api/graphql_spec.rb`

## [1.4.105] - 2026-03-21

### Added
- `Legion::API::Routes::AuthSaml` — SAML 2.0 SP authentication flow
- `GET /api/auth/saml/metadata` — generates SP metadata XML (delegates to `OneLogin::RubySaml::Metadata`)
- `GET /api/auth/saml/login` — initiates IdP redirect via `OneLogin::RubySaml::Authrequest`
- `POST /api/auth/saml/acs` — validates SAML assertion, extracts claims (nameid, email, displayName, groups), maps groups to Legion RBAC roles, and issues a Legion JWT
- Routes are only registered when `OneLogin::RubySaml` is defined and `auth.saml.enabled` is true
- Claims mapping delegates to `Legion::Rbac::ClaimsMapper.groups_to_roles` when available, falls back to `['worker']`
- Configuration via `Legion::Settings.dig(:auth, :saml)` — keys: `idp_sso_url`, `idp_cert`, `sp_entity_id`, `sp_acs_url`, `group_map`, `default_role`, `want_assertions_signed`, `want_assertions_encrypted`
- `Legion::Registry` review workflow: `submit_for_review`, `approve`, `reject`, `deprecate`, `pending_reviews`, `usage_stats` class methods
- `Legion::Registry::Entry` gains `status`, `review_notes`, `reject_reason`, `successor`, `sunset_date`, and timestamp fields; `deprecated?` and `pending_review?` predicates
- `legion marketplace submit NAME` — submit extension for review
- `legion marketplace review` — list extensions pending review
- `legion marketplace approve NAME [--notes TEXT]` — approve an extension
- `legion marketplace reject NAME [--reason TEXT]` — reject an extension
- `legion marketplace deprecate NAME [--successor NAME] [--sunset-date DATE]` — mark extension as deprecated
- `legion marketplace stats NAME` — show usage statistics (install count, active instances, downloads)
- `Legion::API::Routes::Marketplace` — full REST API: `GET /api/marketplace`, `GET /api/marketplace/:name`, `POST /api/marketplace/:name/submit`, `POST /api/marketplace/:name/approve`, `POST /api/marketplace/:name/reject`, `POST /api/marketplace/:name/deprecate`, `GET /api/marketplace/:name/stats`
- 123 new specs across registry, CLI, and API layers

## [1.4.104] - 2026-03-21

### Added
- `legion notebook read PATH` — parse and display a .ipynb notebook with Rouge syntax highlighting
- `legion notebook cells PATH` — list all cells with index numbers and line counts
- `legion notebook export PATH --format md|script` — export notebook to markdown or Python script
- `legion notebook create PATH --description "..."` — generate a new notebook from natural language via LLM (requires legion-llm)
- `Legion::Notebook::Parser` — parse .ipynb JSON into structured data (metadata, kernel, language, cells with outputs)
- `Legion::Notebook::Renderer` — display notebook cells in terminal with Rouge syntax highlighting
- `Legion::Notebook::Generator` — generate notebooks from natural language; strips LLM markdown fences; validates .ipynb structure

## [1.4.103] - 2026-03-21

### Added
- `Legion::Team` module — team registry backed by settings (current, members, find, list)
- `Legion::Team::CostAttribution` — tags LLM request metadata with team and user context
- `legion team` CLI subcommand — list, show, current, set, create, add-member

## [1.4.102] - 2026-03-21

### Added
- `legion image analyze PATH` — analyze an image file via LLM; supports `--prompt`, `--model`, `--provider`, `--format text|json`
- `legion image compare PATH1 PATH2` — compare two images side by side via LLM with same options
- Supports png, jpg, jpeg, gif, webp; base64-encodes image data and builds multimodal content blocks for the LLM message

## [1.4.101] - 2026-03-21

### Fixed
- add post-extension GAIA rediscovery in service boot sequence
- fix self-contained actor dispatch to call instance methods instead of class methods

## [1.4.100] - 2026-03-21

### Changed
- `hook_actor` FATAL now logs actor class name and ancestors for debugging unmatched actors
- `hook_all_actors` logs actor type counts after hooking (subscription/every/poll/once/loop)

## [1.4.99] - 2026-03-21

### Fixed
- `Base#manual` resolves String `runner_class` via `Kernel.const_get` before calling `.send` — fixes NoMethodError on lex-telemetry Publisher and lex-llm-gateway SpoolFlush actors
- `Base#manual` falls back to `:action` when `runner_function` is not defined — fixes NameError on self-contained actors (lex-lex AgentWatcher, lex-detect ObserverTick)

## [1.4.98] - 2026-03-20

### Fixed
- `auto_generate_data` and `auto_generate_transport` use `lex_class.const_defined?(:Data, false)` instead of `Kernel.const_defined?` — fixes constant overwrite when extensions pre-define their own Data/Transport modules (e.g. lex-synapse)

## [1.4.97] - 2026-03-20

### Fixed
- Suppress Puma startup banner by adding `quiet: true` to server settings (routes all API logging through Legion::Logging)

## [1.4.96] - 2026-03-20

### Fixed
- `auto_generate_data` and `auto_generate_transport` in `core.rb` now extend existing namespace modules (e.g. `Synapse::Data::Model`) with the appropriate `Legion::Extensions::Data` or `Legion::Extensions::Transport` mixin when `build` is not already defined, instead of returning early and leaving them without a `build` method

## [1.4.95] - 2026-03-20

### Added
- `GET /api/prompts` — list all prompt templates via lex-prompt Client
- `GET /api/prompts/:name` — show prompt details for the latest version
- `POST /api/prompts/:name/run` — render a prompt template with variables and run it through Legion::LLM; returns rendered_prompt, response, usage, model, version
- 503 guard for missing lex-prompt dependency (LoadError rescue in `prompt_client` helper)
- 503 guard for LLM subsystem unavailable on the `/run` endpoint
- 404 on prompt not found, 422 on version not found for `/run`
- 32 new specs in `spec/legion/api/prompts_spec.rb` covering all routes and error paths

## [1.4.94] - 2026-03-20

### Added
- `legion prompt play NAME` subcommand: renders a prompt template with variables and sends it to an LLM via `Legion::LLM.chat`
- `--variables` (JSON), `--version`, `--model`, `--provider`, and `--compare` options on `play`
- Compare mode (`--compare VERSION`): renders two prompt versions, calls LLM for each, displays side-by-side responses and diff when they differ
- JSON output mode for `play` and compare via `--json`
- `Connection.ensure_llm` called inside `with_prompt_client` so LLM is available to all prompt subcommands
- 14 new specs for `play` covering single-version, compare, LLM unavailable, JSON output, and error paths

## [1.4.93] - 2026-03-20

### Added
- `legion prompt` CLI subcommand for versioned LLM prompt template management (list, show, create, tag, diff)
- `legion dataset` CLI subcommand for versioned dataset management (list, show, import, export)
- Both commands wrap `lex-prompt` and `lex-dataset` extension clients via `begin/rescue LoadError` guards
- Both commands guard with `Connection.ensure_data` and follow existing `with_*_client` pattern
- Tab completion entries for `prompt` and `dataset` in `completions/legion.bash` and `completions/_legion`

## [1.4.92] - 2026-03-20

### Added
- `--template` option on `legion lex create` to scaffold pattern-specific extensions: `llm-agent`, `service-integration`, `data-pipeline` (default: `basic`)
- `--list-templates` option on `legion lex create` to display available templates with descriptions
- `LexTemplates::TemplateOverlay` class renders ERB template files into the target extension directory
- ERB scaffold templates under `lib/legion/cli/lex/templates/`: `llm_agent/`, `service_integration/`, `data_pipeline/`
- `llm-agent` template: LLM runner with `Legion::LLM.chat` and structured output, helpers/client.rb with model/temperature kwargs, default prompt YAML, spec with LLM mock
- `service-integration` template: CRUD runners (list/get/create/update/delete), Faraday HTTP client helper with api_key/bearer/basic auth, auth helper, specs with WebMock stubs
- `data-pipeline` template: transform runner with validate/process/publish pattern, subscription ingest actor, transport exchange/queue/message scaffolds, runner and actor specs
- Template registry extended with `data-pipeline`, `template_dir` class method, new `llm-agent`/`service-integration` entries with `template_dir` keys

## [1.4.91] - 2026-03-20

### Fixed
- Guard `auto_generate_data` against overwriting existing `Data` module on extensions (fixes lex-synapse constant collision)

## [1.4.90] - 2026-03-20

### Fixed
- Extension migrator uses `true` instead of `1` for PostgreSQL boolean `active` column
- Shutdown guards `Legion::Gaia.started?` with `respond_to?` to handle partial GAIA load failures

## [1.4.89] - 2026-03-20

### Added
- ACP provider routes: `GET /.well-known/agent.json`, `POST /api/acp/tasks`, `GET /api/acp/tasks/:id`, `DELETE /api/acp/tasks/:id` (501 stub)
- `Legion::API::Routes::Acp` module for bidirectional ACP interoperability
- `build_agent_card`, `discover_capabilities`, `find_task`, `translate_status` API helpers for ACP support

## [1.4.88] - 2026-03-20

### Added
- ACP provider spec: 25 tests covering agent card discovery, task submission, task status, task cancellation stub, and status translation
- Refactored ACP helpers into `Legion::API::Helpers::Acp` module for testability

## [1.4.87] - 2026-03-20

### Added
- OpenInference OTel span instrumentation (Ingress TOOL spans, Subscription CHAIN spans)
- SafetyMetrics sliding window module with 4 default alert rules
- Fingerprint mixin for actor skip-if-unchanged optimization

## [1.4.86] - 2026-03-20

### Added
- `legion payroll` CLI subcommand for workforce cost visibility (summary, report, forecast, budget)
- Integrated with `Helpers::Economics` from lex-metering for labor economics data

## [1.4.85] - 2026-03-20

### Added
- `legion lex fixes` CLI command to list pending auto-fix patches (filterable by status)
- `legion lex approve-fix FIX_ID` CLI command to approve LLM-generated fixes
- `legion lex reject-fix FIX_ID` CLI command to reject LLM-generated fixes
- `with_data` helper to `legion lex` subcommand class for data-required operations

## [1.4.84] - 2026-03-20

### Added
- `Legion::Extensions.load_yaml_agents` — loads YAML/JSON agent definitions from `~/.legionio/agents/` or configured directory
- `generate_yaml_runner` — dynamically generates a runner Module for each agent with `llm`, `script`, and `http` function types
- YAML agent loading integrated into `hook_extensions` boot sequence
- Governance API routes under `/api/governance/approvals` (list, show, submit, approve, reject)
- HTML governance dashboard at `/governance/` with approve/reject buttons, 30s auto-poll, and reviewer dialog
- Static file serving enabled for `public/` directory in Sinatra

## [1.4.83] - 2026-03-20

### Added
- `Helpers::Context` for filesystem-based inter-agent context sharing
- Org chart API endpoint (`GET /api/org-chart`) with dashboard panel
- Workflow relationship graph API (`GET /api/relationships/graph`)
- Workflow visualizer web page (`public/workflow/`) with Cytoscape.js
- `--worktree` flag for `legion chat` with auto-checkpointing
- `.legion-context/` and `.legion-worktrees/` in generated `.gitignore`

## [1.4.82] - 2026-03-20

### Added
- `legion check --privacy` command: verifies enterprise privacy mode (flag set, no cloud API keys, external endpoints unreachable)
- `PrivacyCheck` class with three probes: flag_set, no_cloud_keys, no_external_endpoints
- `Legion::Service.log_privacy_mode_status` logs enterprise privacy state at startup

## [1.4.81] - 2026-03-20

### Added
- Fingerprint mixin for actor skip-if-unchanged optimization (`Legion::Extensions::Actors::Fingerprint`)
- SHA256-based `skip_or_run` gate: skips execution when `fingerprint_source` is stable
- Fingerprint integrated into `Every` and `Poll` actors via `include Fingerprint`
- Extracted `poll_cycle` method from Poll actor for clean separation of timer vs logic
- `legion eval experiments` subcommand: list all experiment runs with status and summary
- `legion eval promote --experiment NAME --tag TAG` subcommand: tag a prompt version for production via lex-prompt
- `legion eval compare --run1 NAME --run2 NAME` subcommand: side-by-side diff of two experiment runs
- `require_prompt!` guard for lex-prompt extension availability

## [1.4.80] - 2026-03-20

### Added
- OpenInference OTel span helpers (LLM, EMBEDDING, TOOL, CHAIN, EVALUATOR, AGENT)
- SafetyMetrics sliding window module for behavioral monitoring
- 4 safety alert rules (action burst, scope escalation spike, probe detected, confidence collapse)
- OpenInference TOOL spans in Ingress.run
- OpenInference CHAIN spans in Subscription actor dispatch
- SafetyMetrics wired into service boot sequence
- `legion eval run` CLI subcommand for CI/CD threshold-based eval gating
- `--dataset`, `--threshold`, `--evaluator`, `--exit-code` options on `eval run`
- JSON report output to stdout with per-row scores, summary, and timestamp
- `.github/workflow-templates/eval-gate.yml` reusable GitHub Actions workflow template
- PR annotation step in workflow template for inline eval result comments

## [1.4.79] - 2026-03-20

### Added
- Unified LEX routing layer: auto-expose runner functions as POST endpoints at `/api/lex/{ext}/{runner}/{action}`
- `Builders::Routes` auto-discovers runner public methods during extension autobuild
- `Routes::Lex` wildcard handler dispatches through Ingress with JWT + RBAC
- `GET /api/lex` listing endpoint for route discovery
- Settings-based configuration at `api.lex_routes` (global enable, per-extension enable, runner/function exclusions)
- `skip_routes` DSL for runner modules to opt out of auto-route exposure
- Auto-routes included in OpenAPI spec generation
- `runner_module` reference stored in builders runner hash for introspection

## [1.4.78] - 2026-03-19

### Added
- Response headers support in `render_custom_response`: runners can return `response[:headers]` hash for custom HTTP headers

### Removed
- Legacy `POST /api/hooks/:lex_name/:hook_name` route (superseded by `GET|POST /api/hooks/lex/*` splat routes in v1.4.76)
- Hardcoded `GET /api/auth/negotiate` Kerberos route (migrated to lex-kerberos hook at `/api/hooks/lex/kerberos/negotiate`)
- `Routes::AuthKerberos` module and `api/auth_kerberos.rb` file

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
