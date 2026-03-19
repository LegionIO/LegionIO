# Hooks Expansion Design

## Summary

Expand the existing hooks system to support GET + POST, extension-derived URL paths, and runner-controlled responses. Removes hardcoded extension routes from LegionIO (starting with `api/oauth.rb`) by letting extensions own their HTTP surface through the existing `hooks/` convention.

## Problem

Extensions that need HTTP endpoints (OAuth callbacks, webhooks, status pages) currently require hardcoded routes in LegionIO's `api/` directory. The `api/oauth.rb` file knows about Microsoft Teams specifically. This couples LegionIO to individual extensions and bypasses the Ingress pipeline (no RBAC, no audit, no events).

The hooks system already handles inbound webhooks with auto-discovery, verification DSL, and Ingress routing — but it only supports POST and always returns JSON.

## Approach

Expand the existing hooks infrastructure. No new module types, no new DSL classes. Three changes:

1. Add GET alongside POST in `api/hooks.rb`
2. Add a `mount` class method to `Hooks::Base` for sub-path suffixes
3. Add response control so runners can return HTML/redirects instead of JSON

## URL Derivation

The full URL is deterministic and non-overridable:

```
/api/hooks/lex/{extension_name}/{hook_class_name}{mount_suffix}
     fixed      from module       from class name   optional DSL
```

- `extension_name` — derived from Ruby module hierarchy. `Legion::Extensions::MicrosoftTeams` becomes `microsoft_teams`. Cannot be overridden.
- `hook_class_name` — derived from the hook class name. `Hooks::Auth` becomes `auth`. Cannot be overridden.
- `mount_suffix` — optional, declared via `mount '/callback'` in the hook class. Appended after the class name segment.

Examples:

| Hook class | mount | URL |
|-----------|-------|-----|
| `MicrosoftTeams::Hooks::Auth` | `'/callback'` | `/api/hooks/lex/microsoft_teams/auth/callback` |
| `MicrosoftTeams::Hooks::Webhook` | none | `/api/hooks/lex/microsoft_teams/webhook` |
| `Github::Hooks::Push` | none | `/api/hooks/lex/github/push` |
| `Slack::Hooks::Events` | `'/interactive'` | `/api/hooks/lex/slack/events/interactive` |

The extension name prefix acts as a namespace fence — extensions can only define routes under their own name. No collisions.

## HTTP Method Support

Both GET and POST route to the same handler method. The runner receives a normalized request hash:

```ruby
{
  http_method: 'GET',
  params: { code: '...', state: '...' },
  headers: { 'HTTP_HOST' => '...' },
  body: nil
}
```

For GET requests, `params` comes from query string. For POST, `params` is the parsed body. `body` contains the raw POST body (needed for HMAC verification). `headers` are the Rack-normalized request headers.

The API handler:

```ruby
app.get '/api/hooks/lex/:lex_name/*' do
  handle_hook_request(params, request)
end

app.post '/api/hooks/lex/:lex_name/*' do
  handle_hook_request(params, request)
end
```

Both call the same `handle_hook_request` private method that resolves the hook, verifies, and pipes through `Ingress.run`.

## Response Control

If the runner result hash contains a `:response` key, the API layer renders it directly. Otherwise, the default JSON task response.

```ruby
# Runner returning a custom response (OAuth callback):
def auth_callback(code:, state:, **)
  # ... token exchange logic ...
  {
    result: { authenticated: true },
    response: {
      status: 200,
      content_type: 'text/html',
      body: '<html><body><h2>Authentication complete</h2></body></html>'
    }
  }
end
```

API handler logic:

```ruby
result = Ingress.run(...)
if result[:response]
  status result[:response][:status] || 200
  content_type result[:response][:content_type] || 'application/json'
  result[:response][:body]
else
  json_response({ task_id: result[:task_id], status: result[:status] })
end
```

The `result` key alongside `response` means the task system still captures the outcome for audit/logging even when the HTTP response is HTML. If `:response` is absent, behavior is identical to today.

## Hooks::Base Changes

One new class method:

```ruby
class Base
  class << self
    def mount(path)
      @mount_path = path
    end

    attr_reader :mount_path
  end
end
```

Existing DSL unchanged: `route_header`, `route_field`, `verify_hmac`, `verify_token` all still work. They operate on the request after URL routing, same as today.

For hooks that handle both GET callbacks and POST webhooks on the same path, the existing `route` method can inspect the HTTP method from the payload to decide which runner function to call. Or the runner can handle both in a single method.

## Builder Changes

`builders/hooks.rb` `build_hook_list` currently registers hooks keyed by `"lex_name/hook_name"`. Changes:

- Read `hook_class.mount_path` (nil if not declared)
- Build the full route path: `"{extension_name}/{hook_name}{mount_path}"`
- Store the full route path in the registry entry

`find_hook` changes to match against the request splat path instead of discrete lex_name/hook_name params.

## Hook Registry

Current registry on `Legion::API`:

```ruby
register_hook(lex_name:, hook_name:, hook_class:, default_runner:)
```

Add `route_path:` to the registration:

```ruby
register_hook(lex_name:, hook_name:, hook_class:, default_runner:, route_path:)
```

`find_hook` changes from two-param lookup to splat-path matching:

```ruby
def find_hook_by_path(path)
  hook_registry.values.find { |h| h[:route_path] == path }
end
```

## Backward Compatibility

- Hooks without `mount` work exactly as before — filename becomes the hook name, URL is `/api/hooks/lex/{ext}/{hook_name}`
- Old `POST /api/hooks/:lex_name/:hook_name` route stays as deprecated alias pointing to the new handler
- All existing `Hooks::Base` DSL works unchanged
- Extensions that don't define hooks are unaffected

## Migration: api/oauth.rb

The hardcoded Microsoft Teams OAuth callback moves to lex-microsoft_teams:

**New file:** `lex-microsoft_teams/hooks/auth.rb`

```ruby
class Auth < Legion::Extensions::Hooks::Base
  mount '/callback'
end
```

**Runner method** in lex-microsoft_teams handles the callback: receives `code` and `state` params, emits the event, returns HTML response.

**LegionIO:** Remove `require_relative 'api/oauth'` and `register Routes::OAuth` from `api.rb`. Delete or gut `api/oauth.rb`.

## Testing

### LegionIO Specs

- Hooks::Base `mount` sets and reads mount_path
- Builder reads mount_path, builds correct route_path
- API handler resolves hook from splat path (GET and POST)
- API handler renders `:response` when present in runner result
- API handler returns default JSON when `:response` absent
- Backward compat: old `/api/hooks/:lex_name/:hook_name` still works
- Verification (HMAC, token) works on both GET and POST

### lex-microsoft_teams Specs

- Hook class discovered by builder
- OAuth callback runner handles code+state, returns HTML response
- Events emitted on successful callback

## Files Changed

| File | Repo | Change |
|------|------|--------|
| `extensions/hooks/base.rb` | LegionIO | Add `mount` class method |
| `extensions/builders/hooks.rb` | LegionIO | Read mount_path, build full route_path |
| `api/hooks.rb` | LegionIO | Add GET route, splat matching, `handle_hook_request`, response control |
| `api.rb` | LegionIO | Remove `Routes::OAuth`, add backward compat alias |
| `api/oauth.rb` | LegionIO | Delete |
| `hooks/auth.rb` | lex-microsoft_teams | New file |
| Runner (TBD) | lex-microsoft_teams | OAuth callback handler method |
