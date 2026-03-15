# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'json'
require 'legion/cli/chat/agent_registry'

RSpec.describe Legion::CLI::Chat::AgentRegistry do
  let(:tmpdir) { Dir.mktmpdir('agent-registry-test') }
  let(:agents_dir) { File.join(tmpdir, '.legion', 'agents') }

  before do
    FileUtils.mkdir_p(agents_dir)
  end

  after do
    FileUtils.rm_rf(tmpdir)
  end

  def write_agent(name, data)
    File.write(File.join(agents_dir, "#{name}.json"), JSON.generate(data))
  end

  describe '.load_agents' do
    it 'loads JSON agent definitions' do
      write_agent('reviewer', {
                    'name'          => 'reviewer',
                    'description'   => 'Code review specialist',
                    'model'         => 'claude-sonnet-4-5-20250514',
                    'system_prompt' => 'You are a code reviewer.'
                  })

      agents = described_class.load_agents(tmpdir)
      expect(agents.keys).to eq(['reviewer'])
      expect(agents['reviewer'][:description]).to eq('Code review specialist')
      expect(agents['reviewer'][:model]).to eq('claude-sonnet-4-5-20250514')
    end

    it 'loads multiple agents' do
      write_agent('reviewer', { 'name' => 'reviewer', 'description' => 'Reviews code' })
      write_agent('debugger', { 'name' => 'debugger', 'description' => 'Debugs code' })

      agents = described_class.load_agents(tmpdir)
      expect(agents.keys).to contain_exactly('reviewer', 'debugger')
    end

    it 'skips files without name field' do
      write_agent('invalid', { 'description' => 'No name field' })

      agents = described_class.load_agents(tmpdir)
      expect(agents).to be_empty
    end

    it 'returns empty hash when directory does not exist' do
      agents = described_class.load_agents('/nonexistent')
      expect(agents).to eq({})
    end

    it 'normalizes agent data with defaults' do
      write_agent('minimal', { 'name' => 'minimal' })

      agents = described_class.load_agents(tmpdir)
      agent = agents['minimal']
      expect(agent[:weight]).to eq(1.0)
      expect(agent[:description]).to eq('')
      expect(agent[:tools]).to be_nil
    end
  end

  describe '.find' do
    it 'finds a loaded agent by name' do
      write_agent('reviewer', { 'name' => 'reviewer', 'description' => 'Reviews code' })
      described_class.load_agents(tmpdir)

      agent = described_class.find('reviewer')
      expect(agent[:name]).to eq('reviewer')
    end

    it 'returns nil for unknown agent' do
      described_class.load_agents(tmpdir)
      expect(described_class.find('nonexistent')).to be_nil
    end
  end

  describe '.names' do
    it 'returns agent names' do
      write_agent('a', { 'name' => 'a' })
      write_agent('b', { 'name' => 'b' })
      described_class.load_agents(tmpdir)

      expect(described_class.names).to contain_exactly('a', 'b')
    end
  end

  describe '.match_for_task' do
    it 'returns the best matching agent' do
      write_agent('reviewer', { 'name' => 'reviewer', 'description' => 'code review security' })
      write_agent('debugger', { 'name' => 'debugger', 'description' => 'debug errors' })
      described_class.load_agents(tmpdir)

      agent = described_class.match_for_task('review this code for security issues')
      expect(agent[:name]).to eq('reviewer')
    end

    it 'returns nil when no agents loaded' do
      described_class.load_agents(tmpdir)
      expect(described_class.match_for_task('anything')).to be_nil
    end
  end
end
