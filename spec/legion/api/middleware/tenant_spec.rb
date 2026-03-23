# frozen_string_literal: true

require 'spec_helper'
require 'rack/test'
require 'sinatra/base'
require 'legion/api/middleware/tenant'

RSpec.describe Legion::API::Middleware::Tenant do
  let(:captured_env) { {} }
  let(:inner_app) do
    ce = captured_env
    lambda do |_env|
      ce[:tenant_id] = Legion::TenantContext.current
      [200, { 'content-type' => 'text/plain' }, ['OK']]
    end
  end

  let(:app) { described_class.new(inner_app) }

  before do
    tenant_ctx = Module.new do
      @current = nil

      def self.set(id)
        @current = id
      end

      def self.current # rubocop:disable Style/TrivialAccessors
        @current
      end

      def self.clear
        @current = nil
      end
    end
    stub_const('Legion::TenantContext', tenant_ctx)
  end

  describe 'skip paths' do
    it 'skips /api/health' do
      status, = app.call(Rack::MockRequest.env_for('/api/health'))
      expect(status).to eq(200)
    end

    it 'skips /api/ready' do
      status, = app.call(Rack::MockRequest.env_for('/api/ready'))
      expect(status).to eq(200)
    end

    it 'skips /metrics' do
      status, = app.call(Rack::MockRequest.env_for('/metrics'))
      expect(status).to eq(200)
    end
  end

  describe 'tenant extraction' do
    it 'extracts tenant from X-Tenant-ID header' do
      env = Rack::MockRequest.env_for('/api/tasks', 'HTTP_X_TENANT_ID' => 'tenant-abc')
      app.call(env)
      expect(captured_env[:tenant_id]).to eq('tenant-abc')
    end

    it 'extracts tenant from legion.tenant_id env' do
      env = Rack::MockRequest.env_for('/api/tasks')
      env['legion.tenant_id'] = 'tenant-xyz'
      app.call(env)
      expect(captured_env[:tenant_id]).to eq('tenant-xyz')
    end

    it 'prefers legion.tenant_id over header' do
      env = Rack::MockRequest.env_for('/api/tasks', 'HTTP_X_TENANT_ID' => 'header-tenant')
      env['legion.tenant_id'] = 'env-tenant'
      app.call(env)
      expect(captured_env[:tenant_id]).to eq('env-tenant')
    end

    it 'passes nil when no tenant provided' do
      app.call(Rack::MockRequest.env_for('/api/tasks'))
      expect(captured_env[:tenant_id]).to be_nil
    end
  end

  describe 'context cleanup' do
    it 'clears tenant context after request' do
      env = Rack::MockRequest.env_for('/api/tasks', 'HTTP_X_TENANT_ID' => 'tenant-abc')
      app.call(env)
      expect(Legion::TenantContext.current).to be_nil
    end

    it 'clears context even when inner app raises' do
      error_app = ->(_env) { raise StandardError, 'boom' }
      tenant_app = described_class.new(error_app)
      env = Rack::MockRequest.env_for('/api/tasks', 'HTTP_X_TENANT_ID' => 'tenant-abc')
      expect { tenant_app.call(env) }.to raise_error(StandardError, 'boom')
      expect(Legion::TenantContext.current).to be_nil
    end
  end
end
