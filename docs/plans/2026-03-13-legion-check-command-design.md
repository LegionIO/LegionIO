# Design: `legion check` Command

**Date**: 2026-03-13
**Status**: Approved

## Purpose

A CLI command that starts Legion subsystems, verifies they initialize correctly, reports pass/fail per component, and shuts down. Used for smoke testing, CI validation, and deployment verification.

## Command Interface

```
legion check [--extensions] [--full] [--json] [--verbose] [--no-color] [--config-dir DIR]
```

### Depth Levels

| Flag | Level | Subsystems Checked |
|------|-------|--------------------|
| (default) | connections | settings, crypt, transport, cache, data |
| `--extensions` | extensions | connections + extension discovery and loading |
| `--full` | full | extensions + API startup + full readiness verification |

### Output (text mode)

```
$ legion check
  settings    pass
  crypt       pass
  transport   FAIL  Connection refused - connect(2) for 127.0.0.1:5672
  cache       pass
  data        pass

  4/5 passed (transport failed)
```

With `--verbose`, each line includes elapsed time:

```
  settings    pass  (0.02s)
  crypt       pass  (0.15s)
```

### Output (JSON mode)

```json
{
  "results": {
    "settings": { "status": "pass", "time": 0.02 },
    "crypt": { "status": "pass", "time": 0.15 },
    "transport": { "status": "fail", "error": "Connection refused", "time": 2.01 },
    "cache": { "status": "pass", "time": 0.03 },
    "data": { "status": "pass", "time": 0.08 }
  },
  "summary": {
    "passed": 4,
    "failed": 1,
    "level": "connections"
  }
}
```

### Exit Codes

- `0` — all checks passed
- `1` — one or more checks failed

## Behavior

- **No early exit**: Always runs all checks at the selected level so you see the full picture.
- **No daemonization**: No PID files, no process loop, no signal trapping.
- **Always shuts down**: Calls shutdown for any subsystem that was successfully started.
- **Per-subsystem isolation**: Each subsystem is wrapped in begin/rescue so one failure doesn't prevent checking the rest.
- **Dependent ordering**: Some subsystems depend on prior ones (e.g., extensions need transport). If a dependency failed, dependent checks are skipped and marked as such.

## Implementation

### File: `lib/legion/cli/check_command.rb`

A standalone module `Legion::CLI::Check` with a class method `run(formatter, options)`.

### Subsystem check order

1. **settings** — `Legion::Settings.load` from config directory
2. **crypt** — `Legion::Crypt.start` (key generation, optional Vault connect)
3. **transport** — `Legion::Transport::Connection.setup` (RabbitMQ connect)
4. **cache** — `require 'legion/cache'` (Redis/Memcached connect)
5. **data** — `Legion::Data.setup` (DB connect + migrations)
6. **extensions** (if `--extensions` or `--full`) — `Legion::Extensions.hook_extensions`
7. **api** (if `--full`) — Start API server thread, verify it's listening

### Shutdown

After all checks complete, shut down in reverse order. Only shut down subsystems that were successfully started.

### Registration in CLI

```ruby
desc 'check', 'Verify Legion can start successfully'
option :extensions, type: :boolean, default: false, desc: 'Also load extensions'
option :full, type: :boolean, default: false, desc: 'Full boot cycle (extensions + API)'
def check
  Legion::CLI::Check.run(formatter, options)
end
```

### Dependencies on existing code

- Reuses `Legion::Service` initialization logic (require + setup calls) but does NOT instantiate `Legion::Service` directly, since Service does everything in `initialize` with no granular control.
- Instead, reproduces the setup steps individually with rescue per step, similar to how `Legion::CLI::Connection` works for the lazy CLI connections.
- Uses `Legion::Readiness` to track and report state.

## Not in Scope

- Health checks against running Legion instances (that's `legion status`)
- Network reachability tests (ping, DNS)
- Configuration validation without connecting (that's `legion config validate`)
