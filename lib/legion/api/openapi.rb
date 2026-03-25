# frozen_string_literal: true

require 'legion/json'

module Legion
  class API < Sinatra::Base
    module OpenAPI
      META_SCHEMA = {
        type:       'object',
        properties: {
          timestamp: { type: 'string', format: 'date-time' },
          node:      { type: 'string' }
        },
        required:   %w[timestamp node]
      }.freeze

      META_COLLECTION_SCHEMA = {
        type:       'object',
        properties: {
          timestamp: { type: 'string', format: 'date-time' },
          node:      { type: 'string' },
          total:     { type: 'integer' },
          limit:     { type: 'integer' },
          offset:    { type: 'integer' }
        },
        required:   %w[timestamp node total limit offset]
      }.freeze

      ERROR_SCHEMA = {
        type:       'object',
        properties: {
          error: {
            type:       'object',
            properties: {
              code:    { type: 'string' },
              message: { type: 'string' }
            },
            required:   %w[code message]
          },
          meta:  META_SCHEMA
        },
        required:   %w[error meta]
      }.freeze

      PAGINATION_PARAMS = [
        {
          name:        'limit',
          in:          'query',
          description: 'Maximum number of records to return (1-100, default 25)',
          required:    false,
          schema:      { type: 'integer', minimum: 1, maximum: 100, default: 25 }
        },
        {
          name:        'offset',
          in:          'query',
          description: 'Number of records to skip',
          required:    false,
          schema:      { type: 'integer', minimum: 0, default: 0 }
        }
      ].freeze

      NOT_FOUND_RESPONSE = {
        description: 'Not found',
        content:     { 'application/json' => { schema: { '$ref' => '#/components/schemas/ErrorResponse' } } }
      }.freeze

      UNAUTH_RESPONSE = {
        description: 'Unauthorized',
        content:     { 'application/json' => { schema: { '$ref' => '#/components/schemas/ErrorResponse' } } }
      }.freeze

      UNPROCESSABLE_RESPONSE = {
        description: 'Unprocessable entity',
        content:     { 'application/json' => { schema: { '$ref' => '#/components/schemas/ErrorResponse' } } }
      }.freeze

      NOT_IMPL_RESPONSE = {
        description: 'Not implemented',
        content:     { 'application/json' => { schema: { '$ref' => '#/components/schemas/ErrorResponse' } } }
      }.freeze

      def self.spec
        {
          openapi:    '3.1.0',
          info:       info_block,
          servers:    [{ url: 'http://localhost:4567', description: 'Local Legion daemon' }],
          security:   [{ BearerAuth: [] }, { ApiKeyAuth: [] }],
          tags:       tags,
          paths:      paths,
          components: components
        }
      end

      def self.to_json
        require 'json'
        ::JSON.generate(spec)
      end

      # --- private helpers ---

      def self.info_block
        {
          title:       'LegionIO REST API',
          description: 'Async job engine and digital worker platform REST API. ' \
                       'All routes are under the /api/ prefix. ' \
                       'Success responses wrap data in { data: ..., meta: { timestamp:, node: } }. ' \
                       'Error responses use { error: { code:, message: }, meta: ... }.',
          version:     Legion::VERSION,
          contact:     { name: 'LegionIO', url: 'https://github.com/LegionIO/LegionIO' },
          license:     { name: 'Apache-2.0', url: 'https://www.apache.org/licenses/LICENSE-2.0' }
        }
      end
      private_class_method :info_block

      def self.tags
        [
          { name: 'Health',        description: 'Health and readiness probes' },
          { name: 'Tasks',         description: 'Task management and execution' },
          { name: 'Extensions',    description: 'Extension, runner, and function discovery' },
          { name: 'Nodes',         description: 'Node registry' },
          { name: 'Schedules',     description: 'Cron/interval schedule management (requires lex-scheduler)' },
          { name: 'Relationships', description: 'Task relationships (stub, 501)' },
          { name: 'Chains',        description: 'Task chains (stub, 501)' },
          { name: 'Settings',      description: 'Runtime configuration' },
          { name: 'Events',        description: 'SSE event stream and recent event buffer' },
          { name: 'Transport',     description: 'RabbitMQ transport status and publish' },
          { name: 'Hooks',         description: 'Extension webhook endpoints' },
          { name: 'Lex',           description: 'Auto-registered LEX runner routes' },
          { name: 'Workers',       description: 'Digital worker lifecycle management' },
          { name: 'Teams',         description: 'Team-level worker and cost views' },
          { name: 'Coldstart',     description: 'Cold-start memory ingestion (requires lex-coldstart + lex-memory)' },
          { name: 'Gaia',          description: 'Gaia cognitive layer status' },
          { name: 'Apollo',        description: 'Apollo knowledge graph (requires lex-apollo + legion-data)' },
          { name: 'OpenAPI',       description: 'OpenAPI spec endpoint' }
        ]
      end
      private_class_method :tags

      def self.paths
        {}.merge(health_paths)
          .merge(task_paths)
          .merge(extension_paths)
          .merge(node_paths)
          .merge(schedule_paths)
          .merge(relationship_paths)
          .merge(chain_paths)
          .merge(settings_paths)
          .merge(event_paths)
          .merge(transport_paths)
          .merge(hook_paths)
          .merge(lex_paths)
          .merge(worker_paths)
          .merge(team_paths)
          .merge(coldstart_paths)
          .merge(gaia_paths)
          .merge(apollo_paths)
          .merge(openapi_paths)
          .merge(stats_paths)
      end
      private_class_method :paths

      def self.components
        {
          securitySchemes: {
            BearerAuth: {
              type:         'http',
              scheme:       'bearer',
              bearerFormat: 'JWT',
              description:  'Legion-issued JWT token (worker or human scope)'
            },
            ApiKeyAuth: {
              type:        'apiKey',
              in:          'header',
              name:        'X-API-Key',
              description: 'Pre-shared API key'
            }
          },
          schemas:         {
            Meta:               META_SCHEMA,
            MetaCollection:     META_COLLECTION_SCHEMA,
            ErrorResponse:      ERROR_SCHEMA,
            DeletedResponse:    deleted_response_schema,
            TaskObject:         task_object_schema,
            TaskInput:          task_input_schema,
            ExtensionObject:    extension_object_schema,
            RunnerObject:       runner_object_schema,
            FunctionObject:     function_object_schema,
            NodeObject:         node_object_schema,
            ScheduleObject:     schedule_object_schema,
            ScheduleInput:      schedule_input_schema,
            RelationshipObject: stub_object_schema('Relationship'),
            ChainObject:        stub_object_schema('Chain'),
            WorkerObject:       worker_object_schema,
            WorkerInput:        worker_input_schema
          }
        }
      end
      private_class_method :components

      # --- schema helpers ---

      def self.deleted_response_schema
        { type: 'object', properties: { data: { type: 'object', properties: { deleted: { type: 'boolean' } } }, meta: META_SCHEMA } }
      end
      private_class_method :deleted_response_schema

      def self.task_object_schema
        {
          type:       'object',
          properties: {
            id:          { type: 'integer' },
            function_id: { type: 'integer' },
            status:      { type: 'string' },
            payload:     { type: 'object' },
            worker_id:   { type: 'string', nullable: true },
            created_at:  { type: 'string', format: 'date-time' },
            updated_at:  { type: 'string', format: 'date-time' }
          }
        }
      end
      private_class_method :task_object_schema

      def self.task_input_schema
        {
          type:                 'object',
          required:             %w[runner_class function],
          properties:           {
            runner_class:  { type: 'string', description: 'Fully qualified runner class name' },
            function:      { type: 'string', description: 'Runner function name' },
            check_subtask: { type: 'boolean', default: true },
            generate_task: { type: 'boolean', default: true }
          },
          additionalProperties: true
        }
      end
      private_class_method :task_input_schema

      def self.extension_object_schema
        {
          type:       'object',
          properties: {
            id:        { type: 'integer' },
            name:      { type: 'string' },
            namespace: { type: 'string' },
            active:    { type: 'boolean' },
            version:   { type: 'string', nullable: true }
          }
        }
      end
      private_class_method :extension_object_schema

      def self.runner_object_schema
        {
          type:       'object',
          properties: {
            id:           { type: 'integer' },
            extension_id: { type: 'integer' },
            name:         { type: 'string' },
            namespace:    { type: 'string' }
          }
        }
      end
      private_class_method :runner_object_schema

      def self.function_object_schema
        {
          type:       'object',
          properties: {
            id:        { type: 'integer' },
            runner_id: { type: 'integer' },
            name:      { type: 'string' }
          }
        }
      end
      private_class_method :function_object_schema

      def self.node_object_schema
        {
          type:       'object',
          properties: {
            id:         { type: 'integer' },
            name:       { type: 'string' },
            status:     { type: 'string' },
            active:     { type: 'boolean' },
            created_at: { type: 'string', format: 'date-time' }
          }
        }
      end
      private_class_method :node_object_schema

      def self.schedule_object_schema
        {
          type:       'object',
          properties: {
            id:             { type: 'integer' },
            function_id:    { type: 'integer' },
            cron:           { type: 'string', nullable: true },
            interval:       { type: 'integer', nullable: true },
            active:         { type: 'boolean' },
            last_run:       { type: 'string', format: 'date-time' },
            task_ttl:       { type: 'integer', nullable: true },
            payload:        { type: 'string', description: 'JSON-encoded payload' },
            transformation: { type: 'string', nullable: true }
          }
        }
      end
      private_class_method :schedule_object_schema

      def self.schedule_input_schema
        {
          type:       'object',
          required:   %w[function_id],
          properties: {
            function_id:    { type: 'integer' },
            cron:           { type: 'string', description: 'Cron expression (required if interval not given)' },
            interval:       { type: 'integer', description: 'Interval in seconds (required if cron not given)' },
            active:         { type: 'boolean', default: true },
            task_ttl:       { type: 'integer', nullable: true },
            payload:        { type: 'object' },
            transformation: { type: 'string', nullable: true }
          }
        }
      end
      private_class_method :schedule_input_schema

      def self.stub_object_schema(name)
        { type: 'object', description: "#{name} record (schema not yet finalized)", additionalProperties: true }
      end
      private_class_method :stub_object_schema

      def self.worker_object_schema
        {
          type:       'object',
          properties: {
            worker_id:       { type: 'string' },
            name:            { type: 'string' },
            extension_name:  { type: 'string' },
            entra_app_id:    { type: 'string' },
            owner_msid:      { type: 'string' },
            owner_name:      { type: 'string', nullable: true },
            business_role:   { type: 'string', nullable: true },
            risk_tier:       { type: 'string', nullable: true },
            team:            { type: 'string', nullable: true },
            lifecycle_state: { type: 'string' },
            manager_msid:    { type: 'string', nullable: true }
          }
        }
      end
      private_class_method :worker_object_schema

      def self.worker_input_schema
        {
          type:       'object',
          required:   %w[name extension_name entra_app_id owner_msid],
          properties: {
            name:           { type: 'string' },
            extension_name: { type: 'string' },
            entra_app_id:   { type: 'string' },
            owner_msid:     { type: 'string' },
            owner_name:     { type: 'string' },
            business_role:  { type: 'string' },
            risk_tier:      { type: 'string' },
            team:           { type: 'string' },
            manager_msid:   { type: 'string' }
          }
        }
      end
      private_class_method :worker_input_schema

      # --- route path builders ---

      def self.wrap_data(schema_ref)
        {
          type:       'object',
          properties: {
            data: { '$ref' => "#/components/schemas/#{schema_ref}" },
            meta: { '$ref' => '#/components/schemas/Meta' }
          }
        }
      end
      private_class_method :wrap_data

      def self.wrap_collection(schema_ref)
        {
          type:       'object',
          properties: {
            data: { type: 'array', items: { '$ref' => "#/components/schemas/#{schema_ref}" } },
            meta: { '$ref' => '#/components/schemas/MetaCollection' }
          }
        }
      end
      private_class_method :wrap_collection

      def self.json_content(schema)
        { 'application/json' => { schema: schema } }
      end
      private_class_method :json_content

      def self.ok_response(description, schema)
        { description: description, content: json_content(schema) }
      end
      private_class_method :ok_response

      def self.health_paths
        {
          '/api/health' => {
            get: {
              tags:        ['Health'],
              summary:     'Health check',
              description: 'Returns ok status and version. Skips auth middleware.',
              operationId: 'getHealth',
              security:    [],
              responses:   {
                '200' => ok_response('Healthy', wrap_data('TaskObject').merge(
                                                  properties: {
                                                    data: {
                                                      type:       'object',
                                                      properties: { status: { type: 'string', example: 'ok' }, version: { type: 'string' } }
                                                    },
                                                    meta: { '$ref' => '#/components/schemas/Meta' }
                                                  }
                                                ))
              }
            }
          },
          '/api/ready'  => {
            get: {
              tags:        ['Health'],
              summary:     'Readiness check',
              description: 'Returns readiness status for all components. Returns 503 if not ready. Skips auth middleware.',
              operationId: 'getReady',
              security:    [],
              responses:   {
                '200' => { description: 'Ready' },
                '503' => { description: 'Not ready' }
              }
            }
          }
        }
      end
      private_class_method :health_paths

      def self.task_paths
        {
          '/api/tasks'           => {
            get:  {
              tags:        ['Tasks'],
              summary:     'List tasks',
              operationId: 'listTasks',
              parameters:  PAGINATION_PARAMS + [
                { name: 'status', in: 'query', description: 'Filter by task status', required: false,
                  schema: { type: 'string' } },
                { name: 'function_id', in: 'query', description: 'Filter by function ID', required: false,
                  schema: { type: 'integer' } }
              ],
              responses:   {
                '200' => ok_response('Task list', wrap_collection('TaskObject')),
                '401' => UNAUTH_RESPONSE,
                '503' => { description: 'legion-data not connected' }
              }
            },
            post: {
              tags:        ['Tasks'],
              summary:     'Create and dispatch a task',
              operationId: 'createTask',
              requestBody: {
                required: true,
                content:  json_content({ '$ref' => '#/components/schemas/TaskInput' })
              },
              responses:   {
                '201' => ok_response('Task created', wrap_data('TaskObject')),
                '401' => UNAUTH_RESPONSE,
                '422' => UNPROCESSABLE_RESPONSE,
                '500' => { description: 'Execution error' }
              }
            }
          },
          '/api/tasks/{id}'      => {
            get:    {
              tags:        ['Tasks'],
              summary:     'Get task by ID',
              operationId: 'getTask',
              parameters:  [{ name: 'id', in: 'path', required: true, schema: { type: 'integer' } }],
              responses:   {
                '200' => ok_response('Task detail', wrap_data('TaskObject')),
                '401' => UNAUTH_RESPONSE,
                '404' => NOT_FOUND_RESPONSE,
                '503' => { description: 'legion-data not connected' }
              }
            },
            delete: {
              tags:        ['Tasks'],
              summary:     'Delete task',
              operationId: 'deleteTask',
              parameters:  [{ name: 'id', in: 'path', required: true, schema: { type: 'integer' } }],
              responses:   {
                '200' => ok_response('Deleted', wrap_data('DeletedResponse')),
                '401' => UNAUTH_RESPONSE,
                '404' => NOT_FOUND_RESPONSE
              }
            }
          },
          '/api/tasks/{id}/logs' => {
            get: {
              tags:        ['Tasks'],
              summary:     'Get task logs',
              operationId: 'getTaskLogs',
              parameters:  [{ name: 'id', in: 'path', required: true, schema: { type: 'integer' } }] + PAGINATION_PARAMS,
              responses:   {
                '200' => ok_response('Task log entries', wrap_collection('TaskObject')),
                '401' => UNAUTH_RESPONSE,
                '404' => NOT_FOUND_RESPONSE
              }
            }
          }
        }
      end
      private_class_method :task_paths

      def self.extension_paths
        {
          '/api/extensions'                                                         => {
            get: {
              tags:        ['Extensions'],
              summary:     'List extensions',
              operationId: 'listExtensions',
              parameters:  PAGINATION_PARAMS + [
                { name: 'active', in: 'query', description: 'Filter to active extensions only', required: false,
                  schema: { type: 'boolean' } }
              ],
              responses:   {
                '200' => ok_response('Extension list', wrap_collection('ExtensionObject')),
                '401' => UNAUTH_RESPONSE,
                '503' => { description: 'legion-data not connected' }
              }
            }
          },
          '/api/extensions/{id}'                                                    => {
            get: {
              tags:        ['Extensions'],
              summary:     'Get extension by ID',
              operationId: 'getExtension',
              parameters:  [{ name: 'id', in: 'path', required: true, schema: { type: 'integer' } }],
              responses:   {
                '200' => ok_response('Extension detail', wrap_data('ExtensionObject')),
                '401' => UNAUTH_RESPONSE,
                '404' => NOT_FOUND_RESPONSE
              }
            }
          },
          '/api/extensions/{id}/runners'                                            => {
            get: {
              tags:        ['Extensions'],
              summary:     'List runners for extension',
              operationId: 'listExtensionRunners',
              parameters:  [{ name: 'id', in: 'path', required: true, schema: { type: 'integer' } }] + PAGINATION_PARAMS,
              responses:   {
                '200' => ok_response('Runner list', wrap_collection('RunnerObject')),
                '401' => UNAUTH_RESPONSE,
                '404' => NOT_FOUND_RESPONSE
              }
            }
          },
          '/api/extensions/{id}/runners/{runner_id}'                                => {
            get: {
              tags:        ['Extensions'],
              summary:     'Get runner by ID',
              operationId: 'getExtensionRunner',
              parameters:  [
                { name: 'id', in: 'path', required: true, schema: { type: 'integer' } },
                { name: 'runner_id', in: 'path', required: true, schema: { type: 'integer' } }
              ],
              responses:   {
                '200' => ok_response('Runner detail', wrap_data('RunnerObject')),
                '401' => UNAUTH_RESPONSE,
                '404' => NOT_FOUND_RESPONSE
              }
            }
          },
          '/api/extensions/{id}/runners/{runner_id}/functions'                      => {
            get: {
              tags:        ['Extensions'],
              summary:     'List functions for runner',
              operationId: 'listRunnerFunctions',
              parameters:  [
                { name: 'id', in: 'path', required: true, schema: { type: 'integer' } },
                { name: 'runner_id', in: 'path', required: true, schema: { type: 'integer' } }
              ] + PAGINATION_PARAMS,
              responses:   {
                '200' => ok_response('Function list', wrap_collection('FunctionObject')),
                '401' => UNAUTH_RESPONSE,
                '404' => NOT_FOUND_RESPONSE
              }
            }
          },
          '/api/extensions/{id}/runners/{runner_id}/functions/{function_id}'        => {
            get: {
              tags:        ['Extensions'],
              summary:     'Get function by ID',
              operationId: 'getRunnerFunction',
              parameters:  [
                { name: 'id', in: 'path', required: true, schema: { type: 'integer' } },
                { name: 'runner_id', in: 'path', required: true, schema: { type: 'integer' } },
                { name: 'function_id', in: 'path', required: true, schema: { type: 'integer' } }
              ],
              responses:   {
                '200' => ok_response('Function detail', wrap_data('FunctionObject')),
                '401' => UNAUTH_RESPONSE,
                '404' => NOT_FOUND_RESPONSE
              }
            }
          },
          '/api/extensions/{id}/runners/{runner_id}/functions/{function_id}/invoke' => {
            post: {
              tags:        ['Extensions'],
              summary:     'Invoke a function directly',
              operationId: 'invokeFunction',
              parameters:  [
                { name: 'id', in: 'path', required: true, schema: { type: 'integer' } },
                { name: 'runner_id', in: 'path', required: true, schema: { type: 'integer' } },
                { name: 'function_id', in: 'path', required: true, schema: { type: 'integer' } }
              ],
              requestBody: {
                required: false,
                content:  json_content({ type: 'object', additionalProperties: true })
              },
              responses:   {
                '201' => ok_response('Task created', wrap_data('TaskObject')),
                '401' => UNAUTH_RESPONSE,
                '404' => NOT_FOUND_RESPONSE,
                '422' => UNPROCESSABLE_RESPONSE
              }
            }
          }
        }
      end
      private_class_method :extension_paths

      def self.node_paths
        {
          '/api/nodes'      => {
            get: {
              tags:        ['Nodes'],
              summary:     'List nodes',
              operationId: 'listNodes',
              parameters:  PAGINATION_PARAMS + [
                { name: 'active', in: 'query', description: 'Filter to active nodes only', required: false,
                  schema: { type: 'boolean' } },
                { name: 'status', in: 'query', description: 'Filter by node status', required: false,
                  schema: { type: 'string' } }
              ],
              responses:   {
                '200' => ok_response('Node list', wrap_collection('NodeObject')),
                '401' => UNAUTH_RESPONSE,
                '503' => { description: 'legion-data not connected' }
              }
            }
          },
          '/api/nodes/{id}' => {
            get: {
              tags:        ['Nodes'],
              summary:     'Get node by ID',
              operationId: 'getNode',
              parameters:  [{ name: 'id', in: 'path', required: true, schema: { type: 'integer' } }],
              responses:   {
                '200' => ok_response('Node detail', wrap_data('NodeObject')),
                '401' => UNAUTH_RESPONSE,
                '404' => NOT_FOUND_RESPONSE
              }
            }
          }
        }
      end
      private_class_method :node_paths

      def self.schedule_paths
        {
          '/api/schedules'           => {
            get:  {
              tags:        ['Schedules'],
              summary:     'List schedules',
              operationId: 'listSchedules',
              parameters:  PAGINATION_PARAMS + [
                { name: 'active', in: 'query', description: 'Filter to active schedules only', required: false,
                  schema: { type: 'boolean' } }
              ],
              responses:   {
                '200' => ok_response('Schedule list', wrap_collection('ScheduleObject')),
                '401' => UNAUTH_RESPONSE,
                '503' => { description: 'lex-scheduler not loaded' }
              }
            },
            post: {
              tags:        ['Schedules'],
              summary:     'Create schedule',
              operationId: 'createSchedule',
              requestBody: {
                required: true,
                content:  json_content({ '$ref' => '#/components/schemas/ScheduleInput' })
              },
              responses:   {
                '201' => ok_response('Schedule created', wrap_data('ScheduleObject')),
                '401' => UNAUTH_RESPONSE,
                '422' => UNPROCESSABLE_RESPONSE,
                '503' => { description: 'lex-scheduler not loaded' }
              }
            }
          },
          '/api/schedules/{id}'      => {
            get:    {
              tags:        ['Schedules'],
              summary:     'Get schedule by ID',
              operationId: 'getSchedule',
              parameters:  [{ name: 'id', in: 'path', required: true, schema: { type: 'integer' } }],
              responses:   {
                '200' => ok_response('Schedule detail', wrap_data('ScheduleObject')),
                '401' => UNAUTH_RESPONSE,
                '404' => NOT_FOUND_RESPONSE
              }
            },
            put:    {
              tags:        ['Schedules'],
              summary:     'Update schedule',
              operationId: 'updateSchedule',
              parameters:  [{ name: 'id', in: 'path', required: true, schema: { type: 'integer' } }],
              requestBody: {
                required: true,
                content:  json_content({ '$ref' => '#/components/schemas/ScheduleInput' })
              },
              responses:   {
                '200' => ok_response('Updated schedule', wrap_data('ScheduleObject')),
                '401' => UNAUTH_RESPONSE,
                '404' => NOT_FOUND_RESPONSE
              }
            },
            delete: {
              tags:        ['Schedules'],
              summary:     'Delete schedule',
              operationId: 'deleteSchedule',
              parameters:  [{ name: 'id', in: 'path', required: true, schema: { type: 'integer' } }],
              responses:   {
                '200' => ok_response('Deleted', wrap_data('DeletedResponse')),
                '401' => UNAUTH_RESPONSE,
                '404' => NOT_FOUND_RESPONSE
              }
            }
          },
          '/api/schedules/{id}/logs' => {
            get: {
              tags:        ['Schedules'],
              summary:     'Get schedule run logs',
              operationId: 'getScheduleLogs',
              parameters:  [{ name: 'id', in: 'path', required: true, schema: { type: 'integer' } }] + PAGINATION_PARAMS,
              responses:   {
                '200' => ok_response('Schedule log entries', wrap_collection('TaskObject')),
                '401' => UNAUTH_RESPONSE,
                '404' => NOT_FOUND_RESPONSE
              }
            }
          }
        }
      end
      private_class_method :schedule_paths

      def self.relationship_paths
        stub_crud_paths('relationships', 'Relationships', 'Relationship', 'RelationshipObject')
      end
      private_class_method :relationship_paths

      def self.chain_paths
        stub_crud_paths('chains', 'Chains', 'Chain', 'ChainObject')
      end
      private_class_method :chain_paths

      def self.stub_crud_paths(resource, tag, op_prefix, schema_ref)
        {
          "/api/#{resource}"      => {
            get:  {
              tags:        [tag],
              summary:     "List #{resource}",
              description: 'Returns 501 — data model not yet available.',
              operationId: "list#{op_prefix}s",
              responses:   {
                '501' => NOT_IMPL_RESPONSE,
                '401' => UNAUTH_RESPONSE
              }
            },
            post: {
              tags:        [tag],
              summary:     "Create #{resource.chop}",
              description: 'Returns 501 — data model not yet available.',
              operationId: "create#{op_prefix}",
              requestBody: {
                required: true,
                content:  json_content({ type: 'object', additionalProperties: true })
              },
              responses:   {
                '501' => NOT_IMPL_RESPONSE,
                '401' => UNAUTH_RESPONSE
              }
            }
          },
          "/api/#{resource}/{id}" => {
            get:    {
              tags:        [tag],
              summary:     "Get #{resource.chop} by ID",
              description: 'Returns 501 — data model not yet available.',
              operationId: "get#{op_prefix}",
              parameters:  [{ name: 'id', in: 'path', required: true, schema: { type: 'integer' } }],
              responses:   {
                '200' => ok_response("#{op_prefix} detail", wrap_data(schema_ref)),
                '501' => NOT_IMPL_RESPONSE,
                '404' => NOT_FOUND_RESPONSE,
                '401' => UNAUTH_RESPONSE
              }
            },
            put:    {
              tags:        [tag],
              summary:     "Update #{resource.chop}",
              description: 'Returns 501 — data model not yet available.',
              operationId: "update#{op_prefix}",
              parameters:  [{ name: 'id', in: 'path', required: true, schema: { type: 'integer' } }],
              requestBody: {
                required: true,
                content:  json_content({ type: 'object', additionalProperties: true })
              },
              responses:   {
                '200' => ok_response("Updated #{resource.chop}", wrap_data(schema_ref)),
                '501' => NOT_IMPL_RESPONSE,
                '404' => NOT_FOUND_RESPONSE,
                '401' => UNAUTH_RESPONSE
              }
            },
            delete: {
              tags:        [tag],
              summary:     "Delete #{resource.chop}",
              description: 'Returns 501 — data model not yet available.',
              operationId: "delete#{op_prefix}",
              parameters:  [{ name: 'id', in: 'path', required: true, schema: { type: 'integer' } }],
              responses:   {
                '200' => ok_response('Deleted', wrap_data('DeletedResponse')),
                '501' => NOT_IMPL_RESPONSE,
                '404' => NOT_FOUND_RESPONSE,
                '401' => UNAUTH_RESPONSE
              }
            }
          }
        }
      end
      private_class_method :stub_crud_paths

      def self.settings_paths
        {
          '/api/settings'       => {
            get: {
              tags:        ['Settings'],
              summary:     'Get all settings (sensitive values redacted)',
              operationId: 'getSettings',
              responses:   {
                '200' => ok_response('Settings hash', { type: 'object', additionalProperties: true }),
                '401' => UNAUTH_RESPONSE
              }
            }
          },
          '/api/settings/{key}' => {
            get: {
              tags:        ['Settings'],
              summary:     'Get a single setting section',
              operationId: 'getSetting',
              parameters:  [{ name: 'key', in: 'path', required: true, schema: { type: 'string' } }],
              responses:   {
                '200' => ok_response('Setting value',
                                     { type: 'object', properties: { key: { type: 'string' }, value: {} } }),
                '401' => UNAUTH_RESPONSE,
                '404' => NOT_FOUND_RESPONSE
              }
            },
            put: {
              tags:        ['Settings'],
              summary:     'Update a setting section',
              description: 'transport and crypt sections are read-only and return 403.',
              operationId: 'updateSetting',
              parameters:  [{ name: 'key', in: 'path', required: true, schema: { type: 'string' } }],
              requestBody: {
                required: true,
                content:  json_content({ type: 'object', required: ['value'], properties: { value: {} } })
              },
              responses:   {
                '200' => ok_response('Updated setting',
                                     { type: 'object', properties: { key: { type: 'string' }, value: {} } }),
                '401' => UNAUTH_RESPONSE,
                '403' => { description: 'Forbidden — read-only section' },
                '422' => UNPROCESSABLE_RESPONSE
              }
            }
          }
        }
      end
      private_class_method :settings_paths

      def self.event_paths
        {
          '/api/events'        => {
            get: {
              tags:        ['Events'],
              summary:     'Server-Sent Events stream',
              description: 'Streams all Legion events as SSE. Responds with text/event-stream. ' \
                           'Each event: `event: <name>\\ndata: <json>\\n\\n`.',
              operationId: 'streamEvents',
              responses:   {
                '200' => {
                  description: 'SSE stream',
                  content:     { 'text/event-stream' => { schema: { type: 'string' } } }
                },
                '401' => UNAUTH_RESPONSE
              }
            }
          },
          '/api/events/recent' => {
            get: {
              tags:        ['Events'],
              summary:     'Get recent events from ring buffer',
              operationId: 'getRecentEvents',
              parameters:  [
                { name: 'count', in: 'query', description: "Number of events (max #{Routes::Events::BUFFER_SIZE})",
                  required: false, schema: { type: 'integer', default: 25 } }
              ],
              responses:   {
                '200' => ok_response('Recent events', { type: 'object', properties: {
                                       data: { type: 'array', items: { type: 'object' } },
                                       meta: { '$ref' => '#/components/schemas/Meta' }
                                     } }),
                '401' => UNAUTH_RESPONSE
              }
            }
          }
        }
      end
      private_class_method :event_paths

      def self.transport_paths
        {
          '/api/transport'           => {
            get: {
              tags:        ['Transport'],
              summary:     'RabbitMQ transport connection status',
              operationId: 'getTransportStatus',
              responses:   {
                '200' => ok_response('Transport status', { type: 'object', properties: {
                                       data: {
                                         type:       'object',
                                         properties: {
                                           connected:    { type: 'boolean' },
                                           session_open: { type: 'boolean' },
                                           channel_open: { type: 'boolean' },
                                           connector:    { type: 'string' }
                                         }
                                       },
                                       meta: { '$ref' => '#/components/schemas/Meta' }
                                     } }),
                '401' => UNAUTH_RESPONSE
              }
            }
          },
          '/api/transport/exchanges' => {
            get: {
              tags:        ['Transport'],
              summary:     'List known exchange subclasses',
              operationId: 'listExchanges',
              responses:   {
                '200' => ok_response('Exchange list',
                                     { type: 'object', properties: {
                                       data: { type: 'array', items: { type:       'object',
                                                                       properties: { name: { type: 'string' } } } },
                                       meta: { '$ref' => '#/components/schemas/Meta' }
                                     } }),
                '401' => UNAUTH_RESPONSE
              }
            }
          },
          '/api/transport/queues'    => {
            get: {
              tags:        ['Transport'],
              summary:     'List known queue subclasses',
              operationId: 'listQueues',
              responses:   {
                '200' => ok_response('Queue list',
                                     { type: 'object', properties: {
                                       data: { type: 'array', items: { type:       'object',
                                                                       properties: { name: { type: 'string' } } } },
                                       meta: { '$ref' => '#/components/schemas/Meta' }
                                     } }),
                '401' => UNAUTH_RESPONSE
              }
            }
          },
          '/api/transport/publish'   => {
            post: {
              tags:        ['Transport'],
              summary:     'Publish a message to an exchange',
              operationId: 'publishMessage',
              requestBody: {
                required: true,
                content:  json_content({
                                         type:       'object',
                                         required:   %w[exchange routing_key],
                                         properties: {
                                           exchange:    { type: 'string' },
                                           routing_key: { type: 'string' },
                                           payload:     { type: 'object', additionalProperties: true }
                                         }
                                       })
              },
              responses:   {
                '201' => ok_response('Published', { type: 'object', properties: {
                                       data: {
                                         type:       'object',
                                         properties: {
                                           published:   { type: 'boolean' },
                                           exchange:    { type: 'string' },
                                           routing_key: { type: 'string' }
                                         }
                                       },
                                       meta: { '$ref' => '#/components/schemas/Meta' }
                                     } }),
                '401' => UNAUTH_RESPONSE,
                '422' => UNPROCESSABLE_RESPONSE
              }
            }
          }
        }
      end
      private_class_method :transport_paths

      def self.hook_paths
        {
          '/api/hooks'                        => {
            get: {
              tags:        ['Hooks'],
              summary:     'List registered webhook endpoints',
              operationId: 'listHooks',
              responses:   {
                '200' => ok_response('Hook list', { type: 'object', properties: {
                                       data: {
                                         type:  'array',
                                         items: {
                                           type:       'object',
                                           properties: {
                                             lex_name:       { type: 'string' },
                                             hook_name:      { type: 'string' },
                                             hook_class:     { type: 'string' },
                                             default_runner: { type: 'string' },
                                             endpoint:       { type: 'string' }
                                           }
                                         }
                                       },
                                       meta: { '$ref' => '#/components/schemas/Meta' }
                                     } }),
                '401' => UNAUTH_RESPONSE
              }
            }
          },
          '/api/hooks/{lex_name}/{hook_name}' => {
            post: {
              tags:        ['Hooks'],
              summary:     'Trigger a registered webhook',
              description: 'Verifies the webhook signature, routes the event to the configured runner, ' \
                           'and dispatches a task via Ingress.',
              operationId: 'triggerHook',
              parameters:  [
                { name: 'lex_name', in: 'path', required: true, schema: { type: 'string' } },
                { name: 'hook_name', in: 'path', required: false, schema: { type: 'string' } }
              ],
              requestBody: {
                required: false,
                content:  { 'application/json' => { schema: { type: 'object', additionalProperties: true } } }
              },
              responses:   {
                '200' => ok_response('Hook dispatched', { type: 'object', properties: {
                                       data: {
                                         type:       'object',
                                         properties: { task_id: { type: 'integer' }, status: { type: 'string' } }
                                       },
                                       meta: { '$ref' => '#/components/schemas/Meta' }
                                     } }),
                '401' => UNAUTH_RESPONSE,
                '404' => NOT_FOUND_RESPONSE,
                '422' => UNPROCESSABLE_RESPONSE
              }
            }
          }
        }
      end
      private_class_method :hook_paths

      def self.lex_route_responses
        {
          '200' => {
            description: 'Success',
            content:     {
              'application/json' => {
                schema: {
                  type:       'object',
                  properties: {
                    data: {
                      type:       'object',
                      properties: {
                        task_id: { type: 'string' },
                        status:  { type: 'string' },
                        result:  { type: 'object' }
                      }
                    },
                    meta: META_SCHEMA
                  }
                }
              }
            }
          },
          '401' => { description: 'Unauthorized',     content: { 'application/json' => { schema: ERROR_SCHEMA } } },
          '403' => { description: 'Forbidden',        content: { 'application/json' => { schema: ERROR_SCHEMA } } },
          '404' => { description: 'Not found',        content: { 'application/json' => { schema: ERROR_SCHEMA } } },
          '500' => { description: 'Internal error',   content: { 'application/json' => { schema: ERROR_SCHEMA } } }
        }
      end
      private_class_method :lex_route_responses

      def self.lex_paths
        base = {
          '/api/lex' => {
            get: {
              tags:        ['Lex'],
              summary:     'List auto-registered LEX runner routes',
              operationId: 'listLexRoutes',
              responses:   {
                '200' => ok_response('Lex route list', {
                                       type:       'object',
                                       properties: {
                                         data: {
                                           type:  'array',
                                           items: {
                                             type:       'object',
                                             properties: {
                                               endpoint:     { type: 'string' },
                                               extension:    { type: 'string' },
                                               runner:       { type: 'string' },
                                               function:     { type: 'string' },
                                               runner_class: { type: 'string' }
                                             }
                                           }
                                         },
                                         meta: { '$ref' => '#/components/schemas/Meta' }
                                       }
                                     }),
                '401' => UNAUTH_RESPONSE
              }
            }
          }
        }

        # Auto-routes (LEX)
        if defined?(Legion::API) && Legion::API.respond_to?(:registered_routes)
          Legion::API.registered_routes.each do |route|
            path_key = "/api/lex/#{route[:route_path]}"
            base[path_key] = {
              post: {
                operationId: "#{route[:lex_name]}.#{route[:runner_name]}.#{route[:function]}",
                summary:     "Invoke #{route[:runner_name]}##{route[:function]} on lex-#{route[:lex_name]}",
                tags:        [route[:lex_name]],
                requestBody: {
                  required: false,
                  content:  { 'application/json' => { schema: { type: 'object' } } }
                },
                responses:   lex_route_responses
              }
            }
          end
        end

        base
      end
      private_class_method :lex_paths

      def self.worker_paths
        {
          '/api/workers'                => {
            get:  {
              tags:        ['Workers'],
              summary:     'List digital workers',
              operationId: 'listWorkers',
              parameters:  PAGINATION_PARAMS + [
                { name: 'team', in: 'query', required: false, schema: { type: 'string' } },
                { name: 'owner_msid', in: 'query', required: false, schema: { type: 'string' } },
                { name: 'lifecycle_state', in: 'query', required: false, schema: { type: 'string' } },
                { name: 'risk_tier', in: 'query', required: false, schema: { type: 'string' } }
              ],
              responses:   {
                '200' => ok_response('Worker list', wrap_collection('WorkerObject')),
                '401' => UNAUTH_RESPONSE
              }
            },
            post: {
              tags:        ['Workers'],
              summary:     'Register a new digital worker',
              operationId: 'createWorker',
              requestBody: {
                required: true,
                content:  json_content({ '$ref' => '#/components/schemas/WorkerInput' })
              },
              responses:   {
                '201' => ok_response('Worker registered', wrap_data('WorkerObject')),
                '401' => UNAUTH_RESPONSE,
                '422' => UNPROCESSABLE_RESPONSE
              }
            }
          },
          '/api/workers/{id}'           => {
            get:    {
              tags:        ['Workers'],
              summary:     'Get worker by ID',
              operationId: 'getWorker',
              parameters:  [{ name: 'id', in: 'path', required: true, schema: { type: 'string' } }],
              responses:   {
                '200' => ok_response('Worker detail', wrap_data('WorkerObject')),
                '401' => UNAUTH_RESPONSE,
                '404' => NOT_FOUND_RESPONSE
              }
            },
            delete: {
              tags:        ['Workers'],
              summary:     'Retire a worker (transitions to retired state)',
              operationId: 'deleteWorker',
              parameters:  [
                { name: 'id', in: 'path', required: true, schema: { type: 'string' } },
                { name: 'reason', in: 'query', required: false, schema: { type: 'string' } }
              ],
              responses:   {
                '200' => ok_response('Worker retired', wrap_data('WorkerObject')),
                '401' => UNAUTH_RESPONSE,
                '404' => NOT_FOUND_RESPONSE,
                '422' => UNPROCESSABLE_RESPONSE
              }
            }
          },
          '/api/workers/{id}/lifecycle' => {
            patch: {
              tags:        ['Workers'],
              summary:     'Transition worker lifecycle state',
              operationId: 'transitionWorkerLifecycle',
              parameters:  [{ name: 'id', in: 'path', required: true, schema: { type: 'string' } }],
              requestBody: {
                required: true,
                content:  json_content({
                                         type:       'object',
                                         required:   ['state'],
                                         properties: {
                                           state:               { type: 'string', enum: %w[active paused retired terminated] },
                                           by:                  { type: 'string' },
                                           reason:              { type: 'string' },
                                           governance_override: { type: 'boolean', default: false },
                                           authority_verified:  { type: 'boolean', default: false }
                                         }
                                       })
              },
              responses:   {
                '200' => ok_response('Updated worker', wrap_data('WorkerObject')),
                '401' => UNAUTH_RESPONSE,
                '403' => { description: 'Governance or authority required' },
                '404' => NOT_FOUND_RESPONSE,
                '422' => UNPROCESSABLE_RESPONSE
              }
            }
          },
          '/api/workers/{id}/tasks'     => {
            get: {
              tags:        ['Workers'],
              summary:     'List tasks for a worker',
              operationId: 'getWorkerTasks',
              parameters:  [{ name: 'id', in: 'path', required: true, schema: { type: 'string' } }] + PAGINATION_PARAMS,
              responses:   {
                '200' => ok_response('Task list', wrap_collection('TaskObject')),
                '401' => UNAUTH_RESPONSE,
                '404' => NOT_FOUND_RESPONSE
              }
            }
          },
          '/api/workers/{id}/events'    => {
            get: {
              tags:        ['Workers'],
              summary:     'Get worker lifecycle events',
              description: 'Lifecycle event persistence is not yet implemented — returns empty list.',
              operationId: 'getWorkerEvents',
              parameters:  [{ name: 'id', in: 'path', required: true, schema: { type: 'string' } }],
              responses:   {
                '200' => { description: 'Worker events (stub)' },
                '401' => UNAUTH_RESPONSE,
                '404' => NOT_FOUND_RESPONSE
              }
            }
          },
          '/api/workers/{id}/costs'     => {
            get: {
              tags:        ['Workers'],
              summary:     'Get worker cost summary',
              description: 'Requires lex-metering. Returns stub if not available.',
              operationId: 'getWorkerCosts',
              parameters:  [{ name: 'id', in: 'path', required: true, schema: { type: 'string' } }],
              responses:   {
                '200' => { description: 'Worker cost summary' },
                '401' => UNAUTH_RESPONSE,
                '404' => NOT_FOUND_RESPONSE
              }
            }
          },
          '/api/workers/{id}/value'     => {
            get: {
              tags:        ['Workers'],
              summary:     'Get worker value metrics',
              operationId: 'getWorkerValue',
              parameters:  [
                { name: 'id', in: 'path', required: true, schema: { type: 'string' } },
                { name: 'since', in: 'query', required: false, description: 'ISO8601 start timestamp',
                  schema: { type: 'string', format: 'date-time' } }
              ],
              responses:   {
                '200' => { description: 'Worker value summary and recent metrics' },
                '401' => UNAUTH_RESPONSE,
                '404' => NOT_FOUND_RESPONSE
              }
            }
          },
          '/api/workers/{id}/roi'       => {
            get: {
              tags:        ['Workers'],
              summary:     'Get worker ROI (value vs cost)',
              operationId: 'getWorkerRoi',
              parameters:  [
                { name: 'id', in: 'path', required: true, schema: { type: 'string' } },
                { name: 'period', in: 'query', required: false, schema: { type: 'string', default: 'monthly' } }
              ],
              responses:   {
                '200' => { description: 'Worker ROI summary' },
                '401' => UNAUTH_RESPONSE,
                '404' => NOT_FOUND_RESPONSE
              }
            }
          }
        }
      end
      private_class_method :worker_paths

      def self.team_paths
        {
          '/api/teams/{team}/workers' => {
            get: {
              tags:        ['Teams'],
              summary:     'List workers on a team',
              operationId: 'getTeamWorkers',
              parameters:  [{ name: 'team', in: 'path', required: true, schema: { type: 'string' } }] + PAGINATION_PARAMS,
              responses:   {
                '200' => ok_response('Team worker list', wrap_collection('WorkerObject')),
                '401' => UNAUTH_RESPONSE
              }
            }
          },
          '/api/teams/{team}/costs'   => {
            get: {
              tags:        ['Teams'],
              summary:     'Get team cost summary',
              description: 'Requires lex-metering. Returns stub if not available.',
              operationId: 'getTeamCosts',
              parameters:  [{ name: 'team', in: 'path', required: true, schema: { type: 'string' } }],
              responses:   {
                '200' => { description: 'Team cost summary' },
                '401' => UNAUTH_RESPONSE
              }
            }
          }
        }
      end
      private_class_method :team_paths

      def self.coldstart_paths
        {
          '/api/coldstart/ingest' => {
            post: {
              tags:        ['Coldstart'],
              summary:     'Ingest a file or directory into lex-memory',
              description: 'Requires lex-coldstart and lex-memory to be loaded.',
              operationId: 'coldstartIngest',
              requestBody: {
                required: true,
                content:  json_content({
                                         type:       'object',
                                         required:   ['path'],
                                         properties: {
                                           path:    { type: 'string', description: 'File or directory path to ingest' },
                                           pattern: { type: 'string', description: 'Glob pattern (directory only)',
                                         default: '**/{CLAUDE,MEMORY}.md' }
                                         }
                                       })
              },
              responses:   {
                '201' => ok_response('Ingest result', { type: 'object', additionalProperties: true }),
                '401' => UNAUTH_RESPONSE,
                '404' => NOT_FOUND_RESPONSE,
                '422' => UNPROCESSABLE_RESPONSE,
                '503' => { description: 'lex-coldstart or lex-memory not loaded' }
              }
            }
          }
        }
      end
      private_class_method :coldstart_paths

      def self.gaia_paths
        {
          '/api/gaia/status'   => {
            get: {
              tags:        ['Gaia'],
              summary:     'Get Gaia cognitive layer status',
              operationId: 'getGaiaStatus',
              responses:   {
                '200' => ok_response('Gaia status', { type: 'object', additionalProperties: true }),
                '401' => UNAUTH_RESPONSE,
                '503' => { description: 'Gaia not started' }
              }
            }
          },
          '/api/gaia/channels' => {
            get: {
              tags:        ['Gaia'],
              summary:     'List registered communication channels',
              operationId: 'getGaiaChannels',
              responses:   {
                '200' => ok_response('Channel list', gaia_channels_schema),
                '401' => UNAUTH_RESPONSE,
                '503' => { description: 'Gaia not started' }
              }
            }
          },
          '/api/gaia/buffer'   => {
            get: {
              tags:        ['Gaia'],
              summary:     'Get sensory buffer status',
              operationId: 'getGaiaBuffer',
              responses:   {
                '200' => ok_response('Buffer status', gaia_buffer_schema),
                '401' => UNAUTH_RESPONSE,
                '503' => { description: 'Gaia not started' }
              }
            }
          },
          '/api/gaia/sessions' => {
            get: {
              tags:        ['Gaia'],
              summary:     'Get active session count',
              operationId: 'getGaiaSessions',
              responses:   {
                '200' => ok_response('Session info', gaia_sessions_schema),
                '401' => UNAUTH_RESPONSE,
                '503' => { description: 'Gaia not started' }
              }
            }
          }
        }
      end
      private_class_method :gaia_paths

      def self.gaia_channels_schema
        {
          type:       'object',
          properties: {
            channels: { type: 'array', items: {
              type: 'object', properties: {
                id: { type: 'string' }, type: { type: 'string' },
                started: { type: 'boolean' }, capabilities: { type: 'array', items: { type: 'string' } }
              }
            } },
            count:    { type: 'integer' }
          }
        }
      end
      private_class_method :gaia_channels_schema

      def self.gaia_buffer_schema
        {
          type:       'object',
          properties: {
            depth:    { type: 'integer' },
            empty:    { type: 'boolean' },
            max_size: { type: 'integer', nullable: true }
          }
        }
      end
      private_class_method :gaia_buffer_schema

      def self.gaia_sessions_schema
        {
          type:       'object',
          properties: {
            count:  { type: 'integer' },
            active: { type: 'boolean' }
          }
        }
      end
      private_class_method :gaia_sessions_schema

      def self.apollo_paths
        {
          '/api/apollo/status'               => {
            get: {
              tags:        ['Apollo'],
              summary:     'Apollo knowledge graph availability',
              operationId: 'getApolloStatus',
              responses:   {
                '200' => ok_response('Apollo available', { type: 'object', properties: {
                                       available:      { type: 'boolean' },
                                       data_connected: { type: 'boolean' }
                                     } }),
                '401' => UNAUTH_RESPONSE,
                '503' => { description: 'Apollo not available' }
              }
            }
          },
          '/api/apollo/stats'                => {
            get: {
              tags:        ['Apollo'],
              summary:     'Knowledge graph statistics',
              operationId: 'getApolloStats',
              responses:   {
                '200' => ok_response('Apollo stats', { type: 'object', properties: {
                                       total_entries:   { type: 'integer' },
                                       by_status:       { type: 'object', additionalProperties: { type: 'integer' } },
                                       by_content_type: { type: 'object', additionalProperties: { type: 'integer' } },
                                       recent_24h:      { type: 'integer' },
                                       avg_confidence:  { type: 'number' }
                                     } }),
                '401' => UNAUTH_RESPONSE,
                '503' => { description: 'Apollo not available' }
              }
            }
          },
          '/api/apollo/query'                => {
            post: {
              tags:        ['Apollo'],
              summary:     'Query the knowledge graph',
              operationId: 'apolloQuery',
              requestBody: {
                required: true,
                content:  json_content({
                                         type:       'object',
                                         required:   ['query'],
                                         properties: {
                                           query:          { type: 'string', description: 'Semantic search query' },
                                           limit:          { type: 'integer', default: 10 },
                                           min_confidence: { type: 'number', default: 0.3 },
                                           status:         { type: 'array', items: { type: 'string' } },
                                           tags:           { type: 'array', items: { type: 'string' } },
                                           domain:         { type: 'string' },
                                           agent_id:       { type: 'string', default: 'api' }
                                         }
                                       })
              },
              responses:   {
                '200' => ok_response('Query results', { type: 'object', additionalProperties: true }),
                '401' => UNAUTH_RESPONSE,
                '503' => { description: 'Apollo not available' }
              }
            }
          },
          '/api/apollo/ingest'               => {
            post: {
              tags:        ['Apollo'],
              summary:     'Ingest knowledge into the graph',
              operationId: 'apolloIngest',
              requestBody: {
                required: true,
                content:  json_content({
                                         type:       'object',
                                         required:   ['content'],
                                         properties: {
                                           content:          { type: 'string' },
                                           content_type:     { type: 'string', enum: %w[fact concept procedure association observation] },
                                           tags:             { type: 'array', items: { type: 'string' } },
                                           source_agent:     { type: 'string', default: 'api' },
                                           source_provider:  { type: 'string' },
                                           source_channel:   { type: 'string', default: 'rest_api' },
                                           knowledge_domain: { type: 'string' },
                                           context:          { type: 'object', additionalProperties: true }
                                         }
                                       })
              },
              responses:   {
                '201' => ok_response('Ingested', { type: 'object', additionalProperties: true }),
                '401' => UNAUTH_RESPONSE,
                '503' => { description: 'Apollo not available' }
              }
            }
          },
          '/api/apollo/entries/{id}/related' => {
            get: {
              tags:        ['Apollo'],
              summary:     'Get related knowledge entries',
              operationId: 'getApolloRelated',
              parameters:  [
                { name: 'id', in: 'path', required: true, schema: { type: 'integer' } },
                { name: 'relation_types', in: 'query', schema: { type: 'string' },
                  description: 'Comma-separated relation types' },
                { name: 'depth', in: 'query', schema: { type: 'integer', default: 2 } }
              ],
              responses:   {
                '200' => ok_response('Related entries', { type: 'object', additionalProperties: true }),
                '401' => UNAUTH_RESPONSE,
                '503' => { description: 'Apollo not available' }
              }
            }
          },
          '/api/apollo/maintenance'          => {
            post: {
              tags:        ['Apollo'],
              summary:     'Trigger knowledge graph maintenance',
              operationId: 'apolloMaintenance',
              requestBody: {
                required: true,
                content:  json_content({
                                         type:       'object',
                                         required:   ['action'],
                                         properties: {
                                           action: { type: 'string', enum: %w[decay_cycle corroboration] }
                                         }
                                       })
              },
              responses:   {
                '200' => ok_response('Maintenance result', { type: 'object', additionalProperties: true }),
                '400' => { description: 'Invalid action' },
                '401' => UNAUTH_RESPONSE,
                '503' => { description: 'Apollo not available' }
              }
            }
          }
        }
      end
      private_class_method :apollo_paths

      def self.openapi_paths
        {
          '/api/openapi.json' => {
            get: {
              tags:        ['OpenAPI'],
              summary:     'OpenAPI 3.1.0 spec for this API',
              description: 'Returns this document. Skips auth middleware.',
              operationId: 'getOpenApiSpec',
              security:    [],
              responses:   {
                '200' => {
                  description: 'OpenAPI spec',
                  content:     { 'application/json' => { schema: { type: 'object', additionalProperties: true } } }
                }
              }
            }
          }
        }
      end
      private_class_method :openapi_paths

      def self.stats_paths
        {
          '/api/stats' => {
            get: {
              tags:        ['Stats'],
              summary:     'Comprehensive daemon runtime stats',
              description: 'Returns runtime statistics for all subsystems: extensions, gaia, transport, cache, llm, data, and api. ' \
                           'Each section collects independently — one subsystem failure does not affect others.',
              operationId: 'getStats',
              responses:   {
                '200' => ok_response('Stats', wrap_data('StatsObject').merge(
                                                properties: {
                                                  data: {
                                                    type:       'object',
                                                    properties: {
                                                      extensions:  { type: 'object' },
                                                      gaia:        { type: 'object' },
                                                      transport:   { type: 'object' },
                                                      cache:       { type: 'object' },
                                                      cache_local: { type: 'object' },
                                                      llm:         { type: 'object' },
                                                      data:        { type: 'object' },
                                                      data_local:  { type: 'object' },
                                                      api:         { type: 'object' }
                                                    }
                                                  },
                                                  meta: { '$ref' => '#/components/schemas/Meta' }
                                                }
                                              ))
              }
            }
          }
        }
      end
      private_class_method :stats_paths
    end
  end
end
