# Design: `legion config scaffold` Command

## Purpose

Generate starter JSON config files so users can set up LegionIO without reading docs. Writes one file per subsystem to a settings directory.

## Command Interface

```
legion config scaffold [--dir PATH] [--only LIST] [--full] [--force] [--json]
```

| Flag | Default | Behavior |
|------|---------|----------|
| `--dir PATH` | `./settings` | Output directory |
| `--only LIST` | all | Comma-separated: `transport,data,cache,crypt,logging,llm` |
| `--full` | off | Include every field with defaults instead of minimal starter |
| `--force` | off | Overwrite existing files |
| `--json` | off | Machine output: `{ created: [...], skipped: [...] }` |

## Subsystems and Minimal Templates

### transport.json

```json
{
  "transport": {
    "connection": {
      "host": "127.0.0.1",
      "port": 5672,
      "user": "guest",
      "password": "guest",
      "vhost": "/"
    }
  }
}
```

### data.json

```json
{
  "data": {
    "adapter": "sqlite",
    "creds": {
      "database": "legionio.db"
    }
  }
}
```

### cache.json

```json
{
  "cache": {
    "driver": "dalli",
    "servers": ["127.0.0.1:11211"],
    "enabled": true
  }
}
```

### crypt.json

```json
{
  "crypt": {
    "vault": {
      "enabled": false,
      "address": "localhost",
      "port": 8200,
      "token": null
    },
    "jwt": {
      "enabled": true,
      "default_algorithm": "HS256",
      "default_ttl": 3600
    }
  }
}
```

### logging.json

```json
{
  "logging": {
    "level": "info",
    "location": "stdout",
    "trace": true
  }
}
```

### llm.json

```json
{
  "llm": {
    "provider": null,
    "api_key": null,
    "model": null
  }
}
```

## Full Mode (`--full`)

Each file includes every field from the subsystem's `Settings.default` block with current default values. Same file structure, just the complete schema.

Full schemas sourced from:
- `Legion::Transport::Settings.default` (transport)
- `Legion::Data::Settings.default` (data)
- `Legion::Cache::Settings.default` (cache)
- `Legion::Crypt::Settings.default` (crypt)
- Hardcoded logging defaults from `Legion::Settings::Loader#default_settings`
- `Legion::LLM` settings (llm)

## Behavior

1. Create `--dir` directory if it doesn't exist
2. For each subsystem (filtered by `--only` if provided):
   - If file exists and `--force` not set: skip with warning
   - Otherwise: write the JSON file (pretty-printed)
3. Human output: list created/skipped files with paths
4. `--json` output: `{ "created": [...], "skipped": [...] }`

## Implementation

Single new file: `LegionIO/lib/legion/cli/config_scaffold.rb`

Registered as a subcommand of the existing `ConfigCommand` Thor class. No changes to legion-settings or other core libs - this only generates static JSON files.

## Scope

Only LegionIO + legion-* core libraries. No extension settings.
