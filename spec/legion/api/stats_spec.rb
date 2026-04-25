# frozen_string_literal: true

require 'spec_helper'
require 'legion/api/stats'

RSpec.describe Legion::API::Routes::Stats do
  before do
    Legion::Extensions.reset_runtime_handles!
    Legion::Extensions.instance_variable_set(:@loaded_extensions, %w[legacy-only])
  end

  after do
    Legion::Extensions.reset_runtime_handles!
    Legion::Extensions.instance_variable_set(:@loaded_extensions, nil)
  end

  it 'counts loaded and running extensions from runtime handles instead of ivars' do
    Legion::Extensions.register_extension_handle('lex-loaded', state: :loaded)
    Legion::Extensions.register_extension_handle('lex-running', state: :running)

    stats = described_class.collect_extensions

    expect(stats[:loaded]).to eq(2)
    expect(stats[:running]).to eq(1)
  end
end
