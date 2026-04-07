# frozen_string_literal: true

require 'spec_helper'
require 'legion/identity/process'

RSpec.describe Legion::Identity::Process do
  let(:fixed_uuid) { 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' }
  let(:fixed_hostname) { 'test-host-01' }

  before do
    described_class.reset!
    allow(Legion).to receive(:instance_id).and_return(fixed_uuid)
    allow(Socket).to receive(:gethostname).and_return(fixed_hostname)
  end

  describe 'default state' do
    it 'is not resolved' do
      expect(described_class.resolved?).to be(false)
    end

    it 'returns anonymous as canonical_name' do
      expect(described_class.canonical_name).to eq('anonymous')
    end

    it 'returns instance_id as id fallback' do
      expect(described_class.id).to eq(fixed_uuid)
    end

    it 'returns nil for kind' do
      expect(described_class.kind).to be_nil
    end

    it 'is not persistent' do
      expect(described_class.persistent?).to be(false)
    end
  end

  describe '.bind!' do
    let(:provider) { double('provider') }
    let(:identity) do
      {
        id:             'cccccccc-1111-2222-3333-444444444444',
        canonical_name: 'my-service',
        kind:           :service,
        persistent:     true
      }
    end

    before { described_class.bind!(provider, identity) }

    it 'marks as resolved' do
      expect(described_class.resolved?).to be(true)
    end

    it 'stores the id' do
      expect(described_class.id).to eq(identity[:id])
    end

    it 'stores the canonical_name' do
      expect(described_class.canonical_name).to eq('my-service')
    end

    it 'stores the kind' do
      expect(described_class.kind).to eq(:service)
    end

    it 'stores persistent true' do
      expect(described_class.persistent?).to be(true)
    end
  end

  describe '.bind_fallback!' do
    context 'when ENV USER is set' do
      before do
        allow(ENV).to receive(:fetch).with('USER', 'anonymous').and_return('jdoe')
        described_class.bind_fallback!
      end

      it 'uses ENV USER as canonical_name' do
        expect(described_class.canonical_name).to eq('jdoe')
      end

      it 'sets kind to :human' do
        expect(described_class.kind).to eq(:human)
      end

      it 'is not persistent (ephemeral)' do
        expect(described_class.persistent?).to be(false)
      end

      it 'is not resolved' do
        expect(described_class.resolved?).to be(false)
      end
    end

    context 'when ENV USER is not set' do
      before do
        allow(ENV).to receive(:fetch).with('USER', 'anonymous').and_return('anonymous')
        described_class.bind_fallback!
      end

      it 'falls back to anonymous' do
        expect(described_class.canonical_name).to eq('anonymous')
      end
    end
  end

  describe '.mode' do
    it 'delegates to Legion::Mode.current' do
      allow(Legion::Mode).to receive(:current).and_return(:worker)
      expect(described_class.mode).to eq(:worker)
    end
  end

  describe '.queue_prefix' do
    before do
      described_class.bind!(double('provider'), {
                              id:             fixed_uuid,
                              canonical_name: 'my-node',
                              kind:           :service,
                              persistent:     true
                            })
    end

    context 'when mode is :agent' do
      before { allow(Legion::Mode).to receive(:current).and_return(:agent) }

      it 'uses agent.canonical_name.hostname pattern' do
        expect(described_class.queue_prefix).to eq("agent.my-node.#{fixed_hostname}")
      end
    end

    context 'when mode is :worker' do
      before { allow(Legion::Mode).to receive(:current).and_return(:worker) }

      it 'uses worker.canonical_name.instance_id pattern' do
        expect(described_class.queue_prefix).to eq("worker.my-node.#{fixed_uuid}")
      end
    end

    context 'when mode is :infra' do
      before { allow(Legion::Mode).to receive(:current).and_return(:infra) }

      it 'uses infra.canonical_name.hostname pattern' do
        expect(described_class.queue_prefix).to eq("infra.my-node.#{fixed_hostname}")
      end
    end

    context 'when mode is :lite' do
      before { allow(Legion::Mode).to receive(:current).and_return(:lite) }

      it 'uses lite.canonical_name.instance_id pattern' do
        expect(described_class.queue_prefix).to eq("lite.my-node.#{fixed_uuid}")
      end
    end

    context 'with unresolved identity (canonical_name falls back to anonymous)' do
      before do
        described_class.reset!
        allow(Legion).to receive(:instance_id).and_return(fixed_uuid)
        allow(Socket).to receive(:gethostname).and_return(fixed_hostname)
        allow(Legion::Mode).to receive(:current).and_return(:agent)
      end

      it 'uses anonymous as the canonical_name segment' do
        expect(described_class.queue_prefix).to eq("agent.anonymous.#{fixed_hostname}")
      end
    end

    context 'when hostname contains special characters' do
      before do
        allow(Socket).to receive(:gethostname).and_return('Host_Name.local')
        allow(Legion::Mode).to receive(:current).and_return(:agent)
      end

      it 'strips non-alphanumeric/dash characters from hostname' do
        expect(described_class.queue_prefix).to eq('agent.my-node.host-name-local')
      end
    end
  end

  describe '.identity_hash' do
    before do
      allow(Legion::Mode).to receive(:current).and_return(:agent)
      described_class.bind!(double('provider'), {
                              id:             fixed_uuid,
                              canonical_name: 'hash-test',
                              kind:           :machine,
                              persistent:     true
                            })
    end

    subject(:hash) { described_class.identity_hash }

    it 'includes id' do
      expect(hash[:id]).to eq(fixed_uuid)
    end

    it 'includes canonical_name' do
      expect(hash[:canonical_name]).to eq('hash-test')
    end

    it 'includes kind' do
      expect(hash[:kind]).to eq(:machine)
    end

    it 'includes mode' do
      expect(hash[:mode]).to eq(:agent)
    end

    it 'includes queue_prefix' do
      expect(hash[:queue_prefix]).to eq("agent.hash-test.#{fixed_hostname}")
    end

    it 'includes resolved' do
      expect(hash[:resolved]).to be(true)
    end

    it 'includes persistent' do
      expect(hash[:persistent]).to be(true)
    end

    it 'returns a Hash with exactly 7 keys' do
      expect(hash.keys).to match_array(%i[id canonical_name kind mode queue_prefix resolved persistent])
    end
  end

  describe '.reset!' do
    before do
      described_class.bind!(double('provider'), {
                              id:             fixed_uuid,
                              canonical_name: 'before-reset',
                              kind:           :service,
                              persistent:     true
                            })
    end

    it 'clears resolved state' do
      described_class.reset!
      expect(described_class.resolved?).to be(false)
    end

    it 'resets canonical_name to anonymous' do
      described_class.reset!
      expect(described_class.canonical_name).to eq('anonymous')
    end

    it 'clears id to instance_id fallback' do
      described_class.reset!
      expect(described_class.id).to eq(fixed_uuid)
    end

    it 'clears kind to nil' do
      described_class.reset!
      expect(described_class.kind).to be_nil
    end

    it 'resets persistent to false' do
      described_class.reset!
      expect(described_class.persistent?).to be(false)
    end
  end

  describe '.refresh_credentials' do
    context 'when provider responds to refresh' do
      let(:provider) { double('provider', refresh: :refreshed) }

      before do
        described_class.bind!(provider, {
                                id:             fixed_uuid,
                                canonical_name: 'refresh-test',
                                kind:           :service,
                                persistent:     true
                              })
      end

      it 'calls provider.refresh' do
        expect(provider).to receive(:refresh)
        described_class.refresh_credentials
      end
    end

    context 'when provider does not respond to refresh' do
      let(:provider) { double('provider') }

      before do
        described_class.bind!(provider, {
                                id:             fixed_uuid,
                                canonical_name: 'no-refresh',
                                kind:           :service,
                                persistent:     true
                              })
      end

      it 'does not raise' do
        expect { described_class.refresh_credentials }.not_to raise_error
      end
    end

    context 'when no provider has been bound' do
      it 'does not raise' do
        expect { described_class.refresh_credentials }.not_to raise_error
      end
    end
  end

  describe 'thread safety' do
    it 'does not corrupt state under concurrent bind! calls' do
      identities = (1..20).map do |i|
        {
          id:             "id-#{i}",
          canonical_name: "node-#{i}",
          kind:           :service,
          persistent:     true
        }
      end

      threads = identities.map do |ident|
        Thread.new { described_class.bind!(double('provider'), ident) }
      end
      threads.each(&:join)

      # identity_hash reads a single atomic snapshot — id and canonical_name must be consistent
      allow(Legion::Mode).to receive(:current).and_return(:agent)
      snapshot = described_class.identity_hash

      expect(snapshot[:id]).to match(/\Aid-\d+\z/)
      expect(snapshot[:canonical_name]).to match(/\Anode-\d+\z/)
      # The numeric suffix of id and canonical_name must match (same atomic write)
      id_num   = snapshot[:id].split('-').last.to_i
      name_num = snapshot[:canonical_name].split('-').last.to_i
      expect(id_num).to eq(name_num)
    end

    it 'resolved? remains true after concurrent reads during bind!' do
      provider = double('provider')
      described_class.bind!(provider, {
                              id:             fixed_uuid,
                              canonical_name: 'concurrent-read',
                              kind:           :service,
                              persistent:     true
                            })

      results = Array.new(10) { Thread.new { described_class.resolved? } }.map(&:value)
      expect(results).to all(be(true))
    end
  end
end
