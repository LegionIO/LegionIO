# frozen_string_literal: true

require 'spec_helper'
require 'sinatra/base'
require 'legion/extensions/builders/routes'
require 'legion/api/router'

RSpec.describe 'Extension route registration boot order' do
  let(:router) { Legion::API::Router.new }

  let(:fake_runner_module) do
    Module.new do
      def begin_imprint; end

      def send_chat_message; end
    end
  end

  let(:extension_instance) do
    runner_mod = fake_runner_module
    klass = Class.new do
      include Legion::Extensions::Helpers::Logger
      include Legion::Extensions::Builder::Routes

      define_method(:extension_name) { 'coldstart' }
      define_method(:lex_name) { 'coldstart' }
      define_method(:lex_class) { 'Lex::Coldstart' }
      define_method(:amqp_prefix) { 'lex.coldstart' }
    end
    instance = klass.new
    instance.instance_variable_set(:@runners, {
                                     coldstart: {
                                       runner_name:   'coldstart',
                                       runner_class:  'Legion::Extensions::Coldstart::Runners::Coldstart',
                                       runner_module: runner_mod
                                     }
                                   })
    instance
  end

  before do
    allow(Legion::Settings).to receive(:dig).and_return(nil)
    allow(Legion::Settings).to receive(:dig).with(:api, :lex_routes).and_return(nil)
  end

  describe 'routes built without API present' do
    before do
      hide_const('Legion::API')
      extension_instance.build_routes
    end

    it 'populates @routes hash with route entries' do
      expect(extension_instance.routes).not_to be_empty
      expect(extension_instance.routes.size).to eq(2)
    end

    it 'includes the expected function names' do
      functions = extension_instance.routes.values.map { |r| r[:function] }
      expect(functions).to contain_exactly(:begin_imprint, :send_chat_message)
    end
  end

  describe 'register_extension_routes_with_api_router backfill' do
    subject(:service) { Legion::Service.allocate }

    before do
      allow(Legion::API).to receive(:router).and_return(router)

      hide_const('Legion::API')
      extension_instance.build_routes

      stub_const('Legion::API', Class.new(Sinatra::Base) do
        class << self
          attr_accessor :router
        end
      end)
      Legion::API.router = router
      allow(Legion::Extensions).to receive(:loaded_extension_modules).and_return([extension_instance])
    end

    it 'backfills all built routes into the API router' do
      service.send(:register_extension_routes_with_api_router)

      registered = router.extension_routes
      expect(registered.size).to eq(2)
    end

    it 'registers routes with correct keys' do
      service.send(:register_extension_routes_with_api_router)

      route = router.find_extension_route('coldstart', 'runners', 'coldstart', 'begin_imprint')
      expect(route).not_to be_nil
      expect(route[:lex_name]).to eq('coldstart')
      expect(route[:method_name]).to eq('begin_imprint')
      expect(route[:runner_class]).to eq('Legion::Extensions::Coldstart::Runners::Coldstart')
    end

    it 'includes component_type and amqp_prefix' do
      service.send(:register_extension_routes_with_api_router)

      route = router.find_extension_route('coldstart', 'runners', 'coldstart', 'send_chat_message')
      expect(route[:component_type]).to eq('runners')
      expect(route[:amqp_prefix]).to eq('lex.coldstart')
    end

    it 'is idempotent when called multiple times' do
      service.send(:register_extension_routes_with_api_router)
      service.send(:register_extension_routes_with_api_router)

      registered = router.extension_routes
      expect(registered.size).to eq(2)
    end
  end

  describe 'hot-load registration (API already present)' do
    before do
      allow(Legion::API).to receive(:router).and_return(router)
      extension_instance.build_routes
    end

    it 'registers directly with the API router during build_routes' do
      registered = router.extension_routes
      expect(registered.size).to eq(2)
    end
  end
end
