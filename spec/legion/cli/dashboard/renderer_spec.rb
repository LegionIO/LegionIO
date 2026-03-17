# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli/dashboard/renderer'

RSpec.describe Legion::CLI::Dashboard::Renderer do
  let(:renderer) { described_class.new(width: 60) }

  describe '#render' do
    it 'includes header with worker count' do
      output = renderer.render({ workers: [{ worker_id: 'w1', status: 'active' }], events: [], health: {}, fetched_at: Time.now })
      expect(output).to include('Workers: 1')
    end

    it 'shows worker list' do
      output = renderer.render({ workers: [{ worker_id: 'test-bot', status: 'running' }], events: [], health: {}, fetched_at: Time.now })
      expect(output).to include('test-bot')
    end

    it 'handles empty data' do
      output = renderer.render({ workers: [], events: [], health: {}, fetched_at: Time.now })
      expect(output).to include('(none)')
    end

    it 'shows health components' do
      output = renderer.render({ workers: [], events: [], health: { transport: 'ok', data: 'ok' }, fetched_at: Time.now })
      expect(output).to include('transport: ok')
    end
  end
end
