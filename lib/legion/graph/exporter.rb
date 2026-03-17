# frozen_string_literal: true

module Legion
  module Graph
    module Exporter
      class << self
        def to_mermaid(graph)
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
          lines = ['digraph legion_tasks {', '  rankdir=LR;']

          graph[:nodes].each do |key, node|
            label = node[:label].gsub('"', '\\"')
            shape = node[:type] == 'trigger' ? 'box' : 'ellipse'
            lines << "  \"#{key}\" [label=\"#{label}\" shape=#{shape}];"
          end

          graph[:edges].each do |edge|
            label = edge[:label] && !edge[:label].empty? ? " [label=\"#{edge[:label]}\"]" : ''
            lines << "  \"#{edge[:from]}\" -> \"#{edge[:to]}\"#{label};"
          end

          lines << '}'
          lines.join("\n")
        end
      end
    end
  end
end
