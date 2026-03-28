# frozen_string_literal: true

require_relative 'api_spec_helper'
require 'legion/extensions/hooks/base'
require 'legion/ingress'

RSpec.describe 'LexDispatch hook-aware dispatch' do
  include Rack::Test::Methods

  def app
    Legion::API
  end

  before(:all) { ApiSpecSetup.configure_settings }

  # A stub runner class that is NOT a Hooks::Base subclass
  let(:plain_runner_class) do
    klass = Class.new do
      def self.name
        'Lex::TestExt::Runners::Webhook'
      end
    end
    stub_const('Lex::TestExt::Runners::Webhook', klass)
    klass
  end

  # A Hooks::Base subclass with token verification and header routing
  let(:hook_class) do
    klass = Class.new(Legion::Extensions::Hooks::Base) do
      route_header 'X-Event-Type', 'push' => :on_push

      verify_token header: 'Authorization', secret: 'test-secret'

      def runner_class
        nil
      end
    end
    # Give it a name so Class#name works in error messages
    stub_const('Lex::TestExt::Hooks::Github', klass)
    klass
  end

  # Register routes before each test group (reset router between groups)
  before do
    Legion::API.router.clear!
    plain_runner_class # ensure constant is defined before registration
  end

  after do
    Legion::API.router.clear!
  end

  describe 'scenario 1: Hooks::Base subclass with failing verification' do
    before do
      Legion::API.router.register_extension_route(
        lex_name:       'test_ext',
        component_type: 'hooks',
        component_name: 'github',
        method_name:    'receive',
        runner_class:   hook_class,
        amqp_prefix:    '',
        definition:     nil
      )
    end

    it 'returns 401 when Authorization header is missing' do
      post '/api/extensions/test_ext/hooks/github/receive',
           Legion::JSON.dump({ ref: 'refs/heads/main' }),
           'CONTENT_TYPE'      => 'application/json',
           'HTTP_X_EVENT_TYPE' => 'push'
      # No Authorization header → verify_token returns false
      expect(last_response.status).to eq(401)
      body = Legion::JSON.load(last_response.body)
      expect(body[:status]).to eq('failed')
      expect(body[:error][:code]).to eq(401)
      expect(body[:error][:message]).to eq('hook verification failed')
    end

    it 'returns 401 when Authorization header value is wrong' do
      post '/api/extensions/test_ext/hooks/github/receive',
           Legion::JSON.dump({ ref: 'refs/heads/main' }),
           'CONTENT_TYPE'       => 'application/json',
           'HTTP_X_EVENT_TYPE'  => 'push',
           'HTTP_AUTHORIZATION' => 'wrong-secret'
      expect(last_response.status).to eq(401)
    end
  end

  describe 'scenario 2: Hooks::Base subclass with nil route' do
    before do
      Legion::API.router.register_extension_route(
        lex_name:       'test_ext',
        component_type: 'hooks',
        component_name: 'github',
        method_name:    'receive',
        runner_class:   hook_class,
        amqp_prefix:    '',
        definition:     nil
      )
    end

    it 'returns 422 when the event type does not match any mapping' do
      post '/api/extensions/test_ext/hooks/github/receive',
           Legion::JSON.dump({ ref: 'refs/heads/main' }),
           'CONTENT_TYPE'       => 'application/json',
           'HTTP_AUTHORIZATION' => 'test-secret',
           'HTTP_X_EVENT_TYPE'  => 'unknown_event'
      # verify passes, but route returns nil (no mapping for 'unknown_event')
      expect(last_response.status).to eq(422)
      body = Legion::JSON.load(last_response.body)
      expect(body[:status]).to eq('failed')
      expect(body[:error][:code]).to eq(422)
      expect(body[:error][:message]).to eq('hook could not route this event')
    end
  end

  describe 'scenario 3: Hooks::Base subclass with successful verify+route' do
    before do
      Legion::API.router.register_extension_route(
        lex_name:       'test_ext',
        component_type: 'hooks',
        component_name: 'github',
        method_name:    'receive',
        runner_class:   hook_class,
        amqp_prefix:    '',
        definition:     nil
      )

      allow(Legion::Ingress).to receive(:run).and_return({ status: 'success', result: { dispatched: true } })
    end

    it 'dispatches to Ingress with source: hook and the routed function' do
      post '/api/extensions/test_ext/hooks/github/receive',
           Legion::JSON.dump({ ref: 'refs/heads/main' }),
           'CONTENT_TYPE'       => 'application/json',
           'HTTP_AUTHORIZATION' => 'test-secret',
           'HTTP_X_EVENT_TYPE'  => 'push'

      expect(Legion::Ingress).to have_received(:run).with(
        hash_including(
          function:      :on_push,
          source:        'hook',
          generate_task: true,
          check_subtask: true
        )
      )
      expect(last_response.status).to eq(200)
      body = Legion::JSON.load(last_response.body)
      expect(body[:status]).to eq('success')
    end
  end

  describe 'scenario 4: non-Base runner with component_type hooks passes through normally' do
    before do
      Legion::API.router.register_extension_route(
        lex_name:       'test_ext',
        component_type: 'hooks',
        component_name: 'webhook',
        method_name:    'receive',
        runner_class:   plain_runner_class,
        amqp_prefix:    '',
        definition:     nil
      )

      allow(Legion::Ingress).to receive(:run).and_return({ status: 'success', result: nil })
    end

    it 'calls Ingress with source: lex_dispatch (not hook lifecycle)' do
      post '/api/extensions/test_ext/hooks/webhook/receive',
           Legion::JSON.dump({ event: 'ping' }),
           'CONTENT_TYPE' => 'application/json'

      expect(Legion::Ingress).to have_received(:run).with(
        hash_including(
          source:   'lex_dispatch',
          function: :receive
        )
      )
      expect(last_response.status).to eq(200)
    end
  end
end
