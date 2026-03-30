# frozen_string_literal: true

require 'spec_helper'
require 'legion/extensions/helpers/llm'

RSpec.describe Legion::Extensions::Helpers::LLM do
  let(:test_class) do
    Class.new do
      include Legion::Extensions::Helpers::LLM
    end
  end

  subject { test_class.new }

  describe 'includes Legion::LLM::Helper' do
    it 'responds to all helper methods' do
      expect(subject).to respond_to(:llm_chat, :llm_embed, :llm_embed_batch, :llm_session,
                                    :llm_structured, :llm_ask, :llm_connected?, :llm_can_embed?,
                                    :llm_routing_enabled?, :llm_cost_estimate, :llm_cost_summary,
                                    :llm_budget_remaining, :llm_default_model, :llm_default_provider,
                                    :llm_default_intent)
    end
  end

  describe '#llm_embed' do
    it 'forwards all keyword arguments to LLM.embed' do
      expect(Legion::LLM).to receive(:embed).with('test text', provider: :ollama, dimensions: 1024)
      subject.llm_embed('test text', provider: :ollama, dimensions: 1024)
    end
  end

  describe '#llm_connected?' do
    it 'returns true when LLM is started' do
      allow(Legion::LLM).to receive(:started?).and_return(true)
      expect(subject.llm_connected?).to be true
    end

    it 'returns false when LLM is not started' do
      allow(Legion::LLM).to receive(:started?).and_return(false)
      expect(subject.llm_connected?).to be false
    end
  end
end
