# Legion/LegionIO Binary Split Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Split the `legion` executable into two binaries: `legion` (interactive shell + dev workflow) and `legionio` (daemon + operational CLI). Auto-configure LLM providers from environment variables and Claude CLI config files, replacing credential prompts in onboarding with provider ping-testing.

**Architecture:** `exe/legion` routes bare invocation to `Legion::TTY::App.run`, args to a new `Legion::CLI::Interactive` Thor class with dev-workflow commands. `exe/legionio` always routes to the existing `Legion::CLI::Main`. The `legionio` gemspec adds `legion-tty` as a runtime dependency. LLM provider credentials auto-resolve from env vars (`AWS_BEARER_TOKEN_BEDROCK`, `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `CODEX_API_KEY`) and Claude CLI config files (`~/.claude/settings.json`, `~/.claude.json`). Onboarding replaces credential prompts with provider ping-testing.

**Tech Stack:** Ruby, Thor, legion-tty gem, legion-llm, legion-settings, existing Legion::CLI modules

---

### Task 1: Create `exe/legionio`

**Files:**
- Create: `exe/legionio`

**Step 1: Create the legionio executable**

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

RubyVM::YJIT.enable if defined?(RubyVM::YJIT)

ENV['RUBY_GC_HEAP_INIT_SLOTS']           ||= '600000'
ENV['RUBY_GC_HEAP_FREE_SLOTS_MIN_RATIO'] ||= '0.20'
ENV['RUBY_GC_HEAP_FREE_SLOTS_MAX_RATIO'] ||= '0.40'
ENV['RUBY_GC_MALLOC_LIMIT']              ||= '64000000'
ENV['RUBY_GC_MALLOC_LIMIT_MAX']          ||= '128000000'

require 'bootsnap'
Bootsnap.setup(
  cache_dir:          File.expand_path('~/.legionio/cache/bootsnap'),
  development_mode:   false,
  load_path_cache:    true,
  compile_cache_iseq: true,
  compile_cache_yaml: true
)

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

require 'legion/cli'
Legion::CLI::Main.start(ARGV)
```

**Step 2: Make it executable**

Run: `chmod +x exe/legionio`

**Step 3: Verify it works**

Run: `ruby -Ilib exe/legionio version`
Expected: Version output with legionio version number

**Step 4: Commit**

```bash
git add exe/legionio
git commit -m "add legionio executable for daemon and operational CLI"
```

---

### Task 2: Create `Legion::CLI::Interactive` Thor class

**Files:**
- Create: `lib/legion/cli/interactive.rb`

This is a small Thor class that only registers the dev-workflow subcommands. It shares the same autoloaded command classes as `Main`.

**Step 1: Create the Interactive class**

```ruby
# frozen_string_literal: true

require 'thor'
require 'legion/version'
require 'legion/cli/error'
require 'legion/cli/output'

module Legion
  module CLI
    class Interactive < Thor
      def self.exit_on_failure?
        true
      end

      class_option :json, type: :boolean, default: false, desc: 'Output as JSON'
      class_option :no_color, type: :boolean, default: false, desc: 'Disable color output'
      class_option :verbose, type: :boolean, default: false, aliases: ['-V'], desc: 'Verbose logging'

      desc 'version', 'Show version information'
      map %w[-v --version] => :version
      def version
        Main.start(['version'] + ARGV.select { |a| a.start_with?('--') })
      end

      desc 'chat [SUBCOMMAND]', 'Text-based AI conversation'
      subcommand 'chat', Legion::CLI::Chat

      desc 'commit', 'Generate AI commit message from staged changes'
      subcommand 'commit', Legion::CLI::Commit

      desc 'pr', 'Create pull request with AI-generated title and description'
      subcommand 'pr', Legion::CLI::Pr

      desc 'review', 'AI code review of changes'
      subcommand 'review', Legion::CLI::Review

      desc 'memory SUBCOMMAND', 'Persistent project memory across sessions'
      subcommand 'memory', Legion::CLI::Memory

      desc 'plan', 'Start plan mode (read-only exploration, no writes)'
      subcommand 'plan', Legion::CLI::Plan

      desc 'init', 'Initialize a new Legion workspace'
      subcommand 'init', Legion::CLI::Init

      desc 'tty', 'Launch the rich terminal UI'
      subcommand 'tty', Legion::CLI::Tty

      desc 'ask TEXT', 'Quick AI prompt (shortcut for chat prompt)'
      map %w[-p --prompt] => :ask
      def ask(*text)
        Legion::CLI::Chat.start(['prompt', text.join(' ')] + ARGV.select { |a| a.start_with?('--') })
      end

      no_commands do
        def formatter
          @formatter ||= Output::Formatter.new(
            json:  options[:json],
            color: !options[:no_color]
          )
        end
      end
    end
  end
end
```

**Step 2: Add autoload in `lib/legion/cli.rb`**

Add after the existing autoload block (around line 44):

```ruby
autoload :Interactive, 'legion/cli/interactive'
```

**Step 3: Commit**

```bash
git add lib/legion/cli/interactive.rb lib/legion/cli.rb
git commit -m "add Legion::CLI::Interactive with dev-workflow commands"
```

---

### Task 3: Rewrite `exe/legion` to route through TTY and Interactive

**Files:**
- Modify: `exe/legion`

**Step 1: Rewrite exe/legion**

Replace the entire file:

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

RubyVM::YJIT.enable if defined?(RubyVM::YJIT)

ENV['RUBY_GC_HEAP_INIT_SLOTS']           ||= '600000'
ENV['RUBY_GC_HEAP_FREE_SLOTS_MIN_RATIO'] ||= '0.20'
ENV['RUBY_GC_HEAP_FREE_SLOTS_MAX_RATIO'] ||= '0.40'
ENV['RUBY_GC_MALLOC_LIMIT']              ||= '64000000'
ENV['RUBY_GC_MALLOC_LIMIT_MAX']          ||= '128000000'

require 'bootsnap'
Bootsnap.setup(
  cache_dir:          File.expand_path('~/.legionio/cache/bootsnap'),
  development_mode:   false,
  load_path_cache:    true,
  compile_cache_iseq: true,
  compile_cache_yaml: true
)

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

# Bare `legion` (no args, interactive terminal) launches the TTY shell
# Bare `legion` (piped stdin) goes to headless chat prompt
# `legion <subcommand>` routes to the Interactive CLI (dev-workflow commands)
if ARGV.empty?
  if $stdin.tty?
    require 'legion/tty'
    Legion::TTY::App.run
  else
    require 'legion/cli'
    ARGV.replace(['chat', 'prompt', ''])
    Legion::CLI::Main.start(ARGV)
  end
else
  require 'legion/cli'
  Legion::CLI::Interactive.start(ARGV)
end
```

**Step 2: Verify bare legion launches TTY**

Run: `ruby -Ilib exe/legion version`
Expected: Version output (routed through Interactive -> Main)

**Step 3: Commit**

```bash
git add exe/legion
git commit -m "route bare legion to TTY shell, args to Interactive CLI"
```

---

### Task 4: Add `legion-tty` as a runtime dependency

**Files:**
- Modify: `legionio.gemspec`

**Step 1: Add the dependency**

Add after the `lex-node` dependency (line 59):

```ruby
spec.add_dependency 'legion-tty'
```

**Step 2: Commit**

```bash
git add legionio.gemspec
git commit -m "add legion-tty as runtime dependency"
```

---

### Task 5: Update Homebrew formula for dual binaries

**Files:**
- Modify: `../homebrew-tap/Formula/legion.rb`

**Step 1: Add legionio wrapper script**

In the `install` method, after the existing `(bin/"legion").write_env_script` line, add:

```ruby
(bin/"legionio").write_env_script libexec/"bin/legionio", env
```

**Step 2: Update caveats**

Update the caveats to reflect the dual-binary setup:

```ruby
def caveats
  <<~EOS
    Interactive shell (most users):
      legion                           # rich terminal UI with onboarding

    Operational CLI (daemon, extensions, tasks):
      legionio start                   # start the daemon
      legionio config scaffold         # generate config files
      legionio lex list                # list extensions
      legionio --help                  # all operational commands

    Config:  ~/.legionio/settings/
    Logs:    #{var}/log/legion/legion.log
    Data:    #{var}/lib/legion/

    Ruby 3.4.8 with YJIT is bundled — no separate Ruby installation needed.

    To start Legion as a background service:
      brew services start legion

    Start Redis (required for tracing and dream cycle):
      brew services start redis

    Optional services:
      brew services start rabbitmq         # job engine messaging
      brew services start postgresql@17    # legion-data persistence
      brew services start vault            # legion-crypt secrets
      ollama serve                         # local LLM for legion chat
  EOS
end
```

**Step 3: Commit (in homebrew-tap repo)**

```bash
cd ../homebrew-tap
git add Formula/legion.rb
git commit -m "add legionio binary wrapper and update caveats for dual-binary"
```

---

### Task 6: Update shell completions

**Files:**
- Modify: `completions/legion.bash`
- Modify: `completions/_legion`

**Step 1: Update bash completion**

The `legion` completion should only list Interactive commands: `chat commit pr review memory plan init tty ask version help`.

Add a separate `legionio` completion that lists all Main commands.

**Step 2: Update zsh completion**

Same split for zsh.

**Step 3: Commit**

```bash
git add completions/
git commit -m "update shell completions for legion/legionio split"
```

---

### Task 7: Update documentation

**Files:**
- Modify: `README.md` (relevant section about binary usage)
- Modify: `CLAUDE.md` (CLI section)

**Step 1: Update CLAUDE.md CLI section**

Add a section near the top explaining the dual-binary setup:

```markdown
### Binary Split

| Binary | Purpose |
|--------|---------|
| `legion` | Interactive TTY shell + dev-workflow commands (chat, commit, review, plan, memory, init) |
| `legionio` | Daemon lifecycle + all operational commands (start, stop, lex, task, config, mcp, etc.) |

`legion` with no args launches the TTY interactive shell. With args, it routes to dev-workflow subcommands.
`legionio` is the full operational CLI — all 40+ subcommands.
```

**Step 2: Commit**

```bash
git add README.md CLAUDE.md
git commit -m "document legion/legionio binary split"
```

---

### Task 8: Run pre-push pipeline for LegionIO

Covers changes from Tasks 1-7.

**Step 1: Run specs**

Run: `bundle exec rspec`
Expected: All specs pass

**Step 2: Run rubocop auto-fix**

Run: `bundle exec rubocop -A`

**Step 3: Run rubocop**

Run: `bundle exec rubocop`
Expected: 0 offenses

**Step 4: Bump version**

Bump patch version in `lib/legion/version.rb` (1.4.61 -> 1.4.62 or as appropriate).

**Step 5: Update CHANGELOG.md**

Add entry for the binary split.

**Step 6: Push**

```bash
git push
```

---

### Task 9: Add env var defaults to LLM provider settings

**Files:**
- Modify: `../legion-llm/lib/legion/llm/settings.rb`

**Step 1: Update provider defaults with env:// references**

Replace the `providers` method to add `env://` fallback chains for each provider's credentials. The `Legion::Settings::Resolver` already resolves `env://` URIs, so these become auto-configured when the env var is set.

```ruby
def self.providers
  {
    bedrock:   {
      enabled:       false,
      default_model: 'us.anthropic.claude-sonnet-4-6-v1',
      api_key:       nil,
      secret_key:    nil,
      session_token: nil,
      bearer_token:  'env://AWS_BEARER_TOKEN_BEDROCK',
      region:        'us-east-2'
    },
    anthropic: {
      enabled:       false,
      default_model: 'claude-sonnet-4-6',
      api_key:       'env://ANTHROPIC_API_KEY'
    },
    openai:    {
      enabled:       false,
      default_model: 'gpt-4o',
      api_key:       ['env://OPENAI_API_KEY', 'env://CODEX_API_KEY']
    },
    gemini:    {
      enabled:       false,
      default_model: 'gemini-2.0-flash',
      api_key:       'env://GEMINI_API_KEY'
    },
    ollama:    {
      enabled:       false,
      default_model: 'llama3',
      base_url:      'http://localhost:11434'
    }
  }
end
```

**Step 2: Add `ANTHROPIC_MODEL` env var support**

In the same file, update the `default` method to read model override from env:

```ruby
def self.default
  model_override = ENV.fetch('ANTHROPIC_MODEL', nil)
  {
    enabled:          true,
    connected:        false,
    default_model:    model_override,
    default_provider: nil,
    providers:        providers,
    routing:          routing_defaults,
    discovery:        discovery_defaults,
    gateway:          gateway_defaults
  }
end
```

**Step 3: Add auto-enable logic to providers module**

Modify `../legion-llm/lib/legion/llm/providers.rb` — add a method that auto-enables providers whose credentials resolved to non-nil values. Call it from `configure_providers` before the provider loop:

```ruby
def auto_enable_from_resolved_credentials
  settings[:providers].each do |provider, config|
    next if config[:enabled]

    has_creds = case provider
                when :bedrock
                  config[:bearer_token] || (config[:api_key] && config[:secret_key])
                when :ollama
                  true # always check if Ollama is running
                else
                  config[:api_key]
                end
    next unless has_creds

    config[:enabled] = true
    Legion::Logging.info "Auto-enabled #{provider} provider (credentials found)"
  end
end
```

Update `configure_providers` to call `auto_enable_from_resolved_credentials` first:

```ruby
def configure_providers
  auto_enable_from_resolved_credentials
  settings[:providers].each do |provider, config|
    next unless config[:enabled]
    apply_provider_config(provider, config)
  end
end
```

**Step 4: Commit (in legion-llm repo)**

```bash
cd ../legion-llm
git add lib/legion/llm/settings.rb lib/legion/llm/providers.rb
git commit -m "auto-configure providers from env vars, add ANTHROPIC_MODEL support"
```

---

### Task 10: Import Claude CLI settings into Legion::Settings

**Files:**
- Create: `../legion-llm/lib/legion/llm/claude_config_loader.rb`
- Modify: `../legion-llm/lib/legion/llm.rb`

This task reads `~/.claude/settings.json` and `~/.claude.json` to extract any LLM-relevant configuration (API keys, model preferences) and merges them into Legion::Settings as a low-priority source.

**Step 1: Create the Claude config loader**

```ruby
# frozen_string_literal: true

module Legion
  module LLM
    module ClaudeConfigLoader
      CLAUDE_SETTINGS = File.expand_path('~/.claude/settings.json')
      CLAUDE_CONFIG   = File.expand_path('~/.claude.json')

      module_function

      def load
        config = read_json(CLAUDE_SETTINGS).merge(read_json(CLAUDE_CONFIG))
        return if config.empty?

        apply_claude_config(config)
      end

      def read_json(path)
        return {} unless File.exist?(path)

        require 'json'
        ::JSON.parse(File.read(path), symbolize_names: true)
      rescue StandardError
        {}
      end

      def apply_claude_config(config)
        apply_api_keys(config)
        apply_model_preference(config)
      end

      def apply_api_keys(config)
        llm = Legion::LLM.settings
        providers = llm[:providers]

        # Claude CLI stores provider keys in various locations
        if config[:anthropicApiKey] && providers.dig(:anthropic, :api_key).nil?
          providers[:anthropic][:api_key] = config[:anthropicApiKey]
          Legion::Logging.debug 'Imported Anthropic API key from Claude CLI config'
        end

        if config[:openaiApiKey] && providers.dig(:openai, :api_key).nil?
          providers[:openai][:api_key] = config[:openaiApiKey]
          Legion::Logging.debug 'Imported OpenAI API key from Claude CLI config'
        end
      end

      def apply_model_preference(config)
        return unless config[:preferredModel] || config[:model]

        model = config[:preferredModel] || config[:model]
        llm = Legion::LLM.settings
        return if llm[:default_model]

        llm[:default_model] = model
        Legion::Logging.debug "Imported model preference from Claude CLI config: #{model}"
      end
    end
  end
end
```

**Step 2: Call ClaudeConfigLoader during LLM start**

In `../legion-llm/lib/legion/llm.rb`, add `require` and call in `start` before `configure_providers`:

```ruby
def start
  Legion::Logging.debug 'Legion::LLM is running start'

  require 'legion/llm/claude_config_loader'
  ClaudeConfigLoader.load

  configure_providers
  run_discovery
  set_defaults

  @started = true
  Legion::Settings[:llm][:connected] = true
  Legion::Logging.info 'Legion::LLM started'
  ping_provider
end
```

**Step 3: Commit (in legion-llm repo)**

```bash
cd ../legion-llm
git add lib/legion/llm/claude_config_loader.rb lib/legion/llm.rb
git commit -m "import Claude CLI config files for LLM provider auto-configuration"
```

---

### Task 11: Replace onboarding credential prompt with provider ping-testing

**Files:**
- Create: `../legion-tty/lib/legion/tty/background/llm_probe.rb`
- Modify: `../legion-tty/lib/legion/tty/screens/onboarding.rb`
- Modify: `../legion-tty/lib/legion/tty/components/wizard_prompt.rb`

Instead of asking for a provider and API key, the onboarding wizard now:
1. Loads Legion::LLM (which auto-discovers env vars + Claude CLI config)
2. Ping-tests each enabled provider
3. Shows results with green checkmark (working + latency) or red X (failed)
4. Lets the user pick a default if multiple providers work

**Step 1: Create the LLM probe background task**

```ruby
# frozen_string_literal: true

module Legion
  module TTY
    module Background
      class LlmProbe
        def initialize(logger: nil)
          @log = logger
        end

        def run_async(queue)
          Thread.new do
            result = probe_providers
            queue.push({ data: result })
          rescue StandardError => e
            @log&.log('llm_probe', "error: #{e.message}")
            queue.push({ data: { providers: [], error: e.message } })
          end
        end

        private

        def probe_providers
          require 'legion/llm'
          require 'legion/settings'

          # Trigger LLM auto-configuration (env vars, Claude CLI config)
          begin
            Legion::LLM.start unless Legion::LLM.started?
          rescue StandardError => e
            @log&.log('llm_probe', "LLM start failed: #{e.message}")
          end

          results = []
          providers = Legion::LLM.settings[:providers] || {}

          providers.each do |name, config|
            next unless config[:enabled]

            result = ping_provider(name, config)
            results << result
            @log&.log('llm_probe', "#{name}: #{result[:status]} (#{result[:latency_ms]}ms)")
          end

          { providers: results }
        end

        def ping_provider(name, config)
          model = config[:default_model]
          start_time = Time.now
          RubyLLM.chat(model: model, provider: name).ask('Respond with only: pong')
          latency = ((Time.now - start_time) * 1000).round
          { name: name, model: model, status: :ok, latency_ms: latency }
        rescue StandardError => e
          latency = ((Time.now - start_time) * 1000).round
          { name: name, model: model, status: :error, latency_ms: latency, error: e.message }
        end
      end
    end
  end
end
```

**Step 2: Update wizard_prompt to add provider status display**

Add a method to `WizardPrompt` for displaying provider results and picking a default:

```ruby
def display_provider_results(providers)
  providers.each do |p|
    icon = p[:status] == :ok ? "\u2705" : "\u274C"
    latency = "#{p[:latency_ms]}ms"
    label = "#{icon} #{p[:name]} (#{p[:model]}) — #{latency}"
    label += " [#{p[:error]}]" if p[:error]
    @prompt.say(label)
  end
end

def select_default_provider(working_providers)
  return nil if working_providers.empty?
  return working_providers.first if working_providers.size == 1

  choices = working_providers.map do |p|
    { name: "#{p[:name]} (#{p[:model]}, #{p[:latency_ms]}ms)", value: p[:name] }
  end
  @prompt.select('Multiple providers available. Choose your default:', choices)
end
```

**Step 3: Update onboarding `run_wizard` to use probe results**

Replace the provider/API key flow in `onboarding.rb`. The `run_wizard` method should:
1. Ask name (unchanged)
2. Show "Detecting AI providers..." instead of asking for provider/key
3. Collect LLM probe results
4. Display provider status with checkmarks
5. If multiple working providers, let user pick default
6. If no working providers, show manual config guidance

```ruby
def run_wizard
  name = ask_for_name
  sleep 0.8
  typed_output("  Nice to meet you, #{name}.")
  @output.puts
  sleep 1
  typed_output('Detecting AI providers...')
  @output.puts
  @output.puts

  llm_data = drain_with_timeout(@llm_queue, timeout: 15)
  providers = llm_data&.dig(:data, :providers) || []

  @wizard.display_provider_results(providers)
  @output.puts

  working = providers.select { |p| p[:status] == :ok }
  if working.any?
    default = @wizard.select_default_provider(working)
    typed_output("Connected. Let's chat.")
  else
    typed_output('No AI providers detected. Configure one in ~/.legionio/settings/llm.json')
  end

  @output.puts
  { name: name, provider: default, providers: providers }
end
```

**Step 4: Add LLM probe to `start_background_threads`**

Add to onboarding.rb `initialize`:
```ruby
@llm_queue = Queue.new
```

Add to `start_background_threads`:
```ruby
require_relative '../background/llm_probe'
@llm_probe = Background::LlmProbe.new(logger: @log)
@llm_probe.run_async(@llm_queue)
```

**Step 5: Commit (in legion-tty repo)**

```bash
cd ../legion-tty
git add lib/legion/tty/background/llm_probe.rb \
        lib/legion/tty/screens/onboarding.rb \
        lib/legion/tty/components/wizard_prompt.rb
git commit -m "replace credential prompts with LLM provider auto-detection and ping-testing"
```

---

### Task 12: Run pre-push pipeline for legion-llm

Covers changes from Tasks 9, 10, and 16.

**Step 1: Run specs**

Run: `cd ../legion-llm && bundle exec rspec`
Expected: All specs pass

**Step 2: Run rubocop auto-fix**

Run: `bundle exec rubocop -A`

**Step 3: Run rubocop**

Run: `bundle exec rubocop`
Expected: 0 offenses

**Step 4: Bump version**

Bump patch version in `lib/legion/llm/version.rb` (0.3.3 -> 0.3.4).

**Step 5: Update CHANGELOG.md**

Add entries for:
- env var auto-configuration for all providers
- `ANTHROPIC_MODEL` env var support
- Claude CLI config file import (`~/.claude/settings.json`, `~/.claude.json`)
- Ollama auto-detection via local port probe

**Step 6: Push**

```bash
git push
```

---

### Task 13: Publish legion-tty to RubyGems

This is a hard prerequisite for Task 4 (gemspec dependency) and Homebrew builds. Without it, `gem install legionio` and `brew install legion` both fail.

**Step 1: Verify gem builds cleanly**

Run:
```bash
cd ../legion-tty
gem build legion-tty.gemspec
```
Expected: `legion-tty-0.2.1.gem` created with no warnings

**Step 2: Push to RubyGems**

Run:
```bash
gem push legion-tty-0.2.1.gem
```
Expected: Successfully registered gem

**Step 3: Verify it's installable**

Run:
```bash
gem install legion-tty
```
Expected: Successfully installed

---

### Task 14: Fix Homebrew service block for binary split

**Files:**
- Modify: `../homebrew-tap/Formula/legion.rb`

After the split, daemon operations belong to `legionio`, not `legion`. The `brew services start legion` launchd service must use the `legionio` binary.

**Step 1: Update the service block**

Change:
```ruby
service do
  run [opt_bin/"legion", "start", "--log-level", "info"]
```

To:
```ruby
service do
  run [opt_bin/"legionio", "start", "--log-level", "info"]
```

**Step 2: Update the test block**

The test should verify both binaries:

```ruby
test do
  assert_match "legionio", shell_output("#{bin}/legion version")
  assert_match "legionio", shell_output("#{bin}/legionio version")
end
```

**Step 3: Commit (in homebrew-tap repo)**

```bash
cd ../homebrew-tap
git add Formula/legion.rb
git commit -m "use legionio binary for brew service, test both binaries"
```

---

### Task 15: Update build-ruby.yml to verify both binaries

**Files:**
- Modify: `../homebrew-tap/.github/workflows/build-ruby.yml`

**Step 1: Add legionio verification to the verify step**

In the "Verify build" step, after `ruby -e "require 'legion/version'; puts Legion::VERSION"`, add:

```bash
echo "=== Verify legionio binary ==="
legionio_bin="$GITHUB_WORKSPACE/legion-ruby/bin/legionio"
if [ -f "$legionio_bin" ]; then
  echo "legionio binary found"
  ruby "$legionio_bin" version || echo "legionio version check failed"
else
  echo "WARNING: legionio binary not found in tarball"
fi
```

**Step 2: Commit (in homebrew-tap repo)**

```bash
cd ../homebrew-tap
git add .github/workflows/build-ruby.yml
git commit -m "verify legionio binary in build workflow"
```

---

### Task 16: Auto-detect Ollama without env vars

**Files:**
- Modify: `../legion-llm/lib/legion/llm/providers.rb`

Ollama doesn't use API keys — it's a local service. If port 11434 is responding, auto-enable it. This fits the "detect everything" philosophy and works alongside the existing scanner port probe.

**Step 1: Add Ollama port check to auto-enable logic**

Update the `auto_enable_from_resolved_credentials` method's `:ollama` case:

```ruby
when :ollama
  # Auto-enable if Ollama is running locally
  require 'socket'
  begin
    host = (config[:base_url] || 'http://localhost:11434').gsub(%r{^https?://}, '').split(':')
    addr = host[0]
    port = (host[1] || '11434').to_i
    Socket.tcp(addr, port, connect_timeout: 1).close
    true
  rescue StandardError
    false
  end
```

**Step 2: Commit (in legion-llm repo)**

```bash
cd ../legion-llm
git add lib/legion/llm/providers.rb
git commit -m "auto-detect Ollama by probing local port"
```

---

### Task 17: Run pre-push pipeline for legion-tty

Covers changes from Task 11.

**Step 1: Run specs**

Run: `cd ../legion-tty && bundle exec rspec`
Expected: All specs pass

**Step 2: Run rubocop auto-fix**

Run: `bundle exec rubocop -A`

**Step 3: Run rubocop**

Run: `bundle exec rubocop`
Expected: 0 offenses

**Step 4: Bump version**

Bump patch version in `lib/legion/tty/version.rb` (0.2.0 -> 0.2.1).

**Step 5: Update CHANGELOG.md**

Add entry for LLM provider auto-detection in onboarding.

**Step 6: Push**

```bash
git push
```

---

### Task 18: Run pre-push pipeline for homebrew-tap

Covers changes from Tasks 5, 14, and 15.

**Step 1: Commit all homebrew-tap changes**

If not already committed individually:
```bash
cd ../homebrew-tap
git add Formula/legion.rb .github/workflows/build-ruby.yml
git commit -m "dual-binary support: legionio wrapper, service fix, build verification"
```

**Step 2: Push**

```bash
git push
```

**Step 3: Trigger build workflow**

After legion-tty and legionio gems are published, trigger `build-ruby.yml` via GitHub Actions `workflow_dispatch` with `package_revision: 3` to build a new tarball that includes both binaries and legion-tty.

---

### Execution Order Summary

The tasks have dependency ordering:

```
Phase 1 — LegionIO binary split (Tasks 1-8):
  1. Create exe/legionio
  2. Create Legion::CLI::Interactive
  3. Rewrite exe/legion
  4. Add legion-tty gemspec dependency
  5. Update Homebrew formula (dual binaries)
  6. Update shell completions
  7. Update documentation
  8. Pre-push pipeline for LegionIO

Phase 2 — LLM auto-configuration (Tasks 9-12, 16):
  9. Add env var defaults to provider settings
  10. Import Claude CLI settings
  11. Replace onboarding credential prompt with ping-testing
  12. Pre-push pipeline for legion-llm (covers 9, 10, 16)
  16. Auto-detect Ollama via port probe

Phase 3 — Publish and release (Tasks 13-15, 17-18):
  13. Publish legion-tty to RubyGems (prerequisite for Phase 1 gemspec)
  14. Fix Homebrew service block for legionio
  15. Update build-ruby.yml verification
  17. Pre-push pipeline for legion-tty (covers 11)
  18. Pre-push pipeline + build trigger for homebrew-tap
```

**Recommended order**: 13 → 1-8 → 9-10 → 16 → 12 → 11 → 17 → 14-15 → 18
