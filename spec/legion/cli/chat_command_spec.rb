# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli'
require 'legion/cli/connection'
require 'legion/llm/call/daemon_client'

RSpec.describe Legion::CLI::Chat do
  it 'is defined as a Thor subcommand' do
    expect(Legion::CLI::Chat).to be < Thor
  end

  it 'has an interactive command' do
    expect(Legion::CLI::Chat.instance_methods).to include(:interactive)
  end

  it 'has a prompt command for headless mode' do
    expect(Legion::CLI::Chat.instance_methods).to include(:prompt)
  end

  describe '#setup_connection' do
    subject(:chat) { described_class.new([], options) }

    let(:options) { {} }

    before do
      allow(Legion::CLI::Connection).to receive(:ensure_llm_settings)
      allow(Legion::LLM::Call::DaemonClient).to receive(:available?).and_return(true)
    end

    # Regression guard: the daemon URL lives under the :llm settings namespace,
    # which is only populated by merging Legion::LLM::Settings.default. Before the
    # fix, setup_connection called only ensure_settings, so llm.daemon.url was
    # never set and DaemonClient.available? returned false even with a live daemon.
    it 'merges the LLM defaults via ensure_llm_settings before checking the daemon' do
      chat.send(:setup_connection)
      expect(Legion::CLI::Connection).to have_received(:ensure_llm_settings)
    end

    it 'returns without raising when the daemon is available' do
      expect { chat.send(:setup_connection) }.not_to raise_error
    end

    context 'when the daemon is not available' do
      before { allow(Legion::LLM::Call::DaemonClient).to receive(:available?).and_return(false) }

      it 'raises CLI::Error instructing the user to start the daemon' do
        expect { chat.send(:setup_connection) }.to raise_error(
          Legion::CLI::Error,
          /daemon is not running/
        )
      end
    end
  end
end
