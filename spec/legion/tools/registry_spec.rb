# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::Tools::Registry do
  let(:always_tool) do
    Class.new(Legion::Tools::Base) do
      tool_name 'test.always'
      description 'Always loaded'
    end
  end

  let(:deferred_tool) do
    Class.new(Legion::Tools::Base) do
      tool_name 'test.deferred'
      description 'Deferred'
      deferred true
    end
  end

  before { described_class.clear }

  describe '.register' do
    it 'adds to always bucket by default' do
      described_class.register(always_tool)
      expect(described_class.tools).to include(always_tool)
    end

    it 'adds deferred tool to deferred bucket' do
      described_class.register(deferred_tool)
      expect(described_class.deferred_tools).to include(deferred_tool)
    end

    it 'deduplicates by tool_name' do
      described_class.register(always_tool)
      described_class.register(always_tool)
      expect(described_class.tools.size).to eq(1)
    end

    it 'logs warning on duplicate' do
      described_class.register(always_tool)
      expect(Legion::Logging).to receive(:warn).with(/duplicate registration rejected/)
      described_class.register(always_tool)
    end

    it 'handles duck-typed tools without deferred?' do
      duck = Class.new do
        def self.tool_name
          'test.duck'
        end
      end
      described_class.register(duck)
      expect(described_class.tools).to include(duck)
    end
  end

  describe '.find' do
    it 'finds across both buckets' do
      described_class.register(always_tool)
      described_class.register(deferred_tool)
      expect(described_class.find('test.always')).to eq(always_tool)
      expect(described_class.find('test.deferred')).to eq(deferred_tool)
    end
  end

  describe '.for_extension' do
    it 'filters by extension name' do
      tool = Class.new(Legion::Tools::Base) do
        tool_name 'test.ext_tool'
        extension 'node'
      end
      described_class.register(tool)
      expect(described_class.for_extension('node')).to include(tool)
      expect(described_class.for_extension('other')).to be_empty
    end

    it 'unregisters all tools owned by an extension' do
      node_tool = Class.new(Legion::Tools::Base) do
        tool_name 'test.node_tool'
        extension 'node'
      end
      other_tool = Class.new(Legion::Tools::Base) do
        tool_name 'test.other_tool'
        extension 'other'
      end
      described_class.register(node_tool)
      described_class.register(other_tool)

      removed = described_class.unregister_extension('node')

      expect(removed).to eq(1)
      expect(described_class.for_extension('node')).to be_empty
      expect(described_class.for_extension('other')).to include(other_tool)
    end
  end

  describe '.tagged' do
    it 'filters by tag' do
      tool = Class.new(Legion::Tools::Base) do
        tool_name 'test.tagged'
        tags %w[core operational]
      end
      described_class.register(tool)
      expect(described_class.tagged('core')).to include(tool)
      expect(described_class.tagged('missing')).to be_empty
    end
  end

  describe '.clear' do
    it 'empties both buckets' do
      described_class.register(always_tool)
      described_class.register(deferred_tool)
      described_class.clear
      expect(described_class.all_tools).to be_empty
    end
  end
end
