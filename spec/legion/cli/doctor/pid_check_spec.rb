# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli/doctor_command'
require 'legion/cli/doctor/pid_check'
require 'tmpdir'

RSpec.describe Legion::CLI::Doctor::PidCheck do
  subject(:check) { described_class.new }

  describe '#name' do
    it 'returns a human-readable name' do
      expect(check.name).to eq('PID files')
    end
  end

  describe '#run' do
    context 'when no PID files exist' do
      before do
        stub_const('Legion::CLI::Doctor::PidCheck::PID_PATHS', ['/nonexistent/legion.pid'])
      end

      it 'returns a pass result' do
        result = check.run
        expect(result.status).to eq(:pass)
      end

      it 'reports no stale PID files' do
        result = check.run
        expect(result.message).to include('No stale')
      end
    end

    context 'when a PID file exists with a dead process' do
      let(:tmpdir) { Dir.mktmpdir }
      let(:pid_file) { "#{tmpdir}/legion.pid" }

      before do
        File.write(pid_file, '999999')
        stub_const('Legion::CLI::Doctor::PidCheck::PID_PATHS', [pid_file])
        allow(Process).to receive(:kill).with(0, 999_999).and_raise(Errno::ESRCH)
      end

      after { FileUtils.rm_rf(tmpdir) }

      it 'returns a warn result' do
        result = check.run
        expect(result.status).to eq(:warn)
      end

      it 'mentions the stale PID file' do
        result = check.run
        expect(result.message).to include(pid_file)
      end

      it 'prescribes removing the file' do
        result = check.run
        expect(result.prescription).to include("rm #{pid_file}")
      end

      it 'is auto-fixable' do
        result = check.run
        expect(result.auto_fixable).to be true
      end
    end

    context 'when a PID file exists with a running process' do
      let(:tmpdir) { Dir.mktmpdir }
      let(:pid_file) { "#{tmpdir}/legion.pid" }

      before do
        File.write(pid_file, Process.pid.to_s)
        stub_const('Legion::CLI::Doctor::PidCheck::PID_PATHS', [pid_file])
      end

      after { FileUtils.rm_rf(tmpdir) }

      it 'returns a pass result' do
        result = check.run
        expect(result.status).to eq(:pass)
      end
    end
  end

  describe '#fix' do
    let(:tmpdir) { Dir.mktmpdir }
    let(:pid_file) { "#{tmpdir}/legion.pid" }

    before do
      File.write(pid_file, '999999')
      stub_const('Legion::CLI::Doctor::PidCheck::PID_PATHS', [pid_file])
      allow(Process).to receive(:kill).with(0, 999_999).and_raise(Errno::ESRCH)
    end

    after { FileUtils.rm_rf(tmpdir) }

    it 'removes stale PID files' do
      check.fix
      expect(File.exist?(pid_file)).to be false
    end
  end
end
