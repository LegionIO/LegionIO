# frozen_string_literal: true

require 'thor'

module Legion
  module CLI
    class Cost < Thor
      def self.exit_on_failure?
        true
      end

      class_option :url, type: :string, default: 'http://localhost:4567', desc: 'API base URL'

      desc 'summary', 'Overall cost summary'
      option :period, type: :string, default: 'month', desc: 'Time period (day, week, month)'
      def summary
        data = build_client.summary(period: options[:period])
        say 'Cost Summary', :green
        say '-' * 30
        say format('  Today:      $%.2f', data[:today] || 0)
        say format('  This Week:  $%.2f', data[:week] || 0)
        say format('  This Month: $%.2f', data[:month] || 0)
        say "  Workers:    #{data[:workers] || 0}"
      end

      desc 'worker ID', 'Per-worker cost breakdown'
      def worker(id)
        data = build_client.worker_cost(id)
        if data.empty?
          say "No cost data for worker #{id}", :yellow
          return
        end
        say "Worker: #{id}", :green
        say '-' * 30
        data.each { |k, v| say "  #{k}: #{v}" }
      end

      desc 'top', 'Top cost consumers'
      option :limit, type: :numeric, default: 10
      def top
        consumers = build_client.top_consumers(limit: options[:limit])
        if consumers.empty?
          say 'No cost data available', :yellow
          return
        end
        say 'Top Cost Consumers', :green
        say '-' * 40
        consumers.each_with_index do |c, i|
          cost = c.dig(:cost, :total_cost_usd) || 0
          say format('  %<rank>d. %-25<name>s $%<cost>.2f', rank: i + 1, name: c[:worker_id], cost: cost)
        end
      end

      desc 'export', 'Export cost data'
      option :format, type: :string, default: 'json', enum: %w[json csv]
      option :period, type: :string, default: 'month'
      def export
        data = build_client.summary(period: options[:period])
        case options[:format]
        when 'json'
          say Legion::JSON.dump(data)
        when 'csv'
          say 'period,today,week,month,workers'
          say "#{options[:period]},#{data[:today]},#{data[:week]},#{data[:month]},#{data[:workers]}"
        end
      end

      private

      def build_client
        require 'legion/cli/cost/data_client'
        CostData::Client.new(base_url: options[:url])
      end
    end
  end
end
