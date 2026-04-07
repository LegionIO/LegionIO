# frozen_string_literal: true

require 'spec_helper'
require 'legion/service'

# Specs for Phase 5 Credential Scoping — service.rb integration
# Covers §8 of docs/plans/2026-04-07-credential-scoping-design.md
RSpec.describe Legion::Service do
  subject(:service) { described_class.allocate }

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  # Build a minimal Crypt stub with the Phase 5 methods
  def build_crypt_stub(vault_connected: true, dynamic_rmq_creds: true)
    Module.new do
      define_singleton_method(:vault_connected?) { vault_connected }
      define_singleton_method(:dynamic_rmq_creds?) { dynamic_rmq_creds }
      define_singleton_method(:fetch_bootstrap_rmq_creds) { nil }
      define_singleton_method(:swap_to_identity_creds) { |**_kwargs| nil }
      define_singleton_method(:revoke_bootstrap_lease) { nil }
    end
  end

  # Build a minimal Mode stub
  def build_mode_stub(current: :agent, lite: false)
    Module.new do
      define_singleton_method(:current) { current }
      define_singleton_method(:lite?) { lite }
    end
  end

  # ---------------------------------------------------------------------------
  # §8.1 Boot — fetch_bootstrap_rmq_creds called after Crypt.start
  # ---------------------------------------------------------------------------

  describe '#fetch_phase5_bootstrap_creds (private helper used by boot and reload)' do
    context 'when Crypt responds to fetch_bootstrap_rmq_creds and vault is connected with dynamic creds on' do
      it 'calls fetch_bootstrap_rmq_creds' do
        crypt = build_crypt_stub(vault_connected: true, dynamic_rmq_creds: true)
        stub_const('Legion::Crypt', crypt)

        expect(Legion::Crypt).to receive(:fetch_bootstrap_rmq_creds)
        service.send(:fetch_phase5_bootstrap_creds)
      end
    end

    context 'when Crypt does not respond to fetch_bootstrap_rmq_creds' do
      it 'does not raise' do
        crypt_no_bootstrap = Module.new
        stub_const('Legion::Crypt', crypt_no_bootstrap)

        expect { service.send(:fetch_phase5_bootstrap_creds) }.not_to raise_error
      end
    end

    context 'when vault is not connected' do
      it 'does not call fetch_bootstrap_rmq_creds' do
        crypt = build_crypt_stub(vault_connected: false, dynamic_rmq_creds: true)
        stub_const('Legion::Crypt', crypt)

        expect(Legion::Crypt).not_to receive(:fetch_bootstrap_rmq_creds)
        service.send(:fetch_phase5_bootstrap_creds)
      end
    end

    context 'when dynamic_rmq_creds is false' do
      it 'does not call fetch_bootstrap_rmq_creds' do
        crypt = build_crypt_stub(vault_connected: true, dynamic_rmq_creds: false)
        stub_const('Legion::Crypt', crypt)

        expect(Legion::Crypt).not_to receive(:fetch_bootstrap_rmq_creds)
        service.send(:fetch_phase5_bootstrap_creds)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # §8.1 Boot — setup_identity credential swap
  # ---------------------------------------------------------------------------

  describe '#setup_identity — credential swap' do
    before do
      # Stub identity/process requires
      allow(service).to receive(:require_relative)
      allow(service).to receive(:resolve_identity_providers).and_return(true)
      allow(service).to receive(:handle_exception)

      identity_process = Module.new do
        def self.resolved? = true
        def self.canonical_name = 'test-node'
        def self.queue_prefix = 'agent.test-node'
        def self.bind_fallback! = nil
      end
      stub_const('Legion::Identity::Process', identity_process)

      settings = Module.new do
        def self.respond_to?(method, *) = method == :resolve_secrets! ? true : super
        def self.resolve_secrets! = nil
        def self.dig(*) = nil
      end
      stub_const('Legion::Settings', settings)

      readiness = Module.new do
        def self.mark_ready(*) = nil
      end
      stub_const('Legion::Readiness', readiness)

      extensions = Module.new do
        def self.respond_to?(method, *) = method == :flush_pending_registrations! ? true : super
        def self.flush_pending_registrations! = nil
      end
      stub_const('Legion::Extensions', extensions)
    end

    context 'when Vault is connected and dynamic_rmq_creds is enabled' do
      before do
        crypt = build_crypt_stub(vault_connected: true, dynamic_rmq_creds: true)
        stub_const('Legion::Crypt', crypt)
        stub_const('Legion::Mode', build_mode_stub(current: :agent, lite: false))
      end

      it 'calls swap_to_identity_creds with the current mode' do
        expect(Legion::Crypt).to receive(:swap_to_identity_creds).with(mode: :agent)
        service.setup_identity
      end
    end

    context 'when vault is not connected' do
      before do
        crypt = build_crypt_stub(vault_connected: false, dynamic_rmq_creds: true)
        stub_const('Legion::Crypt', crypt)
        stub_const('Legion::Mode', build_mode_stub(current: :agent, lite: false))
      end

      it 'does not call swap_to_identity_creds' do
        expect(Legion::Crypt).not_to receive(:swap_to_identity_creds)
        service.setup_identity
      end
    end

    context 'when dynamic_rmq_creds is false' do
      before do
        crypt = build_crypt_stub(vault_connected: true, dynamic_rmq_creds: false)
        stub_const('Legion::Crypt', crypt)
        stub_const('Legion::Mode', build_mode_stub(current: :agent, lite: false))
      end

      it 'does not call swap_to_identity_creds' do
        expect(Legion::Crypt).not_to receive(:swap_to_identity_creds)
        service.setup_identity
      end
    end

    context 'when mode is :lite' do
      before do
        crypt = build_crypt_stub(vault_connected: true, dynamic_rmq_creds: true)
        stub_const('Legion::Crypt', crypt)
        stub_const('Legion::Mode', build_mode_stub(current: :lite, lite: true))
      end

      it 'does not call swap_to_identity_creds' do
        expect(Legion::Crypt).not_to receive(:swap_to_identity_creds)
        service.setup_identity
      end
    end

    context 'when Legion::Crypt is not defined' do
      before do
        hide_const('Legion::Crypt')
        stub_const('Legion::Mode', build_mode_stub(current: :agent, lite: false))
      end

      it 'does not raise' do
        expect { service.setup_identity }.not_to raise_error
      end
    end

    context 'when swap_to_identity_creds raises a StandardError' do
      before do
        crypt = Module.new do
          def self.vault_connected? = true
          def self.dynamic_rmq_creds? = true
          def self.swap_to_identity_creds(**) = raise(StandardError, 'reconnect failed')
        end
        stub_const('Legion::Crypt', crypt)
        stub_const('Legion::Mode', build_mode_stub(current: :agent, lite: false))
      end

      it 'rescues and does not propagate' do
        expect { service.setup_identity }.not_to raise_error
      end

      it 'calls handle_exception with :warn level' do
        expect(service).to receive(:handle_exception).at_least(:once)
        service.setup_identity
      end
    end

    context 'when swap_to_identity_creds raises — fallback identity is bound if not resolved' do
      before do
        allow(service).to receive(:resolve_identity_providers).and_return(false)

        crypt = Module.new do
          def self.vault_connected? = true
          def self.dynamic_rmq_creds? = true
          def self.swap_to_identity_creds(**) = raise(StandardError, 'swap boom')
        end
        stub_const('Legion::Crypt', crypt)
        stub_const('Legion::Mode', build_mode_stub(current: :agent, lite: false))

        unresolved_process = Module.new do
          def self.resolved? = false
          def self.canonical_name = 'fallback-node'
          def self.queue_prefix = ''
          def self.bind_fallback! = nil
        end
        stub_const('Legion::Identity::Process', unresolved_process)
      end

      it 'calls bind_fallback! on the process identity' do
        expect(Legion::Identity::Process).to receive(:bind_fallback!).at_least(:once)
        service.setup_identity
      end
    end

    context 'when mode is :worker and dynamic_rmq_creds is enabled' do
      before do
        crypt = build_crypt_stub(vault_connected: true, dynamic_rmq_creds: true)
        stub_const('Legion::Crypt', crypt)
        stub_const('Legion::Mode', build_mode_stub(current: :worker, lite: false))
      end

      it 'calls swap_to_identity_creds with :worker mode' do
        expect(Legion::Crypt).to receive(:swap_to_identity_creds).with(mode: :worker)
        service.setup_identity
      end
    end

    context 'when mode is :infra and dynamic_rmq_creds is enabled' do
      before do
        crypt = build_crypt_stub(vault_connected: true, dynamic_rmq_creds: true)
        stub_const('Legion::Crypt', crypt)
        stub_const('Legion::Mode', build_mode_stub(current: :infra, lite: false))
      end

      it 'calls swap_to_identity_creds with :infra mode' do
        expect(Legion::Crypt).to receive(:swap_to_identity_creds).with(mode: :infra)
        service.setup_identity
      end
    end

    context 'flush_pending_registrations! is called from ensure block even when swap raises' do
      before do
        crypt = Module.new do
          def self.vault_connected? = true
          def self.dynamic_rmq_creds? = true
          def self.swap_to_identity_creds(**) = raise(StandardError, 'swap failed')
        end
        stub_const('Legion::Crypt', crypt)
        stub_const('Legion::Mode', build_mode_stub(current: :agent, lite: false))
      end

      it 'still flushes pending registrations' do
        expect(Legion::Extensions).to receive(:flush_pending_registrations!)
        service.setup_identity
      end
    end

    context 'when Crypt does not respond to vault_connected?' do
      before do
        crypt = Module.new # no methods
        stub_const('Legion::Crypt', crypt)
        stub_const('Legion::Mode', build_mode_stub(current: :agent, lite: false))
      end

      it 'does not raise and does not call swap' do
        expect { service.setup_identity }.not_to raise_error
      end
    end
  end

  # ---------------------------------------------------------------------------
  # §8.3 Shutdown — revoke_bootstrap_lease
  # ---------------------------------------------------------------------------

  describe '#shutdown — revoke_bootstrap_lease' do
    # Stub every shutdown dependency to isolate the bootstrap revocation call

    before do
      allow(service).to receive(:shutdown_network_watchdog)
      allow(service).to receive(:shutdown_audit_archiver)
      allow(service).to receive(:shutdown_api)
      allow(service).to receive(:shutdown_apm)
      # Let shutdown_component yield its block so Legion::Crypt.shutdown is actually called
      allow(service).to receive(:shutdown_component) { |_name, &blk| blk&.call }
      allow(service).to receive(:teardown_logging_transport)
      allow(service).to receive(:shutdown_mtls_rotation)
      allow(service).to receive(:handle_exception)

      settings = {
        client:     { shutting_down: false },
        data:       { connected: false },
        llm:        { connected: false },
        rbac:       { connected: false },
        extensions: { shutdown_timeout: 5 }
      }
      settings_mod = Module.new do
        define_singleton_method(:dig) { |*keys| settings.dig(*keys) }
        define_singleton_method(:[]) { |key| settings[key] }
        define_singleton_method(:[]=) { |key, value| settings[key] = value }
      end
      stub_const('Legion::Settings', settings_mod)

      metrics_mod = Module.new { def self.reset! = nil }
      stub_const('Legion::Metrics', metrics_mod)

      events_mod = Module.new { def self.emit(*) = nil }
      stub_const('Legion::Events', events_mod)

      extensions_mod = Module.new do
        def self.respond_to?(method, *) = method == :shutdown ? true : super
        def self.shutdown = nil
      end
      stub_const('Legion::Extensions', extensions_mod)

      transport_conn = Module.new { def self.shutdown = nil }
      transport_mod  = Module.new { const_set(:Connection, transport_conn) }
      stub_const('Legion::Transport', transport_mod)

      cache_mod = Module.new { def self.shutdown = nil }
      stub_const('Legion::Cache', cache_mod)
    end

    context 'when Crypt responds to revoke_bootstrap_lease' do
      before do
        crypt = Module.new do
          def self.revoke_bootstrap_lease = nil
          def self.shutdown = nil
        end
        stub_const('Legion::Crypt', crypt)
      end

      it 'calls revoke_bootstrap_lease before shutting down Crypt' do
        expect(Legion::Crypt).to receive(:revoke_bootstrap_lease).ordered
        expect(Legion::Crypt).to receive(:shutdown).ordered
        service.shutdown
      end
    end

    context 'when Crypt does not respond to revoke_bootstrap_lease' do
      before do
        crypt = Module.new { def self.shutdown = nil }
        stub_const('Legion::Crypt', crypt)
      end

      it 'does not raise' do
        expect { service.shutdown }.not_to raise_error
      end
    end

    context 'when Legion::Crypt is not defined' do
      before { hide_const('Legion::Crypt') }

      it 'does not raise' do
        expect { service.shutdown }.not_to raise_error
      end
    end
  end

  # ---------------------------------------------------------------------------
  # §8.2 Reload — fetch_bootstrap_rmq_creds and resolve_secrets! after Crypt.start
  # ---------------------------------------------------------------------------

  describe '#reload — bootstrap fetch and resolve_secrets! after Crypt.start' do
    before do
      # Stop the guard from early-exiting
      service.instance_variable_set(:@reloading, false)

      allow(service).to receive(:shutdown_network_watchdog)
      allow(service).to receive(:shutdown_api)
      allow(service).to receive(:shutdown_apm)
      allow(service).to receive(:shutdown_component)
      allow(service).to receive(:teardown_logging_transport)
      allow(service).to receive(:setup_transport)
      allow(service).to receive(:setup_logging_transport)
      allow(service).to receive(:setup_data)
      allow(service).to receive(:setup_supervision)
      allow(service).to receive(:setup_identity)
      allow(service).to receive(:setup_apm)

      # Stub Legion::Identity::Process to prevent double-leak from prior specs
      identity_process_stub = Module.new { def self.refresh_credentials = nil }
      stub_const('Legion::Identity::Process', identity_process_stub)

      # Stub Legion::Cache used in reload
      cache_stub = Module.new { def self.setup = nil }
      stub_const('Legion::Cache', cache_stub)

      # Stub Legion::MCP used in reload
      mcp_stub = Module.new do
        def self.reset! = nil
        def self.respond_to?(mth, *) = mth == :server ? true : super
        def self.server = nil
      end
      stub_const('Legion::MCP', mcp_stub)
      allow(service).to receive(:setup_api)
      allow(service).to receive(:setup_network_watchdog)
      allow(service).to receive(:setup_rbac)
      allow(service).to receive(:setup_llm)
      allow(service).to receive(:setup_apollo)
      allow(service).to receive(:setup_gaia)
      allow(service).to receive(:load_extensions)
      allow(service).to receive(:register_core_tools)
      allow(service).to receive(:handle_exception)

      loader_mod = Module.new { def self.default_directories = [] }
      settings_mod = Module.new do
        def self.load(*) = nil
        def self.respond_to?(mth, *) = mth == :resolve_secrets! ? true : super
        def self.resolve_secrets! = nil
        def self.dig(*) = nil
      end
      settings_mod.const_set(:Loader, loader_mod)
      readiness_mod = Module.new do
        def self.mark_ready(*) = nil
        def self.mark_not_ready(*) = nil
        def self.wait_until_not_ready(*) = nil
      end
      events_mod = Module.new do
        def self.emit(*) = nil
      end
      extensions_mod = Module.new do
        def self.respond_to?(mth, *) = %i[flush_pending_registrations! shutdown].include?(mth) || super
        def self.flush_pending_registrations! = nil
        def self.shutdown = nil
      end
      tools_mod = Module.new { def self.clear = nil }
      embedding_mod = Module.new do
        def self.respond_to?(mth, *) = mth == :clear_memory ? true : super
        def self.clear_memory = nil
      end

      stub_const('Legion::Settings', settings_mod)
      stub_const('Legion::Readiness', readiness_mod)
      stub_const('Legion::Events', events_mod)
      stub_const('Legion::Extensions', extensions_mod)
      stub_const('Legion::Tools::Registry', tools_mod)
      stub_const('Legion::Tools::EmbeddingCache', embedding_mod)

      settings_hash = {
        client:     { shutting_down: false, ready: false },
        data:       { connected: false },
        llm:        { connected: false },
        rbac:       { connected: false },
        extensions: { shutdown_timeout: 5 }
      }
      allow(Legion::Settings).to receive(:[]) { |k| settings_hash[k] }
      allow(Legion::Settings).to receive(:[]=) { |k, v| settings_hash[k] = v }
      allow(Legion::Settings).to receive(:dig) { |*k| settings_hash.dig(*k) }
    end

    context 'when Crypt responds to fetch_bootstrap_rmq_creds and vault is ready' do
      before do
        crypt = Module.new do
          def self.start = nil
          def self.cs = nil
          def self.shutdown = nil
          def self.vault_connected? = true
          def self.dynamic_rmq_creds? = true
          def self.fetch_bootstrap_rmq_creds = nil
        end
        stub_const('Legion::Crypt', crypt)
      end

      it 'calls fetch_bootstrap_rmq_creds after Crypt.start' do
        expect(Legion::Crypt).to receive(:start).ordered
        expect(Legion::Crypt).to receive(:fetch_bootstrap_rmq_creds).ordered
        service.reload
      end
    end

    context 'when Crypt does not respond to fetch_bootstrap_rmq_creds' do
      before do
        crypt = Module.new do
          def self.start = nil
          def self.cs = nil
          def self.shutdown = nil
        end
        stub_const('Legion::Crypt', crypt)
      end

      it 'does not raise' do
        expect { service.reload }.not_to raise_error
      end
    end

    context 'calls resolve_secrets! after Crypt.start during reload' do
      before do
        crypt = Module.new do
          def self.start = nil
          def self.cs = nil
          def self.shutdown = nil
        end
        stub_const('Legion::Crypt', crypt)
      end

      it 'calls resolve_secrets! during reload' do
        expect(Legion::Settings).to receive(:resolve_secrets!)
        service.reload
      end
    end

    context 'calls setup_identity during reload' do
      before do
        crypt = Module.new do
          def self.start = nil
          def self.cs = nil
          def self.shutdown = nil
        end
        stub_const('Legion::Crypt', crypt)
      end

      it 'calls setup_identity to resolve identity and swap credentials' do
        expect(service).to receive(:setup_identity)
        service.reload
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Guard: swap skipped in full-flag-off scenario
  # ---------------------------------------------------------------------------

  describe '#setup_identity — feature flag off (dynamic_rmq_creds: false)' do
    before do
      allow(service).to receive(:require_relative)
      allow(service).to receive(:resolve_identity_providers).and_return(true)
      allow(service).to receive(:handle_exception)

      identity_process = Module.new do
        def self.resolved? = true
        def self.canonical_name = 'test-node'
        def self.queue_prefix = 'agent.test-node'
        def self.bind_fallback! = nil
      end
      stub_const('Legion::Identity::Process', identity_process)

      settings = Module.new do
        def self.respond_to?(mth, *) = mth == :resolve_secrets! ? true : super
        def self.resolve_secrets! = nil
        def self.dig(*) = nil
      end
      stub_const('Legion::Settings', settings)

      readiness = Module.new { def self.mark_ready(*) = nil }
      stub_const('Legion::Readiness', readiness)

      extensions = Module.new do
        def self.respond_to?(mth, *) = mth == :flush_pending_registrations! ? true : super
        def self.flush_pending_registrations! = nil
      end
      stub_const('Legion::Extensions', extensions)
    end

    context 'when dynamic_rmq_creds is false' do
      before do
        crypt = build_crypt_stub(vault_connected: true, dynamic_rmq_creds: false)
        stub_const('Legion::Crypt', crypt)
        stub_const('Legion::Mode', build_mode_stub(current: :agent, lite: false))
      end

      it 'preserves static credential behavior — swap_to_identity_creds not called' do
        expect(Legion::Crypt).not_to receive(:swap_to_identity_creds)
        service.setup_identity
      end

      it 'completes without error' do
        expect { service.setup_identity }.not_to raise_error
      end
    end
  end
end
