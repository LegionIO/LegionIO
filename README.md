# LegionIO

**An extensible async job engine, AI coding assistant, and cognitive computing platform for Ruby.**

Schedule tasks, chain services into dependency graphs, run them concurrently via RabbitMQ, and orchestrate AI-powered workflows — from a single `legion` command.

```
         ╭──────────────────────────────────────╮
         │           L E G I O N I O            │
         │                                      │
         │   280+ extensions  ·  30 MCP tools   │
         │   AI chat CLI  ·  REST API  ·  HA    │
         │   cognitive architecture  ·  Vault    │
         ╰──────────────────────────────────────╯
```

**Ruby >= 3.4** | **v1.4.13** | **Apache-2.0** | [@Esity](https://github.com/Esity)

---

## What Does It Do?

LegionIO routes work between services asynchronously. Tasks chain into dependency graphs with conditions and transformations controlling data flow:

```
Task A ──→ [condition] ──→ Task B ──→ [transform] ──→ Task C
                                  └──→ Task D  (parallel)
                                  └──→ Task E ──→ Task F
```

When A completes, B runs. B triggers C, D, and E in parallel. Conditions gate execution. Transformations reshape payloads between steps. Add more workers by running more processes — RabbitMQ handles distribution automatically.

But that's just the foundation. LegionIO is also:

- **An AI coding assistant** — interactive chat with tools, code review, commit messages, PR generation, and multi-agent workflows
- **An MCP server** — 30 tools that let any AI agent run tasks, manage extensions, and query your infrastructure
- **A cognitive computing platform** — 242 brain-modeled extensions across 18 cognitive domains
- **A digital worker platform** — AI-as-labor with governance, risk tiers, and cost tracking

## Quick Start

```bash
gem install legionio
legion check              # verify subsystem connections
legion start              # start the daemon
```

For the AI features:

```bash
legion chat               # interactive AI REPL with 10 built-in tools
legion commit             # AI-generated commit message from staged changes
legion review             # AI code review of your code
```

## Installation

```bash
gem install legionio
```

Or add to your Gemfile:

```ruby
gem 'legionio'
```

### Optional Capabilities

| Gem | What It Unlocks |
|-----|-----------------|
| `legion-data` | Task history, scheduling, chains (SQLite/PostgreSQL/MySQL) |
| `legion-llm` | AI chat, commit, review, agents, multi-provider LLM routing |
| `legion-cache` | Redis/Memcached caching for extensions |
| `legion-crypt` | Vault integration, encryption, JWT auth |

## Infrastructure

| Component | Role | Required? |
|-----------|------|-----------|
| **RabbitMQ** | Task distribution (AMQP 0.9.1) | Yes |
| **SQLite/PostgreSQL/MySQL** | Persistence (tasks, scheduling, chains) | Optional |
| **Redis/Memcached** | Extension caching | Optional |
| **HashiCorp Vault** | Secrets, PKI, encrypted settings | Optional |

## The CLI

Everything runs through `legion`:

### Daemon & Health

```bash
legion start                    # foreground
legion start -d                 # daemonize
legion start --http-port 8080   # custom API port
legion status                   # service status
legion stop                     # graceful shutdown
legion check                    # smoke-test all connections
legion check --extensions       # also verify extensions
legion check --full             # full boot including API
```

### Extensions (LEX)

Extensions are gems named `lex-*`, auto-discovered at startup:

```bash
legion lex list                 # installed extensions
legion lex info <name>          # runners, actors, dependencies
legion lex create <name>        # scaffold a new extension
legion lex enable <name>        # enable / disable
```

### Tasks

```bash
legion task run http.request.get url:https://example.com   # dot notation
legion task run -e http -r request -f get                   # explicit flags
legion task run                                             # interactive picker
legion task list                                            # recent tasks
legion task show <id>                                       # detail + logs
```

### AI Chat

An interactive AI coding assistant with project awareness, persistent memory, tool use, and multi-agent coordination. Requires `legion-llm`.

```bash
legion chat                             # interactive REPL
legion chat prompt "explain main.rb"    # single-prompt mode
echo "fix the bug" | legion chat prompt - # pipe from stdin
```

**10 built-in tools**: read_file, write_file, edit_file, search_files, search_content, run_command, save_memory, search_memory, web_search, spawn_agent

**Slash commands**: `/help` `/quit` `/cost` `/status` `/clear` `/new` `/save` `/load` `/sessions` `/compact` `/fetch URL` `/search QUERY` `/diff` `/copy` `/rewind` `/memory` `/agent` `/agents` `/plan` `/swarm` `/review` `/permissions` `/personality` `/model` `/edit` `/commit` `/workers` `/dream`

**Bang commands**: `!ls -la` — run shell commands with output injected into context

**At-mentions**: `@reviewer check main.rb` — delegate to custom agents in `.legion/agents/`

### AI Workflows

```bash
legion commit                       # AI-generated commit message
legion pr                           # AI-generated PR title + description
legion pr --base develop --draft    # target branch, draft mode
legion review                       # AI code review of staged changes
legion review src/main.rb           # review specific files
legion review --diff                # review uncommitted diff
```

### Multi-Agent Orchestration

```bash
legion plan                         # read-only exploration mode (AI reasons, no writes)
legion swarm start deploy-pipeline  # run multi-agent workflow
legion swarm list                   # available workflows
```

### Memory

Persistent project and global memory that survives across sessions:

```bash
legion memory list                  # project memories
legion memory add "always use rspec"
legion memory search "testing"
legion memory forget 3
```

### Digital Workers

AI-as-labor with governance, risk tiers, and cost tracking:

```bash
legion worker list                  # list workers
legion worker show <id>             # worker detail
legion worker create <name>         # register new worker (bootstrap state)
legion worker pause <id>            # pause / activate / retire
legion worker costs --days 30       # cost report
```

### Code Generation

Run inside a `lex-*` directory:

```bash
legion generate runner <name>       # add runner + spec
legion generate actor <name>        # add actor + spec
legion g exchange <name>            # 'g' is an alias
```

### Scheduling

Requires `lex-scheduler`:

```bash
legion schedule add alerts "*/5 * * * *" http.request.get
legion schedule add daily "every day at noon" report.generate.summary
legion schedule list
```

### Configuration

```bash
legion config show              # resolved config (redacted)
legion config validate          # verify settings + subsystem health
legion config scaffold          # generate starter config files (auto-detects env vars)
```

`config scaffold` auto-detects environment variables (`ANTHROPIC_API_KEY`, `AWS_BEARER_TOKEN_BEDROCK`, `OPENAI_API_KEY`, `GEMINI_API_KEY`, `VAULT_TOKEN`, `RABBITMQ_USER`/`PASSWORD`) and a running Ollama instance, enabling providers and setting `env://` references automatically.

Settings load from the first directory found: `/etc/legionio/` → `~/legionio/` → `./settings/`

### Diagnostics

```bash
legion doctor                   # diagnose environment, suggest fixes
legion doctor --fix             # auto-remediate fixable issues (stale PIDs, missing gems)
legion doctor --json            # machine-readable output
```

Checks Ruby version, bundle status, config files, RabbitMQ, database, cache, Vault, extensions, PID files, and permissions. Exits 1 if any check fails.

### Updating

```bash
legion update                   # update all legion gems in-place
legion update --dry-run         # check what's available without installing
```

Uses the same Ruby that `legion` is running from — safe for Homebrew installs (updates go into the bundled gem directory, not your system Ruby).

All commands support `--json` for structured output and `--no-color` to strip ANSI codes.

## REST API

The daemon exposes a REST API on port 4567 (configurable):

| Route | Description |
|-------|-------------|
| `GET /api/health` | Health check |
| `GET /api/ready` | Readiness + component status |
| `GET/POST /api/tasks` | List / create tasks |
| `GET /api/extensions` | Installed extensions + runners |
| `GET /api/nodes` | Cluster nodes |
| `GET/POST/PUT/DELETE /api/schedules` | Cron / interval scheduling |
| `GET /api/settings` | Config (sensitive values redacted) |
| `GET /api/transport` | RabbitMQ connection status |
| `GET /api/events` | SSE event stream |
| `GET/POST/PUT/DELETE /api/workers` | Digital worker lifecycle |
| `POST /api/coldstart/ingest` | Context ingestion |

```json
{
  "data": { "..." },
  "meta": { "timestamp": "2026-03-15T12:00:00Z", "node": "legion-01" }
}
```

## MCP Server

LegionIO exposes itself as an [MCP](https://modelcontextprotocol.io/) server, letting any AI agent run tasks, manage extensions, and query infrastructure directly.

```bash
legion mcp                # stdio transport (Claude Desktop, agent SDKs)
legion mcp http           # streamable HTTP on localhost:9393
legion mcp http --port 8080 --host 0.0.0.0
```

**30 tools** in the `legion.*` namespace:

| Category | Tools |
|----------|-------|
| **Agentic** | `run_task`, `describe_runner` |
| **Tasks** | `list_tasks`, `get_task`, `delete_task`, `get_task_logs` |
| **Extensions** | `list_extensions`, `get_extension`, `enable_extension`, `disable_extension` |
| **Chains** | `list_chains`, `create_chain`, `update_chain`, `delete_chain` |
| **Relationships** | `list_relationships`, `create_relationship`, `update_relationship`, `delete_relationship` |
| **Schedules** | `list_schedules`, `create_schedule`, `update_schedule`, `delete_schedule` |
| **System** | `get_status`, `get_config` |
| **Workers** | `list_workers`, `show_worker`, `worker_lifecycle`, `worker_costs`, `team_summary` |
| **Analytics** | `routing_stats` |

**Resources**: `legion://runners` (full runner catalog), `legion://extensions/{name}` (extension detail)

## Task Relationships

### Conditions

JSON rule engine via `lex-conditioner`. Supports nested `all`/`any` with operators:

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

Access Vault secrets inline: `<%= Legion::Crypt.read('pushover/token') %>`

## Extensions

Browse: [LegionIO GitHub](https://github.com/LegionIO) | [legionio topic](https://github.com/topics/legionio?l=ruby)

### Core (13 operational extensions)

`lex-node` `lex-tasker` `lex-conditioner` `lex-transformer` `lex-scheduler` `lex-health` `lex-log` `lex-ping` `lex-exec` `lex-lex` `lex-codegen` `lex-metering` `lex-coldstart`

### Agentic (242 cognitive extensions)

Brain-modeled cognitive architecture. 20 core orchestration extensions plus 222 expanded modules across 18 domains:

| Domain | Examples |
|--------|----------|
| **Orchestration** | `lex-tick`, `lex-cortex`, `lex-dream`, `lex-memory`, `lex-identity` |
| **Emotion** | `lex-emotion`, `lex-mood`, `lex-empathy` |
| **Reasoning** | `lex-prediction`, `lex-planning`, `lex-logic` |
| **Social** | `lex-trust`, `lex-consent`, `lex-governance` |
| **Metacognition** | `lex-reflection`, `lex-awareness`, `lex-curiosity` |

Coordinated by [legion-gaia](https://github.com/LegionIO/legion-gaia), the cognitive coordination layer with tick-cycle scheduling, channel abstraction, and weighted routing across cognitive modules.

### AI / LLM (3 provider extensions)

`lex-claude` `lex-openai` `lex-gemini`

Powered by [legion-llm](https://github.com/LegionIO/legion-llm) with three-tier routing (local Ollama, fleet GPU servers, cloud APIs), intent-based dispatch, health tracking, and automatic model discovery.

### Service Integrations (8 common + 15 additional)

**Common**: `lex-http` `lex-redis` `lex-s3` `lex-github` `lex-consul` `lex-nomad` `lex-vault` `lex-microsoft_teams`

**Additional**: `lex-ssh` `lex-slack` `lex-smtp` `lex-influxdb` `lex-pagerduty` `lex-elasticsearch` `lex-chef` `lex-pushover` `lex-twilio` `lex-todoist` `lex-pushbullet` `lex-sleepiq` `lex-elastic_app_search` `lex-memcached` `lex-sonos`

### Build Your Own

```bash
legion lex create myextension
cd lex-myextension
legion generate runner myrunner
legion generate actor myactor
bundle exec rspec
```

## Role Profiles

Control which extensions load at startup via `settings/legion.json`:

```json
{"role": {"profile": "dev"}}
```

| Profile | What loads |
|---------|-----------|
| *(default)* | Everything — no filtering |
| `core` | 14 core operational extensions only |
| `cognitive` | core + all agentic extensions |
| `service` | core + service + other integrations |
| `dev` | core + AI + essential agentic (~20 extensions) |
| `custom` | only what's listed in `role.extensions` |

Faster boot and lower memory footprint for dedicated worker roles.

## Scaling

Task distribution uses RabbitMQ FIFO queues. Add workers by running more Legion processes — each subscribes to the same queues and picks up work automatically. Tested to 100+ workers.

Run different LEX combinations per worker: 10 pods focused on `lex-ssh`, a separate pod for `lex-pagerduty` + `lex-log` notifications.

No paid tiers. No feature gates. Full HA out of the box.

## Security

- **Message encryption**: AES-256-CBC via `legion-crypt`
- **Vault integration**: Secrets, PKI, encrypted settings
- **Node identity**: Each worker generates a keypair for inter-node communication
- **Cluster secret**: Generated at first startup, distributed via Vault or in-memory
- **JWT auth**: Bearer token authentication on the REST API
- **API key support**: `X-API-Key` header authentication

## Docker

```bash
docker pull legionio/legion
```

```dockerfile
FROM ruby:3-alpine
RUN gem install legionio
CMD ruby --yjit $(which legion) start
```

## Architecture

Before any Legion code loads, the executable applies three performance optimizations:

- **YJIT** — `RubyVM::YJIT.enable` for 15-30% runtime throughput (Ruby 3.1+ builds)
- **GC tuning** — pre-allocates 600k heap slots and raises malloc limits (ENV overrides respected)
- **bootsnap** — caches YARV bytecodes and `$LOAD_PATH` resolution at `~/.legionio/cache/bootsnap/`

```
legion start
  └── Legion::Service
      ├── 1. Logging          (legion-logging)
      ├── 2. Settings         (legion-settings — /etc/legionio, ~/legionio, ./settings)
      ├── 3. Crypt            (legion-crypt — Vault connection)
      ├── 4. Transport        (legion-transport — RabbitMQ)
      ├── 5. Cache            (legion-cache — Redis/Memcached)
      ├── 6. Data             (legion-data — database + migrations)
      ├── 7. LLM              (legion-llm — AI provider setup + routing)
      ├── 8. Supervision      (process supervision)
      ├── 9. Extensions       (discover + load 280+ LEX gems, filtered by role profile)
      ├── 10. Cluster Secret  (distribute via Vault or memory)
      └── 11. API             (Sinatra/Puma on port 4567)
```

Each phase registers with `Legion::Readiness`. All phases are individually toggleable.

`SIGHUP` triggers a live reload (`Legion.reload`) — subsystems shut down in reverse order and restart fresh without killing the process. Useful for rolling restarts and config changes.

## Similar Projects

| Project | Language | HA | AI | Cognitive |
|---------|----------|----|----|-----------|
| **LegionIO** | Ruby | Yes | Chat, MCP, agents, LLM routing | 242 extensions |
| [Node-RED](https://nodered.org/) | JS | No | No | No |
| [n8n.io](https://n8n.io/) | TS | Limited | Limited | No |
| [StackStorm](https://stackstorm.com/) | Python | Yes | No | No |
| [Huginn](https://github.com/huginn/huginn) | Ruby | No | No | No |

## Development

```bash
git clone https://github.com/LegionIO/LegionIO.git
cd LegionIO
bundle install
bundle exec rspec       # 880 examples, 0 failures
bundle exec rubocop     # 0 offenses
```

## License

Apache-2.0
