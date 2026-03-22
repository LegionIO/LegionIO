# frozen_string_literal: true

require 'spec_helper'
require 'legion/process_role'

RSpec.describe Legion::ProcessRole do
  describe '.resolve' do
    it 'returns all-true hash for :full' do
      result = described_class.resolve(:full)
      expect(result[:transport]).to be true
      expect(result[:cache]).to be true
      expect(result[:data]).to be true
      expect(result[:extensions]).to be true
      expect(result[:api]).to be true
      expect(result[:llm]).to be true
      expect(result[:gaia]).to be true
      expect(result[:crypt]).to be true
      expect(result[:supervision]).to be true
    end

    it 'disables extensions, llm, gaia, and supervision for :api' do
      result = described_class.resolve(:api)
      expect(result[:extensions]).to be false
      expect(result[:llm]).to be false
      expect(result[:gaia]).to be false
      expect(result[:supervision]).to be false
      expect(result[:api]).to be true
      expect(result[:transport]).to be true
      expect(result[:crypt]).to be true
    end

    it 'disables api for :worker' do
      result = described_class.resolve(:worker)
      expect(result[:api]).to be false
      expect(result[:extensions]).to be true
      expect(result[:transport]).to be true
      expect(result[:llm]).to be true
      expect(result[:gaia]).to be true
      expect(result[:supervision]).to be true
    end

    it 'disables data, api, llm, gaia, and supervision for :router' do
      result = described_class.resolve(:router)
      expect(result[:data]).to be false
      expect(result[:api]).to be false
      expect(result[:llm]).to be false
      expect(result[:gaia]).to be false
      expect(result[:supervision]).to be false
      expect(result[:transport]).to be true
      expect(result[:cache]).to be true
      expect(result[:crypt]).to be true
    end

    it 'accepts string input' do
      result = described_class.resolve('worker')
      expect(result[:api]).to be false
      expect(result[:extensions]).to be true
    end

    it 'falls back to :full for unrecognized roles' do
      allow(Legion::Logging).to receive(:warn) if defined?(Legion::Logging)
      allow($stderr).to receive(:puts)
      result = described_class.resolve(:unknown)
      expect(result).to eq(described_class.resolve(:full))
    end
  end

  describe '.current' do
    it 'returns :full when settings are not available' do
      allow(Legion::Settings).to receive(:[]).with(:process).and_raise(StandardError)
      expect(described_class.current).to eq(:full)
    end

    it 'returns :full when Legion::Settings is not defined' do
      hide_const('Legion::Settings')
      expect(described_class.current).to eq(:full)
    end

    it 'returns :full when process settings have no role key' do
      allow(Legion::Settings).to receive(:[]).with(:process).and_return({})
      expect(described_class.current).to eq(:full)
    end

    it 'returns the configured role as a symbol' do
      allow(Legion::Settings).to receive(:[]).with(:process).and_return({ role: 'worker' })
      expect(described_class.current).to eq(:worker)
    end
  end

  describe '.role?' do
    it 'returns true when current role matches' do
      allow(described_class).to receive(:current).and_return(:full)
      expect(described_class.role?(:full)).to be true
    end

    it 'returns false when current role does not match' do
      allow(described_class).to receive(:current).and_return(:worker)
      expect(described_class.role?(:full)).to be false
    end

    it 'accepts string input' do
      allow(described_class).to receive(:current).and_return(:full)
      expect(described_class.role?('full')).to be true
    end
  end
end
