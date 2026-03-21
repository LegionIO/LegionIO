# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'legion/cli/doctor'

RSpec.describe Legion::CLI::Doctor do
  describe 'class structure' do
    it 'is defined as a Thor subclass' do
      expect(described_class.ancestors).to include(Thor)
    end

    it 'has a diagnose method' do
      expect(described_class.instance_methods(false)).to include(:diagnose)
    end

    it 'defines diagnose as the default task' do
      expect(described_class.default_task).to eq('diagnose')
    end
  end

  describe 'Ruby version check' do
    subject(:check) { Legion::CLI::Doctor::RubyVersionCheck.new }

    it 'passes on the current Ruby version (>= 3.4)' do
      result = check.run
      expect(result.status).to eq(:pass)
    end

    it 'returns a Result with the current Ruby version in the message' do
      result = check.run
      expect(result.message).to include(RUBY_VERSION)
    end
  end

  describe 'settings check (ConfigCheck)' do
    subject(:check) { Legion::CLI::Doctor::ConfigCheck.new }

    context 'when config directory is stubbed to exist with valid JSON' do
      let(:tmpdir) { Dir.mktmpdir }

      before do
        require 'json'
        File.write("#{tmpdir}/transport.json", JSON.generate(host: 'localhost', port: 5672))
        stub_const('Legion::CLI::Doctor::ConfigCheck::CONFIG_PATHS', [tmpdir])
      end

      after { FileUtils.rm_rf(tmpdir) }

      it 'returns a pass result' do
        result = check.run
        expect(result.status).to eq(:pass)
      end
    end

    context 'when config directory is stubbed to not exist' do
      before do
        stub_const('Legion::CLI::Doctor::ConfigCheck::CONFIG_PATHS', ['/nonexistent/legionio/settings'])
      end

      it 'returns a warn result' do
        result = check.run
        expect(result.status).to eq(:warn)
      end

      it 'is auto-fixable' do
        result = check.run
        expect(result.auto_fixable).to be true
      end
    end
  end
end
