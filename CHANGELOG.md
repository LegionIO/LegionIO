# Legion Changelog

## [Unreleased]

## [1.9.32] - 2026-05-14

### Removed
- Removed `gem 'ruby_llm'` dependency from Gemfile; all 40 CLI chat tools now use `Legion::Tools::Base` natively.

### Changed
- Migrated all 40 CLI chat tool classes from `RubyLLM::Tool` to `Legion::Tools::Base`:
  - `param` DSL replaced with `input_schema` (JSON Schema hash)
  - `def execute` instance method replaced with `def self.call` class method
  - Explicit `tool_name 'legion.<snake_case>'` added to each tool
  - Private instance helpers converted to class methods
- Updated `tool_registry.rb`: removed `require 'ruby_llm'` and `begin/rescue LoadError` guard.
- Updated `extension_tool_loader.rb`: `klass < RubyLLM::Tool` changed to `klass < Legion::Tools::Base`.
- Updated `generate_command.rb` tool template to emit `Legion::Tools::Base` with `input_schema` and `def self.call`.
- `Permissions::Gate` now prepends on the singleton class to intercept `self.call` correctly.

## [1.9.31] - 2026-05-14

### Added
- `GET /api/identity` endpoint returning live process identity, provider resolution status, and registered provider metadata.
- `autobuild_submodules` recursive walk in `Legion::Extensions` — nested sub-modules (e.g. `Delegated`, `Application`, `ManagedIdentity`, `WorkloadIdentity` inside `lex-identity-entra`) now have their actors autobuilt and started.

### Fixed
- `Extensions::Helpers::Base#full_path` now walks up gem name segments to find the parent gem when a sub-module gem doesn't exist as a standalone gem (e.g. `lex-identity-entra-delegated`).

## [1.9.30] - 2026-05-12

### Changed
- Slimmed agentic pack to only cognitive/coordination extensions; removed non-agentic gems (`lex-audit`, `lex-autofix`, `lex-codegen`, `lex-cost-scanner`, `lex-dataset`, `lex-factory`, `lex-finops`, `lex-governance`, `lex-llm-ledger`, `lex-onboard`, `lex-pilot-infra-monitor`, `lex-pilot-knowledge-assist`, `lex-prompt`, `lex-react`, `lex-swarm`, `lex-swarm-github`, `lex-transformer`).
- Added `legion-mcp` to the LLM pack.
- Added `lex-kerberos` to the identity pack.
- Added new `developer` pack: `lex-developer`, `lex-dynatrace`, `lex-eval`, `lex-exec`, `lex-github`, `lex-http`, `lex-jfrog`, `lex-skill-superpowers`, `lex-ssh`.

## [1.9.29] - 2026-05-11

### Fixed
- `Subscription#activate` now checks `channel.open?` before calling `subscribe_with`; if closed, it re-prepares once and retries, preventing silent activation failures when a channel is closed between prepare and activate.
- `Transport` mixin now guards `auto_create_dlx_exchange` and `auto_create_dlx_queue` with a `remote_invocable?` check — non-remote extensions no longer attempt to create dead-letter exchanges and queues they never use.
- DLX exchange type corrected from `fanout` to `topic` for consistency with the rest of the exchange topology.
- Identity resolver DB persistence now uses Sequel models (`Identity::Provider`, `Identity::Principal`, `Identity::Identity`, `Identity::AuditLog`) instead of raw `Legion::Data.db` dataset calls that didn't exist on the module.
- Identity audit API endpoint now references correct column names (`detail_payload`, `node_ref`, `session_ref`) matching the schema.
- Fixed `LeaseRenewer#log_renewal_failure` to fall back to `$stderr` when `Legion::Logging` is not yet loaded, matching the original contract.
- Fixed `Legion::Service#log_privacy_mode_status`, `#shutdown_component`, and TLS-fallback logging specs to assert against `emit_tagged` (the actual dispatch path used by `Legion::Logging::Helper`) rather than `Legion::Logging.warn/info` directly.
- Fixed `Cluster::Leader` boot integration spec to stub `Legion::Settings[:logging]` so `log` helper initialization does not raise on unexpectedly-received arguments.
