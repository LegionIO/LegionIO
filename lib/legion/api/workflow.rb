# frozen_string_literal: true

module Legion
  class API < Sinatra::Base
    module Routes
      module Workflow
        def self.registered(app)
          app.helpers WorkflowHelpers
          app.get '/api/relationships/graph' do
            require_data!
            graph = build_relationship_graph(
              chain_id: params[:chain_id]&.to_i,
              extension: params[:extension]
            )
            json_response(graph)
          end
        end

        module WorkflowHelpers
          def build_relationship_graph(chain_id: nil, extension: nil)
            raw = Legion::Graph::Builder.build(chain_id: chain_id)

            nodes = raw[:nodes].map do |id, meta|
              ext = id.to_s.split('.').first
              { id: id, label: meta[:label], type: meta[:type], extension: ext }
            end

            edges = raw[:edges].map do |edge|
              { source: edge[:from], target: edge[:to], label: edge[:label] }
            end

            if extension
              node_ids = nodes.select { |n| n[:extension] == extension }.map { |n| n[:id] }
              nodes = nodes.select { |n| node_ids.include?(n[:id]) }
              edges = edges.select { |e| node_ids.include?(e[:source]) || node_ids.include?(e[:target]) }
            end

            { nodes: nodes, edges: edges }
          rescue StandardError
            { nodes: [], edges: [] }
          end
        end
      end
    end
  end
end
