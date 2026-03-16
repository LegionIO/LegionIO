# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli/doctor_command'
require 'legion/cli/doctor/bundle_check'

RSpec.describe Legion::CLI::Doctor::BundleCheck do
  subject(:check) { described_class.new }

  describe '#name' do
    it 'returns a human-readable name' do
      expect(check.name).to eq('Bundle status')
    end
  end

  describe '#run' do
    context 'when bundle check succeeds' do
      before do
        allow(Open3).to receive(:capture3).with('bundle check').and_return(
          ['The Gemfile dependencies are satisfied', '', double(success?: true)]
        )
        allow(check).to receive(:find_gemfile).and_return('/path/to/Gemfile')
      end

      it 'returns a pass result' do
        result = check.run
        expect(result.status).to eq(:pass)
      end
    end

    context 'when gems are missing' do
      before do
        allow(Open3).to receive(:capture3).with('bundle check').and_return(
          ['', 'The following gems are missing', double(success?: false)]
        )
        allow(check).to receive(:find_gemfile).and_return('/path/to/Gemfile')
      end

      it 'returns a fail result' do
        result = check.run
        expect(result.status).to eq(:fail)
      end

      it 'prescribes running bundle install' do
        result = check.run
        expect(result.prescription).to eq('Run `bundle install`')
      end

      it 'is auto-fixable' do
        result = check.run
        expect(result.auto_fixable).to be true
      end
    end

    context 'when no Gemfile is found' do
      before do
        allow(check).to receive(:find_gemfile).and_return(nil)
      end

      it 'returns a skip result' do
        result = check.run
        expect(result.status).to eq(:skip)
      end
    end
  end
end
