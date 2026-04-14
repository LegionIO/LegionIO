# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli/fleet_command'

RSpec.describe Legion::CLI::FleetCommand do
  let(:output) { StringIO.new }

  before do
    allow($stdout).to receive(:write) { |str| output.write(str) }
    allow($stdout).to receive(:puts) { |*args| output.puts(*args) }
  end

  def extract_json(str)
    lines = str.lines
    json_line = lines.reverse.find { |l| l.strip.start_with?('{', '[') }
    JSON.parse(json_line, symbolize_names: true)
  end

  describe '.exit_on_failure?' do
    it 'returns true' do
      expect(described_class.exit_on_failure?).to be true
    end
  end

  describe 'command registration' do
    it 'has a status command' do
      expect(described_class.commands).to have_key('status')
    end

    it 'has a pending command' do
      expect(described_class.commands).to have_key('pending')
    end

    it 'has an approve command' do
      expect(described_class.commands).to have_key('approve')
    end

    it 'has an add command' do
      expect(described_class.commands).to have_key('add')
    end

    it 'has a config command' do
      expect(described_class.commands).to have_key('config')
    end
  end

  describe '#status' do
    let(:mock_api_response) do
      {
        queues:           [
          { name: 'lex.assessor.runners.assessor', depth: 3 },
          { name: 'lex.developer.runners.developer', depth: 1 }
        ],
        active_work_items: 4,
        workers:           2
      }
    end

    before do
      allow_any_instance_of(described_class).to receive(:fetch_fleet_status)
        .and_return(mock_api_response)
    end

    it 'displays queue depths' do
      described_class.start(%w[status])
      expect(output.string).to include('assessor')
    end

    context 'with --json' do
      it 'outputs JSON' do
        described_class.start(%w[status --json])
        parsed = extract_json(output.string)
        expect(parsed).to have_key(:queues)
      end
    end
  end

  describe '#pending' do
    let(:mock_pending) do
      [
        { id: 1, work_item_id: 'abc-123', title: 'Fix timeout', source: 'github',
          source_ref: 'LegionIO/lex-exec#42', created_at: '2026-04-12T10:00:00Z' },
        { id: 2, work_item_id: 'def-456', title: 'Add retry', source: 'github',
          source_ref: 'LegionIO/lex-exec#43', created_at: '2026-04-12T11:00:00Z' }
      ]
    end

    before do
      allow_any_instance_of(described_class).to receive(:fetch_pending_approvals)
        .and_return(mock_pending)
    end

    it 'displays pending approvals' do
      described_class.start(%w[pending])
      expect(output.string).to include('Fix timeout')
    end

    context 'with --json' do
      it 'outputs JSON array' do
        described_class.start(%w[pending --json])
        parsed = extract_json(output.string)
        expect(parsed).to be_a(Array)
        expect(parsed.size).to eq(2)
      end
    end
  end

  describe '#approve' do
    let(:mock_result) { { success: true, work_item_id: 'abc-123', resumed: true } }

    before do
      allow_any_instance_of(described_class).to receive(:approve_work_item)
        .and_return(mock_result)
    end

    it 'approves a work item by ID' do
      described_class.start(%w[approve 1])
      expect(output.string).to include('Approved')
    end

    context 'with --json' do
      it 'outputs JSON result' do
        described_class.start(%w[approve 1 --json])
        parsed = extract_json(output.string)
        expect(parsed[:success]).to be true
      end
    end
  end

  describe '#add' do
    let(:mock_result) { { success: true, source: 'github', absorber: 'issues' } }

    before do
      allow_any_instance_of(described_class).to receive(:add_fleet_source)
        .and_return(mock_result)
    end

    it 'adds a source' do
      described_class.start(%w[add github])
      expect(output.string).to include('github')
    end

    context 'with --json' do
      it 'outputs JSON result' do
        described_class.start(%w[add github --json])
        parsed = extract_json(output.string)
        expect(parsed[:source]).to eq('github')
      end
    end
  end
end
