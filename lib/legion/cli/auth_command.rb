# frozen_string_literal: true

require 'thor'
require 'uri'
require 'fileutils'

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

      desc 'kerberos', 'Authenticate using Kerberos TGT from your workstation'
      method_option :api_url, type: :string, desc: 'Legion API base URL'
      method_option :realm,   type: :string, desc: 'Kerberos realm override'
      def kerberos
        klist_output = `klist 2>&1`
        unless $CHILD_STATUS&.success?
          say 'No Kerberos ticket found. Run kinit first or check your domain connection.', :red
          return
        end

        principal_match = klist_output.match(/Principal:\s+(\S+)/)
        unless principal_match
          say 'Could not detect Kerberos principal from klist output.', :red
          return
        end

        principal = principal_match[1]
        realm     = options[:realm] || principal.split('@', 2).last
        say 'Detected Kerberos ticket:', :green
        say "  Principal: #{principal}"
        say "  Realm: #{realm}"

        api_url = resolve_api_url
        say "Authenticating to #{api_url}..."

        token    = build_spnego_token(api_url)
        response = send_negotiate_request(api_url, token)
        handle_negotiate_response(response)
      rescue StandardError => e
        say "Kerberos auth error: #{e.message}", :red
      end

      default_task :teams

      no_commands do
        def formatter
          @formatter ||= Output::Formatter.new(
            json:  options[:json],
            color: !options[:no_color]
          )
        end

        def resolve_api_url
          url = options[:api_url]
          url ||= Legion::Settings.dig(:api, :url) if defined?(Legion::Settings)
          url || 'http://127.0.0.1:4567'
        end

        def build_spnego_token(api_url)
          require 'gssapi'
          require 'base64'
          host = ::URI.parse(api_url).host
          spnego = GSSAPI::Simple.new(host, 'HTTP')
          ::Base64.strict_encode64(spnego.init_context)
        end

        def send_negotiate_request(api_url, token)
          require 'net/http'
          uri = ::URI.parse("#{api_url}/api/auth/negotiate")
          http = ::Net::HTTP.new(uri.host, uri.port)
          request = ::Net::HTTP::Get.new(uri.request_uri)
          request['Authorization'] = "Negotiate #{token}"
          http.request(request)
        end

        def handle_negotiate_response(response)
          if response.code.to_i == 200
            body = ::JSON.parse(response.body) rescue {} # rubocop:disable Style/RescueModifier
            data = body.is_a?(Hash) ? (body['data'] || body) : {}
            token_val = data['token']
            if token_val
              save_credentials(token_val)
              display_negotiate_identity(data)
              say 'Login successful (kerberos)', :green
            else
              say 'Authentication succeeded but no token in response', :yellow
            end
          else
            say "Authentication failed: HTTP #{response.code}", :red
            say response.body.to_s, :red
          end
        end

        def display_negotiate_identity(data)
          name = data['display_name'] || [data['first_name'], data['last_name']].compact.join(' ')
          say "  Name: #{name}", :green unless name.empty?
          say "  Email: #{data['email']}", :green if data['email']
          say "  Roles: #{Array(data['roles']).join(', ')}", :green
          say '  Token saved to ~/.legionio/credentials', :green
        end

        def save_credentials(token_val)
          credentials_dir = ::File.join(::Dir.home, '.legionio')
          ::FileUtils.mkdir_p(credentials_dir)
          cred_path = ::File.join(credentials_dir, 'credentials')
          ::File.write(cred_path, token_val)
          ::File.chmod(0o600, cred_path)
        end
      end
    end
  end
end
