# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli/output'
require 'legion/workflow/loader'
require 'legion/cli/fleet_setup'

RSpec.describe Legion::CLI::FleetSetup do
  let(:output) { StringIO.new }
  let(:formatter) { instance_double(Legion::CLI::Output::Formatter) }

  before do
    allow(formatter).to receive(:header)
    allow(formatter).to receive(:success)
    allow(formatter).to receive(:error)
    allow(formatter).to receive(:warn)
    allow(formatter).to receive(:spacer)
    allow(formatter).to receive(:json)
  end

  describe '.fleet_gems' do
    it 'includes the four pipeline extensions' do
      expect(described_class.fleet_gems).to include(
        'lex-assessor', 'lex-planner', 'lex-developer', 'lex-validator'
      )
    end

    it 'includes supporting tool extensions' do
      expect(described_class.fleet_gems).to include(
        'lex-codegen', 'lex-eval', 'lex-exec'
      )
    end

    it 'includes orchestration extensions' do
      expect(described_class.fleet_gems).to include(
        'lex-tasker', 'lex-conditioner', 'lex-transformer'
      )
    end
  end

  describe '.manifest_path' do
    it 'points to the fleet manifest YAML' do
      expect(described_class.manifest_path).to end_with('fleet/manifest.yml')
    end

    it 'references an existing file' do
      expect(File.exist?(described_class.manifest_path)).to be true
    end
  end

  describe '#phase1_install' do
    subject(:setup) { described_class.new(formatter: formatter, options: { json: false }) }

    before do
      allow(setup).to receive(:install_gems).and_return({ installed: 7, failed: 0 })
    end

    it 'installs fleet gems' do
      expect(setup).to receive(:install_gems)
      setup.phase1_install
    end

    it 'returns success when all gems install' do
      result = setup.phase1_install
      expect(result[:success]).to be true
    end
  end

  describe '#phase2_wire' do
    subject(:setup) { described_class.new(formatter: formatter, options: { json: false }) }

    let(:mock_loader) { instance_double(Legion::Workflow::Loader) }

    before do
      allow(Legion::Workflow::Loader).to receive(:new).and_return(mock_loader)
      allow(mock_loader).to receive(:install).and_return({
        success: true, chain_id: 1, relationship_ids: (1..10).to_a
      })
      allow(setup).to receive(:seed_conditioner_rules).and_return({ success: true })
      allow(setup).to receive(:register_settings).and_return({ success: true })
      allow(setup).to receive(:apply_planner_timeout_policy)
    end

    it 'installs the manifest via Workflow::Loader' do
      expect(mock_loader).to receive(:install)
      setup.phase2_wire
    end

    it 'seeds conditioner rules' do
      expect(setup).to receive(:seed_conditioner_rules)
      setup.phase2_wire
    end

    it 'registers fleet settings via load_module_settings' do
      expect(setup).to receive(:register_settings)
      setup.phase2_wire
    end

    it 'applies planner timeout policy' do
      expect(setup).to receive(:apply_planner_timeout_policy)
      setup.phase2_wire
    end

    it 'returns success with chain_id and relationship count' do
      result = setup.phase2_wire
      expect(result[:success]).to be true
      expect(result[:chain_id]).to eq(1)
      expect(result[:relationships]).to eq(10)
    end
  end
end
