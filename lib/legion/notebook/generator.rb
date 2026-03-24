# frozen_string_literal: true

require 'json'

module Legion
  module Notebook
    module Generator
      NOTEBOOK_TEMPLATE = {
        'nbformat'       => 4,
        'nbformat_minor' => 5,
        'metadata'       => {
          'kernelspec'    => {
            'display_name' => 'Python 3',
            'language'     => 'python',
            'name'         => 'python3'
          },
          'language_info' => {
            'name' => 'python'
          }
        },
        'cells'          => []
      }.freeze

      def self.generate(description:, kernel: 'python3', model: nil, provider: nil)
        raise ArgumentError, 'legion-llm is required for notebook generation' unless defined?(Legion::LLM)

        prompt = build_prompt(description, kernel)
        response = call_llm(prompt, model: model, provider: provider)
        parse_notebook_response(response)
      end

      def self.write(path, notebook_data)
        File.write(path, ::JSON.pretty_generate(notebook_data))
      end

      def self.build_prompt(description, kernel)
        <<~PROMPT
          Generate a Jupyter notebook as valid JSON (.ipynb format) for the following task:

          #{description}

          Requirements:
          - Use kernel: #{kernel}
          - Include a markdown cell with a title and description at the top
          - Include well-commented code cells
          - Include markdown explanation cells between code sections
          - Return ONLY the raw JSON, no markdown fences, no explanation

          The JSON must follow the .ipynb format with these top-level keys:
          nbformat, nbformat_minor, metadata, cells

          Each cell must have: cell_type, metadata, source (array of strings), outputs (array), execution_count
        PROMPT
      end

      def self.call_llm(prompt, model: nil, provider: nil)
        kwargs = { messages: [{ role: 'user', content: prompt }] }
        kwargs[:model]    = model           if model
        kwargs[:provider] = provider.to_sym if provider
        Legion::LLM.chat(**kwargs, caller: { source: 'cli', command: 'notebook' })
      end

      def self.parse_notebook_response(response)
        content = response[:content].to_s.strip
        # Strip markdown fences if the LLM wrapped the JSON
        content = content.gsub(/\A```(?:json)?\n?/, '').gsub(/\n?```\z/, '').strip
        data = ::JSON.parse(content)
        validate_notebook!(data)
        data
      rescue ::JSON::ParserError => e
        raise ArgumentError, "LLM returned invalid JSON: #{e.message}"
      end

      def self.validate_notebook!(data)
        raise ArgumentError, 'Missing nbformat key'  unless data.key?('nbformat')
        raise ArgumentError, 'Missing cells key'     unless data.key?('cells')
        raise ArgumentError, 'cells must be an array' unless data['cells'].is_a?(Array)
      end
    end
  end
end
