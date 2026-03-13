# LegionIO Wire Protocol Specification

Version: 1.1.0-draft

This document defines the message format and communication patterns used by LegionIO over AMQP 0.9.1. Any process that speaks this protocol can participate as a Legion Extension (LEX), regardless of programming language.

## Transport Layer

- **Protocol**: AMQP 0.9.1
- **Default Broker**: RabbitMQ
- **Serialization**: JSON (content type `application/json`)
- **Encoding**: `identity` (plaintext), `encrypted/cs` (AES-256-CBC cluster secret), or `encrypted/pk` (public key)
- **Exchange Type**: Topic (supports routing key pattern matching)
- **Queue Properties**: Durable, manual ack, priority 0-255, dead-letter exchange

## Topology

### Naming Convention

The **LEX name** is the central naming primitive. It drives exchange names, queue names, and routing keys.

```
Exchange:    {lex_name}                      e.g., http, redis, conditioner
Queue:       {lex_name}.{runner_name}        e.g., http.http, redis.item, conditioner.rule
Routing Key: {lex_name}.{runner_name}.{function}  e.g., http.http.get, redis.item.set
```

`runner_name` is the snake_cased last segment of the runner module name (e.g., `Legion::Extensions::Http::Runners::Http` → `http`, `Legion::Extensions::Redis::Runners::Item` → `item`).

Both exchange and queue names are derived from position `[2]` in the `Legion::Extensions::{LexName}::...` namespace hierarchy. The namespace IS the topology definition.

The exchange name IS the LEX name. Each LEX gets exactly one exchange. Each runner within a LEX gets its own queue bound to that exchange.

### Exchanges

All exchanges are `topic` type, `durable: true`, `auto_delete: false`.

| Exchange | Purpose |
|----------|---------|
| `task` | Task execution, status updates, logging, subtask checks |
| `node` | Node heartbeat, health, cluster secret exchange |
| `extensions` | Extension registration and management |
| `{lex_name}` | Per-LEX exchange (auto-created when LEX loads) |
| `{lex_name}.dlx` | Dead-letter exchange per LEX |

### Queues

All queues are created with these defaults:

| Property | Default | Description |
|----------|---------|-------------|
| `durable` | `true` | Survives broker restart |
| `manual_ack` | `true` | Explicit acknowledgment required |
| `exclusive` | `false` | Shared across consumers |
| `auto_delete` | `false` | Persists when no consumers |
| `x-max-priority` | `255` | Full priority range (0-255) |
| `x-overflow` | `reject-publish` | Backpressure: rejects new messages when full |
| `x-dead-letter-exchange` | `{lex_name}.dlx` | Routes rejected/expired messages |

### Queue Bindings

Queues bind to their LEX exchange with two routing key patterns:

```
1. {runner_name}           - Exact runner match
2. {lex_name}.{runner_name}.# - Full qualified with wildcard
```

This allows messages to be routed by either short or fully-qualified routing keys.

### Consumer Tags

Format: `{node_name}_{lex_name}_{runner_name}_{thread_id}`

Example: `worker-01_http_get_47302847201840`

## Message Envelope

Every message consists of AMQP properties (metadata) and a JSON body (payload).

### AMQP Properties

| Property | Type | Required | Description |
|----------|------|----------|-------------|
| `routing_key` | string | yes | Determines which queue receives the message |
| `content_type` | string | yes | `application/json` |
| `content_encoding` | string | yes | `identity`, `encrypted/cs`, or `encrypted/pk` |
| `type` | string | yes | Message type (currently always `task`) |
| `priority` | integer | no | 0-255, default 0 |
| `persistent` | boolean | no | Survive broker restart, default `true` |
| `message_id` | string | no | Unique message ID (typically the `task_id`) |
| `app_id` | string | yes | `legion` |
| `user_id` | string | no | RabbitMQ authenticated user |
| `correlation_id` | string | no | Links response to originating request |
| `reply_to` | string | no | Queue name for response routing |
| `timestamp` | integer | yes | Unix epoch seconds |
| `expiration` | string | no | Message TTL in milliseconds |
| `headers` | table | yes | Orchestration metadata (see below) |

### AMQP Headers

Headers carry task orchestration metadata for AMQP-level routing and filtering without deserializing the body. All header values are strings (converted via `.to_s` at publish time).

| Header | Description |
|--------|-------------|
| `task_id` | Unique identifier for this task execution |
| `parent_id` | task_id of the immediate parent task |
| `master_id` | task_id of the root task in a chain |
| `chain_id` | Identifier for the entire task chain |
| `relationship_id` | Relationship definition that triggered this task |
| `function_id` | Database ID of the function being called |
| `function` | Function name (e.g., `get`, `send_message`) |
| `runner_namespace` | Runner identifier (e.g., `legion::extensions::http::runners::get`) |
| `runner_class` | Runner class path (e.g., `Legion::Extensions::Http::Runners::Get`) |
| `namespace_id` | Database ID of the runner namespace |
| `trigger_namespace_id` | Namespace ID of the triggering extension |
| `trigger_function_id` | Function ID that triggered this task |
| `debug` | Enable debug logging for this task |

Headers are populated from the message options hash. Only keys that exist in the options are promoted to headers. Missing keys are omitted entirely (not set to nil).

### Encryption Headers

When encryption is active, additional headers are set:

| `content_encoding` | Additional Header | Description |
|-------------------|-------------------|-------------|
| `encrypted/cs` | `iv` | AES-256-CBC initialization vector |
| `encrypted/pk` | `public_key` | Public key for asymmetric decryption |

## Message Body (Payload)

The body is a JSON-serialized hash, optionally encrypted before transmission. The structure varies by message type.

### Payload vs Headers Relationship

Some fields appear in both the payload body and AMQP headers. Headers exist for AMQP-level routing and filtering; the payload carries the complete message. On the consumer side, headers are merged into the parsed payload hash (see Consumer Processing below).

## Message Types

### 1. Task Message

The primary message type. Requests execution of a function on a runner.

**Exchange**: Per-LEX exchange (e.g., `http`)
**Routing Key**: `{lex_name}.{runner}.{function}` or `{runner}.{function}`

```json
{
  "function": "get",
  "runner_class": "Legion::Extensions::Http::Runners::Get",
  "args": {
    "url": "https://example.com/api",
    "method": "GET",
    "headers": {}
  },
  "task_id": 12345,
  "parent_id": 12344,
  "master_id": 12340
}
```

**Required fields:**
- `function` (string): The function to execute

**Optional fields:**
- `args` (object): Arguments passed to the function
- `runner_class` (string): Identifies which runner handles this
- `task_id` (integer): Unique task identifier
- `parent_id` (integer): Parent task in chain
- `master_id` (integer): Root task in chain
- `relationship_id` (integer): Relationship that triggered this
- `debug` (boolean): Enable debug mode

**Routing key resolution** (first match wins):
1. If `conditions` present: `task.subtask.conditioner` (routed to conditioner first)
2. If `transformation` present: `task.subtask.transform` (routed to transformer first)
3. Explicit `routing_key` in options
4. `{queue}.{function}` from options

### 2. SubTask Message

Routes a task through the conditioner or transformer before execution.

**Exchange**: `task`
**Routing Key**: `task.subtask.conditioner` or `task.subtask.transform`

```json
{
  "transformation": "{\"template\": \"<%= results['message'] %>\"}",
  "conditions": "{\"all\":[{\"fact\":\"status\",\"operator\":\"equal\",\"value\":\"critical\"}]}",
  "results": "{\"status\":\"critical\",\"host\":\"web-01\"}"
}
```

**Fields:**
- `transformation` (string): JSON-encoded ERB template definition
- `conditions` (string): JSON-encoded rule set
- `results` (string): JSON-encoded results from previous task

**Conditions format:**
```json
{
  "all": [
    { "fact": "field_name", "operator": "equal", "value": "expected" }
  ],
  "any": [
    { "fact": "field_name", "operator": "greater_than", "value": 100 }
  ]
}
```

**Supported operators**: `equal`, `not_equal`, `greater_than`, `less_than`, `greater_than_or_equal`, `less_than_or_equal`, `contains`, `not_contains`, `starts_with`, `ends_with`, `matches` (regex)

**Transformation format:**
ERB templates with access to the `results` hash:
```erb
Alert: <%= results['message'] %> on host <%= results['hostname'] %>
```

### 3. Dynamic Task Message

A task resolved by database function ID rather than explicit routing.

**Exchange**: Resolved from database (function -> runner -> extension -> exchange name)
**Routing Key**: `{extension}.{runner}.{function}` (resolved from database)

```json
{
  "args": { "url": "https://example.com" },
  "function": "get"
}
```

The exchange and routing key are resolved at publish time by looking up `function_id` in the database to walk: function -> runner -> extension -> exchange name.

### 4. Task Status Update

Reports task execution status.

**Exchange**: `task`
**Routing Key**: `task.update`

```json
{
  "task_id": 12345,
  "status": "task.completed"
}
```

**Valid statuses:**

| Status | Phase | Description |
|--------|-------|-------------|
| `task.scheduled` | pre-execution | Task is scheduled for future execution |
| `task.delayed` | pre-execution | Task is delayed |
| `task.queued` | pre-execution | Task is in queue awaiting execution |
| `task.completed` | post-execution | Task finished successfully |
| `task.exception` | post-execution | Task failed with an error |
| `conditioner.queued` | conditioner | Condition check is queued |
| `conditioner.failed` | conditioner | Condition evaluated to false |
| `conditioner.exception` | conditioner | Condition check raised an error |
| `transformer.queued` | transformer | Transformation is queued |
| `transformer.succeeded` | transformer | Transformation completed |
| `transformer.exception` | transformer | Transformation raised an error |

### 5. Task Log Entry

Appends a log entry to a task's execution history.

**Exchange**: `task`
**Routing Key**: `task.logs.create.{task_id}`

```json
{
  "task_id": 12345,
  "function": "add_log",
  "runner_class": "Legion::Extensions::Tasker::Runners::Log",
  "entry": { "message": "Request completed with status 200" }
}
```

### 6. Check Subtask

Published after a task completes to check if downstream subtasks should fire.

**Exchange**: `task`
**Routing Key**: `task.subtask.check`

```json
{
  "runner_class": "Legion::Extensions::Http::Runners::Get",
  "function": "get",
  "result": { "status": 200, "body": "OK" },
  "original_args": { "url": "https://example.com" },
  "task_id": 12345,
  "parent_id": 12344
}
```

### 7. Extension Registration

Published when an extension starts up. Registers its runners and functions with the cluster.

**Exchange**: `extensions`
**Routing Key**: `extension_manager.register.save`

```json
{
  "function": "save",
  "runner_namespace": "Legion::Extensions::Http::Runners::Get",
  "extension_namespace": "Legion::Extensions::Http",
  "opts": {
    "http": {
      "extension": "legion::extensions::http",
      "extension_name": "http",
      "runner_name": "get",
      "runner_class": "Legion::Extensions::Http::Runners::Get",
      "class_methods": {
        "get": { "args": [["keyreq", "url"], ["key", "headers"]] },
        "post": { "args": [["keyreq", "url"], ["keyreq", "body"], ["key", "headers"]] }
      }
    }
  }
}
```

The `class_methods` object describes each callable function and its parameter signature:
- `keyreq`: Required keyword argument
- `key`: Optional keyword argument
- `req`: Required positional argument
- `opt`: Optional positional argument
- `rest`: Splat argument

### 8. Cluster Secret Request

Published by a new node to request the cluster encryption secret from an existing node.

**Exchange**: `node`
**Routing Key**: `node.crypt.push_cluster_secret`

```json
{
  "function": "push_cluster_secret",
  "node_name": "worker-02",
  "queue_name": "node.worker-02",
  "runner_class": "Legion::Extensions::Node::Runners::Crypt",
  "public_key": "-----BEGIN PUBLIC KEY-----\n..."
}
```

This message is never encrypted (the requesting node doesn't have the cluster secret yet).

## Consumer Processing

When a Subscription actor receives a message, it processes it through these steps:

### 1. Decryption

Based on `content_encoding`:

| Value | Action |
|-------|--------|
| `identity` | No decryption needed |
| `encrypted/cs` | AES-256-CBC decrypt using cluster secret + `headers['iv']` |
| `encrypted/pk` | Public key decrypt using `headers[:public_key]` |

### 2. Deserialization

Based on `content_type`:

| Value | Action |
|-------|--------|
| `application/json` | Parse JSON into Ruby hash |
| anything else | Wrap in `{ value: raw_payload }` |

### 3. Header Merge

AMQP headers are merged into the parsed message hash with symbol keys:
```ruby
message = message.merge(metadata.headers.transform_keys(&:to_sym))
```

### 4. Metadata Enrichment

- `routing_key` from `delivery_info` is added to the message
- `timestamp_in_ms` is normalized to `timestamp` (seconds)
- `datetime` is derived from `timestamp` as ISO 8601 string

### 5. Function Resolution

The function to call is determined (first match wins):
1. Actor-defined `runner_function` (if the actor overrides it)
2. Actor-defined `function` method
3. Actor-defined `action` method
4. `message[:function]` from the payload

### 6. Execution

```
Legion::Runner.run(
  runner_class:  <resolved runner>,
  function:      <resolved function>,
  check_subtask: <actor setting>,
  generate_task: <actor setting>,
  **message
)
```

### 7. Acknowledgment

- **Success**: `queue.acknowledge(delivery_tag)`
- **Exception**: `queue.reject(delivery_tag)` (no requeue by default)

## Task Execution Lifecycle

```
1. Message arrives on queue
2. Consumer reads (delivery_info, metadata, payload)
3. Decrypt body if content_encoding indicates encryption
4. Parse JSON body
5. Merge AMQP headers into message hash (symbol keys)
6. Add routing_key to message
7. Normalize timestamp/datetime fields
8. Determine function to call
9. Execute via Runner.run():
   a. Generate task_id in DB (if connected and generate_task is true)
   b. Call runner_class.send(function, **message)
   c. On success: status = "task.completed"
   d. On exception: status = "task.exception"
   e. Update task status (DB direct or TaskUpdate message)
   f. If check_subtask enabled: publish CheckSubtask with results
10. ACK on success, REJECT on failure
```

## Task Chaining Flow

```
                    publish Task
                         |
                         v
               +--- has conditions? ---+
               | yes                   | no
               v                       |
        route to conditioner           |
               |                       |
          +----+----+                  |
          | pass    | fail             |
          v         v                  |
          |    status:                 |
          |    conditioner.failed      |
          |         (stop)             |
          |                            |
          +----------------------------+
          v                            v
    +--- has transformation? ----------+
    | yes                              | no
    v                                  |
 route to transformer                  |
    |                                  |
    v                                  v
 execute function <--------------------+
    |
    +-- status: task.completed
    |
    v
 check_subtask?
    | yes
    v
 publish CheckSubtask (with results)
    |
    v
 lex-tasker looks up relationships
    |
    v
 publish downstream Task(s) for each relationship
```

## Writing a LEX in Any Language

To implement a Legion Extension in a non-Ruby language:

### 1. Connect to RabbitMQ

Use any AMQP 0.9.1 client library for your language.

### 2. Declare Your Topology

```
Exchange: {lex_name}       (type: topic, durable: true)
Exchange: {lex_name}.dlx   (type: topic, durable: true)
Queue:    {lex_name}.{runner_name}  (durable, manual ack, priority 255)
Bind:     queue -> exchange with routing_key: {runner_name}
Bind:     queue -> exchange with routing_key: {lex_name}.{runner_name}.#
```

### 3. Subscribe to Your Queue

```
consumer_tag: {node_name}_{lex_name}_{runner_name}_{thread_id}
manual_ack: true
prefetch: 2 (recommended)
```

### 4. Process Messages

```
1. Read AMQP properties and headers
2. Decrypt body based on content_encoding:
   - "identity": no decryption
   - "encrypted/cs": AES-256-CBC with cluster secret and headers["iv"]
   - "encrypted/pk": public key decrypt with headers["public_key"]
3. Parse JSON body
4. Merge headers into message hash
5. Read function name from message["function"] or headers["function"]
6. Execute the function with message contents as arguments
7. ACK the message on success, REJECT on failure
```

### 5. Report Results

Publish a Task Status Update to exchange `task` with routing key `task.update`:
```json
{
  "task_id": "<from incoming message>",
  "status": "task.completed"
}
```

To trigger downstream tasks, publish a CheckSubtask to exchange `task` with routing key `task.subtask.check`:
```json
{
  "runner_class": "your_extension.your_runner",
  "function": "your_function",
  "result": { "your": "output" },
  "original_args": { "the": "input" },
  "task_id": "<from incoming message>"
}
```

### 6. Register Your Extension (Optional)

Publish an Extension Registration message to exchange `extensions` with routing key `extension_manager.register.save` to announce your capabilities to the cluster.

## Known Issues and Planned Fixes

The following were known bugs. Most have been fixed as of 2026-03-12.

### Fixed

- **`app_id` and `correlation_id` now published** — Both passed to `publish()` call. `correlation_id` derives from `parent_id` or `task_id`.
- **Duplicate `LexRegister` removed** — `messages/extension.rb` deleted.
- **Header values preserve native types** — Integer, Float, Boolean stay typed; only others get `.to_s`.
- **Task routing_key consolidated** — Uses `function` only. `function_name`/`name` fallbacks removed.
- **Base `message` method filters `ENVELOPE_KEYS`** — Payload no longer contains transport metadata.
- **DLX exchanges auto-declared** — `ensure_dlx` creates dead-letter exchanges before queue creation.
- **`NodeCrypt#queue_name` fixed** — Returns `'node.crypt'` (was `'node.status'`).
- **Priority reads from options** — `@options[:priority]` then settings, falls back to 0.
- **Per-message `encrypt:` option** — Overrides global toggle per-message.

### Remaining Gaps

- Priority levels are not yet standardized for system vs user messages
- No automatic DLQ consumer for inspecting rejected messages
