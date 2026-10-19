# frozen_string_literal: true

require 'cgi'
require 'securerandom'

module Legion
  class API < Sinatra::Base
    module Routes
      module AuthTeams
        # In-memory pending auth states (state -> { verifier:, created_at:, result: })
        @pending = {}
        @mutex = Mutex.new

        class << self
          attr_reader :pending, :mutex
        end

        LEGACY_DEFAULT_SCOPES = 'OnlineMeetings.Read OnlineMeetingTranscript.Read.All offline_access'

        # Browser page shown after the Microsoft redirect. Prefers the shared page
        # from lex-identity-entra (Helpers::CallbackPage) so every Legion sign-in
        # surface looks the same; core does not depend on that gem, so an
        # identical fallback lives here.
        module CallbackPage
          module_function

          def success_html
            return entra_page.success_html if entra_page

            render(heading: 'LegionIO &mdash; Microsoft Teams / Entra sign-in complete',
                   message: 'You can close this tab.', color: '#107c10', icon: '&#10004;')
          end

          def failure_html(error = nil, description = nil)
            return entra_page.failure_html(error, description) if entra_page

            detail = [error, description].compact.map { |v| CGI.escapeHTML(v.to_s) }.reject(&:empty?).join(': ')
            detail_html = detail.empty? ? '' : "<p class=\"detail\">#{detail}</p>"
            render(heading: 'LegionIO &mdash; Microsoft Teams / Entra sign-in failed',
                   message: 'You can close this tab. To try again, run <code>legionio auth teams</code>.',
                   color: '#a4262c', icon: '&#10008;', extra: detail_html)
          end

          def entra_page
            return nil unless defined?(Legion::Extensions::Identity::Entra::Helpers::CallbackPage)

            page = Legion::Extensions::Identity::Entra::Helpers::CallbackPage
            page.respond_to?(:success_html) && page.respond_to?(:failure_html) ? page : nil
          end

          def render(heading:, message:, color:, icon:, extra: '')
            <<~HTML
              <!DOCTYPE html>
              <html lang="en"><head><meta charset="utf-8"><title>LegionIO &mdash; Microsoft Teams / Entra sign-in</title>
              <style>
                body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;text-align:center;padding:48px;color:#323130}
                .icon{font-size:48px;color:#{color}} h1{font-size:22px;color:#{color}} .detail{color:#605e5c;font-size:13px}
                code{background:#f3f2f1;padding:2px 6px;border-radius:3px}
              </style></head>
              <body><div class="icon">#{icon}</div><h1>#{heading}</h1><p>#{message}</p>#{extra}</body></html>
            HTML
          end
        end

        # tenant/client: microsoft_teams.* (legacy) then identity.entra.auth (what the daemon's
        # TokenManager refreshes with). Scopes: explicit request/teams setting, else the
        # delegated scope set the daemon expects (Entra Scopes registry), else the legacy default.
        def self.resolve_oauth_config(body_scopes = nil)
          teams = Legion::Settings[:microsoft_teams] || {}
          teams_auth = teams[:auth] || {}
          entra_auth = Legion::Settings.dig(:identity, :entra, :auth) || {}

          {
            tenant_id: teams[:tenant_id] || teams_auth[:tenant_id] || entra_auth[:tenant_id],
            client_id: teams[:client_id] || teams_auth[:client_id] || entra_auth[:client_id],
            scopes:    body_scopes || teams_auth.dig(:delegated, :scopes) || entra_delegated_scopes || LEGACY_DEFAULT_SCOPES
          }
        end

        def self.entra_delegated_scopes
          return nil unless defined?(Legion::Extensions::Identity::Entra::Helpers::Scopes)

          scopes = Legion::Extensions::Identity::Entra::Helpers::Scopes.resolve(pattern: :delegated)
          scopes.is_a?(String) && !scopes.strip.empty? ? scopes : nil
        rescue StandardError => e
          Legion::Logging.warn "[auth_teams] action=resolve_scopes error=#{e.class}: #{e.message}" if defined?(Legion::Logging)
          nil
        end

        def self.registered(app)
          register_store_helper(app)
          register_authorize(app)
          register_status(app)
          register_callback(app)
        end

        def self.register_authorize(app)
          app.post '/api/auth/teams/authorize' do
            body = parse_request_body
            config = AuthTeams.resolve_oauth_config(body[:scopes])
            tenant_id = config[:tenant_id]
            client_id = config[:client_id]
            scopes = config[:scopes]

            unless tenant_id && client_id
              halt 422, json_error('missing_config',
                                   'tenant_id and client_id required (identity.entra.auth or microsoft_teams)',
                                   status_code: 422)
            end

            state = SecureRandom.hex(32)
            verifier = SecureRandom.urlsafe_base64(32)
            challenge = Base64.urlsafe_encode64(
              Digest::SHA256.digest(verifier), padding: false
            )

            port = Legion::Settings.dig(:api, :port) || 4567
            redirect_uri = "http://127.0.0.1:#{port}/api/auth/teams/callback"

            authorize_url = "https://login.microsoftonline.com/#{tenant_id}/oauth2/v2.0/authorize?" \
                            "client_id=#{client_id}&response_type=code&redirect_uri=#{::URI.encode_www_form_component(redirect_uri)}" \
                            "&scope=#{::URI.encode_www_form_component(scopes)}" \
                            "&state=#{state}&code_challenge=#{challenge}&code_challenge_method=S256"

            AuthTeams.mutex.synchronize do
              AuthTeams.pending[state] = { verifier: verifier, created_at: Time.now, result: nil,
                                           tenant_id: tenant_id, client_id: client_id,
                                           redirect_uri: redirect_uri, scopes: scopes }
            end

            json_response({ authorize_url: authorize_url, state: state })
          end
        end

        def self.register_status(app)
          app.get '/api/auth/teams/status' do
            state = params[:state]
            halt 422, json_error('missing_state', 'state parameter required', status_code: 422) unless state

            entry = AuthTeams.mutex.synchronize { AuthTeams.pending[state] }
            halt 404, json_error('unknown_state', 'no pending auth for this state', status_code: 404) unless entry

            if entry[:result]
              AuthTeams.mutex.synchronize { AuthTeams.pending.delete(state) }
              json_response(entry[:result])
            else
              json_response({ authenticated: false, waiting: true })
            end
          end
        end

        def self.register_callback(app)
          app.get '/api/auth/teams/callback' do
            content_type 'text/html; charset=utf-8'
            code = params[:code]
            state = params[:state]
            error = params[:error]

            entry = AuthTeams.mutex.synchronize { AuthTeams.pending[state] }

            if error || !entry || !code
              error ||= entry ? 'missing_code' : 'unknown_state'
              description = params[:error_description]
              description ||= 'This sign-in link expired or was already used.' unless entry
              Legion::Logging.warn "[auth_teams] action=callback_failed error=#{error}" if defined?(Legion::Logging)
              AuthTeams.mutex.synchronize { entry[:result] = { authenticated: false, error: error } } if entry
              status 400
              return CallbackPage.failure_html(error, description)
            end

            token_body = exchange_teams_code(entry, code)

            if token_body[:access_token]
              unless store_teams_token(token_body, token_body[:scope] || entry[:scopes],
                                       tenant_id: entry[:tenant_id], client_id: entry[:client_id])
                AuthTeams.mutex.synchronize { entry[:result] = { authenticated: false, error: 'token_store_failed' } }
                status 500
                return CallbackPage.failure_html('token_store_failed', 'Signed in, but the daemon could not save the token. Check the daemon log.')
              end

              AuthTeams.mutex.synchronize { entry[:result] = { authenticated: true } }
              CallbackPage.success_html
            else
              err = token_body[:error] || 'token_exchange_failed'
              desc = token_body[:error_description]
              Legion::Logging.error "Teams OAuth token exchange failed: #{err}: #{desc}" if defined?(Legion::Logging)
              AuthTeams.mutex.synchronize { entry[:result] = { authenticated: false, error: desc || err } }
              status 400
              CallbackPage.failure_html(err, desc)
            end
          rescue StandardError => e
            Legion::Logging.log_exception(e, payload_summary: 'Teams OAuth callback error', component_type: :api) if defined?(Legion::Logging)
            AuthTeams.mutex.synchronize { entry[:result] = { authenticated: false, error: e.message } } if entry
            status 500
            CallbackPage.failure_html('callback_error', e.message)
          end
        end

        module TeamsTokenHelper
          # Writes the delegated token the daemon actually reads (Entra TokenManager :delegated).
          # TokenManager.save_token also clears lex-identity-entra's refresh-failure cache and the
          # automatic-sign-in backoff (>= 0.6.1). Returns true on success, false otherwise.
          def store_teams_token(token_body, scopes, tenant_id: nil, client_id: nil)
            require 'legion/extensions/identity/entra/helpers/token_manager'
            Legion::Extensions::Identity::Entra::Helpers::TokenManager.save_token(
              :delegated,
              access_token:  token_body[:access_token],
              refresh_token: token_body[:refresh_token],
              expires_in:    token_body[:expires_in] || 3600,
              scopes:        scopes,
              tenant_id:     tenant_id,
              client_id:     client_id
            )
            reset_entra_delegated_client
            Legion::Logging.info 'Teams delegated token stored' if defined?(Legion::Logging)
            true
          rescue StandardError, LoadError => e
            Legion::Logging.warn "Failed to store Teams token: #{e.class}: #{e.message}" if defined?(Legion::Logging)
            false
          end

          # Drop the cached Entra delegated client so the next Graph call uses the new token.
          def reset_entra_delegated_client
            return unless defined?(Legion::Extensions::Identity::Entra::Client) &&
                          Legion::Extensions::Identity::Entra::Client.respond_to?(:reset!)

            Legion::Extensions::Identity::Entra::Client.reset!(pattern: :delegated)
          end

          def exchange_teams_code(entry, code)
            require 'net/http'
            token_uri = ::URI.parse("https://login.microsoftonline.com/#{entry[:tenant_id]}/oauth2/v2.0/token")
            response = ::Net::HTTP.post_form(token_uri, {
                                               'client_id'     => entry[:client_id],
                                               'grant_type'    => 'authorization_code',
                                               'code'          => code,
                                               'redirect_uri'  => entry[:redirect_uri],
                                               'code_verifier' => entry[:verifier],
                                               'scope'         => entry[:scopes]
                                             })
            Legion::JSON.load(response.body)
          end
        end

        def self.register_store_helper(app)
          app.helpers TeamsTokenHelper
        end

        class << self
          private :register_authorize, :register_status, :register_callback, :register_store_helper
        end
      end
    end
  end
end
