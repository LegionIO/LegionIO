# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp'

RSpec.describe Legion::MCP::Tools::RunTask do
  describe '.call' do
    context 'with invalid dot notation' do
      it 'returns error for too few parts' do
        response = described_class.call(task: 'http.request')
        expect(response).to be_a(MCP::Tool::Response)
        expect(response.error?).to be true
        expect(response.content.first[:text]).to include('Invalid dot notation')
      end

      it 'returns error for too many parts' do
        response = described_class.call(task: 'a.b.c.d')
        expect(response.error?).to be true
      end
    end

    context 'with valid dot notation but missing runner' do
      it 'returns error when runner class not found' do
        allow(Legion::Ingress).to receive(:run).and_raise(NameError, 'uninitialized constant')
        response = described_class.call(task: 'fake.missing.run')
        expect(response.error?).to be true
        expect(response.content.first[:text]).to include('Runner not found')
      end
    end

    context 'with valid task execution' do
      it 'calls Legion::Ingress.run with correct args' do
        result = { task_id: 1, status: 'completed' }
        allow(Legion::Ingress).to receive(:run).and_return(result)

        response = described_class.call(task: 'http.request.get', params: { url: 'https://example.com' })
        expect(response.error?).to be false

        expect(Legion::Ingress).to have_received(:run).with(
          hash_including(
            runner_class: 'Legion::Extensions::Http::Runners::Request',
            function:     :get,
            source:       'mcp'
          )
        )
      end
    end
  end
end
