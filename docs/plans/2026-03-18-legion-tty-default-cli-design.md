# Design: Make legion-tty the Default CLI

**Date**: 2026-03-18
**Status**: Approved
**Author**: Matthew Iverson (@Esity)

## Problem

LegionIO has a single binary (`legion`) that multiplexes between interactive chat and 40+ operational subcommands. New users get dropped into a text-based chat REPL, which doesn't showcase the framework's capabilities. The `legion-tty` gem provides a much richer interactive experience (onboarding wizard, themed UI, dashboard) but is a separate optional install.

## Solution

Split the `legion` binary into two:

| Binary | Purpose | Target user |
|--------|---------|-------------|
| `legion` | Interactive shell + dev workflow | Everyone (99%) |
| `legionio` | Daemon + operational CLI | LEX builders, ops, troubleshooting |

### `legion` binary

Thin entry point. No args launches the TTY interactive shell. Piped stdin goes to headless chat prompt. Also hosts developer-workflow subcommands that don't require the daemon.

```
legion                          # TTY interactive shell
echo "fix bug" | legion         # headless chat prompt
legion commit                   # AI commit message
legion review [files...]        # AI code review
legion plan                     # read-only exploration
legion chat                     # text-based chat (non-TTY alternative)
legion chat prompt "question"   # single-prompt headless mode
legion memory list              # persistent memory management
legion init                     # project setup wizard
legion tty                      # explicit TTY launch
legion version                  # version info
legion --help                   # show available commands
```

### `legionio` binary

Full Thor CLI for daemon operations and infrastructure management.

```
legionio start [-d]             # daemon boot
legionio stop                   # daemon shutdown
legionio status                 # service status
legionio check [--full]         # smoke test
legionio lex list               # extension management
legionio task list              # task management
legionio config scaffold        # configuration
legionio mcp stdio              # MCP server
legionio worker list            # digital worker management
# ... all other operational subcommands
```

### Command routing

```
exe/legion:
  if ARGV.empty? && $stdin.tty?
    require 'legion/tty'
    Legion::TTY::App.run
  elsif ARGV.empty? && !$stdin.tty?
    require 'legion/cli'
    ARGV.replace(['chat', 'prompt', ''])
    Legion::CLI::Main.start(ARGV)
  else
    require 'legion/cli'
    Legion::CLI::Main.start(ARGV)
  end

exe/legionio:
  require 'legion/cli'
  Legion::CLI::Main.start(ARGV)
```

### Subcommand assignment

**`legion` (interactive + dev workflow):**
- `chat` - text-based AI REPL + headless prompt
- `commit` - AI-generated commit messages
- `review` - AI code review
- `plan` - read-only exploration mode
- `memory` - persistent memory management
- `init` - project setup wizard
- `tty` - explicit TTY shell launch
- `version` - version info

**`legionio` (operational + infrastructure):**
- `start`, `stop`, `status`, `check` - daemon lifecycle
- `lex` - extension management
- `task` - task management
- `chain` - chain management
- `config` - configuration
- `generate` - scaffolding
- `mcp` - MCP server
- `worker` - digital worker management
- `coldstart` - knowledge ingest
- `schedule` - job scheduling
- `dashboard` - TUI ops dashboard
- `cost` - cost tracking
- `audit` - audit log
- `rbac` - access control
- `doctor` - environment diagnosis
- `telemetry` - telemetry stats
- `openapi` - API spec generation
- `completion` - shell completions
- `marketplace` - extension marketplace
- `notebook` - task notebook
- `swarm` - multi-agent orchestration
- `gaia` - cognitive mesh status
- `graph` - task graph visualization
- `trace` - trace search
- `auth` - authentication
- `skill` - skill management
- `update` - self-update

### Implementation approach

Two separate Thor classes:

1. `Legion::CLI::Main` - stays as-is (all subcommands, used by `legionio`)
2. `Legion::CLI::Interactive` - new, small Thor class with only dev-workflow commands (used by `legion` with args)

`exe/legion` checks `ARGV.empty?` first for TTY routing, then delegates to `Legion::CLI::Interactive` for subcommands.

`exe/legionio` always delegates to `Legion::CLI::Main`.

### Homebrew

Both binaries get wrapper scripts in the formula. The formula `caveats` changes to:

```
First run:
  legion                           # interactive shell with onboarding wizard

Operational:
  legionio start                   # start the daemon
  legionio config scaffold         # generate config files
```

### Dependency

`legionio` gemspec adds `legion-tty` as a runtime dependency so it's always installed.

### Migration

- `legion start` still works (Thor routes it) but is undocumented in `legion --help`
- No breaking changes -- all existing `legion <subcommand>` patterns still work through `legionio`
- `legion` bare command changes from text chat to TTY shell

## Alternatives considered

1. **TTY wraps chat engine** - legion-tty calls into Legion::CLI::Chat internals. Rejected: too coupled.
2. **Single binary with mode flag** - `legion --interactive` vs `legion --daemon`. Rejected: two binaries is cleaner and more discoverable.
3. **Both binaries route to same Thor** - `legion` and `legionio` both use Main, just with different defaults. Rejected: `legion --help` would show 40 commands that 99% of users don't need.

## Not included

- Moving chat engine code into legion-tty (future phase)
- MCP integration in TTY shell (future)
- Removing `legion tty` subcommand from legionio (keep for compatibility)
