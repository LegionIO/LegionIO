# frozen_string_literal: true

module Legion
  class API < Sinatra::Base
    module Routes
      module Chains
        def self.registered(app) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
          app.get '/api/chains' do
            require_data!
            halt 501, json_error('not_implemented', 'chain data model is not yet available', status_code: 501) unless Legion::Data::Model.const_defined?(:Chain)

            json_collection(Legion::Data::Model::Chain.order(:id))
          end

          app.post '/api/chains' do
            Legion::Logging.debug "API: POST /api/chains params=#{params.keys}"
            require_data!
            unless Legion::Data::Model.const_defined?(:Chain)
              Legion::Logging.warn 'API POST /api/chains returned 501: chain data model is not yet available'
              halt 501, json_error('not_implemented', 'chain data model is not yet available', status_code: 501)
            end

            body = parse_request_body
            unless body[:name]
              Legion::Logging.warn 'API POST /api/chains returned 422: name is required'
              halt 422, json_error('missing_field', 'name is required', status_code: 422)
            end

            id = Legion::Data::Model::Chain.insert(body)
            record = Legion::Data::Model::Chain[id]
            Legion::Logging.info "API: created chain #{id} (#{body[:name]})"
            json_response(record.values, status_code: 201)
          end

          app.get '/api/chains/:id' do
            require_data!
            unless Legion::Data::Model.const_defined?(:Chain)
              Legion::Logging.warn "API GET /api/chains/#{params[:id]} returned 501: chain data model is not yet available"
              halt 501, json_error('not_implemented', 'chain data model is not yet available', status_code: 501)
            end

            record = find_or_halt(Legion::Data::Model::Chain, params[:id])
            json_response(record.values)
          end

          app.put '/api/chains/:id' do
            Legion::Logging.debug "API: PUT /api/chains/#{params[:id]} params=#{params.keys}"
            require_data!
            unless Legion::Data::Model.const_defined?(:Chain)
              Legion::Logging.warn "API PUT /api/chains/#{params[:id]} returned 501: chain data model is not yet available"
              halt 501, json_error('not_implemented', 'chain data model is not yet available', status_code: 501)
            end

            record = find_or_halt(Legion::Data::Model::Chain, params[:id])
            body = parse_request_body
            record.update(body)
            record.refresh
            Legion::Logging.info "API: updated chain #{params[:id]}"
            json_response(record.values)
          end

          app.delete '/api/chains/:id' do
            require_data!
            unless Legion::Data::Model.const_defined?(:Chain)
              Legion::Logging.warn "API DELETE /api/chains/#{params[:id]} returned 501: chain data model is not yet available"
              halt 501, json_error('not_implemented', 'chain data model is not yet available', status_code: 501)
            end

            record = find_or_halt(Legion::Data::Model::Chain, params[:id])
            record.delete
            Legion::Logging.info "API: deleted chain #{params[:id]}"
            json_response({ deleted: true })
          end
        end
      end
    end
  end
end
