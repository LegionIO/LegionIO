# frozen_string_literal: true

module Legion
  class API < Sinatra::Base
    module Routes
      module Schedules
        def self.registered(app)
          app.get '/api/schedules' do
            require_scheduler!
            dataset = Legion::Extensions::Scheduler::Data::Model::Schedule.order(:id)
            dataset = dataset.where(active: true) if params[:active] == 'true'
            json_collection(dataset)
          end

          app.post '/api/schedules' do
            require_scheduler!
            body = parse_request_body

            halt 422, json_error('missing_field', 'function_id is required', status_code: 422) unless body[:function_id]

            halt 422, json_error('missing_field', 'cron or interval is required', status_code: 422) unless body[:cron] || body[:interval]

            attrs = {}
            attrs[:function_id] = body[:function_id].to_i
            attrs[:cron] = body[:cron] if body[:cron]
            attrs[:interval] = body[:interval].to_i if body[:interval]
            attrs[:active] = body.fetch(:active, true)
            attrs[:task_ttl] = body[:task_ttl].to_i if body[:task_ttl]
            attrs[:payload] = Legion::JSON.dump(body[:payload] || {})
            attrs[:transformation] = body[:transformation] if body[:transformation]
            attrs[:last_run] = Time.at(0)

            id = Legion::Extensions::Scheduler::Data::Model::Schedule.insert(attrs)
            schedule = Legion::Extensions::Scheduler::Data::Model::Schedule[id]
            json_response(schedule.values, status_code: 201)
          end

          app.get '/api/schedules/:id' do
            require_scheduler!
            schedule = find_or_halt(Legion::Extensions::Scheduler::Data::Model::Schedule, params[:id])
            json_response(schedule.values)
          end

          app.put '/api/schedules/:id' do
            require_scheduler!
            schedule = find_or_halt(Legion::Extensions::Scheduler::Data::Model::Schedule, params[:id])
            body = parse_request_body

            updates = {}
            updates[:cron] = body[:cron] if body.key?(:cron)
            updates[:interval] = body[:interval].to_i if body.key?(:interval)
            updates[:active] = body[:active] if body.key?(:active)
            updates[:task_ttl] = body[:task_ttl].to_i if body.key?(:task_ttl)
            updates[:function_id] = body[:function_id].to_i if body.key?(:function_id)
            updates[:payload] = Legion::JSON.dump(body[:payload]) if body.key?(:payload)
            updates[:transformation] = body[:transformation] if body.key?(:transformation)

            schedule.update(updates) unless updates.empty?
            schedule.refresh
            json_response(schedule.values)
          end

          app.delete '/api/schedules/:id' do
            require_scheduler!
            schedule = find_or_halt(Legion::Extensions::Scheduler::Data::Model::Schedule, params[:id])
            schedule.delete
            json_response({ deleted: true })
          end

          app.get '/api/schedules/:id/logs' do
            require_scheduler!
            find_or_halt(Legion::Extensions::Scheduler::Data::Model::Schedule, params[:id])
            logs = Legion::Extensions::Scheduler::Data::Model::ScheduleLog
                   .where(schedule_id: params[:id].to_i)
                   .order(Sequel.desc(:id))
            json_collection(logs)
          end
        end
      end
    end
  end
end
