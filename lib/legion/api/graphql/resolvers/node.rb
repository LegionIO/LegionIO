# frozen_string_literal: true

module Legion
  class API < Sinatra::Base
    module GraphQL
      module Resolvers
        module Node
          def self.resolve
            name    = defined?(Legion::Settings) ? Legion::Settings[:client][:name] : 'legion'
            version = defined?(Legion::VERSION) ? Legion::VERSION : nil
            ready   = defined?(Legion::Readiness) ? Legion::Readiness.ready? : true
            uptime  = defined?(Legion::Process) ? calculate_uptime : nil

            {
              name:    name,
              version: version,
              uptime:  uptime,
              ready:   ready
            }
          rescue StandardError
            { name: nil, version: nil, uptime: nil, ready: false }
          end

          def self.calculate_uptime
            return nil unless defined?(Legion::Process) &&
                              Legion::Process.respond_to?(:started_at) &&
                              Legion::Process.started_at

            (Time.now.utc - Legion::Process.started_at).to_i
          rescue StandardError
            nil
          end

          private_class_method :calculate_uptime
        end
      end
    end
  end
end
