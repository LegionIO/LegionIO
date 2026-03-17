# frozen_string_literal: true

require 'spec_helper'
require 'legion/graph/builder'

RSpec.describe Legion::Graph::Builder do
  describe '.build' do
    it 'returns empty graph when db unavailable' do
      allow(described_class).to receive(:db_available?).and_return(false)
      result = described_class.build
      expect(result[:nodes]).to be_empty
      expect(result[:edges]).to be_empty
    end
  end
end
