# frozen_string_literal: true

module Legion
  module Tools
    # Static tool classes accumulate here at require time for reload safety
    @tool_classes = []
    @mutex = Mutex.new

    class << self
      def tool_classes
        @mutex.synchronize { @tool_classes.dup }
      end

      def register_class(klass)
        @mutex.synchronize do
          @tool_classes << klass unless @tool_classes.include?(klass)
        end
      end

      # Called by Service#register_core_tools on boot AND reload
      def register_all
        @mutex.synchronize { @tool_classes.dup }.each do |klass|
          Legion::Tools::Registry.register(klass)
        end
      end
    end
  end
end

require_relative 'tools/registry'
require_relative 'tools/base'
require_relative 'tools/discovery'
