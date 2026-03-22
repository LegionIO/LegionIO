# frozen_string_literal: true

module Legion
  class API < Sinatra::Base
    module Routes
      module Relationships
        def self.registered(app)
          app.get '/api/relationships' do
            require_data!
            json_collection(Legion::Data::Model::Relationship.order(:id))
          end

          app.post '/api/relationships' do
            Legion::Logging.debug "API: POST /api/relationships params=#{params.keys}"
            require_data!
            body = parse_request_body
            id = Legion::Data::Model::Relationship.insert(body)
            record = Legion::Data::Model::Relationship[id]
            Legion::Logging.info "API: created relationship #{id}"
            json_response(record.values, status_code: 201)
          end

          app.get '/api/relationships/:id' do
            require_data!
            record = find_or_halt(Legion::Data::Model::Relationship, params[:id])
            json_response(record.values)
          end

          app.put '/api/relationships/:id' do
            Legion::Logging.debug "API: PUT /api/relationships/#{params[:id]} params=#{params.keys}"
            require_data!
            record = find_or_halt(Legion::Data::Model::Relationship, params[:id])
            body = parse_request_body
            record.update(body)
            record.refresh
            Legion::Logging.info "API: updated relationship #{params[:id]}"
            json_response(record.values)
          end

          app.delete '/api/relationships/:id' do
            require_data!
            record = find_or_halt(Legion::Data::Model::Relationship, params[:id])
            record.delete
            Legion::Logging.info "API: deleted relationship #{params[:id]}"
            json_response({ deleted: true })
          end
        end
      end
    end
  end
end
