# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli/doctor_command'
require 'legion/cli/doctor/ruby_version_check'

RSpec.describe Legion::CLI::Doctor::RubyVersionCheck do
  subject(:check) { described_class.new }

  describe '#name' do
    it 'returns a human-readable name' do
      expect(check.name).to eq('Ruby version')
    end
  end

  describe '#run' do
    context 'when Ruby version meets the minimum' do
      before do
        stub_const('RUBY_VERSION', '3.4.0')
      end

      it 'returns a pass result' do
        result = check.run
        expect(result.status).to eq(:pass)
      end

      it 'includes the current version in message' do
        result = check.run
        expect(result.message).to include('3.4.0')
      end
    end

    context 'when Ruby version is exactly the minimum' do
      before do
        stub_const('RUBY_VERSION', '3.4.0')
      end

      it 'returns a pass result' do
        result = check.run
        expect(result.status).to eq(:pass)
      end
    end

    context 'when Ruby version is below minimum' do
      before do
        stub_const('RUBY_VERSION', '3.2.0')
      end

      it 'returns a fail result' do
        result = check.run
        expect(result.status).to eq(:fail)
      end

      it 'includes the current version in message' do
        result = check.run
        expect(result.message).to include('3.2.0')
      end

      it 'provides an upgrade prescription' do
        result = check.run
        expect(result.prescription).to include('Upgrade Ruby')
        expect(result.prescription).to include('3.4')
      end

      it 'is not auto-fixable' do
        result = check.run
        expect(result.auto_fixable).to be false
      end
    end
  end
end
