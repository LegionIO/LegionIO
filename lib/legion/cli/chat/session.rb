# frozen_string_literal: true

require 'legion/cli/chat_command'

module Legion
  module CLI
    class Chat
      class Session
        class BudgetExceeded < StandardError; end

        # Conservative per-token rates (USD) — roughly Sonnet-class pricing.
        # Used as a safety cap, not a billing system.
        INPUT_RATE  = 0.003 / 1000.0  # $3 per million input tokens
        OUTPUT_RATE = 0.015 / 1000.0  # $15 per million output tokens

        attr_reader :chat, :stats, :cache_hits_tokens
        attr_accessor :budget_usd

        def initialize(chat:, system_prompt: nil, budget_usd: nil)
          @chat = chat
          @chat.with_instructions(system_prompt) if system_prompt
          @budget_usd = budget_usd
          @stats = {
            messages_sent:     0,
            messages_received: 0,
            started_at:        Time.now
          }
          @model_usage = Hash.new { |h, k| h[k] = { input_tokens: 0, output_tokens: 0, requests: 0 } }
          @cache_hits_tokens = 0
          @callbacks = Hash.new { |h, k| h[k] = [] }
          @turn = 0
        end

        def on(event, &block)
          @callbacks[event] << block
        end

        def emit(event, payload = {})
          @callbacks[event].each { |cb| cb.call(payload) }
        end

        def send_message(message, on_tool_call: nil, on_tool_result: nil, &block)
          check_budget!
          check_for_absorbable_urls(message)

          @stats[:messages_sent] += 1
          @turn += 1
          current_turn = @turn

          @chat.on_tool_call { |tc| on_tool_call&.call(tc) }
          @chat.on_tool_result { |tr| on_tool_result&.call(tr) }

          emit(:llm_start, { turn: current_turn })

          first_token_emitted = false
          wrapped_block = if block
                            proc do |chunk|
                              unless first_token_emitted
                                first_token_emitted = true
                                emit(:llm_first_token, { turn: current_turn })
                              end
                              block.call(chunk)
                            end
                          end

          response = @chat.ask(message, &wrapped_block)
          @stats[:messages_received] += 1

          if response.respond_to?(:input_tokens)
            in_tok  = response.input_tokens || 0
            out_tok = response.output_tokens || 0
            @stats[:input_tokens]  = (@stats[:input_tokens] || 0) + in_tok
            @stats[:output_tokens] = (@stats[:output_tokens] || 0) + out_tok

            resp_model = response.respond_to?(:model_id) ? response.model_id : model_id
            entry = @model_usage[resp_model.to_s]
            entry[:input_tokens]  += in_tok
            entry[:output_tokens] += out_tok
            entry[:requests]      += 1

            @cache_hits_tokens += response.cache_read_input_tokens.to_i if response.respond_to?(:cache_read_input_tokens) && response.cache_read_input_tokens
          end

          emit(:llm_complete, { turn: current_turn, user_message: message })

          response
        end

        def estimated_cost
          if cost_estimator_available? && @model_usage.any?
            @model_usage.sum do |model, usage|
              Legion::LLM::CostEstimator.estimate(
                model_id: model, input_tokens: usage[:input_tokens], output_tokens: usage[:output_tokens]
              )
            end
          else
            input  = (@stats[:input_tokens] || 0) * INPUT_RATE
            output = (@stats[:output_tokens] || 0) * OUTPUT_RATE
            input + output
          end
        end

        def model_usage
          @model_usage.transform_values(&:dup)
        end

        def cost_breakdown
          @model_usage.map do |model, usage|
            cost = if cost_estimator_available?
                     Legion::LLM::CostEstimator.estimate(
                       model_id: model, input_tokens: usage[:input_tokens], output_tokens: usage[:output_tokens]
                     )
                   else
                     (usage[:input_tokens] * INPUT_RATE) + (usage[:output_tokens] * OUTPUT_RATE)
                   end
            { model: model, input_tokens: usage[:input_tokens], output_tokens: usage[:output_tokens],
              requests: usage[:requests], cost: cost }
          end
        end

        def model_id
          @chat.model&.id
        rescue StandardError => e
          Legion::Logging.debug("Session#model_id failed: #{e.message}") if defined?(Legion::Logging)
          'unknown'
        end

        def elapsed
          Time.now - @stats[:started_at]
        end

        private

        def cost_estimator_available?
          defined?(Legion::LLM::CostEstimator)
        end

        def check_budget!
          return unless @budget_usd

          cost = estimated_cost
          return unless cost >= @budget_usd

          raise BudgetExceeded,
                format('Budget exceeded: $%<cost>.4f spent of $%<limit>.2f limit',
                       cost: cost, limit: @budget_usd)
        end

        def check_for_absorbable_urls(text)
          return unless defined?(Legion::Extensions::Absorbers::Dispatch)
          return unless defined?(Legion::Extensions::Absorbers::PatternMatcher)

          urls = Legion::Extensions::Absorbers::Dispatch.extract_urls(text.to_s)
          return if urls.empty?

          urls.each do |url|
            absorber = Legion::Extensions::Absorbers::PatternMatcher.resolve(url)
            next unless absorber

            Legion::Extensions::Absorbers::Dispatch.dispatch(url, context: { conversation_id: object_id.to_s })
          end
        end
      end
    end
  end
end
