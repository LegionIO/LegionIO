# frozen_string_literal: true

module Legion
  module Extensions
    module Helpers
      class SecretAccessor
        def initialize(lex_name:)
          @lex_name = lex_name
          @warned = false
        end

        def [](name, shared: false, user: nil)
          return nil unless crypt_available?

          Legion::Crypt.get(resolve_path(name, shared: shared, user: user))
        rescue StandardError => e
          log_warn("secret read failed for #{name}: #{e.message}")
          nil
        end

        def []=(name, value)
          return unless crypt_available?

          Legion::Crypt.write(resolve_path(name, shared: false, user: nil), **value)
        rescue StandardError => e
          log_warn("secret write failed for #{name}: #{e.message}")
        end

        def write(name, shared: false, user: nil, **data)
          return false unless crypt_available?

          Legion::Crypt.write(resolve_path(name, shared: shared, user: user), **data)
          true
        rescue StandardError => e
          log_warn("secret write failed for #{name}: #{e.message}")
          false
        end

        def exist?(name, shared: false, user: nil)
          return false unless crypt_available?

          Legion::Crypt.exist?(resolve_path(name, shared: shared, user: user))
        rescue StandardError
          false
        end

        def delete(name, shared: false, user: nil)
          return false unless crypt_available?

          Legion::Crypt.delete(resolve_path(name, shared: shared, user: user))
          true
        rescue StandardError => e
          log_warn("secret delete failed for #{name}: #{e.message}")
          false
        end

        private

        def resolve_path(name, shared:, user:)
          prefix = shared ? 'shared' : "users/#{resolve_user(user)}"
          "#{prefix}/#{@lex_name}/#{name}"
        end

        def resolve_user(explicit_user)
          return explicit_user if explicit_user

          Secret.resolved_identity || ENV.fetch('USER', 'default')
        end

        def crypt_available?
          return false unless defined?(Legion::Crypt)

          unless @warned || vault_connected?
            log_warn('Vault not connected — secret operations may fail')
            @warned = true
          end
          true
        end

        def vault_connected?
          defined?(Legion::Settings) &&
            Legion::Settings[:crypt]&.dig(:vault, :connected) == true
        rescue StandardError
          false
        end

        def log_warn(msg)
          Legion::Logging.warn("[Secret] #{msg}") if defined?(Legion::Logging)
        end
      end

      module Secret
        @resolved_identity = nil
        @identity_source = nil

        class << self
          attr_reader :resolved_identity, :identity_source

          def resolve_identity!
            @resolved_identity = nil
            @identity_source = nil

            if defined?(Legion::Crypt) && Legion::Crypt.respond_to?(:kerberos_principal) &&
               Legion::Crypt.kerberos_principal
              @resolved_identity = Legion::Crypt.kerberos_principal
              @identity_source = :kerberos
            elsif entra_principal
              @resolved_identity = entra_principal
              @identity_source = :entra
            end

            @resolved_identity
          end

          def reset_identity!
            @resolved_identity = nil
            @identity_source = nil
          end

          private

          def entra_principal
            return nil unless defined?(Legion::Extensions::MicrosoftTeams::Helpers::TokenCache)

            cache = Legion::Extensions::MicrosoftTeams::Helpers::TokenCache
            return nil unless cache.respond_to?(:instance)

            instance = cache.instance
            return nil unless instance.respond_to?(:user_principal)

            principal = instance.user_principal
            principal unless principal.nil? || principal.empty?
          rescue StandardError
            nil
          end
        end

        def secret
          @secret ||= SecretAccessor.new(lex_name: lex_name)
        end
      end
    end
  end
end
