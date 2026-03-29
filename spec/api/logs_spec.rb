# frozen_string_literal: true

require_relative 'api_spec_helper'

RSpec.describe 'Logs API' do
  include Rack::Test::Methods

  def app = Legion::API

  before(:all) { ApiSpecSetup.configure_settings }

  let(:valid_error_payload) do
    {
      level:           'error',
      message:         'something broke',
      exception_class: 'RuntimeError',
      backtrace:       ['cli.rb:42:in `start\''],
      component_type:  'cli',
      source:          'legion',
      command:         'legion chat prompt hello'
    }
  end

  let(:valid_warn_payload) do
    {
      level:   'warn',
      message: 'something suspicious happened',
      source:  'legion'
    }
  end

  before do
    allow(Legion::Transport::Messages::Dynamic).to receive(:new).and_return(double(publish: true))
    allow(Legion::Logging::EventBuilder).to receive(:send).with(:legion_versions).and_return({})
  end

  describe 'POST /api/logs' do
    context 'with a valid error payload' do
      it 'returns 201' do
        post '/api/logs', Legion::JSON.dump(valid_error_payload), 'CONTENT_TYPE' => 'application/json'
        expect(last_response.status).to eq(201)
      end

      it 'returns published: true' do
        post '/api/logs', Legion::JSON.dump(valid_error_payload), 'CONTENT_TYPE' => 'application/json'
        body = Legion::JSON.load(last_response.body)
        expect(body[:data][:published]).to be true
      end

      it 'returns a routing_key in the response' do
        post '/api/logs', Legion::JSON.dump(valid_error_payload), 'CONTENT_TYPE' => 'application/json'
        body = Legion::JSON.load(last_response.body)
        expect(body[:data][:routing_key]).to include('legion.logging.exception.error.cli.legion')
      end
    end

    context 'with a valid warn payload' do
      it 'returns 201' do
        post '/api/logs', Legion::JSON.dump(valid_warn_payload), 'CONTENT_TYPE' => 'application/json'
        expect(last_response.status).to eq(201)
      end

      it 'returns published: true' do
        post '/api/logs', Legion::JSON.dump(valid_warn_payload), 'CONTENT_TYPE' => 'application/json'
        body = Legion::JSON.load(last_response.body)
        expect(body[:data][:published]).to be true
      end

      it 'uses the log routing key (no exception_class)' do
        post '/api/logs', Legion::JSON.dump(valid_warn_payload), 'CONTENT_TYPE' => 'application/json'
        body = Legion::JSON.load(last_response.body)
        expect(body[:data][:routing_key]).to include('legion.logging.log.warn.cli.legion')
      end
    end

    context 'when level is missing' do
      it 'returns 422' do
        post '/api/logs', Legion::JSON.dump({ message: 'oops' }), 'CONTENT_TYPE' => 'application/json'
        expect(last_response.status).to eq(422)
      end

      it 'returns an error message about level' do
        post '/api/logs', Legion::JSON.dump({ message: 'oops' }), 'CONTENT_TYPE' => 'application/json'
        body = Legion::JSON.load(last_response.body)
        expect(body[:error][:message]).to include('level')
      end
    end

    context 'when level is invalid (e.g. "debug")' do
      it 'returns 422' do
        post '/api/logs', Legion::JSON.dump({ level: 'debug', message: 'too noisy' }),
             'CONTENT_TYPE' => 'application/json'
        expect(last_response.status).to eq(422)
      end

      it 'returns an error message about level' do
        post '/api/logs', Legion::JSON.dump({ level: 'debug', message: 'too noisy' }),
             'CONTENT_TYPE' => 'application/json'
        body = Legion::JSON.load(last_response.body)
        expect(body[:error][:message]).to include('level')
      end
    end

    context 'when message is missing' do
      it 'returns 422' do
        post '/api/logs', Legion::JSON.dump({ level: 'error' }), 'CONTENT_TYPE' => 'application/json'
        expect(last_response.status).to eq(422)
      end

      it 'returns an error message about message' do
        post '/api/logs', Legion::JSON.dump({ level: 'error' }), 'CONTENT_TYPE' => 'application/json'
        body = Legion::JSON.load(last_response.body)
        expect(body[:error][:message]).to include('message')
      end
    end

    context 'when message is empty' do
      it 'returns 422' do
        post '/api/logs', Legion::JSON.dump({ level: 'error', message: '   ' }),
             'CONTENT_TYPE' => 'application/json'
        expect(last_response.status).to eq(422)
      end
    end

    context 'routing key construction' do
      it 'uses exception routing key when exception_class is present' do
        post '/api/logs', Legion::JSON.dump(valid_error_payload), 'CONTENT_TYPE' => 'application/json'
        body = Legion::JSON.load(last_response.body)
        expect(body[:data][:routing_key]).to start_with('legion.logging.exception.')
      end

      it 'uses log routing key when exception_class is absent' do
        post '/api/logs', Legion::JSON.dump(valid_warn_payload), 'CONTENT_TYPE' => 'application/json'
        body = Legion::JSON.load(last_response.body)
        expect(body[:data][:routing_key]).to start_with('legion.logging.log.')
      end

      it 'defaults source to "unknown" when not provided' do
        post '/api/logs', Legion::JSON.dump({ level: 'warn', message: 'test' }),
             'CONTENT_TYPE' => 'application/json'
        body = Legion::JSON.load(last_response.body)
        expect(body[:data][:routing_key]).to end_with('.unknown')
      end
    end
  end
end
