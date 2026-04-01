# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli/doctor_command'
require 'legion/cli/output'
require 'legion/cli/connection'
require 'json'

RSpec.describe Legion::CLI::Doctor do
  let(:formatter) { Legion::CLI::Output::Formatter.new(json: true, color: false) }

  def run_diagnose(extra_opts = {})
    output = StringIO.new
    $stdout = output
    instance = described_class.new([], { json: true, no_color: true }.merge(extra_opts))
    begin
      instance.diagnose
    rescue SystemExit
      # expected on failure
    end
    $stdout = STDOUT
    output.string
  end

  before do
    allow(Legion::CLI::Connection).to receive(:ensure_settings)
    allow(Legion::CLI::Connection).to receive(:shutdown)

    described_class::CHECKS.each do |check_sym|
      check_class = Legion::CLI::Doctor.const_get(check_sym)
      allow_any_instance_of(check_class).to receive(:run).and_return(
        Legion::CLI::Doctor::Result.new(name: check_class.new.name, status: :pass, message: 'ok')
      )
    end
  end

  describe '#diagnose' do
    context 'when all checks pass' do
      it 'outputs JSON with all results' do
        output = run_diagnose
        parsed = JSON.parse(output)
        expect(parsed['results']).to be_an(Array)
        expect(parsed['results'].size).to eq(described_class::CHECKS.size)
      end

      it 'reports zero failures in summary' do
        output = run_diagnose
        parsed = JSON.parse(output)
        expect(parsed['summary']['failed']).to eq(0)
        expect(parsed['summary']['passed']).to eq(described_class::CHECKS.size)
      end
    end

    context 'when a check fails' do
      before do
        allow_any_instance_of(Legion::CLI::Doctor::RubyVersionCheck).to receive(:run).and_return(
          Legion::CLI::Doctor::Result.new(
            name:         'Ruby version',
            status:       :fail,
            message:      'Ruby 3.2 is below minimum 3.4',
            prescription: 'Upgrade Ruby to >= 3.4'
          )
        )
      end

      it 'records the failure in results' do
        output = run_diagnose
        parsed = JSON.parse(output)
        failed = parsed['results'].find { |r| r['status'] == 'fail' }
        expect(failed).not_to be_nil
        expect(failed['name']).to eq('Ruby version')
        expect(failed['prescription']).to include('Upgrade Ruby')
      end

      it 'reports failure count in summary' do
        output = run_diagnose
        parsed = JSON.parse(output)
        expect(parsed['summary']['failed']).to eq(1)
      end
    end

    context 'when a check warns' do
      before do
        allow_any_instance_of(Legion::CLI::Doctor::ConfigCheck).to receive(:run).and_return(
          Legion::CLI::Doctor::Result.new(
            name:         'Config files',
            status:       :warn,
            message:      'No config directory found',
            prescription: 'Run `legion config scaffold`',
            auto_fixable: true
          )
        )
      end

      it 'records the warning in results' do
        output = run_diagnose
        parsed = JSON.parse(output)
        warned = parsed['results'].find { |r| r['status'] == 'warn' }
        expect(warned).not_to be_nil
        expect(warned['auto_fixable']).to be true
      end

      it 'reports auto_fixable count in summary' do
        output = run_diagnose
        parsed = JSON.parse(output)
        expect(parsed['summary']['auto_fixable']).to eq(1)
      end
    end

    context 'with --fix flag' do
      let(:pid_check) { instance_double(Legion::CLI::Doctor::PidCheck) }

      before do
        allow_any_instance_of(Legion::CLI::Doctor::PidCheck).to receive(:run).and_return(
          Legion::CLI::Doctor::Result.new(
            name:         'PID files',
            status:       :warn,
            message:      'Stale PID files: /tmp/legion.pid',
            prescription: 'Remove with: rm /tmp/legion.pid',
            auto_fixable: true
          )
        )
        allow_any_instance_of(Legion::CLI::Doctor::PidCheck).to receive(:fix)
      end

      it 'calls fix on auto-fixable checks' do
        expect_any_instance_of(Legion::CLI::Doctor::PidCheck).to receive(:fix)
        run_diagnose(fix: true)
      end
    end

    context 'when a check raises unexpectedly' do
      before do
        allow_any_instance_of(Legion::CLI::Doctor::RabbitmqCheck).to receive(:run).and_raise(
          RuntimeError, 'unexpected boom'
        )
      end

      it 'captures the error as a failure result' do
        output = run_diagnose
        parsed = JSON.parse(output)
        failed = parsed['results'].find { |r| r['status'] == 'fail' }
        expect(failed).not_to be_nil
        expect(failed['message']).to include('unexpected boom')
      end
    end

    context 'scoring and grading' do
      it 'includes health_score and grade in JSON output when all pass' do
        output = run_diagnose
        parsed = JSON.parse(output)
        expect(parsed['summary']['health_score']).to eq(1.0)
        expect(parsed['summary']['grade']).to eq('A')
      end

      it 'returns grade F when all checks fail' do
        described_class::CHECKS.each do |check_sym|
          check_class = Legion::CLI::Doctor.const_get(check_sym)
          allow_any_instance_of(check_class).to receive(:run).and_return(
            Legion::CLI::Doctor::Result.new(name: check_class.new.name, status: :fail, message: 'bad')
          )
        end

        output = run_diagnose
        parsed = JSON.parse(output)
        expect(parsed['summary']['health_score']).to eq(0.0)
        expect(parsed['summary']['grade']).to eq('F')
      end

      it 'returns intermediate grade for mixed results' do
        described_class::CHECKS.each do |check_sym|
          check_class = Legion::CLI::Doctor.const_get(check_sym)
          allow_any_instance_of(check_class).to receive(:run).and_return(
            Legion::CLI::Doctor::Result.new(name: check_class.new.name, status: :warn, message: 'meh')
          )
        end

        output = run_diagnose
        parsed = JSON.parse(output)
        expect(parsed['summary']['health_score']).to eq(0.5)
        expect(parsed['summary']['grade']).to eq('D')
      end

      it 'includes score and weight in each result' do
        output = run_diagnose
        parsed = JSON.parse(output)
        first = parsed['results'].first
        expect(first).to have_key('score')
        expect(first).to have_key('weight')
        expect(first['score']).to eq(1.0)
      end
    end
  end
end
