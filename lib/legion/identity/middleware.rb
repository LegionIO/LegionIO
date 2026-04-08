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

        request = if auth_claims
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

        env['legion.principal'] = request

        # Bridge to RBAC principal if legion-rbac is loaded.
        # This is a data bridge — set regardless of enforce/audit mode so
        # the RBAC middleware always has a typed principal to evaluate.
        # Guard: require Legion::Rbac.enabled? to confirm the real gem is loaded
        # (not a minimal test stub), and rescue construction errors defensively.
        if request && defined?(Legion::Rbac::Principal) &&
           defined?(Legion::Rbac) && Legion::Rbac.respond_to?(:enabled?) &&
           Legion::Rbac.enabled?
          begin
            env['legion.rbac_principal'] = Legion::Rbac::Principal.new(
              id:    request.principal_id,
              type:  request.kind == :service ? :worker : request.kind,
              roles: request.roles,
              team:  request.metadata&.dig(:team)
            )
          rescue StandardError
            # Best-effort bridge: leave legion.rbac_principal unset on construction errors.
          end
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
        # Use worker_id as principal_id when present — worker tokens encode both
        # worker_id and sub=owner_msid, and we want the worker's identity, not the owner's.
        principal_id = claims[:worker_id] || claims[:sub] || claims[:owner_msid]

        # Separate group OIDs/names from Entra app roles — they are NOT equivalent.
        # claims[:groups] = group OIDs/names (for GroupRoleMapper)
        # claims[:roles]  = Entra app roles (pre-assigned at token-exchange time)
        groups = Array(claims[:groups])
        roles  = Array(claims[:roles])

        # Enrich with group-derived RBAC roles when legion-rbac is loaded (including audit mode).
        resolved_roles = if defined?(Legion::Rbac::GroupRoleMapper) &&
                            Legion::Rbac.respond_to?(:enabled?) &&
                            Legion::Rbac.enabled?
                           group_roles = Legion::Rbac::GroupRoleMapper.resolve_roles(groups: groups)
                           (roles + group_roles).uniq
                         else
                           roles
                         end

        Identity::Request.from_auth_context({
                                              sub:            principal_id,
                                              name:           claims[:name] || claims[:sub],
                                              kind:           determine_kind(claims, method),
                                              groups:         groups,
                                              resolved_roles: resolved_roles,
                                              source:         method&.to_sym
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
