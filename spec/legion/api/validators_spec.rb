# frozen_string_literal: true

require 'spec_helper'
require 'rack/test'
require 'sinatra/base'
require 'legion/api/helpers'
require 'legion/api/validators'

RSpec.describe Legion::API::Validators do
  include Rack::Test::Methods

  let(:test_app) do
    Class.new(Sinatra::Base) do
      helpers Legion::API::Helpers
      helpers Legion::API::Validators

      set :show_exceptions, false
      set :raise_errors, false
      set :host_authorization, permitted: :any

      post '/test/required' do
        body = parse_request_body
        validate_required!(body, :name, :type)
        json_response({ valid: true })
      end

      post '/test/length' do
        body = parse_request_body
        validate_string_length!(body[:name], field: 'name', max: 10)
        json_response({ valid: true })
      end

      post '/test/enum' do
        body = parse_request_body
        validate_enum!(body[:status], field: 'status', allowed: %w[active paused])
        json_response({ valid: true })
      end

      post '/test/uuid' do
        body = parse_request_body
        validate_uuid!(body[:id], field: 'id')
        json_response({ valid: true })
      end
    end
  end

  def app
    test_app
  end

  it 'passes when all required fields present' do
    post '/test/required', Legion::JSON.dump({ name: 'test', type: 'a' }),
         'CONTENT_TYPE' => 'application/json'
    expect(last_response.status).to eq(200)
  end

  it 'rejects missing required fields' do
    post '/test/required', Legion::JSON.dump({ name: 'test' }),
         'CONTENT_TYPE' => 'application/json'
    expect(last_response.status).to eq(400)
    body = Legion::JSON.load(last_response.body)
    expect(body[:error][:code]).to eq('missing_fields')
  end

  it 'rejects too-long strings' do
    post '/test/length', Legion::JSON.dump({ name: 'x' * 20 }),
         'CONTENT_TYPE' => 'application/json'
    expect(last_response.status).to eq(400)
    body = Legion::JSON.load(last_response.body)
    expect(body[:error][:code]).to eq('field_too_long')
  end

  it 'accepts valid enum values' do
    post '/test/enum', Legion::JSON.dump({ status: 'active' }),
         'CONTENT_TYPE' => 'application/json'
    expect(last_response.status).to eq(200)
  end

  it 'rejects invalid enum values' do
    post '/test/enum', Legion::JSON.dump({ status: 'invalid' }),
         'CONTENT_TYPE' => 'application/json'
    expect(last_response.status).to eq(400)
    body = Legion::JSON.load(last_response.body)
    expect(body[:error][:code]).to eq('invalid_value')
  end

  it 'accepts valid UUIDs' do
    post '/test/uuid', Legion::JSON.dump({ id: '550e8400-e29b-41d4-a716-446655440000' }),
         'CONTENT_TYPE' => 'application/json'
    expect(last_response.status).to eq(200)
  end

  it 'rejects invalid UUIDs' do
    post '/test/uuid', Legion::JSON.dump({ id: 'not-a-uuid' }),
         'CONTENT_TYPE' => 'application/json'
    expect(last_response.status).to eq(400)
    body = Legion::JSON.load(last_response.body)
    expect(body[:error][:code]).to eq('invalid_format')
  end
end
