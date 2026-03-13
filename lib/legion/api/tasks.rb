# frozen_string_literal: true

module Legion
  class API < Sinatra::Base
    module Routes
      module Tasks
        def self.registered(app)
          register_collection(app)
          register_member(app)
        end

        def self.register_collection(app)
          app.get '/api/tasks' do
            require_data!
            dataset = Legion::Data::Model::Task.order(Sequel.desc(:id))
            dataset = dataset.where(status: params[:status]) if params[:status]
            dataset = dataset.where(function_id: params[:function_id].to_i) if params[:function_id]
            json_collection(dataset)
          end

          app.post '/api/tasks' do
            body = parse_request_body
            runner_class = body.delete(:runner_class)
            function = body.delete(:function)

            halt 422, json_error('missing_field', 'runner_class is required', status_code: 422) if runner_class.nil?
            halt 422, json_error('missing_field', 'function is required', status_code: 422) if function.nil?

            result = Legion::Ingress.run(
              payload: body, runner_class: runner_class, function: function.to_sym,
              source: 'api', check_subtask: body.fetch(:check_subtask, true),
              generate_task: body.fetch(:generate_task, true)
            )
            json_response(result, status_code: 201)
          rescue NameError => e
            json_error('invalid_runner', e.message, status_code: 422)
          rescue StandardError => e
            Legion::Logging.error "API task create error: #{e.message}"
            json_error('execution_error', e.message, status_code: 500)
          end
        end

        def self.register_member(app)
          app.get '/api/tasks/:id' do
            require_data!
            task = find_or_halt(Legion::Data::Model::Task, params[:id])
            json_response(task.values)
          end

          app.delete '/api/tasks/:id' do
            require_data!
            task = find_or_halt(Legion::Data::Model::Task, params[:id])
            task.delete
            json_response({ deleted: true })
          end

          app.get '/api/tasks/:id/logs' do
            require_data!
            find_or_halt(Legion::Data::Model::Task, params[:id])
            logs = Legion::Data::Model::TaskLog.where(task_id: params[:id].to_i).order(Sequel.desc(:id))
            json_collection(logs)
          end
        end

        class << self
          private :register_collection, :register_member
        end
      end
    end
  end
end
