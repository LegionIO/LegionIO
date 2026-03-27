# frozen_string_literal: true

require 'spec_helper'
require 'legion/extensions/absorbers'

RSpec.describe Legion::Extensions::Absorbers::PatternMatcher do
  let(:teams_absorber) do
    Class.new(Legion::Extensions::Absorbers::Base) do
      pattern :url, 'teams.microsoft.com/l/meetup-join/*'
      description 'Teams meeting absorber'
      def handle(**) = { handler: :teams }
    end
  end

  let(:github_absorber) do
    Class.new(Legion::Extensions::Absorbers::Base) do
      pattern :url, 'github.com/**/issues/*'
      description 'GitHub issue absorber'
      def handle(**) = { handler: :github }
    end
  end

  before do
    described_class.reset!
    described_class.register(teams_absorber)
    described_class.register(github_absorber)
  end

  after { described_class.reset! }

  describe '.register' do
    it 'adds absorber patterns to the registry' do
      expect(described_class.registrations.length).to eq(2)
    end
  end

  describe '.resolve' do
    it 'returns the matching absorber class for a Teams URL' do
      result = described_class.resolve('https://teams.microsoft.com/l/meetup-join/abc123')
      expect(result).to eq(teams_absorber)
    end

    it 'returns the matching absorber class for a GitHub URL' do
      result = described_class.resolve('https://github.com/LegionIO/LegionIO/issues/42')
      expect(result).to eq(github_absorber)
    end

    it 'returns nil when no pattern matches' do
      expect(described_class.resolve('https://zoom.us/j/123')).to be_nil
    end
  end

  describe '.resolve priority' do
    let(:high_priority) do
      Class.new(Legion::Extensions::Absorbers::Base) do
        pattern :url, 'teams.microsoft.com/l/meetup-join/*', priority: 10
        def handle(**) = { handler: :high }
      end
    end

    it 'returns the higher-priority (lower number) absorber' do
      described_class.register(high_priority)
      result = described_class.resolve('https://teams.microsoft.com/l/meetup-join/abc')
      expect(result).to eq(high_priority)
    end
  end

  describe '.list' do
    it 'returns all registered patterns with their absorber classes' do
      list = described_class.list
      expect(list.length).to eq(2)
      expect(list.first).to include(:type, :value, :absorber_class, :description)
    end
  end

  describe '.reset!' do
    it 'clears all registrations' do
      described_class.reset!
      expect(described_class.registrations).to be_empty
    end
  end
end
