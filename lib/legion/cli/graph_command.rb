# frozen_string_literal: true

require 'thor'

module Legion
  module CLI
    class GraphCommand < Thor
      namespace 'graph'

      desc 'show', 'Display task relationship graph'
      option :chain, type: :string, desc: 'Filter by chain ID'
      option :worker, type: :string, desc: 'Filter by worker ID'
      option :format, type: :string, default: 'mermaid', enum: %w[mermaid dot]
      option :output, type: :string, desc: 'Write to file'
      option :limit, type: :numeric, default: 100
      def show
        require 'legion/graph/builder'
        require 'legion/graph/exporter'

        graph = Legion::Graph::Builder.build(
          chain_id:  options[:chain],
          worker_id: options[:worker],
          limit:     options[:limit]
        )

        rendered = case options[:format]
                   when 'dot' then Legion::Graph::Exporter.to_dot(graph)
                   else Legion::Graph::Exporter.to_mermaid(graph)
                   end

        if options[:output]
          File.write(options[:output], rendered)
          say "Written to #{options[:output]}", :green
        else
          say rendered
        end
      end

      default_task :show
    end
  end
end
