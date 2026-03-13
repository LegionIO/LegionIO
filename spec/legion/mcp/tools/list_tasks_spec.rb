# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp'

RSpec.describe Legion::MCP::Tools::ListTasks do
  describe '.call' do
    context 'when data is not connected' do
      before do
        allow(Legion::Settings).to receive(:[]).with(:data).and_return({ connected: false })
      end

      it 'returns an error response' do
        response = described_class.call
        expect(response.error?).to be true
        expect(response.content.first[:text]).to include('not connected')
      end
    end
  end
end
