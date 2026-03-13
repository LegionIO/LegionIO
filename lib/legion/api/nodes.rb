# frozen_string_literal: true

module Legion
  class API < Sinatra::Base
    module Routes
      module Nodes
        def self.registered(app)
          app.get '/api/nodes' do
            require_data!
            dataset = Legion::Data::Model::Node.order(:id)
            dataset = dataset.where(active: true) if params[:active] == 'true'
            dataset = dataset.where(status: params[:status]) if params[:status]
            json_collection(dataset)
          end

          app.get '/api/nodes/:id' do
            require_data!
            node = find_or_halt(Legion::Data::Model::Node, params[:id])
            json_response(node.values)
          end
        end
      end
    end
  end
end
