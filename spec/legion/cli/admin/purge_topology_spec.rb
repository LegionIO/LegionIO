# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli'
require 'legion/cli/admin/purge_topology'

RSpec.describe Legion::CLI::Admin::PurgeTopology do
  describe 'Thor registration' do
    it 'has a purge command' do
      expect(described_class.commands).to have_key('purge')
    end

    it 'has --execute option on purge' do
      opt = described_class.commands['purge']
      expect(opt).not_to be_nil
    end

    it 'defaults to dry-run (execute: false)' do
      expect(described_class.class_options[:execute].default).to be false
    end

    it 'accepts --host option' do
      expect(described_class.class_options).to have_key(:host)
    end

    it 'accepts --port option' do
      expect(described_class.class_options).to have_key(:port)
    end

    it 'has management API default port 15672' do
      expect(described_class.class_options[:port].default).to eq(15_672)
    end
  end

  describe 'find_legacy_topology pattern matching' do
    let(:cmd) do
      instance = described_class.new
      # Stub options to avoid real HTTP calls
      allow(instance).to receive(:options).and_return({
                                                        host: 'localhost', port: 15_672, user: 'guest', password: 'guest', vhost: '/'
                                                      })
      instance
    end

    it 'identifies legacy exchanges matching legion.{lex} pattern' do
      all_exchanges = [
        { name: 'legion.github' },
        { name: 'legion.apollo' },
        { name: 'legion.task' },        # infrastructure — should be excluded
        { name: 'lex.github' },         # v3.0 — should be excluded
        { name: 'amq.direct' }          # AMQP built-in — should be excluded
      ]
      all_queues = []
      allow(cmd).to receive(:management_api).with(%r{/exchanges/}).and_return(all_exchanges)
      allow(cmd).to receive(:management_api).with(%r{/queues/}).and_return(all_queues)

      result = cmd.send(:find_legacy_topology)
      expect(result[:exchanges]).to contain_exactly('legion.github', 'legion.apollo')
      expect(result[:queues]).to be_empty
    end

    it 'identifies legacy queues matching legion.{lex} pattern' do
      all_exchanges = []
      all_queues = [
        { name: 'legion.github.pull_request' },
        { name: 'legion.task.queue' },  # infrastructure — excluded
        { name: 'lex.github.runners.pull_request' } # v3.0 — excluded
      ]
      allow(cmd).to receive(:management_api).with(%r{/exchanges/}).and_return(all_exchanges)
      allow(cmd).to receive(:management_api).with(%r{/queues/}).and_return(all_queues)

      result = cmd.send(:find_legacy_topology)
      expect(result[:queues]).to contain_exactly('legion.github.pull_request')
      expect(result[:exchanges]).to be_empty
    end

    it 'returns empty when no legacy topology exists' do
      allow(cmd).to receive(:management_api).with(%r{/exchanges/}).and_return([{ name: 'lex.github' }])
      allow(cmd).to receive(:management_api).with(%r{/queues/}).and_return([{ name: 'lex.github.runners.pull_request' }])

      result = cmd.send(:find_legacy_topology)
      expect(result[:exchanges]).to be_empty
      expect(result[:queues]).to be_empty
    end
  end
end
