# frozen_string_literal: true

require 'spec_helper'
require 'thor'
require 'legion/cli/output'
require 'legion/cli/codegen_command'

RSpec.describe Legion::CLI::CodegenCommand do
  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end

  describe '#status' do
    it 'calls api_get and outputs JSON' do
      allow_any_instance_of(described_class).to receive(:api_get)
        .with('/api/codegen/status')
        .and_return({ enabled: true, last_cycle_at: '2026-03-26T00:00:00Z', gaps_detected: 3 })
      output = capture_stdout { described_class.start(%w[status --json]) }
      parsed = JSON.parse(output, symbolize_names: true)
      expect(parsed[:enabled]).to eq(true)
    end

    it 'includes gaps_detected count' do
      allow_any_instance_of(described_class).to receive(:api_get)
        .with('/api/codegen/status')
        .and_return({ enabled: true, gaps_detected: 3 })
      output = capture_stdout { described_class.start(%w[status --json]) }
      parsed = JSON.parse(output, symbolize_names: true)
      expect(parsed[:gaps_detected]).to eq(3)
    end
  end

  describe '#list' do
    it 'calls api_get and outputs all records' do
      allow_any_instance_of(described_class).to receive(:api_get)
        .with('/api/codegen/generated')
        .and_return([
                      { id: 'gen_001', name: 'fetch_weather', status: 'approved' },
                      { id: 'gen_002', name: 'parse_csv', status: 'pending' }
                    ])
      output = capture_stdout { described_class.start(%w[list --json]) }
      parsed = JSON.parse(output, symbolize_names: true)
      expect(parsed.size).to eq(2)
    end

    it 'passes status filter as query param' do
      expect_any_instance_of(described_class).to receive(:api_get)
        .with('/api/codegen/generated?status=approved')
        .and_return([{ id: 'gen_001', name: 'fetch_weather', status: 'approved' }])
      capture_stdout { described_class.start(%w[list --status approved --json]) }
    end
  end

  describe '#show' do
    it 'calls api_get with the record id' do
      allow_any_instance_of(described_class).to receive(:api_get)
        .with('/api/codegen/generated/gen_001')
        .and_return({ id: 'gen_001', name: 'fetch_weather', status: 'approved' })
      output = capture_stdout { described_class.start(%w[show gen_001 --json]) }
      parsed = JSON.parse(output, symbolize_names: true)
      expect(parsed[:id]).to eq('gen_001')
      expect(parsed[:name]).to eq('fetch_weather')
    end
  end

  describe '#approve' do
    it 'calls api_post to approve endpoint' do
      allow_any_instance_of(described_class).to receive(:api_post)
        .with('/api/codegen/generated/gen_001/approve')
        .and_return({ generation_id: 'gen_001', status: 'approved' })
      output = capture_stdout { described_class.start(%w[approve gen_001 --json]) }
      parsed = JSON.parse(output, symbolize_names: true)
      expect(parsed[:status]).to eq('approved')
    end
  end

  describe '#reject' do
    it 'calls api_post to reject endpoint' do
      allow_any_instance_of(described_class).to receive(:api_post)
        .with('/api/codegen/generated/gen_001/reject')
        .and_return({ id: 'gen_001', status: 'rejected' })
      output = capture_stdout { described_class.start(%w[reject gen_001 --json]) }
      parsed = JSON.parse(output, symbolize_names: true)
      expect(parsed[:status]).to eq('rejected')
    end
  end

  describe '#retry' do
    it 'calls api_post to retry endpoint' do
      allow_any_instance_of(described_class).to receive(:api_post)
        .with('/api/codegen/generated/gen_001/retry')
        .and_return({ id: 'gen_001', status: 'pending' })
      output = capture_stdout { described_class.start(%w[retry gen_001 --json]) }
      parsed = JSON.parse(output, symbolize_names: true)
      expect(parsed[:status]).to eq('pending')
    end
  end

  describe '#gaps' do
    it 'calls api_get and outputs detected gaps' do
      allow_any_instance_of(described_class).to receive(:api_get)
        .with('/api/codegen/gaps')
        .and_return([
                      { gap_id: 'gap_1', gap_type: 'unmatched_intent', priority: 0.8 },
                      { gap_id: 'gap_2', gap_type: 'frequent_failure', priority: 0.6 }
                    ])
      output = capture_stdout { described_class.start(%w[gaps --json]) }
      parsed = JSON.parse(output, symbolize_names: true)
      expect(parsed.size).to eq(2)
    end

    it 'includes gap details' do
      allow_any_instance_of(described_class).to receive(:api_get)
        .with('/api/codegen/gaps')
        .and_return([{ gap_id: 'gap_1', gap_type: 'unmatched_intent', priority: 0.8 }])
      output = capture_stdout { described_class.start(%w[gaps --json]) }
      parsed = JSON.parse(output, symbolize_names: true)
      expect(parsed.first[:gap_id]).to eq('gap_1')
    end
  end

  describe '#cycle' do
    it 'calls api_post to cycle endpoint' do
      allow_any_instance_of(described_class).to receive(:api_post)
        .with('/api/codegen/cycle')
        .and_return({ triggered: true, gaps_processed: 2 })
      output = capture_stdout { described_class.start(%w[cycle --json]) }
      parsed = JSON.parse(output, symbolize_names: true)
      expect(parsed[:triggered]).to eq(true)
      expect(parsed[:gaps_processed]).to eq(2)
    end
  end
end
