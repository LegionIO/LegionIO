# frozen_string_literal: true

module Legion
  class API < Sinatra::Base
    module Routes
      module Knowledge
        def self.registered(app)
          register_query_routes(app)
          register_ingest_routes(app)
          register_maintenance_routes(app)
          register_monitor_routes(app)
        end

        def self.register_query_routes(app)
          app.post '/api/knowledge/query' do
            require_knowledge_query!
            body = parse_request_body
            result = Legion::Extensions::Knowledge::Runners::Query.query(
              question:   body[:question],
              top_k:      body[:top_k] || 5,
              synthesize: body.fetch(:synthesize, true)
            )
            json_response(result)
          end

          app.post '/api/knowledge/retrieve' do
            require_knowledge_query!
            body = parse_request_body
            result = Legion::Extensions::Knowledge::Runners::Query.retrieve(
              question: body[:question],
              top_k:    body[:top_k] || 5
            )
            json_response(result)
          end
        end

        def self.register_ingest_routes(app)
          app.post '/api/knowledge/ingest' do
            require_knowledge_ingest!
            body = parse_request_body

            result = if body[:content]
                       Legion::Extensions::Knowledge::Runners::Ingest.ingest_content(
                         content:     body[:content],
                         source_type: body[:source] || :text,
                         metadata:    { tags: body[:tags] || [] }
                       )
                     elsif body[:path]
                       if File.directory?(body[:path])
                         Legion::Extensions::Knowledge::Runners::Ingest.ingest_corpus(
                           path:    body[:path],
                           force:   body[:force] || false,
                           dry_run: body[:dry_run] || false
                         )
                       else
                         Legion::Extensions::Knowledge::Runners::Ingest.ingest_file(
                           file_path: body[:path],
                           force:     body[:force] || false,
                           dry_run:   body[:dry_run] || false
                         )
                       end
                     else
                       halt 400, json_error('missing_param', 'content or path is required')
                     end
            json_response(result)
          end

          app.post '/api/knowledge/status' do
            require_knowledge_ingest!
            body = parse_request_body
            path = body[:path] || Dir.pwd
            result = Legion::Extensions::Knowledge::Runners::Ingest.scan_corpus(path: path)
            json_response(result)
          end
        end

        def self.register_maintenance_routes(app)
          app.post '/api/knowledge/health' do
            require_knowledge_maintenance!
            body = parse_request_body
            result = Legion::Extensions::Knowledge::Runners::Maintenance.health(path: body[:path])
            json_response(result)
          end

          app.post '/api/knowledge/maintain' do
            require_knowledge_maintenance!
            body = parse_request_body
            result = Legion::Extensions::Knowledge::Runners::Maintenance.cleanup_orphans(
              path:    body[:path],
              dry_run: body.fetch(:dry_run, true)
            )
            json_response(result)
          end

          app.post '/api/knowledge/quality' do
            require_knowledge_maintenance!
            body = parse_request_body
            result = Legion::Extensions::Knowledge::Runners::Maintenance.quality_report(
              limit: body[:limit] || 10
            )
            json_response(result)
          end
        end

        def self.register_monitor_routes(app)
          monitor_list = lambda do
            require_knowledge_monitor!
            monitors = Legion::Extensions::Knowledge::Runners::Monitor.list_monitors
            json_response(monitors)
          end

          monitor_add = lambda do
            require_knowledge_monitor!
            body = parse_request_body
            result = Legion::Extensions::Knowledge::Runners::Monitor.add_monitor(
              path:       body[:path],
              extensions: body[:extensions],
              label:      body[:label]
            )
            json_response(result, status_code: 201)
          end

          monitor_remove = lambda do
            require_knowledge_monitor!
            body = parse_request_body
            result = Legion::Extensions::Knowledge::Runners::Monitor.remove_monitor(
              identifier: body[:identifier]
            )
            json_response(result)
          end

          # Primary routes
          app.get('/api/knowledge/monitors', &monitor_list)
          app.post('/api/knowledge/monitors', &monitor_add)
          app.delete('/api/knowledge/monitors', &monitor_remove)

          # Interlink v3 aliases
          app.get('/api/extensions/knowledge/runners/monitors/list', &monitor_list)
          app.post('/api/extensions/knowledge/runners/monitors/create', &monitor_add)
          app.delete('/api/extensions/knowledge/runners/monitors/delete', &monitor_remove)

          # Interlink v2 aliases
          app.get('/api/lex/knowledge/monitors', &monitor_list)
          app.post('/api/lex/knowledge/monitors', &monitor_add)
          app.delete('/api/lex/knowledge/monitors', &monitor_remove)

          app.get '/api/knowledge/monitors/status' do
            require_knowledge_monitor!
            result = Legion::Extensions::Knowledge::Runners::Monitor.monitor_status
            json_response(result)
          end
        end

        class << self
          private :register_query_routes, :register_ingest_routes,
                  :register_maintenance_routes, :register_monitor_routes
        end
      end
    end
  end
end
