# frozen_string_literal: true

require 'spec_helper'
require 'legion/runner/log'

module Legion
  module Data
    module Model
      Runner = Class.new unless const_defined?(:Runner, false)
      Function = Class.new unless const_defined?(:Function, false)
      Task = Class.new unless const_defined?(:Task, false)
    end
  end
end

RSpec.describe Legion::Runner::Status do
  describe 'it should have things' do
    it { is_expected.to be_a Module }
    it { is_expected.to respond_to :update }
    it { is_expected.to respond_to :update_rmq }
    it { is_expected.to respond_to :update_db }
    it { is_expected.to respond_to :generate_task_id }
  end

  describe '.generate_task_id' do
    context 'when data is not connected' do
      before do
        allow(Legion::Settings).to receive(:[]).with(:data).and_return({ connected: false })
      end

      it 'returns nil' do
        expect(described_class.generate_task_id(runner_class: 'SomeRunner', function: 'run')).to be_nil
      end
    end

    context 'when data is connected' do
      let(:runner_relation) { double('runner_relation', first: nil) }

      before do
        allow(Legion::Settings).to receive(:[]).with(:data).and_return({ connected: true })
        allow(Legion::Data::Model::Runner).to receive(:where).and_return(runner_relation)
      end

      it 'queries runner namespace without downcasing (preserves mixed case)' do
        expect(Legion::Data::Model::Runner)
          .to receive(:where).with(namespace: 'Legion::Extensions::MyRunner')
          .and_return(runner_relation)
        described_class.generate_task_id(runner_class: 'Legion::Extensions::MyRunner', function: 'run')
      end

      it 'returns nil when runner is not found' do
        result = described_class.generate_task_id(runner_class: 'Legion::Extensions::MyRunner', function: 'run')
        expect(result).to be_nil
      end
    end
  end
end
