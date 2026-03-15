# frozen_string_literal: true

require 'spec_helper'
require 'thor'
require 'legion/cli/output'
require 'legion/cli/gaia_command'

RSpec.describe Legion::CLI::Gaia do
  let(:mock_http) { instance_double(Net::HTTP) }

  let(:gaia_data) do
    {
      mode:              'autonomous',
      started:           true,
      buffer_depth:      3,
      sessions:          2,
      extensions_loaded: 8,
      extensions_total:  10,
      wired_phases:      4,
      active_channels:   %w[alpha beta],
      phase_list:        %w[perception reasoning action reflection]
    }
  end

  let(:success_response) do
    response = instance_double(Net::HTTPOK)
    allow(response).to receive(:body).and_return(JSON.generate({ data: gaia_data }))
    response
  end

  before do
    allow(Net::HTTP).to receive(:new).and_return(mock_http)
    allow(mock_http).to receive(:open_timeout=)
    allow(mock_http).to receive(:read_timeout=)
  end

  describe '#status — daemon running' do
    before do
      allow(mock_http).to receive(:get).and_return(success_response)
    end

    it 'outputs GAIA Status header' do
      expect { described_class.start(['status', '--no-color']) }.to output(/GAIA Status/).to_stdout
    end

    it 'shows mode in output' do
      expect { described_class.start(['status', '--no-color']) }.to output(/autonomous/).to_stdout
    end

    it 'shows active channels' do
      expect { described_class.start(['status', '--no-color']) }.to output(/alpha/).to_stdout
    end

    it 'shows wired phases' do
      expect { described_class.start(['status', '--no-color']) }.to output(/perception/).to_stdout
    end
  end

  describe '#status — daemon not running' do
    before do
      allow(mock_http).to receive(:get).and_raise(Errno::ECONNREFUSED)
    end

    it 'outputs not running message' do
      expect { described_class.start(['status', '--no-color']) }.to output(/not running/).to_stdout
    end

    it 'outputs GAIA Status header even when daemon is down' do
      expect { described_class.start(['status', '--no-color']) }.to output(/GAIA Status/).to_stdout
    end
  end

  describe '#status — JSON mode with daemon running' do
    before do
      allow(mock_http).to receive(:get).and_return(success_response)
    end

    it 'outputs valid JSON' do
      output = capture_stdout { described_class.start(['status', '--json']) }
      parsed = JSON.parse(output, symbolize_names: true)
      expect(parsed).to be_a(Hash)
    end

    it 'includes mode in JSON output' do
      output = capture_stdout { described_class.start(['status', '--json']) }
      parsed = JSON.parse(output, symbolize_names: true)
      expect(parsed[:mode]).to eq('autonomous')
    end

    it 'includes started in JSON output' do
      output = capture_stdout { described_class.start(['status', '--json']) }
      parsed = JSON.parse(output, symbolize_names: true)
      expect(parsed[:started]).to eq(true)
    end
  end

  describe '#status — JSON mode with daemon not running' do
    before do
      allow(mock_http).to receive(:get).and_raise(Errno::ECONNREFUSED)
    end

    it 'outputs JSON with started: false' do
      output = capture_stdout { described_class.start(['status', '--json']) }
      parsed = JSON.parse(output, symbolize_names: true)
      expect(parsed[:started]).to eq(false)
    end

    it 'includes error key in JSON output' do
      output = capture_stdout { described_class.start(['status', '--json']) }
      parsed = JSON.parse(output, symbolize_names: true)
      expect(parsed[:error]).to eq('daemon not running')
    end
  end

  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end
end
