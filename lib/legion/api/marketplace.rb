# frozen_string_literal: true

require 'date'
require 'legion/registry'

module Legion
  class API < Sinatra::Base
    module Routes
      module Marketplace
        module Helpers
          def parse_sunset_date(date_str)
            return nil if date_str.nil? || date_str.empty?

            Date.parse(date_str.to_s)
          rescue ArgumentError => e
            Legion::Logging.debug "Marketplace#parse_sunset_date invalid date '#{date_str}': #{e.message}" if defined?(Legion::Logging)
            nil
          end
        end

        def self.registered(app)
          app.helpers Helpers
          register_collection(app)
          register_member(app)
          register_review_actions(app)
          register_stats(app)
        end

        def self.register_collection(app)
          app.get '/api/marketplace' do
            query   = params[:q] || params[:query]
            entries = query ? Legion::Registry.search(query) : Legion::Registry.all
            entries = entries.select { |e| e.status.to_s == params[:status] } if params[:status]
            entries = entries.select { |e| e.risk_tier == params[:tier] }     if params[:tier]

            paginated = entries.slice((page_offset)..(page_offset + page_limit - 1)) || []
            content_type :json
            status 200
            Legion::JSON.dump({
                                data: paginated.map(&:to_h),
                                meta: response_meta.merge(total: entries.size, limit: page_limit, offset: page_offset)
                              })
          end
        end

        def self.register_member(app)
          app.get '/api/marketplace/:name' do
            entry = Legion::Registry.lookup(params[:name])
            unless entry
              halt 404, { 'Content-Type' => 'application/json' },
                   Legion::JSON.dump({ error: { code: 'not_found', message: "Extension #{params[:name]} not found" } })
            end

            json_response(entry.to_h.merge(stats: Legion::Registry.usage_stats(params[:name])))
          end
        end

        def self.register_review_actions(app) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
          app.post '/api/marketplace/:name/submit' do
            begin
              Legion::Registry.submit_for_review(params[:name])
            rescue ArgumentError => e
              Legion::Logging.warn "API POST /api/marketplace/#{params[:name]}/submit: #{e.message}" if defined?(Legion::Logging)
              halt 404, { 'Content-Type' => 'application/json' },
                   Legion::JSON.dump({ error: { code: 'not_found', message: e.message } })
            end
            json_response({ name: params[:name], status: 'pending_review' }, status_code: 202)
          end

          app.post '/api/marketplace/:name/approve' do
            body = parse_request_body
            begin
              Legion::Registry.approve(params[:name], notes: body[:notes])
            rescue ArgumentError => e
              Legion::Logging.warn "API POST /api/marketplace/#{params[:name]}/approve: #{e.message}" if defined?(Legion::Logging)
              halt 404, { 'Content-Type' => 'application/json' },
                   Legion::JSON.dump({ error: { code: 'not_found', message: e.message } })
            end
            entry = Legion::Registry.lookup(params[:name])
            json_response({ name: params[:name], status: 'approved', entry: entry.to_h })
          end

          app.post '/api/marketplace/:name/reject' do
            body = parse_request_body
            begin
              Legion::Registry.reject(params[:name], reason: body[:reason])
            rescue ArgumentError => e
              Legion::Logging.warn "API POST /api/marketplace/#{params[:name]}/reject: #{e.message}" if defined?(Legion::Logging)
              halt 404, { 'Content-Type' => 'application/json' },
                   Legion::JSON.dump({ error: { code: 'not_found', message: e.message } })
            end
            entry = Legion::Registry.lookup(params[:name])
            json_response({ name: params[:name], status: 'rejected', entry: entry.to_h })
          end

          app.post '/api/marketplace/:name/deprecate' do
            body = parse_request_body
            sunset = begin
              body[:sunset_date] ? Date.parse(body[:sunset_date].to_s) : nil
            rescue ArgumentError => e
              Legion::Logging.debug "Marketplace#deprecate invalid sunset_date '#{body[:sunset_date]}': #{e.message}" if defined?(Legion::Logging)
              nil
            end
            begin
              Legion::Registry.deprecate(params[:name], successor: body[:successor], sunset_date: sunset)
            rescue ArgumentError => e
              Legion::Logging.warn "API POST /api/marketplace/#{params[:name]}/deprecate: #{e.message}" if defined?(Legion::Logging)
              halt 404, { 'Content-Type' => 'application/json' },
                   Legion::JSON.dump({ error: { code: 'not_found', message: e.message } })
            end
            entry = Legion::Registry.lookup(params[:name])
            json_response({ name: params[:name], status: 'deprecated', entry: entry.to_h })
          end
        end

        def self.register_stats(app)
          app.get '/api/marketplace/:name/stats' do
            data = Legion::Registry.usage_stats(params[:name])
            unless data
              halt 404, { 'Content-Type' => 'application/json' },
                   Legion::JSON.dump({ error: { code: 'not_found', message: "Extension #{params[:name]} not found" } })
            end

            json_response(data)
          end
        end
      end
    end
  end
end
