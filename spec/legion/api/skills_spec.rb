# frozen_string_literal: true

require 'spec_helper'
require 'rack/test'
require 'legion/api'

RSpec.describe Legion::API, 'skills routes' do
  include Rack::Test::Methods

  def app
    Legion::API
  end

  before do
    skill_dbl = double(:skill,
                       skill_name:    'brainstorming',
                       namespace:     'superpowers',
                       description:   'Brainstorm',
                       trigger:       :on_demand,
                       follows_skill: nil,
                       steps:         %i[step1])
    registry = Module.new do
      define_singleton_method(:all) { [skill_dbl] }
      define_singleton_method(:find) do |key|
        return nil unless key == 'superpowers:brainstorming'

        skill_dbl
      end
    end
    stub_const('Legion::LLM::Skills::Registry', registry)
  end

  describe 'GET /api/skills' do
    it 'returns 200 with skill list' do
      get '/api/skills'
      expect(last_response.status).to eq(200)
      body = Legion::JSON.load(last_response.body)
      expect(body[:data]).to be_an(Array)
    end
  end

  describe 'GET /api/skills/:namespace/:name' do
    it 'returns 200 for known skill' do
      get '/api/skills/superpowers/brainstorming'
      expect(last_response.status).to eq(200)
    end

    it 'returns 404 for unknown skill' do
      get '/api/skills/unknown/nope'
      expect(last_response.status).to eq(404)
    end
  end

  describe 'DELETE /api/skills/active/:conversation_id' do
    let(:conv_store) do
      Module.new do
        def self.cancel_skill!(_id) = nil
      end
    end

    before { stub_const('Legion::LLM::ConversationStore', conv_store) }

    it 'returns 204 when skill was active' do
      allow(conv_store).to receive(:cancel_skill!)
        .with('conv-123').and_return({ skill_key: 'superpowers:brainstorming' })
      allow(Legion::Events).to receive(:emit)
      delete '/api/skills/active/conv-123'
      expect(last_response.status).to eq(204)
    end

    it 'returns 204 when no active skill' do
      allow(conv_store).to receive(:cancel_skill!).and_return(nil)
      delete '/api/skills/active/conv-none'
      expect(last_response.status).to eq(204)
    end
  end
end
