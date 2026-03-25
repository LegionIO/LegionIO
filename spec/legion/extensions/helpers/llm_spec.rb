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

  describe '#llm_embed' do
    it 'forwards all keyword arguments to LLM.embed' do
      expect(Legion::LLM).to receive(:embed).with('test text', provider: :ollama, dimensions: 1024)
      subject.llm_embed('test text', provider: :ollama, dimensions: 1024)
    end

    it 'forwards model kwarg' do
      expect(Legion::LLM).to receive(:embed).with('hello', model: 'mxbai-embed-large')
      subject.llm_embed('hello', model: 'mxbai-embed-large')
    end

    it 'calls LLM.embed with no kwargs when none are given' do
      expect(Legion::LLM).to receive(:embed).with('bare text')
      subject.llm_embed('bare text')
    end
  end
end
