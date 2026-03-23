# frozen_string_literal: true

require 'spec_helper'
require 'thor'
require 'legion/cli/output'
require 'legion/cli/apollo_command'

RSpec.describe Legion::CLI::Apollo do
  let(:mock_http) { instance_double(Net::HTTP) }

  before do
    allow(Net::HTTP).to receive(:new).and_return(mock_http)
    allow(mock_http).to receive(:open_timeout=)
    allow(mock_http).to receive(:read_timeout=)
  end

  describe '#status' do
    let(:response) do
      r = instance_double(Net::HTTPOK)
      allow(r).to receive(:body).and_return(
        JSON.generate({ data: { available: true, data_connected: true } })
      )
      r
    end

    before { allow(mock_http).to receive(:get).and_return(response) }

    it 'outputs Apollo Status header' do
      expect { described_class.start(%w[status --no-color]) }.to output(/Apollo Status/).to_stdout
    end

    it 'shows availability' do
      expect { described_class.start(%w[status --no-color]) }.to output(/true/).to_stdout
    end
  end

  describe '#stats' do
    let(:response) do
      r = instance_double(Net::HTTPOK)
      allow(r).to receive(:body).and_return(
        JSON.generate({ data: { total_entries: 42, recent_24h: 5, avg_confidence: 0.75,
                                by_status: { confirmed: 30, candidate: 12 },
                                by_content_type: { fact: 20, observation: 22 } } })
      )
      r
    end

    before { allow(mock_http).to receive(:get).and_return(response) }

    it 'outputs knowledge graph header' do
      expect { described_class.start(%w[stats --no-color]) }.to output(/Apollo Knowledge Graph/).to_stdout
    end

    it 'shows total entries' do
      expect { described_class.start(%w[stats --no-color]) }.to output(/42/).to_stdout
    end

    it 'shows breakdown by status' do
      expect { described_class.start(%w[stats --no-color]) }.to output(/confirmed/).to_stdout
    end
  end

  describe '#query' do
    let(:response) do
      r = instance_double(Net::HTTPOK)
      allow(r).to receive(:body).and_return(
        JSON.generate({ data: { entries: [{ content: 'Legion uses AMQP', content_type: 'fact',
                                            confidence: 0.9, status: 'confirmed' }] } })
      )
      r
    end

    before do
      allow(mock_http).to receive(:request).and_return(response)
    end

    it 'outputs query results' do
      expect { described_class.start(['query', 'what is legion', '--no-color']) }.to output(/Apollo Query/).to_stdout
    end

    it 'shows entry content' do
      expect { described_class.start(['query', 'what is legion', '--no-color']) }.to output(/AMQP/).to_stdout
    end
  end

  describe '#maintain' do
    let(:response) do
      r = instance_double(Net::HTTPOK)
      allow(r).to receive(:body).and_return(
        JSON.generate({ data: { decayed: 10, archived: 2 } })
      )
      r
    end

    before do
      allow(mock_http).to receive(:request).and_return(response)
    end

    it 'outputs maintenance result' do
      expect { described_class.start(%w[maintain decay_cycle --no-color]) }.to output(/Maintenance/).to_stdout
    end

    it 'shows decayed count' do
      expect { described_class.start(%w[maintain decay_cycle --no-color]) }.to output(/10/).to_stdout
    end
  end
end
