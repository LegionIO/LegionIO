# frozen_string_literal: true

require 'spec_helper'
require 'legion/sandbox'

RSpec.describe 'Extension Sandbox wiring' do
  before { Legion::Sandbox.clear! }

  describe 'Legion::Extensions.register_sandbox_policy' do
    context 'when Legion::Sandbox is defined' do
      it 'registers a policy from a capabilities list' do
        Legion::Extensions.register_sandbox_policy(
          gem_name:     'lex-example',
          capabilities: %w[network:outbound data:read]
        )

        policy = Legion::Sandbox.policy_for('lex-example')
        expect(policy).not_to be_nil
        expect(policy.allowed?('network:outbound')).to be true
        expect(policy.allowed?('data:read')).to be true
      end

      it 'registers an empty policy when no capabilities are given' do
        Legion::Extensions.register_sandbox_policy(gem_name: 'lex-empty')

        policy = Legion::Sandbox.policy_for('lex-empty')
        expect(policy.capabilities).to eq([])
        expect(policy.allowed?('network:outbound')).to be false
      end

      it 'filters out unknown capabilities' do
        Legion::Extensions.register_sandbox_policy(
          gem_name:     'lex-example',
          capabilities: %w[network:outbound totally:fake]
        )

        policy = Legion::Sandbox.policy_for('lex-example')
        expect(policy.capabilities).to eq(%w[network:outbound])
      end
    end

    context 'when Legion::Sandbox is not defined' do
      it 'returns early without error' do
        hide_const('Legion::Sandbox')

        expect do
          Legion::Extensions.register_sandbox_policy(gem_name: 'lex-example', capabilities: %w[network:outbound])
        end.not_to raise_error
      end
    end
  end
end
