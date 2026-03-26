# frozen_string_literal: true

module Legion
  class API < Sinatra::Base
    module Routes
      module Codegen
        def self.registered(app) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
          app.get '/api/codegen/status' do
            data = if defined?(Legion::MCP::SelfGenerate)
                     Legion::MCP::SelfGenerate.status
                   else
                     { available: false }
                   end
            json_response(data)
          end

          app.get '/api/codegen/generated' do
            unless defined?(Legion::Extensions::Codegen::Helpers::GeneratedRegistry)
              return json_response([], status_code: 200)
            end

            status_filter = params[:status]
            records = Legion::Extensions::Codegen::Helpers::GeneratedRegistry.list(status: status_filter)
            json_response(records)
          end

          app.get '/api/codegen/generated/:id' do |id|
            unless defined?(Legion::Extensions::Codegen::Helpers::GeneratedRegistry)
              halt 503, json_error('codegen_unavailable', 'codegen not available', status_code: 503)
            end

            record = Legion::Extensions::Codegen::Helpers::GeneratedRegistry.get(id: id)
            halt 404, json_error('not_found', 'record not found', status_code: 404) unless record

            json_response(record)
          end

          app.post '/api/codegen/generated/:id/approve' do |id|
            unless defined?(Legion::Extensions::Codegen::Runners::ReviewHandler)
              halt 503, json_error('codegen_unavailable', 'review handler not available', status_code: 503)
            end

            result = Legion::Extensions::Codegen::Runners::ReviewHandler.handle_verdict(
              review: { generation_id: id, verdict: :approve, confidence: 1.0 }
            )
            json_response(result)
          end

          app.post '/api/codegen/generated/:id/reject' do |id|
            unless defined?(Legion::Extensions::Codegen::Helpers::GeneratedRegistry)
              halt 503, json_error('codegen_unavailable', 'codegen not available', status_code: 503)
            end

            Legion::Extensions::Codegen::Helpers::GeneratedRegistry.update_status(id: id, status: 'rejected')
            json_response({ id: id, status: 'rejected' })
          end

          app.post '/api/codegen/generated/:id/retry' do |id|
            unless defined?(Legion::Extensions::Codegen::Helpers::GeneratedRegistry)
              halt 503, json_error('codegen_unavailable', 'codegen not available', status_code: 503)
            end

            Legion::Extensions::Codegen::Helpers::GeneratedRegistry.update_status(id: id, status: 'pending')
            json_response({ id: id, status: 'pending' })
          end

          app.get '/api/codegen/gaps' do
            data = if defined?(Legion::MCP::GapDetector)
                     Legion::MCP::GapDetector.detect_gaps
                   else
                     []
                   end
            json_response(data)
          end

          app.post '/api/codegen/cycle' do
            unless defined?(Legion::MCP::SelfGenerate)
              return json_response({ triggered: false, reason: 'self_generate not available' })
            end

            Legion::MCP::SelfGenerate.instance_variable_set(:@last_cycle_at, nil)
            result = Legion::MCP::SelfGenerate.run_cycle
            json_response(result)
          end
        end
      end
    end
  end
end
