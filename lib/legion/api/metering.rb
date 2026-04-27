# frozen_string_literal: true

module Legion
  class API < Sinatra::Base
    module Routes
      module Metering
        def self.registered(app)
          register_helpers(app)
          register_summary_route(app)
          register_rollup_route(app)
          register_by_model_route(app)
        end

        def self.register_helpers(app)
          app.helpers do
            define_method(:require_metering!) do
              return if defined?(Legion::Extensions::Metering::Runners::Metering)

              halt 503, json_error('metering_unavailable', 'lex-metering is not loaded', status_code: 503)
            end

            define_method(:metering_table?) do
              defined?(Legion::Data) && Legion::Data.respond_to?(:connected?) &&
                Legion::Data.connected? && Legion::Data.connection.table_exists?(:metering_records)
            end
          end
        end

        def self.register_summary_route(app)
          app.get '/api/metering' do
            require_metering!
            unless metering_table?
              return json_response({ total_cost_usd: 0.0, total_tokens: 0, total_requests: 0,
                                     note: 'metering_records table not available' })
            end

            ds = Legion::Data.connection[:metering_records]
            json_response({
                            total_cost_usd: (ds.sum(:cost_usd) || 0).to_f,
                            total_tokens:   (ds.sum(:total_tokens) || 0).to_i,
                            total_requests: ds.count
                          })
          rescue StandardError => e
            Legion::Logging.log_exception(e, payload_summary: 'GET /api/metering', component_type: :api)
            json_response({ total_cost_usd: 0.0, total_tokens: 0, total_requests: 0, error: e.message })
          end
        end

        def self.register_rollup_route(app)
          app.get '/api/metering/rollup' do
            require_metering!
            return json_response({ rollup: [], period: 'hourly', note: 'metering_records table not available' }) unless metering_table?

            return json_response({ rollup: [], period: 'hourly' }) unless defined?(Legion::Extensions::Metering::Runners::Rollup)

            result = Legion::Extensions::Metering::Runners::Rollup.rollup_hour
            json_response(result)
          rescue StandardError => e
            Legion::Logging.log_exception(e, payload_summary: 'GET /api/metering/rollup', component_type: :api)
            json_response({ rollup: [], period: 'hourly', error: e.message })
          end
        end

        def self.register_by_model_route(app)
          app.get '/api/metering/by_model' do
            require_metering!
            return json_response({ models: [], note: 'metering_records table not available' }) unless metering_table?

            ds = Legion::Data.connection[:metering_records]
            models = ds.group(:model_id).select_append do
              [count.as(:call_count),
               sum(total_tokens).as(:total_tokens),
               sum(cost_usd).as(:total_cost),
               avg(latency_ms).as(:avg_latency_ms)]
            end.all

            json_response({ models: models })
          rescue StandardError => e
            Legion::Logging.log_exception(e, payload_summary: 'GET /api/metering/by_model', component_type: :api)
            json_response({ models: [], error: e.message })
          end
        end

        private_class_method :register_helpers, :register_summary_route, :register_rollup_route, :register_by_model_route
      end
    end
  end
end
