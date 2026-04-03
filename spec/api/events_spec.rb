# frozen_string_literal: true

require_relative 'api_spec_helper'

RSpec.describe 'Events API' do
  include Rack::Test::Methods

  def app
    Legion::API
  end

  before(:all) { ApiSpecSetup.configure_settings }

  describe 'GET /api/events/recent' do
    it 'returns recent events as an array' do
      get '/api/events/recent'
      expect(last_response.status).to eq(200)
      body = Legion::JSON.load(last_response.body)
      expect(body[:data]).to be_an(Array)
    end

    it 'respects count parameter' do
      get '/api/events/recent?count=5'
      expect(last_response.status).to eq(200)
    end
  end

  describe '.stop_queue_stream' do
    it 'signals and joins the worker thread during cleanup' do
      queue = Queue.new
      worker = instance_double(Thread, alive?: true)
      listener = double('listener')

      allow(worker).to receive(:join)
      allow(Legion::Events).to receive(:off)

      Legion::API::Routes::Events.stop_queue_stream(queue: queue, worker: worker, listener: listener)

      expect(Legion::Events).to have_received(:off).with('*', listener)
      expect(worker).to have_received(:join).with(0.1)
      expect(queue.pop).to equal(Legion::API::Routes::Events::SSE_STOP)
    end
  end
end
