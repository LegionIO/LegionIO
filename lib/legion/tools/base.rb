# frozen_string_literal: true

module Legion
  module Tools
    class Base
      class << self
        # Lazy delegation instead of include Helper — Base loads at require time
        # before Settings is initialized; Helper#log builds TaggedLogger which
        # calls derive_log_segments -> Settings -> possible recursion.
        # Subclass static tools (Do, Status, Config) CAN include Helper safely.
        def log
          Legion::Logging.respond_to?(:logger) ? Legion::Logging.logger : nil
        end

        def handle_exception(err, **opts)
          log&.warn("[Legion::Tools] #{opts[:operation] || 'unknown'}: #{err.message}")
        end

        def tool_name(name = nil)
          name ? @tool_name = name : @tool_name
        end

        def description(desc = nil)
          desc ? @description = desc : (@description || '')
        end

        def input_schema(schema = nil)
          schema ? @input_schema = schema : @input_schema
        end

        def deferred(val = nil)
          return @deferred || false if val.nil?

          @deferred = val
        end

        def deferred?
          deferred
        end

        # Metadata that replaces Capability - Tools::Registry IS the catalog
        def extension(val = nil)
          return @extension if val.nil?

          @extension = val
        end

        def runner(val = nil)
          return @runner if val.nil?

          @runner = val
        end

        def tags(val = nil)
          return @tags || [] if val.nil?

          @tags = val
        end

        def mcp_category(val = nil)
          return @mcp_category if val.nil?

          @mcp_category = val
        end

        def mcp_tier(val = nil)
          return @mcp_tier if val.nil?

          @mcp_tier = val
        end

        def trigger_words(val = nil)
          return @trigger_words || [] if val.nil?

          @trigger_words = val
        end

        def call(**_args)
          raise NotImplementedError, "#{name} must implement .call"
        end

        def text_response(data)
          text = data.is_a?(String) ? data : Legion::JSON.dump(data)
          { content: [{ type: 'text', text: text }] }
        end

        def error_response(msg)
          { content: [{ type: 'text', text: Legion::JSON.dump({ error: msg }) }], error: true }
        end
      end
    end
  end
end
