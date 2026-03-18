# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli'

RSpec.describe 'Chat settings integration' do
  let(:chat_instance) { Legion::CLI::Chat.new }

  before do
    allow(Legion::Settings).to receive(:dig).and_return(nil)
  end

  describe '#chat_setting' do
    it 'returns nil when setting is not configured' do
      result = chat_instance.send(:chat_setting, :model)
      expect(result).to be_nil
    end

    it 'returns the setting value when configured' do
      allow(Legion::Settings).to receive(:dig).with(:chat, :model).and_return('claude-sonnet-4-6')
      result = chat_instance.send(:chat_setting, :model)
      expect(result).to eq('claude-sonnet-4-6')
    end

    it 'supports nested keys' do
      allow(Legion::Settings).to receive(:dig).with(:chat, :subagent, :max_concurrency).and_return(5)
      result = chat_instance.send(:chat_setting, :subagent, :max_concurrency)
      expect(result).to eq(5)
    end

    it 'returns nil when Settings is not available' do
      allow(Legion::Settings).to receive(:dig).and_raise(StandardError)
      result = chat_instance.send(:chat_setting, :model)
      expect(result).to be_nil
    end
  end

  describe '#configure_permissions' do
    before do
      require 'legion/cli/chat/permissions'
    end

    after do
      Legion::CLI::Chat::Permissions.mode = :interactive
    end

    it 'uses CLI flag when --auto_approve is set' do
      instance = Legion::CLI::Chat.new([], { auto_approve: true })
      allow(Legion::Settings).to receive(:dig).and_return(nil)
      instance.send(:configure_permissions, :interactive)
      expect(Legion::CLI::Chat::Permissions.mode).to eq(:auto_approve)
    end

    it 'uses settings when CLI flag is not set' do
      allow(Legion::Settings).to receive(:dig).with(:chat, :permissions).and_return('read_only')
      chat_instance.send(:configure_permissions, :interactive)
      expect(Legion::CLI::Chat::Permissions.mode).to eq(:read_only)
    end

    it 'falls back to default when neither CLI nor settings set' do
      chat_instance.send(:configure_permissions, :interactive)
      expect(Legion::CLI::Chat::Permissions.mode).to eq(:interactive)
    end

    it 'CLI flag takes priority over settings' do
      allow(Legion::Settings).to receive(:dig).with(:chat, :permissions).and_return('read_only')
      instance = Legion::CLI::Chat.new([], { auto_approve: true })
      allow(Legion::Settings).to receive(:dig).and_return(nil)
      allow(Legion::Settings).to receive(:dig).with(:chat, :permissions).and_return('read_only')
      instance.send(:configure_permissions, :interactive)
      expect(Legion::CLI::Chat::Permissions.mode).to eq(:auto_approve)
    end
  end

  describe '#incognito?' do
    it 'returns false by default' do
      expect(chat_instance.send(:incognito?)).to be false
    end

    it 'reads incognito setting' do
      allow(Legion::Settings).to receive(:dig).with(:chat, :incognito).and_return(true)
      expect(chat_instance.send(:incognito?)).to be true
    end

    it 'CLI flag overrides settings' do
      allow(Legion::Settings).to receive(:dig).with(:chat, :incognito).and_return(false)
      instance = Legion::CLI::Chat.new([], { incognito: true })
      expect(instance.send(:incognito?)).to be true
    end
  end

  describe '#effective_budget' do
    it 'returns nil by default' do
      expect(chat_instance.send(:effective_budget)).to be_nil
    end

    it 'reads budget from settings' do
      allow(Legion::Settings).to receive(:dig).with(:chat, :max_budget_usd).and_return(5.0)
      expect(chat_instance.send(:effective_budget)).to eq(5.0)
    end

    it 'CLI flag overrides settings' do
      allow(Legion::Settings).to receive(:dig).with(:chat, :max_budget_usd).and_return(5.0)
      instance = Legion::CLI::Chat.new([], { max_budget_usd: 10.0 })
      expect(instance.send(:effective_budget)).to eq(10.0)
    end
  end

  describe '#effective_max_turns' do
    it 'defaults to 10' do
      expect(chat_instance.send(:effective_max_turns)).to eq(10)
    end

    it 'reads max_turns from settings' do
      allow(Legion::Settings).to receive(:dig).with(:chat, :headless, :max_turns).and_return(25)
      expect(chat_instance.send(:effective_max_turns)).to eq(25)
    end

    it 'CLI flag overrides settings' do
      allow(Legion::Settings).to receive(:dig).with(:chat, :headless, :max_turns).and_return(25)
      instance = Legion::CLI::Chat.new([], { max_turns: 5 })
      expect(instance.send(:effective_max_turns)).to eq(5)
    end
  end

  describe '#build_system_prompt personality from settings' do
    before do
      require 'legion/cli/chat/context'
      allow(Legion::CLI::Chat::Context).to receive(:to_system_prompt).and_return('base prompt')
    end

    it 'uses settings personality when CLI flag is absent' do
      allow(Legion::Settings).to receive(:dig).with(:chat, :personality).and_return('concise')
      result = chat_instance.send(:build_system_prompt)
      expect(result).to include('extremely concise')
    end

    it 'CLI flag overrides settings personality' do
      allow(Legion::Settings).to receive(:dig).with(:chat, :personality).and_return('verbose')
      instance = Legion::CLI::Chat.new([], { personality: 'educational' })
      allow(Legion::Settings).to receive(:dig).and_return(nil)
      result = instance.send(:build_system_prompt)
      expect(result).to include('educational')
      expect(result).not_to include('thorough and detailed')
    end
  end
end
