# frozen_string_literal: true

require 'spec_helper'
require 'legion/auth/token_manager'
require 'legion/cli/connect_command'

RSpec.describe Legion::CLI::ConnectCommand do
  describe '#status' do
    before do
      allow(Legion::Auth::TokenManager).to receive(:new).and_return(
        instance_double(Legion::Auth::TokenManager, token_valid?: false, revoked?: false)
      )
    end

    context 'when the microsoft delegated token is present via the Entra TokenManager' do
      let(:entra_tm) { class_double('Legion::Extensions::Identity::Entra::Helpers::TokenManager') }

      before do
        stub_const('Legion::Extensions::Identity::Entra::Helpers::TokenManager', entra_tm)
        allow(entra_tm).to receive(:token_data).with(:delegated, refresh: false)
                                               .and_return({ access_token: 'abc', expires_at: Time.now + 3600 })
        allow(entra_tm).to receive(:expired?).and_return(false)
      end

      it 'reports microsoft as connected' do
        expect { described_class.new.invoke(:status, []) }.to output(/microsoft: connected/).to_stdout
      end
    end

    context 'when no microsoft delegated token exists' do
      before do
        stub_const('Legion::Extensions::Identity::Entra::Helpers::TokenManager',
                   class_double('Legion::Extensions::Identity::Entra::Helpers::TokenManager',
                                token_data: nil, expired?: true))
      end

      it 'reports microsoft as not connected' do
        expect { described_class.new.invoke(:status, []) }.to output(/microsoft: not connected/).to_stdout
      end
    end

    it 'reports non-microsoft providers via the legacy Auth::TokenManager' do
      hide_const('Legion::Extensions::Identity::Entra::Helpers::TokenManager')
      expect { described_class.new.invoke(:status, []) }.to output(/github: not connected/).to_stdout
    end
  end

  describe '#disconnect' do
    it 'rejects unknown providers' do
      expect { described_class.new.invoke(:disconnect, ['unknown']) }.to output(/Unknown provider/).to_stdout
    end
  end
end
