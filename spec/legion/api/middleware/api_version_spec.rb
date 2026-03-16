# frozen_string_literal: true

require 'spec_helper'
require 'legion/api/middleware/api_version'

RSpec.describe Legion::API::Middleware::ApiVersion do
  let(:inner_app) { ->(_env) { [200, { 'Content-Type' => 'application/json' }, ['ok']] } }
  let(:app) { described_class.new(inner_app) }

  it 'rewrites /api/v1/ to /api/' do
    env = Rack::MockRequest.env_for('/api/v1/workers')
    status, _headers, _body = app.call(env)
    expect(env['PATH_INFO']).to eq('/api/workers')
    expect(status).to eq(200)
  end

  it 'adds deprecation header to unversioned paths' do
    env = Rack::MockRequest.env_for('/api/workers')
    _status, headers, _body = app.call(env)
    expect(headers['Deprecation']).to eq('true')
    expect(headers['Link']).to include('/api/v1/workers')
  end

  it 'does not add headers to skip paths' do
    env = Rack::MockRequest.env_for('/api/health')
    _status, headers, _body = app.call(env)
    expect(headers).not_to have_key('Deprecation')
  end

  it 'sets X-API-Version header for versioned paths' do
    env = Rack::MockRequest.env_for('/api/v1/tasks')
    app.call(env)
    expect(env['HTTP_X_API_VERSION']).to eq('1')
  end

  it 'includes Sunset header on deprecated paths' do
    env = Rack::MockRequest.env_for('/api/tasks')
    _status, headers, _body = app.call(env)
    expect(headers).to have_key('Sunset')
  end
end
