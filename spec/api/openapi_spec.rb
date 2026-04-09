# frozen_string_literal: true

require_relative 'api_spec_helper'
require 'legion/api/openapi'

RSpec.describe Legion::API::OpenAPI do
  before(:all) { ApiSpecSetup.configure_settings }

  describe '.spec' do
    subject(:spec) { described_class.spec }

    it 'returns a Hash' do
      expect(spec).to be_a(Hash)
    end

    it 'has openapi version 3.1.0' do
      expect(spec[:openapi]).to eq('3.1.0')
    end

    it 'has info block with title' do
      expect(spec[:info][:title]).to eq('LegionIO REST API')
    end

    it 'has info block with version matching Legion::VERSION' do
      expect(spec[:info][:version]).to eq(Legion::VERSION)
    end

    it 'has paths key' do
      expect(spec).to have_key(:paths)
    end

    it 'includes Lex in tags' do
      tag_names = spec[:tags].map { |t| t[:name] }
      expect(tag_names).to include('Lex')
    end

    it 'has components key' do
      expect(spec).to have_key(:components)
    end

    it 'has tags key' do
      expect(spec).to have_key(:tags)
    end

    it 'has servers key' do
      expect(spec).to have_key(:servers)
    end

    describe 'paths' do
      subject(:paths) { spec[:paths] }

      %w[
        /api/health
        /api/ready
        /api/tasks
        /api/tasks/{id}
        /api/tasks/{id}/logs
        /api/extension_catalog
        /api/extension_catalog/available
        /api/extension_catalog/{name}
        /api/extension_catalog/{name}/runners
        /api/extension_catalog/{name}/runners/{runner_name}
        /api/extension_catalog/{name}/runners/{runner_name}/functions
        /api/extension_catalog/{name}/runners/{runner_name}/functions/{function_name}
        /api/extension_catalog/{name}/runners/{runner_name}/functions/{function_name}/invoke
        /api/nodes
        /api/nodes/{id}
        /api/schedules
        /api/schedules/{id}
        /api/schedules/{id}/logs
        /api/relationships
        /api/relationships/{id}
        /api/chains
        /api/chains/{id}
        /api/settings
        /api/settings/{key}
        /api/events
        /api/events/recent
        /api/transport
        /api/transport/exchanges
        /api/transport/queues
        /api/transport/publish
        /api/hooks
        /api/hooks/{lex_name}/{hook_name}
        /api/lex
        /api/workers
        /api/workers/{id}
        /api/workers/{id}/lifecycle
        /api/workers/{id}/tasks
        /api/workers/{id}/events
        /api/workers/{id}/costs
        /api/workers/{id}/value
        /api/workers/{id}/roi
        /api/teams/{team}/workers
        /api/teams/{team}/costs
        /api/coldstart/ingest
        /api/gaia/status
        /api/openapi.json
      ].each do |route|
        it "includes path #{route}" do
          expect(paths).to have_key(route)
        end
      end

      it 'marks health as security-free' do
        expect(paths['/api/health'][:get][:security]).to eq([])
      end

      it 'marks openapi.json as security-free' do
        expect(paths['/api/openapi.json'][:get][:security]).to eq([])
      end

      it 'has GET /api/tasks with Tasks tag' do
        expect(paths['/api/tasks'][:get][:tags]).to include('Tasks')
      end

      it 'has GET /api/lex with Lex tag' do
        expect(paths['/api/lex'][:get][:tags]).to include('Lex')
      end

      it 'has POST /api/tasks' do
        expect(paths['/api/tasks']).to have_key(:post)
      end

      it 'has DELETE /api/tasks/{id}' do
        expect(paths['/api/tasks/{id}']).to have_key(:delete)
      end

      it 'marks relationships as stub (501 response)' do
        responses = paths['/api/relationships'][:get][:responses]
        expect(responses).to have_key('501')
      end

      it 'marks chains as stub (501 response)' do
        responses = paths['/api/chains'][:get][:responses]
        expect(responses).to have_key('501')
      end

      it 'has PATCH /api/workers/{id}/lifecycle' do
        expect(paths['/api/workers/{id}/lifecycle']).to have_key(:patch)
      end
    end

    describe 'components' do
      subject(:components) { spec[:components] }

      it 'has securitySchemes' do
        expect(components).to have_key(:securitySchemes)
      end

      it 'has BearerAuth security scheme' do
        expect(components[:securitySchemes]).to have_key(:BearerAuth)
      end

      it 'has ApiKeyAuth security scheme' do
        expect(components[:securitySchemes]).to have_key(:ApiKeyAuth)
      end

      it 'has schemas' do
        expect(components).to have_key(:schemas)
      end

      %i[Meta MetaCollection ErrorResponse TaskObject WorkerObject].each do |schema|
        it "has #{schema} schema" do
          expect(components[:schemas]).to have_key(schema)
        end
      end

      it 'ErrorResponse has error and meta properties' do
        error_schema = components[:schemas][:ErrorResponse]
        expect(error_schema[:properties]).to have_key(:error)
        expect(error_schema[:properties]).to have_key(:meta)
      end

      it 'MetaCollection has total, limit, offset properties' do
        meta = components[:schemas][:MetaCollection]
        expect(meta[:properties]).to have_key(:total)
        expect(meta[:properties]).to have_key(:limit)
        expect(meta[:properties]).to have_key(:offset)
      end
    end
  end

  describe '.to_json' do
    it 'returns a String' do
      expect(described_class.to_json).to be_a(String)
    end

    it 'returns valid JSON' do
      expect { JSON.parse(described_class.to_json) }.not_to raise_error
    end

    it 'includes openapi version in JSON output' do
      parsed = JSON.parse(described_class.to_json)
      expect(parsed['openapi']).to eq('3.1.0')
    end

    it 'includes paths in JSON output' do
      parsed = JSON.parse(described_class.to_json)
      expect(parsed['paths']).to be_a(Hash)
    end

    it 'includes components in JSON output' do
      parsed = JSON.parse(described_class.to_json)
      expect(parsed['components']).to be_a(Hash)
    end
  end
end

RSpec.describe 'GET /api/openapi.json' do
  include Rack::Test::Methods

  def app
    Legion::API
  end

  before(:all) { ApiSpecSetup.configure_settings }

  it 'returns 200' do
    get '/api/openapi.json'
    expect(last_response.status).to eq(200)
  end

  it 'returns JSON content-type' do
    get '/api/openapi.json'
    expect(last_response.content_type).to include('application/json')
  end

  it 'returns valid JSON' do
    get '/api/openapi.json'
    expect { JSON.parse(last_response.body) }.not_to raise_error
  end

  it 'includes openapi version' do
    get '/api/openapi.json'
    parsed = JSON.parse(last_response.body)
    expect(parsed['openapi']).to eq('3.1.0')
  end
end
