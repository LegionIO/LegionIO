# frozen_string_literal: true

require 'spec_helper'
require 'legion/auth/token_manager'
require 'legion/cli/connect_command'

RSpec.describe Legion::CLI::ConnectCommand do
  describe '#status' do
    it 'shows status for all providers' do
      allow(Legion::Auth::TokenManager).to receive(:new).and_return(
        instance_double(Legion::Auth::TokenManager, token_valid?: false, revoked?: false)
      )
      expect { described_class.new.invoke(:status, []) }.to output(/not connected/).to_stdout
    end
  end

  describe '#disconnect' do
    it 'rejects unknown providers' do
      expect { described_class.new.invoke(:disconnect, ['unknown']) }.to output(/Unknown provider/).to_stdout
    end

    it 'accepts known providers' do
      expect { described_class.new.invoke(:disconnect, ['microsoft']) }.to output(/Disconnected/).to_stdout
    end
  end
end
