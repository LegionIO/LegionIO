# frozen_string_literal: true

require 'spec_helper'
require 'legion/audit'

RSpec.describe Legion::Audit do
  let(:valid_opts) do
    {
      event_type:   'runner_execution',
      principal_id: 'worker-123',
      action:       'execute',
      resource:     'MyRunner/my_function',
      source:       'amqp'
    }
  end

  describe '.record' do
    context 'when transport is available and lex-audit is loaded' do
      let(:message_double) { instance_double('Message', publish: true) }

      before do
        stub_const('Legion::Transport', Module.new)
        stub_const('Legion::Extensions::Audit::Transport::Messages::Audit', Class.new)
        allow(Legion::Settings).to receive(:[]).with(:transport).and_return({ connected: true })
        allow(Legion::Settings).to receive(:[]).with(:client).and_return({ hostname: 'node-01' })
        allow(Legion::Extensions::Audit::Transport::Messages::Audit).to receive(:new).and_return(message_double)
      end

      it 'publishes a message' do
        described_class.record(**valid_opts)
        expect(message_double).to have_received(:publish)
      end

      it 'stamps node from settings' do
        described_class.record(**valid_opts)
        expect(Legion::Extensions::Audit::Transport::Messages::Audit).to have_received(:new).with(
          hash_including(node: 'node-01')
        )
      end

      it 'stamps created_at as ISO8601' do
        described_class.record(**valid_opts)
        expect(Legion::Extensions::Audit::Transport::Messages::Audit).to have_received(:new).with(
          hash_including(created_at: match(/^\d{4}-\d{2}-\d{2}T/))
        )
      end
    end

    context 'when transport is not connected' do
      before do
        stub_const('Legion::Transport', Module.new)
        allow(Legion::Settings).to receive(:[]).with(:transport).and_return({ connected: false })
      end

      it 'silently returns nil' do
        expect(described_class.record(**valid_opts)).to be_nil
      end
    end

    context 'when lex-audit message class is not defined' do
      before do
        stub_const('Legion::Transport', Module.new)
        allow(Legion::Settings).to receive(:[]).with(:transport).and_return({ connected: true })
        # Legion::Extensions::Audit::Transport::Messages::Audit is NOT defined
      end

      it 'silently returns nil' do
        expect(described_class.record(**valid_opts)).to be_nil
      end
    end

    context 'when publishing raises an error' do
      let(:message_double) { instance_double('Message') }

      before do
        stub_const('Legion::Transport', Module.new)
        stub_const('Legion::Extensions::Audit::Transport::Messages::Audit', Class.new)
        allow(Legion::Settings).to receive(:[]).with(:transport).and_return({ connected: true })
        allow(Legion::Settings).to receive(:[]).with(:client).and_return({ hostname: 'node-01' })
        allow(Legion::Extensions::Audit::Transport::Messages::Audit).to receive(:new).and_return(message_double)
        allow(message_double).to receive(:publish).and_raise(StandardError, 'connection lost')
      end

      it 'never raises' do
        expect { described_class.record(**valid_opts) }.not_to raise_error
      end
    end
  end
end
