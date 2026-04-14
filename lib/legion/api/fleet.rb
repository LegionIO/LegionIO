# frozen_string_literal: true

module Legion
  class API < Sinatra::Base
    module Routes
      module Fleet
        def self.registered(app)
          app.helpers FleetHelpers

          app.get '/api/fleet/status' do
            json_response(fleet_status)
          end

          app.get '/api/fleet/pending' do
            items = fleet_pending_approvals
            json_response(items)
          end

          app.post '/api/fleet/approve' do
            body = parse_request_body
            id = body[:id]
            halt 400, json_error('missing_id', 'id is required', status_code: 400) unless id

            result = fleet_approve(id.to_i)
            if result[:success]
              json_response(result)
            else
              json_error('approve_failed', result[:error].to_s, status_code: 422)
            end
          end

          app.get '/api/fleet/sources' do
            sources = Legion::Settings.dig(:fleet, :sources) || []
            json_response({ sources: sources })
          end

          app.post '/api/fleet/sources' do
            body = parse_request_body
            source = body[:source]
            halt 400, json_error('missing_source', 'source is required', status_code: 400) unless source

            result = fleet_add_source(body)
            if result[:success]
              json_response(result, status_code: 201)
            else
              json_error('add_source_failed', result[:error].to_s, status_code: 422)
            end
          end
        end

        module FleetHelpers
          def fleet_status
            queues = []
            active = 0
            workers = 0

            if defined?(Legion::Transport) && Legion::Settings.dig(:transport, :connected)
              %w[assessor planner developer validator].each do |ext|
                queue_name = "lex.#{ext}.runners.#{ext}"
                depth = fleet_queue_depth(queue_name)
                queues << { name: queue_name, depth: depth } if depth
              end
            end

            { queues: queues, active_work_items: active, workers: workers }
          end

          def fleet_queue_depth(queue_name)
            return nil unless defined?(Legion::Transport::Session)

            channel = Legion::Transport::Session.channel
            queue = channel.queue(queue_name, passive: true)
            queue.message_count
          rescue StandardError
            nil
          end

          def fleet_pending_approvals
            approval_types = %w[fleet.shipping fleet.escalation]

            if defined?(Legion::Data::Model::Task)
              Legion::Data::Model::Task
                .where(status: 'pending_approval')
                .where(Sequel.lit('JSON_EXTRACT(payload, ?) IN ?',
                                  '$.approval_type', approval_types))
                .order(Sequel.desc(:created_at))
                .limit(page_limit)
                .all
                .map(&:values)
            else
              []
            end
          rescue StandardError => e
            Legion::Logging.warn "Fleet#fleet_pending_approvals: #{e.message}" if defined?(Legion::Logging)
            []
          end

          def fleet_approve(_id)
            { success: false, error: 'approval system not available' }
          end

          def fleet_add_source(body)
            source = body[:source]
            case source
            when 'github'
              fleet_setup_github_source(body)
            else
              { success: false, error: "Unknown source: #{source}" }
            end
          end

          def fleet_setup_github_source(body)
            sources = Legion::Settings.dig(:fleet, :sources) || []
            entry = {
              type:  'github',
              owner: body[:owner],
              repo:  body[:repo]
            }
            sources << entry

            Legion::Settings.loader.settings[:fleet] ||= {}
            Legion::Settings.loader.settings[:fleet][:sources] = sources

            { success: true, source: 'github', absorber: 'issues' }
          rescue StandardError => e
            { success: false, error: e.message }
          end
        end
      end
    end
  end
end
