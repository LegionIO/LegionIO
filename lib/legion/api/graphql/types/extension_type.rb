# frozen_string_literal: true

return unless defined?(GraphQL)

module Legion
  class API < Sinatra::Base
    module GraphQL
      module Types
        class ExtensionType < BaseObject
          graphql_name 'Extension'
          description 'A LegionIO extension (LEX)'

          field :name,        String,         null: true, description: 'Extension gem name'
          field :version,     String,         null: true, description: 'Extension version'
          field :status,      String,         null: true, description: 'Extension status'
          field :description, String,         null: true, description: 'Extension description'
          field :risk_tier,   String,         null: true, description: 'Risk classification tier'
          field :runners,     [String],       null: true, description: 'Runner class names'
        end
      end
    end
  end
end
