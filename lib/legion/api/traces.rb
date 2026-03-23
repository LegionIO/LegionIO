# frozen_string_literal: true

module Legion
  class API < Sinatra::Base
    module Routes
      module Traces
        def self.registered(app)
          register_search(app)
          register_summary(app)
          register_anomalies(app)
        end

        def self.register_search(app)
          app.post '/api/traces/search' do
            require_trace_search!
            body = parse_request_body
            halt 422, json_error('missing_field', 'query is required', status_code: 422) unless body[:query]

            result = Legion::TraceSearch.search(body[:query], limit: body[:limit] || 50)
            json_response(result)
          end
        end

        def self.register_summary(app)
          app.post '/api/traces/summary' do
            require_trace_search!
            body = parse_request_body
            halt 422, json_error('missing_field', 'query is required', status_code: 422) unless body[:query]

            result = Legion::TraceSearch.summarize(body[:query])
            json_response(result)
          end
        end

        def self.register_anomalies(app)
          app.get '/api/traces/anomalies' do
            require_trace_search!
            threshold = (params[:threshold] || 2.0).to_f
            result = Legion::TraceSearch.detect_anomalies(threshold: threshold)
            json_response(result)
          end
        end

        class << self
          private :register_search, :register_summary, :register_anomalies
        end
      end
    end
  end
end
