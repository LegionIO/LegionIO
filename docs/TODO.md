# LegionIO Modernization Tracker

## Completed

- [x] Ruby 3.4 minimum across all 34 gemspecs
- [x] Git remotes consolidated to github.com/LegionIO
- [x] Gemspec URLs updated (Optum, Bitbucket, Atlassian -> LegionIO GitHub)
- [x] Optum corporate boilerplate removed (CODE_OF_CONDUCT, CONTRIBUTING, NOTICE, SECURITY, ICL, attribution, sourcehawk)
- [x] Optum email removed from gemspec contacts
- [x] Copyright updated to Esity in all LICENSE files
- [x] Author name normalized to Esity
- [x] LegionIO/README.md updated (Atlassian wiki links, /src/master/ paths)
- [x] sourcehawk-scan.yml CI workflows deleted
- [x] CLAUDE.md documentation created for all 34 repos
- [x] docs/protocol.md - wire protocol specification
- [x] docs/overview.md - core framework overview
- [x] CI: GitHub Actions `ci.yml` deployed to all 34 repos (rubocop + rspec on every push/PR)
- [x] `.rubocop.yml` updated to Ruby 3.4 + `frozen_string_literal: true` enabled across all 34 repos
- [x] Old CI deleted: bitbucket-pipelines.yml, .travis.yml, rubocop-analysis.yml, gems_push.yml (42 files)
- [x] All 34 README.md files rewritten (consistent format, Ruby 3.4, no JRuby, no stale boilerplate)
- [x] Fix stale `changelog_uri` paths in gemspecs (`/src/main/` -> `/blob/main/`)
- [x] Remove JRuby/MarchHare code paths (legion-transport, legion-settings, legion-data, LegionIO)
- [x] Update dependency version floors to Ruby 3.4-compatible versions (13 gemspecs across core gems + LEXs)
- [x] Fix `messsages` typo in legion-transport settings (triple s -> double s)
- [x] Fix legion-data to support SQLite, PostgreSQL, and MySQL (adapter-driven via settings)
- [x] Remove sleep hacks in `LegionIO/lib/legion/service.rb` (replaced with `Legion::Readiness`)
- [x] Remove TruffleRuby guard from service.rb
- [x] Structured JSON logging (`format: :json` in legion-logging)
- [x] Webhook hook system and Sinatra API (`Legion::API`, `Legion::Extensions::Hooks::Base`)

## In Progress

### Change: Fix and Clean
- [x] Add `frozen_string_literal: true` to all Ruby files (already done via rubocop -A)
- [x] Update Dockerfile (`ruby:3.4-alpine`, `--yjit` instead of `--jit`)

### Bugs: legion-transport (from protocol spec review) - ALL FIXED
- [x] `app_id` and `correlation_id` now passed to `publish()` call; `app_id` method fixed
- [x] `correlation_id` derives from `parent_id` or `task_id` (links subtasks to parent)
- [x] Duplicate `LexRegister` removed (`messages/extension.rb` deleted)
- [x] Header values preserve native types (Integer, Float, Boolean); only others get `.to_s`
- [x] Task routing_key consolidated to `function` only (removed `function_name`/`name` fallbacks)
- [x] Base `message` method filters `ENVELOPE_KEYS` from payload
- [x] DLX exchanges auto-declared via `ensure_dlx` before queue creation
- [x] `NodeCrypt#queue_name` fixed: `'node.crypt'` (was `'node.status'`)
- [x] Priority reads from `@options[:priority]` then settings, falls back to 0
- [x] Per-message `encrypt:` option overrides global toggle

### Add: New Functionality

- [ ] Test coverage: legion-json
  - [ ] JSON load/dump
  - [ ] Symbolized keys default
  - [ ] Edge cases (nil, empty, nested)
  - [ ] Error handling (InvalidJson, ParseError)
- [ ] Test coverage: legion-settings
  - [ ] File loading
  - [ ] Directory loading
  - [ ] Env var overrides
  - [ ] Deep merge behavior
  - [ ] Auto-load on access
- [ ] Test coverage: core LEXs
  - [ ] lex-conditioner (all/any/fact/operator rule engine)
  - [ ] lex-transformer (ERB template rendering)
  - [ ] lex-scheduler (cron parsing, interval, distributed lock)
  - [ ] lex-node (node identity registration)
  - [ ] lex-tasker (task management)
- [ ] CLI: schedule management commands
  - [ ] `legion schedule list`
  - [ ] `legion schedule add`
  - [ ] `legion schedule remove`

### Architecture: Pre-Web/API Foundations
- [x] Event bus (`Legion::Events`) for in-process pub/sub
  - [x] Lifecycle hooks (service.ready, service.shutting_down, extension.loaded)
  - [x] Runner events (task.completed, task.failed)
- [x] Transport abstraction layer (`Legion::Ingress`)
  - [x] Source-agnostic entry point for runner invocation (normalize + run)
  - [x] AMQP subscription unchanged (handles encryption, ack/reject)
  - [x] HTTP adapter for webhooks/API (uses Ingress.run via Legion::API)
- [ ] Configuration validation in legion-settings
  - [ ] Schema definitions per module (required keys, types)
  - [ ] Fail-fast on startup with clear error messages

## Core Components Reference

**Core Gems (8):** legion-json, legion-logging, legion-settings, legion-crypt, legion-transport, legion-cache, legion-data, legionio

**Core LEXs (5):** lex-conditioner, lex-transformer, lex-tasker, lex-node, lex-scheduler
