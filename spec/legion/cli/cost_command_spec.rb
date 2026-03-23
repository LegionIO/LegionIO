# frozen_string_literal: true

require 'spec_helper'
require 'thor'
require 'legion/cli/cost_command'
require 'legion/cli/cost/data_client'

RSpec.describe Legion::CLI::Cost do
  let(:mock_client) { instance_double(Legion::CLI::CostData::Client) }

  before do
    allow(Legion::CLI::CostData::Client).to receive(:new).and_return(mock_client)
  end

  describe '#summary' do
    before do
      allow(mock_client).to receive(:summary).and_return(
        { today: 12.50, week: 87.30, month: 342.15, workers: 5 }
      )
    end

    it 'shows cost summary header' do
      expect { described_class.start(%w[summary]) }.to output(/Cost Summary/).to_stdout
    end

    it 'shows today cost' do
      expect { described_class.start(%w[summary]) }.to output(/\$12\.50/).to_stdout
    end

    it 'shows week cost' do
      expect { described_class.start(%w[summary]) }.to output(/\$87\.30/).to_stdout
    end

    it 'shows month cost' do
      expect { described_class.start(%w[summary]) }.to output(/\$342\.15/).to_stdout
    end

    it 'shows worker count' do
      expect { described_class.start(%w[summary]) }.to output(/5/).to_stdout
    end
  end

  describe '#worker' do
    context 'with cost data' do
      before do
        allow(mock_client).to receive(:worker_cost).and_return(
          { total_cost_usd: 45.00, total_tokens: 150_000, tasks_completed: 23 }
        )
      end

      it 'shows worker header' do
        expect { described_class.start(%w[worker w-001]) }.to output(/Worker: w-001/).to_stdout
      end

      it 'shows cost fields' do
        expect { described_class.start(%w[worker w-001]) }.to output(/total_cost_usd/).to_stdout
      end
    end

    context 'with no data' do
      before do
        allow(mock_client).to receive(:worker_cost).and_return({})
      end

      it 'shows no data message' do
        expect { described_class.start(%w[worker w-001]) }.to output(/No cost data/).to_stdout
      end
    end
  end

  describe '#top' do
    context 'with consumers' do
      before do
        allow(mock_client).to receive(:top_consumers).and_return([
                                                                   { worker_id: 'w-alpha', cost: { total_cost_usd: 120.0 } },
                                                                   { worker_id: 'w-beta', cost: { total_cost_usd: 45.0 } }
                                                                 ])
      end

      it 'shows header' do
        expect { described_class.start(%w[top]) }.to output(/Top Cost Consumers/).to_stdout
      end

      it 'shows ranked consumers' do
        expect { described_class.start(%w[top]) }.to output(/1\..*w-alpha/).to_stdout
      end

      it 'shows cost amounts' do
        expect { described_class.start(%w[top]) }.to output(/\$120\.00/).to_stdout
      end
    end

    context 'with no data' do
      before do
        allow(mock_client).to receive(:top_consumers).and_return([])
      end

      it 'shows no data message' do
        expect { described_class.start(%w[top]) }.to output(/No cost data/).to_stdout
      end
    end
  end

  describe '#export' do
    before do
      allow(mock_client).to receive(:summary).and_return(
        { today: 10.0, week: 50.0, month: 200.0, workers: 3 }
      )
    end

    it 'outputs JSON by default' do
      expect { described_class.start(%w[export]) }.to output(/today/).to_stdout
    end

    it 'outputs CSV when requested' do
      expect { described_class.start(%w[export --format csv]) }.to output(/period,today,week,month,workers/).to_stdout
    end

    it 'includes data values in CSV' do
      expect { described_class.start(%w[export --format csv]) }.to output(/month,10\.0,50\.0,200\.0,3/).to_stdout
    end
  end
end
