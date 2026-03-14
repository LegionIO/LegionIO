# frozen_string_literal: true

module Legion
  class API < Sinatra::Base
    module Routes
      module Workers
        def self.registered(app)
          register_collection(app)
          register_member(app)
          register_sub_resources(app)
          register_teams(app)
        end

        def self.register_collection(app)
          app.get '/api/workers' do
            require_data!
            dataset = Legion::Data::Model::DigitalWorker.order(:id)
            dataset = dataset.where(team: params[:team])               if params[:team]
            dataset = dataset.where(owner_msid: params[:owner_msid])   if params[:owner_msid]
            dataset = dataset.where(lifecycle_state: params[:lifecycle_state]) if params[:lifecycle_state]
            dataset = dataset.where(risk_tier: params[:risk_tier]) if params[:risk_tier]
            json_collection(dataset)
          end

          app.post '/api/workers' do
            require_data!
            body = parse_request_body

            halt 422, json_error('missing_field', 'name is required',           status_code: 422) unless body[:name]
            halt 422, json_error('missing_field', 'extension_name is required', status_code: 422) unless body[:extension_name]
            halt 422, json_error('missing_field', 'entra_app_id is required',   status_code: 422) unless body[:entra_app_id]
            halt 422, json_error('missing_field', 'owner_msid is required',     status_code: 422) unless body[:owner_msid]

            worker = Legion::DigitalWorker.register(
              name:           body[:name],
              extension_name: body[:extension_name],
              entra_app_id:   body[:entra_app_id],
              owner_msid:     body[:owner_msid],
              owner_name:     body[:owner_name],
              business_role:  body[:business_role],
              risk_tier:      body[:risk_tier],
              team:           body[:team],
              manager_msid:   body[:manager_msid]
            )
            json_response(worker.values, status_code: 201)
          rescue StandardError => e
            Legion::Logging.error "API worker create error: #{e.message}"
            json_error('creation_error', e.message, status_code: 500)
          end
        end

        def self.register_member(app) # rubocop:disable Metrics/AbcSize
          app.get '/api/workers/:id' do
            require_data!
            worker = Legion::Data::Model::DigitalWorker.first(worker_id: params[:id])
            halt 404, json_error('not_found', "Worker #{params[:id]} not found", status_code: 404) if worker.nil?
            json_response(worker.values)
          end

          app.patch '/api/workers/:id/lifecycle' do
            require_data!
            worker = Legion::Data::Model::DigitalWorker.first(worker_id: params[:id])
            halt 404, json_error('not_found', "Worker #{params[:id]} not found", status_code: 404) if worker.nil?

            body     = parse_request_body
            to_state = body[:state]
            by       = body[:by] || current_owner_msid || 'api'
            reason   = body[:reason]

            halt 422, json_error('missing_field', 'state is required', status_code: 422) unless to_state

            updated = Legion::DigitalWorker::Lifecycle.transition!(worker, to_state: to_state, by: by, reason: reason)
            json_response(updated.values)
          rescue Legion::DigitalWorker::Lifecycle::InvalidTransition => e
            json_error('invalid_transition', e.message, status_code: 422)
          rescue StandardError => e
            Legion::Logging.error "API worker lifecycle error: #{e.message}"
            json_error('transition_error', e.message, status_code: 500)
          end

          app.delete '/api/workers/:id' do
            require_data!
            worker = Legion::Data::Model::DigitalWorker.first(worker_id: params[:id])
            halt 404, json_error('not_found', "Worker #{params[:id]} not found", status_code: 404) if worker.nil?

            by     = current_owner_msid || 'api'
            reason = params[:reason] || 'retired via API'

            updated = Legion::DigitalWorker::Lifecycle.transition!(worker, to_state: 'retired', by: by, reason: reason)
            json_response(updated.values)
          rescue Legion::DigitalWorker::Lifecycle::InvalidTransition => e
            json_error('invalid_transition', e.message, status_code: 422)
          rescue StandardError => e
            Legion::Logging.error "API worker delete error: #{e.message}"
            json_error('transition_error', e.message, status_code: 500)
          end
        end

        def self.register_sub_resources(app) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
          app.get '/api/workers/:id/tasks' do
            require_data!
            worker = Legion::Data::Model::DigitalWorker.first(worker_id: params[:id])
            halt 404, json_error('not_found', "Worker #{params[:id]} not found", status_code: 404) if worker.nil?

            dataset = Legion::Data::Model::Task.where(worker_id: params[:id]).order(Sequel.desc(:id))
            json_collection(dataset)
          end

          app.get '/api/workers/:id/events' do
            require_data!
            worker = Legion::Data::Model::DigitalWorker.first(worker_id: params[:id])
            halt 404, json_error('not_found', "Worker #{params[:id]} not found", status_code: 404) if worker.nil?

            json_response({
                            worker_id: params[:id],
                            events:    [],
                            note:      'lifecycle event persistence is not yet implemented'
                          })
          end

          app.get '/api/workers/:id/costs' do
            require_data!
            worker = Legion::Data::Model::DigitalWorker.first(worker_id: params[:id])
            halt 404, json_error('not_found', "Worker #{params[:id]} not found", status_code: 404) if worker.nil?

            json_response({
                            worker_id:       params[:id],
                            total_cost:      nil,
                            currency:        'USD',
                            metering_period: nil,
                            note:            'cost metering requires lex-metering'
                          })
          end

          app.get '/api/workers/:id/value' do
            require_data!
            worker = Legion::Data::Model::DigitalWorker.first(worker_id: params[:id])
            halt 404, json_error('not_found', "Worker #{params[:id]} not found", status_code: 404) if worker.nil?

            summary = Legion::DigitalWorker::ValueMetrics.summary(worker_id: params[:id])
            recent  = Legion::DigitalWorker::ValueMetrics.for_worker(
              worker_id: params[:id],
              since:     params[:since] ? Time.parse(params[:since]) : (Time.now.utc - (86_400 * 7))
            )

            json_response({
                            worker_id: params[:id],
                            summary:   summary,
                            recent:    recent.last(50)
                          })
          rescue StandardError => e
            Legion::Logging.error "API worker value error: #{e.message}"
            json_error('value_error', e.message, status_code: 500)
          end

          app.get '/api/workers/:id/roi' do
            require_data!
            worker = Legion::Data::Model::DigitalWorker.first(worker_id: params[:id])
            halt 404, json_error('not_found', "Worker #{params[:id]} not found", status_code: 404) if worker.nil?

            value_summary = Legion::DigitalWorker::ValueMetrics.summary(worker_id: params[:id])

            cost_summary = if defined?(Legion::Extensions::Metering::Runners::Metering)
                             runner = Object.new.extend(Legion::Extensions::Metering::Runners::Metering)
                             runner.worker_costs(worker_id: params[:id], period: params[:period] || 'monthly')
                           else
                             { total_tokens: 0, total_calls: 0, note: 'lex-metering not available' }
                           end

            json_response({
                            worker_id: params[:id],
                            value:     value_summary,
                            cost:      cost_summary
                          })
          rescue StandardError => e
            Legion::Logging.error "API worker ROI error: #{e.message}"
            json_error('roi_error', e.message, status_code: 500)
          end
        end

        def self.register_teams(app)
          app.get '/api/teams/:team/workers' do
            require_data!
            dataset = Legion::Data::Model::DigitalWorker.where(team: params[:team]).order(:id)
            json_collection(dataset)
          end

          app.get '/api/teams/:team/costs' do
            require_data!
            json_response({
                            team:            params[:team],
                            total_cost:      nil,
                            currency:        'USD',
                            metering_period: nil,
                            note:            'cost metering requires lex-metering'
                          })
          end
        end

        class << self
          private :register_collection, :register_member, :register_sub_resources, :register_teams
        end
      end
    end
  end
end
