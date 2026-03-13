# Legion MCP Server Design

**Date**: 2026-03-13
**Status**: Approved
**Author**: Matthew Iverson (@Esity)

## Overview

Add an MCP (Model Context Protocol) server to LegionIO core, alongside the existing Sinatra HTTP API. This allows AI agents (Claude Code, Cursor, etc.) to interact with Legion — creating tasks, managing chains, querying extensions — via the standard MCP protocol.

## Architecture

The MCP server lives in `lib/legion/mcp/` as a core control-plane interface, the same tier as `lib/legion/api/`. Both call into the same internal layer: `Legion::Ingress.run`, `Legion::Data::Model::*`, `Legion::Extensions`, etc.

```
lib/legion/
├── api.rb              # Sinatra HTTP API (existing)
├── api/                # API route modules (existing)
├── mcp.rb              # MCP server setup + tool/resource registration
├── mcp/
│   ├── server.rb       # MCP::Server factory + configuration
│   ├── tools/          # MCP::Tool subclasses
│   │   ├── run_task.rb
│   │   ├── describe_runner.rb
│   │   ├── list_tasks.rb
│   │   ├── get_task.rb
│   │   ├── delete_task.rb
│   │   ├── get_task_logs.rb
│   │   ├── list_chains.rb
│   │   ├── create_chain.rb
│   │   ├── update_chain.rb
│   │   ├── delete_chain.rb
│   │   ├── list_relationships.rb
│   │   ├── create_relationship.rb
│   │   ├── update_relationship.rb
│   │   ├── delete_relationship.rb
│   │   ├── list_extensions.rb
│   │   ├── get_extension.rb
│   │   ├── enable_extension.rb
│   │   ├── disable_extension.rb
│   │   ├── list_schedules.rb
│   │   ├── create_schedule.rb
│   │   ├── update_schedule.rb
│   │   ├── delete_schedule.rb
│   │   ├── get_status.rb
│   │   └── get_config.rb
│   └── resources/
│       ├── runner_catalog.rb
│       └── extension_info.rb
└── cli/
    └── mcp_command.rb  # `legion mcp` CLI subcommand
```

## Dependency

```ruby
# legionio.gemspec
spec.add_dependency 'mcp', '~> 0.8'
```

Only new dependency. `mcp` gem depends on `json-schema >= 4.1`.

## Transport

### stdio (local dev)

```bash
legion mcp  # starts stdio MCP server
```

Claude Code config:
```json
{
  "mcpServers": {
    "legion": {
      "command": "legion",
      "args": ["mcp"]
    }
  }
}
```

### Streamable HTTP (production/remote)

```bash
legion mcp --http --port 9393  # standalone streamable HTTP
```

Or mounted alongside the Sinatra API when `legion start` runs (future enhancement).

## Tools

### Agentic (higher-level)

| Tool | Description | Input |
|------|-------------|-------|
| `legion.run_task` | Execute task via dot notation | `{task: "http.request.get", params: {url: "..."}}` |
| `legion.describe_runner` | Get runner functions + schemas | `{runner: "http.request"}` |

### CRUD (1:1 with API)

**Tasks**: `legion.list_tasks`, `legion.get_task`, `legion.delete_task`, `legion.get_task_logs`
**Chains**: `legion.list_chains`, `legion.create_chain`, `legion.update_chain`, `legion.delete_chain`
**Relationships**: `legion.list_relationships`, `legion.create_relationship`, `legion.update_relationship`, `legion.delete_relationship`
**Extensions**: `legion.list_extensions`, `legion.get_extension`, `legion.enable_extension`, `legion.disable_extension`
**Schedules**: `legion.list_schedules`, `legion.create_schedule`, `legion.update_schedule`, `legion.delete_schedule`
**System**: `legion.get_status`, `legion.get_config`

All tools use `legion.` prefix for namespace clarity in multi-server MCP setups.

## Resources

| Resource | URI | Description |
|----------|-----|-------------|
| Runner Catalog | `legion://runners` | All extension.runner.function paths |
| Extension Info | `legion://extensions/{name}` | Extension metadata, runners, actors |

Resources are read-only context that agents can pull into their conversation.

## Implementation Notes

- Each tool is an `MCP::Tool` subclass with `description`, `input_schema`, and `self.call`
- Tools return `MCP::Tool::Response` with JSON text content
- `server_context` carries a reference to Legion internals (data connection status, etc.)
- Tools that need `legion-data` check `Legion::Settings[:data][:connected]` and return error responses (not exceptions)
- Tools that need `lex-scheduler` check `defined?(Legion::Extensions::Scheduler)`
- Sensitive values redacted in `get_config` (same logic as API)

## CLI Integration

New Thor subcommand at `lib/legion/cli/mcp_command.rb`:

```
legion mcp                    # stdio transport (default)
legion mcp --http             # streamable HTTP transport
legion mcp --http --port 9393 # custom port
```

Registered in `Legion::CLI::Main` alongside existing subcommands.

## Not Included (Future)

- **`lex-mcp` client extension** — Legion calling external MCP servers as tasks
- **Auth on MCP tools** — could layer in JWT later; stdio is inherently local/trusted
- **MCP Prompts** — pre-built prompts for common workflows
- **Mounting MCP HTTP transport inside Sinatra** — future `legion start` integration

## Spec Coverage

Each tool gets a unit spec in `spec/legion/mcp/tools/`. Server setup gets integration spec testing tool registration and stdio round-trip.
