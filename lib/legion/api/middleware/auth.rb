# frozen_string_literal: true

# TODO: Implement full authentication before production use.
# Planned: JWT via legion-crypt, API key support, role-based access.
# See: docs/plans/2026-03-13-legion-api-design.md
#
# Usage (when implemented):
#   Legion::API.use Legion::API::Middleware::Auth
#
module Legion
  class API < Sinatra::Base
    module Middleware
      class Auth
        def initialize(app)
          @app = app
        end

        def call(env)
          # Alpha: pass-through, no authentication
          @app.call(env)
        end
      end
    end
  end
end
