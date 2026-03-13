# frozen_string_literal: true

module Legion
  class API < Sinatra::Base
    module Routes
      module Extensions
        def self.registered(app)
          register_extension_routes(app)
          register_runner_routes(app)
          register_function_routes(app)
        end

        def self.register_extension_routes(app)
          app.get '/api/extensions' do
            require_data!
            dataset = Legion::Data::Model::Extension.order(:id)
            dataset = dataset.where(active: true) if params[:active] == 'true'
            json_collection(dataset)
          end

          app.get '/api/extensions/:id' do
            require_data!
            ext = find_or_halt(Legion::Data::Model::Extension, params[:id])
            json_response(ext.values)
          end
        end

        def self.register_runner_routes(app)
          app.get '/api/extensions/:id/runners' do
            require_data!
            find_or_halt(Legion::Data::Model::Extension, params[:id])
            runners = Legion::Data::Model::Runner.where(extension_id: params[:id].to_i).order(:id)
            json_collection(runners)
          end

          app.get '/api/extensions/:id/runners/:runner_id' do
            require_data!
            find_or_halt(Legion::Data::Model::Extension, params[:id])
            runner = find_or_halt(Legion::Data::Model::Runner, params[:runner_id])
            json_response(runner.values)
          end
        end

        def self.register_function_routes(app)
          app.get '/api/extensions/:id/runners/:runner_id/functions' do
            require_data!
            find_or_halt(Legion::Data::Model::Extension, params[:id])
            find_or_halt(Legion::Data::Model::Runner, params[:runner_id])
            functions = Legion::Data::Model::Function.where(runner_id: params[:runner_id].to_i).order(:id)
            json_collection(functions)
          end

          app.get '/api/extensions/:id/runners/:runner_id/functions/:function_id' do
            require_data!
            find_or_halt(Legion::Data::Model::Extension, params[:id])
            find_or_halt(Legion::Data::Model::Runner, params[:runner_id])
            func = find_or_halt(Legion::Data::Model::Function, params[:function_id])
            json_response(func.values)
          end

          app.post '/api/extensions/:id/runners/:runner_id/functions/:function_id/invoke' do
            require_data!
            find_or_halt(Legion::Data::Model::Extension, params[:id])
            runner = find_or_halt(Legion::Data::Model::Runner, params[:runner_id])
            func = find_or_halt(Legion::Data::Model::Function, params[:function_id])
            body = parse_request_body

            result = Legion::Ingress.run(
              payload: body, runner_class: runner.values[:namespace],
              function: func.values[:name].to_sym, source: 'api',
              check_subtask: body.fetch(:check_subtask, true),
              generate_task: body.fetch(:generate_task, true)
            )
            json_response(result, status_code: 201)
          rescue NameError => e
            json_error('invalid_runner', e.message, status_code: 422)
          rescue StandardError => e
            Legion::Logging.error "API invoke error: #{e.message}"
            json_error('execution_error', e.message, status_code: 500)
          end
        end

        class << self
          private :register_extension_routes, :register_runner_routes, :register_function_routes
        end
      end
    end
  end
end
