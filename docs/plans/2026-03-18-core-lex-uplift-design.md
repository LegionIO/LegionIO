# Core LEX Uplift Design

## Problem / Motivation

The 5 core operational extensions (lex-tasker, lex-scheduler, lex-node, lex-health, lex-lex) have accumulated bugs, dead code, MySQL-only SQL, and low spec coverage since their initial implementation. A bottom-up audit found **~50 bugs** across the 5 extensions, including:

- **Critical runtime crashes**: NameError, NoMethodError, TypeError on common code paths
- **SQL injection risk**: string interpolation in raw SQL queries
- **Cross-DB failures**: MySQL-only DDL and query syntax that breaks on PostgreSQL/SQLite
- **Dead code**: entire runner modules with no actor wiring, unreachable class methods
- **Architecture gaps**: missing subscription actors, broken model definitions, incorrect Sequel patterns

Meanwhile, lex-conditioner (0.3.0, 140 specs, 99% coverage) and lex-transformer (0.2.0, 86 specs, 96% coverage) demonstrate the quality bar these extensions should meet: standalone Clients where useful, high spec coverage, cross-DB compatibility, and clean code.

## Goal

Uplift all 5 core extensions to conditioner/transformer quality parity:
- Fix all identified bugs
- Add standalone Clients where useful (lex-tasker, lex-scheduler)
- Achieve 90%+ spec coverage
- Clean up dead code, duplicate helpers, broken migrations
- Ensure cross-DB compatibility (SQLite, PostgreSQL, MySQL)

## Approach

**Option B (chosen): Full uplift to conditioner/transformer parity** — bug fixes + standalone Clients + 90%+ spec coverage + cleanup for all 5 extensions. This was chosen over Option A (bugs-only) because many bugs are intertwined with structural issues that require cleanup to fix properly.

## Design Decisions

1. **lex-scheduler mode runners (ModeScheduler, ModeTransition, EmergencyPromotion)**: **Remove**. Dead code with no actor wiring, broken dependencies (Legion::Events doesn't exist), implicit undeclared dependency chains. YAGNI — if HA scheduling is needed later, it would be redesigned against the current architecture.

2. **lex-node Runners::Crypt**: **Consolidate into Runners::Node**. The split was premature — no separate actor wiring exists. Merge the 2-3 working methods, delete the rest. Also delete `data_test/` directory (4 broken migrations, zero consumers).

3. **Standalone Clients**: **lex-tasker and lex-scheduler only**. The other three (lex-health, lex-lex, lex-node) are infrastructure plumbing — no use case for calling them outside the message bus.

4. **Multi-cluster Vault compatibility (lex-node)**: Per the `2026-03-18-config-import-vault-multicluster` design, `Legion::Crypt` now supports multi-cluster Vault. lex-node's vault runners must handle both legacy single-cluster and new multi-cluster token storage paths.

---

## Extension 1: lex-tasker (0.2.3 -> 0.3.0)

### Bug Fixes (15 items)

| # | File | Bug | Fix |
|---|------|-----|-----|
| 1 | `runners/check_subtask.rb` | `extend FindSubtask` — instance calls unreachable | `include FindSubtask` |
| 2 | `runners/fetch_delayed.rb` | `extend FetchDelayed` — same issue | `include FetchDelayed` |
| 3 | `runners/log.rb:14` | `payload[:node_id]` — NameError | `opts[:node_id]` |
| 4 | `runners/log.rb:16` | `Node.where(opts[:name])` — bare string | `Node.where(name: opts[:name])` |
| 5 | `runners/log.rb:17` | `runner.values.nil?` — NoMethodError when runner nil | `runner.nil?` |
| 6 | `runners/log.rb:47` | `TaskLog.all.delete` — Array#delete no-op | `TaskLog.dataset.delete` |
| 7 | `runners/task_manager.rb:13` | `dataset.where(status:)` result discarded | Reassign `dataset =` |
| 8 | `runners/task_manager.rb:11` | MySQL `DATE_SUB(SYSDATE(), ...)` | `Sequel.lit('created <= ?', Time.now - (age * 86_400))` |
| 9 | `runners/updater.rb` | Missing `return` on early exit | Add `return` before `update_hash.none?` |
| 10 | `runners/updater.rb:14` | `log.unknown task.class` debug artifact | Remove |
| 11 | `runners/check_subtask.rb` | `relationship[:delay].zero?` nil crash | `relationship[:delay].to_i.zero?` |
| 12 | `runners/check_subtask.rb` | `task_hash = relationship` cache mutation | `task_hash = relationship.dup` |
| 13 | `runners/check_subtask.rb` | `opts[:result]` vs `opts[:results]` fan-out asymmetry | Check both keys |
| 14 | `helpers/*` | SQL string interpolation (injection risk) | `Sequel.lit('... = ?', value)` |
| 15 | `helpers/*` | Backtick quoting, `legion.` prefix, `CONCAT()` | Sequel DSL |

### Cleanup

- Delete `helpers/base.rb` (empty stub, never included)
- Deduplicate `find_trigger`/`find_subtasks` into single shared helper module
- Remove commented-out `Legion::Runner::Status` reference
- Remove duplicate `data_required?` instance method from entry point
- Implement `expire_queued` or delete it (total no-op stub)
- Fix `fetch_delayed` queue TTL from 1ms to 1000ms
- Fix `task[:task_delay]` missing from SELECT in `find_delayed`
- Remove `check_subtask? true` / `generate_task? true` from TaskManager actor

### Standalone Client

`Legion::Extensions::Tasker::Client.new` wraps `check_subtasks`, `find_trigger`, `find_subtasks` for programmatic use outside AMQP. Accepts `data_model:` injection for testing.

### Spec Coverage Target

75 existing -> ~140+ specs, target 90%+

New specs needed:
- Runners: `check_subtasks`, `dispatch_task`, `send_task`, `insert_task`, `purge_old`, `expire_queued`, `add_log` (all branches), `update_status` (empty hash path)
- Helpers: `find_trigger`, `find_subtasks`, `find_delayed` with cross-DB stubs
- Actors: all 3 actors
- Client suite
- Edge cases: nil delay, nil function, nil runner, cache mutation

---

## Extension 2: lex-scheduler (0.2.0 -> 0.3.0)

### Bug Fixes (10 items)

| # | File | Bug | Fix |
|---|------|-----|-----|
| 1 | `migrations/001` + `002` | Raw MySQL DDL | Rewrite as Sequel DSL |
| 2 | `migrations/005` | Column type `File` | `String, text: true` |
| 3 | `data/models/schedule_log.rb` | Defines `class Schedule` (wrong name) | `class ScheduleLog` |
| 4 | `transport/queues/schedule.rb` | `x-message-ttl: 5` (5ms) | `5000` (5s) |
| 5 | `runners/schedule.rb` | `last_run` nil crash | Nil guard, default to epoch |
| 6 | `runners/schedule.rb` | `function` nil crash | Nil guard on lookup |
| 7 | `runners/schedule.rb` | Dead cron guard `Time.now < previous_time` | Remove (always false) |
| 8 | `messages/send_task.rb` | `function.values[:name]` nil crash | Nil guard on chain |
| 9 | `messages/refresh.rb` | Dead `message_example` from lex-node | Delete method |
| 10 | `runners/schedule.rb` | ScheduleLog never written | Add creation after dispatch |

### Removal

- Delete `runners/mode_scheduler.rb`, `runners/mode_transition.rb`, `runners/emergency_promotion.rb`
- Delete associated specs
- Dead code: no actor wiring, `Legion::Events` doesn't exist, implicit undeclared dependency chain

### Cleanup

- Remove duplicate `data_required?` instance method
- Remove unused `payload` local var in `send_task` no-transform path
- Remove duplicate `scheduler_spec.rb`

### Standalone Client

`Legion::Extensions::Scheduler::Client.new` wraps `schedule_tasks` (list due schedules), `send_task` (dispatch one). Constructor accepts `fugit:` override for testing cron parsing.

### Spec Coverage Target

39 existing -> ~100+ specs, target 90%+

New specs: cron happy-path dispatch, `last_run: nil`, nil function, bad cron string, interval schedules, Schedule/ScheduleLog model CRUD, message validation/routing, actors, Client suite, cross-DB migration verification.

---

## Extension 3: lex-node (0.2.3 -> 0.3.0)

### Bug Fixes (11 items)

| # | File | Bug | Fix |
|---|------|-----|-----|
| 1 | `runners/crypt.rb:17` | `def self.update_public_key` — class method unreachable | Remove `self.` |
| 2 | `runners/crypt.rb:38` | Wrong namespace `Legion::Transport::Messages::RequestClusterSecret` | Use extension's own namespace |
| 3 | `messages/beat.rb` | `[:hostname]` vs `[:name]` | Use `[:name]` |
| 4 | `messages/beat.rb` | `@boot_time` per-instance (uptime always ~0) | Class-level `BOOT_TIME` constant |
| 5 | `messages/request_vault_token.rb` | Public key sent raw (not Base64) | `Base64.encode64()` |
| 6 | `runners/node.rb:63` | `public_key.to_s` gives PEM format | `Base64.encode64(...)` |
| 7 | `transport/transport.rb` | `Settings[:data][:connected]` nil crash | Safe navigation `&.[]` |
| 8 | `runners/beat.rb:13` | `Legion::VERSION \|\| nil` doesn't guard | `defined?` check |
| 9 | `actors/beat.rb` | `settings['beat_interval']` string key | `settings[:beat_interval]` |
| 10 | 3 files | Missing `require 'base64'` | Add require |
| 11 | `runners/beat.rb` | "hearbeat" typo | Fix |

### Consolidation

- Merge useful methods from `Runners::Crypt` into `Runners::Node`: `push_public_key`, `request_cluster_secret`, `push_cluster_secret`, `receive_cluster_secret`
- Delete `runners/crypt.rb` entirely
- Delete `data_test/` directory (4 broken migrations, zero consumers)
- Deduplicate divergent implementations

### Multi-Cluster Vault Compatibility

Per the `2026-03-18-config-import-vault-multicluster` design:
- `Runners::Vault#receive_vault_token` — if `clusters.any?`, store token in cluster entry
- `Runners::Vault#push_vault_token` — iterate `connected_clusters` when multi-cluster active
- `Runners::Vault#request_token` — check `connected_clusters` in addition to legacy path
- Fix `actors/vault_token_request.rb` — set `use_runner? true`

### Cleanup

- Delete unused `require 'socket'` in queues/node.rb
- Remove `|| nil` redundancies
- Remove duplicate node_spec.rb
- Fix exchange references to use extension's own exchange class
- Update README and gemspec

### Spec Coverage Target

61 existing -> ~120+ specs, target 90%+

New specs: all consolidated Node methods, vault runners (single + multi-cluster), all 5 actors, all 8 message classes, transport bindings, edge cases.

---

## Extension 4: lex-health (0.1.8 -> 0.2.0)

### Bug Fixes (7 items)

| # | File | Bug | Fix |
|---|------|-----|-----|
| 1 | `runners/health.rb:27,39` | `active: 1` (integer) on TrueClass column | `active: true` |
| 2 | `messages/watchdog.rb` | Routing key `'health'` doesn't match queue `node.health` | `'node.health'` |
| 3 | `runners/health.rb` | Missing `require 'time'` | Add require |
| 4 | `runners/health.rb:19` | Nil `updated` before time comparison | Nil guard |
| 5 | `runners/health.rb:47` | TOCTOU race on concurrent insert | `insert_conflict` or rescue |
| 6 | `runners/health.rb` | `delete(node_id:)` no nil guard | `Node[node_id]&.delete` |
| 7 | `runners/watchdog.rb` | `mark_workers_offline` doesn't clear `health_node` | Add `health_node: nil` |

### Cleanup

- Remove duplicate `data_required?` instance method
- Remove dead `runner_function` from Watchdog actor
- Fix spec ordering: `create_table` -> `create_table?`
- Normalize `respond_to?(:log)` -> `respond_to?(:log, true)`

### Spec Coverage Target

21 existing -> ~70+ specs, target 90%+

New specs: `update` (existing node path), `insert` (all kwargs), `delete` (found + not found), timestamp guard, watchdog `expire` variants, `mark_workers_offline` clears `health_node`, actors, message validation/routing, concurrent insert race, PostgreSQL boolean.

---

## Extension 5: lex-lex (0.2.1 -> 0.3.0)

### Bug Fixes (4 items)

| # | File | Bug | Fix |
|---|------|-----|-----|
| 1 | `lex.rb` | `def data_required?` instance method (Core's `false` wins) | `def self.data_required?` |
| 2 | `runners/sync.rb` | `updated` counter incremented even when no write | Only increment on actual DB write |
| 3 | `runners/sync.rb` | `active: true` forced on every sync | Respect existing `active` value |
| 4 | `runners/register.rb` | No nil guard on `extension_id` after soft failure | Add guard |

### Cleanup

- Fix `sync.rb` to reconcile runners and functions (not just extensions)
- Remove `update` variable shadowing in Extension, Runner modules
- No standalone Client (infrastructure sink)

### Spec Coverage Target

55 existing -> ~90+ specs, target 90%+

New specs: entry point `data_required?`, Sync actor, Extension.get(namespace:), Function.build_args nil-name edge case, Function.update drops name silently, Sync with matching namespace, Register.save mid-loop failure, runner/function reconciliation.

---

## Cross-Cutting Concerns

- All entry points: remove duplicate `data_required?` instance methods
- All raw SQL: convert to Sequel DSL or `Sequel.lit` with parameterized placeholders
- All migrations: rewrite MySQL-only DDL as Sequel `create_table` blocks
- All specs: fix load-order fragility with `create_table?` (idempotent)
- Version bumps: tasker 0.3.0, scheduler 0.3.0, node 0.3.0, health 0.2.0, lex 0.3.0

## Execution Order

Recommended: **lex-lex first** (simplest, fewest dependencies), then **lex-health**, then **lex-node** (needs multi-cluster vault awareness), then **lex-scheduler**, then **lex-tasker** (most complex, most bugs).

## Not Included

- New features beyond what exists (no new runners, no new actor types)
- lex-node HA mode scheduling (removed, YAGNI)
- lex-scheduler mode transitions (removed, YAGNI)
- Runtime dependency declarations in gemspecs (these extensions run inside the LegionIO bundle)
- Subscription actor for lex-lex Register.save (requires framework-level wiring discussion)
