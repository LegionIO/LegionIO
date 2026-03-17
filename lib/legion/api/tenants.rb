# frozen_string_literal: true

require_relative '../tenants'

module Legion
  class API < Sinatra::Base
    module Routes
      module Tenants
        def self.registered(app)
          app.get '/api/tenants' do
            tenants = Legion::Tenants.list
            json_response(data: tenants)
          end

          app.post '/api/tenants' do
            params = parsed_body
            result = Legion::Tenants.create(
              tenant_id:   params['tenant_id'],
              name:        params['name'],
              max_workers: params['max_workers'] || 10
            )
            status result[:error] ? 409 : 201
            json_response(data: result)
          end

          app.get '/api/tenants/:tenant_id' do
            tenant = Legion::Tenants.find(params[:tenant_id])
            halt 404, json_response(error: 'not_found') unless tenant
            json_response(data: tenant)
          end

          app.post '/api/tenants/:tenant_id/suspend' do
            result = Legion::Tenants.suspend(tenant_id: params[:tenant_id])
            json_response(data: result)
          end

          app.get '/api/tenants/:tenant_id/quota/:resource' do
            result = Legion::Tenants.check_quota(
              tenant_id: params[:tenant_id],
              resource:  params[:resource].to_sym
            )
            json_response(data: result)
          end
        end
      end
    end
  end
end
