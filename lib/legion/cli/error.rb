# frozen_string_literal: true

module Legion
  module CLI
    class Error < StandardError
      attr_reader :suggestions, :code

      def self.actionable(code:, message:, suggestions: [])
        err = new(message)
        err.instance_variable_set(:@code, code)
        err.instance_variable_set(:@suggestions, suggestions)
        err
      end

      def actionable?
        !suggestions.nil? && !suggestions.empty?
      end
    end
  end
end
