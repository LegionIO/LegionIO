# frozen_string_literal: true

require 'spec_helper'
require 'thor'
require 'legion/cli/output'
require 'legion/cli/connection'
require 'legion/cli/error'
require 'legion/cli/config_command'

RSpec.describe Legion::CLI::Config do
  let(:config) { described_class.new }

  describe '#sensitive_key?' do
    def sensitive?(key)
      config.send(:sensitive_key?, key)
    end

    context 'keys that should be redacted' do
      %w[password secret token key credential auth].each do |word|
        it "redacts '#{word}'" do
          expect(sensitive?(word)).to be(true)
        end
      end

      it "redacts 'api_key'" do
        expect(sensitive?(:api_key)).to be(true)
      end

      it "redacts 'cluster_secret'" do
        expect(sensitive?(:cluster_secret)).to be(true)
      end

      it "redacts 'auth_token'" do
        expect(sensitive?(:auth_token)).to be(true)
      end

      it "redacts 'vault_password'" do
        expect(sensitive?(:vault_password)).to be(true)
      end

      it "redacts 'session_token'" do
        expect(sensitive?(:session_token)).to be(true)
      end
    end

    context 'keys that should NOT be redacted' do
      it "does not redact 'cluster_secret_timeout'" do
        expect(sensitive?(:cluster_secret_timeout)).to be(false)
      end

      it "does not redact 'authentication'" do
        expect(sensitive?(:authentication)).to be(false)
      end

      it "does not redact 'key_count'" do
        expect(sensitive?(:key_count)).to be(false)
      end

      it "does not redact 'vault_path'" do
        expect(sensitive?(:vault_path)).to be(false)
      end

      it "does not redact 'token_ttl'" do
        expect(sensitive?(:token_ttl)).to be(false)
      end

      it "does not redact 'password_length'" do
        expect(sensitive?(:password_length)).to be(false)
      end
    end
  end

  describe '#deep_redact' do
    def redact(obj)
      config.send(:deep_redact, obj)
    end

    it 'redacts password but not cluster_secret_timeout' do
      input = { password: 'hunter2', cluster_secret_timeout: 5 }
      result = redact(input)
      expect(result[:password]).to eq('***REDACTED***')
      expect(result[:cluster_secret_timeout]).to eq(5)
    end

    it 'redacts nested sensitive keys' do
      input = { vault: { token: 'abc123', address: 'localhost' } }
      result = redact(input)
      expect(result[:vault][:token]).to eq('***REDACTED***')
      expect(result[:vault][:address]).to eq('localhost')
    end
  end

  describe 'LLM validation' do
    before do
      allow(Legion::CLI::Connection).to receive(:ensure_settings)
      allow(Legion::CLI::Connection).to receive(:settings?).and_return(true)
    end

    def run_validate
      issues = []
      warnings = []
      config.send(:validate_llm, warnings)
      [issues, warnings]
    end

    context 'when LLM is enabled with no default provider' do
      before do
        allow(Legion::Settings).to receive(:[]).with(:transport).and_return({})
        allow(Legion::Settings).to receive(:[]).with(:data).and_return({ adapter: 'sqlite' })
        allow(Legion::Settings).to receive(:[]).with(:extensions).and_return({})
        allow(Legion::Settings).to receive(:[]).with(:llm).and_return({
                                                                        enabled:          true,
                                                                        default_provider: nil,
                                                                        providers:        {}
                                                                      })
      end

      it 'warns about missing default provider' do
        _, warnings = run_validate
        expect(warnings).to include(a_string_matching(/default.provider/i))
      end
    end

    context 'when a provider is enabled without an API key' do
      before do
        allow(Legion::Settings).to receive(:[]).with(:transport).and_return({})
        allow(Legion::Settings).to receive(:[]).with(:data).and_return({ adapter: 'sqlite' })
        allow(Legion::Settings).to receive(:[]).with(:extensions).and_return({})
        allow(Legion::Settings).to receive(:[]).with(:llm).and_return({
                                                                        enabled:   true,
                                                                        providers: {
                                                                          anthropic: { enabled: true, api_key: nil }
                                                                        }
                                                                      })
      end

      it 'warns about missing API key' do
        _, warnings = run_validate
        expect(warnings).to include(a_string_matching(/anthropic.*api.key/i))
      end
    end

    context 'when bedrock is enabled without an API key' do
      before do
        allow(Legion::Settings).to receive(:[]).with(:transport).and_return({})
        allow(Legion::Settings).to receive(:[]).with(:data).and_return({ adapter: 'sqlite' })
        allow(Legion::Settings).to receive(:[]).with(:extensions).and_return({})
        allow(Legion::Settings).to receive(:[]).with(:llm).and_return({
                                                                        enabled:   true,
                                                                        providers: {
                                                                          bedrock: { enabled: true, region: 'us-east-2' }
                                                                        }
                                                                      })
      end

      it 'does not warn (bedrock uses IAM, not API keys)' do
        _, warnings = run_validate
        expect(warnings).not_to include(a_string_matching(/bedrock.*api.key/i))
      end
    end

    context 'when ollama is enabled without an API key' do
      before do
        allow(Legion::Settings).to receive(:[]).with(:transport).and_return({})
        allow(Legion::Settings).to receive(:[]).with(:data).and_return({ adapter: 'sqlite' })
        allow(Legion::Settings).to receive(:[]).with(:extensions).and_return({})
        allow(Legion::Settings).to receive(:[]).with(:llm).and_return({
                                                                        enabled:   true,
                                                                        providers: {
                                                                          ollama: { enabled: true, base_url: 'http://localhost:11434' }
                                                                        }
                                                                      })
      end

      it 'does not warn (ollama is local, no API key needed)' do
        _, warnings = run_validate
        expect(warnings).not_to include(a_string_matching(/ollama.*api.key/i))
      end
    end

    context 'when LLM is disabled' do
      before do
        allow(Legion::Settings).to receive(:[]).with(:transport).and_return({})
        allow(Legion::Settings).to receive(:[]).with(:data).and_return({ adapter: 'sqlite' })
        allow(Legion::Settings).to receive(:[]).with(:extensions).and_return({})
        allow(Legion::Settings).to receive(:[]).with(:llm).and_return({ enabled: false })
      end

      it 'produces no LLM warnings' do
        _, warnings = run_validate
        expect(warnings.grep(/llm|provider|api.key/i)).to be_empty
      end
    end
  end
end
