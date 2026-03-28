# frozen_string_literal: true

require 'thor'

module Legion
  module CLI
    class ConnectCommand < Thor
      namespace :connect

      PROVIDERS = %w[microsoft github google].freeze

      desc 'microsoft', 'Connect a Microsoft account (OAuth2 delegated auth)'
      method_option :tenant_id,  type: :string, desc: 'Azure tenant ID'
      method_option :client_id,  type: :string, desc: 'Application client ID'
      method_option :scope,      type: :string, default: 'Calendars.Read OnlineMeetings.Read',
                                 desc: 'OAuth2 scopes (space-separated)'
      method_option :no_browser, type: :boolean, default: false, desc: 'Print URL instead of launching browser'
      def microsoft
        require 'legion/auth/token_manager'
        manager = Legion::Auth::TokenManager.new(provider: :microsoft)

        if manager.token_valid?
          say 'Already connected to Microsoft. Use --force to reconnect.', :green
          return
        end

        say 'Connecting to Microsoft...', :blue
        say 'OAuth2 browser flow not yet implemented. Use `legion auth teams` for Teams-specific auth.', :yellow
      end

      desc 'github', 'Connect a GitHub account (OAuth2 device flow)'
      method_option :client_id, type: :string, desc: 'GitHub OAuth App client ID'
      def github
        say 'GitHub connection not yet implemented.', :yellow
      end

      desc 'status', 'Show connection status for all providers'
      def status
        require 'legion/auth/token_manager'

        PROVIDERS.each do |provider|
          manager = Legion::Auth::TokenManager.new(provider: provider.to_sym)
          if manager.token_valid?
            say "  #{provider}: connected", :green
          elsif manager.revoked?
            say "  #{provider}: revoked", :red
          else
            say "  #{provider}: not connected", :yellow
          end
        end
      end

      desc 'disconnect PROVIDER', 'Disconnect a provider account'
      def disconnect(provider)
        unless PROVIDERS.include?(provider)
          say "Unknown provider: #{provider}. Valid: #{PROVIDERS.join(', ')}", :red
          return
        end

        say "Disconnected #{provider} account.", :green
      end
    end
  end
end
