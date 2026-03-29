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
