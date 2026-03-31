# frozen_string_literal: true

module Legion
  class API < Sinatra::Base
    module Routes
      module Absorbers
        def self.registered(app)
          app.get '/api/absorbers' do
            patterns = Legion::Extensions::Absorbers::PatternMatcher.list
            items = patterns.map do |p|
              {
                type:           p[:type],
                value:          p[:value],
                priority:       p[:priority],
                description:    p[:description],
                absorber_class: p[:absorber_class]&.name
              }
            end
            json_response(items)
          end

          app.post '/api/absorbers/dispatch' do
            body = parse_request_body
            input = body[:url] || body[:input]
            halt 400, json_error('missing_param', 'url parameter is required') unless input

            require 'legion/extensions/actors/absorber_dispatch'
            context = body[:context] || {}
            job_id = SecureRandom.hex(8)

            Thread.new do
              Legion::Extensions::Actors::AbsorberDispatch.dispatch(
                input: input, job_id: job_id, context: context
              )
            rescue StandardError => e
              Legion::Logging.error("Async absorb #{job_id} failed: #{e.message}") if defined?(Legion::Logging)
            end

            json_response({ success: true, job_id: job_id, absorber: PatternMatcher.resolve(input)&.name, status: :accepted })
          end

          app.get '/api/absorbers/resolve' do
            input = params[:url] || params[:input]
            halt 400, json_error('missing_param', 'url parameter is required') unless input

            absorber = Legion::Extensions::Absorbers::PatternMatcher.resolve(input)
            json_response({
                            input:    input,
                            match:    !absorber.nil?,
                            absorber: absorber&.name
                          })
          end
        end
      end
    end
  end
end
