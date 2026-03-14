# Cold Start Claude Memory Ingestion

**Date**: 2026-03-13
**Status**: Implemented

## Problem

Legion agents experience a cold start problem - they begin with zero knowledge. Claude Code, meanwhile, accumulates rich structured knowledge in MEMORY.md (auto-memory) and CLAUDE.md (project instructions) files. This knowledge maps naturally to Legion's trace type system.

## Solution

Add a Claude memory parser and ingestion runner to `lex-coldstart` that converts markdown sections into typed `lex-memory` traces, bridging Claude Code's knowledge accumulation into Legion's cognitive architecture.

## Architecture

```
~/.claude/projects/.../memory/MEMORY.md  ─┐
project/CLAUDE.md                         ─┤
project/**/CLAUDE.md                      ─┼─> ClaudeParser ─> trace candidates ─> lex-memory store
```

### Trace Type Mapping

| Source | Section Pattern | Trace Type | Rationale |
|--------|----------------|------------|-----------|
| MEMORY.md | Hard Rules | firmware | Never decays, foundational constraints |
| MEMORY.md | Architecture/Structure | semantic | System knowledge |
| MEMORY.md | Gotchas/Caveats | procedural | Operational knowledge |
| MEMORY.md | Identity Auth | identity | Identity modeling |
| CLAUDE.md | What is / Architecture | semantic | Domain knowledge |
| CLAUDE.md | Development / Conventions | procedural | How-to knowledge |
| Any | Fallback | semantic | Safe default |

### Granularity

Each markdown bullet point becomes one trace. This enables:
- Fine-grained Hebbian linking between related facts
- Individual decay/reinforcement per fact
- Domain-tag-based retrieval

### Components

1. **`Helpers::ClaudeParser`** - Pure markdown parser, no dependencies on lex-memory
2. **`Runners::Ingest`** - Orchestrates parsing + optional storage into lex-memory
3. **`CLI::Coldstart`** - `legion coldstart ingest <path>` command

### Integration

- During imprint window: traces get 3x reinforcement multiplier via `imprint_active: true`
- Firmware traces (from Hard Rules) never decay - they are permanent axioms
- Parser respects skip paths (_deprecated/, _ignored/, etc.)
- `--dry-run` / `preview` mode for inspection without storage

## CLI

```
legion coldstart ingest <file_or_dir>  [--dry-run] [--pattern GLOB] [--json]
legion coldstart preview <file_or_dir> [--json]
legion coldstart status                [--json]
```

## File Locations

- Parser: `lex-coldstart/lib/legion/extensions/coldstart/helpers/claude_parser.rb`
- Runner: `lex-coldstart/lib/legion/extensions/coldstart/runners/ingest.rb`
- CLI: `LegionIO/lib/legion/cli/coldstart_command.rb`
- Specs: `lex-coldstart/spec/legion/extensions/coldstart/helpers/claude_parser_spec.rb`
- Specs: `lex-coldstart/spec/legion/extensions/coldstart/runners/ingest_spec.rb`
