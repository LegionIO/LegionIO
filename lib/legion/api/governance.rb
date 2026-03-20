# frozen_string_literal: true

module Legion
  class API < Sinatra::Base
    module Routes
      module Governance
        def self.registered(app)
          app.helpers GovernanceHelpers
          register_approvals(app)
        end

        module GovernanceHelpers
          def run_governance_runner(method, **)
            require 'legion/extensions/audit/runners/approval_queue'
            runner = Object.new.extend(Legion::Extensions::Audit::Runners::ApprovalQueue)
            runner.send(method, **)
          rescue LoadError
            halt 503, json_error('service_unavailable', 'lex-audit not available', status_code: 503)
          end
        end

        def self.register_approvals(app)
          app.get '/api/governance/approvals' do
            require_data!
            result = run_governance_runner(:list_pending,
                                           tenant_id: params[:tenant_id],
                                           limit:     (params[:limit] || 50).to_i)
            json_response(result)
          end

          app.get '/api/governance/approvals/:id' do
            require_data!
            result = run_governance_runner(:show_approval, id: params[:id].to_i)
            if result[:success]
              json_response(result)
            else
              halt 404, json_error('not_found', 'Approval not found', status_code: 404)
            end
          end

          app.post '/api/governance/approvals' do
            require_data!
            body = parse_request_body
            halt 422, json_error('missing_field', 'approval_type is required', status_code: 422) unless body[:approval_type]
            halt 422, json_error('missing_field', 'requester_id is required', status_code: 422) unless body[:requester_id]

            result = run_governance_runner(:submit,
                                           approval_type: body[:approval_type],
                                           payload:       body[:payload] || {},
                                           requester_id:  body[:requester_id],
                                           tenant_id:     body[:tenant_id])
            json_response(result, status_code: 201)
          end

          app.put '/api/governance/approvals/:id/approve' do
            require_data!
            body = parse_request_body
            halt 422, json_error('missing_field', 'reviewer_id is required', status_code: 422) unless body[:reviewer_id]

            result = run_governance_runner(:approve,
                                           id:          params[:id].to_i,
                                           reviewer_id: body[:reviewer_id])
            json_response(result)
          end

          app.put '/api/governance/approvals/:id/reject' do
            require_data!
            body = parse_request_body
            halt 422, json_error('missing_field', 'reviewer_id is required', status_code: 422) unless body[:reviewer_id]

            result = run_governance_runner(:reject,
                                           id:          params[:id].to_i,
                                           reviewer_id: body[:reviewer_id])
            json_response(result)
          end
        end
      end
    end
  end
end
