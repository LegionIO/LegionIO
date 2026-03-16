# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli/doctor_command'
require 'legion/cli/doctor/config_check'
require 'tmpdir'
require 'json'

RSpec.describe Legion::CLI::Doctor::ConfigCheck do
  subject(:check) { described_class.new }

  describe '#name' do
    it 'returns a human-readable name' do
      expect(check.name).to eq('Config files')
    end
  end

  describe '#run' do
    context 'when no config directory exists' do
      before do
        stub_const('Legion::CLI::Doctor::ConfigCheck::CONFIG_PATHS', ['/nonexistent/legionio/path'])
      end

      it 'returns a warn result' do
        result = check.run
        expect(result.status).to eq(:warn)
      end

      it 'suggests running config scaffold' do
        result = check.run
        expect(result.prescription).to include('legion config scaffold')
      end

      it 'is auto-fixable' do
        result = check.run
        expect(result.auto_fixable).to be true
      end
    end

    context 'when config directory exists with valid JSON' do
      let(:tmpdir) { Dir.mktmpdir }

      before do
        File.write("#{tmpdir}/transport.json", JSON.generate(host: 'localhost', port: 5672))
        stub_const('Legion::CLI::Doctor::ConfigCheck::CONFIG_PATHS', [tmpdir])
      end

      after { FileUtils.rm_rf(tmpdir) }

      it 'returns a pass result' do
        result = check.run
        expect(result.status).to eq(:pass)
      end

      it 'mentions the config directory' do
        result = check.run
        expect(result.message).to include(tmpdir)
      end
    end

    context 'when config directory has invalid JSON' do
      let(:tmpdir) { Dir.mktmpdir }

      before do
        File.write("#{tmpdir}/transport.json", '{invalid json}')
        stub_const('Legion::CLI::Doctor::ConfigCheck::CONFIG_PATHS', [tmpdir])
      end

      after { FileUtils.rm_rf(tmpdir) }

      it 'returns a fail result' do
        result = check.run
        expect(result.status).to eq(:fail)
      end

      it 'mentions the file with bad JSON' do
        result = check.run
        expect(result.message).to include('transport.json')
      end

      it 'provides a prescription to fix the JSON' do
        result = check.run
        expect(result.prescription).to include('Fix JSON syntax error')
      end
    end
  end
end
