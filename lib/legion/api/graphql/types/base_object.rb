# frozen_string_literal: true

return unless defined?(GraphQL)

module Legion
  class API < Sinatra::Base
    module GraphQL
      module Types
        class BaseObject < ::GraphQL::Schema::Object
        end
      end
    end
  end
end
