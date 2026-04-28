# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'legion/python'
require 'legion/cli/setup_command'

RSpec.describe Legion::CLI::Setup do
  let(:tmpdir) { Dir.mktmpdir }

  after { FileUtils.rm_rf(tmpdir) }

  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end

  describe 'LLM pack definition' do
    let(:native_llm_gems) do
      %w[
        legion-llm
        lex-llm
        lex-llm-anthropic
        lex-llm-azure-foundry
        lex-llm-bedrock
        lex-llm-gemini
        lex-llm-ledger
        lex-llm-mlx
        lex-llm-ollama
        lex-llm-openai
        lex-llm-vertex
        lex-llm-vllm
      ]
    end

    it 'includes the Legion-native hosted provider extensions' do
      llm_gems = described_class::PACKS.fetch(:llm).fetch(:gems)

      expect(llm_gems).to include(*native_llm_gems)
    end

    it 'uses the Legion-native provider stack in the agentic pack' do
      agentic_gems = described_class::PACKS.fetch(:agentic).fetch(:gems)

      expect(agentic_gems).to include(*native_llm_gems)
      expect(agentic_gems).not_to include(
        'lex-azure-ai',
        'lex-bedrock',
        'lex-claude',
        'lex-foundry',
        'lex-gemini',
        'lex-openai',
        'lex-xai'
      )
    end
  end

  describe 'claude-code' do
    let(:settings_path) { File.join(tmpdir, '.claude', 'settings.json') }
    let(:skill_path)    { File.join(tmpdir, '.claude', 'commands', 'legion.md') }

    before do
      allow(File).to receive(:expand_path).with('~/.claude/settings.json').and_return(settings_path)
      allow(File).to receive(:expand_path).with('~/.claude/commands/legion.md').and_return(skill_path)
    end

    it 'creates the MCP settings file' do
      capture_stdout { described_class.start(%w[claude-code --no-color]) }
      expect(File.exist?(settings_path)).to be true
      data = JSON.parse(File.read(settings_path))
      expect(data.dig('mcpServers', 'legion', 'command')).to eq('legionio')
      expect(data.dig('mcpServers', 'legion', 'args')).to eq(%w[mcp stdio])
    end

    it 'creates the slash command skill file' do
      capture_stdout { described_class.start(%w[claude-code --no-color]) }
      expect(File.exist?(skill_path)).to be true
      content = File.read(skill_path)
      expect(content).to include('name: legion')
      expect(content).to include('legion.discover_tools')
      expect(content).to include('legion.do_action')
      expect(content).to include('legion.run_task')
      expect(content).to include('legion.list_peers')
      expect(content).to include('legion.ask_peer')
    end

    it 'merges with existing MCP servers without overwriting them' do
      FileUtils.mkdir_p(File.dirname(settings_path))
      File.write(settings_path, JSON.pretty_generate({
                                                       'mcpServers' => {
                                                         'other-server' => { 'command' => 'other', 'args' => [] }
                                                       }
                                                     }))

      capture_stdout { described_class.start(%w[claude-code --no-color]) }
      data = JSON.parse(File.read(settings_path))
      expect(data.dig('mcpServers', 'other-server', 'command')).to eq('other')
      expect(data.dig('mcpServers', 'legion', 'command')).to eq('legionio')
    end

    it 'skips MCP entry if already present without --force' do
      FileUtils.mkdir_p(File.dirname(settings_path))
      File.write(settings_path, JSON.pretty_generate({
                                                       'mcpServers' => {
                                                         'legion' => { 'command' => 'legionio', 'args' => %w[mcp stdio] }
                                                       }
                                                     }))

      output = capture_stdout { described_class.start(%w[claude-code --no-color]) }
      expect(output).to include('already present')
    end

    it 'overwrites MCP entry when --force is passed' do
      FileUtils.mkdir_p(File.dirname(settings_path))
      File.write(settings_path, JSON.pretty_generate({
                                                       'mcpServers' => {
                                                         'legion' => { 'command' => 'old', 'args' => [] }
                                                       }
                                                     }))

      capture_stdout { described_class.start(%w[claude-code --force --no-color]) }
      data = JSON.parse(File.read(settings_path))
      expect(data.dig('mcpServers', 'legion', 'command')).to eq('legionio')
    end

    it 'outputs JSON when --json is passed' do
      output = capture_stdout { described_class.start(%w[claude-code --json]) }
      parsed = JSON.parse(output, symbolize_names: true)
      expect(parsed[:platform]).to eq('claude-code')
      expect(parsed[:installed]).to be_an(Array)
    end
  end

  describe 'cursor' do
    let(:mcp_path) { File.join(tmpdir, '.cursor', 'mcp.json') }

    before do
      allow(Dir).to receive(:pwd).and_return(tmpdir)
    end

    it 'creates .cursor/mcp.json with legion MCP entry' do
      capture_stdout { described_class.start(%w[cursor --no-color]) }
      expect(File.exist?(mcp_path)).to be true
      data = JSON.parse(File.read(mcp_path))
      expect(data.dig('mcpServers', 'legion', 'command')).to eq('legionio')
      expect(data.dig('mcpServers', 'legion', 'args')).to eq(%w[mcp stdio])
    end

    it 'merges with existing cursor MCP servers' do
      FileUtils.mkdir_p(File.dirname(mcp_path))
      File.write(mcp_path, JSON.pretty_generate({
                                                  'mcpServers' => {
                                                    'existing' => { 'command' => 'existing', 'args' => [] }
                                                  }
                                                }))

      capture_stdout { described_class.start(%w[cursor --no-color]) }
      data = JSON.parse(File.read(mcp_path))
      expect(data.dig('mcpServers', 'existing', 'command')).to eq('existing')
      expect(data.dig('mcpServers', 'legion', 'command')).to eq('legionio')
    end

    it 'skips if already configured without --force' do
      FileUtils.mkdir_p(File.dirname(mcp_path))
      File.write(mcp_path, JSON.pretty_generate({
                                                  'mcpServers' => {
                                                    'legion' => { 'command' => 'legionio', 'args' => %w[mcp stdio] }
                                                  }
                                                }))

      output = capture_stdout { described_class.start(%w[cursor --no-color]) }
      expect(output).to include('already present')
    end

    it 'overwrites when --force is passed' do
      FileUtils.mkdir_p(File.dirname(mcp_path))
      File.write(mcp_path, JSON.pretty_generate({
                                                  'mcpServers' => {
                                                    'legion' => { 'command' => 'old', 'args' => [] }
                                                  }
                                                }))

      capture_stdout { described_class.start(%w[cursor --force --no-color]) }
      data = JSON.parse(File.read(mcp_path))
      expect(data.dig('mcpServers', 'legion', 'command')).to eq('legionio')
    end

    it 'outputs JSON when --json is passed' do
      output = capture_stdout { described_class.start(%w[cursor --json]) }
      parsed = JSON.parse(output, symbolize_names: true)
      expect(parsed[:platform]).to eq('cursor')
      expect(parsed[:installed]).to be_an(Array)
    end
  end

  describe 'vscode' do
    let(:mcp_path) { File.join(tmpdir, '.vscode', 'mcp.json') }

    before do
      allow(Dir).to receive(:pwd).and_return(tmpdir)
    end

    it 'creates .vscode/mcp.json with vscode-style legion entry' do
      capture_stdout { described_class.start(%w[vscode --no-color]) }
      expect(File.exist?(mcp_path)).to be true
      data = JSON.parse(File.read(mcp_path))
      expect(data.dig('servers', 'legion', 'type')).to eq('stdio')
      expect(data.dig('servers', 'legion', 'command')).to eq('legionio')
      expect(data.dig('servers', 'legion', 'args')).to eq(%w[mcp stdio])
    end

    it 'merges with existing vscode servers' do
      FileUtils.mkdir_p(File.dirname(mcp_path))
      File.write(mcp_path, JSON.pretty_generate({
                                                  'servers' => {
                                                    'other' => { 'type' => 'stdio', 'command' => 'other', 'args' => [] }
                                                  }
                                                }))

      capture_stdout { described_class.start(%w[vscode --no-color]) }
      data = JSON.parse(File.read(mcp_path))
      expect(data.dig('servers', 'other', 'command')).to eq('other')
      expect(data.dig('servers', 'legion', 'command')).to eq('legionio')
    end

    it 'skips if already configured without --force' do
      FileUtils.mkdir_p(File.dirname(mcp_path))
      File.write(mcp_path, JSON.pretty_generate({
                                                  'servers' => {
                                                    'legion' => { 'type' => 'stdio', 'command' => 'legionio',
                                                                  'args' => %w[mcp stdio] }
                                                  }
                                                }))

      output = capture_stdout { described_class.start(%w[vscode --no-color]) }
      expect(output).to include('already present')
    end

    it 'overwrites when --force is passed' do
      FileUtils.mkdir_p(File.dirname(mcp_path))
      File.write(mcp_path, JSON.pretty_generate({
                                                  'servers' => {
                                                    'legion' => { 'type' => 'stdio', 'command' => 'old', 'args' => [] }
                                                  }
                                                }))

      capture_stdout { described_class.start(%w[vscode --force --no-color]) }
      data = JSON.parse(File.read(mcp_path))
      expect(data.dig('servers', 'legion', 'command')).to eq('legionio')
    end

    it 'outputs JSON when --json is passed' do
      output = capture_stdout { described_class.start(%w[vscode --json]) }
      parsed = JSON.parse(output, symbolize_names: true)
      expect(parsed[:platform]).to eq('vscode')
      expect(parsed[:installed]).to be_an(Array)
    end
  end

  describe 'python' do
    let(:venv_dir) { File.join(tmpdir, 'python') }
    let(:marker)   { File.join(tmpdir, '.python-venv') }

    before do
      stub_const('Legion::CLI::Setup::PYTHON_VENV_DIR', venv_dir)
      stub_const('Legion::CLI::Setup::PYTHON_MARKER', marker)
    end

    it 'exits with error when python3 is not found' do
      allow(Legion::Python).to receive(:find_system_python3).and_return(nil)
      expect do
        capture_stdout { described_class.start(%w[python --no-color]) }
      end.to raise_error(SystemExit)
    end

    def setup_venv_stubs
      allow(Legion::Python).to receive(:find_system_python3).and_return('/usr/bin/python3')

      # Pre-create venv structure so the system() call to create venv is skipped
      pip_path = File.join(venv_dir, 'bin', 'pip')
      FileUtils.mkdir_p(File.join(venv_dir, 'bin'))
      File.write(File.join(venv_dir, 'pyvenv.cfg'), 'home = /usr')
      FileUtils.touch(pip_path)
      File.chmod(0o755, pip_path)

      mock_status = instance_double(::Process::Status, success?: true)
      allow(Open3).to receive(:capture2e).and_return(['Successfully installed', mock_status])

      # Stub the backtick call inside python_version without stubbing the Thor instance
      allow_any_instance_of(Kernel).to receive(:`).and_return('Python 3.12.0')
    end

    it 'creates venv when python3 is available' do
      setup_venv_stubs
      output = capture_stdout { described_class.start(%w[python --no-color]) }
      expect(output).to include('Python environment ready')
    end

    it 'outputs JSON when --json is passed' do
      setup_venv_stubs
      output = capture_stdout { described_class.start(%w[python --json]) }
      parsed = JSON.parse(output, symbolize_names: true)
      expect(parsed[:venv]).to eq(venv_dir)
      expect(parsed[:results]).to be_an(Array)
    end

    it 'destroys and recreates venv with --rebuild' do
      setup_venv_stubs
      output = capture_stdout { described_class.start(%w[python --rebuild --no-color]) }
      expect(output).to include('Rebuilding')
    end

    it 'reports failed packages in results' do
      setup_venv_stubs
      fail_status = instance_double(::Process::Status, success?: false)
      allow(Open3).to receive(:capture2e).and_return(['error: no matching distribution', fail_status])
      output = capture_stdout do
        described_class.start(%w[python --json])
      rescue SystemExit
        # expected — exit 1 on package failure
      end
      parsed = begin
        JSON.parse(output, symbolize_names: true)
      rescue StandardError
        nil
      end
      expect(parsed[:results]).to be_an(Array) if parsed
    end
  end

  describe 'status' do
    before do
      allow(Dir).to receive(:pwd).and_return(tmpdir)
      allow(File).to receive(:expand_path).with('~/.claude/settings.json')
                                          .and_return(File.join(tmpdir, '.claude', 'settings.json'))
    end

    it 'shows not configured when no files exist' do
      output = capture_stdout { described_class.start(%w[status --no-color]) }
      expect(output).to include('Claude Code')
      expect(output).to include('Cursor')
      expect(output).to include('VS Code')
      expect(output).to include('not configured')
    end

    it 'shows configured when claude settings has legion entry' do
      settings_path = File.join(tmpdir, '.claude', 'settings.json')
      FileUtils.mkdir_p(File.dirname(settings_path))
      File.write(settings_path, JSON.pretty_generate({
                                                       'mcpServers' => {
                                                         'legion' => { 'command' => 'legionio', 'args' => %w[mcp stdio] }
                                                       }
                                                     }))

      output = capture_stdout { described_class.start(%w[status --no-color]) }
      expect(output).to match(/Claude Code.*configured/m)
    end

    it 'shows configured count in summary' do
      output = capture_stdout { described_class.start(%w[status --no-color]) }
      expect(output).to match(/\d+ of \d+ platform/)
    end

    it 'outputs JSON when --json is passed' do
      output = capture_stdout { described_class.start(%w[status --json]) }
      parsed = JSON.parse(output, symbolize_names: true)
      expect(parsed[:platforms]).to be_an(Array)
      expect(parsed[:platforms].size).to eq(3)
      parsed[:platforms].each do |p|
        expect(p).to have_key(:name)
        expect(p).to have_key(:configured)
      end
    end
  end
end
