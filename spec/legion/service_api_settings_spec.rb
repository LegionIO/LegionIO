# frozen_string_literal: true

require 'spec_helper'
require 'sinatra/base'
require 'legion/api/default_settings'

RSpec.describe 'Service API settings integration' do
  it 'reads port from Settings[:api] without fallback' do
    previous_port = Legion::Settings[:api][:port]
    Legion::Settings[:api][:port] = 9999
    expect(Legion::Settings[:api][:port]).to eq(9999)
  ensure
    Legion::Settings[:api][:port] = previous_port
  end

  it 'reads puma threads from Settings[:api][:puma]' do
    expect(Legion::Settings[:api][:puma][:min_threads]).to eq(10)
    expect(Legion::Settings[:api][:puma][:max_threads]).to eq(16)
  end
end
