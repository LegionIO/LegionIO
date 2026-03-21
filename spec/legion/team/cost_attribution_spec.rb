# frozen_string_literal: true

require 'spec_helper'
require 'legion/team'

RSpec.describe Legion::Team::CostAttribution do
  before do
    allow(Legion::Settings).to receive(:dig).and_call_original
    allow(Legion::Team).to receive(:current).and_return('engineering')
  end

  describe '.tag' do
    it 'merges team and user into metadata' do
      allow(Legion::Settings).to receive(:dig).with(:team, :user).and_return('alice')
      result = described_class.tag(request_id: 'abc')
      expect(result[:team]).to eq('engineering')
      expect(result[:user]).to eq('alice')
      expect(result[:request_id]).to eq('abc')
    end

    it 'falls back to ENV USER when settings has no user' do
      allow(Legion::Settings).to receive(:dig).with(:team, :user).and_return(nil)
      allow(ENV).to receive(:fetch).with('USER', nil).and_return('sysuser')
      result = described_class.tag
      expect(result[:user]).to eq('sysuser')
    end

    it 'works with empty metadata' do
      allow(Legion::Settings).to receive(:dig).with(:team, :user).and_return('bob')
      result = described_class.tag
      expect(result).to have_key(:team)
      expect(result).to have_key(:user)
    end

    it 'does not mutate the original metadata hash' do
      allow(Legion::Settings).to receive(:dig).with(:team, :user).and_return('carol')
      original = { key: 'value' }
      described_class.tag(original)
      expect(original).to eq({ key: 'value' })
    end
  end
end
