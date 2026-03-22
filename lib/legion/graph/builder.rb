# frozen_string_literal: true

module Legion
  module Graph
    module Builder
      class << self
        def build(chain_id: nil, worker_id: nil, limit: 100) # rubocop:disable Lint/UnusedMethodArgument
          Legion::Logging.debug "[Graph::Builder] build chain_id=#{chain_id} limit=#{limit}" if defined?(Legion::Logging)
          return { nodes: {}, edges: [] } unless db_available?

          ds = Legion::Data.connection[:relationships].limit(limit)
          ds = ds.where(chain_id: chain_id) if chain_id

          nodes = {}
          edges = []

          ds.each do |rel|
            trigger = rel[:trigger] || "node_#{rel[:id]}_from"
            action  = rel[:action] || "node_#{rel[:id]}_to"

            nodes[trigger] ||= { label: trigger, type: 'trigger' }
            nodes[action]  ||= { label: action, type: 'action' }
            edges << {
              from:     trigger,
              to:       action,
              label:    rel[:runner_function] || '',
              chain_id: rel[:chain_id]
            }
          end

          Legion::Logging.debug "[Graph::Builder] built nodes=#{nodes.size} edges=#{edges.size}" if defined?(Legion::Logging)
          { nodes: nodes, edges: edges }
        end

        private

        def db_available?
          defined?(Legion::Data) && Legion::Data.connection&.table_exists?(:relationships)
        rescue StandardError => e
          Legion::Logging.debug "Graph::Builder#db_available? check failed: #{e.message}" if defined?(Legion::Logging)
          false
        end
      end
    end
  end
end
