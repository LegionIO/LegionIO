# frozen_string_literal: true

require 'spec_helper'
require 'securerandom'
require 'legion/cluster/lock'
require 'legion/cluster/leader'

RSpec.describe Legion::Cluster::Leader do
  subject(:leader) { described_class.new }

  describe '#initialize' do
    it 'starts not as leader' do
      expect(leader.is_leader).to be false
    end

    it 'assigns a node_id' do
      expect(leader.node_id).not_to be_nil
    end

    it 'accepts a custom node_id' do
      custom = described_class.new(node_id: 'my-node')
      expect(custom.node_id).to eq('my-node')
    end
  end

  describe '#leader?' do
    it 'returns false initially' do
      expect(leader.leader?).to be false
    end
  end

  describe '#node_id' do
    it 'is set to a non-empty string' do
      expect(leader.node_id).to be_a(String)
      expect(leader.node_id).not_to be_empty
    end

    it 'is unique across instances by default' do
      other = described_class.new
      expect(leader.node_id).not_to eq(other.node_id)
    end
  end

  describe '#stop' do
    it 'is safe to call when not started' do
      expect { leader.stop }.not_to raise_error
    end

    it 'does not call resign when not a leader' do
      allow(Legion::Cluster::Lock).to receive(:release)
      leader.stop
      expect(Legion::Cluster::Lock).not_to have_received(:release)
    end
  end

  describe '#start and #stop lifecycle' do
    before do
      allow(Legion::Cluster::Lock).to receive(:acquire).and_return(false)
      allow(Legion::Cluster::Lock).to receive(:release)
    end

    it 'starts a heartbeat thread' do
      leader.start
      expect(leader.instance_variable_get(:@heartbeat_thread)).not_to be_nil
      leader.stop
    end

    it 'sets running to false after stop' do
      leader.start
      leader.stop
      expect(leader.instance_variable_get(:@running)).to be false
    end
  end

  describe 'election logic' do
    it 'becomes leader when lock is acquired' do
      allow(Legion::Cluster::Lock).to receive(:acquire).and_return(true)
      allow(Legion::Cluster::Lock).to receive(:release)
      leader.send(:attempt_election)
      expect(leader.leader?).to be true
    end

    it 'is not leader when lock is unavailable' do
      allow(Legion::Cluster::Lock).to receive(:acquire).and_return(false)
      leader.send(:attempt_election)
      expect(leader.leader?).to be false
    end

    it 'sets is_leader to false when attempt_election raises' do
      allow(Legion::Cluster::Lock).to receive(:acquire).and_raise(StandardError, 'db down')
      leader.send(:attempt_election)
      expect(leader.leader?).to be false
    end
  end
end
