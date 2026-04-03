# frozen_string_literal: true

require 'spec_helper'
require 'sinatra/base'
require 'legion/api'

RSpec.describe Legion::API do
  let(:api_class) { Class.new(described_class) }

  describe '.mount_library_routes' do
    it 'prefers loaded library route modules and tracks them in discovery' do
      llm_routes = Module.new
      stub_const('Legion::LLM::Routes', llm_routes)
      allow(api_class).to receive(:register)

      api_class.mount_library_routes('llm', Legion::API::Routes::Llm, 'Legion::LLM::Routes')

      expect(api_class.router.library_routes['llm']).to eq(llm_routes)
      expect(api_class).to have_received(:register).with(llm_routes)
    end

    it 'falls back to core routes when the library route module is unavailable' do
      allow(api_class).to receive(:register)

      api_class.mount_library_routes('llm', Legion::API::Routes::Llm, 'Legion::LLM::Routes')

      expect(api_class.router.library_routes).to be_empty
      expect(api_class).to have_received(:register).with(Legion::API::Routes::Llm)
    end
  end

  describe '.register_library_routes' do
    it 'does not re-register the same route module twice' do
      allow(api_class).to receive(:register)
      routes_module = Module.new

      api_class.register_library_routes('apollo', routes_module)
      api_class.register_library_routes('apollo', routes_module)

      expect(api_class.router.library_routes['apollo']).to eq(routes_module)
      expect(api_class).to have_received(:register).once.with(routes_module)
    end
  end
end
