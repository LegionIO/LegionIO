# frozen_string_literal: true

module Legion
  module Extensions
    module Catalog
      module Registry
        @capabilities = []
        @by_name = {}
        @mutex = Mutex.new
        @on_change_callbacks = []

        module_function

        def register(capability)
          @mutex.synchronize do
            return if @by_name.key?(capability.name)

            @capabilities << capability
            @by_name[capability.name] = capability
          end
          notify_change
        end

        def unregister(name)
          @mutex.synchronize do
            cap = @by_name.delete(name)
            @capabilities.delete(cap) if cap
            return unless cap
          end
          notify_change
        end

        def unregister_extension(extension_name)
          @mutex.synchronize do
            removed = @capabilities.select { |c| c.extension == extension_name }
            removed.each do |cap|
              @by_name.delete(cap.name)
              @capabilities.delete(cap)
            end
            return if removed.empty?
          end
          notify_change
        end

        def capabilities
          @mutex.synchronize { @capabilities.dup.freeze }
        end

        def find(name:)
          @mutex.synchronize { @by_name[name] }
        end

        def find_by_intent(text)
          @mutex.synchronize do
            @capabilities.select { |c| c.matches_intent?(text) }
          end
        end

        def for_mcp
          @mutex.synchronize { @capabilities.dup }
        end

        def find_by_mcp_name(mcp_name)
          @mutex.synchronize do
            @capabilities.find { |cap| cap.to_mcp_tool[:name] == mcp_name }
          end
        end

        def for_override(tool_name)
          @mutex.synchronize do
            normalized = tool_name.downcase.tr('-', '_')
            @capabilities.find do |cap|
              cap.function.downcase == normalized ||
                cap.name.downcase.end_with?(normalized) ||
                cap.tags.any? { |t| t.downcase == normalized }
            end
          end
        end

        def count
          @mutex.synchronize { @capabilities.length }
        end

        def on_change(&block)
          @mutex.synchronize { @on_change_callbacks << block }
        end

        def reset!
          @mutex.synchronize do
            @capabilities.clear
            @by_name.clear
            @on_change_callbacks.clear
          end
        end

        def notify_change
          callbacks = @mutex.synchronize { @on_change_callbacks.dup }
          callbacks.each do |cb|
            cb.call
          rescue StandardError => e
            Legion::Logging.warn("Catalog::Registry on_change error: #{e.message}") if defined?(Legion::Logging)
          end
        end

        private_class_method :notify_change
      end
    end
  end
end
