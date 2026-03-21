# frozen_string_literal: true

require 'json'

module Legion
  module Notebook
    module Parser
      def self.parse(path)
        data = ::JSON.parse(File.read(path))
        {
          metadata: data['metadata'],
          kernel:   data.dig('metadata', 'kernelspec', 'display_name'),
          language: data.dig('metadata', 'kernelspec', 'language') || 'python',
          cells:    Array(data['cells']).map { |c| parse_cell(c) }
        }
      end

      def self.parse_cell(cell)
        {
          type:    cell['cell_type'],
          source:  Array(cell['source']).join,
          outputs: Array(cell.fetch('outputs', [])).map { |o| parse_output(o) }
        }
      end

      def self.parse_output(output)
        text = case output['output_type']
               when 'execute_result', 'display_data'
                 data = output.fetch('data', {})
                 Array(data.fetch('text/plain', [])).join
               when 'error'
                 "#{output['ename']}: #{output['evalue']}"
               else
                 Array(output.fetch('text', [])).join
               end

        {
          output_type: output['output_type'],
          text:        text
        }
      end
    end
  end
end
