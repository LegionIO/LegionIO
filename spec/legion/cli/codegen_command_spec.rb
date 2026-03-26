# frozen_string_literal: true

require 'spec_helper'
require 'thor'
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
    context 'when SelfGenerate is available' do
      before do
        self_gen = Module.new do
          def self.status
            { enabled: true, last_cycle_at: '2026-03-26T00:00:00Z', gaps_detected: 3 }
          end
        end
        stub_const('Legion::MCP::SelfGenerate', self_gen)
      end

      it 'outputs JSON with data key' do
        output = capture_stdout { described_class.start(%w[status]) }
        parsed = JSON.parse(output, symbolize_names: true)
        expect(parsed[:data]).to be_a(Hash)
      end

      it 'includes enabled status' do
        output = capture_stdout { described_class.start(%w[status]) }
        parsed = JSON.parse(output, symbolize_names: true)
        expect(parsed[:data][:enabled]).to eq(true)
      end

      it 'includes gaps_detected count' do
        output = capture_stdout { described_class.start(%w[status]) }
        parsed = JSON.parse(output, symbolize_names: true)
        expect(parsed[:data][:gaps_detected]).to eq(3)
      end
    end

    context 'when SelfGenerate is not available' do
      before do
        hide_const('Legion::MCP::SelfGenerate')
      end

      it 'outputs error' do
        output = capture_stdout { described_class.start(%w[status]) }
        parsed = JSON.parse(output, symbolize_names: true)
        expect(parsed[:error]).to eq('codegen not available')
      end
    end
  end

  describe '#list' do
    context 'when GeneratedRegistry is available' do
      before do
        registry = Module.new do
          def self.list(status: nil)
            records = [
              { id: 'gen_001', name: 'fetch_weather', status: 'approved' },
              { id: 'gen_002', name: 'parse_csv', status: 'pending' }
            ]
            records = records.select { |r| r[:status] == status } if status
            records
          end
        end
        stub_const('Legion::Extensions::Codegen::Helpers::GeneratedRegistry', registry)
      end

      it 'outputs all records' do
        output = capture_stdout { described_class.start(%w[list]) }
        parsed = JSON.parse(output, symbolize_names: true)
        expect(parsed[:data].size).to eq(2)
      end

      it 'filters by status' do
        output = capture_stdout { described_class.start(%w[list --status approved]) }
        parsed = JSON.parse(output, symbolize_names: true)
        expect(parsed[:data].size).to eq(1)
        expect(parsed[:data].first[:name]).to eq('fetch_weather')
      end
    end

    context 'when GeneratedRegistry is not available' do
      before { hide_const('Legion::Extensions::Codegen::Helpers::GeneratedRegistry') }

      it 'outputs error' do
        output = capture_stdout { described_class.start(%w[list]) }
        parsed = JSON.parse(output, symbolize_names: true)
        expect(parsed[:error]).to eq('codegen registry not available')
      end
    end
  end

  describe '#show' do
    context 'when GeneratedRegistry is available' do
      before do
        registry = Module.new do
          def self.get(id:)
            return { id: id, name: 'fetch_weather', status: 'approved' } if id == 'gen_001'

            nil
          end
        end
        stub_const('Legion::Extensions::Codegen::Helpers::GeneratedRegistry', registry)
      end

      it 'returns the record for a valid id' do
        output = capture_stdout { described_class.start(%w[show gen_001]) }
        parsed = JSON.parse(output, symbolize_names: true)
        expect(parsed[:data][:id]).to eq('gen_001')
        expect(parsed[:data][:name]).to eq('fetch_weather')
      end

      it 'returns error for unknown id' do
        output = capture_stdout { described_class.start(%w[show nonexistent]) }
        parsed = JSON.parse(output, symbolize_names: true)
        expect(parsed[:error]).to eq('not found')
      end
    end

    context 'when GeneratedRegistry is not available' do
      before { hide_const('Legion::Extensions::Codegen::Helpers::GeneratedRegistry') }

      it 'outputs error' do
        output = capture_stdout { described_class.start(%w[show gen_001]) }
        parsed = JSON.parse(output, symbolize_names: true)
        expect(parsed[:error]).to eq('codegen registry not available')
      end
    end
  end

  describe '#approve' do
    context 'when ReviewHandler is available' do
      before do
        handler = Module.new do
          def self.handle_verdict(review:)
            { generation_id: review[:generation_id], status: 'approved' }
          end
        end
        stub_const('Legion::Extensions::Codegen::Runners::ReviewHandler', handler)
      end

      it 'calls handle_verdict with approve and returns result' do
        output = capture_stdout { described_class.start(%w[approve gen_001]) }
        parsed = JSON.parse(output, symbolize_names: true)
        expect(parsed[:data][:status]).to eq('approved')
        expect(parsed[:data][:generation_id]).to eq('gen_001')
      end
    end

    context 'when ReviewHandler is not available' do
      before { hide_const('Legion::Extensions::Codegen::Runners::ReviewHandler') }

      it 'outputs error' do
        output = capture_stdout { described_class.start(%w[approve gen_001]) }
        parsed = JSON.parse(output, symbolize_names: true)
        expect(parsed[:error]).to eq('review handler not available')
      end
    end
  end

  describe '#reject' do
    context 'when GeneratedRegistry is available' do
      before do
        registry = Module.new do
          def self.update_status(id:, status:)
            { id: id, status: status }
          end
        end
        stub_const('Legion::Extensions::Codegen::Helpers::GeneratedRegistry', registry)
      end

      it 'updates status to rejected' do
        output = capture_stdout { described_class.start(%w[reject gen_001]) }
        parsed = JSON.parse(output, symbolize_names: true)
        expect(parsed[:data][:id]).to eq('gen_001')
        expect(parsed[:data][:status]).to eq('rejected')
      end
    end

    context 'when GeneratedRegistry is not available' do
      before { hide_const('Legion::Extensions::Codegen::Helpers::GeneratedRegistry') }

      it 'outputs error' do
        output = capture_stdout { described_class.start(%w[reject gen_001]) }
        parsed = JSON.parse(output, symbolize_names: true)
        expect(parsed[:error]).to eq('codegen registry not available')
      end
    end
  end

  describe '#retry' do
    context 'when GeneratedRegistry is available' do
      before do
        registry = Module.new do
          def self.update_status(id:, status:)
            { id: id, status: status }
          end
        end
        stub_const('Legion::Extensions::Codegen::Helpers::GeneratedRegistry', registry)
      end

      it 'updates status to pending' do
        output = capture_stdout { described_class.start(%w[retry gen_001]) }
        parsed = JSON.parse(output, symbolize_names: true)
        expect(parsed[:data][:id]).to eq('gen_001')
        expect(parsed[:data][:status]).to eq('pending')
      end
    end

    context 'when GeneratedRegistry is not available' do
      before { hide_const('Legion::Extensions::Codegen::Helpers::GeneratedRegistry') }

      it 'outputs error' do
        output = capture_stdout { described_class.start(%w[retry gen_001]) }
        parsed = JSON.parse(output, symbolize_names: true)
        expect(parsed[:error]).to eq('codegen registry not available')
      end
    end
  end

  describe '#gaps' do
    context 'when GapDetector is available' do
      before do
        detector = Module.new do
          def self.detect_gaps
            [
              { gap_id: 'gap_1', gap_type: :unmatched_intent, intent: 'fetch weather', priority: 0.8 },
              { gap_id: 'gap_2', gap_type: :frequent_failure, intent: 'parse csv', priority: 0.6 }
            ]
          end
        end
        stub_const('Legion::MCP::GapDetector', detector)
      end

      it 'outputs detected gaps' do
        output = capture_stdout { described_class.start(%w[gaps]) }
        parsed = JSON.parse(output, symbolize_names: true)
        expect(parsed[:data].size).to eq(2)
      end

      it 'includes gap details' do
        output = capture_stdout { described_class.start(%w[gaps]) }
        parsed = JSON.parse(output, symbolize_names: true)
        expect(parsed[:data].first[:gap_id]).to eq('gap_1')
      end
    end

    context 'when GapDetector is not available' do
      before { hide_const('Legion::MCP::GapDetector') }

      it 'outputs error' do
        output = capture_stdout { described_class.start(%w[gaps]) }
        parsed = JSON.parse(output, symbolize_names: true)
        expect(parsed[:error]).to eq('gap detector not available')
      end
    end
  end

  describe '#cycle' do
    context 'when SelfGenerate is available' do
      before do
        self_gen = Module.new do
          def self.run_cycle
            { triggered: true, gaps_processed: 2 }
          end
        end
        stub_const('Legion::MCP::SelfGenerate', self_gen)
        allow(Legion::MCP::SelfGenerate).to receive(:instance_variable_set)
      end

      it 'triggers a cycle and returns result' do
        output = capture_stdout { described_class.start(%w[cycle]) }
        parsed = JSON.parse(output, symbolize_names: true)
        expect(parsed[:data][:triggered]).to eq(true)
        expect(parsed[:data][:gaps_processed]).to eq(2)
      end

      it 'resets cooldown before running' do
        expect(Legion::MCP::SelfGenerate).to receive(:instance_variable_set).with(:@last_cycle_at, nil)
        capture_stdout { described_class.start(%w[cycle]) }
      end
    end

    context 'when SelfGenerate is not available' do
      before { hide_const('Legion::MCP::SelfGenerate') }

      it 'outputs error' do
        output = capture_stdout { described_class.start(%w[cycle]) }
        parsed = JSON.parse(output, symbolize_names: true)
        expect(parsed[:error]).to eq('self_generate not available')
      end
    end
  end
end
