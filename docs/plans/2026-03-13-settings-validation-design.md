# Settings Validation Design

**Date:** 2026-03-13
**Status:** Approved
**Scope:** legion-settings gem

## Problem

Configuration errors surface as runtime exceptions deep in the call stack. A typo in a JSON config file or a wrong type causes cryptic failures minutes after startup. There is no schema system — modules provide defaults and hope users don't break them.

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Schema source | Convention from defaults + optional overrides | Defaults already encode 90% of type info. Zero effort for common case. |
| Validation timing | Per-module on merge + cross-module on startup | Catches errors early per-module; cross-dependencies validated once all modules registered. |
| Failure mode | Collect all errors, raise once | Users see every problem at once instead of fix-one-rerun cycles. |
| Unknown keys | Warn at top-level and first-level nesting | Catches typos like `:trasport` without being noisy about deep extension keys. |
| Module isolation | LEX can read all, write only own namespace. Core gems unrestricted. | Prevents extensions from interfering with each other's settings. |

**Future TODO:** Dev mode that warns-but-continues instead of raising (configurable via `Legion::Settings[:validation][:mode]`).

## Architecture

### Type Inference

`Schema` walks a module's defaults hash and infers type constraints from values:

| Default Value | Inferred Type |
|---------------|---------------|
| `'guest'` | `:string` |
| `5672` | `:integer` |
| `true`/`false` | `:boolean` |
| `nil` | `:any` (no enforcement unless overridden) |
| `{}` | `:hash` |
| `[]` | `:array` |

### Schema Storage

Nested hashes mirroring the settings structure:

```ruby
{
  transport: {
    connection: {
      host: { type: :string },
      port: { type: :string }
    },
    messages: {
      encrypt: { type: :boolean }
    }
  }
}
```

### Validation Flow

**Pass 1 — Per-module on merge:**
1. `merge_settings('transport', defaults)` triggers schema inference from defaults
2. If `define_schema('transport', overrides)` was called, overrides layer on top
3. Current user-provided values for `:transport` validated against schema
4. Errors collected into `@loader.errors`

**Pass 2 — Cross-module on startup:**
1. `Legion::Settings.validate!` called during `Legion::Service` startup
2. Re-validates all modules
3. Runs registered cross-module validation blocks
4. Checks for unknown top-level and first-level keys (with typo suggestions)
5. Raises `Legion::Settings::ValidationError` if errors exist

### Access Model

| Actor | Read | Write Schema | Write Values |
|-------|------|-------------|-------------|
| Core gem | All settings | Own key | Any key |
| LEX extension | All settings | Own key | Own key only |

### Cross-Module Validation

Self-service registration — any gem can add rules without changing legion-settings:

```ruby
Legion::Settings.add_cross_validation do |settings, errors|
  if settings[:transport][:messages][:encrypt] && !settings[:crypt][:vault][:enabled]
    errors << { module: :transport, path: "messages.encrypt",
                message: "requires crypt.vault.enabled to be true" }
  end
end
```

### Error Reporting

Single `ValidationError` raised with all collected problems:

```
Legion::Settings::ValidationError: 3 configuration errors detected:

  [transport] connection.host: expected String, got Integer (42)
  [cache] driver: expected one of ["dalli", "redis"], got "memcache"
  [unknown_key] top-level key :trasport is not registered (did you mean :transport?)
```

Each error is a hash: `{ module: :sym, path: "dotted.path", message: "description" }`

The `errors` array on `Loader` is public for programmatic access.

### Unknown Key Detection

Top-level and first-level keys not registered by any module trigger warnings. If a key is within edit distance 2 of a known key, suggest the correction.

## File Changes

**New files (legion-settings):**
- `lib/legion/settings/schema.rb` — Type inference, override storage, validation
- `lib/legion/settings/validation_error.rb` — Exception class

**Modified files (legion-settings):**
- `lib/legion/settings.rb` — Add `define_schema`, `add_cross_validation`, `validate!`, `errors`
- `lib/legion/settings/loader.rb` — Hook schema inference into `load_module_settings`, replace broken `validate`

**Deleted files:**
- `lib/legion/settings/validators/legion.rb` — Replaced by schema system

## Public API

| Method | Purpose |
|--------|---------|
| `merge_settings(key, defaults)` | Existing. Now also triggers schema inference. |
| `define_schema(key, overrides)` | Optional. Layer explicit constraints on inferred types. |
| `add_cross_validation(&block)` | Register cross-module validation rule. |
| `validate!` | Run all validations, raise `ValidationError` if errors. |
| `errors` | Read-only access to collected errors array. |

## Constraints

- No LEX or core gem should require a PR to legion-settings to register its schema — self-service only
- LEX extensions cannot write to another extension's settings namespace
- Core gems identified by known key set: `[:transport, :cache, :crypt, :data, :logging, :client]`
