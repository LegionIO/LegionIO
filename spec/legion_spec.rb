# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion do
  it 'has a version number' do
    expect(Legion::VERSION).not_to be nil
  end

  it 'version is a string' do
    expect(Legion::VERSION).to be_a(String)
  end

  it 'responds to start' do
    expect(described_class).to respond_to(:start)
  end

  it 'responds to shutdown' do
    expect(described_class).to respond_to(:shutdown)
  end

  it 'responds to reload' do
    expect(described_class).to respond_to(:reload)
  end
end
