# frozen_string_literal: true

require 'spec_helper'
require 'thor'
require 'sequel'
require 'legion/cli/output'
require 'legion/cli/connection'
require 'legion/cli/error'
require 'legion/cli/chain_command'

RSpec.describe Legion::CLI::Chain do
  let(:out) { instance_double(Legion::CLI::Output::Formatter, success: nil, error: nil, warn: nil, spacer: nil, table: nil, json: nil, status: 'ok') }
  let(:chain_model) { double('ChainModel') }

  before do
    allow_any_instance_of(described_class).to receive(:formatter).and_return(out)
    allow(Legion::CLI::Connection).to receive(:config_dir=)
    allow(Legion::CLI::Connection).to receive(:log_level=)
    allow(Legion::CLI::Connection).to receive(:ensure_data)
    allow(Legion::CLI::Connection).to receive(:shutdown)
    stub_const('Legion::Data::Model::Chain', chain_model)
  end

  describe 'list' do
    it 'queries chains and renders table' do
      fake_dataset = double('dataset')
      allow(chain_model).to receive(:order).and_return(fake_dataset)
      allow(fake_dataset).to receive(:limit).and_return(fake_dataset)
      allow(fake_dataset).to receive(:map).and_return([])

      expect(out).to receive(:table).with(%w[id name active], [])
      described_class.start(%w[list])
    end
  end

  describe 'create' do
    it 'inserts a new chain' do
      allow(chain_model).to receive(:insert).with(name: 'my-chain').and_return(7)

      expect(out).to receive(:success).with(/Chain created.*7.*my-chain/)
      described_class.start(%w[create my-chain])
    end

    it 'outputs JSON when --json flag is set' do
      allow(chain_model).to receive(:insert).and_return(3)

      expect(out).to receive(:json).with(hash_including(id: 3, name: 'test'))
      described_class.start(%w[create test --json])
    end
  end

  describe 'delete' do
    it 'deletes chain when confirmed with -y' do
      fake_chain = double('chain', values: { name: 'old-chain' })
      allow(fake_chain).to receive(:delete)
      allow(chain_model).to receive(:[]).with(5).and_return(fake_chain)

      expect(out).to receive(:success).with(/Chain #5 deleted/)
      described_class.start(%w[delete 5 -y])
    end

    it 'reports error for missing chain' do
      allow(chain_model).to receive(:[]).with(99).and_return(nil)

      expect(out).to receive(:error).with('Chain 99 not found')
      expect { described_class.start(%w[delete 99]) }.to raise_error(SystemExit)
    end

    it 'aborts when user declines confirmation' do
      fake_chain = double('chain', values: { name: 'keep-me' })
      allow(chain_model).to receive(:[]).with(1).and_return(fake_chain)
      allow($stdin).to receive(:gets).and_return("n\n")

      expect(out).to receive(:warn).with('Aborted')
      described_class.start(%w[delete 1])
    end
  end
end
