# frozen_string_literal: true

module Legion
  module Extensions
    Capability = ::Data.define(
      :name, :extension, :runner, :function,
      :description, :parameters, :tags, :loaded_at
    ) do
      def self.from_runner(extension:, runner:, function:, description: nil, parameters: nil, tags: nil)
        canonical = "#{extension}:#{runner.to_s.gsub(/([A-Z])/, '_\1').sub(/^_/, '').downcase}:#{function}"
        new(
          name: canonical,
          extension: extension,
          runner: runner.to_s,
          function: function.to_s,
          description: description,
          parameters: parameters || {},
          tags: Array(tags),
          loaded_at: Time.now
        )
      end

      def matches_intent?(text)
        words = text.downcase.split(/\s+/)
        searchable = [description, *tags, extension, runner, function]
                     .compact.join(' ').downcase

        matching = words.count { |w| searchable.include?(w) }
        matching.to_f / [words.length, 1].max >= 0.4
      end

      def to_mcp_tool
        snake_runner = runner.gsub(/([A-Z])/, '_\1').sub(/^_/, '').downcase
        tool_name = "legion.#{extension.delete_prefix('lex-').tr('-', '_')}.#{snake_runner}.#{function}"
        properties = (parameters || {}).transform_values do |v|
          v.is_a?(Hash) ? v : { type: v.to_s }
        end

        {
          name: tool_name,
          description: description || "#{extension} #{runner}##{function}",
          input_schema: {
            type: 'object',
            properties: properties,
            required: parameters&.select { |_, v| v.is_a?(Hash) && v[:required] }&.keys&.map(&:to_s) || []
          }
        }
      end
    end
  end
end
