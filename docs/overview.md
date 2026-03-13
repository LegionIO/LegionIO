# LegionIO Core Overview

## What is LegionIO?

LegionIO is a polyglot-capable, extensible task orchestration framework. It schedules tasks, creates relationships between them (chains with conditions and transformations), and executes them concurrently across a cluster of nodes. The core is written in Ruby. Extensions communicate over AMQP, making the framework language-agnostic at the extension layer.

LegionIO is not a web framework, a background job processor, or a workflow DSL. It is a **task execution engine** with a plugin system, a message bus, and a database-backed registry of capabilities.

## Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│                          LegionIO Node                               │
│                                                                      │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐  ┌──────────────┐  │
│  │  Settings   │  │  Logging   │  │    JSON    │  │    Crypt     │  │
│  │ config mgmt │  │  console   │  │ serialize  │  │ AES/RSA/Vault│  │
│  └──────┬──────┘  └──────┬─────┘  └─────┬──────┘  └──────┬───────┘  │
│         └────────────────┼───────────────┼────────────────┘          │
│                          │               │                           │
│                    ┌─────┴───────────────┴─────┐                     │
│                    │       LegionIO Core        │                    │
│                    │   Service orchestrator     │                    │
│                    │   Process daemon           │                    │
│                    │   Extension loader         │                    │
│                    │   Runner execution engine  │                    │
│                    │   CLI (Thor)               │                    │
│                    └──────┬──────────┬──────────┘                    │
│                           │          │                               │
│              ┌────────────┘          └────────────┐                  │
│              │                                    │                  │
│        ┌─────┴──────┐                      ┌──────┴─────┐           │
│        │  Transport  │                      │    Data    │           │
│        │  RabbitMQ   │                      │   MySQL    │           │
│        │  AMQP 0.9.1 │                      │  Sequel ORM│           │
│        └─────┬───────┘                      └──────┬─────┘           │
│              │                                     │                 │
│        ┌─────┴──────┐                      ┌───────┴────┐           │
│        │   Cache    │                      │   Models   │           │
│        │Redis/Memcache                     │ Extension  │           │
│        └────────────┘                      │ Runner     │           │
│                                            │ Function   │           │
│  ┌─────────────────────────────────────┐   │ Task       │           │
│  │         Extensions (LEX)            │   │ Node       │           │
│  │                                     │   └────────────┘           │
│  │  lex-http    lex-redis   lex-ssh    │                            │
│  │  lex-slack   lex-chef    lex-ping   │                            │
│  │  lex-scheduler  lex-tasker  ...     │                            │
│  └─────────────────────────────────────┘                            │
└──────────────────────────────────────────────────────────────────────┘
         │                    │                    │
         ▼                    ▼                    ▼
    ┌─────────┐         ┌─────────┐         ┌─────────┐
    │ RabbitMQ │         │  MySQL  │         │ Redis/  │
    │  Broker  │         │   DB    │         │Memcached│
    └─────────┘         └─────────┘         └─────────┘
```

## Core Gems

LegionIO is decomposed into 8 gems, each with a single responsibility. They are listed here in dependency order (foundational first).

### legion-json (v1.2.0)

JSON serialization wrapper. Wraps `multi_json` and `json_pure` to provide a consistent `Legion::JSON.dump` / `Legion::JSON.load` interface. Automatically uses faster C-extension JSON libraries (`oj`) when available.

**Why it exists**: Every other gem needs JSON. Centralizing the serialization library means swapping JSON backends (e.g., switching from `oj` to `yajl`) is a one-gem change.

**Key interface**:
```ruby
Legion::JSON.dump(hash)    # -> JSON string
Legion::JSON.load(string)  # -> Ruby hash
```

### legion-logging (v1.2.0)

Colorized console logging via Rainbow. Provides `Legion::Logging.info`, `.warn`, `.error`, `.fatal`, `.debug` as singleton methods.

**Why it exists**: Consistent log formatting and level control across all gems. First module initialized during startup.

**Key interface**:
```ruby
Legion::Logging.setup(level: 'info', log_file: nil)
Legion::Logging.info("message")
Legion::Logging.error(exception.message)
```

### legion-settings (v1.2.0)

Configuration management. Loads settings from JSON files, directories, and environment variables. Provides a hash-like `Legion::Settings[:key]` accessor.

**Why it exists**: Every gem has configuration. Settings centralizes loading, merging, and access so individual gems don't each invent their own config system.

**Config loading order**:
1. Environment variables
2. Config file (if specified)
3. Config directory (first match from: `/etc/legionio`, `~/legionio`, `./settings`)
4. Module defaults (each gem registers its own via `merge_settings`)

**Key interface**:
```ruby
Legion::Settings.load(config_dir: '/etc/legionio')
Legion::Settings[:transport]           # transport config hash
Legion::Settings[:cache][:driver]      # specific nested value
Legion::Settings.merge_settings(:data, Legion::Data::Settings.default)
```

**Settings are organized by module key**:
```
Legion::Settings[:transport]   # legion-transport config
Legion::Settings[:cache]       # legion-cache config
Legion::Settings[:crypt]       # legion-crypt config
Legion::Settings[:data]        # legion-data config
Legion::Settings[:client]      # node identity (name, hostname, ready state)
Legion::Settings[:extensions]  # per-extension config
```

### legion-crypt (v1.2.0)

Encryption, key management, and HashiCorp Vault integration.

**What it provides**:
- **AES-256-CBC encryption** for inter-node message encryption
- **RSA key pair generation** (dynamic per-process by default)
- **Cluster secret**: A shared AES key distributed across all nodes in the cluster
- **Vault integration**: Token lifecycle management, secret read/write, automatic token renewal via background thread

**Why it exists**: Legion nodes need to communicate securely. The cluster secret enables encrypted messages between nodes without pre-shared keys. Vault provides dynamic credentials for RabbitMQ, MySQL, and other services.

**Key interface**:
```ruby
Legion::Crypt.start                    # generate keys, connect to Vault
Legion::Crypt.encrypt("plaintext")     # -> { enciphered_message:, iv: }
Legion::Crypt.decrypt(message, iv)     # -> "plaintext"
Legion::Crypt.cs                       # distribute cluster secret to new nodes
```

**Vault conditional loading**: The Vault module is only included if the `vault` gem is installed. Legion works without Vault - encryption is optional.

### legion-transport (v1.2.0)

AMQP 0.9.1 messaging layer over RabbitMQ. Manages connections, exchanges, queues, messages, and consumers.

**What it provides**:
- **Thread-safe connection management** via `Concurrent::AtomicReference` (session) and `Concurrent::ThreadLocalVar` (channels)
- **Exchange, Queue, Message, Consumer** base classes that extensions subclass
- **AMQP 0.9.1 client**: Bunny gem for RabbitMQ connectivity
- **Auto-recreate on mismatch**: If a queue/exchange declaration conflicts with an existing one, it deletes and recreates
- **Dead-letter exchanges**: Every extension gets a `.dlx` exchange and queue automatically
- **Optional message encryption**: When enabled, messages are encrypted with the cluster secret before publishing

**Key abstractions**:
```ruby
# Publishing a message
Legion::Transport::Messages::Task.new(function: 'get', args: { url: '...' }).publish

# Exchanges and queues are declared by instantiation
Legion::Transport::Exchange.new('my_exchange')  # creates if not exists
Legion::Transport::Queue.new('my_queue')        # creates if not exists, binds to exchange
```

**Message flow**: See `docs/protocol.md` for the complete wire protocol specification.

**Connection settings** (with env var overrides):

| Setting | Default | Description |
|---------|---------|-------------|
| `transport.connection.host` | `127.0.0.1` | RabbitMQ host |
| `transport.connection.port` | `5672` | RabbitMQ port |
| `transport.connection.user` | `guest` | RabbitMQ user |
| `transport.connection.password` | `guest` | RabbitMQ password |
| `transport.connection.vhost` | `/` | Virtual host |
| `transport.prefetch` | `2` | Consumer prefetch count |
| `transport.messages.encrypt` | `false` | Enable message encryption |
| `transport.messages.persistent` | `true` | Durable messages |

### legion-cache (v1.2.0)

Caching layer with pluggable backends.

**Backends**: Memcached (via `dalli`, default) or Redis (via `redis` gem). Driver selected at load time from `Legion::Settings[:cache][:driver]`.

**Why it exists**: Extensions need caching (e.g., `lex-scheduler` uses cache for distributed locking). The data layer can use Sequel's caching plugin backed by this gem.

**Key interface**:
```ruby
Legion::Cache.setup
Legion::Cache.set('key', 'value', ttl)
Legion::Cache.get('key')
Legion::Cache.connected?
```

### legion-data (v1.2.0)

Persistent storage via MySQL and the Sequel ORM.

**What it provides**:
- **Automatic schema migrations** on startup (8 core migrations)
- **Data models** for the extension registry, task tracking, and cluster state
- **Extension-specific migrations**: Each LEX can define its own migrations (e.g., `lex-scheduler` adds 6 tables)

**Database schema**:

```
extensions
├── id, name, namespace, exchange, uri, active, schema_version
│
├── runners (FK: extension_id)
│   ├── id, name, namespace, queue, uri, active
│   │
│   └── functions (FK: runner_id)
│       ├── id, name, args (JSON), active
│       │
│       └── tasks (FK: function_id)
│           ├── id, status, parent_id (self-ref), master_id (self-ref)
│           ├── relationship_id, function_args, results, payload
│           │
│           └── task_logs (FK: task_id)
│               └── id, function_id, entry, node_id

nodes
├── id, name, status, active

settings
├── id, key, value, encrypted
```

**Model relationships**:
- Extension has many Runners
- Runner has many Functions
- Function has many Tasks
- Task has many TaskLogs
- Task has parent/child (self-referential) for chain tracking
- Task has master/slave (self-referential) for root task tracking

**Database backends**: SQLite (development), PostgreSQL, and MySQL are all supported. The adapter is selected via `Legion::Settings[:data][:adapter]` (defaults to `sqlite` if no credentials are configured).

### legionio gem (v1.2.1)

The main framework gem. Orchestrates all other gems and provides the extension system.

**Subcomponents**:

#### Service (`Legion::Service`)

The startup orchestrator. Initializes all modules in order:

```
1. setup_logging       → legion-logging (console output ready)
2. setup_settings      → legion-settings (config loaded from disk)
3. Legion::Crypt.start → legion-crypt (keys generated, Vault connected)
4. setup_transport     → legion-transport (RabbitMQ connected)
5. require legion-cache → legion-cache (cache backend connected)
6. setup_data          → legion-data (MySQL connected, migrations run, models loaded)
7. setup_supervision   → process supervision initialized
8. load_extensions     → discover and load all lex-* gems
9. Legion::Crypt.cs    → distribute cluster secret to other nodes
```

Each step is optional. You can start Legion without data (`data: false`), without caching (`cache: false`), or without encryption (`crypt: false`). The extension loader checks prerequisites before loading each extension.

#### Process (`Legion::Process`)

Daemon lifecycle management:
- **PID file management**: Write, check, clean up PID files
- **Daemonization**: Double-fork, `setsid`, detach from terminal
- **Signal handling**: SIGINT for graceful shutdown, SIGTERM/SIGHUP trapped
- **Time-limited execution**: Optional `time_limit` for test/CI runs

#### Extensions System (`Legion::Extensions`)

The heart of the framework. Discovers, loads, and wires up all LEX gems.

**Discovery** (`find_extensions`):
- Scans `Gem::Specification.all_names` for gems starting with `lex-`
- Auto-installs missing gems if `auto_install` is enabled in settings
- Builds a registry: gem name, version, derived Ruby class name

**Loading** (`load_extension`):
- Requires the gem's main file
- Mixes in `Legion::Extensions::Core` (builders, helpers, transport)
- Checks prerequisites: data_required? cache_required? crypt_required? vault_required?
- Calls `autobuild` (see below)
- Publishes a `LexRegister` message to announce the extension to the cluster
- Hooks actors into the execution system

**Autobuild** (`autobuild` in `Legion::Extensions::Core`):
1. `build_settings` - merge extension defaults with user config
2. `build_transport` - declare AMQP exchanges, queues, bindings, dead-letter topology
3. `build_data` - run extension-specific database migrations (if data required)
4. `build_helpers` - load helper modules
5. `build_runners` - discover runner classes, introspect public methods, build function registry
6. `build_actors` - discover actor classes, **auto-generate Subscription actors** for runners that don't have explicit actors

**Meta-actor generation**: If a runner has no corresponding actor class, the framework dynamically creates one:
```ruby
Class.new(Legion::Extensions::Actors::Subscription)
```
This means writing a single runner file with public methods is enough to get a fully functional AMQP-connected extension. No actor, transport, or queue boilerplate required.

#### Actor Types

Actors determine **how** a runner function executes:

| Actor | Base Class | Behavior |
|-------|-----------|----------|
| **Subscription** | `Legion::Extensions::Actors::Subscription` | Subscribes to AMQP queue, executes on message arrival. Runs in a `FixedThreadPool` with configurable worker count. |
| **Every** | `Legion::Extensions::Actors::Every` | Runs at a fixed interval via `Concurrent::TimerTask`. Configurable `time` (seconds) and `timeout`. |
| **Once** | `Legion::Extensions::Actors::Once` | Runs once at startup, then stops. |
| **Loop** | `Legion::Extensions::Actors::Loop` | Continuous execution loop. |
| **Poll** | `Legion::Extensions::Actors::Poll` | Polling-based execution. |
| **Nothing** | `Legion::Extensions::Actors::Nothing` | Registered but does not execute. |

**Subscription actors** are the default. When an AMQP message arrives:
1. Decrypt body if encrypted
2. Parse JSON
3. Merge AMQP headers into message hash
4. Determine function name (from actor override or message body)
5. Call `Legion::Runner.run(runner_class:, function:, **message)`
6. ACK on success, REJECT on failure

#### Runner (`Legion::Runner`)

The task execution engine. `Legion::Runner.run` is the single entry point for all task execution:

```
Runner.run(runner_class:, function:, **args)
  │
  ├── Generate task_id (if DB connected and generate_task is true)
  │     └── INSERT into tasks table with status 'task.queued'
  │
  ├── Execute: runner_class.send(function, **args)
  │
  ├── On success: status = 'task.completed'
  │   On exception: status = 'task.exception'
  │
  ├── Update task status (DB direct or via TaskUpdate message)
  │
  └── If check_subtask: publish CheckSubtask message
        └── Carries results to lex-tasker for relationship chain evaluation
```

#### CLI (`legion` command)

Thor-based command-line interface:

| Subcommand | Description |
|-----------|-------------|
| `legion lex create <name>` | Scaffold a new extension |
| `legion lex actor create <name>` | Add an actor to current extension |
| `legion lex runner create <name>` | Add a runner to current extension |
| `legion lex queue create <name>` | Add a queue to current extension |
| `legion lex exchange create <name>` | Add an exchange to current extension |
| `legion lex message create <name>` | Add a message to current extension |
| `legion trigger queue` | Send a task to a worker (interactive or flags) |
| `legion relationship create` | Create a task relationship |
| `legion task` | Task management |
| `legion chain` | Chain management |
| `legion function` | Function queries |
| `legion cohort` | Cohort management |

**`legion start` command**: Starts the daemon process.

## Task Relationships and Chaining

The power of LegionIO is in task relationships. A relationship connects two functions: when function A completes, function B fires (optionally with conditions and transformations).

### Chain Flow

```
Task A completes
  │
  ▼
CheckSubtask message published (carries A's results)
  │
  ▼
lex-tasker receives CheckSubtask
  │
  ├── Looks up relationships where trigger = function A
  │
  ├── For each relationship:
  │     │
  │     ├── Has conditions?
  │     │     └── Route to lex-conditioner
  │     │           ├── Pass → continue
  │     │           └── Fail → stop (conditioner.failed)
  │     │
  │     ├── Has transformation?
  │     │     └── Route to lex-transformer
  │     │           └── Apply ERB template to results → new payload
  │     │
  │     └── Publish Task message for function B
  │
  └── Multiple relationships = parallel fan-out
```

### Conditions

JSON rule engine evaluated by `lex-conditioner`:

```json
{
  "all": [
    { "fact": "status_code", "operator": "equal", "value": 200 },
    { "fact": "response_time", "operator": "less_than", "value": 5000 }
  ],
  "any": [
    { "fact": "region", "operator": "equal", "value": "us-east" },
    { "fact": "region", "operator": "equal", "value": "us-west" }
  ]
}
```

`all` = AND, `any` = OR. Each rule has a `fact` (field name in results), `operator`, and `value`.

### Transformations

ERB templates evaluated by `lex-transformer`:

```erb
Alert: <%= results['message'] %> on host <%= results['hostname'] %>
Severity: <%= results['level'] %>
```

The template receives the previous task's results hash and produces the payload for the next task.

## Built-In Extensions

These extensions are part of the core and handle framework-level concerns:

| Extension | Purpose |
|-----------|---------|
| **lex-node** | Node identity, heartbeat broadcasting, cluster secret exchange, Vault token management |
| **lex-tasker** | Task lifecycle: status tracking, subtask evaluation, delayed task scheduling, logging |
| **lex-conditioner** | Conditional rule evaluation for task chain branching |
| **lex-transformer** | ERB-based payload transformation between chained tasks |
| **lex-scheduler** | Cron and interval scheduling with distributed lock (via cache) and DB persistence |
| **task_pruner** | Cleanup old task history records |

## Cluster Behavior

### Multi-Node

Multiple Legion nodes can run simultaneously against the same RabbitMQ broker and MySQL database. RabbitMQ's consumer model distributes messages across nodes automatically. The scheduler uses a distributed lock (via `Legion::Cache`) to ensure only one node runs scheduled tasks.

### Node Discovery

Each node:
1. Generates an RSA key pair on startup
2. Broadcasts heartbeats via `lex-node`
3. Requests the cluster secret from existing nodes
4. Receives the cluster secret encrypted with its public key
5. Registers its loaded extensions with the cluster

### Graceful Shutdown

```
SIGINT received
  │
  ├── Set shutting_down flag
  ├── Cancel all subscription consumers
  ├── Shutdown thread pools (5s timeout, then kill)
  ├── Cancel timer tasks (Every, Poll)
  ├── Close database connections
  ├── Close cache connections
  ├── Close RabbitMQ connection
  ├── Stop Vault token renewer
  └── Exit
```

## Extension Development

### Minimal Extension (Runner Only)

A runner file is all you need. The framework auto-generates everything else:

```ruby
# lib/legion/extensions/example/runners/greeting.rb
module Legion::Extensions::Example::Runners
  module Greeting
    def say_hello(name:, **_opts)
      { message: "Hello, #{name}!" }
    end
  end
end
```

This automatically gets:
- An AMQP exchange (`example`)
- A queue (`example.greeting`) bound to the exchange
- A subscription actor consuming from the queue
- A dead-letter exchange and queue (`example.dlx`)
- Registration in the cluster function registry

### Full Extension Structure

```
lex-myext/
├── lib/legion/extensions/myext.rb           # Entry point
├── lib/legion/extensions/myext/version.rb   # Version
├── lib/legion/extensions/myext/
│   ├── runners/                             # Business logic
│   │   └── widget.rb                        # Module with public methods = functions
│   ├── actors/                              # Execution mode (optional)
│   │   └── widget.rb                        # Subscription/Every/Once/Loop/Poll
│   ├── helpers/                             # Shared utilities (optional)
│   │   └── client.rb                        # Connection helpers
│   ├── transport/                           # AMQP topology (optional)
│   │   ├── exchanges/widget.rb
│   │   ├── queues/widget.rb
│   │   └── messages/widget.rb
│   └── data/                                # Database schema (optional)
│       ├── migrations/001_create_widgets.rb
│       └── models/widget.rb
├── spec/
├── lex-myext.gemspec
└── Gemfile
```

### Scaffolding

```bash
legion lex create myext
legion lex runner create widget
legion lex actor create widget
```

## Configuration

### File-Based Config

Place JSON files in `/etc/legionio/`, `~/legionio/`, or `./settings/`:

```json
// transport.json
{
  "transport": {
    "connection": {
      "host": "rabbitmq.example.com",
      "port": 5672,
      "user": "legion",
      "password": "secret"
    }
  }
}
```

```json
// data.json
{
  "data": {
    "creds": {
      "host": "mysql.example.com",
      "username": "legion",
      "password": "secret",
      "database": "legionio"
    }
  }
}
```

```json
// extensions.json
{
  "extensions": {
    "http": {
      "enabled": true,
      "workers": 4
    },
    "slack": {
      "enabled": true,
      "api_token": "xoxb-..."
    }
  }
}
```

### Per-Extension Config

Extensions read their config from `Legion::Settings[:extensions][:extension_name]`. Extensions can define default settings by overriding `default_settings` in their module.

## Deployment

### Docker

```dockerfile
FROM ruby:3-alpine
RUN gem install legionio
CMD ruby --yjit $(which legion) start
```

### Systemd

```ini
[Unit]
Description=LegionIO
After=rabbitmq-server.service mysql.service

[Service]
ExecStart=/usr/local/bin/legion start
Restart=always
User=legion

[Install]
WantedBy=multi-user.target
```

### Requirements

| Service | Required | Purpose |
|---------|----------|---------|
| RabbitMQ | Yes | Message broker |
| MySQL | No | Persistent storage (task tracking, extension registry, scheduling) |
| Redis or Memcached | No | Caching, distributed locking |
| HashiCorp Vault | No | Dynamic credentials, message encryption |

Only RabbitMQ is required. All other services are optional and gracefully degrade when unavailable.

### Settings Validation

legion-settings now includes automatic schema validation:

```ruby
# Types are inferred from defaults — no manual schema needed
Legion::Settings.merge_settings('mymodule', { host: 'localhost', port: 8080 })

# Optional: add constraints
Legion::Settings.define_schema('mymodule', { driver: { enum: %w[dalli redis] } })

# Validate all settings at once
Legion::Settings.validate!  # raises ValidationError with all errors collected
```

- **Type inference**: Types derived from default values automatically
- **Per-module on merge**: Type mismatches caught immediately when a module registers
- **Cross-module on startup**: `validate!` runs all checks, collects errors, raises once
- **Unknown key detection**: Typo suggestions via Levenshtein distance

### Event Bus (`Legion::Events`)

In-process pub/sub for lifecycle and task events:

```ruby
Legion::Events.subscribe('task.completed') { |data| log_completion(data) }
Legion::Events.subscribe('service.ready') { |data| notify_cluster(data) }
Legion::Events.emit('task.completed', task_id: 123, status: 'success')
```

Events: `service.ready`, `service.shutting_down`, `extension.loaded`, `task.completed`, `task.failed`

### Transport Abstraction (`Legion::Ingress`)

Source-agnostic entry point for runner invocation. Normalizes input regardless of source (AMQP, HTTP, direct call) and routes to `Legion::Runner.run`.

### Webhook API (`Legion::API`)

Sinatra-based HTTP API for receiving webhooks. Extensions can register hook endpoints via `Legion::Extensions::Hooks::Base`. The API adapter feeds through `Legion::Ingress` so webhooks follow the same execution path as AMQP messages.

### Readiness (`Legion::Readiness`)

Tracks startup readiness across all modules. Replaces the previous sleep-based approach with explicit readiness signals from each component.

## Version History

All core gems are currently at v1.2.0 (the `legionio` gem at v1.2.1). The framework requires Ruby >= 3.4.
