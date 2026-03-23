# frozen_string_literal: true

require 'spec_helper'
require 'thor'
require 'tmpdir'
require 'json'
require 'legion/cli/output'
require 'legion/cli/error'
require 'legion/cli/chat/subagent'
require 'legion/cli/swarm_command'

RSpec.describe Legion::CLI::Swarm do
  let(:tmpdir) { Dir.mktmpdir('swarm-test') }
  let(:workflow_dir) { File.join(tmpdir, '.legion', 'swarms') }

  let(:workflow) do
    {
      'name'     => 'test-flow',
      'goal'     => 'Analyze and improve the auth module',
      'agents'   => [
        { 'role' => 'researcher', 'description' => 'Analyze codebase', 'tools' => %w[read search], 'model' => 'claude-sonnet' },
        { 'role' => 'planner', 'description' => 'Create implementation plan', 'tools' => %w[write], 'model' => nil }
      ],
      'pipeline' => %w[researcher planner]
    }
  end

  before do
    FileUtils.mkdir_p(workflow_dir)
    File.write(File.join(workflow_dir, 'test-flow.json'), JSON.pretty_generate(workflow))
    allow(Dir).to receive(:pwd).and_return(tmpdir)
  end

  after { FileUtils.rm_rf(tmpdir) }

  describe '#list' do
    it 'shows workflow count' do
      expect { described_class.start(%w[list --no-color]) }.to output(/Swarm Workflows \(1\)/).to_stdout
    end

    it 'shows workflow name and goal' do
      expect { described_class.start(%w[list --no-color]) }.to output(/test-flow.*Analyze/).to_stdout
    end

    context 'when no workflow directory exists' do
      before { FileUtils.rm_rf(workflow_dir) }

      it 'shows warning' do
        expect { described_class.start(%w[list --no-color]) }.to output(/No workflows found/).to_stdout
      end
    end

    context 'when directory is empty' do
      before { FileUtils.rm(File.join(workflow_dir, 'test-flow.json')) }

      it 'shows warning' do
        expect { described_class.start(%w[list --no-color]) }.to output(/No workflow files found/).to_stdout
      end
    end
  end

  describe '#show' do
    it 'shows workflow header' do
      expect { described_class.start(%w[show test-flow --no-color]) }.to output(/Workflow: test-flow/).to_stdout
    end

    it 'shows goal' do
      expect { described_class.start(%w[show test-flow --no-color]) }.to output(/Analyze and improve/).to_stdout
    end

    it 'shows agents with roles' do
      expect { described_class.start(%w[show test-flow --no-color]) }.to output(/researcher/).to_stdout
    end

    it 'shows pipeline' do
      expect { described_class.start(%w[show test-flow --no-color]) }.to output(/researcher -> planner/).to_stdout
    end

    it 'outputs JSON when requested' do
      output = capture_stdout { described_class.start(%w[show test-flow --json --no-color]) }
      parsed = JSON.parse(output, symbolize_names: true)
      expect(parsed[:name]).to eq('test-flow')
      expect(parsed[:agents].length).to eq(2)
    end

    context 'with nonexistent workflow' do
      it 'raises error' do
        expect { described_class.start(%w[show nonexistent --no-color]) }.to raise_error(Legion::CLI::Error, /Workflow not found/)
      end
    end
  end

  describe '#start' do
    before do
      allow(Legion::CLI::Chat::Subagent).to receive(:run_headless).and_return(
        { exit_code: 0, output: 'Agent output here' }
      )
    end

    it 'shows swarm header' do
      expect { described_class.start(%w[start test-flow --no-color]) }.to output(/Swarm: test-flow/).to_stdout
    end

    it 'shows step progress' do
      expect { described_class.start(%w[start test-flow --no-color]) }.to output(%r{Step 1/2: researcher}).to_stdout
    end

    it 'shows completion' do
      expect { described_class.start(%w[start test-flow --no-color]) }.to output(/Swarm Complete/).to_stdout
    end

    it 'calls subagent for each pipeline step' do
      described_class.start(%w[start test-flow --no-color])
      expect(Legion::CLI::Chat::Subagent).to have_received(:run_headless).twice
    end

    context 'when a step fails' do
      before do
        allow(Legion::CLI::Chat::Subagent).to receive(:run_headless).and_return(
          { exit_code: 1, error: 'model unavailable' }
        )
      end

      it 'shows error and stops pipeline' do
        expect { described_class.start(%w[start test-flow --no-color]) }.to output(/researcher failed/).to_stdout
      end

      it 'does not run subsequent steps' do
        described_class.start(%w[start test-flow --no-color])
        expect(Legion::CLI::Chat::Subagent).to have_received(:run_headless).once
      end
    end
  end

  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end
end
