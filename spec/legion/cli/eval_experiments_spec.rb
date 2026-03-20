# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli'

RSpec.describe Legion::CLI::Eval, '#experiments' do
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
      cli = described_class.new([], { json: false, no_color: false, verbose: false })
      expect { cli.experiments }.to raise_error(Legion::CLI::Error, /lex-dataset/)
    end
  end

  context 'with lex-dataset available' do
    let(:dataset_client) { instance_double(Legion::Extensions::Dataset::Client) }

    let(:experiment_rows) do
      [
        { id: 1, name: 'baseline', status: 'completed',
          created_at: '2026-03-18 10:00:00', summary: 'total:10 passed:8' },
        { id: 2, name: 'prompt_v2', status: 'completed',
          created_at: '2026-03-19 14:00:00', summary: 'total:10 passed:9' }
      ]
    end

    before do
      stub_const('Legion::Extensions::Dataset::Client', Class.new do
        def initialize(**); end
      end)
      allow(Legion::Extensions::Dataset::Client).to receive(:new).and_return(dataset_client)
      allow(dataset_client).to receive(:list_experiments).and_return(experiment_rows)
    end

    it 'calls list_experiments on the dataset client' do
      expect(dataset_client).to receive(:list_experiments).and_return(experiment_rows)
      cli = described_class.new([], { json: false, no_color: false, verbose: false })
      cli.experiments
    end

    it 'renders a table in human mode' do
      expect(out).to receive(:table)
      cli = described_class.new([], { json: false, no_color: false, verbose: false })
      cli.experiments
    end

    it 'renders JSON in json mode' do
      expect(out).to receive(:json)
      cli = described_class.new([], { json: true, no_color: false, verbose: false })
      cli.experiments
    end

    it 'shows no results message when no experiments exist' do
      allow(dataset_client).to receive(:list_experiments).and_return([])
      expect(out).to receive(:warn).with(/no experiments/)
      cli = described_class.new([], { json: false, no_color: false, verbose: false })
      cli.experiments
    end
  end
end
