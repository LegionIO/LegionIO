# Legion/LegionIO Binary Split Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Split the `legion` executable into two binaries: `legion` (interactive shell + dev workflow) and `legionio` (daemon + operational CLI).

**Architecture:** `exe/legion` routes bare invocation to `Legion::TTY::App.run`, args to a new `Legion::CLI::Interactive` Thor class with dev-workflow commands. `exe/legionio` always routes to the existing `Legion::CLI::Main`. The `legionio` gemspec adds `legion-tty` as a runtime dependency.

**Tech Stack:** Ruby, Thor, legion-tty gem, existing Legion::CLI modules

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

### Task 8: Run pre-push pipeline

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
