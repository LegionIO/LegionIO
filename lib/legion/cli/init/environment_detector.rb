# frozen_string_literal: true

require 'socket'

module Legion
  module CLI
    module InitHelpers
      module EnvironmentDetector
        class << self
          def detect
            {
              rabbitmq:        check_rabbitmq,
              database:        check_database,
              vault:           check_vault,
              redis:           check_redis,
              git:             check_git,
              existing_config: check_config
            }
          end

          private

          def check_rabbitmq
            return { available: true, source: 'env' } if ENV['AMQP_URL'] || ENV['RABBITMQ_URL']

            Socket.tcp('localhost', 5672, connect_timeout: 2) { true }
            { available: true, source: 'localhost' }
          rescue StandardError => e
            Legion::Logging.debug("EnvironmentDetector#check_rabbitmq not reachable: #{e.message}") if defined?(Legion::Logging)
            { available: false }
          end

          def check_database
            return { available: true, adapter: 'postgresql', source: 'env' } if ENV['DATABASE_URL']

            { available: true, adapter: 'sqlite', source: 'fallback' }
          end

          def check_vault
            return { available: true, source: 'env' } if ENV['VAULT_ADDR']

            { available: false }
          end

          def check_redis
            return { available: true, source: 'env' } if ENV['REDIS_URL']

            Socket.tcp('localhost', 6379, connect_timeout: 2) { true }
            { available: true, source: 'localhost' }
          rescue StandardError => e
            Legion::Logging.debug("EnvironmentDetector#check_redis not reachable: #{e.message}") if defined?(Legion::Logging)
            { available: false }
          end

          def check_git
            { available: Dir.exist?('.git') }
          end

          def check_config
            dir = File.expand_path('~/.legionio/settings')
            { available: Dir.exist?(dir), path: dir }
          end
        end
      end
    end
  end
end
