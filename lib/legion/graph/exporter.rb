# frozen_string_literal: true

module Legion
  module Graph
    module Exporter
      class << self
        def to_mermaid(graph)
          Legion::Logging.debug "[Graph::Exporter] to_mermaid nodes=#{graph[:nodes].size} edges=#{graph[:edges].size}" if defined?(Legion::Logging)
          lines = ['graph TD']
          node_ids = {}
          counter = 0

          graph[:nodes].each do |key, node|
            counter += 1
            id = "N#{counter}"
            node_ids[key] = id
            lines << "  #{id}[#{node[:label]}]"
          end

          graph[:edges].each do |edge|
            from = node_ids[edge[:from]]
            to   = node_ids[edge[:to]]
            next unless from && to

            lines << if edge[:label] && !edge[:label].empty?
                       "  #{from} -->|#{edge[:label]}| #{to}"
                     else
                       "  #{from} --> #{to}"
                     end
          end

          lines.join("\n")
        end

        def to_dot(graph)
          Legion::Logging.debug "[Graph::Exporter] to_dot nodes=#{graph[:nodes].size} edges=#{graph[:edges].size}" if defined?(Legion::Logging)
          lines = ['digraph legion_tasks {', '  rankdir=LR;']

          graph[:nodes].each do |key, node|
            label = dot_escape(node[:label])
            shape = node[:type] == 'trigger' ? 'box' : 'ellipse'
            lines << "  \"#{key}\" [label=\"#{label}\" shape=#{shape}];"
          end

          graph[:edges].each do |edge|
            escaped = dot_escape(edge[:label])
            label = escaped && !escaped.empty? ? " [label=\"#{escaped}\"]" : ''
            lines << "  \"#{edge[:from]}\" -> \"#{edge[:to]}\"#{label};"
          end

          lines << '}'
          lines.join("\n")
        end

        private

        def dot_escape(str)
          return str unless str.is_a?(String)

          result = String.new(capacity: str.length)
          str.each_char do |ch|
            escaped = case ch
                      when '\\' then '\\\\'
                      when '"'  then '\\"'
                      else ch
                      end
            result << escaped
          end
          result
        end
      end
    end
  end
end
