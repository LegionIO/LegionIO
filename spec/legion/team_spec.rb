# frozen_string_literal: true

require 'spec_helper'
require 'legion/team'

RSpec.describe Legion::Team do
  before do
    allow(Legion::Settings).to receive(:dig).and_call_original
  end

  describe '.current' do
    it 'returns the team name from settings' do
      allow(Legion::Settings).to receive(:dig).with(:team, :name).and_return('engineering')
      expect(described_class.current).to eq('engineering')
    end

    it 'returns "default" when settings has no team name' do
      allow(Legion::Settings).to receive(:dig).with(:team, :name).and_return(nil)
      expect(described_class.current).to eq('default')
    end
  end

  describe '.members' do
    it 'returns the members array from settings' do
      allow(Legion::Settings).to receive(:dig).with(:team, :members).and_return(%w[alice bob])
      expect(described_class.members).to eq(%w[alice bob])
    end

    it 'returns an empty array when settings has no members' do
      allow(Legion::Settings).to receive(:dig).with(:team, :members).and_return(nil)
      expect(described_class.members).to eq([])
    end
  end

  describe '.find' do
    it 'returns team data by symbol key' do
      teams = { engineering: { name: 'engineering', members: ['alice'] } }
      allow(Legion::Settings).to receive(:[]).with(:teams).and_return(teams)
      expect(described_class.find('engineering')).to eq({ name: 'engineering', members: ['alice'] })
    end

    it 'returns nil when team does not exist' do
      allow(Legion::Settings).to receive(:[]).with(:teams).and_return({})
      expect(described_class.find('unknown')).to be_nil
    end

    it 'returns nil when no teams are configured' do
      allow(Legion::Settings).to receive(:[]).with(:teams).and_return(nil)
      expect(described_class.find('anything')).to be_nil
    end
  end

  describe '.list' do
    it 'returns team names as strings' do
      teams = { engineering: {}, ops: {} }
      allow(Legion::Settings).to receive(:[]).with(:teams).and_return(teams)
      expect(described_class.list).to contain_exactly('engineering', 'ops')
    end

    it 'returns an empty array when no teams are configured' do
      allow(Legion::Settings).to receive(:[]).with(:teams).and_return(nil)
      expect(described_class.list).to eq([])
    end

    it 'returns an empty array when teams hash is empty' do
      allow(Legion::Settings).to receive(:[]).with(:teams).and_return({})
      expect(described_class.list).to eq([])
    end
  end
end
