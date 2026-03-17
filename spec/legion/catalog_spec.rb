# frozen_string_literal: true

require 'spec_helper'
require 'legion/catalog'

RSpec.describe Legion::Catalog do
  describe '.collect_mcp_tools' do
    it 'returns empty array when MCP unavailable' do
      expect(described_class.collect_mcp_tools).to eq([])
    end
  end
end
