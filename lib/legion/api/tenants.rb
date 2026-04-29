# frozen_string_literal: true

require_relative '../tenants'

module Legion
  class API < Sinatra::Base
    module Routes
      module Tenants
        def self.registered(app)
          app.get '/api/tenants' do
            tenants = Legion::Tenants.list
            json_response(tenants)
          end

          app.post '/api/tenants' do
            body = parse_request_body
            result = Legion::Tenants.create(
              tenant_id:   body[:tenant_id],
              name:        body[:name],
              max_workers: body[:max_workers] || 10
            )
            json_response(result, status_code: result[:error] ? 409 : 201)
          end

          app.get '/api/tenants/:tenant_id' do
            tenant = Legion::Tenants.find(params[:tenant_id])
            halt 404, json_error('not_found', 'Tenant not found', status_code: 404) unless tenant
            json_response(tenant)
          end

          app.post '/api/tenants/:tenant_id/suspend' do
            result = Legion::Tenants.suspend(tenant_id: params[:tenant_id])
            json_response(result)
          end

          app.get '/api/tenants/:tenant_id/quota/:resource' do
            result = Legion::Tenants.check_quota(
              tenant_id: params[:tenant_id],
              resource:  params[:resource].to_sym
            )
            json_response(result)
          end
        end
      end
    end
  end
end
