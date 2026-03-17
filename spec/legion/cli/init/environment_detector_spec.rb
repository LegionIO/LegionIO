# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli/init/environment_detector'

RSpec.describe Legion::CLI::InitHelpers::EnvironmentDetector do
  describe '.detect' do
    it 'returns hash with expected keys' do
      result = described_class.detect
      expect(result.keys).to include(:rabbitmq, :database, :vault, :redis, :git, :existing_config)
    end

    it 'detects vault from VAULT_ADDR env' do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('VAULT_ADDR').and_return('https://vault.example.com')
      result = described_class.detect
      expect(result[:vault][:available]).to be true
    end

    it 'always detects database as available (sqlite fallback)' do
      result = described_class.detect
      expect(result[:database][:available]).to be true
    end
  end
end
