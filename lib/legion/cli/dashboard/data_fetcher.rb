# frozen_string_literal: true

require 'net/http'

module Legion
  module CLI
    module Dashboard
      class DataFetcher
        def initialize(base_url: 'http://localhost:4567')
          @base_url = base_url
        end

        def workers
          fetch('/api/workers') || []
        end

        def health
          fetch('/api/health') || {}
        end

        def recent_events(limit: 10)
          fetch("/api/events/recent?limit=#{limit}") || []
        end

        def summary
          {
            workers:    workers,
            health:     health,
            events:     recent_events,
            fetched_at: Time.now
          }
        end

        private

        def fetch(path)
          uri = URI("#{@base_url}#{path}")
          response = Net::HTTP.get_response(uri)
          return nil unless response.is_a?(Net::HTTPSuccess)

          Legion::JSON.load(response.body)
        rescue StandardError => e
          Legion::Logging.warn("Dashboard::DataFetcher#fetch failed for #{path}: #{e.message}") if defined?(Legion::Logging)
          nil
        end
      end
    end
  end
end
