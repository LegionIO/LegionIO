# frozen_string_literal: true

module Legion
  class API < Sinatra::Base
    module Routes
      module Schedules
        def self.registered(app)
          register_list_and_create(app)
          register_show_update_delete(app)
          register_logs(app)
        end

        def self.register_list_and_create(app)
          app.get '/api/schedules' do
            require_scheduler!
            dataset = Legion::Extensions::Scheduler::Data::Model::Schedule.order(:id)
            dataset = dataset.where(active: true) if params[:active] == 'true'
            json_collection(dataset)
          end

          app.post '/api/schedules' do
            Legion::Logging.debug "API: POST /api/schedules params=#{params.keys}"
            require_scheduler!
            body = parse_request_body

            unless body[:function_id]
              Legion::Logging.warn 'API POST /api/schedules returned 422: function_id is required'
              halt 422, json_error('missing_field', 'function_id is required', status_code: 422)
            end
            unless body[:cron] || body[:interval]
              Legion::Logging.warn 'API POST /api/schedules returned 422: cron or interval is required'
              halt 422, json_error('missing_field', 'cron or interval is required', status_code: 422)
            end

            attrs = build_schedule_attrs(body)
            id = Legion::Extensions::Scheduler::Data::Model::Schedule.insert(attrs)
            schedule = Legion::Extensions::Scheduler::Data::Model::Schedule[id]
            Legion::Logging.info "API: created schedule #{id}"
            json_response(schedule.values, status_code: 201)
          end
        end

        def self.register_show_update_delete(app)
          app.get '/api/schedules/:id' do
            require_scheduler!
            schedule = find_or_halt(Legion::Extensions::Scheduler::Data::Model::Schedule, params[:id])
            json_response(schedule.values)
          end

          app.put '/api/schedules/:id' do
            require_scheduler!
            schedule = find_or_halt(Legion::Extensions::Scheduler::Data::Model::Schedule, params[:id])
            body = parse_request_body

            updates = build_schedule_updates(body)
            schedule.update(updates) unless updates.empty?
            schedule.refresh
            Legion::Logging.info "API: updated schedule #{params[:id]}"
            json_response(schedule.values)
          end

          app.delete '/api/schedules/:id' do
            require_scheduler!
            schedule = find_or_halt(Legion::Extensions::Scheduler::Data::Model::Schedule, params[:id])
            schedule.delete
            Legion::Logging.info "API: deleted schedule #{params[:id]}"
            json_response({ deleted: true })
          end
        end

        def self.register_logs(app)
          app.get '/api/schedules/:id/logs' do
            require_scheduler!
            find_or_halt(Legion::Extensions::Scheduler::Data::Model::Schedule, params[:id])
            logs = Legion::Extensions::Scheduler::Data::Model::ScheduleLog
                   .where(schedule_id: params[:id].to_i)
                   .order(Sequel.desc(:id))
            json_collection(logs)
          end
        end

        class << self
          private :register_list_and_create, :register_show_update_delete, :register_logs
        end
      end
    end
  end
end
