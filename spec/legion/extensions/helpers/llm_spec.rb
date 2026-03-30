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

  describe 'includes Legion::LLM::Helper when available' do
    it 'responds to llm_embed (always available)' do
      expect(subject).to respond_to(:llm_embed)
    end

    it 'responds to extended helper methods when Legion::LLM::Helper is defined', if: defined?(Legion::LLM::Helper) do
      expect(subject).to respond_to(:llm_chat, :llm_embed_batch, :llm_session,
                                    :llm_structured, :llm_ask, :llm_connected?,
                                    :llm_cost_estimate, :llm_default_model)
    end
  end

  describe '#llm_embed' do
    it 'delegates to LLM.embed' do
      expect(Legion::LLM).to receive(:embed).with('test text')
      subject.llm_embed('test text')
    end
  end

  describe '#llm_connected?', if: defined?(Legion::LLM::Helper) do
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
