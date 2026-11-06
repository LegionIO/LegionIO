# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'legion/settings/agent_loader'

RSpec.describe 'Legion::Extensions YAML agent loading' do
  around do |example|
    original = Legion::Settings[:agents]
    Legion::Settings.loader.settings[:agents] = {}
    Legion::Extensions.instance_variable_set(:@load_yaml_agents, nil)
    example.run
  ensure
    Legion::Settings.loader.settings[:agents] = original
    Legion::Extensions.instance_variable_set(:@load_yaml_agents, nil)
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
        Legion::Settings.loader.settings[:agents] = { directory: agents_dir }
      end

      after { FileUtils.rm_rf(agents_dir) }

      it 'loads agent definitions and generates runner modules' do
        agents = Legion::Extensions.load_yaml_agents
        expect(agents).to be_an(Array)
        expect(agents.size).to eq(1)
        expect(agents.first[:name]).to eq('test-yaml-agent')
      end
    end

    context 'when agents directory does not exist' do
      before do
        Legion::Settings.loader.settings[:agents] = { directory: nil }
      end

      it 'returns empty array' do
        expect(Legion::Extensions.load_yaml_agents).to eq([])
      end
    end
  end
end
