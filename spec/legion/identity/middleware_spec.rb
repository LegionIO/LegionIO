# frozen_string_literal: true

require 'spec_helper'
require 'legion/identity/request'
require 'legion/identity/middleware'

RSpec.describe Legion::Identity::Middleware do
  let(:inner_app)  { ->(_env) { [200, {}, ['ok']] } }
  let(:middleware) { described_class.new(inner_app) }

  def env_for(path, extra = {})
    { 'PATH_INFO' => path }.merge(extra)
  end

  # ─── skip paths ─────────────────────────────────────────────────────────────

  describe 'skip paths' do
    described_class::SKIP_PATHS.each do |path|
      it "returns the app response directly for #{path}" do
        allow(inner_app).to receive(:call).and_call_original
        middleware.call(env_for(path))
        expect(inner_app).to have_received(:call) do |received_env|
          expect(received_env.key?('legion.principal')).to be(false)
        end
      end
    end

    it 'skips paths that start with a skip prefix' do
      env = env_for('/api/health/detail')
      allow(inner_app).to receive(:call).and_call_original
      middleware.call(env)
      expect(inner_app).to have_received(:call) do |received_env|
        expect(received_env.key?('legion.principal')).to be(false)
      end
    end
  end

  # ─── bridge legion.auth to legion.principal ──────────────────────────────────

  describe 'when legion.auth is present' do
    let(:jwt_claims) do
      { sub: 'user-001', name: 'Alice Smith', groups: ['readers'], scope: 'human' }
    end

    let(:env) { env_for('/api/tasks', 'legion.auth' => jwt_claims, 'legion.auth_method' => 'jwt') }

    it 'sets legion.principal on the downstream env' do
      captured = nil
      app = described_class.new(->(e) { captured = e; [200, {}, []] })
      app.call(env)
      expect(captured['legion.principal']).to be_a(Legion::Identity::Request)
    end

    it 'sets principal_id from sub' do
      captured = nil
      app = described_class.new(->(e) { captured = e; [200, {}, []] })
      app.call(env)
      expect(captured['legion.principal'].principal_id).to eq('user-001')
    end

    it 'sets kind to :human for human scope' do
      captured = nil
      app = described_class.new(->(e) { captured = e; [200, {}, []] })
      app.call(env)
      expect(captured['legion.principal'].kind).to eq(:human)
    end

    it 'sets source from the auth method' do
      captured = nil
      app = described_class.new(->(e) { captured = e; [200, {}, []] })
      app.call(env)
      expect(captured['legion.principal'].source).to eq(:jwt)
    end
  end

  # ─── worker scope → :service kind ────────────────────────────────────────────

  describe 'when auth claims indicate a worker' do
    let(:worker_claims) { { sub: nil, worker_id: 'w-99', name: 'Bot', scope: 'worker' } }
    let(:env) { env_for('/api/tasks', 'legion.auth' => worker_claims, 'legion.auth_method' => 'api_key') }

    it 'sets kind to :service' do
      captured = nil
      app = described_class.new(->(e) { captured = e; [200, {}, []] })
      app.call(env)
      expect(captured['legion.principal'].kind).to eq(:service)
    end

    it 'falls back to worker_id when sub is nil' do
      captured = nil
      app = described_class.new(->(e) { captured = e; [200, {}, []] })
      app.call(env)
      expect(captured['legion.principal'].principal_id).to eq('w-99')
    end
  end

  # ─── kerberos auth → :human kind ─────────────────────────────────────────────

  describe 'when auth method is kerberos' do
    let(:krb_claims) { { sub: 'jdoe@EXAMPLE.COM', name: 'John Doe', groups: [] } }
    let(:env) { env_for('/api/tasks', 'legion.auth' => krb_claims, 'legion.auth_method' => 'kerberos') }

    it 'sets kind to :human' do
      captured = nil
      app = described_class.new(->(e) { captured = e; [200, {}, []] })
      app.call(env)
      expect(captured['legion.principal'].kind).to eq(:human)
    end

    it 'sets source to :kerberos' do
      captured = nil
      app = described_class.new(->(e) { captured = e; [200, {}, []] })
      app.call(env)
      expect(captured['legion.principal'].source).to eq(:kerberos)
    end
  end

  # ─── no auth, auth not required → system principal ───────────────────────────

  describe 'when no auth is present and require_auth is false (default)' do
    let(:env) { env_for('/api/tasks') }

    it 'sets a system principal' do
      captured = nil
      app = described_class.new(->(e) { captured = e; [200, {}, []] })
      app.call(env)
      expect(captured['legion.principal']).to be_a(Legion::Identity::Request)
    end

    it 'sets principal_id to system:local' do
      captured = nil
      app = described_class.new(->(e) { captured = e; [200, {}, []] })
      app.call(env)
      expect(captured['legion.principal'].principal_id).to eq('system:local')
    end

    it 'sets kind to :service' do
      captured = nil
      app = described_class.new(->(e) { captured = e; [200, {}, []] })
      app.call(env)
      expect(captured['legion.principal'].kind).to eq(:service)
    end

    it 'memoizes the system principal across calls' do
      principals = []
      app = described_class.new(->(e) { principals << e['legion.principal']; [200, {}, []] })
      2.times { app.call(env_for('/api/tasks')) }
      expect(principals[0]).to equal(principals[1])
    end
  end

  # ─── no auth, auth required → nil principal ──────────────────────────────────

  describe 'when no auth is present and require_auth is true' do
    let(:env) { env_for('/api/tasks') }

    it 'sets legion.principal to nil' do
      captured = nil
      app = described_class.new(->(e) { captured = e; [200, {}, []] }, require_auth: true)
      app.call(env)
      expect(captured['legion.principal']).to be_nil
    end

    it 'still calls the downstream app' do
      called = false
      app = described_class.new(->(_e) { called = true; [200, {}, []] }, require_auth: true)
      app.call(env)
      expect(called).to be(true)
    end
  end

  # ─── .require_auth? class method ─────────────────────────────────────────────

  describe '.require_auth?' do
    context 'when mode is :lite' do
      it 'returns false for a non-loopback bind' do
        expect(described_class.require_auth?(bind: '0.0.0.0', mode: :lite)).to be(false)
      end

      it 'returns false for a loopback bind' do
        expect(described_class.require_auth?(bind: '127.0.0.1', mode: :lite)).to be(false)
      end
    end

    context 'when mode is :agent' do
      described_class::LOOPBACK_BINDS.each do |loopback|
        it "returns false for loopback bind #{loopback}" do
          expect(described_class.require_auth?(bind: loopback, mode: :agent)).to be(false)
        end
      end

      it 'returns true for a non-loopback bind' do
        expect(described_class.require_auth?(bind: '10.0.0.5', mode: :agent)).to be(true)
      end

      it 'returns true for 0.0.0.0 (public bind)' do
        expect(described_class.require_auth?(bind: '0.0.0.0', mode: :agent)).to be(true)
      end
    end

    context 'when mode is :worker' do
      it 'returns false for localhost' do
        expect(described_class.require_auth?(bind: 'localhost', mode: :worker)).to be(false)
      end

      it 'returns true for a routable IP' do
        expect(described_class.require_auth?(bind: '192.168.1.10', mode: :worker)).to be(true)
      end
    end

    context 'when mode is :infra' do
      it 'returns false for ::1' do
        expect(described_class.require_auth?(bind: '::1', mode: :infra)).to be(false)
      end

      it 'returns true for a routable IP' do
        expect(described_class.require_auth?(bind: '172.16.0.1', mode: :infra)).to be(true)
      end
    end
  end
end
