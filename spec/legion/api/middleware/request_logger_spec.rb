# frozen_string_literal: true

require 'spec_helper'
require 'rack/test'
require 'sinatra/base'
require 'legion/api/middleware/request_logger'

RSpec.describe Legion::API::Middleware::RequestLogger do
  let(:inner_app) do
    ->(_env) { [200, { 'content-type' => 'text/plain' }, ['OK']] }
  end

  let(:app) { described_class.new(inner_app) }

  it 'passes request through and returns response' do
    status, _, body = app.call(Rack::MockRequest.env_for('/api/tasks'))
    expect(status).to eq(200)
    expect(body).to eq(['OK'])
  end

  it 'logs request with method, path, status, and duration' do
    expect(Legion::Logging).to receive(:info).with(%r{\[api\]\[request-start\] GET /api/tasks}).ordered
    expect(Legion::Logging).to receive(:info).with(%r{\[api\] GET /api/tasks 200 \d+(\.\d+)?ms}).ordered
    app.call(Rack::MockRequest.env_for('/api/tasks'))
  end

  it 'logs error and re-raises on failure' do
    error_app = ->(_env) { raise StandardError, 'boom' }
    logger_app = described_class.new(error_app)

    expect(Legion::Logging).to receive(:error).with(%r{\[api\] GET /api/tasks 500.*boom})
    expect { logger_app.call(Rack::MockRequest.env_for('/api/tasks')) }.to raise_error(StandardError, 'boom')
  end

  it 'reports duration in milliseconds' do
    allow(Legion::Logging).to receive(:info)
    app.call(Rack::MockRequest.env_for('/api/tasks'))
    expect(Legion::Logging).to have_received(:info).with(/\d+\.\d+ms/)
  end
end
