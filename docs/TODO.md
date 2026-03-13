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
- [ ] Add `frozen_string_literal: true` to all Ruby files (core gems + core LEXs)
- [ ] Update Dockerfile (`ruby:3.4-alpine`, `--yjit` instead of `--jit`)

### Bugs: legion-transport (from protocol spec review)
- [ ] `app_id` and `user_id` defined but not passed to `publish()` call
- [ ] `correlation_id` always returns nil (should link subtasks to parent task_id)
- [ ] Duplicate `LexRegister` class in `messages/extension.rb` and `messages/lex_register.rb` (remove `extension.rb`)
- [ ] Header `.to_s` stringification overwrites typed JSON body values on consumer merge
- [ ] Task routing_key has redundant fallbacks (`function`, `function_name`, `name`) - consolidate to `function`
- [ ] Payload leaks transport metadata (filter `@options` to separate envelope from business data)
- [ ] DLX exchanges declared in queue args but never created (rejected messages silently dropped)
- [ ] `NodeCrypt#queue_name` returns `'node.status'` (copy-paste bug, should be `'node.crypt'`)
- [ ] Priority always 0 despite queues supporting 0-255 (allow per-message priority via options)
- [ ] No per-message encryption control (only global toggle, need per-message option)

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
