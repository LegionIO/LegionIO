# frozen_string_literal: true

module Legion
  module Identity
    class Middleware
      SKIP_PATHS     = %w[/api/health /api/ready /api/openapi.json /metrics].freeze
      LOOPBACK_BINDS = %w[127.0.0.1 ::1 localhost].freeze

      def initialize(app, require_auth: false)
        @app          = app
        @require_auth = require_auth
      end

      def call(env)
        return @app.call(env) if skip_path?(env['PATH_INFO'])

        # Bridge from existing auth middleware
        auth_claims  = env['legion.auth']
        auth_method  = env['legion.auth_method']

        env['legion.principal'] = if auth_claims
                                    build_request(auth_claims, auth_method)
                                  elsif @require_auth
                                    # Auth middleware already handled 401 for protected paths;
                                    # this is a safety net for any path that slipped through.
                                    nil
                                  else
                                    # No auth required (loopback bind, lite mode, etc.).
                                    # Set a system-level principal so audit trails always have an identity.
                                    system_principal
                                  end

        @app.call(env)
      end

      # Returns whether the API should require authentication.
      # Skips auth for lite mode and loopback binds (local dev / CI).
      def self.require_auth?(bind:, mode:)
        return false if mode == :lite
        return false if LOOPBACK_BINDS.include?(bind)

        true
      end

      private

      def skip_path?(path)
        SKIP_PATHS.any? { |p| path.start_with?(p) }
      end

      def build_request(claims, method)
        Identity::Request.from_auth_context({
                                              sub:    claims[:sub] || claims[:worker_id] || claims[:owner_msid],
                                              name:   claims[:name] || claims[:sub],
                                              kind:   determine_kind(claims, method),
                                              groups: Array(claims[:roles] || claims[:groups]),
                                              source: method&.to_sym
                                            })
      end

      def determine_kind(claims, method)
        return :service if claims[:scope] == 'worker' || claims[:worker_id]
        return :human   if method == 'kerberos' || claims[:scope] == 'human'

        :human
      end

      def system_principal
        @system_principal ||= Identity::Request.new(
          principal_id:   'system:local',
          canonical_name: 'system',
          kind:           :service,
          groups:         [],
          source:         :local
        )
      end
    end
  end
end
