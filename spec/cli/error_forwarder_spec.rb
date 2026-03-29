# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli/error_forwarder'

RSpec.describe Legion::CLI::ErrorForwarder do
  let(:exception) { RuntimeError.new('something broke') }
  let(:http_double) { instance_double(Net::HTTP) }
  let(:response_double) { instance_double(Net::HTTPResponse) }

  before do
    exception.set_backtrace(['cli.rb:42:in `start\'', 'exe/legion:10:in `<main>\''])
    allow(Net::HTTP).to receive(:new).and_return(http_double)
    allow(http_double).to receive(:open_timeout=)
    allow(http_double).to receive(:read_timeout=)
    allow(http_double).to receive(:request).and_return(response_double)
  end

  describe '.forward_error' do
    it 'sends a POST request to /api/logs' do
      expect(http_double).to receive(:request) do |req|
        expect(req).to be_a(Net::HTTP::Post)
        expect(req.path).to eq('/api/logs')
        response_double
      end
      described_class.forward_error(exception)
    end

    it 'includes level "error" in the payload' do
      expect(http_double).to receive(:request) do |req|
        body = JSON.parse(req.body, symbolize_names: true)
        expect(body[:level]).to eq('error')
        response_double
      end
      described_class.forward_error(exception)
    end

    it 'includes the exception message in the payload' do
      expect(http_double).to receive(:request) do |req|
        body = JSON.parse(req.body, symbolize_names: true)
        expect(body[:message]).to eq('something broke')
        response_double
      end
      described_class.forward_error(exception)
    end

    it 'includes the exception class name in the payload' do
      expect(http_double).to receive(:request) do |req|
        body = JSON.parse(req.body, symbolize_names: true)
        expect(body[:exception_class]).to eq('RuntimeError')
        response_double
      end
      described_class.forward_error(exception)
    end

    it 'includes the backtrace in the payload' do
      expect(http_double).to receive(:request) do |req|
        body = JSON.parse(req.body, symbolize_names: true)
        expect(body[:backtrace]).to be_an(Array)
        expect(body[:backtrace].first).to include('cli.rb')
        response_double
      end
      described_class.forward_error(exception)
    end

    it 'includes the command when provided' do
      expect(http_double).to receive(:request) do |req|
        body = JSON.parse(req.body, symbolize_names: true)
        expect(body[:command]).to eq('legion chat prompt hello')
        response_double
      end
      described_class.forward_error(exception, command: 'legion chat prompt hello')
    end

    it 'sets component_type to "cli"' do
      expect(http_double).to receive(:request) do |req|
        body = JSON.parse(req.body, symbolize_names: true)
        expect(body[:component_type]).to eq('cli')
        response_double
      end
      described_class.forward_error(exception)
    end
  end

  describe '.forward_warning' do
    it 'sends a POST request to /api/logs' do
      expect(http_double).to receive(:request) do |req|
        expect(req.path).to eq('/api/logs')
        response_double
      end
      described_class.forward_warning('suspicious activity')
    end

    it 'includes level "warn" in the payload' do
      expect(http_double).to receive(:request) do |req|
        body = JSON.parse(req.body, symbolize_names: true)
        expect(body[:level]).to eq('warn')
        response_double
      end
      described_class.forward_warning('suspicious activity')
    end

    it 'includes the message in the payload' do
      expect(http_double).to receive(:request) do |req|
        body = JSON.parse(req.body, symbolize_names: true)
        expect(body[:message]).to eq('suspicious activity')
        response_double
      end
      described_class.forward_warning('suspicious activity')
    end

    it 'includes the command when provided' do
      expect(http_double).to receive(:request) do |req|
        body = JSON.parse(req.body, symbolize_names: true)
        expect(body[:command]).to eq('legion check')
        response_double
      end
      described_class.forward_warning('suspicious activity', command: 'legion check')
    end

    it 'does not include exception_class' do
      expect(http_double).to receive(:request) do |req|
        body = JSON.parse(req.body, symbolize_names: true)
        expect(body).not_to have_key(:exception_class)
        response_double
      end
      described_class.forward_warning('suspicious activity')
    end
  end

  describe 'error resilience' do
    it 'silently swallows Errno::ECONNREFUSED (daemon not running)' do
      allow(http_double).to receive(:request).and_raise(Errno::ECONNREFUSED)
      expect { described_class.forward_error(exception) }.not_to raise_error
    end

    it 'silently swallows Net::OpenTimeout' do
      allow(http_double).to receive(:request).and_raise(Net::OpenTimeout)
      expect { described_class.forward_error(exception) }.not_to raise_error
    end

    it 'silently swallows Net::ReadTimeout' do
      allow(http_double).to receive(:request).and_raise(Net::ReadTimeout)
      expect { described_class.forward_error(exception) }.not_to raise_error
    end

    it 'silently swallows SocketError' do
      allow(http_double).to receive(:request).and_raise(SocketError)
      expect { described_class.forward_warning('msg') }.not_to raise_error
    end

    it 'silently swallows arbitrary StandardError' do
      allow(http_double).to receive(:request).and_raise(StandardError, 'unexpected')
      expect { described_class.forward_error(exception) }.not_to raise_error
    end
  end
end
