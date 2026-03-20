# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli/dashboard/renderer'

RSpec.describe Legion::CLI::Dashboard::Renderer do
  subject(:renderer) { described_class.new(width: 80) }

  describe '#render' do
    it 'includes org chart section when departments are present' do
      data = {
        workers: [],
        events: [],
        health: {},
        departments: [
          {
            name: 'lex-audit',
            roles: [
              { name: 'audit.write', workers: [{ name: 'audit-bot', status: 'active' }] }
            ]
          }
        ],
        fetched_at: Time.now
      }
      output = renderer.render(data)
      expect(output).to include('Org Chart:')
      expect(output).to include('lex-audit')
      expect(output).to include('audit.write')
      expect(output).to include('audit-bot')
    end

    it 'shows no departments message when empty' do
      data = { workers: [], events: [], health: {}, departments: [], fetched_at: Time.now }
      output = renderer.render(data)
      expect(output).to include('(no departments)')
    end

    it 'handles missing departments key' do
      data = { workers: [], events: [], health: {}, fetched_at: Time.now }
      output = renderer.render(data)
      expect(output).to include('(no departments)')
    end
  end
end
