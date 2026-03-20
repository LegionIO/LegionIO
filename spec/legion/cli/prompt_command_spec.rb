# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli'
require 'legion/cli/prompt_command'

RSpec.describe Legion::CLI::Prompt do
  let(:out) { instance_double(Legion::CLI::Output::Formatter) }
  let(:client) { instance_double('Legion::Extensions::Prompt::Client') }

  before do
    allow(Legion::CLI::Output::Formatter).to receive(:new).and_return(out)
    allow(out).to receive(:success)
    allow(out).to receive(:error)
    allow(out).to receive(:warn)
    allow(out).to receive(:json)
    allow(out).to receive(:spacer)
    allow(out).to receive(:detail)
    allow(out).to receive(:header)
    allow(out).to receive(:table)

    allow(Legion::CLI::Connection).to receive(:config_dir=)
    allow(Legion::CLI::Connection).to receive(:log_level=)
    allow(Legion::CLI::Connection).to receive(:ensure_data)
    allow(Legion::CLI::Connection).to receive(:shutdown)

    stub_const('Legion::Extensions::Prompt::Client', Class.new do
      def initialize(**); end
    end)
    allow(Legion::Extensions::Prompt::Client).to receive(:new).and_return(client)

    data_mod = Module.new { def self.db = nil }
    stub_const('Legion::Data', data_mod)
  end

  def build_command(opts = {})
    described_class.new([], opts.merge(json: false, no_color: true, verbose: false))
  end

  def build_json_command(opts = {})
    described_class.new([], opts.merge(json: true, no_color: true, verbose: false))
  end

  # Helper to stub the with_prompt_client block to yield our test client
  def stub_client(cmd)
    allow(cmd).to receive(:with_prompt_client).and_yield(client)
  end

  describe 'class structure' do
    it 'is a Thor subcommand' do
      expect(described_class).to be < Thor
    end

    it 'has list as default task' do
      expect(described_class.default_command).to eq('list')
    end

    it 'responds to list, show, create, tag, diff' do
      expect(described_class.commands.keys).to include('list', 'show', 'create', 'tag', 'diff')
    end
  end

  describe '#list' do
    let(:prompts) do
      [
        { name: 'summarize', description: 'Summarize text', latest_version: 2, updated_at: '2026-01-01' },
        { name: 'translate', description: 'Translate text', latest_version: 1, updated_at: '2026-01-02' }
      ]
    end

    before { allow(client).to receive(:list_prompts).and_return(prompts) }

    it 'renders a table of prompts' do
      cmd = build_command
      stub_client(cmd)
      expect(out).to receive(:table).with(%w[name description version updated_at], anything)
      cmd.list
    end

    it 'outputs JSON when --json is set' do
      cmd = build_json_command
      stub_client(cmd)
      expect(out).to receive(:json).with(prompts)
      cmd.list
    end

    it 'warns when no prompts exist' do
      allow(client).to receive(:list_prompts).and_return([])
      cmd = build_command
      stub_client(cmd)
      expect(out).to receive(:warn).with('No prompts found')
      cmd.list
    end
  end

  describe '#show' do
    let(:prompt_result) do
      { name: 'summarize', version: 2, template: 'Summarize: {{text}}',
        model_params: { temperature: 0.5 }, content_hash: 'abc123', created_at: '2026-01-01' }
    end

    before { allow(client).to receive(:get_prompt).and_return(prompt_result) }

    it 'renders prompt details' do
      cmd = build_command
      stub_client(cmd)
      expect(out).to receive(:header).with('Prompt: summarize')
      cmd.show('summarize')
    end

    it 'outputs JSON when --json is set' do
      cmd = build_json_command
      stub_client(cmd)
      expect(out).to receive(:json).with(prompt_result)
      cmd.show('summarize')
    end

    it 'shows error when prompt not found' do
      allow(client).to receive(:get_prompt).and_return({ error: 'not_found' })
      cmd = build_command
      stub_client(cmd)
      expect(out).to receive(:error).with(/not_found/)
      expect { cmd.show('missing') }.to raise_error(SystemExit)
    end

    it 'passes version option to get_prompt' do
      cmd = described_class.new([], json: false, no_color: true, verbose: false, version: 1)
      stub_client(cmd)
      expect(client).to receive(:get_prompt).with(name: 'summarize', version: 1).and_return(prompt_result)
      cmd.show('summarize')
    end

    it 'passes tag option to get_prompt' do
      cmd = described_class.new([], json: false, no_color: true, verbose: false, tag: 'stable')
      stub_client(cmd)
      expect(client).to receive(:get_prompt).with(name: 'summarize', tag: 'stable').and_return(prompt_result)
      cmd.show('summarize')
    end
  end

  describe '#create' do
    let(:create_result) { { created: true, name: 'new-prompt', version: 1, prompt_id: 42 } }

    before { allow(client).to receive(:create_prompt).and_return(create_result) }

    it 'calls create_prompt with name and template' do
      cmd = described_class.new([], json: false, no_color: true, verbose: false,
                                    template: 'Hello {{name}}')
      stub_client(cmd)
      expect(client).to receive(:create_prompt).with(
        name: 'new-prompt', template: 'Hello {{name}}', description: nil, model_params: {}
      ).and_return(create_result)
      cmd.create('new-prompt')
    end

    it 'outputs success message after creation' do
      cmd = described_class.new([], json: false, no_color: true, verbose: false,
                                    template: 'Hello {{name}}')
      stub_client(cmd)
      expect(out).to receive(:success).with(/new-prompt.*version 1/i)
      cmd.create('new-prompt')
    end

    it 'outputs JSON when --json is set' do
      cmd = described_class.new([], json: true, no_color: true, verbose: false,
                                    template: 'Hello')
      stub_client(cmd)
      expect(out).to receive(:json).with(create_result)
      cmd.create('new-prompt')
    end

    it 'passes description and model_params when provided' do
      cmd = described_class.new([], json: false, no_color: true, verbose: false,
                                    template: 'tmpl', description: 'my desc',
                                    model_params: '{"temperature":0.7}')
      stub_client(cmd)
      expect(client).to receive(:create_prompt).with(
        name: 'new-prompt', template: 'tmpl', description: 'my desc',
        model_params: { 'temperature' => 0.7 }
      ).and_return(create_result)
      cmd.create('new-prompt')
    end

    it 'shows error on invalid JSON in --model-params' do
      cmd = described_class.new([], json: false, no_color: true, verbose: false,
                                    template: 'tmpl', model_params: 'not-json')
      stub_client(cmd)
      expect(client).not_to receive(:create_prompt)
      expect(out).to receive(:error).with(/Invalid JSON/)
      cmd.create('new-prompt')
    end
  end

  describe '#tag' do
    let(:tag_result) { { tagged: true, name: 'summarize', tag: 'stable', version: 2 } }

    before { allow(client).to receive(:tag_prompt).and_return(tag_result) }

    it 'calls tag_prompt with name and tag' do
      cmd = build_command
      stub_client(cmd)
      expect(client).to receive(:tag_prompt).with(name: 'summarize', tag: 'stable').and_return(tag_result)
      cmd.tag('summarize', 'stable')
    end

    it 'outputs success message' do
      cmd = build_command
      stub_client(cmd)
      expect(out).to receive(:success).with(/summarize.*v2.*stable/i)
      cmd.tag('summarize', 'stable')
    end

    it 'outputs JSON when --json is set' do
      cmd = build_json_command
      stub_client(cmd)
      expect(out).to receive(:json).with(tag_result)
      cmd.tag('summarize', 'stable')
    end

    it 'shows error when not found' do
      allow(client).to receive(:tag_prompt).and_return({ error: 'not_found' })
      cmd = build_command
      stub_client(cmd)
      expect(out).to receive(:error).with(/not_found/)
      expect { cmd.tag('missing', 'stable') }.to raise_error(SystemExit)
    end

    it 'passes version option to tag_prompt' do
      cmd = described_class.new([], json: false, no_color: true, verbose: false, version: 3)
      stub_client(cmd)
      expect(client).to receive(:tag_prompt).with(name: 'summarize', tag: 'stable', version: 3).and_return(tag_result)
      cmd.tag('summarize', 'stable')
    end
  end

  describe '#diff' do
    let(:v1_result) { { name: 'summarize', version: 1, template: "line one\nline two" } }
    let(:v2_result) { { name: 'summarize', version: 2, template: "line one\nline three" } }

    before do
      allow(client).to receive(:get_prompt).with(name: 'summarize', version: 1).and_return(v1_result)
      allow(client).to receive(:get_prompt).with(name: 'summarize', version: 2).and_return(v2_result)
    end

    it 'fetches both versions and prints diff' do
      cmd = build_command
      stub_client(cmd)
      output = StringIO.new
      $stdout = output
      cmd.diff('summarize', '1', '2')
      $stdout = STDOUT
      expect(output.string).to include('--- v1')
      expect(output.string).to include('+++ v2')
    end

    it 'outputs JSON when --json is set' do
      cmd = build_json_command
      stub_client(cmd)
      expect(out).to receive(:json).with(hash_including(name: 'summarize', v1: 1, v2: 2))
      cmd.diff('summarize', '1', '2')
    end

    it 'shows error when v1 not found' do
      allow(client).to receive(:get_prompt).with(name: 'summarize', version: 1)
                                           .and_return({ error: 'not_found' })
      cmd = build_command
      stub_client(cmd)
      expect(out).to receive(:error).with(/Version 1/)
      expect { cmd.diff('summarize', '1', '2') }.to raise_error(SystemExit)
    end

    it 'shows error when v2 not found' do
      allow(client).to receive(:get_prompt).with(name: 'summarize', version: 2)
                                           .and_return({ error: 'not_found' })
      cmd = build_command
      stub_client(cmd)
      expect(out).to receive(:error).with(/Version 2/)
      expect { cmd.diff('summarize', '1', '2') }.to raise_error(SystemExit)
    end
  end
end
