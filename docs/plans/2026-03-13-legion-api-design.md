# Legion API Design

## Overview

Full REST API for LegionIO, expanding the existing `Legion::API` Sinatra app.
Exposes tasks, extensions, runners, functions, nodes, schedules, settings, events,
transport status, and hooks via properly nested REST resources under `/api/`.

No URL versioning. Design it right, evolve additively.

## Endpoints

### Health & Readiness (existing, moved under /api/)
- `GET /api/health` - Service health
- `GET /api/ready` - Component readiness

### Tasks
- `GET    /api/tasks`          - List tasks (paginated, filterable by status)
- `POST   /api/tasks`          - Create/trigger task (shorthand invoke)
- `GET    /api/tasks/:id`      - Task detail
- `DELETE /api/tasks/:id`      - Delete task
- `GET    /api/tasks/:id/logs` - Task execution logs

### Extensions (nested: runners, functions)
- `GET /api/extensions`                                              - List loaded
- `GET /api/extensions/:id`                                          - Detail
- `GET /api/extensions/:id/runners`                                  - Runners for ext
- `GET /api/extensions/:id/runners/:rid`                             - Runner detail
- `GET /api/extensions/:id/runners/:rid/functions`                   - Functions for runner
- `GET /api/extensions/:id/runners/:rid/functions/:fid`              - Function detail
- `POST /api/extensions/:id/runners/:rid/functions/:fid/invoke`      - Execute via Ingress

### Nodes
- `GET /api/nodes`      - List cluster nodes
- `GET /api/nodes/:id`  - Node detail

### Schedules (requires legion-data + lex-scheduler)
- `GET    /api/schedules`          - List
- `POST   /api/schedules`          - Create
- `GET    /api/schedules/:id`      - Detail
- `PUT    /api/schedules/:id`      - Update
- `DELETE /api/schedules/:id`      - Delete
- `GET    /api/schedules/:id/logs` - Schedule execution logs

### Relationships (pending data model)
- `GET    /api/relationships`      - List
- `POST   /api/relationships`      - Create
- `GET    /api/relationships/:id`  - Detail
- `PUT    /api/relationships/:id`  - Update
- `DELETE /api/relationships/:id`  - Delete

### Chains (pending data model)
- `GET    /api/chains`      - List
- `POST   /api/chains`      - Create
- `GET    /api/chains/:id`  - Detail
- `PUT    /api/chains/:id`  - Update
- `DELETE /api/chains/:id`  - Delete

### Settings
- `GET /api/settings`      - List all (redacted sensitive values)
- `GET /api/settings/:key` - Get specific setting
- `PUT /api/settings/:key` - Update setting

### Events
- `GET /api/events`        - SSE stream of Legion::Events
- `GET /api/events/recent` - Last N events (polling fallback)

### Transport
- `GET  /api/transport`           - Connection status
- `GET  /api/transport/exchanges` - List exchanges
- `GET  /api/transport/queues`    - List queues
- `POST /api/transport/publish`   - Publish message

### Hooks
- `GET  /api/hooks`                        - List registered hooks
- `POST /api/hooks/:lex_name/:hook_name?`  - Trigger hook (existing)

## Response Envelope

```json
{
  "data": {},
  "meta": { "timestamp": "ISO8601", "node": "node_name" }
}
```

Collections add pagination:
```json
{
  "data": [],
  "meta": { "timestamp": "...", "node": "...", "total": 142, "limit": 25, "offset": 0 }
}
```

Errors:
```json
{
  "error": { "code": "not_found", "message": "..." },
  "meta": { "timestamp": "...", "node": "..." }
}
```

## Authentication

Alpha: no auth. TODO: full auth before production use.
Placeholder middleware at `lib/legion/api/middleware/auth.rb`.

## File Structure

```
LegionIO/lib/legion/
  api.rb                  - Base Sinatra app
  api/
    helpers.rb            - Response envelope, pagination, errors
    tasks.rb
    extensions.rb
    nodes.rb
    schedules.rb
    relationships.rb
    chains.rb
    settings.rb
    events.rb
    transport.rb
    hooks.rb
    middleware/
      auth.rb             - TODO: auth middleware
```

## Dependencies

Already in gemspec: sinatra >= 4.0, puma >= 6.0.
No new dependencies required.

## TODO

- [ ] Full authentication middleware (JWT via legion-crypt, API keys)
- [ ] Rate limiting
- [ ] Request logging middleware
- [ ] OpenAPI/Swagger spec generation
- [ ] Websocket support for events (alternative to SSE)
