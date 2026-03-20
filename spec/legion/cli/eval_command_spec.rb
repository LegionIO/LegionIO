# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli'

RSpec.describe Legion::CLI::Eval do
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

  describe '#run' do
    context 'when lex-eval is not loaded' do
      before do
        hide_const('Legion::Extensions::Eval') if defined?(Legion::Extensions::Eval)
      end

      it 'raises CLI::Error with helpful message' do
        cli = described_class.new([], { dataset: 'my_ds', threshold: 0.8, exit_code: false })
        expect { cli.execute }.to raise_error(Legion::CLI::Error, /lex-eval/)
      end
    end

    context 'when lex-dataset is not loaded' do
      before do
        stub_const('Legion::Extensions::Eval::Client', Class.new do
          def initialize(**); end
        end)
        hide_const('Legion::Extensions::Dataset') if defined?(Legion::Extensions::Dataset)
      end

      it 'raises CLI::Error with helpful message' do
        cli = described_class.new([], { dataset: 'my_ds', threshold: 0.8, exit_code: false })
        expect { cli.execute }.to raise_error(Legion::CLI::Error, /lex-dataset/)
      end
    end

    context 'with both extensions available' do
      let(:dataset_client) { instance_double(Legion::Extensions::Dataset::Client) }
      let(:eval_client)    { instance_double(Legion::Extensions::Eval::Client) }

      let(:dataset_result) do
        {
          name: 'my_ds', version: 1, version_id: 1, row_count: 3,
          rows: [
            { row_index: 0, input: 'a', expected_output: 'A' },
            { row_index: 1, input: 'b', expected_output: 'B' },
            { row_index: 2, input: 'c', expected_output: 'C' }
          ]
        }
      end

      let(:passing_report) do
        {
          evaluator: 'default',
          results:   [
            { row_index: 0, passed: true,  score: 1.0 },
            { row_index: 1, passed: true,  score: 1.0 },
            { row_index: 2, passed: true,  score: 0.9 }
          ],
          summary:   { total: 3, passed: 3, failed: 0, avg_score: 0.967 }
        }
      end

      let(:failing_report) do
        {
          evaluator: 'default',
          results:   [
            { row_index: 0, passed: false, score: 0.3 },
            { row_index: 1, passed: false, score: 0.4 },
            { row_index: 2, passed: true,  score: 0.9 }
          ],
          summary:   { total: 3, passed: 1, failed: 2, avg_score: 0.533 }
        }
      end

      before do
        stub_const('Legion::Extensions::Dataset::Client', Class.new do
          def initialize(**); end
        end)
        stub_const('Legion::Extensions::Eval::Client', Class.new do
          def initialize(**); end
        end)
        allow(Legion::Extensions::Dataset::Client).to receive(:new).and_return(dataset_client)
        allow(Legion::Extensions::Eval::Client).to receive(:new).and_return(eval_client)
        allow(dataset_client).to receive(:get_dataset).with(name: 'my_ds').and_return(dataset_result)
      end

      context 'when avg_score >= threshold' do
        before { allow(eval_client).to receive(:run_evaluation).and_return(passing_report) }

        it 'outputs JSON report to stdout' do
          expect(out).to receive(:json)
          cli = described_class.new([], { dataset: 'my_ds', threshold: 0.8, exit_code: false,
                                         json: true, no_color: false, verbose: false })
          cli.execute
        end

        it 'does not exit 1 when exit_code is true and passing' do
          cli = described_class.new([], { dataset: 'my_ds', threshold: 0.8, exit_code: true,
                                         json: false, no_color: false, verbose: false })
          expect { cli.execute }.not_to raise_error
        end
      end

      context 'when avg_score < threshold' do
        before { allow(eval_client).to receive(:run_evaluation).and_return(failing_report) }

        it 'raises SystemExit with code 1 when --exit-code is set' do
          cli = described_class.new([], { dataset: 'my_ds', threshold: 0.8, exit_code: true,
                                         json: false, no_color: false, verbose: false })
          expect { cli.execute }.to raise_error(SystemExit)
        end

        it 'does not exit when --exit-code is omitted' do
          cli = described_class.new([], { dataset: 'my_ds', threshold: 0.8, exit_code: false,
                                         json: false, no_color: false, verbose: false })
          expect { cli.execute }.not_to raise_error
        end
      end

      context 'when dataset is not found' do
        before do
          allow(dataset_client).to receive(:get_dataset).and_return({ error: 'not_found' })
        end

        it 'raises CLI::Error' do
          cli = described_class.new([], { dataset: 'missing', threshold: 0.8, exit_code: false,
                                         json: false, no_color: false, verbose: false })
          expect { cli.execute }.to raise_error(Legion::CLI::Error, /not found/)
        end
      end
    end
  end
end
