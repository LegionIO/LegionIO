# frozen_string_literal: true

return unless defined?(GraphQL)

require_relative 'types/base_object'
require_relative 'types/node_type'
require_relative 'types/worker_type'
require_relative 'types/extension_type'
require_relative 'types/task_type'
require_relative 'resolvers/node'
require_relative 'resolvers/workers'
require_relative 'resolvers/extensions'
require_relative 'resolvers/tasks'
require_relative 'types/query_type'

module Legion
  class API < Sinatra::Base
    module GraphQL
      class Schema < ::GraphQL::Schema
        query Types::QueryType

        max_depth      10
        max_complexity 200
      end
    end
  end
end
