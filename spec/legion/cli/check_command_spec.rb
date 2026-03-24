# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli/check_command'
require 'legion/cli/output'
require 'json'

RSpec.describe Legion::CLI::Check do
  let(:base_options) { { json: true, no_color: true, verbose: false, extensions: false, full: false } }

  def run_check(options = base_options)
    formatter = Legion::CLI::Output::Formatter.new(json: options[:json], color: false)
    output = StringIO.new
    exit_code = nil
    begin
      $stdout = output
      exit_code = described_class.run(formatter, options)
    ensure
      $stdout = STDOUT
    end
    [exit_code, output.string]
  end

  before do
    allow(Legion::Logging).to receive(:setup)
  end

  describe '.run' do
    context 'when all checks pass' do
      before do
        described_class::CHECKS.each do |name|
          allow(described_class).to receive(:"check_#{name}")
          allow(described_class).to receive(:"shutdown_#{name}")
        end
      end

      it 'returns 0' do
        exit_code, = run_check
        expect(exit_code).to eq(0)
      end

      it 'reports all checks as pass in JSON' do
        _, output = run_check
        parsed = JSON.parse(output)
        expect(parsed['results'].keys).to eq(%w[settings crypt transport cache cache_local data data_local])
        parsed['results'].each_value do |result|
          expect(result['status']).to eq('pass')
        end
      end

      it 'reports summary with 0 failures' do
        _, output = run_check
        parsed = JSON.parse(output)
        expect(parsed['summary']['passed']).to eq(7)
        expect(parsed['summary']['failed']).to eq(0)
        expect(parsed['summary']['level']).to eq('connections')
      end
    end

    context 'when a check fails' do
      before do
        allow(described_class).to receive(:check_settings)
        allow(described_class).to receive(:check_crypt)
        allow(described_class).to receive(:check_transport)
        allow(described_class).to receive(:check_cache)
        allow(described_class).to receive(:check_cache_local)
        allow(described_class).to receive(:check_data).and_raise(StandardError, 'no db')
        allow(described_class).to receive(:shutdown_settings)
        allow(described_class).to receive(:shutdown_crypt)
        allow(described_class).to receive(:shutdown_transport)
        allow(described_class).to receive(:shutdown_cache)
        allow(described_class).to receive(:shutdown_cache_local)
      end

      it 'returns 1' do
        exit_code, = run_check
        expect(exit_code).to eq(1)
      end

      it 'marks failed check with error message' do
        _, output = run_check
        parsed = JSON.parse(output)
        expect(parsed['results']['data']['status']).to eq('fail')
        expect(parsed['results']['data']['error']).to include('no db')
      end
    end

    context 'when a check raises LoadError' do
      before do
        allow(described_class).to receive(:check_settings)
        allow(described_class).to receive(:check_crypt)
        allow(described_class).to receive(:check_transport)
        allow(described_class).to receive(:check_cache).and_raise(LoadError, 'cannot load such file -- legion/cache')
        allow(described_class).to receive(:check_data)
        allow(described_class).to receive(:check_data_local)
        allow(described_class).to receive(:shutdown_settings)
        allow(described_class).to receive(:shutdown_crypt)
        allow(described_class).to receive(:shutdown_transport)
        allow(described_class).to receive(:shutdown_data)
        allow(described_class).to receive(:shutdown_data_local)
      end

      it 'returns 1' do
        exit_code, = run_check
        expect(exit_code).to eq(1)
      end

      it 'records the check as fail instead of crashing' do
        _, output = run_check
        parsed = JSON.parse(output)
        expect(parsed['results']['cache']['status']).to eq('fail')
        expect(parsed['results']['cache']['error']).to include('legion/cache')
      end
    end

    context 'dependency skipping' do
      before do
        allow(described_class).to receive(:check_settings).and_raise(StandardError, 'bad config')
        allow(described_class).to receive(:shutdown_settings)
      end

      it 'skips checks that depend on failed check' do
        _, output = run_check
        parsed = JSON.parse(output)
        %w[crypt transport cache data].each do |name|
          expect(parsed['results'][name]['status']).to eq('skip')
          expect(parsed['results'][name]['error']).to eq('settings failed')
        end
        expect(parsed['results']['cache_local']['status']).to eq('skip')
        expect(parsed['results']['data_local']['status']).to eq('skip')
      end
    end

    context 'with --extensions flag' do
      before do
        (described_class::CHECKS + described_class::EXTENSION_CHECKS).each do |name|
          allow(described_class).to receive(:"check_#{name}")
          allow(described_class).to receive(:"shutdown_#{name}")
        end
      end

      it 'includes extensions in results' do
        _, output = run_check(base_options.merge(extensions: true))
        parsed = JSON.parse(output)
        expect(parsed['results']).to have_key('extensions')
        expect(parsed['summary']['level']).to eq('extensions')
      end
    end

    context 'with --full flag' do
      before do
        all_checks = described_class::CHECKS + described_class::EXTENSION_CHECKS + described_class::FULL_CHECKS
        all_checks.each do |name|
          allow(described_class).to receive(:"check_#{name}")
          allow(described_class).to receive(:"shutdown_#{name}")
        end
      end

      it 'includes extensions and api in results' do
        _, output = run_check(base_options.merge(full: true))
        parsed = JSON.parse(output)
        expect(parsed['results']).to have_key('extensions')
        expect(parsed['results']).to have_key('api')
        expect(parsed['summary']['level']).to eq('full')
      end
    end

    context 'text output with verbose' do
      before do
        described_class::CHECKS.each do |name|
          allow(described_class).to receive(:"check_#{name}")
          allow(described_class).to receive(:"shutdown_#{name}")
        end
      end

      it 'includes timing information' do
        _, output = run_check(base_options.merge(json: false, verbose: true))
        expect(output).to match(/\(\d+\.\d+s\)/)
      end
    end
  end
end
