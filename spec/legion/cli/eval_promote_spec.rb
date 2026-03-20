# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli'

RSpec.describe Legion::CLI::Eval, '#promote' do
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

    it 'raises CLI::Error mentioning lex-dataset' do
      cli = described_class.new([], { experiment: 'baseline', tag: 'production',
                                      json: false, no_color: false, verbose: false })
      expect { cli.promote }.to raise_error(Legion::CLI::Error, /lex-dataset/)
    end
  end

  context 'when lex-prompt is not loaded' do
    before do
      stub_const('Legion::Extensions::Dataset::Client', Class.new { def initialize(**); end })
      hide_const('Legion::Extensions::Prompt') if defined?(Legion::Extensions::Prompt)
    end

    it 'raises CLI::Error mentioning lex-prompt' do
      cli = described_class.new([], { experiment: 'baseline', tag: 'production',
                                      json: false, no_color: false, verbose: false })
      expect { cli.promote }.to raise_error(Legion::CLI::Error, /lex-prompt/)
    end
  end

  context 'with both extensions available' do
    let(:dataset_client) { instance_double(Legion::Extensions::Dataset::Client) }
    let(:prompt_client)  { instance_double(Legion::Extensions::Prompt::Client) }

    let(:experiment_row) do
      { id: 2, name: 'prompt_v2', status: 'completed',
        prompt_name: 'my_prompt', prompt_version: 3 }
    end

    before do
      stub_const('Legion::Extensions::Dataset::Client', Class.new { def initialize(**); end })
      stub_const('Legion::Extensions::Prompt::Client', Class.new { def initialize(**); end })
      allow(Legion::Extensions::Dataset::Client).to receive(:new).and_return(dataset_client)
      allow(Legion::Extensions::Prompt::Client).to receive(:new).and_return(prompt_client)
      allow(dataset_client).to receive(:get_experiment).with(name: 'prompt_v2').and_return(experiment_row)
    end

    context 'when experiment exists and has a linked prompt' do
      before do
        allow(prompt_client).to receive(:tag_prompt)
          .and_return({ tagged: true, name: 'my_prompt', tag: 'production', version: 3 })
      end

      it 'calls tag_prompt with the correct arguments' do
        expect(prompt_client).to receive(:tag_prompt).with(
          name: 'my_prompt', tag: 'production', version: 3
        )
        cli = described_class.new([], { experiment: 'prompt_v2', tag: 'production',
                                        json: false, no_color: false, verbose: false })
        cli.promote
      end

      it 'outputs success in human mode' do
        expect(out).to receive(:success)
        cli = described_class.new([], { experiment: 'prompt_v2', tag: 'production',
                                        json: false, no_color: false, verbose: false })
        cli.promote
      end

      it 'outputs JSON in json mode' do
        expect(out).to receive(:json)
        cli = described_class.new([], { experiment: 'prompt_v2', tag: 'production',
                                        json: true, no_color: false, verbose: false })
        cli.promote
      end
    end

    context 'when experiment is not found' do
      before { allow(dataset_client).to receive(:get_experiment).and_return(nil) }

      it 'raises CLI::Error' do
        cli = described_class.new([], { experiment: 'missing', tag: 'production',
                                        json: false, no_color: false, verbose: false })
        expect { cli.promote }.to raise_error(Legion::CLI::Error, /not found/)
      end
    end

    context 'when experiment has no linked prompt' do
      before do
        allow(dataset_client).to receive(:get_experiment)
          .and_return(experiment_row.merge(prompt_name: nil))
      end

      it 'raises CLI::Error explaining no prompt is linked' do
        cli = described_class.new([], { experiment: 'prompt_v2', tag: 'production',
                                        json: false, no_color: false, verbose: false })
        expect { cli.promote }.to raise_error(Legion::CLI::Error, /no prompt linked/)
      end
    end
  end
end
