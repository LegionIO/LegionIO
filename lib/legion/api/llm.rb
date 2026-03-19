# frozen_string_literal: true

require 'securerandom'

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
          end

          register_chat(app)
        end

        def self.register_chat(app)
          app.post '/api/llm/chat' do # rubocop:disable Metrics/BlockLength
            require_llm!

            body = parse_request_body
            validate_required!(body, :message)

            request_id = body[:request_id] || SecureRandom.uuid
            message    = body[:message]
            model      = body[:model]
            provider   = body[:provider]

            if cache_available?
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
                rc.fail_request(request_id, code: 'llm_error', message: e.message)
              end

              json_response({ request_id: request_id, poll_key: "llm:#{request_id}:status" },
                            status_code: 202)
            else
              session  = Legion::LLM.chat_direct(model: model, provider: provider)
              response = session.ask(message)
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
