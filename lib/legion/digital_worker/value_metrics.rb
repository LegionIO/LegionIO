# frozen_string_literal: true

module Legion
  module DigitalWorker
    module ValueMetrics
      METRIC_TYPES = %i[counter gauge duration].freeze

      def self.record(worker_id:, metric_name:, metric_type:, value:, metadata: {})
        raise ArgumentError, "invalid metric_type: #{metric_type}" unless METRIC_TYPES.include?(metric_type)

        record = {
          worker_id:   worker_id,
          metric_name: metric_name.to_s,
          metric_type: metric_type.to_s,
          value:       value.to_f,
          metadata:    Legion::JSON.dump(metadata),
          recorded_at: Time.now.utc
        }

        if defined?(Legion::Data) && Legion::Data.connection.table_exists?(:value_metrics)
          Legion::Data.connection[:value_metrics].insert(record)
        end

        Legion::Logging.debug "[value_metrics] recorded: worker=#{worker_id} #{metric_name}=#{value} (#{metric_type})"
        record
      end

      def self.for_worker(worker_id:, metric_name: nil, since: nil)
        return [] unless defined?(Legion::Data) && Legion::Data.connection.table_exists?(:value_metrics)

        ds = Legion::Data.connection[:value_metrics].where(worker_id: worker_id)
        ds = ds.where(metric_name: metric_name.to_s) if metric_name
        ds = ds.where { recorded_at >= since } if since
        ds.order(:recorded_at).all
      end

      def self.summary(worker_id:)
        return {} unless defined?(Legion::Data) && Legion::Data.connection.table_exists?(:value_metrics)

        ds = Legion::Data.connection[:value_metrics].where(worker_id: worker_id)
        metrics = ds.select(:metric_name).distinct.select_map(:metric_name)

        metrics.each_with_object({}) do |name, acc|
          subset = ds.where(metric_name: name)
          acc[name] = {
            count:  subset.count,
            sum:    subset.sum(:value) || 0,
            avg:    subset.avg(:value)&.round(4) || 0,
            min:    subset.min(:value) || 0,
            max:    subset.max(:value) || 0,
            latest: subset.order(Sequel.desc(:recorded_at)).first&.dig(:value)
          }
        end
      end
    end
  end
end
