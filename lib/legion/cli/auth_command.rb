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
        Connection.ensure_settings

        port = begin
          Legion::Settings.dig(:api, :port) || 4567
        rescue StandardError
          4567
        end

        out.header('Microsoft Teams Authentication')

        require 'net/http'
        require 'legion/json'

        # Ask the daemon for the authorize URL
        uri = ::URI.parse("http://127.0.0.1:#{port}/api/auth/teams/authorize")
        params = {}
        params[:scopes] = options[:scopes] if options[:scopes]
        response = ::Net::HTTP.post(uri, Legion::JSON.dump(params), 'Content-Type' => 'application/json')
        parsed = Legion::JSON.load(response.body)

        unless response.code.to_i == 200 && parsed.dig(:data, :authorize_url)
          error_msg = parsed.dig(:error, :message) || "HTTP #{response.code}"
          out.error("Daemon returned: #{error_msg}")
          raise SystemExit, 1
        end

        url = parsed[:data][:authorize_url]
        out.info('Opening browser for Microsoft login...')
        system('open', url) || out.warn("Open this URL manually:\n  #{url}")
        out.info('Waiting for callback on daemon...')

        # Poll daemon for auth result
        poll_uri = ::URI.parse("http://127.0.0.1:#{port}/api/auth/teams/status?state=#{parsed.dig(:data, :state)}")
        30.times do
          sleep 2
          poll_response = ::Net::HTTP.get_response(poll_uri)
          poll_data = Legion::JSON.load(poll_response.body)

          if poll_data.dig(:data, :authenticated)
            out.success('Authentication successful! Token stored by daemon.')
            return
          end

          next unless poll_data.dig(:data, :error)

          out.error("Authentication failed: #{poll_data[:data][:error]}")
          raise SystemExit, 1
        end

        out.error('Timed out waiting for authentication (60s)')
        raise SystemExit, 1
      rescue Errno::ECONNREFUSED
        out = formatter
        out.error('Daemon not running. Start it first: legionio start')
        raise SystemExit, 1
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
        Legion::Logging.error("Auth#kerberos failed: #{e.message}") if defined?(Legion::Logging)
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
            body = begin
              ::JSON.parse(response.body)
            rescue ::JSON::ParserError => e
              Legion::Logging.debug("Auth#handle_negotiate_response JSON parse failed: #{e.message}") if defined?(Legion::Logging)
              {}
            end
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
