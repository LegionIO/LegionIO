# frozen_string_literal: true

return unless defined?(GraphQL)

require_relative 'graphql/schema'

module Legion
  class API < Sinatra::Base
    module Routes
      module GraphQL
        def self.registered(app)
          app.post '/api/graphql' do
            content_type :json
            Legion::Logging.debug "API: POST /api/graphql params=#{params.keys}" if defined?(Legion::Logging)

            body_str = request.body.read
            payload  = body_str.empty? ? {} : Legion::JSON.load(body_str)
            payload  = payload.transform_keys(&:to_sym) if payload.is_a?(Hash)

            query          = payload[:query]
            variables      = payload[:variables] || {}
            operation_name = payload[:operationName]

            if query.nil? || query.strip.empty?
              Legion::Logging.warn 'API POST /api/graphql returned 400: query is required' if defined?(Legion::Logging)
              status 400
              next Legion::JSON.dump({
                                       errors: [{ message: 'query is required' }]
                                     })
            end

            result = Legion::API::GraphQL::Schema.execute(
              query,
              variables:      variables,
              operation_name: operation_name,
              context:        { request: request }
            )

            status 200
            Legion::JSON.dump(result.to_h)
          rescue StandardError => e
            Legion::Logging.error "API POST /api/graphql: #{e.class} — #{e.message}" if defined?(Legion::Logging)
            status 500
            Legion::JSON.dump({ errors: [{ message: e.message }] })
          end

          app.get '/api/graphql' do
            content_type 'text/html'
            Legion::API::Routes::GraphQL.graphiql_html
          end
        end

        def self.graphiql_html
          <<~HTML
            <!DOCTYPE html>
            <html>
              <head>
                <title>LegionIO GraphiQL</title>
                <link href="https://cdn.jsdelivr.net/npm/graphiql@3/graphiql.min.css" rel="stylesheet" />
              </head>
              <body style="margin:0">
                <div id="graphiql" style="height:100vh"></div>
                <script crossorigin src="https://cdn.jsdelivr.net/npm/react@18/umd/react.development.js"></script>
                <script crossorigin src="https://cdn.jsdelivr.net/npm/react-dom@18/umd/react-dom.development.js"></script>
                <script crossorigin src="https://cdn.jsdelivr.net/npm/graphiql@3/graphiql.min.js"></script>
                <script>
                  const root = ReactDOM.createRoot(document.getElementById('graphiql'));
                  root.render(React.createElement(GraphiQL, {
                    fetcher: GraphiQL.createFetcher({ url: '/api/graphql' })
                  }));
                </script>
              </body>
            </html>
          HTML
        end
      end
    end
  end
end
