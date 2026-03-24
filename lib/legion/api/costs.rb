# frozen_string_literal: true

module Legion
  class API < Sinatra::Base
    module Routes
      module Costs
        def self.registered(app)
          app.helpers CostHelpers
          register_summary(app)
          register_by_worker(app)
          register_by_extension(app)
        end

        def self.register_summary(app)
          app.get '/api/costs/summary' do
            halt 503, json_error('data_unavailable', 'metering data not available', status_code: 503) unless metering_available?

            period = params[:period] || 'month'
            json_response(cost_summary(period))
          end
        end

        def self.register_by_worker(app)
          app.get '/api/costs/workers' do
            halt 503, json_error('data_unavailable', 'metering data not available', status_code: 503) unless metering_available?

            limit = (params[:limit] || 10).to_i.clamp(1, 100)
            json_response(costs_by_worker(limit))
          end
        end

        def self.register_by_extension(app)
          app.get '/api/costs/extensions' do
            halt 503, json_error('data_unavailable', 'metering data not available', status_code: 503) unless metering_available?

            limit = (params[:limit] || 10).to_i.clamp(1, 100)
            json_response(costs_by_extension(limit))
          end
        end

        class << self
          private :register_summary, :register_by_worker, :register_by_extension
        end
      end

      module CostHelpers
        def metering_available?
          defined?(Legion::Data) && Legion::Data.respond_to?(:connection) && !Legion::Data.connection.nil?
        rescue StandardError => e
          Legion::Logging.debug("CostHelpers#metering_available? check failed: #{e.message}") if defined?(Legion::Logging)
          false
        end

        def metering_records
          Legion::Data.connection[:metering_records]
        end

        def cost_summary(period)
          now = Time.now.utc
          today_start = Time.utc(now.year, now.month, now.day)
          week_start = today_start - ((today_start.wday % 7) * 86_400)
          month_start = Time.utc(now.year, now.month, 1)

          ds = metering_records
          worker_count = ds.distinct.select(:worker_id).exclude(worker_id: nil).count

          {
            today:   sum_cost_since(ds, today_start),
            week:    sum_cost_since(ds, week_start),
            month:   sum_cost_since(ds, month_start),
            workers: worker_count,
            period:  period
          }
        rescue ::Sequel::Error => e
          { today: 0.0, week: 0.0, month: 0.0, workers: 0, error: e.message }
        end

        def costs_by_worker(limit)
          metering_records
            .group(:worker_id)
            .select(
              :worker_id,
              ::Sequel.function(:sum, :cost_usd).as(:total_cost),
              ::Sequel.function(:count, ::Sequel.lit('*')).as(:call_count)
            )
            .order(::Sequel.desc(:total_cost))
            .limit(limit)
            .all
        rescue ::Sequel::Error
          []
        end

        def costs_by_extension(limit)
          metering_records
            .exclude(extension: nil)
            .group(:extension)
            .select(
              :extension,
              ::Sequel.function(:sum, :cost_usd).as(:total_cost),
              ::Sequel.function(:count, ::Sequel.lit('*')).as(:call_count)
            )
            .order(::Sequel.desc(:total_cost))
            .limit(limit)
            .all
        rescue ::Sequel::Error
          []
        end

        private

        def sum_cost_since(dataset, since_time)
          (dataset.where(::Sequel.lit('recorded_at >= ?', since_time)).sum(:cost_usd) || 0.0).to_f.round(6)
        end
      end
    end
  end
end
