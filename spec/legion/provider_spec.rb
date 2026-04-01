# frozen_string_literal: true

require 'spec_helper'
require 'legion/provider'

RSpec.describe Legion::Provider do
  before do
    Legion::Provider::Registry.reset!
    allow(Legion::Logging).to receive(:info)
    allow(Legion::Logging).to receive(:debug)
    allow(Legion::Logging).to receive(:warn)
  end

  after { Legion::Provider::Registry.reset! }

  describe 'DSL' do
    it 'declares provides, depends_on, and adapters' do
      klass = Class.new(described_class) do
        provides :test_component
        depends_on :settings
        adapters lite: 'legion/crypt/mock_vault', full: 'legion/crypt'
      end

      expect(klass.provides).to eq(:test_component)
      expect(klass.depends_on).to eq([:settings])
      expect(klass.adapters[:lite]).to eq('legion/crypt/mock_vault')
    end

    it 'defaults depends_on to empty array' do
      klass = Class.new(described_class) { provides :standalone }
      expect(klass.depends_on).to eq([])
    end
  end

  describe 'auto-registration' do
    it 'registers subclasses in the Registry' do
      Class.new(described_class) { provides :auto_registered }
      expect(Legion::Provider::Registry.providers).to have_key(:auto_registered)
    end
  end
end

RSpec.describe Legion::Provider::Registry do
  before do
    described_class.reset!
    allow(Legion::Logging).to receive(:info)
    allow(Legion::Logging).to receive(:debug)
    allow(Legion::Logging).to receive(:warn)
  end

  after { described_class.reset! }

  describe '.boot_order' do
    it 'returns topologically sorted provider keys' do
      Class.new(Legion::Provider) { provides :settings }
      Class.new(Legion::Provider) do
        provides :crypt
        depends_on :settings
      end
      Class.new(Legion::Provider) do
        provides :transport
        depends_on :settings, :crypt
      end

      order = described_class.boot_order
      expect(order.index(:settings)).to be < order.index(:crypt)
      expect(order.index(:crypt)).to be < order.index(:transport)
    end

    it 'raises CyclicDependencyError on cycles' do
      Class.new(Legion::Provider) do
        provides :alpha
        depends_on :beta
      end
      Class.new(Legion::Provider) do
        provides :beta
        depends_on :alpha
      end

      expect { described_class.boot_order }.to raise_error(Legion::Provider::CyclicDependencyError)
    end

    it 'raises MissingDependencyError for unregistered dependencies' do
      Class.new(Legion::Provider) do
        provides :orphan
        depends_on :nonexistent
      end

      expect { described_class.boot_order }.to raise_error(
        Legion::Provider::MissingDependencyError, /nonexistent/
      )
    end
  end

  describe '.boot!' do
    it 'calls boot on each provider in order' do
      booted = []

      Class.new(Legion::Provider) do
        provides :first
        define_method(:boot) { booted << :first }
      end
      Class.new(Legion::Provider) do
        provides :second
        depends_on :first
        define_method(:boot) { booted << :second }
      end

      instances = described_class.boot!(mode: :full, timeout: 5)
      expect(booted).to eq(%i[first second])
      expect(instances.length).to eq(2)
    end
  end

  describe '.shutdown!' do
    it 'shuts down instances in reverse boot order' do
      shut = []

      Class.new(Legion::Provider) do
        provides :a_prov
        define_method(:boot) { nil }
        define_method(:shutdown) { shut << :a_prov }
      end
      Class.new(Legion::Provider) do
        provides :b_prov
        depends_on :a_prov
        define_method(:boot) { nil }
        define_method(:shutdown) { shut << :b_prov }
      end

      instances = described_class.boot!(mode: :full, timeout: 5)
      described_class.shutdown!(instances)
      expect(shut).to eq(%i[b_prov a_prov])
    end

    it 'does not raise if a shutdown fails' do
      Class.new(Legion::Provider) do
        provides :fragile
        define_method(:boot) { nil }
        define_method(:shutdown) { raise 'boom' }
      end

      instances = described_class.boot!(mode: :full, timeout: 5)
      expect { described_class.shutdown!(instances) }.not_to raise_error
    end
  end

  describe '.reset!' do
    it 'clears all registered providers' do
      Class.new(Legion::Provider) { provides :temp }
      described_class.reset!
      expect(described_class.providers).to be_empty
    end
  end
end
