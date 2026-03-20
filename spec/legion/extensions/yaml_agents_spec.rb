# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

RSpec.describe 'Legion::Extensions YAML agent loading' do
  before do
    Legion::Extensions.instance_variable_set(:@load_yaml_agents, nil)

    # Stub the AgentLoader in case the installed legion-settings gem doesn't yet include it
    unless defined?(Legion::Settings::AgentLoader)
      stub_const('Legion::Settings::AgentLoader', Module.new do
        def self.load_agents(dir)
          return [] unless dir && Dir.exist?(dir)

          require 'yaml'
          Dir.glob(File.join(dir, '*.{yaml,yml,json}')).filter_map do |path|
            content = File.read(path)
            defn = YAML.safe_load(content, symbolize_names: true)
            next unless defn.is_a?(Hash) && defn[:name] && defn.dig(:runner, :functions)&.any?

            defn
          end
        end
      end)
      $LOADED_FEATURES << 'legion/settings/agent_loader.rb'
    end
  end

  describe '.load_yaml_agents' do
    context 'when agents directory exists' do
      let(:agents_dir) { Dir.mktmpdir }
      let(:agent_yaml) do
        {
          'name'    => 'test-yaml-agent',
          'version' => '1.0',
          'runner'  => {
            'functions' => [
              { 'name' => 'greet', 'type' => 'llm', 'prompt' => 'Hello {{name}}', 'model' => 'test' }
            ]
          }
        }
      end

      before do
        require 'yaml'
        File.write(File.join(agents_dir, 'test.yaml'), YAML.dump(agent_yaml))
        allow(Legion::Settings).to receive(:dig).with(:agents, :directory).and_return(agents_dir)
      end

      after { FileUtils.rm_rf(agents_dir) }

      it 'loads agent definitions and generates runner modules' do
        agents = Legion::Extensions.load_yaml_agents
        expect(agents).to be_an(Array)
        expect(agents.size).to eq(1)
        expect(agents.first[:name]).to eq('test-yaml-agent')
      end

      it 'generates a runner module with defined methods' do
        agents = Legion::Extensions.load_yaml_agents
        runner_mod = agents.first[:_runner_module]
        expect(runner_mod).to be_a(Module)

        instance = Object.new.extend(runner_mod)
        expect(instance).to respond_to(:greet)
      end
    end

    context 'when agents directory does not exist' do
      before do
        allow(Legion::Settings).to receive(:dig).with(:agents, :directory).and_return(nil)
      end

      it 'returns empty array' do
        expect(Legion::Extensions.load_yaml_agents).to eq([])
      end
    end
  end
end
