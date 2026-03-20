# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Enterprise privacy mode audit logging' do
  describe 'Legion::Service.log_privacy_mode_status' do
    context 'when privacy mode is enabled' do
      before do
        allow(Legion::Settings).to receive(:enterprise_privacy?).and_return(true)
      end

      it 'logs an info entry when privacy mode is enabled' do
        allow(Legion::Logging).to receive(:info)
        Legion::Service.log_privacy_mode_status
        expect(Legion::Logging).to have_received(:info).with(/enterprise_data_privacy.*enabled/)
      end
    end

    context 'when privacy mode is disabled' do
      before do
        allow(Legion::Settings).to receive(:enterprise_privacy?).and_return(false)
      end

      it 'logs an info entry indicating privacy is disabled' do
        allow(Legion::Logging).to receive(:info)
        Legion::Service.log_privacy_mode_status
        expect(Legion::Logging).to have_received(:info).with(/enterprise_data_privacy.*disabled/)
      end
    end

    context 'when Legion::Logging is unavailable' do
      it 'does not raise' do
        allow(Legion).to receive(:const_defined?).with('Settings').and_return(true)
        allow(Legion::Settings).to receive(:respond_to?).with(:enterprise_privacy?).and_return(true)
        allow(Legion::Settings).to receive(:enterprise_privacy?).and_return(true)
        allow(Legion).to receive(:const_defined?).with('Logging').and_return(false)
        expect { Legion::Service.log_privacy_mode_status }.not_to raise_error
      end
    end
  end
end
