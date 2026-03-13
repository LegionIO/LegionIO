# Extension Development Guide

This guide covers everything you need to build a Legion Extension (LEX).

## Minimal Extension

A single runner module is all you need. The framework auto-generates AMQP topology, actors, and registration.

### 1. Scaffold

```bash
legion lex create myservice
```

This creates:

```
lex-myservice/
├── lib/legion/extensions/myservice.rb
├── lib/legion/extensions/myservice/version.rb
├── lib/legion/extensions/myservice/runners/
├── lex-myservice.gemspec
├── Gemfile
├── spec/
└── CLAUDE.md
```

### 2. Write a Runner

```ruby
# lib/legion/extensions/myservice/runners/api.rb
# frozen_string_literal: true

module Legion
  module Extensions
    module Myservice
      module Runners
        module Api
          def fetch(endpoint:, api_key: nil, timeout: 30, **)
            # Your API interaction logic here
            response = make_request(endpoint, api_key: api_key, timeout: timeout)
            { success: response.ok?, data: response.body }
          end

          def create(endpoint:, payload:, api_key: nil, **)
            response = make_request(endpoint, method: :post, body: payload, api_key: api_key)
            { success: response.ok?, id: response.body['id'] }
          end

          include Legion::Extensions::Helpers::Lex
        end
      end
    end
  end
end
```

**That's it.** This automatically gets:
- Exchange: `myservice`
- Queue: `myservice.api` (bound to the exchange)
- Dead-letter exchange: `myservice.dlx`
- Subscription actor consuming from the queue
- Registration in the cluster function registry

### 3. Add Entry Point

```ruby
# lib/legion/extensions/myservice.rb
# frozen_string_literal: true

require 'legion/extensions/myservice/version'

module Legion
  module Extensions
    module Myservice
      extend Legion::Extensions::Core if Legion::Extensions.const_defined? :Core
    end
  end
end
```

### 4. Gemspec

```ruby
# lex-myservice.gemspec
Gem::Specification.new do |spec|
  spec.name          = 'lex-myservice'
  spec.version       = Legion::Extensions::Myservice::VERSION
  spec.authors       = ['Your Name']
  spec.summary       = 'LegionIO extension for MyService API'
  spec.license       = 'MIT'
  spec.required_ruby_version = '>= 3.4'

  spec.files         = Dir['lib/**/*']
  spec.require_paths = ['lib']

  # Add your service-specific dependencies
  spec.add_dependency 'faraday', '~> 2.0'
end
```

Note: Do NOT add `legionio` as a dependency. LEX gems should only depend on what they directly use. The framework loads them at runtime.

## Full Extension Structure

For more complex extensions:

```
lex-myservice/
├── lib/legion/extensions/myservice.rb           # Entry point
├── lib/legion/extensions/myservice/version.rb   # Version
├── lib/legion/extensions/myservice/
│   ├── client.rb                                # Standalone API client
│   ├── runners/                                 # Business logic
│   │   ├── api.rb                               # API operations
│   │   └── admin.rb                             # Admin operations
│   ├── actors/                                  # Custom execution modes
│   │   └── poller.rb                            # Polling actor
│   ├── helpers/                                 # Shared utilities
│   │   └── connection.rb                        # Connection factory
│   ├── transport/                               # Custom AMQP topology
│   │   ├── exchanges/myservice.rb
│   │   ├── queues/api.rb
│   │   └── messages/api.rb
│   └── data/                                    # Database extensions
│       ├── migrations/001_create_myservice.rb
│       └── models/myservice_record.rb
├── spec/
│   └── legion/extensions/myservice/
│       ├── runners/api_spec.rb
│       └── client_spec.rb
├── lex-myservice.gemspec
├── Gemfile
├── CLAUDE.md
└── README.md
```

## Runner Rules

### Method Signature

Every public method on a runner module is a callable function. Use keyword arguments:

```ruby
def fetch(endpoint:, api_key: nil, timeout: 30, **)
```

- **Required args** (`endpoint:`) — the framework raises if missing
- **Optional args** (`api_key: nil`) — default when not provided
- **Double splat** (`**`) — always include to accept framework metadata (task_id, etc.)
- **Return a hash** — the result is passed to downstream tasks via CheckSubtask

### Config as Keyword Args

Runner methods should accept configuration values as keyword args with sensible defaults, not read from `settings` directly:

```ruby
# Good: works standalone and in framework
def fetch(endpoint:, host: 'api.example.com', api_key: nil, timeout: 30, **)

# Avoid: couples to Legion::Settings
def fetch(endpoint:, **)
  host = settings[:host]  # breaks standalone use
```

### Include Helpers

Always include `Legion::Extensions::Helpers::Lex` at the bottom of the module:

```ruby
module Api
  def fetch(...)
    # ...
  end

  include Legion::Extensions::Helpers::Lex
end
```

This provides:
- `settings` — extension config from `Legion::Settings[:extensions][:myservice]`
- `find_setting(name)` — cascading lookup: args > Vault > settings > cache > env
- `function_desc`, `function_example`, `function_options` — metadata registration
- `log` — logger access

### Function Metadata

Document your functions for the registry:

```ruby
module Api
  def fetch(endpoint:, **)
    # ...
  end

  function_desc :fetch, 'Fetch data from the MyService API'
  function_example :fetch, { endpoint: '/users/123' }
  function_options :fetch, { timeout: 'Request timeout in seconds' }

  include Legion::Extensions::Helpers::Lex
end
```

## Standalone Client Pattern

LEX gems should also work as standalone API client libraries without the full framework.

### Add a Client Class

```ruby
# lib/legion/extensions/myservice/client.rb
# frozen_string_literal: true

module Legion
  module Extensions
    module Myservice
      class Client
        def initialize(host:, api_key: nil, timeout: 30, **opts)
          @config = { host: host, api_key: api_key, timeout: timeout, **opts }
        end

        include Legion::Extensions::Myservice::Runners::Api
        include Legion::Extensions::Myservice::Runners::Admin

        private

        def make_request(endpoint, method: :get, **opts)
          # Use @config for connection defaults
          Faraday.new(@config[:host]).send(method, endpoint) do |req|
            req.headers['Authorization'] = "Bearer #{@config[:api_key]}" if @config[:api_key]
            req.options.timeout = opts[:timeout] || @config[:timeout]
            req.body = opts[:body] if opts[:body]
          end
        end
      end
    end
  end
end
```

### Two Usage Modes

```ruby
# Standalone (script, service, test)
client = Legion::Extensions::Myservice::Client.new(host: 'https://api.example.com', api_key: 'sk-...')
client.fetch(endpoint: '/users/123')

# Stateless one-off
Legion::Extensions::Myservice::Runners::Api.fetch(endpoint: '/users/123', host: 'https://api.example.com')
```

## Actor Types

Override the default Subscription actor when your extension needs a different execution mode.

### Polling Actor

```ruby
# lib/legion/extensions/myservice/actors/poller.rb
module Legion
  module Extensions
    module Myservice
      module Actors
        class Poller < Legion::Extensions::Actors::Every
          self.time = 60  # seconds between runs

          def action
            # Called every 60 seconds
            runner_class.check_status
          end
        end
      end
    end
  end
end
```

### Actor Types Reference

| Type | Use When |
|------|----------|
| `Subscription` | Default. React to AMQP messages. |
| `Every` | Run at fixed intervals (polling, health checks). |
| `Once` | Run once at startup (initialization, registration). |
| `Loop` | Continuous execution (stream processing). |
| `Poll` | Polling-based with custom logic. |
| `Nothing` | Register but don't execute (placeholder, manual trigger only). |

## Settings Registration

Register your extension's default settings so they participate in validation:

```ruby
# lib/legion/extensions/myservice.rb
module Legion
  module Extensions
    module Myservice
      extend Legion::Extensions::Core if Legion::Extensions.const_defined? :Core

      def self.default_settings
        {
          host: 'https://api.example.com',
          api_key: nil,
          timeout: 30,
          max_retries: 3
        }
      end
    end
  end
end
```

Types are inferred from these defaults automatically. Add explicit constraints if needed:

```ruby
Legion::Settings.define_schema('myservice', {
  timeout: { required: true },
  max_retries: { enum: [0, 1, 3, 5, 10] }
})
```

## Database Extensions

If your extension needs persistent storage:

### Migration

```ruby
# lib/legion/extensions/myservice/data/migrations/001_create_records.rb
Sequel.migration do
  change do
    create_table(:myservice_records) do
      primary_key :id
      String :name, null: false
      String :status, default: 'active'
      DateTime :created_at
      DateTime :updated_at
    end
  end
end
```

### Model

```ruby
# lib/legion/extensions/myservice/data/models/record.rb
module Legion
  module Extensions
    module Myservice
      module Data
        class Record < Sequel::Model(:myservice_records)
          plugin :timestamps, update_on_create: true
        end
      end
    end
  end
end
```

## Helpers

Share connection logic across runners:

```ruby
# lib/legion/extensions/myservice/helpers/connection.rb
module Legion
  module Extensions
    module Myservice
      module Helpers
        module Connection
          def connection(host:, api_key: nil, **opts)
            Faraday.new(host) do |conn|
              conn.headers['Authorization'] = "Bearer #{api_key}" if api_key
              conn.options.timeout = opts[:timeout] || 30
              conn.request :json
              conn.response :json
            end
          end
        end
      end
    end
  end
end
```

Keep helpers pure — accept explicit args, don't reach into global state.

## Testing

```ruby
# spec/legion/extensions/myservice/runners/api_spec.rb
require 'spec_helper'

RSpec.describe Legion::Extensions::Myservice::Runners::Api do
  describe '.fetch' do
    it 'returns data from the API' do
      result = described_class.fetch(
        endpoint: '/users/123',
        host: 'https://api.example.com'
      )
      expect(result).to include(:success, :data)
    end
  end
end
```

Run:

```bash
bundle exec rspec
bundle exec rubocop
```

## CI

Every LEX should have a `.github/workflows/ci.yml`:

```yaml
name: CI
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: '3.4'
          bundler-cache: true
      - run: bundle exec rubocop
      - run: bundle exec rspec
```

## Checklist

Before publishing a LEX:

- [ ] Runner methods use keyword args with `**` splat
- [ ] Runner methods accept config as keyword args (not from `settings` directly)
- [ ] `include Legion::Extensions::Helpers::Lex` at bottom of each runner module
- [ ] Entry point conditionally extends `Legion::Extensions::Core`
- [ ] `default_settings` defined if extension has configurable options
- [ ] Client class provided for standalone use
- [ ] Helpers are pure (explicit args, no global state)
- [ ] Gemspec does NOT depend on `legionio`
- [ ] Ruby >= 3.4 in gemspec
- [ ] `frozen_string_literal: true` in all files
- [ ] RSpec tests for runner methods
- [ ] Rubocop passes
- [ ] CI workflow (`.github/workflows/ci.yml`)
- [ ] CLAUDE.md with Level 3 documentation
- [ ] README.md with installation, usage, and API reference
