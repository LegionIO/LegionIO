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

  describe '#status -- daemon running' do
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

  describe '#status -- daemon not running' do
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

  describe '#status -- JSON mode with daemon running' do
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

  describe '#status -- JSON mode with daemon not running' do
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

  describe '#channels' do
    let(:channels_data) do
      {
        channels: [
          { id: :cli, type: 'CliAdapter', started: true, capabilities: %w[text markdown] },
          { id: :teams, type: 'TeamsAdapter', started: false, capabilities: %w[text] }
        ],
        count:    2
      }
    end

    let(:channels_response) do
      response = instance_double(Net::HTTPOK)
      allow(response).to receive(:body).and_return(JSON.generate({ data: channels_data }))
      response
    end

    before { allow(mock_http).to receive(:get).and_return(channels_response) }

    it 'outputs channel header with count' do
      expect { described_class.start(%w[channels --no-color]) }.to output(/GAIA Channels \(2\)/).to_stdout
    end

    it 'shows channel type' do
      expect { described_class.start(%w[channels --no-color]) }.to output(/CliAdapter/).to_stdout
    end

    it 'shows channel status' do
      expect { described_class.start(%w[channels --no-color]) }.to output(/active/).to_stdout
    end

    it 'shows capabilities' do
      expect { described_class.start(%w[channels --no-color]) }.to output(/text, markdown/).to_stdout
    end

    context 'when daemon not running' do
      before { allow(mock_http).to receive(:get).and_raise(Errno::ECONNREFUSED) }

      it 'shows not running' do
        expect { described_class.start(%w[channels --no-color]) }.to output(/not running/).to_stdout
      end
    end
  end

  describe '#buffer' do
    let(:buffer_data) { { depth: 5, empty: false, max_size: 1000 } }

    let(:buffer_response) do
      response = instance_double(Net::HTTPOK)
      allow(response).to receive(:body).and_return(JSON.generate({ data: buffer_data }))
      response
    end

    before { allow(mock_http).to receive(:get).and_return(buffer_response) }

    it 'outputs buffer header' do
      expect { described_class.start(%w[buffer --no-color]) }.to output(/Sensory Buffer/).to_stdout
    end

    it 'shows depth' do
      expect { described_class.start(%w[buffer --no-color]) }.to output(/5/).to_stdout
    end

    it 'shows max size' do
      expect { described_class.start(%w[buffer --no-color]) }.to output(/1000/).to_stdout
    end

    context 'with --json' do
      it 'outputs JSON' do
        output = capture_stdout { described_class.start(%w[buffer --json]) }
        parsed = JSON.parse(output, symbolize_names: true)
        expect(parsed[:depth]).to eq(5)
      end
    end
  end

  describe '#sessions' do
    let(:sessions_data) { { count: 3, active: true } }

    let(:sessions_response) do
      response = instance_double(Net::HTTPOK)
      allow(response).to receive(:body).and_return(JSON.generate({ data: sessions_data }))
      response
    end

    before { allow(mock_http).to receive(:get).and_return(sessions_response) }

    it 'outputs sessions header' do
      expect { described_class.start(%w[sessions --no-color]) }.to output(/GAIA Sessions/).to_stdout
    end

    it 'shows session count' do
      expect { described_class.start(%w[sessions --no-color]) }.to output(/3/).to_stdout
    end

    it 'shows system active status' do
      expect { described_class.start(%w[sessions --no-color]) }.to output(/true/).to_stdout
    end

    context 'with --json' do
      it 'outputs JSON with count' do
        output = capture_stdout { described_class.start(%w[sessions --json]) }
        parsed = JSON.parse(output, symbolize_names: true)
        expect(parsed[:count]).to eq(3)
      end
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
