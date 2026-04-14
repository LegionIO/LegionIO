# frozen_string_literal: true

require 'spec_helper'
require 'thor'
require 'sequel'
require 'legion/cli/output'
require 'legion/cli/connection'
require 'legion/cli/error'
require 'legion/cli/task_command'

RSpec.describe Legion::CLI::Task do
  let(:out) { instance_double(Legion::CLI::Output::Formatter, success: nil, error: nil, warn: nil, spacer: nil, header: nil, detail: nil, table: nil, json: nil, status: 'ok') }

  before do
    allow_any_instance_of(described_class).to receive(:formatter).and_return(out)
  end

  def stub_data_connection
    allow(Legion::CLI::Connection).to receive(:config_dir=)
    allow(Legion::CLI::Connection).to receive(:log_level=)
    allow(Legion::CLI::Connection).to receive(:ensure_data)
    allow(Legion::CLI::Connection).to receive(:shutdown)
  end

  def stub_transport_connection
    allow(Legion::CLI::Connection).to receive(:ensure_transport)
  end

  describe 'list' do
    before { stub_data_connection }

    it 'queries tasks and renders table' do
      task_model = double('Legion::Data::Model::Task')
      stub_const('Legion::Data::Model::Task', task_model)

      fake_dataset = double('dataset')
      allow(task_model).to receive(:order).and_return(fake_dataset)
      allow(fake_dataset).to receive(:limit).and_return(fake_dataset)
      allow(fake_dataset).to receive(:map).and_return([])

      expect(out).to receive(:table).with(%w[id function status created relationship], [])
      described_class.start(%w[list])
    end

    it 'applies status filter when provided' do
      task_model = double('Legion::Data::Model::Task')
      stub_const('Legion::Data::Model::Task', task_model)

      fake_dataset = double('dataset')
      allow(task_model).to receive(:order).and_return(fake_dataset)
      allow(fake_dataset).to receive(:limit).and_return(fake_dataset)
      allow(fake_dataset).to receive(:where).and_return(fake_dataset)
      allow(fake_dataset).to receive(:map).and_return([])

      expect(fake_dataset).to receive(:where)
      described_class.start(%w[list -s completed])
    end
  end

  describe 'show' do
    before { stub_data_connection }

    it 'displays task details' do
      task_model = double('Legion::Data::Model::Task')
      stub_const('Legion::Data::Model::Task', task_model)

      fake_task = double('task', values: {
                           id: 42, status: 'completed', function_id: 1, relationship_id: nil,
        runner_id: 2, created: Time.now, updated: Time.now,
        parent_id: nil, master_id: nil, args: nil
                         })
      allow(task_model).to receive(:[]).with(42).and_return(fake_task)

      expect(out).to receive(:header).with('Task #42')
      expect(out).to receive(:detail)
      described_class.start(%w[show 42])
    end

    it 'reports error for missing task' do
      task_model = double('Legion::Data::Model::Task')
      stub_const('Legion::Data::Model::Task', task_model)
      allow(task_model).to receive(:[]).with(999).and_return(nil)

      expect(out).to receive(:error).with('Task 999 not found')
      expect { described_class.start(%w[show 999]) }.to raise_error(SystemExit)
    end

    it 'outputs JSON when --json flag is set' do
      task_model = double('Legion::Data::Model::Task')
      stub_const('Legion::Data::Model::Task', task_model)

      fake_task = double('task', values: { id: 1, status: 'queued' })
      allow(task_model).to receive(:[]).with(1).and_return(fake_task)

      expect(out).to receive(:json).with(hash_including(id: 1))
      described_class.start(%w[show 1 --json])
    end
  end

  describe 'logs' do
    before { stub_data_connection }

    it 'displays log entries' do
      log_model = class_double('Legion::Data::Model::TaskLog')
      stub_const('Legion::Data::Model::TaskLog', log_model)

      fake_dataset = double('dataset')
      allow(log_model).to receive(:where).and_return(fake_dataset)
      allow(fake_dataset).to receive(:order).and_return(fake_dataset)
      allow(fake_dataset).to receive(:limit).and_return(fake_dataset)
      allow(fake_dataset).to receive(:map).and_return([%w[1 - 2026-01-01 started]])

      expect(out).to receive(:table).with(%w[id node created entry], [%w[1 - 2026-01-01 started]])
      described_class.start(%w[logs 10])
    end

    it 'warns when no logs found' do
      log_model = class_double('Legion::Data::Model::TaskLog')
      stub_const('Legion::Data::Model::TaskLog', log_model)

      fake_dataset = double('dataset')
      allow(log_model).to receive(:where).and_return(fake_dataset)
      allow(fake_dataset).to receive(:order).and_return(fake_dataset)
      allow(fake_dataset).to receive(:limit).and_return(fake_dataset)
      allow(fake_dataset).to receive(:map).and_return([])

      expect(out).to receive(:warn).with(/No logs found/)
      described_class.start(%w[logs 10])
    end
  end

  describe 'purge' do
    before { stub_data_connection }

    it 'reports no tasks to purge when count is zero' do
      task_model = double('Legion::Data::Model::Task')
      stub_const('Legion::Data::Model::Task', task_model)

      fake_dataset = double('dataset')
      allow(task_model).to receive(:where).and_return(fake_dataset)
      allow(fake_dataset).to receive(:count).and_return(0)

      expect(out).to receive(:success).with('No tasks to purge')
      described_class.start(%w[purge])
    end

    it 'deletes old tasks when confirmed' do
      task_model = double('Legion::Data::Model::Task')
      stub_const('Legion::Data::Model::Task', task_model)

      fake_dataset = double('dataset')
      allow(task_model).to receive(:where).and_return(fake_dataset)
      allow(fake_dataset).to receive(:count).and_return(5)
      allow(fake_dataset).to receive(:delete)

      expect(out).to receive(:success).with('Purged 5 tasks')
      described_class.start(%w[purge -y])
    end
  end

  describe 'helper methods' do
    let(:instance) { described_class.new }

    describe '#short_status' do
      it 'removes task. prefix' do
        expect(instance.send(:short_status, 'task.completed')).to eq('completed')
      end

      it 'returns non-string values unchanged' do
        expect(instance.send(:short_status, nil)).to be_nil
      end
    end

    describe '#format_time' do
      it 'formats Time objects' do
        t = Time.new(2026, 3, 15, 10, 30, 0)
        expect(instance.send(:format_time, t)).to eq('2026-03-15 10:30:00')
      end

      it 'returns dash for nil' do
        expect(instance.send(:format_time, nil)).to eq('-')
      end
    end
  end
end
