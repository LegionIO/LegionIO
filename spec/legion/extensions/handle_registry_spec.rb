# frozen_string_literal: true

require 'spec_helper'
require 'legion/extensions/handle_registry'

RSpec.describe Legion::Extensions::HandleRegistry do
  subject(:registry) { described_class.new }

  let(:spec) do
    instance_double(Gem::Specification,
                    name:    'lex-example',
                    version: Gem::Version.new('1.2.3'),
                    gem_dir: '/gems/lex-example-1.2.3')
  end

  it 'registers an extension handle with runtime metadata' do
    handle = registry.register('lex-example', spec: spec, state: :loaded)

    expect(handle.lex_name).to eq('lex-example')
    expect(handle.gem_name).to eq('lex-example')
    expect(handle.active_version).to eq(Gem::Version.new('1.2.3'))
    expect(handle.gem_dir).to eq('/gems/lex-example-1.2.3')
    expect(handle.state).to eq(:loaded)
    expect(handle.reload_state).to eq(:idle)
    expect(handle.loaded_at).to be_a(Time)
  end

  it 'transitions state without replacing unrelated metadata' do
    registry.register('lex-example', spec: spec)

    handle = registry.transition('lex-example', :running)

    expect(handle.state).to eq(:running)
    expect(handle.active_version).to eq(Gem::Version.new('1.2.3'))
  end

  it 'updates controlled fields on an existing handle' do
    registry.register('lex-example', spec: spec)

    handle = registry.update('lex-example', reload_state: :pending, last_error: 'newer version installed')

    expect(handle.reload_state).to eq(:pending)
    expect(handle.last_error).to eq('newer version installed')
  end

  it 'returns state-filtered handle collections' do
    registry.register('lex-loaded', state: :loaded)
    registry.register('lex-running', state: :running)

    expect(registry.loaded.map(&:lex_name)).to contain_exactly('lex-loaded', 'lex-running')
    expect(registry.running.map(&:lex_name)).to contain_exactly('lex-running')
  end

  it 'does not treat stopped or failed handles as loaded' do
    registry.register('lex-loaded', state: :loaded)
    registry.register('lex-stopped', state: :stopped)
    registry.register('lex-failed', state: :failed)

    expect(registry.loaded.map(&:lex_name)).to contain_exactly('lex-loaded')
  end

  it 'derives pending reload from installed and active versions' do
    handle = registry.register('lex-example',
                               active_version:           '1.2.3',
                               latest_installed_version: '1.2.4')

    expect(handle.pending_reload?).to be true
  end

  it 'reports non-dispatchable handles while reload or stop is in progress' do
    registry.register('lex-example', state: :running, reload_state: :updating)

    expect(registry.fetch('lex-example')).not_to be_dispatchable
  end

  it 'can delete and reset handles' do
    registry.register('lex-example')
    expect(registry.delete('lex-example').lex_name).to eq('lex-example')
    expect(registry.fetch('lex-example')).to be_nil

    registry.register('lex-other')
    registry.reset!
    expect(registry.all).to be_empty
  end
end
