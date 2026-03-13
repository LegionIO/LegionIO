# Getting Started with LegionIO

## Prerequisites

- Ruby >= 3.4
- RabbitMQ (running locally or accessible)
- Bundler

Optional:
- SQLite/PostgreSQL/MySQL (for task persistence via legion-data)
- Redis or Memcached (for caching via legion-cache)
- HashiCorp Vault (for secrets via legion-crypt)

## Quick Start

### 1. Install

```bash
gem install legionio
```

Or in a Gemfile:

```ruby
gem 'legionio'
```

### 2. Configure

Create a settings directory with JSON config files. LegionIO checks these paths in order:

1. `/etc/legionio/`
2. `~/legionio/`
3. `./settings/`

Minimal config (`settings/transport.json`):

```json
{
  "transport": {
    "connection": {
      "host": "127.0.0.1",
      "port": 5672,
      "user": "guest",
      "password": "guest"
    }
  }
}
```

### 3. Verify Connectivity

Before starting the daemon, verify all subsystems can connect:

```bash
legion check
```

This tests settings, crypt, transport (RabbitMQ), cache, and data (DB) connections, then shuts down. Add `--extensions` to also verify extension loading, or `--full` for a complete boot cycle including the API server.

### 4. Start the Daemon

```bash
legion start
```

Or with YJIT (recommended for Ruby 3.4):

```bash
ruby --yjit $(which legion) start
```

### 5. Install Extensions

Extensions are auto-discovered from installed gems:

```bash
gem install lex-http lex-redis lex-slack
```

Restart LegionIO and it will automatically load any `lex-*` gems found.

### 6. Send a Task

Using the CLI:

```bash
legion trigger queue --exchange http --routing-key http.http.get --args '{"host":"https://example.com","uri":"/api"}'
```

Or programmatically:

```ruby
require 'legion/transport'
Legion::Transport::Messages::Task.new(
  function: 'get',
  routing_key: 'http.http.get',
  host: 'https://example.com',
  uri: '/api'
).publish
```

## Docker

```bash
docker pull legionio/legion
docker run -e LEGION_TRANSPORT_HOST=rabbitmq legionio/legion
```

Or build your own:

```dockerfile
FROM ruby:3.4-alpine
RUN gem install legionio lex-http lex-redis
CMD ruby --yjit $(which legion) start
```

## Development Mode

For local development without external services:

```json
{
  "data": {
    "adapter": "sqlite"
  },
  "cache": {
    "enabled": false
  },
  "crypt": {
    "cluster_secret": null
  }
}
```

This gives you SQLite for persistence, no caching requirement, and no encryption. Only RabbitMQ is required.

## Configuration Reference

### Environment Variables

| Variable | Purpose |
|----------|---------|
| `LEGION_API_PORT` | HTTP API port (enables webhook endpoint) |
| `LEGION_LOADED_TEMPFILE_DIR` | Directory for loaded config tracking |

### Settings Keys

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `transport.connection.host` | string | `127.0.0.1` | RabbitMQ host |
| `transport.connection.port` | integer | `5672` | RabbitMQ port |
| `transport.connection.user` | string | `guest` | RabbitMQ user |
| `transport.connection.password` | string | `guest` | RabbitMQ password |
| `transport.connection.vhost` | string | `/` | RabbitMQ vhost |
| `transport.prefetch` | integer | `2` | Consumer prefetch count |
| `transport.messages.encrypt` | boolean | `false` | Enable message encryption |
| `transport.messages.persistent` | boolean | `true` | Durable messages |
| `data.adapter` | string | `sqlite` | Database adapter (sqlite, postgres, mysql2) |
| `data.creds.host` | string | | Database host |
| `data.creds.username` | string | | Database user |
| `data.creds.password` | string | | Database password |
| `data.creds.database` | string | | Database name |
| `cache.enabled` | boolean | `true` | Enable caching |
| `cache.driver` | string | `dalli` | Cache driver (dalli, redis) |
| `crypt.cluster_secret` | string | nil | Pre-shared cluster encryption key |
| `logging.level` | string | `info` | Log level (debug, info, warn, error, fatal) |
| `logging.location` | string | `stdout` | Log output (stdout, or file path) |
| `logging.format` | symbol | nil | Log format (nil for default, `:json` for structured) |
| `auto_install_missing_lex` | boolean | `true` | Auto-install missing LEX gems |
| `extensions.{name}.enabled` | boolean | `true` | Enable/disable specific extension |
| `extensions.{name}.workers` | integer | `1` | Worker thread count for extension |

### Settings Validation

Settings are validated automatically. Types are inferred from defaults:

```ruby
# Register defaults (types inferred)
Legion::Settings.merge_settings('mymodule', { host: 'localhost', port: 8080 })

# Optional: add constraints
Legion::Settings.define_schema('mymodule', {
  driver: { enum: %w[dalli redis] },
  port: { required: true }
})

# Validate everything
Legion::Settings.validate!
```

If validation fails, `ValidationError` is raised with all errors:

```
2 configuration errors detected:

  [mymodule] port: expected Integer, got String ("abc")
  [mymodule] driver: expected one of ["dalli", "redis"], got "memcache"
```

## Next Steps

- [Extension Development Guide](extension-development.md) — build your own LEX
- [Wire Protocol](protocol.md) — AMQP message format specification
- [Architecture Overview](overview.md) — deep dive into internals
- [Best Practices](best-practices.md) — conventions and patterns
