# frozen_string_literal: true

require 'spec_helper'
require 'legion/extensions/definitions'

RSpec.describe Legion::Extensions::Definitions do
  let(:klass) do
    Class.new do
      extend Legion::Extensions::Definitions
    end
  end

  describe '.definition' do
    it 'stores a definition for a method' do
      klass.definition :create,
                       desc:    'Create a thing',
                       inputs:  { name: { type: :string, required: true } },
                       outputs: { id: { type: :integer } }

      expect(klass.definitions[:create]).to include(
        desc:    'Create a thing',
        inputs:  { name: { type: :string, required: true } },
        outputs: { id: { type: :integer } }
      )
    end

    it 'stores multiple definitions independently' do
      klass.definition :create, desc: 'Create'
      klass.definition :delete, desc: 'Delete'
      expect(klass.definitions.keys).to contain_exactly(:create, :delete)
    end

    it 'defaults remote_invocable to true' do
      klass.definition :create, desc: 'Create'
      expect(klass.definitions[:create][:remote_invocable]).to be true
    end

    it 'defaults mcp_exposed to true' do
      klass.definition :create, desc: 'Create'
      expect(klass.definitions[:create][:mcp_exposed]).to be true
    end

    it 'defaults idempotent to false' do
      klass.definition :create, desc: 'Create'
      expect(klass.definitions[:create][:idempotent]).to be false
    end

    it 'defaults risk_tier to :standard' do
      klass.definition :create, desc: 'Create'
      expect(klass.definitions[:create][:risk_tier]).to eq(:standard)
    end

    it 'allows overriding all flags' do
      klass.definition :create, desc: 'Create',
                                remote_invocable: false, mcp_exposed: false,
                                idempotent: true, risk_tier: :critical
      defn = klass.definitions[:create]
      expect(defn[:remote_invocable]).to be false
      expect(defn[:mcp_exposed]).to be false
      expect(defn[:idempotent]).to be true
      expect(defn[:risk_tier]).to eq(:critical)
    end

    it 'returns empty hash when no definitions' do
      expect(klass.definitions).to eq({})
    end

    it 'supports definition reuse via hash merge' do
      shared = { repo: { type: :string, required: true } }
      klass.definition :create, desc:   'Create',
                                inputs: shared.merge(title: { type: :string, required: true })
      expect(klass.definitions[:create][:inputs]).to include(:repo, :title)
    end

    it 'inherits definitions from parent class' do
      klass.definition :create, desc: 'Create'
      child = Class.new(klass)
      child.definition :update, desc: 'Update'
      expect(child.definitions.keys).to contain_exactly(:create, :update)
      expect(klass.definitions.keys).to contain_exactly(:create)
    end
  end

  describe '.definition_for' do
    it 'returns a single definition' do
      klass.definition :create, desc: 'Create'
      expect(klass.definition_for(:create)[:desc]).to eq('Create')
    end

    it 'returns nil for undefined method' do
      expect(klass.definition_for(:missing)).to be_nil
    end
  end
end
