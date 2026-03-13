# LegionIO Best Practices

## Ruby Conventions

### Version and Style
- Ruby >= 3.4 required across all gems
- `frozen_string_literal: true` in every file
- Rubocop with Ruby 3.4 target (`TargetRubyVersion: 3.4`)
- Follow standard rubocop defaults with spec exclusions for `Metrics/BlockLength`

### Naming
- Gem names: `lex-{service}` (lowercase, hyphenated)
- Module names: `Legion::Extensions::{Service}` (CamelCase)
- Runner methods: snake_case, descriptive verbs (`fetch`, `create`, `delete`)
- Settings keys: snake_case symbols (`:host`, `:api_key`, `:max_retries`)

### Dependencies
- LEX gems should NOT depend on `legionio` — they are loaded by the framework at runtime
- Only depend on what you directly use (e.g., `faraday` for HTTP, `redis` for Redis)
- Use `legion-json` for JSON operations (not `json` or `oj` directly)
- Put test-only dependencies in the Gemfile, not the gemspec

## Extension Design

### Runner Methods

**Accept config as keyword args:**

```ruby
# Good: standalone-friendly, testable
def get(key:, host: '127.0.0.1', port: 6379, **)
  Redis.new(host: host, port: port).get(key)
end

# Bad: coupled to framework globals
def get(key:, **)
  Redis.new(host: settings[:host]).get(key)
end
```

**Always include double splat (`**`):**

The framework passes metadata (task_id, parent_id, etc.) alongside business args. The double splat absorbs these without breaking your method signature.

**Return hashes:**

Runner methods should return a hash. This result is carried to downstream tasks via CheckSubtask:

```ruby
def fetch(url:, **)
  response = Faraday.get(url)
  { success: response.success?, status: response.status, body: response.body }
end
```

### Helpers

**Keep helpers pure:**

```ruby
# Good: explicit args, no global state
def connection(host:, port:, **)
  Redis.new(host: host, port: port)
end

# Bad: reaches into framework
def connection
  Redis.new(host: Legion::Settings[:extensions][:redis][:host])
end
```

### Standalone Client

Every LEX that wraps an external API should provide a `Client` class:

```ruby
client = Legion::Extensions::Redis::Client.new(host: '10.0.0.1', port: 6379)
client.get(key: 'foo')
```

The Client class:
- Lives in `lib/legion/extensions/{name}/client.rb`
- Includes all runner modules
- Stores connection config in `initialize`
- Is config-agnostic (no conditional framework checks)

Framework actors construct the Client from settings. The Client itself never reads from `Legion::Settings`.

See [LEX Standalone Client Pattern](plans/2026-03-13-lex-standalone-client-design.md) for the full design.

### Settings

**Register defaults via `default_settings`:**

```ruby
module Legion::Extensions::Myservice
  def self.default_settings
    { host: 'localhost', port: 443, timeout: 30 }
  end
end
```

Types are inferred automatically. Add explicit constraints only when needed:

```ruby
Legion::Settings.define_schema('myservice', {
  driver: { enum: %w[http grpc] },
  port: { required: true }
})
```

**No LEX should require a PR to legion core code** unless it's a bug or feature request. Schema registration is self-service via `merge_settings` and `define_schema`.

## Task Chains

### Conditions

Use `lex-conditioner` for branching logic. Conditions are JSON rule sets:

```json
{
  "all": [
    { "fact": "status_code", "operator": "equal", "value": 200 }
  ]
}
```

**Supported operators:** `equal`, `not_equal`, `greater_than`, `less_than`, `greater_than_or_equal`, `less_than_or_equal`, `contains`, `not_contains`, `starts_with`, `ends_with`, `matches`

### Transformations

Use `lex-transformer` to reshape data between tasks. Templates are ERB:

```erb
{ "message": "<%= results['alert'] %> on <%= results['host'] %>" }
```

### Chain Design

- Keep chains shallow (< 5 levels deep)
- Use conditions to prevent unnecessary downstream execution
- Use transformations to decouple task interfaces (task A's output format != task B's input format)
- Fan-out (one task triggers many) is fine; fan-in (many tasks converge) requires explicit coordination

## Configuration

### File Organization

Organize config by concern:

```
settings/
├── transport.json    # RabbitMQ connection
├── data.json         # Database connection
├── cache.json        # Cache connection
├── crypt.json        # Encryption settings
└── extensions.json   # Per-extension config
```

### Secrets

Never put secrets in config files checked into git. Use one of:
- HashiCorp Vault (via `legion-crypt`)
- Environment variables
- Config files in `/etc/legionio/` (managed by deployment tooling)

The `find_setting` cascade checks: args > Vault > settings > cache > env.

### Validation

Run `Legion::Settings.validate!` at startup to catch config errors early. The framework does this automatically during `Legion::Service` startup.

Cross-module validation catches dependency conflicts:

```ruby
Legion::Settings.add_cross_validation do |settings, errors|
  if settings[:transport][:messages][:encrypt] && settings[:crypt][:cluster_secret].nil?
    errors << {
      module: :crypt,
      path: 'crypt.cluster_secret',
      message: 'required when message encryption is enabled'
    }
  end
end
```

## Testing

### Unit Tests

Test runner methods in isolation with explicit args:

```ruby
RSpec.describe Legion::Extensions::Http::Runners::Http do
  describe '.get' do
    it 'returns a hash with response data' do
      result = described_class.get(host: 'https://httpbin.org', uri: '/get')
      expect(result).to be_a(Hash)
    end
  end
end
```

### Test Without Framework

Runner methods should be testable without starting LegionIO:

```ruby
# This should work without RabbitMQ, without MySQL, without anything
result = Legion::Extensions::Redis::Runners::Item.get(
  key: 'test', host: 'localhost', port: 6379
)
```

### CI

Every repo has `.github/workflows/ci.yml` running rubocop + rspec on push/PR.

## Git Conventions

- Commit messages: lowercase, imperative mood (`add vault namespace`, `fix typo in queue name`)
- Branch naming: kebab-case (`feature/add-webhook-support`)
- No force pushes to main
- Each LEX is its own git repo under https://github.com/LegionIO

## Documentation

Every repo has:
- `README.md` — user-facing: what it is, how to install, how to use
- `CLAUDE.md` — AI-facing: architecture, file map, design decisions, Level 3 in hierarchy

The docs hierarchy:
```
Level 1: /legion/CLAUDE.md (ecosystem overview)
Level 2: /legion/extensions/CLAUDE.md (extension collection)
Level 3: /legion/{repo}/CLAUDE.md (individual repo)
```

## Common Pitfalls

1. **Don't depend on `legionio` in your gemspec** — the framework loads you, not the other way around
2. **Don't read `settings` inside runner methods** — accept config as keyword args
3. **Don't forget the `**` splat** — framework metadata will break your method without it
4. **Don't put test deps in gemspec** — use Gemfile for development dependencies
5. **Don't write actors unless you need them** — the framework auto-generates Subscription actors
6. **Don't use `sleep` for timing** — use the `Every` actor type for intervals
7. **Don't assume MySQL** — legion-data supports SQLite, PostgreSQL, and MySQL
8. **Don't hardcode exchange/queue names** — let the framework derive them from your module namespace
