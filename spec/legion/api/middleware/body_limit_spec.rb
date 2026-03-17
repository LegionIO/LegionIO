# frozen_string_literal: true

require 'spec_helper'
require 'legion/api/middleware/body_limit'

RSpec.describe Legion::API::Middleware::BodyLimit do
  let(:inner_app) { ->(_env) { [200, { 'Content-Type' => 'application/json' }, ['ok']] } }
  let(:app) { described_class.new(inner_app, max_size: 1024) }

  it 'allows requests within size limit' do
    env = Rack::MockRequest.env_for('/api/test', method: 'POST',
                                                  'CONTENT_LENGTH' => '100')
    status, _headers, _body = app.call(env)
    expect(status).to eq(200)
  end

  it 'rejects requests exceeding size limit' do
    env = Rack::MockRequest.env_for('/api/test', method: 'POST',
                                                  'CONTENT_LENGTH' => '2048')
    status, _headers, body = app.call(env)
    expect(status).to eq(413)
    parsed = Legion::JSON.load(body.first)
    expect(parsed[:error][:code]).to eq('payload_too_large')
  end

  it 'allows requests with no content length' do
    env = Rack::MockRequest.env_for('/api/test', method: 'GET')
    status, _headers, _body = app.call(env)
    expect(status).to eq(200)
  end
end
