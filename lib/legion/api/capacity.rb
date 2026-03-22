# frozen_string_literal: true

require_relative '../capacity/model'

module Legion
  class API < Sinatra::Base
    module Routes
      module Capacity
        def self.registered(app)
          app.get '/api/capacity' do
            workers = Routes::Capacity.fetch_worker_list
            model = Legion::Capacity::Model.new(workers: workers)
            json_response(model.aggregate)
          rescue StandardError => e
            Legion::Logging.error "API GET /api/capacity: #{e.class} — #{e.message}"
            json_error('capacity_error', e.message, status_code: 500)
          end

          app.get '/api/capacity/forecast' do
            workers = Routes::Capacity.fetch_worker_list
            model = Legion::Capacity::Model.new(workers: workers)
            forecast = model.forecast(
              days:        (params[:days] || 30).to_i,
              growth_rate: (params[:growth_rate] || 0).to_f
            )
            json_response(forecast)
          rescue StandardError => e
            Legion::Logging.error "API GET /api/capacity/forecast: #{e.class} — #{e.message}"
            json_error('capacity_error', e.message, status_code: 500)
          end

          app.get '/api/capacity/workers' do
            workers = Routes::Capacity.fetch_worker_list
            model = Legion::Capacity::Model.new(workers: workers)
            json_response(model.per_worker_stats)
          rescue StandardError => e
            Legion::Logging.error "API GET /api/capacity/workers: #{e.class} — #{e.message}"
            json_error('capacity_error', e.message, status_code: 500)
          end
        end

        def self.fetch_worker_list
          return [] unless defined?(Legion::Data::Model::DigitalWorker)

          Legion::Data::Model::DigitalWorker.all.map do |w|
            { worker_id: w.worker_id, status: w.lifecycle_state }
          end
        rescue StandardError => e
          Legion::Logging.warn "Capacity#fetch_worker_list failed: #{e.message}" if defined?(Legion::Logging)
          []
        end
      end
    end
  end
end
