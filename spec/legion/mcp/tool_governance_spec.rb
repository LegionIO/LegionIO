# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp/tool_governance'

RSpec.describe Legion::MCP::ToolGovernance do
  before { allow(Legion::Settings).to receive(:dig).and_return(nil) }

  let(:low_tool) { double('tool', tool_name: 'legion.list_tasks') }
  let(:high_tool) { double('tool', tool_name: 'legion.worker_lifecycle') }
  let(:medium_tool) { double('tool', tool_name: 'legion.run_task') }

  describe '.filter_tools' do
    context 'when governance is disabled' do
      it 'returns all tools unfiltered' do
        tools = [low_tool, high_tool, medium_tool]
        expect(described_class.filter_tools(tools, nil)).to eq(tools)
      end
    end

    context 'when governance is enabled' do
      before do
        allow(Legion::Settings).to receive(:dig).with(:mcp, :governance, :enabled).and_return(true)
        allow(Legion::Settings).to receive(:dig).with(:mcp, :governance, :tool_risk_tiers).and_return({})
      end

      it 'filters tools for low-tier identity' do
        identity = { risk_tier: :low }
        result = described_class.filter_tools([low_tool, high_tool, medium_tool], identity)
        expect(result).to contain_exactly(low_tool)
      end

      it 'allows medium tools for medium-tier identity' do
        identity = { risk_tier: :medium }
        result = described_class.filter_tools([low_tool, high_tool, medium_tool], identity)
        expect(result).to contain_exactly(low_tool, medium_tool)
      end

      it 'allows all tools for high-tier identity' do
        identity = { risk_tier: :high }
        result = described_class.filter_tools([low_tool, high_tool, medium_tool], identity)
        expect(result).to contain_exactly(low_tool, high_tool, medium_tool)
      end

      it 'defaults to low tier for nil identity' do
        result = described_class.filter_tools([low_tool, high_tool], nil)
        expect(result).to contain_exactly(low_tool)
      end
    end
  end

  describe '.audit_invocation' do
    it 'does nothing when audit is disabled' do
      allow(Legion::Settings).to receive(:dig).with(:mcp, :governance, :audit_invocations).and_return(false)
      expect { described_class.audit_invocation(tool_name: 'test', identity: nil, params: {}, result: {}) }
        .not_to raise_error
    end
  end

  describe '.governance_enabled?' do
    it 'returns false by default' do
      expect(described_class.governance_enabled?).to be false
    end

    it 'returns true when enabled' do
      allow(Legion::Settings).to receive(:dig).with(:mcp, :governance, :enabled).and_return(true)
      expect(described_class.governance_enabled?).to be true
    end
  end
end
