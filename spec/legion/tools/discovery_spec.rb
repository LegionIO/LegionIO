# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::Tools::Discovery do
  before { Legion::Tools::Registry.clear }

  let(:mock_runner) do
    Module.new do
      def self.name
        'Legion::Extensions::TestExt::Runners::MyRunner'
      end

      def self.settings
        {
          functions: {
            do_thing: { desc: 'Does a thing', options: { properties: { id: { type: 'string' } } } }
          }
        }
      end

      def self.do_thing(**_params)
        { result: 'ok' }
      end
    end
  end

  let(:mock_extension) do
    mod = Module.new do
      def self.name
        'Legion::Extensions::TestExt'
      end

      def self.mcp_tools?
        true
      end

      def self.mcp_tools_deferred?
        false
      end
    end

    runner = mock_runner
    mod.define_singleton_method(:runner_modules) { [runner] }
    mod
  end

  describe '.discover_and_register' do
    before do
      allow(Legion::Extensions).to receive(:loaded_extension_modules).and_return([mock_extension])
    end

    it 'registers discovered tools into Registry' do
      described_class.discover_and_register
      expect(Legion::Tools::Registry.all_tools.size).to eq(1)
    end

    it 'builds correct tool_name' do
      described_class.discover_and_register
      tool = Legion::Tools::Registry.all_tools.first
      expect(tool.tool_name).to include('do_thing')
    end

    it 'sets deferred based on extension DSL' do
      described_class.discover_and_register
      tool = Legion::Tools::Registry.all_tools.first
      expect(tool.deferred?).to be false
    end

    it 'builds callable tool that delegates to runner' do
      described_class.discover_and_register
      tool = Legion::Tools::Registry.all_tools.first
      result = tool.call(id: '123')
      expect(result[:content].first[:text]).to include('ok')
    end
  end

  describe '.discover_and_register with mcp_tools? false' do
    let(:disabled_extension) do
      mod = Module.new do
        def self.name
          'Legion::Extensions::Disabled'
        end

        def self.mcp_tools?
          false
        end

        def self.mcp_tools_deferred?
          true
        end
      end
      runner = mock_runner
      mod.define_singleton_method(:runner_modules) { [runner] }
      mod
    end

    before do
      allow(Legion::Extensions).to receive(:loaded_extension_modules).and_return([disabled_extension])
    end

    it 'skips extensions with mcp_tools? false' do
      described_class.discover_and_register
      expect(Legion::Tools::Registry.all_tools).to be_empty
    end
  end

  describe 'trigger_words propagation' do
    before { Legion::Tools::Registry.clear }

    let(:runner_mod) do
      mod = Module.new do
        def self.name = 'Legion::Extensions::Testlex::Runners::Stuff'
        def self.mcp_tools? = true
        def self.mcp_tools_deferred? = true
        def self.trigger_words = %w[stuff things]
        def self.settings = { functions: { do_stuff: { desc: 'does stuff', options: {} } } }
        def self.do_stuff(**) = { result: true }
      end
      mod.extend(Legion::Extensions::Definitions)
      mod
    end

    let(:ext_mod) do
      runner = runner_mod
      Module.new do
        def self.name = 'Legion::Extensions::Testlex'
        def self.lex_name = 'testlex'
        def self.mcp_tools? = true
        def self.mcp_tools_deferred? = true
        def self.trigger_words = %w[test]
        define_singleton_method(:runner_modules) { [runner] }
      end
    end

    it 'propagates merged trigger words to registered tool classes' do
      allow(Legion::Extensions).to receive(:loaded_extension_modules).and_return([ext_mod])
      Legion::Tools::Discovery.discover_and_register

      tool = Legion::Tools::Registry.all_tools.first
      expect(tool.trigger_words).to include('stuff', 'things', 'test')
    end
  end

  describe 'sticky attribute on discovered tool classes' do
    let(:ext) do
      mod = Module.new
      mod.extend(Legion::Extensions::Core) if Legion::Extensions.const_defined?(:Core, false)
      mod
    end

    it 'sets sticky true when extension returns true from sticky_tools?' do
      allow(ext).to receive(:sticky_tools?).and_return(true)
      attrs = Legion::Tools::Discovery.send(:tool_attributes, ext, double(name: 'Ext::Runners::Test'),
                                            :do_thing, { desc: 'test', options: {} }, nil, false)
      expect(attrs[:sticky]).to eq(true)
    end

    it 'sets sticky false when extension returns false' do
      allow(ext).to receive(:sticky_tools?).and_return(false)
      attrs = Legion::Tools::Discovery.send(:tool_attributes, ext, double(name: 'Ext::Runners::Test'),
                                            :do_thing, { desc: 'test', options: {} }, nil, false)
      expect(attrs[:sticky]).to eq(false)
    end

    it 'treats nil return from sticky_tools? as false (conservative opt-out)' do
      allow(ext).to receive(:sticky_tools?).and_return(nil)
      attrs = Legion::Tools::Discovery.send(:tool_attributes, ext, double(name: 'Ext::Runners::Test'),
                                            :do_thing, { desc: 'test', options: {} }, nil, false)
      expect(attrs[:sticky]).to eq(false)
    end

    it 'calls sticky() on the created tool class' do
      allow(ext).to receive(:sticky_tools?).and_return(false)
      tool_class = Legion::Tools::Discovery.send(:build_tool_class,
                                                 ext:        ext,
                                                 runner_mod: double(name: 'Ext::Runners::Test', respond_to?: false),
                                                 func_name:  :do_thing,
                                                 meta:       { desc: 'test', options: {} },
                                                 defn:       nil,
                                                 deferred:   false)
      expect(tool_class.sticky).to eq(false)
    end
  end

  describe 'runner-level override' do
    let(:override_runner) do
      Module.new do
        def self.name
          'Legion::Extensions::Override::Runners::Special'
        end

        def self.mcp_tools?
          false
        end

        def self.settings
          {
            functions: {
              hidden: { desc: 'Hidden', options: {} }
            }
          }
        end
      end
    end

    let(:override_extension) do
      mod = Module.new do
        def self.name
          'Legion::Extensions::Override'
        end

        def self.mcp_tools?
          true
        end

        def self.mcp_tools_deferred?
          true
        end
      end
      runner = override_runner
      mod.define_singleton_method(:runner_modules) { [runner] }
      mod
    end

    before do
      allow(Legion::Extensions).to receive(:loaded_extension_modules).and_return([override_extension])
    end

    it 'respects runner-level mcp_tools? override' do
      described_class.discover_and_register
      expect(Legion::Tools::Registry.all_tools).to be_empty
    end
  end
end
