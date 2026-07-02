<h1 align="center">LegionIO</h1>

<p align="center">
  <b>A modular Ruby framework for async jobs and AI infrastructure.</b><br>
  Start with a task engine that runs on zero infrastructure. Add LLM routing with
  measured context curation, an MCP server, RBAC, a knowledge store, or an experimental
  cognitive layer. Each is an independent gem. All of it is open source. Nothing is gated.
</p>

<p align="center">
  <a href="https://rubygems.org/gems/legionio"><img alt="Gem Version" src="https://img.shields.io/gem/v/legionio.svg"></a>
  <img alt="Ruby" src="https://img.shields.io/badge/ruby-%3E%3D%203.4-CC342D.svg">
  <img alt="License" src="https://img.shields.io/badge/license-Apache--2.0-blue.svg">
</p>

```bash
gem install legionio
LEGION_MODE=lite legion start   # no RabbitMQ, no Redis, no database required
```

## What this is

LegionIO is a distributed async job engine (RabbitMQ-backed, in the Sidekiq/Celery
family) that chains tasks into dependency graphs, plus a set of optional layers that
install as separate gems:

| Layer | Gem | What it adds | Requires |
|-------|-----|--------------|----------|
| Task engine | [legionio](https://github.com/LegionIO/LegionIO) | Task chains, scheduling, 8 actor types, CLI, REST API | nothing (lite mode) |
| LLM gateway | [legion-llm](https://github.com/LegionIO/legion-llm) | Any-client-to-any-provider routing, tiered escalation, mid-stream failover, context curation | usable standalone |
| MCP server | [legion-mcp](https://github.com/LegionIO/legion-mcp) | Exposes tasks and extensions as MCP tools (stdio or HTTP) | legion-llm |
| Knowledge store | [legion-apollo](https://github.com/LegionIO/legion-apollo) | RAG retrieval, embeddings, confidence-decayed knowledge | activated by lex-apollo / lex-knowledge |
| Access control | [legion-rbac](https://github.com/LegionIO/legion-rbac) | Vault-style flat policies | usable standalone |
| Cognitive layer | [legion-gaia](https://github.com/LegionIO/legion-gaia) | Experimental: tick-cycle scheduling over agentic extensions | see "The experimental part" below |

The composition rules are simple and enforced by gemspecs, not documentation: every
layer is optional, dependencies between layers are declared where they exist
(legion-mcp depends on legion-llm; Apollo does little until a lex-* extension activates
it), and installing a core gem you don't use adds a contract, not overhead. You can run
the LLM gateway without the task engine, the task engine without any AI, or the whole
stack together.

There are no paid tiers, no enterprise editions, and no feature gates. RBAC, the audit
ledger, identity integration, and every operational control ship in the open-source
gems, because there is no commercial version for them to be held back for.

## The part most worth your skepticism budget: legion-llm

legion-llm is a proxy/gateway between AI clients and model backends, in the same
category as LiteLLM or OpenRouter, with one addition neither has: automatic context
curation for long agent sessions.

**Routing.** Every model is classified into a tier:
[`local(0) → direct(1) → fleet(2) → cloud(3) → frontier(4)`](https://github.com/LegionIO/legion-llm/blob/main/lib/legion/llm/router.rb).
Requests try the cheapest capable tier first and escalate on failure or capability
mismatch. A [health tracker](https://github.com/LegionIO/legion-llm/blob/main/lib/legion/llm/router/health_tracker.rb)
(300s window, 3 failures trips the circuit, 60s cooldown) keys availability per
provider instance, and a provider dying mid-stream fails over and continues the stream
rather than erroring the client.

**Curation.** After each turn (async, off the request path), the
[Curator](https://github.com/LegionIO/legion-llm/blob/main/lib/legion/llm/context/curator.rb)
shrinks accumulated history with six deterministic strategies: `strip_thinking`,
`distill_tool_result`, `fold_resolved_exchanges`, `evict_superseded`, `dedup_similar`,
and `drop_and_archive` (overflow goes to the knowledge store, not the trash).

**Measured, including where it does nothing.** Production ledger aggregates, all
requests, by conversation length:

| Turns | 1 | 2–3 | 4–5 | 6–9 | 10–19 | 20–49 | 50+ |
|-------|---|-----|-----|-----|-------|-------|-----|
| Reduction vs. naive full-history resend | -0.1% | 9.6% | 13.3% | 23.6% | 54.3% | 72.8% | **97.7%** |

Single-turn workloads gain nothing; long agent sessions go from an average 1.13M
naive tokens per turn to ~26K. The asymmetry is the point: curation doesn't make cheap
traffic cheaper, it bounds the runaway sessions where cost concentrates. Methodology,
baseline definition, raw numbers, and caveats:
[curation-production-metrics.md](https://github.com/LegionIO/legion-llm/blob/main/docs/curation-production-metrics.md).

Nine provider adapters exist today (Anthropic, OpenAI, Bedrock, Gemini, Vertex,
Azure Foundry, Ollama, vLLM, MLX), each its own gem built on the
[lex-llm](https://github.com/LegionIO/lex-llm) contract layer. lex-llm defines what a
provider is; legion-llm decides where traffic goes. Install only the adapters you use.

## The job engine

The original core, in production since before any of the AI layers existed:

- Task chains with conditions and transformations:
  `Task A → [condition] → Task B → [transform] → Task C`, with parallel fan-out.
- Eight actor types (subscription, poll, every, once, loop, singleton, nothing,
  absorber_dispatch) — see
  [lib/legion/extensions/actors/](https://github.com/LegionIO/LegionIO/tree/main/lib/legion/extensions/actors).
- Distributed cron scheduling with interval locking.
- A JSONL disk spool that buffers messages through AMQP outages.
- Scale by starting more processes; RabbitMQ distributes the work.

`LEGION_MODE=lite` swaps RabbitMQ for in-process pub/sub and Redis for an in-memory
cache. Every feature works; nothing external is required. This is the recommended way
to evaluate the framework, and it takes about five minutes.

## The experimental part, labeled as such

The `lex-agentic-*` gems are a research layer: 16 gems containing 369 actor and runner
modules that model cognition-inspired behaviors on top of the job engine. The honest
mechanical description is that each is a scheduled job or subscription that adjusts
persistent state. The interesting research idea is what that state does: task-routing
connections strengthen when chains succeed and
[decay](https://github.com/LegionIO/lex-synapse) when unused, so frequently-successful
paths get cheaper to select. A
[16-phase tick cycle](https://github.com/LegionIO/lex-tick/blob/main/lib/legion/extensions/tick/helpers/constants.rb)
schedules this work in budgeted modes (dormant 0.2s, sentinel 0.5s, full 5.0s), and a
10-phase idle-time cycle consolidates memory and feeds what it learns about your usage
back into RAG retrieval for the LLM layer.

Whether this framing earns its keep is an open question we're running in production to
answer. If you don't install these gems, none of this exists in your deployment.

## Interfaces

```bash
legion start                 # the engine
legion chat                  # agentic REPL with tools, memory, subagents
legion task run http.request.get url:https://example.com
legion mcp                   # MCP server over stdio or streamable HTTP
curl http://localhost:4567/api/v1/tasks   # REST API (OpenAPI 3.1 spec in legionio-spec)
```

Every CLI command supports `--json`. MCP tools are discovered at runtime from
installed extensions, so the tool list reflects what your deployment can actually do.

## Verify the claims yourself

Every number above is reproducible from public source. A few one-liners:

```bash
# tick and dream phase counts (16 and 10)
git clone https://github.com/LegionIO/lex-tick && \
  grep -A20 'PHASES = ' lex-tick/lib/legion/extensions/tick/helpers/constants.rb

# legion-llm test surface (269 spec files, ~3,050 examples)
git clone https://github.com/LegionIO/legion-llm && \
  find legion-llm/spec -name '*_spec.rb' | wc -l

# router tiers and circuit-breaker defaults
grep -n 'TIER_RANK\|failure_threshold' legion-llm/lib/legion/llm/router.rb \
  legion-llm/lib/legion/llm/router/health_tracker.rb
```

Engineering docs are public in each repo, including the
[router design doc](https://github.com/LegionIO/legion-llm/tree/main/docs/work/planning)
and the [debugging methodology](https://github.com/LegionIO/legion-llm/blob/main/docs/work/planning/nxn-debugging-method.md)
the routing layer is held to. They are the most accurate picture of how this project
is actually built.

## Project status, honestly

LegionIO is built primarily by one engineer, with a disciplined process: PR-based flow,
CI on every repo, RSpec and RuboCop green before merge, conventional commits. The
GitHub org dates to 2018 (the job engine's first life); the AI platform is a 2025–2026
rebuild, which is why most public repos are young. It runs production workloads daily.
It is early, it is small, and the code is real. Read the source before betting on it —
that's what it's there for.

LegionIO is also published through [Optum Open Source](https://github.com/Optum/LegionIO),
where it first shipped publicly; this org is the active development home, and updates are
periodically merged back upstream. The enterprise provenance is why a framework this young
ships RBAC, an audit ledger, and identity integration — a real production deployment
required them.

## Requirements

- Ruby >= 3.4
- Nothing else in lite mode. Full mode: RabbitMQ; optional PostgreSQL/MySQL/SQLite,
  Redis/Memcached, HashiCorp Vault.

## License

Core framework: [Apache-2.0](https://www.apache.org/licenses/LICENSE-2.0).
Extensions: [MIT](https://opensource.org/licenses/MIT).
