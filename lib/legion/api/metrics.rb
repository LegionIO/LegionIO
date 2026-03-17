# frozen_string_literal: true

module Legion
  class API < Sinatra::Base
    module Routes
      module Metrics
        def self.registered(app)
          app.get '/metrics' do
            unless defined?(Legion::Metrics) && Legion::Metrics.available?
              content_type 'text/plain'
              halt 404, 'prometheus-client gem not available'
            end

            Legion::Metrics.refresh_gauges
            content_type 'text/plain; version=0.0.4; charset=utf-8'
            Legion::Metrics.render
          end
        end
      end
    end
  end
end
