# frozen_string_literal: true

require 'securerandom'

begin
  require 'legion/cli/chat/tools/search_traces'
  if defined?(Legion::LLM::ToolRegistry) && defined?(Legion::CLI::Chat::Tools::SearchTraces)
    Legion::LLM::ToolRegistry.register(Legion::CLI::Chat::Tools::SearchTraces)
  end
rescue LoadError => e
  Legion::Logging.debug("SearchTraces not available for API: #{e.message}") if defined?(Legion::Logging)
end

module Legion
  class API < Sinatra::Base
    module Routes
      module Llm
        def self.registered(app)
          app.helpers do
            define_method(:require_llm!) do
              return if defined?(Legion::LLM) &&
                        Legion::LLM.respond_to?(:started?) &&
                        Legion::LLM.started?

              halt 503, { 'Content-Type' => 'application/json' },
                   Legion::JSON.dump({ error: { code:    'llm_unavailable',
                                                message: 'LLM subsystem is not available' } })
            end

            define_method(:cache_available?) do
              defined?(Legion::Cache) &&
                Legion::Cache.respond_to?(:connected?) &&
                Legion::Cache.connected?
            end

            define_method(:gateway_available?) do
              defined?(Legion::Extensions::LLM::Gateway::Runners::Inference)
            end
          end

          register_chat(app)
        end

        def self.register_chat(app) # rubocop:disable Metrics/MethodLength,Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity
          app.post '/api/llm/chat' do # rubocop:disable Metrics/BlockLength
            Legion::Logging.debug "API: POST /api/llm/chat params=#{params.keys}"
            require_llm!

            body = parse_request_body
            validate_required!(body, :message)

            message = body[:message]

            # Tier 0 check — serve from PatternStore if available
            if defined?(Legion::MCP::TierRouter)
              tier_result = Legion::MCP::TierRouter.route(
                intent:  message,
                params:  body.except(:message, :model, :provider, :request_id),
                context: {}
              )
              if tier_result[:tier]&.zero?
                return json_response({
                                       response:           tier_result[:response],
                                       tier:               0,
                                       latency_ms:         tier_result[:latency_ms],
                                       pattern_confidence: tier_result[:pattern_confidence]
                                     })
              end
            end

            request_id = body[:request_id] || SecureRandom.uuid
            model      = body[:model]
            provider   = body[:provider]

            # Route through full Legion pipeline when gateway is available:
            #   Ingress -> RBAC -> Events -> Task -> Gateway (metering + fleet) -> LLM
            if gateway_available?
              ingress_result = Legion::Ingress.run(
                payload:      { message: message, model: model, provider: provider,
                                request_id: request_id },
                runner_class: 'Legion::Extensions::LLM::Gateway::Runners::Inference',
                function:     'chat',
                source:       'api'
              )

              unless ingress_result[:success]
                Legion::Logging.error "[api/llm/chat] ingress failed: #{ingress_result}"
                return json_response({ error: ingress_result[:error] || ingress_result[:status] },
                                     status_code: 502)
              end

              result = ingress_result[:result]

              if result.nil?
                Legion::Logging.warn "[api/llm/chat] runner returned nil (status=#{ingress_result[:status]})"
                return json_response({ error: { code:    'empty_result',
                                                message: 'Gateway runner returned no result' } },
                                     status_code: 502)
              end

              response_content = if result.respond_to?(:content)
                                   result.content
                                 elsif result.is_a?(Hash) && result[:error]
                                   return json_response({ error: result[:error] }, status_code: 502)
                                 elsif result.is_a?(Hash)
                                   result[:response] || result[:content] || result.to_s
                                 else
                                   result.to_s
                                 end

              meta = { routed_via: 'gateway' }
              meta[:model] = result.model.to_s if result.respond_to?(:model)
              meta[:tokens_in] = result.input_tokens if result.respond_to?(:input_tokens)
              meta[:tokens_out] = result.output_tokens if result.respond_to?(:output_tokens)

              return json_response({ response: response_content, meta: meta }, status_code: 201)
            end

            # Fallback: direct LLM call (no metering, no task tracking)
            if cache_available? && env['HTTP_X_LEGION_SYNC'] != 'true'
              llm = Legion::LLM
              rc  = Legion::LLM::ResponseCache
              rc.init_request(request_id)

              Thread.new do
                session  = llm.chat_direct(model: model, provider: provider)
                response = session.ask(message)
                rc.complete(
                  request_id,
                  response: response.content,
                  meta:     {
                    model:      session.model.to_s,
                    tokens_in:  response.respond_to?(:input_tokens) ? response.input_tokens : nil,
                    tokens_out: response.respond_to?(:output_tokens) ? response.output_tokens : nil
                  }
                )
              rescue StandardError => e
                Legion::Logging.error "API POST /api/llm/chat async: #{e.class} — #{e.message}"
                rc.fail_request(request_id, code: 'llm_error', message: e.message)
              end

              Legion::Logging.info "API: LLM chat request #{request_id} queued async"
              json_response({ request_id: request_id, poll_key: "llm:#{request_id}:status" },
                            status_code: 202)
            else
              session  = Legion::LLM.chat_direct(model: model, provider: provider)
              response = session.ask(message)
              Legion::Logging.info "API: LLM chat request #{request_id} completed sync model=#{session.model}"
              json_response(
                {
                  response: response.content,
                  meta:     {
                    model:      session.model.to_s,
                    tokens_in:  response.respond_to?(:input_tokens) ? response.input_tokens : nil,
                    tokens_out: response.respond_to?(:output_tokens) ? response.output_tokens : nil
                  }
                },
                status_code: 201
              )
            end
          end
        end

        class << self
          private :register_chat
        end
      end
    end
  end
end
