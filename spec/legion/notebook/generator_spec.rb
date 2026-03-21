# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'legion/notebook/generator'

RSpec.describe Legion::Notebook::Generator do
  let(:llm_mod) { Module.new }

  let(:valid_notebook) do
    {
      'nbformat'       => 4,
      'nbformat_minor' => 5,
      'metadata'       => { 'kernelspec' => { 'name' => 'python3' } },
      'cells'          => [
        { 'cell_type' => 'markdown', 'source' => ['# Generated'], 'metadata' => {}, 'outputs' => [] }
      ]
    }
  end

  before do
    stub_const('Legion::LLM', llm_mod)
    allow(Legion::LLM).to receive(:chat).and_return({
                                                      content: JSON.generate(valid_notebook),
                                                      usage:   {}
                                                    })
  end

  describe '.generate' do
    it 'returns a notebook hash' do
      result = described_class.generate(description: 'A test notebook')
      expect(result).to be_a(Hash)
      expect(result['nbformat']).to eq(4)
    end

    it 'calls LLM with the description' do
      expect(Legion::LLM).to receive(:chat).with(
        hash_including(messages: [hash_including(role: 'user')])
      ).and_return({ content: JSON.generate(valid_notebook), usage: {} })
      described_class.generate(description: 'plot some data')
    end

    it 'passes model option to LLM when provided' do
      expect(Legion::LLM).to receive(:chat)
        .with(hash_including(model: 'claude-opus-4-5'))
        .and_return({ content: JSON.generate(valid_notebook), usage: {} })
      described_class.generate(description: 'test', model: 'claude-opus-4-5')
    end

    it 'passes provider option as symbol to LLM when provided' do
      expect(Legion::LLM).to receive(:chat)
        .with(hash_including(provider: :anthropic))
        .and_return({ content: JSON.generate(valid_notebook), usage: {} })
      described_class.generate(description: 'test', provider: 'anthropic')
    end

    it 'strips markdown fences from LLM response' do
      fenced = "```json\n#{JSON.generate(valid_notebook)}\n```"
      allow(Legion::LLM).to receive(:chat).and_return({ content: fenced, usage: {} })
      result = described_class.generate(description: 'test')
      expect(result['nbformat']).to eq(4)
    end

    it 'strips bare code fences from LLM response' do
      fenced = "```\n#{JSON.generate(valid_notebook)}\n```"
      allow(Legion::LLM).to receive(:chat).and_return({ content: fenced, usage: {} })
      result = described_class.generate(description: 'test')
      expect(result['nbformat']).to eq(4)
    end

    it 'raises ArgumentError when legion-llm is not available' do
      hide_const('Legion::LLM')
      expect do
        described_class.generate(description: 'test')
      end.to raise_error(ArgumentError, /legion-llm is required/)
    end

    it 'raises ArgumentError when LLM returns invalid JSON' do
      allow(Legion::LLM).to receive(:chat).and_return({ content: 'not valid json', usage: {} })
      expect do
        described_class.generate(description: 'test')
      end.to raise_error(ArgumentError, /invalid JSON/)
    end

    it 'raises ArgumentError when notebook is missing nbformat' do
      bad = valid_notebook.except('nbformat')
      allow(Legion::LLM).to receive(:chat).and_return({ content: JSON.generate(bad), usage: {} })
      expect do
        described_class.generate(description: 'test')
      end.to raise_error(ArgumentError, /nbformat/)
    end

    it 'raises ArgumentError when cells is not an array' do
      bad = valid_notebook.merge('cells' => 'not_an_array')
      allow(Legion::LLM).to receive(:chat).and_return({ content: JSON.generate(bad), usage: {} })
      expect do
        described_class.generate(description: 'test')
      end.to raise_error(ArgumentError, /array/)
    end
  end

  describe '.write' do
    it 'writes JSON to file' do
      require 'tempfile'
      f = Tempfile.new(['nb', '.ipynb'])
      f.close
      described_class.write(f.path, valid_notebook)
      data = JSON.parse(File.read(f.path))
      expect(data['nbformat']).to eq(4)
    ensure
      f&.unlink
    end

    it 'writes pretty-formatted JSON' do
      require 'tempfile'
      f = Tempfile.new(['nb', '.ipynb'])
      f.close
      described_class.write(f.path, valid_notebook)
      content = File.read(f.path)
      expect(content).to include("\n")
    ensure
      f&.unlink
    end
  end

  describe '.build_prompt' do
    it 'includes the description' do
      result = described_class.build_prompt('plot data', 'python3')
      expect(result).to include('plot data')
    end

    it 'includes the kernel' do
      result = described_class.build_prompt('test', 'julia')
      expect(result).to include('julia')
    end

    it 'mentions .ipynb format' do
      result = described_class.build_prompt('test', 'python3')
      expect(result).to include('.ipynb')
    end
  end

  describe '.validate_notebook!' do
    it 'raises when nbformat is missing' do
      expect { described_class.validate_notebook!({ 'cells' => [] }) }
        .to raise_error(ArgumentError, /nbformat/)
    end

    it 'raises when cells is missing' do
      expect { described_class.validate_notebook!({ 'nbformat' => 4 }) }
        .to raise_error(ArgumentError, /cells/)
    end

    it 'raises when cells is not an array' do
      expect { described_class.validate_notebook!({ 'nbformat' => 4, 'cells' => {} }) }
        .to raise_error(ArgumentError, /array/)
    end

    it 'does not raise for valid data' do
      expect { described_class.validate_notebook!({ 'nbformat' => 4, 'cells' => [] }) }.not_to raise_error
    end
  end

  describe 'NOTEBOOK_TEMPLATE' do
    it 'has the standard .ipynb keys' do
      template = described_class::NOTEBOOK_TEMPLATE
      expect(template).to have_key('nbformat')
      expect(template).to have_key('cells')
      expect(template).to have_key('metadata')
    end

    it 'defaults to python3 kernel' do
      template = described_class::NOTEBOOK_TEMPLATE
      expect(template.dig('metadata', 'kernelspec', 'name')).to eq('python3')
    end
  end
end
