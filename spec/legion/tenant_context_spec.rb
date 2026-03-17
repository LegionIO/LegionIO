# frozen_string_literal: true

require 'spec_helper'
require 'legion/tenant_context'

RSpec.describe Legion::TenantContext do
  after { described_class.clear }

  describe '.set and .current' do
    it 'stores and retrieves tenant_id' do
      described_class.set('askid-123')
      expect(described_class.current).to eq('askid-123')
    end

    it 'returns nil when not set' do
      expect(described_class.current).to be_nil
    end
  end

  describe '.with' do
    it 'sets context for the block and restores after' do
      described_class.set('original')
      described_class.with('temporary') do
        expect(described_class.current).to eq('temporary')
      end
      expect(described_class.current).to eq('original')
    end

    it 'restores on exception' do
      described_class.set('original')
      begin
        described_class.with('temp') { raise 'oops' }
      rescue RuntimeError
        nil
      end
      expect(described_class.current).to eq('original')
    end
  end

  describe '.clear' do
    it 'removes tenant context' do
      described_class.set('askid-123')
      described_class.clear
      expect(described_class.current).to be_nil
    end
  end
end
