# frozen_string_literal: true

require 'thor'

module Legion
  module CLI
    class Auth < Thor
      def self.exit_on_failure?
        true
      end

      class_option :json,     type: :boolean, default: false, desc: 'Output as JSON'
      class_option :no_color, type: :boolean, default: false, desc: 'Disable color output'

      desc 'teams', 'Authenticate with Microsoft Teams using your browser'
      method_option :tenant_id,  type: :string, desc: 'Azure AD tenant ID'
      method_option :client_id,  type: :string, desc: 'Entra application client ID'
      method_option :scopes,     type: :string, desc: 'OAuth scopes to request'
      def teams
        out = formatter
        require 'legion/settings'
        Legion::Settings.load unless Legion::Settings.instance_variable_get(:@loader)

        auth_settings = Legion::Settings.dig(:microsoft_teams, :auth) || {}
        delegated = auth_settings[:delegated] || {}

        tenant_id = options[:tenant_id] || auth_settings[:tenant_id]
        client_id = options[:client_id] || auth_settings[:client_id]
        scopes    = options[:scopes] || delegated[:scopes] ||
                    'OnlineMeetings.Read OnlineMeetingTranscript.Read.All offline_access'

        unless tenant_id && client_id
          out.error('Missing tenant_id or client_id. Set in settings or pass --tenant-id and --client-id')
          raise SystemExit, 1
        end

        require 'legion/extensions/microsoft_teams/helpers/browser_auth'
        browser_auth = Legion::Extensions::MicrosoftTeams::Helpers::BrowserAuth.new(
          tenant_id: tenant_id,
          client_id: client_id,
          scopes:    scopes
        )

        out.header('Microsoft Teams Authentication')
        result = browser_auth.authenticate

        if result[:error]
          out.error("Authentication failed: #{result[:error]} - #{result[:description]}")
          raise SystemExit, 1
        end

        body = result[:result]
        out.success('Authentication successful!')

        require 'legion/extensions/microsoft_teams/helpers/token_cache'
        cache = Legion::Extensions::MicrosoftTeams::Helpers::TokenCache.new
        cache.store_delegated_token(
          access_token:  body['access_token'],
          refresh_token: body['refresh_token'],
          expires_in:    body['expires_in'] || 3600,
          scopes:        scopes
        )

        if cache.save_to_vault
          out.success('Token saved to Vault')
        else
          out.warn('Could not save token to Vault (Vault may not be connected)')
        end

        return unless options[:json]

        out.json({ authenticated: true, scopes: scopes, expires_in: body['expires_in'] })
      end

      default_task :teams

      no_commands do
        def formatter
          @formatter ||= Output::Formatter.new(
            json:  options[:json],
            color: !options[:no_color]
          )
        end
      end
    end
  end
end
