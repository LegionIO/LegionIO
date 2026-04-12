# frozen_string_literal: true

require 'securerandom'
require 'open3'

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

            define_method(:build_client_tool_class) do |tname, tdesc, tschema|
              klass = Class.new(RubyLLM::Tool) do
                description tdesc
                define_method(:name) { tname }
                tool_ref = tname
                define_method(:execute) do |**kwargs|
                  case tool_ref
                  when 'sh'
                    cmd = kwargs[:command] || kwargs[:cmd] || kwargs.values.first.to_s
                    output, status = ::Open3.capture2e(cmd, chdir: Dir.pwd)
                    "exit=#{status.exitstatus}\n#{output}"
                  when 'file_read'
                    path = kwargs[:path] || kwargs[:file_path] || kwargs.values.first.to_s
                    ::File.exist?(path) ? ::File.read(path, encoding: 'utf-8') : "File not found: #{path}"
                  when 'file_write'
                    path = kwargs[:path] || kwargs[:file_path]
                    content = kwargs[:content] || kwargs[:contents]
                    ::File.write(path, content)
                    "Written #{content.to_s.bytesize} bytes to #{path}"
                  when 'file_edit'
                    path = kwargs[:path] || kwargs[:file_path]
                    old_text = kwargs[:old_text] || kwargs[:search]
                    new_text = kwargs[:new_text] || kwargs[:replace]
                    content = ::File.read(path, encoding: 'utf-8')
                    content.sub!(old_text, new_text)
                    ::File.write(path, content)
                    "Edited #{path}"
                  when 'list_directory'
                    path = kwargs[:path] || kwargs[:dir] || Dir.pwd
                    Dir.entries(path).reject { |e| e.start_with?('.') }.sort.join("\n")
                  when 'grep'
                    pattern = kwargs[:pattern] || kwargs[:query] || kwargs.values.first.to_s
                    path = kwargs[:path] || Dir.pwd
                    output, = ::Open3.capture2e('grep', '-rn', '--include=*.rb', pattern, path)
                    output.lines.first(50).join
                  when 'glob'
                    pattern = kwargs[:pattern] || kwargs.values.first.to_s
                    Dir.glob(pattern).first(100).join("\n")
                  when 'web_fetch'
                    url = kwargs[:url] || kwargs.values.first.to_s
                    require 'net/http'
                    uri = URI(url)
                    Net::HTTP.get(uri)
                  else
                    "Tool #{tool_ref} is not executable server-side. Use a legion_ prefixed tool instead."
                  end
                rescue StandardError => e
                  Legion::Logging.log_exception(e, payload_summary: "client tool #{tool_ref} failed", component_type: :api)
                  "Tool error: #{e.message}"
                end
              end
              klass.params(tschema) if tschema.is_a?(Hash) && tschema[:properties]
              klass
            rescue StandardError => e
              Legion::Logging.log_exception(e, payload_summary: "build_client_tool_class failed for #{tname}", component_type: :api)
              nil
            end

            define_method(:extract_tool_calls) do |pipeline_response|
              tools_data = pipeline_response.tools
              return nil unless tools_data.is_a?(Array) && !tools_data.empty?

              tools_data.map do |tc|
                {
                  id:        tc.respond_to?(:id) ? tc.id : nil,
                  name:      tc.respond_to?(:name) ? tc.name : tc.to_s,
                  arguments: tc.respond_to?(:arguments) ? tc.arguments : {}
                }
              end
            end
          end

          register_chat(app)
          register_providers(app)
        end

        def self.register_chat(app)
          register_inference(app)

          app.post '/api/llm/chat' do
            Legion::Logging.debug "API: POST /api/llm/chat params=#{params.keys}"
            require_llm!

            body = parse_request_body
            validate_required!(body, :message)

            message = body[:message]

            # Tier 0 check - serve from PatternStore if available
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

            # Route through full Legion pipeline when gateway is available
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
                Legion::Logging.log_exception(e, payload_summary: 'api/llm/chat async failed', component_type: :api)
                rc.fail_request(request_id, code: 'llm_error', message: e.message)
              end

              Legion::Logging.info "API: LLM chat request #{request_id} queued async"
              json_response({ request_id: request_id, poll_key: "llm:#{request_id}:status" },
                            status_code: 202)
            else
              session  = Legion::LLM.chat(model: model, provider: provider,
                                          caller: { source: 'api', path: request.path })
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

        def self.register_inference(app)
          app.post '/api/llm/inference' do
            require_llm!
            body = parse_request_body
            validate_required!(body, :messages)

            messages        = body[:messages]
            tools           = body[:tools] || []
            model           = body[:model]
            provider        = body[:provider]
            requested_tools = body[:requested_tools] || []

            unless messages.is_a?(Array)
              halt 400, { 'Content-Type' => 'application/json' },
                   Legion::JSON.dump({ error: { code: 'invalid_messages', message: 'messages must be an array' } })
            end

            caller_identity = env['legion.tenant_id'] || 'api:inference'

            # GAIA bridge - push InputFrame to sensory buffer
            last_user = messages.select { |m| (m[:role] || m['role']).to_s == 'user' }.last
            prompt    = (last_user || {})[:content] || (last_user || {})['content'] || ''

            if defined?(Legion::Gaia) && Legion::Gaia.respond_to?(:started?) && Legion::Gaia.started? && prompt.length.positive?
              begin
                frame = Legion::Gaia::InputFrame.new(
                  content:      prompt,
                  channel_id:   :api,
                  content_type: :text,
                  auth_context: { identity: caller_identity },
                  metadata:     { source_type: :human_direct, salience: 0.5 }
                )
                Legion::Gaia.ingest(frame)
              rescue StandardError => e
                Legion::Logging.log_exception(e, payload_summary: 'gaia ingest failed in inference', component_type: :api)
              end
            end

            # Build client-side tool classes from Interlink definitions
            tool_classes = tools.filter_map do |t|
              ts = t.respond_to?(:transform_keys) ? t.transform_keys(&:to_sym) : t
              build_client_tool_class(ts[:name].to_s, ts[:description].to_s, ts[:parameters] || ts[:input_schema])
            end

            Legion::Logging.debug "[llm][api] inference inbound client_tools=#{tool_classes.size} requested_tools=#{requested_tools.size}"

            # Detect streaming mode
            streaming = body[:stream] == true && env['HTTP_ACCEPT']&.include?('text/event-stream')

            # Executor handles all registry tool injection — API only passes client-defined tools
            require 'legion/llm/pipeline/request' unless defined?(Legion::LLM::Pipeline::Request)
            require 'legion/llm/pipeline/executor' unless defined?(Legion::LLM::Pipeline::Executor)

            principal  = defined?(Legion::Identity::Request) && env['legion.principal']
            caller_ctx = if principal
                           principal.to_caller_hash
                         else
                           { requested_by: { identity: caller_identity, type: :user, credential: :api } }
                         end

            caller_metadata = body[:metadata].is_a?(Hash) ? body[:metadata] : {}
            req = Legion::LLM::Pipeline::Request.build(
              messages:        messages,
              system:          body[:system],
              routing:         { provider: provider, model: model },
              tools:           tool_classes,
              caller:          caller_ctx,
              conversation_id: body[:conversation_id],
              metadata:        caller_metadata.merge(requested_tools: requested_tools),
              stream:          streaming,
              cache:           { strategy: :default, cacheable: true }
            )
            executor = Legion::LLM::Pipeline::Executor.new(req)

            if streaming
              content_type 'text/event-stream'
              headers 'Cache-Control' => 'no-cache', 'Connection' => 'keep-alive',
                      'X-Accel-Buffering' => 'no'

              stream do |out|
                # Wire up real-time tool-call / tool-result / tool-error / model-fallback SSE events.
                # The executor fires tool_event_handler for each event as it happens,
                # including accurate wall-clock startedAt/finishedAt/durationMs timing.
                emitted_tool_call_ids = Set.new
                executor.tool_event_handler = lambda do |event|
                  case event[:type]
                  when :tool_call
                    emitted_tool_call_ids << event[:tool_call_id] if event[:tool_call_id]
                    out << "event: tool-call\ndata: #{Legion::JSON.dump({
                                                                          toolCallId: event[:tool_call_id],
                                                                          toolName:   event[:tool_name],
                                                                          args:       event[:arguments] || {},
                                                                          startedAt:  event[:started_at]&.iso8601(3),
                                                                          timestamp:  event[:started_at]&.iso8601(3) || Time.now.iso8601(3)
                                                                        })}\n\n"
                  when :tool_result
                    out << "event: tool-result\ndata: #{Legion::JSON.dump({
                                                                            toolCallId: event[:tool_call_id],
                                                                            toolName:   event[:tool_name],
                                                                            result:     event[:result],
                                                                            startedAt:  event[:started_at]&.iso8601(3),
                                                                            finishedAt: event[:finished_at]&.iso8601(3) || Time.now.iso8601(3),
                                                                            durationMs: event[:duration_ms],
                                                                            timestamp:  event[:finished_at]&.iso8601(3) || Time.now.iso8601(3)
                                                                          })}\n\n"
                  when :tool_error
                    out << "event: tool-error\ndata: #{Legion::JSON.dump({
                                                                           toolCallId: event[:tool_call_id],
                                                                           toolName:   event[:tool_name],
                                                                           error:      (event[:error] || event[:result]).to_s,
                                                                           startedAt:  event[:started_at]&.iso8601(3),
                                                                           finishedAt: Time.now.iso8601(3),
                                                                           timestamp:  Time.now.iso8601(3)
                                                                         })}\n\n"
                  when :model_fallback
                    out << "event: model-fallback\ndata: #{Legion::JSON.dump({
                                                                               fromModel:  event[:from_model],
                                                                               toModel:    event[:to_model],
                                                                               toModelKey: event[:to_model],
                                                                               error:      event[:error] || 'Provider unavailable',
                                                                               reason:     event[:reason] || 'provider_fallback'
                                                                             })}\n\n"
                  end
                end

                full_text = +''
                pipeline_response = executor.call_stream do |chunk|
                  text = chunk.respond_to?(:content) ? chunk.content.to_s : chunk.to_s
                  next if text.empty?

                  full_text << text
                  out << "event: text-delta\ndata: #{Legion::JSON.dump({ delta: text })}\n\n"
                end

                # Post-hoc safety net: emit any tool-calls that weren't fired in real-time
                # (e.g. non-streaming tool paths). Skip IDs already sent via tool_event_handler.
                if pipeline_response.tools.is_a?(Array) && !pipeline_response.tools.empty?
                  pipeline_response.tools.each do |tc|
                    tc_id = tc.respond_to?(:id) ? tc.id : nil
                    next if tc_id && emitted_tool_call_ids.include?(tc_id)

                    out << "event: tool-call\ndata: #{Legion::JSON.dump({
                                                                          toolCallId: tc_id,
                                                                          toolName:   tc.respond_to?(:name) ? tc.name : tc.to_s,
                                                                          args:       tc.respond_to?(:arguments) ? tc.arguments : {}
                                                                        })}\n\n"
                  end
                end

                # Emit any model-fallback warnings collected post-hoc
                Array(pipeline_response.warnings).each do |w|
                  next unless w.is_a?(Hash) && w[:type] == :provider_fallback

                  fallback = w[:fallback].to_s
                  provider, model = fallback.split(':', 2)
                  resolved_model = (model || provider).to_s.strip
                  next if resolved_model.empty?

                  out << "event: model-fallback\ndata: #{Legion::JSON.dump({
                                                                             fromModel:  pipeline_response.routing&.dig(:model),
                                                                             toModel:    resolved_model,
                                                                             toModelKey: resolved_model,
                                                                             error:      w[:original_error] || 'Provider unavailable',
                                                                             reason:     'provider_fallback'
                                                                           })}\n\n"
                end

                enrichments = pipeline_response.enrichments
                out << "event: enrichment\ndata: #{Legion::JSON.dump(enrichments)}\n\n" if enrichments.is_a?(Hash) && !enrichments.empty?

                tokens = pipeline_response.tokens
                out << "event: done\ndata: #{Legion::JSON.dump({
                  content:            full_text,
                  model:              pipeline_response.routing&.dig(:model),
                  conversation_id:    pipeline_response.conversation_id,
                  stop_reason:        pipeline_response.stop&.dig(:reason)&.to_s,
                  input_tokens:       tokens.respond_to?(:input_tokens)        ? tokens.input_tokens        : nil,
                  output_tokens:      tokens.respond_to?(:output_tokens)       ? tokens.output_tokens       : nil,
                  cache_read_tokens:  tokens.respond_to?(:cache_read_tokens)   ? tokens.cache_read_tokens   : nil,
                  cache_write_tokens: tokens.respond_to?(:cache_write_tokens)  ? tokens.cache_write_tokens  : nil
                }.compact)}\n\n"
              rescue StandardError => e
                Legion::Logging.log_exception(e, payload_summary: 'api/llm/inference stream failed', component_type: :api)
                out << "event: error\ndata: #{Legion::JSON.dump({ code: 'stream_error', message: e.message })}\n\n"
              end
            else
              pipeline_response = executor.call
              tokens = pipeline_response.tokens

              json_response({
                              content:       pipeline_response.message&.dig(:content),
                              tool_calls:    extract_tool_calls(pipeline_response),
                              stop_reason:   pipeline_response.stop&.dig(:reason),
                              model:         pipeline_response.routing&.dig(:model) || model,
                              input_tokens:  tokens.respond_to?(:input_tokens) ? tokens.input_tokens : nil,
                              output_tokens: tokens.respond_to?(:output_tokens) ? tokens.output_tokens : nil
                            }, status_code: 200)
            end
          rescue Legion::LLM::AuthError => e
            Legion::Logging.log_exception(e, payload_summary: 'api/llm/inference auth failed', component_type: :api)
            json_response({ error: { code: 'auth_error', message: e.message } }, status_code: 401)
          rescue Legion::LLM::RateLimitError => e
            Legion::Logging.log_exception(e, payload_summary: 'api/llm/inference rate limited', component_type: :api)
            json_response({ error: { code: 'rate_limit', message: e.message } }, status_code: 429)
          rescue Legion::LLM::TokenBudgetExceeded => e
            Legion::Logging.log_exception(e, payload_summary: 'api/llm/inference token budget exceeded', component_type: :api)
            json_response({ error: { code: 'token_budget_exceeded', message: e.message } }, status_code: 413)
          rescue Legion::LLM::ProviderDown, Legion::LLM::ProviderError => e
            Legion::Logging.log_exception(e, payload_summary: 'api/llm/inference provider error', component_type: :api)
            json_response({ error: { code: 'provider_error', message: e.message } }, status_code: 502)
          rescue StandardError => e
            Legion::Logging.log_exception(e, payload_summary: 'api/llm/inference failed', component_type: :api)
            json_response({ error: { code: 'inference_error', message: e.message } }, status_code: 500)
          end
        end

        def self.register_providers(app)
          app.get '/api/llm/providers' do
            require_llm!
            unless gateway_available? && defined?(Legion::Extensions::LLM::Gateway::Runners::ProviderStats)
              halt 503, json_error('gateway_unavailable', 'LLM gateway is not loaded', status_code: 503)
            end

            stats = Legion::Extensions::LLM::Gateway::Runners::ProviderStats
            json_response({
                            providers: stats.health_report,
                            summary:   stats.circuit_summary
                          })
          end

          app.get '/api/llm/providers/:name' do
            require_llm!
            unless gateway_available? && defined?(Legion::Extensions::LLM::Gateway::Runners::ProviderStats)
              halt 503, json_error('gateway_unavailable', 'LLM gateway is not loaded', status_code: 503)
            end

            stats = Legion::Extensions::LLM::Gateway::Runners::ProviderStats
            detail = stats.provider_detail(provider: params[:name])
            json_response(detail)
          end
        end

        class << self
          private :register_chat, :register_inference, :register_providers
        end
      end
    end
  end
end
