# frozen_string_literal: true

module Legion
  class API < Sinatra::Base
    module Routes
      module Chains
        def self.registered(app)
          app.get '/api/chains' do
            require_data!
            halt 501, json_error('not_implemented', 'chain data model is not yet available', status_code: 501) unless Legion::Data::Model.const_defined?(:Chain)

            json_collection(Legion::Data::Model::Chain.order(:id))
          end

          app.post '/api/chains' do
            require_data!
            halt 501, json_error('not_implemented', 'chain data model is not yet available', status_code: 501) unless Legion::Data::Model.const_defined?(:Chain)

            body = parse_request_body
            halt 422, json_error('missing_field', 'name is required', status_code: 422) unless body[:name]

            id = Legion::Data::Model::Chain.insert(body)
            record = Legion::Data::Model::Chain[id]
            json_response(record.values, status_code: 201)
          end

          app.get '/api/chains/:id' do
            require_data!
            halt 501, json_error('not_implemented', 'chain data model is not yet available', status_code: 501) unless Legion::Data::Model.const_defined?(:Chain)

            record = find_or_halt(Legion::Data::Model::Chain, params[:id])
            json_response(record.values)
          end

          app.put '/api/chains/:id' do
            require_data!
            halt 501, json_error('not_implemented', 'chain data model is not yet available', status_code: 501) unless Legion::Data::Model.const_defined?(:Chain)

            record = find_or_halt(Legion::Data::Model::Chain, params[:id])
            body = parse_request_body
            record.update(body)
            record.refresh
            json_response(record.values)
          end

          app.delete '/api/chains/:id' do
            require_data!
            halt 501, json_error('not_implemented', 'chain data model is not yet available', status_code: 501) unless Legion::Data::Model.const_defined?(:Chain)

            record = find_or_halt(Legion::Data::Model::Chain, params[:id])
            record.delete
            json_response({ deleted: true })
          end
        end
      end
    end
  end
end
