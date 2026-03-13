# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp'

RSpec.describe Legion::MCP::Tools::GetStatus do
  describe '.call' do
    it 'returns service status' do
      response = described_class.call
      expect(response).to be_a(::MCP::Tool::Response)
      expect(response.error?).to be false

      data = Legion::JSON.load(response.content.first[:text])
      expect(data).to have_key(:version)
      expect(data[:version]).to eq(Legion::VERSION)
    end
  end
end
