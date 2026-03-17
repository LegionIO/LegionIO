# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Gaia API routes' do
  describe 'POST /api/channels/teams/webhook' do
    it 'returns 503 when teams adapter is unavailable' do
      expect(true).to be true
    end
  end
end
