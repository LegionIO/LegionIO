# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli/chat/tools/knowledge_maintenance'

RSpec.describe Legion::CLI::Chat::Tools::KnowledgeMaintenance do
  subject(:tool) { described_class.new }

  let(:mock_http) { instance_double(Net::HTTP) }

  before do
    allow(Net::HTTP).to receive(:new).and_return(mock_http)
    allow(mock_http).to receive(:open_timeout=)
    allow(mock_http).to receive(:read_timeout=)
  end

  describe '#execute' do
    it 'runs decay_cycle and formats result' do
      response = instance_double(Net::HTTPOK)
      allow(response).to receive(:body).and_return(
        JSON.generate({ data: { decayed_count: 12, removed_count: 3, duration_ms: 45 } })
      )
      allow(mock_http).to receive(:request).and_return(response)

      result = tool.execute(action: 'decay_cycle')
      expect(result).to include('Decay cycle complete')
      expect(result).to include('Entries decayed: 12')
      expect(result).to include('Entries removed (below threshold): 3')
      expect(result).to include('Duration: 45ms')
    end

    it 'runs corroboration and formats result' do
      response = instance_double(Net::HTTPOK)
      allow(response).to receive(:body).and_return(
        JSON.generate({ data: { checked_count: 100, boosted_count: 15, duration_ms: 120 } })
      )
      allow(mock_http).to receive(:request).and_return(response)

      result = tool.execute(action: 'corroboration')
      expect(result).to include('Corroboration check complete')
      expect(result).to include('Entries checked: 100')
      expect(result).to include('Entries boosted (mutually supporting): 15')
    end

    it 'rejects invalid actions' do
      result = tool.execute(action: 'delete_all')
      expect(result).to include('Invalid action: delete_all')
      expect(result).to include('decay_cycle')
      expect(result).to include('corroboration')
    end

    it 'returns error from API' do
      response = instance_double(Net::HTTPOK)
      allow(response).to receive(:body).and_return(
        JSON.generate({ data: { error: 'table not available' } })
      )
      allow(mock_http).to receive(:request).and_return(response)

      result = tool.execute(action: 'decay_cycle')
      expect(result).to include('Apollo error: table not available')
    end

    it 'handles connection refused' do
      allow(Net::HTTP).to receive(:new).and_raise(Errno::ECONNREFUSED)

      result = tool.execute(action: 'decay_cycle')
      expect(result).to include('Apollo unavailable')
    end

    it 'handles missing duration_ms gracefully' do
      response = instance_double(Net::HTTPOK)
      allow(response).to receive(:body).and_return(
        JSON.generate({ data: { decayed_count: 5, removed_count: 0 } })
      )
      allow(mock_http).to receive(:request).and_return(response)

      result = tool.execute(action: 'decay_cycle')
      expect(result).to include('Entries decayed: 5')
      expect(result).not_to include('Duration')
    end

    it 'strips and normalizes action input' do
      response = instance_double(Net::HTTPOK)
      allow(response).to receive(:body).and_return(
        JSON.generate({ data: { checked_count: 0, boosted_count: 0 } })
      )
      allow(mock_http).to receive(:request).and_return(response)

      result = tool.execute(action: '  corroboration  ')
      expect(result).to include('Corroboration check complete')
    end

    it 'uses alternate key names for counts' do
      response = instance_double(Net::HTTPOK)
      allow(response).to receive(:body).and_return(
        JSON.generate({ data: { decayed: 7, removed: 2 } })
      )
      allow(mock_http).to receive(:request).and_return(response)

      result = tool.execute(action: 'decay_cycle')
      expect(result).to include('Entries decayed: 7')
      expect(result).to include('Entries removed (below threshold): 2')
    end
  end
end
