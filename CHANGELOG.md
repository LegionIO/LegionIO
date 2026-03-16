# Legion Changelog

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
