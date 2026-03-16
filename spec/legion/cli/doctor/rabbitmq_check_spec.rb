# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli/doctor_command'
require 'legion/cli/doctor/rabbitmq_check'

RSpec.describe Legion::CLI::Doctor::RabbitmqCheck do
  subject(:check) { described_class.new }

  describe '#name' do
    it 'returns a human-readable name' do
      expect(check.name).to eq('RabbitMQ connection')
    end
  end

  describe '#run' do
    context 'when RabbitMQ is reachable' do
      before do
        allow(Socket).to receive(:tcp).and_yield(double('socket', close: nil))
      end

      it 'returns a pass result' do
        result = check.run
        expect(result.status).to eq(:pass)
      end

      it 'mentions the host and port' do
        result = check.run
        expect(result.message).to include('localhost')
        expect(result.message).to include('5672')
      end
    end

    context 'when RabbitMQ connection is refused' do
      before do
        allow(Socket).to receive(:tcp).and_raise(Errno::ECONNREFUSED)
      end

      it 'returns a fail result' do
        result = check.run
        expect(result.status).to eq(:fail)
      end

      it 'provides a prescription to start RabbitMQ' do
        result = check.run
        expect(result.prescription).to include('rabbitmq')
      end
    end

    context 'when connection times out' do
      before do
        allow(Socket).to receive(:tcp).and_raise(Errno::ETIMEDOUT)
      end

      it 'returns a fail result' do
        result = check.run
        expect(result.status).to eq(:fail)
      end
    end

    context 'when SocketError is raised' do
      before do
        allow(Socket).to receive(:tcp).and_raise(SocketError, 'getaddrinfo: nodename nor servname provided')
      end

      it 'returns a fail result' do
        result = check.run
        expect(result.status).to eq(:fail)
      end
    end
  end
end
