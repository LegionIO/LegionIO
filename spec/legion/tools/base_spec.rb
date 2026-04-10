# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::Tools::Base do
  let(:tool_class) do
    Class.new(described_class) do
      tool_name 'test.example'
      description 'A test tool'
      input_schema(
        properties: {
          name: { type: 'string', description: 'Name' }
        },
        required:   ['name']
      )

      class << self
        def call(name:)
          text_response({ greeting: "hello #{name}" })
        end
      end
    end
  end

  let(:deferred_tool) do
    Class.new(described_class) do
      tool_name 'test.deferred'
      description 'A deferred tool'
      deferred true
    end
  end

  describe 'DSL' do
    it 'stores tool_name' do
      expect(tool_class.tool_name).to eq('test.example')
    end

    it 'stores description' do
      expect(tool_class.description).to eq('A test tool')
    end

    it 'stores input_schema' do
      expect(tool_class.input_schema).to include(:properties)
    end

    it 'defaults deferred to false' do
      expect(tool_class.deferred?).to be false
    end

    it 'allows deferred override' do
      expect(deferred_tool.deferred?).to be true
    end
  end

  describe '.text_response' do
    it 'wraps data in content array' do
      result = tool_class.text_response({ key: 'val' })
      expect(result[:content]).to be_an(Array)
      expect(result[:content].first[:type]).to eq('text')
    end

    it 'passes strings through directly' do
      result = tool_class.text_response('raw text')
      expect(result[:content].first[:text]).to eq('raw text')
    end
  end

  describe '.error_response' do
    it 'wraps error with error flag' do
      result = tool_class.error_response('broke')
      expect(result[:error]).to be true
    end
  end

  describe '.trigger_words' do
    let(:tool_class) { Class.new(described_class) }

    it 'defaults to an empty array' do
      expect(tool_class.trigger_words).to eq([])
    end

    it 'stores and returns trigger words' do
      tool_class.trigger_words(%w[git github gh])
      expect(tool_class.trigger_words).to eq(%w[git github gh])
    end
  end

  describe '.call' do
    it 'raises NotImplementedError on base class' do
      expect { described_class.call }.to raise_error(NotImplementedError)
    end

    it 'executes subclass implementation' do
      result = tool_class.call(name: 'world')
      expect(result[:content].first[:text]).to include('hello world')
    end
  end
end
