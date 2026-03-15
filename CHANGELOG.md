# Legion Changelog

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
