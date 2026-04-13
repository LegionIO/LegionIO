# frozen_string_literal: true

require 'spec_helper'
require 'legion/fleet/settings'

RSpec.describe Legion::Fleet::Settings do
  describe 'FLEET_DEFAULTS' do
    subject { described_class::FLEET_DEFAULTS }

    it 'is frozen' do
      expect(subject).to be_frozen
    end

    it 'disables fleet by default' do
      expect(subject[:enabled]).to be false
    end

    it 'sets poison_message_threshold to 2' do
      expect(subject[:poison_message_threshold]).to eq(2)
    end

    it 'sets transport retry_base_delay_seconds' do
      expect(subject[:transport][:retry_base_delay_seconds]).to eq(1)
    end

    it 'sets transport retry_max_delay_seconds' do
      expect(subject[:transport][:retry_max_delay_seconds]).to eq(30)
    end

    it 'sets git clone depth' do
      expect(subject[:git][:depth]).to eq(5)
    end

    it 'sets workspace base_dir' do
      expect(subject[:workspace][:base_dir]).to eq('~/.legionio/fleet/repos')
    end

    it 'sets workspace worktree_base' do
      expect(subject[:workspace][:worktree_base]).to eq('~/.legionio/fleet/worktrees')
    end

    it 'sets workspace isolation to worktree' do
      expect(subject[:workspace][:isolation]).to eq(:worktree)
    end

    it 'sets workspace cleanup_on_complete to true' do
      expect(subject[:workspace][:cleanup_on_complete]).to be true
    end

    it 'sets workspace cleanup_clones to false' do
      expect(subject[:workspace][:cleanup_clones]).to be false
    end

    it 'sets materialization strategy to clone' do
      expect(subject[:materialization][:strategy]).to eq(:clone)
    end

    it 'sets cache dedup TTL' do
      expect(subject[:cache][:dedup_ttl_seconds]).to eq(86_400)
    end

    it 'sets cache payload TTL' do
      expect(subject[:cache][:payload_ttl_seconds]).to eq(86_400)
    end

    it 'sets cache context TTL' do
      expect(subject[:cache][:context_ttl_seconds]).to eq(86_400)
    end

    it 'sets cache worktree TTL' do
      expect(subject[:cache][:worktree_ttl_seconds]).to eq(86_400)
    end

    it 'enables planning by default' do
      expect(subject[:planning][:enabled]).to be true
    end

    it 'sets planning solvers to 1' do
      expect(subject[:planning][:solvers]).to eq(1)
    end

    it 'sets planning validators to 2' do
      expect(subject[:planning][:validators]).to eq(2)
    end

    it 'sets planning max_iterations to 5' do
      expect(subject[:planning][:max_iterations]).to eq(5)
    end

    it 'sets implementation solvers to 1' do
      expect(subject[:implementation][:solvers]).to eq(1)
    end

    it 'sets implementation validators to 3' do
      expect(subject[:implementation][:validators]).to eq(3)
    end

    it 'sets implementation max_iterations to 5' do
      expect(subject[:implementation][:max_iterations]).to eq(5)
    end

    it 'enables validation by default' do
      expect(subject[:validation][:enabled]).to be true
    end

    it 'enables adversarial_review' do
      expect(subject[:validation][:adversarial_review]).to be true
    end

    it 'sets validation quality_gate_threshold' do
      expect(subject[:validation][:quality_gate_threshold]).to eq(0.8)
    end

    it 'enables feedback drain' do
      expect(subject[:feedback][:drain_enabled]).to be true
    end

    it 'sets feedback max_drain_rounds to 3' do
      expect(subject[:feedback][:max_drain_rounds]).to eq(3)
    end

    it 'sets context max_context_files to 50' do
      expect(subject[:context][:max_context_files]).to eq(50)
    end

    it 'sets llm thinking_budget_base_tokens' do
      expect(subject[:llm][:thinking_budget_base_tokens]).to eq(16_000)
    end

    it 'sets llm thinking_budget_max_tokens' do
      expect(subject[:llm][:thinking_budget_max_tokens]).to eq(64_000)
    end

    it 'sets llm validator_timeout_seconds to 120' do
      expect(subject[:llm][:validator_timeout_seconds]).to eq(120)
    end

    it 'sets github pr_files_per_page to 30' do
      expect(subject[:github][:pr_files_per_page]).to eq(30)
    end

    it 'sets escalation on_max_iterations to human' do
      expect(subject[:escalation][:on_max_iterations]).to eq(:human)
    end

    it 'sets escalation consent_domain' do
      expect(subject[:escalation][:consent_domain]).to eq('fleet.shipping')
    end
  end

  describe 'LLM_ROUTING_OVERRIDES' do
    subject { described_class::LLM_ROUTING_OVERRIDES }

    it 'enables escalation' do
      expect(subject[:escalation][:enabled]).to be true
    end

    it 'enables pipeline_enabled' do
      expect(subject[:escalation][:pipeline_enabled]).to be true
    end

    it 'sets max_attempts to 3' do
      expect(subject[:escalation][:max_attempts]).to eq(3)
    end

    it 'sets quality_threshold to 50' do
      expect(subject[:escalation][:quality_threshold]).to eq(50)
    end

    it 'is frozen' do
      expect(subject).to be_frozen
    end
  end

  describe '.apply!' do
    context 'when Legion::Settings is defined' do
      let(:loader) { double('loader') }

      before do
        allow(Legion::Settings).to receive(:loader).and_return(loader)
        allow(loader).to receive(:load_module_settings)
      end

      it 'loads fleet defaults into settings' do
        expect(loader).to receive(:load_module_settings).with(
          { fleet: Legion::Fleet::Settings::FLEET_DEFAULTS }
        )
        allow(loader).to receive(:load_module_settings).with(anything)
        Legion::Fleet::Settings.apply!
      end

      it 'loads LLM routing overrides into settings' do
        allow(loader).to receive(:load_module_settings).with(hash_including(fleet: anything))
        expect(loader).to receive(:load_module_settings).with(
          { llm: { routing: Legion::Fleet::Settings::LLM_ROUTING_OVERRIDES } }
        )
        Legion::Fleet::Settings.apply!
      end

      it 'calls load_module_settings twice' do
        expect(loader).to receive(:load_module_settings).twice
        Legion::Fleet::Settings.apply!
      end
    end

    context 'when Legion::Settings is not defined' do
      it 'returns without error' do
        hide_const('Legion::Settings')
        expect { Legion::Fleet::Settings.apply! }.not_to raise_error
      end
    end
  end
end
