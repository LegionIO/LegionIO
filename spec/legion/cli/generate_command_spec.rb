# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'thor'
require 'legion/cli/output'
require 'legion/cli/generate_command'

RSpec.describe Legion::CLI::Generate do
  let(:parent_dir) { Dir.mktmpdir('gen-test') }
  let(:lex_dir) { File.join(parent_dir, 'lex-testext') }

  around do |example|
    FileUtils.mkdir_p(lex_dir)
    original_dir = Dir.pwd
    Dir.chdir(lex_dir)
    example.run
    Dir.chdir(original_dir)
    FileUtils.rm_rf(parent_dir)
  end

  describe 'runner' do
    it 'creates runner and spec files' do
      described_class.start(%w[runner my_runner])
      expect(File).to exist('lib/legion/extensions/testext/runners/my_runner.rb')
      expect(File).to exist('spec/runners/my_runner_spec.rb')
    end

    it 'scaffolds specified functions' do
      described_class.start(%w[runner api_call --functions fetch,post])
      content = File.read('lib/legion/extensions/testext/runners/api_call.rb')
      expect(content).to include('def fetch')
      expect(content).to include('def post')
    end

    it 'defaults to execute function' do
      described_class.start(%w[runner simple])
      content = File.read('lib/legion/extensions/testext/runners/simple.rb')
      expect(content).to include('def execute')
    end

    it 'generates correct class name from snake_case' do
      described_class.start(%w[runner data_fetch])
      content = File.read('lib/legion/extensions/testext/runners/data_fetch.rb')
      expect(content).to include('module DataFetch')
    end
  end

  describe 'actor' do
    it 'creates actor and spec files' do
      described_class.start(%w[actor poller --type every])
      expect(File).to exist('lib/legion/extensions/testext/actors/poller.rb')
      expect(File).to exist('spec/actors/poller_spec.rb')
    end

    it 'uses subscription parent by default' do
      described_class.start(%w[actor listener])
      content = File.read('lib/legion/extensions/testext/actors/listener.rb')
      expect(content).to include('Legion::Extensions::Actors::Subscription')
    end

    it 'includes interval for every type' do
      described_class.start(%w[actor ticker --type every --interval 30])
      content = File.read('lib/legion/extensions/testext/actors/ticker.rb')
      expect(content).to include('INTERVAL = 30')
    end

    it 'does not include interval for subscription type' do
      described_class.start(%w[actor sub_actor --type subscription])
      content = File.read('lib/legion/extensions/testext/actors/sub_actor.rb')
      expect(content).not_to include('INTERVAL')
    end
  end

  describe 'exchange' do
    it 'creates exchange file' do
      described_class.start(%w[exchange events])
      path = 'lib/legion/extensions/testext/transport/exchanges/events.rb'
      expect(File).to exist(path)
      expect(File.read(path)).to include('class Events < Legion::Transport::Exchange')
    end
  end

  describe 'queue' do
    it 'creates queue file' do
      described_class.start(%w[queue tasks])
      path = 'lib/legion/extensions/testext/transport/queues/tasks.rb'
      expect(File).to exist(path)
      expect(File.read(path)).to include('class Tasks < Legion::Transport::Queue')
    end
  end

  describe 'message' do
    it 'creates message file' do
      described_class.start(%w[message notify])
      path = 'lib/legion/extensions/testext/transport/messages/notify.rb'
      expect(File).to exist(path)
      expect(File.read(path)).to include('class Notify < Legion::Transport::Message')
    end
  end

  describe 'tool' do
    it 'creates tool and spec files' do
      described_class.start(%w[tool lookup])
      expect(File).to exist('lib/legion/extensions/testext/tools/lookup.rb')
      expect(File).to exist('spec/tools/lookup_spec.rb')
    end

    it 'includes ExtensionTool mixin' do
      described_class.start(%w[tool search])
      content = File.read('lib/legion/extensions/testext/tools/search.rb')
      expect(content).to include('include Legion::CLI::Chat::ExtensionTool')
      expect(content).to include('permission_tier :write')
    end
  end

  # TODO: fix SystemExit leaking into SimpleCov at_exit on CI
  # describe 'detect_lex' do
  #   it 'raises when not in a lex directory' do
  #     non_lex = File.join(parent_dir, 'myproject')
  #     FileUtils.mkdir_p(non_lex)
  #     Dir.chdir(non_lex)
  #     expect { described_class.start(%w[runner test]) }.to raise_error(SystemExit)
  #   end
  # end
end
