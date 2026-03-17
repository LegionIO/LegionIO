# frozen_string_literal: true

require 'net/http'

module Legion
  module CLI
    module CostData
      class Client
        def initialize(base_url: 'http://localhost:4567')
          @base_url = base_url
        end

        def summary(period: 'month')
          fetch("/api/costs/summary?period=#{period}") || default_summary
        end

        def worker_cost(worker_id)
          fetch("/api/workers/#{worker_id}/value") || {}
        end

        def top_consumers(limit: 10)
          workers = fetch('/api/workers') || []
          workers = workers[:data] if workers.is_a?(Hash) && workers.key?(:data)
          results = Array(workers).map do |w|
            id = w[:worker_id] || w[:id]
            cost = worker_cost(id)
            { worker_id: id, cost: cost }
          end
          results.sort_by { |w| -(w.dig(:cost, :total_cost_usd) || 0) }.first(limit)
        end

        private

        def fetch(path)
          uri = URI("#{@base_url}#{path}")
          http = Net::HTTP.new(uri.host, uri.port)
          http.open_timeout = 5
          http.read_timeout = 5
          response = http.request(Net::HTTP::Get.new(uri))
          return nil unless response.is_a?(Net::HTTPSuccess)

          Legion::JSON.load(response.body)
        rescue StandardError
          nil
        end

        def default_summary
          { today: 0.0, week: 0.0, month: 0.0, workers: 0 }
        end
      end
    end
  end
end
