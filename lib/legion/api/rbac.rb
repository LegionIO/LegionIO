# frozen_string_literal: true

module Legion
  class API < Sinatra::Base
    module Routes
      module Rbac
        def self.registered(app)
          register_roles(app)
          register_check(app)
          register_assignments(app)
          register_grants(app)
          register_cross_team_grants(app)
        end

        def self.register_roles(app)
          app.get '/api/rbac/roles' do
            return json_error('rbac_unavailable', 'legion-rbac not installed', status_code: 501) unless defined?(Legion::Rbac)

            roles = Legion::Rbac.role_index.transform_values do |role|
              { name: role.name, description: role.description, cross_team: role.cross_team? }
            end
            json_response(roles)
          end

          app.get '/api/rbac/roles/:name' do
            return json_error('rbac_unavailable', 'legion-rbac not installed', status_code: 501) unless defined?(Legion::Rbac)

            role = Legion::Rbac.role_index[params[:name].to_sym]
            halt 404, json_error('not_found', "Role #{params[:name]} not found", status_code: 404) unless role

            json_response({
                            name:        role.name,
                            description: role.description,
                            cross_team:  role.cross_team?,
                            permissions: role.permissions.map { |p| { resource: p.resource_pattern, actions: p.actions } },
                            deny_rules:  role.deny_rules.map { |d| { resource: d.resource_pattern, above_level: d.above_level } }
                          })
          end
        end

        def self.register_check(app)
          app.post '/api/rbac/check' do
            Legion::Logging.debug "API: POST /api/rbac/check params=#{params.keys}"
            return json_error('rbac_unavailable', 'legion-rbac not installed', status_code: 501) unless defined?(Legion::Rbac)

            body = parse_request_body
            principal = Legion::Rbac::Principal.new(
              id:    body[:principal] || 'anonymous',
              roles: body[:roles] || [],
              team:  body[:team]
            )
            result = Legion::Rbac::PolicyEngine.evaluate(
              principal: principal,
              action:    body[:action] || 'read',
              resource:  body[:resource] || '*',
              enforce:   false
            )
            json_response(result)
          rescue StandardError => e
            Legion::Logging.error "API POST /api/rbac/check: #{e.class} — #{e.message}"
            json_error('rbac_error', e.message, status_code: 500)
          end
        end

        def self.register_assignments(app) # rubocop:disable Metrics/AbcSize
          app.get '/api/rbac/assignments' do
            return json_error('rbac_unavailable', 'legion-rbac not installed', status_code: 501) unless defined?(Legion::Rbac)
            return json_error('db_unavailable', 'legion-data not connected', status_code: 503) unless Legion::Rbac::Store.db_available?

            dataset = Legion::Data::Model::RbacRoleAssignment.order(:id)
            dataset = dataset.where(team: params[:team]) if params[:team]
            dataset = dataset.where(role: params[:role]) if params[:role]
            dataset = dataset.where(principal_id: params[:principal]) if params[:principal]
            json_collection(dataset)
          end

          app.post '/api/rbac/assignments' do
            Legion::Logging.debug "API: POST /api/rbac/assignments params=#{params.keys}"
            return json_error('rbac_unavailable', 'legion-rbac not installed', status_code: 501) unless defined?(Legion::Rbac)
            return json_error('db_unavailable', 'legion-data not connected', status_code: 503) unless Legion::Rbac::Store.db_available?

            body = parse_request_body
            record = Legion::Data::Model::RbacRoleAssignment.create(
              principal_type: body[:principal_type] || 'human',
              principal_id:   body[:principal_id],
              role:           body[:role],
              team:           body[:team],
              granted_by:     current_owner_msid || 'api',
              expires_at:     body[:expires_at] ? Time.parse(body[:expires_at]) : nil
            )
            Legion::Logging.info "API: created RBAC assignment #{record.id} role=#{body[:role]} principal=#{body[:principal_id]}"
            json_response(record.values, status_code: 201)
          rescue Sequel::ValidationFailed => e
            Legion::Logging.warn "API POST /api/rbac/assignments returned 422: #{e.message}"
            json_error('validation_error', e.message, status_code: 422)
          end

          app.delete '/api/rbac/assignments/:id' do
            return json_error('rbac_unavailable', 'legion-rbac not installed', status_code: 501) unless defined?(Legion::Rbac)
            return json_error('db_unavailable', 'legion-data not connected', status_code: 503) unless Legion::Rbac::Store.db_available?

            record = Legion::Data::Model::RbacRoleAssignment[params[:id].to_i]
            halt 404, json_error('not_found', 'Assignment not found', status_code: 404) unless record

            record.destroy
            Legion::Logging.info "API: deleted RBAC assignment #{params[:id]}"
            json_response({ deleted: true })
          end
        end

        def self.register_grants(app)
          app.get '/api/rbac/grants' do
            return json_error('rbac_unavailable', 'legion-rbac not installed', status_code: 501) unless defined?(Legion::Rbac)
            return json_error('db_unavailable', 'legion-data not connected', status_code: 503) unless Legion::Rbac::Store.db_available?

            dataset = Legion::Data::Model::RbacRunnerGrant.order(:id)
            dataset = dataset.where(team: params[:team]) if params[:team]
            json_collection(dataset)
          end

          app.post '/api/rbac/grants' do
            Legion::Logging.debug "API: POST /api/rbac/grants params=#{params.keys}"
            return json_error('rbac_unavailable', 'legion-rbac not installed', status_code: 501) unless defined?(Legion::Rbac)
            return json_error('db_unavailable', 'legion-data not connected', status_code: 503) unless Legion::Rbac::Store.db_available?

            body = parse_request_body
            record = Legion::Data::Model::RbacRunnerGrant.create(
              team:           body[:team],
              runner_pattern: body[:runner_pattern],
              actions:        Array(body[:actions]).join(','),
              granted_by:     current_owner_msid || 'api'
            )
            Legion::Logging.info "API: created RBAC grant #{record.id} team=#{body[:team]} pattern=#{body[:runner_pattern]}"
            json_response(record.values, status_code: 201)
          rescue Sequel::ValidationFailed => e
            Legion::Logging.warn "API POST /api/rbac/grants returned 422: #{e.message}"
            json_error('validation_error', e.message, status_code: 422)
          end

          app.delete '/api/rbac/grants/:id' do
            return json_error('rbac_unavailable', 'legion-rbac not installed', status_code: 501) unless defined?(Legion::Rbac)
            return json_error('db_unavailable', 'legion-data not connected', status_code: 503) unless Legion::Rbac::Store.db_available?

            record = Legion::Data::Model::RbacRunnerGrant[params[:id].to_i]
            halt 404, json_error('not_found', 'Grant not found', status_code: 404) unless record

            record.destroy
            Legion::Logging.info "API: deleted RBAC grant #{params[:id]}"
            json_response({ deleted: true })
          end
        end

        def self.register_cross_team_grants(app)
          app.get '/api/rbac/grants/cross-team' do
            return json_error('rbac_unavailable', 'legion-rbac not installed', status_code: 501) unless defined?(Legion::Rbac)
            return json_error('db_unavailable', 'legion-data not connected', status_code: 503) unless Legion::Rbac::Store.db_available?

            dataset = Legion::Data::Model::RbacCrossTeamGrant.order(:id)
            json_collection(dataset)
          end

          app.post '/api/rbac/grants/cross-team' do
            Legion::Logging.debug "API: POST /api/rbac/grants/cross-team params=#{params.keys}"
            return json_error('rbac_unavailable', 'legion-rbac not installed', status_code: 501) unless defined?(Legion::Rbac)
            return json_error('db_unavailable', 'legion-data not connected', status_code: 503) unless Legion::Rbac::Store.db_available?

            body = parse_request_body
            record = Legion::Data::Model::RbacCrossTeamGrant.create(
              source_team:    body[:source_team],
              target_team:    body[:target_team],
              runner_pattern: body[:runner_pattern],
              actions:        Array(body[:actions]).join(','),
              granted_by:     current_owner_msid || 'api',
              expires_at:     body[:expires_at] ? Time.parse(body[:expires_at]) : nil
            )
            Legion::Logging.info "API: created cross-team RBAC grant #{record.id} #{body[:source_team]}->#{body[:target_team]}"
            json_response(record.values, status_code: 201)
          rescue Sequel::ValidationFailed => e
            Legion::Logging.warn "API POST /api/rbac/grants/cross-team returned 422: #{e.message}"
            json_error('validation_error', e.message, status_code: 422)
          end

          app.delete '/api/rbac/grants/cross-team/:id' do
            return json_error('rbac_unavailable', 'legion-rbac not installed', status_code: 501) unless defined?(Legion::Rbac)
            return json_error('db_unavailable', 'legion-data not connected', status_code: 503) unless Legion::Rbac::Store.db_available?

            record = Legion::Data::Model::RbacCrossTeamGrant[params[:id].to_i]
            halt 404, json_error('not_found', 'Grant not found', status_code: 404) unless record

            record.destroy
            Legion::Logging.info "API: deleted cross-team RBAC grant #{params[:id]}"
            json_response({ deleted: true })
          end
        end

        class << self
          private :register_roles, :register_check, :register_assignments, :register_grants, :register_cross_team_grants
        end
      end
    end
  end
end
