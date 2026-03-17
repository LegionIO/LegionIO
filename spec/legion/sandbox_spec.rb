# frozen_string_literal: true

require 'spec_helper'
require 'legion/sandbox'

RSpec.describe Legion::Sandbox do
  before do
    described_class.clear!
    allow(Legion::Settings).to receive(:dig).and_return(nil)
  end

  describe '.enforce!' do
    it 'raises for unauthorized capability' do
      described_class.register_policy('lex-test', capabilities: ['data:read'])
      expect { described_class.enforce!('lex-test', 'network:outbound') }.to raise_error(SecurityError)
    end

    it 'passes for authorized capability' do
      described_class.register_policy('lex-test', capabilities: ['data:read'])
      expect(described_class.enforce!('lex-test', 'data:read')).to be true
    end

    it 'raises for unregistered extensions with no capabilities' do
      expect { described_class.enforce!('lex-unknown', 'data:read') }.to raise_error(SecurityError)
    end

    it 'passes when enforcement is disabled' do
      allow(Legion::Settings).to receive(:dig).with(:sandbox, :enabled).and_return(false)
      expect(described_class.enforce!('lex-unknown', 'anything')).to be true
    end
  end

  describe '.policy_for' do
    it 'returns empty policy for unknown extension' do
      policy = described_class.policy_for('lex-unknown')
      expect(policy.capabilities).to be_empty
    end
  end
end

RSpec.describe Legion::Sandbox::Policy do
  let(:policy) { described_class.new(extension_name: 'test', capabilities: %w[data:read llm:invoke]) }

  it 'checks capability allowance' do
    expect(policy.allowed?('data:read')).to be true
    expect(policy.allowed?('filesystem:write')).to be false
  end

  it 'filters invalid capabilities' do
    bad_policy = described_class.new(extension_name: 'test', capabilities: ['invalid:cap'])
    expect(bad_policy.capabilities).to be_empty
  end
end
