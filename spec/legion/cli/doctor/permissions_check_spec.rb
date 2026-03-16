# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli/doctor_command'
require 'legion/cli/doctor/permissions_check'

RSpec.describe Legion::CLI::Doctor::PermissionsCheck do
  subject(:check) { described_class.new }

  describe '#name' do
    it 'returns a human-readable name' do
      expect(check.name).to eq('Permissions')
    end
  end

  describe '#run' do
    context 'when all directories are writable' do
      before do
        stub_const('Legion::CLI::Doctor::PermissionsCheck::DIRECTORIES', ['/tmp'])
        allow(Dir).to receive(:exist?).with('/tmp').and_return(true)
        allow(File).to receive(:writable?).with('/tmp').and_return(true)
      end

      it 'returns a pass result' do
        result = check.run
        expect(result.status).to eq(:pass)
      end
    end

    context 'when a directory is not writable' do
      before do
        stub_const('Legion::CLI::Doctor::PermissionsCheck::DIRECTORIES', ['/tmp/unwritable_test'])
        allow(Dir).to receive(:exist?).with('/tmp/unwritable_test').and_return(true)
        allow(File).to receive(:writable?).with('/tmp/unwritable_test').and_return(false)
      end

      it 'returns a warn result' do
        result = check.run
        expect(result.status).to eq(:warn)
      end

      it 'mentions the unwritable directory' do
        result = check.run
        expect(result.message).to include('/tmp/unwritable_test')
      end

      it 'prescribes chmod' do
        result = check.run
        expect(result.prescription).to include('chmod 755')
      end
    end

    context 'when a directory does not exist' do
      before do
        stub_const('Legion::CLI::Doctor::PermissionsCheck::DIRECTORIES', ['/nonexistent/dir'])
        allow(Dir).to receive(:exist?).with('/nonexistent/dir').and_return(false)
      end

      it 'returns a pass result (non-existent dirs are skipped)' do
        result = check.run
        expect(result.status).to eq(:pass)
      end
    end
  end
end
