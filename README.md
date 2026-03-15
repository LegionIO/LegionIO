# LegionIO

An extensible async job engine and AI coding assistant for Ruby. Schedule tasks, create relationships between services, and run them concurrently via RabbitMQ. Includes an interactive AI chat CLI with built-in tools, code review, and multi-agent workflows.

**Ruby >= 3.4** | **Version**: 1.4.3 | **License**: Apache-2.0 | **Author**: [@Esity](https://github.com/Esity)

## What does it do?

LegionIO routes work between services asynchronously. Tasks can be chained into dependency graphs:

```
a -> b -> c
     b -> e -> z
          e -> g
```

When `a` completes, `b` runs, which triggers `c` and `e` in parallel. Conditions and transformations control when and how data flows between steps.

## Installation

```bash
gem install legionio
```

For database features (task history, scheduling, chains):

```bash
gem install legion-data
```

## Infrastructure Requirements

- **RabbitMQ**: Required. All task distribution runs over AMQP 0.9.1.
- **SQLite/PostgreSQL/MySQL**: Optional. Required for task history, scheduling, and chains.
- **Redis/Memcached**: Optional. Required for extensions that use caching.
- **HashiCorp Vault**: Optional. Required for extensions that use secrets management.

## Running

Use the `legion` command for everything:

```bash
legion start                    # Start the daemon (foreground)
legion start -d                 # Daemonize
legion start -d -p /tmp/l.pid   # With PID file
legion status                   # Show running service status
legion stop                     # Stop the daemon
legion check                    # Smoke-test all subsystem connections
legion check --extensions       # Also load and verify extensions
legion check --full             # Full boot cycle including API server
```

All commands support `--json` for structured output and `--no-color` to strip ANSI codes.

## Extensions (LEX)

Extensions are gems named `lex-*`. They are auto-discovered from installed gems and loaded at startup.

```bash
legion lex list                 # List installed extensions
legion lex info <name>          # Extension detail: runners, actors, deps
legion lex create <name>        # Scaffold a new extension
legion lex enable <name>        # Enable extension
legion lex disable <name>       # Disable extension
```

### Running Tasks

```bash
legion task run http.request.get url:https://example.com   # dot notation
legion task run -e http -r request -f get                   # explicit flags
legion task run                                             # interactive selection
legion task list                                            # recent tasks
legion task show <id>                                       # task detail
legion task logs <id>                                       # execution logs
legion task purge --days 7                                  # cleanup old tasks
```

### Chains and Config

```bash
legion chain list
legion chain create <name>
legion chain delete <id>

legion config show              # resolved config (sensitive values redacted)
legion config path              # config search paths
legion config validate          # verify settings + subsystem health
```

### Code Generation

Run from inside a `lex-*` directory:

```bash
legion generate runner <name>   # add a runner + spec
legion generate actor <name>    # add an actor + spec
legion generate exchange <name>
legion generate queue <name>
legion generate message <name>
```

`legion g` is an alias for `legion generate`.

### AI Chat

Interactive AI conversation with built-in tools for file operations and shell commands. Requires `legion-llm`.

```bash
legion chat                         # interactive REPL (default command)
legion chat prompt "explain main.rb" # headless single-prompt mode
echo "fix the bug" | legion chat prompt - # stdin pipe
```

**Flags**: `--model`, `--provider`, `--auto_approve` (`-y`), `--max_budget_usd N`, `--no_markdown`, `--incognito`, `--add_dir DIR`, `--personality STYLE`, `--continue` (`-c`), `--resume NAME`, `--fork NAME`

**Slash commands**: `/help`, `/quit`, `/cost`, `/status`, `/clear`, `/new`, `/save`, `/load`, `/sessions`, `/compact`, `/fetch URL`, `/search QUERY`, `/diff`, `/copy`, `/rewind`, `/memory`, `/agent`, `/agents`, `/plan`, `/swarm`, `/review`, `/permissions`, `/personality`, `/model`, `/edit`, `/commit`, `/workers`, `/dream`

**Bang commands**: `!ls -la` — run shell commands with output injected into context

**At-mentions**: `@reviewer check main.rb` — delegate to custom agents defined in `.legion/agents/`

**10 built-in tools**: read_file, write_file, edit_file (string + line-number mode), search_files, search_content, run_command, save_memory, search_memory, web_search, spawn_agent

### AI Workflow Commands

```bash
legion commit                       # AI-generated commit message from staged changes
legion pr                           # AI-generated PR title + description
legion pr --base develop --draft    # target branch and draft mode
legion review                       # AI code review of staged changes
legion review src/main.rb           # review specific files
legion review --diff                # review uncommitted diff
```

### Memory, Plan, and Swarm

```bash
legion memory list                  # list project memories
legion memory add "always use rspec" # add a memory
legion memory search "testing"      # search memories
legion memory forget 3              # remove memory by index

legion plan                         # read-only exploration mode (no writes)

legion swarm start deploy-pipeline  # run multi-agent workflow
legion swarm list                   # list available workflows
legion swarm show deploy-pipeline   # workflow details
```

### Digital Workers and Coldstart

```bash
legion worker list                  # list digital workers
legion worker show <id>             # worker details
legion worker pause <id>            # pause a worker
legion worker activate <id>         # reactivate a paused worker
legion worker retire <id>           # retire a worker
legion worker costs --days 30       # cost report

legion coldstart ingest .           # ingest CLAUDE.md/MEMORY.md into lex-memory
legion coldstart preview .          # dry-run (show what would be ingested)
legion coldstart status             # ingestion status

legion gaia status                  # probe GAIA cognitive layer health

legion schedule list                # list schedules
legion schedule show <id>           # schedule detail
legion schedule add <name> <cron> <runner>  # create a schedule
legion schedule remove <id>         # delete a schedule
legion schedule logs <id>           # execution logs (wraps /api/schedules)
```

## Configuration

Settings are loaded from the first directory found (in order):

1. `/etc/legionio/`
2. `~/legionio/`
3. `./settings/`

## Task Relationships

Tasks chain together with optional conditions and transformations:

```
Task A -> [condition check] -> Task B -> [transform payload] -> Task C
                                      -> Task D  (parallel)
```

### Conditions

JSON rule engine via `lex-conditioner`. Supports nested `all`/`any` with operators like `equal`, `is_true`, `is_false`:

```json
{
  "all": [
    {"fact": "pet.type", "value": "dog", "operator": "equal"},
    {"fact": "pet.hungry", "operator": "is_true"}
  ]
}
```

### Transformations

ERB templates via `lex-transformer`. Map data between services:

```json
{"message": "Incident assigned to <%= assignee %> with priority <%= severity %>"}
```

Access Vault secrets inline:

```json
{"token": "<%= Legion::Crypt.read('pushover/token') %>"}
```

## REST API

The daemon exposes a REST API on port 4567 (configurable). All routes are under `/api/`.

| Route | Description |
|-------|-------------|
| `GET /api/health` | Health check |
| `GET /api/ready` | Readiness + component status |
| `GET/POST /api/tasks` | List/create tasks |
| `GET /api/extensions` | Installed extensions + runners |
| `GET /api/nodes` | Cluster nodes |
| `GET/POST/PUT/DELETE /api/schedules` | Cron/interval scheduling |
| `GET /api/settings` | Config (sensitive values redacted) |
| `GET /api/transport` | RabbitMQ connection status |
| `GET /api/events` | SSE event stream |
| `GET/POST/PUT/DELETE /api/workers` | Digital worker lifecycle management |
| `POST /api/coldstart/ingest` | Trigger lex-coldstart context ingestion |

Response envelope:

```json
{
  "data": { ... },
  "meta": { "timestamp": "...", "node": "..." }
}
```

## MCP Server (AI Agent Integration)

LegionIO exposes itself as an MCP server so AI agents can invoke tasks, inspect extensions, manage schedules, and query status directly.

```bash
legion mcp            # stdio transport (default, for Claude Desktop / agent SDKs)
legion mcp http       # streamable HTTP on localhost:9393
legion mcp http --port 8080 --host 0.0.0.0
```

**30 tools** in the `legion.*` namespace:

- `legion.run_task` - execute any task by dot notation (e.g., `http.request.get`)
- `legion.describe_runner` - discover available functions on a runner
- `legion.list_tasks`, `legion.get_task`, `legion.delete_task`, `legion.get_task_logs`
- `legion.list_extensions`, `legion.get_extension`, `legion.enable_extension`, `legion.disable_extension`
- `legion.list_chains`, `legion.create_chain`, `legion.update_chain`, `legion.delete_chain`
- `legion.list_relationships`, `legion.create_relationship`, `legion.update_relationship`, `legion.delete_relationship`
- `legion.list_schedules`, `legion.create_schedule`, `legion.update_schedule`, `legion.delete_schedule`
- `legion.get_status`, `legion.get_config`
- `legion.list_workers`, `legion.show_worker`, `legion.worker_lifecycle`, `legion.worker_costs`, `legion.team_summary`
- `legion.routing_stats` - LLM routing statistics by provider, model, and routing reason

**Resources**: `legion://runners` (full runner catalog), `legion://extensions/{name}` (extension detail template)

## Scheduling

Requires `lex-scheduler`. Supports both cron syntax and plain-English intervals:

- `*/5 * * * *` — every 5 minutes
- `every minute` — plain English
- `every day at noon`

Setting `interval` (seconds since last completion) takes precedence over `cron`.

## Scaling and High Availability

Task distribution uses RabbitMQ FIFO queues. Add more workers by running additional Legion processes — each subscribes to the same queues and picks up work automatically. Tested to 100+ workers without performance issues. No paid features or configuration required for HA.

Different LEX combinations per worker are supported: run 10 pods focused on `lex-ssh`, and a separate pod running `lex-pagerduty` + `lex-log` for notifications.

## Docker

```bash
docker pull legionio/legion
```

```dockerfile
FROM ruby:3-alpine
RUN gem install legionio
CMD ruby --yjit $(which legion) start
```

## Security

- Global message encryption available (AES-256-CBC) via `legion-crypt`
- HashiCorp Vault integration for secrets and settings
- Each worker generates a private/public keypair for inter-node communication
- Cluster secret generated at first startup, stored only in memory by default

## Extensions

Browse available extensions: [LegionIO GitHub org](https://github.com/LegionIO) | [legionio topic](https://github.com/topics/legionio?l=ruby)

**Core extensions (operational):**
`lex-node`, `lex-tasker`, `lex-conditioner`, `lex-transformer`, `lex-scheduler`, `lex-health`, `lex-log`, `lex-ping`, `lex-exec`, `lex-lex`, `lex-codegen`, `lex-metering`

**Agentic extensions (242):**
Brain-modeled cognitive architecture. 20 core orchestration extensions (`lex-tick`, `lex-cortex`, `lex-dream`, `lex-memory`, `lex-emotion`, `lex-prediction`, `lex-identity`, `lex-trust`, `lex-consent`, `lex-governance`, etc.) plus 222 expanded cognitive modules across 18 domains: attention, reasoning, executive function, metacognition, emotion, curiosity, social cognition, language, learning, and more.

**AI/LLM extensions:**
`lex-claude`, `lex-openai`, `lex-gemini`

**Common service integrations:**
`lex-http`, `lex-redis`, `lex-s3`, `lex-github`, `lex-consul`, `lex-nomad`, `lex-vault`, `lex-microsoft_teams`

**Other integrations:**
`lex-ssh`, `lex-slack`, `lex-smtp`, `lex-influxdb`, `lex-pagerduty`, `lex-elasticsearch`, `lex-chef`, `lex-pushover`, `lex-twilio`, and more

## Similar Projects

- [Node-RED](https://nodered.org/) - Visual flow editor, no HA
- [n8n.io](https://n8n.io/) - Good features, HA limited
- [StackStorm](https://stackstorm.com/) - Python-based, feature drift toward paid tiers
- [Huginn](https://github.com/huginn/huginn) - Ruby IFTTT-style, no HA
