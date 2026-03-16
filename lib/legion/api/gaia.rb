# frozen_string_literal: true

module Legion
  class API < Sinatra::Base
    module Routes
      module Gaia
        def self.registered(app)
          app.get '/api/gaia/status' do
            if defined?(Legion::Gaia) && Legion::Gaia.respond_to?(:started?) && Legion::Gaia.started?
              json_response(Legion::Gaia.status)
            else
              json_response({ started: false }, status_code: 503)
            end
          end
        end
      end
    end
  end
end
