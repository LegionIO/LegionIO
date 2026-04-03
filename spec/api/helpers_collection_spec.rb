# frozen_string_literal: true

require_relative 'api_spec_helper'
require 'sinatra/base'

class HelperCollectionDataset
  attr_reader :count_calls

  def initialize(items)
    @items = items
    @count_calls = 0
  end

  def count
    @count_calls += 1
    @items.length
  end

  def limit(limit, offset)
    @items.slice(offset, limit) || []
  end
end

RSpec.describe 'API helper collection responses' do
  include Rack::Test::Methods

  before(:all) { ApiSpecSetup.configure_settings }

  let(:dataset) { HelperCollectionDataset.new(Array.new(50) { |index| { id: index + 1 } }) }

  let(:test_app) do
    current_dataset = dataset

    Class.new(Sinatra::Base) do
      helpers Legion::API::Helpers

      set :show_exceptions, false
      set :raise_errors, false
      set :host_authorization, permitted: :any
      set :dataset, current_dataset

      get '/items' do
        json_collection(settings.dataset)
      end
    end
  end

  def app
    test_app
  end

  it 'avoids counting by default on a full page' do
    get '/items?limit=25'

    expect(last_response.status).to eq(200)
    body = Legion::JSON.load(last_response.body)
    expect(dataset.count_calls).to eq(0)
    expect(body[:meta][:count]).to eq(25)
    expect(body[:meta]).not_to have_key(:total)
    expect(body[:meta][:has_more]).to be(true)
  end

  it 'includes total when explicitly requested' do
    get '/items?limit=25&include_total=true'

    expect(last_response.status).to eq(200)
    body = Legion::JSON.load(last_response.body)
    expect(dataset.count_calls).to eq(1)
    expect(body[:meta][:total]).to eq(50)
    expect(body[:meta][:has_more]).to be(true)
  end
end
