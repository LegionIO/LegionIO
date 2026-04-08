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
      app = described_class.new(lambda { |e|
        captured = e
        [200, {}, []]
      })
      app.call(env)
      expect(captured['legion.principal']).to be_a(Legion::Identity::Request)
    end

    it 'sets principal_id from sub' do
      captured = nil
      app = described_class.new(lambda { |e|
        captured = e
        [200, {}, []]
      })
      app.call(env)
      expect(captured['legion.principal'].principal_id).to eq('user-001')
    end

    it 'sets kind to :human for human scope' do
      captured = nil
      app = described_class.new(lambda { |e|
        captured = e
        [200, {}, []]
      })
      app.call(env)
      expect(captured['legion.principal'].kind).to eq(:human)
    end

    it 'sets source from the auth method' do
      captured = nil
      app = described_class.new(lambda { |e|
        captured = e
        [200, {}, []]
      })
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
      app = described_class.new(lambda { |e|
        captured = e
        [200, {}, []]
      })
      app.call(env)
      expect(captured['legion.principal'].kind).to eq(:service)
    end

    it 'falls back to worker_id when sub is nil' do
      captured = nil
      app = described_class.new(lambda { |e|
        captured = e
        [200, {}, []]
      })
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
      app = described_class.new(lambda { |e|
        captured = e
        [200, {}, []]
      })
      app.call(env)
      expect(captured['legion.principal'].kind).to eq(:human)
    end

    it 'sets source to :kerberos' do
      captured = nil
      app = described_class.new(lambda { |e|
        captured = e
        [200, {}, []]
      })
      app.call(env)
      expect(captured['legion.principal'].source).to eq(:kerberos)
    end
  end

  # ─── no auth, auth not required → system principal ───────────────────────────

  describe 'when no auth is present and require_auth is false (default)' do
    let(:env) { env_for('/api/tasks') }

    it 'sets a system principal' do
      captured = nil
      app = described_class.new(lambda { |e|
        captured = e
        [200, {}, []]
      })
      app.call(env)
      expect(captured['legion.principal']).to be_a(Legion::Identity::Request)
    end

    it 'sets principal_id to system:local' do
      captured = nil
      app = described_class.new(lambda { |e|
        captured = e
        [200, {}, []]
      })
      app.call(env)
      expect(captured['legion.principal'].principal_id).to eq('system:local')
    end

    it 'sets kind to :service' do
      captured = nil
      app = described_class.new(lambda { |e|
        captured = e
        [200, {}, []]
      })
      app.call(env)
      expect(captured['legion.principal'].kind).to eq(:service)
    end

    it 'memoizes the system principal across calls' do
      principals = []
      app = described_class.new(lambda { |e|
        principals << e['legion.principal']
        [200, {}, []]
      })
      2.times { app.call(env_for('/api/tasks')) }
      expect(principals[0]).to equal(principals[1])
    end
  end

  # ─── no auth, auth required → nil principal ──────────────────────────────────

  describe 'when no auth is present and require_auth is true' do
    let(:env) { env_for('/api/tasks') }

    it 'sets legion.principal to nil' do
      captured = nil
      app = described_class.new(lambda { |e|
        captured = e
        [200, {}, []]
      }, require_auth: true)
      app.call(env)
      expect(captured['legion.principal']).to be_nil
    end

    it 'still calls the downstream app' do
      called = false
      app = described_class.new(lambda { |_e|
        called = true
        [200, {}, []]
      }, require_auth: true)
      app.call(env)
      expect(called).to be(true)
    end
  end

  # ─── groups vs roles separation (§3.4 prerequisite fix) ─────────────────────

  describe 'groups vs roles separation in build_request' do
    let(:claims_with_both) do
      {
        sub:    'user-001',
        name:   'Alice',
        groups: ['group-oid-abc'],
        roles:  ['app-admin'],
        scope:  'human'
      }
    end

    it 'passes groups from claims[:groups] to Request, not claims[:roles]' do
      captured = nil
      app = described_class.new(lambda { |e|
        captured = e
        [200, {}, []]
      })
      env = env_for('/api/tasks', 'legion.auth' => claims_with_both, 'legion.auth_method' => 'jwt')
      app.call(env)
      expect(captured['legion.principal'].groups).to eq(['group-oid-abc'])
    end

    it 'does not conflate claims[:roles] into groups' do
      captured = nil
      app = described_class.new(lambda { |e|
        captured = e
        [200, {}, []]
      })
      env = env_for('/api/tasks', 'legion.auth' => claims_with_both, 'legion.auth_method' => 'jwt')
      app.call(env)
      expect(captured['legion.principal'].groups).not_to include('app-admin')
    end
  end

  # ─── worker token: worker_id takes precedence over sub ───────────────────────

  describe 'worker token principal_id resolution' do
    let(:worker_token_claims) do
      { sub: 'owner@example.com', worker_id: 'w-007', name: 'Bot', scope: 'worker' }
    end

    it 'uses worker_id as principal_id when both sub and worker_id are present' do
      captured = nil
      app = described_class.new(lambda { |e|
        captured = e
        [200, {}, []]
      })
      env = env_for('/api/tasks', 'legion.auth' => worker_token_claims, 'legion.auth_method' => 'jwt')
      app.call(env)
      expect(captured['legion.principal'].principal_id).to eq('w-007')
    end

    it 'does not use the owner sub as principal_id when worker_id is present' do
      captured = nil
      app = described_class.new(lambda { |e|
        captured = e
        [200, {}, []]
      })
      env = env_for('/api/tasks', 'legion.auth' => worker_token_claims, 'legion.auth_method' => 'jwt')
      app.call(env)
      expect(captured['legion.principal'].principal_id).not_to eq('owner@example.com')
    end
  end

  # ─── RBAC principal bridge (§5.3) ────────────────────────────────────────────

  describe 'RBAC principal bridge' do
    let(:jwt_claims) do
      { sub: 'user-001', name: 'Alice', groups: ['readers'], scope: 'human' }
    end

    context 'when Legion::Rbac::Principal is NOT available' do
      it 'does not set legion.rbac_principal' do
        captured = nil
        app = described_class.new(lambda { |e|
          captured = e
          [200, {}, []]
        })
        env = env_for('/api/tasks', 'legion.auth' => jwt_claims, 'legion.auth_method' => 'jwt')
        app.call(env)
        expect(captured.key?('legion.rbac_principal')).to be(false)
      end
    end

    context 'when Legion::Rbac::Principal is available with enabled?' do
      let(:rbac_principal_double) { double('rbac_principal') }
      let(:principal_class) do
        klass = Class.new
        allow(klass).to receive(:new).and_return(rbac_principal_double)
        klass
      end
      let(:rbac_module) do
        Module.new do
          def self.enabled?
            true
          end
        end
      end

      before do
        stub_const('Legion::Rbac', rbac_module)
        stub_const('Legion::Rbac::Principal', principal_class)
      end

      it 'sets legion.rbac_principal on the env' do
        captured = nil
        app = described_class.new(lambda { |e|
          captured = e
          [200, {}, []]
        })
        env = env_for('/api/tasks', 'legion.auth' => jwt_claims, 'legion.auth_method' => 'jwt')
        app.call(env)
        expect(captured['legion.rbac_principal']).to eq(rbac_principal_double)
      end

      it 'passes the principal_id to Legion::Rbac::Principal' do
        captured = nil
        app = described_class.new(lambda { |e|
          captured = e
          [200, {}, []]
        })
        env = env_for('/api/tasks', 'legion.auth' => jwt_claims, 'legion.auth_method' => 'jwt')
        app.call(env)
        expect(principal_class).to have_received(:new).with(hash_including(id: 'user-001'))
      end

      it 'maps :service kind to :worker type in the RBAC principal' do
        service_claims = { sub: 'svc-1', name: 'Bot', scope: 'worker', worker_id: 'svc-1' }
        captured = nil
        app = described_class.new(lambda { |e|
          captured = e
          [200, {}, []]
        })
        env = env_for('/api/tasks', 'legion.auth' => service_claims, 'legion.auth_method' => 'jwt')
        app.call(env)
        expect(principal_class).to have_received(:new).with(hash_including(type: :worker))
      end

      it 'passes resolved roles (from claims[:roles]) to the RBAC principal' do
        claims_with_roles = jwt_claims.merge(roles: ['admin'])
        captured = nil
        app = described_class.new(lambda { |e|
          captured = e
          [200, {}, []]
        })
        env = env_for('/api/tasks', 'legion.auth' => claims_with_roles, 'legion.auth_method' => 'jwt')
        app.call(env)
        expect(principal_class).to have_received(:new).with(hash_including(roles: ['admin']))
      end
    end

    context 'when request is nil (require_auth=true, no auth)' do
      it 'does not set legion.rbac_principal' do
        captured = nil
        app = described_class.new(lambda { |e|
          captured = e
          [200, {}, []]
        }, require_auth: true)
        app.call(env_for('/api/tasks'))
        expect(captured.key?('legion.rbac_principal')).to be(false)
      end
    end
  end

  # ─── GroupRoleMapper enrichment (§5.2) ───────────────────────────────────────

  describe 'GroupRoleMapper enrichment in build_request' do
    let(:claims_with_groups) do
      {
        sub:    'user-001',
        name:   'Alice',
        groups: %w[group-a group-b],
        roles:  ['existing-role'],
        scope:  'human'
      }
    end

    context 'when GroupRoleMapper is available and RBAC is enabled' do
      let(:rbac_module) do
        Module.new do
          def self.enabled?
            true
          end
        end
      end

      let(:mapper_module) do
        Module.new do
          def self.resolve_roles(groups:, **)
            groups.include?('group-a') ? ['mapped-admin'] : []
          end
        end
      end

      before do
        stub_const('Legion::Rbac', rbac_module)
        stub_const('Legion::Rbac::GroupRoleMapper', mapper_module)
      end

      it 'merges group-derived roles with existing roles' do
        captured = nil
        app = described_class.new(lambda { |e|
          captured = e
          [200, {}, []]
        })
        env = env_for('/api/tasks', 'legion.auth' => claims_with_groups, 'legion.auth_method' => 'jwt')
        app.call(env)
        expect(captured['legion.principal'].roles).to include('existing-role', 'mapped-admin')
      end

      it 'deduplicates roles' do
        dup_claims = claims_with_groups.merge(roles: ['mapped-admin'])
        captured = nil
        app = described_class.new(lambda { |e|
          captured = e
          [200, {}, []]
        })
        env = env_for('/api/tasks', 'legion.auth' => dup_claims, 'legion.auth_method' => 'jwt')
        app.call(env)
        expect(captured['legion.principal'].roles.count('mapped-admin')).to eq(1)
      end
    end

    context 'when RBAC is disabled (no enabled? method)' do
      it 'passes claims[:roles] through as resolved_roles without enrichment' do
        stub_const('Legion::Rbac', Module.new)
        captured = nil
        app = described_class.new(lambda { |e|
          captured = e
          [200, {}, []]
        })
        env = env_for('/api/tasks', 'legion.auth' => claims_with_groups, 'legion.auth_method' => 'jwt')
        app.call(env)
        expect(captured['legion.principal'].roles).to eq(['existing-role'])
      end
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
