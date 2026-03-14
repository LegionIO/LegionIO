# frozen_string_literal: true

require 'spec_helper'
require 'legion/digital_worker/value_metrics'

RSpec.describe Legion::DigitalWorker::ValueMetrics do
  describe 'METRIC_TYPES' do
    it 'contains the three supported metric types' do
      expect(described_class::METRIC_TYPES).to contain_exactly(:counter, :gauge, :duration)
    end

    it 'is frozen' do
      expect(described_class::METRIC_TYPES).to be_frozen
    end
  end

  describe '.record' do
    before do
      allow(Legion::Logging).to receive(:debug)
      allow(Legion::JSON).to receive(:dump).and_return('{}')
    end

    it 'raises ArgumentError for an invalid metric_type' do
      expect do
        described_class.record(worker_id: 'w1', metric_name: 'tasks_run', metric_type: :histogram, value: 5)
      end.to raise_error(ArgumentError, /invalid metric_type: histogram/)
    end

    it 'returns a record hash with the normalized fields' do
      result = described_class.record(
        worker_id:   'w1',
        metric_name: :tasks_run,
        metric_type: :counter,
        value:       42
      )
      expect(result[:worker_id]).to eq('w1')
      expect(result[:metric_name]).to eq('tasks_run')
      expect(result[:metric_type]).to eq('counter')
      expect(result[:value]).to eq(42.0)
      expect(result[:recorded_at]).to be_a(Time)
    end

    it 'converts value to float' do
      result = described_class.record(worker_id: 'w1', metric_name: 'latency', metric_type: :duration, value: '3')
      expect(result[:value]).to eq(3.0)
    end

    it 'serializes metadata via Legion::JSON.dump' do
      meta = { env: 'prod' }
      expect(Legion::JSON).to receive(:dump).with(meta).and_return('{"env":"prod"}')
      result = described_class.record(
        worker_id:   'w1',
        metric_name: 'cpu',
        metric_type: :gauge,
        value:       0.8,
        metadata:    meta
      )
      expect(result[:metadata]).to eq('{"env":"prod"}')
    end

    it 'defaults metadata to empty hash when not provided' do
      expect(Legion::JSON).to receive(:dump).with({}).and_return('{}')
      described_class.record(worker_id: 'w1', metric_name: 'mem', metric_type: :gauge, value: 1.0)
    end

    it 'inserts into the database when Legion::Data is available and table exists' do
      dataset = double('dataset')
      connection = double('connection')
      allow(connection).to receive(:table_exists?).with(:value_metrics).and_return(true)
      allow(connection).to receive(:[]).with(:value_metrics).and_return(dataset)
      allow(dataset).to receive(:insert)

      stub_const('Legion::Data', double(connection: connection))

      described_class.record(worker_id: 'w1', metric_name: 'tasks', metric_type: :counter, value: 1)

      expect(dataset).to have_received(:insert)
    end

    it 'skips DB insert when table does not exist' do
      connection = double('connection')
      allow(connection).to receive(:table_exists?).with(:value_metrics).and_return(false)
      stub_const('Legion::Data', double(connection: connection))

      expect(connection).not_to receive(:[])
      described_class.record(worker_id: 'w1', metric_name: 'tasks', metric_type: :counter, value: 1)
    end

    it 'logs a debug message' do
      expect(Legion::Logging).to receive(:debug).with(/worker=w1.*tasks_run.*counter/)
      described_class.record(worker_id: 'w1', metric_name: 'tasks_run', metric_type: :counter, value: 7)
    end
  end

  describe '.for_worker' do
    context 'when Legion::Data is not available' do
      it 'returns an empty array' do
        hide_const('Legion::Data')
        expect(described_class.for_worker(worker_id: 'w1')).to eq([])
      end
    end

    context 'when the value_metrics table does not exist' do
      it 'returns an empty array' do
        connection = double('connection')
        allow(connection).to receive(:table_exists?).with(:value_metrics).and_return(false)
        stub_const('Legion::Data', double(connection: connection))

        expect(described_class.for_worker(worker_id: 'w1')).to eq([])
      end
    end

    context 'when Legion::Data is available and table exists' do
      let(:rows)       { [{ worker_id: 'w1', metric_name: 'cpu', value: 0.5 }] }
      let(:dataset)    { double('dataset') }
      let(:connection) { double('connection') }

      before do
        allow(connection).to receive(:table_exists?).with(:value_metrics).and_return(true)
        allow(connection).to receive(:[]).with(:value_metrics).and_return(dataset)
        allow(dataset).to receive(:where).and_return(dataset)
        allow(dataset).to receive(:order).and_return(dataset)
        allow(dataset).to receive(:all).and_return(rows)
        stub_const('Legion::Data', double(connection: connection))
      end

      it 'returns all rows for the worker' do
        result = described_class.for_worker(worker_id: 'w1')
        expect(result).to eq(rows)
      end

      it 'filters by metric_name when provided' do
        expect(dataset).to receive(:where).with(worker_id: 'w1').and_return(dataset)
        expect(dataset).to receive(:where).with(metric_name: 'cpu').and_return(dataset)
        described_class.for_worker(worker_id: 'w1', metric_name: :cpu)
      end

      it 'filters by since when provided' do
        cutoff = Time.now.utc - 3600
        expect(dataset).to receive(:where).with(worker_id: 'w1').and_return(dataset)
        expect(dataset).to receive(:where).and_return(dataset)
        described_class.for_worker(worker_id: 'w1', since: cutoff)
      end
    end
  end

  describe '.summary' do
    context 'when Legion::Data is not available' do
      it 'returns an empty hash' do
        hide_const('Legion::Data')
        expect(described_class.summary(worker_id: 'w1')).to eq({})
      end
    end

    context 'when the value_metrics table does not exist' do
      it 'returns an empty hash' do
        connection = double('connection')
        allow(connection).to receive(:table_exists?).with(:value_metrics).and_return(false)
        stub_const('Legion::Data', double(connection: connection))

        expect(described_class.summary(worker_id: 'w1')).to eq({})
      end
    end

    context 'when Legion::Data is available and table exists' do
      let(:connection) { double('connection') }
      let(:ds)         { double('dataset') }
      let(:subset)     { double('subset') }

      before do
        allow(connection).to receive(:table_exists?).with(:value_metrics).and_return(true)
        allow(connection).to receive(:[]).with(:value_metrics).and_return(ds)
        allow(ds).to receive(:where).with(worker_id: 'w1').and_return(ds)
        allow(ds).to receive(:select).and_return(ds)
        allow(ds).to receive(:distinct).and_return(ds)
        allow(ds).to receive(:select_map).with(:metric_name).and_return(['tasks_run'])
        allow(ds).to receive(:where).with(metric_name: 'tasks_run').and_return(subset)
        allow(subset).to receive(:count).and_return(5)
        allow(subset).to receive(:sum).with(:value).and_return(50.0)
        allow(subset).to receive(:avg).with(:value).and_return(10.0)
        allow(subset).to receive(:min).with(:value).and_return(8.0)
        allow(subset).to receive(:max).with(:value).and_return(12.0)
        allow(subset).to receive(:order).and_return(subset)
        allow(subset).to receive(:first).and_return({ value: 12.0 })
        stub_const('Legion::Data', double(connection: connection))
      end

      it 'returns a hash keyed by metric name' do
        result = described_class.summary(worker_id: 'w1')
        expect(result).to have_key('tasks_run')
      end

      it 'includes count, sum, avg, min, max, and latest' do
        result = described_class.summary(worker_id: 'w1')
        stat = result['tasks_run']
        expect(stat[:count]).to eq(5)
        expect(stat[:sum]).to eq(50.0)
        expect(stat[:avg]).to eq(10.0)
        expect(stat[:min]).to eq(8.0)
        expect(stat[:max]).to eq(12.0)
        expect(stat[:latest]).to eq(12.0)
      end

      it 'returns empty hash when worker has no metrics' do
        allow(ds).to receive(:select_map).with(:metric_name).and_return([])
        result = described_class.summary(worker_id: 'w1')
        expect(result).to eq({})
      end
    end
  end
end
