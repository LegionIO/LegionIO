# Legion Changelog

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
