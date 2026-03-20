# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli'

RSpec.describe Legion::CLI::Eval, '#compare' do
  let(:out) do
    instance_double(Legion::CLI::Output::Formatter,
                    header: nil, spacer: nil, success: nil, warn: nil,
                    error: nil, json: nil, table: nil, detail: nil)
  end

  before do
    allow(Legion::CLI::Output::Formatter).to receive(:new).and_return(out)
    allow(Legion::CLI::Connection).to receive(:config_dir=)
    allow(Legion::CLI::Connection).to receive(:log_level=)
    allow(Legion::CLI::Connection).to receive(:ensure_data)
    allow(Legion::CLI::Connection).to receive(:shutdown)
  end

  context 'when lex-dataset is not loaded' do
    before { hide_const('Legion::Extensions::Dataset') if defined?(Legion::Extensions::Dataset) }

    it 'raises CLI::Error' do
      cli = described_class.new([], { run1: 'baseline', run2: 'candidate',
                                      json: false, no_color: false, verbose: false })
      expect { cli.compare }.to raise_error(Legion::CLI::Error, /lex-dataset/)
    end
  end

  context 'with lex-dataset available' do
    let(:dataset_client) { instance_double(Legion::Extensions::Dataset::Client) }

    let(:diff_result) do
      {
        exp1:              'baseline',
        exp2:              'candidate',
        rows_compared:     10,
        regression_count:  2,
        improvement_count: 3
      }
    end

    before do
      stub_const('Legion::Extensions::Dataset::Client', Class.new { def initialize(**); end })
      allow(Legion::Extensions::Dataset::Client).to receive(:new).and_return(dataset_client)
    end

    context 'when both experiments exist' do
      before { allow(dataset_client).to receive(:compare_experiments).and_return(diff_result) }

      it 'calls compare_experiments with the correct names' do
        expect(dataset_client).to receive(:compare_experiments)
          .with(exp1_name: 'baseline', exp2_name: 'candidate')
        cli = described_class.new([], { run1: 'baseline', run2: 'candidate',
                                        json: false, no_color: false, verbose: false })
        cli.compare
      end

      it 'renders a table in human mode' do
        expect(out).to receive(:table)
        cli = described_class.new([], { run1: 'baseline', run2: 'candidate',
                                        json: false, no_color: false, verbose: false })
        cli.compare
      end

      it 'renders JSON in json mode' do
        expect(out).to receive(:json)
        cli = described_class.new([], { run1: 'baseline', run2: 'candidate',
                                        json: true, no_color: false, verbose: false })
        cli.compare
      end
    end

    context 'when one experiment does not exist' do
      before do
        allow(dataset_client).to receive(:compare_experiments)
          .and_return({ error: 'experiments_not_found' })
      end

      it 'raises CLI::Error' do
        cli = described_class.new([], { run1: 'baseline', run2: 'missing',
                                        json: false, no_color: false, verbose: false })
        expect { cli.compare }.to raise_error(Legion::CLI::Error, /not found/)
      end
    end
  end
end
