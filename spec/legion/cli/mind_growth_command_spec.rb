# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli/error'
require 'legion/cli/output'
require 'legion/cli/mind_growth_command'

RSpec.describe Legion::CLI::MindGrowth do
  let(:client) { instance_double(Legion::Extensions::MindGrowth::Client) }

  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end

  before do
    stub_const('Legion::Extensions::MindGrowth::Runners::Proposer', Module.new do
      def self.get_proposal_object(_id); end
    end)
    allow(Legion::Extensions::MindGrowth::Client).to receive(:new).and_return(client)
  end

  describe '#status' do
    let(:result) { { success: true, proposals: 3, coverage: 0.72 } }

    before { allow(client).to receive(:growth_status).and_return(result) }

    it 'renders the status header' do
      output = capture_stdout { described_class.start(%w[status --no-color]) }
      expect(output).to include('Mind-Growth Status')
    end

    it 'outputs JSON when --json is passed' do
      output = capture_stdout { described_class.start(%w[status --json]) }
      parsed = JSON.parse(output, symbolize_names: true)
      expect(parsed[:success]).to eq(true)
    end
  end

  describe '#propose' do
    let(:proposal_id) { 'abc12345-0000-0000-0000-000000000000' }

    context 'when proposal succeeds' do
      let(:result) { { success: true, proposal: { id: proposal_id } } }

      before { allow(client).to receive(:propose_concept).and_return(result) }

      it 'shows a success message with proposal id' do
        output = capture_stdout { described_class.start(%w[propose --no-color]) }
        expect(output).to include('Proposal created')
        expect(output).to include(proposal_id)
      end

      it 'outputs JSON when --json is passed' do
        output = capture_stdout { described_class.start(%w[propose --json]) }
        parsed = JSON.parse(output, symbolize_names: true)
        expect(parsed[:success]).to eq(true)
      end

      it 'forwards --category as symbol' do
        expect(client).to receive(:propose_concept).with(
          hash_including(category: :cognition)
        ).and_return(result)
        capture_stdout { described_class.start(%w[propose --category cognition --no-color]) }
      end
    end

    context 'when proposal is rejected as redundant' do
      let(:result) { { success: false, error: :redundant } }

      before { allow(client).to receive(:propose_concept).and_return(result) }

      it 'shows a warning' do
        output = capture_stdout { described_class.start(%w[propose --no-color]) }
        expect(output).to include('redundant')
      end
    end
  end

  describe '#approve' do
    let(:proposal_id) { 'deadbeef-0000-0000-0000-000000000000' }

    context 'when approved' do
      let(:result) { { success: true, approved: true, auto_approved: false } }

      before { allow(client).to receive(:evaluate_proposal).with(proposal_id: proposal_id).and_return(result) }

      it 'shows approval status' do
        output = capture_stdout { described_class.start(['approve', proposal_id, '--no-color']) }
        expect(output).to include('approved')
      end

      it 'truncates id to 8 chars in output' do
        output = capture_stdout { described_class.start(['approve', proposal_id, '--no-color']) }
        expect(output).to include('deadbeef')
      end

      it 'outputs JSON when --json is passed' do
        output = capture_stdout { described_class.start(['approve', proposal_id, '--json']) }
        parsed = JSON.parse(output, symbolize_names: true)
        expect(parsed[:success]).to eq(true)
      end
    end
  end

  describe '#reject_proposal' do
    let(:proposal_id) { 'feedcafe-0000-0000-0000-000000000000' }

    context 'when proposal exists' do
      let(:fake_proposal) do
        obj = Object.new
        def obj.transition!(status); end
        obj
      end

      before do
        allow(Legion::Extensions::MindGrowth::Runners::Proposer)
          .to receive(:get_proposal_object).with(proposal_id).and_return(fake_proposal)
      end

      it 'transitions proposal to rejected' do
        expect(fake_proposal).to receive(:transition!).with(:rejected)
        capture_stdout { described_class.start(['reject', proposal_id, '--no-color']) }
      end

      it 'shows success message' do
        allow(fake_proposal).to receive(:transition!)
        output = capture_stdout { described_class.start(['reject', proposal_id, '--no-color']) }
        expect(output).to include('rejected')
      end

      it 'outputs JSON when --json is passed' do
        allow(fake_proposal).to receive(:transition!)
        output = capture_stdout { described_class.start(['reject', proposal_id, '--json']) }
        parsed = JSON.parse(output, symbolize_names: true)
        expect(parsed[:success]).to eq(true)
        expect(parsed[:status]).to eq('rejected')
      end
    end

    context 'when proposal is not found' do
      before do
        allow(Legion::Extensions::MindGrowth::Runners::Proposer)
          .to receive(:get_proposal_object).with(proposal_id).and_return(nil)
      end

      it 'shows a not-found warning' do
        output = capture_stdout { described_class.start(['reject', proposal_id, '--no-color']) }
        expect(output).to include('not found')
      end
    end
  end

  describe '#build' do
    let(:proposal_id) { 'b00b1e00-0000-0000-0000-000000000000' }

    context 'when build succeeds' do
      let(:result) { { success: true, pipeline: { stage: 'scaffold', status: :running } } }

      before { allow(client).to receive(:build_extension).with(proposal_id: proposal_id).and_return(result) }

      it 'shows build started message' do
        output = capture_stdout { described_class.start(['build', proposal_id, '--no-color']) }
        expect(output).to include('Build pipeline started')
      end

      it 'outputs JSON when --json is passed' do
        output = capture_stdout { described_class.start(['build', proposal_id, '--json']) }
        parsed = JSON.parse(output, symbolize_names: true)
        expect(parsed[:success]).to eq(true)
      end
    end

    context 'when build fails' do
      let(:result) { { success: false, error: 'proposal not approved' } }

      before { allow(client).to receive(:build_extension).with(proposal_id: proposal_id).and_return(result) }

      it 'shows failure warning' do
        output = capture_stdout { described_class.start(['build', proposal_id, '--no-color']) }
        expect(output).to include('Build failed')
      end
    end
  end

  describe '#proposals' do
    let(:result) do
      {
        success:   true,
        proposals: [
          { id: 'aabbccdd-1111-0000-0000-000000000000', name: 'attention_gate',
            category: :cognition, status: :approved, created_at: '2026-03-24' },
          { id: 'eeff0011-2222-0000-0000-000000000000', name: 'belief_updater',
            category: :inference, status: :proposed, created_at: '2026-03-23' }
        ],
        count:     2
      }
    end

    before { allow(client).to receive(:list_proposals).and_return(result) }

    it 'renders a table with proposal names' do
      output = capture_stdout { described_class.start(%w[proposals --no-color]) }
      expect(output).to include('attention_gate')
      expect(output).to include('belief_updater')
    end

    it 'truncates ids to 8 chars in table' do
      output = capture_stdout { described_class.start(%w[proposals --no-color]) }
      expect(output).to include('aabbccdd')
      expect(output).not_to include('aabbccdd-1111')
    end

    it 'outputs JSON when --json is passed' do
      output = capture_stdout { described_class.start(%w[proposals --json]) }
      parsed = JSON.parse(output, symbolize_names: true)
      expect(parsed[:proposals]).to be_an(Array)
      expect(parsed[:proposals].size).to eq(2)
    end

    it 'shows warning when no proposals found' do
      allow(client).to receive(:list_proposals).and_return({ success: true, proposals: [], count: 0 })
      output = capture_stdout { described_class.start(%w[proposals --no-color]) }
      expect(output).to include('No proposals found')
    end

    it 'forwards --status as symbol' do
      expect(client).to receive(:list_proposals).with(hash_including(status: :approved)).and_return(result)
      capture_stdout { described_class.start(%w[proposals --status approved --no-color]) }
    end
  end

  describe '#profile' do
    let(:result) do
      {
        success:          true,
        total_extensions: 8,
        overall_coverage: 0.65,
        model_coverage:   {
          global_workspace: { coverage: 0.8, missing: %w[broadcasting] },
          free_energy:      { coverage: 0.5, missing: %w[prediction free_energy] }
        }
      }
    end

    before { allow(client).to receive(:cognitive_profile).and_return(result) }

    it 'renders the profile header' do
      output = capture_stdout { described_class.start(%w[profile --no-color]) }
      expect(output).to include('Cognitive Architecture Profile')
    end

    it 'shows total extensions' do
      output = capture_stdout { described_class.start(%w[profile --no-color]) }
      expect(output).to include('8')
    end

    it 'outputs JSON when --json is passed' do
      output = capture_stdout { described_class.start(%w[profile --json]) }
      parsed = JSON.parse(output, symbolize_names: true)
      expect(parsed[:total_extensions]).to eq(8)
    end
  end

  describe '#health' do
    let(:result) do
      {
        success:                true,
        ranked:                 [
          { name: 'lex-attention', fitness: 0.87 },
          { name: 'lex-memory',    fitness: 0.54 }
        ],
        prune_candidates:       [],
        improvement_candidates: []
      }
    end

    before { allow(client).to receive(:validate_fitness).with(extensions: []).and_return(result) }

    it 'renders the fitness header' do
      output = capture_stdout { described_class.start(%w[health --no-color]) }
      expect(output).to include('Extension Fitness')
    end

    it 'shows extension names and fitness scores' do
      output = capture_stdout { described_class.start(%w[health --no-color]) }
      expect(output).to include('lex-attention')
      expect(output).to include('0.870')
    end

    it 'outputs JSON when --json is passed' do
      output = capture_stdout { described_class.start(%w[health --json]) }
      parsed = JSON.parse(output, symbolize_names: true)
      expect(parsed[:ranked]).to be_an(Array)
    end
  end

  describe '#report' do
    let(:result) do
      { success: true, total_cycles: 5, proposals_created: 12, extensions_built: 3 }
    end

    before { allow(client).to receive(:session_report).and_return(result) }

    it 'renders the report header' do
      output = capture_stdout { described_class.start(%w[report --no-color]) }
      expect(output).to include('Mind-Growth Report')
    end

    it 'outputs JSON when --json is passed' do
      output = capture_stdout { described_class.start(%w[report --json]) }
      parsed = JSON.parse(output, symbolize_names: true)
      expect(parsed[:total_cycles]).to eq(5)
    end
  end

  describe '#history' do
    let(:result) do
      {
        success:   true,
        proposals: [
          { id: 'cafe1234-0000-0000-0000-000000000000', name: 'somatic_gate',
            category: :affect, status: :active, created_at: '2026-03-22' }
        ],
        count:     1
      }
    end

    before { allow(client).to receive(:list_proposals).and_return(result) }

    it 'renders proposal history table' do
      output = capture_stdout { described_class.start(%w[history --no-color]) }
      expect(output).to include('somatic_gate')
    end

    it 'defaults to limit 50' do
      expect(client).to receive(:list_proposals).with(hash_including(limit: 50)).and_return(result)
      capture_stdout { described_class.start(%w[history --no-color]) }
    end

    it 'outputs JSON when --json is passed' do
      output = capture_stdout { described_class.start(%w[history --json]) }
      parsed = JSON.parse(output, symbolize_names: true)
      expect(parsed[:proposals]).to be_an(Array)
    end
  end

  describe 'extension guard' do
    before { hide_const('Legion::Extensions::MindGrowth') }

    it 'raises CLI::Error when extension is not loaded' do
      cli = described_class.new([], {})
      expect { cli.status }.to raise_error(Legion::CLI::Error, /lex-mind-growth/)
    end
  end
end
