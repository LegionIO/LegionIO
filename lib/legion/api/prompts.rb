# frozen_string_literal: true

module Legion
  class API < Sinatra::Base
    module Routes
      module Prompts
        def self.registered(app)
          app.helpers do
            define_method(:require_llm!) do
              return if defined?(Legion::LLM) &&
                        Legion::LLM.respond_to?(:started?) &&
                        Legion::LLM.started?

              halt 503, json_error('llm_unavailable', 'LLM subsystem is not available', status_code: 503)
            end

            define_method(:prompt_client) do
              require 'legion/extensions/prompt/client'
              Legion::Extensions::Prompt::Client.new
            rescue LoadError
              halt 503, json_error('prompt_unavailable', 'lex-prompt is not loaded', status_code: 503)
            end
          end

          register_list(app)
          register_show(app)
          register_run(app)
        end

        def self.register_list(app)
          app.get '/api/prompts' do
            client = prompt_client
            result = client.list_prompts
            json_response(result)
          rescue StandardError => e
            Legion::Logging.error "API prompts list error: #{e.message}"
            json_error('execution_error', e.message, status_code: 500)
          end
        end

        def self.register_show(app)
          app.get '/api/prompts/:name' do
            name = params[:name]
            client = prompt_client
            result = client.get_prompt(name: name)

            halt 404, json_error('not_found', "prompt '#{name}' not found", status_code: 404) if result[:error]

            json_response(result)
          rescue StandardError => e
            Legion::Logging.error "API prompts show error: #{e.message}"
            json_error('execution_error', e.message, status_code: 500)
          end
        end

        def self.register_run(app)
          app.post '/api/prompts/:name/run' do
            require_llm!

            name      = params[:name]
            body      = parse_request_body
            variables = body[:variables] || {}
            version   = body[:version]
            model     = body[:model]
            provider  = body[:provider]

            client = prompt_client
            rendered = client.render_prompt(name: name, variables: variables, version: version)

            if rendered[:error]
              code = rendered[:error] == 'not_found' ? 404 : 422
              halt code, json_error(rendered[:error], "prompt '#{name}' #{rendered[:error].tr('_', ' ')}", status_code: code)
            end

            session  = Legion::LLM.chat_direct(model: model, provider: provider)
            response = session.ask(rendered[:rendered])

            prompt_version = rendered[:prompt_version]
            model_used     = session.model.to_s

            usage = {
              input_tokens:  response.respond_to?(:input_tokens) ? response.input_tokens : nil,
              output_tokens: response.respond_to?(:output_tokens) ? response.output_tokens : nil
            }

            json_response({
                            name:            name,
                            version:         prompt_version,
                            rendered_prompt: rendered[:rendered],
                            response:        response.content,
                            usage:           usage,
                            model:           model_used,
                            provider:        provider
                          })
          rescue StandardError => e
            Legion::Logging.error "API prompts run error: #{e.message}"
            json_error('execution_error', e.message, status_code: 500)
          end
        end

        class << self
          private :register_list, :register_show, :register_run
        end
      end
    end
  end
end
