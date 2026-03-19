# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli/llm_command'
require 'legion/cli/output'

RSpec.describe Legion::CLI::Llm do
  let(:formatter) { Legion::CLI::Output::Formatter.new(json: false, color: false) }
  let(:instance) { described_class.new([], options) }
  let(:options) { { json: false, no_color: true, verbose: false } }

  let(:default_settings) do
    {
      enabled:          true,
      connected:        false,
      default_model:    'claude-sonnet-4-6',
      default_provider: :anthropic,
      providers:        {
        bedrock:   { enabled: false, default_model: 'us.anthropic.claude-sonnet-4-6-v1',
                     api_key: nil, secret_key: nil, bearer_token: nil, region: 'us-east-2' },
        anthropic: { enabled: true, default_model: 'claude-sonnet-4-6', api_key: 'sk-test' },
        openai:    { enabled: false, default_model: 'gpt-4o', api_key: nil },
        gemini:    { enabled: false, default_model: 'gemini-2.0-flash', api_key: nil },
        ollama:    { enabled: false, default_model: 'llama3', base_url: 'http://localhost:11434' }
      },
      routing:          { enabled: false, rules: [] },
      discovery:        { enabled: true, refresh_seconds: 60, memory_floor_mb: 2048 }
    }
  end

  before do
    allow(instance).to receive(:formatter).and_return(formatter)
    allow(instance).to receive(:boot_llm_settings)
    allow(instance).to receive(:llm_settings).and_return(default_settings)
  end

  describe '#collect_providers' do
    it 'returns provider list with enabled status' do
      providers = instance.send(:collect_providers)
      expect(providers).to be_an(Array)
      expect(providers.size).to eq(5)

      anthropic = providers.find { |p| p[:name] == :anthropic }
      expect(anthropic[:enabled]).to be true
      expect(anthropic[:default_model]).to eq('claude-sonnet-4-6')
    end

    it 'marks disabled providers correctly' do
      providers = instance.send(:collect_providers)
      openai = providers.find { |p| p[:name] == :openai }
      expect(openai[:enabled]).to be false
    end
  end

  describe '#collect_status' do
    before do
      stub_const('Legion::LLM', Module.new) unless defined?(Legion::LLM)
      allow(Legion::LLM).to receive(:started?).and_return(false)
    end

    it 'returns status hash with required keys' do
      status = instance.send(:collect_status)
      expect(status).to have_key(:started)
      expect(status).to have_key(:default_model)
      expect(status).to have_key(:default_provider)
      expect(status).to have_key(:enabled_count)
      expect(status).to have_key(:total_count)
      expect(status).to have_key(:providers)
      expect(status).to have_key(:routing)
      expect(status).to have_key(:system)
    end

    it 'counts enabled providers correctly' do
      status = instance.send(:collect_status)
      expect(status[:enabled_count]).to eq(1)
      expect(status[:total_count]).to eq(5)
    end

    it 'includes default model and provider' do
      status = instance.send(:collect_status)
      expect(status[:default_model]).to eq('claude-sonnet-4-6')
      expect(status[:default_provider]).to eq(:anthropic)
    end
  end

  describe '#check_reachable' do
    it 'returns :credentials_present for enabled cloud provider with api_key' do
      cfg = { enabled: true, api_key: 'sk-test' }
      result = instance.send(:check_reachable, :anthropic, cfg)
      expect(result).to eq(:credentials_present)
    end

    it 'returns false for enabled cloud provider without api_key' do
      cfg = { enabled: true, api_key: nil }
      result = instance.send(:check_reachable, :anthropic, cfg)
      expect(result).to be false
    end

    it 'returns nil for disabled provider' do
      cfg = { enabled: false, api_key: 'sk-test' }
      result = instance.send(:check_reachable, :anthropic, cfg)
      expect(result).to be_nil
    end

    it 'returns false for disabled ollama' do
      cfg = { enabled: false, base_url: 'http://localhost:11434' }
      result = instance.send(:check_reachable, :ollama, cfg)
      expect(result).to be false
    end

    it 'returns :credentials_present for bedrock with bearer_token' do
      cfg = { enabled: true, bearer_token: 'token-123', api_key: nil, secret_key: nil }
      result = instance.send(:check_reachable, :bedrock, cfg)
      expect(result).to eq(:credentials_present)
    end

    it 'returns :credentials_present for bedrock with api_key and secret_key' do
      cfg = { enabled: true, bearer_token: nil, api_key: 'key', secret_key: 'secret' }
      result = instance.send(:check_reachable, :bedrock, cfg)
      expect(result).to eq(:credentials_present)
    end

    it 'returns false for bedrock without any credentials' do
      cfg = { enabled: true, bearer_token: nil, api_key: nil, secret_key: nil }
      result = instance.send(:check_reachable, :bedrock, cfg)
      expect(result).to be false
    end
  end

  describe '#collect_models' do
    it 'returns default model for enabled cloud providers' do
      models = instance.send(:collect_models)
      expect(models[:anthropic]).to eq(['claude-sonnet-4-6'])
    end

    it 'excludes disabled providers' do
      models = instance.send(:collect_models)
      expect(models).not_to have_key(:openai)
      expect(models).not_to have_key(:gemini)
    end
  end

  describe '#collect_routing' do
    it 'returns enabled: false when Router is not defined' do
      hide_const('Legion::LLM::Router') if defined?(Legion::LLM::Router)
      routing = instance.send(:collect_routing)
      expect(routing[:enabled]).to be false
    end
  end

  describe '#status (text output)' do
    before do
      stub_const('Legion::LLM', Module.new) unless defined?(Legion::LLM)
      allow(Legion::LLM).to receive(:started?).and_return(false)
    end

    it 'outputs status header and provider info' do
      output = StringIO.new
      $stdout = output
      instance.status
      $stdout = STDOUT
      expect(output.string).to include('LLM Status')
      expect(output.string).to include('Providers')
      expect(output.string).to include('anthropic')
    end
  end

  describe '#status (json output)' do
    let(:options) { { json: true, no_color: true, verbose: false } }

    before do
      stub_const('Legion::LLM', Module.new) unless defined?(Legion::LLM)
      allow(Legion::LLM).to receive(:started?).and_return(false)
    end

    it 'outputs valid JSON with status keys' do
      output = StringIO.new
      $stdout = output
      instance.status
      $stdout = STDOUT
      parsed = JSON.parse(output.string)
      expect(parsed).to have_key('started')
      expect(parsed).to have_key('default_model')
      expect(parsed).to have_key('providers')
    end
  end

  describe '#providers (text output)' do
    it 'outputs provider list' do
      output = StringIO.new
      $stdout = output
      instance.providers
      $stdout = STDOUT
      expect(output.string).to include('Providers')
      expect(output.string).to include('anthropic')
      expect(output.string).to include('bedrock')
    end
  end

  describe '#models (text output)' do
    it 'outputs model list for enabled providers' do
      output = StringIO.new
      $stdout = output
      instance.models
      $stdout = STDOUT
      expect(output.string).to include('Available Models')
      expect(output.string).to include('anthropic')
      expect(output.string).to include('claude-sonnet-4-6')
    end
  end

  describe '#models (json output)' do
    let(:options) { { json: true, no_color: true, verbose: false } }

    it 'outputs valid JSON with models key' do
      output = StringIO.new
      $stdout = output
      instance.models
      $stdout = STDOUT
      parsed = JSON.parse(output.string)
      expect(parsed).to have_key('models')
      expect(parsed['models']['anthropic']).to include('claude-sonnet-4-6')
    end
  end

  describe '#show_providers' do
    it 'shows enabled status for active providers' do
      output = StringIO.new
      $stdout = output
      providers_data = [
        { name: :anthropic, enabled: true, reachable: :credentials_present, default_model: 'claude-sonnet-4-6' },
        { name: :openai, enabled: false, reachable: nil, default_model: 'gpt-4o' }
      ]
      instance.send(:show_providers, formatter, providers_data)
      $stdout = STDOUT
      expect(output.string).to include('enabled')
      expect(output.string).to include('disabled')
    end

    it 'shows reachable status for ollama' do
      output = StringIO.new
      $stdout = output
      providers_data = [
        { name: :ollama, enabled: true, reachable: true, default_model: 'llama3' }
      ]
      instance.send(:show_providers, formatter, providers_data)
      $stdout = STDOUT
      expect(output.string).to include('reachable')
    end
  end

  describe '#ping_all_providers' do
    it 'warns when no providers are enabled' do
      all_disabled = default_settings.merge(
        providers: default_settings[:providers].transform_values { |v| v.merge(enabled: false) }
      )
      allow(instance).to receive(:llm_settings).and_return(all_disabled)

      output = StringIO.new
      $stdout = output
      results = instance.send(:ping_all_providers, formatter)
      $stdout = STDOUT
      expect(results).to be_empty
      expect(output.string).to include('No providers enabled')
    end
  end

  describe '#ping_one_provider' do
    it 'returns skip when no default model configured' do
      result = instance.send(:ping_one_provider, formatter, :anthropic, { default_model: nil })
      expect(result[:status]).to eq('skip')
      expect(result[:message]).to include('no default model')
    end
  end

  describe '#show_ping_results' do
    it 'shows success summary when all pass' do
      output = StringIO.new
      $stdout = output
      results = [
        { provider: :anthropic, status: 'ok', model: 'claude-sonnet-4-6', latency_ms: 450 }
      ]
      instance.send(:show_ping_results, formatter, results)
      $stdout = STDOUT
      expect(output.string).to include('1 provider(s) responding')
    end

    it 'shows failure summary with counts' do
      output = StringIO.new
      $stdout = output
      results = [
        { provider: :anthropic, status: 'ok', model: 'claude-sonnet-4-6', latency_ms: 450 },
        { provider: :openai, status: 'error', message: 'timeout', model: 'gpt-4o', latency_ms: 15_000 }
      ]
      instance.send(:show_ping_results, formatter, results)
      $stdout = STDOUT
      expect(output.string).to include('1 provider(s) failed')
      expect(output.string).to include('1 responding')
    end

    it 'shows skip reason for providers without models' do
      output = StringIO.new
      $stdout = output
      results = [
        { provider: :gemini, status: 'skip', message: 'no default model configured', latency_ms: nil }
      ]
      instance.send(:show_ping_results, formatter, results)
      $stdout = STDOUT
      expect(output.string).to include('skipped')
    end
  end
end
