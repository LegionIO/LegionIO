# frozen_string_literal: true

require 'spec_helper'
require 'rack/test'
require 'sinatra/base'
require 'legion/api/helpers'
require 'legion/api/gaia'

RSpec.describe 'Gaia API routes' do
  include Rack::Test::Methods

  before(:all) do
    Legion::Logging.setup(log_level: 'fatal', level: 'fatal', trace: false)
    Legion::Settings.load(config_dir: File.expand_path('../../..', __dir__))
  end

  let(:test_app) do
    Class.new(Sinatra::Base) do
      helpers Legion::API::Helpers

      set :show_exceptions, false
      set :raise_errors, false
      set :host_authorization, permitted: :any

      error do
        content_type :json
        err = env['sinatra.error']
        status 500
        Legion::JSON.dump({ error: { code: 'internal_error', message: err.message } })
      end

      register Legion::API::Routes::Gaia
    end
  end

  def app
    test_app
  end

  describe 'GET /api/gaia/status' do
    context 'when gaia is not started' do
      it 'returns 503' do
        get '/api/gaia/status'
        expect(last_response.status).to eq(503)
      end

      it 'returns started: false' do
        get '/api/gaia/status'
        body = Legion::JSON.load(last_response.body)
        expect(body[:data][:started]).to eq(false)
      end
    end
  end

  describe 'GET /api/gaia/channels' do
    context 'when gaia is not started' do
      it 'returns 503' do
        get '/api/gaia/channels'
        expect(last_response.status).to eq(503)
      end
    end

    context 'when gaia is started' do
      let(:mock_registry) { double('ChannelRegistry') }
      let(:mock_adapter) { double('CliAdapter', started?: true, capabilities: %w[text]) }

      before do
        gaia = Module.new
        stub_const('Legion::Gaia', gaia)
        allow(gaia).to receive(:started?).and_return(true)
        allow(gaia).to receive(:channel_registry).and_return(mock_registry)
        allow(mock_registry).to receive(:active_channels).and_return([:cli])
        allow(mock_registry).to receive(:adapter_for).with(:cli).and_return(mock_adapter)
        allow(mock_adapter).to receive(:respond_to?).with(:capabilities).and_return(true)
        allow(mock_adapter).to receive_message_chain(:class, :name).and_return('Legion::Gaia::Channels::CliAdapter')
      end

      it 'returns 200 with channel list' do
        get '/api/gaia/channels'
        expect(last_response.status).to eq(200)
        body = Legion::JSON.load(last_response.body)
        expect(body[:data][:channels]).to be_an(Array)
        expect(body[:data][:count]).to eq(1)
      end

      it 'includes channel details' do
        get '/api/gaia/channels'
        body = Legion::JSON.load(last_response.body)
        ch = body[:data][:channels].first
        expect(ch[:id]).to eq('cli')
        expect(ch[:started]).to eq(true)
      end
    end
  end

  describe 'GET /api/gaia/buffer' do
    context 'when gaia is not started' do
      it 'returns 503' do
        get '/api/gaia/buffer'
        expect(last_response.status).to eq(503)
      end
    end

    context 'when gaia is started' do
      let(:mock_buffer) { double('SensoryBuffer', size: 3, empty?: false) }

      before do
        gaia = Module.new
        stub_const('Legion::Gaia', gaia)
        buffer_class = Class.new
        buffer_class.const_set(:MAX_BUFFER_SIZE, 1000)
        stub_const('Legion::Gaia::SensoryBuffer', buffer_class)
        allow(gaia).to receive(:started?).and_return(true)
        allow(gaia).to receive(:sensory_buffer).and_return(mock_buffer)
      end

      it 'returns buffer depth' do
        get '/api/gaia/buffer'
        expect(last_response.status).to eq(200)
        body = Legion::JSON.load(last_response.body)
        expect(body[:data][:depth]).to eq(3)
        expect(body[:data][:empty]).to eq(false)
      end

      it 'returns max_size' do
        get '/api/gaia/buffer'
        body = Legion::JSON.load(last_response.body)
        expect(body[:data][:max_size]).to eq(1000)
      end
    end
  end

  describe 'GET /api/gaia/sessions' do
    context 'when gaia is not started' do
      it 'returns 503' do
        get '/api/gaia/sessions'
        expect(last_response.status).to eq(503)
      end
    end

    context 'when gaia is started' do
      let(:mock_store) { double('SessionStore', size: 5) }

      before do
        gaia = Module.new
        stub_const('Legion::Gaia', gaia)
        allow(gaia).to receive(:started?).and_return(true)
        allow(gaia).to receive(:session_store).and_return(mock_store)
      end

      it 'returns session count' do
        get '/api/gaia/sessions'
        expect(last_response.status).to eq(200)
        body = Legion::JSON.load(last_response.body)
        expect(body[:data][:count]).to eq(5)
        expect(body[:data][:active]).to eq(true)
      end
    end
  end
end
