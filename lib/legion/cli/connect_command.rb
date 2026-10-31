# frozen_string_literal: true

require 'thor'

module Legion
  module CLI
    class ConnectCommand < Thor
      namespace :connect

      def self.exit_on_failure?
        true
      end

      PROVIDERS = %w[microsoft github google].freeze
      STATE_COLORS = { 'connected' => :green, 'revoked' => :red, 'not connected' => :yellow }.freeze
      CHATGPT_STATES = {
        'missing' => :yellow, 'authenticated' => :green,
        'expired_refreshable' => :yellow, 'reauth_required' => :red
      }.freeze
      CHATGPT_INSTALL = 'Install or update lex-llm-openai >= 0.6.7 in the same Ruby environment as Legion.'

      desc 'microsoft', 'Connect a Microsoft account (OAuth2 delegated auth)'
      method_option :tenant_id,  type: :string, desc: 'Azure tenant ID'
      method_option :client_id,  type: :string, desc: 'Application client ID'
      method_option :scope,      type: :string, default: 'Calendars.Read OnlineMeetings.Read',
                                 desc: 'OAuth2 scopes (space-separated)'
      method_option :no_browser, type: :boolean, default: false, desc: 'Print URL instead of launching browser'
      def microsoft
        say 'Delegating to Teams OAuth2 browser auth...', :blue
        forwarded = ['teams']
        forwarded += ['--tenant_id', options[:tenant_id]] if options[:tenant_id]
        forwarded += ['--client_id', options[:client_id]] if options[:client_id]
        forwarded += ['--scopes', options[:scope]] if options[:scope]
        Legion::CLI::Auth.start(forwarded)
      end

      desc 'github', 'Connect a GitHub account (OAuth2 device flow)'
      method_option :client_id, type: :string, desc: 'GitHub OAuth App client ID'
      def github
        say 'GitHub connection not yet implemented.', :yellow
      end

      desc 'chatgpt', 'Sign in to a native ChatGPT subscription on this host'
      long_desc <<~HELP
        Save a native ChatGPT login for the named instance on this host and OS account.
        Run as the account that runs Legion; this does not authenticate a remote daemon.
        For a headless worker, run this command on that worker with --device.
        OAuth and local credential storage are owned by lex-llm-openai, not the daemon login store.
      HELP
      method_option :instance, type: :string, required: true, desc: 'Exact local instance name'
      method_option :device, type: :boolean, default: false, desc: 'Use device authorization on a headless worker'
      def chatgpt
        instance = chatgpt_instance
        with_chatgpt_auth do |auth|
          say 'Authenticating on this host and OS account; a different daemon account is not authenticated.', :blue
          say 'For a headless worker, run this command on that worker with --device.'
          result = auth.login(instance: instance, device: options[:device]) do |progress|
            chatgpt_progress(progress: progress)
          end
          raise Thor::Error, 'ChatGPT did not confirm a persisted login; inspect local connection status.' unless result.fetch(:status) == 'authenticated'

          say "Saved local ChatGPT login for #{instance.inspect}.", :green
        end
      end

      desc 'status', 'Show legacy provider status, or a named login with --provider chatgpt --instance NAME'
      method_option :provider, type: :string, enum: PROVIDERS + ['chatgpt'],
                               desc: 'Filter by provider; ChatGPT also requires --instance'
      method_option :instance, type: :string, desc: 'Exact native ChatGPT instance name'
      def status
        return chatgpt_status if options[:provider] == 'chatgpt'

        reject_legacy_instance
        require 'legion/auth/token_manager'

        providers = options[:provider] ? [options[:provider]] : PROVIDERS
        providers.each do |provider|
          state = provider_state(provider)
          say "  #{provider}: #{state}", STATE_COLORS.fetch(state, :yellow)
        end
      end

      desc 'disconnect PROVIDER', 'Disconnect a provider account'
      method_option :instance, type: :string, desc: 'Required for a native ChatGPT login on this host/OS account'
      def disconnect(provider)
        return chatgpt_disconnect if provider == 'chatgpt'

        reject_legacy_instance
        unless PROVIDERS.include?(provider)
          say "Unknown provider: #{provider}. Valid: #{(PROVIDERS + ['chatgpt']).join(', ')}", :red
          return
        end

        say "Disconnected #{provider} account.", :green
      end

      no_commands do
        def chatgpt_instance
          instance = options[:instance]
          raise Thor::Error, 'ChatGPT requires --instance NAME; no default account is selected.' if instance.to_s.empty?

          instance
        end

        def reject_legacy_instance
          return unless options[:instance]

          raise Thor::Error, '--instance is only supported for native ChatGPT connections.'
        end

        def with_chatgpt_auth
          require 'legion/extensions'
          require 'legion/extensions/llm/openai'
          raise Thor::Error, CHATGPT_INSTALL unless defined?(Legion::Extensions::Llm::Openai::Chatgpt::Auth)

          yield Legion::Extensions::Llm::Openai::Chatgpt::Auth
        rescue LoadError
          raise Thor::Error, CHATGPT_INSTALL, cause: nil
        rescue Interrupt
          raise Thor::Error, 'ChatGPT operation cancelled; inspect local connection status before retrying.', cause: nil
        rescue StandardError => e
          raise if e.is_a?(Thor::Error)

          message = if defined?(Legion::Extensions::Llm::Openai::Chatgpt::Error) &&
                       e.is_a?(Legion::Extensions::Llm::Openai::Chatgpt::Error)
                      e.message
                    else
                      "ChatGPT operation failed (#{e.class}); check the extension and local credential permissions."
                    end
          raise Thor::Error, message, cause: nil
        end

        def chatgpt_progress(progress:)
          if progress[:authorization_url]
            say 'Open this URL in a browser to approve the local login:'
            say progress.fetch(:authorization_url)
          else
            say "Open #{progress.fetch(:verification_uri)} and enter code #{progress.fetch(:user_code)}."
          end
          $stdout.flush
        end

        def chatgpt_status
          instance = chatgpt_instance
          with_chatgpt_auth do |auth|
            state = auth.status(instance: instance).fetch(:status)
            say "  chatgpt[#{instance.inspect}]: #{state}", CHATGPT_STATES.fetch(state)
            say 'Local credential status only; no login, refresh, or live provider readiness check was performed.'
          end
        end

        def chatgpt_disconnect
          instance = chatgpt_instance
          with_chatgpt_auth do |auth|
            if auth.status(instance: instance).fetch(:status) == 'missing'
              raise Thor::Error, "No local ChatGPT login exists for #{instance.inspect}; nothing was disconnected."
            end

            unless auth.logout(instance: instance).fetch(:status) == 'missing'
              raise Thor::Error, 'ChatGPT did not confirm removal; inspect local connection status.'
            end

            say "Cleared local ChatGPT login for #{instance.inspect}.", :green
            say 'Other ChatGPT, Codex, and OMP sessions are unchanged.'
          end
        end

        # Microsoft delegated login writes tokens via the Entra TokenManager
        # (vault/local/memory), not the legacy Legion::Auth secret store — so
        # status for :microsoft must consult the Entra store to avoid always
        # reporting 'not connected' after a successful Teams/delegated login.
        def provider_state(provider)
          return microsoft_state if provider == 'microsoft'

          manager = Legion::Auth::TokenManager.new(provider: provider.to_sym)
          return 'connected' if manager.token_valid?
          return 'revoked' if manager.revoked?

          'not connected'
        end

        def microsoft_state
          return 'not connected' unless defined?(Legion::Extensions::Identity::Entra::Helpers::TokenManager)

          tm = Legion::Extensions::Identity::Entra::Helpers::TokenManager
          data = tm.token_data(:delegated, refresh: false)
          data && !tm.expired?(data) ? 'connected' : 'not connected'
        rescue StandardError
          'not connected'
        end
      end
    end
  end
end
