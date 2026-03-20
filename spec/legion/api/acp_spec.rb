# frozen_string_literal: true

require 'spec_helper'
require 'rack/test'
require 'sinatra/base'
require 'legion/api/helpers'
require 'legion/api/validators'
require 'legion/api/acp'

RSpec.describe 'ACP API routes' do
  include Rack::Test::Methods

  before(:all) do
    Legion::Logging.setup(log_level: 'fatal', level: 'fatal', trace: false)
    Legion::Settings.load(config_dir: File.expand_path('../../..', __dir__))
    loader = Legion::Settings.loader
    loader.settings[:client] = { name: 'test-node', ready: true }
    loader.settings[:data] = { connected: false }
    loader.settings[:transport] = { connected: false }
    loader.settings[:extensions] = {}
  end

  let(:test_app) do
    Class.new(Sinatra::Base) do
      helpers Legion::API::Helpers
      helpers Legion::API::Validators

      set :show_exceptions, false
      set :raise_errors, false
      set :host_authorization, permitted: :any

      register Legion::API::Routes::Acp
    end
  end

  def app
    test_app
  end

  # ──────────────────────────────────────────────────────────
  # GET /.well-known/agent.json
  # ──────────────────────────────────────────────────────────

  describe 'GET /.well-known/agent.json' do
    it 'returns 200' do
      get '/.well-known/agent.json'
      expect(last_response.status).to eq(200)
    end

    it 'returns a name field' do
      get '/.well-known/agent.json'
      body = Legion::JSON.load(last_response.body)
      expect(body[:name]).to be_a(String)
    end

    it 'returns protocol acp/1.0' do
      get '/.well-known/agent.json'
      body = Legion::JSON.load(last_response.body)
      expect(body[:protocol]).to eq('acp/1.0')
    end

    it 'returns version 2.0' do
      get '/.well-known/agent.json'
      body = Legion::JSON.load(last_response.body)
      expect(body[:version]).to eq('2.0')
    end

    it 'returns defaultInputModes as an array' do
      get '/.well-known/agent.json'
      body = Legion::JSON.load(last_response.body)
      expect(body[:defaultInputModes]).to be_an(Array)
    end

    it 'returns defaultOutputModes as an array' do
      get '/.well-known/agent.json'
      body = Legion::JSON.load(last_response.body)
      expect(body[:defaultOutputModes]).to be_an(Array)
    end

    it 'returns authentication schemes' do
      get '/.well-known/agent.json'
      body = Legion::JSON.load(last_response.body)
      expect(body[:authentication]).to have_key(:schemes)
    end

    it 'returns capabilities as an array' do
      get '/.well-known/agent.json'
      body = Legion::JSON.load(last_response.body)
      expect(body[:capabilities]).to be_an(Array)
    end

    it 'returns content-type application/json' do
      get '/.well-known/agent.json'
      expect(last_response.content_type).to include('application/json')
    end
  end

  # ──────────────────────────────────────────────────────────
  # POST /api/acp/tasks
  # ──────────────────────────────────────────────────────────

  describe 'POST /api/acp/tasks' do
    before do
      ingress_mod = Module.new do
        def self.run(**_kwargs)
          { task_id: 42, success: true }
        end
      end
      stub_const('Legion::Ingress', ingress_mod)
    end

    it 'returns 202' do
      post '/api/acp/tasks',
           Legion::JSON.dump({ input: { text: 'hello' } }),
           'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eq(202)
    end

    it 'returns queued status in data' do
      post '/api/acp/tasks',
           Legion::JSON.dump({ input: { text: 'hello' } }),
           'CONTENT_TYPE' => 'application/json'
      body = Legion::JSON.load(last_response.body)
      expect(body[:data][:status]).to eq('queued')
    end

    it 'returns task_id in data' do
      post '/api/acp/tasks',
           Legion::JSON.dump({ input: { text: 'hello' } }),
           'CONTENT_TYPE' => 'application/json'
      body = Legion::JSON.load(last_response.body)
      expect(body[:data][:task_id]).to eq(42)
    end

    it 'accepts empty input' do
      post '/api/acp/tasks',
           Legion::JSON.dump({}),
           'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eq(202)
    end

    it 'passes runner_class to Ingress.run when provided' do
      expect(Legion::Ingress).to receive(:run).with(
        hash_including(runner_class: 'MyRunner')
      ).and_return({ task_id: 1, success: true })
      post '/api/acp/tasks',
           Legion::JSON.dump({ input: {}, runner_class: 'MyRunner' }),
           'CONTENT_TYPE' => 'application/json'
    end

    it 'passes function to Ingress.run when provided' do
      expect(Legion::Ingress).to receive(:run).with(
        hash_including(function: 'my_func')
      ).and_return({ task_id: 1, success: true })
      post '/api/acp/tasks',
           Legion::JSON.dump({ input: {}, function: 'my_func' }),
           'CONTENT_TYPE' => 'application/json'
    end
  end

  # ──────────────────────────────────────────────────────────
  # GET /api/acp/tasks/:id
  # ──────────────────────────────────────────────────────────

  describe 'GET /api/acp/tasks/:id' do
    context 'when task does not exist' do
      it 'returns 404' do
        get '/api/acp/tasks/99999'
        expect(last_response.status).to eq(404)
      end

      it 'returns an error body' do
        get '/api/acp/tasks/99999'
        body = Legion::JSON.load(last_response.body)
        expect(body[:error]).not_to be_nil
      end
    end

    context 'when task exists' do
      before do
        data_mod = Module.new
        model_mod = Module.new
        task_record = {
          id:           7,
          status:       'completed',
          result:       'done',
          created_at:   Time.now.utc,
          completed_at: Time.now.utc
        }
        fake_row = double('TaskRow', values: task_record)
        task_model = Module.new do
          define_singleton_method(:[]) { |_id| fake_row }
        end
        stub_const('Legion::Data', data_mod)
        stub_const('Legion::Data::Model', model_mod)
        stub_const('Legion::Data::Model::Task', task_model)
      end

      it 'returns 200' do
        get '/api/acp/tasks/7'
        expect(last_response.status).to eq(200)
      end

      it 'returns task_id in data' do
        get '/api/acp/tasks/7'
        body = Legion::JSON.load(last_response.body)
        expect(body[:data][:task_id]).to eq(7)
      end

      it 'translates completed status correctly' do
        get '/api/acp/tasks/7'
        body = Legion::JSON.load(last_response.body)
        expect(body[:data][:status]).to eq('completed')
      end
    end
  end

  # ──────────────────────────────────────────────────────────
  # DELETE /api/acp/tasks/:id
  # ──────────────────────────────────────────────────────────

  describe 'DELETE /api/acp/tasks/:id' do
    it 'returns 501 not implemented' do
      delete '/api/acp/tasks/1'
      expect(last_response.status).to eq(501)
    end

    it 'returns an error body' do
      delete '/api/acp/tasks/1'
      body = Legion::JSON.load(last_response.body)
      expect(body[:error]).not_to be_nil
    end
  end

  # ──────────────────────────────────────────────────────────
  # translate_status helper
  # ──────────────────────────────────────────────────────────

  describe '#translate_status (via GET /api/acp/tasks/:id)' do
    let(:task_stub_for) do
      lambda do |status_str|
        data_mod = Module.new
        model_mod = Module.new
        task_record = { id: 1, status: status_str, result: nil, created_at: nil, completed_at: nil }
        fake_row = double('TaskRow', values: task_record)
        task_model = Module.new do
          define_singleton_method(:[]) { |_id| fake_row }
        end
        stub_const('Legion::Data', data_mod)
        stub_const('Legion::Data::Model', model_mod)
        stub_const('Legion::Data::Model::Task', task_model)
      end
    end

    it 'maps exception status to failed' do
      task_stub_for.call('exception')
      get '/api/acp/tasks/1'
      body = Legion::JSON.load(last_response.body)
      expect(body[:data][:status]).to eq('failed')
    end

    it 'maps queued status to queued' do
      task_stub_for.call('queued')
      get '/api/acp/tasks/1'
      body = Legion::JSON.load(last_response.body)
      expect(body[:data][:status]).to eq('queued')
    end

    it 'maps unknown status to in_progress' do
      task_stub_for.call('running')
      get '/api/acp/tasks/1'
      body = Legion::JSON.load(last_response.body)
      expect(body[:data][:status]).to eq('in_progress')
    end
  end
end
