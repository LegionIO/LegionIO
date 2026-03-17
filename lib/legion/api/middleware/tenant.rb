# frozen_string_literal: true

module Legion
  class API < Sinatra::Base
    module Middleware
      class Tenant
        SKIP_PATHS = %w[/api/health /api/ready /api/openapi.json /metrics].freeze

        def initialize(app, opts = {})
          @app = app
          @opts = opts
        end

        def call(env)
          return @app.call(env) if skip_path?(env['PATH_INFO'])

          tenant_id = extract_tenant(env)
          Legion::TenantContext.set(tenant_id) if tenant_id
          @app.call(env)
        ensure
          Legion::TenantContext.clear
        end

        private

        def skip_path?(path)
          SKIP_PATHS.any? { |sp| path.start_with?(sp) }
        end

        def extract_tenant(env)
          env['legion.tenant_id'] || env['HTTP_X_TENANT_ID']
        end
      end
    end
  end
end
