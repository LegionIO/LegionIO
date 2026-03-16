# Legion Changelog

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
