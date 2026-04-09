# frozen_string_literal: true

module Legion
  class API < Sinatra::Base
    module Routes
      module Extensions
        def self.registered(app)
          register_available_route(app)
          register_extension_routes(app)
          register_runner_routes(app)
          register_function_routes(app)
          register_invoke_route(app)
        end

        def self.register_available_route(app)
          app.get '/api/extensions/available' do
            entries = Legion::Extensions::Catalog::Available.all
            entries = entries.select { |e| e[:category] == params[:category] } if params[:category]
            json_response(entries)
          end
        end

        def self.register_extension_routes(app)
          app.get '/api/extensions' do
            entries = Legion::Extensions::Catalog.all.map do |name, entry|
              { name: name, state: entry[:state].to_s,
                registered_at: entry[:registered_at]&.iso8601,
                started_at: entry[:started_at]&.iso8601 }
            end
            entries = entries.select { |e| e[:state] == params[:state] } if params[:state]
            json_response(entries)
          end

          app.get '/api/extensions/:name' do
            name = params[:name]
            entry = Legion::Extensions::Catalog.entry(name)
            halt_not_found("extension '#{name}' not found") unless entry

            ext_mod = find_extension_module(name)
            version = ext_mod&.const_defined?(:VERSION) ? ext_mod::VERSION : nil

            runners = ext_mod ? runner_summaries(ext_mod) : []

            json_response({
              name:          name,
              state:         entry[:state].to_s,
              version:       version,
              registered_at: entry[:registered_at]&.iso8601,
              started_at:    entry[:started_at]&.iso8601,
              runners:       runners
            }.compact)
          end
        end

        def self.register_runner_routes(app)
          app.get '/api/extensions/:name/runners' do
            name = params[:name]
            halt_not_found("extension '#{name}' not found") unless Legion::Extensions::Catalog.entry(name)

            ext_mod = find_extension_module(name)
            halt_not_found("extension '#{name}' not loaded") unless ext_mod

            json_response(runner_summaries(ext_mod))
          end

          app.get '/api/extensions/:name/runners/:runner_name' do
            name = params[:name]
            halt_not_found("extension '#{name}' not found") unless Legion::Extensions::Catalog.entry(name)

            ext_mod = find_extension_module(name)
            halt_not_found("extension '#{name}' not loaded") unless ext_mod

            info = find_runner_info(ext_mod, params[:runner_name])
            halt_not_found("runner '#{params[:runner_name]}' not found") unless info

            runner_mod = info[:runner_module]
            functions = runner_mod.instance_methods(false).map(&:to_s)

            json_response({
                            name:         info[:runner_name],
                            runner_class: info[:runner_class],
                            functions:    functions
                          })
          end
        end

        def self.register_function_routes(app)
          app.get '/api/extensions/:name/runners/:runner_name/functions' do
            name = params[:name]
            halt_not_found("extension '#{name}' not found") unless Legion::Extensions::Catalog.entry(name)

            ext_mod = find_extension_module(name)
            halt_not_found("extension '#{name}' not loaded") unless ext_mod

            info = find_runner_info(ext_mod, params[:runner_name])
            halt_not_found("runner '#{params[:runner_name]}' not found") unless info

            functions = info[:runner_module].instance_methods(false).map do |m|
              args = info.dig(:class_methods, m, :args)
              { name: m.to_s, args: args }
            end
            json_response(functions)
          end

          app.get '/api/extensions/:name/runners/:runner_name/functions/:function_name' do
            name = params[:name]
            halt_not_found("extension '#{name}' not found") unless Legion::Extensions::Catalog.entry(name)

            ext_mod = find_extension_module(name)
            halt_not_found("extension '#{name}' not loaded") unless ext_mod

            info = find_runner_info(ext_mod, params[:runner_name])
            halt_not_found("runner '#{params[:runner_name]}' not found") unless info

            func_sym = params[:function_name].to_sym
            halt_not_found("function '#{params[:function_name]}' not found") unless info[:runner_module].method_defined?(func_sym, false)

            args = info.dig(:class_methods, func_sym, :args)
            json_response({ name: params[:function_name], runner: params[:runner_name], args: args })
          end
        end

        def self.register_invoke_route(app)
          app.post '/api/extensions/:name/runners/:runner_name/functions/:function_name/invoke' do
            name = params[:name]
            halt_not_found("extension '#{name}' not found") unless Legion::Extensions::Catalog.entry(name)

            ext_mod = find_extension_module(name)
            halt_not_found("extension '#{name}' not loaded") unless ext_mod

            info = find_runner_info(ext_mod, params[:runner_name])
            halt_not_found("runner '#{params[:runner_name]}' not found") unless info

            func_sym = params[:function_name].to_sym
            halt_not_found("function '#{params[:function_name]}' not found") unless info[:runner_module].method_defined?(func_sym, false)

            body = parse_request_body

            result = Legion::Ingress.run(
              payload:       body,
              runner_class:  info[:runner_class],
              function:      func_sym,
              source:        'api',
              check_subtask: body.fetch(:check_subtask, true),
              generate_task: body.fetch(:generate_task, true)
            )
            json_response(result, status_code: 201)
          rescue NameError => e
            json_error('invalid_runner', e.message, status_code: 422)
          rescue StandardError => e
            Legion::Logging.error "API POST /api/extensions invoke: #{e.class} - #{e.message}" if defined?(Legion::Logging)
            json_error('execution_error', e.message, status_code: 500)
          end
        end

        class << self
          private :register_available_route, :register_extension_routes,
                  :register_runner_routes, :register_function_routes, :register_invoke_route
        end
      end
    end
  end
end
