# LEX Standalone Client Pattern Design

**Date**: 2026-03-13
**Status**: Approved

## Goal

LEX gems should be usable as standalone API client libraries. `gem install lex-redis` + `require` + `Client.new` = working API client, no full LegionIO framework needed.

## Problem

Today, LEX runner methods work as module-level methods deeply nested in `Legion::Extensions::{Name}::Runners::{Runner}`. They rely on `Legion::Extensions::Helpers::Lex` for config via `settings`, which reads from `Legion::Settings[:extensions][:lex_name]`. While the actual API logic (Faraday calls, Redis commands, SSH sessions) has almost zero framework coupling, the ergonomics for standalone use are poor — long module paths, no instance-based API, and some methods hard-read from `settings` for defaults (e.g., lex-http timeouts).

## Design Decisions

### 1. Client Instance Pattern
Standard Ruby API gem convention. Users instantiate a Client with connection config, then call methods on it.

```ruby
client = Legion::Extensions::Redis::Client.new(host: '10.0.0.1', port: 6379)
client.set(key: 'foo', value: 'bar', ttl: 300)
client.get(key: 'foo')
```

### 2. Two Entry Points
- **Client instance** (stateful, standalone): `Client.new(host: '...').get(key: 'foo')`
- **Module method** (stateless, one-off): `Runners::Item.set(key: 'foo', value: 'bar', host: '...')`

Both use the same runner method code.

### 3. Client is Config-Agnostic
The Client class always requires explicit args in `initialize`. It never checks "am I in the framework?" or conditionally reads from `Legion::Settings`. Framework actors are responsible for constructing the Client from settings.

### 4. Convention, Not Inheritance
No shared base Client class. Each LEX implements its own Client class following the documented pattern. The `lex_gen` template provides scaffolding. LEX owner decides what `initialize` needs for their specific service.

### 5. Runner Methods Accept Config as Keyword Args
Runner methods should accept config values as keyword args with sensible defaults, rather than reading from `settings` directly. This makes them work in both standalone and framework contexts.

```ruby
# Good: config-agnostic
def get(key:, host: '127.0.0.1', port: 6379, **opts)

# Avoid: framework-coupled
def get(key:, **)
  connection = connect(settings[:host], settings[:port])
```

### 6. Connection Lifecycle is LEX Owner's Choice
- HTTP-based LEXs are naturally stateless per-call
- Redis/SSH LEXs may benefit from persistent connections in the Client
- Framework actors always treat connections as stateless per-task

### 7. Framework Path Stays Stateless
Anything running through the LegionIO async process uses stateless per-task connections. The Client pattern with persistent connections is for standalone use only.

## Architecture

```
LEX Gem (e.g., lex-redis)
├── Runners/          # Pure business logic (module methods)
│   ├── Item          # get, set, delete, keys...
│   └── Server        # info, flushdb...
├── Helpers/          # Pure connection factories (explicit args)
│   └── Client        # Redis.new(host:, port:)
├── Client            # Standalone entry point
│   ├── initialize(host:, port:, ...) → stores @config
│   ├── include Runners::Item
│   ├── include Runners::Server
│   └── provides connection context to runner methods
├── Actors/           # Framework glue (AMQP subscription, etc.)
│   └── constructs from Legion::Settings, stateless per-task
└── Transport/        # Framework glue (exchanges, queues, messages)
```

## Standalone Usage Example

```ruby
require 'legion/extensions/redis'

client = Legion::Extensions::Redis::Client.new(host: '10.0.0.1', port: 6379)
client.set(key: 'user:1', value: 'Alice', ttl: 300)
result = client.get(key: 'user:1')  # => { result: "Alice" }
client.keys(glob: 'user:*')         # => { result: ["user:1"] }
```

## Stateless Module Usage Example

```ruby
require 'legion/extensions/redis'

Legion::Extensions::Redis::Runners::Item.set(
  key: 'user:1', value: 'Alice', host: '10.0.0.1', port: 6379
)
```

## Rollout Plan

1. Document the pattern in `extensions/CLAUDE.md` (done)
2. Update `lex_gen` template to scaffold a Client class
3. Implement Client on key LEXs: lex-http, lex-redis, lex-slack, lex-ssh
4. Refactor runner methods to accept config as keyword args
5. Update remaining LEXs incrementally
