# frozen_string_literal: true

module Legion
  class API < Sinatra::Base
    module Routes
      module Coldstart
        def self.registered(app)
          app.post '/api/coldstart/ingest' do
            Legion::Logging.debug "API: POST /api/coldstart/ingest params=#{params.keys}"
            body = parse_request_body
            path = body[:path]
            if path.nil? || path.empty?
              Legion::Logging.warn 'API POST /api/coldstart/ingest returned 422: path is required'
              halt 422, json_error('missing_field', 'path is required', status_code: 422)
            end

            unless defined?(Legion::Extensions::Coldstart)
              Legion::Logging.warn 'API POST /api/coldstart/ingest returned 503: lex-coldstart is not loaded'
              halt 503, json_error('coldstart_unavailable', 'lex-coldstart is not loaded', status_code: 503)
            end

            unless defined?(Legion::Extensions::Memory)
              Legion::Logging.warn 'API POST /api/coldstart/ingest returned 503: lex-memory is not loaded'
              halt 503, json_error('memory_unavailable', 'lex-memory is not loaded', status_code: 503)
            end

            runner = Object.new.extend(Legion::Extensions::Coldstart::Runners::Ingest)

            result = if File.file?(path)
                       runner.ingest_file(file_path: File.expand_path(path))
                     elsif File.directory?(path)
                       runner.ingest_directory(
                         dir_path: File.expand_path(path),
                         pattern:  body[:pattern] || '**/{CLAUDE,MEMORY}.md'
                       )
                     else
                       Legion::Logging.warn "API POST /api/coldstart/ingest returned 404: path not found: #{path}"
                       halt 404, json_error('path_not_found', "path not found: #{path}", status_code: 404)
                     end

            Legion::Logging.info "API: coldstart ingest completed for path=#{path}"
            json_response(result, status_code: 201)
          rescue StandardError => e
            Legion::Logging.error "API POST /api/coldstart/ingest: #{e.class} — #{e.message}"
            json_error('execution_error', e.message, status_code: 500)
          end
        end
      end
    end
  end
end
