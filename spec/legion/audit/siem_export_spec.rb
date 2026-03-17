# frozen_string_literal: true

require 'spec_helper'
require 'legion/audit/siem_export'

RSpec.describe Legion::Audit::SiemExport do
  let(:records) do
    [
      { created_at: '2026-03-16T00:00:00Z', event_type: 'runner_execution',
        principal_id: 'w1', action: 'mcp.run_task', resource: 'task',
        status: 'success', detail: '{}', record_hash: 'abc', previous_hash: '0' * 64 }
    ]
  end

  describe '.export_batch' do
    it 'transforms records to SIEM format' do
      result = described_class.export_batch(records)
      expect(result.size).to eq(1)
      expect(result.first[:source]).to eq('legion')
      expect(result.first[:integrity][:algorithm]).to eq('SHA256')
    end

    it 'handles empty records' do
      expect(described_class.export_batch([])).to eq([])
    end
  end

  describe '.to_ndjson' do
    it 'returns newline-delimited JSON' do
      result = described_class.to_ndjson(records)
      expect(result).to be_a(String)
      expect(result.lines.size).to eq(1)
    end
  end
end
