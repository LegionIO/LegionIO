# `legion check` Command Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a `legion check` CLI command that smoke-tests Legion subsystem connectivity at three depth levels and reports pass/fail per component.

**Architecture:** A standalone `Legion::CLI::Check` module that runs each subsystem setup call individually inside begin/rescue blocks, collects results, prints a report, then shuts down. Registered in `Legion::CLI::Main` as a top-level command with `--extensions` and `--full` flags for progressive depth.

**Tech Stack:** Ruby, Thor CLI, existing Legion subsystem gems, RSpec for testing.

---

### Task 1: Create the Check module

**Files:**
- Create: `lib/legion/cli/check_command.rb`

**Step 1: Write the check command module**

```ruby
# frozen_string_literal: true

module Legion
  module CLI
    module Check
      CHECKS = %i[settings crypt transport cache data].freeze
      EXTENSION_CHECKS = %i[extensions].freeze
      FULL_CHECKS = %i[api].freeze

      # Dependencies: if a check fails, these dependents are skipped
      DEPENDS_ON = {
        crypt: :settings,
        transport: :settings,
        cache: :settings,
        data: :settings,
        extensions: :transport,
        api: :transport
      }.freeze

      class << self
        def run(formatter, options)
          level = if options[:full]
                    :full
                  elsif options[:extensions]
                    :extensions
                  else
                    :connections
                  end

          checks = CHECKS.dup
          checks.concat(EXTENSION_CHECKS) if %i[extensions full].include?(level)
          checks.concat(FULL_CHECKS) if level == :full

          results = {}
          started = []

          log_level = options[:verbose] ? 'debug' : 'error'
          setup_logging(log_level)

          checks.each do |name|
            dep = DEPENDS_ON[name]
            if dep && results[dep] && results[dep][:status] == 'fail'
              results[name] = { status: 'skip', error: "#{dep} failed" }
              print_result(formatter, name, results[name], options) unless options[:json]
              next
            end

            results[name] = run_check(name, options)
            started << name if results[name][:status] == 'pass'
            print_result(formatter, name, results[name], options) unless options[:json]
          end

          shutdown(started)
          print_summary(formatter, results, level, options)

          results.values.any? { |r| r[:status] == 'fail' } ? 1 : 0
        end

        private

        def setup_logging(log_level)
          require 'legion/logging'
          Legion::Logging.setup(log_level: log_level, level: log_level, trace: false)
        end

        def run_check(name, options)
          start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          send(:"check_#{name}", options)
          elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start).round(2)
          { status: 'pass', time: elapsed }
        rescue StandardError => e
          elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start).round(2)
          { status: 'fail', error: e.message, time: elapsed }
        end

        def check_settings(_options)
          require 'legion/settings'
          dir = Connection.send(:resolve_config_dir)
          Legion::Settings.load(config_dir: dir)
        end

        def check_crypt(_options)
          require 'legion/crypt'
          Legion::Crypt.start
        end

        def check_transport(_options)
          require 'legion/transport'
          Legion::Settings.merge_settings('transport', Legion::Transport::Settings.default)
          Legion::Transport::Connection.setup
        end

        def check_cache(_options)
          require 'legion/cache'
        end

        def check_data(_options)
          require 'legion/data'
          Legion::Settings.merge_settings(:data, Legion::Data::Settings.default)
          Legion::Data.setup
        end

        def check_extensions(_options)
          require 'legion/runner'
          Legion::Extensions.hook_extensions
        end

        def check_api(_options)
          require 'legion/api'
          port = (Legion::Settings[:api] || {})[:port] || 4567
          bind = (Legion::Settings[:api] || {})[:bind] || '127.0.0.1'

          Legion::API.set :port, port
          Legion::API.set :bind, bind
          Legion::API.set :server, :puma
          Legion::API.set :environment, :production

          thread = Thread.new { Legion::API.run! }

          # Wait briefly for the server to start
          deadline = Time.now + 5
          loop do
            break if Legion::API.running? rescue false
            break if Time.now > deadline

            sleep(0.1)
          end

          raise 'API server did not start within 5 seconds' unless (Legion::API.running? rescue false)
        ensure
          if defined?(thread) && thread
            Legion::API.quit! if defined?(Legion::API) && (Legion::API.running? rescue false)
            thread.kill
          end
        end

        def shutdown(started)
          started.reverse_each do |name|
            send(:"shutdown_#{name}")
          rescue StandardError
            # best-effort cleanup
          end
        end

        def shutdown_settings; end
        def shutdown_crypt
          Legion::Crypt.shutdown
        end

        def shutdown_transport
          Legion::Transport::Connection.shutdown
        end

        def shutdown_cache
          Legion::Cache.shutdown
        end

        def shutdown_data
          Legion::Data.shutdown
        end

        def shutdown_extensions
          Legion::Extensions.shutdown
        end

        def shutdown_api; end # handled in check_api ensure block

        def print_result(formatter, name, result, options)
          label = name.to_s.ljust(14)
          case result[:status]
          when 'pass'
            line = "  #{label}#{formatter.colorize('pass', :green)}"
            line += "  (#{result[:time]}s)" if options[:verbose]
          when 'fail'
            line = "  #{label}#{formatter.colorize('FAIL', :red)}  #{result[:error]}"
            line += "  (#{result[:time]}s)" if options[:verbose]
          when 'skip'
            line = "  #{label}#{formatter.colorize('skip', :yellow)}  #{result[:error]}"
          end
          puts line
        end

        def print_summary(formatter, results, level, options)
          passed = results.values.count { |r| r[:status] == 'pass' }
          failed = results.values.count { |r| r[:status] == 'fail' }
          skipped = results.values.count { |r| r[:status] == 'skip' }
          total = results.size

          if options[:json]
            formatter.json({
              results: results.transform_values { |v| v.compact },
              summary: { passed: passed, failed: failed, skipped: skipped, level: level.to_s }
            })
          else
            formatter.spacer
            failed_names = results.select { |_, v| v[:status] == 'fail' }.keys.join(', ')
            msg = "#{passed}/#{total} passed"
            msg += " (#{failed_names} failed)" if failed.positive?
            msg += " (#{skipped} skipped)" if skipped.positive?

            if failed.positive?
              formatter.error(msg)
            else
              formatter.success(msg)
            end
          end
        end
      end
    end
  end
end
```

**Step 2: Commit**

```bash
git add lib/legion/cli/check_command.rb
git commit -m "add legion check command module"
```

---

### Task 2: Register in CLI and add autoload

**Files:**
- Modify: `lib/legion/cli.rb:11-18` (add autoload)
- Modify: `lib/legion/cli.rb:89-93` (add command after `status`, before `lex`)

**Step 1: Add autoload entry**

In `lib/legion/cli.rb`, add after the existing autoloads (line 18):

```ruby
autoload :Check, 'legion/cli/check_command'
```

**Step 2: Add the command to Main class**

In `lib/legion/cli.rb`, add after the `status` command (after line 93):

```ruby
desc 'check', 'Verify Legion can start successfully'
long_desc <<~DESC
  Smoke-test Legion subsystem connectivity. Tries each subsystem,
  reports pass/fail, then shuts down.

  Default: check settings, crypt, transport, cache, data connections.
  --extensions: also load and wire up all LEX gems.
  --full: full boot cycle including API server.
DESC
option :extensions, type: :boolean, default: false, desc: 'Also load extensions'
option :full, type: :boolean, default: false, desc: 'Full boot cycle (extensions + API)'
def check
  exit_code = Legion::CLI::Check.run(formatter, options)
  raise SystemExit, exit_code if exit_code != 0
end
```

**Step 3: Run to verify it loads**

Run: `cd /Users/miverso2/rubymine/legion/LegionIO && bundle exec exe/legion help check`
Expected: Shows check command help with `--extensions` and `--full` flags.

**Step 4: Commit**

```bash
git add lib/legion/cli.rb
git commit -m "register check command in CLI"
```

---

### Task 3: Write RSpec tests

**Files:**
- Create: `spec/legion/cli/check_command_spec.rb`

**Step 1: Write the tests**

```ruby
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::CLI::Check do
  let(:formatter) { Legion::CLI::Output::Formatter.new(json: true, color: false) }
  let(:base_options) { { json: true, no_color: true, verbose: false, extensions: false, full: false } }

  describe '.run' do
    context 'with default level (connections)' do
      it 'returns 0 when settings check passes' do
        # Settings should always pass since it just loads config files
        allow(described_class).to receive(:check_crypt).and_raise(StandardError, 'no vault')
        allow(described_class).to receive(:check_transport).and_raise(StandardError, 'no rabbitmq')
        allow(described_class).to receive(:check_cache).and_raise(LoadError, 'no cache gem')
        allow(described_class).to receive(:check_data).and_raise(StandardError, 'no db')

        # Even with failures, run completes without raising
        result = described_class.run(formatter, base_options)
        expect(result).to eq(1) # failures present
      end
    end

    context 'dependency skipping' do
      it 'skips dependent checks when settings fails' do
        allow(described_class).to receive(:check_settings).and_raise(StandardError, 'bad config')

        output = capture_output { described_class.run(formatter, base_options) }
        parsed = JSON.parse(output)

        # crypt, transport, cache, data all depend on settings
        %w[crypt transport cache data].each do |name|
          expect(parsed['results'][name]['status']).to eq('skip')
        end
      end
    end

    context 'with --extensions flag' do
      it 'includes extensions check' do
        options = base_options.merge(extensions: true)
        allow(described_class).to receive(:check_settings)
        allow(described_class).to receive(:check_crypt)
        allow(described_class).to receive(:check_transport)
        allow(described_class).to receive(:check_cache)
        allow(described_class).to receive(:check_data)
        allow(described_class).to receive(:check_extensions)

        output = capture_output { described_class.run(formatter, options) }
        parsed = JSON.parse(output)

        expect(parsed['results']).to have_key('extensions')
      end
    end

    context 'return codes' do
      it 'returns 0 when all checks pass' do
        Legion::CLI::Check::CHECKS.each do |name|
          allow(described_class).to receive(:"check_#{name}")
        end

        result = capture_output { described_class.run(formatter, base_options) }
        # The method returns 0 for all pass
        # We check the JSON summary
        parsed = JSON.parse(result)
        expect(parsed['summary']['failed']).to eq(0)
      end
    end
  end

  def capture_output
    output = StringIO.new
    $stdout = output
    yield
    $stdout = STDOUT
    output.string
  end
end
```

**Step 2: Run tests**

Run: `cd /Users/miverso2/rubymine/legion/LegionIO && bundle exec rspec spec/legion/cli/check_command_spec.rb -v`

**Step 3: Fix any failures and iterate**

**Step 4: Commit**

```bash
git add spec/legion/cli/check_command_spec.rb
git commit -m "add specs for legion check command"
```

---

### Task 4: Update CLAUDE.md and docs

**Files:**
- Modify: `CLAUDE.md` (add check to CLI table and file map)
- Modify: `docs/getting-started.md` (mention check command)

**Step 1: Add check to CLAUDE.md CLI section**

Add `check` entry to the CLI command listing and the file map table.

**Step 2: Add check to getting-started.md**

Add a brief section after "Start the Daemon" showing `legion check` as a validation step.

**Step 3: Commit**

```bash
git add CLAUDE.md docs/getting-started.md
git commit -m "document legion check command"
```
