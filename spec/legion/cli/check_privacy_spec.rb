# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli/check/privacy_check'

RSpec.describe Legion::CLI::Check::PrivacyCheck do
  describe '#run' do
    let(:checker) { described_class.new }

    context 'when privacy mode is fully configured' do
      before do
        allow(Legion::Settings).to receive(:enterprise_privacy?).and_return(true)
        allow(Legion::Settings).to receive(:[]).with(:llm).and_return(
          { providers: { bedrock: { api_key: nil }, anthropic: { api_key: nil } } }
        )
      end

      it 'reports flag_set as pass' do
        result = checker.run
        expect(result[:flag_set]).to eq(:pass)
      end

      it 'reports no_cloud_keys as pass when all cloud API keys are nil' do
        result = checker.run
        expect(result[:no_cloud_keys]).to eq(:pass)
      end
    end

    context 'when privacy mode is not set' do
      before { allow(Legion::Settings).to receive(:enterprise_privacy?).and_return(false) }

      it 'reports flag_set as fail' do
        result = checker.run
        expect(result[:flag_set]).to eq(:fail)
      end
    end

    context 'when a cloud API key is present' do
      before do
        allow(Legion::Settings).to receive(:enterprise_privacy?).and_return(true)
        allow(Legion::Settings).to receive(:[]).with(:llm).and_return(
          { providers: { anthropic: { api_key: 'sk-real-key' } } }
        )
      end

      it 'reports no_cloud_keys as fail' do
        result = checker.run
        expect(result[:no_cloud_keys]).to eq(:fail)
      end
    end

    context 'when a cloud key uses vault:// reference' do
      before do
        allow(Legion::Settings).to receive(:enterprise_privacy?).and_return(true)
        allow(Legion::Settings).to receive(:[]).with(:llm).and_return(
          { providers: { anthropic: { api_key: 'vault://secret/data/llm#key' } } }
        )
      end

      it 'reports no_cloud_keys as pass (vault refs are not raw keys)' do
        result = checker.run
        expect(result[:no_cloud_keys]).to eq(:pass)
      end
    end
  end

  describe '#overall_pass?' do
    let(:checker) { described_class.new }

    it 'returns true when all probes pass' do
      allow(checker).to receive(:run).and_return({ flag_set: :pass, no_cloud_keys: :pass, no_external_endpoints: :pass })
      expect(checker.overall_pass?).to be true
    end

    it 'returns false when any probe fails' do
      allow(checker).to receive(:run).and_return({ flag_set: :fail, no_cloud_keys: :pass, no_external_endpoints: :pass })
      expect(checker.overall_pass?).to be false
    end
  end
end
