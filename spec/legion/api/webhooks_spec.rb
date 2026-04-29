# frozen_string_literal: true

require 'spec_helper'
require 'rack/test'
require 'sinatra/base'
require 'legion/api/helpers'
require 'legion/api/webhooks'

RSpec.describe 'Webhooks API routes' do
  include Rack::Test::Methods

  let(:test_app) do
    Class.new(Sinatra::Base) do
      helpers Legion::API::Helpers

      set :show_exceptions, false
      set :raise_errors, false
      set :host_authorization, permitted: :any

      register Legion::API::Routes::Webhooks
    end
  end

  def app
    test_app
  end

  describe 'GET /api/webhooks' do
    it 'uses the loaded Legion::Webhooks implementation' do
      allow(Legion::Webhooks).to receive(:list).and_return([])

      get '/api/webhooks'

      expect(last_response.status).to eq(200)
      body = Legion::JSON.load(last_response.body)
      expect(body[:data]).to eq([])
    end
  end
end
