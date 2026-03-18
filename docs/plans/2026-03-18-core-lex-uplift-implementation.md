# Core LEX Uplift Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix ~50 bugs, add standalone Clients, and achieve 90%+ spec coverage across 5 core extensions (lex-lex, lex-health, lex-node, lex-scheduler, lex-tasker).

**Architecture:** Each extension is uplifted independently in order of complexity (lex-lex -> lex-health -> lex-node -> lex-scheduler -> lex-tasker). Within each extension: fix bugs with TDD, clean up dead code, add missing specs, add Client where applicable, then run the pre-push pipeline (rspec -> rubocop -A -> rubocop -> version bump -> changelog -> push).

**Tech Stack:** Ruby >= 3.4, RSpec, Sequel ORM, RabbitMQ (AMQP), SQLite (in-memory for specs)

**Design Doc:** `docs/plans/2026-03-18-core-lex-uplift-design.md`

**Pre-push pipeline (MUST run after each extension):**
```bash
cd <extension-dir>
bundle exec rspec                          # ALL specs pass
bundle exec rubocop -A                     # auto-fix, then git add ALL modified files
bundle exec rubocop                        # zero offenses
# bump version in lib/**/version.rb
# update CHANGELOG.md
# update CLAUDE.md if it exists
git add <all changed files> && git commit
git push # pipeline-complete
```

**Reference extensions for quality bar:**
- `extensions-core/lex-conditioner/` — 0.3.0, 140 specs, 99% coverage, standalone Client
- `extensions-core/lex-transformer/` — 0.2.0, 86 specs, 96% coverage, standalone Client

---

## Part 1: lex-lex (0.2.1 -> 0.3.0)

Base path: `/Users/miverso2/rubymine/legion/extensions-core/lex-lex/`

### Task 1: Fix data_required? and entry point

The most critical bug: `data_required?` is an instance method, so the framework's `Core` mixin default of `false` wins. lex-lex silently skips database setup.

**Files:**
- Modify: `lib/legion/extensions/lex.rb`
- Test: `spec/legion/extensions/lex_spec.rb`

**Step 1: Write the failing test**

```ruby
# spec/legion/extensions/lex_spec.rb — add to existing describe block
RSpec.describe Legion::Extensions::Lex do
  it 'has a version number' do
    expect(described_class::VERSION).not_to be_nil
  end

  describe '.data_required?' do
    it 'returns true' do
      expect(described_class.data_required?).to be true
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `cd /Users/miverso2/rubymine/legion/extensions-core/lex-lex && bundle exec rspec spec/legion/extensions/lex_spec.rb -v`
Expected: FAIL — `data_required?` returns false (from Core mixin default)

**Step 3: Fix the entry point**

In `lib/legion/extensions/lex.rb`, change:
```ruby
# BEFORE (broken — instance method, Core's false wins):
def data_required?
  true
end

# AFTER (correct — module-level method override):
def self.data_required?
  true
end
```

**Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/legion/extensions/lex_spec.rb -v`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/legion/extensions/lex.rb spec/legion/extensions/lex_spec.rb
git commit -m "fix data_required? to be class method so framework respects it"
```

---

### Task 2: Fix sync runner bugs

Two bugs in `runners/sync.rb`: (1) `updated` counter incremented even when no DB write happens, (2) `active: true` forced on every sync, re-enabling intentionally disabled extensions.

**Files:**
- Modify: `lib/legion/extensions/lex/runners/sync.rb`
- Modify: `spec/legion/extensions/lex/runners/sync_spec.rb`

**Step 1: Write the failing tests**

```ruby
# Add to sync_spec.rb
describe '#sync' do
  context 'when extension exists with matching namespace' do
    before do
      Legion::Data::Model::Extension.insert(
        name: 'lex-http', namespace: 'Legion::Extensions::Http', active: true
      )
    end

    it 'does not increment updated count when namespace matches' do
      result = runner.sync
      expect(result[:updated]).to eq(0)
    end
  end

  context 'when extension was intentionally disabled' do
    before do
      Legion::Data::Model::Extension.insert(
        name: 'lex-http', namespace: 'Legion::Extensions::Http', active: false
      )
    end

    it 'does not re-enable disabled extensions' do
      runner.sync
      ext = Legion::Data::Model::Extension.where(name: 'lex-http').first
      expect(ext.values[:active]).to be false
    end
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/legion/extensions/lex/runners/sync_spec.rb -v`
Expected: FAIL — updated count is 1 (not 0), and active gets forced to true

**Step 3: Fix sync.rb**

In `lib/legion/extensions/lex/runners/sync.rb`, change the else branch:
```ruby
# BEFORE:
else
  ns = values[:extension_class].to_s
  existing.update(namespace: ns, active: true) if existing.values[:namespace] != ns
  updated += 1
end

# AFTER:
else
  ns = values[:extension_class].to_s
  if existing.values[:namespace] != ns
    existing.update(namespace: ns)
    updated += 1
  end
end
```

**Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/legion/extensions/lex/runners/sync_spec.rb -v`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/legion/extensions/lex/runners/sync.rb spec/legion/extensions/lex/runners/sync_spec.rb
git commit -m "fix sync: only count actual updates, respect disabled extensions"
```

---

### Task 3: Fix register.rb nil guard and variable shadowing

`Register.save` has no guard if `extension_id` is nil after `Extension.create` failure. Also fix `update` variable shadowing in Extension, Runner, Function modules.

**Files:**
- Modify: `lib/legion/extensions/lex/runners/register.rb`
- Modify: `lib/legion/extensions/lex/runners/extension.rb`
- Modify: `lib/legion/extensions/lex/runners/runner.rb`
- Modify: `lib/legion/extensions/lex/runners/function.rb`
- Modify: `spec/legion/extensions/lex/runners/register_spec.rb`

**Step 1: Write the failing test**

```ruby
# Add to register_spec.rb
context 'when extension creation fails' do
  before do
    allow(Extension).to receive(:create).and_return({ success: false })
  end

  it 'returns failure without crashing' do
    result = Register.save(opts: { runners: { 'MyRunner' => { functions: {} } } },
                           extension_name: 'lex-broken',
                           extension_class: 'Legion::Extensions::Broken')
    expect(result[:success]).to be false
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/legion/extensions/lex/runners/register_spec.rb -v`
Expected: FAIL — NoMethodError or nil propagation

**Step 3: Fix register.rb**

In `lib/legion/extensions/lex/runners/register.rb`, after `Extension.create`:
```ruby
if extension_id.nil?
  ext_result = Extension.create(name: opts[:extension_name] || extension_name,
                                 namespace: opts[:extension_class] || extension_class)
  extension_id = ext_result[:extension_id]
  return { success: false, error: 'extension creation failed' } if extension_id.nil?
end
```

In `extension.rb`, `runner.rb`, `function.rb` — rename local `update = {}` to `changes = {}`:
```ruby
# BEFORE:
update = {}
# ... update[column] = ...
# ... record.update(update) ...

# AFTER:
changes = {}
# ... changes[column] = ...
# ... record.update(changes) ...
```

**Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/legion/extensions/lex/runners/register_spec.rb -v`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/legion/extensions/lex/runners/register.rb \
        lib/legion/extensions/lex/runners/extension.rb \
        lib/legion/extensions/lex/runners/runner.rb \
        lib/legion/extensions/lex/runners/function.rb \
        spec/legion/extensions/lex/runners/register_spec.rb
git commit -m "fix register nil guard, rename shadowed update vars to changes"
```

---

### Task 4: Add missing spec coverage for lex-lex

Fill the test gaps: actor spec, Extension.get(namespace:), Function.build_args edge cases, Function.update name-drop behavior.

**Files:**
- Create: `spec/legion/extensions/lex/actors/sync_spec.rb`
- Modify: `spec/legion/extensions/lex/runners/extension_spec.rb`
- Modify: `spec/legion/extensions/lex/runners/function_spec.rb`

**Step 1: Write the actor spec**

```ruby
# spec/legion/extensions/lex/actors/sync_spec.rb
require 'spec_helper'

RSpec.describe Legion::Extensions::Lex::Actor::Sync do
  subject(:actor_class) { described_class }

  it 'sets runner_class to Sync' do
    expect(actor_class.instance_method(:runner_class).bind_call(actor_class.allocate))
      .to eq(Legion::Extensions::Lex::Runners::Sync)
  end

  it 'sets runner_function to sync' do
    expect(actor_class.instance_method(:runner_function).bind_call(actor_class.allocate))
      .to eq('sync')
  end

  it 'disables subtask checking' do
    expect(actor_class.instance_method(:check_subtask?).bind_call(actor_class.allocate))
      .to be false
  end

  it 'disables task generation' do
    expect(actor_class.instance_method(:generate_task?).bind_call(actor_class.allocate))
      .to be false
  end

  it 'uses the runner' do
    expect(actor_class.instance_method(:use_runner?).bind_call(actor_class.allocate))
      .to be true
  end
end
```

Load the actor file in spec_helper or at top of spec:
```ruby
require 'legion/extensions/lex/actors/sync'
```

**Step 2: Write extension get-by-namespace test**

```ruby
# Add to extension_spec.rb
describe '.get' do
  context 'with namespace' do
    before { Extension.create(name: 'lex-http', namespace: 'Legion::Extensions::Http') }

    it 'finds by namespace' do
      result = Extension.get(namespace: 'Legion::Extensions::Http')
      expect(result[:name]).to eq('lex-http')
    end
  end
end
```

**Step 3: Write function edge case tests**

```ruby
# Add to function_spec.rb
describe '.build_args' do
  it 'handles parameters with nil name' do
    result = Function.build_args(raw_args: [[:rest]])
    expect(result[:success]).to be true
  end
end

describe '.update' do
  it 'silently ignores name in changes' do
    Function.create(runner_id: 1, name: 'original')
    func = Function.where(name: 'original').first
    result = Function.update(function_id: func.values[:id], name: 'renamed', active: false)
    expect(result[:success]).to be true
    updated = Function[func.values[:id]]
    expect(updated.values[:name]).to eq('original')
    expect(updated.values[:active]).to be false
  end
end
```

**Step 4: Run all specs**

Run: `bundle exec rspec -v`
Expected: All pass, coverage should be ~85-90%+

**Step 5: Commit**

```bash
git add spec/
git commit -m "add actor spec and missing coverage for extension, function edge cases"
```

---

### Task 5: lex-lex pipeline and release

**Files:**
- Modify: `lib/legion/extensions/lex/version.rb` (0.2.1 -> 0.3.0)
- Modify: `CHANGELOG.md`

**Step 1: Run full spec suite**

Run: `bundle exec rspec`
Expected: All pass

**Step 2: Run rubocop auto-fix**

Run: `bundle exec rubocop -A`
Then: `git add` ALL files rubocop modified

**Step 3: Run rubocop verify**

Run: `bundle exec rubocop`
Expected: 0 offenses

**Step 4: Bump version**

```ruby
# lib/legion/extensions/lex/version.rb
VERSION = '0.3.0'
```

**Step 5: Update CHANGELOG**

```markdown
## [0.3.0] - 2026-03-18

### Fixed
- `data_required?` now correctly overrides Core default (was instance method, framework ignored it)
- Sync runner only increments update counter on actual DB writes
- Sync runner no longer re-enables intentionally disabled extensions
- Register.save guards against nil extension_id after creation failure

### Changed
- Renamed shadowed `update` local variables to `changes` in Extension, Runner, Function modules
```

**Step 6: Commit and push**

```bash
git add -A
git commit -m "release lex-lex 0.3.0: fix data_required?, sync bugs, add spec coverage"
git push # pipeline-complete
```

---

## Part 2: lex-health (0.1.8 -> 0.2.0)

Base path: `/Users/miverso2/rubymine/legion/extensions-core/lex-health/`

### Task 6: Fix health runner boolean and require bugs

Three bugs: `active: 1` instead of `true`, missing `require 'time'`, and nil guard on `updated` timestamp.

**Files:**
- Modify: `lib/legion/extensions/health/runners/health.rb`
- Modify: `spec/legion/extensions/health/runners/health_spec.rb`

**Step 1: Write failing tests**

```ruby
# Add to health_spec.rb
describe '#update' do
  context 'with a new node' do
    it 'sets active as boolean true, not integer' do
      result = runner.update(status: 'online', hostname: 'new-node')
      expect(result[:active]).to be true
    end
  end

  context 'with existing node that has nil updated timestamp' do
    before do
      DB[:nodes].insert(name: 'stale-node', active: true, status: 'unknown',
                        created: Time.now - 3600, updated: nil)
    end

    it 'updates without crashing on nil timestamp' do
      result = runner.update(status: 'online', hostname: 'stale-node', timestamp: Time.now.to_s)
      expect(result[:success]).to be true
    end
  end

  context 'with an existing node' do
    before do
      DB[:nodes].insert(name: 'existing-node', active: true, status: 'online',
                        created: Time.now - 3600, updated: Time.now - 60)
    end

    it 'updates the existing node' do
      result = runner.update(status: 'degraded', hostname: 'existing-node')
      expect(result[:success]).to be true
      expect(result[:status]).to eq('degraded')
    end
  end
end

describe '#delete' do
  it 'deletes an existing node' do
    id = DB[:nodes].insert(name: 'doomed', active: true, status: 'online', created: Time.now)
    result = runner.delete(node_id: id)
    expect(result[:success]).to be true
  end

  it 'returns failure for nonexistent node' do
    result = runner.delete(node_id: 99999)
    expect(result[:success]).to be false
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `cd /Users/miverso2/rubymine/legion/extensions-core/lex-health && bundle exec rspec spec/legion/extensions/health/runners/health_spec.rb -v`
Expected: Multiple failures

**Step 3: Fix health.rb**

At the top of the file, add:
```ruby
require 'time'
```

In `update` method, fix the timestamp guard:
```ruby
# BEFORE:
if opts.key?(:timestamp) && !item.values[:updated].nil? && item.values[:updated] > Time.parse(opts[:timestamp])

# AFTER:
if opts.key?(:timestamp) && item.values[:updated] && item.values[:updated] > Time.parse(opts[:timestamp])
```

In `update` method, fix boolean:
```ruby
# BEFORE:
update_hash = { active: 1, status: opts[:status], ...

# AFTER:
update_hash = { active: true, status: opts[:status], ...
```

In `insert` method, fix boolean:
```ruby
# BEFORE:
insert = { active: 1, status: status, name: hostname }

# AFTER:
insert = { active: true, status: status, name: hostname }
```

Remove the `insert[:active] = opts[:active] if opts.key? :active` line (a heartbeat should always mean active).

Fix `delete` method with nil guard:
```ruby
def delete(node_id:, **)
  node = Legion::Data::Model::Node[node_id]
  return { success: false, error: 'node not found' } if node.nil?

  node.delete
  { success: true, node_id: node_id }
end
```

**Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/legion/extensions/health/runners/health_spec.rb -v`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/legion/extensions/health/runners/health.rb spec/legion/extensions/health/runners/health_spec.rb
git commit -m "fix boolean type, require time, nil guards, delete safety in health runner"
```

---

### Task 7: Fix watchdog routing and worker cleanup

Two bugs: message routing key mismatch, and `mark_workers_offline` doesn't clear `health_node`.

**Files:**
- Modify: `lib/legion/extensions/health/transport/messages/watchdog.rb`
- Modify: `lib/legion/extensions/health/runners/watchdog.rb`
- Modify: `spec/legion/extensions/health/runners/watchdog_spec.rb`

**Step 1: Write failing tests**

```ruby
# Add to watchdog_spec.rb
describe '#expire' do
  context 'with workers attached to expired nodes' do
    before do
      node_id = DB[:nodes].insert(name: 'dead-node', active: true, status: 'online',
                                   created: Time.now - 3600, updated: Time.now - 3600)
      DB[:digital_workers].insert(worker_id: 'w-001', worker_name: 'test-worker',
                                   health_status: 'online', health_node: 'dead-node',
                                   status: 'active', risk_tier: 'low')
    end

    it 'clears health_node on expired workers' do
      runner.expire(expire_time: 60)
      worker = DB[:digital_workers].where(worker_id: 'w-001').first
      expect(worker[:health_node]).to be_nil
      expect(worker[:health_status]).to eq('offline')
    end
  end
end
```

For the message routing key, create a new spec:
```ruby
# Create: spec/legion/extensions/health/transport/messages/watchdog_spec.rb
require 'spec_helper'
# stub transport base classes before requiring message
unless defined?(Legion::Transport::Message)
  module Legion; module Transport; class Message
    def self.routing_key(val = nil); @rk = val; end
    def self.type(val = nil); @type = val; end
  end; end; end
end
require 'legion/extensions/health/transport/messages/watchdog'

RSpec.describe Legion::Extensions::Health::Transport::Messages::Watchdog do
  it 'has routing_key matching the queue binding' do
    msg = described_class.allocate
    expect(msg.routing_key).to eq('node.health')
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bundle exec rspec -v`
Expected: FAIL

**Step 3: Fix watchdog message routing key**

In `transport/messages/watchdog.rb`:
```ruby
# BEFORE:
routing_key 'health'

# AFTER:
routing_key 'node.health'
```

Fix `mark_workers_offline` in `runners/watchdog.rb`:
```ruby
# BEFORE:
worker.update(health_status: 'offline')

# AFTER:
worker.update(health_status: 'offline', health_node: nil)
```

**Step 4: Run tests to verify they pass**

Run: `bundle exec rspec -v`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/legion/extensions/health/transport/messages/watchdog.rb \
        lib/legion/extensions/health/runners/watchdog.rb \
        spec/
git commit -m "fix watchdog routing key and clear health_node on worker expiry"
```

---

### Task 8: Fix TOCTOU race and entry point cleanup

Fix concurrent insert race condition and remove duplicate `data_required?` instance method.

**Files:**
- Modify: `lib/legion/extensions/health/runners/health.rb`
- Modify: `lib/legion/extensions/health.rb`
- Modify: `spec/legion/extensions/health/runners/health_spec.rb`
- Modify: `spec/spec_helper.rb` (fix `create_table` -> `create_table?`)

**Step 1: Write the failing test**

```ruby
# Add to health_spec.rb
describe '#update' do
  context 'when concurrent insert race occurs' do
    it 'handles unique constraint violation gracefully' do
      # Insert the node out-of-band to simulate race
      DB[:nodes].insert(name: 'race-node', active: true, status: 'online', created: Time.now)
      # Now call update which will try to insert (since it doesn't see the record in its lookup)
      allow(Legion::Data::Model::Node).to receive(:where).and_return(
        double(first: nil) # Simulate not finding the record
      )
      # The insert will hit the unique constraint
      result = runner.update(status: 'online', hostname: 'race-node')
      expect(result[:success]).to be true
    end
  end
end
```

**Step 2: Fix health.rb insert to handle constraint violation**

In `runners/health.rb`, wrap the insert:
```ruby
def insert(hostname:, status: 'unknown', **)
  insert = { active: true, status: status, name: hostname }
  insert[:created] = Sequel::CURRENT_TIMESTAMP

  node_id = Legion::Data::Model::Node.insert(insert)
  { success: true, hostname: hostname, node_id: node_id, **insert }
rescue Sequel::UniqueConstraintViolation
  # Lost the race — another process inserted first, fall through to update path
  item = Legion::Data::Model::Node.where(name: hostname).first
  return { success: false, error: 'node vanished after race' } unless item

  item.update(active: true, status: status, updated: Sequel::CURRENT_TIMESTAMP)
  { success: true, hostname: hostname, node_id: item.values[:id], status: status }
end
```

Fix the entry point:
```ruby
# lib/legion/extensions/health.rb — remove the instance method, keep only:
def self.data_required?
  true
end
```

Fix spec ordering in `spec/spec_helper.rb` and `spec/legion/extensions/health/runners/health_spec.rb`:
```ruby
# Change all create_table to create_table? for idempotent creation
DB.create_table?(:nodes) do ...
DB.create_table?(:digital_workers) do ...
```

**Step 3: Run tests**

Run: `bundle exec rspec -v`
Expected: PASS

**Step 4: Commit**

```bash
git add lib/legion/extensions/health/runners/health.rb \
        lib/legion/extensions/health.rb \
        spec/
git commit -m "handle TOCTOU race on insert, fix entry point data_required?"
```

---

### Task 9: lex-health pipeline and release

**Files:**
- Modify: `lib/legion/extensions/health/version.rb` (0.1.8 -> 0.2.0)
- Modify: `CHANGELOG.md`

**Step 1:** Run `bundle exec rspec` — all pass
**Step 2:** Run `bundle exec rubocop -A` — stage all modified
**Step 3:** Run `bundle exec rubocop` — 0 offenses
**Step 4:** Bump version to `0.2.0`
**Step 5:** Update CHANGELOG:

```markdown
## [0.2.0] - 2026-03-18

### Fixed
- `active` column now uses boolean `true` instead of integer `1` (PostgreSQL compatibility)
- Watchdog message routing key changed from `'health'` to `'node.health'` to match queue binding
- Added `require 'time'` for `Time.parse`
- Nil guard on `updated` timestamp in back-in-time comparison
- TOCTOU race condition on concurrent heartbeat inserts (rescue UniqueConstraintViolation)
- `delete` method nil guard for nonexistent nodes
- `mark_workers_offline` now clears `health_node` on expired workers

### Changed
- Entry point `data_required?` is now `self.` (class method) matching framework expectation
- Removed dead `runner_function` from Watchdog actor
```

**Step 6:** Commit and push:
```bash
git add -A && git commit -m "release lex-health 0.2.0: fix boolean, routing, race condition, nil guards"
git push # pipeline-complete
```

---

## Part 3: lex-node (0.2.3 -> 0.3.0)

Base path: `/Users/miverso2/rubymine/legion/extensions-core/lex-node/`

### Task 10: Delete data_test/ and Runners::Crypt, consolidate into Node

Delete broken migrations and dead crypt runner. Merge the 3-4 useful methods into Runners::Node.

**Files:**
- Delete: `data_test/` directory (all 4 migrations)
- Delete: `lib/legion/extensions/node/runners/crypt.rb`
- Modify: `lib/legion/extensions/node/runners/node.rb`
- Modify: `spec/legion/extensions/node/runners/node_spec.rb`

**Step 1: Read both runner files to identify methods to merge**

Read `runners/crypt.rb` and `runners/node.rb`. The useful methods from Crypt to keep in Node:
- `push_public_key` (fix Base64 encoding)
- `request_cluster_secret` (fix namespace)
- `push_cluster_secret`
- `receive_cluster_secret` (use the Crypt version which stores validation_string)

Remove from Node: the duplicate `push_public_key`, `push_cluster_secret`, `receive_cluster_secret` that have divergent/broken behavior.

**Step 2: Write tests for consolidated methods**

```ruby
# Add to node_spec.rb
describe '#push_public_key' do
  it 'publishes a PublicKey message with Base64-encoded key' do
    allow(Legion::Crypt).to receive(:public_key).and_return('raw-key-bytes')
    msg_double = double(publish: true)
    allow(Legion::Extensions::Node::Transport::Messages::PublicKey)
      .to receive(:new).and_return(msg_double)

    runner.push_public_key
    expect(Legion::Extensions::Node::Transport::Messages::PublicKey)
      .to have_received(:new).with(hash_including(public_key: Base64.encode64('raw-key-bytes')))
  end
end

describe '#request_cluster_secret' do
  it 'publishes using the correct namespace' do
    msg_double = double(publish: true)
    allow(Legion::Extensions::Node::Transport::Messages::RequestClusterSecret)
      .to receive(:new).and_return(msg_double)

    runner.request_cluster_secret
    expect(Legion::Extensions::Node::Transport::Messages::RequestClusterSecret)
      .to have_received(:new)
  end
end

describe '#receive_cluster_secret' do
  it 'stores encrypted_string and validation_string' do
    runner.receive_cluster_secret(
      message: 'test', encrypted_string: 'enc123', validation_string: 'val456'
    )
    expect(Legion::Settings[:crypt][:cluster_secret][:encrypted_string]).to eq('enc123')
    expect(Legion::Settings[:crypt][:cluster_secret][:validation_string]).to eq('val456')
  end
end
```

**Step 3: Consolidate runners/node.rb**

Move the correct implementations from crypt.rb into node.rb. Fix:
- `def self.update_public_key` -> `def update_public_key` (remove `self.`)
- `Base64.encode64(Legion::Crypt.public_key)` (consistent encoding)
- `Legion::Extensions::Node::Transport::Messages::RequestClusterSecret` (correct namespace)
- Add `require 'base64'` at top

**Step 4: Delete files**

```bash
rm -rf data_test/
rm lib/legion/extensions/node/runners/crypt.rb
```

**Step 5: Run tests and commit**

Run: `bundle exec rspec -v`
Expected: PASS (some existing specs may need adjustment for removed crypt runner)

```bash
git add -A
git commit -m "consolidate Runners::Crypt into Runners::Node, delete broken data_test/"
```

---

### Task 11: Fix beat message and actor bugs

Fix `[:hostname]` vs `[:name]`, boot_time per-instance, string key in actor, require base64.

**Files:**
- Modify: `lib/legion/extensions/node/transport/messages/beat.rb`
- Modify: `lib/legion/extensions/node/actors/beat.rb`
- Modify: `lib/legion/extensions/node/runners/beat.rb`
- Modify: `spec/legion/extensions/node/transport/messages/beat_spec.rb`

**Step 1: Write failing tests**

```ruby
# beat message spec — add or fix:
describe '#message' do
  it 'uses :name not :hostname from settings' do
    msg = described_class.new
    expect(msg.message[:name]).to eq(Legion::Settings[:client][:name])
  end

  it 'reports meaningful uptime_seconds' do
    msg = described_class.new
    # boot_time should be from class constant, not per-instance
    expect(msg.message[:uptime_seconds]).to be >= 0
  end
end
```

**Step 2: Fix beat.rb message**

```ruby
# transport/messages/beat.rb
BOOT_TIME = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)

# In message method:
name: Legion::Settings[:client][:name],  # was :hostname

# In uptime_seconds:
def uptime_seconds
  (::Process.clock_gettime(::Process::CLOCK_MONOTONIC) - BOOT_TIME).round(2)
end
```

Fix runner:
```ruby
# runners/beat.rb
version: defined?(Legion::VERSION) ? Legion::VERSION : nil  # was Legion::VERSION || nil
```

Fix typo: `'sending hearbeat'` -> `'sending heartbeat'`

Fix actor:
```ruby
# actors/beat.rb
settings[:beat_interval]  # was settings['beat_interval']
```

Add `require 'base64'` to `runners/node.rb` (already done in Task 10, verify).

**Step 3: Run tests and commit**

```bash
bundle exec rspec -v
git add lib/legion/extensions/node/transport/messages/beat.rb \
        lib/legion/extensions/node/actors/beat.rb \
        lib/legion/extensions/node/runners/beat.rb \
        spec/
git commit -m "fix beat message: name key, boot_time constant, symbol settings key, typo"
```

---

### Task 12: Fix vault runners for multi-cluster compatibility

Update vault runners to handle both legacy single-cluster and new multi-cluster token paths per the `2026-03-18-config-import-vault-multicluster` design.

**Files:**
- Modify: `lib/legion/extensions/node/runners/vault.rb`
- Modify: `lib/legion/extensions/node/actors/vault_token_request.rb`
- Modify: `lib/legion/extensions/node/transport/messages/request_vault_token.rb`
- Modify: `spec/legion/extensions/node/runners/vault_spec.rb`

**Step 1: Write failing tests**

```ruby
# Add to vault_spec.rb
describe '#receive_vault_token' do
  context 'with multi-cluster vault' do
    before do
      Legion::Settings[:crypt][:vault][:clusters] = {
        prod: { address: 'vault.example.com', token: nil, connected: false }
      }
    end

    it 'stores token in the cluster entry' do
      runner.receive_vault_token(token: 'hvs.new', cluster_name: :prod)
      expect(Legion::Settings[:crypt][:vault][:clusters][:prod][:token]).to eq('hvs.new')
    end
  end

  context 'with legacy single-cluster' do
    before { Legion::Settings[:crypt][:vault][:clusters] = {} }

    it 'stores token in top-level vault settings' do
      runner.receive_vault_token(token: 'hvs.legacy')
      expect(Legion::Settings[:crypt][:vault][:token]).to eq('hvs.legacy')
    end
  end
end
```

**Step 2: Fix vault.rb**

```ruby
def receive_vault_token(token:, cluster_name: nil, **)
  return if Legion::Settings[:crypt][:vault][:connected]

  clusters = Legion::Settings[:crypt][:vault][:clusters] || {}
  if cluster_name && clusters[cluster_name.to_sym]
    clusters[cluster_name.to_sym][:token] = token
    clusters[cluster_name.to_sym][:connected] = true
  else
    Legion::Settings[:crypt][:vault][:token] = token
  end
  { success: true }
end
```

Fix `request_vault_token.rb` — add Base64 encoding:
```ruby
require 'base64'
# ...
public_key: Base64.encode64(Legion::Crypt.public_key)
```

Fix `vault_token_request.rb` actor — set `use_runner?` to `true`:
```ruby
def use_runner?
  true
end
```

**Step 3: Run tests and commit**

```bash
bundle exec rspec -v
git add lib/legion/extensions/node/runners/vault.rb \
        lib/legion/extensions/node/actors/vault_token_request.rb \
        lib/legion/extensions/node/transport/messages/request_vault_token.rb \
        spec/
git commit -m "update vault runners for multi-cluster compatibility, fix Base64 encoding"
```

---

### Task 13: Fix transport and cleanup

Fix transport.rb nil crash, exchange references, unused require, duplicate specs.

**Files:**
- Modify: `lib/legion/extensions/node/transport/transport.rb`
- Modify: `lib/legion/extensions/node/transport/queues/node.rb`
- Modify: `lib/legion/extensions/node/transport/messages/push_cluster_secret.rb`
- Delete: `spec/legion/extensions/node_spec.rb` (duplicate of version_spec.rb)

**Step 1: Fix transport.rb safe navigation**

```ruby
# BEFORE:
data_connected = Legion::Settings[:data][:connected]
cache_connected = Legion::Settings[:cache][:connected]

# AFTER:
data_connected = Legion::Settings[:data]&.[](:connected) || false
cache_connected = Legion::Settings[:cache]&.[](:connected) || false
```

**Step 2: Remove unused require in queues/node.rb**

```ruby
# Remove: require 'socket'
```

**Step 3: Remove || nil redundancies**

In `push_cluster_secret.rb`:
```ruby
# BEFORE:
@options[:validation_string] || nil

# AFTER:
@options[:validation_string]
```

**Step 4: Delete duplicate spec**

```bash
rm spec/legion/extensions/node_spec.rb
```

**Step 5: Run tests and commit**

```bash
bundle exec rspec -v
git add -A
git commit -m "fix transport nil crash, remove dead code and duplicate spec"
```

---

### Task 14: Add missing spec coverage for lex-node

Add specs for actors, messages, and transport bindings.

**Files:**
- Create: `spec/legion/extensions/node/actors/beat_spec.rb`
- Create: `spec/legion/extensions/node/actors/push_key_spec.rb`
- Create: `spec/legion/extensions/node/transport/messages/public_key_spec.rb`
- Create: `spec/legion/extensions/node/transport/messages/request_cluster_secret_spec.rb`

**Step 1: Write actor specs**

```ruby
# spec/legion/extensions/node/actors/beat_spec.rb
require 'spec_helper'
require 'legion/extensions/node/actors/beat'

RSpec.describe Legion::Extensions::Node::Actor::Beat do
  let(:actor) { described_class.allocate }

  it 'returns runner class' do
    expect(actor.runner_class).to eq(Legion::Extensions::Node::Runners::Beat)
  end

  it 'returns beat function' do
    expect(actor.runner_function).to eq('beat')
  end

  it 'uses symbol key for beat_interval' do
    allow(actor).to receive(:settings).and_return({ beat_interval: 30 })
    expect(actor.time).to eq(30)
  end
end
```

Write similar specs for PushKey, and message specs verifying routing_key, validate, and message body methods.

**Step 2: Run all specs**

Run: `bundle exec rspec -v`
Expected: PASS, coverage ~90%+

**Step 3: Commit**

```bash
git add spec/
git commit -m "add actor and message specs for lex-node"
```

---

### Task 15: lex-node pipeline and release

Same pattern as Tasks 5 and 9.

- Bump to `0.3.0`
- Update CHANGELOG, README, CLAUDE.md if present
- Full pipeline: rspec, rubocop -A, rubocop
- Commit and push

```markdown
## [0.3.0] - 2026-03-18

### Fixed
- `update_public_key` changed from class method to instance method (was unreachable by AMQP dispatch)
- `request_cluster_secret` now uses correct message namespace
- Beat message uses `[:name]` instead of `[:hostname]` for node identity
- Boot time tracked as class constant (uptime_seconds was always ~0)
- Added `require 'base64'` for Ruby 3.4+ compatibility
- Public key encoding standardized to Base64 across all messages
- Transport settings access uses safe navigation (nil crash prevention)
- Beat actor uses symbol key for `beat_interval` setting
- VaultTokenRequest actor now has `use_runner? true` (was dead wiring)

### Changed
- Consolidated Runners::Crypt into Runners::Node (deleted runners/crypt.rb)
- Deleted data_test/ directory (broken MySQL-only migrations, zero consumers)
- Vault runners support multi-cluster token storage (backward-compatible)

### Removed
- Duplicate push_public_key/receive_cluster_secret in Runners::Node (used Crypt versions)
```

---

## Part 4: lex-scheduler (0.2.0 -> 0.3.0)

Base path: `/Users/miverso2/rubymine/legion/extensions-core/lex-scheduler/`

### Task 16: Delete dead mode runners

Remove ModeScheduler, ModeTransition, EmergencyPromotion and their specs.

**Files:**
- Delete: `lib/legion/extensions/scheduler/runners/mode_scheduler.rb`
- Delete: `lib/legion/extensions/scheduler/runners/mode_transition.rb`
- Delete: `lib/legion/extensions/scheduler/runners/emergency_promotion.rb`
- Delete: `spec/legion/extensions/scheduler/runners/mode_scheduler_spec.rb`
- Delete: `spec/legion/extensions/scheduler/runners/mode_transition_spec.rb`
- Delete: `spec/legion/extensions/scheduler/runners/emergency_promotion_spec.rb`

**Step 1: Verify no other file requires these**

```bash
grep -r 'mode_scheduler\|mode_transition\|emergency_promotion\|ModeScheduler\|ModeTransition\|EmergencyPromotion' lib/ --include='*.rb'
```

Expected: Only the files being deleted reference these.

**Step 2: Delete the files**

```bash
rm lib/legion/extensions/scheduler/runners/mode_scheduler.rb
rm lib/legion/extensions/scheduler/runners/mode_transition.rb
rm lib/legion/extensions/scheduler/runners/emergency_promotion.rb
rm spec/legion/extensions/scheduler/runners/mode_scheduler_spec.rb
rm spec/legion/extensions/scheduler/runners/mode_transition_spec.rb
rm spec/legion/extensions/scheduler/runners/emergency_promotion_spec.rb
```

**Step 3: Run remaining specs**

Run: `bundle exec rspec -v`
Expected: PASS (remaining specs unaffected)

**Step 4: Commit**

```bash
git add -A
git commit -m "remove dead mode runners (no actor wiring, broken dependencies)"
```

---

### Task 17: Fix migrations and model naming

Rewrite MySQL-only migrations 001/002 as Sequel DSL, fix migration 005 column type, fix ScheduleLog model name.

**Files:**
- Modify: `lib/legion/extensions/scheduler/data/migrations/001_schedule_table.rb`
- Modify: `lib/legion/extensions/scheduler/data/migrations/002_schedule_log.rb`
- Modify: `lib/legion/extensions/scheduler/data/migrations/005_add_payload_column.rb`
- Modify: `lib/legion/extensions/scheduler/data/models/schedule_log.rb`

**Step 1: Rewrite migration 001**

```ruby
# 001_schedule_table.rb
Sequel.migration do
  change do
    create_table(:schedules) do
      primary_key :id
      foreign_key :function_id, :functions, null: true
      String :name, null: false
      Integer :interval, null: true
      String :cron, null: true, text: true
      TrueClass :active, default: true
      DateTime :last_run, null: true
      DateTime :created, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated, null: true
    end
  end
end
```

**Step 2: Rewrite migration 002**

```ruby
# 002_schedule_log.rb
Sequel.migration do
  change do
    create_table(:schedule_logs) do
      primary_key :id
      foreign_key :schedule_id, :schedules, null: true
      foreign_key :task_id, :tasks, null: true
      foreign_key :function_id, :functions, null: true
      TrueClass :success, null: true
      String :status, null: true
      DateTime :created, default: Sequel::CURRENT_TIMESTAMP
    end
  end
end
```

**Step 3: Fix migration 005**

```ruby
# BEFORE:
add_column :payload, File, null: false, default: '{}'

# AFTER:
add_column :payload, String, text: true, null: true, default: '{}'
```

**Step 4: Fix model name**

In `data/models/schedule_log.rb`:
```ruby
# BEFORE:
class Schedule < Sequel::Model

# AFTER:
class ScheduleLog < Sequel::Model(:schedule_logs)
  many_to_one :schedule, class: '::Legion::Extensions::Scheduler::Data::Model::Schedule'
  many_to_one :task, class: '::Legion::Data::Model::Task'
  many_to_one :function, class: '::Legion::Data::Model::Function'
end
```

**Step 5: Run tests and commit**

```bash
bundle exec rspec -v
git add lib/legion/extensions/scheduler/data/
git commit -m "rewrite migrations as Sequel DSL, fix ScheduleLog model name"
```

---

### Task 18: Fix schedule runner bugs

Fix last_run nil crash, function nil crash, dead cron guard, missing ScheduleLog creation, queue TTL.

**Files:**
- Modify: `lib/legion/extensions/scheduler/runners/schedule.rb`
- Modify: `lib/legion/extensions/scheduler/transport/queues/schedule.rb`
- Modify: `lib/legion/extensions/scheduler/transport/messages/refresh.rb`
- Modify: `spec/legion/extensions/scheduler/runners/schedule_spec.rb`

**Step 1: Write failing tests**

```ruby
# Add to schedule_spec.rb
context 'when schedule has nil last_run' do
  let(:schedule_row) do
    double(values: { id: 1, function_id: 1, interval: 60, cron: nil,
                     last_run: nil, active: true, payload: nil, transformation: nil })
  end

  it 'dispatches the task without crashing' do
    allow(models_class::Schedule).to receive(:where).and_return(double(all: [schedule_row]))
    allow(function_model).to receive(:[]).and_return(function_record)
    expect { runner.schedule_tasks }.not_to raise_error
  end
end

context 'when function_id returns nil record' do
  let(:schedule_row) do
    double(values: { id: 2, function_id: 9999, interval: 60, cron: nil,
                     last_run: Time.now - 120, active: true, payload: nil, transformation: nil })
  end

  it 'skips the schedule without crashing' do
    allow(models_class::Schedule).to receive(:where).and_return(double(all: [schedule_row]))
    allow(function_model).to receive(:[]).with(9999).and_return(nil)
    expect { runner.schedule_tasks }.not_to raise_error
  end
end
```

**Step 2: Fix schedule.rb**

```ruby
# Fix nil last_run — treat as epoch (always due):
last_run = row.values[:last_run] || Time.at(0)

# For interval schedules:
next if (Time.now - last_run) < row.values[:interval]

# For cron schedules — remove dead guard, add nil check:
cron_class = Fugit.parse(row.values[:cron])
next unless cron_class # skip unparseable cron

if cron_class.respond_to? :previous_time
  # Remove dead guard: next if Time.now < Time.parse(cron_class.previous_time.to_s)
  prev = Time.parse(cron_class.previous_time.to_s)
  next if last_run > prev
end

# Fix function nil guard:
function = Legion::Data::Model::Function[row.values[:function_id]]
next unless function  # skip if function not found

# Add ScheduleLog creation after send_task:
models_class::ScheduleLog.insert(
  schedule_id: row.values[:id],
  function_id: row.values[:function_id],
  success: true,
  status: 'dispatched',
  created: Sequel::CURRENT_TIMESTAMP
)
```

Fix queue TTL:
```ruby
# transport/queues/schedule.rb
'x-message-ttl': 5000  # was 5 (milliseconds)
```

Delete dead `message_example` from `transport/messages/refresh.rb`.

**Step 3: Run tests and commit**

```bash
bundle exec rspec -v
git add lib/legion/extensions/scheduler/ spec/
git commit -m "fix nil crashes, remove dead cron guard, add ScheduleLog, fix queue TTL"
```

---

### Task 19: Add standalone Client and missing specs

**Files:**
- Create: `lib/legion/extensions/scheduler/client.rb`
- Create: `spec/legion/extensions/scheduler/client_spec.rb`
- Modify: `spec/` (additional coverage for models, messages, actors)

**Step 1: Write Client**

```ruby
# lib/legion/extensions/scheduler/client.rb
require_relative 'runners/schedule'

module Legion
  module Extensions
    module Scheduler
      class Client
        include Runners::Schedule

        def initialize(data_model: nil, fugit: nil)
          @data_model = data_model
          @fugit = fugit || require('fugit') && Fugit
        end

        def models_class
          @data_model || Legion::Data::Model
        end

        def log
          @log ||= defined?(Legion::Logging) ? Legion::Logging : Logger.new($stdout)
        end

        def settings
          { options: {} }
        end
      end
    end
  end
end
```

**Step 2: Write Client spec and additional coverage**

Test Client initialization, schedule_tasks delegation, model/message/actor specs.

**Step 3: Run all specs**

Run: `bundle exec rspec -v`
Expected: PASS, ~90%+ coverage

**Step 4: Commit**

```bash
git add lib/legion/extensions/scheduler/client.rb spec/
git commit -m "add standalone Client and missing spec coverage"
```

---

### Task 20: lex-scheduler pipeline and release

Bump to `0.3.0`. Full pipeline. CHANGELOG:

```markdown
## [0.3.0] - 2026-03-18

### Fixed
- Migrations 001/002 rewritten as Sequel DSL (cross-DB: SQLite, PostgreSQL, MySQL)
- Migration 005 column type `File` -> `String, text: true`
- ScheduleLog model class name (was defining duplicate `Schedule`)
- Queue TTL from 5ms to 5000ms (messages were expiring instantly)
- Nil guard on `last_run` (was TypeError on new schedules)
- Nil guard on function lookup (was NoMethodError on missing function)
- Removed dead cron guard (`Time.now < previous_time` was always false)
- ScheduleLog records now created after each dispatch

### Added
- Standalone `Scheduler::Client` for programmatic schedule management
- ScheduleLog model (was missing entirely)

### Removed
- ModeScheduler, ModeTransition, EmergencyPromotion runners (dead code, no actor wiring)
- Dead `message_example` in Refresh message (copy-paste from lex-node)
```

---

## Part 5: lex-tasker (0.2.3 -> 0.3.0)

Base path: `/Users/miverso2/rubymine/legion/extensions-core/lex-tasker/`

### Task 21: Fix extend/include and helper deduplication

The most critical structural bug: `extend` instead of `include` makes helpers unreachable on instances.

**Files:**
- Modify: `lib/legion/extensions/tasker/runners/check_subtask.rb`
- Modify: `lib/legion/extensions/tasker/runners/fetch_delayed.rb`
- Modify: `lib/legion/extensions/tasker/helpers/find_subtask.rb`
- Delete: `lib/legion/extensions/tasker/helpers/fetch_delayed.rb` (deduplicate into find_subtask.rb)
- Delete: `lib/legion/extensions/tasker/helpers/base.rb` (empty stub)
- Modify: `spec/legion/extensions/tasker/runners/check_subtask_spec.rb`

**Step 1: Deduplicate helpers**

Move `find_delayed` from `helpers/fetch_delayed.rb` into `helpers/find_subtask.rb` (since it already contains `find_trigger` and `find_subtasks`). Rename module to `Helpers::TaskFinder`. Delete `fetch_delayed.rb` and `base.rb`.

**Step 2: Fix extend -> include**

```ruby
# runners/check_subtask.rb
# BEFORE:
extend Legion::Extensions::Tasker::Helpers::FindSubtask

# AFTER:
include Legion::Extensions::Tasker::Helpers::TaskFinder
```

Same in `runners/fetch_delayed.rb`.

**Step 3: Convert all raw SQL to Sequel DSL**

Replace string interpolation in `find_trigger`:
```ruby
def find_trigger(function:, runner_class:, **)
  Legion::Data::Model::Function
    .join(:runners, id: :runner_id)
    .where(Sequel[:functions][:name] => function,
           Sequel[:runners][:namespace] => runner_class)
    .select(Sequel[:functions][:id].as(:function_id))
    .first
end
```

Similar for `find_subtasks` and `find_delayed` — replace CONCAT, backticks, and `legion.` prefix with Sequel joins and qualified identifiers.

**Step 4: Run tests and commit**

```bash
bundle exec rspec -v
git add -A
git commit -m "fix extend/include, deduplicate helpers, convert SQL to Sequel DSL"
```

---

### Task 22: Fix runner bugs in log, updater, task_manager

**Files:**
- Modify: `lib/legion/extensions/tasker/runners/log.rb`
- Modify: `lib/legion/extensions/tasker/runners/updater.rb`
- Modify: `lib/legion/extensions/tasker/runners/task_manager.rb`
- Modify specs for each

**Step 1: Fix log.rb (4 bugs)**

```ruby
# Line 14: payload[:node_id] -> opts[:node_id]
insert[:node_id] = opts[:node_id]

# Line 16: Node.where(opts[:name]) -> Node.where(name: opts[:name])
node = Legion::Data::Model::Node.where(name: opts[:name]).first

# Line 17: runner.values.nil? -> runner.nil?
insert[:function_id] = runner.functions_dataset.where(name: function).first.values[:id] unless runner.nil?

# Line 47: TaskLog.all.delete -> TaskLog.dataset.delete
def delete_all(**_opts)
  count = Legion::Data::Model::TaskLog.dataset.delete
  { success: true, deleted: count }
end
```

**Step 2: Fix updater.rb (2 bugs)**

```ruby
# Add return on early exit:
return { success: true, changed: false, task_id: task_id } if update_hash.none?

# Remove debug artifact:
# DELETE: log.unknown task.class
```

**Step 3: Fix task_manager.rb (2 bugs)**

```ruby
# Fix Sequel immutable chain:
dataset = dataset.where(status: status) unless ['*', nil, ''].include?(status)

# Fix MySQL-only SQL:
.where(Sequel.lit('created <= ?', Time.now - (age * 86_400)))
```

**Step 4: Write tests for all fixed paths**

```ruby
# log_spec.rb additions:
it 'uses opts[:node_id] not payload[:node_id]' do ...
it 'finds node by name hash syntax' do ...
it 'handles nil runner gracefully' do ...
it 'deletes all task logs via dataset' do ...

# updater_spec.rb additions:
it 'returns early without calling update when no changes' do ...

# task_manager_spec.rb additions:
it 'applies status filter to purge_old' do ...
it 'uses cross-DB time comparison' do ...
```

**Step 5: Run tests and commit**

```bash
bundle exec rspec -v
git add -A
git commit -m "fix log, updater, task_manager: nil guards, SQL, early return, debug removal"
```

---

### Task 23: Fix check_subtask runner bugs

**Files:**
- Modify: `lib/legion/extensions/tasker/runners/check_subtask.rb`
- Modify: `spec/legion/extensions/tasker/runners/check_subtask_spec.rb`

**Step 1: Write failing tests**

```ruby
describe '#build_task_hash' do
  it 'handles nil delay without crashing' do
    relationship = { delay: nil, function_id: 1 }
    result = runner.build_task_hash(relationship, {})
    expect(result[:status]).to eq('conditioner.queued')
  end
end

describe '#check_subtasks' do
  it 'returns early when find_trigger returns nil' do
    allow(runner).to receive(:find_trigger).and_return(nil)
    result = runner.check_subtasks(function: 'test', runner_class: 'Test')
    expect(result).to eq({ success: true, subtasks: 0 })
  end
end

describe '#dispatch_task' do
  it 'does not mutate the cached relationship hash' do
    original = { delay: 0, function_id: 1 }
    frozen_copy = original.dup.freeze
    allow(runner).to receive(:find_subtasks).and_return([frozen_copy])
    allow(runner).to receive(:send_task)
    expect { runner.dispatch_task(opts: {}) }.not_to raise_error
  end
end
```

**Step 2: Fix check_subtask.rb**

```ruby
# Nil delay guard:
task_hash[:status] = relationship[:delay].to_i.zero? ? 'conditioner.queued' : 'task.delayed'

# Cache mutation fix:
task_hash = relationship.dup

# Nil guard after find_trigger:
trigger = find_trigger(function: opts[:function], runner_class: opts[:runner_class])
return { success: true, subtasks: 0 } unless trigger

# Fix result/results fan-out:
results_value = opts[:result] || opts[:results]
if results_value.is_a?(Array)
  results_value.each { |r| send_task(results: r, **task_hash) }
else
  send_task(results: resolve_results(opts), **task_hash)
end
```

Remove commented-out `Legion::Runner::Status` line.

Remove `check_subtask? true` / `generate_task? true` from `actors/task_manager.rb`.

**Step 3: Run tests and commit**

```bash
bundle exec rspec -v
git add -A
git commit -m "fix check_subtask: nil delay, cache mutation, nil trigger, fan-out"
```

---

### Task 24: Fix fetch_delayed and queue TTL

**Files:**
- Modify: `lib/legion/extensions/tasker/runners/fetch_delayed.rb`
- Modify: `lib/legion/extensions/tasker/transport/queues/fetch_delayed.rb`

**Step 1: Fix fetch_delayed SELECT to include task_delay**

In `helpers/task_finder.rb` (the deduplicated helper from Task 21), update `find_delayed` SQL/Sequel query to include `task_delay` in the SELECT list.

**Step 2: Fix queue TTL**

```ruby
# transport/queues/fetch_delayed.rb
'x-message-ttl': 1000  # was 1 (millisecond)
```

**Step 3: Implement or delete expire_queued**

In `runners/task_manager.rb`, either implement `expire_queued` properly or delete it. Recommended: implement minimally:

```ruby
def expire_queued(age: 1, limit: 10, **)
  cutoff = Time.now - (age * 3600)
  dataset = Legion::Data::Model::Task
            .where(status: ['conditioner.queued', 'transformer.queued', 'task.queued'])
            .where(Sequel.lit('created <= ?', cutoff))
            .limit(limit)
  count = dataset.update(status: 'task.expired')
  { success: true, expired: count }
end
```

**Step 4: Run tests and commit**

```bash
bundle exec rspec -v
git add -A
git commit -m "fix fetch_delayed SELECT, queue TTL, implement expire_queued"
```

---

### Task 25: Add standalone Client and missing specs

**Files:**
- Create: `lib/legion/extensions/tasker/client.rb`
- Create: `spec/legion/extensions/tasker/client_spec.rb`
- Add actor specs, transport specs

**Step 1: Write Client**

```ruby
# lib/legion/extensions/tasker/client.rb
module Legion
  module Extensions
    module Tasker
      class Client
        include Helpers::TaskFinder

        def initialize(data_model: nil)
          @data_model = data_model
        end

        def models_class
          @data_model || Legion::Data::Model
        end
      end
    end
  end
end
```

**Step 2: Write Client spec**

```ruby
RSpec.describe Legion::Extensions::Tasker::Client do
  let(:client) { described_class.new(data_model: test_model) }

  it 'finds triggers via TaskFinder' do
    expect(client).to respond_to(:find_trigger)
  end

  it 'finds subtasks via TaskFinder' do
    expect(client).to respond_to(:find_subtasks)
  end
end
```

**Step 3: Add actor specs for CheckSubtask, FetchDelayedPush, Log, TaskManager**

**Step 4: Run all specs**

Run: `bundle exec rspec -v`
Expected: PASS, coverage ~90%+

**Step 5: Commit**

```bash
git add -A
git commit -m "add standalone Client and missing spec coverage"
```

---

### Task 26: lex-tasker pipeline and release

Bump to `0.3.0`. Full pipeline. CHANGELOG:

```markdown
## [0.3.0] - 2026-03-18

### Fixed
- `extend` -> `include` for helper modules (instance methods were unreachable)
- SQL injection risk: string interpolation replaced with Sequel DSL parameterized queries
- Cross-DB: backtick quoting, `legion.` prefix, `CONCAT()` replaced with Sequel joins
- `runners/log.rb`: `payload[:node_id]` -> `opts[:node_id]` (NameError)
- `runners/log.rb`: `Node.where(opts[:name])` -> `Node.where(name: opts[:name])`
- `runners/log.rb`: `runner.values.nil?` -> `runner.nil?`
- `runners/log.rb`: `TaskLog.all.delete` -> `TaskLog.dataset.delete`
- `runners/updater.rb`: added missing `return` on early exit
- `runners/task_manager.rb`: Sequel chain reassignment for status filter
- `runners/task_manager.rb`: MySQL `DATE_SUB` -> `Sequel.lit` with Ruby Time
- `runners/check_subtask.rb`: nil delay guard (`.to_i.zero?`)
- `runners/check_subtask.rb`: cache mutation via `relationship.dup`
- `runners/check_subtask.rb`: nil guard after `find_trigger`
- `runners/check_subtask.rb`: result/results fan-out asymmetry
- `fetch_delayed` queue TTL from 1ms to 1000ms
- `find_delayed` SELECT now includes `task_delay` column

### Added
- Standalone `Tasker::Client` for programmatic subtask dispatch
- `expire_queued` implementation (was a no-op stub)
- Shared `Helpers::TaskFinder` module (deduplicated from find_subtask + fetch_delayed)

### Removed
- `helpers/base.rb` (empty stub, never included)
- `helpers/fetch_delayed.rb` (merged into TaskFinder)
- Debug artifact `log.unknown task.class` in updater
- Commented-out `Legion::Runner::Status` reference
- `check_subtask?`/`generate_task?` flags on TaskManager actor
```

---

## Execution Summary

| Part | Extension | Tasks | Version |
|------|-----------|-------|---------|
| 1 | lex-lex | 1-5 | 0.2.1 -> 0.3.0 |
| 2 | lex-health | 6-9 | 0.1.8 -> 0.2.0 |
| 3 | lex-node | 10-15 | 0.2.3 -> 0.3.0 |
| 4 | lex-scheduler | 16-20 | 0.2.0 -> 0.3.0 |
| 5 | lex-tasker | 21-26 | 0.2.3 -> 0.3.0 |

**Total: 26 tasks across 5 extensions.**

Each Part ends with a pipeline task (rspec, rubocop, version bump, changelog, push). Extensions are independent — no cross-extension dependencies except lex-node's awareness of the multi-cluster vault design.
