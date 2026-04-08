# frozen_string_literal: true

require 'securerandom'
require 'legion/cli/chat_command'

begin
  require 'legion/llm/daemon_client'
rescue LoadError
  # legion-llm not yet loaded; DaemonClient must be defined before DaemonChat#ask is called.
end

module Legion
  module CLI
    class Chat
      # Daemon-backed chat adapter. Matches the interface that Session expects
      # from a chat object (ask, with_tools, with_instructions, on_tool_call,
      # on_tool_result, model, add_message, reset_messages!, with_model).
      #
      # All LLM inference is routed through the running daemon via
      # POST /api/llm/inference. Tool execution runs locally on the client
      # machine — the daemon returns tool_call requests and the client
      # executes them and loops.
      class DaemonChat
        # Minimal response-like object returned from ask.
        # Responds to the same interface Session#send_message reads.
        Response = Struct.new(:content, :input_tokens, :output_tokens, :model)

        # Minimal model object responding to .id (used by Session#model_id).
        ModelInfo = Struct.new(:id) do
          def to_s
            id.to_s
          end
        end

        # Single shared struct class for tool result objects; avoids allocating
        # an anonymous Struct class on every build_tool_result_object call.
        ToolResult = Struct.new(:content, :tool_call_id, :id)

        attr_reader :model, :conversation_id, :caller_context

        def initialize(model: nil, provider: nil)
          @model    = ModelInfo.new(id: model)
          @provider = provider
          @messages = []
          @tools    = []
          @instructions = nil
          @on_tool_call   = nil
          @on_tool_result = nil
          @conversation_id = SecureRandom.uuid
          @caller_context  = build_caller
        end

        # Sets the system prompt. Returns self for chaining.
        def with_instructions(prompt)
          @instructions = prompt
          self
        end

        # Registers tool classes for local execution and schema forwarding.
        # Returns self for chaining.
        def with_tools(*tools)
          @tools = tools.flatten
          self
        end

        # Switches the active model. Returns self for chaining.
        def with_model(model_id)
          @model = ModelInfo.new(id: model_id)
          self
        end

        # Stores a tool_call callback invoked before each local tool execution.
        def on_tool_call(&block)
          @on_tool_call = block
        end

        # Stores a tool_result callback invoked after each local tool execution.
        def on_tool_result(&block)
          @on_tool_result = block
        end

        # Appends a message to the conversation history directly (used by
        # slash commands /fetch, /search, /agent, etc. that inject context).
        def add_message(role:, content:)
          @messages << { role: role.to_s, content: content }
        end

        # Clears all conversation history (used by /clear slash command).
        def reset_messages!
          @messages = []
        end

        # Sends a message through the daemon inference loop.
        # Executes any tool_calls locally and loops until the LLM stops.
        # Yields response-like chunks for streaming display (Phase 1: single chunk).
        # Returns a Response object compatible with Session#send_message.
        def ask(message, &on_chunk)
          @messages << { role: 'user', content: message }

          loop do
            result = call_daemon_inference

            raise CLI::Error, "Daemon inference error: #{result[:error]}" if result[:status] == :error
            raise CLI::Error, 'Daemon is unavailable' if result[:status] == :unavailable

            data = extract_data(result)

            if data[:tool_calls]&.any?
              execute_tool_calls(data[:tool_calls], data[:content])
            else
              on_chunk&.call(Response.new(content: data[:content]))
              @messages << { role: 'assistant', content: data[:content] }
              return build_response(data)
            end
          end
        end

        private

        def call_daemon_inference
          Legion::LLM::DaemonClient.inference(
            messages:        build_messages,
            tools:           build_tool_schemas,
            model:           @model.id,
            provider:        @provider,
            caller:          @caller_context,
            conversation_id: @conversation_id
          )
        end

        def extract_data(result)
          # DaemonClient.inference returns { status:, data: { content:, tool_calls:, ... } }
          data = result[:data] || result[:body] || {}
          data.is_a?(Hash) ? data : {}
        end

        def build_messages
          msgs = []
          msgs << { role: 'system', content: @instructions } if @instructions
          msgs + @messages
        end

        def build_tool_schemas
          @tools.map do |tool|
            {
              name:        tool_name(tool),
              description: tool_description(tool),
              parameters:  tool_parameters(tool)
            }
          end
        end

        def tool_name(tool)
          if tool.respond_to?(:tool_name)
            tool.tool_name
          else
            tool.name.to_s.split('::').last.gsub(/([A-Z])/) do
              "_#{::Regexp.last_match(1).downcase}"
            end.delete_prefix('_')
          end
        end

        def tool_description(tool)
          tool.respond_to?(:description) ? tool.description : ''
        end

        def tool_parameters(tool)
          tool.respond_to?(:parameters) ? tool.parameters : {}
        end

        def execute_tool_calls(tool_calls, assistant_content)
          # Record the assistant turn with tool_calls before appending results.
          @messages << { role: 'assistant', content: assistant_content, tool_calls: tool_calls }

          # Normalize all tool calls upfront so threads don't mutate shared state
          normalized = tool_calls.map do |tc|
            tc.respond_to?(:transform_keys) ? tc.transform_keys(&:to_sym) : tc
          end

          # Fire on_tool_call callbacks immediately (serial — fast, just event emission)
          normalized.each do |tc|
            @on_tool_call&.call(build_tool_call_object(tc))
          end

          # Execute all tools in parallel, preserving original order for message replay
          results = normalized.map do |tc|
            Thread.new { [tc, run_tool(tc)] }
          end.map(&:value)

          # Collect results serially: fire callbacks and append messages in order
          results.each do |tc, result_text|
            result_obj = build_tool_result_object(result_text, tc[:id] || tc[:tool_call_id])
            @on_tool_result&.call(result_obj)

            @messages << {
              role:         'tool',
              tool_call_id: tc[:id] || tc[:tool_call_id],
              content:      result_text.to_s
            }
          end
        end

        def build_tool_call_object(tool_call)
          Struct.new(:name, :arguments, :id).new(
            name:      tool_call[:name].to_s,
            arguments: (tool_call[:arguments] || tool_call[:input] || {}).transform_keys(&:to_sym),
            id:        tool_call[:id] || tool_call[:tool_call_id]
          )
        end

        # Carries both the result content AND the originating tool_call_id so the
        # daemon-bridge-script serializer can include it in the tool-result event,
        # allowing the Interlink frontend to match results back to the correct
        # tool call by ID (rather than falling back to name-based matching which
        # breaks when multiple tools of the same type run in parallel).
        def build_tool_result_object(text, tool_call_id = nil)
          ToolResult.new(text.to_s, tool_call_id, tool_call_id)
        end

        def run_tool(tool_call)
          name      = tool_call[:name].to_s
          arguments = (tool_call[:arguments] || tool_call[:input] || {}).transform_keys(&:to_sym)

          tool_class = @tools.find { |t| tool_name(t) == name }
          return "Unknown tool: #{name}" unless tool_class

          tool_class.call(**arguments)
        rescue StandardError => e
          "Tool error (#{name}): #{e.message}"
        end

        def build_caller
          identity = resolve_identity
          { requested_by: { identity: identity, type: :human, credential: :local } }
        end

        def resolve_identity
          if defined?(Legion::Crypt) && Legion::Crypt.respond_to?(:kerberos_principal)
            principal = Legion::Crypt.kerberos_principal
            return principal if principal
          end

          require 'etc'
          Etc.getlogin || ENV.fetch('USER', 'unknown')
        rescue StandardError
          ENV.fetch('USER', 'unknown')
        end

        def build_response(data)
          Response.new(
            content:       data[:content],
            input_tokens:  data[:input_tokens],
            output_tokens: data[:output_tokens],
            model:         ModelInfo.new(id: data[:model] || @model.id)
          )
        end
      end
    end
  end
end
