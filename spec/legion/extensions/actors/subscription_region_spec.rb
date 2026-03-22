# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Legion::Extensions::Actors::Subscription region affinity' do
  let(:actor) { Legion::Extensions::Actors::Subscription.allocate }

  describe '#check_region_affinity' do
    context 'when Legion::Region is not defined' do
      before { hide_const('Legion::Region') }

      it 'returns :local regardless of message contents' do
        expect(actor.send(:check_region_affinity, { region: 'us-east-2', region_affinity: 'require_local' })).to eq(:local)
      end
    end

    context 'when Legion::Region is defined' do
      before do
        stub_const('Legion::Region', Module.new do
          module_function

          def affinity_for(message_region, affinity)
            return :local if message_region.nil? || message_region == current || affinity == 'any'
            return :remote if affinity == 'prefer_local'
            return :reject if affinity == 'require_local'

            :local
          end

          def current
            'us-east-1'
          end
        end)
      end

      it 'returns :local when message has no region header' do
        expect(actor.send(:check_region_affinity, {})).to eq(:local)
      end

      it 'returns :local when message region matches current region' do
        expect(actor.send(:check_region_affinity, { region: 'us-east-1' })).to eq(:local)
      end

      it 'returns :local when affinity is any regardless of region' do
        expect(actor.send(:check_region_affinity, { region: 'eu-west-1', region_affinity: 'any' })).to eq(:local)
      end

      it 'returns :remote when region differs and affinity is prefer_local' do
        expect(actor.send(:check_region_affinity, { region: 'eu-west-1', region_affinity: 'prefer_local' })).to eq(:remote)
      end

      it 'returns :reject when region differs and affinity is require_local' do
        expect(actor.send(:check_region_affinity, { region: 'eu-west-1', region_affinity: 'require_local' })).to eq(:reject)
      end
    end
  end

  describe 'subscribe block region affinity enforcement' do
    let(:delivery_info) { double('delivery_info', delivery_tag: 'tag-1', :[] => nil) }
    let(:metadata) do
      double('metadata',
             content_encoding: nil,
             content_type:     'application/json',
             headers:          nil)
    end
    let(:queue_double) { double('queue') }

    before do
      stub_const('Legion::Region', Module.new do
        module_function

        def affinity_for(message_region, affinity)
          return :local if message_region.nil? || message_region == current || affinity == 'any'
          return :remote if affinity == 'prefer_local'
          return :reject if affinity == 'require_local'

          :local
        end

        def current
          'us-east-1'
        end
      end)

      allow(Legion::JSON).to receive(:load).and_return({})
      allow(Legion::Logging).to receive(:warn)
      allow(Legion::Logging).to receive(:debug)

      allow(actor).to receive(:manual_ack).and_return(true)
      allow(actor).to receive(:use_runner?).and_return(false)
      allow(actor).to receive(:runner_class).and_return(double('runner_class'))
      allow(actor).to receive(:find_function).and_return(:process)
      allow(actor).to receive(:process_message).and_return({ function: :process })
      allow(actor).to receive(:instance_variable_get).with(:@queue).and_return(queue_double)
      actor.instance_variable_set(:@queue, queue_double)
    end

    context 'when affinity result is :reject' do
      it 'returns :reject for a different region with require_local affinity' do
        result = actor.send(:check_region_affinity, { region: 'eu-west-1', region_affinity: 'require_local' })
        expect(result).to eq(:reject)
      end
    end

    context 'when affinity result is :remote' do
      it 'logs a debug message and continues processing' do
        result = actor.send(:check_region_affinity, { region: 'eu-west-1', region_affinity: 'prefer_local' })
        expect(result).to eq(:remote)
      end
    end

    context 'when affinity result is :local' do
      it 'processes normally without extra logging' do
        result = actor.send(:check_region_affinity, { region: 'us-east-1' })
        expect(result).to eq(:local)
      end
    end
  end
end
