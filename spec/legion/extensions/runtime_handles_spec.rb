# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::Extensions do
  before do
    described_class.reset_runtime_handles!
    described_class.instance_variable_set(:@loaded_extensions, %w[lex-example])
  end

  after do
    described_class.reset_runtime_handles!
    described_class.instance_variable_set(:@loaded_extensions, nil)
  end

  it 'exposes extension handles without requiring callers to read ivars' do
    described_class.register_extension_handle('lex-example', state: :loaded)
    described_class.transition_extension_handle('lex-example', :running)

    handle = described_class.extension_handle('lex-example')

    expect(handle.state).to eq(:running)
    expect(described_class.extension_handles.map(&:lex_name)).to contain_exactly('lex-example')
    expect(described_class.loaded_extensions).to eq(%w[lex-example])
  end

  it 'blocks dispatch when a handle is stopping or reloading' do
    described_class.register_extension_handle('lex-example', state: :running)
    expect(described_class.dispatch_allowed?('lex-example')).to be true

    described_class.update_extension_handle('lex-example', reload_state: :updating)
    expect(described_class.dispatch_allowed?('lex-example')).to be false

    described_class.update_extension_handle('lex-example', reload_state: :idle, state: :stopping)
    expect(described_class.dispatch_allowed?('lex-example')).to be false
  end

  it 'does not expose modules for handles that are not dispatchable' do
    ext_mod = Module.new do
      def self.name = 'Legion::Extensions::Example'
      def self.runner_modules = []
    end
    described_class.const_set(:Example, ext_mod)
    described_class.register_extension_handle('lex-example', state: :failed)

    expect(described_class.loaded_extension_modules).to be_empty
  ensure
    described_class.send(:remove_const, :Example) if described_class.const_defined?(:Example, false)
  end

  it 'provides a scoped reload hook that quiesces, cleans callable state, and reopens dispatch' do
    described_class.register_extension_handle('lex-example', state: :running, tools: ['legion-example-runner-call'])
    allow(described_class).to receive(:unregister_capabilities)
    stub_const('Legion::Ingress', Module.new)
    allow(Legion::Ingress).to receive(:reset_runner_cache!)

    expect(described_class.reload_extension('lex-example')).to be true

    handle = described_class.extension_handle('lex-example')
    expect(handle.state).to eq(:running)
    expect(handle.reload_state).to eq(:idle)
    expect(handle.last_error).to be_nil
    expect(described_class).to have_received(:unregister_capabilities).with('lex-example')
    expect(Legion::Ingress).to have_received(:reset_runner_cache!)
  end
end
