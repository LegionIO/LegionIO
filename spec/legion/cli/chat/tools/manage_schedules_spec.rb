# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli/chat/tools/manage_schedules'

RSpec.describe Legion::CLI::Chat::Tools::ManageSchedules do
  subject(:tool) { described_class.new }

  let(:stub_http) { instance_double(Net::HTTP) }

  before do
    allow(Net::HTTP).to receive(:new).and_return(stub_http)
    allow(stub_http).to receive(:open_timeout=)
    allow(stub_http).to receive(:read_timeout=)
  end

  describe '#execute' do
    context 'with invalid action' do
      it 'returns error message' do
        result = tool.execute(action: 'delete')
        expect(result).to include('Invalid action')
      end
    end

    context 'with list action' do
      let(:body) do
        '{"data":[{"id":1,"function_id":5,"cron":"0 * * * *","active":true,"description":"Hourly sync"}]}'
      end

      before do
        response = instance_double(Net::HTTPResponse, body: body)
        allow(stub_http).to receive(:get).and_return(response)
      end

      it 'returns formatted schedule list' do
        result = tool.execute(action: 'list')
        expect(result).to include('Schedules (1)')
        expect(result).to include('#1')
        expect(result).to include('active')
        expect(result).to include('0 * * * *')
        expect(result).to include('Hourly sync')
      end
    end

    context 'with empty list' do
      before do
        response = instance_double(Net::HTTPResponse, body: '{"data":[]}')
        allow(stub_http).to receive(:get).and_return(response)
      end

      it 'returns no schedules message' do
        result = tool.execute(action: 'list')
        expect(result).to eq('No schedules found.')
      end
    end

    context 'with show action' do
      let(:body) do
        '{"data":{"id":1,"function_id":5,"cron":"0 * * * *","active":true}}'
      end

      before do
        response = instance_double(Net::HTTPResponse, body: body)
        allow(stub_http).to receive(:get).and_return(response)
      end

      it 'returns schedule details' do
        result = tool.execute(action: 'show', schedule_id: '1')
        expect(result).to include('Schedule #1')
        expect(result).to include('cron: 0 * * * *')
      end

      it 'requires schedule_id' do
        result = tool.execute(action: 'show')
        expect(result).to include('schedule_id is required')
      end
    end

    context 'with logs action' do
      let(:body) do
        '{"data":[{"started_at":"2026-03-23T05:00:00Z","status":"success","message":"completed"}]}'
      end

      before do
        response = instance_double(Net::HTTPResponse, body: body)
        allow(stub_http).to receive(:get).and_return(response)
      end

      it 'returns schedule logs' do
        result = tool.execute(action: 'logs', schedule_id: '1')
        expect(result).to include('Logs for Schedule #1')
        expect(result).to include('success')
      end

      it 'requires schedule_id' do
        result = tool.execute(action: 'logs')
        expect(result).to include('schedule_id is required')
      end
    end

    context 'with create action' do
      let(:body) { '{"data":{"id":2}}' }

      before do
        response = instance_double(Net::HTTPResponse, body: body)
        allow(stub_http).to receive(:request).and_return(response)
      end

      it 'creates a schedule' do
        result = tool.execute(action: 'create', function_id: '5', cron: '0 * * * *')
        expect(result).to include('Schedule created')
        expect(result).to include('id: 2')
      end

      it 'requires function_id' do
        result = tool.execute(action: 'create', cron: '0 * * * *')
        expect(result).to include('function_id is required')
      end

      it 'requires cron' do
        result = tool.execute(action: 'create', function_id: '5')
        expect(result).to include('cron expression is required')
      end
    end

    context 'when daemon is not running' do
      before do
        allow(stub_http).to receive(:get).and_raise(Errno::ECONNREFUSED)
      end

      it 'returns daemon not running message' do
        result = tool.execute(action: 'list')
        expect(result).to include('daemon not running')
      end
    end
  end
end
